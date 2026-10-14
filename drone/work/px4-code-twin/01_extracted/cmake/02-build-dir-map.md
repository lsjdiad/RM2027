# 01 · `build/rm2027_fmu-h743_default/` 目录地图：每个子目录是谁产出的

> 层：`01_extracted/`（提炼知识）｜视角：**构建运行时**
> 目的：看到 `build/` 里某个文件时，能立刻说出"它是**哪一步**生成的、**下一跳**给谁"。
> 所有大小为**实测**（`stat`），行数/条数为**实测**（`wc`/`grep`）。
> 时点提醒：本目录是 **`4e910b6`** 那次构建的产物（见 `[03_moc/00-build-walkthrough](../../03_moc/00-build-walkthrough.md)` §0.2）。

---

## 0. 一句话总览

```
build/rm2027_fmu-h743_default/
├── CMake 配置期产出   boardconfig / px4_boardconfig.h / CMakeCache.txt / build.ninja / compile_commands.json / config_module_list.txt
├── 生成器产出（代码） generated_params/ · msg/ · uORB/ · mavlink/ · events/ · src/ · boards/ · platforms/
├── NuttX 侧           NuttX/            ← 独立的 make 工程
├── ROMFS 侧           ROMFS/ · etc/ · romfs_files.tar · romfs_extras/ · gencromfs
└── 最终产物           rm2027_fmu-h743_default.{elf,bin,px4,map} · *.sbom.spdx.json · parameters.xml/json · airframes.xml
```

---

## 1. 配置期的 6 个文件（"变量在哪一步变成了值"）

