# PX4 构建完整总树 · Make → CMake → Kconfig → Ninja → PX4

> 入口：`make px4_sitl gz_x500`
> 目标：把 Makefile、CMake、Kconfig、Ninja、PX4 启动脚本串成一棵完整的因果树。

---

## 0. 一句话总览

```text
Makefile   负责调度
CMake      负责配置
Kconfig    负责选模块
Ninja      负责构建和执行目标
px4        负责运行
rcS        负责启动时选机型
```

---

## 1. 完整总树

```text
make px4_sitl gz_x500
│
├── [1] Shell / Make 解析层
│   │
│   ├── MAKECMDGOALS = px4_sitl gz_x500
│   ├── FIRST_ARG := $(firstword $(MAKECMDGOALS)) = px4_sitl
│   ├── ARGS := $(wordlist 2,...) = gz_x500
│   ├── SRC_DIR := /path/to/PX4-Autopilot
│   ├── ALL_CONFIG_TARGETS := $(shell find boards ...)
│   │   └── boards/**/*.px4board
│   │       ├── boards/px4/sitl/default.px4board      → px4_sitl_default
│   │       ├── boards/px4/fmu-v5/default.px4board    → px4_fmu-v5_default
│   │       └── ...
│   ├── CONFIG_TARGETS_DEFAULT := $(patsubst %_default,%,$(filter %_default,$(ALL_CONFIG_TARGETS)))
│   │   └── px4_sitl / px4_fmu-v5 / ...
│   └── PX4_CMAKE_GENERATOR := Ninja
│
├── [2] Make 目标匹配层
│   │
│   ├── px4_sitl
│   │   ├── 命中 $(CONFIG_TARGETS_DEFAULT):
│   │   ├── $@ = px4_sitl
│   │   ├── $@_default = px4_sitl_default
│   │   └── $(call cmake-build,px4_sitl_default)
│   │
│   └── gz_x500
│       ├── 命中 %:
│       ├── $(filter $(FIRST_ARG),$@) = 空
│       └── @# → 不执行
│           仍留在 ARGS
│
├── [3] cmake-build 函数层
│   │
│   ├── $(1) = px4_sitl_default
│   ├── CMAKE_ARGS += -DCONFIG=px4_sitl_default
│   ├── BUILD_DIR = $(SRC_DIR)/build/px4_sitl_default
│   ├── cmake-cache-check
│   ├── 必要时清理 NuttX / build
│   └── cmake "$(SRC_DIR)" -G Ninja -DCONFIG=px4_sitl_default
│
├── [4] CMake Configure 层
│   │
│   ├── 顶层 CMakeLists.txt
│   │   ├── list(APPEND CMAKE_MODULE_PATH ${PX4_SOURCE_DIR}/cmake)
│   │   ├── include(px4_parse_function_args)
│   │   │   └── cmake/px4_parse_function_args.cmake
│   │   │       └── 解析 PX4 自定义 CMake 函数参数
│   │   ├── include(px4_git)
│   │   │   └── cmake/px4_git.cmake
│   │   │       └── 获取 git 版本 / commit
│   │   ├── include(px4_add_module)
│   │   │   └── cmake/px4_add_module.cmake
│   │   │       └── 定义 px4_add_module()
│   │   ├── include(px4_config)
│   │   │   └── cmake/px4_config.cmake
│   │   │       ├── 用 -DCONFIG=px4_sitl_default
│   │   │       ├── 查找 boards/**/*.px4board
│   │   │       └── 找到 boards/px4/sitl/default.px4board
│   │   ├── include(kconfig)
│   │   │   └── cmake/kconfig.cmake
│   │   │       ├── 读 default.px4board
│   │   │       ├── 生成 boardconfig
│   │   │       ├── 生成 px4_boardconfig.h
│   │   │       └── 生成 config_module_list
│   │   └── include(px4_add_library)
│   │       └── cmake/px4_add_library.cmake
│   │
│   ├── add_subdirectory(src/lib)
│   ├── add_subdirectory(platforms/posix/src/px4)
│   ├── add_subdirectory(platforms)
│   ├── if board CMakeLists exists
│   │   └── add_subdirectory(boards/...)
│   │
│   ├── foreach(module in config_module_list)
│   │   └── add_subdirectory(src/${module})
│   │       └── modules/simulation/gz_bridge
│   │           └── src/modules/simulation/gz_bridge/CMakeLists.txt
│   │               ├── px4_add_module(
│   │               │     MODULE modules__simulation__gz_bridge
│   │               │     MAIN gz_bridge
│   │               │     ...)
│   │               └── add_custom_target(gz_x500 ...)
│   │
│   ├── add_subdirectory(src/lib/events)
│   ├── add_subdirectory(src/lib/metadata)
│   ├── add_subdirectory(src/lib/parameters)
│   └── add_subdirectory(platforms/posix)
│
├── [5] CMake 生成物
│   ├── build/px4_sitl_default/CMakeCache.txt
│   ├── build/px4_sitl_default/build.ninja
│   ├── build/px4_sitl_default/boardconfig
│   ├── build/px4_sitl_default/px4_boardconfig.h
│   └── build/px4_sitl_default/etc/   ← ROMFS 复制结果
│
├── [6] CMake Build / Ninja 层
│   │
│   ├── cmake --build build/px4_sitl_default -- gz_x500
│   │
│   └── Ninja
│       ├── 读 build.ninja
│       ├── 依赖：
│       │   ├── build/px4_sitl_default/bin/px4
│       │   └── build/.../src/modules/simulation/gz_plugins/px4_gz_plugins
│       │
│       ├── 编译/链接 px4
│       │
│       └── 执行 gz_x500 规则：
│           ├── cd .../gz_bridge
│           ├── PX4_SIM_MODEL=gz_x500
│           ├── GZ_IP=127.0.0.1
│           └── .../bin/px4
│
└── [7] PX4 运行层
    │
    ├── PX4 启动
    │   └── 执行 build/px4_sitl_default/etc/init.d-posix/rcS
    │
    ├── rcS
    │   ├── 读 PX4_SIM_MODEL=gz_x500
    │   ├── 在 etc/init.d-posix/airframes 里匹配
    │   │   └── <数字>_gz_x500
    │   ├── 匹配到 4001_gz_x500
    │   └── SYS_AUTOSTART=4001
    │
    ├── 4001_gz_x500
    │   ├── . rc.mc_defaults
    │   ├── SIM_GZ_EN=1
    │   ├── CA_ROTOR_*
    │   └── SIM_GZ_EC_*
    │
    ├── px4-rc.gzsim
    │   ├── gz sim
    │   └── gz_bridge
    │
    ├── model.sdf
    │   └── Tools/simulation/gz/models/x500/model.sdf
    │
    └── QGC
        └── MAVLink 14550
```

