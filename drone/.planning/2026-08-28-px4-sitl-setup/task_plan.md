# Task Plan · RM2027 无人机 L00.5 整理 + L00 PX4 SITL 环境安装

> 计划创建：2026-08-28
> 目标：① 整理 L00.5《无人机系统全局图景》课程文档 ② 在本机（Windows 11）装好 PX4 SITL 仿真环境
> 前置认知：用户电控出身（STM32/ThreadX/云台），无人机概念已由多轮对话补齐

## Goal
在本会话内：产出 L00.5 系统图景文档；PX4 SITL 在本机跑通（仿真里"能飞"）或明确给出被卡住的步骤与替代方案。

## Phases

### Phase 0 · 整理 L00.5 系统全局图景课程 ✅
- [x] 写 `learning/L00.5-系统全局图景.md`：一张图讲清 飞控MCU/机载电脑/机库/UWB/通信/249g 关系
- [x] 更新 `learning/README.md` 课程地图
- 产出：L00.5 文档 ✅

### Phase 1 · 检查本机 WSL2/虚拟化状态 ✅
- [x] `wsl --status` / `wsl --list` / 虚拟化检查
- [x] 判断：WSL 可用但**无任何发行版**；CPU 虚拟化已开(VT-x True)；Hypervisor 未运行；**当前会话非管理员**
- 产出：环境基线已记 findings.md ✅
- **阻塞点**：装发行版需管理员权限 → 需用户以管理员执行 `wsl --install`

### Phase 2 · 安装 WSL 发行版 Ubuntu（用户选定：命令行+web-download，绕过商店）
- [ ] 用户以管理员 PowerShell 运行 `wsl --install -d Ubuntu-24.04 --web-download`（官方直链，不走商店）
- [ ] WSL 内核已就绪 → 大概率直接装发行版不需重启；若提示重启则重启
- [ ] 装完开始菜单搜 "Ubuntu" 打开，设用户名密码
- [ ] 我验证 `wsl -l -v` 出现 Ubuntu-24.04 且 VERSION=2
- 说明：`--web-download` 绕过微软商店（用户顾虑商店版本/速度）；需管理员。用户"记得装了"的是原生双系统 Ubuntu（97GB），与 WSL 无关

### Phase 3 · Ubuntu 内装 PX4 工具链 ✅
- [x] PX4 源码（git clone 失败 → codeload tarball 270MB 成功 → git fetch 补元数据）
- [x] 子模块 35/35 + 嵌套子模块递归补齐（klt_feature_tracker ×2）
- [x] ubuntu.sh（apt+pip 完成；ARM 交叉链 463MB 顺带装上）
- [x] OpenCV 4.6.0 单独补装（gz optical_flow 插件需要）
- [x] Gazebo Harmonic 1.0.0 单独装（osrf 官方源）
- [x] make px4_sitl_default 编译成功（1225/1225 目标）
- 修复记录：嵌套子模块 ×3、OpenCV、git index

### Phase 4 · 跑通 PX4 SITL ✅（headless 验证）
- [x] `make px4_sitl gz_x500 HEADLESS=1` 35 秒试跑：
  - Gazebo 8.15.0 启动、world ready、x500_0 生成
  - gz_bridge 桥接 OK、MAVLink 14550/14580 就绪、uxrce_dds 8888 就绪
  - logger/ekf2/commander 全模块加载
  - WARN "No connection to GCS" = 待装 QGC（预期内）
- [ ] QGroundControl 安装 + 连接 + 解锁起飞（下一轮）

## Next Step
L00 核心达成。下一轮：装 QGroundControl（Windows 侧）→ 连 SITL → 手动解锁起飞 → 进 L01 实验。

## Errors Encountered
| Error | Attempt | Resolution |
|-------|---------|------------|
| wsl 输出中文乱码 | 2 | 用 Python subprocess + utf-16-le 解码解决（最可靠） |
| 查询 WSL 可选功能/`wsl --install` 需管理员 | 1 | 改用微软商店装发行版（不需要管理员） |
| PowerShell ProcessStartInfo 构造语法错 | 1 | 改用 Python subprocess 解码 |
