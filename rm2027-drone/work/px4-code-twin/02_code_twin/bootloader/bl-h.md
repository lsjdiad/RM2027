# `bl.h` —— ①层写给 ②③层的一张"你必须实现我"的清单

> **源码**：`platforms/nuttx/src/bootloader/common/bl.h`（135 行）
> **层**：① 通用（但内容全是**对 ②层的接口要求**）
> **被谁包含**：[`bl.c:48`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-c-48)、[`main.c:19`](bl-h.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-19)、[`bootloader_main.c:41`](bl-h.md#^src-boards-rm2027-fmu-h743-src-bootloader-main-c-41)（③层也要它——因为要用 `bootloader()` 和 `boardinfo`）

---

## 1. 运行时它处在哪

`bl.h` **不是**一个"被调用的东西"，它是一份**编译期契约**。
它出现的唯一理由是：**①层（`bl.c`）需要操作 flash / LED / 串口 / 时钟，但它一行芯片相关代码都不许有**
（[`bl.c:34`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-c-34) 的文档注释原文：*"Aside from the header includes below, this file should have no board-specific logic."*）。

**⇒ 所以这份清单的用途是：谁要把 PX4 bootloader 移植到一块新板，就按这张表把 ②③层填出来。**

---

## 2. 契约清单（逐条）

### 2.1 数据结构：一个 `struct boardinfo`，两个 `extern`

| 行号 | 内容 | 谁填 / 谁读 |
|---|---|---|
| [`bl.h:56`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-h-56) | `struct boardinfo { board_type; board_rev; fw_size; systick_mhz } __attribute__((packed))` | ②层 [`main.c:98`](bl-h.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-98) **填初值**（`board_type = BOARD_TYPE`、`systick_mhz = CPUCLK/1e6`），`board_init()` 再补 `fw_size`（[`main.c:274`](stm32-common-main-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-274)） |
| [`bl.h:64`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-h-64) | `extern struct boardinfo board_info;` | ①层读它决定擦多少（[`bl.c:785`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-c-785) `board_info.fw_size`、[`bl.c:902`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-c-902) CRC 范围）、②层读它决定 SysTick 重载（[`main.c:369`](bl-h.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-369)） |
| [`bl.h:67`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-h-67) | `void bootloader(unsigned timeout)` | **①层唯一的对外入口**；②层 [`main.c:802`](bl-h.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-802) 调用 |
| [`bl.h:66`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-h-66) | `void jump_to_app(void)` | ①层**实现**（[`bl.c:307`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-c-307)），②层**调用**（[`main.c:771`](bl-h.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-771)、[`main.c:824`](bl-h.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-824)）—— **定义在①、调用在②** |
| [`bl.h:68`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-h-68) | `void delay(unsigned msec)` | ①层实现（[`bl.c:453`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-c-453)），①层自己用（[`bl.c:1131`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-c-1131)） |

> ★ [`bl.h:70`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-h-70) 的 `BL_WAIT_MAGIC 0x19710317`（"magic number in PWR regs to wait in bootloader"）在本仓
> **查不到使用处**，标**未核实**（可能是给 PX4IO 或旧平台留的）。

### 2.2 通用定时器系统：4 个 `timer[]`

| 行号 | 内容 | 关键点 |
|---|---|---|
| [`bl.h:73`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-h-73) | `NTIMERS=4`；`TIMER_BL_WAIT=0`、`TIMER_CIN=1`、`TIMER_LED=2`、`TIMER_DELAY=3`；`extern volatile unsigned timer[]` | 注释写明：**"each timer decrements every millisecond if > 0"** |
| [`bl.c:435`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-c-435) | 定义处 | — |
| [`bl.c:437`](board-layer.md#^src-platforms-nuttx-src-bootloader-common-bl-c-437) | **唯一递减它们的地方** = `sys_tick_handler()` | ⇒ 这个计数器**不是**由硬件自动减的，是靠 ②③层**把它挂到系统 tick 上** |

> ★★ **执行序上的关键一跳**：`bl.c:453 delay()` 用 `while (timer[TIMER_DELAY] > 0);` 死等，
> 而 `timer[]` 只在 `bl.c:437 sys_tick_handler()` 里递减；
> `sys_tick_handler()` 只被 ③层 `bootloader_main.c:75 board_timerhook()` 调用；
> `board_timerhook()` 只在 NuttX 的 `CONFIG_SYSTEMTICK_HOOK=y` 打开时被内核调用
> （[`nuttx/sched/sched/sched_processtimer.c:199`](bl-h.md#^src-platforms-nuttx-NuttX-nuttx-sched-sched-sched-processtimer-c-199)）。
> **⇒ 若把 `CONFIG_SYSTEMTICK_HOOK` 关掉，`bl.c` 里所有超时/延时都会永久卡死。**
> 本板是开的：`nuttx-config/bootloader/defconfig:71`（构建产物 `build/rm2027_fmu-h743_bootloader/NuttX/nuttx/.config:578` 复核一致）。

### 2.3 异步收字节缓冲区（**本板实际是死代码**）

| 行号 | 内容 |
|---|---|
| [`bl.h:81`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-h-81) | `extern void buf_put(uint8_t b); extern int buf_get(void);` |
| [`bl.c:276`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-c-276) | `static unsigned head, tail; static uint8_t rx_buf[256] USB_DATA_ALIGN;` |
| [`bl.c:283`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-c-283) / [`bl.c:294`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-c-294) | 环形缓冲实现 |

**实测**：在整棵 `platforms/nuttx/src/bootloader/` 里 grep `buf_put`，**除了定义处没有任何调用者**。
⇒ 这块 256 B 的 `rx_buf` 在本板上是**未使用的 RAM**（上游给"中断驱动收字节"的平台留的钩子）。
标**实测**（grep 全仓无调用）。

### 2.4 LED：只有两种"灯位"，但语义由①层给

| 行号 | 内容 |
|---|---|
| [`bl.h:89`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-h-89) | `LED_ACTIVITY 1` / `LED_BOOTLOADER 2` |
| [`bl.h:96`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-h-96) | `extern void led_on/led_off/led_toggle(unsigned led);` —— ②③层必须实现 |
| ①层怎么用 | [`bl.c:651`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-c-651) / [`bl.c:664`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-c-664) 操作 **`LED_ACTIVITY`**（"正在收命令"心跳，无 blink 状态机）；`bl.c:462-481 led_set()` 操作 **`LED_BOOTLOADER`**（三态：`LED_BLINK/LED_ON/LED_OFF`） |
| ②层实现 | [`main.c:572`](bl-h.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-572)（三个函数各一个 `switch`，空的 —— 因为要等 ③层的 `BOARD_PIN_LED_*` 宏） |
| ③层填 | [`hw_config.h:109`](board-layer.md#^src-boards-rm2027-fmu-h743-src-hw-config-h-109)（**本板两颗灯都是悬空占位脚**，见 [02_code_twin/bootloader/board-layer](board-layer.md)） |

### 2.5 flash / 架构原语（②层必须全实现）

| 行号 | 函数 | ②层实现处 | ①层调用处 |
|---|---|---|---|
| [`bl.h:101`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-h-101) | `board_deinit(void)` | [`main.c:317`](bl-h.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-317) | [`bl.c:426`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-c-426)（跳转前清板级外设） |
| [`bl.h:102`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-h-102) | `board_get_devices(void)` | [`main.c:258`](uart-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-258) | [`bl.c:540`](uart-c.md#^src-platforms-nuttx-src-bootloader-common-bl-c-540)（决定去哪个通道收字节） |
| [`bl.h:103`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-h-103) | `clock_deinit(void)` | [`main.c:406`](bl-h.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-406) | [`bl.c:423`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-c-423)（跳转前把 RCC 打回 HSI） |
| [`bl.h:104`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-h-104) | `flash_func_sector_size(unsigned)` | [`main.c:467`](stm32-common-main-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-467) | [`bl.c:777`](stm32-common-main-c.md#^src-platforms-nuttx-src-bootloader-common-bl-c-777)（用返回值 `!= 0` 当循环终止条件） |
| [`bl.h:105`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-h-105) | `flash_func_erase_sector(unsigned, bool)` | [`main.c:477`](stm32-common-main-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-477) | [`bl.c:778`](ecc-scrub-c.md#^src-platforms-nuttx-src-bootloader-common-bl-c-778) |
| [`bl.h:106`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-h-106) | `flash_func_write_word(addr, word)` | [`main.c:489`](bl-h.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-489) | [`bl.c:873`](flash-cache-c.md#^src-platforms-nuttx-src-bootloader-common-bl-c-873) / [`bl.c:1074`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-c-1074) / [`bl.c:1119`](flash-cache-c.md#^src-platforms-nuttx-src-bootloader-common-bl-c-1119) |
| [`bl.h:107`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-h-107) | `flash_func_read_word(addr)` | [`main.c:496`](bl-h.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-496) | [`bl.c:727`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-c-727) / `:786` / `:876` / `:909` / `:1076` / `:1121` |
| [`bl.h:108`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-h-108) | `flash_func_read_otp(addr)` | [`main.c:508`](bl-h.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-508)（**本板恒返回 0**） | [`bl.c:937`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-c-937) |
| [`bl.h:109`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-h-109) | `flash_func_read_sn(addr)` | [`main.c:564`](bl-h.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-564)（读 `STM32_SYSMEM_UID`） | [`bl.c:965`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-c-965) |
| [`bl.h:110`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-h-110) | `arch_flash_lock/unlock()` | [`main.c:439`](bl-h.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-439) / `:445` | [`bl.c:414`](stm32-common-main-c.md#^src-platforms-nuttx-src-bootloader-common-bl-c-414) / `:775` |
| [`bl.h:112`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-h-112) | `arch_setvtor(const uint32_t *)` | [`main.c:457`](bl-h.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-457) | **[`bl.c:429`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-c-429)**（★ 向量表切换，见 [01_extracted/stm32/vtor-vector-tables](../../01_extracted/stm32/vtor-vector-tables.md)） |
| [`bl.h:113`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-h-113) | `arch_do_jump(const uint32_t *)` | [`main.c:632`](bl-h.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-632) | **[`bl.c:432`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-c-432)** |
| [`bl.h:114`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-h-114) | `arch_systic_init/deinit()` | [`main.c:365`](stm32-common-main-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-365) / `:374` | [`bl.c:632`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-c-632) / [`bl.c:417`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-c-417) |
| [`bl.h:117`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-h-117) | `get_mcu_id` / `get_mcu_desc` / `check_silicon` | [`main.c:514`](bl-h.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-514) / `:519` / `:559` | [`bl.c:981`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-c-981) / `:999` / `:760`（`check_silicon` 在 H7 上恒返回 0，且调用点被 `TARGET_HW_PX4_FMU_V4` 包住 ⇒ **本板进不去**） |

### 2.6 通道 in/out 与 APP 向量表偏移

| 行号 | 内容 | 关键点 |
|---|---|---|
| [`bl.h:127`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-h-127) | `cinit(void*, uint8_t interface)` / `cfini` / `cin(uint32_t devices)` / `cout(uint8_t*, unsigned)` | ①层实现（`bl.c:174 / :191 / :200 / :231`），内部按 `INTERFACE_USB`/`INTERFACE_USART` 编译期裁剪 |
| [`bl.h:132`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-h-132) | `APP_VECTOR_OFFSET`（默认 0）+ `APP_VECTOR_OFFSET_WORDS` | ⇒ **本板 = 0**（无人重定义），所以走 [`bl.c:840`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-c-840) 那条 `#if APP_VECTOR_OFFSET == 0` 的分支；②层 `fmc.c:60 fc_reset()` 也用这个宏 |

---

## 3. "我看到的现象由谁产生"

| 现象 | 契约里对应哪一条 |
|---|---|
| 上位机 `GET_DEVICE` 报回的 board_id = **2027** | `bl.h:57 board_type` ← ②层 [`main.c:99`](board-layer.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-99) ← ③层 [`hw_config.h:102`](board-layer.md#^src-boards-rm2027-fmu-h743-src-hw-config-h-102) |
| 上位机 `GET_DEVICE` 报回的 FW_SIZE = **1920 K**（本板推导值，未上板核实） | `bl.h:59 fw_size` ← ②层 [`main.c:86`](stm32-common-main-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-86) 的 `APP_SIZE_MAX` |
| LED 闪 / 亮 / 灭 | [`bl.h:96`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-h-96) 三个函数 ← ③层 `BOARD_PIN_LED_*` 宏（**本板悬空 ⇒ 看不到**） |
| 擦除耗时可感知（几十秒级） | [`bl.c:777`](stm32-common-main-c.md#^src-platforms-nuttx-src-bootloader-common-bl-c-777) 先擦全片再**逐字读回校验**，每 4 B 一次 `flash_func_read_word` |
| 上传中途断电，板子"变砖"但能重刷 | `bl.h` 不含这条设计本身；它是 ①层 `bl.c:629/853/1118` 的实现 + `bl.h:132 APP_VECTOR_OFFSET`（详见 [02_code_twin/bootloader/bl-c](bl-c.md)） |

---

## 跳转

- **下一步**：②层拿到这份清单后实际怎么填 → [02_code_twin/bootloader/stm32-common-main-c](stm32-common-main-c.md)。
- 若你是要**给一块新板写 ③ 层**，先看 [02_code_twin/bootloader/board-layer](board-layer.md)（本板填了什么、缺了什么），
  再去 [02_code_twin/bootloader/cmakelists](cmakelists.md) 看它怎么被编进去。
- `arch_setvtor` / `arch_do_jump` 的硬件语义（VTOR、MSP 切换）→ [01_extracted/stm32/vtor-vector-tables](../../01_extracted/stm32/vtor-vector-tables.md)。
- `timer[]` 靠系统 tick 递减这件事背后的 NuttX 机制 → [01_extracted/nuttx/00-poweron-chain](../../01_extracted/nuttx/00-poweron-chain.md)。

---

## 未核实

- `bl.h:70 BL_WAIT_MAGIC` 全仓无使用者（grep 无命中）⇒ 我标"未核实用途"，未编造。
- `timer[TIMER_LED] = 50` ⇒ 50 ms 半周期 ⇒ 10 Hz 整周期：这是**从 [`bl.c:447`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-c-447) 与 [`bl.c:478`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-c-478) 的代码推理**，
  不是实测（本板 LED 悬空，台架上无法目视核对）。

---

## 标注源码（代码 + 本文档对它的解释）

> **这是「代码孪生」层**：上面是代码原文（带行号），下面是**本文档针对这一段说的话**。
> 行号可点，直接跳到 PX4 源码那一行。
### `boards/rm2027/fmu-h743/src/bootloader_main.c`
<a id="src-boards-rm2027-fmu-h743-src-bootloader-main-c-41"></a>
**↓ 文档在讲这里：**[`boards/rm2027/fmu-h743/src/bootloader_main.c:41`](bl-h.md#^src-boards-rm2027-fmu-h743-src-bootloader-main-c-41)

```c
    38 │ */
    39 │ 
    40 │ #include "board_config.h"
▶   41 │ #include "bl.h"
    42 │ 
    43 │ #include <nuttx/config.h>
    44 │ #include <nuttx/board.h>
```
> **说明**：层：① 通用（但内容全是对 ②层的接口要求） ┃ 被谁包含：bl.c:48、main.c:19、bootloader_main.c:41（③层也要它——因为要用 bootloader() 和 boardinfo）
^src-boards-rm2027-fmu-h743-src-bootloader-main-c-41

### `boards/rm2027/fmu-h743/src/hw_config.h`
<a id="src-boards-rm2027-fmu-h743-src-hw-config-h-102"></a>
**↓ 文档在讲这里：**[`boards/rm2027/fmu-h743/src/hw_config.h:102`](bl-h.md#^src-boards-rm2027-fmu-h743-src-hw-config-h-102)

```c
    99 │ #define INTERFACE_USART                1
   100 │ #define INTERFACE_USART_CONFIG         "/dev/ttyS0,57600"
   101 │ /* ★ 必须与 firmware.prototype 的 board_id 一致（本板 = 2027） */
▶  102 │ #define BOARD_TYPE                     2027
   103 │ #define _FLASH_KBYTES                  (*(uint32_t *)0x1FF1E880)
   104 │ #define BOARD_FLASH_SECTORS            (15)
   105 │ #define BOARD_FLASH_SIZE               (_FLASH_KBYTES * 1024)
```
> **说明**：上位机 GET_DEVICE 报回的 board_id = 2027 | bl.h:57 board_type ← ②层 main.c:99 ← ③层 hw_config.h:102 |
^src-boards-rm2027-fmu-h743-src-hw-config-h-102

<a id="src-boards-rm2027-fmu-h743-src-hw-config-h-109"></a>
**↓ 文档在讲这里：**[`boards/rm2027/fmu-h743/src/hw_config.h:109`](bl-h.md#^src-boards-rm2027-fmu-h743-src-hw-config-h-109)

```c
   106 │ 
   107 │ #define OSC_FREQ                       8
   108 │ 
▶  109 │ #define BOARD_PIN_LED_ACTIVITY         GPIO_nLED_BLUE // BLUE
   110 │ #define BOARD_PIN_LED_BOOTLOADER       GPIO_nLED_GREEN // GREEN
   111 │ #define BOARD_LED_ON                   0
   112 │ #define BOARD_LED_OFF                  1
```
> **说明**：②层实现 | main.c:572（三个函数各一个 switch，空的 —— 因为要等 ③层的 BOARD_PIN_LED_* 宏） | ┃ ③层填 | hw_config.h:109（本板两颗灯都是悬空占位脚，见 02_code_twin/bootloader/board-layer） |
^src-boards-rm2027-fmu-h743-src-hw-config-h-109

### `platforms/nuttx/NuttX/nuttx/sched/sched/sched_processtimer.c`
<a id="src-platforms-nuttx-NuttX-nuttx-sched-sched-sched-processtimer-c-199"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/NuttX/nuttx/sched/sched/sched_processtimer.c:199`](bl-h.md#^src-platforms-nuttx-NuttX-nuttx-sched-sched-sched-processtimer-c-199)

```c
   196 │ 
   197 │   wd_timer(clock_systime_ticks());
   198 │ 
▶  199 │ #ifdef CONFIG_SYSTEMTICK_HOOK
   200 │   /* Call out to a user-provided function in order to perform board-specific,
   201 │    * custom timer operations.
   202 │    */
```
> **说明**：board_timerhook() 只在 NuttX 的 CONFIG_SYSTEMTICK_HOOK=y 打开时被内核调用 ┃ （nuttx/sched/sched/sched_processtimer.c:199）。
^src-platforms-nuttx-NuttX-nuttx-sched-sched-sched-processtimer-c-199

### `platforms/nuttx/src/bootloader/common/bl.c`
<a id="src-platforms-nuttx-src-bootloader-common-bl-c-34"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:34`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-c-34)

```c
    31 │  *
    32 │  ****************************************************************************/
    33 │ 
▶   34 │ /**
    35 │  * @file bl.c
    36 │  *
    37 │  * Common bootloader logic.
```
> **说明**：它出现的唯一理由是：①层（bl.c）需要操作 flash / LED / 串口 / 时钟，但它一行芯片相关代码都不许有 ┃ （bl.c:34 的文档注释原文：*"Aside from the header includes below, this file should have no board-specific logic."*）。
^src-platforms-nuttx-src-bootloader-common-bl-c-34

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-48"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:48`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-c-48)

```c
    45 │ #include <stdbool.h>
    46 │ #include <string.h>
    47 │ 
▶   48 │ #include "bl.h"
    49 │ #include "image_toc.h"
    50 │ #include "crypto.h"
    51 │ #include "cdcacm.h"
```
> **说明**：层：① 通用（但内容全是对 ②层的接口要求） ┃ 被谁包含：bl.c:48、main.c:19、bootloader_main.c:41（③层也要它——因为要用 bootloader() 和 boardinfo）
^src-platforms-nuttx-src-bootloader-common-bl-c-48

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-276"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:276`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-c-276)

```c
   273 │ 
   274 │ static const uint32_t bl_proto_rev = BL_PROTOCOL_REVISION; // value returned by PROTO_DEVICE_BL_REV
   275 │ 
▶  276 │ static unsigned head, tail;
   277 │ static uint8_t rx_buf[256] USB_DATA_ALIGN;
   278 │ 
   279 │ static enum led_state {LED_BLINK, LED_ON, LED_OFF} _led_state;
```
> **说明**：bl.h:81 | extern void buf_put(uint8_t b); extern int buf_get(void); | ┃ bl.c:276 | static unsigned head, tail; static uint8_t rx_buf[256] USB_DATA_ALIGN; |
^src-platforms-nuttx-src-bootloader-common-bl-c-276

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-283"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:283`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-c-283)

```c
   280 │ 
   281 │ void sys_tick_handler(void);
   282 │ 
▶  283 │ void
   284 │ buf_put(uint8_t b)
   285 │ {
   286 │ 	unsigned next = (head + 1) % sizeof(rx_buf);
```
> **说明**：bl.c:276 | static unsigned head, tail; static uint8_t rx_buf[256] USB_DATA_ALIGN; | ┃ bl.c:283 / bl.c:294 | 环形缓冲实现 |
^src-platforms-nuttx-src-bootloader-common-bl-c-283

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-294"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:294`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-c-294)

```c
   291 │ 	}
   292 │ }
   293 │ 
▶  294 │ int
   295 │ buf_get(void)
   296 │ {
   297 │ 	int ret = -1;
```
> **说明**：bl.c:276 | static unsigned head, tail; static uint8_t rx_buf[256] USB_DATA_ALIGN; | ┃ bl.c:283 / bl.c:294 | 环形缓冲实现 |
^src-platforms-nuttx-src-bootloader-common-bl-c-294

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-307"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:307`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-c-307)

```c
   304 │ 	return ret;
   305 │ }
   306 │ 
▶  307 │ void
   308 │ jump_to_app()
   309 │ {
   310 │ 	const uint32_t *app_base = (const uint32_t *)APP_LOAD_ADDRESS;
```
> **说明**：bl.h:67 | void bootloader(unsigned timeout) | ①层唯一的对外入口；②层 main.c:802 调用 | ┃ bl.h:66 | void jump_to_app(void) | ①层实现（bl.c:307），②层调用（main.c:771、main.c:824）—— 定义在①、调用在② |
^src-platforms-nuttx-src-bootloader-common-bl-c-307

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-414"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:414`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-c-414)

```c
   411 │ #endif
   412 │ 
   413 │ 	/* just for paranoia's sake */
▶  414 │ 	arch_flash_lock();
   415 │ 
   416 │ 	/* kill the systick interrupt */
   417 │ 	arch_systic_deinit();
```
> **说明**：bl.h:109 | flash_func_read_sn(addr) | main.c:564（读 STM32_SYSMEM_UID） | bl.c:965 | ┃ bl.h:110 | arch_flash_lock/unlock() | main.c:439 / :445 | bl.c:414 / :775 |
^src-platforms-nuttx-src-bootloader-common-bl-c-414

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-417"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:417`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-c-417)

```c
   414 │ 	arch_flash_lock();
   415 │ 
   416 │ 	/* kill the systick interrupt */
▶  417 │ 	arch_systic_deinit();
   418 │ 
   419 │ 	/* deinitialise the interface */
   420 │ 	cfini();
```
> **说明**：bl.h:113 | arch_do_jump(const uint32_t *) | main.c:632 | bl.c:432 | ┃ bl.h:114 | arch_systic_init/deinit() | main.c:365 / :374 | bl.c:632 / bl.c:417 |
^src-platforms-nuttx-src-bootloader-common-bl-c-417

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-423"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:423`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-c-423)

```c
   420 │ 	cfini();
   421 │ 
   422 │ 	/* reset the clock */
▶  423 │ 	clock_deinit();
   424 │ 
   425 │ 	/* deinitialise the board */
   426 │ 	board_deinit();
```
> **说明**：bl.h:102 | board_get_devices(void) | main.c:258 | bl.c:540（决定去哪个通道收字节） | ┃ bl.h:103 | clock_deinit(void) | main.c:406 | bl.c:423（跳转前把 RCC 打回 HSI） |
^src-platforms-nuttx-src-bootloader-common-bl-c-423

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-426"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:426`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-c-426)

```c
   423 │ 	clock_deinit();
   424 │ 
   425 │ 	/* deinitialise the board */
▶  426 │ 	board_deinit();
   427 │ 
   428 │ 	/* switch exception handlers to the application */
   429 │ 	arch_setvtor(vec_base);
```
> **说明**：bl.h:101 | board_deinit(void) | main.c:317 | bl.c:426（跳转前清板级外设） |
^src-platforms-nuttx-src-bootloader-common-bl-c-426

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-429"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:429`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-c-429)

```c
   426 │ 	board_deinit();
   427 │ 
   428 │ 	/* switch exception handlers to the application */
▶  429 │ 	arch_setvtor(vec_base);
   430 │ 
   431 │ 	/* make arch specific jump to app */
   432 │ 	arch_do_jump(app_base);
```
> **说明**：bl.h:110 | arch_flash_lock/unlock() | main.c:439 / :445 | bl.c:414 / :775 | ┃ bl.h:112 | arch_setvtor(const uint32_t *) | main.c:457 | bl.c:429（★ 向量表切换，见 01_extracted/stm32/vtor-vector-tables） |
^src-platforms-nuttx-src-bootloader-common-bl-c-429

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-432"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:432`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-c-432)

```c
   429 │ 	arch_setvtor(vec_base);
   430 │ 
   431 │ 	/* make arch specific jump to app */
▶  432 │ 	arch_do_jump(app_base);
   433 │ }
   434 │ 
   435 │ volatile unsigned timer[NTIMERS];
```
> **说明**：bl.h:112 | arch_setvtor(const uint32_t *) | main.c:457 | bl.c:429（★ 向量表切换，见 01_extracted/stm32/vtor-vector-tables） | ┃ bl.h:113 | arch_do_jump(const uint32_t *) | main.c:632 | bl.c:432 |
^src-platforms-nuttx-src-bootloader-common-bl-c-432

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-435"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:435`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-c-435)

```c
   432 │ 	arch_do_jump(app_base);
   433 │ }
   434 │ 
▶  435 │ volatile unsigned timer[NTIMERS];
   436 │ 
   437 │ void
   438 │ sys_tick_handler(void)
```
> **说明**：bl.h:73 | NTIMERS=4；TIMER_BL_WAIT=0、TIMER_CIN=1、TIMER_LED=2、TIMER_DELAY=3；extern volatile unsigned timer[] | 注释写明："each timer decrements every millisecond if > 0" | ┃ bl.c:435 | 定义处 | — |
^src-platforms-nuttx-src-bootloader-common-bl-c-435

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-437"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:437`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-c-437)

```c
   434 │ 
   435 │ volatile unsigned timer[NTIMERS];
   436 │ 
▶  437 │ void
   438 │ sys_tick_handler(void)
   439 │ {
   440 │ 	unsigned i;
```
> **说明**：bl.c:435 | 定义处 | — | ┃ bl.c:437 | 唯一递减它们的地方 = sys_tick_handler() | ⇒ 这个计数器不是由硬件自动减的，是靠 ②③层把它挂到系统 tick 上 |
^src-platforms-nuttx-src-bootloader-common-bl-c-437

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-447"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:447`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-c-447)

```c
   444 │ 			timer[i]--;
   445 │ 		}
   446 │ 
▶  447 │ 	if ((_led_state == LED_BLINK) && (timer[TIMER_LED] == 0)) {
   448 │ 		led_toggle(LED_BOOTLOADER);
   449 │ 		timer[TIMER_LED] = 50;
   450 │ 	}
```
> **说明**：bl.h:70 BL_WAIT_MAGIC 全仓无使用者（grep 无命中）⇒ 我标"未核实用途"，未编造。 ┃ timer[TIMER_LED] = 50 ⇒ 50 ms 半周期 ⇒ 10 Hz 整周期：这是从 bl.c:447 与 bl.c:478 的代码推理，
^src-platforms-nuttx-src-bootloader-common-bl-c-447

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-453"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:453`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-c-453)

```c
   450 │ 	}
   451 │ }
   452 │ 
▶  453 │ void
   454 │ delay(unsigned msec)
   455 │ {
   456 │ 	timer[TIMER_DELAY] = msec;
```
> **说明**：bl.h:66 | void jump_to_app(void) | ①层实现（bl.c:307），②层调用（main.c:771、main.c:824）—— 定义在①、调用在② | ┃ bl.h:68 | void delay(unsigned msec) | ①层实现（bl.c:453），①层自己用（bl.c:1131） |
^src-platforms-nuttx-src-bootloader-common-bl-c-453

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-478"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:478`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-c-478)

```c
   475 │ 
   476 │ 	case LED_BLINK:
   477 │ 		/* restart the blink state machine ASAP */
▶  478 │ 		timer[TIMER_LED] = 0;
   479 │ 		break;
   480 │ 	}
   481 │ }
```
> **说明**：bl.h:70 BL_WAIT_MAGIC 全仓无使用者（grep 无命中）⇒ 我标"未核实用途"，未编造。 ┃ timer[TIMER_LED] = 50 ⇒ 50 ms 半周期 ⇒ 10 Hz 整周期：这是从 bl.c:447 与 bl.c:478 的代码推理，
^src-platforms-nuttx-src-bootloader-common-bl-c-478

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-540"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:540`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-c-540)

```c
   537 │ 	timer[TIMER_CIN] = timeout;
   538 │ 
   539 │ 	do {
▶  540 │ 		c = cin(board_get_devices());
   541 │ 
   542 │ 		if (c >= 0) {
   543 │ 			cin_count++;
```
> **说明**：bl.h:101 | board_deinit(void) | main.c:317 | bl.c:426（跳转前清板级外设） | ┃ bl.h:102 | board_get_devices(void) | main.c:258 | bl.c:540（决定去哪个通道收字节） |
^src-platforms-nuttx-src-bootloader-common-bl-c-540

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-632"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:632`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-c-632)

```c
   629 │ 	uint32_t  first_word = 0xffffffff;
   630 │ 
   631 │ 	/* (re)start the timer system */
▶  632 │ 	arch_systic_init();
   633 │ 
   634 │ 	/* if we are working with a timeout, start it running */
   635 │ 	if (timeout) {
```
> **说明**：bl.h:113 | arch_do_jump(const uint32_t *) | main.c:632 | bl.c:432 | ┃ bl.h:114 | arch_systic_init/deinit() | main.c:365 / :374 | bl.c:632 / bl.c:417 |
^src-platforms-nuttx-src-bootloader-common-bl-c-632

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-651"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:651`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-c-651)

```c
   648 │ 		} flash_buffer;
   649 │ 
   650 │ 		// Wait for a command byte
▶  651 │ 		led_off(LED_ACTIVITY);
   652 │ 
   653 │ 		do {
   654 │ 			/* if we have a timeout and the timer has expired, return now */
```
> **说明**：bl.h:96 | extern void led_on/led_off/led_toggle(unsigned led); —— ②③层必须实现 | ┃ ①层怎么用 | bl.c:651 / bl.c:664 操作 LED_ACTIVITY（"正在收命令"心跳，无 blink 状态机）；bl.c:462-481 led_set() 操作 LED_BOOTLOADER（三态：LED_BLINK/LED_ON/LED_OFF） |
^src-platforms-nuttx-src-bootloader-common-bl-c-651

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-664"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:664`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-c-664)

```c
   661 │ 
   662 │ 		} while (c < 0);
   663 │ 
▶  664 │ 		led_on(LED_ACTIVITY);
   665 │ 
   666 │ 		bool full_erase = false;
   667 │ 
```
> **说明**：bl.h:96 | extern void led_on/led_off/led_toggle(unsigned led); —— ②③层必须实现 | ┃ ①层怎么用 | bl.c:651 / bl.c:664 操作 LED_ACTIVITY（"正在收命令"心跳，无 blink 状态机）；bl.c:462-481 led_set() 操作 LED_BOOTLOADER（三态：LED_BLINK/LED_ON/LED_OFF） |
^src-platforms-nuttx-src-bootloader-common-bl-c-664

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-727"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:727`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-c-727)

```c
   724 │ 
   725 │ 			case PROTO_DEVICE_VEC_AREA:
   726 │ 				for (unsigned p = 7; p <= 10; p++) {
▶  727 │ 					uint32_t bytes = flash_func_read_word(p * 4);
   728 │ 
   729 │ 					cout((uint8_t *)&bytes, sizeof(bytes));
   730 │ 				}
```
> **说明**：bl.h:106 | flash_func_write_word(addr, word) | main.c:489 | bl.c:873 / bl.c:1074 / bl.c:1119 | ┃ bl.h:107 | flash_func_read_word(addr) | main.c:496 | bl.c:727 / :786 / :876 / :909 / :1076 / :1121 |
^src-platforms-nuttx-src-bootloader-common-bl-c-727

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-777"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:777`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-c-777)

```c
   774 │ 			// erase all sectors
   775 │ 			arch_flash_unlock();
   776 │ 
▶  777 │ 			for (int i = 0; flash_func_sector_size(i) != 0; i++) {
   778 │ 				flash_func_erase_sector(i, full_erase);
   779 │ 			}
   780 │ 
```
> **说明**：bl.h:103 | clock_deinit(void) | main.c:406 | bl.c:423（跳转前把 RCC 打回 HSI） | ┃ bl.h:104 | flash_func_sector_size(unsigned) | main.c:467 | bl.c:777（用返回值 != 0 当循环终止条件） |
> **说明**：LED 闪 / 亮 / 灭 | bl.h:96 三个函数 ← ③层 BOARD_PIN_LED_* 宏（本板悬空 ⇒ 看不到） | ┃ 擦除耗时可感知（几十秒级） | bl.c:777 先擦全片再逐字读回校验，每 4 B 一次 flash_func_read_word |
^src-platforms-nuttx-src-bootloader-common-bl-c-777

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-778"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:778`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-c-778)

```c
   775 │ 			arch_flash_unlock();
   776 │ 
   777 │ 			for (int i = 0; flash_func_sector_size(i) != 0; i++) {
▶  778 │ 				flash_func_erase_sector(i, full_erase);
   779 │ 			}
   780 │ 
   781 │ 			// disable the LED while verifying the erase
```
> **说明**：bl.h:104 | flash_func_sector_size(unsigned) | main.c:467 | bl.c:777（用返回值 != 0 当循环终止条件） | ┃ bl.h:105 | flash_func_erase_sector(unsigned, bool) | main.c:477 | bl.c:778 |
^src-platforms-nuttx-src-bootloader-common-bl-c-778

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-785"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:785`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-c-785)

```c
   782 │ 			led_set(LED_OFF);
   783 │ 
   784 │ 			// verify the erase
▶  785 │ 			for (address = 0; address < board_info.fw_size; address += 4) {
   786 │ 				if (flash_func_read_word(address) != 0xffffffff) {
   787 │ 					goto cmd_fail;
   788 │ 				}
```
> **说明**：bl.h:56 | struct boardinfo { board_type; board_rev; fw_size; systick_mhz } attribute((packed)) | ②层 main.c:98 填初值（board_type = BOARD_TYPE、systick_mhz = CPUCLK/1e6），board_init() 再补 fw_size（main.c:274）  ┃ bl.h:64 | extern struct boardinfo board_info; | ①层读它决定擦多少（bl.c:785 board_info.fw_size、bl.c:902 CRC 范围）、②层读它决定 SysTick 重载（main.c:369） |
^src-platforms-nuttx-src-bootloader-common-bl-c-785

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-840"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:840`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-c-840)

```c
   837 │ 				goto cmd_bad;
   838 │ 			}
   839 │ 
▶  840 │ #if APP_VECTOR_OFFSET == 0
   841 │ 
   842 │ 			if (address == APP_VECTOR_OFFSET) {
   843 │ 
```
> **说明**：bl.h:127 | cinit(void*, uint8_t interface) / cfini / cin(uint32_t devices) / cout(uint8_t*, unsigned) | ①层实现（bl.c:174 / :191 / :200 / :231），内部按 INTERFACE_USB/INTERFACE_USART 编译期裁剪 | ┃ bl.h:132 | APP_VECTOR_OFFSET（默认 0）+ APP_VECTOR_OFFSET_WORDS | ⇒ 本板 = 0（无人重定义），所以走 bl.c:840 那条 #if APP_VECTOR_OFFSET == 0 的分支；②层 fmc.c:60 fc_reset() 也用这个宏 |
^src-platforms-nuttx-src-bootloader-common-bl-c-840

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-873"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:873`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-c-873)

```c
   870 │ 
   871 │ #endif
   872 │ 				// program the word
▶  873 │ 				flash_func_write_word(address, flash_buffer.w[i]);
   874 │ 
   875 │ 				// do immediate read-back verify
   876 │ 				if (flash_func_read_word(address) != flash_buffer.w[i]) {
```
> **说明**：bl.h:105 | flash_func_erase_sector(unsigned, bool) | main.c:477 | bl.c:778 | ┃ bl.h:106 | flash_func_write_word(addr, word) | main.c:489 | bl.c:873 / bl.c:1074 / bl.c:1119 |
^src-platforms-nuttx-src-bootloader-common-bl-c-873

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-902"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:902`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-c-902)

```c
   899 │ 			// compute CRC of the programmed area
   900 │ 			uint32_t sum = 0;
   901 │ 
▶  902 │ 			for (unsigned p = 0; p < board_info.fw_size; p += 4) {
   903 │ 				uint32_t bytes;
   904 │ 
   905 │ 				if ((p == APP_VECTOR_OFFSET) && (first_word != 0xffffffff)) {
```
> **说明**：bl.h:56 | struct boardinfo { board_type; board_rev; fw_size; systick_mhz } attribute((packed)) | ②层 main.c:98 填初值（board_type = BOARD_TYPE、systick_mhz = CPUCLK/1e6），board_init() 再补 fw_size（main.c:274）  ┃ bl.h:64 | extern struct boardinfo board_info; | ①层读它决定擦多少（bl.c:785 board_info.fw_size、bl.c:902 CRC 范围）、②层读它决定 SysTick 重载（main.c:369） |
^src-platforms-nuttx-src-bootloader-common-bl-c-902

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-937"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:937`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-c-937)

```c
   934 │ 					goto cmd_bad;
   935 │ 				}
   936 │ 
▶  937 │ 				cout_word(flash_func_read_otp(index));
   938 │ 			}
   939 │ 			break;
   940 │ 
```
> **说明**：bl.h:107 | flash_func_read_word(addr) | main.c:496 | bl.c:727 / :786 / :876 / :909 / :1076 / :1121 | ┃ bl.h:108 | flash_func_read_otp(addr) | main.c:508（本板恒返回 0） | bl.c:937 |
^src-platforms-nuttx-src-bootloader-common-bl-c-937

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-965"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:965`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-c-965)

```c
   962 │ 					goto cmd_bad;
   963 │ 				}
   964 │ 
▶  965 │ 				cout_word(flash_func_read_sn(index));
   966 │ 			}
   967 │ 
   968 │ 			SET_BL_STATE(STATE_PROTO_GET_SN);
```
> **说明**：bl.h:108 | flash_func_read_otp(addr) | main.c:508（本板恒返回 0） | bl.c:937 | ┃ bl.h:109 | flash_func_read_sn(addr) | main.c:564（读 STM32_SYSMEM_UID） | bl.c:965 |
^src-platforms-nuttx-src-bootloader-common-bl-c-965

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-981"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:981`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-c-981)

```c
   978 │ 					goto cmd_bad;
   979 │ 				}
   980 │ 
▶  981 │ 				cout_word(get_mcu_id());
   982 │ 				SET_BL_STATE(STATE_PROTO_GET_CHIP);
   983 │ 			}
   984 │ 			break;
```
> **说明**：bl.h:114 | arch_systic_init/deinit() | main.c:365 / :374 | bl.c:632 / bl.c:417 | ┃ bl.h:117 | get_mcu_id / get_mcu_desc / check_silicon | main.c:514 / :519 / :559 | bl.c:981 / :999 / :760（check_silicon 在 H7 上恒返回 0，且调用点被 TARGET_HW_PX4_FMU_V4 包住 ⇒ 本板进不去） |
^src-platforms-nuttx-src-bootloader-common-bl-c-981

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-1074"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:1074`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-c-1074)

```c
  1071 │ 			 * half of the BOOT handler below.
  1072 │ 			 */
  1073 │ 			if (first_word != 0xffffffff) {
▶ 1074 │ 				flash_func_write_word(APP_VECTOR_OFFSET, first_word);
  1075 │ 
  1076 │ 				if (flash_func_read_word(APP_VECTOR_OFFSET) != first_word) {
  1077 │ 					goto cmd_fail;
```
> **说明**：bl.h:105 | flash_func_erase_sector(unsigned, bool) | main.c:477 | bl.c:778 | ┃ bl.h:106 | flash_func_write_word(addr, word) | main.c:489 | bl.c:873 / bl.c:1074 / bl.c:1119 |
^src-platforms-nuttx-src-bootloader-common-bl-c-1074

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-1119"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:1119`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-c-1119)

```c
  1116 │ 
  1117 │ 			// program the deferred first word
  1118 │ 			if (first_word != 0xffffffff) {
▶ 1119 │ 				flash_func_write_word(APP_VECTOR_OFFSET, first_word);
  1120 │ 
  1121 │ 				if (flash_func_read_word(APP_VECTOR_OFFSET) != first_word) {
  1122 │ 					goto cmd_fail;
```
> **说明**：bl.h:105 | flash_func_erase_sector(unsigned, bool) | main.c:477 | bl.c:778 | ┃ bl.h:106 | flash_func_write_word(addr, word) | main.c:489 | bl.c:873 / bl.c:1074 / bl.c:1119 |
^src-platforms-nuttx-src-bootloader-common-bl-c-1119

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-1131"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:1131`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-c-1131)

```c
  1128 │ 
  1129 │ 			// send a sync and wait for it to be collected
  1130 │ 			sync_response();
▶ 1131 │ 			delay(100);
  1132 │ 
  1133 │ 			// quiesce and jump to the app
  1134 │ 			return;
```
> **说明**：bl.h:66 | void jump_to_app(void) | ①层实现（bl.c:307），②层调用（main.c:771、main.c:824）—— 定义在①、调用在② | ┃ bl.h:68 | void delay(unsigned msec) | ①层实现（bl.c:453），①层自己用（bl.c:1131） |
^src-platforms-nuttx-src-bootloader-common-bl-c-1131

### `platforms/nuttx/src/bootloader/common/bl.h`
<a id="src-platforms-nuttx-src-bootloader-common-bl-h-56"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.h:56`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-h-56)

```c
    53 │ };
    54 │ 
    55 │ /* board info forwarded from board-specific code to booloader */
▶   56 │ struct boardinfo {
    57 │ 	uint32_t  board_type;
    58 │ 	uint32_t  board_rev;
    59 │ 	uint32_t  fw_size;
```
> **说明**：bl.h:56 | struct boardinfo { board_type; board_rev; fw_size; systick_mhz } attribute((packed)) | ②层 main.c:98 填初值（board_type = BOARD_TYPE、systick_mhz = CPUCLK/1e6），board_init() 再补 fw_size（main.c:274） 
^src-platforms-nuttx-src-bootloader-common-bl-h-56

<a id="src-platforms-nuttx-src-bootloader-common-bl-h-64"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.h:64`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-h-64)

```c
    61 │ 
    62 │ } __attribute__((packed));
    63 │ 
▶   64 │ extern struct boardinfo board_info;
    65 │ 
    66 │ extern void jump_to_app(void);
    67 │ extern void bootloader(unsigned timeout);
```
> **说明**：bl.h:56 | struct boardinfo { board_type; board_rev; fw_size; systick_mhz } attribute((packed)) | ②层 main.c:98 填初值（board_type = BOARD_TYPE、systick_mhz = CPUCLK/1e6），board_init() 再补 fw_size（main.c:274）  ┃ bl.h:64 | extern struct boardinfo board_info; | ①层读它决定擦多少（bl.c:785 board_info.fw_size、bl.c:902 CRC 范围）、②层读它决定 SysTick 重载（main.c:369） |
^src-platforms-nuttx-src-bootloader-common-bl-h-64

<a id="src-platforms-nuttx-src-bootloader-common-bl-h-66"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.h:66`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-h-66)

```c
    63 │ 
    64 │ extern struct boardinfo board_info;
    65 │ 
▶   66 │ extern void jump_to_app(void);
    67 │ extern void bootloader(unsigned timeout);
    68 │ extern void delay(unsigned msec);
    69 │ 
```
> **说明**：bl.h:67 | void bootloader(unsigned timeout) | ①层唯一的对外入口；②层 main.c:802 调用 | ┃ bl.h:66 | void jump_to_app(void) | ①层实现（bl.c:307），②层调用（main.c:771、main.c:824）—— 定义在①、调用在② |
^src-platforms-nuttx-src-bootloader-common-bl-h-66

<a id="src-platforms-nuttx-src-bootloader-common-bl-h-67"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.h:67`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-h-67)

```c
    64 │ extern struct boardinfo board_info;
    65 │ 
    66 │ extern void jump_to_app(void);
▶   67 │ extern void bootloader(unsigned timeout);
    68 │ extern void delay(unsigned msec);
    69 │ 
    70 │ #define BL_WAIT_MAGIC 0x19710317    /* magic number in PWR regs to wait in bootloader */
```
> **说明**：bl.h:64 | extern struct boardinfo board_info; | ①层读它决定擦多少（bl.c:785 board_info.fw_size、bl.c:902 CRC 范围）、②层读它决定 SysTick 重载（main.c:369） | ┃ bl.h:67 | void bootloader(unsigned timeout) | ①层唯一的对外入口；②层 main.c:802 调用 |
^src-platforms-nuttx-src-bootloader-common-bl-h-67

<a id="src-platforms-nuttx-src-bootloader-common-bl-h-68"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.h:68`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-h-68)

```c
    65 │ 
    66 │ extern void jump_to_app(void);
    67 │ extern void bootloader(unsigned timeout);
▶   68 │ extern void delay(unsigned msec);
    69 │ 
    70 │ #define BL_WAIT_MAGIC 0x19710317    /* magic number in PWR regs to wait in bootloader */
    71 │ 
```
> **说明**：bl.h:66 | void jump_to_app(void) | ①层实现（bl.c:307），②层调用（main.c:771、main.c:824）—— 定义在①、调用在② | ┃ bl.h:68 | void delay(unsigned msec) | ①层实现（bl.c:453），①层自己用（bl.c:1131） |
^src-platforms-nuttx-src-bootloader-common-bl-h-68

<a id="src-platforms-nuttx-src-bootloader-common-bl-h-70"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.h:70`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-h-70)

```c
    67 │ extern void bootloader(unsigned timeout);
    68 │ extern void delay(unsigned msec);
    69 │ 
▶   70 │ #define BL_WAIT_MAGIC 0x19710317    /* magic number in PWR regs to wait in bootloader */
    71 │ 
    72 │ /* generic timers */
    73 │ #define NTIMERS   4
```
> **说明**：★ bl.h:70 的 BL_WAIT_MAGIC 0x19710317（"magic number in PWR regs to wait in bootloader"）在本仓
^src-platforms-nuttx-src-bootloader-common-bl-h-70

<a id="src-platforms-nuttx-src-bootloader-common-bl-h-73"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.h:73`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-h-73)

```c
    70 │ #define BL_WAIT_MAGIC 0x19710317    /* magic number in PWR regs to wait in bootloader */
    71 │ 
    72 │ /* generic timers */
▶   73 │ #define NTIMERS   4
    74 │ #define TIMER_BL_WAIT 0
    75 │ #define TIMER_CIN 1
    76 │ #define TIMER_LED 2
```
> **说明**：bl.h:73 | NTIMERS=4；TIMER_BL_WAIT=0、TIMER_CIN=1、TIMER_LED=2、TIMER_DELAY=3；extern volatile unsigned timer[] | 注释写明："each timer decrements every millisecond if > 0" |
^src-platforms-nuttx-src-bootloader-common-bl-h-73

<a id="src-platforms-nuttx-src-bootloader-common-bl-h-81"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.h:81`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-h-81)

```c
    78 │ extern volatile unsigned timer[NTIMERS];  /* each timer decrements every millisecond if > 0 */
    79 │ 
    80 │ /* generic receive buffer for async reads */
▶   81 │ extern void buf_put(uint8_t b);
    82 │ extern int buf_get(void);
    83 │ 
    84 │ /*****************************************************************************
```
> **说明**：bl.h:81 | extern void buf_put(uint8_t b); extern int buf_get(void); |
^src-platforms-nuttx-src-bootloader-common-bl-h-81

<a id="src-platforms-nuttx-src-bootloader-common-bl-h-89"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.h:89`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-h-89)

```c
    86 │  */
    87 │ 
    88 │ /* LEDs */
▶   89 │ #define LED_ACTIVITY  1
    90 │ #define LED_BOOTLOADER  2
    91 │ 
    92 │ #define MAX_DES_LENGTH 20
```
> **说明**：bl.h:89 | LED_ACTIVITY 1 / LED_BOOTLOADER 2 |
^src-platforms-nuttx-src-bootloader-common-bl-h-89

<a id="src-platforms-nuttx-src-bootloader-common-bl-h-96"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.h:96`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-h-96)

```c
    93 │ #define MAX_VERSION_LENGTH 32
    94 │ 
    95 │ #define arraySize(a) (sizeof((a))/sizeof(((a)[0])))
▶   96 │ extern void led_on(unsigned led);
    97 │ extern void led_off(unsigned led);
    98 │ extern void led_toggle(unsigned led);
    99 │ 
```
> **说明**：bl.h:89 | LED_ACTIVITY 1 / LED_BOOTLOADER 2 | ┃ bl.h:96 | extern void led_on/led_off/led_toggle(unsigned led); —— ②③层必须实现 |
> **说明**：上位机 GET_DEVICE 报回的 FW_SIZE = 1920 K（本板推导值，未上板核实） | bl.h:59 fw_size ← ②层 main.c:86 的 APP_SIZE_MAX | ┃ LED 闪 / 亮 / 灭 | bl.h:96 三个函数 ← ③层 BOARD_PIN_LED_* 宏（本板悬空 ⇒ 看不到） |
^src-platforms-nuttx-src-bootloader-common-bl-h-96

<a id="src-platforms-nuttx-src-bootloader-common-bl-h-101"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.h:101`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-h-101)

```c
    98 │ extern void led_toggle(unsigned led);
    99 │ 
   100 │ /* flash helpers from main_*.c */
▶  101 │ extern void board_deinit(void);
   102 │ extern uint32_t board_get_devices(void);
   103 │ extern void clock_deinit(void);
   104 │ extern uint32_t flash_func_sector_size(unsigned sector);
```
> **说明**：bl.h:101 | board_deinit(void) | main.c:317 | bl.c:426（跳转前清板级外设） |
^src-platforms-nuttx-src-bootloader-common-bl-h-101

<a id="src-platforms-nuttx-src-bootloader-common-bl-h-102"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.h:102`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-h-102)

```c
    99 │ 
   100 │ /* flash helpers from main_*.c */
   101 │ extern void board_deinit(void);
▶  102 │ extern uint32_t board_get_devices(void);
   103 │ extern void clock_deinit(void);
   104 │ extern uint32_t flash_func_sector_size(unsigned sector);
   105 │ extern void flash_func_erase_sector(unsigned sector, bool force);
```
> **说明**：bl.h:101 | board_deinit(void) | main.c:317 | bl.c:426（跳转前清板级外设） | ┃ bl.h:102 | board_get_devices(void) | main.c:258 | bl.c:540（决定去哪个通道收字节） |
^src-platforms-nuttx-src-bootloader-common-bl-h-102

<a id="src-platforms-nuttx-src-bootloader-common-bl-h-103"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.h:103`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-h-103)

```c
   100 │ /* flash helpers from main_*.c */
   101 │ extern void board_deinit(void);
   102 │ extern uint32_t board_get_devices(void);
▶  103 │ extern void clock_deinit(void);
   104 │ extern uint32_t flash_func_sector_size(unsigned sector);
   105 │ extern void flash_func_erase_sector(unsigned sector, bool force);
   106 │ extern void flash_func_write_word(uintptr_t address, uint32_t word);
```
> **说明**：bl.h:102 | board_get_devices(void) | main.c:258 | bl.c:540（决定去哪个通道收字节） | ┃ bl.h:103 | clock_deinit(void) | main.c:406 | bl.c:423（跳转前把 RCC 打回 HSI） |
^src-platforms-nuttx-src-bootloader-common-bl-h-103

<a id="src-platforms-nuttx-src-bootloader-common-bl-h-104"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.h:104`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-h-104)

```c
   101 │ extern void board_deinit(void);
   102 │ extern uint32_t board_get_devices(void);
   103 │ extern void clock_deinit(void);
▶  104 │ extern uint32_t flash_func_sector_size(unsigned sector);
   105 │ extern void flash_func_erase_sector(unsigned sector, bool force);
   106 │ extern void flash_func_write_word(uintptr_t address, uint32_t word);
   107 │ extern uint32_t flash_func_read_word(uintptr_t address);
```
> **说明**：bl.h:103 | clock_deinit(void) | main.c:406 | bl.c:423（跳转前把 RCC 打回 HSI） | ┃ bl.h:104 | flash_func_sector_size(unsigned) | main.c:467 | bl.c:777（用返回值 != 0 当循环终止条件） |
^src-platforms-nuttx-src-bootloader-common-bl-h-104

<a id="src-platforms-nuttx-src-bootloader-common-bl-h-105"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.h:105`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-h-105)

```c
   102 │ extern uint32_t board_get_devices(void);
   103 │ extern void clock_deinit(void);
   104 │ extern uint32_t flash_func_sector_size(unsigned sector);
▶  105 │ extern void flash_func_erase_sector(unsigned sector, bool force);
   106 │ extern void flash_func_write_word(uintptr_t address, uint32_t word);
   107 │ extern uint32_t flash_func_read_word(uintptr_t address);
   108 │ extern uint32_t flash_func_read_otp(uintptr_t address);
```
> **说明**：bl.h:104 | flash_func_sector_size(unsigned) | main.c:467 | bl.c:777（用返回值 != 0 当循环终止条件） | ┃ bl.h:105 | flash_func_erase_sector(unsigned, bool) | main.c:477 | bl.c:778 |
^src-platforms-nuttx-src-bootloader-common-bl-h-105

<a id="src-platforms-nuttx-src-bootloader-common-bl-h-106"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.h:106`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-h-106)

```c
   103 │ extern void clock_deinit(void);
   104 │ extern uint32_t flash_func_sector_size(unsigned sector);
   105 │ extern void flash_func_erase_sector(unsigned sector, bool force);
▶  106 │ extern void flash_func_write_word(uintptr_t address, uint32_t word);
   107 │ extern uint32_t flash_func_read_word(uintptr_t address);
   108 │ extern uint32_t flash_func_read_otp(uintptr_t address);
   109 │ extern uint32_t flash_func_read_sn(uintptr_t address);
```
> **说明**：bl.h:105 | flash_func_erase_sector(unsigned, bool) | main.c:477 | bl.c:778 | ┃ bl.h:106 | flash_func_write_word(addr, word) | main.c:489 | bl.c:873 / bl.c:1074 / bl.c:1119 |
^src-platforms-nuttx-src-bootloader-common-bl-h-106

<a id="src-platforms-nuttx-src-bootloader-common-bl-h-107"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.h:107`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-h-107)

```c
   104 │ extern uint32_t flash_func_sector_size(unsigned sector);
   105 │ extern void flash_func_erase_sector(unsigned sector, bool force);
   106 │ extern void flash_func_write_word(uintptr_t address, uint32_t word);
▶  107 │ extern uint32_t flash_func_read_word(uintptr_t address);
   108 │ extern uint32_t flash_func_read_otp(uintptr_t address);
   109 │ extern uint32_t flash_func_read_sn(uintptr_t address);
   110 │ extern void arch_flash_lock(void);
```
> **说明**：bl.h:106 | flash_func_write_word(addr, word) | main.c:489 | bl.c:873 / bl.c:1074 / bl.c:1119 | ┃ bl.h:107 | flash_func_read_word(addr) | main.c:496 | bl.c:727 / :786 / :876 / :909 / :1076 / :1121 |
^src-platforms-nuttx-src-bootloader-common-bl-h-107

<a id="src-platforms-nuttx-src-bootloader-common-bl-h-108"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.h:108`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-h-108)

```c
   105 │ extern void flash_func_erase_sector(unsigned sector, bool force);
   106 │ extern void flash_func_write_word(uintptr_t address, uint32_t word);
   107 │ extern uint32_t flash_func_read_word(uintptr_t address);
▶  108 │ extern uint32_t flash_func_read_otp(uintptr_t address);
   109 │ extern uint32_t flash_func_read_sn(uintptr_t address);
   110 │ extern void arch_flash_lock(void);
   111 │ extern void arch_flash_unlock(void);
```
> **说明**：bl.h:107 | flash_func_read_word(addr) | main.c:496 | bl.c:727 / :786 / :876 / :909 / :1076 / :1121 | ┃ bl.h:108 | flash_func_read_otp(addr) | main.c:508（本板恒返回 0） | bl.c:937 |
^src-platforms-nuttx-src-bootloader-common-bl-h-108

<a id="src-platforms-nuttx-src-bootloader-common-bl-h-109"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.h:109`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-h-109)

```c
   106 │ extern void flash_func_write_word(uintptr_t address, uint32_t word);
   107 │ extern uint32_t flash_func_read_word(uintptr_t address);
   108 │ extern uint32_t flash_func_read_otp(uintptr_t address);
▶  109 │ extern uint32_t flash_func_read_sn(uintptr_t address);
   110 │ extern void arch_flash_lock(void);
   111 │ extern void arch_flash_unlock(void);
   112 │ extern void arch_setvtor(const uint32_t *address);
```
> **说明**：bl.h:108 | flash_func_read_otp(addr) | main.c:508（本板恒返回 0） | bl.c:937 | ┃ bl.h:109 | flash_func_read_sn(addr) | main.c:564（读 STM32_SYSMEM_UID） | bl.c:965 |
^src-platforms-nuttx-src-bootloader-common-bl-h-109

<a id="src-platforms-nuttx-src-bootloader-common-bl-h-110"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.h:110`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-h-110)

```c
   107 │ extern uint32_t flash_func_read_word(uintptr_t address);
   108 │ extern uint32_t flash_func_read_otp(uintptr_t address);
   109 │ extern uint32_t flash_func_read_sn(uintptr_t address);
▶  110 │ extern void arch_flash_lock(void);
   111 │ extern void arch_flash_unlock(void);
   112 │ extern void arch_setvtor(const uint32_t *address);
   113 │ extern void arch_do_jump(const uint32_t *app_base);
```
> **说明**：bl.h:109 | flash_func_read_sn(addr) | main.c:564（读 STM32_SYSMEM_UID） | bl.c:965 | ┃ bl.h:110 | arch_flash_lock/unlock() | main.c:439 / :445 | bl.c:414 / :775 |
^src-platforms-nuttx-src-bootloader-common-bl-h-110

<a id="src-platforms-nuttx-src-bootloader-common-bl-h-112"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.h:112`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-h-112)

```c
   109 │ extern uint32_t flash_func_read_sn(uintptr_t address);
   110 │ extern void arch_flash_lock(void);
   111 │ extern void arch_flash_unlock(void);
▶  112 │ extern void arch_setvtor(const uint32_t *address);
   113 │ extern void arch_do_jump(const uint32_t *app_base);
   114 │ void arch_systic_init(void);
   115 │ void arch_systic_deinit(void);
```
> **说明**：bl.h:110 | arch_flash_lock/unlock() | main.c:439 / :445 | bl.c:414 / :775 | ┃ bl.h:112 | arch_setvtor(const uint32_t *) | main.c:457 | bl.c:429（★ 向量表切换，见 01_extracted/stm32/vtor-vector-tables） |
^src-platforms-nuttx-src-bootloader-common-bl-h-112

<a id="src-platforms-nuttx-src-bootloader-common-bl-h-113"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.h:113`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-h-113)

```c
   110 │ extern void arch_flash_lock(void);
   111 │ extern void arch_flash_unlock(void);
   112 │ extern void arch_setvtor(const uint32_t *address);
▶  113 │ extern void arch_do_jump(const uint32_t *app_base);
   114 │ void arch_systic_init(void);
   115 │ void arch_systic_deinit(void);
   116 │ 
```
> **说明**：bl.h:112 | arch_setvtor(const uint32_t *) | main.c:457 | bl.c:429（★ 向量表切换，见 01_extracted/stm32/vtor-vector-tables） | ┃ bl.h:113 | arch_do_jump(const uint32_t *) | main.c:632 | bl.c:432 |
^src-platforms-nuttx-src-bootloader-common-bl-h-113

<a id="src-platforms-nuttx-src-bootloader-common-bl-h-114"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.h:114`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-h-114)

```c
   111 │ extern void arch_flash_unlock(void);
   112 │ extern void arch_setvtor(const uint32_t *address);
   113 │ extern void arch_do_jump(const uint32_t *app_base);
▶  114 │ void arch_systic_init(void);
   115 │ void arch_systic_deinit(void);
   116 │ 
   117 │ extern uint32_t get_mcu_id(void);
```
> **说明**：bl.h:113 | arch_do_jump(const uint32_t *) | main.c:632 | bl.c:432 | ┃ bl.h:114 | arch_systic_init/deinit() | main.c:365 / :374 | bl.c:632 / bl.c:417 |
^src-platforms-nuttx-src-bootloader-common-bl-h-114

<a id="src-platforms-nuttx-src-bootloader-common-bl-h-117"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.h:117`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-h-117)

```c
   114 │ void arch_systic_init(void);
   115 │ void arch_systic_deinit(void);
   116 │ 
▶  117 │ extern uint32_t get_mcu_id(void);
   118 │ int get_mcu_desc(int max, uint8_t *revstr);
   119 │ extern int check_silicon(void);
   120 │ 
```
> **说明**：bl.h:114 | arch_systic_init/deinit() | main.c:365 / :374 | bl.c:632 / bl.c:417 | ┃ bl.h:117 | get_mcu_id / get_mcu_desc / check_silicon | main.c:514 / :519 / :559 | bl.c:981 / :999 / :760（check_silicon 在 H7 上恒返回 0，且调用点被 TARGET_HW_PX4_FMU_V4 包住 ⇒ 本板进不去） |
^src-platforms-nuttx-src-bootloader-common-bl-h-117

<a id="src-platforms-nuttx-src-bootloader-common-bl-h-127"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.h:127`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-h-127)

```c
   124 │  * Interface in/output.
   125 │  */
   126 │ 
▶  127 │ extern void cinit(void *config, uint8_t interface);
   128 │ extern void cfini(void);
   129 │ extern int cin(uint32_t devices);
   130 │ extern void cout(uint8_t *buf, unsigned len);
```
> **说明**：bl.h:127 | cinit(void*, uint8_t interface) / cfini / cin(uint32_t devices) / cout(uint8_t*, unsigned) | ①层实现（bl.c:174 / :191 / :200 / :231），内部按 INTERFACE_USB/INTERFACE_USART 编译期裁剪 |
^src-platforms-nuttx-src-bootloader-common-bl-h-127

<a id="src-platforms-nuttx-src-bootloader-common-bl-h-132"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.h:132`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-h-132)

