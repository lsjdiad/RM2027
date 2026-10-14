# Findings · RM2027 无人机 L00 环境安装

> 规划：2026-08-28 · 记录发现/决策/环境基线

## 环境基线
- 系统：Windows 11（x64，25H2 26200），shell=PowerShell
- Python：`H:\Python\python.exe`（3.12.4）
- 工作根：`H:\AI\shared`
- PX4 SITL 需要 Linux → 计划用 WSL2 + Ubuntu
- 外部工具目录：`H:\AI\tools_that_agent_pull_from_gitxxx`（可写）

## WSL 检查结果（Phase 1，2026-08-28，二次确认，Python UTF-16 解码）
- **WSL2 本体完全正常**：`wsl --version` → WSL 2.7.12.0 / 内核 6.18.33.2 / WSLg 1.0.73 / Windows 10.0.26200(25H2)；`wsl --status` → 默认版本 2；`WSLService Running`
- **确认无任何发行版**：`wsl -l -v` → "没有已安装的分发"；注册表真源 `HKCU\...\Lxss` 空；无 .vhdx；开始菜单无 Ubuntu
- CPU 虚拟化已开（VT-x True）；Hypervisor 未运行（装 WSL 后会出现）
- 当前会话**非管理员**
- **用户"记得装了"的 = 原生双系统 Ubuntu**（Disk1 P7 97.2GB Unknown 分区，Grub 引导），不是 WSL 发行版——两者无关，互不影响
- 结论：需单独装 WSL 发行版（Ubuntu 24.04），建议微软商店方案（不需要管理员）；`wsl --install -d` 才需管理员
- 经验：wsl.exe 输出是 UTF-16LE，PowerShell 直接捕获会乱码 → 用 Python subprocess + decode('utf-16-le') 最可靠

## 已知决策/认知（来自前几轮）
- RM2027 新规：249g 小型空间智能机器人、4架、机库、30s、UWB 定位
- 249g 不需要上位机：PX4 MCU + UWB + 机库地面算力
- 学习主教材：浙大 Fast-Lab 课程（BV1WZ4y167me）+ Fast-Drone-250（GitHub）
- PX4 SITL 是后续一切验证的平台（L00 是第一道坎）
- WSL2 与原生 Ubuntu 可共存；shared 数据经 /mnt/h 直接互通（无需 git 同步）
