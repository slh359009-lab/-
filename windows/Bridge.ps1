param(
    [ValidateRange(0,65535)][int]$Port = 0,
    [string]$ExportDirectory = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'ECommerceStudio\exports'),
    [switch]$NoTunnel
)
$ErrorActionPreference = 'Stop'
$script:Photoshop = $null
$script:SessionFiles = @{}
$script:Utf8 = New-Object System.Text.UTF8Encoding($false, $true)
$template = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'photoshop-task.jsx'))
$ExportDirectory = [IO.Path]::GetFullPath($ExportDirectory)
[IO.Directory]::CreateDirectory($ExportDirectory) | Out-Null

# The token lives only in process memory. Never write it to a log or script.
function New-SessionToken {
    $bytes = New-Object byte[] 32
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    return ([BitConverter]::ToString($bytes)).Replace('-', '').ToLowerInvariant()
}
$script:SessionToken = New-SessionToken

function Invoke-ConsoleKey([ConsoleKey]$Key) {
    if ($Key -eq [ConsoleKey]::C) {
        Set-Clipboard -Value $script:SessionToken -ErrorAction Stop
        Write-Host 'Token copied. Paste ONLY into the secure environment secret field.' -ForegroundColor Yellow
    } elseif ($Key -eq [ConsoleKey]::R) {
        $script:SessionToken = New-SessionToken
        Write-Host 'Token changed. URL unchanged. Press C to copy the new token.' -ForegroundColor Yellow
    }
}
if ($NoTunnel -and $env:PS_BRIDGE_TEST_TOKEN) {
    # Explicit loopback-only integration testing; not used by Run.cmd.
    $script:SessionToken = $env:PS_BRIDGE_TEST_TOKEN
}

function Test-Token([string]$Header) {
    if ($Header -notmatch '^Bearer ([a-f0-9]{64})$') { return $false }
    $candidate = $Matches[1]
    $diff = 0
    for ($i=0; $i -lt 64; $i++) {
        $diff = $diff -bor ([int][char]$candidate[$i] -bxor [int][char]$script:SessionToken[$i])
    }
    return ($diff -eq 0)
}

function Send-Response($Stream, [int]$Status, [byte[]]$Body, [string]$ContentType = 'application/json; charset=utf-8') {
    $reason = @{200='OK';400='Bad Request';401='Unauthorized';404='Not Found';409='Conflict';413='Payload Too Large';500='Internal Server Error';503='Service Unavailable'}[$Status]
    $header = "HTTP/1.1 $Status $reason`r`nContent-Type: $ContentType`r`nContent-Length: $($Body.Length)`r`nConnection: close`r`nCache-Control: no-store`r`nX-Content-Type-Options: nosniff`r`n`r`n"
    $bytes = [Text.Encoding]::ASCII.GetBytes($header)
    $Stream.Write($bytes,0,$bytes.Length)
    $Stream.Write($Body,0,$Body.Length)
    $Stream.Flush()
}

function Send-Json($Stream, [int]$Status, $Value) {
    $json = ConvertTo-Json -InputObject $Value -Depth 8 -Compress
    Send-Response $Stream $Status $script:Utf8.GetBytes($json)
}

function Invoke-Photoshop($Task) {
    if ($null -eq $script:Photoshop) {
        $script:Photoshop = New-Object -ComObject Photoshop.Application.170
    }
    $data = ConvertTo-Json -InputObject $Task -Compress -Depth 8
    $source = $template.Replace('__TASK_JSON__', $data)
    try {
        return ($script:Photoshop.DoJavaScript($source) | ConvertFrom-Json)
    } catch {
        $script:Photoshop = $null
        throw
    }
}

