# VTOR 与两套向量表：bootloader → app 的"异常处理权"交接

> **层**：01 提炼知识
> **素材**：`nuttx/arch/arm/src/stm32h7/stm32_irq.c`、`nuttx/arch/arm/src/armv7-m/arm_vectors.c`、
> `nuttx/arch/arm/src/armv7-m/ram_vectors.h`、`nuttx/sched/irq/irq_initialize.c`、
> `platforms/nuttx/src/bootloader/common/bl.c`、`stm/stm32_common/main.c`
> **回答**：**为什么 bootloader 与 app 各要一套向量表？谁在什么时刻切换？切错会怎样？**

---

## 1. VTOR 是什么（一句话）

Cortex-M7 的 **VTOR**（Vector Table Offset Register）= 一个**告诉 CPU"异常向量表在内存哪个地址"**的寄存器。
复位后它有默认值；只要表不在默认位置，**软件必须自己写它**，否则中断会跳到错误的地址。

| 项 | 位置 |
|---|---|
| 寄存器地址 | [`nuttx/arch/arm/src/armv7-m/nvic.h:383`](vtor-vector-tables.md#^src-platforms-nuttx-NuttX-nuttx-arch-arm-src-armv7-m-nvic-h-383) → `NVIC_VECTAB = ARMV7M_NVIC_BASE + 0x0d08`（`:189`） |
| 对齐约束 | [`ram_vectors.h:89`](vtor-vector-tables.md#^src-platforms-nuttx-NuttX-nuttx-arch-arm-src-armv7-m-ram-vectors-h-89) `VECTAB_ALIGN`；`:57-72` 的 `NVIC_VECTAB_TBLOFF_MASK` 按表大小决定 |
| 向量表本体 | [`arm_vectors.c:91`](vtor-vector-tables.md#^src-platforms-nuttx-NuttX-nuttx-arch-arm-src-armv7-m-arm-vectors-c-91) 的 `_vectors[]`（见 [01_extracted/stm32/00-reset-clock-peripherals](00-reset-clock-peripherals.md) §1） |

---

## 2. ★ 全系统只有**三个**写 VTOR 的地方

| # | 时刻 | 谁写 | 写成什么 | 依据 |
|---|---|---|---|---|
| **1** | **启动早期（内核起来时）** | NuttX 架构层 | **当前镜像自己的 `_vectors`** | `nuttx/sched/init/nx_start.c:635 irq_initialize()` → `nuttx/sched/irq/irq_initialize.c:98 up_irqinitialize()` → [`nuttx/arch/arm/src/stm32h7/stm32_irq.c:372`](vtor-vector-tables.md#^src-platforms-nuttx-NuttX-nuttx-arch-arm-src-stm32-stm32-irq-c-372) 函数体，**`:408 putreg32((uint32_t)_vectors, NVIC_VECTAB);`** |
| **2** | **跳 app 之前** | bootloader ②层 | **app 的向量表地址** | `bl.c:429 arch_setvtor(vec_base)` → `stm/stm32_common/main.c:457-460 putreg32((uint32_t)address, NVIC_VECTAB);` |
| **3** | 同一个 bootloader 里**再次**启动内核时 | 同 #1 | 又是当前镜像的 `_vectors` | 同上；只是这次当前镜像是 app |

**⇒ 结论**：**没有任何"上电时初始化 VTOR"的代码。**

- bootloader 上电：硬件按 boot 地址取向量 → 跑到 `nx_start` → #1 把 VTOR 设成 `0x08000000`（bootloader 的 `_vectors`）。
- 跳 app：[`bl.c:429`](../../02_code_twin/bootloader/bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-c-429) 把它改成 `0x08020000`（app 的 `_vectors`）。
- app 起来：`nx_start` 里 #1 再把它写成 `0x08020000` —— **和 #2 设的是同一个值**。

**⇒ 所以 #2 这一步在"正常路径"上有点像冗余，但它是必需的**：因为 `arch_do_jump()`
（[`main.c:632`](../../02_code_twin/bootloader/bl-h.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-632)）是**直接 `bx` 到 app 的 `__start`**，app 从头跑，中间有一段
（`stm32_clockconfig()`、`stm32_boardinitialize()`，`stm32_start.c:249/262`）**在 `nx_start` 之前** ——
这段期间若来一个中断（比如 SysTick 还没关干净），VTOR 必须已经指向 app 的表，否则会跳到 bootloader 的旧处理函数。

---

## 3. 两套向量表长什么样（表内容其实"几乎一样"）

| 构建 | `_vectors` 链接地址 | 依据 |
|---|---|---|
| bootloader | **`0x08000000`** | `bootloader_script.ld:113 flash ORIGIN=0x08000000, LENGTH=128K` + `:125 EXTERN(_vectors)` + `:137 *(.vectors)` |
| app | **`0x08020000`** | `nuttx-config/scripts/script.ld:113 FLASH ORIGIN=0x08020000, LENGTH=1792K` + `:126 EXTERN(_vectors)` |

**实测**：`arm-none-eabi-nm build/rm2027_fmu-h743_bootloader/rm2027_fmu-h743_bootloader.elf | grep _vectors`
⇒ `08000000 T _vectors`。

**表的内容由 [`arm_vectors.c:91`](vtor-vector-tables.md#^src-platforms-nuttx-NuttX-nuttx-arch-arm-src-armv7-m-arm-vectors-c-91) 统一生成**（`IDLE_STACK` / `start` / `exception_common` / `exception_direct`），
⇒ **两套表的"形状"完全一样，区别只在"它住在哪个 flash 地址"**。
（`start` 会 `b __start`，而 `__start` 是**各自镜像里**的那个 ⇒ 中断与复位都自动落到当前镜像。）

---

## 4. 本板没有启用 RAM 向量表（易搞错）

`ram_vectors.h` 与 `arm_ramvec_initialize.c` 描述的是 **RAM 向量表**模式：
在 RAM 里放一份可改写的中断向量表（`g_ram_vectors`），运行时能动态挂中断处理函数。

**本板两个构建都没有 `CONFIG_ARCH_RAMVECTORS`**（**已实测**）：
```
build/rm2027_fmu-h743_bootloader/NuttX/nuttx/.config:473  # CONFIG_ARCH_RAMVECTORS is not set
build/rm2027_fmu-h743_default/NuttX/nuttx/.config:577     # CONFIG_ARCH_RAMVECTORS is not set
```
⇒ [`stm32_irq.c:410`](vtor-vector-tables.md#^src-platforms-nuttx-NuttX-nuttx-arch-arm-src-stm32-stm32-irq-c-410) 的 `#ifdef` 为假；`arm_ramvec_initialize.c:42/118` 的整段逻辑不参与编译。
**⇒ 向量表是只读的 flash 副本，中断分发表在编译期就固定了。**

---

## 5. 切错的后果（把"看到的现象"和"VTOR"对上）

| 现象 | 机制 |
|---|---|
| 跳进 app 后**第一个中断就崩**（HardFault） | #2 没做 / 写成错地址 ⇒ CPU 去 bootloader 的 `exception_common`，而那里的上下文已被 `board_deinit()` 清掉 |
| app 里 `SysTick` 走的是 bootloader 的处理函数 | `bl.c:417 arch_systic_deinit()` 没执行到（它在 `jump_to_app()` 里，失败就 return） |
| 中断进得去但**处理函数是错的** | VTOR 指向了另一套表（两套表地址差 `0x20000`） |
| 想用调试器动态改中断表却无效 | 本板没有 RAM 向量表（§4） |
| `arch_do_jump` 之后 app 用**bootloader 的栈** | 那是 MSP/PSP 问题（[`main.c:646`](../../02_code_twin/bootloader/stm32-common-main-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-646) 清 `CONTROL.SPSEL` + `msr msp`），**与 VTOR 无关** —— 两个坑容易混 |

> ★ 最后一条是**最容易误判的**：`arch_do_jump()` 里同时干了两件事 ——
> **切 VTOR（在 [`bl.c:429`](../../02_code_twin/bootloader/bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-c-429)，不在 `arch_do_jump` 里）** 和 **切 MSP**。
> 现象都是"进 app 就崩"，但根因不同。

---

## 6. 一图看完整交接

```
复位
 │ 硬件按 boot 地址取 SP/PC（VTOR 还是复位默认值）   ← 本仓代码查不到，标"硬件行为"
 ▼
bootloader __start ─ stm32_clockconfig ─ stm32_boardinitialize
 ▼
nx_start:635 irq_initialize → up_irqinitialize
 │  ★写 VTOR = 0x08000000        （stm32_irq.c:408）   ← 交点 1
 ▼
bootloader_main ─ 4 个决策点 ─ jump_to_app()
 │
 ├─ bl.c:417 arch_systic_deinit()   关 SysTick 中断
 ├─ bl.c:420 cfini()                关 /dev/ttyS0
 ├─ bl.c:423 clock_deinit()         RCC 回 HSI
 ├─ bl.c:426 board_deinit()         LED 脚切回输入
 ├─ bl.c:429 arch_setvtor(vec)      ★写 VTOR = 0x08020000  ← 交点 2
 └─ bl.c:432 arch_do_jump(app)
        ├─ msr msp, app_base[0]      切栈
        ├─ 清 CONTROL.SPSEL          回 MSP（main.c:646-653）
        └─ bx app_base[1]            跳 app 的 __start
 ▼
app __start ─ … ─ nx_start:635 irq_initialize
 │  ★写 VTOR = 0x08020000        （同一个函数，值现在是 app 的表）  ← 交点 3
 ▼
nsh_main → rcS → 各 module
```

---

## 跳转

- **执行序上一步**（谁触发这三个交点）→ [01_extracted/nuttx/00-poweron-chain](../nuttx/00-poweron-chain.md)。
- **`jump_to_app()` 里这几步的完整顺序与失败分支** → [02_code_twin/bootloader/bl-c](../../02_code_twin/bootloader/bl-c.md) §6。
- **两个 linker script 的完整 flash 布局** → [01_extracted/stm32/flash-layout](flash-layout.md)。
- **`arch_do_jump()` 的 MSP/PSP 切换细节** → [02_code_twin/bootloader/stm32-common-main-c](../../02_code_twin/bootloader/stm32-common-main-c.md) §4.2。
- **MSP/PSP 为什么会不一致**（`CONFIG_ARCH_INTERRUPTSTACK=768 > 7` ⇒ `arm_initialize_stack()`）→ [01_extracted/nuttx/00-poweron-chain](../nuttx/00-poweron-chain.md) 第 8 步。

---

## 未核实

- **复位后 VTOR 的默认值与"硬件按 boot 地址取向量"的寄存器级细节**（`BOOT_ADD0` 等）**本仓代码里查不到**，
  §6 第一行标"硬件行为"。
- `VECTAB_ALIGN` 在 H743 上的具体字节数（取决于 `ARMV7M_PERIPHERAL_INTERRUPTS`）未算。
- 交点 1 与本篇的因果（`irq_initialize()` 在 `nx_start` 的哪个位置）来自 [01_extracted/nuttx/00-poweron-chain](../nuttx/00-poweron-chain.md) 第 7 步，
  该步行号已回验。

---

## 标注源码（代码 + 本文档对它的解释）

> **这是「代码孪生」层**：上面是代码原文（带行号），下面是**本文档针对这一段说的话**。
> 行号可点，直接跳到 PX4 源码那一行。
### `platforms/nuttx/NuttX/nuttx/arch/arm/src/armv7-m/arm_vectors.c`
<a id="src-platforms-nuttx-NuttX-nuttx-arch-arm-src-armv7-m-arm-vectors-c-91"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/NuttX/nuttx/arch/arm/src/armv7-m/arm_vectors.c:91`](vtor-vector-tables.md#^src-platforms-nuttx-NuttX-nuttx-arch-arm-src-armv7-m-arm-vectors-c-91)

```c
    88 │  * Note that the [ ... ] designated initializer is a GCC extension.
    89 │  */
    90 │ 
▶   91 │ const void * const _vectors[] locate_data(".vectors")
    92 │                               aligned_data(VECTAB_ALIGN) =
    93 │ {
    94 │   /* Initial stack */
```
> **说明**：对齐约束 | ram_vectors.h:89 VECTAB_ALIGN；:57-72 的 NVIC_VECTAB_TBLOFF_MASK 按表大小决定 | ┃ 向量表本体 | arm_vectors.c:91 的 _vectors[]（见 01_extracted/stm32/00-reset-clock-peripherals §1） |
> **说明**：表的内容由 arm_vectors.c:91 统一生成（IDLE_STACK / start / exception_common / exception_direct），
^src-platforms-nuttx-NuttX-nuttx-arch-arm-src-armv7-m-arm-vectors-c-91

### `platforms/nuttx/NuttX/nuttx/arch/arm/src/armv7-m/nvic.h`
<a id="src-platforms-nuttx-NuttX-nuttx-arch-arm-src-armv7-m-nvic-h-383"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/NuttX/nuttx/arch/arm/src/armv7-m/nvic.h:383`](vtor-vector-tables.md#^src-platforms-nuttx-NuttX-nuttx-arch-arm-src-armv7-m-nvic-h-383)

```c
   380 │ 
   381 │ #define NVIC_CPUID_BASE                 (ARMV7M_NVIC_BASE + NVIC_CPUID_BASE_OFFSET)
   382 │ #define NVIC_INTCTRL                    (ARMV7M_NVIC_BASE + NVIC_INTCTRL_OFFSET)
▶  383 │ #define NVIC_VECTAB                     (ARMV7M_NVIC_BASE + NVIC_VECTAB_OFFSET)
   384 │ #define NVIC_AIRCR                      (ARMV7M_NVIC_BASE + NVIC_AIRCR_OFFSET)
   385 │ #define NVIC_SYSCON                     (ARMV7M_NVIC_BASE + NVIC_SYSCON_OFFSET)
   386 │ #define NVIC_CFGCON                     (ARMV7M_NVIC_BASE + NVIC_CFGCON_OFFSET)
```
> **说明**：寄存器地址 | nuttx/arch/arm/src/armv7-m/nvic.h:383 → NVIC_VECTAB = ARMV7M_NVIC_BASE + 0x0d08（:189） |
^src-platforms-nuttx-NuttX-nuttx-arch-arm-src-armv7-m-nvic-h-383

### `platforms/nuttx/NuttX/nuttx/arch/arm/src/armv7-m/ram_vectors.h`
<a id="src-platforms-nuttx-NuttX-nuttx-arch-arm-src-armv7-m-ram-vectors-h-89"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/NuttX/nuttx/arch/arm/src/armv7-m/ram_vectors.h:89`](vtor-vector-tables.md#^src-platforms-nuttx-NuttX-nuttx-arch-arm-src-armv7-m-ram-vectors-h-89)

```c
    86 │  * appropriate mask.
    87 │  */
    88 │ 
▶   89 │ #define VECTAB_ALIGN ((~NVIC_VECTAB_TBLOFF_MASK & 0xffff) + 1)
    90 │ 
    91 │ #ifdef CONFIG_ARCH_RAMVECTORS
    92 │ 
```
> **说明**：寄存器地址 | nuttx/arch/arm/src/armv7-m/nvic.h:383 → NVIC_VECTAB = ARMV7M_NVIC_BASE + 0x0d08（:189） | ┃ 对齐约束 | ram_vectors.h:89 VECTAB_ALIGN；:57-72 的 NVIC_VECTAB_TBLOFF_MASK 按表大小决定 |
^src-platforms-nuttx-NuttX-nuttx-arch-arm-src-armv7-m-ram-vectors-h-89

### `platforms/nuttx/NuttX/nuttx/arch/arm/src/stm32/stm32_irq.c`
<a id="src-platforms-nuttx-NuttX-nuttx-arch-arm-src-stm32-stm32-irq-c-372"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/NuttX/nuttx/arch/arm/src/stm32/stm32_irq.c:372`](vtor-vector-tables.md#^src-platforms-nuttx-NuttX-nuttx-arch-arm-src-stm32-stm32-irq-c-372)

```c
   369 │   up_irq_enable();
   370 │ #endif
   371 │ }
▶  372 │ 
   373 │ /****************************************************************************
   374 │  * Name: up_disable_irq
   375 │  *
```
> **说明**：1 | 启动早期（内核起来时） | NuttX 架构层 | 当前镜像自己的 _vectors | nuttx/sched/init/nx_start.c:635 irq_initialize() → nuttx/sched/irq/irq_initialize.c:98 up_irqinitialize() → nuttx/arch/arm/src/stm32h7/stm32_irq.c:372 
^src-platforms-nuttx-NuttX-nuttx-arch-arm-src-stm32-stm32-irq-c-372

<a id="src-platforms-nuttx-NuttX-nuttx-arch-arm-src-stm32-stm32-irq-c-410"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/NuttX/nuttx/arch/arm/src/stm32/stm32_irq.c:410`](vtor-vector-tables.md#^src-platforms-nuttx-NuttX-nuttx-arch-arm-src-stm32-stm32-irq-c-410)

```c
   407 │ 
   408 │ /****************************************************************************
   409 │  * Name: up_enable_irq
▶  410 │  *
   411 │  * Description:
   412 │  *   Enable the IRQ specified by 'irq'
   413 │  *
```
> **说明**：⇒ stm32_irq.c:410 的 #ifdef 为假；arm_ramvec_initialize.c:42/118 的整段逻辑不参与编译。
^src-platforms-nuttx-NuttX-nuttx-arch-arm-src-stm32-stm32-irq-c-410

### `platforms/nuttx/src/bootloader/common/bl.c`
<a id="src-platforms-nuttx-src-bootloader-common-bl-c-417"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:417`](vtor-vector-tables.md#^src-platforms-nuttx-src-bootloader-common-bl-c-417)

```c
   414 │ 	arch_flash_lock();
   415 │ 
   416 │ 	/* kill the systick interrupt */
▶  417 │ 	arch_systic_deinit();
   418 │ 
   419 │ 	/* deinitialise the interface */
   420 │ 	cfini();
```
> **说明**：├─ bl.c:417 arch_systic_deinit() 关 SysTick 中断
^src-platforms-nuttx-src-bootloader-common-bl-c-417

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-420"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:420`](vtor-vector-tables.md#^src-platforms-nuttx-src-bootloader-common-bl-c-420)

```c
   417 │ 	arch_systic_deinit();
   418 │ 
   419 │ 	/* deinitialise the interface */
▶  420 │ 	cfini();
   421 │ 
   422 │ 	/* reset the clock */
   423 │ 	clock_deinit();
```
> **说明**：├─ bl.c:420 cfini() 关 /dev/ttyS0
^src-platforms-nuttx-src-bootloader-common-bl-c-420

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-423"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:423`](vtor-vector-tables.md#^src-platforms-nuttx-src-bootloader-common-bl-c-423)

```c
   420 │ 	cfini();
   421 │ 
   422 │ 	/* reset the clock */
▶  423 │ 	clock_deinit();
   424 │ 
   425 │ 	/* deinitialise the board */
   426 │ 	board_deinit();
```
> **说明**：├─ bl.c:423 clock_deinit() RCC 回 HSI
^src-platforms-nuttx-src-bootloader-common-bl-c-423

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-426"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:426`](vtor-vector-tables.md#^src-platforms-nuttx-src-bootloader-common-bl-c-426)

```c
   423 │ 	clock_deinit();
   424 │ 
   425 │ 	/* deinitialise the board */
▶  426 │ 	board_deinit();
   427 │ 
   428 │ 	/* switch exception handlers to the application */
   429 │ 	arch_setvtor(vec_base);
```
> **说明**：├─ bl.c:426 board_deinit() LED 脚切回输入
^src-platforms-nuttx-src-bootloader-common-bl-c-426

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-429"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:429`](vtor-vector-tables.md#^src-platforms-nuttx-src-bootloader-common-bl-c-429)

```c
   426 │ 	board_deinit();
   427 │ 
   428 │ 	/* switch exception handlers to the application */
▶  429 │ 	arch_setvtor(vec_base);
   430 │ 
   431 │ 	/* make arch specific jump to app */
   432 │ 	arch_do_jump(app_base);
```
> **说明**：bootloader 上电：硬件按 boot 地址取向量 → 跑到 nx_start → #1 把 VTOR 设成 0x08000000（bootloader 的 _vectors）。 ┃ 跳 app：bl.c:429 把它改成 0x08020000（app 的 _vectors）。
> **说明**：★ 最后一条是最容易误判的：arch_do_jump() 里同时干了两件事 —— ┃ 切 VTOR（在 bl.c:429，不在 arch_do_jump 里） 和 切 MSP。
^src-platforms-nuttx-src-bootloader-common-bl-c-429

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-432"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:432`](vtor-vector-tables.md#^src-platforms-nuttx-src-bootloader-common-bl-c-432)

```c
   429 │ 	arch_setvtor(vec_base);
   430 │ 
   431 │ 	/* make arch specific jump to app */
▶  432 │ 	arch_do_jump(app_base);
   433 │ }
   434 │ 
   435 │ volatile unsigned timer[NTIMERS];
```
> **说明**：└─ bl.c:432 arch_do_jump(app)
^src-platforms-nuttx-src-bootloader-common-bl-c-432

### `platforms/nuttx/src/bootloader/stm/stm32_common/main.c`
<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-632"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:632`](vtor-vector-tables.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-632)

```c
   629 │ #endif
   630 │ 
   631 │ /* Make the actual jump to app */
▶  632 │ void
   633 │ arch_do_jump(const uint32_t *app_base)
   634 │ {
   635 │ 	/* extract the stack and entrypoint from the app vector table and go */
```
> **说明**：⇒ 所以 #2 这一步在"正常路径"上有点像冗余，但它是必需的：因为 arch_do_jump() ┃ （main.c:632）是直接 bx 到 app 的 start，app 从头跑，中间有一段
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-632

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-646"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:646`](vtor-vector-tables.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-646)

```c
   643 │ 	 * on the MSP, so select it again before handing over -- otherwise the app
   644 │ 	 * keeps running on the bootloader's stack and faults once it is clobbered.
   645 │ 	 */
▶  646 │ 	asm volatile(
   647 │ 		"mrs %0, control  \n"
   648 │ 		"bic %0, %0, #2   \n"
   649 │ 		"msr control, %0  \n"
```
> **说明**：想用调试器动态改中断表却无效 | 本板没有 RAM 向量表（§4） | ┃ arch_do_jump 之后 app 用bootloader 的栈 | 那是 MSP/PSP 问题（main.c:646 清 CONTROL.SPSEL + msr msp），与 VTOR 无关 —— 两个坑容易混 |
> **说明**：├─ 清 CONTROL.SPSEL 回 MSP（main.c:646-653）
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-646