```c
   129 │ extern int cin(uint32_t devices);
   130 │ extern void cout(uint8_t *buf, unsigned len);
   131 │ 
▶  132 │ #if !defined(APP_VECTOR_OFFSET)
   133 │ #  define APP_VECTOR_OFFSET 0
   134 │ #endif
   135 │ #define APP_VECTOR_OFFSET_WORDS (APP_VECTOR_OFFSET/sizeof(uint32_t))
```
> **说明**：bl.h:127 | cinit(void*, uint8_t interface) / cfini / cin(uint32_t devices) / cout(uint8_t*, unsigned) | ①层实现（bl.c:174 / :191 / :200 / :231），内部按 INTERFACE_USB/INTERFACE_USART 编译期裁剪 | ┃ bl.h:132 | APP_VECTOR_OFFSET（默认 0）+ APP_VECTOR_OFFSET_WORDS | ⇒ 本板 = 0（无人重定义），所以走 bl.c:840 那条 #if APP_VECTOR_OFFSET == 0 的分支；②层 fmc.c:60 fc_reset() 也用这个宏 |
^src-platforms-nuttx-src-bootloader-common-bl-h-132

### `platforms/nuttx/src/bootloader/stm/stm32_common/main.c`
<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-19"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:19`](bl-h.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-19)

