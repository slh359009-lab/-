# Windows Photoshop 2023 云端连接器

通过本机 PowerShell 调用 Photoshop，由带口令验证的 HTTPS 通道接收云端任务。

## 下载与启动

1. 打开 [修正版 ZIP](downloads/photoshop-windows-bridge-v4.zip)，点击文件页面右侧的下载按钮；也可以在此分支选择 **Code → Download ZIP**。
2. 解压 ZIP 到新文件夹，启动器会先核对 Bridge.ps1 与 JSX 的 SHA-256，再仅解除 Bridge.ps1 的下载来源标记；不更改全局执行策略。
3. 以普通用户权限打开 **Windows x64 Photoshop 2023**，关闭弹出的对话框。
4. 在 ZIP 内的 `PhotoshopBridge` 文件夹双击 **Run.cmd**；连接器与 PS 应由同一 Windows 用户以普通权限运行。
5. 首次运行会下载并校验 Cloudflare 官方的 `cloudflared`。保持窗口打开，等待显示 **PS_BRIDGE_URL**。
6. **只把 HTTPS 地址发给 Codex。口令默认隐藏。** Codex 配置确切域名的密钥要求后，在连接器窗口按字母 **C**（不是 Ctrl+C）复制口令，直接粘贴到云环境设置的安全密钥输入框；不要粘贴到聊天。

GitHub 源码目录 `windows/` 也提供 `Run.cmd`、`Bridge.ps1` 和 `photoshop-task.jsx`；它们必须保持在同一文件夹。另提供内联 JSX 的 `Bridge-Single.ps1`，可作为独立脚本使用。

## 已验证与待验证

用户已在普通用户的 Windows PowerShell STA 模式下通过 `Photoshop.Application.170` 执行脚本，实际返回 **Photoshop 24.0.1**。本版沿用该版本接口；`Run.cmd` 显式选择 STA，仅设置进程级 RemoteSigned 执行策略。

云端已完成 PowerShell 语法检查、13 项 HTTP 监听器检查、9 项 JSX 模拟检查及 6 项客户端测试。本机短脚本成功不代表完整桥接、图片导出或 HTTPS 端到端连接已验证；启动后仍需真实连接检查。

## 能力与文件

- 读取 Photoshop 版本、打开文档数量、当前文档名称和尺寸。
- 导出当前文档副本为 JPG 或 PNG。原始文档不保存、不覆盖，已有同名导出会被拒绝。
- 将副本转换为 8 位 sRGB；指定宽高时等比例缩放至该范围内，不自动填成方形画布。JPG 质量范围为 0–12。透明区域的 JPG 底色未作平台主图保证。
- 本机输出位于“文档/ECommerceStudio/exports”。仅可取回本次连接器会话生成的 JPG/PNG，传输上限 100 MiB。
- 首版不提供任意 JSX 执行、任意本机文件读取、PSD 上传或图层/文案替换接口。

所有业务接口均需 Bearer 口令。监听器绑定本机 loopback；Cloudflare 提供临时 HTTPS 通道。没有内置凭据或商品素材。

## 隧道和排障

需要访问 GitHub 官方下载以及 Cloudflare 隧道服务，后者可能使用 TCP 7844。临时隧道不需要 Cloudflare 账户；重启后地址和口令变化。运行时按字母 **R** 可以只更换口令，网址保持不变；更换后旧口令立即失效，需要重新按 C 复制并更新安全绑定。固定地址需要另行配置用户自己的稳定隧道。

关闭窗口或 Ctrl+C 断开。隧道日志在连接器的 `bin/tunnel-*.log` 中，不要将包含口令的窗口截图发到聊天。

如果出现 `80080005`，先保存工作并退出 PS 和 PowerShell，再使用同一普通用户打开 PS、运行 `Run.cmd`。不要未经诊断修改注册表；已知在本机成功的接口是 `Photoshop.Application.170`。

若导出请求超时，先检查本机输出目录再决定是否重试；请求不会自动重试，同名文件不覆盖。若本机已有 Cloudflare 配置影响临时隧道，应保留原配置并单独排查。

## 下载完整性

ZIP 的 SHA-256 见 [SHA256SUMS](SHA256SUMS)。连接器使用 Cloudflare 官方 [2026.10.3 Release](https://github.com/cloudflare/cloudflared/releases/tag/2026.10.3) 的 `cloudflared-windows-amd64.exe`，首次下载及每次使用前均校验官方 SHA-256：

```text
76b2805253d0d6ffacb092a7acfbee99e7af6917835c0c5410e23f3ef5052da2
```

云端控制客户端已保留在配套云环境 `/workspace/ecommerce-studio/photoshop/cloud/ps_client.py`。云端需要 `PS_BRIDGE_URL` 和安全绑定的 `PS_BRIDGE_TOKEN`；本仓库不包含它们的值。

## v3 日志读取修复

修复 Windows 上 cloudflared 正在写日志时，`ReadAllText` 因文件共享模式冲突而失败的问题。改为支持共享读取的 `Get-Content -Raw`。保留哈希、TLS 与脚本执行策略校验。新增 3 项共享日志读取检查（Linux PowerShell）：写入句柄保持打开时可读、可观察追加内容、读取句柄释放；13 项 HTTP 检查继续通过。真实 Windows 隧道恢复仍需用户启动验证。

## v4 口令交付与启动

控制台不再输出原始口令，复制整段日志不会带出口令。按 C 时才把当前口令放入 Windows 剪贴板，仅用于安全设置；按 R 在同一网址上更换口令。停止与重新启动仍使用 Ctrl+C；不要把复制口令与停止操作混淆。

Run.cmd 会校验 Bridge.ps1 和 JSX 的固定哈希，只有一致时才解除 Bridge.ps1 的下载标记并以 STA、RemoteSigned 启动；不会修改系统或用户全局执行策略。旧版程序缺少这些交付改进，建议改用 v4。当前仍未完成真实云端到 PS 的端到端验证。
