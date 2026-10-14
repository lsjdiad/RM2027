# 交接文档 · 到 Ubuntu（原生双系统）后怎么开始

> 2026-09 交接。目标：Ubuntu 上做 PX4 学习/无人机开发。
> 前提：原生 Ubuntu 能上网。本文是"到那边照着搞"的清单，详细步骤见各链接文档。

---

## 一、先建环境（网络/工具）

### 1. Clash Verge（代理）
```bash
wget https://github.com/clash-verge-rev/clash-verge-rev/releases/download/v2.5.2/Clash.Verge_2.5.2_amd64.deb
sudo apt install ./Clash.Verge_2.5.2_amd64.deb
clash-verge
```
- 导入你自己的机场订阅；缺依赖 `sudo apt -f install`
- 详细：`by_agent/learning/资料-Ubuntu环境-ClashVerge与Tailscale配置.md`

### 2. Tailscale（远程/组网）
```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up       # 登录同 GitHub 账号（跟 Windows/手机同网）
```

## 二、拿项目文档（by_agent）

```bash
git clone https://gitee.com/AdoreElysia/by_agent.git
```
| 文件 | 用途 |
|------|------|
| `learning/资源包-PX4-QGC-SITL视频清单.md` | PX4/QGC/SITL 学习视频（含 BV 号）|
| `learning/L00.5-系统全局图景.md` | 无人机系统全貌（先看这个）|
| `learning/L00-环境搭建-PX4-SITL.md` | SITL 环境 |
| `learning/L01-四旋翼怎么飞.md` | 第一课 |
| `硬件需求-给硬件组-v1.md` | 双 MCU 硬件方案 |
| `日志.md` | 项目工程日志 |

## 三、PX4 学习最小软件（Ubuntu 装）

```bash
# VS Code（.deb）
# 官网 https://code.visualstudio.com 下 deb，sudo dpkg -i 或 sudo apt install ./xxx.deb

# QGroundControl（AppImage）
# https://qgroundcontrol.com 选 Linux 下载，chmod +x 后运行

# PX4 源码（能 git clone 就直接 clone，网络不好可用 WSL 那台 scp）
git clone --recursive https://github.com/PX4/PX4-Autopilot.git

# PlotJuggler（PX4 日志/曲线分析，飞完复盘必备）
sudo apt install plotjuggler

# pyulog（.ulg 日志解析）
pip install pyulog
```

**学习节奏**：先 `learning/L00.5` 看全貌 → `L00` 搭 SITL → 视频清单跟着看 → 对照硬件方案文档。

## 四、Command Code（AI 通道）

> ⚠️ 凭据（base url + API key）**单独微信发你**，不写进 git。
> 拿到后配置：base `https://api.commandcode.ai/provider/v1`，key 填进去，模型 `deepseek/deepseek-v4-flash`。
> （完整凭据/协议细节见你微信收到的；也可回 Windows 查 `memory/steward/密码大全.md`）

## 五、Windows ↔ Ubuntu 互传文件

- 项目/文档：git（by_agent）
- 大文件：U 盘 或 Tailscale + `scp`
- 字幕/素材（可选）：B站字幕库在 Windows `memory/materials/bili-subtitles/`，需要再传

## 六、踩坑速记
- Clash 系统代理会拦 `*.ts.net` → no_proxy 加 `*.ts.net`
- tailscale serve 在 Linux 要 sudo
- dsh 若本地跑：host 白名单只放 127.0.0.1，远程走 trusted-host + tailscale
- 飞控 IMU：PX4 用 SPI 裸芯片（MPU6500/ICM42688），别用串口成品 IMU（见 `learning/资料-HI04外置IMU接PX4调研.md`）

---
**到 Ubuntu 后有任何一步卡住，把报错贴回来（微信/对话），我远程帮解。**