```c
    16 │ #include <lib/systick.h>
    17 │ #include <lib/flash_cache.h>
    18 │ 
▶   19 │ #include "bl.h"
    20 │ #include "uart.h"
    21 │ 
    22 │ #if defined(CONFIG_ARCH_CHIP_STM32H7)
```
> **说明**：层：① 通用（但内容全是对 ②层的接口要求） ┃ 被谁包含：bl.c:48、main.c:19、bootloader_main.c:41（③层也要它——因为要用 bootloader() 和 boardinfo）
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-19

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-86"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:86`](bl-h.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-86)

```c
    83 │ # error "APP_RESERVATION_SIZE must be greater than 0 if FLASH_BASED_PARAMS is defined"
    84 │ #endif
    85 │ 
▶   86 │ #define APP_SIZE_MAX			(BOARD_FLASH_SIZE - (BOOTLOADER_RESERVATION_SIZE + APP_RESERVATION_SIZE))
    87 │ 
    88 │ 
    89 │ /* context passed to cinit */
```
> **说明**：上位机 GET_DEVICE 报回的 board_id = 2027 | bl.h:57 board_type ← ②层 main.c:99 ← ③层 hw_config.h:102 | ┃ 上位机 GET_DEVICE 报回的 FW_SIZE = 1920 K（本板推导值，未上板核实） | bl.h:59 fw_size ← ②层 main.c:86 的 APP_SIZE_MAX |
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-86

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-98"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:98`](bl-h.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-98)

