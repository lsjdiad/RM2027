# ③ 板级层 —— 本板（rm2027/fmu-h743）给 bootloader 提供了什么

> **源码**：`boards/rm2027/fmu-h743/src/hw_config.h`（138 行）、`src/bootloader_main.c`（78 行）、
> `nuttx-config/bootloader/defconfig`（78 行）、`bootloader.px4board`（3 行）
> **层**：③ 板级（**本板唯一改动过的一层**；①② 层 `git diff upstream/main` 为空）
> **本篇视角**：只讲"**它们给 bootloader 的运行提供了什么**"。
> 这 4 个文件的"文件孪生"本体归 [02_code_twin/board](../board/README.md)（task-12 负责），本篇不重复其内容清单。

---

## 1. 运行时它处在哪：三个不同的时间点

③层的东西**不是在一个时间点生效的**，这点很容易搞混：

| 时间点 | 谁读它 | 影响什么 |
|---|---|---|
| **① 构建期（CMake/NuttX 配置阶段）** | `bootloader.px4board` → Kconfig → `nuttx-config/bootloader/defconfig` | 决定 NuttX 内核编出什么（有没有 ROMFS、串口、SysTick hook…） |
| **② `__start` 里（内核起来之前）** | `bootloader_main.c:55 stm32_boardinitialize()` | 板级早期外设初始化 |
| **③ `AppBringUp` 线程上（内核起来之后、`bootloader_main` 之前）** | `bootloader_main.c:69 board_late_initialize()`；`bootloader_main.c:75 board_timerhook()`（被 SysTick 中断反复调用） | 起控制台、驱动 bootloader 的"时间" |

**⇒ ③层在 bootloader 里的"执行位置"是**：一次在复位后（②）、一次在决策前（③），其余时间**寄生在 SysTick 中断里**。

---

## 2. `hw_config.h` 提供什么（逐组）

### 2.1 flash / 地址（决定"app 在哪、擦多少"）

