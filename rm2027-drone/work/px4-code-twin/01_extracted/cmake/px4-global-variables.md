# PX4 构建期的关键全局变量（提炼知识）

> **这是 01 层（提炼知识）** —— 从 PX4 的 CMake 体系里挑出**又关键又全局**的那几个变量。
> **02 层遇到它们时链接回这里；03 层讲流程时引用这里。**
>
> **什么时候读这篇**：想知道"改哪个变量会波及全身"、"为什么这个变量引用次数很少却最重要"。
> **出处**：源码根见 [`../../tools/source-root.conf`](../../tools/source-root.conf)；数据为**实测统计**
> （统计口径：`CMakeLists.txt` + `cmake/*.cmake` + `platforms/nuttx/CMakeLists.txt` + `ROMFS/CMakeLists.txt`）。

---

## 0. 为什么要单独一篇

**构建期变量几百个，但真正"改了会波及全身"的就那么几个。**
**认识它们有个直接好处：**以后看到一个陌生的 `CMakeLists.txt`，你能一眼认出"哪些是全局的、哪些是局部的"。**

**★ 先说一条反直觉的结论（后面有数据）：**
```
引用次数【少】 ≠ 【不重要】。
有三个变量引用次数只有 3~5 次，却分别是：
  整条链的起点 / 决定编译宏名 / 决定"编什么进去"
⇒ 它们是【枢纽】：定义一处、影响全身。
```

---

## 1. 数据表（实测）

