# 启动汇编与 C 运行时初始化（提炼知识）

> **这是 01 层（提炼知识）** —— 从 NuttX/STM32H7 的启动代码里萃取的 **"复位 → 能跑 C"这一段**。
> **02 层遇到它时链接回这里。**
>
> **什么时候读这篇**：想知道**上电后最初几十条指令在干什么**、
> `.data` 为什么必须"从 flash 搬到 RAM"、`_sdata`/`_ebss` 这些符号从哪来。
> **出处**：源码根见 [`../../tools/source-root.conf`](../../tools/source-root.conf)。

**★ 与已有两篇的分工（别读重）：**
| 篇 | 讲 |
|---|---|
| [`vtor-vector-tables`](vtor-vector-tables.md) | **VTOR / 两套向量表 / 切错的后果** |
| [`flash-layout`](flash-layout.md) | **flash 分区 / 参数区 / ECC scrub** |
| **本篇** | ★ **复位向量 → `__start()` → C 运行时就绪 → `nx_start()`** |

---

## 0. 一句话：这一段就干四件事

```
① 清 .bss     （把"该是 0 的变量"清零）
② 搬 .data    （把"有初值的变量"从 flash 拷到 RAM）
③ 配时钟/串口/FPU（让外设和 printf 能用）
④ 进调度器    nx_start()
```

**★ 为什么你觉得陌生**：你在 CubeMX 里，① ② 是 `startup_stm32xxx.s` 里的汇编，**③ 在 `SystemInit()`**，
你**从来不用看**。NuttX 把 ①② 用 C 写在了 `__start()` 里 —— 所以现在能读懂，但得知道它在干嘛。

---

## 1. 完整链条（本板）

```
【硬件】上电/复位
   ↓ CPU 从 0x08000000 取前两个字：初始 SP、复位处理函数地址
【向量表】platforms/nuttx/NuttX/nuttx/arch/arm/src/armv7-m/arm_vectors.c
   :59   extern void __start(void);
   :61-66  static void start(void) {
              asm volatile ("mov lr, #0\n\t"      // ★ 把 LR 清零 = "调用栈到此为止"（给 backtrace 用）
                            "b  __start\n\t");    // ★ 直接【跳】过去（不是 bl，所以不会返回）
           }
   ↓
【C 运行时初始化】platforms/nuttx/NuttX/nuttx/arch/arm/src/stm32h7/stm32_start.c
   :183   void __start(void)                        ← ★ 真正的 C 入口（:117 声明带 noinstrument_function）
   :209   清 .bss：for (dest = _sbss; dest < _ebss; ) *dest++ = 0;
   :220-221 搬 .data：for (src = _eronly, dest = _sdata; dest < _edata; ) *dest++ = *src++;
   …      配时钟 / 串口 / FPU 等
   :315   nx_start();                               ← ★ 进入 NuttX 调度器（之后就是你熟悉的 rcS 那套）
```