```c
    95 │ #endif
    96 │ 
    97 │ /* board definition */
▶   98 │ struct boardinfo board_info = {
    99 │ 	.board_type	= BOARD_TYPE,
   100 │ 	.board_rev	= 0,
   101 │ 	.fw_size	= 0,
```
> **说明**：bl.h:56 | struct boardinfo { board_type; board_rev; fw_size; systick_mhz } attribute((packed)) | ②层 main.c:98 填初值（board_type = BOARD_TYPE、systick_mhz = CPUCLK/1e6），board_init() 再补 fw_size（main.c:274） 
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-98

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-99"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:99`](bl-h.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-99)

```c
    96 │ 
    97 │ /* board definition */
    98 │ struct boardinfo board_info = {
▶   99 │ 	.board_type	= BOARD_TYPE,
   100 │ 	.board_rev	= 0,
   101 │ 	.fw_size	= 0,
   102 │ 	.systick_mhz	= STM32_CPUCLK_FREQUENCY / 1000000,
```
> **说明**：上位机 GET_DEVICE 报回的 board_id = 2027 | bl.h:57 board_type ← ②层 main.c:99 ← ③层 hw_config.h:102 |
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-99

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-258"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:258`](bl-h.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-258)

```c
   255 │ }
   256 │ #endif
   257 │ 
▶  258 │ uint32_t
   259 │ board_get_devices(void)
   260 │ {
   261 │ 	uint32_t devices = BOOT_DEVICES_SELECTION;
```
> **说明**：bl.h:101 | board_deinit(void) | main.c:317 | bl.c:426（跳转前清板级外设） | ┃ bl.h:102 | board_get_devices(void) | main.c:258 | bl.c:540（决定去哪个通道收字节） |
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-258

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-274"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:274`](bl-h.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-274)

