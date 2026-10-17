# L00 · 环境搭建（PX4 SITL 仿真）

> 目标：在你的 Windows 上跑起 **PX4 软件在环仿真（SITL）**，让"仿真里的无人机"能飞。
> 为什么必须先装它：后面每课都在仿真里验证，不烧钱、不炸机、可回放。
> ⚠️ 步骤可能随 PX4 版本漂移，**以官方 `docs.px4.io/dev_setup/dev_env_linux` 为准**，这里给主线。

---

## 〇、为什么用 WSL2 而不是原生双系统？

> 2026-08-28 补充（用户本机是 Win11 + 原生 Ubuntu 双系统）。

| 方案 | 能否同时跑 Windows+Linux | 切换成本 |
|------|------------------------|---------|
| **WSL2**（推荐） | ✅ 一起跑，秒切 | 同一个桌面，无重启 |
| 虚拟机 | ✅ 一起跑 | 窗口切换 |
| 原生双系统 | ❌ 一次一个 | **必须重启** |

- 你的工作流 = Windows（文档/IDE/沟通）+ Linux（PX4）**同时用** → WSL2 正解。
- WSL2 与原生 Ubuntu 可共存、不冲突；97GB 原生 Ubuntu 保留不删。
- WSL 内可直接访问 Windows 文件（如 `/mnt/h/AI/shared`），本项目文档资料互通。

---

## 一、总体方案

```
Windows 11
 └─ WSL2（Linux 内核）── 装 Ubuntu 发行版
      └─ 在 Ubuntu 里装 PX4 源码 + 工具链 + Gazebo（仿真器）
           └─ 跑 PX4 SITL（自动驾驶仪本体跑在本机 Ubuntu 进程里，仿真器渲染）
Windows 侧 ── QGroundControl（地面站，连 SITL 看姿态/地图/发任务）
```

> PX4 SITL 官方主推 Linux；Windows 上没有官方直跑方案，用 **WSL2** 最省事。你的机子是 Windows 11，WSL2 支持良好。

---

## 二、步骤（主线）

### 1. 装/确认 WSL2
```powershell
wsl --status            # 看 WSL 版本（要 v2）
wsl --install -d Ubuntu-24.04   # 没装就装（首次可能要重启；需管理员）
wsl --set-default-version 2
```
> 装完打开 Ubuntu 终端，设一个用户名/密码（这是 Ubuntu 里的账号，和 Windows 账号无关）。

### 2. 在 Ubuntu 里装 PX4 工具链
```bash
cd ~
git clone --recursive https://github.com/PX4/PX4-Autopilot.git
cd PX4-Autopilot
bash ./Tools/setup/ubuntu.sh     # 自动装编译器/仿真器依赖（很久，等它跑完）
```

### 3. 跑 SITL（两条路）
```bash
# 路A：Gazebo 三维仿真（推荐，真实感强）
make px4_sitl gz_x500
# 路B：jMAVSim 轻量仿真（快，验证控制够用）
make px4_sitl jmavsim
```
> 跑起来后会弹出一个飞行器，终端里能看到 PX4 启动日志。**第一次跑通 = L00 完成 60%。**

### 4. 连地面站
- Windows 侧装 **QGroundControl**（`qgroundcontrol.com` 下载）。
- SITL 默认在本机 `127.0.0.1:14550` 发 MAVLink，QGC 用"UDP 连接"连上。
- 在 QGC 里能看到姿态、油门、地图，能**手动解锁起飞**（这是 L01 的实验台）。

---

## 三、验证标准（达到才算过）

- [ ] `make px4_sitl gz_x500` 启动后仿真器出现四旋翼，PX4 无致命报错
- [ ] QGroundControl 连上 SITL，能看到实时姿态/GPS（仿真坐标）
- [ ] 在 QGC 里能解锁（arm）并手动起飞/降落
- [ ] 截图存到 `learning/lab/L00/`

---

## 四、常见卡点

| 卡点 | 解决 |
|------|------|
| `wsl --install` 需要重启 | 正常，重启后继续 |
| ubuntu.sh 卡网络 | 国内网络给 git/apt 换源（阿里云镜像），脚本重跑 |
| 编译报缺依赖 | 重跑 `bash ./Tools/setup/ubuntu.sh`（它幂等） |
| QGC 连不上 | SITL 先跑起来，再开 QGC；确认端口 14550 |
| WSL2 内存不足 | `%USERPROFILE%\.wslconfig` 加 `[wsl2] memory=8GB` 后 `wsl --shutdown` |

---

## 五、这一课你带走的一句话

**PX4 SITL = 把真实飞控的软件原样跑在你电脑上，连一个假飞机。** 以后你写的一切自主代码（L04 定位、L05 任务）都能先在这台"假飞机"上试，再搬到 249g 实机。

> 环境装好之前，L01 可以先读；装好之后立刻回头做 L01 的实验（在 QGC 里看姿态/油门联动）。
