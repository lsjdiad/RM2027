# 01 · PX4 的 CMake 组织方式：三个函数 + 三个全局属性

> 层：`01_extracted/`（提炼知识）｜视角：**构建运行时**
> 本篇只讲 PX4 自己发明的机制。CMake 本身的语法（`add_library`、`add_subdirectory`、`foreach`、`set(... CACHE ...)`）**默认你已经会**，只在 PX4 用法不直观的地方点一句。
> 本板实例一律用 `rm2027_fmu-h743_default`。

---

## 1. 一张图：PX4 顶层 CMakeLists 的执行序

`CMakeLists.txt` 从 `:102` 到 `:544`，关键顺序（**顺序本身有语义**）：

| 序 | 行 | 动作 | 为什么在这个位置 |
|---|---|---|---|
| 1 | `:104-105` | `PX4_SOURCE_DIR` / `PX4_BINARY_DIR` | 后面全要用 |
| 2 | `:107-108` | `list(APPEND CMAKE_MODULE_PATH ${PX4_SOURCE_DIR}/cmake)` | 才能 `include(px4_xxx)` |
| 3 | `:171` | `include(px4_add_module)` | 定义 `px4_add_module()` 函数 |
| 4 | `:172-173` | `set(config_module_list)` / `set(config_kernel_list)` | ★ **先清空**，等 `kconfig.cmake` 往里灌 |
| 5 | `:202` | `include(px4_config)` | `CONFIG` → `PX4_BOARD_DIR` / `PX4_BOARD_NAME`… |
| 6 | `:203` | `include(kconfig)` | ★ **`default.px4board` → `config_module_list`**（全部在这） |
| 7 | `:232-237` | `include(platforms/${PX4_PLATFORM}/cmake/px4_impl_os.cmake)` + `include(init)` | NuttX 侧的 `NUTTX_CONFIG` / 工具链 |
| 8 | `:242` | `project(px4 CXX C ASM)` | 到这里才知道语言与工具链 |
| 9 | `:413-415` | `include(px4_add_common_flags)` + `px4_add_common_flags()` + `px4_os_add_flags()` | ★ 产生 `-DCONFIG_ARCH_BOARD_RM2027_FMU_H743` |
| 10 | `:420-422` | 可选 `${PX4_BOARD_DIR}/cmake/init.cmake` | 本板**没有**这个文件 |
| 11 | `:429` | `add_subdirectory(msg EXCLUDE_FROM_ALL)` | 先生成 uORB 消息，别人才编译得过 |
| 12 | `:431` | `px4_generate_airframes_xml(BOARD ${PX4_BOARD})` | |
| 13 | `:465-468` | 4 个 INTERFACE 库：`parameters_interface` / `kernel_parameters_interface` / `events_interface` / `kernel_events_interface`（`:470` 才 `include(px4_add_library)`） | 解耦"谁依赖参数/事件" |
| 14 | `:471` | `add_subdirectory(src/lib EXCLUDE_FROM_ALL)` | |
| 15 | `:473-474` | `add_subdirectory(platforms/${PX4_PLATFORM}/src/px4)` + `add_subdirectory(platforms EXCLUDE_FROM_ALL)` | |
| 16 | `:476-478` | `if(EXISTS ${PX4_BOARD_DIR}/CMakeLists.txt) add_subdirectory(${PX4_BOARD_DIR})` | ★ **本板不触发**（该文件不存在） |
| 17 | `:480-482` | **`foreach(module ${config_module_list}) add_subdirectory(src/${module}) endforeach()`** | ★ **这就是"编哪些模块"的唯一入口** |
| 18 | `:485` | `add_subdirectory(src/lib/events EXCLUDE_FROM_ALL)` | 需要先知道全部源文件 |
| 19 | `:487` | `add_subdirectory(src/lib/metadata EXCLUDE_FROM_ALL)` | |
| 20 | `:490` | `add_subdirectory(src/lib/parameters EXCLUDE_FROM_ALL)` | ★ 生成 `generated_params/*.c` 与 `parameters.xml` |
| 21 | `:492-500` | 把 `parameters` / `events` 库接上 INTERFACE | |
| 22 | `:503` | `add_subdirectory(platforms/${PX4_PLATFORM})` | ★ **最后**才建 `px4` 可执行（`:40`）与 `.px4` 打包 |

> **最该记住的一句**：**第 17 步的输入 `config_module_list` 完全由第 6 步决定。**
> 所以"板子编出什么"这个问题，**答案只在 `cmake/kconfig.cmake` 里**，不在任何 `CMakeLists.txt` 里。
> ⇒ 详表见 `[03_moc/00-build-walkthrough](../../03_moc/00-build-walkthrough.md)` §3。

---

## 2. 三个函数：`px4_add_module` / `px4_add_library` / `px4_add_functional_gtest`

### 2.1 `px4_add_module`（[`cmake/px4_add_module.cmake:84`](../../02_code_twin/build/cmake-kconfig.md#^src-cmake-px4-add-module-cmake-84)）

**签名**（`:86-92`）：