```c
   271 │ board_init(void)
   272 │ {
   273 │ 	/* fix up the max firmware size, we have to read memory to get this */
▶  274 │ 	board_info.fw_size = APP_SIZE_MAX;
   275 │ 
   276 │ #if defined(BOARD_POWER_PIN_OUT)
   277 │ 	/* Configure the Power pins */
```
> **说明**：bl.h:56 | struct boardinfo { board_type; board_rev; fw_size; systick_mhz } attribute((packed)) | ②层 main.c:98 填初值（board_type = BOARD_TYPE、systick_mhz = CPUCLK/1e6），board_init() 再补 fw_size（main.c:274） 
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-274

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-317"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:317`](bl-h.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-317)

```c
   314 │ #endif
   315 │ }
   316 │ 
▶  317 │ void
   318 │ board_deinit(void)
   319 │ {
   320 │ 
```
> **说明**：bl.h:101 | board_deinit(void) | main.c:317 | bl.c:426（跳转前清板级外设） |
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-317

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-365"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:365`](bl-h.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-365)

```c
   362 │ 	putreg32(0, STM32_RCC_AHB1ENR);
   363 │ }
   364 │ 
▶  365 │ inline void arch_systic_init(void)
   366 │ {
   367 │ 	/* (re)start the timer system */
   368 │ 	systick_set_clocksource(CLKSOURCE_PROCESOR);
```
> **说明**：bl.h:113 | arch_do_jump(const uint32_t *) | main.c:632 | bl.c:432 | ┃ bl.h:114 | arch_systic_init/deinit() | main.c:365 / :374 | bl.c:632 / bl.c:417 |
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-365

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-369"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:369`](bl-h.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-369)

