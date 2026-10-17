# PX4 构建因果链 · 从 make 到 rcS

> 入口：`make px4_sitl gz_x500`
> 重点：不是“文件树”，而是“参数怎么一路传下去，最后为什么匹配到 rcS / 4001_gz_x500”。

---

## 0. 一句话总览

```text
make 负责拆参数
CMake configure 负责选板级配置和模块
CMake build 负责构建并运行 gz_x500
Ninja 运行 px4 时设置 PX4_SIM_MODEL=gz_x500
px4 启动后执行 rcS
rcS 用 PX4_SIM_MODEL 匹配 airframe
匹配到 4001_gz_x500
```

rcS 不是 CMake 匹配出来的，它是 PX4 启动时**固定会执行**的启动脚本。

---

## 1. 因果链总图

```text
make px4_sitl gz_x500
│
├── A. Make 解析
│   ├── MAKECMDGOALS = px4_sitl gz_x500
│   ├── FIRST_ARG = px4_sitl
│   └── ARGS = gz_x500
│
├── B. 配置参数流（Make → CMake configure）
│   │
│   ├── FIRST_ARG = px4_sitl
│   │   └── 匹配 CONFIG_TARGETS_DEFAULT
│   │       └── $@_default = px4_sitl_default
│   │           └── $(call cmake-build,px4_sitl_default)
│   │
│   ├── cmake-build 内部
│   │   └── CMAKE_ARGS += -DCONFIG=px4_sitl_default
│   │
│   └── cmake -S <src> -B build/px4_sitl_default -G Ninja -DCONFIG=px4_sitl_default
│
├── C. CMake configure 阶段
│   │
│   ├── CMakeLists.txt
│   │   └── include(px4_config)
│   │       └── cmake/px4_config.cmake
│   │           ├── 用 CONFIG=px4_sitl_default 查找
│   │           └── 找到 boards/px4/sitl/default.px4board
│   │
│   ├── CMakeLists.txt
│   │   └── include(kconfig)
│   │       └── cmake/kconfig.cmake
│   │           ├── 读 default.px4board
│   │           ├── 生成 boardconfig
│   │           ├── 生成 px4_boardconfig.h
│   │           └── 生成 config_module_list
│   │                └── 包含 modules/simulation/gz_bridge
│   │
│   └── CMakeLists.txt
│       └── foreach(module in config_module_list)
│           └── add_subdirectory(src/${module})
│               └── add_subdirectory(src/modules/simulation/gz_bridge)
│                   └── gz_bridge/CMakeLists.txt
│                       ├── px4_add_module(...)
│                       └── add_custom_target(gz_x500 ...)
│
├── D. 构建目标流（Make → CMake build）
│   │
│   ├── ARGS = gz_x500
│   │   └── cmake --build build/px4_sitl_default -- gz_x500
│   │
│   └── Ninja
│       ├── 读 build.ninja
│       ├── 依赖 bin/px4 + px4_gz_plugins
│       └── 执行 gz_x500 目标
│           ├── cd .../gz_bridge
│           ├── PX4_SIM_MODEL=gz_x500
│           ├── GZ_IP=127.0.0.1
│           └── .../bin/px4
│
└── E. PX4 运行阶段
    │
    ├── PX4 启动
    │   └── 执行 ROMFS 启动脚本
    │       └── build/px4_sitl_default/etc/init.d-posix/rcS
    │
    ├── rcS
    │   ├── 读环境变量 PX4_SIM_MODEL=gz_x500
    │   ├── 在 etc/init.d-posix/airframes 里匹配
    │   │   └── [0-9]+_gz_x500
    │   ├── 匹配到 4001_gz_x500
    │   └── 设置 SYS_AUTOSTART=4001
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
    └── QGC
        └── MAVLink 14550
```

---

## 2. 为什么最后会匹配到 rcS

关键点：

```text
rcS 不是 CMake 选出来的
rcS 是 PX4 启动时固定执行的第一个脚本
```

CMake build 只是：

```text
把 px4 二进制编出来
把 ROMFS/px4fmu_common 复制到 build/px4_sitl_default/etc
```

PX4 二进制启动后，会去读：

```text
build/px4_sitl_default/etc/init.d-posix/rcS
```

所以：

```text
rcS = PX4 运行入口
```

它和 CMake 的配置没关系。

---

## 3. 为什么 rcS 能匹配到 4001_gz_x500

因为 Ninja 运行 px4 时设置了：

```text
PX4_SIM_MODEL=gz_x500
```

rcS 里做的是：

```sh
ls "${R}etc/init.d-posix/airframes" | \
  sed -n 's/^\([0-9][0-9]*\)_'${PX4_SIM_MODEL}'$/\1/p'
```

意思：

```text
在 airframes 目录里找文件名：
  <数字>_gz_x500
```

找到：

```text
4001_gz_x500
```

于是：

```text
SYS_AUTOSTART=4001
```

然后执行：

```text
4001_gz_x500
```

---

## 4. 两条参数链要分开

### 链 A：配置链

```text
FIRST_ARG=px4_sitl
→ px4_sitl_default
→ -DCONFIG=px4_sitl_default
→ boards/px4/sitl/default.px4board
→ config_module_list
→ add_subdirectory(gz_bridge)
→ gz_bridge/CMakeLists.txt
→ add_custom_target(gz_x500)
```

### 链 B：运行链

```text
ARGS=gz_x500
→ cmake --build ... -- gz_x500
→ Ninja 目标 gz_x500
→ PX4_SIM_MODEL=gz_x500
→ px4
→ rcS
→ 4001_gz_x500
```

两条链在 `gz_x500` 这个目标上汇合。

---

## 5. 哪些 CMake include 是后面会用到的

| include | 作用 | 后面用在哪 |
|---|---|---|
| `px4_parse_function_args` | 解析自定义 CMake 函数参数 | `px4_add_module` / `px4_add_library` |
| `px4_git` | 获取 git 版本 | 固件版本 / 日志 / QGC `ver` |
| `px4_add_module` | 定义模块 | 每个模块的 CMakeLists.txt |
| `px4_config` | 根据 CONFIG 找 `.px4board` | 板级配置选择 |
| `kconfig` | 读 `.px4board` 生成模块列表 | `config_module_list` |
| `px4_add_library` | 定义库 | 公共库 / 模块库 |

---

## 6. 一句话

```text
CMake 负责“编译什么、怎么编”
rcS 负责“启动时选哪架飞机”
两者通过 PX4_SIM_MODEL 间接连起来
```
