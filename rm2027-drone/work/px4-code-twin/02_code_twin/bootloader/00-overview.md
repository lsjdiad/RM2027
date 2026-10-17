# bootloader 篇 · 00 总览 —— 上电后最先拿到控制权的那段代码

> **本目录（`02_code_twin/bootloader/`）镜像 `platforms/nuttx/src/bootloader/`**，
> 全部行号以飞控源码仓 `源码根（见 `tools/source-root.conf`）`（分支 `teaching/minimal-path`）为基准。
> `git diff upstream/main -- platforms/nuttx/src/bootloader/` **为空** ⇒ 这一层是**未改动的上游代码**；
> 本板只改了 ③ 板级文件（见 [02_code_twin/bootloader/board-layer](board-layer.md)）。

**路径简写**（本目录统一使用）：

| 简写 | 完整路径 |
|---|---|
| `bl.c` / `bl.h` | `platforms/nuttx/src/bootloader/common/bl.c`（1175 行）/ `bl.h`（135 行） |
| `main.c` | `platforms/nuttx/src/bootloader/stm/stm32_common/main.c`（829 行） |
| `ecc_scrub.c` | `platforms/nuttx/src/bootloader/stm/stm32h7/ecc_scrub.c`（155 行） |
| `fmc.c` | `platforms/nuttx/src/bootloader/common/lib/flash_cache.c`（163 行） |
| `uart.c` | `platforms/nuttx/src/bootloader/common/lib/uart.c`（130 行） |
| `hw_config.h` | `boards/rm2027/fmu-h743/src/hw_config.h`（138 行） |
| `nuttx` | `platforms/nuttx/NuttX/nuttx/`（NuttX 内核） |
| `apps` | `platforms/nuttx/NuttX/apps/`（NuttX 用户态/应用） |

---

## 1. 一句话：控制权从哪来、到哪去

```
硬件复位
  └─ 从 BOOT_ADD0 = 0x08000000 取 SP / 复位向量        ← bootloader 的镜像基址 = flash 扇区 0
      └─ __start（NuttX 的复位入口）                     nuttx/arch/arm/src/stm32h7/stm32_start.c:183
          └─ nx_start（NuttX 内核启动）                  :315 → nuttx/sched/init/nx_start.c:506
              └─ nx_bringup → AppBringUp 线程            nuttx/sched/init/nx_bringup.c:494 / :443
                  └─ board_late_initialize()             boards/rm2027/fmu-h743/src/bootloader_main.c:69
                  └─ task_spawn("bootloader_main")       nuttx/sched/init/nx_bringup.c:356
                      └─ bootloader_main() ★ ②层真正的主函数   main.c:660
                          ├─ try_boot = true ⇒ jump_to_app()  main.c:771   ← 常态路径
                          └─ 否则 ⇒ cinit(...) → while(1) bootloader(timeout)  main.c:783 / :802
                                                                  └─ bl.c:624（①层协议循环）
                          └─ jump_to_app() 跳成功后 → app 的 __start（0x08020000）
```

