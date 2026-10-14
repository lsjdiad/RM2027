# NuttX 启动链（复位 → 内核 → 第一个用户任务）

> **层**：01 提炼知识（从 NuttX 内核源码里把"上电到交出控制权"这条链抽出来）
> **素材**：`platforms/nuttx/NuttX/nuttx/`（下称 `nuttx/`）、`platforms/nuttx/NuttX/apps/`（下称 `apps/`）
> **被谁引用**：本套所有需要解释"现在控制权在哪"的篇
> **本板适用性**：本板的 **bootloader 构建**与 **app 构建**走的是**同一条链**，只有第 6/7 步的参数不同
> ⇒ 差异逐条列在 [01_extracted/nuttx/bootloader-vs-app](bootloader-vs-app.md)

---

## 1. 整条链（一张表看完）

| # | 控制权在哪 | 代码位置 | 干了什么 | 本板相关宏 |
|---|---|---|---|---|
| 1 | 硬件 | — | 取初始 SP + 复位向量 | — |
| 2 | `__start` | [`nuttx/arch/arm/src/stm32h7/stm32_start.c:183`](00-poweron-chain.md#^src-platforms-nuttx-NuttX-nuttx-arch-arm-src-stm32-stm32-start-c-183) | 清 `.bss`（`:209`）、搬 `.data`（`:220`）、搬 ramfuncs（`:235`） | — |
| 3 | `__start` | `:249` | `stm32_clockconfig()` ⇐ **480 MHz PLL 在这里起来** | [`board.h:104`](../../02_code_twin/bootloader/00-overview.md#^src-boards-rm2027-fmu-h743-nuttx-config-include-board-h-104) |
| 4 | `__start` | `:250-251` | `arm_fpuconfig()`、`stm32_lowsetup()` | — |
| 5 | `__start` | `:257` → `:262` → `:268-269` | TCM 使能 → **`stm32_boardinitialize()`（★ 进 ③ 板级）** → 开 I/D-Cache | [`boards/.../src/init.c:120`](../stm32/00-reset-clock-peripherals.md#^src-boards-rm2027-fmu-h743-src-init-c-120)（app）／[`bootloader_main.c:55`](../../02_code_twin/bootloader/00-overview.md#^src-boards-rm2027-fmu-h743-src-bootloader-main-c-55)（bl） |
| 6 | `nx_start` | `:315` → [`nuttx/sched/init/nx_start.c:506`](../stm32/startup-and-crt.md#^src-platforms-nuttx-NuttX-nuttx-sched-init-nx-start-c-506) | NuttX 内核启动 | — |
| 7 | `nx_start` | `:635` | `irq_initialize()` ⇒ `up_irqinitialize()` ⇒ **写 `NVIC_VECTAB`** | [`nuttx/sched/irq/irq_initialize.c:98`](../../02_code_twin/bootloader/00-overview.md#^src-platforms-nuttx-NuttX-nuttx-sched-irq-irq-initialize-c-98) → [`nuttx/arch/arm/src/stm32h7/stm32_irq.c:372`](../stm32/vtor-vector-tables.md#^src-platforms-nuttx-NuttX-nuttx-arch-arm-src-stm32-stm32-irq-c-372) / **`:408`** |
| 8 | `nx_start` | `:675` | `up_initialize()` ⇒ `arm_initialize_stack()` ⇐ **线程模式改用 PSP** | [`nuttx/arch/arm/src/common/arm_initialize.c:62`](../stm32/00-reset-clock-peripherals.md#^src-platforms-nuttx-NuttX-nuttx-arch-arm-src-common-arm-initialize-c-62) / `:67`；条件是 `CONFIG_ARCH_INTERRUPTSTACK > 7` |
| 9 | `nx_start` | `:679` | `drivers_initialize()` 注册设备驱动（**`/dev/ttyS0` 在这里出现**，`arm_serialinit()` 在 [`arm_initialize.c:100`](../stm32/00-reset-clock-peripherals.md#^src-platforms-nuttx-NuttX-nuttx-arch-arm-src-common-arm-initialize-c-100)） | — |
| 10 | `nx_start` | `:743` | `nx_bringup()` | [`nuttx/sched/init/nx_bringup.c:494`](00-poweron-chain.md#^src-platforms-nuttx-NuttX-nuttx-sched-init-nx-bringup-c-494) |
| 11 | `nx_bringup` | `:524` / `:530` | 起 pgworker / **起工作队列** | `nx_pgworker()` / `nx_workqueues()` |
| 12 | `nx_bringup` | `:537` | `nx_create_initthread()` | `:434` |
| 13a | `nx_bringup` | `:443-446` | **若 `CONFIG_BOARD_LATE_INITIALIZE=y`**：新建 `AppBringUp` 线程跑 `nx_start_task` | bl 构建 **=y**；app 构建 **=not set** |
| 13b | `nx_bringup` | `:452` | **否则**：直接在当前线程上 `nx_start_application()` | app 走这条 |
| 14 | `nx_start_application` | `:297` | `CONFIG_ETC_ROMFS` ⇒ `nx_romfsetc()`（挂 `/etc`） | app 有；bl 无 |
| 15 | `nx_start_application` | `:321` | `CONFIG_BOARD_LATE_INITIALIZE` ⇒ `board_late_initialize()` | bl: [`bootloader_main.c:69`](../../02_code_twin/bootloader/00-overview.md#^src-boards-rm2027-fmu-h743-src-bootloader-main-c-69) |
| 16 | `nx_start_application` | `:356-358` | `task_spawn(CONFIG_INIT_ENTRYNAME, **CONFIG_INIT_ENTRYPOINT**, …)` | bl: `"bootloader_main"`；app: `"nsh_main"` |
| 17 | 新任务 | 各自入口 | **控制权离开"内核启动"，进入板级/应用代码** | — |

---

## 2. 三个"控制权交接点"（本篇的重点）

### 交接点 A：内核 → 板级早期初始化（`__start` 阶段，③层第一次被调）

```
stm32_start.c:262   stm32_boardinitialize();
```
- **app 构建** → [`boards/rm2027/fmu-h743/src/init.c:120`](../stm32/00-reset-clock-peripherals.md#^src-boards-rm2027-fmu-h743-src-init-c-120)：复位 PWM（`:123`）、配 LED（`:126`）、配 GPIO（`:129-130`）、配 SPI（`:133`）
- **bootloader 构建** → [`boards/rm2027/fmu-h743/src/bootloader_main.c:55`](../../02_code_twin/bootloader/00-overview.md#^src-boards-rm2027-fmu-h743-src-bootloader-main-c-55)：**空函数**（USB 被 `INTERFACE_USB=0` 裁掉）

**⇒ 同一个符号名、两个不同实现 —— 靠"哪个 build 目录"来选，不是靠宏。**
（这正是 `boards/<板>/src/` 下两份文件共用同名函数的正确用法。）

### 交接点 B：内核 → 板级晚期初始化（`nx_start_application`，③层第二次被调）

```
nx_bringup.c:321   board_late_initialize();
```
- **bootloader 构建** → [`bootloader_main.c:69`](../../02_code_twin/bootloader/00-overview.md#^src-boards-rm2027-fmu-h743-src-bootloader-main-c-69)：调 `sercon_main(0,NULL)`（本板空转，见 [02_code_twin/bootloader/board-layer](../../02_code_twin/bootloader/board-layer.md) §3.1）
- **app 构建** → `boards/rm2027/fmu-h743/` 里**没有** `board_late_initialize`（grep 全目录只有 [`bootloader_main.c:69`](../../02_code_twin/bootloader/00-overview.md#^src-boards-rm2027-fmu-h743-src-bootloader-main-c-69) 一处）
  ⇒ 因为 app 的 `CONFIG_BOARD_LATE_INITIALIZE` **is not set**（`build/…_default/NuttX/nuttx/.config:789`）⇒ **这个函数根本不会被调用**。

**⇒ 一个容易误解的点：`CONFIG_BOARD_LATE_INITIALIZE` 不只是"要不要调"，它还会改变线程模型**——
打开时 `AppBringUp` 是**新线程**（`:443`），关闭时 `nx_start_application()` 跑在**调用者线程**上（`:452`）。

### 交接点 C：内核 → 第一个用户任务（`task_spawn`）

```
nx_bringup.c:356-358
  ret = task_spawn(CONFIG_INIT_ENTRYNAME, CONFIG_INIT_ENTRYPOINT, NULL, &attr, argv, NULL);
```

| 构建 | `CONFIG_INIT_ENTRYNAME` | `CONFIG_INIT_ENTRYPOINT` | 依据 |
|---|---|---|---|
| bootloader | `"bootloader_main"` | `"bootloader_main"` | `.config:601-602`；defconfig `:45` |
| app | `"nsh_main"` | `"nsh_main"` | `.config:707-708`；nsh/defconfig `:116` |

生效前提是 `CONFIG_INIT_ENTRY=y`（`:340` 的 `#if defined(CONFIG_INIT_ENTRY)`）——
两个构建都有（bl `.config:597`、app `.config:703`）。

> ★ **`bootloader_main` 与 `nsh_main` 都不是 `main()`。**
> NuttX 的 apps 体系在编译每个 app 时把源码里的 `main` **改名**：
> [`apps/Application.mk:328`](../../02_code_twin/bootloader/board-layer.md#^src-platforms-nuttx-NuttX-apps-Application-mk-328)（C）与 `:322`（C++）
> —— `$<_CFLAGS += -Dmain=$(addsuffix _main,$(PROGNAME_$@))`；
> 注册进 builtin 表时用 `$(PROGNAME)_main`（[`apps/Application.mk:366`](00-poweron-chain.md#^src-platforms-nuttx-NuttX-apps-Application-mk-366) / `:368`）。
> **实测**：[`apps/system/cdcacm/sercon_main.c:52`](00-poweron-chain.md#^src-platforms-nuttx-NuttX-apps-system-cdcacm-sercon-main-c-52) 写的是 `int main(...)`，
> 而 `build/rm2027_fmu-h743_bootloader/rm2027_fmu-h743_bootloader.map:2051` 里的符号名是 `sercon_main`。
> ⇒ 所以"入口"是由 `CONFIG_INIT_ENTRYPOINT` 的**字符串**决定的一个**符号名**，不是文件位置。
>
> ⚠️ **一个查得到但容易找不到的点**：apps 是 **Makefile 体系**（`Application.mk`）编的，
> **不在 `build/.../compile_commands.json` 里** —— 所以想在那里面 grep `-Dmain=` **是找不到的**（我试过，为空）。

---

## 3. `nx_start()` 里"顺序为什么不能换"的三段

| 段 | 行号 | 为什么必须在这个位置 |
|---|---|---|
| OS 基础（内存/任务表/idle） | `:514` → `:613` | `:619 g_nx_initstate = OSINIT_MEMORY` —— 后面所有 `nx_*` 都要用堆 |
| `irq_initialize()` → `up_initialize()` | `:635` / `:675` | `:692 g_nx_initstate = OSINIT_HARDWARE`；`up_initialize()` 里注册串口驱动 ⇒ **`/dev/ttyS0` 必须早于任何用它的人** |
| `nx_bringup()` | `:743` | `:739 g_nx_initstate = OSINIT_OSREADY` ⇒ "OS 完全就绪、开始多任务"；`nx_bringup` 里才有 `nxthread_create` |
| 之后 | `:747` | `g_nx_initstate = OSINIT_IDLELOOP` ⇒ 进 idle |

**⇒ 对本板 bootloader 的直接后果**：②层在 [`main.c:783`](../../02_code_twin/bootloader/uart-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-783) 里调 `cinit()` 去 `open("/dev/ttyS0")` 之前，
内核早已把 USART1 驱动注册好（第 9 步）。
**所以 NuttX 的串口驱动是本板的 bootloader 能上传固件的**前置**条件**，不是可选项。

---

## 4. "我看到的现象由谁产生"

| 现象 | 由谁 | 依据 |
|---|---|---|
| 上电后先看 I/D-Cache 打开才变快 | `__start` | `stm32_start.c:268` |
| 无论 bootloader 还是 app，**串口设备节点都一样是 `/dev/ttyS0`** | `arm_serialinit()` | [`arm_initialize.c:100`](../stm32/00-reset-clock-peripherals.md#^src-platforms-nuttx-NuttX-nuttx-arch-arm-src-common-arm-initialize-c-100) |
| 从 bootloader 跳进 app 后，app 又完整跑了一遍 `__start` | 两个构建共用同一份 `stm32_start.c` | [01_extracted/stm32/00-reset-clock-peripherals](../stm32/00-reset-clock-peripherals.md) |
| bootloader 里"灯闪"依赖内核 tick | `CONFIG_SYSTEMTICK_HOOK` | [`sched_processtimer.c:199`](../../02_code_twin/bootloader/bl-h.md#^src-platforms-nuttx-NuttX-nuttx-sched-sched-sched-processtimer-c-199) |
| `nx_start` 之后才有 `ps`、才有任务列表 | `:613 group_initialize` / `:514` 起 | — |

---

## 跳转

- **执行序下一步**（bootloader 构建）：`task_spawn("bootloader_main")` ⇒ [02_code_twin/bootloader/stm32-common-main-c](../../02_code_twin/bootloader/stm32-common-main-c.md)。
- **执行序下一步**（app 构建）：`task_spawn("nsh_main")` ⇒ [01_extracted/nuttx/nsh-and-rcS](nsh-and-rcS.md)。
- **两个构建的差异逐条对照** ⇒ [01_extracted/nuttx/bootloader-vs-app](bootloader-vs-app.md)。
- **`nx_romfsetc()` 那一步（脚本从哪来）** ⇒ [01_extracted/nuttx/romfs](romfs.md)。
- **`up_irqinitialize()` 写的那个寄存器是什么** ⇒ [01_extracted/stm32/vtor-vector-tables](../stm32/vtor-vector-tables.md)。
- **`__start` 里时钟/外设初始化细节** ⇒ [01_extracted/stm32/00-reset-clock-peripherals](../stm32/00-reset-clock-peripherals.md)。

---

## 未核实

- 第 1 步"硬件取向量"的寄存器级细节（`BOOT_ADD0` 等）未在本仓代码里核实。
- `task_spawn()` 的**第一个参数** `CONFIG_INIT_ENTRYNAME` 到底按什么规则解析成符号地址
  （builtin 注册表 vs 直接按符号名），我只确认了 [`nx_bringup.c:356`](../../02_code_twin/bootloader/stm32-common-main-c.md#^src-platforms-nuttx-NuttX-nuttx-sched-init-nx-bringup-c-356) 的调用形式，**没有**读 `task_spawn` 实现。标"未核实"。

---

## 标注源码（代码 + 本文档对它的解释）

> **这是「代码孪生」层**：上面是代码原文（带行号），下面是**本文档针对这一段说的话**。
> 行号可点，直接跳到 PX4 源码那一行。
### `boards/rm2027/fmu-h743/nuttx-config/include/board.h`
<a id="src-boards-rm2027-fmu-h743-nuttx-config-include-board-h-104"></a>
**↓ 文档在讲这里：**[`boards/rm2027/fmu-h743/nuttx-config/include/board.h:104`](00-poweron-chain.md#^src-boards-rm2027-fmu-h743-nuttx-config-include-board-h-104)

```c
   101 │ 
   102 │ #define STM32_BOARD_USEHSE
   103 │ 
▶  104 │ #define STM32_PLLCFG_PLLSRC      RCC_PLLCKSELR_PLLSRC_HSE
   105 │ 
   106 │ /* PLL1, wide 4 - 8 MHz input, enable DIVP, DIVQ, DIVR
   107 │  *
```
> **说明**：2 | start | nuttx/arch/arm/src/stm32h7/stm32_start.c:183 | 清 .bss（:209）、搬 .data（:220）、搬 ramfuncs（:235） | — | ┃ 3 | start | :249 | stm32_clockconfig() ⇐ 480 MHz PLL 在这里起来 | board.h:104 |
^src-boards-rm2027-fmu-h743-nuttx-config-include-board-h-104

### `boards/rm2027/fmu-h743/src/bootloader_main.c`
<a id="src-boards-rm2027-fmu-h743-src-bootloader-main-c-55"></a>
**↓ 文档在讲这里：**[`boards/rm2027/fmu-h743/src/bootloader_main.c:55`](00-poweron-chain.md#^src-boards-rm2027-fmu-h743-src-bootloader-main-c-55)

```c
    52 │ 
    53 │ __EXPORT void board_on_reset(int status) {}
    54 │ 
▶   55 │ __EXPORT void stm32_boardinitialize(void)
    56 │ {
    57 │ #if INTERFACE_USB
    58 │ 	/* configure USB interfaces */
```
> **说明**：4 | start | :250-251 | arm_fpuconfig()、stm32_lowsetup() | — | ┃ 5 | start | :257 → :262 → :268-269 | TCM 使能 → stm32_boardinitialize()（★ 进 ③ 板级） → 开 I/D-Cache | boards/.../src/init.c:120（app）／bootloader_main.c:55（bl） |
> **说明**：app 构建 → boards/rm2027/fmu-h743/src/init.c:120：复位 PWM（:123）、配 LED（:126）、配 GPIO（:129-130）、配 SPI（:133） ┃ bootloader 构建 → boards/rm2027/fmu-h743/src/bootloader_main.c:55：空函数（USB 被 INTERFACE_USB=0 裁掉）
^src-boards-rm2027-fmu-h743-src-bootloader-main-c-55

<a id="src-boards-rm2027-fmu-h743-src-bootloader-main-c-69"></a>
**↓ 文档在讲这里：**[`boards/rm2027/fmu-h743/src/bootloader_main.c:69`](00-poweron-chain.md#^src-boards-rm2027-fmu-h743-src-bootloader-main-c-69)

```c
    66 │ 	return 0;
    67 │ }
    68 │ 
▶   69 │ void board_late_initialize(void)
    70 │ {
    71 │ 	sercon_main(0, NULL);
    72 │ }
```
> **说明**：14 | nx_start_application | :297 | CONFIG_ETC_ROMFS ⇒ nx_romfsetc()（挂 /etc） | app 有；bl 无 | ┃ 15 | nx_start_application | :321 | CONFIG_BOARD_LATE_INITIALIZE ⇒ board_late_initialize() | bl: bootloader_main.c:69 |
> **说明**：bootloader 构建 → bootloader_main.c:69：调 sercon_main(0,NULL)（本板空转，见 02_code_twin/bootloader/board-layer §3.1）
^src-boards-rm2027-fmu-h743-src-bootloader-main-c-69

### `boards/rm2027/fmu-h743/src/init.c`
<a id="src-boards-rm2027-fmu-h743-src-init-c-120"></a>
**↓ 文档在讲这里：**[`boards/rm2027/fmu-h743/src/init.c:120`](00-poweron-chain.md#^src-boards-rm2027-fmu-h743-src-init-c-120)

```c
   117 │  *   and mapped but before any devices have been initialized.
   118 │  *
   119 │  ************************************************************************************/
▶  120 │ __EXPORT void stm32_boardinitialize(void)
   121 │ {
   122 │ 	/* Reset PWM first thing */
   123 │ 	board_on_reset(-1);
```
> **说明**：4 | start | :250-251 | arm_fpuconfig()、stm32_lowsetup() | — | ┃ 5 | start | :257 → :262 → :268-269 | TCM 使能 → stm32_boardinitialize()（★ 进 ③ 板级） → 开 I/D-Cache | boards/.../src/init.c:120（app）／bootloader_main.c:55（bl） |
> **说明**：app 构建 → boards/rm2027/fmu-h743/src/init.c:120：复位 PWM（:123）、配 LED（:126）、配 GPIO（:129-130）、配 SPI（:133）
^src-boards-rm2027-fmu-h743-src-init-c-120

### `platforms/nuttx/NuttX/apps/Application.mk`
<a id="src-platforms-nuttx-NuttX-apps-Application-mk-328"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/NuttX/apps/Application.mk:328`](00-poweron-chain.md#^src-platforms-nuttx-NuttX-apps-Application-mk-328)

```c
   325 │ 		$(call ELFCOMPILEXX, $<, $@), $(call COMPILEXX, $<, $@))
   326 │ 
   327 │ $(MAINCOBJ): $(PREFIX)%.c$(SUFFIX)$(OBJEXT): %.c
▶  328 │ 	$(eval $<_CFLAGS += ${DEFINE_PREFIX}main=$(addsuffix _main,$(PROGNAME_$@)))
   329 │ 	$(eval $<_CELFFLAGS += ${DEFINE_PREFIX}main=$(addsuffix _main,$(PROGNAME_$@)))
   330 │ 	$(if $(and $(CONFIG_MODULES),$(MODCFLAGS)), \
   331 │ 		$(call ELFCOMPILE, $<, $@), $(call COMPILE, $<, $@))
```
> **说明**：NuttX 的 apps 体系在编译每个 app 时把源码里的 main 改名： ┃ apps/Application.mk:328（C）与 :322（C++）
^src-platforms-nuttx-NuttX-apps-Application-mk-328

<a id="src-platforms-nuttx-NuttX-apps-Application-mk-366"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/NuttX/apps/Application.mk:366`](00-poweron-chain.md#^src-platforms-nuttx-NuttX-apps-Application-mk-366)

```c
   363 │ $(REGLIST): $(DEPCONFIG) Makefile
   364 │ 	$(eval PROGNAME_$@ := $(basename $(notdir $@)))
   365 │ ifeq ($(CONFIG_SCHED_USER_IDENTITY),y)
▶  366 │ 	$(call REGISTER,$(PROGNAME_$@),$(PRIORITY_$@),$(STACKSIZE_$@),$(if $(BUILD_MODULE),,$(PROGNAME_$@)_main),$(UID_$@),$(GID_$@),$(MODE_$@))
   367 │ else
   368 │ 	$(call REGISTER,$(PROGNAME_$@),$(PRIORITY_$@),$(STACKSIZE_$@),$(if $(BUILD_MODULE),,$(PROGNAME_$@)_main))
   369 │ endif
```
> **说明**：—— $<_CFLAGS += -Dmain=$(addsuffix _main,$(PROGNAME_$@))； ┃ 注册进 builtin 表时用 $(PROGNAME)_main（apps/Application.mk:366 / :368）。
^src-platforms-nuttx-NuttX-apps-Application-mk-366

### `platforms/nuttx/NuttX/apps/system/cdcacm/sercon_main.c`
<a id="src-platforms-nuttx-NuttX-apps-system-cdcacm-sercon-main-c-52"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/NuttX/apps/system/cdcacm/sercon_main.c:52`](00-poweron-chain.md#^src-platforms-nuttx-NuttX-apps-system-cdcacm-sercon-main-c-52)

```c
    49 │  *
    50 │  ****************************************************************************/
    51 │ 
▶   52 │ int main(int argc, FAR char *argv[])
    53 │ {
    54 │   struct boardioc_usbdev_ctrl_s ctrl;
    55 │   int ret;
```
> **说明**：注册进 builtin 表时用 $(PROGNAME)_main（apps/Application.mk:366 / :368）。 ┃ 实测：apps/system/cdcacm/sercon_main.c:52 写的是 int main(...)，
^src-platforms-nuttx-NuttX-apps-system-cdcacm-sercon-main-c-52

### `platforms/nuttx/NuttX/nuttx/arch/arm/src/common/arm_initialize.c`
<a id="src-platforms-nuttx-NuttX-nuttx-arch-arm-src-common-arm-initialize-c-62"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/NuttX/nuttx/arch/arm/src/common/arm_initialize.c:62`](00-poweron-chain.md#^src-platforms-nuttx-NuttX-nuttx-arch-arm-src-common-arm-initialize-c-62)

```c
    59 │  *
    60 │  ****************************************************************************/
    61 │ 
▶   62 │ void up_initialize(void)
    63 │ {
    64 │ #if CONFIG_ARCH_INTERRUPTSTACK > 7
    65 │   /* Reinitializes the stack pointer */
```
> **说明**：7 | nx_start | :635 | irq_initialize() ⇒ up_irqinitialize() ⇒ 写 NVIC_VECTAB | nuttx/sched/irq/irq_initialize.c:98 → nuttx/arch/arm/src/stm32h7/stm32_irq.c:372 / :408 | ┃ 8 | nx_start | :675 | up_initialize() ⇒ arm_initialize_stack() ⇐ 线程模式改用 PSP | nuttx/arch/arm/src/common/arm_initialize.c:62 / :67；条件是 CONFIG_ARCH_INTERRUPTSTACK > 7 |
^src-platforms-nuttx-NuttX-nuttx-arch-arm-src-common-arm-initialize-c-62

<a id="src-platforms-nuttx-NuttX-nuttx-arch-arm-src-common-arm-initialize-c-100"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/NuttX/nuttx/arch/arm/src/common/arm_initialize.c:100`](00-poweron-chain.md#^src-platforms-nuttx-NuttX-nuttx-arch-arm-src-common-arm-initialize-c-100)

```c
    97 │   /* Initialize the serial device driver */
    98 │ 
    99 │ #ifdef USE_SERIALDRIVER
▶  100 │   arm_serialinit();
   101 │ #endif
   102 │ 
   103 │   /* Initialize the network */
```
> **说明**：8 | nx_start | :675 | up_initialize() ⇒ arm_initialize_stack() ⇐ 线程模式改用 PSP | nuttx/arch/arm/src/common/arm_initialize.c:62 / :67；条件是 CONFIG_ARCH_INTERRUPTSTACK > 7 | ┃ 9 | nx_start | :679 | drivers_initialize() 注册设备驱动（/dev/ttyS0 在这里出现，arm_serialinit() 在 arm_initialize.c:100） | — |
> **说明**：上电后先看 I/D-Cache 打开才变快 | start | stm32_start.c:268 | ┃ 无论 bootloader 还是 app，串口设备节点都一样是 /dev/ttyS0 | arm_serialinit() | arm_initialize.c:100 |
^src-platforms-nuttx-NuttX-nuttx-arch-arm-src-common-arm-initialize-c-100

### `platforms/nuttx/NuttX/nuttx/arch/arm/src/stm32/stm32_irq.c`
<a id="src-platforms-nuttx-NuttX-nuttx-arch-arm-src-stm32-stm32-irq-c-372"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/NuttX/nuttx/arch/arm/src/stm32/stm32_irq.c:372`](00-poweron-chain.md#^src-platforms-nuttx-NuttX-nuttx-arch-arm-src-stm32-stm32-irq-c-372)

```c
   369 │   up_irq_enable();
   370 │ #endif
   371 │ }
▶  372 │ 
   373 │ /****************************************************************************
   374 │  * Name: up_disable_irq
   375 │  *
```
> **说明**：6 | nx_start | :315 → nuttx/sched/init/nx_start.c:506 | NuttX 内核启动 | — | ┃ 7 | nx_start | :635 | irq_initialize() ⇒ up_irqinitialize() ⇒ 写 NVIC_VECTAB | nuttx/sched/irq/irq_initialize.c:98 → nuttx/arch/arm/src/stm32h7/stm32_irq.c:372 / :408 |
^src-platforms-nuttx-NuttX-nuttx-arch-arm-src-stm32-stm32-irq-c-372

### `platforms/nuttx/NuttX/nuttx/arch/arm/src/stm32/stm32_start.c`
<a id="src-platforms-nuttx-NuttX-nuttx-arch-arm-src-stm32-stm32-start-c-183"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/NuttX/nuttx/arch/arm/src/stm32/stm32_start.c:183`](00-poweron-chain.md#^src-platforms-nuttx-NuttX-nuttx-arch-arm-src-stm32-stm32-start-c-183)

```c
   180 │ #ifdef USE_EARLYSERIALINIT
   181 │   arm_earlyserialinit();
   182 │ #endif
▶  183 │   showprogress('D');
   184 │ 
   185 │   /* For the case of the separate user-/kernel-space build, perform whatever
   186 │    * platform specific initialization of the user memory is required.
```
> **说明**：1 | 硬件 | — | 取初始 SP + 复位向量 | — | ┃ 2 | start | nuttx/arch/arm/src/stm32h7/stm32_start.c:183 | 清 .bss（:209）、搬 .data（:220）、搬 ramfuncs（:235） | — |
^src-platforms-nuttx-NuttX-nuttx-arch-arm-src-stm32-stm32-start-c-183

### `platforms/nuttx/NuttX/nuttx/sched/init/nx_bringup.c`
<a id="src-platforms-nuttx-NuttX-nuttx-sched-init-nx-bringup-c-356"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/NuttX/nuttx/sched/init/nx_bringup.c:356`](00-poweron-chain.md#^src-platforms-nuttx-NuttX-nuttx-sched-init-nx-bringup-c-356)

```c
   353 │                    USERSPACE->us_entrypoint,
   354 │                    NULL, &attr, argv, NULL);
   355 │ #  else
▶  356 │   ret = task_spawn(CONFIG_INIT_ENTRYNAME,
   357 │                    CONFIG_INIT_ENTRYPOINT,
   358 │                    NULL, &attr, argv, NULL);
   359 │ #  endif
```
> **说明**：task_spawn() 的第一个参数 CONFIG_INIT_ENTRYNAME 到底按什么规则解析成符号地址 ┃ （builtin 注册表 vs 直接按符号名），我只确认了 nx_bringup.c:356 的调用形式，没有读 task_spawn 实现。标"未核实"。
^src-platforms-nuttx-NuttX-nuttx-sched-init-nx-bringup-c-356

<a id="src-platforms-nuttx-NuttX-nuttx-sched-init-nx-bringup-c-494"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/NuttX/nuttx/sched/init/nx_bringup.c:494`](00-poweron-chain.md#^src-platforms-nuttx-NuttX-nuttx-sched-init-nx-bringup-c-494)

```c
   491 │  *
   492 │  ****************************************************************************/
   493 │ 
▶  494 │ int nx_bringup(void)
   495 │ {
   496 │   sched_trace_begin();
   497 │ 
```
> **说明**：9 | nx_start | :679 | drivers_initialize() 注册设备驱动（/dev/ttyS0 在这里出现，arm_serialinit() 在 arm_initialize.c:100） | — | ┃ 10 | nx_start | :743 | nx_bringup() | nuttx/sched/init/nx_bringup.c:494 |
^src-platforms-nuttx-NuttX-nuttx-sched-init-nx-bringup-c-494

### `platforms/nuttx/NuttX/nuttx/sched/init/nx_start.c`
<a id="src-platforms-nuttx-NuttX-nuttx-sched-init-nx-start-c-506"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/NuttX/nuttx/sched/init/nx_start.c:506`](00-poweron-chain.md#^src-platforms-nuttx-NuttX-nuttx-sched-init-nx-start-c-506)

```c
   503 │  *
   504 │  ****************************************************************************/
   505 │ 
▶  506 │ void nx_start(void)
   507 │ {
   508 │   int i;
   509 │ 
```
> **说明**：5 | start | :257 → :262 → :268-269 | TCM 使能 → stm32_boardinitialize()（★ 进 ③ 板级） → 开 I/D-Cache | boards/.../src/init.c:120（app）／bootloader_main.c:55（bl） | ┃ 6 | nx_start | :315 → nuttx/sched/init/nx_start.c:506 | NuttX 内核启动 | — |
^src-platforms-nuttx-NuttX-nuttx-sched-init-nx-start-c-506

### `platforms/nuttx/NuttX/nuttx/sched/irq/irq_initialize.c`
<a id="src-platforms-nuttx-NuttX-nuttx-sched-irq-irq-initialize-c-98"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/NuttX/nuttx/sched/irq/irq_initialize.c:98`](00-poweron-chain.md#^src-platforms-nuttx-NuttX-nuttx-sched-irq-irq-initialize-c-98)

```c
    95 │   irqchain_initialize();
    96 │ #endif
    97 │ 
▶   98 │   up_irqinitialize();
    99 │ 
   100 │ #ifdef CONFIG_ARCH_PROTECT_ZERO_ADDRESS
   101 │   up_debugpoint_add(DEBUGPOINT_WATCHPOINT_RW, 0, 0,
```
> **说明**：6 | nx_start | :315 → nuttx/sched/init/nx_start.c:506 | NuttX 内核启动 | — | ┃ 7 | nx_start | :635 | irq_initialize() ⇒ up_irqinitialize() ⇒ 写 NVIC_VECTAB | nuttx/sched/irq/irq_initialize.c:98 → nuttx/arch/arm/src/stm32h7/stm32_irq.c:372 / :408 |
^src-platforms-nuttx-NuttX-nuttx-sched-irq-irq-initialize-c-98

### `platforms/nuttx/NuttX/nuttx/sched/sched/sched_processtimer.c`
<a id="src-platforms-nuttx-NuttX-nuttx-sched-sched-sched-processtimer-c-199"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/NuttX/nuttx/sched/sched/sched_processtimer.c:199`](00-poweron-chain.md#^src-platforms-nuttx-NuttX-nuttx-sched-sched-sched-processtimer-c-199)

```c
   196 │ 
   197 │   wd_timer(clock_systime_ticks());
   198 │ 
▶  199 │ #ifdef CONFIG_SYSTEMTICK_HOOK
   200 │   /* Call out to a user-provided function in order to perform board-specific,
   201 │    * custom timer operations.
   202 │    */
```
> **说明**：从 bootloader 跳进 app 后，app 又完整跑了一遍 start | 两个构建共用同一份 stm32_start.c | 01_extracted/stm32/00-reset-clock-peripherals | ┃ bootloader 里"灯闪"依赖内核 tick | CONFIG_SYSTEMTICK_HOOK | sched_processtimer.c:199 |
^src-platforms-nuttx-NuttX-nuttx-sched-sched-sched-processtimer-c-199

### `platforms/nuttx/src/bootloader/stm/stm32_common/main.c`
<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-783"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:783`](00-poweron-chain.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-783)

```c
   780 │ 
   781 │ 	/* start the interface */
   782 │ #if INTERFACE_USART
▶  783 │ 	cinit(BOARD_INTERFACE_CONFIG_USART, USART);
   784 │ #endif
   785 │ #if INTERFACE_USB
   786 │ 	cinit(BOARD_INTERFACE_CONFIG_USB, USB);
```
> **说明**：⇒ 对本板 bootloader 的直接后果：②层在 main.c:783 里调 cinit() 去 open("/dev/ttyS0") 之前，
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-783