---

## 2. “Ninja 执行 gz_x500” 到底是什么意思

`gz_x500` 不是一个可执行文件。

它是 CMake 在：

```text
src/modules/simulation/gz_bridge/CMakeLists.txt
```

里用：

```cmake
add_custom_target(gz_x500 ...)
```

创建的一个 **自定义目标**。

CMake 会把它写进：

```text
build/px4_sitl_default/build.ninja
```

类似这样：

```ninja
build .../gz_x500: phony .../CMakeFiles/gz_x500 bin/px4 .../px4_gz_plugins

COMMAND = cd .../gz_bridge &&
          cmake -E env PX4_SIM_MODEL=gz_x500 GZ_IP=127.0.0.1 .../bin/px4
```

所以 Ninja 执行 `gz_x500` 的意思是：

```text
1. 读 build.ninja
2. 找到 gz_x500 规则
3. 先确保 bin/px4 和 px4_gz_plugins 已构建
4. 执行命令：
   PX4_SIM_MODEL=gz_x500 GZ_IP=127.0.0.1 bin/px4
```

也就是：

```text
Ninja 执行 gz_x500
= Ninja 启动 px4，并设置 PX4_SIM_MODEL=gz_x500
```

---

## 3. 两条链在哪里汇合

配置链：

```text
FIRST_ARG=px4_sitl
→ px4_sitl_default
→ -DCONFIG=px4_sitl_default
→ .px4board
→ config_module_list
→ add_subdirectory(gz_bridge)
→ add_custom_target(gz_x500)
```

运行链：

```text
ARGS=gz_x500
→ cmake --build ... -- gz_x500
→ Ninja 目标 gz_x500
→ PX4_SIM_MODEL=gz_x500
→ px4
→ rcS
→ 4001_gz_x500
```

汇合点：

```text
gz_x500
```

---

## 4. 为什么后面会走到 rcS

因为：

```text
rcS 不是 CMake 选的
rcS 是 px4 启动时固定执行的第一个脚本
```

CMake build 只负责：

```text
1. 编出 bin/px4
2. 把 ROMFS 复制到 build/.../etc
```

px4 启动后固定读：

```text
build/px4_sitl_default/etc/init.d-posix/rcS
```

rcS 再根据：

```text
PX4_SIM_MODEL=gz_x500
```

匹配到：

```text
4001_gz_x500
```

---

## 5. 一句话

```text
CMake 管“编译什么”
Ninja 管“构建和启动什么目标”
rcS 管“启动哪架飞机”
```
