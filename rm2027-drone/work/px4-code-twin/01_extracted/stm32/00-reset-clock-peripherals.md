# STM32H743：复位向量 → 时钟树 → 外设初始化

> **层**：01 提炼知识（H7 芯片侧的最小知识集）
> **素材**：`nuttx/arch/arm/src/armv7-m/arm_vectors.c`、`nuttx/arch/arm/src/stm32h7/stm32_start.c`、
> `stm32_rcc.c`、`stm32h7x3xx_rcc.c`、`stm32_lowputc.c`、`stm32_irq.c`、
> 本板 `boards/rm2027/fmu-h743/nuttx-config/include/board.h`
> **被谁引用**：[01_extracted/nuttx/00-poweron-chain](../nuttx/00-poweron-chain.md)、[02_code_twin/bootloader/00-overview](../../02_code_twin/bootloader/00-overview.md)

---

## 1. 复位向量表：`_vectors` 的第 0/1 项

```
nuttx/arch/arm/src/armv7-m/arm_vectors.c
:51   #define IDLE_STACK (_ebss + CONFIG_IDLETHREAD_STACKSIZE)      ← 向量表第 0 个字 = 初始 SP
:59   extern void __start(void);
:61-67 static void start(void)  { mov lr,#0 ; b __start }          ← 向量表第 1 个字指向它
:91   const void * const _vectors[] locate_data(".vectors") aligned_data(VECTAB_ALIGN) =
:96       IDLE_STACK,
:100      start,
:104      [2 ... NVIC_IRQ_PENDSV] = &exception_common,            ← 其余异常都走同一个入口
:105-106  [(NVIC_IRQ_PENDSV + 1) ... (15 + ARMV7M_PERIPHERAL_INTERRUPTS)] = &exception_direct
```

**⇒ 两条关键认知**：
1. **`_vectors` 是一个 C 数组**（不是汇编文件），用 `locate_data(".vectors")` 塞进 `.vectors` 段。
2. 除 `SysTick/PendSV` 之外的**所有**外设中断都指向 `exception_direct`，
   由 NuttX 的公共异常入口分发（这意味着中断分发表在 RAM 里，见 [01_extracted/stm32/vtor-vector-tables](vtor-vector-tables.md) §4）。