function Handle-Request($Stream) {
    $headerBytes = New-Object 'System.Collections.Generic.List[byte]'
    $ended = $false
    while ($headerBytes.Count -lt 16384) {
        $next = $Stream.ReadByte()
        if ($next -lt 0) { throw 'Incomplete HTTP header' }
        $headerBytes.Add([byte]$next)
        $n = $headerBytes.Count
        if ($n -ge 4 -and $headerBytes[$n-4] -eq 13 -and $headerBytes[$n-3] -eq 10 -and $headerBytes[$n-2] -eq 13 -and $headerBytes[$n-1] -eq 10) {
            $ended = $true
            break
        }
    }
    if (-not $ended) { Send-Json $Stream 400 @{error='Header too large'}; return }
    $lines = [Text.Encoding]::ASCII.GetString($headerBytes.ToArray()).Split(@("`r`n"), [StringSplitOptions]::None)
    if ($lines[0] -notmatch '^(GET|POST) (/[^ ]*) HTTP/1\.[01]$') {
        Send-Json $Stream 400 @{error='Unsupported HTTP request'}; return
    }
    $method = $Matches[1]; $path = $Matches[2]
    $headers = @{}
    foreach ($line in $lines[1..($lines.Length-1)]) {
        if (-not $line) { continue }
        $pair = $line.Split(@(':'), 2)
        if ($pair.Length -ne 2) { Send-Json $Stream 400 @{error='Malformed header'}; return }
        $name = $pair[0].Trim().ToLowerInvariant()
        if ($headers.ContainsKey($name)) { Send-Json $Stream 400 @{error='Duplicate header'}; return }
        $headers[$name] = $pair[1].Trim()
    }
    if (-not (Test-Token $headers['authorization'])) {
        Send-Json $Stream 401 @{error='Authentication required'}; return
    }
    if ($headers.ContainsKey('transfer-encoding')) {
        Send-Json $Stream 400 @{error='Content-Length is required instead of transfer encoding'}; return
    }
    $length = 0
    if ($headers.ContainsKey('content-length') -and (-not [int]::TryParse($headers['content-length'], [ref]$length) -or $length -lt 0)) {
        Send-Json $Stream 400 @{error='Invalid Content-Length'}; return
    }
    if ($length -gt 32768) { Send-Json $Stream 413 @{error='Body too large'}; return }
    $body = New-Object byte[] $length
    $read = 0
    while ($read -lt $length) {
        $count = $Stream.Read($body,$read,$length-$read)
        if ($count -eq 0) { throw 'Incomplete request body' }
        $read += $count
    }
    if ($method -eq 'GET' -and $path -eq '/v1/status') {
        try { Send-Json $Stream 200 (Invoke-Photoshop @{action='status'}) }
        catch { Send-Json $Stream 503 @{error='Photoshop scripting failed. Open Photoshop 2023, close modal dialogs, and inspect the local console.'}; Write-Host $_.Exception.Message }
        return
    }
    if ($method -eq 'GET' -and $path -match '^/v1/files/([A-Za-z0-9][A-Za-z0-9_-]{0,63}\.(jpg|png))$') {
        $fileName = $Matches[1]
        if (-not $script:SessionFiles.ContainsKey($fileName)) { Send-Json $Stream 404 @{error='No export with that name in this session'}; return }
        $file = $script:SessionFiles[$fileName]
        if (-not [IO.File]::Exists($file)) { Send-Json $Stream 404 @{error='Export no longer exists'}; return }
        if ((Get-Item -LiteralPath $file).Length -gt 104857600) { Send-Json $Stream 413 @{error='Export exceeds 100 MiB transfer limit'}; return }
        $mime = if ($fileName.EndsWith('.png')) { 'image/png' } else { 'image/jpeg' }
        Send-Response $Stream 200 ([IO.File]::ReadAllBytes($file)) $mime
        return
    }
    if ($method -ne 'POST' -or $path -ne '/v1/export') { Send-Json $Stream 404 @{error='Unsupported endpoint'}; return }
    try { $request = $script:Utf8.GetString($body) | ConvertFrom-Json }
    catch { Send-Json $Stream 400 @{error='Invalid JSON body'}; return }
    if ($null -eq $request -or $request -is [array] -or $request -is [string] -or $request -is [ValueType]) {
        Send-Json $Stream 400 @{error='Expected a JSON object'}; return
    }
    if ($request.file_stem -isnot [string] -or $request.file_stem -cnotmatch '\A[A-Za-z0-9][A-Za-z0-9_-]{0,63}\z' -or $request.format -cnotin @('jpg','png')) {
        Send-Json $Stream 400 @{error='Use a safe file_stem (letters, numbers, underscore, hyphen) and format jpg or png'}; return
    }
    if ($request.file_stem -match '^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$') {
        Send-Json $Stream 400 @{error='Windows device names cannot be used as export names'}; return
    }
    $width = 0; $height = 0; $quality = 10
    if ($null -ne $request.width -or $null -ne $request.height) {
        if (($request.width -isnot [int] -and $request.width -isnot [long]) -or ($request.height -isnot [int] -and $request.height -isnot [long]) -or $request.width -lt 1 -or $request.width -gt 10000 -or $request.height -lt 1 -or $request.height -gt 10000) {
            Send-Json $Stream 400 @{error='Provide both width and height as integers between 1 and 10000'}; return
        }
        $width = [int]$request.width; $height = [int]$request.height
    }
    if ($null -ne $request.quality) {
        if (($request.quality -isnot [int] -and $request.quality -isnot [long]) -or $request.quality -lt 0 -or $request.quality -gt 12) {
            Send-Json $Stream 400 @{error='JPEG quality must be an integer from 0 to 12'}; return
        }
        $quality = [int]$request.quality
    }
    $fileName = $request.file_stem + '.' + $request.format
    $output = Join-Path $ExportDirectory $fileName
    if ([IO.File]::Exists($output)) { Send-Json $Stream 409 @{error='File already exists; use another file_stem'}; return }
    try {
        $result = Invoke-Photoshop @{action='export_copy';output_path=$output;file_name=$fileName;format=$request.format;width=$width;height=$height;quality=$quality}
        if (-not [IO.File]::Exists($output)) { throw 'Photoshop did not produce an export' }
        $script:SessionFiles[$fileName] = $output
        Send-Json $Stream 200 $result
    } catch {
        Send-Json $Stream 503 @{error='Photoshop export failed. Inspect the local console; no automatic retry was made.'}
        Write-Host $_.Exception.Message
    }
}

$listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, $Port)
$tunnel = $null
try {
    $listener.Start()
    $Port = ([Net.IPEndPoint]$listener.LocalEndpoint).Port
    Write-Host ('Local port: ' + $Port)
    if (-not $NoTunnel) {
        if ($env:PROCESSOR_ARCHITECTURE -ne 'AMD64' -and $env:PROCESSOR_ARCHITEW6432 -ne 'AMD64') {
            throw 'This package targets Windows x64. Use x64 Windows PowerShell.'
        }
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $bin = Join-Path $PSScriptRoot 'bin'
        [IO.Directory]::CreateDirectory($bin) | Out-Null
        $exe = Join-Path $bin 'cloudflared.exe'
        $expected = '76b2805253d0d6ffacb092a7acfbee99e7af6917835c0c5410e23f3ef5052da2'
        if (-not [IO.File]::Exists($exe)) {
            $pending = Join-Path $bin 'cloudflared.download'
            Invoke-WebRequest -UseBasicParsing -Uri 'https://github.com/cloudflare/cloudflared/releases/download/2026.10.3/cloudflared-windows-amd64.exe' -OutFile $pending
            if ((Get-FileHash -LiteralPath $pending -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expected) {
                Remove-Item -LiteralPath $pending
                throw 'Cloudflared checksum verification failed; download was not used.'
            }
            Move-Item -LiteralPath $pending -Destination $exe
        }
        if ((Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expected) {
            throw 'Existing cloudflared does not match the pinned checksum. Do not use it.'
        }
        $log = Join-Path $bin ('tunnel-' + [Guid]::NewGuid().ToString('N') + '.log')
        $tunnel = Start-Process -FilePath $exe -ArgumentList @('tunnel','--no-autoupdate','--protocol','http2','--url',"http://127.0.0.1:$Port") -PassThru -WindowStyle Hidden -RedirectStandardError $log
        $url = $null
        for ($i=0; $i -lt 90; $i++) {
            if ($tunnel.HasExited) { throw "Tunnel exited. Inspect $log" }
            if (Test-Path -LiteralPath $log) {
                $text = (Get-Content -LiteralPath $log -Raw -ErrorAction Stop)
                if ($text -match 'https://[a-z0-9-]+\.trycloudflare\.com') { $url = $Matches[0]; break }
            }
            Start-Sleep -Milliseconds 500
        }
        if (-not $url) { throw "Tunnel address unavailable. Inspect $log" }
        Write-Host "`nPS_BRIDGE_URL: $url" -ForegroundColor Cyan
        Write-Host 'Token is hidden. Send ONLY the URL to Codex.'
        Write-Host 'When filling secure settings: press C (without Ctrl) to copy the token.' -ForegroundColor Yellow
        Write-Host 'Press R (without Ctrl) to change the token without changing the URL.'
    }
    Write-Host "Ready. Export directory: $ExportDirectory"
    Write-Host 'Keep this window open. Close it or press Ctrl+C to disconnect.'
    while ($true) {
        if (-not $NoTunnel -and [Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true)
            try { Invoke-ConsoleKey $key.Key }
            catch { Write-Host 'Clipboard unavailable. Try C again from an interactive Windows session.' -ForegroundColor Yellow }
        }
        if ($tunnel -and $tunnel.HasExited) { throw 'Tunnel stopped. Restart Run.cmd to reconnect.' }
        if (-not $listener.Pending()) { Start-Sleep -Milliseconds 100; continue }
        $client = $listener.AcceptTcpClient()
        $client.ReceiveTimeout = 10000; $client.SendTimeout = 30000
        $stream = $client.GetStream()
        try { Handle-Request $stream }
        catch {
            Write-Host ('Request failed: ' + $_.Exception.Message)
            try { Send-Json $stream 400 @{error='Request could not be processed'} } catch {}
        } finally { $stream.Dispose(); $client.Close() }
    }
} finally {
    $listener.Stop()
    if ($tunnel -and -not $tunnel.HasExited) { Stop-Process -Id $tunnel.Id }
    if ($script:Photoshop) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($script:Photoshop) }
    $script:SessionToken = $null
}
