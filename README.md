# ~/RM2027 —— PX4 / QGC 学习与仿真环境

| 路径 | 是什么 |
|---|---|
| `PX4-Autopilot/` | PX4 固件源码（看代码、编译 SITL 都在这里） |
| `start-sitl.sh` | 一键启动 PX4 SITL + Gazebo（x500） |
| `notes/学习路线.md` | 学习路线文档（软链到 `~/桌面/无人机/学习路线.md`） |
| `notes/阶段0-基础篇.md` | 阶段 0 **原理层**：为什么能飞、坐标系、传感器融合、串级控制、动力/硬件/通信、飞行模式（软链到 `~/桌面/无人机/阶段0-基础篇.md`） |
| `notes/阶段0-教学.md` | 阶段 0 **操作层**：动手教学，怎么飞、怎么看日志（软链到 `~/桌面/无人机/阶段0-教学.md`） |
| `plotlog.py` | 把 .ulg 日志画成高度/姿态/电机三张曲线图 |
| `logs/` | ulog / tlog 飞行日志复盘放这里 |
| `notes/` | 代码阅读笔记放这里 |
| `my_modules/` | 以后自己写的 PX4 模块/驱动放这里 |

- QGC 地面站：`~/Applications/QGroundControl.AppImage`（或应用菜单里的 QGroundControl）
- 桌面入口：`~/桌面/RM2027` → 本目录
- 飞行日志（SITL）：`PX4-Autopilot/build/px4_sitl_default/rootfs/fs/log/<日期>/*.ulg`
- GitHub 走 ghfast 镜像：`git config --global --get-regexp url.` 可见改写规则；
  如需直连原站：`git config --global --unset-all url.https://ghfast.top/https://github.com/.insteadOf`