```c
   366 │ {
   367 │ 	/* (re)start the timer system */
   368 │ 	systick_set_clocksource(CLKSOURCE_PROCESOR);
▶  369 │ 	systick_set_reload(board_info.systick_mhz * 1000);  /* 1ms tick, magic number */
   370 │ 	systick_interrupt_enable();
   371 │ 	systick_counter_enable();
   372 │ }
```
> **说明**：bl.h:56 | struct boardinfo { board_type; board_rev; fw_size; systick_mhz } attribute((packed)) | ②层 main.c:98 填初值（board_type = BOARD_TYPE、systick_mhz = CPUCLK/1e6），board_init() 再补 fw_size（main.c:274）  ┃ bl.h:64 | extern struct boardinfo board_info; | ①层读它决定擦多少（bl.c:785 board_info.fw_size、bl.c:902 CRC 范围）、②层读它决定 SysTick 重载（main.c:369） |
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-369

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-406"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:406`](bl-h.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-406)

```c
   403 │   *            - Peripheral clocks
   404 │   *            - LSI, LSE and RTC clocks
   405 │   */
▶  406 │ void
   407 │ clock_deinit(void)
   408 │ {
   409 │ 	uint32_t regval;
```
> **说明**：bl.h:102 | board_get_devices(void) | main.c:258 | bl.c:540（决定去哪个通道收字节） | ┃ bl.h:103 | clock_deinit(void) | main.c:406 | bl.c:423（跳转前把 RCC 打回 HSI） |
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-406

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-439"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:439`](bl-h.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-439)