**⇒ 本板镜像里它落在哪**（实测）：
`arm-none-eabi-nm build/rm2027_fmu-h743_bootloader/rm2027_fmu-h743_bootloader.elf` ⇒ `08000000 T _vectors`
（因为 [`bootloader_script.ld:137`](00-reset-clock-peripherals.md#^src-boards-rm2027-fmu-h743-nuttx-config-scripts-bootloader-script-ld-137) 把 `*(.vectors)` 放在 `.text` 最前，而 `.text` 进 `flash ORIGIN=0x08000000`，`:113`）。
app 构建同理，只是 [`script.ld:113`](../../02_code_twin/bootloader/stm32-common-main-c.md#^src-boards-rm2027-fmu-h743-nuttx-config-scripts-script-ld-113) 的 ORIGIN 是 `0x08020000`。

---

## 2. `__start` 的 8 个动作（`stm32_start.c`）

| 行号 | 动作 | 为什么在这个位置 |
|---|---|---|
| `:203` | `mpu_early_reset()` | 在**任何数据访问**之前，保证 MPU 是复位态 |
| `:209-212` | 清 `.bss` | 手写内联，注释 `:205-207` 原话：*"just to be certain that there are no issues with the state of global variables"*（**不用 `memset`**） |
| `:220-225` | 把 `.data` 从 flash 搬到 SRAM | 源在 `_eronly`（[`bootloader_script.ld:173`](00-reset-clock-peripherals.md#^src-boards-rm2027-fmu-h743-nuttx-config-scripts-bootloader-script-ld-173)） |
| `:234-241` | 搬 ramfuncs（`CONFIG_ARCH_RAMFUNCS`） | 注释 `:230-231`：**必须早于 `stm32_clockconfig()`**，因为改时钟的代码本身要在 RAM 里跑 |
| **`:249`** | **`stm32_clockconfig()`** | ★ 见 §3 |
| `:250-251` | `arm_fpuconfig()`、`stm32_lowsetup()` | 开 FPU；`stm32_lowsetup()`（[`stm32_lowputc.c:358`](00-reset-clock-peripherals.md#^src-platforms-nuttx-NuttX-nuttx-arch-arm-src-stm32-stm32-lowputc-c-358)）配"早期串口"以便立刻能打字符 |
| `:257` | `stm32_tcmenable()`（`:130` 定义，`static inline`） | 使能 ITCM/DTCM —— NuttX 的堆布局依赖它 |
| **`:262`** | **`stm32_boardinitialize()`** | ★ **控制权交给 ③ 板级**（app: [`init.c:120`](00-reset-clock-peripherals.md#^src-boards-rm2027-fmu-h743-src-init-c-120)；bl: [`bootloader_main.c:55`](../../02_code_twin/bootloader/00-overview.md#^src-boards-rm2027-fmu-h743-src-bootloader-main-c-55)） |
| `:268-269` | `up_enable_icache()` / `up_enable_dcache()` | 注释 `:265-267`；**放在板级初始化之后** |
| `:274` | `up_perf_init()`（`CONFIG_ARCH_PERF_EVENTS`） | — |
| `:280` | `arm_earlyserialinit()`（`USE_EARLYSERIALINIT`） | — |
| `:297` | `stm32_mpuinitialize()`（`CONFIG_ARM_MPU`） | — |
| **`:315`** | **`nx_start()`** | 离开芯片层，进 NuttX 内核 |
| `:319` | `for(;;);` | 注释 `:317`：*"Shouldn't get here"* |

### ★ 顺序上的两个"必须"

- **`.data` 搬完才能调任何 C 函数** ⇒ `:220` 早于 `:249`。
- **ramfuncs 搬完才能改时钟** ⇒ `:234` 早于 `:249`（否则改 PLL 时代码所在 flash 的等待周期还没对上）。

---

## 3. 时钟树：从 25 MHz 晶振到 480 MHz

### 3.1 调用链

```
stm32_start.c:249  stm32_clockconfig()                       stm32_rcc.c:98
                     :103  rcc_reset()                        ← 注释 :101：保证从复位态开始
                     :124  stm32_stdclockconfig()             stm32h7x3xx_rcc.c:696
                             :841-846  写 RCC_PLLCKSELR（源 = HSE，M1/M2/M3）
                             :852-...  写 PLL1 的 N/P/Q/R
                             :206      等 RCC_CR 的 CSION/PLL1ON 就绪位
                     :131  rcc_enableperipherals()            ← 按 CONFIG_* 打开各外设时钟
                     :136  stm32_iocompensation()（若配置）
```

**选哪个 rcc 文件**：[`stm32_rcc.c:61`](00-reset-clock-peripherals.md#^src-platforms-nuttx-NuttX-nuttx-arch-arm-src-stm32-stm32-rcc-c-61) —— `CONFIG_STM32H7_STM32H7X3XX` ⇒ `#include "stm32h7x3xx_rcc.c"`。
本板该键**两个构建都是 `y`**（bl `.config:264`、app `.config:297`）。

### 3.2 本板的 PLL 参数（全部在 `board.h`）

| 量 | 值 | 依据 |
|---|---|---|
| 晶振 | **25 MHz** | `board.h:74 STM32_BOARD_XTAL 25000000ul`，`:78` 即 HSE |
| PLL 源 | **HSE** | `board.h:104 STM32_PLLCFG_PLLSRC = RCC_PLLCKSELR_PLLSRC_HSE` |
| PLL1 M / N | 5 / 192 | [`board.h:124`](00-reset-clock-peripherals.md#^src-boards-rm2027-fmu-h743-nuttx-config-include-board-h-124) / `:125` |
| ⇒ VCO1 | `25/5*192` = **960 MHz** | [`board.h:130`](00-reset-clock-peripherals.md#^src-boards-rm2027-fmu-h743-nuttx-config-include-board-h-130) |
| PLL1 P | 2 | [`board.h:126`](00-reset-clock-peripherals.md#^src-boards-rm2027-fmu-h743-nuttx-config-include-board-h-126) |
| ⇒ **SYSCLK / CPUCLK** | 960/2 = **480 MHz** | [`board.h:131`](00-reset-clock-peripherals.md#^src-boards-rm2027-fmu-h743-nuttx-config-include-board-h-131) / `:181-182` |
| HCLK（D2/D3） | CPUCLK/2 = **240 MHz** | [`board.h:192`](00-reset-clock-peripherals.md#^src-boards-rm2027-fmu-h743-nuttx-config-include-board-h-192) |
| ACLK（D1） | CPUCLK/2 = 240 MHz | [`board.h:191`](00-reset-clock-peripherals.md#^src-boards-rm2027-fmu-h743-nuttx-config-include-board-h-191) |
| PCLK1 | HCLK/2 = 120 MHz | [`board.h:198`](00-reset-clock-peripherals.md#^src-boards-rm2027-fmu-h743-nuttx-config-include-board-h-198) |
| PLL2 / PLL3 | 960/5*96 → 各自 /5 等 | [`board.h:146`](00-reset-clock-peripherals.md#^src-boards-rm2027-fmu-h743-nuttx-config-include-board-h-146) |

### ★ 这一节和 bootloader 的直接关系：`SysTick` 的 1 ms

```
②层 main.c:102   .systick_mhz = STM32_CPUCLK_FREQUENCY / 1000000 = 480
②层 main.c:365-372 arch_systic_init():
                   systick_set_clocksource(CLKSOURCE_PROCESOR)      ← = 处理器时钟 = 480 MHz
                   systick_set_reload(480 * 1000)                    ← 480000
                   systick_interrupt_enable(); systick_counter_enable();
①层 bl.c:447-450  sys_tick_handler() 里每 50 个 tick 翻一次 LED   ⇒ 50 ms ⇒ 约 10 Hz
```

**⇒ 如果时钟树配错（例如 PLL 没起来、跑在 64 MHz HSI 上），SysTick 周期就不是 1 ms，
`bl.c` 的所有超时（`:655`）都会等比拉长** —— 症状是"上传等待时间不对"，而不是报错。

---

## 4. 外设初始化：两个时间点，两组人

| 时间点 | 函数 | 谁实现 | 干了什么 |
|---|---|---|---|
| `__start:262`（内核起来**之前**） | `stm32_boardinitialize()` | [`boards/rm2027/fmu-h743/src/init.c:120`](00-reset-clock-peripherals.md#^src-boards-rm2027-fmu-h743-src-init-c-120)（app）/ [`bootloader_main.c:55`](../../02_code_twin/bootloader/00-overview.md#^src-boards-rm2027-fmu-h743-src-bootloader-main-c-55)（bl） | app：`board_on_reset(-1)`、LED、`px4_gpio_init(PX4_GPIO_INIT_LIST)`、`stm32_spiinitialize()`
| `nx_start:675` → [`arm_initialize.c:62`](00-reset-clock-peripherals.md#^src-platforms-nuttx-NuttX-nuttx-arch-arm-src-common-arm-initialize-c-62) | `up_initialize()` | NuttX 芯片层 | `arm_initialize_stack()`、`arm_serialinit()`（`:100`，注册 `/dev/ttyS0`）、`arm_netinitialize()`、USB（条件） |
| `nx_start:679` | `drivers_initialize()` | NuttX | 注册通用驱动 |
| `boardctl(BOARDIOC_INIT)` （**app 才有**） | `board_app_initialize()` | [`init.c:157`](00-reset-clock-peripherals.md#^src-boards-rm2027-fmu-h743-src-init-c-157) | `px4_platform_init()`、DMA 分配器、LED、hardfault |

**⇒ 三条结论**：
1. **`stm32_boardinitialize()` 是"芯片引脚级"的初始化**——它跑的时候**堆还没建好**（所以只能配寄存器，不能 `malloc`）。
2. **`board_app_initialize()` 是"设备级"的初始化**——它跑的时候 NuttX 已经完整（`px4_platform_init()` 要用 hrt/工作队列）。
3. **bootloader 构建里 `board_app_initialize()` 恒 `return 0`（[`bootloader_main.c:64`](00-reset-clock-peripherals.md#^src-boards-rm2027-fmu-h743-src-bootloader-main-c-64)）**，
   而且它的调用者 `nsh` 也不存在 ⇒ **bootloader 不做"设备级"初始化**，只做 `board_init()`（②层 [`main.c:682`](../../02_code_twin/bootloader/ecc-scrub-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-682)）。

---

## 5. "我看到的现象由谁产生"

| 现象 | 由谁 | 依据 |
|---|---|---|
| 上电后有一段"看不见的空白"才可能有输出 | `__start` 的 `.bss`/`.data` 搬运 + 时钟配置 | [`stm32_start.c:209`](00-reset-clock-peripherals.md#^src-platforms-nuttx-NuttX-nuttx-arch-arm-src-stm32-stm32-start-c-209) |
| 早期串口能在时钟配好前就打字符 | `stm32_lowsetup()` | `:251`（[`stm32_lowputc.c:358`](00-reset-clock-peripherals.md#^src-platforms-nuttx-NuttX-nuttx-arch-arm-src-stm32-stm32-lowputc-c-358)） |
| I/D-Cache 打开后性能跳变 | `up_enable_icache/dcache()` | `:268-269` |
| bootloader 里 `/dev/ttyS0` 存在 | `arm_serialinit()` | [`arm_initialize.c:100`](00-reset-clock-peripherals.md#^src-platforms-nuttx-NuttX-nuttx-arch-arm-src-common-arm-initialize-c-100) |
| 板级 LED/引脚在 `__start` 阶段就已配好 | `stm32_boardinitialize()` | `:262` → [`init.c:120`](00-reset-clock-peripherals.md#^src-boards-rm2027-fmu-h743-src-init-c-120) / [`bootloader_main.c:55`](../../02_code_twin/bootloader/00-overview.md#^src-boards-rm2027-fmu-h743-src-bootloader-main-c-55) |
| 跳进 app 后**又完整跑了一遍 `__start`** | 两个构建共用同一份 `stm32_start.c` | — |

---

## 跳转

- **执行序下一步**（`nx_start()` 之后）→ [01_extracted/nuttx/00-poweron-chain](../nuttx/00-poweron-chain.md)。
- **`_vectors` 与 VTOR 的关系、bootloader/app 两套向量表怎么切换** → [01_extracted/stm32/vtor-vector-tables](vtor-vector-tables.md)。
- **两个 linker script 的 flash 布局（128K / 1792K / 参数扇区）** → [01_extracted/stm32/flash-layout](flash-layout.md)。
- **`board.h` 这些宏怎么从 `.px4board`/Kconfig 传进来** → [03_moc/00-build-walkthrough](../../03_moc/00-build-walkthrough.md)（task-10）。
- **③层 `init.c` 的逐行孪生** → [02_code_twin/board](../../02_code_twin/board/README.md)（task-12 负责）。

---

## 未核实

- `rcc_reset()`（定义在 [`stm32h7x3xx_rcc.c:180`](00-reset-clock-peripherals.md#^src-platforms-nuttx-NuttX-nuttx-arch-arm-src-stm32h7-stm32h7x3xx-rcc-c-180)，`static inline`）的**具体复位范围**我没有逐行读，
  只按调用点 [`stm32_rcc.c:103`](00-reset-clock-peripherals.md#^src-platforms-nuttx-NuttX-nuttx-arch-arm-src-stm32-stm32-rcc-c-103) 与注释 `:101`（*"Make sure that we are starting in the reset state"*）描述其作用。
- [`board.h:198`](00-reset-clock-peripherals.md#^src-boards-rm2027-fmu-h743-nuttx-config-include-board-h-198) 的 PCLK1 值我只核了宏定义行，**没有**回 ST 参考手册核对分频上限。
- `stm32_lowsetup()` 具体配的是哪个串口/引脚（[`stm32_lowputc.c:358`](00-reset-clock-peripherals.md#^src-platforms-nuttx-NuttX-nuttx-arch-arm-src-stm32-stm32-lowputc-c-358) 未展开）；
  与"early serial"和 USART1 的关系**未核实**。

---

## 标注源码（代码 + 本文档对它的解释）

> **这是「代码孪生」层**：上面是代码原文（带行号），下面是**本文档针对这一段说的话**。
> 行号可点，直接跳到 PX4 源码那一行。
### `boards/rm2027/fmu-h743/nuttx-config/include/board.h`
<a id="src-boards-rm2027-fmu-h743-nuttx-config-include-board-h-124"></a>
**↓ 文档在讲这里：**[`boards/rm2027/fmu-h743/nuttx-config/include/board.h:124`](00-reset-clock-peripherals.md#^src-boards-rm2027-fmu-h743-nuttx-config-include-board-h-124)

```c
   121 │ 				 RCC_PLLCFGR_DIVP1EN | \
   122 │ 				 RCC_PLLCFGR_DIVQ1EN | \
   123 │ 				 RCC_PLLCFGR_DIVR1EN)
▶  124 │ #define STM32_PLLCFG_PLL1M       RCC_PLLCKSELR_DIVM1(5)
   125 │ #define STM32_PLLCFG_PLL1N       RCC_PLL1DIVR_N1(192)
   126 │ #define STM32_PLLCFG_PLL1P       RCC_PLL1DIVR_P1(2)
   127 │ #define STM32_PLLCFG_PLL1Q       RCC_PLL1DIVR_Q1(4)
```
> **说明**：PLL 源 | HSE | board.h:104 STM32_PLLCFG_PLLSRC = RCC_PLLCKSELR_PLLSRC_HSE | ┃ PLL1 M / N | 5 / 192 | board.h:124 / :125 |
^src-boards-rm2027-fmu-h743-nuttx-config-include-board-h-124

<a id="src-boards-rm2027-fmu-h743-nuttx-config-include-board-h-126"></a>
**↓ 文档在讲这里：**[`boards/rm2027/fmu-h743/nuttx-config/include/board.h:126`](00-reset-clock-peripherals.md#^src-boards-rm2027-fmu-h743-nuttx-config-include-board-h-126)

```c
   123 │ 				 RCC_PLLCFGR_DIVR1EN)
   124 │ #define STM32_PLLCFG_PLL1M       RCC_PLLCKSELR_DIVM1(5)
   125 │ #define STM32_PLLCFG_PLL1N       RCC_PLL1DIVR_N1(192)
▶  126 │ #define STM32_PLLCFG_PLL1P       RCC_PLL1DIVR_P1(2)
   127 │ #define STM32_PLLCFG_PLL1Q       RCC_PLL1DIVR_Q1(4)
   128 │ #define STM32_PLLCFG_PLL1R       RCC_PLL1DIVR_R1(8)
   129 │ 
```
> **说明**：⇒ VCO1 | 25/5*192 = 960 MHz | board.h:130 | ┃ PLL1 P | 2 | board.h:126 |
^src-boards-rm2027-fmu-h743-nuttx-config-include-board-h-126

<a id="src-boards-rm2027-fmu-h743-nuttx-config-include-board-h-130"></a>
**↓ 文档在讲这里：**[`boards/rm2027/fmu-h743/nuttx-config/include/board.h:130`](00-reset-clock-peripherals.md#^src-boards-rm2027-fmu-h743-nuttx-config-include-board-h-130)

```c
   127 │ #define STM32_PLLCFG_PLL1Q       RCC_PLL1DIVR_Q1(4)
   128 │ #define STM32_PLLCFG_PLL1R       RCC_PLL1DIVR_R1(8)
   129 │ 
▶  130 │ #define STM32_VCO1_FREQUENCY     ((STM32_HSE_FREQUENCY / 5) * 192)
   131 │ #define STM32_PLL1P_FREQUENCY    (STM32_VCO1_FREQUENCY / 2)
   132 │ #define STM32_PLL1Q_FREQUENCY    (STM32_VCO1_FREQUENCY / 4)
   133 │ #define STM32_PLL1R_FREQUENCY    (STM32_VCO1_FREQUENCY / 8)
```
> **说明**：PLL1 M / N | 5 / 192 | board.h:124 / :125 | ┃ ⇒ VCO1 | 25/5*192 = 960 MHz | board.h:130 |
^src-boards-rm2027-fmu-h743-nuttx-config-include-board-h-130

<a id="src-boards-rm2027-fmu-h743-nuttx-config-include-board-h-131"></a>
**↓ 文档在讲这里：**[`boards/rm2027/fmu-h743/nuttx-config/include/board.h:131`](00-reset-clock-peripherals.md#^src-boards-rm2027-fmu-h743-nuttx-config-include-board-h-131)

```c
   128 │ #define STM32_PLLCFG_PLL1R       RCC_PLL1DIVR_R1(8)
   129 │ 
   130 │ #define STM32_VCO1_FREQUENCY     ((STM32_HSE_FREQUENCY / 5) * 192)
▶  131 │ #define STM32_PLL1P_FREQUENCY    (STM32_VCO1_FREQUENCY / 2)
   132 │ #define STM32_PLL1Q_FREQUENCY    (STM32_VCO1_FREQUENCY / 4)
   133 │ #define STM32_PLL1R_FREQUENCY    (STM32_VCO1_FREQUENCY / 8)
   134 │ 
```
> **说明**：PLL1 P | 2 | board.h:126 | ┃ ⇒ SYSCLK / CPUCLK | 960/2 = 480 MHz | board.h:131 / :181-182 |
^src-boards-rm2027-fmu-h743-nuttx-config-include-board-h-131

<a id="src-boards-rm2027-fmu-h743-nuttx-config-include-board-h-146"></a>
**↓ 文档在讲这里：**[`boards/rm2027/fmu-h743/nuttx-config/include/board.h:146`](00-reset-clock-peripherals.md#^src-boards-rm2027-fmu-h743-nuttx-config-include-board-h-146)

```c
   143 │  * ★ 输出 96/96/96 与 matek 一致（SPI123 / SPI45 / ADC 的时钟源）
   144 │  *   matek 原式：M=2,N=48 → VCO 192MHz, /2 = 96MHz
   145 │  */
▶  146 │ #define STM32_PLLCFG_PLL2M       RCC_PLLCKSELR_DIVM2(5)
   147 │ #define STM32_PLLCFG_PLL2N       RCC_PLL2DIVR_N2(96)
   148 │ #define STM32_PLLCFG_PLL2P       RCC_PLL2DIVR_P2(5)
   149 │ #define STM32_PLLCFG_PLL2Q       RCC_PLL2DIVR_Q2(5)
```
> **说明**：PCLK1 | HCLK/2 = 120 MHz | board.h:198 | ┃ PLL2 / PLL3 | 960/5*96 → 各自 /5 等 | board.h:146 |
^src-boards-rm2027-fmu-h743-nuttx-config-include-board-h-146

<a id="src-boards-rm2027-fmu-h743-nuttx-config-include-board-h-191"></a>
**↓ 文档在讲这里：**[`boards/rm2027/fmu-h743/nuttx-config/include/board.h:191`](00-reset-clock-peripherals.md#^src-boards-rm2027-fmu-h743-nuttx-config-include-board-h-191)

```c
   188 │  */
   189 │ 
   190 │ #define STM32_RCC_D1CFGR_HPRE   RCC_D1CFGR_HPRE_SYSCLKd2        /* HCLK  = SYSCLK / 2 */
▶  191 │ #define STM32_ACLK_FREQUENCY    (STM32_CPUCLK_FREQUENCY / 2)    /* ACLK in D1, HCLK3 in D1 */
   192 │ #define STM32_HCLK_FREQUENCY    (STM32_CPUCLK_FREQUENCY / 2)    /* HCLK in D2, HCLK4 in D3 */
   193 │ #define STM32_BOARD_HCLK        STM32_HCLK_FREQUENCY            /* same as above, to satisfy compiler */
   194 │ 
```
> **说明**：HCLK（D2/D3） | CPUCLK/2 = 240 MHz | board.h:192 | ┃ ACLK（D1） | CPUCLK/2 = 240 MHz | board.h:191 |
^src-boards-rm2027-fmu-h743-nuttx-config-include-board-h-191

<a id="src-boards-rm2027-fmu-h743-nuttx-config-include-board-h-192"></a>
**↓ 文档在讲这里：**[`boards/rm2027/fmu-h743/nuttx-config/include/board.h:192`](00-reset-clock-peripherals.md#^src-boards-rm2027-fmu-h743-nuttx-config-include-board-h-192)

```c
   189 │ 
   190 │ #define STM32_RCC_D1CFGR_HPRE   RCC_D1CFGR_HPRE_SYSCLKd2        /* HCLK  = SYSCLK / 2 */
   191 │ #define STM32_ACLK_FREQUENCY    (STM32_CPUCLK_FREQUENCY / 2)    /* ACLK in D1, HCLK3 in D1 */
▶  192 │ #define STM32_HCLK_FREQUENCY    (STM32_CPUCLK_FREQUENCY / 2)    /* HCLK in D2, HCLK4 in D3 */
   193 │ #define STM32_BOARD_HCLK        STM32_HCLK_FREQUENCY            /* same as above, to satisfy compiler */
   194 │ 
   195 │ /* APB1 clock (PCLK1) is HCLK/2 (120 MHz) */
```
> **说明**：⇒ SYSCLK / CPUCLK | 960/2 = 480 MHz | board.h:131 / :181-182 | ┃ HCLK（D2/D3） | CPUCLK/2 = 240 MHz | board.h:192 |
^src-boards-rm2027-fmu-h743-nuttx-config-include-board-h-192

<a id="src-boards-rm2027-fmu-h743-nuttx-config-include-board-h-198"></a>
**↓ 文档在讲这里：**[`boards/rm2027/fmu-h743/nuttx-config/include/board.h:198`](00-reset-clock-peripherals.md#^src-boards-rm2027-fmu-h743-nuttx-config-include-board-h-198)

```c
   195 │ /* APB1 clock (PCLK1) is HCLK/2 (120 MHz) */
   196 │ 
   197 │ #define STM32_RCC_D2CFGR_D2PPRE1  RCC_D2CFGR_D2PPRE1_HCLKd2       /* PCLK1 = HCLK / 2 */
▶  198 │ #define STM32_PCLK1_FREQUENCY     (STM32_HCLK_FREQUENCY/2)
   199 │ 
   200 │ /* APB2 clock (PCLK2) is HCLK/2 (120 MHz) */
   201 │ 
```
> **说明**：ACLK（D1） | CPUCLK/2 = 240 MHz | board.h:191 | ┃ PCLK1 | HCLK/2 = 120 MHz | board.h:198 |
> **说明**：只按调用点 stm32_rcc.c:103 与注释 :101（*"Make sure that we are starting in the reset state"*）描述其作用。 ┃ board.h:198 的 PCLK1 值我只核了宏定义行，没有回 ST 参考手册核对分频上限。
^src-boards-rm2027-fmu-h743-nuttx-config-include-board-h-198

### `boards/rm2027/fmu-h743/nuttx-config/scripts/bootloader_script.ld`
<a id="src-boards-rm2027-fmu-h743-nuttx-config-scripts-bootloader-script-ld-137"></a>
**↓ 文档在讲这里：**[`boards/rm2027/fmu-h743/nuttx-config/scripts/bootloader_script.ld:137`](00-reset-clock-peripherals.md#^src-boards-rm2027-fmu-h743-nuttx-config-scripts-bootloader-script-ld-137)

```c
   134 │ {
   135 │ 	.text : {
   136 │ 		_stext = ABSOLUTE(.);
▶  137 │ 		*(.vectors)
   138 │ 		. = ALIGN(32);
   139 │ 		*(.text .text.*)
   140 │ 		*(.fixup)
```
> **说明**：arm-none-eabi-nm build/rm2027_fmu-h743_bootloader/rm2027_fmu-h743_bootloader.elf ⇒ 08000000 T _vectors ┃ （因为 bootloader_script.ld:137 把 *(.vectors) 放在 .text 最前，而 .text 进 flash ORIGIN=0x08000000，:113）。
^src-boards-rm2027-fmu-h743-nuttx-config-scripts-bootloader-script-ld-137

<a id="src-boards-rm2027-fmu-h743-nuttx-config-scripts-bootloader-script-ld-173"></a>
**↓ 文档在讲这里：**[`boards/rm2027/fmu-h743/nuttx-config/scripts/bootloader_script.ld:173`](00-reset-clock-peripherals.md#^src-boards-rm2027-fmu-h743-nuttx-config-scripts-bootloader-script-ld-173)

```c
   170 │ 	} > flash
   171 │ 	__exidx_end = ABSOLUTE(.);
   172 │ 
▶  173 │ 	_eronly = ABSOLUTE(.);
   174 │ 
   175 │ 	.data : {
   176 │ 		_sdata = ABSOLUTE(.);
```
> **说明**：:209-212 | 清 .bss | 手写内联，注释 :205-207 原话：*"just to be certain that there are no issues with the state of global variables"*（不用 memset） | ┃ :220-225 | 把 .data 从 flash 搬到 SRAM | 源在 _eronly（bootloader_script.ld:173） |
^src-boards-rm2027-fmu-h743-nuttx-config-scripts-bootloader-script-ld-173

### `boards/rm2027/fmu-h743/nuttx-config/scripts/script.ld`
<a id="src-boards-rm2027-fmu-h743-nuttx-config-scripts-script-ld-113"></a>
**↓ 文档在讲这里：**[`boards/rm2027/fmu-h743/nuttx-config/scripts/script.ld:113`](00-reset-clock-peripherals.md#^src-boards-rm2027-fmu-h743-nuttx-config-scripts-script-ld-113)

```c
   110 │ MEMORY
   111 │ {
   112 │ 	ITCM_RAM  (rwx) : ORIGIN = 0x00000000, LENGTH =   64K
▶  113 │ 	FLASH      (rx) : ORIGIN = 0x08020000, LENGTH = 1792K /* ★ 最后 1 个 128K 扇区(0x081E0000)让给 flash 参数存储，见 src/init.c */
   114 │ 
   115 │ 	DTCM1_RAM (rwx) : ORIGIN = 0x20000000, LENGTH =   64K
   116 │ 	DTCM2_RAM (rwx) : ORIGIN = 0x20010000, LENGTH =   64K
```
> **说明**：（因为 bootloader_script.ld:137 把 *(.vectors) 放在 .text 最前，而 .text 进 flash ORIGIN=0x08000000，:113）。 ┃ app 构建同理，只是 script.ld:113 的 ORIGIN 是 0x08020000。
^src-boards-rm2027-fmu-h743-nuttx-config-scripts-script-ld-113

### `boards/rm2027/fmu-h743/src/bootloader_main.c`
<a id="src-boards-rm2027-fmu-h743-src-bootloader-main-c-55"></a>
**↓ 文档在讲这里：**[`boards/rm2027/fmu-h743/src/bootloader_main.c:55`](00-reset-clock-peripherals.md#^src-boards-rm2027-fmu-h743-src-bootloader-main-c-55)

```c
    52 │ 
    53 │ __EXPORT void board_on_reset(int status) {}
    54 │ 
▶   55 │ __EXPORT void stm32_boardinitialize(void)
    56 │ {
    57 │ #if INTERFACE_USB
    58 │ 	/* configure USB interfaces */
```
> **说明**：:257 | stm32_tcmenable()（:130 定义，static inline） | 使能 ITCM/DTCM —— NuttX 的堆布局依赖它 | ┃ :262 | stm32_boardinitialize() | ★ 控制权交给 ③ 板级（app: init.c:120；bl: bootloader_main.c:55） |
> **说明**：start:262（内核起来之前） | stm32_boardinitialize() | boards/rm2027/fmu-h743/src/init.c:120（app）/ bootloader_main.c:55（bl） | app：board_on_reset(-1)、LED、px4_gpio_init(PX4_GPIO_INIT_LIST)、stm32_spiinitialize()
^src-boards-rm2027-fmu-h743-src-bootloader-main-c-55

<a id="src-boards-rm2027-fmu-h743-src-bootloader-main-c-64"></a>
**↓ 文档在讲这里：**[`boards/rm2027/fmu-h743/src/bootloader_main.c:64`](00-reset-clock-peripherals.md#^src-boards-rm2027-fmu-h743-src-bootloader-main-c-64)

```c
    61 │ 	/* 本板无 USB：只走 INTERFACE_USART 通道 */
    62 │ }
    63 │ 
▶   64 │ __EXPORT int board_app_initialize(uintptr_t arg)
    65 │ {
    66 │ 	return 0;
    67 │ }
```
> **说明**：2. board_app_initialize() 是"设备级"的初始化——它跑的时候 NuttX 已经完整（px4_platform_init() 要用 hrt/工作队列）。 ┃ 3. bootloader 构建里 board_app_initialize() 恒 return 0（bootloader_main.c:64），
^src-boards-rm2027-fmu-h743-src-bootloader-main-c-64

### `boards/rm2027/fmu-h743/src/init.c`
<a id="src-boards-rm2027-fmu-h743-src-init-c-120"></a>
**↓ 文档在讲这里：**[`boards/rm2027/fmu-h743/src/init.c:120`](00-reset-clock-peripherals.md#^src-boards-rm2027-fmu-h743-src-init-c-120)

```c
   117 │  *   and mapped but before any devices have been initialized.
   118 │  *
   119 │  ************************************************************************************/
▶  120 │ __EXPORT void stm32_boardinitialize(void)
   121 │ {
   122 │ 	/* Reset PWM first thing */
   123 │ 	board_on_reset(-1);
```
> **说明**：:257 | stm32_tcmenable()（:130 定义，static inline） | 使能 ITCM/DTCM —— NuttX 的堆布局依赖它 | ┃ :262 | stm32_boardinitialize() | ★ 控制权交给 ③ 板级（app: init.c:120；bl: bootloader_main.c:55） |
> **说明**：start:262（内核起来之前） | stm32_boardinitialize() | boards/rm2027/fmu-h743/src/init.c:120（app）/ bootloader_main.c:55（bl） | app：board_on_reset(-1)、LED、px4_gpio_init(PX4_GPIO_INIT_LIST)、stm32_spiinitialize()
^src-boards-rm2027-fmu-h743-src-init-c-120

<a id="src-boards-rm2027-fmu-h743-src-init-c-157"></a>
**↓ 文档在讲这里：**[`boards/rm2027/fmu-h743/src/init.c:157`](00-reset-clock-peripherals.md#^src-boards-rm2027-fmu-h743-src-init-c-157)

```c
   154 │  *   any failure to indicate the nature of the failure.
   155 │  *
   156 │  ****************************************************************************/
▶  157 │ __EXPORT int board_app_initialize(uintptr_t arg)
   158 │ {
   159 │ 	/* Need hrt running before using the ADC */
   160 │ 	px4_platform_init();
```
> **说明**：nx_start:679 | drivers_initialize() | NuttX | 注册通用驱动 | ┃ boardctl(BOARDIOC_INIT) （app 才有） | board_app_initialize() | init.c:157 | px4_platform_init()、DMA 分配器、LED、hardfault |
^src-boards-rm2027-fmu-h743-src-init-c-157

### `platforms/nuttx/NuttX/nuttx/arch/arm/src/common/arm_initialize.c`
<a id="src-platforms-nuttx-NuttX-nuttx-arch-arm-src-common-arm-initialize-c-62"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/NuttX/nuttx/arch/arm/src/common/arm_initialize.c:62`](00-reset-clock-peripherals.md#^src-platforms-nuttx-NuttX-nuttx-arch-arm-src-common-arm-initialize-c-62)

```c
    59 │  *
    60 │  ****************************************************************************/
    61 │ 
▶   62 │ void up_initialize(void)
    63 │ {
    64 │ #if CONFIG_ARCH_INTERRUPTSTACK > 7
    65 │   /* Reinitializes the stack pointer */
```
> **说明**：start:262（内核起来之前） | stm32_boardinitialize() | boards/rm2027/fmu-h743/src/init.c:120（app）/ bootloader_main.c:55（bl） | app：board_on_reset(-1)、LED、px4_gpio_init(PX4_GPIO_INIT_LIST)、stm32_spiinitialize() ┃ nx_start:675 → arm_initialize.c:62 | up_initialize() | NuttX 芯片层 | arm_initialize_stack()、arm_serialinit()（:100，注册 /dev/ttyS0）、arm_netinitialize()、USB（条件） |
^src-platforms-nuttx-NuttX-nuttx-arch-arm-src-common-arm-initialize-c-62

<a id="src-platforms-nuttx-NuttX-nuttx-arch-arm-src-common-arm-initialize-c-100"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/NuttX/nuttx/arch/arm/src/common/arm_initialize.c:100`](00-reset-clock-peripherals.md#^src-platforms-nuttx-NuttX-nuttx-arch-arm-src-common-arm-initialize-c-100)

```c
    97 │   /* Initialize the serial device driver */
    98 │ 
    99 │ #ifdef USE_SERIALDRIVER
▶  100 │   arm_serialinit();
   101 │ #endif
   102 │ 
   103 │   /* Initialize the network */
```
> **说明**：I/D-Cache 打开后性能跳变 | up_enable_icache/dcache() | :268-269 | ┃ bootloader 里 /dev/ttyS0 存在 | arm_serialinit() | arm_initialize.c:100 |
^src-platforms-nuttx-NuttX-nuttx-arch-arm-src-common-arm-initialize-c-100

### `platforms/nuttx/NuttX/nuttx/arch/arm/src/stm32/stm32_lowputc.c`
<a id="src-platforms-nuttx-NuttX-nuttx-arch-arm-src-stm32-stm32-lowputc-c-358"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/NuttX/nuttx/arch/arm/src/stm32/stm32_lowputc.c:358`](00-reset-clock-peripherals.md#^src-platforms-nuttx-NuttX-nuttx-arch-arm-src-stm32-stm32-lowputc-c-358)

```c
   355 │  * usartdiv=39.0625=39 1/16th;
   356 │  *
   357 │  * First calculate:
▶  358 │  *
   359 │  *   usartdiv32 = 32 * usartdiv = fCK / (baud/2)
   360 │  *
   361 │  * (NOTE: all standard baud values are even so dividing by two does not
```
> **说明**：:249 | stm32_clockconfig() | ★ 见 §3 | ┃ :250-251 | arm_fpuconfig()、stm32_lowsetup() | 开 FPU；stm32_lowsetup()（stm32_lowputc.c:358）配"早期串口"以便立刻能打字符 |
> **说明**：上电后有一段"看不见的空白"才可能有输出 | start 的 .bss/.data 搬运 + 时钟配置 | stm32_start.c:209 | ┃ 早期串口能在时钟配好前就打字符 | stm32_lowsetup() | :251（stm32_lowputc.c:358） |
^src-platforms-nuttx-NuttX-nuttx-arch-arm-src-stm32-stm32-lowputc-c-358

### `platforms/nuttx/NuttX/nuttx/arch/arm/src/stm32/stm32_rcc.c`
<a id="src-platforms-nuttx-NuttX-nuttx-arch-arm-src-stm32-stm32-rcc-c-61"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/NuttX/nuttx/arch/arm/src/stm32/stm32_rcc.c:61`](00-reset-clock-peripherals.md#^src-platforms-nuttx-NuttX-nuttx-arch-arm-src-stm32-stm32-rcc-c-61)

```c
    58 │  ****************************************************************************/
    59 │ 
    60 │ /* Include chip-specific clocking initialization logic */
▶   61 │ 
    62 │ #if defined(CONFIG_STM32_STM32L15XX)
    63 │ #  include "stm32l15xxx_rcc.c"
    64 │ #elif defined(CONFIG_STM32_STM32F10XX)
```
> **说明**：选哪个 rcc 文件：stm32_rcc.c:61 —— CONFIG_STM32H7_STM32H7X3XX ⇒ #include "stm32h7x3xx_rcc.c"。
^src-platforms-nuttx-NuttX-nuttx-arch-arm-src-stm32-stm32-rcc-c-61

<a id="src-platforms-nuttx-NuttX-nuttx-arch-arm-src-stm32-stm32-rcc-c-103"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/NuttX/nuttx/arch/arm/src/stm32/stm32_rcc.c:103`](00-reset-clock-peripherals.md#^src-platforms-nuttx-NuttX-nuttx-arch-arm-src-stm32-stm32-rcc-c-103)

```c
   100 │  *
   101 │  * Description:
   102 │  *   The RTC needs to reset the Backup Domain to change RTCSEL and resetting
▶  103 │  *   the Backup Domain renders to disabling the LSE as consequence.
   104 │  *   In order to avoid resetting the Backup Domain when we already
   105 │  *   configured LSE we will reset the Backup Domain early (here).
   106 │  *
```
> **说明**：rcc_reset()（定义在 stm32h7x3xx_rcc.c:180，static inline）的具体复位范围我没有逐行读， ┃ 只按调用点 stm32_rcc.c:103 与注释 :101（*"Make sure that we are starting in the reset state"*）描述其作用。
^src-platforms-nuttx-NuttX-nuttx-arch-arm-src-stm32-stm32-rcc-c-103

### `platforms/nuttx/NuttX/nuttx/arch/arm/src/stm32/stm32_start.c`
<a id="src-platforms-nuttx-NuttX-nuttx-arch-arm-src-stm32-stm32-start-c-209"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/NuttX/nuttx/arch/arm/src/stm32/stm32_start.c:209`](00-reset-clock-peripherals.md#^src-platforms-nuttx-NuttX-nuttx-arch-arm-src-stm32-stm32-start-c-209)

```c
   206 │   nx_start();
   207 │ 
   208 │   /* Shouldn't get here */
▶  209 │ 
   210 │ #ifndef CONFIG_DISABLE_IDLE_LOOP
   211 │   for (; ; );
   212 │ #endif
```
> **说明**：上电后有一段"看不见的空白"才可能有输出 | start 的 .bss/.data 搬运 + 时钟配置 | stm32_start.c:209 |
^src-platforms-nuttx-NuttX-nuttx-arch-arm-src-stm32-stm32-start-c-209

### `platforms/nuttx/NuttX/nuttx/arch/arm/src/stm32h7/stm32h7x3xx_rcc.c`
<a id="src-platforms-nuttx-NuttX-nuttx-arch-arm-src-stm32h7-stm32h7x3xx-rcc-c-180"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/NuttX/nuttx/arch/arm/src/stm32h7/stm32h7x3xx_rcc.c:180`](00-reset-clock-peripherals.md#^src-platforms-nuttx-NuttX-nuttx-arch-arm-src-stm32h7-stm32h7x3xx-rcc-c-180)

```c
   177 │  *
   178 │  ****************************************************************************/
   179 │ 
▶  180 │ static inline void rcc_reset(void)
   181 │ {
   182 │   uint32_t regval;
   183 │ 
```
> **说明**：rcc_reset()（定义在 stm32h7x3xx_rcc.c:180，static inline）的具体复位范围我没有逐行读，
^src-platforms-nuttx-NuttX-nuttx-arch-arm-src-stm32h7-stm32h7x3xx-rcc-c-180

### `platforms/nuttx/src/bootloader/common/bl.c`
<a id="src-platforms-nuttx-src-bootloader-common-bl-c-447"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:447`](00-reset-clock-peripherals.md#^src-platforms-nuttx-src-bootloader-common-bl-c-447)

```c
   444 │ 			timer[i]--;
   445 │ 		}
   446 │ 
▶  447 │ 	if ((_led_state == LED_BLINK) && (timer[TIMER_LED] == 0)) {
   448 │ 		led_toggle(LED_BOOTLOADER);
   449 │ 		timer[TIMER_LED] = 50;
   450 │ 	}
```
> **说明**：①层 bl.c:447-450 sys_tick_handler() 里每 50 个 tick 翻一次 LED ⇒ 50 ms ⇒ 约 10 Hz
^src-platforms-nuttx-src-bootloader-common-bl-c-447

### `platforms/nuttx/src/bootloader/stm/stm32_common/main.c`
<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-102"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:102`](00-reset-clock-peripherals.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-102)

```c
    99 │ 	.board_type	= BOARD_TYPE,
   100 │ 	.board_rev	= 0,
   101 │ 	.fw_size	= 0,
▶  102 │ 	.systick_mhz	= STM32_CPUCLK_FREQUENCY / 1000000,
   103 │ };
   104 │ 
   105 │ static void board_init(void);
```
> **说明**：②层 main.c:102 .systick_mhz = STM32_CPUCLK_FREQUENCY / 1000000 = 480
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-102

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-365"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:365`](00-reset-clock-peripherals.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-365)

```c
   362 │ 	putreg32(0, STM32_RCC_AHB1ENR);
   363 │ }
   364 │ 
▶  365 │ inline void arch_systic_init(void)
   366 │ {
   367 │ 	/* (re)start the timer system */
   368 │ 	systick_set_clocksource(CLKSOURCE_PROCESOR);
```
> **说明**：②层 main.c:365-372 arch_systic_init():
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-365

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-682"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:682`](00-reset-clock-peripherals.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-682)

```c
   679 │ #endif
   680 │ 
   681 │ 	/* do board-specific initialisation */
▶  682 │ 	board_init();
   683 │ 
   684 │ 	/* configure the clock for bootloader activity */
   685 │ 	clock_init();
```
> **说明**：3. bootloader 构建里 board_app_initialize() 恒 return 0（bootloader_main.c:64）， ┃ 而且它的调用者 nsh 也不存在 ⇒ bootloader 不做"设备级"初始化，只做 board_init()（②层 main.c:682）。
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-682
