# PX4 构建全流程

> 从 `make px4_sitl gz_x500` 到虚拟飞机飞起来，PX4 到底干了什么。
> 本文是阅读入口，按顺序链接到 PX4 各文件和启动脚本。
> 写法对齐 `03_moc/CMake-build-walkthrough.md`：先看链路，再看单个文件。

---

## 阅读顺序

先看 `Makefile`——它定义了命令怎么被翻译成 CMake 调用。

再由 `cmake-build` 进入 CMake，找到 `gz_x500` 目标。

然后看 PX4 启动脚本：

```
Makefile
  → src/modules/simulation/gz_bridge/CMakeLists.txt
    → ROMFS/px4fmu_common/init.d-posix/rcS
      → ROMFS/px4fmu_common/init.d-posix/airframes/4001_gz_x500
        → ROMFS/px4fmu_common/init.d-posix/px4-rc.gzsim
          → Tools/simulation/gz/models/x500/model.sdf
```

整条链路是单向的：

```
make 命令 → Makefile → CMake → Ninja → px4 → rcS → 机型 → Gazebo
```

---

## 全流程概览

```
make px4_sitl gz_x500
  │
  │  FIRST_ARG = px4_sitl
  │  ARGS      = gz_x500
  ▼
Makefile
  │  $(call cmake-build,px4_sitl_default)
  │
  │  cmake-build 做三件事：
  │    1. 准备 build/px4_sitl_default
  │    2. 运行 cmake 配置
  │    3. 运行 cmake --build
  ▼
cmake --build build/px4_sitl_default -- gz_x500
  │
  ▼
src/modules/simulation/gz_bridge/CMakeLists.txt
  │  add_custom_target(gz_x500 ...)
  │
  │  设置环境变量：
  │    PX4_SIM_MODEL=gz_x500
  │    GZ_IP=127.0.0.1
  ▼
build/px4_sitl_default/bin/px4
  │
  │  PX4 启动流程
  ▼
ROMFS/px4fmu_common/init.d-posix/rcS
  │  看到 PX4_SIM_MODEL=gz_x500
  │  匹配 airframes/4001_gz_x500
  │  设置 SYS_AUTOSTART=4001
  ▼
ROMFS/px4fmu_common/init.d-posix/airframes/4001_gz_x500
  │  . rc.mc_defaults
  │  param set-default SIM_GZ_EN 1
  │  param set-default CA_ROTOR_COUNT 4
  │  param set-default CA_ROTOR0_PX / PY / KM
  │  param set-default SIM_GZ_EC_*
  ▼
ROMFS/px4fmu_common/init.d-posix/px4-rc.gzsim
  │  启动 Gazebo
  │  启动 gz_bridge
  ▼
Tools/simulation/gz/models/x500/model.sdf
  │  机身
  │  4 个电机
  │  桨
  │  传感器
  ▼
Gazebo + gz_bridge + PX4
  │  传感器 → PX4 → 电机 → Gazebo
  ▼
QGC 通过 MAVLink 连接
```

---

## 代码孪生

| PX4 文件 | 作用 | 电控类比 |
|---|---|---|
| `Makefile` | 调度 make 参数给 CMake | 总调度表 |
| `cmake-build` | 准备目录、配置、构建 | 调度员 |
| `gz_bridge/CMakeLists.txt` | 定义 `gz_x500` 目标 | 工程图纸 |
| `build/px4_sitl_default/build.ninja` | CMake 生成的构建文件 | 施工计划 |
| `px4` 二进制 | PX4 主程序 | 主控程序 |
| `rcS` | 启动流程、选机型 | 上电初始化 |
| `4001_gz_x500` | 机型参数 | 机型参数表 |
| `model.sdf` | Gazebo 物理模型 | 机械/电机模型 |
| `gz_bridge` | PX4 ↔ Gazebo 数据桥 | CAN / SPI 驱动桥 |
| `QGC` | 地面站 | 遥控器 / 地面站 |

---

## 各文件详解入口

- [[Makefile]] — 只看 `FIRST_ARG` / `ARGS` / `cmake-build` / `cmake --build`
- [[gz_bridge/CMakeLists.txt]] — 只看 `add_custom_target(gz_x500 ...)`
- [[init.d-posix/rcS]] — 只看 `PX4_SIM_MODEL` 匹配机型
- [[airframes/4001_gz_x500]] — 只看 `CA_ROTOR_*` / `SIM_GZ_EC_*`
- [[px4-rc.gzsim]] — 只看启动 Gazebo / gz_bridge
- [[models/x500/model.sdf]] — 只看电机 / 桨 / 传感器

---

## 你想理解到哪一层

```
只想看懂命令：
  Makefile → cmake-build → cmake --build

想看懂机型：
  rcS → 4001_gz_x500

想看懂仿真：
  px4-rc.gzsim → model.sdf → gz_bridge

想自己改模型：
  model.sdf + CA_ROTOR_*
```

---

## 一句话记忆

```
Makefile   = 调度
CMake      = 图纸
Ninja      = 施工
px4        = 主控
rcS        = 上电
4001       = 机型
model.sdf  = 机械
gz_bridge  = 总线
QGC        = 遥控
```