```c
   436 │ 
   437 │ }
   438 │ 
▶  439 │ void arch_flash_lock(void)
   440 │ {
   441 │ 	stm32h7_flash_lock(STM32_FLASH_BANK1);
   442 │ 	stm32h7_flash_lock(STM32_FLASH_BANK2);
```
> **说明**：bl.h:109 | flash_func_read_sn(addr) | main.c:564（读 STM32_SYSMEM_UID） | bl.c:965 | ┃ bl.h:110 | arch_flash_lock/unlock() | main.c:439 / :445 | bl.c:414 / :775 |
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-439

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-457"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:457`](bl-h.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-457)

```c
   454 │ 	return up_progmem_write(address, buffer, buflen);
   455 │ }
   456 │ 
▶  457 │ inline void arch_setvtor(const uint32_t *address)
   458 │ {
   459 │ 	putreg32((uint32_t)address, NVIC_VECTAB);
   460 │ }
```
> **说明**：bl.h:110 | arch_flash_lock/unlock() | main.c:439 / :445 | bl.c:414 / :775 | ┃ bl.h:112 | arch_setvtor(const uint32_t *) | main.c:457 | bl.c:429（★ 向量表切换，见 01_extracted/stm32/vtor-vector-tables） |
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-457

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-467"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:467`](bl-h.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-467)

