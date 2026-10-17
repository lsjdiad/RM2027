# 资料 · Ubuntu(原生双系统) 环境配置：Clash Verge + Tailscale + dsh

> 2026-09 整理 · 已确认场景：**原生双系统 Ubuntu** + **dsh 本地跑** + **Clash 订阅自己导入**（机场账号在 Edge 可登）。
> 已有 Windows 版记录：`obsidian/2026/08/环境配置/DeepSeek-Harness与Tailscale部署.md`（本文是原生 Linux 版）。

---

## 〇、视频清单怎么在 Ubuntu 里看

视频清单已同步在 gitee `by_agent` 仓库：
```bash
git clone https://gitee.com/AdoreElysia/by_agent.git
# 看文件: by_agent/learning/资源包-PX4-QGC-SITL视频清单.md（含 BV 号）
```

---

## 1. Clash Verge Rev · Linux 安装（Ubuntu amd64）

**Clash Verge Rev = 最主流 Clash GUI（Rust+Tauri）**，版本 v2.5.2（2026），GitHub: `clash-verge-rev/clash-verge-rev`

```bash
# 1) 下载 amd64 .deb（最新版去 GitHub releases 看）
wget https://github.com/clash-verge-rev/clash-verge-rev/releases/download/v2.5.2/Clash.Verge_2.5.2_amd64.deb

# 2) 安装（apt 会自动拉依赖）
sudo apt install ./Clash.Verge_2.5.2_amd64.deb

# 3) 运行
clash-verge
```

- 若报缺 `libwebkit2gtk` 等依赖：`sudo apt -f install` 修复，或先 `sudo apt install libwebkit2gtk-4.1-0 libgtk-3-0`
- 启动后：导入**订阅**（你机场的订阅链接）→ 开**系统代理**或 **TUN 模式**（TUN 需要内核模块，Ubuntu 一般有）
- 开机自启：GUI 里开"开机自启"或按你桌面环境配置

> 如果是 Arch: AUR 有 `clash-verge-rev`。如果不想 GUI：纯内核用 `mihomo`（Clash.Meta），命令行配。

---

## 2. Tailscale · Linux 安装

```bash
# 1) 官方脚本装
curl -fsSL https://tailscale.com/install.sh | sh

# 2) 登录（同一 GitHub 账号，跟 Windows/手机同账号才同网络）
sudo tailscale up
#   → 会打印登录链接，浏览器授权

# 3) 验证
tailscale ip -4        # 100.x.x.x
tailscale status       # 看同网络设备（含 Windows laptop-js8lh3h8、手机）
```

### Tailscale Serve（把 Ubuntu 上的端口发布到 Tailnet）
```bash
# 后台把本机 3080 发布成 https://<机器名>.tailXXXX.ts.net/
sudo tailscale serve --bg 3080
sudo tailscale serve status   # 看发布的域名
```
> Linux 上 serve 一般要 sudo；域名格式跟 Windows 那台类似 `xxx.tail0c65e9.ts.net`。

---

## 3. dsh（DeepSeek Harness）—— 原生 Ubuntu 本地跑

> deepseek-harness 是 node/pnpm monorepo（60+ 子包），Ubuntu 本地跑 = 装 node/pnpm → clone → build → 起 web。

```bash
# 1) 装 node 22 + pnpm
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - && sudo apt install -y nodejs
sudo npm install -g pnpm

# 2) 克隆（国内用 gh-proxy 加速）
git clone https://gh-proxy.com/https://github.com/deepseek-ai/deepseek-harness.git
cd deepseek-harness

# 3) 装依赖 + 构建（必须 build：web UI 需要前端 dist）
pnpm install
npm run build

# 4) 本机跑
npm run dsh -- web                # http://127.0.0.1:3080

# 5) 远程访问（要跨设备/手机用 Tailscale）→ 加 trusted-host + tailscale serve
sudo tailscale serve --bg 3080    # 发布成 https://<机器名>.tailXXXX.ts.net/
npm run dsh -- web --trusted-host <机器名>.tailXXXX.ts.net
```
> ⚠️ dsh 安全护栏：host 只允许 127.0.0.1，禁全网监听（RCE 能力）；远程必须走 tailscale serve + trusted-host，别暴露公网。
> 如果你主要在本机 Ubuntu 用，第 5 步可省，直接 `npm run dsh -- web` 就行。

---

## 4. 注意事项

- **代理冲突**：Clash 开系统代理后，访问 `*.ts.net`（tailscale）可能被代理拦 → 把 `*.ts.net` 加进 no_proxy / Clash 直连名单
- **tailscale serve 权限**：Linux 上 serve 要 sudo
- **token 安全**：dsh 有 RCE 能力，trusted-host 只加自己 tailnet 域名
- **Clash 订阅**：你导入自己的机场订阅链接即可（Edge 能登机场账号）；装好界面后 Profiles/订阅 里导入
