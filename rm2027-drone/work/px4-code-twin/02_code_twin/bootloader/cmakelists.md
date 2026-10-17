# `bootloader/CMakeLists.txt` 一族 —— ①②③ 三层在构建期怎么被拼成一个镜像

> **源码**：
> `platforms/nuttx/src/bootloader/CMakeLists.txt`（37 行）、
> `common/CMakeLists.txt`（58 行）、`common/lib/CMakeLists.txt`（40 行）、
> `stm/CMakeLists.txt`（34 行）、`stm/stm32_common/CMakeLists.txt`（43 行）、`stm/stm32h7/CMakeLists.txt`（44 行）
> **上游接线**：[`platforms/nuttx/CMakeLists.txt:74`](cmakelists.md#^src-platforms-nuttx-CMakeLists-txt-74)、`:522-528`、`:539-550`
> **层**：构建期（属于 [03_moc/00-build-walkthrough](../../03_moc/00-build-walkthrough.md) 的"板型变量展开"支线，本篇只讲 bootloader 这一侧）

---

## 1. 运行时它处在哪：**构建期**，`make rm2027_fmu-h743_bootloader` 那一刻

```
PX4_BOARD_LABEL = "bootloader"              ← CMakeCache.txt:319（由 boards/rm2027/fmu-h743/bootloader.px4board 产生）
platforms/nuttx/CMakeLists.txt:74  if("${PX4_BOARD_LABEL}" MATCHES "^bootloader")
                            :78      set(SCRIPT_PREFIX bootloader_)      ← 决定用 bootloader_script.ld
                            :79      add_subdirectory(src/bootloader)   ← ★ 进本目录
                            :80-84   nuttx_libs += bootloader / bootloader_lib / drivers_board
```

**⇒ 一个 CMake 变量（`PX4_BOARD_LABEL`）决定了"这个 build 目录编出来的是 bootloader 还是 app"。**
同一个 `boards/rm2027/fmu-h743/` 目录，靠 `bootloader.px4board` / `default.px4board` 两个文件分出两个构建。

---

## 2. 三层是怎么"挂"起来的

[`stm/stm32_common/CMakeLists.txt:34`](../drivers/dshot.md#^src-CMakeLists-txt-34)

```cmake
px4_add_library(arch_bootloader        # ← ②层：芯片族
    main.c
    systick.c
)
target_link_libraries(arch_bootloader PRIVATE bootloader_lib nuttx_arch)
```

`stm32h7/CMakeLists.txt`（H7 专属，四行而已）

```cmake
:34  add_subdirectory(../stm32_common arch_bootloader)   # ← 复用 stm32_common，二进制目录名 arch_bootloader
:36-39 target_sources(arch_bootloader PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/ecc_scrub.c)  # ← ★ 追加 H7 补丁
:41-44 target_include_directories(arch_bootloader PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}) # ★ 让 main.c 能 #include "ecc_scrub.h"
```

> ★ 这两行解释了 [`main.c:22`](cmakelists.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-22) 为什么可以 `#if defined(CONFIG_ARCH_CHIP_STM32H7) #include "ecc_scrub.h"`：
> **include 路径是 [`stm32h7/CMakeLists.txt:41`](../drivers/dshot.md#^src-CMakeLists-txt-41) 加的**，而 `main.c` 住在 `stm32_common/`。

`common/CMakeLists.txt`

```cmake
:34-38  add_library(bootloader bl.c image_toc.c crypto.c)        # ← ①层
:40-42  target_compile_definitions(bootloader PRIVATE
            BOOTLOADER_VERSION="PX4BLv${PX4_VERSION_MAJOR}.${...}.g${PX4_GIT_HASH}")
:44-47  target_link_libraries(bootloader PRIVATE arch_bootloader) # ★ ①→② 的链接方向
:49-54  if (DEFINED PX4_CRYPTO) target_link_libraries(bootloader PRIVATE crypto_backend) endif()
:56     add_dependencies(bootloader prebuild_targets)
:58     add_subdirectory(lib)                                     # ← bootloader_lib
```

`common/lib/CMakeLists.txt`

```cmake
:34-38  add_library(bootloader_lib cdcacm.c uart.c flash_cache.c)
```

### 2.1 ★ 依赖方向表（谁"知道"谁）

| 从 | 到 | 依据 |
|---|---|---|
| `bootloader`（①） | `arch_bootloader`（②） | [`common/CMakeLists.txt:44`](cmakelists.md#^src-CMakeLists-txt-44) |
| `arch_bootloader`（②） | `bootloader_lib`（①的 lib） + `nuttx_arch` | [`stm32_common/CMakeLists.txt:39`](cmakelists.md#^src-CMakeLists-txt-39) |
| ③（`drivers_board`） | 被顶层直接加进 `nuttx_libs` | [`platforms/nuttx/CMakeLists.txt:83`](cmakelists.md#^src-platforms-nuttx-CMakeLists-txt-83) |
| ③（`hw_config.h` / `bootloader_main.c`） | 被 ①②层通过 `#include "hw_config.h"` 反向使用 | [`bl.c:41`](cmakelists.md#^src-platforms-nuttx-src-bootloader-common-bl-c-41)、[`main.c:9`](cmakelists.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-9)、[`bootloader_main.c:40`](cmakelists.md#^src-boards-rm2027-fmu-h743-src-bootloader-main-c-40) |

**⇒ 依赖图是"环"的**：① 链 ②、② 链 ①的 lib、③ 又链回 ①。
**这不矛盾**，因为 CMake 的 `target_link_libraries` 只在**最终可执行文件**那一层做合并；
编译期真正的耦合是 **③层用宏（`hw_config.h`）参数化 ①②层**，而不是 ①② 调用 ③ 的函数。

**⇒ 这正是"移植一块新板只需要写 ③"的根本原因**：①②层一行都不用改。

`stm/CMakeLists.txt` 只有一行：`add_subdirectory(${PX4_CHIP})`
⇒ `PX4_CHIP = stm32h7`（CMakeCache.txt:334）⇒ 进 `stm/stm32h7/`。
而 [`bootloader/CMakeLists.txt:36`](ecc-scrub-c.md#^src-CMakeLists-txt-36)：

```cmake
:34 include_directories(${CMAKE_CURRENT_SOURCE_DIR}/common)
:36 add_subdirectory(common)
:37 add_subdirectory(${PX4_CHIP_MANUFACTURER})   # ← PX4_CHIP_MANUFACTURER = stm（CMakeCache.txt:337）
```

---

## 3. 产物：bootloader 那条额外的 objcopy

```cmake
platforms/nuttx/CMakeLists.txt
:522  if("${PX4_BOARD_LABEL}" STREQUAL "bootloader")
:523-526  add_custom_command(OUTPUT ${PX4_BOARD_DIR}/extras/${PX4_BOARD}_bootloader.bin
              COMMAND ${CMAKE_OBJCOPY} -O binary ${PX4_BINARY_DIR_REL}/${FW_NAME} ...)
:527      add_custom_target(px4_bootloader_keep ALL DEPENDS ...)
```

⇒ 编译 bootloader 时会**往源码树里写一个 `.bin`**：
`boards/rm2027/fmu-h743/extras/rm2027_fmu-h743_bootloader.bin`（**本板 25 个文件清单里的那一个**）。

然后 **app 的构建**反过来用它：

```cmake
:539  if(NOT label==bootloader AND EXISTS .../extras/${PX4_BOARD_VENDOR}_${PX4_BOARD_MODEL}_bootloader.bin)
:543      ${CMAKE_OBJCOPY} -I binary -O elf32-little --change-section-address .data=0x08000000 ...
              ...bin → ${PX4_BINARY_DIR}/rm2027_fmu-h743_bootloader.elf
:549      add_custom_target(bootloader_elf DEPENDS ...)
```

**⇒ 执行序上的因果**：
1. 先 `make rm2027_fmu-h743_bootloader` ⇒ 产出 `extras/*_bootloader.bin`（**这就是"烧到 0x08000000 的东西"**）；
2. 再 `make rm2027_fmu-h743_default` ⇒ 顺带把那个 `.bin` 包成一个 `.elf` 供上位机（`px_uploader`）识别/烧写；
3. **如果跳过第 1 步**，app 构建里 `:539` 的 `EXISTS` 为假 ⇒ 没有 `bootloader_elf` 目标，上位机烧 bootloader 那一步会缺文件。

> ⇒ 这条也是"为什么 repo 里要**提交**那个 `.bin`"的理由：它既是产物、又是 app 构建的输入。

---

## 4. 编译进来的东西 vs 被裁掉的东西（精确清单）

| 目标文件 | 是否进镜像 | 依据 |
|---|---|---|
| `bl.c` | ✅ | [`common/CMakeLists.txt:35`](cmakelists.md#^src-CMakeLists-txt-35) |
| `image_toc.c` / `crypto.c` | ⚠️ **编进库，但符号不进镜像**（已 nm 实测） | [`common/CMakeLists.txt:36`](ecc-scrub-c.md#^src-CMakeLists-txt-36) + `bl.c:321/1039` 的 `#ifdef` 全关（见 [02_code_twin/bootloader/image-toc-crypto](image-toc-crypto.md)） |
| `uart.c` | ✅（本板唯一通道） | [`common/lib/CMakeLists.txt:36`](ecc-scrub-c.md#^src-CMakeLists-txt-36) |
| `cdcacm.c` | ❌ 调用点全被裁 | [`common/lib/CMakeLists.txt:35`](cmakelists.md#^src-CMakeLists-txt-35) + `bl.c:176/193/202/233` |
| `flash_cache.c` | ✅ | [`common/lib/CMakeLists.txt:37`](../drivers/h104_imu.md#^src-CMakeLists-txt-37) |
| `stm32_common/main.c` | ✅ | [`stm32_common/CMakeLists.txt:35`](cmakelists.md#^src-CMakeLists-txt-35) |
| `stm32_common/systick.c` | ✅ | [`stm32_common/CMakeLists.txt:36`](ecc-scrub-c.md#^src-CMakeLists-txt-36) |
| `stm32h7/ecc_scrub.c` | ✅（仅在 H7 构建里） | [`stm32h7/CMakeLists.txt:36`](ecc-scrub-c.md#^src-CMakeLists-txt-36) |
| `bootloader_main.c`（③层） | ✅ | `boards/rm2027/fmu-h743/src/CMakeLists.txt`（由 `drivers_board` 目标收集） |

**⇒ 一句话**：`CMakeLists` 决定"**哪些 .o 参与链接**"，
`hw_config.h` 里的宏决定"**同一份 .o 里哪些代码被预处理掉**"。
两者合起来才是"最终镜像里有什么"。**这是两套完全不同的机制，不要混起来看。**

---

## 5. "我看到的现象由谁产生"

| 现象 | 由谁 | 依据 |
|---|---|---|
| `build/` 下同时有 `rm2027_fmu-h743_bootloader/` 和 `rm2027_fmu-h743_default/` | `PX4_BOARD_LABEL` 两个取值 | [`platforms/nuttx/CMakeLists.txt:74`](cmakelists.md#^src-platforms-nuttx-CMakeLists-txt-74) |
| bootloader 用的是 `bootloader_script.ld`（flash 只有 128K） | `SCRIPT_PREFIX bootloader_` | 同上 `:78` |
| 用错 linker script ⇒ bootloader 链接溢出 | 同上 | — |
| `GET_VERSION` 回 `PX4BLv…g<githash>` | `target_compile_definitions(BOOTLOADER_VERSION=…)` | [`common/CMakeLists.txt:40`](cmakelists.md#^src-CMakeLists-txt-40) |
| 只编 app 不编 bootloader ⇒ 上位机缺 `bootloader_elf` | [`platforms/nuttx/CMakeLists.txt:539`](cmakelists.md#^src-platforms-nuttx-CMakeLists-txt-539) 的 `EXISTS` 条件 | — |
| 改了 `hw_config.h` 却"没生效" | 只有宏变而 `CMakeLists` 没变 ⇒ **需重新编译**（`hw_config.h` 是头依赖，正常 ninja 会重编） | — |

---

## 跳转

- **执行序上一步**（"板型 → 变量 → 源文件"整条链）→ [03_moc/00-build-walkthrough](../../03_moc/00-build-walkthrough.md)（task-10 主交付）。
  本篇只覆盖 bootloader 这一支；`PX4_BOARD_LABEL` 的来源、`default.px4board` 里 `CONFIG_*` 怎么变成宏，去那边。
- **执行序下一步**（产物怎么被烧进 0x08000000、然后跑起来）→ [02_code_twin/bootloader/00-overview](00-overview.md) §3 第 1 步。
- **③层文件在构建期被谁读** → [02_code_twin/bootloader/board-layer](board-layer.md)。
- **`image_toc.c/crypto.c` 为什么编了却不进镜像** → [02_code_twin/bootloader/image-toc-crypto](image-toc-crypto.md)。

---

## 未核实

- `boards/rm2027/fmu-h743/src/CMakeLists.txt` 里 `bootloader_main.c` 的确切收集方式我**没有逐行读**
  （只从 map 文件 `build/.../rm2027_fmu-h743_bootloader.map:168` 看到 `libdrivers_board.a(bootloader_main.c.obj)` 反证它被编进了）。标"部分核实"。
- `bootloader.px4board` 里 `CONFIG_BOARD_ROMFSROOT=""` 如何变成"bootloader 没有 ROMFS"的完整链路 → [01_extracted/nuttx/romfs](../../01_extracted/nuttx/romfs.md)。

---

## 标注源码（代码 + 本文档对它的解释）

> **这是「代码孪生」层**：上面是代码原文（带行号），下面是**本文档针对这一段说的话**。
> 行号可点，直接跳到 PX4 源码那一行。
### `CMakeLists.txt`
<a id="src-CMakeLists-txt-34"></a>
**↓ 文档在讲这里：**[`CMakeLists.txt:34`](cmakelists.md#^src-CMakeLists-txt-34)

```c
    31 │ #
    32 │ ############################################################################
    33 │ 
▶   34 │ #=============================================================================
    35 │ # CMAKE CODING STANDARD FOR PX4
    36 │ #
    37 │ # Structure
```
> **说明**：stm/stm32_common/CMakeLists.txt:34
^src-CMakeLists-txt-34

<a id="src-CMakeLists-txt-35"></a>
**↓ 文档在讲这里：**[`CMakeLists.txt:35`](cmakelists.md#^src-CMakeLists-txt-35)

```c
    32 │ ############################################################################
    33 │ 
    34 │ #=============================================================================
▶   35 │ # CMAKE CODING STANDARD FOR PX4
    36 │ #
    37 │ # Structure
    38 │ # ---------------------------------------------------------------------------
```
> **说明**：bl.c | ✅ | common/CMakeLists.txt:35 |
> **说明**：uart.c | ✅（本板唯一通道） | common/lib/CMakeLists.txt:36 | ┃ cdcacm.c | ❌ 调用点全被裁 | common/lib/CMakeLists.txt:35 + bl.c:176/193/202/233 |
^src-CMakeLists-txt-35

<a id="src-CMakeLists-txt-36"></a>
**↓ 文档在讲这里：**[`CMakeLists.txt:36`](cmakelists.md#^src-CMakeLists-txt-36)

```c
    33 │ 
    34 │ #=============================================================================
    35 │ # CMAKE CODING STANDARD FOR PX4
▶   36 │ #
    37 │ # Structure
    38 │ # ---------------------------------------------------------------------------
    39 │ #
```
> **说明**：⇒ PX4_CHIP = stm32h7（CMakeCache.txt:334）⇒ 进 stm/stm32h7/。 ┃ 而 bootloader/CMakeLists.txt:36：
> **说明**：bl.c | ✅ | common/CMakeLists.txt:35 | ┃ image_toc.c / crypto.c | ⚠️ 编进库，但符号不进镜像（已 nm 实测） | common/CMakeLists.txt:36 + bl.c:321/1039 的 #ifdef 全关（见 02_code_twin/bootloader/image-toc-crypto） |
^src-CMakeLists-txt-36

<a id="src-CMakeLists-txt-37"></a>
**↓ 文档在讲这里：**[`CMakeLists.txt:37`](cmakelists.md#^src-CMakeLists-txt-37)

```c
    34 │ #=============================================================================
    35 │ # CMAKE CODING STANDARD FOR PX4
    36 │ #
▶   37 │ # Structure
    38 │ # ---------------------------------------------------------------------------
    39 │ #
    40 │ # * Common functions should be included in px_base.cmake.
```
> **说明**：cdcacm.c | ❌ 调用点全被裁 | common/lib/CMakeLists.txt:35 + bl.c:176/193/202/233 | ┃ flash_cache.c | ✅ | common/lib/CMakeLists.txt:37 |
^src-CMakeLists-txt-37

<a id="src-CMakeLists-txt-39"></a>
**↓ 文档在讲这里：**[`CMakeLists.txt:39`](cmakelists.md#^src-CMakeLists-txt-39)

```c
    36 │ #
    37 │ # Structure
    38 │ # ---------------------------------------------------------------------------
▶   39 │ #
    40 │ # * Common functions should be included in px_base.cmake.
    41 │ #
    42 │ # * OS/ board specific fucntions should be include in
```
> **说明**：bootloader（①） | arch_bootloader（②） | common/CMakeLists.txt:44 | ┃ arch_bootloader（②） | bootloader_lib（①的 lib） + nuttx_arch | stm32_common/CMakeLists.txt:39 |
^src-CMakeLists-txt-39

<a id="src-CMakeLists-txt-40"></a>
**↓ 文档在讲这里：**[`CMakeLists.txt:40`](cmakelists.md#^src-CMakeLists-txt-40)

```c
    37 │ # Structure
    38 │ # ---------------------------------------------------------------------------
    39 │ #
▶   40 │ # * Common functions should be included in px_base.cmake.
    41 │ #
    42 │ # * OS/ board specific fucntions should be include in
    43 │ #	px_impl_${PX4_PLATFORM}.cmake
```
> **说明**：用错 linker script ⇒ bootloader 链接溢出 | 同上 | — | ┃ GET_VERSION 回 PX4BLv…g<githash> | target_compile_definitions(BOOTLOADER_VERSION=…) | common/CMakeLists.txt:40 |
^src-CMakeLists-txt-40

<a id="src-CMakeLists-txt-41"></a>
**↓ 文档在讲这里：**[`CMakeLists.txt:41`](cmakelists.md#^src-CMakeLists-txt-41)

```c
    38 │ # ---------------------------------------------------------------------------
    39 │ #
    40 │ # * Common functions should be included in px_base.cmake.
▶   41 │ #
    42 │ # * OS/ board specific fucntions should be include in
    43 │ #	px_impl_${PX4_PLATFORM}.cmake
    44 │ #
```
> **说明**：★ 这两行解释了 main.c:22 为什么可以 #if defined(CONFIG_ARCH_CHIP_STM32H7) #include "ecc_scrub.h"： ┃ include 路径是 stm32h7/CMakeLists.txt:41 加的，而 main.c 住在 stm32_common/。
^src-CMakeLists-txt-41

<a id="src-CMakeLists-txt-44"></a>
**↓ 文档在讲这里：**[`CMakeLists.txt:44`](cmakelists.md#^src-CMakeLists-txt-44)

```c
    41 │ #
    42 │ # * OS/ board specific fucntions should be include in
    43 │ #	px_impl_${PX4_PLATFORM}.cmake
▶   44 │ #
    45 │ # Formatting
    46 │ # ---------------------------------------------------------------------------
    47 │ #
```
> **说明**：bootloader（①） | arch_bootloader（②） | common/CMakeLists.txt:44 |
^src-CMakeLists-txt-44

### `boards/rm2027/fmu-h743/src/bootloader_main.c`
<a id="src-boards-rm2027-fmu-h743-src-bootloader-main-c-40"></a>
**↓ 文档在讲这里：**[`boards/rm2027/fmu-h743/src/bootloader_main.c:40`](cmakelists.md#^src-boards-rm2027-fmu-h743-src-bootloader-main-c-40)

```c
    37 │  * FMU-specific early startup code for bootloader
    38 │ */
    39 │ 
▶   40 │ #include "board_config.h"
    41 │ #include "bl.h"
    42 │ 
    43 │ #include <nuttx/config.h>
```
> **说明**：③（drivers_board） | 被顶层直接加进 nuttx_libs | platforms/nuttx/CMakeLists.txt:83 | ┃ ③（hw_config.h / bootloader_main.c） | 被 ①②层通过 #include "hw_config.h" 反向使用 | bl.c:41、main.c:9、bootloader_main.c:40 |
^src-boards-rm2027-fmu-h743-src-bootloader-main-c-40

### `platforms/nuttx/CMakeLists.txt`
<a id="src-platforms-nuttx-CMakeLists-txt-74"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/CMakeLists.txt:74`](cmakelists.md#^src-platforms-nuttx-CMakeLists-txt-74)

```c
    71 │ # "bootloader_secureboot") so a board can ship a bootloader variant
    72 │ # with extra Kconfig (crypto, keystore, etc.) without duplicating
    73 │ # the bootloader build wiring.
▶   74 │ if("${PX4_BOARD_LABEL}" MATCHES "^bootloader")
    75 │ 	# All bootloader variants share the same linker script
    76 │ 	# (bootloader_script.ld); the label suffix only changes which
    77 │ 	# Kconfig and which Tools/test_keys/*.pub are baked in.
```
> **说明**：stm/CMakeLists.txt（34 行）、stm/stm32_common/CMakeLists.txt（43 行）、stm/stm32h7/CMakeLists.txt（44 行） ┃ 上游接线：platforms/nuttx/CMakeLists.txt:74、:522-528、:539-550
> **说明**：build/ 下同时有 rm2027_fmu-h743_bootloader/ 和 rm2027_fmu-h743_default/ | PX4_BOARD_LABEL 两个取值 | platforms/nuttx/CMakeLists.txt:74 |
^src-platforms-nuttx-CMakeLists-txt-74

<a id="src-platforms-nuttx-CMakeLists-txt-83"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/CMakeLists.txt:83`](cmakelists.md#^src-platforms-nuttx-CMakeLists-txt-83)

```c
    80 │ 	list(APPEND nuttx_libs
    81 │ 		bootloader
    82 │ 		bootloader_lib
▶   83 │ 		drivers_board
    84 │ 	)
    85 │ elseif("${PX4_BOARD_LABEL}" STREQUAL "canbootloader")
    86 │ 	set(SCRIPT_PREFIX ${PX4_BOARD_LABEL}_)
```
> **说明**：arch_bootloader（②） | bootloader_lib（①的 lib） + nuttx_arch | stm32_common/CMakeLists.txt:39 | ┃ ③（drivers_board） | 被顶层直接加进 nuttx_libs | platforms/nuttx/CMakeLists.txt:83 |
^src-platforms-nuttx-CMakeLists-txt-83

<a id="src-platforms-nuttx-CMakeLists-txt-539"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/CMakeLists.txt:539`](cmakelists.md#^src-platforms-nuttx-CMakeLists-txt-539)

```c
   536 │ )
   537 │ 
   538 │ # generate bootloader.elf and copy to top level build directory
▶  539 │ if(NOT ("${PX4_BOARD_LABEL}" STREQUAL "bootloader") AND (EXISTS "${PX4_BOARD_DIR}/extras/${PX4_BOARD_VENDOR}_${PX4_BOARD_MODEL}_bootloader.bin"))
   540 │ 	add_custom_command(
   541 │ 		OUTPUT ${PX4_BINARY_DIR}/${PX4_BOARD_VENDOR}_${PX4_BOARD_MODEL}_bootloader.elf
   542 │ 		COMMAND
```
> **说明**：GET_VERSION 回 PX4BLv…g<githash> | target_compile_definitions(BOOTLOADER_VERSION=…) | common/CMakeLists.txt:40 | ┃ 只编 app 不编 bootloader ⇒ 上位机缺 bootloader_elf | platforms/nuttx/CMakeLists.txt:539 的 EXISTS 条件 | — |
^src-platforms-nuttx-CMakeLists-txt-539

### `platforms/nuttx/src/bootloader/common/bl.c`
<a id="src-platforms-nuttx-src-bootloader-common-bl-c-41"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:41`](cmakelists.md#^src-platforms-nuttx-src-bootloader-common-bl-c-41)

```c
    38 │  *
    39 │  * Aside from the header includes below, this file should have no board-specific logic.
    40 │  */
▶   41 │ #include "hw_config.h"
    42 │ 
    43 │ #include <inttypes.h>
    44 │ #include <stdlib.h>
```
> **说明**：③（drivers_board） | 被顶层直接加进 nuttx_libs | platforms/nuttx/CMakeLists.txt:83 | ┃ ③（hw_config.h / bootloader_main.c） | 被 ①②层通过 #include "hw_config.h" 反向使用 | bl.c:41、main.c:9、bootloader_main.c:40 |
^src-platforms-nuttx-src-bootloader-common-bl-c-41

### `platforms/nuttx/src/bootloader/stm/stm32_common/main.c`
<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-9"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:9`](cmakelists.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-9)

```c
     6 │ #include <px4_platform_common/px4_config.h>
     7 │ #include <px4_defines.h>
     8 │ 
▶    9 │ #include "hw_config.h"
    10 │ 
    11 │ #include <stm32_pwr.h>
    12 │ #include <stm32_rtc.h>
```
> **说明**：③（drivers_board） | 被顶层直接加进 nuttx_libs | platforms/nuttx/CMakeLists.txt:83 | ┃ ③（hw_config.h / bootloader_main.c） | 被 ①②层通过 #include "hw_config.h" 反向使用 | bl.c:41、main.c:9、bootloader_main.c:40 |
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-9

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-22"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:22`](cmakelists.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-22)

```c
    19 │ #include "bl.h"
    20 │ #include "uart.h"
    21 │ 
▶   22 │ #if defined(CONFIG_ARCH_CHIP_STM32H7)
    23 │ #include "ecc_scrub.h"
    24 │ #endif
    25 │ 
```
> **说明**：★ 这两行解释了 main.c:22 为什么可以 #if defined(CONFIG_ARCH_CHIP_STM32H7) #include "ecc_scrub.h"：
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-22