**⇒ 最关键的一条认知（很多人会搞反）**：
**`main.c` 才是"跳不跳"的裁判，`bl.c` 只是"裁判说去等主机"之后才上场的协议机。**
`jump_to_app()` **定义**在 ① 层（[`bl.c:308`](stm32-common-main-c.md#^src-platforms-nuttx-src-bootloader-common-bl-c-308)），**调用**却在 ② 层（[`main.c:771`](bl-h.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-771)、[`main.c:824`](bl-h.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-824)）——
这是 ①/② 分工最直观的一处证据。

---

## 2. 三层分工（对应 ③ → ① 的调用方向）

| 层 | 文件 | 它决定什么 | 它**不**知道什么 |
|---|---|---|---|
| **③ 板级** | `hw_config.h` + `bootloader_main.c` | flash 起始地址、超时、通道、LED/force 引脚、`board_timerhook` 转发 | 协议、擦除算法、跳转合法性 |
| **② 芯片族** | `main.c` + `systick.c` +（H7）`ecc_scrub.c` | **跳不跳**（force pin / USB / break / RTC 签名）、flash 读写原语、时钟/接口反初始化、真正执行跳转 | 主机协议 |
| **① 通用** | `bl.c` + `bl.h` + `lib/*` | **等主机上传**：协议分派、擦除、写入、CRC、延时提交首字 | **它不知道"要不要跳"** —— `bootloader()` 一 `return` 就等于说"该跳了" |

`bl.h`（135 行）的实质是一份**"②层必须实现什么"的清单**：19 个 `extern` 函数 + 1 个 `struct boardinfo`。
逐条见 [02_code_twin/bootloader/bl-h](bl-h.md)。

---

## 3. 上电到"跳 app"的 13 步（执行序，带行号）

| # | 控制权在哪 | 干了什么 | 依据 |
|---|---|---|---|
| 1 | 硬件 | 从 `0x08000000` 取初始 SP + 复位向量 | 链接脚本 [`bootloader_script.ld:113`](00-overview.md#^src-boards-rm2027-fmu-h743-nuttx-config-scripts-bootloader-script-ld-113)（`flash ORIGIN=0x08000000, LENGTH=128K`）+ `EXTERN(_vectors)`(:125) |
| 2 | `__start` | 清 `.bss` / 搬 `.data` / 搬 ramfuncs | `nuttx/arch/arm/src/stm32h7/stm32_start.c:209 / :220 / :235` |
| 3 | `__start` | `stm32_clockconfig()` ⇒ **PLL 起来，CPU=480 MHz** | `:249`；参数在 [`boards/rm2027/fmu-h743/nuttx-config/include/board.h:104`](00-overview.md#^src-boards-rm2027-fmu-h743-nuttx-config-include-board-h-104) |
| 4 | `__start` | `stm32_boardinitialize()` ⇒ **跳进 ③ 层** | `:262` → [`bootloader_main.c:55`](00-overview.md#^src-boards-rm2027-fmu-h743-src-bootloader-main-c-55) |
| 5 | `__start` | 开 I/D-Cache → `nx_start()` | `:268-269` / `:315` |
| 6 | `nx_start` | `irq_initialize()` ⇒ `up_irqinitialize()` ⇒ **VTOR = 0x08000000** | [`nx_start.c:635`](00-overview.md#^src-platforms-nuttx-NuttX-nuttx-sched-init-nx-start-c-635) → [`nuttx/sched/irq/irq_initialize.c:98`](00-overview.md#^src-platforms-nuttx-NuttX-nuttx-sched-irq-irq-initialize-c-98) → `nuttx/arch/arm/src/stm32h7/stm32_irq.c:372 / :408` |
| 7 | `nx_start` | `up_initialize()` ⇒ `arm_initialize_stack()`（**线程模式改用 PSP**） | [`nx_start.c:675`](00-overview.md#^src-platforms-nuttx-NuttX-nuttx-sched-init-nx-start-c-675) → `nuttx/arch/arm/src/common/arm_initialize.c:62 / :67`（`CONFIG_ARCH_INTERRUPTSTACK=768 > 7`） |
| 8 | `nx_start` | `nx_bringup()` ⇒ 建 workqueue + 建 `AppBringUp` 线程 | [`nx_start.c:743`](00-overview.md#^src-platforms-nuttx-NuttX-nuttx-sched-init-nx-start-c-743) → `nx_bringup.c:530 / :537 / :443` |
| 9 | AppBringUp 线程 | `board_late_initialize()` ⇒ `sercon_main()`（USB CDC/ACM，本板落空） | [`nx_bringup.c:321`](board-layer.md#^src-platforms-nuttx-NuttX-nuttx-sched-init-nx-bringup-c-321) → [`bootloader_main.c:69`](00-overview.md#^src-boards-rm2027-fmu-h743-src-bootloader-main-c-69) |
| 10 | AppBringUp 线程 | `task_spawn("bootloader_main", …)` ⇒ **②层主函数起跑** | [`nx_bringup.c:356`](stm32-common-main-c.md#^src-platforms-nuttx-NuttX-nuttx-sched-init-nx-bringup-c-356)；`CONFIG_INIT_ENTRYPOINT="bootloader_main"`（`nuttx-config/bootloader/defconfig:45`） |
| 11 | `bootloader_main` | `board_init()` ⇒ `fw_size = APP_SIZE_MAX`；`check_ecc_errors()` | [`main.c:682`](ecc-scrub-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-682) → `:274`；`:689` |
| 12 | `bootloader_main` | 4 个决策点全判完 ⇒ `try_boot` 通常仍为 `true` ⇒ `jump_to_app()` | `main.c:696 / :719 / :734 / :756` → `:771` |
| 13 | `jump_to_app` | 校验过 ⇒ 关 Systick/接口/时钟 ⇒ `arch_setvtor(0x08020000)` ⇒ `arch_do_jump()` | [`bl.c:414`](stm32-common-main-c.md#^src-platforms-nuttx-src-bootloader-common-bl-c-414) → [`main.c:457`](bl-h.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-457) → [`main.c:632`](bl-h.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-632) |

**⇒ 在这块板上，一次正常上电根本走不到 `bl.c` 的协议循环。** 只有第 12 步 `jump_to_app()` 返回（没跳成）才会掉进 [`bl.c:624`](stm32-common-main-c.md#^src-platforms-nuttx-src-bootloader-common-bl-c-624)。

---

## 4. "我看到的现象由谁产生"

| 台架现象 | 产生者 | 依据 |
|---|---|---|
| **绿色 LED 约 10 Hz 闪** | ①层 `led_set(LED_BLINK)` + SysTick 每 50 tick 翻转 | [`bl.c:640`](00-overview.md#^src-platforms-nuttx-src-bootloader-common-bl-c-640)、[`bl.c:447`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-c-447)、[`bl.c:478`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-c-478) |
| **绿 LED 常亮** | ①层正在擦除 | [`bl.c:772`](00-overview.md#^src-platforms-nuttx-src-bootloader-common-bl-c-772) |
| **上位机 `GET_SYNC` 收到 `0x12 0x10`** | ①层 `sync_response()` 经 ②层 `uart_cout` 发出 | [`bl.c:484`](bl-c.md#^src-platforms-nuttx-src-bootloader-common-bl-c-484) → [`bl.c:231`](00-overview.md#^src-platforms-nuttx-src-bootloader-common-bl-c-231) → [`uart.c:108`](bl-c.md#^src-src-lib-drivers-device-qurt-uart-c-108) |
| **"等一会儿自己跑了"** | ②层 `timeout = BOOTLOADER_DELAY = 5000 ms` 到期 | [`main.c:663`](00-overview.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-663)、[`hw_config.h:88`](stm32-common-main-c.md#^src-boards-rm2027-fmu-h743-src-hw-config-h-88)、[`bl.c:655`](uart-c.md#^src-platforms-nuttx-src-bootloader-common-bl-c-655) |
| **参数莫名其妙回默认 / app 突然过不了校验** | H7 ECC scrub 静默擦掉坏扇区 | [`main.c:689`](ecc-scrub-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-689) → [`ecc_scrub.c:142`](ecc-scrub-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32h7-ecc-scrub-c-142) |
| **跳 app 失败后 LED 一直闪、不再自动跳** | ②层 `timeout = 0` | [`main.c:777`](bl-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-777) / [`main.c:827`](00-overview.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-827) |
| **⚠️ 本板：绿 LED 其实在 PD11，板上是空的占位脚** | ③层 `BOARD_PIN_LED_BOOTLOADER` | [`hw_config.h:110`](00-overview.md#^src-boards-rm2027-fmu-h743-src-hw-config-h-110)、[`board_config.h:86`](board-layer.md#^src-boards-rm2027-fmu-h743-src-board-config-h-86)（注释："本板悬空，占位"） |

> **⇒ 最后一条是本板特有的坑**：上游 bootloader 用 LED 当"唯一可读日志"，本板这两颗 LED 都是**悬空占位脚**。
> 所以"怎么看 bootloader 活着"在本板上只能靠**上位机能不能握手**，不能靠灯。详见 [02_code_twin/bootloader/board-layer](board-layer.md)。

---

## 5. 本目录的阅读顺序

| 顺序 | 篇 | 读它回答什么 |
|---|---|---|
| 1 | [02_code_twin/bootloader/bl-h](bl-h.md) | ②层必须实现哪些函数（接口契约） |
| 2 | [02_code_twin/bootloader/stm32-common-main-c](stm32-common-main-c.md) | **跳不跳**怎么算出来的（本板 4 个决策点全都恒假 ⇒ 必然先试跳） |
| 3 | [02_code_twin/bootloader/bl-c](bl-c.md) | 跳不成之后，协议机怎么跑；首字延迟提交 |
| 4 | [02_code_twin/bootloader/flash-cache-c](flash-cache-c.md) | 为什么 H7 上"写一个 word"要先攒 8 个 |
| 5 | [02_code_twin/bootloader/ecc-scrub-c](ecc-scrub-c.md) | 那颗 H7 防砖补丁 |
| 6 | [02_code_twin/bootloader/uart-c](uart-c.md) | 本板唯一的上传通道 |
| 7 | [02_code_twin/bootloader/image-toc-crypto](image-toc-crypto.md) | TOC/签名分支（本板**没编进去**） |
| 8 | [02_code_twin/bootloader/board-layer](board-layer.md) | ③层要提供什么（含本板缺失项） |
| 9 | [02_code_twin/bootloader/cmakelists](cmakelists.md) | ①②③ 三层在构建期怎么被拼成一个镜像 |

---

## 跳转

**执行序的下一步**（不是目录的下一步）：

1. **想知道"为什么一次正常上电根本进不了协议循环"** → 读 [02_code_twin/bootloader/stm32-common-main-c](stm32-common-main-c.md)（4 个决策点逐个求值）。
2. **想知道"重启之后内核怎么把控制权交给 `bootloader_main`"**（本篇第 1 步到第 10 步的展开）
   → 跳到 01 层：[01_extracted/nuttx/00-poweron-chain](../../01_extracted/nuttx/00-poweron-chain.md)。
3. **想知道"跳过去之后 app 那侧发生了什么"**（第 13 步之后的 0x08020000）
   → [01_extracted/nuttx/bootloader-vs-app](../../01_extracted/nuttx/bootloader-vs-app.md) → [01_extracted/nuttx/nsh-and-rcS](../../01_extracted/nuttx/nsh-and-rcS.md)。
4. **想知道"为什么 bootloader 和 app 各有一套向量表、怎么切换"**
   → [01_extracted/stm32/vtor-vector-tables](../../01_extracted/stm32/vtor-vector-tables.md)。
5. **想知道"flash 怎么划分、参数区在哪"**
   → [01_extracted/stm32/flash-layout](../../01_extracted/stm32/flash-layout.md)。
6. **主线（上电到飞行的完整版本）** → [03_moc/01-poweron-walkthrough](../../03_moc/01-poweron-walkthrough.md)。
   ⚠️ **链接名对不上**：那篇里指向本套的 `[02_code_twin/bootloader/bl.c](bl-c.md)`、`[02_code_twin/bootloader/stm32-common-main.c](stm32-common-main-c.md)`、
   `[01_extracted/nuttx/nuttx启动链](../../01_extracted/nuttx/00-poweron-chain.md)`、`[01_extracted/stm32/h743-复位与启动](../../01_extracted/stm32/00-reset-clock-peripherals.md)` **不是本篇的实际文件名**；
   本目录的实际文件名是 `bl-c` / `stm32-common-main-c` / `00-poweron-chain` / `00-reset-clock-peripherals` + `vtor-vector-tables`。
   （已上报 lead，本篇不改别人的文件。）

### 本套内部推荐阅读序（执行序视角）

1. [02_code_twin/bootloader/bl-h](bl-h.md) → 2. [02_code_twin/bootloader/stm32-common-main-c](stm32-common-main-c.md) → 3. [02_code_twin/bootloader/bl-c](bl-c.md)
→ 4. [02_code_twin/bootloader/flash-cache-c](flash-cache-c.md) → 5. [02_code_twin/bootloader/ecc-scrub-c](ecc-scrub-c.md) → 6. [02_code_twin/bootloader/uart-c](uart-c.md)
→ 7. [01_extracted/nuttx/00-poweron-chain](../../01_extracted/nuttx/00-poweron-chain.md) → 8. [01_extracted/nuttx/bootloader-vs-app](../../01_extracted/nuttx/bootloader-vs-app.md) → 9. [01_extracted/nuttx/romfs](../../01_extracted/nuttx/romfs.md)
→ 10. [01_extracted/nuttx/nsh-and-rcS](../../01_extracted/nuttx/nsh-and-rcS.md) → 11. [01_extracted/stm32/vtor-vector-tables](../../01_extracted/stm32/vtor-vector-tables.md) → 12. [01_extracted/stm32/flash-layout](../../01_extracted/stm32/flash-layout.md)

---

## 未核实

- 第 1 步"硬件从 `BOOT_ADD0` 取向量"是 H7 参考手册级事实，**本仓代码里查不到**（[`bootloader_script.ld:126`](00-overview.md#^src-boards-rm2027-fmu-h743-nuttx-config-scripts-bootloader-script-ld-126) 只有 `ENTRY(_stext)`），标为**推理**。
- `_FLASH_KBYTES = *(uint32_t *)0x1FF1E880`（[`hw_config.h:103`](00-overview.md#^src-boards-rm2027-fmu-h743-src-hw-config-h-103)）用 **32 位**读一个 16 位寄存器，高 16 位取值我**没有核实**，故 `BOARD_FLASH_SIZE` 的实机数值标"未核实"（见 [01_extracted/stm32/flash-layout](../../01_extracted/stm32/flash-layout.md)）。

---

## 标注源码（代码 + 本文档对它的解释）

> **这是「代码孪生」层**：上面是代码原文（带行号），下面是**本文档针对这一段说的话**。
> 行号可点，直接跳到 PX4 源码那一行。
### `boards/rm2027/fmu-h743/nuttx-config/include/board.h`
<a id="src-boards-rm2027-fmu-h743-nuttx-config-include-board-h-104"></a>
**↓ 文档在讲这里：**[`boards/rm2027/fmu-h743/nuttx-config/include/board.h:104`](00-overview.md#^src-boards-rm2027-fmu-h743-nuttx-config-include-board-h-104)

```c
   101 │ 
   102 │ #define STM32_BOARD_USEHSE
   103 │ 
▶  104 │ #define STM32_PLLCFG_PLLSRC      RCC_PLLCKSELR_PLLSRC_HSE
   105 │ 
   106 │ /* PLL1, wide 4 - 8 MHz input, enable DIVP, DIVQ, DIVR
   107 │  *
```
> **说明**：2 | start | 清 .bss / 搬 .data / 搬 ramfuncs | nuttx/arch/arm/src/stm32h7/stm32_start.c:209 / :220 / :235 | ┃ 3 | start | stm32_clockconfig() ⇒ PLL 起来，CPU=480 MHz | :249；参数在 boards/rm2027/fmu-h743/nuttx-config/include/board.h:104 |
^src-boards-rm2027-fmu-h743-nuttx-config-include-board-h-104

### `boards/rm2027/fmu-h743/nuttx-config/scripts/bootloader_script.ld`
<a id="src-boards-rm2027-fmu-h743-nuttx-config-scripts-bootloader-script-ld-113"></a>
**↓ 文档在讲这里：**[`boards/rm2027/fmu-h743/nuttx-config/scripts/bootloader_script.ld:113`](00-overview.md#^src-boards-rm2027-fmu-h743-nuttx-config-scripts-bootloader-script-ld-113)

```c
   110 │ MEMORY
   111 │ {
   112 │ 	itcm  (rwx) : ORIGIN = 0x00000000, LENGTH =   64K
▶  113 │ 	flash (rx)  : ORIGIN = 0x08000000, LENGTH =  128K
   114 │ 	dtcm1 (rwx) : ORIGIN = 0x20000000, LENGTH =   64K
   115 │ 	dtcm2 (rwx) : ORIGIN = 0x20010000, LENGTH =   64K
   116 │ 	sram  (rwx) : ORIGIN = 0x24000000, LENGTH =  512K
```
> **说明**：1 | 硬件 | 从 0x08000000 取初始 SP + 复位向量 | 链接脚本 bootloader_script.ld:113（flash ORIGIN=0x08000000, LENGTH=128K）+ EXTERN(_vectors)(:125) |
^src-boards-rm2027-fmu-h743-nuttx-config-scripts-bootloader-script-ld-113

<a id="src-boards-rm2027-fmu-h743-nuttx-config-scripts-bootloader-script-ld-126"></a>
**↓ 文档在讲这里：**[`boards/rm2027/fmu-h743/nuttx-config/scripts/bootloader_script.ld:126`](00-overview.md#^src-boards-rm2027-fmu-h743-nuttx-config-scripts-bootloader-script-ld-126)

```c
   123 │ 
   124 │ OUTPUT_ARCH(arm)
   125 │ EXTERN(_vectors)
▶  126 │ ENTRY(_stext)
   127 │ 
   128 │ /*
   129 │  * Ensure that abort() is present in the final object.  The exception handling
```
> **说明**：第 1 步"硬件从 BOOT_ADD0 取向量"是 H7 参考手册级事实，本仓代码里查不到（bootloader_script.ld:126 只有 ENTRY(_stext)），标为推理。
^src-boards-rm2027-fmu-h743-nuttx-config-scripts-bootloader-script-ld-126

### `boards/rm2027/fmu-h743/src/board_config.h`
<a id="src-boards-rm2027-fmu-h743-src-board-config-h-86"></a>
**↓ 文档在讲这里：**[`boards/rm2027/fmu-h743/src/board_config.h:86`](00-overview.md#^src-boards-rm2027-fmu-h743-src-board-config-h-86)

```c
    83 │  * 真要做指示灯 → 飞线到这两个脚即可，无需改代码。
    84 │  */
    85 │ #define GPIO_nLED_BLUE          /* PD10（本板悬空，占位） */  (GPIO_OUTPUT|GPIO_PUSHPULL|GPIO_SPEED_2MHz|GPIO_OUTPUT_SET|GPIO_PORTD|GPIO_PIN10)
▶   86 │ #define GPIO_nLED_GREEN         /* PD11（本板悬空，占位） */  (GPIO_OUTPUT|GPIO_PUSHPULL|GPIO_SPEED_2MHz|GPIO_OUTPUT_SET|GPIO_PORTD|GPIO_PIN11)
    87 │ 
    88 │ #define BOARD_HAS_CONTROL_STATUS_LEDS   1
    89 │ #define BOARD_ARMED_STATE_LED           1
```
> **说明**：跳 app 失败后 LED 一直闪、不再自动跳 | ②层 timeout = 0 | main.c:777 / main.c:827 | ┃ ⚠️ 本板：绿 LED 其实在 PD11，板上是空的占位脚 | ③层 BOARD_PIN_LED_BOOTLOADER | hw_config.h:110、board_config.h:86（注释："本板悬空，占位"） |
^src-boards-rm2027-fmu-h743-src-board-config-h-86

### `boards/rm2027/fmu-h743/src/bootloader_main.c`
<a id="src-boards-rm2027-fmu-h743-src-bootloader-main-c-55"></a>
**↓ 文档在讲这里：**[`boards/rm2027/fmu-h743/src/bootloader_main.c:55`](00-overview.md#^src-boards-rm2027-fmu-h743-src-bootloader-main-c-55)

```c
    52 │ 
    53 │ __EXPORT void board_on_reset(int status) {}
    54 │ 
▶   55 │ __EXPORT void stm32_boardinitialize(void)
    56 │ {
    57 │ #if INTERFACE_USB
    58 │ 	/* configure USB interfaces */
```
> **说明**：3 | start | stm32_clockconfig() ⇒ PLL 起来，CPU=480 MHz | :249；参数在 boards/rm2027/fmu-h743/nuttx-config/include/board.h:104 | ┃ 4 | start | stm32_boardinitialize() ⇒ 跳进 ③ 层 | :262 → bootloader_main.c:55 |
^src-boards-rm2027-fmu-h743-src-bootloader-main-c-55

<a id="src-boards-rm2027-fmu-h743-src-bootloader-main-c-69"></a>
**↓ 文档在讲这里：**[`boards/rm2027/fmu-h743/src/bootloader_main.c:69`](00-overview.md#^src-boards-rm2027-fmu-h743-src-bootloader-main-c-69)

```c
    66 │ 	return 0;
    67 │ }
    68 │ 
▶   69 │ void board_late_initialize(void)
    70 │ {
    71 │ 	sercon_main(0, NULL);
    72 │ }
```
> **说明**：8 | nx_start | nx_bringup() ⇒ 建 workqueue + 建 AppBringUp 线程 | nx_start.c:743 → nx_bringup.c:530 / :537 / :443 | ┃ 9 | AppBringUp 线程 | board_late_initialize() ⇒ sercon_main()（USB CDC/ACM，本板落空） | nx_bringup.c:321 → bootloader_main.c:69 |
^src-boards-rm2027-fmu-h743-src-bootloader-main-c-69

### `boards/rm2027/fmu-h743/src/hw_config.h`
<a id="src-boards-rm2027-fmu-h743-src-hw-config-h-88"></a>
**↓ 文档在讲这里：**[`boards/rm2027/fmu-h743/src/hw_config.h:88`](00-overview.md#^src-boards-rm2027-fmu-h743-src-hw-config-h-88)

```c
    85 │ #define SERIAL1_DEV    0x04
    86 │ 
    87 │ #define APP_LOAD_ADDRESS               0x08020000
▶   88 │ #define BOOTLOADER_DELAY               5000
    89 │ /* ★ 本板（rm2027/fmu-h743）**没有 USB 硬件**
    90 │  *   → 关掉 USB 上传通道，只用串口通道上传固件
    91 │  *   → 串口通道模板板就有（/dev/ttyS0,57600 = USART1 = ttyS0）
```
> **说明**：上位机 GET_SYNC 收到 0x12 0x10 | ①层 sync_response() 经 ②层 uart_cout 发出 | bl.c:484 → bl.c:231 → uart.c:108 | ┃ "等一会儿自己跑了" | ②层 timeout = BOOTLOADER_DELAY = 5000 ms 到期 | main.c:663、hw_config.h:88、bl.c:655 |
^src-boards-rm2027-fmu-h743-src-hw-config-h-88

<a id="src-boards-rm2027-fmu-h743-src-hw-config-h-103"></a>
**↓ 文档在讲这里：**[`boards/rm2027/fmu-h743/src/hw_config.h:103`](00-overview.md#^src-boards-rm2027-fmu-h743-src-hw-config-h-103)

```c
   100 │ #define INTERFACE_USART_CONFIG         "/dev/ttyS0,57600"
   101 │ /* ★ 必须与 firmware.prototype 的 board_id 一致（本板 = 2027） */
   102 │ #define BOARD_TYPE                     2027
▶  103 │ #define _FLASH_KBYTES                  (*(uint32_t *)0x1FF1E880)
   104 │ #define BOARD_FLASH_SECTORS            (15)
   105 │ #define BOARD_FLASH_SIZE               (_FLASH_KBYTES * 1024)
   106 │ 
```
> **说明**：第 1 步"硬件从 BOOT_ADD0 取向量"是 H7 参考手册级事实，本仓代码里查不到（bootloader_script.ld:126 只有 ENTRY(_stext)），标为推理。 ┃ _FLASH_KBYTES = *(uint32_t *)0x1FF1E880（hw_config.h:103）用 32 位读一个 16 位寄存器，高 16 位取值我没有核实，故 BOARD_FLASH_SIZE 的实机数值标"未核实"（见 01_extracted/stm32/flash-layout）。
^src-boards-rm2027-fmu-h743-src-hw-config-h-103

<a id="src-boards-rm2027-fmu-h743-src-hw-config-h-110"></a>
**↓ 文档在讲这里：**[`boards/rm2027/fmu-h743/src/hw_config.h:110`](00-overview.md#^src-boards-rm2027-fmu-h743-src-hw-config-h-110)

```c
   107 │ #define OSC_FREQ                       8
   108 │ 
   109 │ #define BOARD_PIN_LED_ACTIVITY         GPIO_nLED_BLUE // BLUE
▶  110 │ #define BOARD_PIN_LED_BOOTLOADER       GPIO_nLED_GREEN // GREEN
   111 │ #define BOARD_LED_ON                   0
   112 │ #define BOARD_LED_OFF                  1
   113 │ 
```
> **说明**：跳 app 失败后 LED 一直闪、不再自动跳 | ②层 timeout = 0 | main.c:777 / main.c:827 | ┃ ⚠️ 本板：绿 LED 其实在 PD11，板上是空的占位脚 | ③层 BOARD_PIN_LED_BOOTLOADER | hw_config.h:110、board_config.h:86（注释："本板悬空，占位"） |
^src-boards-rm2027-fmu-h743-src-hw-config-h-110

### `platforms/nuttx/NuttX/nuttx/sched/init/nx_bringup.c`
<a id="src-platforms-nuttx-NuttX-nuttx-sched-init-nx-bringup-c-321"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/NuttX/nuttx/sched/init/nx_bringup.c:321`](00-overview.md#^src-platforms-nuttx-NuttX-nuttx-sched-init-nx-bringup-c-321)

```c
   318 │    * configured.
   319 │    */
   320 │ 
▶  321 │   board_late_initialize();
   322 │ #endif
   323 │ 
   324 │ #ifdef CONFIG_COREDUMP
```
> **说明**：8 | nx_start | nx_bringup() ⇒ 建 workqueue + 建 AppBringUp 线程 | nx_start.c:743 → nx_bringup.c:530 / :537 / :443 | ┃ 9 | AppBringUp 线程 | board_late_initialize() ⇒ sercon_main()（USB CDC/ACM，本板落空） | nx_bringup.c:321 → bootloader_main.c:69 |
^src-platforms-nuttx-NuttX-nuttx-sched-init-nx-bringup-c-321

<a id="src-platforms-nuttx-NuttX-nuttx-sched-init-nx-bringup-c-356"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/NuttX/nuttx/sched/init/nx_bringup.c:356`](00-overview.md#^src-platforms-nuttx-NuttX-nuttx-sched-init-nx-bringup-c-356)

```c
   353 │                    USERSPACE->us_entrypoint,
   354 │                    NULL, &attr, argv, NULL);
   355 │ #  else
▶  356 │   ret = task_spawn(CONFIG_INIT_ENTRYNAME,
   357 │                    CONFIG_INIT_ENTRYPOINT,
   358 │                    NULL, &attr, argv, NULL);
   359 │ #  endif
```
> **说明**：9 | AppBringUp 线程 | board_late_initialize() ⇒ sercon_main()（USB CDC/ACM，本板落空） | nx_bringup.c:321 → bootloader_main.c:69 | ┃ 10 | AppBringUp 线程 | task_spawn("bootloader_main", …) ⇒ ②层主函数起跑 | nx_bringup.c:356；CONFIG_INIT_ENTRYPOINT="bootloader_main"（nuttx-config/bootloader/defconfig:45） |
^src-platforms-nuttx-NuttX-nuttx-sched-init-nx-bringup-c-356

### `platforms/nuttx/NuttX/nuttx/sched/init/nx_start.c`
<a id="src-platforms-nuttx-NuttX-nuttx-sched-init-nx-start-c-635"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/NuttX/nuttx/sched/init/nx_start.c:635`](00-overview.md#^src-platforms-nuttx-NuttX-nuttx-sched-init-nx-start-c-635)

```c
   632 │ 
   633 │   /* Initialize the interrupt handling subsystem (if included) */
   634 │ 
▶  635 │   irq_initialize();
   636 │ 
   637 │   /* Initialize the POSIX timer facility (if included in the link) */
   638 │ 
```
> **说明**：5 | start | 开 I/D-Cache → nx_start() | :268-269 / :315 | ┃ 6 | nx_start | irq_initialize() ⇒ up_irqinitialize() ⇒ VTOR = 0x08000000 | nx_start.c:635 → nuttx/sched/irq/irq_initialize.c:98 → nuttx/arch/arm/src/stm32h7/stm32_irq.c:372 / :408 |
^src-platforms-nuttx-NuttX-nuttx-sched-init-nx-start-c-635

<a id="src-platforms-nuttx-NuttX-nuttx-sched-init-nx-start-c-675"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/NuttX/nuttx/sched/init/nx_start.c:675`](00-overview.md#^src-platforms-nuttx-NuttX-nuttx-sched-init-nx-start-c-675)

```c
   672 │    * that are different for each  processor and hardware platform.
   673 │    */
   674 │ 
▶  675 │   up_initialize();
   676 │ 
   677 │   /* Initialize common drivers */
   678 │ 
```
> **说明**：6 | nx_start | irq_initialize() ⇒ up_irqinitialize() ⇒ VTOR = 0x08000000 | nx_start.c:635 → nuttx/sched/irq/irq_initialize.c:98 → nuttx/arch/arm/src/stm32h7/stm32_irq.c:372 / :408 | ┃ 7 | nx_start | up_initialize() ⇒ arm_initialize_stack()（线程模式改用 PSP） | nx_start.c:675 → nuttx/arch/arm/src/common/arm_initialize.c:62 / :67（CONFIG_ARCH_INTERRUPTSTACK=768 > 7） |
^src-platforms-nuttx-NuttX-nuttx-sched-init-nx-start-c-675

<a id="src-platforms-nuttx-NuttX-nuttx-sched-init-nx-start-c-743"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/NuttX/nuttx/sched/init/nx_start.c:743`](00-overview.md#^src-platforms-nuttx-NuttX-nuttx-sched-init-nx-start-c-743)

```c
   740 │ 
   741 │   /* Create initial tasks and bring-up the system */
   742 │ 
▶  743 │   DEBUGVERIFY(nx_bringup());
   744 │ 
   745 │   /* Enter to idleloop */
   746 │ 
```
> **说明**：7 | nx_start | up_initialize() ⇒ arm_initialize_stack()（线程模式改用 PSP） | nx_start.c:675 → nuttx/arch/arm/src/common/arm_initialize.c:62 / :67（CONFIG_ARCH_INTERRUPTSTACK=768 > 7） | ┃ 8 | nx_start | nx_bringup() ⇒ 建 workqueue + 建 AppBringUp 线程 | nx_start.c:743 → nx_bringup.c:530 / :537 / :443 |
^src-platforms-nuttx-NuttX-nuttx-sched-init-nx-start-c-743

### `platforms/nuttx/NuttX/nuttx/sched/irq/irq_initialize.c`
<a id="src-platforms-nuttx-NuttX-nuttx-sched-irq-irq-initialize-c-98"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/NuttX/nuttx/sched/irq/irq_initialize.c:98`](00-overview.md#^src-platforms-nuttx-NuttX-nuttx-sched-irq-irq-initialize-c-98)

```c
    95 │   irqchain_initialize();
    96 │ #endif
    97 │ 
▶   98 │   up_irqinitialize();
    99 │ 
   100 │ #ifdef CONFIG_ARCH_PROTECT_ZERO_ADDRESS
   101 │   up_debugpoint_add(DEBUGPOINT_WATCHPOINT_RW, 0, 0,
```
> **说明**：5 | start | 开 I/D-Cache → nx_start() | :268-269 / :315 | ┃ 6 | nx_start | irq_initialize() ⇒ up_irqinitialize() ⇒ VTOR = 0x08000000 | nx_start.c:635 → nuttx/sched/irq/irq_initialize.c:98 → nuttx/arch/arm/src/stm32h7/stm32_irq.c:372 / :408 |
^src-platforms-nuttx-NuttX-nuttx-sched-irq-irq-initialize-c-98

### `platforms/nuttx/src/bootloader/common/bl.c`
<a id="src-platforms-nuttx-src-bootloader-common-bl-c-231"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:231`](00-overview.md#^src-platforms-nuttx-src-bootloader-common-bl-c-231)

```c
   228 │ 	return -1;
   229 │ }
   230 │ 
▶  231 │ inline void cout(uint8_t *buf, unsigned len)
   232 │ {
   233 │ #if INTERFACE_USB
   234 │ 
```
> **说明**：绿 LED 常亮 | ①层正在擦除 | bl.c:772 | ┃ 上位机 GET_SYNC 收到 0x12 0x10 | ①层 sync_response() 经 ②层 uart_cout 发出 | bl.c:484 → bl.c:231 → uart.c:108 |
^src-platforms-nuttx-src-bootloader-common-bl-c-231

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-308"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:308`](00-overview.md#^src-platforms-nuttx-src-bootloader-common-bl-c-308)

```c
   305 │ }
   306 │ 
   307 │ void
▶  308 │ jump_to_app()
   309 │ {
   310 │ 	const uint32_t *app_base = (const uint32_t *)APP_LOAD_ADDRESS;
   311 │ 	const uint32_t *vec_base = (const uint32_t *)((const uint32_t)app_base + APP_VECTOR_OFFSET);
```
> **说明**：main.c 才是"跳不跳"的裁判，bl.c 只是"裁判说去等主机"之后才上场的协议机。 ┃ jump_to_app() 定义在 ① 层（bl.c:308），调用却在 ② 层（main.c:771、main.c:824）——
^src-platforms-nuttx-src-bootloader-common-bl-c-308

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-414"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:414`](00-overview.md#^src-platforms-nuttx-src-bootloader-common-bl-c-414)

```c
   411 │ #endif
   412 │ 
   413 │ 	/* just for paranoia's sake */
▶  414 │ 	arch_flash_lock();
   415 │ 
   416 │ 	/* kill the systick interrupt */
   417 │ 	arch_systic_deinit();
```
> **说明**：12 | bootloader_main | 4 个决策点全判完 ⇒ try_boot 通常仍为 true ⇒ jump_to_app() | main.c:696 / :719 / :734 / :756 → :771 | ┃ 13 | jump_to_app | 校验过 ⇒ 关 Systick/接口/时钟 ⇒ arch_setvtor(0x08020000) ⇒ arch_do_jump() | bl.c:414 → main.c:457 → main.c:632 |
^src-platforms-nuttx-src-bootloader-common-bl-c-414

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-447"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:447`](00-overview.md#^src-platforms-nuttx-src-bootloader-common-bl-c-447)

```c
   444 │ 			timer[i]--;
   445 │ 		}
   446 │ 
▶  447 │ 	if ((_led_state == LED_BLINK) && (timer[TIMER_LED] == 0)) {
   448 │ 		led_toggle(LED_BOOTLOADER);
   449 │ 		timer[TIMER_LED] = 50;
   450 │ 	}
```
> **说明**：绿色 LED 约 10 Hz 闪 | ①层 led_set(LED_BLINK) + SysTick 每 50 tick 翻转 | bl.c:640、bl.c:447、bl.c:478 |
^src-platforms-nuttx-src-bootloader-common-bl-c-447

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-478"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:478`](00-overview.md#^src-platforms-nuttx-src-bootloader-common-bl-c-478)

```c
   475 │ 
   476 │ 	case LED_BLINK:
   477 │ 		/* restart the blink state machine ASAP */
▶  478 │ 		timer[TIMER_LED] = 0;
   479 │ 		break;
   480 │ 	}
   481 │ }
```
> **说明**：绿色 LED 约 10 Hz 闪 | ①层 led_set(LED_BLINK) + SysTick 每 50 tick 翻转 | bl.c:640、bl.c:447、bl.c:478 |
^src-platforms-nuttx-src-bootloader-common-bl-c-478

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-484"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:484`](00-overview.md#^src-platforms-nuttx-src-bootloader-common-bl-c-484)

```c
   481 │ }
   482 │ 
   483 │ static void
▶  484 │ sync_response(void)
   485 │ {
   486 │ 	uint8_t data[] = {
   487 │ 		PROTO_INSYNC, // "in sync"
```
> **说明**：绿 LED 常亮 | ①层正在擦除 | bl.c:772 | ┃ 上位机 GET_SYNC 收到 0x12 0x10 | ①层 sync_response() 经 ②层 uart_cout 发出 | bl.c:484 → bl.c:231 → uart.c:108 |
^src-platforms-nuttx-src-bootloader-common-bl-c-484

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-624"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:624`](00-overview.md#^src-platforms-nuttx-src-bootloader-common-bl-c-624)

```c
   621 │ }
   622 │ 
   623 │ void
▶  624 │ bootloader(unsigned timeout)
   625 │ {
   626 │ 	bl_type = NONE; // The type of the bootloader, whether loading from USB or USART, will be determined by on what port the bootloader recevies its first valid command.
   627 │ 	volatile uint32_t  bl_state = 0; // Must see correct command sequence to erase and reboot (commit first word)
```
> **说明**：└─ bl.c:624（①层协议循环）
> **说明**：⇒ 在这块板上，一次正常上电根本走不到 bl.c 的协议循环。 只有第 12 步 jump_to_app() 返回（没跳成）才会掉进 bl.c:624。
^src-platforms-nuttx-src-bootloader-common-bl-c-624

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-640"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:640`](00-overview.md#^src-platforms-nuttx-src-bootloader-common-bl-c-640)

```c
   637 │ 	}
   638 │ 
   639 │ 	/* make the LED blink while we are idle */
▶  640 │ 	led_set(LED_BLINK);
   641 │ 
   642 │ 	while (true) {
   643 │ 		volatile int c;
```
> **说明**：绿色 LED 约 10 Hz 闪 | ①层 led_set(LED_BLINK) + SysTick 每 50 tick 翻转 | bl.c:640、bl.c:447、bl.c:478 |
^src-platforms-nuttx-src-bootloader-common-bl-c-640

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-655"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:655`](00-overview.md#^src-platforms-nuttx-src-bootloader-common-bl-c-655)

```c
   652 │ 
   653 │ 		do {
   654 │ 			/* if we have a timeout and the timer has expired, return now */
▶  655 │ 			if (timeout && !timer[TIMER_BL_WAIT]) {
   656 │ 				return;
   657 │ 			}
   658 │ 
```
> **说明**：上位机 GET_SYNC 收到 0x12 0x10 | ①层 sync_response() 经 ②层 uart_cout 发出 | bl.c:484 → bl.c:231 → uart.c:108 | ┃ "等一会儿自己跑了" | ②层 timeout = BOOTLOADER_DELAY = 5000 ms 到期 | main.c:663、hw_config.h:88、bl.c:655 |
^src-platforms-nuttx-src-bootloader-common-bl-c-655

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-772"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:772`](00-overview.md#^src-platforms-nuttx-src-bootloader-common-bl-c-772)

```c
   769 │ 
   770 │ 			// clear the bootloader LED while erasing - it stops blinking at random
   771 │ 			// and that's confusing
▶  772 │ 			led_set(LED_ON);
   773 │ 
   774 │ 			// erase all sectors
   775 │ 			arch_flash_unlock();
```
> **说明**：绿色 LED 约 10 Hz 闪 | ①层 led_set(LED_BLINK) + SysTick 每 50 tick 翻转 | bl.c:640、bl.c:447、bl.c:478 | ┃ 绿 LED 常亮 | ①层正在擦除 | bl.c:772 |
^src-platforms-nuttx-src-bootloader-common-bl-c-772

### `platforms/nuttx/src/bootloader/stm/stm32_common/main.c`
<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-457"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:457`](00-overview.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-457)

```c
   454 │ 	return up_progmem_write(address, buffer, buflen);
   455 │ }
   456 │ 
▶  457 │ inline void arch_setvtor(const uint32_t *address)
   458 │ {
   459 │ 	putreg32((uint32_t)address, NVIC_VECTAB);
   460 │ }
```
> **说明**：12 | bootloader_main | 4 个决策点全判完 ⇒ try_boot 通常仍为 true ⇒ jump_to_app() | main.c:696 / :719 / :734 / :756 → :771 | ┃ 13 | jump_to_app | 校验过 ⇒ 关 Systick/接口/时钟 ⇒ arch_setvtor(0x08020000) ⇒ arch_do_jump() | bl.c:414 → main.c:457 → main.c:632 |
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-457

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-632"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:632`](00-overview.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-632)

```c
   629 │ #endif
   630 │ 
   631 │ /* Make the actual jump to app */
▶  632 │ void
   633 │ arch_do_jump(const uint32_t *app_base)
   634 │ {
   635 │ 	/* extract the stack and entrypoint from the app vector table and go */
```
> **说明**：12 | bootloader_main | 4 个决策点全判完 ⇒ try_boot 通常仍为 true ⇒ jump_to_app() | main.c:696 / :719 / :734 / :756 → :771 | ┃ 13 | jump_to_app | 校验过 ⇒ 关 Systick/接口/时钟 ⇒ arch_setvtor(0x08020000) ⇒ arch_do_jump() | bl.c:414 → main.c:457 → main.c:632 |
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-632

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-660"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:660`](00-overview.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-660)

```c
   657 │ }
   658 │ 
   659 │ int
▶  660 │ bootloader_main(int argc, char *argv[])
   661 │ {
   662 │ 	bool try_boot = true;			/* try booting before we drop to the bootloader */
   663 │ 	unsigned timeout = BOOTLOADER_DELAY;	/* if nonzero, drop out of the bootloader after this time */
```
> **说明**：└─ bootloader_main() ★ ②层真正的主函数 main.c:660
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-660

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-663"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:663`](00-overview.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-663)

```c
   660 │ bootloader_main(int argc, char *argv[])
   661 │ {
   662 │ 	bool try_boot = true;			/* try booting before we drop to the bootloader */
▶  663 │ 	unsigned timeout = BOOTLOADER_DELAY;	/* if nonzero, drop out of the bootloader after this time */
   664 │ 
   665 │ 	/* Enable the FPU before we hit any FP instructions */
   666 │ 	SCB_CPACR |= ((3UL << 10 * 2) | (3UL << 11 * 2)); /* set CP10 Full Access and set CP11 Full Access */
```
> **说明**：上位机 GET_SYNC 收到 0x12 0x10 | ①层 sync_response() 经 ②层 uart_cout 发出 | bl.c:484 → bl.c:231 → uart.c:108 | ┃ "等一会儿自己跑了" | ②层 timeout = BOOTLOADER_DELAY = 5000 ms 到期 | main.c:663、hw_config.h:88、bl.c:655 |
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-663

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-682"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:682`](00-overview.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-682)

```c
   679 │ #endif
   680 │ 
   681 │ 	/* do board-specific initialisation */
▶  682 │ 	board_init();
   683 │ 
   684 │ 	/* configure the clock for bootloader activity */
   685 │ 	clock_init();
```
> **说明**：10 | AppBringUp 线程 | task_spawn("bootloader_main", …) ⇒ ②层主函数起跑 | nx_bringup.c:356；CONFIG_INIT_ENTRYPOINT="bootloader_main"（nuttx-config/bootloader/defconfig:45） | ┃ 11 | bootloader_main | board_init() ⇒ fw_size = APP_SIZE_MAX；check_ecc_errors() | main.c:682 → :274；:689 |
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-682

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-689"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:689`](00-overview.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-689)

```c
   686 │ 
   687 │ #if defined(CONFIG_ARCH_CHIP_STM32H7)
   688 │ 	/* scrub any uncorrectable flash ECC errors before we try to run the app */
▶  689 │ 	check_ecc_errors();
   690 │ #endif
   691 │ 
   692 │ 	/*
```
> **说明**："等一会儿自己跑了" | ②层 timeout = BOOTLOADER_DELAY = 5000 ms 到期 | main.c:663、hw_config.h:88、bl.c:655 | ┃ 参数莫名其妙回默认 / app 突然过不了校验 | H7 ECC scrub 静默擦掉坏扇区 | main.c:689 → ecc_scrub.c:142 |
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-689

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-771"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:771`](00-overview.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-771)

```c
   768 │ #endif
   769 │ 
   770 │ 		/* try to boot immediately */
▶  771 │ 		jump_to_app();
   772 │ 
   773 │ 		// If it failed to boot, reset the boot signature and stay in bootloader
   774 │ 		board_set_rtc_signature(BOOT_RTC_SIGNATURE);
```
> **说明**：├─ try_boot = true ⇒ jump_to_app() main.c:771 ← 常态路径
> **说明**：main.c 才是"跳不跳"的裁判，bl.c 只是"裁判说去等主机"之后才上场的协议机。 ┃ jump_to_app() 定义在 ① 层（bl.c:308），调用却在 ② 层（main.c:771、main.c:824）——
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-771

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-777"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:777`](00-overview.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-777)

```c
   774 │ 		board_set_rtc_signature(BOOT_RTC_SIGNATURE);
   775 │ 
   776 │ 		/* booting failed, stay in the bootloader forever */
▶  777 │ 		timeout = 0;
   778 │ 	}
   779 │ 
   780 │ 
```
> **说明**：参数莫名其妙回默认 / app 突然过不了校验 | H7 ECC scrub 静默擦掉坏扇区 | main.c:689 → ecc_scrub.c:142 | ┃ 跳 app 失败后 LED 一直闪、不再自动跳 | ②层 timeout = 0 | main.c:777 / main.c:827 |
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-777

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-783"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:783`](00-overview.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-783)

```c
   780 │ 
   781 │ 	/* start the interface */
   782 │ #if INTERFACE_USART
▶  783 │ 	cinit(BOARD_INTERFACE_CONFIG_USART, USART);
   784 │ #endif
   785 │ #if INTERFACE_USB
   786 │ 	cinit(BOARD_INTERFACE_CONFIG_USB, USB);
```
> **说明**：└─ 否则 ⇒ cinit(...) → while(1) bootloader(timeout) main.c:783 / :802
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-783

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-824"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:824`](00-overview.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-824)

```c
   821 │ #endif
   822 │ 
   823 │ 		/* look to see if we can boot the app */
▶  824 │ 		jump_to_app();
   825 │ 
   826 │ 		/* launching the app failed - stay in the bootloader forever */
   827 │ 		timeout = 0;
```
> **说明**：main.c 才是"跳不跳"的裁判，bl.c 只是"裁判说去等主机"之后才上场的协议机。 ┃ jump_to_app() 定义在 ① 层（bl.c:308），调用却在 ② 层（main.c:771、main.c:824）——
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-824

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-827"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:827`](00-overview.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-827)

```c
   824 │ 		jump_to_app();
   825 │ 
   826 │ 		/* launching the app failed - stay in the bootloader forever */
▶  827 │ 		timeout = 0;
   828 │ 	}
   829 │ }
   830 │ 
```
> **说明**：参数莫名其妙回默认 / app 突然过不了校验 | H7 ECC scrub 静默擦掉坏扇区 | main.c:689 → ecc_scrub.c:142 | ┃ 跳 app 失败后 LED 一直闪、不再自动跳 | ②层 timeout = 0 | main.c:777 / main.c:827 |
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-827

### `platforms/nuttx/src/bootloader/stm/stm32h7/ecc_scrub.c`
<a id="src-platforms-nuttx-src-bootloader-stm-stm32h7-ecc-scrub-c-142"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32h7/ecc_scrub.c:142`](00-overview.md#^src-platforms-nuttx-src-bootloader-stm-stm32h7-ecc-scrub-c-142)

```c
   139 │ 	for (unsigned sector = BOARD_FIRST_FLASH_SECTOR_TO_ERASE; sector <= last_sector; sector++) {
   140 │ 		uintptr_t base = APP_LOAD_ADDRESS + (sector - BOARD_FIRST_FLASH_SECTOR_TO_ERASE) * FLASH_SECTOR_SIZE;
   141 │ 
▶  142 │ 		if (flash_region_has_ecc_error(base, FLASH_SECTOR_SIZE)) {
   143 │ 			ecc_flags_clear();
   144 │ 			up_progmem_eraseblock(sector);
   145 │ 		}
```
> **说明**："等一会儿自己跑了" | ②层 timeout = BOOTLOADER_DELAY = 5000 ms 到期 | main.c:663、hw_config.h:88、bl.c:655 | ┃ 参数莫名其妙回默认 / app 突然过不了校验 | H7 ECC scrub 静默擦掉坏扇区 | main.c:689 → ecc_scrub.c:142 |
^src-platforms-nuttx-src-bootloader-stm-stm32h7-ecc-scrub-c-142

### `src/lib/drivers/device/qurt/uart.c`
<a id="src-src-lib-drivers-device-qurt-uart-c-108"></a>
**↓ 文档在讲这里：**[`src/lib/drivers/device/qurt/uart.c:108`](00-overview.md#^src-src-lib-drivers-device-qurt-uart-c-108)

```c
   105 │ 
   106 │ 	if (_callbacks_configured) {
   107 │ 		uint32_t interval_counter = (timeout_us + (UART_READ_POLL_INTERVAL_US - 1)) / UART_READ_POLL_INTERVAL_US;
▶  108 │ 		// PX4_INFO("UART interval counter = %d", interval_counter);
   109 │ 		int read_len = 0;
   110 │ 
   111 │ 		do {
```
> **说明**：绿 LED 常亮 | ①层正在擦除 | bl.c:772 | ┃ 上位机 GET_SYNC 收到 0x12 0x10 | ①层 sync_response() 经 ②层 uart_cout 发出 | bl.c:484 → bl.c:231 → uart.c:108 |
^src-src-lib-drivers-device-qurt-uart-c-108
