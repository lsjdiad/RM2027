# 01 · Kconfig 桥：`default.px4board` ↔ Kconfig ↔ CMake ↔ C 宏

> 层：`01_extracted/`（提炼知识）｜视角：**构建运行时**
> 一句话：**PX4 的一整块板子（有哪些驱动、哪些模块、ROMFS 装什么、串口在哪）全部来自一个叫 `default.px4board` 的纯文本文件，中间只经过 Kconfig 一层翻译。**
> 本篇讲清这层翻译的**四个面**（Kconfig 符号 / 配置文件 / C 宏 / CMake 变量）以及它们之间**没有自动推导的那一格**（目录路径）。

---

## 1. 四层对应的名字

同一个开关在四个地方各有一张脸：

| 层 | 形态 | 本板例子 | 谁看它 |
|---|---|---|---|
| ① Kconfig 声明 | `menuconfig <NAME>` + help | `menuconfig DRIVERS_DSHOT`（[`src/drivers/dshot/Kconfig:1`](../../02_code_twin/build/drivers-build.md#^src-src-drivers-dshot-Kconfig-1)） | 人（`make boardconfig` 的 TUI）；kconfiglib |
| ② 板级配置文件（= defconfig） | `CONFIG_<NAME>=y` | `CONFIG_DRIVERS_DSHOT=y`（[`boards/rm2027/fmu-h743/default.px4board:6`](../../02_code_twin/build/board-build.md#^src-boards-rm2027-fmu-h743-default-px4board-6)） | `python -m defconfig` |
| ③ 翻译产物 A：CMake 变量 / 模块列表 | `set(CONFIG_<NAME> y CACHE INTERNAL)`、`config_module_list += drivers/dshot` | [`cmake/kconfig.cmake:130`](03-kconfig-bridge.md#^src-cmake-kconfig-cmake-130)、`:197-198` | CMake：`if(CONFIG_…)`、`add_subdirectory` |
| ④ 翻译产物 B：C 宏 | `#define CONFIG_<NAME> 1` | `build/…/px4_boardconfig.h:27` | 编译器：`#ifdef CONFIG_DRIVERS_DSHOT` |

> ★ **①③④ 都是机制，② 是本板唯一手写的东西。** 换板子 = 换 ②。
> 顺序反过来说更清楚：**C 宏是 Kconfig 的产物，CMake 变量也是 Kconfig 的产物，二者同源不同形。**

---

## 2. Kconfig 树长什么样（源码：仓库根的 `Kconfig`，263 行）

[`kconfig.cmake:76`](03-kconfig-bridge.md#^src-cmake-kconfig-cmake-76) 跑 `python -m defconfig <default.px4board>` 时，工作目录是 `${PX4_SOURCE_DIR}`（`:79`）⇒ **Kconfig 入口就是仓库根的 `Kconfig`**。

根 `Kconfig` 的结构（**这是理解"某个开关从哪来"的最快索引**）：

| 行 | 内容 | 管什么 |
|---|---|---|
| `:4` | `mainmenu "PX4 Firmware Configuration"` | |
| `:6-8` | `comment "Vendor: $(VENDOR)"` 等三行 | ★ **Kconfig 里能用环境变量**：`VENDOR`/`MODEL`/`LABEL` 由 [`kconfig.cmake:55`](03-kconfig-bridge.md#^src-cmake-kconfig-cmake-55) 注入 |
| `:10-127` | `menu "Toolchain"` | `PLATFORM_*`、`BOARD_PLATFORM`、`BOARD_TOOLCHAIN`、`BOARD_ARCHITECTURE`、`BOARD_ROMFSROOT`、`BOARD_LTO`、`BOARD_CONSTRAINED_FLASH`、`BOARD_LINKER_PREFIX`… |
| `:129-174` | 顶层 bool | `BOARD_TESTING`、`BOARD_ETHERNET`、`BOARD_CRYPTO`、`BOARD_SECUREBOOT`、`BOARD_PROTECTED` |
| `:176-219` | `menu "Serial ports"` | ★ `BOARD_SERIAL_TEL1` … `BOARD_SERIAL_EXT2` 全在这一段 |
| `:221-236` | `menu "File paths"` | `BOARD_ROOT_PATH`（默认 `/fs/microsd`）、`BOARD_PARAM_FILE`（默认 `/fs/mtd_params`）、`BOARD_NO_SDCARD` |
| `:238-240` | `menu "drivers"` + `source "src/drivers/Kconfig"` | ★ **全部驱动** |
| `:242-244` | `source "src/modules/Kconfig"` | 全部模块 |
| `:246-248` | `source "src/systemcmds/Kconfig"` | 全部系统命令 |
| `:250-252` / `:254-256` | `examples` / `templates` | |
| `:258-261` | `source "platforms/Kconfig"` | 平台 |
| `:263` | `source "src/lib/*/Kconfig"` | ★ 通配：**lib 目录下任意一级子目录的 Kconfig 自动收** |

### 2.1 子树的递归约定（写新驱动时要遵守）

| 上层文件 | 这一行 | 作用 |
|---|---|---|
| `src/drivers/Kconfig` | （见文件内 `source "*/Kconfig"` / `rsource "*/Kconfig"`） | 收 `src/drivers/<子目录>/Kconfig` |
| `src/drivers/imu/Kconfig` | `rsource "*/Kconfig"` | ★ **收 `src/drivers/imu/<子目录>/Kconfig`** ⇒ 新增 `imu/hxy/` 不用改上层 |
| [`src/drivers/magnetometer/Kconfig:22`](03-kconfig-bridge.md#^src-src-drivers-magnetometer-Kconfig-22) | `rsource "*/Kconfig"` | 同上 |
| `src/drivers/imu/hxy/Kconfig` | `rsource "*/Kconfig"` | 再收一层 ⇒ `hxy42688p/Kconfig` |

⇒ **本板的两个新驱动正是靠这个约定"零改上层"接进去的**（[`src/drivers/imu/hxy/hxy42688p/Kconfig:1`](03-kconfig-bridge.md#^src-src-drivers-imu-hxy-hxy42688p-Kconfig-1)、[`src/drivers/imu/hipnuc_h104/Kconfig:1`](03-kconfig-bridge.md#^src-src-drivers-imu-hipnuc-h104-Kconfig-1)）。

### 2.2 另一个 Kconfig 树：板级 NuttX 配置

`boards/rm2027/fmu-h743/nuttx-config/Kconfig`（**定义 `BOARD_HAS_PROBES` / `BOARD_USE_PROBES`**）**不属于** PX4 这棵树，它进的是 **NuttX 的 `.config`**。
链路（**源码**）：

1. [`platforms/nuttx/NuttX/nuttx/tools/Config.mk:163`](03-kconfig-bridge.md#^src-platforms-nuttx-NuttX-nuttx-tools-Config-mk-163) — `ARCH_BOARD_CUSTOM=y` ⇒ `:166 CUSTOM_DIR = $(patsubst "%",%,$(CONFIG_ARCH_BOARD_CUSTOM_DIR))`、`:168 BOARD_DIR = $(TOPDIR)/$(CUSTOM_DIR)`
2. `:172` `CUSTOM_BOARD_KPATH = $(BOARD_DIR)/Kconfig` ⇒ 就是 `boards/rm2027/fmu-h743/nuttx-config/Kconfig`
3. `:176-180` `BOARD_KCONFIG = $(CUSTOM_BOARD_KPATH)`（文件存在时；否则指向 `boards/dummy/dummy_kconfig`）
4. [`platforms/nuttx/NuttX/nuttx/tools/Unix.mk:364`](03-kconfig-bridge.md#^src-platforms-nuttx-NuttX-nuttx-tools-Unix-mk-364) — `cp -f $(BOARD_KCONFIG) boards/dummy/Kconfig`
5. NuttX 的 Kconfig 树 `source` 这个 dummy ⇒ 板级选项进 `.config`

**实测**：`build/rm2027_fmu-h743_default/NuttX/nuttx/.config:635-636`
`CONFIG_BOARD_HAS_PROBES=y` / `# CONFIG_BOARD_USE_PROBES is not set`

> ⇒ **两棵 Kconfig 树不要混**：PX4 树的产物是 `build/…/boardconfig` + `px4_boardconfig.h`；NuttX 树的产物是 `build/…/NuttX/nuttx/.config` + `platforms/nuttx/NuttX/nuttx/include/nuttx/config.h`。

---

## 3. 三跳翻译（本文核心）

```
boards/rm2027/fmu-h743/default.px4board          ← 你手写的 98 行
        │  python -m defconfig  （Kconfig 树 + select 展开 + 补默认值）
        ▼
build/rm2027_fmu-h743_default/boardconfig        ← 760 行，Kconfig 全量
        │
        ├─ python -m genconfig --header-path
        │         ▼
        │  build/…/px4_boardconfig.h  （182 行，182 个 #define）  ──►  编译器
        │
        └─ file(STRINGS) + 前缀分派（cmake/kconfig.cmake:114-273）
                  ▼
           CMake 变量 CONFIG_* + config_module_list  ──►  add_subdirectory / if()
```

### 3.1 第一跳：`.px4board` 就是 defconfig

**源码**：[`cmake/kconfig.cmake:1`](../../02_code_twin/build/cmake-kconfig.md#^src-cmake-kconfig-cmake-1) `set(BOARD_DEFCONFIG ${PX4_CONFIG_FILE} ...)`，`:74-81` 直接把它当 kconfiglib `defconfig` 命令的输入。

`.px4board` 文件格式 = **`savedefconfig` 的输出格式**（也就是"只写跟默认值不同的项"），所以：

- 只写 `CONFIG_X=y` 表示"打开"，**不需要写 `# CONFIG_Y is not set`**
- 但**可以**写（kconfiglib 认），本板没写
- **`select` 出来的项不用写** —— 例如 `default.px4board:33 CONFIG_COMMON_MAGNETOMETER=y` 一行就带出 15 个磁罗盘驱动的 `=y`（[`src/drivers/magnetometer/Kconfig:2`](../../02_code_twin/build/drivers-build.md#^src-src-drivers-magnetometer-Kconfig-2)）

### 3.2 第二跳：`boardconfig` —— 前缀分派表

**源码**：[`cmake/kconfig.cmake:114`](../../02_code_twin/build/cmake-kconfig.md#^src-cmake-kconfig-cmake-114) 起，逐行 `file(STRINGS)` + 6 个 `string(REGEX MATCH "^CONFIG_<前缀>")`。

| 前缀 | 行号 | 产物 | 是否影响"编什么" |
|---|---|---|---|
| （无前缀，兜底）`CONFIG_*` | `:130` | `set(CONFIG_X <值> CACHE INTERNAL ...)` | ⇒ **使 `if(CONFIG_X)` 在任何 CMakeLists 里可用** |
| `CONFIG_BOARD_*` | `:142-150` | 去掉前缀当 CMake 变量 + `message(STATUS)` | 间接：`:324-375` 组装 `board_serial_ports` / `config_romfs_root` |
| `CONFIG_USER_*` | `:153-161` | `config_user_list` | 只在 `CONFIG_BOARD_PROTECTED` 时用 |
| `CONFIG_DRIVERS_*` | `:164-214` | `config_module_list += drivers/<路径>` | ★ **是** |
| `CONFIG_MODULES_*` | `:217-247` | `config_module_list += modules/<路径>` | ★ **是** |
| `CONFIG_SYSTEMCMDS_*` | `:250-259` | `config_module_list += systemcmds/<小写名>` | ★ **是** |
| `CONFIG_EXAMPLES_*` | `:262-271` | `config_module_list += examples/<小写名>` | ★ **是** |

**另外几个开关不在"模块列表"里，而是直接改构建行为**（同文件）：

| 开关 | 行号 | 行为 |
|---|---|---|
| `CONFIG_BOARD_CONSTRAINED_FLASH` | `:397-400` | `px4_constrained_flash_build=1` + `-DCONSTRAINED_FLASH` |
| `CONFIG_BOARD_NO_HELP` | `:402-404` | `-DCONSTRAINED_FLASH_NO_HELP="<url>"` |
| `CONFIG_BOARD_CONSTRAINED_MEMORY` | `:406-409` | `-DCONSTRAINED_MEMORY` |
| `CONFIG_BOARD_TESTING` / `ETHERNET` / `CRYPTO` | `:411-422` | `PX4_TESTING` / `PX4_ETHERNET` / `-DPX4_CRYPTO` |
| `CONFIG_BOARD_LINKER_PREFIX` | `:424-428` | `PX4_BOARD_LINKER_PREFIX`（决定链接脚本前缀 `<prefix>-script.ld`） |
| `CONFIG_BOARD_COMPILE_DEFINITIONS` | `:430-432` | `add_definitions(${COMPILE_DEFINITIONS})` |
| `CONFIG_BOARD_LOCKSTEP` / `NOLOCKSTEP` | `:438-444` | `ENABLE_LOCKSTEP_SCHEDULER` |
| `CONFIG_BOARD_FULL_OPTIMIZATION` | `:446-448` | `CMAKE_BUILD_TYPE=Release` |
| `CONFIG_BOARD_ROMFSROOT` | `:374-375` | `config_romfs_root` ⇒ `add_subdirectory(ROMFS)` |
| `CONFIG_BOARD_ADDITIONAL_INIT` | `:383-385` | `config_additional_init` |
| `CONFIG_BOARD_SERIAL_*` | `:324-371` | `board_serial_ports` ⇒ 生成 `SER_*_BAUD` 参数 + `rc.serial` |

### 3.3 第三跳 A：`boardconfig` → `px4_boardconfig.h`

**源码**：[`kconfig.cmake:106`](../../02_code_twin/build/cmake-kconfig.md#^src-cmake-kconfig-cmake-106) `python -m genconfig --header-path ${PX4_BINARY_DIR}/px4_boardconfig.h`。

**规则**：`CONFIG_X=y` → `#define CONFIG_X 1`；`CONFIG_X="str"` → `#define CONFIG_X "str"`；`# CONFIG_X is not set` → **不生成**（所以 `#ifdef` 语义天然正确）。

**谁 include 它**（**源码**）：
- [`platforms/common/include/px4_platform_common/px4_config.h:57`](../../02_code_twin/build/others.md#^src-platforms-common-include-px4-platform-common-px4-config-h-57)
- [`platforms/common/include/px4_platform_common/defines.h:43`](03-kconfig-bridge.md#^src-platforms-common-include-px4-platform-common-defines-h-43)
- [`platforms/common/include/px4_platform_common/board_common.h:50`](03-kconfig-bridge.md#^src-platforms-common-include-px4-platform-common-board-common-h-50)
- 少数直接 include 的：[`src/drivers/pca9685_pwm_out/PCA9685.h:37`](03-kconfig-bridge.md#^src-src-drivers-pca9685-pwm-out-PCA9685-h-37)、[`src/lib/adsb/AdsbConflict.h:37`](03-kconfig-bridge.md#^src-src-lib-adsb-AdsbConflict-h-37)、[`src/lib/gnss/correction_framer.h:69`](03-kconfig-bridge.md#^src-src-lib-gnss-correction-framer-h-69)

⇒ **结论：`CONFIG_*` 宏对"几乎任何 PX4 源文件"都是可见的。** 但这**不等于**该驱动被编进去了 —— 编不编由 `config_module_list` 决定（§3.4）。

### 3.4 ★ 唯一没有自动推导的一格：`CONFIG_DRIVERS_*` → 源目录

**源码**：[`kconfig.cmake:169`](../../02_code_twin/build/cmake-kconfig.md#^src-cmake-kconfig-cmake-169)。变形规则：

```
driver = 小写(去掉 "CONFIG_DRIVERS_")
driver_path = driver 里的 "_" 全换成 "/"
```

然后按**书写顺序**试 7 个候选（[`kconfig.cmake:197`](../../02_code_twin/build/cmake-kconfig.md#^src-cmake-kconfig-cmake-197)），命中即 `list(APPEND config_module_list ...)`，全不中 ⇒ `message(FATAL_ERROR "Couldn't find path for ${driver}")`（`:212`）。

| 候选 | 行号 | 拼出的路径形态 | 适用例子 |
|---|---|---|---|
| ① | `:197-198` | `src/drivers/<driver>` | `dshot`、`pwm_out` |
| ② | `:199-200` | `src/drivers/<下划线→斜杠>` | ★ 本板 3 个都走这条 |
| ③ | `:201-202` | `src/drivers/A/B/C`（三段式，A/B/C 从名字切） | 三段式命名 |
| ④ | `:203-204` | `src/drivers/A/B`（`A` = 第一段，`B` = 剩下全部） | `imu/hipnuc_h104` |
| ⑤ | `:205-206` | Pattern 4：`A_B/_C…` | |
| ⑥ | `:207-208` | Pattern 2：`A_B/C…` | |
| ⑦ | `:209-210` | Pattern 5：`A/B/C_D` | |

**本板实测命中结果**（`build/…/config_module_list.txt` 里只有三段式路径 ⇒ 都是候选②）：

| `.px4board` | `driver` | 命中 | 实际目录 |
|---|---|---|---|
| `:6 CONFIG_DRIVERS_DSHOT=y` | `dshot` | ① | `src/drivers/dshot` |
| `:48 CONFIG_DRIVERS_PWM_OUT=y` | `pwm_out` | ① | `src/drivers/pwm_out` |
| `:5 CONFIG_DRIVERS_BAROMETER_GOERTEK_SPA06=y` | `barometer_goertek_spa06` | ② | `src/drivers/barometer/goertek/spa06` |
| `:22 CONFIG_DRIVERS_IMU_HXY_HXY42688P=y` | `imu_hxy_hxy42688p` | ② | `src/drivers/imu/hxy/hxy42688p` |
| `:47 CONFIG_DRIVERS_MAGNETOMETER_ISENTEK_IST8310=y` | `magnetometer_isentek_ist8310` | ② | `src/drivers/magnetometer/isentek/ist8310` |
| `:24 CONFIG_DRIVERS_IMU_HIPNUC_H104=y` | `imu_hipnuc_h104` | ②✗ → ③✗ → **④** | `src/drivers/imu/hipnuc_h104` |

**`CONFIG_MODULES_*` / `CONFIG_SYSTEMCMDS_*` 用同一套思路**（`:217-247` / `:250-259`），但 `SYSTEMCMDS` 是**直接拼**（`systemcmds/<小写名>`，无路径猜测）。

> ✓ **实践结论**：写新驱动时，**目录名要能命中①或②**（`src/drivers/<a>/<b>` 或 `src/drivers/<a>/<b>/<c>`），否则就要去凑③~⑦的奇怪形态。本板的 `hipnuc_h104` 就是"故意不用斜杠"从而落到④的那个例子。
> 为什么顺序是①~⑦、为什么不是先精确匹配：**未核实**（没有上游 commit 依据），只是从 `if/elseif` 的书写顺序读出来的。

---

## 4. 反向操作：改 Kconfig 之后怎么回写

[`kconfig.cmake:463`](03-kconfig-bridge.md#^src-cmake-kconfig-cmake-463) 提供了 4 个 CMake target（不是 shell 命令，要 `make`）：

| target | 行号 | 行为 |
|---|---|---|
| `boardconfig` | `:464-473` | `python -m menuconfig Kconfig` → `savedefconfig` → **覆盖回 `default.px4board`** → 删 `NuttX/apps_copy.stamp` |
| `boardguiconfig` | `:475-484` | 同上，GUI 版 |
| `px4_savedefconfig` | `:486-494` | 从当前 `boardconfig` 直接 `savedefconfig` 回写（不弹 TUI） |
| 非 `default` label | `:497-527` | 用 `Tools/kconfig/diffconfig.py -m default.px4board` 只回写**差异** |

⇒ **改板级配置有两种姿势**：① 直接手改 `default.px4board`（本项目的做法，文件里全是注释说明）；② `make rm2027_fmu-h743_default boardconfig` 走 TUI 再回写。
⇒ 项目选①是合理的：`default.px4board` 里的注释承担了"为什么开这个开关"的文档职责（例如 `:8-46` 解释为什么是 HXY 而不是 BMI270）。

**其他工具**（`Tools/kconfig/`）：`merge_config.py`（[`kconfig.cmake:90`](03-kconfig-bridge.md#^src-cmake-kconfig-cmake-90) 非 default label 用）、`diffconfig.py`、`allyesconfig.py`（[`kconfig.cmake:96`](03-kconfig-bridge.md#^src-cmake-kconfig-cmake-96)，CI 用，会 warn "not for use in production"）、`loadconfig.py`、`updateconfig.py`。

---

## 5. 与 `01_extracted` 邻居的分工

| 问题 | 去哪 |
|---|---|
| `CONFIG_*` 解析完，CMake 这边怎么变成库和可执行文件 | `[01_extracted/cmake/01-px4-cmake-organization](01-px4-cmake-organization.md)` |
| `boardconfig` / `px4_boardconfig.h` / `NuttX/nuttx/.config` 这些文件在 `build/` 里的位置与生命周期 | `[01_extracted/cmake/02-build-dir-map](02-build-dir-map.md)` |
| 本板 98 行 `default.px4board` 逐行膨胀成什么、生成哪些参数 | `[03_moc/00-build-walkthrough](../../03_moc/00-build-walkthrough.md)` §3–§4 |
| `NuttX/nuttx/.config` 之后控制权去哪 | `[03_moc/01-poweron-walkthrough](../../03_moc/01-poweron-walkthrough.md)` |

---

## 6. 跳转

**执行序意义上的下一步**：Kconfig 三跳跑完，`config_module_list` 已经确定 ⇒ 回到 [`CMakeLists.txt:480`](../../02_code_twin/build/cmake-kconfig.md#^src-CMakeLists-txt-480) 逐个 `add_subdirectory`。
⇒ 读 `[01_extracted/cmake/01-px4-cmake-organization](01-px4-cmake-organization.md)` §1 的第 17 步，看这份列表怎么变成静态库、再变成 NSH 命令。

---

## 标注源码（代码 + 本文档对它的解释）

> **这是「代码孪生」层**：上面是代码原文（带行号），下面是**本文档针对这一段说的话**。
> 行号可点，直接跳到 PX4 源码那一行。
### `CMakeLists.txt`
<a id="src-CMakeLists-txt-480"></a>
**↓ 文档在讲这里：**[`CMakeLists.txt:480`](03-kconfig-bridge.md#^src-CMakeLists-txt-480)

```c
   477 │ 	add_subdirectory(${PX4_BOARD_DIR})
   478 │ endif()
   479 │ 
▶  480 │ foreach(module ${config_module_list})
   481 │ 	add_subdirectory(src/${module})
   482 │ endforeach()
   483 │ 
```
> **说明**：执行序意义上的下一步：Kconfig 三跳跑完，config_module_list 已经确定 ⇒ 回到 CMakeLists.txt:480 逐个 add_subdirectory。
^src-CMakeLists-txt-480

### `boards/rm2027/fmu-h743/default.px4board`
<a id="src-boards-rm2027-fmu-h743-default-px4board-6"></a>
**↓ 文档在讲这里：**[`boards/rm2027/fmu-h743/default.px4board:6`](03-kconfig-bridge.md#^src-boards-rm2027-fmu-h743-default-px4board-6)

```c
     3 │ CONFIG_BOARD_SERIAL_TEL1="/dev/ttyS2"   # USART3（本板唯一空闲串口）
     4 │ CONFIG_DRIVERS_ADC_BOARD_ADC=y
     5 │ CONFIG_DRIVERS_BAROMETER_GOERTEK_SPA06=y
▶    6 │ CONFIG_DRIVERS_DSHOT=y
     7 │ # --- IMU（SPI1 / CS=PB4）-----------------------------------------------------
     8 │ # ★ 2026-09-30 最终结论（唯一基准 = 厂商手册）：
     9 │ #   实物 = 华轩阳（HXY）「ICM-42688P」六轴传感器模块，WHO_AM_I(0x01) = 0x6A；
```
> **说明**：① Kconfig 声明 | menuconfig <NAME> + help | menuconfig DRIVERS_DSHOT（src/drivers/dshot/Kconfig:1） | 人（make boardconfig 的 TUI）；kconfiglib | ┃ ② 板级配置文件（= defconfig） | CONFIG_<NAME>=y | CONFIG_DRIVERS_DSHOT=y（boards/rm2027/fmu-h743/default.px4board:6） | python -m defconfig |
^src-boards-rm2027-fmu-h743-default-px4board-6

### `cmake/kconfig.cmake`
<a id="src-cmake-kconfig-cmake-1"></a>
**↓ 文档在讲这里：**[`cmake/kconfig.cmake:1`](03-kconfig-bridge.md#^src-cmake-kconfig-cmake-1)

```c
▶    1 │ set(BOARD_DEFCONFIG ${PX4_CONFIG_FILE} CACHE FILEPATH "path to defconfig" FORCE)
     2 │ set(BOARD_CONFIG ${PX4_BINARY_DIR}/boardconfig CACHE FILEPATH "path to config" FORCE)
     3 │ 
     4 │ execute_process(COMMAND ${PYTHON_EXECUTABLE} -c "import menuconfig" RESULT_VARIABLE ret)
```
> **说明**：源码：cmake/kconfig.cmake:1 set(BOARD_DEFCONFIG ${PX4_CONFIG_FILE} ...)，:74-81 直接把它当 kconfiglib defconfig 命令的输入。
^src-cmake-kconfig-cmake-1

<a id="src-cmake-kconfig-cmake-55"></a>
**↓ 文档在讲这里：**[`cmake/kconfig.cmake:55`](03-kconfig-bridge.md#^src-cmake-kconfig-cmake-55)

```c
    52 │ 	# Set environment variables so that Kconfig can prune Kconfig source
    53 │ 	# files for other architectures
    54 │ 	PLATFORM=${PX4_PLATFORM}
▶   55 │ 	VENDOR=${PX4_BOARD_VENDOR}
    56 │ 	MODEL=${PX4_BOARD_MODEL}
    57 │ 	LABEL=${PX4_BOARD_LABEL}
    58 │ 	TOOLCHAIN=${CMAKE_TOOLCHAIN_FILE}
```
> **说明**：:4 | mainmenu "PX4 Firmware Configuration" | | ┃ :6-8 | comment "Vendor: $(VENDOR)" 等三行 | ★ Kconfig 里能用环境变量：VENDOR/MODEL/LABEL 由 kconfig.cmake:55 注入 |
^src-cmake-kconfig-cmake-55

<a id="src-cmake-kconfig-cmake-76"></a>
**↓ 文档在讲这里：**[`cmake/kconfig.cmake:76`](03-kconfig-bridge.md#^src-cmake-kconfig-cmake-76)

```c
    73 │ 
    74 │ 	if(${LABEL} MATCHES "default" OR ${LABEL} MATCHES "performance-test" OR ${LABEL} MATCHES "bootloader" OR ${LABEL} MATCHES "canbootloader")
    75 │ 		# Generate boardconfig from saved defconfig
▶   76 │ 		execute_process(
    77 │ 			COMMAND ${CMAKE_COMMAND} -E env ${COMMON_KCONFIG_ENV_SETTINGS}
    78 │ 			${DEFCONFIG_PATH} ${BOARD_DEFCONFIG}
    79 │ 			WORKING_DIRECTORY ${PX4_SOURCE_DIR}
```
> **说明**：kconfig.cmake:76 跑 python -m defconfig <default.px4board> 时，工作目录是 ${PX4_SOURCE_DIR}（:79）⇒ Kconfig 入口就是仓库根的 Kconfig。
^src-cmake-kconfig-cmake-76

<a id="src-cmake-kconfig-cmake-90"></a>
**↓ 文档在讲这里：**[`cmake/kconfig.cmake:90`](03-kconfig-bridge.md#^src-cmake-kconfig-cmake-90)

```c
    87 │ 		# Generate boardconfig from default.px4board and {label}.px4board
    88 │ 		execute_process(
    89 │ 			COMMAND ${CMAKE_COMMAND} -E env ${COMMON_KCONFIG_ENV_SETTINGS}
▶   90 │ 			${PYTHON_EXECUTABLE} ${PX4_SOURCE_DIR}/Tools/kconfig/merge_config.py Kconfig ${BOARD_CONFIG} ${PX4_BOARD_DIR}/default.px4board ${BOARD_DEFCONFIG}
    91 │ 			WORKING_DIRECTORY ${PX4_SOURCE_DIR}
    92 │ 			OUTPUT_VARIABLE DUMMY_RESULTS
    93 │ 		)
```
> **说明**：其他工具（Tools/kconfig/）：merge_config.py（kconfig.cmake:90 非 default label 用）、diffconfig.py、allyesconfig.py（kconfig.cmake:96，CI 用，会 warn "not for use in production"）、loadconfig.py、updateconfig.py。
^src-cmake-kconfig-cmake-90

<a id="src-cmake-kconfig-cmake-96"></a>
**↓ 文档在讲这里：**[`cmake/kconfig.cmake:96`](03-kconfig-bridge.md#^src-cmake-kconfig-cmake-96)

```c
    93 │ 		)
    94 │ 	endif()
    95 │ 
▶   96 │ 	if(${LABEL} MATCHES "allyes")
    97 │ 		message(AUTHOR_WARNING "allyes build: allyes is for CI coverage and not for use in production")
    98 │ 		execute_process(
    99 │ 			COMMAND ${CMAKE_COMMAND} -E env ${COMMON_KCONFIG_ENV_SETTINGS}
```
> **说明**：其他工具（Tools/kconfig/）：merge_config.py（kconfig.cmake:90 非 default label 用）、diffconfig.py、allyesconfig.py（kconfig.cmake:96，CI 用，会 warn "not for use in production"）、loadconfig.py、updateconfig.py。
^src-cmake-kconfig-cmake-96

<a id="src-cmake-kconfig-cmake-106"></a>
**↓ 文档在讲这里：**[`cmake/kconfig.cmake:106`](03-kconfig-bridge.md#^src-cmake-kconfig-cmake-106)

```c
   103 │ 	endif()
   104 │ 
   105 │     # Generate header file for C/C++ preprocessor
▶  106 │     execute_process(
   107 │ 	COMMAND ${CMAKE_COMMAND} -E env ${COMMON_KCONFIG_ENV_SETTINGS}
   108 │ 		${GENCONFIG_PATH} --header-path ${PX4_BINARY_DIR}/px4_boardconfig.h
   109 │ 	WORKING_DIRECTORY ${PX4_SOURCE_DIR}
```
> **说明**：源码：kconfig.cmake:106 python -m genconfig --header-path ${PX4_BINARY_DIR}/px4_boardconfig.h。
^src-cmake-kconfig-cmake-106

<a id="src-cmake-kconfig-cmake-114"></a>
**↓ 文档在讲这里：**[`cmake/kconfig.cmake:114`](03-kconfig-bridge.md#^src-cmake-kconfig-cmake-114)

```c
   111 │ 	)
   112 │ 
   113 │ 	# parse board config options for cmake
▶  114 │ 	file(STRINGS ${BOARD_CONFIG} ConfigContents)
   115 │ 	foreach(NameAndValue ${ConfigContents})
   116 │ 		# Strip leading spaces
   117 │ 		string(REGEX REPLACE "^[ ]+" "" NameAndValue ${NameAndValue})
```
> **说明**：源码：cmake/kconfig.cmake:114 起，逐行 file(STRINGS) + 6 个 string(REGEX MATCH "^CONFIG_<前缀>")。
^src-cmake-kconfig-cmake-114

<a id="src-cmake-kconfig-cmake-130"></a>
**↓ 文档在讲这里：**[`cmake/kconfig.cmake:130`](03-kconfig-bridge.md#^src-cmake-kconfig-cmake-130)

```c
   127 │ 			string(REPLACE "\"" "" Value ${Value})
   128 │ 
   129 │ 			# Set the variable
▶  130 │ 			set(${Name} ${Value} CACHE INTERNAL "BOARD DEFCONFIG: ${Name}" FORCE)
   131 │ 
   132 │ 		else()
   133 │ 			# Find boolean not set
```
> **说明**：② 板级配置文件（= defconfig） | CONFIG_<NAME>=y | CONFIG_DRIVERS_DSHOT=y（boards/rm2027/fmu-h743/default.px4board:6） | python -m defconfig | ┃ ③ 翻译产物 A：CMake 变量 / 模块列表 | set(CONFIG_<NAME> y CACHE INTERNAL)、config_module_list += drivers/dshot | cmake/kconfig.cmake:130、:197-198 | CMake：if(CONFIG_…)、add_subdirectory |
^src-cmake-kconfig-cmake-130

<a id="src-cmake-kconfig-cmake-169"></a>
**↓ 文档在讲这里：**[`cmake/kconfig.cmake:169`](03-kconfig-bridge.md#^src-cmake-kconfig-cmake-169)

```c
   166 │ 		if(Drivers)
   167 │ 			# Find the value
   168 │ 			string(REPLACE "${Name}=" "" Value ${NameAndValue})
▶  169 │ 			string(REPLACE "CONFIG_DRIVERS_" "" driver ${Name})
   170 │ 			string(TOLOWER ${driver} driver)
   171 │ 
   172 │ 			string(REPLACE "_" "/" driver_path ${driver})
```
> **说明**：源码：kconfig.cmake:169。变形规则：
^src-cmake-kconfig-cmake-169

<a id="src-cmake-kconfig-cmake-197"></a>
**↓ 文档在讲这里：**[`cmake/kconfig.cmake:197`](03-kconfig-bridge.md#^src-cmake-kconfig-cmake-197)

```c
   194 │ 			string(REGEX REPLACE "(^[a-z]+)_([a-z0-9]+[a-z0-9]+)_([a-z0-9]+_[a-z0-9]+).*$" "\\3" driver_p5_subsubfolder ${driver})
   195 │ 
   196 │ 			# Trick circumvent PX4 src naming problem with underscores and slashes
▶  197 │ 			if(EXISTS ${PX4_SOURCE_DIR}/src/drivers/${driver})
   198 │ 				list(APPEND config_module_list drivers/${driver})
   199 │ 			elseif(EXISTS ${PX4_SOURCE_DIR}/src/drivers/${driver_path})
   200 │ 				list(APPEND config_module_list drivers/${driver_path})
```
> **说明**：然后按书写顺序试 7 个候选（kconfig.cmake:197），命中即 list(APPEND config_module_list ...)，全不中 ⇒ message(FATAL_ERROR "Couldn't find path for ${driver}")（:212）。
^src-cmake-kconfig-cmake-197

<a id="src-cmake-kconfig-cmake-463"></a>
**↓ 文档在讲这里：**[`cmake/kconfig.cmake:463`](03-kconfig-bridge.md#^src-cmake-kconfig-cmake-463)

```c
   460 │ endif()
   461 │ 
   462 │ 
▶  463 │ if(${LABEL} MATCHES "default" OR ${LABEL} MATCHES "bootloader" OR ${LABEL} MATCHES "canbootloader")
   464 │ 	add_custom_target(boardconfig
   465 │ 		${CMAKE_COMMAND} -E env ${COMMON_KCONFIG_ENV_SETTINGS} ${MENUCONFIG_PATH} Kconfig
   466 │ 		COMMAND ${CMAKE_COMMAND} -E env ${COMMON_KCONFIG_ENV_SETTINGS} ${SAVEDEFCONFIG_PATH}
```
> **说明**：kconfig.cmake:463 提供了 4 个 CMake target（不是 shell 命令，要 make）：
^src-cmake-kconfig-cmake-463

### `platforms/common/include/px4_platform_common/board_common.h`
<a id="src-platforms-common-include-px4-platform-common-board-common-h-50"></a>
**↓ 文档在讲这里：**[`platforms/common/include/px4_platform_common/board_common.h:50`](03-kconfig-bridge.md#^src-platforms-common-include-px4-platform-common-board-common-h-50)

```c
    47 │ #include <stdint.h>
    48 │ #include <stdbool.h>
    49 │ #include <string.h>
▶   50 │ #include <px4_boardconfig.h>
    51 │ /************************************************************************************
    52 │  * Definitions
    53 │  ************************************************************************************/
```
> **说明**：platforms/common/include/px4_platform_common/defines.h:43 ┃ platforms/common/include/px4_platform_common/board_common.h:50
^src-platforms-common-include-px4-platform-common-board-common-h-50

### `platforms/common/include/px4_platform_common/defines.h`
<a id="src-platforms-common-include-px4-platform-common-defines-h-43"></a>
**↓ 文档在讲这里：**[`platforms/common/include/px4_platform_common/defines.h:43`](03-kconfig-bridge.md#^src-platforms-common-include-px4-platform-common-defines-h-43)

```c
    40 │ #pragma once
    41 │ 
    42 │ #include <sys/ioctl.h>
▶   43 │ #include <px4_boardconfig.h>
    44 │ 
    45 │ 
    46 │ /****************************************************************************
```
> **说明**：platforms/common/include/px4_platform_common/px4_config.h:57 ┃ platforms/common/include/px4_platform_common/defines.h:43
^src-platforms-common-include-px4-platform-common-defines-h-43

### `platforms/common/include/px4_platform_common/px4_config.h`
<a id="src-platforms-common-include-px4-platform-common-px4-config-h-57"></a>
**↓ 文档在讲这里：**[`platforms/common/include/px4_platform_common/px4_config.h:57`](03-kconfig-bridge.md#^src-platforms-common-include-px4-platform-common-px4-config-h-57)

```c
    54 │ #endif
    55 │ 
    56 │ /* PX4 board kconfig symbols */
▶   57 │ #include <px4_boardconfig.h>
    58 │ 
```
> **说明**：谁 include 它（源码）： ┃ platforms/common/include/px4_platform_common/px4_config.h:57
^src-platforms-common-include-px4-platform-common-px4-config-h-57

### `platforms/nuttx/NuttX/nuttx/tools/Config.mk`
<a id="src-platforms-nuttx-NuttX-nuttx-tools-Config-mk-163"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/NuttX/nuttx/tools/Config.mk:163`](03-kconfig-bridge.md#^src-platforms-nuttx-NuttX-nuttx-tools-Config-mk-163)

```c
   160 │   CHIP_KCONFIG = $(TOPDIR)$(DELIM)arch$(DELIM)dummy$(DELIM)dummy_kconfig
   161 │ endif
   162 │ 
▶  163 │ # Process board-specific directories
   164 │ 
   165 │ ifeq ($(CONFIG_ARCH_BOARD_CUSTOM),y)
   166 │   CUSTOM_DIR = $(patsubst "%",%,$(CONFIG_ARCH_BOARD_CUSTOM_DIR))
```
> **说明**：1. platforms/nuttx/NuttX/nuttx/tools/Config.mk:163 — ARCH_BOARD_CUSTOM=y ⇒ :166 CUSTOM_DIR = $(patsubst "%",%,$(CONFIG_ARCH_BOARD_CUSTOM_DIR))、:168 BOARD_DIR = $(TOPDIR)/$(CUSTOM_DIR)
^src-platforms-nuttx-NuttX-nuttx-tools-Config-mk-163

### `platforms/nuttx/NuttX/nuttx/tools/Unix.mk`
<a id="src-platforms-nuttx-NuttX-nuttx-tools-Unix-mk-364"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/NuttX/nuttx/tools/Unix.mk:364`](03-kconfig-bridge.md#^src-platforms-nuttx-NuttX-nuttx-tools-Unix-mk-364)

```c
   361 │ 	@echo "CP: $@ to $(CHIP_KCONFIG)"
   362 │ 	$(Q) cp -f $(CHIP_KCONFIG) $@
   363 │ 
▶  364 │ # Copy $(BOARD_KCONFIG) to boards/dummy/Kconfig
   365 │ 
   366 │ boards/dummy/Kconfig:
   367 │ 	@echo "CP: $@ to $(BOARD_KCONFIG)"
```
> **说明**：3. :176-180 BOARD_KCONFIG = $(CUSTOM_BOARD_KPATH)（文件存在时；否则指向 boards/dummy/dummy_kconfig） ┃ 4. platforms/nuttx/NuttX/nuttx/tools/Unix.mk:364 — cp -f $(BOARD_KCONFIG) boards/dummy/Kconfig
^src-platforms-nuttx-NuttX-nuttx-tools-Unix-mk-364

### `src/drivers/dshot/Kconfig`
<a id="src-src-drivers-dshot-Kconfig-1"></a>
**↓ 文档在讲这里：**[`src/drivers/dshot/Kconfig:1`](03-kconfig-bridge.md#^src-src-drivers-dshot-Kconfig-1)

```c
▶    1 │ menuconfig DRIVERS_DSHOT
     2 │ 	bool "dshot"
     3 │ 	default n
     4 │ 	---help---
```
> **说明**：① Kconfig 声明 | menuconfig <NAME> + help | menuconfig DRIVERS_DSHOT（src/drivers/dshot/Kconfig:1） | 人（make boardconfig 的 TUI）；kconfiglib |
^src-src-drivers-dshot-Kconfig-1

### `src/drivers/imu/hipnuc_h104/Kconfig`
<a id="src-src-drivers-imu-hipnuc-h104-Kconfig-1"></a>
**↓ 文档在讲这里：**[`src/drivers/imu/hipnuc_h104/Kconfig:1`](03-kconfig-bridge.md#^src-src-drivers-imu-hipnuc-h104-Kconfig-1)

```c
▶    1 │ menuconfig DRIVERS_IMU_HIPNUC_H104
     2 │ 	bool "hipnuc h104 (serial IMU)"
     3 │ 	default n
     4 │ 	---help---
```
> **说明**：⇒ 本板的两个新驱动正是靠这个约定"零改上层"接进去的（src/drivers/imu/hxy/hxy42688p/Kconfig:1、src/drivers/imu/hipnuc_h104/Kconfig:1）。
^src-src-drivers-imu-hipnuc-h104-Kconfig-1

### `src/drivers/imu/hxy/hxy42688p/Kconfig`
<a id="src-src-drivers-imu-hxy-hxy42688p-Kconfig-1"></a>
**↓ 文档在讲这里：**[`src/drivers/imu/hxy/hxy42688p/Kconfig:1`](03-kconfig-bridge.md#^src-src-drivers-imu-hxy-hxy42688p-Kconfig-1)

```c
▶    1 │ menuconfig DRIVERS_IMU_HXY_HXY42688P
     2 │ 	bool "huaxuanyang hxy42688p"
     3 │ 	default n
     4 │ 	---help---
```
> **说明**：⇒ 本板的两个新驱动正是靠这个约定"零改上层"接进去的（src/drivers/imu/hxy/hxy42688p/Kconfig:1、src/drivers/imu/hipnuc_h104/Kconfig:1）。
^src-src-drivers-imu-hxy-hxy42688p-Kconfig-1

### `src/drivers/magnetometer/Kconfig`
<a id="src-src-drivers-magnetometer-Kconfig-2"></a>
**↓ 文档在讲这里：**[`src/drivers/magnetometer/Kconfig:2`](03-kconfig-bridge.md#^src-src-drivers-magnetometer-Kconfig-2)

```c
     1 │ menu "Magnetometer"
▶    2 │     menuconfig COMMON_MAGNETOMETER
     3 │         bool "Common Magnetometer's"
     4 │         default n
     5 │         select DRIVERS_MAGNETOMETER_AKM_AK8963
```
> **说明**：但可以写（kconfiglib 认），本板没写 ┃ select 出来的项不用写 —— 例如 default.px4board:33 CONFIG_COMMON_MAGNETOMETER=y 一行就带出 15 个磁罗盘驱动的 =y（src/drivers/magnetometer/Kconfig:2）
^src-src-drivers-magnetometer-Kconfig-2

<a id="src-src-drivers-magnetometer-Kconfig-22"></a>
**↓ 文档在讲这里：**[`src/drivers/magnetometer/Kconfig:22`](03-kconfig-bridge.md#^src-src-drivers-magnetometer-Kconfig-22)

```c
    19 │ 	select DRIVERS_MAGNETOMETER_VOLTAFIELD_AF9838
    20 │         ---help---
    21 │             Enable default set of magnetometer drivers
▶   22 │     rsource "*/Kconfig"
    23 │ endmenu
    24 │ 
```
> **说明**：src/drivers/imu/Kconfig | rsource "*/Kconfig" | ★ 收 src/drivers/imu/<子目录>/Kconfig ⇒ 新增 imu/hxy/ 不用改上层 | ┃ src/drivers/magnetometer/Kconfig:22 | rsource "*/Kconfig" | 同上 |
^src-src-drivers-magnetometer-Kconfig-22

### `src/drivers/pca9685_pwm_out/PCA9685.h`
<a id="src-src-drivers-pca9685-pwm-out-PCA9685-h-37"></a>
**↓ 文档在讲这里：**[`src/drivers/pca9685_pwm_out/PCA9685.h:37`](03-kconfig-bridge.md#^src-src-drivers-pca9685-pwm-out-PCA9685-h-37)

```c
    34 │ #pragma once
    35 │ #include <cstdint>
    36 │ #include <drivers/device/i2c.h>
▶   37 │ #include <px4_boardconfig.h>
    38 │ #include <px4_platform_common/i2c_spi_buses.h>
    39 │ 
    40 │ #define PCA9685_REG_MODE1 0x00			// Mode  register  1
```
> **说明**：platforms/common/include/px4_platform_common/board_common.h:50 ┃ 少数直接 include 的：src/drivers/pca9685_pwm_out/PCA9685.h:37、src/lib/adsb/AdsbConflict.h:37、src/lib/gnss/correction_framer.h:69
^src-src-drivers-pca9685-pwm-out-PCA9685-h-37

### `src/lib/adsb/AdsbConflict.h`
<a id="src-src-lib-adsb-AdsbConflict-h-37"></a>
**↓ 文档在讲这里：**[`src/lib/adsb/AdsbConflict.h:37`](03-kconfig-bridge.md#^src-src-lib-adsb-AdsbConflict-h-37)

```c
    34 │ #pragma once
    35 │ 
    36 │ // Provides CONFIG_NAVIGATOR_ADSB_F3442 for the standard selection.
▶   37 │ #include <px4_boardconfig.h>
    38 │ 
    39 │ #if defined(CONFIG_NAVIGATOR_ADSB_F3442) && CONFIG_NAVIGATOR_ADSB_F3442
    40 │ #include "f3442_standard/DaaF3442.h"
```
> **说明**：platforms/common/include/px4_platform_common/board_common.h:50 ┃ 少数直接 include 的：src/drivers/pca9685_pwm_out/PCA9685.h:37、src/lib/adsb/AdsbConflict.h:37、src/lib/gnss/correction_framer.h:69
^src-src-lib-adsb-AdsbConflict-h-37

### `src/lib/gnss/correction_framer.h`
<a id="src-src-lib-gnss-correction-framer-h-69"></a>
**↓ 文档在讲这里：**[`src/lib/gnss/correction_framer.h:69`](03-kconfig-bridge.md#^src-src-lib-gnss-correction-framer-h-69)

```c
    66 │ 
    67 │ #pragma once
    68 │ 
▶   69 │ #include <px4_boardconfig.h> // CONFIG_GPS_SPARTN
    70 │ 
    71 │ #include <cstdint>
    72 │ #include <cstddef>
```
> **说明**：platforms/common/include/px4_platform_common/board_common.h:50 ┃ 少数直接 include 的：src/drivers/pca9685_pwm_out/PCA9685.h:37、src/lib/adsb/AdsbConflict.h:37、src/lib/gnss/correction_framer.h:69
^src-src-lib-gnss-correction-framer-h-69
