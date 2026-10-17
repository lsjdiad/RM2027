# 00 · 构建走查：`make rm2027_fmu-h743_default` 的变量到底变成了什么

> 层：`03_moc/`（多维度入口）｜视角：**构建运行时**（不是文件清单）
> 源码基准：`源码根（见 `tools/source-root.conf`）`（= `<源码根>`，`桌面/RM2027` 是该目录的软链）
> 自查用的构建目录：`源码根（见 `tools/source-root.conf`）/build/rm2027_fmu-h743_default/`
> 上游来源：本文所有上游通用机制都来自 PX4 上游；本板"特有"的全部内容 = 1 个板级目录 `boards/rm2027/fmu-h743/` + 2 个新 IMU 驱动 + 1 个 `h104cap` 工具 + 1 个 `DEVTYPE`（见 §7）

---

## 0. 先说三件必须知道的事

### 0.1 这一篇要回答什么

用户的验收标准是"**展开**"：不是"这里配置了驱动"，而是

> **`CONFIG_DRIVERS_DSHOT=y` ⇒ 编入 `src/drivers/dshot/DShot.cpp`（还有两行）⇒ 生成参数 `PWM_MAIN_TIM0` / `DSHOT_MIN` / `DSHOT_MOT_POL1..12`。**

所以本文每一节都按同一模板写：**输入变量 → 在哪一步被读 → 变成了什么值 → 谁吃了它**。

### 0.2 ⚠️ 构建目录不是"当前 HEAD"的产物（重要）

| 事实 | 值 | 依据 |
|---|---|---|
| 构建目录里的固件来自哪个 commit | **`4e910b6`** | `.px4` 头部 `git_identity=4e910b6` / `git_hash=4e910b61…`（`firmware.prototype` + `Tools/px_mkfw.py` 注入） |
| 当前 checkout 的 HEAD | **`3b5de24`**（分支 `teaching/minimal-path`） | `git log -1` |
| 两者差多少 | **只有 1 个文件**：`src/drivers/imu/hxy/hxy42688p/HXY42688P.cpp`（+26/−1，chip Y 增益修正） | `git diff --stat 4e910b6 HEAD` |
| 对"构建变量展开"有没有影响 | **没有**。Kconfig / CMakeLists / `default.px4board` 三者一字未改 | `git diff --name-only 4e910b6 HEAD` 只列出这一个文件 |

⇒ **本文里的"构建产物"数值（行数、字节数、参数默认值）都是 `4e910b6` 那次构建的实测值**，对当前源码仍然成立（除非改 `default.px4board`）。
⇒ 但 `build/…/etc/init.d/rc.board_sensors`（123 B）反映的是 **10-01 那版板级脚本**；源文件今天被重写成 8942 B（只加了注释），**内容命令完全一致**（见 §5.2）。

### 0.3 三层标注约定

| 标记 | 含义 |
|---|---|
| **实测** | 直接读已生成的构建产物 / 可执行文件得到 |
| **源码** | 有 `file:line` 可查 |
| **推理** | 我的推断，标注了依据，但没实测 |

---

## 1. 执行序入口：`make` 只做两件事

```
$ make rm2027_fmu-h743_default
        │
        ├─(A) 目标名 → 找到板级配置文件
        └─(B) 配置 + 构建
```

### 1.1 (A) `rm2027_fmu-h743_default` 这个名字是**扫出来的**，不是写死的

> **★ 行号级详解在 02 层**：`Makefile:237/244/248` 这几行**逐行在干什么、为什么关键**，
> 见 [`02_code_twin/build/Makefile`](../02_code_twin/build/Makefile.md)（本篇只讲流程）。