```cmake
px4_add_module(MODULE <唯一名> MAIN <命令名>
               [STACK_MAIN] [STACK_MAX] [PRIORITY]
               [SRCS …] [INCLUDES …] [COMPILE_FLAGS …]
               [DEPENDS …] [MODULE_CONFIG …]
               [EXTERNAL] [DYNAMIC] [UNITY_BUILD])
```

**做了什么，按行号**：

| 行 | 行为 | 关心的人 |
|---|---|---|
| `:151` | `add_library(${MODULE} STATIC EXCLUDE_FROM_ALL ${SRCS})` | 默认路径（NuttX 板子走这条）⇒ **每个模块 = 一个静态库** |
| `:213-218` | `target_compile_definitions(... PX4_MAIN=${MAIN}_app_main)` + `MODULE_NAME="${MAIN}"` | ★ 于是 `dshot` 模块的入口符号叫 `dshot_app_main` |
| `:187-197` | `MAIN_DEFAULT`/`STACK_MAIN_DEFAULT 2048`/`PRIORITY_DEFAULT`，写进 target property | 供 NuttX 侧读（见 §3.2） |
| `:205-209` | NuttX 专属：`STACK_MAIN *= (__SIZEOF_POINTER__ >> 2)`；`-Wframe-larger-than=${STACK_MAX}` | ★ 所以 `h104_imu` 写 `STACK_MAIN 2048`，最终 builtin 表里是 `2048 * (__SIZEOF_POINTER__ >> 2)` |
| `:220-222` | `COMPILE_FLAGS` → `target_compile_options` | ★ `-DPARAM_PREFIX="PWM_MAIN"` 就是从这进来的 |
| `:228-230` | `INCLUDES` → `target_include_directories` | |
| `:232-243` | `DEPENDS`：静态库/接口库 → `target_link_libraries`，其余 → `add_dependencies` | ★ `DEPENDS arch_dshot` ⇒ 把平台库链进来 |
| `:251-255` | `MODULE_CONFIG <yaml>` → **`set_property(GLOBAL APPEND PROPERTY PX4_MODULE_CONFIG_FILES ...)`** | ★ 参数生成的输入 |
| `:176` / `:173` | `PX4_MODULE_LIBRARIES` / `PX4_KERNEL_MODULE_LIBRARIES` | ★ 最终链接列表 |
| `:178` / `:183` | `PX4_MODULE_PATHS`（**append 两次**） | ⇒ `build/…/config_module_list.txt` 里每个目录出现两遍 |
| `:179-180`/`:184-185` | `PX4_SRC_FILES` | 事件/metadata 生成要用 |
| `:94-135` | `UNITY_BUILD` 分支（把多个 `.cpp` `cat` 成一个） | 本板未用 |

### 2.2 `px4_add_library`（[`cmake/px4_add_library.cmake:41`](cmake-syntax.md#^src-cmake-px4-add-library-cmake-41)）

和 `px4_add_module` 的区别就三点：

| 行 | 内容 |
|---|---|
| `:42-44` | `add_library(${target} STATIC EXCLUDE_FROM_ALL ${ARGN})` |
| `:46` | `target_compile_definitions(${target} PRIVATE MODULE_NAME="${target}")` |
| `:51` | `add_dependencies(${target} uorb_headers parameters)` ← ★ **库自动依赖参数与 uORB**（module 是显式 `DEPENDS`） |
| `:54-56` | 同样往 `PX4_MODULE_PATHS` / `PX4_SRC_FILES` 里灌 |

