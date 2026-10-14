# 本板 25 个文件：按「被读时机」组织

> **本板 = `boards/rm2027/fmu-h743/`，共 25 个文件**（清单已与 `h104-protocol` 分支 `comm` 双向比对，0 差异）。
>
> **本篇不按目录讲，按"这个文件在什么时候被谁读走"讲。**
> 同一个目录下的文件可能处在完全不同的阶段 —— 这是最容易搞混的地方。

---

## 0. 一句话总览：25 个文件分布在**五个阶段**

```
【A】构建期（CMake / Kconfig 读它）           8 个
【B】bootloader 阶段（②层）                   2 个
【C】rcS 之前（板级 C 初始化）                6 个
【D】rcS 运行期（脚本被 source）              3 个
【E】文档 / 元数据                            2 个
                                            ─────
                                             25 个（README.md 与 firmware.prototype 归 E）
```

**⇒ 关键认知：`src/` 目录下的 7 个文件里，`timer_config.cpp` 是【构建期】读的，
其余 6 个是【rcS 之前】跑的 —— 同在 `src/`，阶段完全不同。**

---

## A. 构建期：CMake / Kconfig 读它（8 个）

| 文件 | 谁读 | 影响什么 |
|---|---|---|
| **`default.px4board`** | Kconfig → `config_module_list` | **决定哪些模块/驱动被编进去**（如 `CONFIG_DRIVERS_DSHOT=y` ⇒ 编入 `DShot.cpp`） |
| **`bootloader.px4board`** | bootloader 构建 | 决定 **bootloader 镜像** 编哪些东西 |
| **`src/CMakeLists.txt`** | CMake | ★ **板级代码的唯一入口**：板根目录没有 `CMakeLists.txt`，只有 [`kconfig.cmake:454`](README.md#^src-cmake-kconfig-cmake-454) 把 `../boards/rm2027/fmu-h743/src` 塞进 `config_module_list` ⇒ **"板级 src 目录必须叫 `src`"是硬约束** |
| **`src/timer_config.cpp`** | ★ **构建期**（CMake `--timer-config` 生成定时器参数） | 决定 `Timer1..N` 的编号 ⇒ **生成 `PWM_MAIN_TIM0` 这样的参数名** ← 这就是"TIM0 从哪来"的答案 |
| **`src/board_config.h`** | 编译期（`#include`） | 板级宏：`FLASH_BASED_PARAMS`（:60）、引脚、总线号… |
| **`src/hw_config.h`** | 编译期（`#include`） | 板级硬件常量：`BOOTLOADER_DELAY 5000`（:88）等 |
| **`nuttx-config/Kconfig`** | Kconfig → NuttX 树 | 板级 Kconfig 项；经 `tools/Config.mk` → `tools/Unix.mk` **cp 到 `boards/dummy/Kconfig`** 才进 NuttX |
| `nuttx-config/{nsh/defconfig, bootloader/defconfig, include/board.h, include/board_dma_map.h, scripts/script.ld, scripts/bootloader_script.ld}` | NuttX / 链接器 | 共 6 个，见下 |

**NuttX 配置那 6 个（同属 A）：**
```
nuttx-config/nsh/defconfig              ← app 侧 NuttX 配置（如 CONFIG_INIT_ENTRYPOINT="nsh_main" @ :116）
nuttx-config/bootloader/defconfig       ← bootloader 侧 NuttX 配置
nuttx-config/include/board.h            ← 时钟、引脚 AF 定义（NuttX 视角）
nuttx-config/include/board_dma_map.h    ← DMA 通道分配
nuttx-config/scripts/script.ld          ← ★ app 链接脚本：FLASH @0x08020000 LENGTH 1792K（:113）
nuttx-config/scripts/bootloader_script.ld ← ★ bootloader 链接脚本：flash @0x08000000 LENGTH 128K（:113）
```

**⇒ A 组交付的最终产物（实测）：**
```
build/rm2027_fmu-h743_default/rm2027_fmu-h743_default.px4     最终镜像（1.5 MB）
build/rm2027_fmu-h743_default/.px4 头: image_maxsize = 1966080 (1920K)
    ⚠️ 与 script.ld 的 1792K 不同源，差 128K（= 让给参数区的扇区）
```

**🔗 完整展开**：`[../../03_moc/00-build-walkthrough](../../03_moc/00-build-walkthrough.md)`

---

## B. bootloader 阶段：上电最先跑（2 个）

| 文件 | 时机 | 说明 |
|---|---|---|
| **`src/bootloader_main.c`** | **T1（bootloader 跑起来时）** | 板级那薄薄一层。上游参照板只提供两个钩子：`board_late_initialize()` + `board_timerhook()` （`boards/matek/h743-slim/src/bootloader_main.c:66,72`） |
| **`extras/rm2027_fmu-h743_bootloader.bin`** | **编译产物，被刷进 `0x08000000`** | 38,148 字节。**是产物不是源码** ⇒ **没法手写**，要么从分支取，要么自己编（`extras/*_bootloader.bin` 是上游通用惯例：`boards/px4/fmu-v6x/extras/`、`boards/matek/h743-slim/extras/` 都有） |

**⇒ B 组对应的运行时刻：`[../bootloader/bl-c](../bootloader/bl-c.md)` 的 §「跳转动作」。**
**🔗 完整决策序**：`[PX4-bootloader主流程时序图](../../../PX4-bootloader主流程时序图.md)`

---

## C. rcS **之前**：板级 C 初始化（6 个）

**★ 这一组的统一入口只有一个：**
```
boards/rm2027/fmu-h743/src/init.c:157   board_app_initialize()
    └─ :160  px4_platform_init()
官方注释（同款见 boards/ark/fmu-v6x/src/init.c:40）:
    "Code here is run before the rcS script is invoked"
```

| 文件 | 谁调用它 | 干什么 |
|---|---|---|
| **`src/init.c`** | **NuttX（nsh 启动早期）** | ★ **板级初始化的总入口**；还定义了 flash 参数区扇区表（`:201 {15, 128*1024, 0x081E0000}`） |
| `src/led.c` | 被 `init.c` / 驱动调用 | LED 驱动（bootloader 阶段也用它，但那时走的是 ②层 的 `led_on/off`） |
| `src/usb.c` | 被 `init.c` 调用 | USB（本板**无 USB 口**，见 `[PX4接电调-QGC配置清单](../../../PX4接电调-QGC配置清单.md)` 的 preflight 说明） |
| `src/i2c.cpp` | 被 `init.c` 调用 | I²C 总线注册（磁力计 IST8310 = I2C4、气压计 SPA06 = I2C2） |
| `src/spi.cpp` | 被 `init.c` 调用 | **SPI 总线注册 + 片选/DRDY 引脚**（陀螺 `hxy42688p` = SPI1） |
| — | — | （第 6 个是上面 A 组里的 `timer_config.cpp` 吗？**不是** —— 图纸上 `src/` 共 7 个 `.c/.cpp`，其中 `timer_config.cpp` 属 A 组） |

**⇒ 这 5 个文件（init/led/usb/i2c/spi）都跑在 `rcS` 之前 ⇒ 你在 `rc.board_sensors` 里
可以放心认为"总线已经初始化好了"。**

**🔗 执行链位置**：`[../../03_moc/01-poweron-walkthrough](../../03_moc/01-poweron-walkthrough.md)` §5

---

## D. rcS 运行期：脚本被 source（3 个）

**★ 本板只有 3 个钩子**（另两个 `rc.board_early` / `rc.board_mavlink` **本板没有** ⇒ `if [ -f ]` 判空后**静默跳过、不报错**）。

| 文件 | rcS 行 | 时机 | 干什么 |
|---|---|---|---|
| **`init/rc.board_defaults`** | **`:278`** | 参数就绪后 | 板级**默认参数**（用 `param set` 写）—— **⚠️ 每次开机都重设，会覆盖你在 QGC 改的值** |
| **`init/rc.board_sensors`** | **`:420`（source 在 `:424`）** | 传感器阶段 | ★ **拉起本板传感器驱动**（`hxy42688p` / `h104_imu` / `ist8310` / `spa06` 的 module 命令逐行） |
| **`init/rc.board_extras`** | **`:693`** | 最后 | 其它额外启动项 |

**★ 判据（台架上唯一可见的来源）：**
```
开机 console 出现  Board sensors: /etc/init.d/rc.board_sensors   (rcS:423)
✅ 有 ⇒ 文件进了 ROMFS 且被执行
❌ 没有 ⇒ 问题在【构建期】（文件名/路径/白名单），不是脚本内容
```

**⚠️ ★ 写这三个文件时的硬约束（构建会直接崩）：**
```
Tools/px_romfs_pruner.py:121   pruned_content.encode("ascii", errors='strict')
⇒ 【非注释行】出现任何非 ASCII 字符（中文）⇒ UnicodeEncodeError ⇒ 构建中断
⇒ 中文只能写在 # 后面
（本板当前 3 个脚本已自查：非注释行含非 ASCII = 0 处，安全）
```

**另一个可用技巧**：[`Tools/px_romfs_pruner.py:106`](README.md#^src-Tools-px-romfs-pruner-py-106) 支持 `# <board> exclude`（如 `# rm2027_fmu-h743 exclude`）⇒ **整文件不进 ROMFS**。

**🔗 完整阶段表**：`[PX4-rcS执行时序表](../../../PX4-rcS执行时序表.md)`

---

## E. 文档 / 元数据（2 个）

| 文件 | 是什么 |
|---|---|
| `README.md` | 板级说明（上游惯例，每个板都有一份） |
| `firmware.prototype` | 固件原型标记（上游构建脚本用） |

---

## ★ 一张"当系统跑到这里时，哪些文件在起作用"对照表

| 时刻 | 谁在跑 | 本板哪些文件在起作用 |
|---|---|---|
| **构建时** | `make rm2027_fmu-h743_default` | **A 组 8 个**（含 `src/timer_config.cpp` ★） |
| **T0** | 复位向量 | — |
| **T1** | bootloader @`0x08000000` | **B 组 2 个**（`src/bootloader_main.c` + `extras/*.bin`） |
| **T2** | NuttX 内核 @`0x08020000` | A 组产出的配置（`nuttx-config/*`）已固化在固件里 |
| **T3** | `nsh_main` → `board_app_initialize()` | **C 组 5 个**（`init.c` → `led/usb/i2c/spi`） |
| **T4** | `rcS` 逐行 | **D 组 3 个**（`:278` / `:420` / `:693`） |
| **T5** | 各 module | 不再有板级文件参与（驱动在 `src/drivers/`） |

**⇒ ⇒ 这就是"25 个文件"在一个运行中的系统里的完整分布。**

---

## 跳转

- **执行主线** → `[../../03_moc/01-poweron-walkthrough](../../03_moc/01-poweron-walkthrough.md)`
- **构建/变量展开** → `[../../03_moc/00-build-walkthrough](../../03_moc/00-build-walkthrough.md)`
- **参数（含 flash 参数区三处同源）** → `[../../03_moc/04-params-map](../../03_moc/04-params-map.md)`
- **复刻待办（每个文件一句话 + 依据）** → `[PX4板级复刻-待办清单](../../../PX4板级复刻-待办清单.md)`
- **bootloader 深挖** → `[../bootloader/](../bootloader/00-overview.md)`

**★ 想按"复刻顺序"学（而不是按执行时机读）：**
先把 A 组写出来（能编），再补 B（bootloader），再补 C（板级 C 初始化），最后补 D（脚本）——
这样每一层都能独立验证：**A 组写对 ⇒ 能编出来；C 组写对 ⇒ 传感器能通信；D 组写对 ⇒ 日志出现 `Board sensors:`。**

---

## 标注源码（代码 + 本文档对它的解释）

> **这是「代码孪生」层**：上面是代码原文（带行号），下面是**本文档针对这一段说的话**。
> 行号可点，直接跳到 PX4 源码那一行。
### `Tools/px_romfs_pruner.py`
<a id="src-Tools-px-romfs-pruner-py-106"></a>
**↓ 文档在讲这里：**[`Tools/px_romfs_pruner.py:106`](README.md#^src-Tools-px-romfs-pruner-py-106)

```c
   103 │                         err_count += 1
   104 │ 
   105 │                     # find excluded boards
▶  106 │                     if re.search(r'\b{0} exclude\b'.format(args.board), line):
   107 │                         board_excluded = True
   108 │ 
   109 │                     if not line.isspace() \
```
> **说明**：另一个可用技巧：Tools/px_romfs_pruner.py:106 支持 # <board> exclude（如 # rm2027_fmu-h743 exclude）⇒ 整文件不进 ROMFS。
^src-Tools-px-romfs-pruner-py-106

### `cmake/kconfig.cmake`
<a id="src-cmake-kconfig-cmake-454"></a>
**↓ 文档在讲这里：**[`cmake/kconfig.cmake:454`](README.md#^src-cmake-kconfig-cmake-454)

```c
   451 │ 	px4_os_prebuild_targets(OUT prebuild_targets BOARD ${PX4_BOARD})
   452 │ 
   453 │ 	# add board config directory src to build modules
▶  454 │ 	file(RELATIVE_PATH board_support_src_rel ${PX4_SOURCE_DIR}/src ${PX4_BOARD_DIR})
   455 │ 	list(APPEND config_module_list ${board_support_src_rel}/src)
   456 │ 
   457 │ 	set(config_module_list ${config_module_list})
```
> **说明**：bootloader.px4board | bootloader 构建 | 决定 bootloader 镜像 编哪些东西 | ┃ src/CMakeLists.txt | CMake | ★ 板级代码的唯一入口：板根目录没有 CMakeLists.txt，只有 kconfig.cmake:454 把 ../boards/rm2027/fmu-h743/src 塞进 config_module_list ⇒ "板级 src 目录必须叫 src"是硬约束 |
^src-cmake-kconfig-cmake-454