| 行号 | 宏 | 值 | 谁读它 |
|---|---|---|---|
| `:87` | `APP_LOAD_ADDRESS` | `0x08020000` | [`bl.c:310`](board-layer.md#^src-platforms-nuttx-src-bootloader-common-bl-c-310)（app_base）、[`main.c:492`](board-layer.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-492) / [`main.c:503`](board-layer.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-503)（flash 读写的相对↔绝对换算）、`fmc.c:60`（缓存标签）、[`ecc_scrub.c:140`](board-layer.md#^src-platforms-nuttx-src-bootloader-stm-stm32h7-ecc-scrub-c-140)（扇区基址） |
| `:103` | `_FLASH_KBYTES` | `*(uint32_t*)0x1FF1E880` | `:105` |
| `:105` | `BOARD_FLASH_SIZE` | `_FLASH_KBYTES * 1024` | [`main.c:86`](stm32-common-main-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-86) |
| `:104` | `BOARD_FLASH_SECTORS` | `15` | [`main.c:470`](board-layer.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-470)（扇区上界）、`:480`（擦除上界） |
| `:124-126` | `BOARD_FIRST_FLASH_SECTOR_TO_ERASE` | `1` | [`main.c:480`](board-layer.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-480)（跳过扇区 0 = bootloader 自己） |
| `:120-122` | `APP_RESERVATION_SIZE` | `0`（未定义时的默认） | [`main.c:86`](stm32-common-main-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-86) ⇒ **`fw_size = 1920 KiB`**（见 [02_code_twin/bootloader/stm32-common-main-c](stm32-common-main-c.md) §3） |

### 2.2 通道（决定"怎么跟主机说话"）

| 行号 | 宏 | 值 | 后果 |
|---|---|---|---|
| `:94` | `INTERFACE_USB` | **0** | `bl.c:176/193/202/233` 四处 USB 分支全裁；[`main.c:723`](stm32-common-main-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-723) VBUS 判断全裁 |
| `:99` | `INTERFACE_USART` | **1** | `bl.c:183/196/215/240` 生效 ⇒ 走 `uart.c` |
| `:100` | `INTERFACE_USART_CONFIG` | `"/dev/ttyS0,57600"` | [`uart.c:53`](board-layer.md#^src-src-lib-drivers-device-qurt-uart-c-53) 解析成设备名 + 波特率；**它覆盖 `defconfig` 里的 `CONFIG_USART1_BAUD=115200`** |
| `:133` | `BOOT_DEVICES_SELECTION` | `USB0_DEV\|SERIAL0_DEV\|SERIAL1_DEV` | [`main.c:261`](board-layer.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-261) (`board_get_devices`) 返回给 [`bl.c:540`](uart-c.md#^src-platforms-nuttx-src-bootloader-common-bl-c-540) |

### 2.3 身份（决定"上位机愿不愿意跟你谈"）

| 行号 | 宏 | 值 | 谁读它 |
|---|---|---|---|
| `:102` | `BOARD_TYPE` | **2027** | [`main.c:99`](board-layer.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-99) → `board_info.board_type` → [`bl.c:714`](board-layer.md#^src-platforms-nuttx-src-bootloader-common-bl-c-714)（`GET_DEVICE/arg=2` 回给上位机） |

**⇒ 必须与 `boards/rm2027/fmu-h743/firmware.prototype` 里的 `board_id` 一致**（`:101` 的注释就是这么说的）。
上位机（`px_uploader.py`）会拿它选固件。**不一致的症状是"上传被拒绝/选错固件"。**

### 2.4 LED（本板**都不可见**）

| 行号 | 宏 | 值 | 实情 |
|---|---|---|---|
| `:109` | `BOARD_PIN_LED_ACTIVITY` | `GPIO_nLED_BLUE` | [`board_config.h:85`](board-layer.md#^src-boards-rm2027-fmu-h743-src-board-config-h-85) 注释：**"PD10（本板悬空，占位）"** |
| `:110` | `BOARD_PIN_LED_BOOTLOADER` | `GPIO_nLED_GREEN` | [`board_config.h:86`](board-layer.md#^src-boards-rm2027-fmu-h743-src-board-config-h-86) 注释：**"PD11（本板悬空，占位）"** |
| `:111-112` | `BOARD_LED_ON` / `BOARD_LED_OFF` | `0` / `1` | `main.c:578/584/596/602` 用（低有效） |

> ★★ **本板最重要的台架结论**：
> 上游 bootloader 的"唯一可读日志"是这两颗灯（`bl.c` 全篇无 `printf`），
> **而本板的这两颗灯是悬空占位脚** ⇒ **灯语在本板上完全不可用**。
> ⇒ 判"bootloader 活着"只能靠：**上位机能不能在 57600 上握手拿到 `0x12 0x10`**。
> （顺带：app 侧也用同一对宏 —— [`board_config.h:85`](board-layer.md#^src-boards-rm2027-fmu-h743-src-board-config-h-85) 是**唯一的一处定义**，bootloader 与 app 共享它。）

### 2.5 本板**故意没定义**的宏（⇒ 决策点恒假）

| 宏 | 若定义会怎样 | 本板 | 依据 |
|---|---|---|---|
| `BOARD_FORCE_BL_PIN` / `_IN` / `_OUT` | `board_test_force_pin()` 能强制进 bootloader | **未定义** ⇒ 函数恒 `return false`（[`main.c:191`](board-layer.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-191)） | `main.c:141/174/296/302/329/335` 全是 `#if defined(...)` |
| `BOARD_VBUS` | USB 插入即停住等主机 | **注释掉了**（[`hw_config.h:96`](stm32-common-main-c.md#^src-boards-rm2027-fmu-h743-src-hw-config-h-96)） | — |
| `BOARD_POWER_PIN_OUT` / `BOARD_POWER_PIN_RELEASE` | 掉电保持 / `POWER_DOWN_RTC_SIGNATURE` 分支 | **未定义** ⇒ [`main.c:668`](board-layer.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-668) 与 [`main.c:340`](board-layer.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-340) 全裁 | — |
| `BOARD_BOOT_FAIL_DETECT` | "跳失败 ⇒ 下次复位停住在 bootloader" | **全仓无定义**（只出现在 2 处 `#ifdef`） | [`main.c:766`](stm32-common-main-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-766) / `:819` |
| `USBDEVICESTRING` / `USBPRODUCTID` | USB 通道的身份串 | 不需要（无 USB） | [`hw_config.h:34`](board-layer.md#^src-boards-rm2027-fmu-h743-src-hw-config-h-34) 的说明区块 |
| `SERIAL_BREAK_DETECT_DISABLED` | — | **已定义 = 1** ⇒ `board_test_usart_receiving_break()` 恒 `false` | [`hw_config.h:114`](board-layer.md#^src-boards-rm2027-fmu-h743-src-hw-config-h-114)；[`main.c:197`](stm32-common-main-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-197) |

**⇒ 4 个决策点里 3 个被 ③层关掉、第 4 个（RTC 签名）因为 `BOARD_BOOT_FAIL_DETECT` 未定义而永远没被写过。
这就是"本板每次上电必然先试跳 app"的**全部原因**，全在 ③层这一份文件里。
（推理链与逐行依据见 [02_code_twin/bootloader/stm32-common-main-c](stm32-common-main-c.md) §2。）**

### 2.6 其它（和 bootloader 关系较小）

| 行号 | 宏 | 用途 |
|---|---|---|
| `:107` | `OSC_FREQ 8` | **全仓 grep 在 bootloader 里无使用者** ⇒ 我标"未核实/疑似遗留"（真值在 [`nuttx-config/include/board.h:74`](board-layer.md#^src-boards-rm2027-fmu-h743-nuttx-config-include-board-h-74) 的 25 MHz 晶振） |
| `:116-118` | `ARCH_SN_MAX_LENGTH 12` | [`bl.c:961`](board-layer.md#^src-platforms-nuttx-src-bootloader-common-bl-c-961) 用它做 `PROTO_GET_SN` 的越界检查 |
| `:128-130` | `USB_DATA_ALIGN` | [`bl.c:277`](board-layer.md#^src-platforms-nuttx-src-bootloader-common-bl-c-277) 用它修饰 `rx_buf`（那块**没人用**的缓冲区，见 [02_code_twin/bootloader/bl-h](bl-h.md) §2.3） |
| `:136-138` | `BOOT_DEVICES_FILTER_ONUSB` | [`main.c:264`](board-layer.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-264) 用（本板 `usb_connected` 恒 false ⇒ 不生效） |

---

## 3. `bootloader_main.c` 提供什么（3 个钩子 + 1 个声明）

| 行号 | 函数 | **谁在什么时刻调它** | 本板行为 |
|---|---|---|---|
| `:51` | `extern int sercon_main(int, char**)` | 只声明 | 真正的定义是 `apps/system/cdcacm/sercon_main.c:52 int main(...)`，**NuttX 的 apps 构建在编译它时用 `-Dmain=sercon_main` 改名**（[`apps/Application.mk:328`](board-layer.md#^src-platforms-nuttx-NuttX-apps-Application-mk-328)）⇒ 实测符号 `sercon_main` 在 map 里（`build/.../rm2027_fmu-h743_bootloader.map:2051`） |
| `:53` | `board_on_reset(int)` | 空实现 | — |
| **`:55`** | **`stm32_boardinitialize(void)`** | **NuttX `__start` 里**：`nuttx/arch/arm/src/stm32h7/stm32_start.c:262` | 本板把 USB 初始化也去掉了（`:57-60` 的 `#if INTERFACE_USB` 判假）⇒ **整个函数体为空** |
| `:64` | `board_app_initialize(uintptr_t)` | 由 `boardctl(BOARDIOC_INIT)` 调用（app 侧才用） | 恒 `return 0` |
| **`:69`** | **`board_late_initialize(void)`** | [`nx_bringup.c:321`](board-layer.md#^src-platforms-nuttx-NuttX-nuttx-sched-init-nx-bringup-c-321)（`AppBringUp` 线程） | **调 `sercon_main(0, NULL)`** —— 见下 |
| **`:75`** | **`board_timerhook(void)`** | [`nuttx/sched/sched/sched_processtimer.c:204`](board-layer.md#^src-platforms-nuttx-NuttX-nuttx-sched-sched-sched-processtimer-c-204)（**每 1 ms 的 SysTick 中断**，靠 `CONFIG_SYSTEMTICK_HOOK=y`） | **`sys_tick_handler()`**（[`bl.c:437`](board-layer.md#^src-platforms-nuttx-src-bootloader-common-bl-c-437)）⇒ 递减 `timer[]`、翻转 LED |

### 3.1 ★ `board_late_initialize()` → `sercon_main()` 在本板是"空转"

```
nx_bringup.c:321  board_late_initialize()
  └─ bootloader_main.c:71  sercon_main(0, NULL)
       └─ sercon_main.c:52  main()
            :61  usbtrace_enable(TRACE_BITSET)
            :72  boardctl(BOARDIOC_USBDEV_CONTROL, CDCACM/CONNECT)
                 ↑ 本板 CONFIG_USBDEV is not set（bootloader .config:888）
                   ⇒ 失败返回 ⇒ :75 printf(...) 一行错误文本
            :77  return EXIT_FAILURE
```

而且那行 `printf` 也**出不来**：bootloader 的 `.config:868` `# CONFIG_USART1_SERIAL_CONSOLE is not set`、
`.config:870 CONFIG_NO_SERIAL_CONSOLE=y` ⇒ **没有控制台**。

**⇒ 结论**：本板每次上电，`AppBringUp` 线程都会做一次注定失败的"注册 USB CDC/ACM"，
然后 `bootloader_main` 才被 `task_spawn` 起来。**执行序上是"先空转一次，再进主函数"**。
（这一条是上游所有 `INTERFACE_USART`-only 板子的共同形态，不是本板的 bug。）

### 3.2 ★ `board_timerhook()` 是 bootloader 的"心跳"

```
SysTick 中断
  └─ nxsched_process_timer → sched_processtimer.c:204 board_timerhook()
       └─ bootloader_main.c:77 sys_tick_handler()      ← ①层 bl.c:437
            :442-445  递减 timer[0..3]
            :447-450  LED_BLINK 态下每 50 ms 翻转一次 LED
```

**⇒ 这条链一断，`bl.c` 里所有超时都会永久卡死**（[`bl.c:655`](uart-c.md#^src-platforms-nuttx-src-bootloader-common-bl-c-655) 永不返回、[`bl.c:458`](board-layer.md#^src-platforms-nuttx-src-bootloader-common-bl-c-458) 死循环）。
判据：`build/rm2027_fmu-h743_bootloader/NuttX/nuttx/.config:578` 必须是 `CONFIG_SYSTEMTICK_HOOK=y`
（对应 `nuttx-config/bootloader/defconfig:71`）。**这是 ③层唯一"不能少"的配置项。**

---

## 4. `nuttx-config/bootloader/defconfig` 里的关键 5 项

| 行号 | 配置 | 为什么关键 |
|---|---|---|
| `:45` | `CONFIG_INIT_ENTRYPOINT="bootloader_main"` | ★ **这就是"控制权从 NuttX 交到 ②层"的那条接线**（[`nx_bringup.c:356`](stm32-common-main-c.md#^src-platforms-nuttx-NuttX-nuttx-sched-init-nx-bringup-c-356)） |
| `:71` | `CONFIG_SYSTEMTICK_HOOK=y` | ★ 让 `board_timerhook()` 被调用 ⇒ `timer[]` 才会走 |
| `:32` | `CONFIG_BOARD_LATE_INITIALIZE=y` | ⇒ `board_late_initialize()` 会被调（起 `AppBringUp` 线程，[`nx_bringup.c:436`](board-layer.md#^src-platforms-nuttx-NuttX-nuttx-sched-init-nx-bringup-c-436)） |
| `:24` | `CONFIG_ARCH_INTERRUPTSTACK=768` | >7 ⇒ NuttX 把线程模式栈切到 **PSP** ⇒ 这正是 [`main.c:641`](board-layer.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-641) 里 `arch_do_jump` 必须清 `CONTROL.SPSEL` 的原因 |
| `:70` | `CONFIG_STM32H7_USART1=y` | `uart.c` 要 `open("/dev/ttyS0")` 所依赖的串口驱动 |

外加 `bootloader.px4board:3 CONFIG_BOARD_ROMFSROOT=""` ⇒ **bootloader 不带 ROMFS**（→ [01_extracted/nuttx/romfs](../../01_extracted/nuttx/romfs.md)）。

---

## 5. "我看到的现象由谁产生"

| 现象 | ③层的哪一条 | 依据 |
|---|---|---|
| 上电**没有任何灯**（哪怕报错时） | LED 宏指向悬空脚 | [`hw_config.h:109`](board-layer.md#^src-boards-rm2027-fmu-h743-src-hw-config-h-109) + [`board_config.h:85`](board-layer.md#^src-boards-rm2027-fmu-h743-src-board-config-h-85) |
| 上位机必须用 **57600** | `INTERFACE_USART_CONFIG` | [`hw_config.h:100`](uart-c.md#^src-boards-rm2027-fmu-h743-src-hw-config-h-100) |
| 短接某个引脚**进不去 bootloader** | 没有 `BOARD_FORCE_BL_PIN` | `hw_config.h`（未定义） |
| 跳 app 失败后**每次复位都再试**（不自锁） | 没有 `BOARD_BOOT_FAIL_DETECT` | `main.c:766/819` |
| 串口上打 break **不会**让板子停在 bootloader | `SERIAL_BREAK_DETECT_DISABLED` | [`hw_config.h:114`](board-layer.md#^src-boards-rm2027-fmu-h743-src-hw-config-h-114) |
| 上位机报"板子 ID 不对" | `BOARD_TYPE 2027` 与 `firmware.prototype` 不一致 | [`hw_config.h:102`](board-layer.md#^src-boards-rm2027-fmu-h743-src-hw-config-h-102) |
| 刷完固件参数回默认 | `APP_RESERVATION_SIZE=0` ⇒ `fw_size` 覆盖参数扇区 | [`hw_config.h:120`](board-layer.md#^src-boards-rm2027-fmu-h743-src-hw-config-h-120) ⇒ [01_extracted/stm32/flash-layout](../../01_extracted/stm32/flash-layout.md) |

---

## 跳转

- **执行序上一步**（谁调这三个钩子）→ [01_extracted/nuttx/00-poweron-chain](../../01_extracted/nuttx/00-poweron-chain.md)。
- **执行序下一步**（钩子跑完，`bootloader_main` 怎么决策）→ [02_code_twin/bootloader/stm32-common-main-c](stm32-common-main-c.md)。
- **`APP_LOAD_ADDRESS` / `fw_size` / 参数扇区三者怎么对不上** → [01_extracted/stm32/flash-layout](../../01_extracted/stm32/flash-layout.md)。
- **③层在构建期怎么被编进去** → [02_code_twin/bootloader/cmakelists](cmakelists.md)。
- **文件本体（25 个板级文件的完整孪生）** → [02_code_twin/board](../board/README.md)（task-12 负责）。
- **ROMFS 为什么本板 app 有、bootloader 没有** → [01_extracted/nuttx/romfs](../../01_extracted/nuttx/romfs.md)。

---

## 未核实

- `OSC_FREQ 8` 在 bootloader 构建里**是否真的无人使用**：我 grep 了 `platforms/nuttx/src/bootloader/` 全目录无命中，
  但**没有**在全仓范围确认（可能被 NuttX 或 `px4_platform_common` 用到）。标"疑似遗留"。
- `sercon_main()` 里的 `printf` 在 `CONFIG_NO_SERIAL_CONSOLE=y` 下**具体落到哪**（丢弃 / 走 /dev/console 失败 / 触发断言），我**没有追 NuttX 的 stdio 初始化**，标"未核实"。

---

## 标注源码（代码 + 本文档对它的解释）

> **这是「代码孪生」层**：上面是代码原文（带行号），下面是**本文档针对这一段说的话**。
> 行号可点，直接跳到 PX4 源码那一行。
### `boards/rm2027/fmu-h743/nuttx-config/include/board.h`
<a id="src-boards-rm2027-fmu-h743-nuttx-config-include-board-h-74"></a>
**↓ 文档在讲这里：**[`boards/rm2027/fmu-h743/nuttx-config/include/board.h:74`](board-layer.md#^src-boards-rm2027-fmu-h743-nuttx-config-include-board-h-74)

```c
    71 │  *   HSE:  8 MHz crystal for HSE
    72 │  */
    73 │ 
▶   74 │ #define STM32_BOARD_XTAL        25000000ul
    75 │ 
    76 │ #define STM32_HSI_FREQUENCY     16000000ul
    77 │ #define STM32_LSI_FREQUENCY     32000
```
> **说明**：:107 | OSC_FREQ 8 | 全仓 grep 在 bootloader 里无使用者 ⇒ 我标"未核实/疑似遗留"（真值在 nuttx-config/include/board.h:74 的 25 MHz 晶振） |
^src-boards-rm2027-fmu-h743-nuttx-config-include-board-h-74

### `boards/rm2027/fmu-h743/src/board_config.h`
<a id="src-boards-rm2027-fmu-h743-src-board-config-h-85"></a>
**↓ 文档在讲这里：**[`boards/rm2027/fmu-h743/src/board_config.h:85`](board-layer.md#^src-boards-rm2027-fmu-h743-src-board-config-h-85)

```c
    82 │  * 驱动能跑、能编译，只是物理上看不见。
    83 │  * 真要做指示灯 → 飞线到这两个脚即可，无需改代码。
    84 │  */
▶   85 │ #define GPIO_nLED_BLUE          /* PD10（本板悬空，占位） */  (GPIO_OUTPUT|GPIO_PUSHPULL|GPIO_SPEED_2MHz|GPIO_OUTPUT_SET|GPIO_PORTD|GPIO_PIN10)
    86 │ #define GPIO_nLED_GREEN         /* PD11（本板悬空，占位） */  (GPIO_OUTPUT|GPIO_PUSHPULL|GPIO_SPEED_2MHz|GPIO_OUTPUT_SET|GPIO_PORTD|GPIO_PIN11)
    87 │ 
    88 │ #define BOARD_HAS_CONTROL_STATUS_LEDS   1
```
> **说明**：:109 | BOARD_PIN_LED_ACTIVITY | GPIO_nLED_BLUE | board_config.h:85 注释："PD10（本板悬空，占位）" |
> **说明**：⇒ 判"bootloader 活着"只能靠：上位机能不能在 57600 上握手拿到 0x12 0x10。 ┃ （顺带：app 侧也用同一对宏 —— board_config.h:85 是唯一的一处定义，bootloader 与 app 共享它。）
^src-boards-rm2027-fmu-h743-src-board-config-h-85

<a id="src-boards-rm2027-fmu-h743-src-board-config-h-86"></a>
**↓ 文档在讲这里：**[`boards/rm2027/fmu-h743/src/board_config.h:86`](board-layer.md#^src-boards-rm2027-fmu-h743-src-board-config-h-86)

```c
    83 │  * 真要做指示灯 → 飞线到这两个脚即可，无需改代码。
    84 │  */
    85 │ #define GPIO_nLED_BLUE          /* PD10（本板悬空，占位） */  (GPIO_OUTPUT|GPIO_PUSHPULL|GPIO_SPEED_2MHz|GPIO_OUTPUT_SET|GPIO_PORTD|GPIO_PIN10)
▶   86 │ #define GPIO_nLED_GREEN         /* PD11（本板悬空，占位） */  (GPIO_OUTPUT|GPIO_PUSHPULL|GPIO_SPEED_2MHz|GPIO_OUTPUT_SET|GPIO_PORTD|GPIO_PIN11)
    87 │ 
    88 │ #define BOARD_HAS_CONTROL_STATUS_LEDS   1
    89 │ #define BOARD_ARMED_STATE_LED           1
```
> **说明**：:109 | BOARD_PIN_LED_ACTIVITY | GPIO_nLED_BLUE | board_config.h:85 注释："PD10（本板悬空，占位）" | ┃ :110 | BOARD_PIN_LED_BOOTLOADER | GPIO_nLED_GREEN | board_config.h:86 注释："PD11（本板悬空，占位）" |
^src-boards-rm2027-fmu-h743-src-board-config-h-86

### `boards/rm2027/fmu-h743/src/hw_config.h`
<a id="src-boards-rm2027-fmu-h743-src-hw-config-h-34"></a>
**↓ 文档在讲这里：**[`boards/rm2027/fmu-h743/src/hw_config.h:34`](board-layer.md#^src-boards-rm2027-fmu-h743-src-hw-config-h-34)

```c
    31 │  *
    32 │  ****************************************************************************/
    33 │ 
▶   34 │ #pragma once
    35 │ 
    36 │ /****************************************************************************
    37 │  * 10-8--2016:
```
> **说明**：BOARD_BOOT_FAIL_DETECT | "跳失败 ⇒ 下次复位停住在 bootloader" | 全仓无定义（只出现在 2 处 #ifdef） | main.c:766 / :819 | ┃ USBDEVICESTRING / USBPRODUCTID | USB 通道的身份串 | 不需要（无 USB） | hw_config.h:34 的说明区块 |
^src-boards-rm2027-fmu-h743-src-hw-config-h-34

<a id="src-boards-rm2027-fmu-h743-src-hw-config-h-96"></a>
**↓ 文档在讲这里：**[`boards/rm2027/fmu-h743/src/hw_config.h:96`](board-layer.md#^src-boards-rm2027-fmu-h743-src-hw-config-h-96)

```c
    93 │  */
    94 │ #define INTERFACE_USB                  0
    95 │ // #define INTERFACE_USB_CONFIG        "/dev/ttyACM0"
▶   96 │ // #define BOARD_VBUS                  MK_GPIO_INPUT(GPIO_OTGFS_VBUS)   /* 本板无 VBUS 检测脚 */
    97 │ 
    98 │ //#define USE_VBUS_PULL_DOWN
    99 │ #define INTERFACE_USART                1
```
> **说明**：BOARD_FORCE_BL_PIN / _IN / _OUT | board_test_force_pin() 能强制进 bootloader | 未定义 ⇒ 函数恒 return false（main.c:191） | main.c:141/174/296/302/329/335 全是 #if defined(...) | ┃ BOARD_VBUS | USB 插入即停住等主机 | 注释掉了（hw_config.h:96） | — |
^src-boards-rm2027-fmu-h743-src-hw-config-h-96

<a id="src-boards-rm2027-fmu-h743-src-hw-config-h-100"></a>
**↓ 文档在讲这里：**[`boards/rm2027/fmu-h743/src/hw_config.h:100`](board-layer.md#^src-boards-rm2027-fmu-h743-src-hw-config-h-100)

```c
    97 │ 
    98 │ //#define USE_VBUS_PULL_DOWN
    99 │ #define INTERFACE_USART                1
▶  100 │ #define INTERFACE_USART_CONFIG         "/dev/ttyS0,57600"
   101 │ /* ★ 必须与 firmware.prototype 的 board_id 一致（本板 = 2027） */
   102 │ #define BOARD_TYPE                     2027
   103 │ #define _FLASH_KBYTES                  (*(uint32_t *)0x1FF1E880)
```
> **说明**：上电没有任何灯（哪怕报错时） | LED 宏指向悬空脚 | hw_config.h:109 + board_config.h:85 | ┃ 上位机必须用 57600 | INTERFACE_USART_CONFIG | hw_config.h:100 |
^src-boards-rm2027-fmu-h743-src-hw-config-h-100

<a id="src-boards-rm2027-fmu-h743-src-hw-config-h-102"></a>
**↓ 文档在讲这里：**[`boards/rm2027/fmu-h743/src/hw_config.h:102`](board-layer.md#^src-boards-rm2027-fmu-h743-src-hw-config-h-102)

```c
    99 │ #define INTERFACE_USART                1
   100 │ #define INTERFACE_USART_CONFIG         "/dev/ttyS0,57600"
   101 │ /* ★ 必须与 firmware.prototype 的 board_id 一致（本板 = 2027） */
▶  102 │ #define BOARD_TYPE                     2027
   103 │ #define _FLASH_KBYTES                  (*(uint32_t *)0x1FF1E880)
   104 │ #define BOARD_FLASH_SECTORS            (15)
   105 │ #define BOARD_FLASH_SIZE               (_FLASH_KBYTES * 1024)
```
> **说明**：串口上打 break 不会让板子停在 bootloader | SERIAL_BREAK_DETECT_DISABLED | hw_config.h:114 | ┃ 上位机报"板子 ID 不对" | BOARD_TYPE 2027 与 firmware.prototype 不一致 | hw_config.h:102 |
^src-boards-rm2027-fmu-h743-src-hw-config-h-102

<a id="src-boards-rm2027-fmu-h743-src-hw-config-h-109"></a>
**↓ 文档在讲这里：**[`boards/rm2027/fmu-h743/src/hw_config.h:109`](board-layer.md#^src-boards-rm2027-fmu-h743-src-hw-config-h-109)

```c
   106 │ 
   107 │ #define OSC_FREQ                       8
   108 │ 
▶  109 │ #define BOARD_PIN_LED_ACTIVITY         GPIO_nLED_BLUE // BLUE
   110 │ #define BOARD_PIN_LED_BOOTLOADER       GPIO_nLED_GREEN // GREEN
   111 │ #define BOARD_LED_ON                   0
   112 │ #define BOARD_LED_OFF                  1
```
> **说明**：上电没有任何灯（哪怕报错时） | LED 宏指向悬空脚 | hw_config.h:109 + board_config.h:85 |
^src-boards-rm2027-fmu-h743-src-hw-config-h-109

<a id="src-boards-rm2027-fmu-h743-src-hw-config-h-114"></a>
**↓ 文档在讲这里：**[`boards/rm2027/fmu-h743/src/hw_config.h:114`](board-layer.md#^src-boards-rm2027-fmu-h743-src-hw-config-h-114)

```c
   111 │ #define BOARD_LED_ON                   0
   112 │ #define BOARD_LED_OFF                  1
   113 │ 
▶  114 │ #define SERIAL_BREAK_DETECT_DISABLED   1
   115 │ 
   116 │ #if !defined(ARCH_SN_MAX_LENGTH)
   117 │ # define ARCH_SN_MAX_LENGTH 12
```
> **说明**：USBDEVICESTRING / USBPRODUCTID | USB 通道的身份串 | 不需要（无 USB） | hw_config.h:34 的说明区块 | ┃ SERIAL_BREAK_DETECT_DISABLED | — | 已定义 = 1 ⇒ board_test_usart_receiving_break() 恒 false | hw_config.h:114；main.c:197 |
> **说明**：跳 app 失败后每次复位都再试（不自锁） | 没有 BOARD_BOOT_FAIL_DETECT | main.c:766/819 | ┃ 串口上打 break 不会让板子停在 bootloader | SERIAL_BREAK_DETECT_DISABLED | hw_config.h:114 |
^src-boards-rm2027-fmu-h743-src-hw-config-h-114

<a id="src-boards-rm2027-fmu-h743-src-hw-config-h-120"></a>
**↓ 文档在讲这里：**[`boards/rm2027/fmu-h743/src/hw_config.h:120`](board-layer.md#^src-boards-rm2027-fmu-h743-src-hw-config-h-120)

```c
   117 │ # define ARCH_SN_MAX_LENGTH 12
   118 │ #endif
   119 │ 
▶  120 │ #if !defined(APP_RESERVATION_SIZE)
   121 │ #  define APP_RESERVATION_SIZE 0
   122 │ #endif
   123 │ 
```
> **说明**：上位机报"板子 ID 不对" | BOARD_TYPE 2027 与 firmware.prototype 不一致 | hw_config.h:102 | ┃ 刷完固件参数回默认 | APP_RESERVATION_SIZE=0 ⇒ fw_size 覆盖参数扇区 | hw_config.h:120 ⇒ 01_extracted/stm32/flash-layout |
^src-boards-rm2027-fmu-h743-src-hw-config-h-120

### `platforms/nuttx/NuttX/apps/Application.mk`
<a id="src-platforms-nuttx-NuttX-apps-Application-mk-328"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/NuttX/apps/Application.mk:328`](board-layer.md#^src-platforms-nuttx-NuttX-apps-Application-mk-328)

```c
   325 │ 		$(call ELFCOMPILEXX, $<, $@), $(call COMPILEXX, $<, $@))
   326 │ 
   327 │ $(MAINCOBJ): $(PREFIX)%.c$(SUFFIX)$(OBJEXT): %.c
▶  328 │ 	$(eval $<_CFLAGS += ${DEFINE_PREFIX}main=$(addsuffix _main,$(PROGNAME_$@)))
   329 │ 	$(eval $<_CELFFLAGS += ${DEFINE_PREFIX}main=$(addsuffix _main,$(PROGNAME_$@)))
   330 │ 	$(if $(and $(CONFIG_MODULES),$(MODCFLAGS)), \
   331 │ 		$(call ELFCOMPILE, $<, $@), $(call COMPILE, $<, $@))
```
> **说明**：:51 | extern int sercon_main(int, char) | 只声明 | 真正的定义是 apps/system/cdcacm/sercon_main.c:52 int main(...)，NuttX 的 apps 构建在编译它时用 -Dmain=sercon_main 改名（apps/Application.mk:328）⇒ 实测符号 sercon_main 在 map 里（
^src-platforms-nuttx-NuttX-apps-Application-mk-328

### `platforms/nuttx/NuttX/nuttx/arch/arm/src/stm32/stm32_start.c`
### `platforms/nuttx/NuttX/nuttx/sched/init/nx_bringup.c`
<a id="src-platforms-nuttx-NuttX-nuttx-sched-init-nx-bringup-c-321"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/NuttX/nuttx/sched/init/nx_bringup.c:321`](board-layer.md#^src-platforms-nuttx-NuttX-nuttx-sched-init-nx-bringup-c-321)

```c
   318 │    * configured.
   319 │    */
   320 │ 
▶  321 │   board_late_initialize();
   322 │ #endif
   323 │ 
   324 │ #ifdef CONFIG_COREDUMP
```
> **说明**：:64 | board_app_initialize(uintptr_t) | 由 boardctl(BOARDIOC_INIT) 调用（app 侧才用） | 恒 return 0 | ┃ :69 | board_late_initialize(void) | nx_bringup.c:321（AppBringUp 线程） | 调 sercon_main(0, NULL) —— 见下 |
^src-platforms-nuttx-NuttX-nuttx-sched-init-nx-bringup-c-321

<a id="src-platforms-nuttx-NuttX-nuttx-sched-init-nx-bringup-c-356"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/NuttX/nuttx/sched/init/nx_bringup.c:356`](board-layer.md#^src-platforms-nuttx-NuttX-nuttx-sched-init-nx-bringup-c-356)

```c
   353 │                    USERSPACE->us_entrypoint,
   354 │                    NULL, &attr, argv, NULL);
   355 │ #  else
▶  356 │   ret = task_spawn(CONFIG_INIT_ENTRYNAME,
   357 │                    CONFIG_INIT_ENTRYPOINT,
   358 │                    NULL, &attr, argv, NULL);
   359 │ #  endif
```
> **说明**：:45 | CONFIG_INIT_ENTRYPOINT="bootloader_main" | ★ 这就是"控制权从 NuttX 交到 ②层"的那条接线（nx_bringup.c:356） |
^src-platforms-nuttx-NuttX-nuttx-sched-init-nx-bringup-c-356

<a id="src-platforms-nuttx-NuttX-nuttx-sched-init-nx-bringup-c-436"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/NuttX/nuttx/sched/init/nx_bringup.c:436`](board-layer.md#^src-platforms-nuttx-NuttX-nuttx-sched-init-nx-bringup-c-436)

```c
   433 │ 
   434 │ static inline void nx_create_initthread(void)
   435 │ {
▶  436 │ #ifdef CONFIG_BOARD_LATE_INITIALIZE
   437 │   int pid;
   438 │ 
   439 │   /* Do the board/application initialization on a separate thread of
```
> **说明**：:71 | CONFIG_SYSTEMTICK_HOOK=y | ★ 让 board_timerhook() 被调用 ⇒ timer[] 才会走 | ┃ :32 | CONFIG_BOARD_LATE_INITIALIZE=y | ⇒ board_late_initialize() 会被调（起 AppBringUp 线程，nx_bringup.c:436） |
^src-platforms-nuttx-NuttX-nuttx-sched-init-nx-bringup-c-436

### `platforms/nuttx/NuttX/nuttx/sched/sched/sched_processtimer.c`
<a id="src-platforms-nuttx-NuttX-nuttx-sched-sched-sched-processtimer-c-204"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/NuttX/nuttx/sched/sched/sched_processtimer.c:204`](board-layer.md#^src-platforms-nuttx-NuttX-nuttx-sched-sched-sched-processtimer-c-204)

```c
   201 │    * custom timer operations.
   202 │    */
   203 │ 
▶  204 │   board_timerhook();
   205 │ #endif
   206 │ }
   207 │ 
```
> **说明**：:69 | board_late_initialize(void) | nx_bringup.c:321（AppBringUp 线程） | 调 sercon_main(0, NULL) —— 见下 | ┃ :75 | board_timerhook(void) | nuttx/sched/sched/sched_processtimer.c:204（每 1 ms 的 SysTick 中断，靠 CONFIG_SYSTEMTICK_HOOK=y） | sys_tick_handler()（bl.c:437）⇒ 递减 timer[]、翻转 LED |
^src-platforms-nuttx-NuttX-nuttx-sched-sched-sched-processtimer-c-204

### `platforms/nuttx/src/bootloader/common/bl.c`
<a id="src-platforms-nuttx-src-bootloader-common-bl-c-277"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:277`](board-layer.md#^src-platforms-nuttx-src-bootloader-common-bl-c-277)

```c
   274 │ static const uint32_t bl_proto_rev = BL_PROTOCOL_REVISION; // value returned by PROTO_DEVICE_BL_REV
   275 │ 
   276 │ static unsigned head, tail;
▶  277 │ static uint8_t rx_buf[256] USB_DATA_ALIGN;
   278 │ 
   279 │ static enum led_state {LED_BLINK, LED_ON, LED_OFF} _led_state;
   280 │ 
```
> **说明**：:116-118 | ARCH_SN_MAX_LENGTH 12 | bl.c:961 用它做 PROTO_GET_SN 的越界检查 | ┃ :128-130 | USB_DATA_ALIGN | bl.c:277 用它修饰 rx_buf（那块没人用的缓冲区，见 02_code_twin/bootloader/bl-h §2.3） |
^src-platforms-nuttx-src-bootloader-common-bl-c-277

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-310"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:310`](board-layer.md#^src-platforms-nuttx-src-bootloader-common-bl-c-310)

```c
   307 │ void
   308 │ jump_to_app()
   309 │ {
▶  310 │ 	const uint32_t *app_base = (const uint32_t *)APP_LOAD_ADDRESS;
   311 │ 	const uint32_t *vec_base = (const uint32_t *)((const uint32_t)app_base + APP_VECTOR_OFFSET);
   312 │ 
   313 │ 	/*
```
> **说明**：:87 | APP_LOAD_ADDRESS | 0x08020000 | bl.c:310（app_base）、main.c:492 / main.c:503（flash 读写的相对↔绝对换算）、fmc.c:60（缓存标签）、ecc_scrub.c:140（扇区基址） |
^src-platforms-nuttx-src-bootloader-common-bl-c-310

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-437"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:437`](board-layer.md#^src-platforms-nuttx-src-bootloader-common-bl-c-437)

```c
   434 │ 
   435 │ volatile unsigned timer[NTIMERS];
   436 │ 
▶  437 │ void
   438 │ sys_tick_handler(void)
   439 │ {
   440 │ 	unsigned i;
```
> **说明**：:69 | board_late_initialize(void) | nx_bringup.c:321（AppBringUp 线程） | 调 sercon_main(0, NULL) —— 见下 | ┃ :75 | board_timerhook(void) | nuttx/sched/sched/sched_processtimer.c:204（每 1 ms 的 SysTick 中断，靠 CONFIG_SYSTEMTICK_HOOK=y） | sys_tick_handler()（bl.c:437）⇒ 递减 timer[]、翻转 LED |
> **说明**：└─ bootloader_main.c:77 sys_tick_handler() ← ①层 bl.c:437
^src-platforms-nuttx-src-bootloader-common-bl-c-437

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-458"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:458`](board-layer.md#^src-platforms-nuttx-src-bootloader-common-bl-c-458)

```c
   455 │ {
   456 │ 	timer[TIMER_DELAY] = msec;
   457 │ 
▶  458 │ 	while (timer[TIMER_DELAY] > 0)
   459 │ 		;
   460 │ }
   461 │ 
```
> **说明**：⇒ 这条链一断，bl.c 里所有超时都会永久卡死（bl.c:655 永不返回、bl.c:458 死循环）。
^src-platforms-nuttx-src-bootloader-common-bl-c-458

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-540"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:540`](board-layer.md#^src-platforms-nuttx-src-bootloader-common-bl-c-540)

```c
   537 │ 	timer[TIMER_CIN] = timeout;
   538 │ 
   539 │ 	do {
▶  540 │ 		c = cin(board_get_devices());
   541 │ 
   542 │ 		if (c >= 0) {
   543 │ 			cin_count++;
```
> **说明**：:100 | INTERFACE_USART_CONFIG | "/dev/ttyS0,57600" | uart.c:53 解析成设备名 + 波特率；它覆盖 defconfig 里的 CONFIG_USART1_BAUD=115200 | ┃ :133 | BOOT_DEVICES_SELECTION | USB0_DEV\|SERIAL0_DEV\|SERIAL1_DEV | main.c:261 (board_get_devices) 返回给 bl.c:540 |
^src-platforms-nuttx-src-bootloader-common-bl-c-540

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-655"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:655`](board-layer.md#^src-platforms-nuttx-src-bootloader-common-bl-c-655)

```c
   652 │ 
   653 │ 		do {
   654 │ 			/* if we have a timeout and the timer has expired, return now */
▶  655 │ 			if (timeout && !timer[TIMER_BL_WAIT]) {
   656 │ 				return;
   657 │ 			}
   658 │ 
```
> **说明**：⇒ 这条链一断，bl.c 里所有超时都会永久卡死（bl.c:655 永不返回、bl.c:458 死循环）。
^src-platforms-nuttx-src-bootloader-common-bl-c-655

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-714"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:714`](board-layer.md#^src-platforms-nuttx-src-bootloader-common-bl-c-714)

```c
   711 │ 				break;
   712 │ 
   713 │ 			case PROTO_DEVICE_BOARD_ID:
▶  714 │ 				cout((uint8_t *)&board_info.board_type, sizeof(board_info.board_type));
   715 │ 				break;
   716 │ 
   717 │ 			case PROTO_DEVICE_BOARD_REV:
```
> **说明**：:102 | BOARD_TYPE | 2027 | main.c:99 → board_info.board_type → bl.c:714（GET_DEVICE/arg=2 回给上位机） |
^src-platforms-nuttx-src-bootloader-common-bl-c-714

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-961"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:961`](board-layer.md#^src-platforms-nuttx-src-bootloader-common-bl-c-961)

```c
   958 │ 
   959 │ 				// expect valid indices 0, 4 ...ARCH_SN_MAX_LENGTH-4
   960 │ 
▶  961 │ 				if (index % sizeof(uint32_t) != 0 || index > ARCH_SN_MAX_LENGTH - sizeof(uint32_t)) {
   962 │ 					goto cmd_bad;
   963 │ 				}
   964 │ 
```
> **说明**：:107 | OSC_FREQ 8 | 全仓 grep 在 bootloader 里无使用者 ⇒ 我标"未核实/疑似遗留"（真值在 nuttx-config/include/board.h:74 的 25 MHz 晶振） | ┃ :116-118 | ARCH_SN_MAX_LENGTH 12 | bl.c:961 用它做 PROTO_GET_SN 的越界检查 |
^src-platforms-nuttx-src-bootloader-common-bl-c-961

### `platforms/nuttx/src/bootloader/stm/stm32_common/main.c`
<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-86"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:86`](board-layer.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-86)

```c
    83 │ # error "APP_RESERVATION_SIZE must be greater than 0 if FLASH_BASED_PARAMS is defined"
    84 │ #endif
    85 │ 
▶   86 │ #define APP_SIZE_MAX			(BOARD_FLASH_SIZE - (BOOTLOADER_RESERVATION_SIZE + APP_RESERVATION_SIZE))
    87 │ 
    88 │ 
    89 │ /* context passed to cinit */
```
> **说明**：:103 | _FLASH_KBYTES | *(uint32_t*)0x1FF1E880 | :105 | ┃ :105 | BOARD_FLASH_SIZE | _FLASH_KBYTES * 1024 | main.c:86 |
> **说明**：:124-126 | BOARD_FIRST_FLASH_SECTOR_TO_ERASE | 1 | main.c:480（跳过扇区 0 = bootloader 自己） | ┃ :120-122 | APP_RESERVATION_SIZE | 0（未定义时的默认） | main.c:86 ⇒ fw_size = 1920 KiB（见 02_code_twin/bootloader/stm32-common-main-c §3） |
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-86

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-99"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:99`](board-layer.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-99)

```c
    96 │ 
    97 │ /* board definition */
    98 │ struct boardinfo board_info = {
▶   99 │ 	.board_type	= BOARD_TYPE,
   100 │ 	.board_rev	= 0,
   101 │ 	.fw_size	= 0,
   102 │ 	.systick_mhz	= STM32_CPUCLK_FREQUENCY / 1000000,
```
> **说明**：:102 | BOARD_TYPE | 2027 | main.c:99 → board_info.board_type → bl.c:714（GET_DEVICE/arg=2 回给上位机） |
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-99

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-191"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:191`](board-layer.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-191)

```c
   188 │ 	}
   189 │ 
   190 │ #endif
▶  191 │ 	return false;
   192 │ }
   193 │ 
   194 │ #if INTERFACE_USART
```
> **说明**：BOARD_FORCE_BL_PIN / _IN / _OUT | board_test_force_pin() 能强制进 bootloader | 未定义 ⇒ 函数恒 return false（main.c:191） | main.c:141/174/296/302/329/335 全是 #if defined(...) |
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-191

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-197"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:197`](board-layer.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-197)

```c
   194 │ #if INTERFACE_USART
   195 │ static bool board_test_usart_receiving_break(void)
   196 │ {
▶  197 │ #if !defined(SERIAL_BREAK_DETECT_DISABLED)
   198 │ 	/* (re)start the SysTick timer system */
   199 │ 	systick_interrupt_disable(); // Kill the interrupt if it is still active
   200 │ 	systick_counter_disable(); // Stop the timer
```
> **说明**：USBDEVICESTRING / USBPRODUCTID | USB 通道的身份串 | 不需要（无 USB） | hw_config.h:34 的说明区块 | ┃ SERIAL_BREAK_DETECT_DISABLED | — | 已定义 = 1 ⇒ board_test_usart_receiving_break() 恒 false | hw_config.h:114；main.c:197 |
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-197

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-261"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:261`](board-layer.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-261)

```c
   258 │ uint32_t
   259 │ board_get_devices(void)
   260 │ {
▶  261 │ 	uint32_t devices = BOOT_DEVICES_SELECTION;
   262 │ 
   263 │ 	if (usb_connected) {
   264 │ 		devices &= BOOT_DEVICES_FILTER_ONUSB;
```
> **说明**：:100 | INTERFACE_USART_CONFIG | "/dev/ttyS0,57600" | uart.c:53 解析成设备名 + 波特率；它覆盖 defconfig 里的 CONFIG_USART1_BAUD=115200 | ┃ :133 | BOOT_DEVICES_SELECTION | USB0_DEV\|SERIAL0_DEV\|SERIAL1_DEV | main.c:261 (board_get_devices) 返回给 bl.c:540 |
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-261

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-264"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:264`](board-layer.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-264)

```c
   261 │ 	uint32_t devices = BOOT_DEVICES_SELECTION;
   262 │ 
   263 │ 	if (usb_connected) {
▶  264 │ 		devices &= BOOT_DEVICES_FILTER_ONUSB;
   265 │ 	}
   266 │ 
   267 │ 	return devices;
```
> **说明**：:128-130 | USB_DATA_ALIGN | bl.c:277 用它修饰 rx_buf（那块没人用的缓冲区，见 02_code_twin/bootloader/bl-h §2.3） | ┃ :136-138 | BOOT_DEVICES_FILTER_ONUSB | main.c:264 用（本板 usb_connected 恒 false ⇒ 不生效） |
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-264

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-340"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:340`](board-layer.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-340)

```c
   337 │ 	px4_arch_configgpio(MK_GPIO_INPUT(BOARD_FORCE_BL_PIN));
   338 │ #endif
   339 │ 
▶  340 │ #if defined(BOARD_POWER_PIN_OUT) && defined(BOARD_POWER_PIN_RELEASE)
   341 │ 	/* deinitialize the POWER pin - with the assumption the hold up time of
   342 │ 	 * the voltage being bleed off by an inupt pin impedance will allow
   343 │ 	 * enough time to boot the app
```
> **说明**：BOARD_VBUS | USB 插入即停住等主机 | 注释掉了（hw_config.h:96） | — | ┃ BOARD_POWER_PIN_OUT / BOARD_POWER_PIN_RELEASE | 掉电保持 / POWER_DOWN_RTC_SIGNATURE 分支 | 未定义 ⇒ main.c:668 与 main.c:340 全裁 | — |
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-340

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-470"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:470`](board-layer.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-470)

```c
   467 │ uint32_t
   468 │ flash_func_sector_size(unsigned sector)
   469 │ {
▶  470 │ 	if (sector <= BOARD_FLASH_SECTORS) {
   471 │ 		return FLASH_SECTOR_SIZE;
   472 │ 	}
   473 │ 
```
> **说明**：:105 | BOARD_FLASH_SIZE | _FLASH_KBYTES * 1024 | main.c:86 | ┃ :104 | BOARD_FLASH_SECTORS | 15 | main.c:470（扇区上界）、:480（擦除上界） |
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-470

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-480"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:480`](board-layer.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-480)

```c
   477 │ void
   478 │ flash_func_erase_sector(unsigned sector, bool force)
   479 │ {
▶  480 │ 	if (sector > BOARD_FLASH_SECTORS || (int)sector < BOARD_FIRST_FLASH_SECTOR_TO_ERASE) {
   481 │ 		return;
   482 │ 	}
   483 │ 
```
> **说明**：:104 | BOARD_FLASH_SECTORS | 15 | main.c:470（扇区上界）、:480（擦除上界） | ┃ :124-126 | BOARD_FIRST_FLASH_SECTOR_TO_ERASE | 1 | main.c:480（跳过扇区 0 = bootloader 自己） |
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-480

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-492"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:492`](board-layer.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-492)

```c
   489 │ void
   490 │ flash_func_write_word(uintptr_t address, uint32_t word)
   491 │ {
▶  492 │ 	address += APP_LOAD_ADDRESS;
   493 │ 	fc_write(address, word);
   494 │ }
   495 │ 
```
> **说明**：:87 | APP_LOAD_ADDRESS | 0x08020000 | bl.c:310（app_base）、main.c:492 / main.c:503（flash 读写的相对↔绝对换算）、fmc.c:60（缓存标签）、ecc_scrub.c:140（扇区基址） |
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-492

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-503"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:503`](board-layer.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-503)

```c
   500 │ 		return 0;
   501 │ 	}
   502 │ 
▶  503 │ 	return fc_read(address + APP_LOAD_ADDRESS);
   504 │ 
   505 │ }
   506 │ 
```
> **说明**：:87 | APP_LOAD_ADDRESS | 0x08020000 | bl.c:310（app_base）、main.c:492 / main.c:503（flash 读写的相对↔绝对换算）、fmc.c:60（缓存标签）、ecc_scrub.c:140（扇区基址） |
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-503

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-641"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:641`](board-layer.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-641)

```c
   638 │ 
   639 │ 	uint32_t scratch;
   640 │ 
▶  641 │ 	/* NuttX 12.12 runs thread mode on the PSP (arm_initialize_stack(), enabled
   642 │ 	 * whenever CONFIG_ARCH_INTERRUPTSTACK > 7). The application expects to start
   643 │ 	 * on the MSP, so select it again before handing over -- otherwise the app
   644 │ 	 * keeps running on the bootloader's stack and faults once it is clobbered.
```
> **说明**：:32 | CONFIG_BOARD_LATE_INITIALIZE=y | ⇒ board_late_initialize() 会被调（起 AppBringUp 线程，nx_bringup.c:436） | ┃ :24 | CONFIG_ARCH_INTERRUPTSTACK=768 | >7 ⇒ NuttX 把线程模式栈切到 PSP ⇒ 这正是 main.c:641 里 arch_do_jump 必须清 CONTROL.SPSEL 的原因 |
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-641

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-668"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:668`](board-layer.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-668)

```c
   665 │ 	/* Enable the FPU before we hit any FP instructions */
   666 │ 	SCB_CPACR |= ((3UL << 10 * 2) | (3UL << 11 * 2)); /* set CP10 Full Access and set CP11 Full Access */
   667 │ 
▶  668 │ #if defined(BOARD_POWER_PIN_OUT)
   669 │ 
   670 │ 	/* Here we check for the app setting the POWER_DOWN_RTC_SIGNATURE
   671 │ 	 * in this case, we reset the signature and wait to die
```
> **说明**：BOARD_VBUS | USB 插入即停住等主机 | 注释掉了（hw_config.h:96） | — | ┃ BOARD_POWER_PIN_OUT / BOARD_POWER_PIN_RELEASE | 掉电保持 / POWER_DOWN_RTC_SIGNATURE 分支 | 未定义 ⇒ main.c:668 与 main.c:340 全裁 | — |
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-668

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-723"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:723`](board-layer.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-723)

```c
   720 │ 		try_boot = false;
   721 │ 	}
   722 │ 
▶  723 │ #if INTERFACE_USB
   724 │ 
   725 │ 	/*
   726 │ 	 * Check for USB connection - if present, don't try to boot, but set a timeout after
```
> **说明**：:94 | INTERFACE_USB | 0 | bl.c:176/193/202/233 四处 USB 分支全裁；main.c:723 VBUS 判断全裁 |
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-723

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-766"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:766`](board-layer.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-766)

```c
   763 │ 	if (try_boot) {
   764 │ 
   765 │ 		/* set the boot-to-bootloader flag so that if boot fails on reset we will stop here */
▶  766 │ #ifdef BOARD_BOOT_FAIL_DETECT
   767 │ 		board_set_rtc_signature(BOOT_RTC_SIGNATURE);
   768 │ #endif
   769 │ 
```
> **说明**：BOARD_POWER_PIN_OUT / BOARD_POWER_PIN_RELEASE | 掉电保持 / POWER_DOWN_RTC_SIGNATURE 分支 | 未定义 ⇒ main.c:668 与 main.c:340 全裁 | — | ┃ BOARD_BOOT_FAIL_DETECT | "跳失败 ⇒ 下次复位停住在 bootloader" | 全仓无定义（只出现在 2 处 #ifdef） | main.c:766 / :819 |
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-766

### `platforms/nuttx/src/bootloader/stm/stm32h7/ecc_scrub.c`
<a id="src-platforms-nuttx-src-bootloader-stm-stm32h7-ecc-scrub-c-140"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32h7/ecc_scrub.c:140`](board-layer.md#^src-platforms-nuttx-src-bootloader-stm-stm32h7-ecc-scrub-c-140)

```c
   137 │ 	const unsigned last_sector = up_progmem_neraseblocks() - 1;
   138 │ 
   139 │ 	for (unsigned sector = BOARD_FIRST_FLASH_SECTOR_TO_ERASE; sector <= last_sector; sector++) {
▶  140 │ 		uintptr_t base = APP_LOAD_ADDRESS + (sector - BOARD_FIRST_FLASH_SECTOR_TO_ERASE) * FLASH_SECTOR_SIZE;
   141 │ 
   142 │ 		if (flash_region_has_ecc_error(base, FLASH_SECTOR_SIZE)) {
   143 │ 			ecc_flags_clear();
```
> **说明**：:87 | APP_LOAD_ADDRESS | 0x08020000 | bl.c:310（app_base）、main.c:492 / main.c:503（flash 读写的相对↔绝对换算）、fmc.c:60（缓存标签）、ecc_scrub.c:140（扇区基址） |
^src-platforms-nuttx-src-bootloader-stm-stm32h7-ecc-scrub-c-140

### `src/lib/drivers/device/qurt/uart.c`
<a id="src-src-lib-drivers-device-qurt-uart-c-53"></a>
**↓ 文档在讲这里：**[`src/lib/drivers/device/qurt/uart.c:53`](board-layer.md#^src-src-lib-drivers-device-qurt-uart-c-53)

```c
    50 │ 
    51 │ 	if (_callbacks_configured && (port_number >= 0)) {
    52 │ 
▶   53 │ 		return _open_uart((uint8_t) port_number, speed);
    54 │ 
    55 │ 	} else {
    56 │ 		PX4_ERR("Cannot open uart until callbacks have been configured");
```
> **说明**：:99 | INTERFACE_USART | 1 | bl.c:183/196/215/240 生效 ⇒ 走 uart.c | ┃ :100 | INTERFACE_USART_CONFIG | "/dev/ttyS0,57600" | uart.c:53 解析成设备名 + 波特率；它覆盖 defconfig 里的 CONFIG_USART1_BAUD=115200 |
^src-src-lib-drivers-device-qurt-uart-c-53