本板用到的例子：`arch_dshot`（[`platforms/nuttx/src/px4/stm/stm32_common/dshot/CMakeLists.txt:34`](../../02_code_twin/build/nuttx-build.md#^src-platforms-nuttx-src-px4-stm-stm32-common-dshot-CMakeLists-txt-34)）、`mixer_module`（[`src/lib/mixer_module/CMakeLists.txt:46`](01-px4-cmake-organization.md#^src-src-lib-mixer-module-CMakeLists-txt-46)）。

> ⚠️ `px4_add_library` **没有 MAIN** ⇒ 它不注册成 NSH 命令、不进 `PX4_MODULE_LIBRARIES`。**"库"与"模块"的差别就在这。**

---

## 3. 三个全局属性：模块之间怎么互相看见

CMake 的 `GLOBAL` 属性是 PX4 用来"跨目录收集信息"的工具（因为 `add_subdirectory` 有作用域边界）。[`CMakeLists.txt:147`](../../tools/README.md#^src-CMakeLists-txt-147) 先 `define_property` 声明：

| 属性 | 谁 append | 谁读 | 用途 |
|---|---|---|---|
| `PX4_MODULE_LIBRARIES` | [`px4_add_module.cmake:176`](01-px4-cmake-organization.md#^src-cmake-px4-add-module-cmake-176) | [`platforms/nuttx/CMakeLists.txt:45`](01-px4-cmake-organization.md#^src-platforms-nuttx-CMakeLists-txt-45) `get_property(module_libraries …)` → `:392` `target_link_libraries(px4 PRIVATE ${module_libraries})` | ★ **决定固件里有哪些模块** |
| `PX4_MODULE_CONFIG_FILES` | [`px4_add_module.cmake:253`](01-px4-cmake-organization.md#^src-cmake-px4-add-module-cmake-253)、`px4_add_library` 使用者手写（如 [`mixer_module/CMakeLists.txt:63`](01-px4-cmake-organization.md#^src-CMakeLists-txt-63)） | [`src/lib/parameters/CMakeLists.txt:40`](01-px4-cmake-organization.md#^src-src-lib-parameters-CMakeLists-txt-40)、[`src/lib/metadata/CMakeLists.txt:35`](01-px4-cmake-organization.md#^src-src-lib-metadata-CMakeLists-txt-35) | ★ **参数 / 元数据生成的输入 yaml 清单** |
| `PX4_SRC_FILES` | `px4_add_module.cmake:180,185`、[`px4_add_library.cmake:56`](01-px4-cmake-organization.md#^src-cmake-px4-add-library-cmake-56) | `src/lib/events/CMakeLists.txt`（生成事件表用） | 全量源文件清单 |
| `PX4_MODULE_PATHS` | `px4_add_module.cmake:178,183`、[`px4_add_library.cmake:54`](01-px4-cmake-organization.md#^src-cmake-px4-add-library-cmake-54) | [`cmake/sbom.cmake:46`](01-px4-cmake-organization.md#^src-cmake-sbom-cmake-46) | SBOM；也是本文用来**回验路径解析**的证据 |

### 3.1 ★ `PX4_MODULE_LIBRARIES` 的后半段：从"目标"到"NSH 命令"

[`platforms/nuttx/NuttX/CMakeLists.txt:87`](01-px4-cmake-organization.md#^src-platforms-nuttx-NuttX-CMakeLists-txt-87)：

```cmake
if(CONFIG_NSH_LIBRARY)
    list(SORT module_libraries)              # :91
    foreach(module ${module_libraries})      # :92
        get_target_property(MAIN   ${module} MAIN)       # :93
        get_target_property(STACK  ${module} STACK_MAIN) # :94
        get_target_property(PRI   ${module} PRIORITY)    # :95
        if(MAIN)  # :97
            builtin_apps_string += '{ "MAIN", PRI, STACK, MAIN_main },\n'   # :98
```

`px4.bdat.in` / `px4.pdat.in`（`:137-138` `configure_file`）→ `:154-155` 拷进 `platforms/nuttx/NuttX/apps/builtin/registry/` → `:158` `make` 编 apps → 生成 `builtin_list.c`。

⇒ **这就是"为什么在 NSH 里敲 `dshot` 能跑起来"的全部机制。**
**实测**：`platforms/nuttx/NuttX/apps/builtin/registry/px4.bdat` 里本板那行是
`{ "dshot", SCHED_PRIORITY_DEFAULT, 2048 * (__SIZEOF_POINTER__ >> 2), dshot_main }`
（`STACK_MAIN` 走的是 [`px4_add_module.cmake:189`](01-px4-cmake-organization.md#^src-cmake-px4-add-module-cmake-189) 的默认值 2048，`:207` 把栈大小写成宏表达式。**推理**：本板是 32 位 ARM ⇒ `__SIZEOF_POINTER__` = 4 ⇒ `4 >> 2` = 1 ⇒ 实际仍是 **2048 字节**。`:206` 的注释说这个表达式是为了"给 64 位 NuttX 目标翻倍"，与本板无关。）

### 3.2 一个反直觉点：`MAIN` 名字 ≠ 库名

`px4_add_module(MODULE drivers__dshot MAIN dshot ...)` ⇒
- 静态库名：`drivers__dshot`（`px4.bdat` 里的 C 函数是 `dshot_main`，不是 `drivers__dshot_main`）
- NSH 命令名：`dshot`（`MAIN`）
- 入口符号：`dshot_app_main`（`PX4_MAIN=dshot_app_main`，`:214`）

**实测**（`compile_commands.json`）：`-DMODULE_NAME=\"dshot\" -DPX4_MAIN=dshot_app_main`。

---

## 4. 本板的自定义驱动为什么"加两个目录就够了"

| 驱动 | 加了什么 | 谁读它 |
|---|---|---|
| `hxy42688p` | `src/drivers/imu/hxy/{Kconfig, CMakeLists.txt}` + `src/drivers/imu/hxy/hxy42688p/{Kconfig, CMakeLists.txt, *.cpp/hpp}` | `src/drivers/imu/Kconfig` 用 `rsource "*/Kconfig"` 收子目录 Kconfig；[`cmake/kconfig.cmake:199`](01-px4-cmake-organization.md#^src-cmake-kconfig-cmake-199) 按 `imu/hxy/hxy42688p` 找到目录 |
| `h104_imu` | `src/drivers/imu/hipnuc_h104/**` | 同上（例外：目录名带下划线，靠 [`kconfig.cmake:203`](01-px4-cmake-organization.md#^src-cmake-kconfig-cmake-203) 的 `p1` 候选命中） |

**关键点**（**源码 + 推理**）：
- `src/drivers/imu/Kconfig` 用 `rsource "*/Kconfig"` 递归收 ⇒ **新增一级子目录不用改上层 Kconfig**。
- `src/drivers/imu/CMakeLists.txt` **不存在**，`src/drivers/CMakeLists.txt` **也不存在**（`ls` 确认）⇒ **模块目录的纳入只走 `config_module_list` 这一条路**，不走 `add_subdirectory` 树。
- ⇒ **`src/drivers/imu/hxy/CMakeLists.txt`（内容仅 `add_subdirectory(hxy42688p)`）在本构建里是死代码** —— `config_module_list` 给的是叶子 `drivers/imu/hxy/hxy42688p`，`add_subdirectory` 直达叶子。**推理**，未用 `cmake --graphviz` 验证。

---

## 5. 名称映射速查（写新驱动时最容易错的一格）

| 概念 | 语法 | 本板例子 |
|---|---|---|
| Kconfig 符号 | `menuconfig <NAME>` | `DRIVERS_IMU_HXY_HXY42688P` |
| `.px4board` 行 | `CONFIG_<NAME>=y` | `CONFIG_DRIVERS_IMU_HXY_HXY42688P=y` |
| C 宏 | `#define CONFIG_<NAME> 1` | `#define CONFIG_DRIVERS_IMU_HXY_HXY42688P 1` |
| 目录（**由 CMake 按名字猜，不是你写死**） | `<CONFIG_DRIVERS_ 后面的部分，`_`→`/`>` | `src/drivers/imu/hxy/hxy42688p` |
| `px4_add_module(MODULE …)` | 任意唯一串，习惯 `父__子` | `drivers__imu__hxy__hxy42688p` |
| `px4_add_module(MAIN …)` | **NSH 命令名** | `hxy42688p` |
| 源文件的 `hrt`/uORB 名 | | 见 `[03_moc/02-sensor-flow](../../03_moc/02-sensor-flow.md)` |

> ★ 唯一**没有**自动推导的一格是"目录"：[`kconfig.cmake:197`](../../02_code_twin/build/cmake-kconfig.md#^src-cmake-kconfig-cmake-197) 用 7 个正则候选去**猜**你的目录排布。猜不到就 `FATAL_ERROR`（`:212`）。这就是为什么 PX4 里目录命名看起来五花八门（`barometer/goertek/spa06`、`magnetometer/isentek/ist8310`、`imu/hipnuc_h104`），**它们都是在迎合那 7 个候选**。
> 细节见 `[01_extracted/cmake/03-kconfig-bridge](03-kconfig-bridge.md)`。

---

## 6. 跳转

- **想看这套机制在本板跑出什么具体值**：`[03_moc/00-build-walkthrough](../../03_moc/00-build-walkthrough.md)`（§3 是 Kconfig 桥，§4 是"宏→源文件→参数"对照表）。
- **想知道 `build/` 目录里每个子目录是谁产出的**：`[01_extracted/cmake/02-build-dir-map](02-build-dir-map.md)`。
- **想知道 `default.px4board` ↔ Kconfig ↔ CMake ↔ C 宏 四层怎么对应**：`[01_extracted/cmake/03-kconfig-bridge](03-kconfig-bridge.md)`。
- **构建走完之后的执行序**：`[03_moc/01-poweron-walkthrough](../../03_moc/01-poweron-walkthrough.md)`。

---

## 标注源码（代码 + 本文档对它的解释）

> **这是「代码孪生」层**：上面是代码原文（带行号），下面是**本文档针对这一段说的话**。
> 行号可点，直接跳到 PX4 源码那一行。
### `CMakeLists.txt`
<a id="src-CMakeLists-txt-63"></a>
**↓ 文档在讲这里：**[`CMakeLists.txt:63`](01-px4-cmake-organization.md#^src-CMakeLists-txt-63)

```c
    60 │ #
    61 │ # * Use px4_parse_function_args to parse functions and check for required
    62 │ #   arguments. Unless there is only one argument in the function and it is clear.
▶   63 │ #
    64 │ # * Never use macros. They allow overwriting global variables and this
    65 │ #	makes variable declarations hard to locate.
    66 │ #
```
> **说明**：PX4_MODULE_LIBRARIES | px4_add_module.cmake:176 | platforms/nuttx/CMakeLists.txt:45 get_property(module_libraries …) → :392 target_link_libraries(px4 PRIVATE ${module_libraries}) | ★ 决定固件里有哪些模块 | ┃ PX4_MODULE_CONFIG_FILES | px4_add_module.cmake:253、px4_add_library 使用者手写（如 mixer_module/CMakeLists.txt:63） | src/lib/parameters/CMakeLists.txt:40、src/lib/metadata/CMakeLists.txt:35 | ★ 参数 / 元数据生成的输入 y
^src-CMakeLists-txt-63

<a id="src-CMakeLists-txt-147"></a>
**↓ 文档在讲这里：**[`CMakeLists.txt:147`](01-px4-cmake-organization.md#^src-CMakeLists-txt-147)

```c
   144 │ string(REGEX MATCH "g([a-f0-9]+)$" GIT_HASH "${PX4_GIT_TAG}")
   145 │ set(PX4_GIT_HASH ${CMAKE_MATCH_1})
   146 │ 
▶  147 │ define_property(GLOBAL PROPERTY PX4_MODULE_LIBRARIES
   148 │                  BRIEF_DOCS "PX4 module libs"
   149 │                  FULL_DOCS "List of all PX4 module libraries"
   150 │                  )
```
> **说明**：CMake 的 GLOBAL 属性是 PX4 用来"跨目录收集信息"的工具（因为 add_subdirectory 有作用域边界）。CMakeLists.txt:147 先 define_property 声明：
^src-CMakeLists-txt-147

### `cmake/kconfig.cmake`
<a id="src-cmake-kconfig-cmake-197"></a>
**↓ 文档在讲这里：**[`cmake/kconfig.cmake:197`](01-px4-cmake-organization.md#^src-cmake-kconfig-cmake-197)

```c
   194 │ 			string(REGEX REPLACE "(^[a-z]+)_([a-z0-9]+[a-z0-9]+)_([a-z0-9]+_[a-z0-9]+).*$" "\\3" driver_p5_subsubfolder ${driver})
   195 │ 
   196 │ 			# Trick circumvent PX4 src naming problem with underscores and slashes
▶  197 │ 			if(EXISTS ${PX4_SOURCE_DIR}/src/drivers/${driver})
   198 │ 				list(APPEND config_module_list drivers/${driver})
   199 │ 			elseif(EXISTS ${PX4_SOURCE_DIR}/src/drivers/${driver_path})
   200 │ 				list(APPEND config_module_list drivers/${driver_path})
```
> **说明**：★ 唯一没有自动推导的一格是"目录"：kconfig.cmake:197 用 7 个正则候选去猜你的目录排布。猜不到就 FATAL_ERROR（:212）。这就是为什么 PX4 里目录命名看起来五花八门（barometer/goertek/spa06、magnetometer/isentek/ist8310、imu/hipnuc_h104），它们都是在迎合那 7 个候选。
^src-cmake-kconfig-cmake-197

<a id="src-cmake-kconfig-cmake-199"></a>
**↓ 文档在讲这里：**[`cmake/kconfig.cmake:199`](01-px4-cmake-organization.md#^src-cmake-kconfig-cmake-199)

```c
   196 │ 			# Trick circumvent PX4 src naming problem with underscores and slashes
   197 │ 			if(EXISTS ${PX4_SOURCE_DIR}/src/drivers/${driver})
   198 │ 				list(APPEND config_module_list drivers/${driver})
▶  199 │ 			elseif(EXISTS ${PX4_SOURCE_DIR}/src/drivers/${driver_path})
   200 │ 				list(APPEND config_module_list drivers/${driver_path})
   201 │ 			elseif(EXISTS ${PX4_SOURCE_DIR}/src/drivers/${driver_p3_folder}/${driver_p3_subfolder}/${driver_p3_subsubfolder})
   202 │ 				list(APPEND config_module_list drivers/${driver_p3_folder}/${driver_p3_subfolder}/${driver_p3_subsubfolder})
```
> **说明**：hxy42688p | src/drivers/imu/hxy/{Kconfig, CMakeLists.txt} + src/drivers/imu/hxy/hxy42688p/{Kconfig, CMakeLists.txt, *.cpp/hpp} | src/drivers/imu/Kconfig 用 rsource "*/Kconfig" 收子目录 Kconfig；cmake/kconfi
^src-cmake-kconfig-cmake-199

<a id="src-cmake-kconfig-cmake-203"></a>
**↓ 文档在讲这里：**[`cmake/kconfig.cmake:203`](01-px4-cmake-organization.md#^src-cmake-kconfig-cmake-203)

```c
   200 │ 				list(APPEND config_module_list drivers/${driver_path})
   201 │ 			elseif(EXISTS ${PX4_SOURCE_DIR}/src/drivers/${driver_p3_folder}/${driver_p3_subfolder}/${driver_p3_subsubfolder})
   202 │ 				list(APPEND config_module_list drivers/${driver_p3_folder}/${driver_p3_subfolder}/${driver_p3_subsubfolder})
▶  203 │ 			elseif(EXISTS ${PX4_SOURCE_DIR}/src/drivers/${driver_p1_folder}/${driver_p1_subfolder})
   204 │ 				list(APPEND config_module_list drivers/${driver_p1_folder}/${driver_p1_subfolder})
   205 │ 			elseif(EXISTS ${PX4_SOURCE_DIR}/src/drivers/${driver_p4_folder}/${driver_p4_subfolder})
   206 │ 				list(APPEND config_module_list drivers/${driver_p4_folder}/${driver_p4_subfolder})
```
> **说明**：hxy42688p | src/drivers/imu/hxy/{Kconfig, CMakeLists.txt} + src/drivers/imu/hxy/hxy42688p/{Kconfig, CMakeLists.txt, *.cpp/hpp} | src/drivers/imu/Kconfig 用 rsource "*/Kconfig" 收子目录 Kconfig；cmake/kconfi ┃ h104_imu | src/drivers/imu/hipnuc_h104/ | 同上（例外：目录名带下划线，靠 kconfig.cmake:203 的 p1 候选命中） |
^src-cmake-kconfig-cmake-203

### `cmake/px4_add_library.cmake`
<a id="src-cmake-px4-add-library-cmake-41"></a>
**↓ 文档在讲这里：**[`cmake/px4_add_library.cmake:41`](01-px4-cmake-organization.md#^src-cmake-px4-add-library-cmake-41)

```c
    38 │ #
    39 │ #	Like add_library but with PX4 platform dependencies
    40 │ #
▶   41 │ function(px4_add_library target)
    42 │ 	add_library(${target} STATIC EXCLUDE_FROM_ALL
    43 │ 		${ARGN}
    44 │ 	)
```
> **说明**：2.2 px4_add_library（cmake/px4_add_library.cmake:41）
^src-cmake-px4-add-library-cmake-41

<a id="src-cmake-px4-add-library-cmake-54"></a>
**↓ 文档在讲这里：**[`cmake/px4_add_library.cmake:54`](01-px4-cmake-organization.md#^src-cmake-px4-add-library-cmake-54)

```c
    51 │ 	add_dependencies(${target} uorb_headers parameters)
    52 │ 	target_link_libraries(${target} PRIVATE prebuild_targets)
    53 │ 
▶   54 │ 	set_property(GLOBAL APPEND PROPERTY PX4_MODULE_PATHS ${CMAKE_CURRENT_SOURCE_DIR})
    55 │ 	px4_list_make_absolute(ABS_SRCS ${CMAKE_CURRENT_SOURCE_DIR} ${ARGN})
    56 │ 	set_property(GLOBAL APPEND PROPERTY PX4_SRC_FILES ${ABS_SRCS})
    57 │ endfunction()
```
> **说明**：PX4_SRC_FILES | px4_add_module.cmake:180,185、px4_add_library.cmake:56 | src/lib/events/CMakeLists.txt（生成事件表用） | 全量源文件清单 | ┃ PX4_MODULE_PATHS | px4_add_module.cmake:178,183、px4_add_library.cmake:54 | cmake/sbom.cmake:46 | SBOM；也是本文用来回验路径解析的证据 |
^src-cmake-px4-add-library-cmake-54

<a id="src-cmake-px4-add-library-cmake-56"></a>
**↓ 文档在讲这里：**[`cmake/px4_add_library.cmake:56`](01-px4-cmake-organization.md#^src-cmake-px4-add-library-cmake-56)

```c
    53 │ 
    54 │ 	set_property(GLOBAL APPEND PROPERTY PX4_MODULE_PATHS ${CMAKE_CURRENT_SOURCE_DIR})
    55 │ 	px4_list_make_absolute(ABS_SRCS ${CMAKE_CURRENT_SOURCE_DIR} ${ARGN})
▶   56 │ 	set_property(GLOBAL APPEND PROPERTY PX4_SRC_FILES ${ABS_SRCS})
    57 │ endfunction()
    58 │ 
```
> **说明**：PX4_MODULE_CONFIG_FILES | px4_add_module.cmake:253、px4_add_library 使用者手写（如 mixer_module/CMakeLists.txt:63） | src/lib/parameters/CMakeLists.txt:40、src/lib/metadata/CMakeLists.txt:35 | ★ 参数 / 元数据生成的输入 y ┃ PX4_SRC_FILES | px4_add_module.cmake:180,185、px4_add_library.cmake:56 | src/lib/events/CMakeLists.txt（生成事件表用） | 全量源文件清单 |
^src-cmake-px4-add-library-cmake-56

### `cmake/px4_add_module.cmake`
<a id="src-cmake-px4-add-module-cmake-84"></a>
**↓ 文档在讲这里：**[`cmake/px4_add_module.cmake:84`](01-px4-cmake-organization.md#^src-cmake-px4-add-module-cmake-84)

```c
    81 │ #				git_nuttx
    82 │ #			)
    83 │ #
▶   84 │ function(px4_add_module)
    85 │ 
    86 │ 	px4_parse_function_args(
    87 │ 		NAME px4_add_module
```
> **说明**：2.1 px4_add_module（cmake/px4_add_module.cmake:84）
^src-cmake-px4-add-module-cmake-84

<a id="src-cmake-px4-add-module-cmake-176"></a>
**↓ 文档在讲这里：**[`cmake/px4_add_module.cmake:176`](01-px4-cmake-organization.md#^src-cmake-px4-add-module-cmake-176)

```c
   173 │ 			set_property(GLOBAL APPEND PROPERTY PX4_KERNEL_MODULE_LIBRARIES ${MODULE})
   174 │ 		else()
   175 │ 			target_link_libraries(${MODULE} PRIVATE events_interface parameters_interface px4_layer uORB)
▶  176 │ 			set_property(GLOBAL APPEND PROPERTY PX4_MODULE_LIBRARIES ${MODULE})
   177 │ 		endif()
   178 │ 		set_property(GLOBAL APPEND PROPERTY PX4_MODULE_PATHS ${CMAKE_CURRENT_SOURCE_DIR})
   179 │ 		px4_list_make_absolute(ABS_SRCS ${CMAKE_CURRENT_SOURCE_DIR} ${SRCS})
```
> **说明**：PX4_MODULE_LIBRARIES | px4_add_module.cmake:176 | platforms/nuttx/CMakeLists.txt:45 get_property(module_libraries …) → :392 target_link_libraries(px4 PRIVATE ${module_libraries}) | ★ 决定固件里有哪些模块 |
^src-cmake-px4-add-module-cmake-176

<a id="src-cmake-px4-add-module-cmake-189"></a>
**↓ 文档在讲这里：**[`cmake/px4_add_module.cmake:189`](01-px4-cmake-organization.md#^src-cmake-px4-add-module-cmake-189)

```c
   186 │ 
   187 │ 	# set defaults if not set
   188 │ 	set(MAIN_DEFAULT MAIN-NOTFOUND)
▶  189 │ 	set(STACK_MAIN_DEFAULT 2048)
   190 │ 	set(PRIORITY_DEFAULT SCHED_PRIORITY_DEFAULT)
   191 │ 
   192 │ 	foreach(property MAIN STACK_MAIN PRIORITY)
```
> **说明**：{ "dshot", SCHED_PRIORITY_DEFAULT, 2048 * (SIZEOF_POINTER >> 2), dshot_main } ┃ （STACK_MAIN 走的是 px4_add_module.cmake:189 的默认值 2048，:207 把栈大小写成宏表达式。推理：本板是 32 位 ARM ⇒ SIZEOF_POINTER = 4 ⇒ 4 >> 2 = 1 ⇒ 实际仍是 2048 字节。:206 的注释说这个表达式是为了"给 64 位 NuttX 目标翻倍"，与本板无关。）
^src-cmake-px4-add-module-cmake-189

<a id="src-cmake-px4-add-module-cmake-253"></a>
**↓ 文档在讲这里：**[`cmake/px4_add_module.cmake:253`](01-px4-cmake-organization.md#^src-cmake-px4-add-module-cmake-253)

```c
   250 │ 
   251 │ 	if(MODULE_CONFIG)
   252 │ 		foreach(module_config ${MODULE_CONFIG})
▶  253 │ 			set_property(GLOBAL APPEND PROPERTY PX4_MODULE_CONFIG_FILES ${CMAKE_CURRENT_SOURCE_DIR}/${module_config})
   254 │ 		endforeach()
   255 │ 	endif()
   256 │ endfunction()
```
> **说明**：PX4_MODULE_LIBRARIES | px4_add_module.cmake:176 | platforms/nuttx/CMakeLists.txt:45 get_property(module_libraries …) → :392 target_link_libraries(px4 PRIVATE ${module_libraries}) | ★ 决定固件里有哪些模块 | ┃ PX4_MODULE_CONFIG_FILES | px4_add_module.cmake:253、px4_add_library 使用者手写（如 mixer_module/CMakeLists.txt:63） | src/lib/parameters/CMakeLists.txt:40、src/lib/metadata/CMakeLists.txt:35 | ★ 参数 / 元数据生成的输入 y
^src-cmake-px4-add-module-cmake-253

### `cmake/sbom.cmake`
<a id="src-cmake-sbom-cmake-46"></a>
**↓ 文档在讲这里：**[`cmake/sbom.cmake:46`](01-px4-cmake-organization.md#^src-cmake-sbom-cmake-46)

```c
    43 │ 
    44 │ 	# Write board-specific module list for the SBOM generator
    45 │ 	set(sbom_module_list_file "${PX4_BINARY_DIR}/config_module_list.txt")
▶   46 │ 	get_property(module_list GLOBAL PROPERTY PX4_MODULE_PATHS)
    47 │ 	string(REPLACE ";" "\n" module_list_content "${module_list}")
    48 │ 	file(GENERATE OUTPUT ${sbom_module_list_file} CONTENT "${module_list_content}\n")
    49 │ 
```
> **说明**：PX4_SRC_FILES | px4_add_module.cmake:180,185、px4_add_library.cmake:56 | src/lib/events/CMakeLists.txt（生成事件表用） | 全量源文件清单 | ┃ PX4_MODULE_PATHS | px4_add_module.cmake:178,183、px4_add_library.cmake:54 | cmake/sbom.cmake:46 | SBOM；也是本文用来回验路径解析的证据 |
^src-cmake-sbom-cmake-46

### `platforms/nuttx/CMakeLists.txt`
<a id="src-platforms-nuttx-CMakeLists-txt-45"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/CMakeLists.txt:45`](01-px4-cmake-organization.md#^src-platforms-nuttx-CMakeLists-txt-45)

```c
    42 │ set_target_properties(px4 PROPERTIES OUTPUT_NAME ${FW_NAME})
    43 │ add_dependencies(px4 git_nuttx)
    44 │ 
▶   45 │ get_property(module_libraries GLOBAL PROPERTY PX4_MODULE_LIBRARIES)
    46 │ 
    47 │ if (NOT CONFIG_BUILD_FLAT)
    48 │ 	add_executable(px4_kernel ${PX4_SOURCE_DIR}/platforms/common/empty.c)
```
> **说明**：PX4_MODULE_LIBRARIES | px4_add_module.cmake:176 | platforms/nuttx/CMakeLists.txt:45 get_property(module_libraries …) → :392 target_link_libraries(px4 PRIVATE ${module_libraries}) | ★ 决定固件里有哪些模块 |
^src-platforms-nuttx-CMakeLists-txt-45

### `platforms/nuttx/NuttX/CMakeLists.txt`
<a id="src-platforms-nuttx-NuttX-CMakeLists-txt-87"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/NuttX/CMakeLists.txt:87`](01-px4-cmake-organization.md#^src-platforms-nuttx-NuttX-CMakeLists-txt-87)

```c
    84 │ add_custom_target(nuttx_context DEPENDS ${NUTTX_DIR}/include/nuttx/config.h)
    85 │ 
    86 │ 
▶   87 │ # builtins
    88 │ set(builtin_apps_string)
    89 │ set(builtin_apps_decl_string)
    90 │ if(CONFIG_NSH_LIBRARY)
```
> **说明**：platforms/nuttx/NuttX/CMakeLists.txt:87：
^src-platforms-nuttx-NuttX-CMakeLists-txt-87

### `platforms/nuttx/src/px4/stm/stm32_common/dshot/CMakeLists.txt`
<a id="src-platforms-nuttx-src-px4-stm-stm32-common-dshot-CMakeLists-txt-34"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/px4/stm/stm32_common/dshot/CMakeLists.txt:34`](01-px4-cmake-organization.md#^src-platforms-nuttx-src-px4-stm-stm32-common-dshot-CMakeLists-txt-34)

```c
    31 │ #
    32 │ ############################################################################
    33 │ 
▶   34 │ px4_add_library(arch_dshot
    35 │ 	dshot.c
    36 │ )
    37 │ target_compile_options(arch_dshot PRIVATE ${MAX_CUSTOM_OPT_LEVEL})
```
> **说明**：本板用到的例子：arch_dshot（platforms/nuttx/src/px4/stm/stm32_common/dshot/CMakeLists.txt:34）、mixer_module（src/lib/mixer_module/CMakeLists.txt:46）。
^src-platforms-nuttx-src-px4-stm-stm32-common-dshot-CMakeLists-txt-34

### `src/lib/metadata/CMakeLists.txt`
<a id="src-src-lib-metadata-CMakeLists-txt-35"></a>
**↓ 文档在讲这里：**[`src/lib/metadata/CMakeLists.txt:35`](01-px4-cmake-organization.md#^src-src-lib-metadata-CMakeLists-txt-35)

```c
    32 │ ############################################################################
    33 │ 
    34 │ # actuator metadata generation
▶   35 │ get_property(module_config_files GLOBAL PROPERTY PX4_MODULE_CONFIG_FILES)
    36 │ if(CONFIG_BOARD_IO)
    37 │ 	set(board_with_io_arg --board-with-io)
    38 │ endif()
```
> **说明**：PX4_MODULE_LIBRARIES | px4_add_module.cmake:176 | platforms/nuttx/CMakeLists.txt:45 get_property(module_libraries …) → :392 target_link_libraries(px4 PRIVATE ${module_libraries}) | ★ 决定固件里有哪些模块 | ┃ PX4_MODULE_CONFIG_FILES | px4_add_module.cmake:253、px4_add_library 使用者手写（如 mixer_module/CMakeLists.txt:63） | src/lib/parameters/CMakeLists.txt:40、src/lib/metadata/CMakeLists.txt:35 | ★ 参数 / 元数据生成的输入 y
^src-src-lib-metadata-CMakeLists-txt-35

### `src/lib/mixer_module/CMakeLists.txt`
<a id="src-src-lib-mixer-module-CMakeLists-txt-46"></a>
**↓ 文档在讲这里：**[`src/lib/mixer_module/CMakeLists.txt:46`](01-px4-cmake-organization.md#^src-src-lib-mixer-module-CMakeLists-txt-46)

```c
    43 │ )
    44 │ add_custom_target(output_functions_header DEPENDS ${functions_header})
    45 │ 
▶   46 │ px4_add_library(mixer_module
    47 │ 	functions/FunctionActuatorSet.hpp
    48 │ 	functions/FunctionConstantMax.hpp
    49 │ 	functions/FunctionConstantMin.hpp
```
> **说明**：本板用到的例子：arch_dshot（platforms/nuttx/src/px4/stm/stm32_common/dshot/CMakeLists.txt:34）、mixer_module（src/lib/mixer_module/CMakeLists.txt:46）。
^src-src-lib-mixer-module-CMakeLists-txt-46

### `src/lib/parameters/CMakeLists.txt`
<a id="src-src-lib-parameters-CMakeLists-txt-40"></a>
**↓ 文档在讲这里：**[`src/lib/parameters/CMakeLists.txt:40`](01-px4-cmake-organization.md#^src-src-lib-parameters-CMakeLists-txt-40)

```c
    37 │ 	set(PARAM_DEFAULT_OVERRIDES "{}")
    38 │ endif()
    39 │ 
▶   40 │ get_property(module_config_files GLOBAL PROPERTY PX4_MODULE_CONFIG_FILES)
    41 │ 
    42 │ if(DISABLE_PARAMS_MODULE_SCOPING)
    43 │ 	# search for all module configs as well
```
> **说明**：PX4_MODULE_LIBRARIES | px4_add_module.cmake:176 | platforms/nuttx/CMakeLists.txt:45 get_property(module_libraries …) → :392 target_link_libraries(px4 PRIVATE ${module_libraries}) | ★ 决定固件里有哪些模块 | ┃ PX4_MODULE_CONFIG_FILES | px4_add_module.cmake:253、px4_add_library 使用者手写（如 mixer_module/CMakeLists.txt:63） | src/lib/parameters/CMakeLists.txt:40、src/lib/metadata/CMakeLists.txt:35 | ★ 参数 / 元数据生成的输入 y
^src-src-lib-parameters-CMakeLists-txt-40