- **源码**：[`Makefile:237`](../tools/README.md#^src-Makefile-237) — `ALL_CONFIG_TARGETS := $(shell find boards -maxdepth 3 -mindepth 3 -name '*.px4board' -print | sed …)`
- 扫到的路径：`boards/rm2027/fmu-h743/default.px4board` → 去掉 `boards/`、去掉 `.px4board`、`/`→`_` ⇒ **`rm2027_fmu-h743_default`**
- **源码**：[`Makefile:244`](../02_code_twin/build/Makefile.md#^src-Makefile-244) — `$(ALL_CONFIG_TARGETS): @$(call cmake-build,$@$(BUILD_DIR_SUFFIX))`
- **源码**：`Makefile:248` — 额外规则：`%_default` 可省略后缀，所以 `make rm2027_fmu-h743` 也能编（`CONFIG_TARGETS_DEFAULT`）

> ⇒ **新增一块板 = 新增一个 `boards/<vendor>/<model>/default.px4board`，`make <vendor>_<model>_default` 自动可用。** 不需要改 Makefile。

### 1.2 (B) `cmake-build` 宏：5 步

**源码 [`Makefile:179`](../02_code_twin/build/Makefile.md#^src-Makefile-179)**，逐步：

| 步 | 行号 | 干了什么 | 本板的实际值 |
|---|---|---|---|
| 1 | `:183` | `override CMAKE_ARGS += -DCONFIG=$(patsubst %$(BUILD_DIR_SUFFIX),%,$(1))` | `-DCONFIG=rm2027_fmu-h743_default` |
| 2 | `:184` | `BUILD_DIR = "$(SRC_DIR)/build/$(1)"` | `…/build/rm2027_fmu-h743_default` |
| 3 | `:196-200` | 若 `build/.last_target` ≠ 本目标 → `git clean -dXfq` 清 NuttX 两个子模块 | 本次没触发（`build/.last_target` 里就是本目标） |
| 4 | `:206-211` | **仅当** `build/…/CMakeCache.txt` 不存在（或缓存选项对不上）时 `cmake <src> -G"Ninja" -DCONFIG=…` | 已存在 ⇒ 跳过配置，直接走 5 |
| 5 | `:213` | `cmake --build $(BUILD_DIR) -- $(PX4_MAKE_ARGS) $(ARGS)` | 就是 `ninja` |

**生成器是 Ninja 不是 Make**：`Makefile:85` 先探测 `ninja --version`，成功则 `PX4_CMAKE_GENERATOR := Ninja`、`PX4_MAKE := ninja`。（**实测**：`build/rm2027_fmu-h743_default/build.ninja` 6,199,786 B 存在，且目录里没有 `Makefile`。）
**源码**：`Makefile:202` 若探测到旧的非 Ninja 构建目录会 `rm -rf` 重来。

⇒ **`make` 只是"配置一次 + 交给 ninja"的壳。** 真正的变量展开下面才开始。

### 1.3 顺带：另外两个 label 也是同一个板

`boards/rm2027/fmu-h743/bootloader.px4board` ⇒ `make rm2027_fmu-h743_bootloader`，产出 `extras/rm2027_fmu-h743_bootloader.bin`。

---

## 2. 阶段一：CMake 配置期 —— `CONFIG` 这一个字符串怎么变成 14 个板型变量

**入口**：[`CMakeLists.txt:202`](../02_code_twin/build/CMakeLists.md#^src-CMakeLists-txt-202) `include(px4_config)`。
**全部逻辑在** `cmake/px4_config.cmake`。
(x)02里面为什么没有cmake/px4_config.cmake放在build里买年了??
(x)`
### 2.1 逐跳展开（本板的真实取值）

| #   | 变量                                                         | 值                                                                        | 出处                                                                                                                                                                                                   |
| --- | ---------------------------------------------------------- | ------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | `CONFIG`                                                   | `rm2027_fmu-h743_default`                                                | 来自 `-D`（[`Makefile:183`](../01_extracted/make/gnu-make-syntax.md#^src-Makefile-183)）；[`px4_config.cmake:44`](../02_code_twin/build/cmake-kconfig.md#^src-cmake-px4-config-cmake-44) 提升为 CACHE STRING |
| 2   | `PX4_SOURCE_DIR`                                           | `<源码根>`                                                                  | [`CMakeLists.txt:104`](../02_code_twin/build/cmake-kconfig.md#^src-CMakeLists-txt-104)                                                                                                               |
| 3   | `PX4_BINARY_DIR`                                           | `<源码根>/build/rm2027_fmu-h743_default`                                    | [`CMakeLists.txt:105`](../02_code_twin/build/cmake-kconfig.md#^src-CMakeLists-txt-105)                                                                                                               |
| 4   | `board_configs`                                            | `rm2027/fmu-h743/bootloader.px4board`、`rm2027/fmu-h743/default.px4board` | [`px4_config.cmake:53`](../02_code_twin/build/cmake-kconfig.md#^src-cmake-px4-config-cmake-53) `file(GLOB_RECURSE …)`                                                                                |
| 5   | `vendor;model;label`                                       | `rm2027` / `fmu-h743` / `default`                                        | `:61-68`（按 `/` 切三段，`list(LENGTH)==3`）                                                                                                                                                                |
| 6   | `board`                                                    | `rm2027fmu-h743`                                                         | `:70`                                                                                                                                                                                                |
| 7   | 匹配成功                                                       | 第 5 跳和 `CONFIG` 相等 ⇒ `break()`                                           | `:74-83`                                                                                                                                                                                             |
| 8   | `PX4_CONFIG_FILE`                                          | `…/boards/rm2027/fmu-h743/default.px4board`                              | `:77`                                                                                                                                                                                                |
| 9   | `PX4_BOARD_DIR`                                            | `…/boards/rm2027/fmu-h743`                                               | `:78`                                                                                                                                                                                                |
| 10  | `MODEL` / `VENDOR` / `LABEL`                               | `fmu-h743` / `rm2027` / `default`                                        | `:79-81`                                                                                                                                                                                             |
| 11  | `PX4_BOARD`                                                | `rm2027_fmu-h743`                                                        | `:105`（`${VENDOR}_${MODEL}`）                                                                                                                                                                         |
| 12  | `PX4_BOARD_NAME`                                           | **`RM2027_FMU_H743`**                                                    | `:108-110`（大写 + `-`→`_`）                                                                                                                                                                             |
| 13  | `PX4_BOARD_VENDOR` / `PX4_BOARD_MODEL` / `PX4_BOARD_LABEL` | `rm2027` / `fmu-h743` / `default`                                        | `:112-115`                                                                                                                                                                                           |
| 14  | `PX4_CONFIG`                                               | `rm2027_fmu-h743_default`                                                | `:117`                                                                                                                                                                                               |

**两个立刻生效的副作用**：

- [`px4_config.cmake:103`](../02_code_twin/build/CMakeLists.md#^src-cmake-px4-config-cmake-103) `include_directories(${PX4_BOARD_DIR}/src)`
  ⇒ **实测**：`build/…/compile_commands.json` 里每个编译单元都带 `-I<源码根>/boards/rm2027/fmu-h743/src`，所以板级头文件（`board_config.h`/`hw_config.h`）能被任意驱动 `#include`。
- [`cmake/px4_add_common_flags.cmake:195`](../02_code_twin/build/cmake-kconfig.md#^src-cmake-px4-add-common-flags-cmake-195) `add_definitions(-DCONFIG_ARCH_BOARD_${PX4_BOARD_NAME})`
  ⇒ **实测**：编译命令行里出现 `-DCONFIG_ARCH_BOARD_RM2027_FMU_H743`。
  ⇒ 这是板型第 12 跳的直接落地：**所有代码里 `#ifdef CONFIG_ARCH_BOARD_RM2027_FMU_H743` 就是靠这一行**。
(x)px4config 和kconfig不应该是两个文件吗
> **这里唯一"本板特有"的东西**：`boards/rm2027/fmu-h743/default.px4board` 这一个文件的存在。**其余 14 跳全是上游通用逻辑**。
> ⇒ **跳转**：这 14 个变量后面谁在用？下一节（Kconfig 桥）用 `PX4_CONFIG_FILE`、`PX4_BOARD_DIR`、`PX4_BOARD_VENDOR/MODEL/LABEL`；`01_extracted/cmake/03-kconfig-bridge.md` 有这张桥的完整词典。
> ⇒ 更细的"`px4_add_module` / `add_subdirectory` 分工"见 `[01_extracted/cmake/01-px4-cmake-organization](../01_extracted/cmake/01-px4-cmake-organization.md)`。

---

## 3. 阶段二：Kconfig —— `default.px4board` 的 98 行怎么变成 760 行 + 182 行头文件

**入口**：[`CMakeLists.txt:203`](../02_code_twin/build/CMakeLists.md#^src-CMakeLists-txt-203) `include(kconfig)`。**全部逻辑在** `cmake/kconfig.cmake`。

### 3.1 三个中间产物，先记名字

| 变量 | 值 | 出处 |
|---|---|---|
| `BOARD_DEFCONFIG` | `<src>/boards/rm2027/fmu-h743/default.px4board` | [`kconfig.cmake:1`](../02_code_twin/build/cmake-kconfig.md#^src-cmake-kconfig-cmake-1) |
| `BOARD_CONFIG` | `build/rm2027_fmu-h743_default/boardconfig` | `:2` |
| `px4_boardconfig.h` | `build/rm2027_fmu-h743_default/px4_boardconfig.h` | `:108` |

### 3.2 第 1 跳：`default.px4board` → `boardconfig`（**98 行 → 760 行**）

- [`kconfig.cmake:74`](../02_code_twin/build/cmake-kconfig.md#^src-cmake-kconfig-cmake-74)：因为 `LABEL == "default"`，走 **true** 分支
- `:76-81`：`python -m defconfig <default.px4board>`，环境变量 `KCONFIG_CONFIG=boardconfig`（`:51`）
- 结果落盘：`build/rm2027_fmu-h743_default/boardconfig`

**推理依据**：`defconfig` 是 kconfiglib 的命令 —— 它按 **Kconfig 语法树**把省略项补默认值、把 `select` 依赖展开。所以**你在 `.px4board` 里只写 98 行，Kconfig 树替你补到 760 行**。
**实测**（本板 4 个例子）：

| 你在 `.px4board` 写的 | `boardconfig` 里多出来的（你没写、被 `select` 出来的） | `boardconfig` 行 |
|---|---|---|
| `default.px4board:33 CONFIG_COMMON_MAGNETOMETER=y` | `CONFIG_DRIVERS_MAGNETOMETER_AKM_AK8963/…/BMM150/BMM350/HMC5883/QMC5883L/QMC5883P/IST8308/IST8310/LIS3MDL/LSM303AGR/RM3100/MMC5983MA/IIS2MDC/AF9838` 全部 `=y` | [`src/drivers/magnetometer/Kconfig:2`](../02_code_twin/build/drivers-build.md#^src-src-drivers-magnetometer-Kconfig-2) 是 15 条 `select` |
| `:55 CONFIG_MODULES_DATAMAN=y` | `CONFIG_DATAMAN_PERSISTENT_STORAGE=1`、`CONFIG_NUM_MISSION_ITEMS_SUPPORTED=500`（都是 `default y`/`default 500` + `depends on MODULES_DATAMAN`） | [`px4_boardconfig.h:61`](../02_code_twin/build/artifacts.md#^src-build-rm2027-fmu-h743-default-px4-boardconfig-h-61)；[`src/modules/dataman/Kconfig:16`](../02_code_twin/build/drivers-build.md#^src-src-modules-dataman-Kconfig-16) |
| `:50 CONFIG_COMMON_TELEMETRY=y` | `CONFIG_DRIVERS_TELEMETRY_BST/FRSKY_TELEMETRY/HOTT` | `boardconfig:445` 起；[`px4_boardconfig.h:54`](../02_code_twin/build/artifacts.md#^src-build-rm2027-fmu-h743-default-px4-boardconfig-h-54) |
| `:56 CONFIG_MODULES_EKF2=y` | `CONFIG_EKF2_MULTI_INSTANCE/AIRSPEED/AUX_GLOBAL_POSITION/BAROMETER/MAGNETOMETER/WIND/…` 一大串 | [`px4_boardconfig.h:60`](../02_code_twin/build/artifacts.md#^src-build-rm2027-fmu-h743-default-px4-boardconfig-h-60) 一带 |

> ★ 这条对用户最直接：**`default.px4board` 里的一行 `=y` 可能换来十几行 `.config` + 十几个 `#define`。** 想知道某行"膨胀成什么"，看 `build/…/boardconfig`（760 行，带 Kconfig 分节注释）。

### 3.3 第 2 跳：`boardconfig` → `px4_boardconfig.h`（**760 行 → 182 行：只剩宏，没有 Kconfig 注释**）

- [`kconfig.cmake:106`](../02_code_twin/build/cmake-kconfig.md#^src-cmake-kconfig-cmake-106)：`python -m genconfig --header-path build/…/px4_boardconfig.h`
- **实测**：`build/…/px4_boardconfig.h` **182 行，且 `grep -c "^#define"` 也是 182** ⇒ 每一行都是一个 `#define CONFIG_X 1` / `#define CONFIG_X "值"`，Kconfig 的分节注释一条不剩
- 谁 `#include` 它：[`platforms/common/include/px4_platform_common/px4_config.h:57`](../02_code_twin/build/others.md#^src-platforms-common-include-px4-platform-common-px4-config-h-57)、`…/defines.h:43`、`…/board_common.h:50`
  ⇒ 所以 **任何 PX4 源文件只要 include 了 `px4_config.h`（几乎都 include），就能 `#ifdef CONFIG_DRIVERS_DSHOT`**。

**实测**（本板关心项）：

| `px4_boardconfig.h` 行 | 内容 |
|---|---|
| `:4` | `#define CONFIG_BOARD_ARCHITECTURE "cortex-m7"` |
| `:15` | `#define CONFIG_BOARD_SERIAL_TEL1 "/dev/ttyS2"` |
| `:26` | `#define CONFIG_DRIVERS_BAROMETER_GOERTEK_SPA06 1` |
| `:27` | `#define CONFIG_DRIVERS_DSHOT 1` |
| `:28` | `#define CONFIG_DRIVERS_IMU_HIPNUC_H104 1` |
| `:29` | `#define CONFIG_DRIVERS_IMU_HXY_HXY42688P 1` |
| `:42` | `#define CONFIG_DRIVERS_MAGNETOMETER_ISENTEK_IST8310 1` |
| `:51` | `#define CONFIG_DRIVERS_PWM_OUT 1` |
| `:111` | `#define CONFIG_MODULES_SENSORS 1` |
| `:137` | `#define CONFIG_ARCH_CHIP_STM32H7 1` |

### 3.4 第 3 跳：`boardconfig` → `config_module_list`（**"编哪些源文件"就靠这一步**）

[`kconfig.cmake:114`](../02_code_twin/build/cmake-kconfig.md#^src-cmake-kconfig-cmake-114) `file(STRINGS ${BOARD_CONFIG} ConfigContents)` —— **逐行文本解析**，然后按**变量名前缀**分 6 类处理：

| 前缀 | 行号 | 干什么 | 结果 |
|---|---|---|---|
| `CONFIG_BOARD_*` | `:142-150` | 去掉 `CONFIG_BOARD_` 当 cmake 变量 | `SERIAL_TEL1`、`ROMFSROOT`、`PARAM_FILE`、`ROOT_PATH`…（随后 `:324-375` 组装 `board_serial_ports` / `config_romfs_root`） |
| `CONFIG_USER_*` | `:153-161` | 追加到 `config_user_list`（protected build 用） | 本板 `CONFIG_BOARD_PROTECTED` 未开 ⇒ 不用 |
| `CONFIG_DRIVERS_*` | `:164-214` | ★ **把宏名反推成源目录** | 见 §3.5 |
| `CONFIG_MODULES_*` | `:217-247` | 同上，查 `src/modules/` | 见 §3.5 |
| `CONFIG_SYSTEMCMDS_*` | `:250-259` | 直接拼 `systemcmds/<小写名>` | `h104cap`、`param`、`top`… |
| `CONFIG_EXAMPLES_*` | `:262-271` | 拼 `examples/<小写名>` | 本板无 |
| 兜底 | `:130` | 所有 `CONFIG_*` 无条件 `set(... CACHE INTERNAL)` | ⇒ CMake 里可以直接 `if(CONFIG_DRIVERS_DSHOT)` |

### 3.5 ★ `CONFIG_DRIVERS_*` → 源目录：宏名是按"路径猜"出来的

[`kconfig.cmake:169`](../02_code_twin/build/cmake-kconfig.md#^src-cmake-kconfig-cmake-169) 先做字符串变形：

```
CONFIG_DRIVERS_DSHOT               → driver = "dshot"
CONFIG_DRIVERS_IMU_HXY_HXY42688P   → driver = "imu_hxy_hxy42688p"
CONFIG_DRIVERS_IMU_HIPNUC_H104     → driver = "imu_hipnuc_h104"
```

然后 `:172` `driver_path` = 把 `_` 换成 `/`；接着 `:197-213` **按顺序试 7 种候选路径，命中即用，全不中就 `FATAL_ERROR "Couldn't find path for …"`（`:212`）**。

**本板 5 个真实展开**（每个都实测命中）：

| `.px4board` 行 | `driver` | 命中的候选 / 行号 | 实际路径 | `config_module_list` 元素 |
|---|---|---|---|---|
| `:6 CONFIG_DRIVERS_DSHOT=y` | `dshot` | 候选① `src/drivers/dshot` / `:197-198` | 同名目录 | `drivers/dshot` |
| `:48 CONFIG_DRIVERS_PWM_OUT=y` | `pwm_out` | 候选① / `:197-198` | 同名目录 | `drivers/pwm_out` |
| `:22 CONFIG_DRIVERS_IMU_HXY_HXY42688P=y` | `imu_hxy_hxy42688p` | 候选② `driver_path` = `imu/hxy/hxy42688p` / `:199-200` | `src/drivers/imu/hxy/hxy42688p` | `drivers/imu/hxy/hxy42688p` |
| `:24 CONFIG_DRIVERS_IMU_HIPNUC_H104=y` | `imu_hipnuc_h104` | 候选② ✗（`imu/hipnuc/h104` 不存在）→ 候选③ `p3` ✗ → **候选④ `p1`**：`folder=imu` `subfolder=hipnuc_h104` / `:203-204` | `src/drivers/imu/hipnuc_h104` | `drivers/imu/hipnuc_h104` |
| `:5 CONFIG_DRIVERS_BAROMETER_GOERTEK_SPA06=y` | `barometer_goertek_spa06` | 候选② `driver_path` = `barometer/goertek/spa06` / `:199-200` | `src/drivers/barometer/goertek/spa06` | `drivers/barometer/goertek/spa06` |
| `:47 CONFIG_DRIVERS_MAGNETOMETER_ISENTEK_IST8310=y` | `magnetometer_isentek_ist8310` | 候选② `driver_path` = `magnetometer/isentek/ist8310` / `:199-200` | `src/drivers/magnetometer/isentek/ist8310` | `drivers/magnetometer/isentek/ist8310` |

> 上表后两行的"命中路径"**实测**依据：`build/rm2027_fmu-h743_default/config_module_list.txt` 里没有 `goertek_spa06` / `isentek_ist8310` 这种"扁平化"路径，只有三段式的 `src/drivers/barometer/goertek/spa06`（第 74/75 行）与 `src/drivers/magnetometer/isentek/ist8310`（第 104/105 行） ⇒ 只有候选② 成立。
> ⚠️ 该 txt 严格说不是 `config_module_list`，而是 **`PX4_MODULE_PATHS`**（[`cmake/sbom.cmake:44`](../02_code_twin/build/cmake-kconfig.md#^src-cmake-sbom-cmake-44)）。它作为证据仍然有效：凡是出现在这里的目录都被 `px4_add_module`/`px4_add_library` 注册过。每个路径**出现两次**是因为 [`px4_add_module.cmake:178`](../02_code_twin/build/cmake-kconfig.md#^src-cmake-px4-add-module-cmake-178) 和 `:183` 各 append 了一次。

### 3.6 第 4 跳：`config_module_list` 末尾被追加了"板级 src"

- [`kconfig.cmake:454`](../02_code_twin/board/README.md#^src-cmake-kconfig-cmake-454)
  - `file(RELATIVE_PATH board_support_src_rel ${PX4_SOURCE_DIR}/src ${PX4_BOARD_DIR})` ⇒ `../boards/rm2027/fmu-h743`
  - `list(APPEND config_module_list ../boards/rm2027/fmu-h743/src)`
- 于是 [`CMakeLists.txt:480`](../02_code_twin/build/cmake-kconfig.md#^src-CMakeLists-txt-480) 的 `foreach(module ${config_module_list}) add_subdirectory(src/${module})` 会展开出 `add_subdirectory(src/../boards/rm2027/fmu-h743/src)`
  ⇒ 编译 [`boards/rm2027/fmu-h743/src/CMakeLists.txt:47`](../02_code_twin/build/board-build.md#^src-boards-rm2027-fmu-h743-src-CMakeLists-txt-47) 列的 6 个文件（`i2c.cpp` `init.c` `led.c` `spi.cpp` `timer_config.cpp` `usb.c`）成静态库 **`drivers_board`**

> **★ 源码级事实**：`boards/rm2027/fmu-h743/CMakeLists.txt` **不存在**（`find` 已确认）。
> ⇒ [`CMakeLists.txt:476`](../02_code_twin/build/cmake-kconfig.md#^src-CMakeLists-txt-476) 的 `if(EXISTS "${PX4_BOARD_DIR}/CMakeLists.txt") add_subdirectory(${PX4_BOARD_DIR})` **本板不触发**。
> ⇒ 板级代码**唯一**入口是 §3.6 这一条 `config_module_list` 追加。
> **推理**：所以"板级 src 目录名必须叫 `src`"是硬约束（`:454-455` 写死了 `/src`）。
> **另注**：`src/drivers/imu/hxy/CMakeLists.txt`（内容只有 `add_subdirectory(hxy42688p)`）**不在** `config_module_list` 路径上 —— `config_module_list` 给的是叶子目录 `drivers/imu/hxy/hxy42688p`。**推理**：该文件对本构建是死代码（`src/drivers/` 与 `src/drivers/imu/` 都没有 `CMakeLists.txt`，已 `ls` 确认）。

---

## 4. ★★ 板型 → 宏 → 源文件 → 参数 对照表（本板真实例子）

**谁把 §3.6 的 `config_module_list` 变成"编哪些 `.cpp`"**：
[`CMakeLists.txt:480`](../02_code_twin/build/cmake-kconfig.md#^src-CMakeLists-txt-480) → 每个模块目录的 `CMakeLists.txt` 里 `px4_add_module(...)`（[`cmake/px4_add_module.cmake:84`](../02_code_twin/build/cmake-kconfig.md#^src-cmake-px4-add-module-cmake-84)）→ `:151` `add_library(... STATIC EXCLUDE_FROM_ALL ${SRCS})`。

### 4.1 `CONFIG_DRIVERS_DSHOT=y` 完整展开（本表是本轮的核心）

| 跳 | 事实 | 出处 |
|---|---|---|
| ① 板级开关 | `CONFIG_DRIVERS_DSHOT=y` | [`boards/rm2027/fmu-h743/default.px4board:6`](../02_code_twin/build/board-build.md#^src-boards-rm2027-fmu-h743-default-px4board-6) |
| ② Kconfig 声明 | `menuconfig DRIVERS_DSHOT` / `bool "dshot"` / `default n` | [`src/drivers/dshot/Kconfig:1`](../02_code_twin/build/drivers-build.md#^src-src-drivers-dshot-Kconfig-1) |
| ③ 解析进 boardconfig | `CONFIG_DRIVERS_DSHOT=y` | `build/rm2027_fmu-h743_default/boardconfig:174` |
| ④ 编译宏 | `#define CONFIG_DRIVERS_DSHOT 1` | [`build/rm2027_fmu-h743_default/px4_boardconfig.h:27`](../02_code_twin/build/artifacts.md#^src-build-rm2027-fmu-h743-default-px4-boardconfig-h-27) |
| ⑤ 源目录 | `config_module_list += drivers/dshot` | [`kconfig.cmake:197`](../02_code_twin/build/cmake-kconfig.md#^src-cmake-kconfig-cmake-197) |
| ⑥ 编译单元（**实测** `build.ninja`） | `src/drivers/dshot/CMakeFiles/drivers__dshot.dir/DShot.cpp.obj`、`…/DShotTelemetry.cpp.obj`、`…/esc/AM32Settings.cpp.obj` | [`src/drivers/dshot/CMakeLists.txt:47`](../02_code_twin/build/drivers-build.md#^src-src-drivers-dshot-CMakeLists-txt-47) |
| ⑦ 附带平台库 | `arch_dshot`（`platforms/nuttx/src/px4/stm/stm32_common/dshot/dshot.c`）被 `DEPENDS arch_dshot` 拉进来 | [`src/drivers/dshot/CMakeLists.txt:51`](../02_code_twin/build/drivers-build.md#^src-src-drivers-dshot-CMakeLists-txt-51) + [`platforms/nuttx/src/px4/stm/stm32_common/dshot/CMakeLists.txt:34`](../02_code_twin/build/nuttx-build.md#^src-platforms-nuttx-src-px4-stm-stm32-common-dshot-CMakeLists-txt-34) |
| ⑧ 编译期宏 | `-DMODULE_NAME=\"dshot\"` `-DPX4_MAIN=dshot_app_main` `-DPARAM_PREFIX=\"PWM_MAIN\"` | [`px4_add_module.cmake:215`](../02_code_twin/build/cmake-kconfig.md#^src-cmake-px4-add-module-cmake-215) / `:214` + `src/drivers/dshot/CMakeLists.txt:34,43-44`（**实测**见 `compile_commands.json`） |
| ⑨ 启动项注册 | `{ "dshot", SCHED_PRIORITY_DEFAULT, 2048 * (__SIZEOF_POINTER__ >> 2), dshot_main }` 出现在 `platforms/nuttx/NuttX/apps/builtin/registry/px4.bdat` | `platforms/nuttx/NuttX/CMakeLists.txt:90-102,137-138,153-159`（**实测** grep 到该行） |
| ⑩ 生成的参数 | `DSHOT_ESC_TYPE`(0) `DSHOT_MIN`(0.055) `DSHOT_3D_ENABLE` `DSHOT_BIDIR_EDT` `DSHOT_3D_DEAD_H/L` `DSHOT_MOT_POL1..12`(14) `DSHOT_TEL_CFG` | [`src/drivers/dshot/module.yaml:8`](../02_code_twin/build/drivers-build.md#^src-src-drivers-dshot-module-yaml-8) → `build/…/generated_params/module_params.c:1827,1844,1859,1873,1887,1901,1917…2093` |

> ★ **`DSHOT_MOT_POL1..12` 是 12 个，不是 4 个** —— 因为它的实例数来自 `module.yaml:90 num_instances: 12`，**与板子有几路输出无关**。
> 对比 `PWM_MAIN_FUNC1..4` 是 4 个 —— 它来自板级 `timer_config.cpp` 的通道数。**这就是"上游通用"与"板型相关"的分界线。**

### 4.2 `PWM_MAIN_*` / `CONFIG_DRIVERS_PWM_OUT=y` 完整展开（★ 用户已知事实的机制）

| 跳 | 事实 | 出处 |
|---|---|---|
| ① 板级 | `CONFIG_DRIVERS_PWM_OUT=y` | [`default.px4board:48`](../02_code_twin/build/board-build.md#^src-boards-rm2027-fmu-h743-default-px4board-48) |
| ② boardconfig / 头 | `boardconfig:398` / [`px4_boardconfig.h:51`](../02_code_twin/build/artifacts.md#^src-build-rm2027-fmu-h743-default-px4-boardconfig-h-51) | — |
| ③ 源目录 | `drivers/pwm_out` | [`kconfig.cmake:197`](../02_code_twin/build/cmake-kconfig.md#^src-cmake-kconfig-cmake-197) |
| ④ 编译单元（**实测**） | `PWMOut.cpp.obj` | `src/drivers/pwm_out/CMakeLists.txt` `SRCS PWMOut.cpp` |
| ⑤ PARAM_PREFIX | `-DPARAM_PREFIX="PWM_MAIN"`（若 `CONFIG_BOARD_IO` 才是 `PWM_AUX`，本板不是） | `src/drivers/pwm_out/CMakeLists.txt` `:34-38` |
| ⑥ 参数**生成** | `generate_params.py --timer-config boards/rm2027/fmu-h743/src/timer_config.cpp --config-files <含 pwm_out/module.yaml + mixer_module/params.yaml>` | [`src/lib/parameters/CMakeLists.txt:86`](../02_code_twin/build/drivers-build.md#^src-src-lib-parameters-CMakeLists-txt-86) |
| ⑦ 定时器分组 | `io_timers[]` 只有 1 项（Timer1）⇒ `timer_index=0`；`timer_io_channels[]` 有 4 路（TIM1_CH1..CH4 = PA8/PE11/PE13/PE14）⇒ 1 组 4 通道 | [`boards/rm2027/fmu-h743/src/timer_config.cpp:52`](../02_code_twin/build/board-build.md#^src-boards-rm2027-fmu-h743-src-timer-config-cpp-52)；分组算法 [`Tools/module_config/output_groups_from_timer_config.py:133`](../02_code_twin/build/romfs-and-tools.md#^src-Tools-module-config-output-groups-from-timer-config-py-133) |
| ⑧ 参数名 = 前缀+索引 | `PWM_MAIN_TIM0`（`:187` `param_prefix+'_TIM'+str(timer_index)`）、`PWM_MAIN_FUNC1..4` / `DIS/MIN/CENT/MAX/FAIL1..4` / `REV` | [`output_groups_from_timer_config.py:187`](../02_code_twin/build/romfs-and-tools.md#^src-Tools-module-config-output-groups-from-timer-config-py-187) + [`mixer_module.cpp:117`](../02_code_twin/build/drivers-build.md#^src-src-lib-mixer-module-mixer-module-cpp-117) |
| ⑨ `PWM_MAIN_TIM0` 的**默认值 400** | `pwm_timer_param.default: 400` | [`src/drivers/pwm_out/module.yaml:22`](../02_code_twin/build/drivers-build.md#^src-src-drivers-pwm-out-module-yaml-22) |
| ⑩ 生成产物（**实测**） | `PARAM_DEFINE_INT32(PWM_MAIN_TIM0, 400);` @ [`module_params.c:2164`](../02_code_twin/drivers/dshot.md#^src-build-rm2027-fmu-h743-default-generated-params-module-params-c-2164)；`PWM_MAIN_FUNC1, 0` @ `:2243`；`PWM_MAIN_FUNC4, 0` @ `:2480`；本板共 **26 个** `PWM_MAIN_*` 参数 | `build/…/generated_params/module_params.c` |
| ⑪ 运行时谁读它 | `snprintf(param_name, "%s_TIM%u", _mixing_output.paramPrefix(), timer_index)` → [`DShot.cpp:1086`](../02_code_twin/build/drivers-build.md#^src-src-drivers-dshot-DShot-cpp-1086)、[`PWMOut.cpp:73`](../02_code_twin/build/drivers-build.md#^src-src-drivers-pwm-out-PWMOut-cpp-73) | — |

**★ 而这 26 个参数的默认值决定了"实际编出什么"**（这正是用户给的已知事实的来源）：

```
PWM_MAIN_TIM0 = 400                      （默认，module_params.c:2164）
      │
      ├─ DShot.cpp:1088-1110  param_get("PWM_MAIN_TIM0")
      │      switch(400): 只认 -8/-7/-6/-5/-4/-3（DShot.h:59-64），400 落到 default: → freq = 0
      │      ⇒ DShot.cpp:1126-1128  `if (dshot_timer_channels == 0) { PX4_INFO("No channels configured"); return false; }`
      │      ⇒ **DShot 模块虽然被编进固件、也被 rcS:559 拉起，但 4 路输出一个都不归它管**
      │
      └─ PWMOut.cpp:73-83  同一个参数字符串 → _timer_rates[0] = 400
             ⇒ **输出是 PWM 400 Hz**（不是 DShot）
```

⇒ **这就是"`PWM_MAIN_TIM0` 默认 400 = PWM 400Hz，不是 DShot"的完整机制**（**结论 = 源码，数值 = 实测**）。
⇒ 要把 4 路改成 DShot600：把 `PWM_MAIN_TIM0` 从 `400` 改成 `-3`（`DShot.h:61 TIM_CONFIG_DSHOT600 = -3`）。**这一条不改 `.px4board`、不用重编、运行期 `param set` 即可**（但 `module.yaml:35 reboot_required: true` ⇒ **要重启**）。
⇒ 而 `PWM_MAIN_FUNC1..4 = 0`（`= Disabled`，[`module_params.c:2243`](../02_code_twin/build/artifacts.md#^src-build-rm2027-fmu-h743-default-generated-params-module-params-c-2243)）意味着**混控器还没把 motor 功能绑到这 4 个通道上** —— 那是 `control_allocator` / airframe 的事。

### 4.3 三个"本板新驱动"的展开

| 开关 | boardconfig | 头 | `config_module_list` | **实测编译单元** | 参数 |
|---|---|---|---|---|---|
| `default.px4board:22 CONFIG_DRIVERS_IMU_HXY_HXY42688P=y` | `boardconfig:228` | [`px4_boardconfig.h:29`](../02_code_twin/build/artifacts.md#^src-build-rm2027-fmu-h743-default-px4-boardconfig-h-29) | `drivers/imu/hxy/hxy42688p` | `HXY42688P.cpp.obj`、`hxy42688p_main.cpp.obj`（[`src/drivers/imu/hxy/hxy42688p/CMakeLists.txt:34`](../02_code_twin/build/drivers-build.md#^src-src-drivers-imu-hxy-hxy42688p-CMakeLists-txt-34)，`MAIN hxy42688p`） | **无**（该驱动没有 `module.yaml`，`ls` 确认） |
| `default.px4board:24 CONFIG_DRIVERS_IMU_HIPNUC_H104=y` | `boardconfig:223` | `:28` | `drivers/imu/hipnuc_h104` | `H104IMU.cpp.obj`、`h104_imu_main.cpp.obj`（该目录 `CMakeLists.txt`，`MAIN h104_imu`） | **无** |
| `default.px4board:85 CONFIG_SYSTEMCMDS_H104CAP=y` | — | — | `systemcmds/h104cap` | `h104cap.c.obj` | **无** |

> ⇒ **"编进固件"≠"有参数"**：这三个新驱动都**不定义任何参数**，所以 `generated_params/module_params.c` 里找不到它们。**推理**：因此 §4.2 那 26 个 `PWM_MAIN_*` 是本板**唯一**由板型（通道数）直接决定的参数组。

### 4.4 串口 → 参数（另一条板型相关的链）

| 跳 | 事实 | 出处 |
|---|---|---|
| ① 板级 | `CONFIG_BOARD_SERIAL_TEL1="/dev/ttyS2"` | [`default.px4board:3`](../02_code_twin/modules/mavlink.md#^src-boards-rm2027-fmu-h743-default-px4board-3)（注释写 USART3） |
| ② boardconfig / 头 | `boardconfig:52` / [`px4_boardconfig.h:15`](../02_code_twin/build/artifacts.md#^src-build-rm2027-fmu-h743-default-px4-boardconfig-h-15) | — |
| ③ cmake 变量 | `SERIAL_TEL1`（`CONFIG_BOARD_` 被剥掉） | [`kconfig.cmake:142`](../02_code_twin/build/cmake-kconfig.md#^src-cmake-kconfig-cmake-142) |
| ④ 端口表 | `board_serial_ports = TEL1:/dev/ttyS2` | [`kconfig.cmake:348`](../02_code_twin/build/cmake-kconfig.md#^src-cmake-kconfig-cmake-348) |
| ⑤ 生成参数 | `SER_TEL1_BAUD` 默认 **57600** | `build/…/generated_params/serial_params.c:40`（由 `Tools/serial/generate_config.py` 生成，调用点 [`src/lib/parameters/CMakeLists.txt:81`](../02_code_twin/build/drivers-build.md#^src-src-lib-parameters-CMakeLists-txt-81)） |
| ⑥ 生成启动脚本 | `build/…/etc/init.d/rc.serial`（162 行）：`mavlink start -d ${SERIAL_DEV} -b p:${BAUD_PARAM} …` | [`ROMFS/CMakeLists.txt:153`](../02_code_twin/build/romfs-and-tools.md#^src-ROMFS-CMakeLists-txt-153) |

---

## 5. 阶段三：两棵"平行树" —— NuttX 与 ROMFS

PX4 固件不是一个 CMake 项目，是**三个东西拼起来**：PX4 自己的 app（`px4` 可执行）、NuttX 内核（独立 make）、ROMFS（另一个 CMake 子项目）。

### 5.1 NuttX 树：板级 `defconfig` → `.config` → `config.h`

| 跳 | 事实 | 出处 |
|---|---|---|
| ① `NUTTX_CONFIG` 取值 | **`nsh`**（因为 `boards/rm2027/fmu-h743/nuttx-config/default` 不存在，落到 `else` 分支） | [`platforms/nuttx/cmake/px4_impl_os.cmake:217`](../02_code_twin/build/nuttx-build.md#^src-platforms-nuttx-cmake-px4-impl-os-cmake-217) |
| ② `NUTTX_DEFCONFIG` | `boards/rm2027/fmu-h743/nuttx-config/nsh/defconfig`（**237 行**） | `platforms/nuttx/cmake/init.cmake:52,56` |
| ③ 配置期 inflate | copy → `platforms/nuttx/NuttX/nuttx/.config` + `defconfig`，再跑 `px4_nuttx_make_olddefconfig.sh` | [`init.cmake:69`](../02_code_twin/build/nuttx-build.md#^src-platforms-nuttx-cmake-init-cmake-69) |
| ④ copy 进 build | `build/rm2027_fmu-h743_default/NuttX/nuttx/.config` | [`init.cmake:84`](../02_code_twin/build/nuttx-build.md#^src-platforms-nuttx-cmake-init-cmake-84) |
| ⑤ 构建期再 inflate | `cat ${NUTTX_DEFCONFIG} ${EXTRA_NUTTX_CONFIG_FILE} > ${NUTTX_DIR}/.config` → olddefconfig | [`platforms/nuttx/NuttX/CMakeLists.txt:55`](../02_code_twin/build/nuttx-build.md#^src-platforms-nuttx-NuttX-CMakeLists-txt-55) |
| ⑥ 生成 C 头 | `make pass1dep` → `platforms/nuttx/NuttX/nuttx/include/nuttx/config.h` | [`platforms/nuttx/NuttX/CMakeLists.txt:72`](../02_code_twin/build/nuttx-build.md#^src-platforms-nuttx-NuttX-CMakeLists-txt-72) |

**实测**（`build/…/NuttX/nuttx/.config`）：

| 行 | 内容 |
|---|---|
| `:267` | `CONFIG_ARCH_CHIP_STM32H743VI=y` |
| `:419` | `CONFIG_STM32H7_USART1=y`（H104 挂的 USART1 ⇒ `/dev/ttyS0`） |
| `:622` | `CONFIG_ARCH_BOARD_CUSTOM_DIR="../../../../boards/rm2027/fmu-h743/nuttx-config"` ← ★ **NuttX 回指板级目录的那根线**（源头 `nsh/defconfig:63`） |
| `:1339-1340` | `# CONFIG_FS_ROMFS is not set` / `CONFIG_FS_CROMFS=y` ← 决定 ROMFS 走 `gencromfs` 分支 |
| `:2095` | `CONFIG_NSH_INITSCRIPT="init.d/rcS"` |

> ⚠️ **一个容易踩的坑（源码级）**：`nsh/defconfig:62-65` 里的 `CONFIG_ARCH_BOARD_CUSTOM_DIR` 是**相对 `platforms/nuttx/NuttX/nuttx/` 的 `../../../../`**，所以它**只在源码树原位构建时成立**。把 PX4 源码整体挪走，这条相对路径就断了。[`platforms/nuttx/CMakeLists.txt:59`](../02_code_twin/build/nuttx-build.md#^src-platforms-nuttx-CMakeLists-txt-59) 有断言会报 `NuttX custom board directory … isn't in board directory`。

### 5.2 ROMFS 树：板级 `init/rc.board_*` → 剥注释 → 打成 C 数组

| 跳 | 事实 | 出处 |
|---|---|---|
| ① ROMFS 根 | `config_romfs_root` = `px4fmu_common`（来自 `CONFIG_BOARD_ROMFSROOT`） | `default.px4board` → `boardconfig:27` → [`kconfig.cmake:374`](../02_code_twin/build/cmake-kconfig.md#^src-cmake-kconfig-cmake-374) |
| ② 生成目录 | `${PX4_BINARY_DIR}/etc` | [`ROMFS/CMakeLists.txt:35`](../02_code_twin/build/romfs-and-tools.md#^src-ROMFS-CMakeLists-txt-35) |
| ③ 铺底 | `tar xf romfs_files.tar` 到 `etc/`（**raw，带注释**） | `:116-165` |
| ④ ★ **板级脚本注入** | 遍历 `rc.board_early / defaults / sensors / extras / mavlink`，存在的 `copy_if_different` 到 `etc/init.d/` | `:194-227` |
| ⑤ 本板实际注入 3 个 | `rc.board_defaults`、`rc.board_sensors`、`rc.board_extras`（`rc.board_early`/`rc.board_mavlink` 不存在） | **实测** `ls build/…/etc/init.d/` |
| ⑥ ★ **剥注释** | `python Tools/px_romfs_pruner.py --folder build/…/etc --board rm2027_fmu-h743` | `:401-410` |
| ⑦ 打镜像 | `gencromfs build/…/etc nsh_romfsimg.c` → `libromfs.a`（**实测 806,054 B → 125,608 B**） | `:412-433` |
| ⑧ 链进固件 | `target_link_libraries(px4 PRIVATE romfs)` | [`platforms/nuttx/CMakeLists.txt:394`](../02_code_twin/build/nuttx-build.md#^src-platforms-nuttx-CMakeLists-txt-394) |

**★★ 第 ⑥ 步是本板最容易"看到的和想到的不一样"的地方**（`Tools/px_romfs_pruner.py`）：

| 规则 | 行号 | 后果 |
|---|---|---|
| 删空行、删**整行** `#` 注释、删**行尾** `# …` 注释、压缩连续空格 | `:109-114` | **实测**：`boards/…/init/rc.board_sensors` **8,942 B / 119 行 → 123 B / 5 行** |
| 文件名以 `.` 开头 / `README*` / `CMakeLists*` 的**直接删** | `:71-84` | 板级 rc 脚本别用这些名字 |
| 含 `<board> exclude` 的脚本**整文件删** | `:106` | 本板写 `# rm2027_fmu-h743 exclude` 就能屏蔽某个 `rc.board_*` |
| 结尾用 `encode("ascii", errors='strict')` | `:119-121` | ★ **非注释行出现任何非 ASCII 字符（中文）会直接抛 `UnicodeEncodeError` 中断构建** |

**实测**：`build/…/etc/init.d/rc.board_sensors` 这 5 行就是最终进镜像的东西：

```
board_adc start
hxy42688p -s -b 1 -R 6 start
ist8310 -I -b 4 -a 0x0C -R 0 start
spa06 -I -b 2 -a 0x77 start
h104_imu start
```

> **源码 + 推理**：源文件 `boards/rm2027/fmu-h743/init/rc.board_sensors` 的 8942 B 里 **全部中文都在 `#` 行**（我用 pruner 的同一套正则跑过一遍：三个 `rc.board_*` 的**非注释行非 ASCII = 0 处**）⇒ **中文注释安全，但只能在 `#` 后面写。**

---

## 6. 阶段四：最终产物 —— `.px4` 里到底装了什么

### 6.1 从 `.elf` 到 `.px4` 的流水线

| 产物 | 大小（实测） | 谁生成 | 出处 |
|---|---|---|---|
| `rm2027_fmu-h743_default.elf` | 35,285,444 B | 链接 `px4` 可执行 | [`platforms/nuttx/CMakeLists.txt:40`](../02_code_twin/build/nuttx-build.md#^src-platforms-nuttx-CMakeLists-txt-40) |
| `rm2027_fmu-h743_default.bin` | **1,554,376 B** | `objcopy -O binary` | [`platforms/nuttx/CMakeLists.txt:399`](../02_code_twin/build/nuttx-build.md#^src-platforms-nuttx-CMakeLists-txt-399) |
| `parameters.xml` / `.json` | 660,680 B | `px_process_params.py`（扫 `generated_params/`） | [`src/lib/parameters/CMakeLists.txt:113`](../02_code_twin/build/drivers-build.md#^src-src-lib-parameters-CMakeLists-txt-113) |
| `airframes.xml` | 21,495 B | `px4_generate_airframes_xml(BOARD rm2027_fmu-h743)` | [`CMakeLists.txt:431`](../02_code_twin/build/cmake-kconfig.md#^src-CMakeLists-txt-431) |
| **`rm2027_fmu-h743_default.px4`** | **1,504,526 B** | `python Tools/px_mkfw.py --prototype boards/rm2027/fmu-h743/firmware.prototype --parameter_xml … --airframe_xml … --image …` | [`platforms/nuttx/CMakeLists.txt:478`](../02_code_twin/build/nuttx-build.md#^src-platforms-nuttx-CMakeLists-txt-478) |

### 6.2 `.px4` 头部（**实测**：直接解析了那个文件）

| 字段 | 值 | 说明 |
|---|---|---|
| `magic` | `PX4FWv1` | |
| `board_id` | **2027** | 来自 `boards/rm2027/fmu-h743/firmware.prototype:2`（[`px_mkfw.py:93`](../02_code_twin/build/romfs-and-tools.md#^src-Tools-px-mkfw-py-93) 只有传 `--board_id` 才覆盖，本构建没传） |
| `summary` / `description` / `version` | `rm2027 fmu-h743` / `Firmware for the rm2027 fmu-h743 board` / `0.1` | `firmware.prototype:4,7,8` |
| `image` | 1,392,352 B 的 **xz 压缩流** | = `.bin` 压缩后 |
| `image_size` | **1,554,376** | 与 `.bin` 字节数完全一致 ⇒ **`.px4` 里的 `image` 就是 app 的 `.bin`，不含 bootloader** |
| `image_maxsize` | 1,966,080（= 1920 K = 2 MB − 128 K） | `firmware.prototype:10`；上传器用它校验（[`Tools/px4_uploader.py:2209`](../02_code_twin/build/romfs-and-tools.md#^src-Tools-px4-uploader-py-2209)） |
| `parameter_xml_size` | 660,680 | 参数默认值随镜像走 ⇒ **刷完固件参数默认值就有** |
| `airframe_xml_size` | 21,495 | |
| `git_identity` / `git_hash` | `4e910b6` / `4e910b61…` | ★ 这是判"构建目录属于哪个 commit"的唯一可靠依据 |

### 6.3 **bootloader 不在 `.px4` 里**

- bootloader 是**另一个目标**：`make rm2027_fmu-h743_bootloader` → `boards/rm2027/fmu-h743/extras/rm2027_fmu-h743_bootloader.bin`（**实测 38,148 B**）
- 把它塞进 ROMFS 的条件是 `CONFIG_SYSTEMCMDS_BL_UPDATE=y`（[`ROMFS/CMakeLists.txt:262`](../02_code_twin/build/romfs-and-tools.md#^src-ROMFS-CMakeLists-txt-262)）；**推理**：本板 `default.px4board` 里没有这一条 ⇒ 走 `else`（`:291-294`）**从 ROMFS 里剔除**。

### 6.4 flash 布局（决定"能塞多大 app"）

- **源码**：[`boards/rm2027/fmu-h743/nuttx-config/scripts/script.ld:113`](../02_code_twin/bootloader/stm32-common-main-c.md#^src-boards-rm2027-fmu-h743-nuttx-config-scripts-script-ld-113)
  `FLASH (rx) : ORIGIN = 0x08020000, LENGTH = 1792K /* ★ 最后 1 个 128K 扇区(0x081E0000)让给 flash 参数存储 */`
- 即：`0x08000000` bootloader(128K) ｜ `0x08020000` app(1792K) ｜ `0x081E0000` **参数区(128K)**
- **推理 + 待核实**：`.px4` 头里 `image_maxsize = 1920 K`（覆盖到 `0x08200000`）**比 app 实际可链接的 1792 K 大 128 K**。因为链接脚本先卡住，实际塞不进去，所以**不构成风险**；但这两个数不同源。→ **这条与 `FLASH_BASED_PARAMS` / 参数区起始地址的"三处同源"欠账是同一个话题，归 task-12。**

---

## 7. 哪些是本板特有、哪些是上游通用

**实测依据**：`git diff --name-only upstream/main...HEAD` ⇒ **47 个文件**，全部落在这 6 组路径：

| 本板特有（相对 `upstream/main` 有改动/新增） | 文件数 | 在构建链里的位置 |
|---|---|---|
| `boards/rm2027/fmu-h743/**` | 25 | §2 的 `PX4_CONFIG_FILE`/`PX4_BOARD_DIR`；§5.1 的 `defconfig`；§5.2 的 3 个 `rc.board_*`；§3.6 的板级 `src` |
| `src/drivers/imu/hxy/{CMakeLists.txt,Kconfig,hxy42688p/**}` | 8 | §4.3 驱动① |
| `src/drivers/imu/hipnuc_h104/**` | 7 | §4.3 驱动② |
| `src/systemcmds/h104cap/**` | 3 | §4.3 工具 |
| `src/drivers/drv_sensor.h` | 1 | 给上面两个新驱动加 `DEVTYPE` |
| `src/drivers/imu/bosch/bmi270/**` | 3 | **存档补丁，未编入**（`default.px4board` 里没有 `CONFIG_DRIVERS_IMU_BOSCH_BMI270`） |

**上游通用（一个字没改，只是被喂了不同输入）**：

| 组件 | 位置 |
|---|---|
| `make` 目标扫描 + cmake/ninja 调用 | `Makefile:237,244-250,179-214` |
| `CONFIG` → 板型变量 | `cmake/px4_config.cmake` |
| `CONFIG_*` → 模块列表 | `cmake/kconfig.cmake`（含 §3.5 的 7 种路径猜测） |
| `px4_add_module` / `px4_add_library` | `cmake/px4_add_module.cmake`、`cmake/px4_add_library.cmake` |
| `-DCONFIG_ARCH_BOARD_*` | [`cmake/px4_add_common_flags.cmake:195`](../02_code_twin/build/cmake-kconfig.md#^src-cmake-px4-add-common-flags-cmake-195) |
| NuttX inflate / `pass1dep` | `platforms/nuttx/cmake/init.cmake`、`platforms/nuttx/NuttX/CMakeLists.txt` |
| ROMFS 铺底 + 注入 + **pruner** | `ROMFS/CMakeLists.txt`、`Tools/px_romfs_pruner.py` |
| `.px4` 打包 | [`platforms/nuttx/CMakeLists.txt:431`](../02_code_twin/build/nuttx-build.md#^src-platforms-nuttx-CMakeLists-txt-431)、`Tools/px_mkfw.py` |
| 参数生成 | `src/lib/parameters/CMakeLists.txt`、`Tools/module_config/generate_params.py`、`Tools/serial/generate_config.py` |
| DShot / PWMOut / 磁罗盘 / 气压计驱动本体 | `src/drivers/{dshot,pwm_out,magnetometer,barometer}/**` |

> ⇒ **一句话**：**"板型"在这套构建里 = 1 份 `.px4board` + 1 个 `boards/<vendor>/<model>/` 目录 + （可选）几个新驱动目录。** 剩下的全是上游机制在按这份输入展开。

---

## 8. 自查与不确定项

### 8.1 已实测回验（本轮）

- ✅ `Makefile:237/244-245/179-214/85-108/202-204` 行号与内容
- ✅ `cmake/px4_config.cmake:44-49,53-56,61-83,101-117`；`cmake/kconfig.cmake:1-2,74-81,106-111,114,130,142-150,164-214,217-271,324-375,401-410,454-455`
- ✅ `cmake/px4_add_module.cmake:84-92,151,187-197,205-209,213-218,220-222,232-243,251-255`；`px4_add_library.cmake:41-44,46,51,54-56`
- ✅ `cmake/px4_add_common_flags.cmake:191-193,195-199`
- ✅ `platforms/nuttx/cmake/init.cmake:52,56,59-61,69-79,84`；[`px4_impl_os.cmake:217`](../02_code_twin/build/nuttx-build.md#^src-platforms-nuttx-cmake-px4-impl-os-cmake-217)
- ✅ `platforms/nuttx/NuttX/CMakeLists.txt:34-42,55-84,90-102,137-138,153-159`；`platforms/nuttx/CMakeLists.txt:394-397,399-403,431-497`
- ✅ `ROMFS/CMakeLists.txt:34-35,116-165,194-227,262-296,380-410,412-433,442-450`
- ✅ `Tools/px_romfs_pruner.py:71-84,106,109-114,119-121`；[`Tools/px_mkfw.py:93`](../02_code_twin/build/romfs-and-tools.md#^src-Tools-px-mkfw-py-93)
- ✅ 变量/宏在**产物里**的存在性：`boardconfig`(760 行)、`px4_boardconfig.h`(182 行)、`config_module_list.txt`(269 行 = `PX4_MODULE_PATHS`)、`build.ninja`(dshot/hxy/hipnuc/pwm_out 的 `.obj`)、`compile_commands.json`(`-DCONFIG_ARCH_BOARD_RM2027_FMU_H743`、`-DPARAM_PREFIX="PWM_MAIN"`)、`px4.bdat`(`{ "dshot", …, dshot_main }`)、`.px4` 头部 11 个字段、`.config` 5 条、[`script.ld:113`](../02_code_twin/bootloader/stm32-common-main-c.md#^src-boards-rm2027-fmu-h743-nuttx-config-scripts-script-ld-113)、`module_params.c` 行号
- ✅ §3.5 六个驱动路径的**命中结果**（`config_module_list.txt` 里只有三段式路径 ⇒ 都是候选②）
- ✅ `git diff --name-only upstream/main...HEAD` = 47 文件；`git diff --stat 4e910b6 HEAD` = 1 文件

### 8.2 明确标"未核实"的

1. **`image_maxsize` 与链接脚本 LENGTH 不同源**（1920 K vs 1792 K）：我确认了**两个数值本身**，但**没有去看 bootloader 侧怎么用 `image_maxsize`**（那是 `02_code_twin/bootloader/` 的地盘）。
2. **`src/drivers/imu/hxy/CMakeLists.txt` 是死代码**这个结论：`src/drivers/` 与 `src/drivers/imu/` 都无 `CMakeLists.txt` 是**实测**；"因此不被任何 `add_subdirectory` 走到"是**推理**（没有跑 `cmake --graphviz` 之类）。
3. **§3.5 的候选顺序**（①②③…⑦）是我按 [`kconfig.cmake:197`](../02_code_twin/build/cmake-kconfig.md#^src-cmake-kconfig-cmake-197) 的 `if/elseif` **书写顺序**读出来的；"为什么是这个顺序"（历史原因）我没有上游 commit 依据。
4. **`DSHOT_*` 参数被哪个 commit 引入本板**：我确认了参数存在与默认值，**没有**追它是哪个 commit 加进 `module.yaml` 的。

### 8.3 被构建目录冻住的时点

`build/rm2027_fmu-h743_default/` 里所有文件都是 **10-01 ~ 10-02** 生成的；`boards/rm2027/fmu-h743/**` 与 `src/drivers/imu/hxy/**` 的 mtime 是 **10-03**（今天）。**实测**：`git diff 4e910b6 HEAD` 只有 `HXY42688P.cpp` 一个文件 ⇒ **Kconfig/CMake 层面完全等价**，但**若你重新编译，产物会与本文数值有 1 个源文件的差别**。

---

## 9. 跳转（执行序意义上的下一步）

构建走完了，接下来按"运行时"顺序读：

1. **上电之后**：`[03_moc/01-poweron-walkthrough](01-poweron-walkthrough.md)` —— §5 里那条 `CONFIG_NSH_INITSCRIPT="init.d/rcS"` 之后，控制权交给 NSH，再执行 `rcS`。看 `.config:2095` 那条字符串是怎么变成"开机自己跑起来"的。
   - 特别是 §5.2 打进 ROMFS 的那 5 行 `rc.board_sensors` —— 它就是 `hxy42688p -s -b 1 -R 6 start` 被执行的**唯一原因**。
2. **数据从硬件进来之后**：`[03_moc/02-sensor-flow](02-sensor-flow.md)`（task-11 交付）—— §4.3 编进去的两个 IMU 驱动，各自发什么 topic。
3. **参数**：`[03_moc/04-params-map](04-params-map.md)`（task-12 交付）—— §4.2 的 26 个 `PWM_MAIN_*` 从 `module_params.c` 到 flash 参数区的完整链，以及 §6.4 那笔"FLASH 长度 / 参数区 / `FLASH_BASED_PARAMS` 三处同源"的欠账。
4. **板级 25 个文件**：`02_code_twin/board/`（task-12 交付）—— §2 第 9 跳那个 `PX4_BOARD_DIR` 底下的每个文件分别在"配置期 / 编译期 / 运行期"哪个时点被读走。
5. **想让 DShot 真的动起来**（本文直接可用的行动项）：
   ```
   param set PWM_MAIN_TIM0 -3        # DShot600，见 DShot.h:61
   param set PWM_MAIN_FUNC1 101      # Motor 1，见 module_params.c 的 @value 表
   param set PWM_MAIN_FUNC2 102
   param set PWM_MAIN_FUNC3 103
   param set PWM_MAIN_FUNC4 104
   param save                        # module.yaml:35 reboot_required ⇒ 要重启
   ```
   （依据：[`src/drivers/dshot/DShot.h:59`](../02_code_twin/drivers/dshot.md#^src-src-drivers-dshot-DShot-h-59)、[`module_params.c:2243`](../02_code_twin/build/artifacts.md#^src-build-rm2027-fmu-h743-default-generated-params-module-params-c-2243) 的 `@value 101 Motor 1`…；**"改完真的变成 DShot"未经上板验证** —— 本文只做到"源码判据"。）

---

## 相关支撑知识

- `[01_extracted/cmake/01-px4-cmake-organization](../01_extracted/cmake/01-px4-cmake-organization.md)` —— `px4_add_module` / `px4_add_library` / `add_subdirectory` 的分工，以及 `PX4_MODULE_LIBRARIES` / `PX4_MODULE_CONFIG_FILES` 两个全局属性
- `[01_extracted/cmake/02-build-dir-map](../01_extracted/cmake/02-build-dir-map.md)` —— `build/rm2027_fmu-h743_default/` 里每个子目录是什么
- `[01_extracted/cmake/03-kconfig-bridge](../01_extracted/cmake/03-kconfig-bridge.md)` —— `default.px4board` ↔ Kconfig ↔ CMake ↔ C 宏 四者的桥
- `[README](../02_code_twin/board/README.md)` —— 四层架构与引用规则

---

## 源码在哪（本文只讲流程；代码与逐行解释已归位到 02 层）

> ★ **本文里每一条 `文件:行` 都能点** —— 它跳到 `02_code_twin/` 里对应的篇，代码旁边就是解释。
> 这样三层各司其职：**01 讲语法/机制通则 · 02 讲某个文件的行号在干什么 · 本文（03）只讲执行序**。

| 你在本文看到的东西 | 代码与逐行解释在 |
|---|---|
| 根 `CMakeLists.txt`、`cmake/*.cmake` | [`02_code_twin/build/cmake-kconfig`](../../02_code_twin/build/cmake-kconfig.md) |
| `Makefile` | [`02_code_twin/build/Makefile`](../../02_code_twin/build/Makefile.md) |
| `boards/rm2027/fmu-h743/` 的板级构建 | [`02_code_twin/build/board-build`](../../02_code_twin/build/board-build.md) |
| `platforms/nuttx/` 的整合 | [`02_code_twin/build/nuttx-build`](../../02_code_twin/build/nuttx-build.md) |
| `ROMFS/`、`Tools/*.py` | [`02_code_twin/build/romfs-and-tools`](../../02_code_twin/build/romfs-and-tools.md) |
| 各驱动/模块的构建登记 | [`02_code_twin/build/drivers-build`](../../02_code_twin/build/drivers-build.md) |
| `build/…/` 里的生成物 | [`02_code_twin/build/artifacts`](../../02_code_twin/build/artifacts.md) |

**★ 语法/机制通则**（CMake 的 `file()`/`function` vs `macro`、Kconfig 的 `menuconfig`、Make 的 `$(eval)`…）在
[`01_extracted/`](../../01_extracted/) 层：
[`cmake-syntax`](../../01_extracted/cmake/cmake-syntax.md) ·
[`01-px4-cmake-organization`](../../01_extracted/cmake/01-px4-cmake-organization.md) ·
[`03-kconfig-bridge`](../../01_extracted/cmake/03-kconfig-bridge.md) ·
[`gnu-make-syntax`](../../01_extracted/make/gnu-make-syntax.md)