```c
   464 │ #define FLASH_SECTOR_SIZE   (128u * 1024u)
   465 │ #endif
   466 │ 
▶  467 │ uint32_t
   468 │ flash_func_sector_size(unsigned sector)
   469 │ {
   470 │ 	if (sector <= BOARD_FLASH_SECTORS) {
```
> **说明**：bl.h:103 | clock_deinit(void) | main.c:406 | bl.c:423（跳转前把 RCC 打回 HSI） | ┃ bl.h:104 | flash_func_sector_size(unsigned) | main.c:467 | bl.c:777（用返回值 != 0 当循环终止条件） |
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-467

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-477"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:477`](bl-h.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-477)

```c
   474 │ 	return 0;
   475 │ }
   476 │ 
▶  477 │ void
   478 │ flash_func_erase_sector(unsigned sector, bool force)
   479 │ {
   480 │ 	if (sector > BOARD_FLASH_SECTORS || (int)sector < BOARD_FIRST_FLASH_SECTOR_TO_ERASE) {
```
> **说明**：bl.h:104 | flash_func_sector_size(unsigned) | main.c:467 | bl.c:777（用返回值 != 0 当循环终止条件） | ┃ bl.h:105 | flash_func_erase_sector(unsigned, bool) | main.c:477 | bl.c:778 |
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-477

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-489"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:489`](bl-h.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-489)

```c
   486 │ 	}
   487 │ }
   488 │ 
▶  489 │ void
   490 │ flash_func_write_word(uintptr_t address, uint32_t word)
   491 │ {
   492 │ 	address += APP_LOAD_ADDRESS;
```
> **说明**：bl.h:105 | flash_func_erase_sector(unsigned, bool) | main.c:477 | bl.c:778 | ┃ bl.h:106 | flash_func_write_word(addr, word) | main.c:489 | bl.c:873 / bl.c:1074 / bl.c:1119 |
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-489

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-496"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:496`](bl-h.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-496)

```c
   493 │ 	fc_write(address, word);
   494 │ }
   495 │ 
▶  496 │ uint32_t flash_func_read_word(uintptr_t address)
   497 │ {
   498 │ 
   499 │ 	if (address & 3) {
```
> **说明**：bl.h:106 | flash_func_write_word(addr, word) | main.c:489 | bl.c:873 / bl.c:1074 / bl.c:1119 | ┃ bl.h:107 | flash_func_read_word(addr) | main.c:496 | bl.c:727 / :786 / :876 / :909 / :1076 / :1121 |
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-496

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-508"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:508`](bl-h.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-508)

```c
   505 │ }
   506 │ 
   507 │ 
▶  508 │ uint32_t
   509 │ flash_func_read_otp(uintptr_t address)
   510 │ {
   511 │ 	return 0;
```
> **说明**：bl.h:107 | flash_func_read_word(addr) | main.c:496 | bl.c:727 / :786 / :876 / :909 / :1076 / :1121 | ┃ bl.h:108 | flash_func_read_otp(addr) | main.c:508（本板恒返回 0） | bl.c:937 |
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-508

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-514"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:514`](bl-h.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-514)

```c
   511 │ 	return 0;
   512 │ }
   513 │ 
▶  514 │ uint32_t get_mcu_id(void)
   515 │ {
   516 │ 	return *(uint32_t *)STM32_DEBUGMCU_BASE;
   517 │ }
```
> **说明**：bl.h:114 | arch_systic_init/deinit() | main.c:365 / :374 | bl.c:632 / bl.c:417 | ┃ bl.h:117 | get_mcu_id / get_mcu_desc / check_silicon | main.c:514 / :519 / :559 | bl.c:981 / :999 / :760（check_silicon 在 H7 上恒返回 0，且调用点被 TARGET_HW_PX4_FMU_V4 包住 ⇒ 本板进不去） |
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-514

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-564"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:564`](bl-h.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-564)

```c
   561 │ 	return 0;
   562 │ }
   563 │ 
▶  564 │ uint32_t
   565 │ flash_func_read_sn(uintptr_t address)
   566 │ {
   567 │ 	// read a byte out from unique chip ID area
```
> **说明**：bl.h:108 | flash_func_read_otp(addr) | main.c:508（本板恒返回 0） | bl.c:937 | ┃ bl.h:109 | flash_func_read_sn(addr) | main.c:564（读 STM32_SYSMEM_UID） | bl.c:965 |
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-564

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-572"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:572`](bl-h.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-572)

```c
   569 │ 	return *(uint32_t *)(address + STM32_SYSMEM_UID);
   570 │ }
   571 │ 
▶  572 │ void
   573 │ led_on(unsigned led)
   574 │ {
   575 │ 	switch (led) {
```
> **说明**：①层怎么用 | bl.c:651 / bl.c:664 操作 LED_ACTIVITY（"正在收命令"心跳，无 blink 状态机）；bl.c:462-481 led_set() 操作 LED_BOOTLOADER（三态：LED_BLINK/LED_ON/LED_OFF） | ┃ ②层实现 | main.c:572（三个函数各一个 switch，空的 —— 因为要等 ③层的 BOARD_PIN_LED_* 宏） |
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-572

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-632"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:632`](bl-h.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-632)

```c
   629 │ #endif
   630 │ 
   631 │ /* Make the actual jump to app */
▶  632 │ void
   633 │ arch_do_jump(const uint32_t *app_base)
   634 │ {
   635 │ 	/* extract the stack and entrypoint from the app vector table and go */
```
> **说明**：bl.h:112 | arch_setvtor(const uint32_t *) | main.c:457 | bl.c:429（★ 向量表切换，见 01_extracted/stm32/vtor-vector-tables） | ┃ bl.h:113 | arch_do_jump(const uint32_t *) | main.c:632 | bl.c:432 |
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-632

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-771"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:771`](bl-h.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-771)

```c
   768 │ #endif
   769 │ 
   770 │ 		/* try to boot immediately */
▶  771 │ 		jump_to_app();
   772 │ 
   773 │ 		// If it failed to boot, reset the boot signature and stay in bootloader
   774 │ 		board_set_rtc_signature(BOOT_RTC_SIGNATURE);
```
> **说明**：bl.h:67 | void bootloader(unsigned timeout) | ①层唯一的对外入口；②层 main.c:802 调用 | ┃ bl.h:66 | void jump_to_app(void) | ①层实现（bl.c:307），②层调用（main.c:771、main.c:824）—— 定义在①、调用在② |
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-771

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-802"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:802`](bl-h.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-802)

```c
   799 │ 
   800 │ 	while (1) {
   801 │ 		/* run the bootloader, come back after an app is uploaded or we time out */
▶  802 │ 		bootloader(timeout);
   803 │ 
   804 │ 		/* if the force-bootloader pins are strapped, just loop back */
   805 │ 		if (board_test_force_pin()) {
```
> **说明**：bl.h:64 | extern struct boardinfo board_info; | ①层读它决定擦多少（bl.c:785 board_info.fw_size、bl.c:902 CRC 范围）、②层读它决定 SysTick 重载（main.c:369） | ┃ bl.h:67 | void bootloader(unsigned timeout) | ①层唯一的对外入口；②层 main.c:802 调用 |
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-802

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-824"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:824`](bl-h.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-824)

```c
   821 │ #endif
   822 │ 
   823 │ 		/* look to see if we can boot the app */
▶  824 │ 		jump_to_app();
   825 │ 
   826 │ 		/* launching the app failed - stay in the bootloader forever */
   827 │ 		timeout = 0;
```
> **说明**：bl.h:67 | void bootloader(unsigned timeout) | ①层唯一的对外入口；②层 main.c:802 调用 | ┃ bl.h:66 | void jump_to_app(void) | ①层实现（bl.c:307），②层调用（main.c:771、main.c:824）—— 定义在①、调用在② |
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-824
