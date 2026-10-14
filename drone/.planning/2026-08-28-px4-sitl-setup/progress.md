# Progress · RM2027 无人机 L00 环境安装

> 会话日志：2026-08-28~29

## Session 2026-08-29（管理员会话）
- [x] 用户以管理员重开会话 → 验证 IsAdmin=True
- [x] `wsl --install -d Ubuntu-24.04` 成功（Provisioning 完成；注册表 Lxss 确认；vhdx 在 `C:\Users\w2006\AppData\Local\wsl\{0f4bc4c7-...}`）
- [x] Ubuntu 24.04.4 LTS 启动验证（内核 6.18.33 WSL2）
- [x] 建 drone 用户（免密sudo）+ /etc/wsl.conf 设默认用户 + systemd=true
- [x] 网络验证：archive.ubuntu.com 直连 200（无需换源）
- [x] gcc 13.3 / make 4.3 / git 2.43 装好
- [x] PX4 主仓库：git clone 失败（fetch-pack invalid index-pack，GitHub 大传输不稳）→ 改 codeload tarball 成功（270MB / 14min / curl 直连）
- [x] 解压 414MB + git init（git fetch 历史仍失败 GnuTLS，暂不需要）
- [x] 子模块 35/35 全部完成 0 失败（自写 pull_submodules.sh 逐个浅clone+重试3次，nohup 后台）
- [x] ubuntu.sh 后台跑：apt 阶段完成 → pip 阶段完成 → 下载 ARM 交叉工具链 463MB 大包中（SITL 不需要，后台继续）
- [x] Gazebo Harmonic 单独安装（osrf 官方源；ubuntu.sh 卡 ARM 大包时并行解决）
- [x] OpenCV 4.6.0 补装（gz optical_flow 插件需要）
- [x] make px4_sitl_default 编译成功（1225/1225 目标）
- [x] SITL headless 试跑成功（Gazebo world ready / gz_bridge / MAVLink 14550）
- [x] QGroundControl v5.1.3 安装（C:\Program Files\QGroundControl\bin\；安装包留存 File-Manager\Downloads\Installers\）
- [x] VSCode Remote-WSL 扩展安装（v0.104.3）
- [x] WSL 网络切 mirrored 模式（.wslconfig；解决 QGC↔SITL localhost 互通）
- [x] vhdx 从 C 盘迁 E 盘（wsl --manage --move；E:\WSL\Ubuntu-24.04）
- [x] SITL 持久化方案定型：Windows 侧 bat 宿主撑 VM（setsid 后台会被 VM 闲置回收杀）
- [x] **用户手动完成 T1**：切 Position → 解锁 → Takeoff → **8.2m 悬停**（ulog 06_14_49.ulg）
- [x] 工具脚本固化到项目 work\（start_sitl_headed/headless.bat、wsl_run.py、parse_ulog.py）
- [x] L00.9 日常使用手册 + 学习任务线 T1-T7 落盘

## L00 完成宣言（2026-08-29）
环境→仿真→地面站→手动飞行全闭环。用户已具备：独立启动三件套、QGC 基础飞行（切模式/解锁/起飞/悬停）、读黑匣子数据。
下一步：T2 虚拟摇杆画"回"字（L01 手感）+ 尚硅谷 P100-140（姿态解算/PID）。

## 技术要点（复用价值）
- wsl.exe 输出是 UTF-16LE → Python subprocess decode('utf-16-le') 最可靠（`_tmp\wsl_run.py` 助手脚本）
- PowerShell 嵌套 bash 转义地狱 → bash 脚本写 /mnt/h 文件再执行
- WSL 单命令 10 分钟上限 → 长任务 nohup 后台 + 轮询（VM 有进程不闲置）
- GitHub git 协议大传输不稳（fetch-pack 损坏）→ codeload tarball 稳；子模块逐个 clone+重试稳
- ubuntu.sh 的 ARM 交叉链 463MB 对 SITL 非必需（真机编译才要）

## 已完成文档（历轮，供参考）
- learning/L00-环境搭建-PX4-SITL.md（含"为什么 WSL 不选原生双系统"）+ L00-安装离线手册.md
- learning/L00.5-系统全局图景.md / L01-四旋翼怎么飞.md
- learning/资料-浙大课程成本与周期.md / 资料-飞控板硬件构成.md / 资料-RM2027无人机外设与通信.md / 资料-机库系统怎么搞.md / 资料-任务规划与硬件接口需求.md