**⇒ 之后的事**：`nx_start()`（[`platforms/nuttx/NuttX/nuttx/sched/init/nx_start.c:506`](startup-and-crt.md#^src-platforms-nuttx-NuttX-nuttx-sched-init-nx-start-c-506)）
→ 建 idle 任务 → 起内核 → 按 `CONFIG_INIT_ENTRYPOINT` 进 `nsh_main` → 跑 `rcS`
（**这一段见** [`../nuttx/00-poweron-chain`](../nuttx/00-poweron-chain.md)）。

---

## 2. ★★ 为什么必须"搬" `.data`（本篇最该懂的一条）

**看本板的链接脚本 `boards/rm2027/fmu-h743/nuttx-config/scripts/script.ld`：**
```ld
.data : {
    _sdata = ABSOLUTE(.);          /* :177 ← RAM 里的起点（VMA） */
    *(.data .data.*)
    *(.gnu.linkonce.d.*)
    CONSTRUCTORS
    _edata = ABSOLUTE(.);          /* :181 */
    ...
} > AXI_SRAM AT > FLASH  = 0xffff  /* :187 ★★★ 关键这一行 */
```ld

**`> AXI_SRAM AT > FLASH` 的意思是：**
```
VMA（运行地址） = AXI_SRAM   ← 变量运行时必须在 RAM（因为要能被改）
LMA（加载地址） = FLASH      ← 但它的【初值】固化在 flash 里
⇒ ⇒ 两者不同 ⇒ 【上电后 RAM 里是空的，必须从 flash 拷过来】
```

**⇒ 所以那行循环不是"多余的优化"，而是**唯一的初值来源**：**
```c
for (src = (const uint32_t *)_eronly,          /* :220  flash 里初值的拷贝源 */
     dest = (uint32_t *)_sdata;                /* :221  RAM 里的目的地 */
     dest < (uint32_t *)_edata;
     ...) { *dest++ = *src++; }
```

**★ 对照理解 `.bss`：**
```ld
.bss : { _sbss = ...; *(.bss …); _ebss = ...; } > AXI_SRAM    /* :189-196，只有 VMA，没有 AT */
```
**⇒ `.bss` 里全是"初值为 0"的变量 ⇒ **不需要在 flash 里存一份** ⇒ 只要**清零**就行（`:209`）。**
**⇒ 这就是"为什么 .bss 不占固件体积、.data 占"的根本原因。**

---

## 3. 链接脚本里的运行时符号（逐个对上）

| 符号 | 定义处（`script.ld`） | 含义 | 谁用它 |
|---|---|---|---|
| **`_eronly`** | `:174` | **flash 里 `.data` 初值的末尾**（= 拷贝源区的结束） | `stm32_start.c:220` 的 `src` 起点 |
| **`_sdata`** | `:177` | RAM 里 `.data` 的**起点** | `:221` 的 `dest` 起点 |
| **`_edata`** | `:181` | RAM 里 `.data` 的**终点** | `:221` 的循环条件 |
| **`_sbss`** | `:190` | `.bss` 起点 | `:209` 清零循环 |
| **`_ebss`** | `:195` | `.bss` 终点 | `:209` 循环；**还是 idle 栈底**（见 §4） |

**★ 记法：`_s*` = start，`_e*` = end，`_eronly` 的 "r" = ROM/read-only（flash）。**

---

## 4. 栈和堆从哪来（`stm32_start.c` 里的两行）

```c
:74   #define HEAP_BASE  ((uintptr_t)_ebss + CONFIG_IDLETHREAD_STACKSIZE)
:90   const uintptr_t g_idle_topstack = HEAP_BASE;
```
**⇒ 内存布局的约定（`:64-67` 的注释原文）：**
```ld
0x2000:0000            ← 内部 SRAM 起点 = .data 起点(_sdata)
…                      ← .data
_edata / _sbss         ← .data 结束、.bss 开始（接在一起）
_ebss                  ← .bss 结束 = 【idle 任务的栈底】
_ebss + IDLE_STACK_SIZE← 堆起点（HEAP_BASE）
```
**⇒ 所以 `.bss` 之后紧跟着 idle 栈，再往后是堆 —— **静态内存就这样被切完了**。**
**★ 判据：**想在 RAM 里多要空间，先看 `_ebss` 在哪、还剩多少。**

---

## 5. 那 `__libc_init_array()` 呢？（C++ 全局构造）

**在 NuttX 这套里，`.data` 搬运之后还有一步"跑全局构造函数"** —— 它让
`static Foo obj;` 这类**C++ 全局对象的构造函数**得以执行。

**它靠链接脚本里的这两行兜底（[`script.ld:180`](startup-and-crt.md#^src-boards-rm2027-fmu-h743-nuttx-config-scripts-script-ld-180)）：**
```ld
CONSTRUCTORS                     /* ← ★ 把 .init_array / .ctors 收进 .data 段 */
```
**⇒ `CONSTRUCTORS` 是链接器的关键字：把"全局构造表"放进这个段。**
**⇒ 于是搬运 `.data` 的同时，构造表也被搬进 RAM；随后由 C 运行时代码遍历它逐个调用。**

**★ 与本项目的关系：**PX4 的模块大多是**运行时显式启动**（NSH 命令 / `rcS`），
**不是靠全局构造自动跑** —— 所以这条链在本板上主要保证 `ModuleParams` 之类的静态初始化正常。

---

## 6. 和你在 CubeMX 里见过的那套对照

| 步骤 | CubeMX（裸机） | 本板（NuttX） |
|---|---|---|
| 复位向量 | `startup_stm32h743xx.s` 里 `Reset_Handler` | [`armv7-m/arm_vectors.c:61`](startup-and-crt.md#^src-platforms-nuttx-NuttX-nuttx-arch-arm-src-armv7-m-arm-vectors-c-61) 的 `start()` → `b __start` |
| 清 `.bss` / 搬 `.data` | **汇编** `_sbss/_ebss/_sdata/_edata` 循环 | **C** 代码 `stm32_start.c:209/221` |
| 时钟 | `SystemInit()` | `__start()` 里调 `stm32_clockconfig()` 一类 |
| 进 `main()` | `bl main` | **没有 `main()`** —— `:315 nx_start()` 进内核，之后是脚本 `rcS` |
| 向量表重定位 | 一般不做 | bootloader → app 时靠 **VTOR**（见 [`vtor-vector-tables`](vtor-vector-tables.md)） |

**⇒ 一句话：**你以前"跳过"的那段汇编，现在换成了 C，而且**必须自己会读**（因为 `_sdata` 这些符号是链接脚本给的）。**

---

## 7. 现象 ↔ 原因（这段出错会怎样）

| 现象 | 大概率的根因 |
|---|---|
| 上电就 hardfault，连串口都没输出 | ① 初始 SP 无效（向量表位置/内容不对）；② `__start` 之前就跑了不该跑的代码 |
| 全局变量**初值不对**（该是 3 却是 0 / 乱值） | **`.data` 没搬对** —— `_eronly/_sdata/_edata` 与实际不符，或链接脚本被改坏 |
| 全局变量**偶发**变化 | `.bss` 没清干净（`_sbss/_ebss` 范围错），或栈/堆与 `.bss` 重叠 |
| 链接时报 `undefined reference to _sdata` 等 | 链接脚本没定义（本板在 [`script.ld:177`](startup-and-crt.md#^src-boards-rm2027-fmu-h743-nuttx-config-scripts-script-ld-177) 等） |
| 卡在启动、串口无输出 | 时钟没配好（`__start` 里那几步） |

**★ 判据链：**"现象" → 看 `_sdata/_edata/_sbss/_ebss` 是否符合预期 → 再看向量表与时钟。**

---

## 8. 跳转

- **复位之后的内核与脚本** → [`../nuttx/00-poweron-chain`](../nuttx/00-poweron-chain.md)
- **向量表与 VTOR** → [`vtor-vector-tables`](vtor-vector-tables.md)
- **flash 分区（bootloader/app/参数区）** → [`flash-layout`](flash-layout.md)
- **`Reset_Handler` 之前发生了什么（bootloader 阶段）** → [`../../02_code_twin/bootloader/`](../../02_code_twin/bootloader/)
- **链接脚本的 `MEMORY/SECTIONS` 语法** → 见审计 §3 第 6 条（按需再补）
- **其它 01 层** → [`../cmake/cmake-syntax`](../cmake/cmake-syntax.md)、[`../make/gnu-make-syntax`](../make/gnu-make-syntax.md)、[`../uorb/uorb-mechanism`](../uorb/uorb-mechanism.md)、[`../c/px4-c-macros`](../c/px4-c-macros.md)

---

## 标注源码（代码 + 本文档对它的解释）

> **这是「代码孪生」层**：上面是代码原文（带行号），下面是**本文档针对这一段说的话**。
> 行号可点，直接跳到 PX4 源码那一行。
### `boards/rm2027/fmu-h743/nuttx-config/scripts/script.ld`
<a id="src-boards-rm2027-fmu-h743-nuttx-config-scripts-script-ld-177"></a>
**↓ 文档在讲这里：**[`boards/rm2027/fmu-h743/nuttx-config/scripts/script.ld:177`](startup-and-crt.md#^src-boards-rm2027-fmu-h743-nuttx-config-scripts-script-ld-177)

```c
   174 │ 	_eronly = ABSOLUTE(.);
   175 │ 
   176 │ 	.data : {
▶  177 │ 		_sdata = ABSOLUTE(.);
   178 │ 		*(.data .data.*)
   179 │ 		*(.gnu.linkonce.d.*)
   180 │ 		CONSTRUCTORS
```
> **说明**：全局变量偶发变化 | .bss 没清干净（_sbss/_ebss 范围错），或栈/堆与 .bss 重叠 | ┃ 链接时报 undefined reference to _sdata 等 | 链接脚本没定义（本板在 script.ld:177 等） |
^src-boards-rm2027-fmu-h743-nuttx-config-scripts-script-ld-177

<a id="src-boards-rm2027-fmu-h743-nuttx-config-scripts-script-ld-180"></a>
**↓ 文档在讲这里：**[`boards/rm2027/fmu-h743/nuttx-config/scripts/script.ld:180`](startup-and-crt.md#^src-boards-rm2027-fmu-h743-nuttx-config-scripts-script-ld-180)

```c
   177 │ 		_sdata = ABSOLUTE(.);
   178 │ 		*(.data .data.*)
   179 │ 		*(.gnu.linkonce.d.*)
▶  180 │ 		CONSTRUCTORS
   181 │ 		_edata = ABSOLUTE(.);
   182 │ 
   183 │ 		/* Pad out last section as the STM32H7 Flash write size is 256 bits. 32 bytes */
```
> **说明**：它靠链接脚本里的这两行兜底（script.ld:180）：
^src-boards-rm2027-fmu-h743-nuttx-config-scripts-script-ld-180

### `platforms/nuttx/NuttX/nuttx/arch/arm/src/armv7-m/arm_vectors.c`
<a id="src-platforms-nuttx-NuttX-nuttx-arch-arm-src-armv7-m-arm-vectors-c-61"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/NuttX/nuttx/arch/arm/src/armv7-m/arm_vectors.c:61`](startup-and-crt.md#^src-platforms-nuttx-NuttX-nuttx-arch-arm-src-armv7-m-arm-vectors-c-61)

```c
    58 │ 
    59 │ extern void __start(void);
    60 │ 
▶   61 │ static void start(void)
    62 │ {
    63 │   /* Zero lr to mark the end of backtrace */
    64 │ 
```
> **说明**：复位向量 | startup_stm32h743xx.s 里 Reset_Handler | armv7-m/arm_vectors.c:61 的 start() → b start |
^src-platforms-nuttx-NuttX-nuttx-arch-arm-src-armv7-m-arm-vectors-c-61

### `platforms/nuttx/NuttX/nuttx/arch/arm/src/stm32/stm32_start.c`
### `platforms/nuttx/NuttX/nuttx/sched/init/nx_start.c`
<a id="src-platforms-nuttx-NuttX-nuttx-sched-init-nx-start-c-506"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/NuttX/nuttx/sched/init/nx_start.c:506`](startup-and-crt.md#^src-platforms-nuttx-NuttX-nuttx-sched-init-nx-start-c-506)

```c
   503 │  *
   504 │  ****************************************************************************/
   505 │ 
▶  506 │ void nx_start(void)
   507 │ {
   508 │   int i;
   509 │ 
```
> **说明**：⇒ 之后的事：nx_start()（platforms/nuttx/NuttX/nuttx/sched/init/nx_start.c:506）
^src-platforms-nuttx-NuttX-nuttx-sched-init-nx-start-c-506
