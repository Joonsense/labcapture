# LabCapture

[English](README.md) | [한국어](README.ko.md) | **简体中文** | [日本語](README.ja.md) | [Español](README.es.md)

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black?logo=apple) ![Swift](https://img.shields.io/badge/Swift-5.9-orange?logo=swift) ![License: MIT](https://img.shields.io/badge/License-MIT-green) ![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen)

**在构建中公开分享，不打断你的工作流。**

LabCapture 是一个轻量级 macOS 菜单栏应用，在你工作时自动记录屏幕和摄像头约 3 秒钟，并将录像转换为可直接发布的内容：GIF、高质量的日制时光延时视频（带圆形摄像头窗口），以及 AI 生成的构建日志。

你构建。它捕捉。在一天结束时，你会得到一个 1080p 的工作时光延时视频、可分享的 GIF，以及一份 Markdown 格式的工作日志——所有内容都在你的机器上生成。

## 你将获得

每次捕捉（默认：每 20 分钟一次，加上每次 `git push` 时）会生成名为 `YYYY-MM-DD_HHmmss_*` 的文件：

- `*_screen.gif` — 你的屏幕（960px 宽，带时间戳）
- `*_face.gif` — 你的摄像头
- `*_combo.gif` — 屏幕加上**圆形摄像头**叠加层（绿色环，画中画）
- `*_screen.mp4` / `*_face.mp4` — 高质量原始文件（CRF 18，30 fps）

每天一次（一键或一个 API 调用）：

- **时光延时视频** — 将今天的所有捕捉拼接成一个 1080p/30fps MP4：你的屏幕作为背景，你的脸作为中心的圆形，每段录像带时间戳
- **构建日志** — Claude 读取你的捕捉清单和关键帧，生成 `summary.md`：单行摘要、你所做工作的时间轴，以及 1-2 个建议发送到 X/Twitter 的帖子
- **剪贴板助手** — 复制最后的捕捉，然后 ⌘V 直接粘贴到帖子中

## 隐私和安全优先

这是一个记录你屏幕的工具，所以它被设计得偏执：

- **100% 本地。** 没有账户、没有遥测、没有上传。文件仅存在于你机器上的 `~/LabCapture` 中。唯一的可选网络调用是构建日志，它只在你触发时才将数据发送到 Claude API。
- **秘密守卫（OCR）。** 在每次录制之后，Apple Vision OCR 会扫描帧。如果屏幕上显示了 API 密钥、令牌、密码或数据库连接字符串，**整个捕捉会被丢弃**并重试。三次连续丢弃会暂停捕捉数小时（可配置）。覆盖的模式：`sk-...` 密钥、GitHub PAT、AWS 密钥、Slack/Notion 令牌、JWT、PRIVATE KEY 块、Bearer 令牌、`API_KEY=` 环境变量赋值等——故意匹配松散，因为过度检测是安全的方向。
- **捕捉前警告。** 一个可选的通知会在每次捕捉前几秒钟触发，这样你永远不会被意外录制。
- **到处都是杀死开关。** 从菜单栏（或 API）独立切换屏幕/摄像头源，暂停一小时/当天/按夜间计划。当你的屏幕锁定或睡眠时，捕捉会自动跳过。
- **永远不提交任何内容。** 仓库的 `.gitignore` 会阻止所有媒体文件，你的输出文件夹在仓库外。

## 需求

- macOS 14+（Apple Silicon）
- ffmpeg：`brew install ffmpeg`
- Xcode 命令行工具（用于构建）：`xcode-select --install`

## 安装

```bash
git clone https://github.com/Joonsense/labcapture.git
cd labcapture
./build.sh
open dist/LabCapture.app
```

首次启动时，一个引导窗口会带你完成它需要的两个权限：

| 权限 | 位置 | 用途 |
|---|---|---|
| 屏幕录制 | 系统设置 → 隐私与安全 | 屏幕捕捉（ffmpeg 子进程） |
| 摄像头 | 系统设置 → 隐私与安全 | 摄像头捕捉 |

提示：

- 在运行已构建的 `dist/LabCapture.app` 时授予权限（不是从终端构建）— TCC 会单独追踪它们。
- 如果捕捉失败且切换*看起来*已启用，权限记录已过期：`tccutil reset ScreenCapture com.deblockx.labcapture`，然后重新授予。参见 [docs/SIGNING.md](docs/SIGNING.md) 了解如何创建本地签名证书，使权限能**在重新构建后保留**（如果你修改源代码，推荐使用）。
- 没有权限时，捕捉会优雅地跳过并显示通知——无崩溃。

## 使用

- **自动** — 默认每 20 分钟捕捉一次（5-120 分钟可配置）
- **菜单栏** — 立即捕捉/暂停（1 小时、当天）/显示最后捕捉/打开今天的文件夹/设置
- **全局快捷键** — 默认 `⌃⌥⌘C`（可重新绑定）
- **安静时间** — 例如暂停定时器捕捉 21:00-09:00（手动捕捉仍然有效）
- 在锁定/睡眠时自动跳过，当剩余磁盘空间低于 500 MB 时

### 菜单栏图标

两种形状：**矩形 = 屏幕源，圆形 = 摄像头源**。填充 = 开，轮廓加斜线 = 关。颜色显示整体状态：🟢 绿色活跃 · ⚪ 灰色暂停 · 🔴 红色录制中 · 🟠 橙色最后捕捉失败。

## 输出布局

```
~/LabCapture/
  2026-06-12/
    2026-06-12_143012_screen.gif
    2026-06-12_143012_face.gif
    2026-06-12_143012_combo.gif
    2026-06-12_143012_screen.mp4     ← 启用"保留原始文件"时（默认）
    2026-06-12_143012_face.mp4
    timelapse_2026-06-12_213000.mp4  ← 日制时光延时视频
    summary.md                       ← AI 构建日志
    manifest.jsonl                   ← 每次捕捉一行 JSON
  labcapture.log
```

## HTTP API — 为人类*和* AI 代理构建

应用在 `http://127.0.0.1:48620`（仅本地环回，永不暴露）监听。**一个 LLM 代理可以从单个调用 `GET /capabilities`** 发现整个 API — 它返回机器可读的规范。

| 方法 | 路径 | 操作 |
|---|---|---|
| GET | `/capabilities` | 机器可读的 API 规范 |
| GET | `/status` | 状态（`active/paused/capturing/warning`）、源、下次捕捉时间、最后错误/文件 |
| POST | `/capture` | 立即捕捉（202；若忙则 409）。`GET/POST /trigger` 是 git 钩子的别名 |
| POST | `/source/screen/on` · `/off` | 切换屏幕源 |
| POST | `/source/face/on` · `/off` | 切换摄像头（网络摄像头）源 |
| POST | `/pause` · `/pause/today` · `/resume` | 暂停 1 小时/到午夜/恢复 |
| POST | `/last/copy` | 将最后的 combo.gif 复制到剪贴板（在 X 中 ⌘V） |
| POST | `/timelapse` | 将今天的原始文件编译成 1080p 时光延时视频（202） |
| POST | `/summary` | 生成今天的 AI 构建日志（202；无 API 密钥时 400） |

```bash
curl -s http://127.0.0.1:48620/status | jq .sources
curl -s -X POST http://127.0.0.1:48620/source/face/off   # 仅屏幕捕捉
curl -s -X POST http://127.0.0.1:48620/capture
```

### 每次 git push 时捕捉

```bash
# <your-repo>/.git/hooks/pre-push  (chmod +x)
#!/bin/sh
curl -s -m 2 http://127.0.0.1:48620/trigger >/dev/null 2>&1 || true
exit 0
```

或作为成功推送后立即触发的全局别名：

```bash
git config --global alias.pushc '!git push "$@" && curl -s -m 2 http://127.0.0.1:48620/trigger >/dev/null; true'
```

## AI 构建日志（可选）

设置 Claude API 密钥（永不硬编码——文件或环境变量）：

```bash
mkdir -p ~/.config/labcapture && printf '%s' 'sk-ant-...' > ~/.config/labcapture/anthropic_api_key && chmod 600 ~/.config/labcapture/anthropic_api_key
```

然后在菜单中点击"每日总结"（或 `POST /summary`）会发送 `manifest.jsonl` 加上最多 6 个代表性帧到 Claude，并生成 `summary.md`：单行摘要、工作时间轴和建议的 X 帖子，基于你的捕捉中实际可见的内容。

## 设置

| 设置 | 默认 | 范围 |
|---|---|---|
| 捕捉间隔 | 20 分钟 | 5-120 |
| 捕捉长度 | 3 秒 | 1-5 |
| 捕捉前通知/提前时间 | 开/3 秒 | 0-10 秒 |
| 网络摄像头捕捉 | 开 | 关 → 仅屏幕 |
| PiP 位置（combo GIF） | 右下 | tl / tr / bl / br |
| GIF fps | 15 | 8-15 |
| 屏幕 GIF 宽度 | 960 px | 480-1080 |
| 输出文件夹 | `~/LabCapture` | 任意 |
| 保留原始 mp4 | 开 | 关 → 时光延时回退到 GIF（低质量） |
| 安静时间 | 关 | 开始/结束时间 |
| 全局快捷键 | ⌃⌥⌘C | 可重新绑定 |
| 秘密守卫（OCR） | 开 | 3 次丢弃后暂停 1-12 小时 |

所有设置通过 `UserDefaults` 持久化。

## manifest.jsonl 模式（LLM 管道输入）

每次捕捉一行 JSON，`schema: 1`：

```json
{"schema":1,"ts":"2026-06-12T18:25:23+09:00","trigger":"push","duration":3,
 "sources":["screen","face"],
 "files":["2026-06-12_182523_screen.gif","2026-06-12_182523_face.gif","2026-06-12_182523_combo.gif"],
 "kinds":{"2026-06-12_182523_screen.gif":"screen","2026-06-12_182523_face.gif":"face","2026-06-12_182523_combo.gif":"combo"}}
```

`trigger`：`timer` / `manual` / `hotkey` / `push`（git 集成）

## 架构

一个 Swift/SwiftUI 菜单栏应用进行编排；录制/编码被委托给 ffmpeg 子进程。

```
Sources/LabCapture/
  LabCaptureApp.swift    入口（MenuBarExtra + Settings 场景）
  AppModel.swift         中央状态：计时器/暂停/锁检测/错误日志/引导
  CaptureEngine.swift    录制 → 3 个 GIF → 清单（核心管道）
  DailyPipeline.swift    时光延时 + Claude 日志 + 剪贴板助手
  FFmpeg.swift           ffmpeg 进程运行器 + avfoundation 设备检测
  OCRGuard.swift         Vision OCR 秘密检测
  TriggerServer.swift    127.0.0.1:48620 HTTP 服务器
  HotkeyManager.swift    Carbon 全局快捷键
  Permissions.swift      TCC 检查/设置深层链接
  Views/                 菜单/设置/引导 UI
```

编码详情：两遍 GIF 调色板（`palettegen stats_mode=diff` → `paletteuse` sierra2_4a 抖动）；圆形脸部掩码通过 `geq` alpha 与羽毛边缘；时光延时段规范化为 1080p/30fps 然后无损连接；时间戳通过 `drawtext` + `textfile=`（避免 filtergraph 冒号转义）。

## 故障排除

- **"视频设备配置失败"**当屏幕录制切换看起来开启时 → TCC 记录过期（应用被重新签名）。修复：`tccutil reset ScreenCapture com.deblockx.labcapture`，重新启动，重新授予。用[本地签名证书](docs/SIGNING.md)永久防止它。
- **找不到 ffmpeg** → `brew install ffmpeg`（应在 `/opt/homebrew/bin/ffmpeg`）。
- 错误被记录到 `~/LabCapture/labcapture.log`（也可从菜单查看）。

## 路线图

- ffmpeg 捆绑（零依赖安装）
- 公证发布
- 多显示器选择（当前仅主显示器）
- Intel Mac 支持

欢迎 PR。

## 许可证

[MIT](LICENSE) © DeblockX Labs
