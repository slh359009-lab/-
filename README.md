# Windows Photoshop 2023 云端连接器

通过本机 PowerShell 调用 Photoshop，由带口令验证的 HTTPS 通道接收云端任务。

## 下载与启动

1. 打开 [修正版 ZIP](downloads/photoshop-windows-bridge-v2.zip)，点击文件页面右侧的下载按钮；也可以在此分支选择 **Code → Download ZIP**。
2. 如果 Windows 给 ZIP 添加了锁定标记，检查来源和脚本后，在文件“属性”中选择“解除锁定”，再解压。
3. 以普通用户权限打开 **Windows x64 Photoshop 2023**，关闭弹出的对话框。
4. 在 ZIP 内的 `PhotoshopBridge` 文件夹双击 **Run.cmd**；连接器与 PS 应由同一 Windows 用户以普通权限运行。
5. 首次运行会下载并校验 Cloudflare 官方的 `cloudflared`。保持窗口打开，等待显示 **PS_BRIDGE_URL**。
6. **只把 HTTPS 地址发给 Codex，访问口令不要发到聊天中。** Codex 为确切域名声明密钥要求后，再把口令填入云环境设置的安全输入框。

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

需要访问 GitHub 官方下载以及 Cloudflare 隧道服务，后者可能使用 TCP 7844。临时隧道不需要 Cloudflare 账户；地址和口令每次启动后变化，需要更新云端绑定。固定地址需要另行配置用户自己的稳定隧道。

关闭窗口或 Ctrl+C 断开。隧道日志在连接器的 `bin/tunnel-*.log` 中，不要将包含口令的窗口截图发到聊天。

如果出现 `80080005`，先保存工作并退出 PS 和 PowerShell，再使用同一普通用户打开 PS、运行 `Run.cmd`。不要未经诊断修改注册表；已知在本机成功的接口是 `Photoshop.Application.170`。

若导出请求超时，先检查本机输出目录再决定是否重试；请求不会自动重试，同名文件不覆盖。若本机已有 Cloudflare 配置影响临时隧道，应保留原配置并单独排查。

## 下载完整性

ZIP 的 SHA-256 见 [SHA256SUMS](SHA256SUMS)。连接器使用 Cloudflare 官方 [2026.10.3 Release](https://github.com/cloudflare/cloudflared/releases/tag/2026.10.3) 的 `cloudflared-windows-amd64.exe`，首次下载及每次使用前均校验官方 SHA-256：

```text
76b2805253d0d6ffacb092a7acfbee99e7af6917835c0c5410e23f3ef5052da2
```

云端控制客户端已保留在配套云环境 `/workspace/ecommerce-studio/photoshop/cloud/ps_client.py`。云端需要 `PS_BRIDGE_URL` 和安全绑定的 `PS_BRIDGE_TOKEN`；本仓库不包含它们的值。