| 文件 | 大小 | 谁生成 | 下文 |
|---|---|---|---|
| `boardconfig` | 20,282 B / **760 行** | [`cmake/kconfig.cmake:74`](../../02_code_twin/build/cmake-kconfig.md#^src-cmake-kconfig-cmake-74)：`python -m defconfig <default.px4board>` | 它是"Kconfig 展开后的全量配置"。**想知道某个 `CONFIG_*` 到底有没有被 `select` 出来，看这里** |
| `boardconfig.old` | 20,184 B | 上一次构建的备份（`boardconfig` 目标用） | 出现它就说明有人跑过 `make boardconfig` |
| `px4_boardconfig.h` | **182 行 / 182 个 `#define`** | [`kconfig.cmake:106`](../../02_code_twin/build/cmake-kconfig.md#^src-cmake-kconfig-cmake-106)：`python -m genconfig --header-path` | ★ 被 `platforms/common/include/px4_platform_common/{px4_config.h:57, defines.h:43, board_common.h:50}` `#include` ⇒ **所有 C/C++ 代码都能 `#ifdef CONFIG_*`** |
| `CMakeCache.txt` | 102,326 B | `cmake` 自己 | [`Makefile:206`](02-build-dir-map.md#^src-Makefile-206) 用它判断"要不要重新配置" |
| `build.ninja` | 6,199,786 B | `cmake -G Ninja` | ★ **"哪些 `.cpp` 被编译"的最终真相**。想回验某个驱动是否编入：`grep -o 'src/…/[^ ]*\.obj' build.ninja \| sort -u` |
| `compile_commands.json` | 2,664,997 B | [`CMakeLists.txt:315`](02-build-dir-map.md#^src-CMakeLists-txt-315) `set(CMAKE_EXPORT_COMPILE_COMMANDS ON)` | ★ **"每个文件用什么宏/包含什么路径编译"的最终真相**。回验 `-DPARAM_PREFIX` / `-DCONFIG_ARCH_BOARD_*` 只能靠它 |
| `config_module_list.txt` | 269 行 | [`cmake/sbom.cmake:44`](../../02_code_twin/build/cmake-kconfig.md#^src-cmake-sbom-cmake-44)（来自全局属性 `PX4_MODULE_PATHS`） | ⚠️ **它不是 `config_module_list`**。它是 SBOM 的输入，每条路径出现两次（[`px4_add_module.cmake:178`](../../02_code_twin/build/cmake-kconfig.md#^src-cmake-px4-add-module-cmake-178) 与 `:183` 各 append 一次） |

**"两个真相源"原则**（本文反复用）：
> 怀疑某驱动/模块编没编进去 → 查 **`build.ninja`**（有没有 `.obj`）；
> 怀疑某个宏/开关值 → 查 **`compile_commands.json`**（命令行）；
> 怀疑某个 `CONFIG_*` 有没有 → 查 **`boardconfig`** + **`px4_boardconfig.h`**。

---

## 2. 代码生成器产出（都是"源码 → 代码"）

| 目录 | 内容 | 谁生成 | 下一跳 |
|---|---|---|---|
| `generated_params/` | `module_params.c`（**482,324 B / 1464 个 `PARAM_DEFINE`**）、`serial_params.c`（**9 个**） | [`src/lib/parameters/CMakeLists.txt:79`](02-build-dir-map.md#^src-src-lib-parameters-CMakeLists-txt-79)：`Tools/serial/generate_config.py` + `Tools/module_config/generate_params.py` | 被 `src/lib/parameters/` 编进 `parameters` 库 ⇒ 链进固件 ⇒ 运行期进 flash 参数区 |
| `msg/` | `libuorb_msgs.a`、`topics_sources/*.cpp`（每个 `.msg` 一个）、`.json` | `add_subdirectory(msg)`（[`CMakeLists.txt:429`](02-build-dir-map.md#^src-CMakeLists-txt-429)） | 链接进固件；`.json` 供 `<topic>_listener` 打印字段名 |
| `uORB/topics/` | 每个话题一个 `.h`（如 `actuator_motors.h`、`sensor_gyro.h`） | `msg/CMakeLists.txt` 生成、并 `include` 到编译单元 | ★ **`src/` 下的每个模块都 include 这些头**；[`px4_add_module.cmake:155`](02-build-dir-map.md#^src-cmake-px4-add-module-cmake-155) 的 `add_dependencies(${MODULE} uorb_headers)` 就是保它先出来 |
| `uORB/ucdr/` | 微 CDR 序列化（uXRCE-DDS 用） | 同上 | 本板开了 `CONFIG_MODULES_UXRCE_DDS_CLIENT` |
| `mavlink/` | `common/` `minimal/` `standard/` `uAvionix/` 等协议头 | ★ 不是 `add_subdirectory` —— 是 [`src/modules/mavlink/CMakeLists.txt:34`](02-build-dir-map.md#^src-src-modules-mavlink-CMakeLists-txt-34)：`MAVLINK_LIBRARY_DIR = ${CMAKE_BINARY_DIR}/mavlink`，用 `pymavlink/tools/mavgen.py` 现场生成 | 供 `src/modules/mavlink` 编译（`.h` 里 `#include <mavlink/…>`） |
| `events/` | `events_generated.h`、`all_events.json(+.xz)`、`px4.json`、`common_with_enums.json` | `src/lib/events/CMakeLists.txt`（读全局属性 `PX4_SRC_FILES`） | 头文件进固件；`.json.xz` 进 ROMFS 的 `/etc/extras/` |
| `src/` | `drivers/` `lib/` `modules/` `systemcmds/` —— **各模块的 `.obj` 与 `.a`** | 逐个 `add_subdirectory(src/${module})`（[`CMakeLists.txt:480`](../../02_code_twin/build/cmake-kconfig.md#^src-CMakeLists-txt-480)） | 供 [`platforms/nuttx/CMakeLists.txt:392`](02-build-dir-map.md#^src-platforms-nuttx-CMakeLists-txt-392) 链成 `px4` |
| `boards/rm2027/fmu-h743/src/` | 板级 6 个源文件的 `.obj` ⇒ 库 **`drivers_board`** | [`kconfig.cmake:454`](../../02_code_twin/board/README.md#^src-cmake-kconfig-cmake-454) 把 `../boards/rm2027/fmu-h743/src` 塞进 `config_module_list` | ★ 见 `[03_moc/00-build-walkthrough](../../03_moc/00-build-walkthrough.md)` §3.6 |
| `platforms/` | `common/` 与 `nuttx/` 的平台层目标 | [`CMakeLists.txt:473`](02-build-dir-map.md#^src-CMakeLists-txt-473) | |

> ★ **`generated_params/module_params.c` 值得单独记一笔**：它不是"某个模块的参数"，而是**全板所有模块的参数**汇总进一个 `.c`（1464 个 `PARAM_DEFINE`）。所以 `PWM_MAIN_FUNC1`（来自 `pwm_out/module.yaml` + `timer_config.cpp`）和 `DSHOT_MIN`（来自 `dshot/module.yaml`）在**同一个文件**里。
> 这个文件是回验"某开关有没有生成参数"的**唯一权威**：`grep -n "^PARAM_DEFINE.*PWM_MAIN" build/…/generated_params/module_params.c`

---

## 3. `NuttX/`：一个被 CMake 驱动的**独立 make 工程**

| 路径 | 内容 | 谁生成 |
|---|---|---|
| `NuttX/nuttx/.config` | **NuttX 的全量配置**（`CONFIG_NSH_INITSCRIPT` / `CONFIG_FS_CROMFS` / `CONFIG_STM32H7_USART1` …） | [`platforms/nuttx/cmake/init.cmake:69`](../../02_code_twin/build/nuttx-build.md#^src-platforms-nuttx-cmake-init-cmake-69)（配置期）+ [`platforms/nuttx/NuttX/CMakeLists.txt:55`](../../02_code_twin/build/nuttx-build.md#^src-platforms-nuttx-NuttX-CMakeLists-txt-55)（构建期） |
| `NuttX/extra_config_options` | 可由环境变量 `PX4_EXTRA_NUTTX_CONFIG` 注入的额外 `CONFIG_*`（本板为空） | [`NuttX/CMakeLists.txt:43`](02-build-dir-map.md#^src-CMakeLists-txt-43) |
| `NuttX/nuttx_olddefconfig.log` | `px4_nuttx_make_olddefconfig.sh` 的输出 | [`init.cmake:74`](02-build-dir-map.md#^src-platforms-nuttx-cmake-init-cmake-74) |
| `NuttX/nuttx_context.log` | `make pass1dep` 的输出 | [`NuttX/CMakeLists.txt:72`](02-build-dir-map.md#^src-CMakeLists-txt-72) |
| `NuttX/nuttx_apps.log` | `make` 编 NuttX apps 的日志 | [`NuttX/CMakeLists.txt:158`](02-build-dir-map.md#^src-CMakeLists-txt-158) |
| `NuttX/apps/libapps.a` | NuttX 的 apps 库（NSH 本体在里面） | 同上 |
| `NuttX/px4.bdat` / `px4.pdat` | ★ **builtin 注册表**（`{ "dshot", …, dshot_main }` 就在这里） | [`NuttX/CMakeLists.txt:137`](02-build-dir-map.md#^src-CMakeLists-txt-137) `configure_file` |
| `../defconfig_inflate_stamp` | "配置期已经把 defconfig 展开过"的戳 | [`init.cmake:80`](02-build-dir-map.md#^src-platforms-nuttx-cmake-init-cmake-80) |

> ⚠️ **注意 NuttX 实际不是在 `build/` 里编的**：`NUTTX_DIR = <src>/platforms/nuttx/NuttX/nuttx`（[`init.cmake:60`](02-build-dir-map.md#^src-platforms-nuttx-cmake-init-cmake-60)），对象文件落在**源码树**里。`build/NuttX/` 只是"控制面 + 拷回来的 `.config` + 日志 + builtin 注册表"。
> **推理**：这正好解释了 [`Makefile:196`](02-build-dir-map.md#^src-Makefile-196) 为什么要写那段"切目标时 `git clean -dXfq` 清 NuttX 子模块"——因为那里的构建状态是**共享的**，换板子不擦会链到上一次的对象（Makefile 注释原文说的就是 `kmm_*` 从 protected build 混进 flat build）。

---

## 4. `ROMFS/` + `etc/`：从"板级 shell 脚本"到"C 数组"

| 路径 | 内容 | 谁生成 | 说明 |
|---|---|---|---|
| `romfs_files.tar` | 131,072 B，**未剥注释**的原始 ROMFS | [`ROMFS/CMakeLists.txt:120`](02-build-dir-map.md#^src-ROMFS-CMakeLists-txt-120) | 想核对"注入前后差别"就解这个 tar |
| `etc/` | **剥过注释**的最终 ROMFS 树：`init.d/`（+ `airframes/` 几百个）、`extras/` | `:140-165` 铺底 + `:194-227` 注入 + `:380-391` extras + **`:401-410` pruner** | ★ 你在镜像里看到的每个脚本都是这里的样子 |
| `etc/init.d/rc.board_sensors` | **123 B / 5 行**（源文件 8,942 B / 119 行） | `Tools/px_romfs_pruner.py` | ★ 注释全被删掉，见 `[03_moc/00-build-walkthrough](../../03_moc/00-build-walkthrough.md)` §5.2 |
| `etc/init.d/rc.serial` | 162 行，`mavlink start` / `dshot telemetry` / `uxrce_dds_client start` … | `Tools/serial/generate_config.py`（`:153-156`） | 由 `CONFIG_BOARD_SERIAL_TEL1` 等生成 |
| `etc/init.d/rc.filepaths` | 62 B | `Tools/filepaths/generate_config.py`（`:157-160`） | 由 `CONFIG_BOARD_PARAM_FILE` / `CONFIG_BOARD_ROOT_PATH` 生成 |
| `etc/extras/` | `parameters.json.xz` / `all_events.json.xz` / `actuators.json.xz` / `component_general.json.xz` | `:375-391`（文件清单来自 [`kconfig.cmake:304`](02-build-dir-map.md#^src-cmake-kconfig-cmake-304)） | ⇒ 这些是**塞进 ROMFS 的元数据**，不是编译进代码的 |
| `ROMFS/nsh_romfsimg.c` | **806,054 B** | [`ROMFS/CMakeLists.txt:422`](../nuttx/romfs.md#^src-ROMFS-CMakeLists-txt-422) `gencromfs etc nsh_romfsimg.c` | ROMFS 被打成一个巨大的 C 字节数组 |
| `ROMFS/libromfs.a` | **125,608 B** | `:431-433` `add_library(romfs STATIC nsh_romfsimg.c)` | 链进 `px4`（[`platforms/nuttx/CMakeLists.txt:394`](../../02_code_twin/build/nuttx-build.md#^src-platforms-nuttx-CMakeLists-txt-394)） |
| `ROMFS/romfs_pruned.stamp` 等 | 0 B 戳文件 | 各 `add_custom_command` | 判断增量构建用 |
| `romfs_extras/` | 空 | `:380-383` | 备用目录（本板没有额外文件） |
| `gencromfs` | 22,056 B 可执行 | `:412-419` `make -f Makefile.host gencromfs` | 只有当 `CONFIG_FS_CROMFS=y` 时才编（本板：`NuttX/nuttx/.config:1340`） |

> ★ **两条 ROMFS 打包路径**（[`ROMFS/CMakeLists.txt:412`](../nuttx/romfs.md#^src-ROMFS-CMakeLists-txt-412)）：
> - `CONFIG_FS_CROMFS=y` ⇒ `gencromfs` ⇒ `nsh_romfsimg.c`（**本板走这条**，`.config:1339-1340`）
> - `CONFIG_FS_ROMFS=y` ⇒ `genromfs` + `xxd` ⇒ 同一个文件名
> 两条最终都产出 `libromfs.a`，**上层不关心走哪条**。

---

## 5. 最终产物

| 文件 | 大小 | 是什么 | 出处 |
|---|---|---|---|
| `rm2027_fmu-h743_default.elf` | 35,285,444 B | 链接产物（带调试信息） | [`platforms/nuttx/CMakeLists.txt:40`](../../02_code_twin/build/nuttx-build.md#^src-platforms-nuttx-CMakeLists-txt-40) |
| `rm2027_fmu-h743_default.bin` | **1,554,376 B** | `objcopy -O binary` 的裸镜像 | `:399-403` |
| `rm2027_fmu-h743_default.map` | 5,450,862 B | 链接 map（看谁把 flash 吃掉了） | [`platforms/nuttx/CMakeLists.txt:376`](02-build-dir-map.md#^src-platforms-nuttx-CMakeLists-txt-376) `-Wl,-Map=${PX4_CONFIG}.map`（flat build 的 `px4` target；`CONFIG_BUILD_FLAT` 分支） |
| **`rm2027_fmu-h743_default.px4`** | **1,504,526 B** | ★ **真正刷的包**：`px_mkfw` 把 `.bin` + `parameters.xml` + `airframes.xml` 打成一个带 JSON 头的容器 | `:478-497` |
| `rm2027_fmu-h743_default.sbom.spdx.json` | 150,048 B | SPDX 2.3 软件物料清单 | [`cmake/sbom.cmake:50`](02-build-dir-map.md#^src-cmake-sbom-cmake-50) |
| `parameters.xml` / `.json` / `.json.xz` | 660,680 / 631,792 / … | 全量参数表（1473 个 `<parameter`） | [`src/lib/parameters/CMakeLists.txt:113`](../../02_code_twin/build/drivers-build.md#^src-src-lib-parameters-CMakeLists-txt-113) |
| `airframes.xml` | 21,495 B | 机型表 | [`CMakeLists.txt:431`](../../02_code_twin/build/cmake-kconfig.md#^src-CMakeLists-txt-431) |
| `actuators.json`(+xz) | 27,064 B | 执行机构函数表（`output_functions.yaml` 的机器可读版） | `src/lib/mixer_module/`（与 `generate_function_header.py` 同源；target `actuators_json`） |
| `component_general.json`(+xz) | 865 B | 组件通用元数据（供 QGC 校验） | [`src/lib/component_information/CMakeLists.txt:83`](02-build-dir-map.md#^src-src-lib-component-information-CMakeLists-txt-83)，target `component_general_json` |

> ✋ **`rm2027_fmu-h743_default.px4` 里没有 bootloader**。bootloader 是另一个目标（`make rm2027_fmu-h743_bootloader`）的产物，落在 `boards/rm2027/fmu-h743/extras/`。详说见 `[03_moc/00-build-walkthrough](../../03_moc/00-build-walkthrough.md)` §6.3。

---

## 6. 回验配方（想自己确认任何一条时用这四行）

```bash
B=源码根（见 `tools/source-root.conf`）/build/rm2027_fmu-h743_default

# ① 某个开关有没有生效？
grep -n "CONFIG_<NAME>" $B/boardconfig $B/px4_boardconfig.h

# ② 某个源文件到底编进去了吗？
grep -o 'src/[a-z_/]*/[A-Za-z0-9_.]*\.obj' $B/build.ninja | sort -u | grep -i <关键词>

# ③ 某个文件是用什么宏/包含路径编的？
python3 -c "import json;[print(e['file'],e['command'][-300:]) for e in json.load(open('$B/compile_commands.json')) if '<关键词>' in e['file']]"

# ④ 某个开关生成了哪些参数？
grep -n "^PARAM_DEFINE.*<前缀>" $B/generated_params/module_params.c
```

---

## 7. 跳转

- **这些文件"为什么会有"** → `[03_moc/00-build-walkthrough](../../03_moc/00-build-walkthrough.md)`（每一节的末尾都指回本目录的某个文件）
- **`px4_add_module` / `add_subdirectory` / 全局属性** → `[01_extracted/cmake/01-px4-cmake-organization](01-px4-cmake-organization.md)`
- **`default.px4board` ↔ Kconfig ↔ CMake ↔ C 宏 四层对应** → `[01_extracted/cmake/03-kconfig-bridge](03-kconfig-bridge.md)`
- **`NuttX/nuttx/.config` 之后控制权去哪** → `[03_moc/01-poweron-walkthrough](../../03_moc/01-poweron-walkthrough.md)`

---

## 标注源码（代码 + 本文档对它的解释）

> **这是「代码孪生」层**：上面是代码原文（带行号），下面是**本文档针对这一段说的话**。
> 行号可点，直接跳到 PX4 源码那一行。
### `CMakeLists.txt`
<a id="src-CMakeLists-txt-43"></a>
**↓ 文档在讲这里：**[`CMakeLists.txt:43`](02-build-dir-map.md#^src-CMakeLists-txt-43)

```c
    40 │ # * Common functions should be included in px_base.cmake.
    41 │ #
    42 │ # * OS/ board specific fucntions should be include in
▶   43 │ #	px_impl_${PX4_PLATFORM}.cmake
    44 │ #
    45 │ # Formatting
    46 │ # ---------------------------------------------------------------------------
```
> **说明**：NuttX/nuttx/.config | NuttX 的全量配置（CONFIG_NSH_INITSCRIPT / CONFIG_FS_CROMFS / CONFIG_STM32H7_USART1 …） | platforms/nuttx/cmake/init.cmake:69（配置期）+ platforms/nuttx/NuttX/CMakeLists.txt:55（构建期） | ┃ NuttX/extra_config_options | 可由环境变量 PX4_EXTRA_NUTTX_CONFIG 注入的额外 CONFIG_*（本板为空） | NuttX/CMakeLists.txt:43 |
^src-CMakeLists-txt-43

<a id="src-CMakeLists-txt-72"></a>
**↓ 文档在讲这里：**[`CMakeLists.txt:72`](02-build-dir-map.md#^src-CMakeLists-txt-72)

```c
    69 │ #
    70 │ # * Avoid use of global variables in functions. Functions in a nested
    71 │ #	scope may use global variables, but this makes it difficult to
▶   72 │ #	reuse functions.
    73 │ #
    74 │ # Included CMake Files
    75 │ # ---------------------------------------------------------------------------
```
> **说明**：NuttX/nuttx_olddefconfig.log | px4_nuttx_make_olddefconfig.sh 的输出 | init.cmake:74 | ┃ NuttX/nuttx_context.log | make pass1dep 的输出 | NuttX/CMakeLists.txt:72 |
^src-CMakeLists-txt-72

<a id="src-CMakeLists-txt-137"></a>
**↓ 文档在讲这里：**[`CMakeLists.txt:137`](02-build-dir-map.md#^src-CMakeLists-txt-137)

```c
   134 │ list(GET VERSION_LIST 0 PX4_VERSION_MAJOR)
   135 │ string(REPLACE "v" "" PX4_VERSION_MAJOR ${PX4_VERSION_MAJOR})
   136 │ # minor version
▶  137 │ list(GET VERSION_LIST 1 PX4_VERSION_MINOR)
   138 │ # patch version
   139 │ list(GET VERSION_LIST 2 PX4_VERSION_PATCH)
   140 │ string(REPLACE "-" ";" PX4_VERSION_PATCH ${PX4_VERSION_PATCH})
```
> **说明**：NuttX/apps/libapps.a | NuttX 的 apps 库（NSH 本体在里面） | 同上 | ┃ NuttX/px4.bdat / px4.pdat | ★ builtin 注册表（{ "dshot", …, dshot_main } 就在这里） | NuttX/CMakeLists.txt:137 configure_file |
^src-CMakeLists-txt-137

<a id="src-CMakeLists-txt-158"></a>
**↓ 文档在讲这里：**[`CMakeLists.txt:158`](02-build-dir-map.md#^src-CMakeLists-txt-158)

```c
   155 │                  )
   156 │ 
   157 │ define_property(GLOBAL PROPERTY PX4_MODULE_PATHS
▶  158 │                  BRIEF_DOCS "PX4 module paths"
   159 │                  FULL_DOCS "List of paths to all PX4 modules"
   160 │                  )
   161 │ 
```
> **说明**：NuttX/nuttx_context.log | make pass1dep 的输出 | NuttX/CMakeLists.txt:72 | ┃ NuttX/nuttx_apps.log | make 编 NuttX apps 的日志 | NuttX/CMakeLists.txt:158 |
^src-CMakeLists-txt-158

<a id="src-CMakeLists-txt-315"></a>
**↓ 文档在讲这里：**[`CMakeLists.txt:315`](02-build-dir-map.md#^src-CMakeLists-txt-315)

```c
   312 │ set(CMAKE_CXX_STANDARD_REQUIRED ON)
   313 │ set(CMAKE_C_STANDARD 11)
   314 │ set(CMAKE_C_STANDARD_REQUIRED ON)
▶  315 │ set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
   316 │ 
   317 │ set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${PX4_BINARY_DIR})
   318 │ set(CMAKE_RUNTIME_OUTPUT_DIRECTORY_DEBUG ${PX4_BINARY_DIR})
```
> **说明**：build.ninja | 6,199,786 B | cmake -G Ninja | ★ "哪些 .cpp 被编译"的最终真相。想回验某个驱动是否编入：grep -o 'src/…/[^ ]*\.obj' build.ninja \| sort -u | ┃ compile_commands.json | 2,664,997 B | CMakeLists.txt:315 set(CMAKE_EXPORT_COMPILE_COMMANDS ON) | ★ "每个文件用什么宏/包含什么路径编译"的最终真相。回验 -DPARAM_PREFIX / -DCONFIG_ARCH_BOARD_* 只能靠它 |
^src-CMakeLists-txt-315

<a id="src-CMakeLists-txt-429"></a>
**↓ 文档在讲这里：**[`CMakeLists.txt:429`](02-build-dir-map.md#^src-CMakeLists-txt-429)

```c
   426 │ #
   427 │ include(px4_metadata)
   428 │ 
▶  429 │ add_subdirectory(msg EXCLUDE_FROM_ALL)
   430 │ 
   431 │ px4_generate_airframes_xml(BOARD ${PX4_BOARD})
   432 │ 
```
> **说明**：generated_params/ | module_params.c（482,324 B / 1464 个 PARAM_DEFINE）、serial_params.c（9 个） | src/lib/parameters/CMakeLists.txt:79：Tools/serial/generate_config.py + Tools/module_config/generate_params.p ┃ msg/ | libuorb_msgs.a、topics_sources/*.cpp（每个 .msg 一个）、.json | add_subdirectory(msg)（CMakeLists.txt:429） | 链接进固件；.json 供 <topic>_listener 打印字段名 |
^src-CMakeLists-txt-429

<a id="src-CMakeLists-txt-431"></a>
**↓ 文档在讲这里：**[`CMakeLists.txt:431`](02-build-dir-map.md#^src-CMakeLists-txt-431)

```c
   428 │ 
   429 │ add_subdirectory(msg EXCLUDE_FROM_ALL)
   430 │ 
▶  431 │ px4_generate_airframes_xml(BOARD ${PX4_BOARD})
   432 │ 
   433 │ #=============================================================================
   434 │ # external projects
```
> **说明**：parameters.xml / .json / .json.xz | 660,680 / 631,792 / … | 全量参数表（1473 个 <parameter） | src/lib/parameters/CMakeLists.txt:113 | ┃ airframes.xml | 21,495 B | 机型表 | CMakeLists.txt:431 |
^src-CMakeLists-txt-431

<a id="src-CMakeLists-txt-473"></a>
**↓ 文档在讲这里：**[`CMakeLists.txt:473`](02-build-dir-map.md#^src-CMakeLists-txt-473)

```c
   470 │ include(px4_add_library)
   471 │ add_subdirectory(src/lib EXCLUDE_FROM_ALL)
   472 │ 
▶  473 │ add_subdirectory(platforms/${PX4_PLATFORM}/src/px4)
   474 │ add_subdirectory(platforms EXCLUDE_FROM_ALL)
   475 │ 
   476 │ if(EXISTS "${PX4_BOARD_DIR}/CMakeLists.txt")
```
> **说明**：boards/rm2027/fmu-h743/src/ | 板级 6 个源文件的 .obj ⇒ 库 drivers_board | kconfig.cmake:454 把 ../boards/rm2027/fmu-h743/src 塞进 config_module_list | ★ 见 03_moc/00-build-walkthrough §3.6 | ┃ platforms/ | common/ 与 nuttx/ 的平台层目标 | CMakeLists.txt:473 | |
^src-CMakeLists-txt-473

<a id="src-CMakeLists-txt-480"></a>
**↓ 文档在讲这里：**[`CMakeLists.txt:480`](02-build-dir-map.md#^src-CMakeLists-txt-480)

```c
   477 │ 	add_subdirectory(${PX4_BOARD_DIR})
   478 │ endif()
   479 │ 
▶  480 │ foreach(module ${config_module_list})
   481 │ 	add_subdirectory(src/${module})
   482 │ endforeach()
   483 │ 
```
> **说明**：events/ | events_generated.h、all_events.json(+.xz)、px4.json、common_with_enums.json | src/lib/events/CMakeLists.txt（读全局属性 PX4_SRC_FILES） | 头文件进固件；.json.xz 进 ROMFS 的 /etc/extras/ | ┃ src/ | drivers/ lib/ modules/ systemcmds/ —— 各模块的 .obj 与 .a | 逐个 add_subdirectory(src/${module})（CMakeLists.txt:480） | 供 platforms/nuttx/CMakeLists.txt:392 链成 px4 |
^src-CMakeLists-txt-480

### `Makefile`
<a id="src-Makefile-196"></a>
**↓ 文档在讲这里：**[`Makefile:196`](02-build-dir-map.md#^src-Makefile-196)

```c
   193 │ 	@stamp="$(SRC_DIR)/build/.last_target"; \
   194 │ 	prev=$$(cat "$$stamp" 2>/dev/null || echo ""); \
   195 │ 	if [ "$$prev" != "$(1)" ]; then \
▶  196 │ 		[ -n "$$prev" ] && echo "switching NuttX target $$prev -> $(1): wiping submodule state"; \
   197 │ 		git -C "$(SRC_DIR)/platforms/nuttx/NuttX/nuttx" clean -dXfq 2>/dev/null || true; \
   198 │ 		git -C "$(SRC_DIR)/platforms/nuttx/NuttX/apps"  clean -dXfq 2>/dev/null || true; \
   199 │ 		echo "$(1)" > "$$stamp"; \
```
> **说明**：⚠️ 注意 NuttX 实际不是在 build/ 里编的：NUTTX_DIR = <src>/platforms/nuttx/NuttX/nuttx（init.cmake:60），对象文件落在源码树里。build/NuttX/ 只是"控制面 + 拷回来的 .config + 日志 + builtin 注册表"。 ┃ 推理：这正好解释了 Makefile:196 为什么要写那段"切目标时 git clean -dXfq 清 NuttX 子模块"——因为那里的构建状态是共享的，换板子不擦会链到上一次的对象（Makefile 注释原文说的就是 kmm_* 从 protected build 混进 flat build）。
^src-Makefile-196

<a id="src-Makefile-206"></a>
**↓ 文档在讲这里：**[`Makefile:206`](02-build-dir-map.md#^src-Makefile-206)

```c
   203 │ 	@# make sure to start from scratch if ninja build file is missing
   204 │ 	@if [ $(PX4_CMAKE_GENERATOR) = "Ninja" ] && [ ! -f $(BUILD_DIR)/build.ninja ]; then rm -rf $(BUILD_DIR); fi
   205 │ 	@# only excplicitly configure the first build, if cache file already exists the makefile will rerun cmake automatically if necessary
▶  206 │ 	@if [ ! -e $(BUILD_DIR)/CMakeCache.txt ] || [ $(CMAKE_CACHE_CHECK) ]; then \
   207 │ 		mkdir -p $(BUILD_DIR) \
   208 │ 		&& cd $(BUILD_DIR) \
   209 │ 		&& cmake "$(SRC_DIR)" -G"$(PX4_CMAKE_GENERATOR)" $(CMAKE_ARGS) \
```
> **说明**：px4_boardconfig.h | 182 行 / 182 个 #define | kconfig.cmake:106：python -m genconfig --header-path | ★ 被 platforms/common/include/px4_platform_common/{px4_config.h:57, defines.h:43, board_common.h:50} #i ┃ CMakeCache.txt | 102,326 B | cmake 自己 | Makefile:206 用它判断"要不要重新配置" |
^src-Makefile-206

### `ROMFS/CMakeLists.txt`
<a id="src-ROMFS-CMakeLists-txt-120"></a>
**↓ 文档在讲这里：**[`ROMFS/CMakeLists.txt:120`](02-build-dir-map.md#^src-ROMFS-CMakeLists-txt-120)

```c
   117 │ # directory (which preserves the directory structure)
   118 │ file(MAKE_DIRECTORY ${romfs_gen_root_dir})
   119 │ set(romfs_tar_file ${PX4_BINARY_DIR}/romfs_files.tar)
▶  120 │ add_custom_command(
   121 │ 	OUTPUT ${romfs_tar_file}
   122 │ 	COMMAND ${CMAKE_COMMAND} -E tar cf ${romfs_tar_file} ${romfs_copy_files_relative}
   123 │ 	WORKING_DIRECTORY ${romfs_src_dir}
```
> **说明**：romfs_files.tar | 131,072 B，未剥注释的原始 ROMFS | ROMFS/CMakeLists.txt:120 | 想核对"注入前后差别"就解这个 tar |
^src-ROMFS-CMakeLists-txt-120

<a id="src-ROMFS-CMakeLists-txt-412"></a>
**↓ 文档在讲这里：**[`ROMFS/CMakeLists.txt:412`](02-build-dir-map.md#^src-ROMFS-CMakeLists-txt-412)

```c
   409 │ 	COMMENT "ROMFS: pruning"
   410 │ 	)
   411 │ 
▶  412 │ if("${CONFIG_FS_CROMFS}" STREQUAL "y")
   413 │ 	add_custom_command(
   414 │ 		OUTPUT ${CMAKE_BINARY_DIR}/gencromfs
   415 │ 		COMMAND make --no-print-directory --silent -f Makefile.host gencromfs
```
> **说明**：★ 两条 ROMFS 打包路径（ROMFS/CMakeLists.txt:412）：
^src-ROMFS-CMakeLists-txt-412

<a id="src-ROMFS-CMakeLists-txt-422"></a>
**↓ 文档在讲这里：**[`ROMFS/CMakeLists.txt:422`](02-build-dir-map.md#^src-ROMFS-CMakeLists-txt-422)

```c
   419 │ 	)
   420 │ 
   421 │ 	# create nsh_romfsimg.c
▶  422 │ 	add_custom_command(OUTPUT nsh_romfsimg.c
   423 │ 		COMMAND ${CMAKE_COMMAND} -E remove -f nsh_romfsimg.c
   424 │ 		COMMAND ${CMAKE_BINARY_DIR}/gencromfs ${romfs_gen_root_dir} nsh_romfsimg.c
   425 │ 		DEPENDS
```
> **说明**：etc/extras/ | parameters.json.xz / all_events.json.xz / actuators.json.xz / component_general.json.xz | :375-391（文件清单来自 kconfig.cmake:304） | ⇒ 这些是塞进 ROMFS 的元数据，不是编译进代码的 | ┃ ROMFS/nsh_romfsimg.c | 806,054 B | ROMFS/CMakeLists.txt:422 gencromfs etc nsh_romfsimg.c | ROMFS 被打成一个巨大的 C 字节数组 |
^src-ROMFS-CMakeLists-txt-422

### `cmake/kconfig.cmake`
<a id="src-cmake-kconfig-cmake-74"></a>
**↓ 文档在讲这里：**[`cmake/kconfig.cmake:74`](02-build-dir-map.md#^src-cmake-kconfig-cmake-74)

```c
    71 │ 	# Depend on BOARD_DEFCONFIG so that we reconfigure on config change
    72 │ 	set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS ${BOARD_DEFCONFIG})
    73 │ 
▶   74 │ 	if(${LABEL} MATCHES "default" OR ${LABEL} MATCHES "performance-test" OR ${LABEL} MATCHES "bootloader" OR ${LABEL} MATCHES "canbootloader")
    75 │ 		# Generate boardconfig from saved defconfig
    76 │ 		execute_process(
    77 │ 			COMMAND ${CMAKE_COMMAND} -E env ${COMMON_KCONFIG_ENV_SETTINGS}
```
> **说明**：boardconfig | 20,282 B / 760 行 | cmake/kconfig.cmake:74：python -m defconfig <default.px4board> | 它是"Kconfig 展开后的全量配置"。想知道某个 CONFIG_* 到底有没有被 select 出来，看这里 |
^src-cmake-kconfig-cmake-74

<a id="src-cmake-kconfig-cmake-106"></a>
**↓ 文档在讲这里：**[`cmake/kconfig.cmake:106`](02-build-dir-map.md#^src-cmake-kconfig-cmake-106)

```c
   103 │ 	endif()
   104 │ 
   105 │     # Generate header file for C/C++ preprocessor
▶  106 │     execute_process(
   107 │ 	COMMAND ${CMAKE_COMMAND} -E env ${COMMON_KCONFIG_ENV_SETTINGS}
   108 │ 		${GENCONFIG_PATH} --header-path ${PX4_BINARY_DIR}/px4_boardconfig.h
   109 │ 	WORKING_DIRECTORY ${PX4_SOURCE_DIR}
```
> **说明**：boardconfig.old | 20,184 B | 上一次构建的备份（boardconfig 目标用） | 出现它就说明有人跑过 make boardconfig | ┃ px4_boardconfig.h | 182 行 / 182 个 #define | kconfig.cmake:106：python -m genconfig --header-path | ★ 被 platforms/common/include/px4_platform_common/{px4_config.h:57, defines.h:43, board_common.h:50} #i
^src-cmake-kconfig-cmake-106

<a id="src-cmake-kconfig-cmake-304"></a>
**↓ 文档在讲这里：**[`cmake/kconfig.cmake:304`](02-build-dir-map.md#^src-cmake-kconfig-cmake-304)

```c
   301 │ 		set(CMAKE_TOOLCHAIN_FILE Toolchain-${TOOLCHAIN} CACHE INTERNAL "toolchain file" FORCE)
   302 │ 	endif()
   303 │ 
▶  304 │ 	set(romfs_extra_files)
   305 │ 	set(config_romfs_extra_dependencies)
   306 │ 	# additional embedded metadata
   307 │ 	if(NOT CONSTRAINED_FLASH AND NOT EXTERNAL_METADATA AND NOT ${PX4_BOARD_LABEL} STREQUAL "test")
```
> **说明**：etc/init.d/rc.filepaths | 62 B | Tools/filepaths/generate_config.py（:157-160） | 由 CONFIG_BOARD_PARAM_FILE / CONFIG_BOARD_ROOT_PATH 生成 | ┃ etc/extras/ | parameters.json.xz / all_events.json.xz / actuators.json.xz / component_general.json.xz | :375-391（文件清单来自 kconfig.cmake:304） | ⇒ 这些是塞进 ROMFS 的元数据，不是编译进代码的 |
^src-cmake-kconfig-cmake-304

<a id="src-cmake-kconfig-cmake-454"></a>
**↓ 文档在讲这里：**[`cmake/kconfig.cmake:454`](02-build-dir-map.md#^src-cmake-kconfig-cmake-454)

```c
   451 │ 	px4_os_prebuild_targets(OUT prebuild_targets BOARD ${PX4_BOARD})
   452 │ 
   453 │ 	# add board config directory src to build modules
▶  454 │ 	file(RELATIVE_PATH board_support_src_rel ${PX4_SOURCE_DIR}/src ${PX4_BOARD_DIR})
   455 │ 	list(APPEND config_module_list ${board_support_src_rel}/src)
   456 │ 
   457 │ 	set(config_module_list ${config_module_list})
```
> **说明**：src/ | drivers/ lib/ modules/ systemcmds/ —— 各模块的 .obj 与 .a | 逐个 add_subdirectory(src/${module})（CMakeLists.txt:480） | 供 platforms/nuttx/CMakeLists.txt:392 链成 px4 | ┃ boards/rm2027/fmu-h743/src/ | 板级 6 个源文件的 .obj ⇒ 库 drivers_board | kconfig.cmake:454 把 ../boards/rm2027/fmu-h743/src 塞进 config_module_list | ★ 见 03_moc/00-build-walkthrough §3.6 |
^src-cmake-kconfig-cmake-454

### `cmake/px4_add_module.cmake`
<a id="src-cmake-px4-add-module-cmake-155"></a>
**↓ 文档在讲这里：**[`cmake/px4_add_module.cmake:155`](02-build-dir-map.md#^src-cmake-px4-add-module-cmake-155)

```c
   152 │ 	endif()
   153 │ 
   154 │ 	# all modules can potentially use parameters and uORB
▶  155 │ 	add_dependencies(${MODULE} uorb_headers)
   156 │ 
   157 │ 	# Check if the modules source dir exists in config_kernel_list
   158 │ 	# in this case, treat is as a kernel side component for
```
> **说明**：msg/ | libuorb_msgs.a、topics_sources/*.cpp（每个 .msg 一个）、.json | add_subdirectory(msg)（CMakeLists.txt:429） | 链接进固件；.json 供 <topic>_listener 打印字段名 | ┃ uORB/topics/ | 每个话题一个 .h（如 actuator_motors.h、sensor_gyro.h） | msg/CMakeLists.txt 生成、并 include 到编译单元 | ★ src/ 下的每个模块都 include 这些头；px4_add_module.cmake:155 的 add_dependencies(${MODULE} uorb_headers) 就是保
^src-cmake-px4-add-module-cmake-155

<a id="src-cmake-px4-add-module-cmake-178"></a>
**↓ 文档在讲这里：**[`cmake/px4_add_module.cmake:178`](02-build-dir-map.md#^src-cmake-px4-add-module-cmake-178)

```c
   175 │ 			target_link_libraries(${MODULE} PRIVATE events_interface parameters_interface px4_layer uORB)
   176 │ 			set_property(GLOBAL APPEND PROPERTY PX4_MODULE_LIBRARIES ${MODULE})
   177 │ 		endif()
▶  178 │ 		set_property(GLOBAL APPEND PROPERTY PX4_MODULE_PATHS ${CMAKE_CURRENT_SOURCE_DIR})
   179 │ 		px4_list_make_absolute(ABS_SRCS ${CMAKE_CURRENT_SOURCE_DIR} ${SRCS})
   180 │ 		set_property(GLOBAL APPEND PROPERTY PX4_SRC_FILES ${ABS_SRCS})
   181 │ 	endif()
```
> **说明**：compile_commands.json | 2,664,997 B | CMakeLists.txt:315 set(CMAKE_EXPORT_COMPILE_COMMANDS ON) | ★ "每个文件用什么宏/包含什么路径编译"的最终真相。回验 -DPARAM_PREFIX / -DCONFIG_ARCH_BOARD_* 只能靠它 | ┃ config_module_list.txt | 269 行 | cmake/sbom.cmake:44（来自全局属性 PX4_MODULE_PATHS） | ⚠️ 它不是 config_module_list。它是 SBOM 的输入，每条路径出现两次（px4_add_module.cmake:178 与 :183 各 append 一次） |
^src-cmake-px4-add-module-cmake-178

### `cmake/sbom.cmake`
<a id="src-cmake-sbom-cmake-44"></a>
**↓ 文档在讲这里：**[`cmake/sbom.cmake:44`](02-build-dir-map.md#^src-cmake-sbom-cmake-44)

```c
    41 │ 
    42 │ if(GENERATE_SBOM)
    43 │ 
▶   44 │ 	# Write board-specific module list for the SBOM generator
    45 │ 	set(sbom_module_list_file "${PX4_BINARY_DIR}/config_module_list.txt")
    46 │ 	get_property(module_list GLOBAL PROPERTY PX4_MODULE_PATHS)
    47 │ 	string(REPLACE ";" "\n" module_list_content "${module_list}")
```
> **说明**：compile_commands.json | 2,664,997 B | CMakeLists.txt:315 set(CMAKE_EXPORT_COMPILE_COMMANDS ON) | ★ "每个文件用什么宏/包含什么路径编译"的最终真相。回验 -DPARAM_PREFIX / -DCONFIG_ARCH_BOARD_* 只能靠它 | ┃ config_module_list.txt | 269 行 | cmake/sbom.cmake:44（来自全局属性 PX4_MODULE_PATHS） | ⚠️ 它不是 config_module_list。它是 SBOM 的输入，每条路径出现两次（px4_add_module.cmake:178 与 :183 各 append 一次） |
^src-cmake-sbom-cmake-44

<a id="src-cmake-sbom-cmake-50"></a>
**↓ 文档在讲这里：**[`cmake/sbom.cmake:50`](02-build-dir-map.md#^src-cmake-sbom-cmake-50)

```c
    47 │ 	string(REPLACE ";" "\n" module_list_content "${module_list}")
    48 │ 	file(GENERATE OUTPUT ${sbom_module_list_file} CONTENT "${module_list_content}\n")
    49 │ 
▶   50 │ 	set(sbom_output "${PX4_BINARY_DIR}/${PX4_CONFIG}.sbom.spdx.json")
    51 │ 
    52 │ 	add_custom_command(
    53 │ 		OUTPUT ${sbom_output}
```
> **说明**：rm2027_fmu-h743_default.px4 | 1,504,526 B | ★ 真正刷的包：px_mkfw 把 .bin + parameters.xml + airframes.xml 打成一个带 JSON 头的容器 | :478-497 | ┃ rm2027_fmu-h743_default.sbom.spdx.json | 150,048 B | SPDX 2.3 软件物料清单 | cmake/sbom.cmake:50 |
^src-cmake-sbom-cmake-50

### `platforms/nuttx/CMakeLists.txt`
<a id="src-platforms-nuttx-CMakeLists-txt-40"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/CMakeLists.txt:40`](02-build-dir-map.md#^src-platforms-nuttx-CMakeLists-txt-40)

```c
    37 │ 
    38 │ include(cygwin_cygpath)
    39 │ 
▶   40 │ add_executable(px4 ${PX4_SOURCE_DIR}/platforms/common/empty.c)
    41 │ set(FW_NAME ${PX4_BOARD_VENDOR}_${PX4_BOARD_MODEL}_${PX4_BOARD_LABEL}.elf)
    42 │ set_target_properties(px4 PROPERTIES OUTPUT_NAME ${FW_NAME})
    43 │ add_dependencies(px4 git_nuttx)
```
> **说明**：rm2027_fmu-h743_default.elf | 35,285,444 B | 链接产物（带调试信息） | platforms/nuttx/CMakeLists.txt:40 |
^src-platforms-nuttx-CMakeLists-txt-40

<a id="src-platforms-nuttx-CMakeLists-txt-376"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/CMakeLists.txt:376`](02-build-dir-map.md#^src-platforms-nuttx-CMakeLists-txt-376)

```c
   373 │ 		-fno-rtti
   374 │ 		-Wl,--script=${NUTTX_CONFIG_DIR_CYG}/scripts/${SCRIPT_PREFIX}script.ld
   375 │ 		-L${NUTTX_CONFIG_DIR_CYG}/scripts
▶  376 │ 		-Wl,-Map=${PX4_CONFIG}.map
   377 │ 		-Wl,--warn-common
   378 │ 		-Wl,--gc-sections
   379 │ 
```
> **说明**：rm2027_fmu-h743_default.bin | 1,554,376 B | objcopy -O binary 的裸镜像 | :399-403 | ┃ rm2027_fmu-h743_default.map | 5,450,862 B | 链接 map（看谁把 flash 吃掉了） | platforms/nuttx/CMakeLists.txt:376 -Wl,-Map=${PX4_CONFIG}.map（flat build 的 px4 target；CONFIG_BUILD_FLAT 分支） |
^src-platforms-nuttx-CMakeLists-txt-376

<a id="src-platforms-nuttx-CMakeLists-txt-392"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/CMakeLists.txt:392`](02-build-dir-map.md#^src-platforms-nuttx-CMakeLists-txt-392)

```c
   389 │ 		target_link_libraries(px4 PRIVATE -Wl,--print-memory-usage)
   390 │ 	endif()
   391 │ 
▶  392 │ 	target_link_libraries(px4 PRIVATE ${module_libraries})
   393 │ 
   394 │ 	if(config_romfs_root)
   395 │ 		add_subdirectory(${PX4_SOURCE_DIR}/ROMFS ${PX4_BINARY_DIR}/ROMFS)
```
> **说明**：events/ | events_generated.h、all_events.json(+.xz)、px4.json、common_with_enums.json | src/lib/events/CMakeLists.txt（读全局属性 PX4_SRC_FILES） | 头文件进固件；.json.xz 进 ROMFS 的 /etc/extras/ | ┃ src/ | drivers/ lib/ modules/ systemcmds/ —— 各模块的 .obj 与 .a | 逐个 add_subdirectory(src/${module})（CMakeLists.txt:480） | 供 platforms/nuttx/CMakeLists.txt:392 链成 px4 |
^src-platforms-nuttx-CMakeLists-txt-392

<a id="src-platforms-nuttx-CMakeLists-txt-394"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/CMakeLists.txt:394`](02-build-dir-map.md#^src-platforms-nuttx-CMakeLists-txt-394)

```c
   391 │ 
   392 │ 	target_link_libraries(px4 PRIVATE ${module_libraries})
   393 │ 
▶  394 │ 	if(config_romfs_root)
   395 │ 		add_subdirectory(${PX4_SOURCE_DIR}/ROMFS ${PX4_BINARY_DIR}/ROMFS)
   396 │ 		target_link_libraries(px4 PRIVATE romfs)
   397 │ 	endif()
```
> **说明**：ROMFS/nsh_romfsimg.c | 806,054 B | ROMFS/CMakeLists.txt:422 gencromfs etc nsh_romfsimg.c | ROMFS 被打成一个巨大的 C 字节数组 | ┃ ROMFS/libromfs.a | 125,608 B | :431-433 add_library(romfs STATIC nsh_romfsimg.c) | 链进 px4（platforms/nuttx/CMakeLists.txt:394） |
^src-platforms-nuttx-CMakeLists-txt-394

### `platforms/nuttx/NuttX/CMakeLists.txt`
<a id="src-platforms-nuttx-NuttX-CMakeLists-txt-55"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/NuttX/CMakeLists.txt:55`](02-build-dir-map.md#^src-platforms-nuttx-NuttX-CMakeLists-txt-55)

```c
    52 │ 
    53 │ 
    54 │ # inflate .config
▶   55 │ add_custom_command(
    56 │ 	OUTPUT ${NUTTX_DIR}/.config
    57 │ 	COMMAND ${CMAKE_COMMAND} -E copy_if_different ${CMAKE_CURRENT_BINARY_DIR}/nuttx/Make.defs ${NUTTX_DIR}/Make.defs
    58 │ 	COMMAND cat ${NUTTX_DEFCONFIG} ${EXTRA_NUTTX_CONFIG_FILE} > ${NUTTX_DIR}/.config
```
> **说明**：NuttX/nuttx/.config | NuttX 的全量配置（CONFIG_NSH_INITSCRIPT / CONFIG_FS_CROMFS / CONFIG_STM32H7_USART1 …） | platforms/nuttx/cmake/init.cmake:69（配置期）+ platforms/nuttx/NuttX/CMakeLists.txt:55（构建期） |
^src-platforms-nuttx-NuttX-CMakeLists-txt-55

### `platforms/nuttx/cmake/init.cmake`
<a id="src-platforms-nuttx-cmake-init-cmake-60"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/cmake/init.cmake:60`](02-build-dir-map.md#^src-platforms-nuttx-cmake-init-cmake-60)

```c
    57 │ set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS ${NUTTX_DEFCONFIG})
    58 │ 
    59 │ set(NUTTX_SRC_DIR  ${PX4_SOURCE_DIR}/platforms/nuttx/NuttX)
▶   60 │ set(NUTTX_DIR      ${PX4_SOURCE_DIR}/platforms/nuttx/NuttX/nuttx CACHE FILEPATH "NuttX directory" FORCE)
    61 │ set(NUTTX_APPS_DIR ${PX4_SOURCE_DIR}/platforms/nuttx/NuttX/apps CACHE FILEPATH "NuttX apps directory" FORCE)
    62 │ 
    63 │ px4_add_git_submodule(TARGET git_nuttx PATH "${NUTTX_SRC_DIR}/nuttx")
```
> **说明**：⚠️ 注意 NuttX 实际不是在 build/ 里编的：NUTTX_DIR = <src>/platforms/nuttx/NuttX/nuttx（init.cmake:60），对象文件落在源码树里。build/NuttX/ 只是"控制面 + 拷回来的 .config + 日志 + builtin 注册表"。
^src-platforms-nuttx-cmake-init-cmake-60

<a id="src-platforms-nuttx-cmake-init-cmake-69"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/cmake/init.cmake:69`](02-build-dir-map.md#^src-platforms-nuttx-cmake-init-cmake-69)

```c
    66 │ # make olddefconfig (inflate defconfig to full .config)
    67 │ execute_process(COMMAND ${CMAKE_COMMAND} -E make_directory ${NUTTX_CONFIG_DIR}/src) # needed for NuttX build
    68 │ execute_process(COMMAND ${CMAKE_COMMAND} -E copy_if_different ${NUTTX_SRC_DIR}/Make.defs.in ${NUTTX_DIR}/Make.defs) # Create a temporary Toplevel Make.defs for the oldconfig step
▶   69 │ execute_process(COMMAND ${CMAKE_COMMAND} -E copy_if_different ${NUTTX_DEFCONFIG} ${NUTTX_DIR}/.config)
    70 │ execute_process(COMMAND ${CMAKE_COMMAND} -E copy_if_different ${NUTTX_DEFCONFIG} ${NUTTX_DIR}/defconfig)
    71 │ 
    72 │ set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS ${NUTTX_DIR}/defconfig)
```
> **说明**：NuttX/nuttx/.config | NuttX 的全量配置（CONFIG_NSH_INITSCRIPT / CONFIG_FS_CROMFS / CONFIG_STM32H7_USART1 …） | platforms/nuttx/cmake/init.cmake:69（配置期）+ platforms/nuttx/NuttX/CMakeLists.txt:55（构建期） |
^src-platforms-nuttx-cmake-init-cmake-69

<a id="src-platforms-nuttx-cmake-init-cmake-74"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/cmake/init.cmake:74`](02-build-dir-map.md#^src-platforms-nuttx-cmake-init-cmake-74)

```c
    71 │ 
    72 │ set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS ${NUTTX_DIR}/defconfig)
    73 │ 
▶   74 │ execute_process(
    75 │ 	COMMAND ${NUTTX_SRC_DIR}/tools/px4_nuttx_make_olddefconfig.sh
    76 │ 	WORKING_DIRECTORY ${NUTTX_DIR}
    77 │ 	OUTPUT_FILE ${CMAKE_CURRENT_BINARY_DIR}/nuttx_olddefconfig.log
```
> **说明**：NuttX/extra_config_options | 可由环境变量 PX4_EXTRA_NUTTX_CONFIG 注入的额外 CONFIG_*（本板为空） | NuttX/CMakeLists.txt:43 | ┃ NuttX/nuttx_olddefconfig.log | px4_nuttx_make_olddefconfig.sh 的输出 | init.cmake:74 |
^src-platforms-nuttx-cmake-init-cmake-74

<a id="src-platforms-nuttx-cmake-init-cmake-80"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/cmake/init.cmake:80`](02-build-dir-map.md#^src-platforms-nuttx-cmake-init-cmake-80)

```c
    77 │ 	OUTPUT_FILE ${CMAKE_CURRENT_BINARY_DIR}/nuttx_olddefconfig.log
    78 │ 	RESULT_VARIABLE ret
    79 │ )
▶   80 │ execute_process(
    81 │ 	COMMAND ${CMAKE_COMMAND} -E touch ${CMAKE_CURRENT_BINARY_DIR}/defconfig_inflate_stamp
    82 │ 	WORKING_DIRECTORY ${NUTTX_DIR}
    83 │ )
```
> **说明**：NuttX/px4.bdat / px4.pdat | ★ builtin 注册表（{ "dshot", …, dshot_main } 就在这里） | NuttX/CMakeLists.txt:137 configure_file | ┃ ../defconfig_inflate_stamp | "配置期已经把 defconfig 展开过"的戳 | init.cmake:80 |
^src-platforms-nuttx-cmake-init-cmake-80

### `src/lib/component_information/CMakeLists.txt`
<a id="src-src-lib-component-information-CMakeLists-txt-83"></a>
**↓ 文档在讲这里：**[`src/lib/component_information/CMakeLists.txt:83`](02-build-dir-map.md#^src-src-lib-component-information-CMakeLists-txt-83)

```c
    80 │ list(APPEND comp_metadata_types "--type" "5,${PX4_BINARY_DIR}/actuators.json.xz,${comp_metadata_actuators_uri},${comp_metadata_actuators_uri_fallback},")
    81 │ 
    82 │ 
▶   83 │ set(component_general_json ${PX4_BINARY_DIR}/component_general.json)
    84 │ set(component_information_header ${CMAKE_CURRENT_BINARY_DIR}/checksums.h)
    85 │ add_custom_command(OUTPUT ${component_general_json} ${component_general_json}.xz ${component_information_header}
    86 │ 	COMMAND ${PYTHON_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/generate_component_general.py
```
> **说明**：actuators.json(+xz) | 27,064 B | 执行机构函数表（output_functions.yaml 的机器可读版） | src/lib/mixer_module/（与 generate_function_header.py 同源；target actuators_json） | ┃ component_general.json(+xz) | 865 B | 组件通用元数据（供 QGC 校验） | src/lib/component_information/CMakeLists.txt:83，target component_general_json |
^src-src-lib-component-information-CMakeLists-txt-83

### `src/lib/parameters/CMakeLists.txt`
<a id="src-src-lib-parameters-CMakeLists-txt-79"></a>
**↓ 文档在讲这里：**[`src/lib/parameters/CMakeLists.txt:79`](02-build-dir-map.md#^src-src-lib-parameters-CMakeLists-txt-79)

```c
    76 │ 	set(board_with_io_arg --board-with-io)
    77 │ endif()
    78 │ 
▶   79 │ add_custom_command(OUTPUT ${generated_serial_params_file} ${generated_module_params_file}
    80 │ 	COMMAND ${CMAKE_COMMAND} -E make_directory ${generated_params_dir}
    81 │ 	COMMAND ${PYTHON_EXECUTABLE} ${PX4_SOURCE_DIR}/Tools/serial/generate_config.py
    82 │ 		--params-file ${generated_serial_params_file}
```
> **说明**：generated_params/ | module_params.c（482,324 B / 1464 个 PARAM_DEFINE）、serial_params.c（9 个） | src/lib/parameters/CMakeLists.txt:79：Tools/serial/generate_config.py + Tools/module_config/generate_params.p
^src-src-lib-parameters-CMakeLists-txt-79

<a id="src-src-lib-parameters-CMakeLists-txt-113"></a>
**↓ 文档在讲这里：**[`src/lib/parameters/CMakeLists.txt:113`](02-build-dir-map.md#^src-src-lib-parameters-CMakeLists-txt-113)

```c
   110 │ 
   111 │ set(parameters_xml ${PX4_BINARY_DIR}/parameters.xml)
   112 │ set(parameters_json ${PX4_BINARY_DIR}/parameters.json)
▶  113 │ add_custom_command(OUTPUT ${parameters_xml} ${parameters_json} ${parameters_json}.xz
   114 │ 	COMMAND ${PYTHON_EXECUTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/px_process_params.py
   115 │ 		--src-path ${generated_params_dir}
   116 │ 		--xml ${parameters_xml}
```
> **说明**：rm2027_fmu-h743_default.sbom.spdx.json | 150,048 B | SPDX 2.3 软件物料清单 | cmake/sbom.cmake:50 | ┃ parameters.xml / .json / .json.xz | 660,680 / 631,792 / … | 全量参数表（1473 个 <parameter） | src/lib/parameters/CMakeLists.txt:113 |
^src-src-lib-parameters-CMakeLists-txt-113

### `src/modules/mavlink/CMakeLists.txt`
<a id="src-src-modules-mavlink-CMakeLists-txt-34"></a>
**↓ 文档在讲这里：**[`src/modules/mavlink/CMakeLists.txt:34`](02-build-dir-map.md#^src-src-modules-mavlink-CMakeLists-txt-34)

```c
    31 │ #
    32 │ ############################################################################
    33 │ 
▶   34 │ set(MAVLINK_GIT_DIR "${CMAKE_CURRENT_LIST_DIR}/mavlink")
    35 │ set(MAVLINK_LIBRARY_DIR "${CMAKE_BINARY_DIR}/mavlink")
    36 │ file(RELATIVE_PATH MAVLINK_GIT_DIR_RELATIVE ${CMAKE_SOURCE_DIR} ${MAVLINK_GIT_DIR})
    37 │ 
```
> **说明**：uORB/ucdr/ | 微 CDR 序列化（uXRCE-DDS 用） | 同上 | 本板开了 CONFIG_MODULES_UXRCE_DDS_CLIENT | ┃ mavlink/ | common/ minimal/ standard/ uAvionix/ 等协议头 | ★ 不是 add_subdirectory —— 是 src/modules/mavlink/CMakeLists.txt:34：MAVLINK_LIBRARY_DIR = ${CMAKE_BINARY_DIR}/mavlink，用 pymavlink/tools/mavgen.py 现场
^src-src-modules-mavlink-CMakeLists-txt-34