| 分级 | 变量 | 定义处 | 被引用的文件数 | 引用次数 | 一句话 |
|---|---|---|---|---|---|
| **T1** | **`PX4_SOURCE_DIR`** | [`CMakeLists.txt:104`](../../02_code_twin/build/cmake-kconfig.md#^src-CMakeLists-txt-104) | **13** | **141** | 源码根 —— 到处都是它 |
| **T1** | **`PX4_BINARY_DIR`** | [`CMakeLists.txt:105`](../../02_code_twin/build/cmake-kconfig.md#^src-CMakeLists-txt-105) | **11** | **78** | 构建目录 |
| **T1** | **`PX4_BOARD_DIR`** | [`cmake/px4_config.cmake:78`](../../02_code_twin/build/CMakeLists.md#^src-cmake-px4-config-cmake-78) | **7** | **42** | ★ **板级一切路径的根**（板级 `src/` 进 include 靠它） |
| **T1** | **`PX4_PLATFORM`** | [`cmake/kconfig.cmake:289`](px4-global-variables.md#^src-cmake-kconfig-cmake-289) | **7** | **31** | `nuttx` / `posix` —— 决定走哪套平台层 |
| **T2** | `PX4_CONFIG` | [`cmake/px4_config.cmake:117`](px4-global-variables.md#^src-cmake-px4-config-cmake-117) | 3 | 21 | 完整配置名 `<厂商>_<型号>_<标签>` |
| **T2** | `PX4_BOARD_VENDOR` | [`cmake/px4_config.cmake:112`](../../02_code_twin/build/CMakeLists.md#^src-cmake-px4-config-cmake-112) | 5 | 14 | 厂商（`rm2027`） |
| **T2** | `PX4_BOARD_MODEL` | [`cmake/px4_config.cmake:113`](px4-global-variables.md#^src-cmake-px4-config-cmake-113) | 5 | 14 | 型号（`fmu-h743`） |
| **T2** | `PX4_BOARD` | [`cmake/px4_config.cmake:105`](../../02_code_twin/build/CMakeLists.md#^src-cmake-px4-config-cmake-105) | 6 | 12 | `rm2027_fmu-h743`（构建目录名 / make 目标名） |
| **T3** | ★ **`CONFIG`** | [`cmake/px4_config.cmake:40`](px4-global-variables.md#^src-cmake-px4-config-cmake-40) | **1** | **5** | **整条链的起点** —— 没它什么都解不出来 |
| **T3** | ★ **`PX4_BOARD_NAME`** | [`cmake/px4_config.cmake:110`](../../02_code_twin/build/CMakeLists.md#^src-cmake-px4-config-cmake-110) | **2** | **3** | **决定 `CONFIG_ARCH_BOARD_*` 的宏名** ⇒ 写错整个板级 `#ifdef` 全失效 |
| **T3** | ★ **`config_module_list`** | [`cmake/kconfig.cmake:457`](px4-global-variables.md#^src-cmake-kconfig-cmake-457) | **2** | **4** | **决定"编什么进去"** —— 这块板有什么功能的总开关 |

---

## 2. T1：四个"到处都在用"的

### 2.1 `PX4_SOURCE_DIR` / `PX4_BINARY_DIR` —— 最先被定的两个
```cmake
# CMakeLists.txt:104-105
set(PX4_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}" CACHE FILEPATH "PX4 source directory" FORCE)
set(PX4_BINARY_DIR "${CMAKE_CURRENT_BINARY_DIR}" CACHE FILEPATH "PX4 binary directory" FORCE)
```
| 点 | 说明 |
|---|---|
| **它们是最早的一批** | 就在 `cmake_minimum_required` 之后（[`CMakeLists.txt:102`](px4-global-variables.md#^src-CMakeLists-txt-102)） |
| **`CACHE FILEPATH`** | 存进 `CMakeCache.txt`，跨目录可见 |
| **`FORCE`** | 每次都强制写（不信旧缓存） |
| **为什么是 `CACHE`** | 后面 `add_subdirectory` 进去的子目录也要读 ⇒ **必须跨目录作用域** |
| **紧接着就用了它** | [`CMakeLists.txt:107`](px4-global-variables.md#^src-CMakeLists-txt-107)：`list(APPEND CMAKE_MODULE_PATH ${PX4_SOURCE_DIR}/cmake)` ⇒ 于是 `include(px4_parse_function_args)` 才能被找到 |

**★ 判据：**看到 `${PX4_SOURCE_DIR}/xxx` 就是"从源码根往下找"**；`${PX4_BINARY_DIR}` 是"从构建目录往下找"。**

### 2.2 `PX4_BOARD_DIR` —— 板级一切的根（★ 板级移植时最该懂的一个）
```cmake
# cmake/px4_config.cmake:78
set(PX4_BOARD_DIR "${PX4_SOURCE_DIR}/boards/${vendor}/${model}" CACHE STRING "PX4 board directory" FORCE)
# :103
include_directories(${PX4_BOARD_DIR}/src)
```
**⇒ 这一行 `include_directories(${PX4_BOARD_DIR}/src)` 解释了**为什么板级头文件能被任意驱动 `#include`**。**
**⇒ 也是**为什么板级目录必须叫 `src`****（不叫 `src` 就进不了 include 路径）。

**★ 它被引用了 42 次 / 7 个文件** —— 包括：
```
boards/.../cmake/init.cmake 的 include（CMakeLists.txt:421）
extras/*_bootloader.bin 的生成（platforms/nuttx/CMakeLists.txt）
板级 Kconfig / defconfig 的查找
```

### 2.3 `PX4_PLATFORM` —— 决定走哪套平台层
```cmake
# cmake/kconfig.cmake:289-290
set(PX4_PLATFORM ${PLATFORM} CACHE STRING "PX4 board OS" FORCE)
list(APPEND CMAKE_MODULE_PATH ${PX4_SOURCE_DIR}/platforms/${PX4_PLATFORM}/cmake)
```
**⇒ 它是 `nuttx`（本板）还是 `posix`（SITL），决定了：**
```
· include 哪个平台目录
· 用哪套 px4_impl_os.cmake
· 编出的是 .px4 固件（nuttx）还是可执行文件（posix）
```

---

## 3. ★★ T3：三个"引用少但决定一切"的枢纽变量

**这三个是本文最该记的部分 —— 它们体现"详略得当"里的"略"：不需要多讲，但必须知道它们**存在**。**

### 3.1 `CONFIG` —— 整条链的起点（引用只 5 次）
```cmake
# cmake/px4_config.cmake:40-48
if(("$ENV{COLCON}" MATCHES "1") AND ("$ENV{ROS_VERSION}" MATCHES "2"))
    set(CONFIG "px4_ros2_default" CACHE STRING "desired configuration")
else()
    set(CONFIG "px4_sitl_default" CACHE STRING "desired configuration")
endif()
else()
    # Promote CONFIG from UNINITIALIZED (set by -D on command line) to STRING
    # so that cmake -L lists it. The Makefile's cmake-cache-check relies on
    # finding CONFIG in cmake -L output to avoid unnecessary reconfiguration.
    set(CONFIG "${CONFIG}" CACHE STRING "desired configuration" FORCE)
endif()
```
**★ 这段注释本身就把两个世界连起来了：**
```
你敲 make rm2027_fmu-h743_default
  → Makefile 传 -DCONFIG=rm2027_fmu-h743_default
  → CMake 把它从 UNINITIALIZED 提升成 STRING（上面那段 else 分支）
  → 【因为 Makefile 的 cmake-cache-check 要靠 `cmake -L` 的输出里找到 CONFIG】
  ⇒ 找不到它 ⇒ 每次都重新 configure（慢，但不致命）
```
**⇒ 这就是"变量引用少但关键"的典型：它只被 5 处引用，但没有它整条链起不来。**

**🔗 配套**：[`../make/gnu-make-syntax`](../make/gnu-make-syntax.md) 讲 `cmake-cache-check` 的 Make 语法；
[`../../02_code_twin/build/Makefile`](../../02_code_twin/build/Makefile.md) 讲那几行在干什么。

### 3.2 `PX4_BOARD_NAME` —— 决定编译宏名（引用只 3 次）
```cmake
# cmake/px4_config.cmake:108-110
string(TOUPPER ${PX4_BOARD} PX4_BOARD_NAME)         # rm2027_fmu-h743 → RM2027_FMU-H743
string(REPLACE "-" "_" PX4_BOARD_NAME ${PX4_BOARD_NAME})  # → RM2027_FMU_H743
set(PX4_BOARD_NAME ${PX4_BOARD_NAME} CACHE STRING "PX4 board define" FORCE)
# cmake/px4_add_common_flags.cmake:196
-DCONFIG_ARCH_BOARD_${PX4_BOARD_NAME}
```
**⇒ 最终宏：`CONFIG_ARCH_BOARD_RM2027_FMU_H743`。**
**★ 判据（写板级 `#ifdef` 时最容易错的一处）：**
```
必须【全大写 + 连字符变下划线】
  ✓ CONFIG_ARCH_BOARD_RM2027_FMU_H743
  ✗ CONFIG_ARCH_BOARD_rm2027_fmu_h743   （小写 ⇒ 永不命中）
  ✗ CONFIG_ARCH_BOARD_RM2027_FMU-H743   （带连字符 ⇒ 预处理器不认）
```

### 3.3 `config_module_list` —— 决定"编什么进去"（引用只 4 次）
```cmake
# cmake/kconfig.cmake:457
set(config_module_list ${config_module_list})
# :455
list(APPEND config_module_list ${board_support_src_rel}/src)     # ★ 板级 src 也是靠这个进去的
```
**⇒ 它是**"这块板有什么功能"的总开关**：**
```
.px4board 里的 CONFIG_* → Kconfig 展开 → config_module_list → 决定 add_subdirectory 哪些模块
⇒ 然后每个模块通过 set_property(GLOBAL APPEND PROPERTY PX4_MODULE_LIBRARIES …) 汇总到最终链接
```
**★ 判据：**"为什么这个驱动没编进去？" 第一个该看的就是它 —— 而不是去看驱动代码。**

---

## 4. 一条完整的传递链（把 T1/T2/T3 串起来）

```
你敲: make rm2027_fmu-h743_default
  ↓ Makefile:245 → cmake-build 宏 → -DCONFIG=rm2027_fmu-h743_default
【T3】CONFIG            px4_config.cmake:40      ← 整条链的起点
  ↓ :74-78 按 vendor/model/label 匹配
【T1】PX4_BOARD_DIR     px4_config.cmake:78      ← 板级一切的根
  ↓ :103 include_directories(${PX4_BOARD_DIR}/src)
【T3】PX4_BOARD_NAME    px4_config.cmake:108-110 ← 决定宏名
【T2】PX4_BOARD         px4_config.cmake:105     ← 构建目录名
【T2】PX4_BOARD_VENDOR/MODEL/LABEL               ← 拼出
【T2】PX4_CONFIG        px4_config.cmake:117
【T3】config_module_list kconfig.cmake:457       ← 决定编什么
【T1】PX4_PLATFORM      kconfig.cmake:289        ← 决定平台层
【T1】PX4_SOURCE_DIR    CMakeLists.txt:104       ← 到处都在用
【T1】PX4_BINARY_DIR    CMakeLists.txt:105
  ↓
产出: -DCONFIG_ARCH_BOARD_RM2027_FMU_H743 (px4_add_common_flags.cmake:196)
      build/rm2027_fmu-h743_default/ 整个目录
```

**⇒ 详细的逐行版在** [`../../02_code_twin/build/CMakeLists`](../../02_code_twin/build/CMakeLists.md)（02 层，行号孪生）。

---

## 5. 判据：改一个变量要连带检查什么

| 你改了 | 必须连带看 |
|---|---|
| **板名（`default.px4board` 所在目录）** | `PX4_BOARD_DIR` 是否指对 ⇒ 板级 `src` 进没进 include；`PX4_BOARD_NAME` 生成的宏名是否与板级 `#ifdef` 一致 |
| **`.px4board` 里的 `CONFIG_*`** | `config_module_list` 变了没 ⇒ 目标模块编进去没 |
| **`PX4_PLATFORM`** | `platforms/<平台>/cmake/px4_impl_os.cmake` 找得到没；产物类型（固件/可执行）对不对 |
| **`PX4_BOARD_DIR` 下的文件布局** | 板级目录**必须**有 `src/`（`:103` 写死）；`cmake/init.cmake` 会被 [`CMakeLists.txt:421`](../../02_code_twin/build/CMakeLists.md#^src-CMakeLists-txt-421) include |
| **`CONFIG`** | `CMakeCache.txt` 里旧值还在 ⇒ 可能要删掉重建（`CMakeCache.txt` 是缓存的真相） |

**★ 通用判据（本仓实测过的教训）：**
```
构建系统里"改了没生效"的头号原因 = 【CACHE 变量 + 旧的 CMakeCache.txt】
⇒ 判据动作：删 build/<目标>/CMakeCache.txt 再 configure
```

---

## 6. 跳转

- **逐行版（02 层）** → [`../../02_code_twin/build/CMakeLists`](../../02_code_twin/build/CMakeLists.md)（板名十条链 / `include()` 顺序 / GLOBAL 属性读写点）
- **CMake 语法本身** → [`cmake-syntax`](cmake-syntax.md)（`function` vs `macro` 作用域 / `GLOBAL` / `CACHE` / `if()` 的坑）
- **`px4_add_module` / `px4_add_library` 逐段** → [`01-px4-cmake-organization`](01-px4-cmake-organization.md)
- **`.px4board` ↔ Kconfig ↔ 宏 的桥** → [`03-kconfig-bridge`](03-kconfig-bridge.md)
- **`Makefile` 那几行（含 `cmake-cache-check`）** → [`../../02_code_twin/build/Makefile`](../../02_code_twin/build/Makefile.md) + [`../make/gnu-make-syntax`](../make/gnu-make-syntax.md)
- **流程全景** → [`../../03_moc/00-build-walkthrough`](../../03_moc/00-build-walkthrough.md)

---

## 标注源码（代码 + 本文档对它的解释）

> **这是「代码孪生」层**：上面是代码原文（带行号），下面是**本文档针对这一段说的话**。
> 行号可点，直接跳到 PX4 源码那一行。
### `CMakeLists.txt`
<a id="src-CMakeLists-txt-102"></a>
**↓ 文档在讲这里：**[`CMakeLists.txt:102`](px4-global-variables.md#^src-CMakeLists-txt-102)

```c
    99 │ #
   100 │ #=============================================================================
   101 │ 
▶  102 │ cmake_minimum_required(VERSION 3.10 FATAL_ERROR)
   103 │ 
   104 │ set(PX4_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}" CACHE FILEPATH "PX4 source directory" FORCE)
   105 │ set(PX4_BINARY_DIR "${CMAKE_CURRENT_BINARY_DIR}" CACHE FILEPATH "PX4 binary directory" FORCE)
```
> **说明**：它们是最早的一批 | 就在 cmake_minimum_required 之后（CMakeLists.txt:102） |
^src-CMakeLists-txt-102

<a id="src-CMakeLists-txt-104"></a>
**↓ 文档在讲这里：**[`CMakeLists.txt:104`](px4-global-variables.md#^src-CMakeLists-txt-104)

```c
   101 │ 
   102 │ cmake_minimum_required(VERSION 3.10 FATAL_ERROR)
   103 │ 
▶  104 │ set(PX4_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}" CACHE FILEPATH "PX4 source directory" FORCE)
   105 │ set(PX4_BINARY_DIR "${CMAKE_CURRENT_BINARY_DIR}" CACHE FILEPATH "PX4 binary directory" FORCE)
   106 │ 
   107 │ list(APPEND CMAKE_MODULE_PATH ${PX4_SOURCE_DIR}/cmake)
```
> **说明**：T1 | PX4_SOURCE_DIR | CMakeLists.txt:104 | 13 | 141 | 源码根 —— 到处都是它 |
^src-CMakeLists-txt-104

<a id="src-CMakeLists-txt-105"></a>
**↓ 文档在讲这里：**[`CMakeLists.txt:105`](px4-global-variables.md#^src-CMakeLists-txt-105)

```c
   102 │ cmake_minimum_required(VERSION 3.10 FATAL_ERROR)
   103 │ 
   104 │ set(PX4_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}" CACHE FILEPATH "PX4 source directory" FORCE)
▶  105 │ set(PX4_BINARY_DIR "${CMAKE_CURRENT_BINARY_DIR}" CACHE FILEPATH "PX4 binary directory" FORCE)
   106 │ 
   107 │ list(APPEND CMAKE_MODULE_PATH ${PX4_SOURCE_DIR}/cmake)
   108 │ include(px4_parse_function_args)
```
> **说明**：T1 | PX4_SOURCE_DIR | CMakeLists.txt:104 | 13 | 141 | 源码根 —— 到处都是它 | ┃ T1 | PX4_BINARY_DIR | CMakeLists.txt:105 | 11 | 78 | 构建目录 |
^src-CMakeLists-txt-105

<a id="src-CMakeLists-txt-107"></a>
**↓ 文档在讲这里：**[`CMakeLists.txt:107`](px4-global-variables.md#^src-CMakeLists-txt-107)

```c
   104 │ set(PX4_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}" CACHE FILEPATH "PX4 source directory" FORCE)
   105 │ set(PX4_BINARY_DIR "${CMAKE_CURRENT_BINARY_DIR}" CACHE FILEPATH "PX4 binary directory" FORCE)
   106 │ 
▶  107 │ list(APPEND CMAKE_MODULE_PATH ${PX4_SOURCE_DIR}/cmake)
   108 │ include(px4_parse_function_args)
   109 │ 
   110 │ #=============================================================================
```
> **说明**：为什么是 CACHE | 后面 add_subdirectory 进去的子目录也要读 ⇒ 必须跨目录作用域 | ┃ 紧接着就用了它 | CMakeLists.txt:107：list(APPEND CMAKE_MODULE_PATH ${PX4_SOURCE_DIR}/cmake) ⇒ 于是 include(px4_parse_function_args) 才能被找到 |
^src-CMakeLists-txt-107

<a id="src-CMakeLists-txt-421"></a>
**↓ 文档在讲这里：**[`CMakeLists.txt:421`](px4-global-variables.md#^src-CMakeLists-txt-421)

```c
   418 │ # board cmake init (optional)
   419 │ #
   420 │ if(EXISTS ${PX4_BOARD_DIR}/cmake/init.cmake)
▶  421 │ 	include(${PX4_BOARD_DIR}/cmake/init.cmake)
   422 │ endif()
   423 │ 
   424 │ #=============================================================================
```
> **说明**：PX4_PLATFORM | platforms/<平台>/cmake/px4_impl_os.cmake 找得到没；产物类型（固件/可执行）对不对 | ┃ PX4_BOARD_DIR 下的文件布局 | 板级目录必须有 src/（:103 写死）；cmake/init.cmake 会被 CMakeLists.txt:421 include |
^src-CMakeLists-txt-421

### `cmake/kconfig.cmake`
<a id="src-cmake-kconfig-cmake-289"></a>
**↓ 文档在讲这里：**[`cmake/kconfig.cmake:289`](px4-global-variables.md#^src-cmake-kconfig-cmake-289)

```c
   286 │ 
   287 │ 	if(PLATFORM)
   288 │ 		# set OS, and append specific platform module path
▶  289 │ 		set(PX4_PLATFORM ${PLATFORM} CACHE STRING "PX4 board OS" FORCE)
   290 │ 		list(APPEND CMAKE_MODULE_PATH ${PX4_SOURCE_DIR}/platforms/${PX4_PLATFORM}/cmake)
   291 │ 
   292 │ 		# platform-specific include path
```
> **说明**：T1 | PX4_BOARD_DIR | cmake/px4_config.cmake:78 | 7 | 42 | ★ 板级一切路径的根（板级 src/ 进 include 靠它） | ┃ T1 | PX4_PLATFORM | cmake/kconfig.cmake:289 | 7 | 31 | nuttx / posix —— 决定走哪套平台层 |
^src-cmake-kconfig-cmake-289

<a id="src-cmake-kconfig-cmake-457"></a>
**↓ 文档在讲这里：**[`cmake/kconfig.cmake:457`](px4-global-variables.md#^src-cmake-kconfig-cmake-457)

```c
   454 │ 	file(RELATIVE_PATH board_support_src_rel ${PX4_SOURCE_DIR}/src ${PX4_BOARD_DIR})
   455 │ 	list(APPEND config_module_list ${board_support_src_rel}/src)
   456 │ 
▶  457 │ 	set(config_module_list ${config_module_list})
   458 │ 	set(config_kernel_list ${config_kernel_list})
   459 │ 
   460 │ endif()
```
> **说明**：T3 | ★ PX4_BOARD_NAME | cmake/px4_config.cmake:110 | 2 | 3 | 决定 CONFIG_ARCH_BOARD_* 的宏名 ⇒ 写错整个板级 #ifdef 全失效 | ┃ T3 | ★ config_module_list | cmake/kconfig.cmake:457 | 2 | 4 | 决定"编什么进去" —— 这块板有什么功能的总开关 |
^src-cmake-kconfig-cmake-457

### `cmake/px4_config.cmake`
<a id="src-cmake-px4-config-cmake-40"></a>
**↓ 文档在讲这里：**[`cmake/px4_config.cmake:40`](px4-global-variables.md#^src-cmake-px4-config-cmake-40)

```c
    37 │ if(NOT CONFIG)
    38 │ 	# default to px4_ros2_default if building within a ROS2 colcon environment
    39 │ 	if(("$ENV{COLCON}" MATCHES "1") AND ("$ENV{ROS_VERSION}" MATCHES "2"))
▶   40 │ 		set(CONFIG "px4_ros2_default" CACHE STRING "desired configuration")
    41 │ 	else()
    42 │ 		set(CONFIG "px4_sitl_default" CACHE STRING "desired configuration")
    43 │ 	endif()
```
> **说明**：T2 | PX4_BOARD | cmake/px4_config.cmake:105 | 6 | 12 | rm2027_fmu-h743（构建目录名 / make 目标名） | ┃ T3 | ★ CONFIG | cmake/px4_config.cmake:40 | 1 | 5 | 整条链的起点 —— 没它什么都解不出来 |
^src-cmake-px4-config-cmake-40

<a id="src-cmake-px4-config-cmake-78"></a>
**↓ 文档在讲这里：**[`cmake/px4_config.cmake:78`](px4-global-variables.md#^src-cmake-px4-config-cmake-78)

```c
    75 │ 			    ((${label} STREQUAL "default") AND (${CONFIG} STREQUAL "${vendor}_${model}")) # default label can be omitted
    76 │ 			)
    77 │ 				set(PX4_CONFIG_FILE "${PX4_SOURCE_DIR}/boards/${filename}" CACHE FILEPATH "path to PX4 CONFIG file" FORCE)
▶   78 │ 				set(PX4_BOARD_DIR "${PX4_SOURCE_DIR}/boards/${vendor}/${model}" CACHE STRING "PX4 board directory" FORCE)
    79 │ 				set(MODEL "${model}" CACHE STRING "PX4 board model" FORCE)
    80 │ 				set(VENDOR "${vendor}" CACHE STRING "PX4 board vendor" FORCE)
    81 │ 				set(LABEL "${label}" CACHE STRING "PX4 board vendor" FORCE)
```
> **说明**：T1 | PX4_BINARY_DIR | CMakeLists.txt:105 | 11 | 78 | 构建目录 | ┃ T1 | PX4_BOARD_DIR | cmake/px4_config.cmake:78 | 7 | 42 | ★ 板级一切路径的根（板级 src/ 进 include 靠它） |
^src-cmake-px4-config-cmake-78

<a id="src-cmake-px4-config-cmake-105"></a>
**↓ 文档在讲这里：**[`cmake/px4_config.cmake:105`](px4-global-variables.md#^src-cmake-px4-config-cmake-105)

```c
   102 │ 
   103 │ include_directories(${PX4_BOARD_DIR}/src)
   104 │ 
▶  105 │ set(PX4_BOARD ${VENDOR}_${MODEL} CACHE STRING "PX4 board" FORCE)
   106 │ 
   107 │ # board name is uppercase with no underscores when used as a define
   108 │ string(TOUPPER ${PX4_BOARD} PX4_BOARD_NAME)
```
> **说明**：T2 | PX4_BOARD_MODEL | cmake/px4_config.cmake:113 | 5 | 14 | 型号（fmu-h743） | ┃ T2 | PX4_BOARD | cmake/px4_config.cmake:105 | 6 | 12 | rm2027_fmu-h743（构建目录名 / make 目标名） |
^src-cmake-px4-config-cmake-105

<a id="src-cmake-px4-config-cmake-110"></a>
**↓ 文档在讲这里：**[`cmake/px4_config.cmake:110`](px4-global-variables.md#^src-cmake-px4-config-cmake-110)

```c
   107 │ # board name is uppercase with no underscores when used as a define
   108 │ string(TOUPPER ${PX4_BOARD} PX4_BOARD_NAME)
   109 │ string(REPLACE "-" "_" PX4_BOARD_NAME ${PX4_BOARD_NAME})
▶  110 │ set(PX4_BOARD_NAME ${PX4_BOARD_NAME} CACHE STRING "PX4 board define" FORCE)
   111 │ 
   112 │ set(PX4_BOARD_VENDOR ${VENDOR} CACHE STRING "PX4 board vendor" FORCE)
   113 │ set(PX4_BOARD_MODEL ${MODEL} CACHE STRING "PX4 board model" FORCE)
```
> **说明**：T3 | ★ CONFIG | cmake/px4_config.cmake:40 | 1 | 5 | 整条链的起点 —— 没它什么都解不出来 | ┃ T3 | ★ PX4_BOARD_NAME | cmake/px4_config.cmake:110 | 2 | 3 | 决定 CONFIG_ARCH_BOARD_* 的宏名 ⇒ 写错整个板级 #ifdef 全失效 |
^src-cmake-px4-config-cmake-110

<a id="src-cmake-px4-config-cmake-112"></a>
**↓ 文档在讲这里：**[`cmake/px4_config.cmake:112`](px4-global-variables.md#^src-cmake-px4-config-cmake-112)

```c
   109 │ string(REPLACE "-" "_" PX4_BOARD_NAME ${PX4_BOARD_NAME})
   110 │ set(PX4_BOARD_NAME ${PX4_BOARD_NAME} CACHE STRING "PX4 board define" FORCE)
   111 │ 
▶  112 │ set(PX4_BOARD_VENDOR ${VENDOR} CACHE STRING "PX4 board vendor" FORCE)
   113 │ set(PX4_BOARD_MODEL ${MODEL} CACHE STRING "PX4 board model" FORCE)
   114 │ 
   115 │ set(PX4_BOARD_LABEL ${LABEL} CACHE STRING "PX4 board label" FORCE)
```
> **说明**：T2 | PX4_CONFIG | cmake/px4_config.cmake:117 | 3 | 21 | 完整配置名 <厂商>_<型号>_<标签> | ┃ T2 | PX4_BOARD_VENDOR | cmake/px4_config.cmake:112 | 5 | 14 | 厂商（rm2027） |
^src-cmake-px4-config-cmake-112

<a id="src-cmake-px4-config-cmake-113"></a>
**↓ 文档在讲这里：**[`cmake/px4_config.cmake:113`](px4-global-variables.md#^src-cmake-px4-config-cmake-113)

```c
   110 │ set(PX4_BOARD_NAME ${PX4_BOARD_NAME} CACHE STRING "PX4 board define" FORCE)
   111 │ 
   112 │ set(PX4_BOARD_VENDOR ${VENDOR} CACHE STRING "PX4 board vendor" FORCE)
▶  113 │ set(PX4_BOARD_MODEL ${MODEL} CACHE STRING "PX4 board model" FORCE)
   114 │ 
   115 │ set(PX4_BOARD_LABEL ${LABEL} CACHE STRING "PX4 board label" FORCE)
   116 │ 
```
> **说明**：T2 | PX4_BOARD_VENDOR | cmake/px4_config.cmake:112 | 5 | 14 | 厂商（rm2027） | ┃ T2 | PX4_BOARD_MODEL | cmake/px4_config.cmake:113 | 5 | 14 | 型号（fmu-h743） |
^src-cmake-px4-config-cmake-113

<a id="src-cmake-px4-config-cmake-117"></a>
**↓ 文档在讲这里：**[`cmake/px4_config.cmake:117`](px4-global-variables.md#^src-cmake-px4-config-cmake-117)

```c
   114 │ 
   115 │ set(PX4_BOARD_LABEL ${LABEL} CACHE STRING "PX4 board label" FORCE)
   116 │ 
▶  117 │ set(PX4_CONFIG "${PX4_BOARD_VENDOR}_${PX4_BOARD_MODEL}_${PX4_BOARD_LABEL}" CACHE STRING "PX4 config" FORCE)
   118 │ 
   119 │ if(EXISTS "${PX4_BOARD_DIR}/uavcan_board_identity")
   120 │ 	include ("${PX4_BOARD_DIR}/uavcan_board_identity")
```
> **说明**：T1 | PX4_PLATFORM | cmake/kconfig.cmake:289 | 7 | 31 | nuttx / posix —— 决定走哪套平台层 | ┃ T2 | PX4_CONFIG | cmake/px4_config.cmake:117 | 3 | 21 | 完整配置名 <厂商>_<型号>_<标签> |
^src-cmake-px4-config-cmake-117
