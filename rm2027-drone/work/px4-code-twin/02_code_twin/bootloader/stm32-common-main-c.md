# `stm/stm32_common/main.c` —— 决定"跳不跳"的那一层

> **源码**：`platforms/nuttx/src/bootloader/stm/stm32_common/main.c`（829 行）
> **层**：② 芯片族（STM32 全系共用，H7 由 `stm32h7/CMakeLists.txt` 追加 `ecc_scrub.c`，见 [02_code_twin/bootloader/cmakelists](cmakelists.md)）
> **进入方式**：被 NuttX 的 `task_spawn("bootloader_main", …)` 拉起（[`nuttx/sched/init/nx_bringup.c:356`](stm32-common-main-c.md#^src-platforms-nuttx-NuttX-nuttx-sched-init-nx-bringup-c-356)），**不是** `main()`——NuttX 会把 `main` 宏改名

---

## 1. 运行时它处在哪

```
NuttX 内核已完全起来（时钟 = 480 MHz，串口驱动已注册，VTOR 已指向 0x08000000）
   └─ 新任务 "bootloader_main" 开始执行  ← main.c:660
         board_init()          :682   ⇒ 唯一实质动作：board_info.fw_size = APP_SIZE_MAX
         clock_init()          :685   ⇒ 【空函数】:388-392，注释 "Done by Nuttx"
         check_ecc_errors()    :689   ⇒ H7 专属，静默擦坏扇区
         ── 4 个决策点 ──
         try_boot 默认 true    :662
```

**关键认知：这一层跑的时候，NuttX 是活着的。** 所以：
- `arch_systic_init()`（[`main.c:365`](stm32-common-main-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-365)）不是"从零配 SysTick"，而是**和 NuttX 自己的 tick 对齐**（重载值同样按 1 ms 算）；
- `clock_init()` 是空函数，因为时钟早在 `__start` 里配好了；
- 上传通道**不是裸寄存器 UART**，而是走 NuttX 的 POSIX 设备节点 `/dev/ttyS0`（见 [02_code_twin/bootloader/uart-c](uart-c.md)）。

---

## 2. 4 个决策点：在本板上逐个求值

| 行号 | 决策 | 上游写法 | **本板的实际值** | 为什么 |
|---|---|---|---|---|
| `:696` | `board_get_rtc_signature() == BOOT_RTC_SIGNATURE` | RTC 备份寄存器 BK0R | **恒 false** | `BOOT_RTC_SIGNATURE` 只在 `#ifdef BOARD_BOOT_FAIL_DETECT` 里被写（`:767`、`:820`），而**全仓 grep `BOARD_BOOT_FAIL_DETECT` 只有这两处 `#ifdef`，没有任何地方 `#define`** ⇒ 本板从不写这个签名 |
| `:719` | `board_test_force_pin()` | 跳线/strapping pin 投票 ≥90% | **恒 false** | `hw_config.h` 里没有 `BOARD_FORCE_BL_PIN` / `BOARD_FORCE_BL_PIN_IN/OUT` ⇒ [`main.c:139`](stm32-common-main-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-139) 的整个函数体被预处理掉，只剩 `return false`（`:191`） |
| `:734` | `px4_arch_gpioread(BOARD_VBUS) != 0` | USB 已插入 | **编译期不存在** | `hw_config.h:94 #define INTERFACE_USB 0` ⇒ [`main.c:723`](stm32-common-main-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-723) 整段被裁掉；`BOARD_VBUS` 也已在 [`hw_config.h:96`](stm32-common-main-c.md#^src-boards-rm2027-fmu-h743-src-hw-config-h-96) 被注释掉 |
| `:756` | `board_test_usart_receiving_break()` | 串口线上收到 break/常低 | **恒 false** | `hw_config.h:114 #define SERIAL_BREAK_DETECT_DISABLED 1` ⇒ [`main.c:197`](stm32-common-main-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-197) 的整段采样逻辑被裁掉，只剩 `return false`（`:254`） |

**⇒ 结论：`try_boot` 永远保持 `true` ⇒ 本板每次上电都**先试跳 app**（`:763`→`:771`）。
bootloader 协议循环只有在"app 跳不成"（`jump_to_app()` 返回）之后才会被碰到。**

> 这正是"为什么上电看不到 bootloader 在等主机"的**唯一原因**——不是没进 bootloader，而是**进来后立刻就把控制权交出去了**。

### 2.1 ★ 上游文档/直觉容易错的两处（已回验）

1. **`board_set_rtc_signature(BOOT_RTC_SIGNATURE)` 在本板是"死代码"。**
   既有素材 `work/PX4-bootloader主流程时序图.md:32/40` 把它列成一个生效的决策点。
   回验结论：它在 `#ifdef BOARD_BOOT_FAIL_DETECT` 内（[`main.c:766`](stm32-common-main-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-766)、`:819-821`），
   本板该宏**未定义** ⇒ `:767`、`:820` 两行不参与编译。
   **后果**：「跳失败 ⇒ 下次复位停住」这条**自愈保护在本板上不存在**——每次复位都会重新尝试跳 app。
2. **RTC 签名那一支仍然存在**（`:696`），但它被触发的路径只剩"app 自己写 `POWER_DOWN_RTC_SIGNATURE`"
   ——而那条路径又在 `#if defined(BOARD_POWER_PIN_OUT)`（`:668-679`）里，本板同样未定义。
   ⇒ **本板 `:696` 的分支事实上永远进不去。**

---

## 3. `fw_size` 是怎么算出来的（并且和 app 的链接脚本不是一个数）

```
main.c:29   BOOTLOADER_RESERVATION_SIZE = 128*1024
main.c:86   APP_SIZE_MAX = BOARD_FLASH_SIZE - (BOOTLOADER_RESERVATION_SIZE + APP_RESERVATION_SIZE)
main.c:274  board_info.fw_size = APP_SIZE_MAX           ← board_init() 里赋值
hw_config.h:105  BOARD_FLASH_SIZE = _FLASH_KBYTES * 1024
hw_config.h:103  _FLASH_KBYTES    = *(uint32_t *)0x1FF1E880
hw_config.h:120-122  #if !defined(APP_RESERVATION_SIZE) → 0
```

**求证 `APP_RESERVATION_SIZE` 真的是 0**（不是被 CMake 传进来的）：
`build/rm2027_fmu-h743_bootloader/compile_commands.json` 里 `stm32_common/main.c` 的编译命令
**没有** `-DAPP_RESERVATION_SIZE`。⇒ 取默认 0。

**于是本板（`_FLASH_KBYTES` 按 2048 推）**：

| 量 | 值 | 依据 |
|---|---|---|
| `BOARD_FLASH_SIZE` | 2048 × 1024 = **2 MiB** | [`hw_config.h:105`](stm32-common-main-c.md#^src-boards-rm2027-fmu-h743-src-hw-config-h-105) |
| `APP_SIZE_MAX` = `fw_size` | 2 MiB − 128 KiB = **1920 KiB**（= flash 扇区 1..15） | [`main.c:86`](stm32-common-main-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-86) / `:274` |
| 擦除循环实际扫到 | `flash_func_sector_size(i) != 0` 时 `i ≤ BOARD_FLASH_SECTORS(15)`；`flash_func_erase_sector` 又跳过 `i < BOARD_FIRST_FLASH_SECTOR_TO_ERASE(1)` ⇒ **扇区 1..15** | [`bl.c:777`](stm32-common-main-c.md#^src-platforms-nuttx-src-bootloader-common-bl-c-777)、[`main.c:467`](stm32-common-main-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-467)、[`main.c:477`](stm32-common-main-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-477)、[`hw_config.h:104`](stm32-common-main-c.md#^src-boards-rm2027-fmu-h743-src-hw-config-h-104)、[`hw_config.h:124`](stm32-common-main-c.md#^src-boards-rm2027-fmu-h743-src-hw-config-h-124) |
| **而 app 自己的链接脚本说** | app 占 `0x08020000` 起 **1792 KiB**（扇区 1..14），**最后 1 个扇区 `0x081E0000` 留给 flash 参数** | [`nuttx-config/scripts/script.ld:113`](stm32-common-main-c.md#^src-boards-rm2027-fmu-h743-nuttx-config-scripts-script-ld-113) + 同文件注释 |
| app 侧确认参数放 flash | `#define FLASH_BASED_PARAMS` | [`src/board_config.h:60`](../params/param-system.md#^src-boards-rm2027-fmu-h743-src-board-config-h-60) |

### ⇒ 这是一个真实的"三处同源"不一致（**推理，需上板判**）

- **bootloader 认为** app 区 = 扇区 1..15（含参数扇区）
- **app 链接脚本认为** app 区 = 扇区 1..14，参数独占扇区 15
- 差 **正好一个 128 KiB 扇区**

**判据（可执行，不需要改任何代码）**：
1. 上位机 `GET_DEVICE / arg=4(FW_SIZE)` 回读的 4 字节 ÷ 1024 = ？
   - `1920` ⇒ 按 [`main.c:86`](stm32-common-main-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-86) 走，与本推导一致
   - `1792` ⇒ 说明我漏了某个 `-DAPP_RESERVATION_SIZE=131072`（我已在 `compile_commands.json` 里查过，**没有**）
2. 更硬的一条：**刷一次固件之后再读参数**。
   [`bl.c:777`](stm32-common-main-c.md#^src-platforms-nuttx-src-bootloader-common-bl-c-777) 的擦除循环覆盖扇区 1..15 ⇒ 若参数区在扇区 15，**刷完固件参数应当回默认**；
   若参数没丢，说明擦除没覆盖到扇区 15（即我对 `BOARD_FLASH_SECTORS` 语义的理解有误）。

> ⚠️ **本节数值标"源码推导"，不是实测。** `_FLASH_KBYTES` 用 **32 位**读 `0x1FF1E880`
> （该处按 ST 参考手册是 16 位 flash size 寄存器），高 16 位取值我**没有核实**。
> 详见 [01_extracted/stm32/flash-layout](../../01_extracted/stm32/flash-layout.md)。

---

## 4. 决策之后的两条路（执行序）

### 4.1 `try_boot == true`（本板的常态）

```
:763 if (try_boot) {
:771     jump_to_app();                 ← ①层 bl.c:308，成功则永不返回
:774     board_set_rtc_signature(...)   ← 被 BOARD_BOOT_FAIL_DETECT 裁掉，本板不执行
:777     timeout = 0;                  ← 跳失败 ⇒ 本次上电不再自动超时
     }
:783 cinit(BOARD_INTERFACE_CONFIG_USART, USART);   ← 打开 /dev/ttyS0（本板唯一通道）
:800 while (1) {
:802     bootloader(timeout);          ← ①层 bl.c:624（timeout 此时为 0 ⇒ 无限等）
:805     if (board_test_force_pin()) continue;      ← 恒 false
:812     if (board_test_usart_receiving_break()) continue;  ← 被裁掉
:820     board_set_rtc_signature(...)  ← 被裁掉
:824     jump_to_app();                ← 主机上传完 / 或超时后再试
:827     timeout = 0;
     }
```

### 4.2 `jump_to_app()` 里面那条链（合起来才是"跳成功"的完整判据）

见 [02_code_twin/bootloader/bl-c](bl-c.md) §"jump_to_app 校验链"。
②层在这里只提供**两个原子动作**：

| 行号 | 动作 | 干了什么 |
|---|---|---|
| `main.c:457-460 arch_setvtor()` | `putreg32((uint32_t)address, NVIC_VECTAB)` | 把 VTOR 从 bootloader 的向量表（`0x08000000`）切到 app 的（`0x08020000`） |
| `main.c:632-657 arch_do_jump()` | 内联汇编 5 条 | `app_base[0]` → MSP；`app_base[1]` → `bx`；**并且先把 CONTROL 寄存器的 SPSEL 位清 0**，因为 NuttX 12.x 下线程模式跑在 PSP（`:641-645` 注释原文），不切回 MSP 的话 app 会继续用 bootloader 的栈，然后崩 |

> **本节两条是"跳 app"能成功的最硬条件**，也是本板上唯一能解释"为什么必须 `arch_systic_deinit()` + `clock_deinit()` + `board_deinit()`"
> 的地方——①层在 [`bl.c:414`](stm32-common-main-c.md#^src-platforms-nuttx-src-bootloader-common-bl-c-414) 按固定顺序调它们，**顺序错一个就会丢中断或带错时钟进 app**。

### 4.3 其它被 ②层实现、但本板走不到的东西

| 行号 | 内容 | 本板状态 |
|---|---|---|
| `main.c:559-562 check_silicon()` | 恒 `return 0` | 调用点 [`bl.c:760`](stm32-common-main-c.md#^src-platforms-nuttx-src-bootloader-common-bl-c-760)、`main.c:760/846` 都在 `#if defined(TARGET_HW_PX4_FMU_V4)` 内 ⇒ **本板不编** |
| `main.c:494-505 bad_silicon_response()` | H7 上被裁 | 同上 |
| `main.c:508-512 flash_func_read_otp()` | 恒 `return 0` | `PROTO_GET_OTP`（[`bl.c:923`](stm32-common-main-c.md#^src-platforms-nuttx-src-bootloader-common-bl-c-923)）会恒定回 0 |
| `main.c:682 board_init()` 里 `BOARD_POWER_PIN_OUT` / `BOARD_VBUS` / `BOARD_FORCE_BL_PIN*` 段 | 本板全未定义 | [`main.c:276`](stm32-common-main-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-276) 里只剩 LED 配置生效 |
| `main.c:317-363 board_deinit()` | 反初始化 | 本板生效段只有 `:348-355`（把 LED 脚切回输入）+ `:361-362`（清 RCC AHB1 复位/使能） |

---

## 5. "我看到的现象由谁产生"

| 现象 | 产生者 | 依据 |
|---|---|---|
| 上电后**看不到**任何 bootloader 等待，直接跑 app | `try_boot` 恒 true ⇒ `:771` | 本篇 §2 |
| 刷固件后**参数全丢** | [`bl.c:777`](stm32-common-main-c.md#^src-platforms-nuttx-src-bootloader-common-bl-c-777) 擦到扇区 15（含参数区） | `hw_config.h:104/124-126`（**推理，判据见 §3**） |
| 上传超时"自己跑了" | `:663 timeout = BOOTLOADER_DELAY = 5000` → [`bl.c:655`](uart-c.md#^src-platforms-nuttx-src-bootloader-common-bl-c-655) | [`hw_config.h:88`](stm32-common-main-c.md#^src-boards-rm2027-fmu-h743-src-hw-config-h-88) |
| 跳 app 失败后**灯一直闪不再自动跳** | `:777` / `:827 timeout = 0` | — |
| 参数莫名回默认（即使没刷固件） | `:689 check_ecc_errors()` 静默擦坏扇区 | [02_code_twin/bootloader/ecc-scrub-c](ecc-scrub-c.md) |
| app 一启动就跑在 PSP 上 / 进 app 后 hardfault | `arch_do_jump` 的 CONTROL 清位是否生效 | [`main.c:646`](stm32-common-main-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-646) |

---

## 跳转

- **执行序下一步**：`jump_to_app()` 成功 ⇒ 控制权交回 app；`bootloader_main` 返回后 ⇒ 进①层协议循环。
  ①层的展开 → [02_code_twin/bootloader/bl-c](bl-c.md)。
- `jump_to_app()` 内部调的两个②层原语的**硬件语义** → [01_extracted/stm32/vtor-vector-tables](../../01_extracted/stm32/vtor-vector-tables.md)。
- `fw_size` 与扇区布局的完整推导、以及"三处同源"欠账 → [01_extracted/stm32/flash-layout](../../01_extracted/stm32/flash-layout.md)。
- 想搞清"为什么这段代码跑起来时 NuttX 已经活着" → [01_extracted/nuttx/00-poweron-chain](../../01_extracted/nuttx/00-poweron-chain.md)。
- ③层（本板）给这一层填了哪些宏 → [02_code_twin/bootloader/board-layer](board-layer.md)。

---

## 未核实

- `BOARD_FLASH_SECTORS (15)` 的**语义**我按"允许的最大扇区索引（0-based）"理解，
  依据是 `main.c:470 if (sector <= BOARD_FLASH_SECTORS)` 这个上界写法 + [`hw_config.h:59`](stm32-common-main-c.md#^src-boards-rm2027-fmu-h743-src-hw-config-h-59) 的注释
  *"Hard coded zero based last sector"*。⇒ 扇区数 = 16。**未上板核实**。
- `_FLASH_KBYTES` 实际读到的值（见 §3 警告）。
- [`main.c:713`](stm32-common-main-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-713)（RTC 签名分支内的几行）我只确认了 `:712 board_set_rtc_signature(0)` 与 `:719` 的位置关系，未逐行展开。

---

## 标注源码（代码 + 本文档对它的解释）

> **这是「代码孪生」层**：上面是代码原文（带行号），下面是**本文档针对这一段说的话**。
> 行号可点，直接跳到 PX4 源码那一行。
### `boards/rm2027/fmu-h743/nuttx-config/scripts/script.ld`
<a id="src-boards-rm2027-fmu-h743-nuttx-config-scripts-script-ld-113"></a>
**↓ 文档在讲这里：**[`boards/rm2027/fmu-h743/nuttx-config/scripts/script.ld:113`](stm32-common-main-c.md#^src-boards-rm2027-fmu-h743-nuttx-config-scripts-script-ld-113)

```c
   110 │ MEMORY
   111 │ {
   112 │ 	ITCM_RAM  (rwx) : ORIGIN = 0x00000000, LENGTH =   64K
▶  113 │ 	FLASH      (rx) : ORIGIN = 0x08020000, LENGTH = 1792K /* ★ 最后 1 个 128K 扇区(0x081E0000)让给 flash 参数存储，见 src/init.c */
   114 │ 
   115 │ 	DTCM1_RAM (rwx) : ORIGIN = 0x20000000, LENGTH =   64K
   116 │ 	DTCM2_RAM (rwx) : ORIGIN = 0x20010000, LENGTH =   64K
```
> **说明**：擦除循环实际扫到 | flash_func_sector_size(i) != 0 时 i ≤ BOARD_FLASH_SECTORS(15)；flash_func_erase_sector 又跳过 i < BOARD_FIRST_FLASH_SECTOR_TO_ERASE(1) ⇒ 扇区 1..15 | bl.c:777、main.c:467、main.c:477、hw_config.h:104 ┃ 而 app 自己的链接脚本说 | app 占 0x08020000 起 1792 KiB（扇区 1..14），最后 1 个扇区 0x081E0000 留给 flash 参数 | nuttx-config/scripts/script.ld:113 + 同文件注释 |
^src-boards-rm2027-fmu-h743-nuttx-config-scripts-script-ld-113

### `boards/rm2027/fmu-h743/src/board_config.h`
<a id="src-boards-rm2027-fmu-h743-src-board-config-h-60"></a>
**↓ 文档在讲这里：**[`boards/rm2027/fmu-h743/src/board_config.h:60`](stm32-common-main-c.md#^src-boards-rm2027-fmu-h743-src-board-config-h-60)

```c
    57 │ //   不开这个 ⇒ 每次上电参数全丢、标定白做。故开启片内 flash 存参数，
    58 │ //   占用最后一个 128K 扇区 0x081E0000（配套 script.ld 的 FLASH LENGTH 1792K）。
    59 │ //   详见 src/init.c 里 params_sector_map 的注释。
▶   60 │ #define FLASH_BASED_PARAMS
    61 │ 
    62 │ 
    63 │ /* ============================================================================
```
> **说明**：而 app 自己的链接脚本说 | app 占 0x08020000 起 1792 KiB（扇区 1..14），最后 1 个扇区 0x081E0000 留给 flash 参数 | nuttx-config/scripts/script.ld:113 + 同文件注释 | ┃ app 侧确认参数放 flash | #define FLASH_BASED_PARAMS | src/board_config.h:60 |
^src-boards-rm2027-fmu-h743-src-board-config-h-60

### `boards/rm2027/fmu-h743/src/hw_config.h`
<a id="src-boards-rm2027-fmu-h743-src-hw-config-h-59"></a>
**↓ 文档在讲这里：**[`boards/rm2027/fmu-h743/src/hw_config.h:59`](stm32-common-main-c.md#^src-boards-rm2027-fmu-h743-src-hw-config-h-59)

```c
    56 │  * BOARD_TYPE           9                     - Must match .prototype boad_id
    57 │  * _FLASH_KBYTES        (*(uint16_t *)0x1fff7a22) - Run time flash size detection
    58 │  * BOARD_FLASH_SECTORS  ((_FLASH_KBYTES == 0x400) ? 11 : 23) - Run time determine the physical last sector
▶   59 │  * BOARD_FLASH_SECTORS   11                   - Hard coded zero based last sector
    60 │  * BOARD_FLASH_SIZE     (_FLASH_KBYTES*1024)-   Total Flash size of device, determined at run time.
    61 │  *                         (1024 * 1024)      - Hard coded Total Flash of device - The bootloader and app reserved will be deducted
    62 │  *                                              programmatically
```
> **说明**：BOARD_FLASH_SECTORS (15) 的语义我按"允许的最大扇区索引（0-based）"理解， ┃ 依据是 main.c:470 if (sector <= BOARD_FLASH_SECTORS) 这个上界写法 + hw_config.h:59 的注释
^src-boards-rm2027-fmu-h743-src-hw-config-h-59

<a id="src-boards-rm2027-fmu-h743-src-hw-config-h-88"></a>
**↓ 文档在讲这里：**[`boards/rm2027/fmu-h743/src/hw_config.h:88`](stm32-common-main-c.md#^src-boards-rm2027-fmu-h743-src-hw-config-h-88)

```c
    85 │ #define SERIAL1_DEV    0x04
    86 │ 
    87 │ #define APP_LOAD_ADDRESS               0x08020000
▶   88 │ #define BOOTLOADER_DELAY               5000
    89 │ /* ★ 本板（rm2027/fmu-h743）**没有 USB 硬件**
    90 │  *   → 关掉 USB 上传通道，只用串口通道上传固件
    91 │  *   → 串口通道模板板就有（/dev/ttyS0,57600 = USART1 = ttyS0）
```
> **说明**：刷固件后参数全丢 | bl.c:777 擦到扇区 15（含参数区） | hw_config.h:104/124-126（推理，判据见 §3） | ┃ 上传超时"自己跑了" | :663 timeout = BOOTLOADER_DELAY = 5000 → bl.c:655 | hw_config.h:88 |
^src-boards-rm2027-fmu-h743-src-hw-config-h-88

<a id="src-boards-rm2027-fmu-h743-src-hw-config-h-96"></a>
**↓ 文档在讲这里：**[`boards/rm2027/fmu-h743/src/hw_config.h:96`](stm32-common-main-c.md#^src-boards-rm2027-fmu-h743-src-hw-config-h-96)

```c
    93 │  */
    94 │ #define INTERFACE_USB                  0
    95 │ // #define INTERFACE_USB_CONFIG        "/dev/ttyACM0"
▶   96 │ // #define BOARD_VBUS                  MK_GPIO_INPUT(GPIO_OTGFS_VBUS)   /* 本板无 VBUS 检测脚 */
    97 │ 
    98 │ //#define USE_VBUS_PULL_DOWN
    99 │ #define INTERFACE_USART                1
```
> **说明**：:719 | board_test_force_pin() | 跳线/strapping pin 投票 ≥90% | 恒 false | hw_config.h 里没有 BOARD_FORCE_BL_PIN / BOARD_FORCE_BL_PIN_IN/OUT ⇒ main.c:139 的整个函数体被预处理掉，只剩 return false（:191） | ┃ :734 | px4_arch_gpioread(BOARD_VBUS) != 0 | USB 已插入 | 编译期不存在 | hw_config.h:94 #define INTERFACE_USB 0 ⇒ main.c:723 整段被裁掉；BOARD_VBUS 也已在 hw_config.h:96 被注释掉 |
^src-boards-rm2027-fmu-h743-src-hw-config-h-96

<a id="src-boards-rm2027-fmu-h743-src-hw-config-h-104"></a>
**↓ 文档在讲这里：**[`boards/rm2027/fmu-h743/src/hw_config.h:104`](stm32-common-main-c.md#^src-boards-rm2027-fmu-h743-src-hw-config-h-104)

```c
   101 │ /* ★ 必须与 firmware.prototype 的 board_id 一致（本板 = 2027） */
   102 │ #define BOARD_TYPE                     2027
   103 │ #define _FLASH_KBYTES                  (*(uint32_t *)0x1FF1E880)
▶  104 │ #define BOARD_FLASH_SECTORS            (15)
   105 │ #define BOARD_FLASH_SIZE               (_FLASH_KBYTES * 1024)
   106 │ 
   107 │ #define OSC_FREQ                       8
```
> **说明**：APP_SIZE_MAX = fw_size | 2 MiB − 128 KiB = 1920 KiB（= flash 扇区 1..15） | main.c:86 / :274 | ┃ 擦除循环实际扫到 | flash_func_sector_size(i) != 0 时 i ≤ BOARD_FLASH_SECTORS(15)；flash_func_erase_sector 又跳过 i < BOARD_FIRST_FLASH_SECTOR_TO_ERASE(1) ⇒ 扇区 1..15 | bl.c:777、main.c:467、main.c:477、hw_config.h:104
^src-boards-rm2027-fmu-h743-src-hw-config-h-104

<a id="src-boards-rm2027-fmu-h743-src-hw-config-h-105"></a>
**↓ 文档在讲这里：**[`boards/rm2027/fmu-h743/src/hw_config.h:105`](stm32-common-main-c.md#^src-boards-rm2027-fmu-h743-src-hw-config-h-105)

```c
   102 │ #define BOARD_TYPE                     2027
   103 │ #define _FLASH_KBYTES                  (*(uint32_t *)0x1FF1E880)
   104 │ #define BOARD_FLASH_SECTORS            (15)
▶  105 │ #define BOARD_FLASH_SIZE               (_FLASH_KBYTES * 1024)
   106 │ 
   107 │ #define OSC_FREQ                       8
   108 │ 
```
> **说明**：BOARD_FLASH_SIZE | 2048 × 1024 = 2 MiB | hw_config.h:105 |
^src-boards-rm2027-fmu-h743-src-hw-config-h-105

<a id="src-boards-rm2027-fmu-h743-src-hw-config-h-124"></a>
**↓ 文档在讲这里：**[`boards/rm2027/fmu-h743/src/hw_config.h:124`](stm32-common-main-c.md#^src-boards-rm2027-fmu-h743-src-hw-config-h-124)

```c
   121 │ #  define APP_RESERVATION_SIZE 0
   122 │ #endif
   123 │ 
▶  124 │ #if !defined(BOARD_FIRST_FLASH_SECTOR_TO_ERASE)
   125 │ #  define BOARD_FIRST_FLASH_SECTOR_TO_ERASE 1
   126 │ #endif
   127 │ 
```
> **说明**：APP_SIZE_MAX = fw_size | 2 MiB − 128 KiB = 1920 KiB（= flash 扇区 1..15） | main.c:86 / :274 | ┃ 擦除循环实际扫到 | flash_func_sector_size(i) != 0 时 i ≤ BOARD_FLASH_SECTORS(15)；flash_func_erase_sector 又跳过 i < BOARD_FIRST_FLASH_SECTOR_TO_ERASE(1) ⇒ 扇区 1..15 | bl.c:777、main.c:467、main.c:477、hw_config.h:104
^src-boards-rm2027-fmu-h743-src-hw-config-h-124

### `platforms/nuttx/NuttX/nuttx/sched/init/nx_bringup.c`
<a id="src-platforms-nuttx-NuttX-nuttx-sched-init-nx-bringup-c-356"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/NuttX/nuttx/sched/init/nx_bringup.c:356`](stm32-common-main-c.md#^src-platforms-nuttx-NuttX-nuttx-sched-init-nx-bringup-c-356)

```c
   353 │                    USERSPACE->us_entrypoint,
   354 │                    NULL, &attr, argv, NULL);
   355 │ #  else
▶  356 │   ret = task_spawn(CONFIG_INIT_ENTRYNAME,
   357 │                    CONFIG_INIT_ENTRYPOINT,
   358 │                    NULL, &attr, argv, NULL);
   359 │ #  endif
```
> **说明**：层：② 芯片族（STM32 全系共用，H7 由 stm32h7/CMakeLists.txt 追加 ecc_scrub.c，见 02_code_twin/bootloader/cmakelists） ┃ 进入方式：被 NuttX 的 task_spawn("bootloader_main", …) 拉起（nuttx/sched/init/nx_bringup.c:356），不是 main()——NuttX 会把 main 宏改名
^src-platforms-nuttx-NuttX-nuttx-sched-init-nx-bringup-c-356

### `platforms/nuttx/src/bootloader/common/bl.c`
<a id="src-platforms-nuttx-src-bootloader-common-bl-c-308"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:308`](stm32-common-main-c.md#^src-platforms-nuttx-src-bootloader-common-bl-c-308)

```c
   305 │ }
   306 │ 
   307 │ void
▶  308 │ jump_to_app()
   309 │ {
   310 │ 	const uint32_t *app_base = (const uint32_t *)APP_LOAD_ADDRESS;
   311 │ 	const uint32_t *vec_base = (const uint32_t *)((const uint32_t)app_base + APP_VECTOR_OFFSET);
```
> **说明**：:771 jump_to_app(); ← ①层 bl.c:308，成功则永不返回
^src-platforms-nuttx-src-bootloader-common-bl-c-308

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-414"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:414`](stm32-common-main-c.md#^src-platforms-nuttx-src-bootloader-common-bl-c-414)

```c
   411 │ #endif
   412 │ 
   413 │ 	/* just for paranoia's sake */
▶  414 │ 	arch_flash_lock();
   415 │ 
   416 │ 	/* kill the systick interrupt */
   417 │ 	arch_systic_deinit();
```
> **说明**：本节两条是"跳 app"能成功的最硬条件，也是本板上唯一能解释"为什么必须 arch_systic_deinit() + clock_deinit() + board_deinit()" ┃ 的地方——①层在 bl.c:414 按固定顺序调它们，顺序错一个就会丢中断或带错时钟进 app。
^src-platforms-nuttx-src-bootloader-common-bl-c-414

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-624"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:624`](stm32-common-main-c.md#^src-platforms-nuttx-src-bootloader-common-bl-c-624)

```c
   621 │ }
   622 │ 
   623 │ void
▶  624 │ bootloader(unsigned timeout)
   625 │ {
   626 │ 	bl_type = NONE; // The type of the bootloader, whether loading from USB or USART, will be determined by on what port the bootloader recevies its first valid command.
   627 │ 	volatile uint32_t  bl_state = 0; // Must see correct command sequence to erase and reboot (commit first word)
```
> **说明**：:802 bootloader(timeout); ← ①层 bl.c:624（timeout 此时为 0 ⇒ 无限等）
^src-platforms-nuttx-src-bootloader-common-bl-c-624

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-655"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:655`](stm32-common-main-c.md#^src-platforms-nuttx-src-bootloader-common-bl-c-655)

```c
   652 │ 
   653 │ 		do {
   654 │ 			/* if we have a timeout and the timer has expired, return now */
▶  655 │ 			if (timeout && !timer[TIMER_BL_WAIT]) {
   656 │ 				return;
   657 │ 			}
   658 │ 
```
> **说明**：刷固件后参数全丢 | bl.c:777 擦到扇区 15（含参数区） | hw_config.h:104/124-126（推理，判据见 §3） | ┃ 上传超时"自己跑了" | :663 timeout = BOOTLOADER_DELAY = 5000 → bl.c:655 | hw_config.h:88 |
^src-platforms-nuttx-src-bootloader-common-bl-c-655

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-760"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:760`](stm32-common-main-c.md#^src-platforms-nuttx-src-bootloader-common-bl-c-760)

```c
   757 │ 
   758 │ #if defined(TARGET_HW_PX4_FMU_V4)
   759 │ 
▶  760 │ 			if (check_silicon()) {
   761 │ 				goto bad_silicon;
   762 │ 			}
   763 │ 
```
> **说明**：main.c:559-562 check_silicon() | 恒 return 0 | 调用点 bl.c:760、main.c:760/846 都在 #if defined(TARGET_HW_PX4_FMU_V4) 内 ⇒ 本板不编 |
^src-platforms-nuttx-src-bootloader-common-bl-c-760

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-777"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:777`](stm32-common-main-c.md#^src-platforms-nuttx-src-bootloader-common-bl-c-777)

```c
   774 │ 			// erase all sectors
   775 │ 			arch_flash_unlock();
   776 │ 
▶  777 │ 			for (int i = 0; flash_func_sector_size(i) != 0; i++) {
   778 │ 				flash_func_erase_sector(i, full_erase);
   779 │ 			}
   780 │ 
```
> **说明**：APP_SIZE_MAX = fw_size | 2 MiB − 128 KiB = 1920 KiB（= flash 扇区 1..15） | main.c:86 / :274 | ┃ 擦除循环实际扫到 | flash_func_sector_size(i) != 0 时 i ≤ BOARD_FLASH_SECTORS(15)；flash_func_erase_sector 又跳过 i < BOARD_FIRST_FLASH_SECTOR_TO_ERASE(1) ⇒ 扇区 1..15 | bl.c:777、main.c:467、main.c:477、hw_config.h:104
> **说明**：2. 更硬的一条：刷一次固件之后再读参数。 ┃ bl.c:777 的擦除循环覆盖扇区 1..15 ⇒ 若参数区在扇区 15，刷完固件参数应当回默认；
^src-platforms-nuttx-src-bootloader-common-bl-c-777

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-923"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:923`](stm32-common-main-c.md#^src-platforms-nuttx-src-bootloader-common-bl-c-923)

```c
   920 │ 		//
   921 │ 		// command:     GET_OTP/<addr:4>/EOC
   922 │ 		// reply:     <value:4>/INSYNC/OK
▶  923 │ 		case PROTO_GET_OTP:
   924 │ 			// expect argument
   925 │ 			{
   926 │ 				uint32_t index = 0;
```
> **说明**：main.c:494-505 bad_silicon_response() | H7 上被裁 | 同上 | ┃ main.c:508-512 flash_func_read_otp() | 恒 return 0 | PROTO_GET_OTP（bl.c:923）会恒定回 0 |
^src-platforms-nuttx-src-bootloader-common-bl-c-923

### `platforms/nuttx/src/bootloader/stm/stm32_common/main.c`
<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-29"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:29`](stm32-common-main-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-29)

```c
    26 │ 
    27 │ #define MK_GPIO_INPUT(def) (((def) & (GPIO_PORT_MASK | GPIO_PIN_MASK)) | (GPIO_INPUT))
    28 │ 
▶   29 │ #define BOOTLOADER_RESERVATION_SIZE	(128 * 1024)
    30 │ 
    31 │ //STM DocID018909 Rev 8 Sect 38.18 and DocID026670 Rev 5 40.6.1 (MCU device ID code)
    32 │ # define REVID_MASK    0xFFFF0000
```
> **说明**：main.c:29 BOOTLOADER_RESERVATION_SIZE = 128*1024
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-29

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-86"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:86`](stm32-common-main-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-86)

```c
    83 │ # error "APP_RESERVATION_SIZE must be greater than 0 if FLASH_BASED_PARAMS is defined"
    84 │ #endif
    85 │ 
▶   86 │ #define APP_SIZE_MAX			(BOARD_FLASH_SIZE - (BOOTLOADER_RESERVATION_SIZE + APP_RESERVATION_SIZE))
    87 │ 
    88 │ 
    89 │ /* context passed to cinit */
```
> **说明**：main.c:86 APP_SIZE_MAX = BOARD_FLASH_SIZE - (BOOTLOADER_RESERVATION_SIZE + APP_RESERVATION_SIZE)
> **说明**：BOARD_FLASH_SIZE | 2048 × 1024 = 2 MiB | hw_config.h:105 | ┃ APP_SIZE_MAX = fw_size | 2 MiB − 128 KiB = 1920 KiB（= flash 扇区 1..15） | main.c:86 / :274 |
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-86

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-139"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:139`](stm32-common-main-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-139)

```c
   136 │ 
   137 │ }
   138 │ 
▶  139 │ static bool board_test_force_pin(void)
   140 │ {
   141 │ #if defined(BOARD_FORCE_BL_PIN_IN) && defined(BOARD_FORCE_BL_PIN_OUT)
   142 │ 	/* two pins strapped together */
```
> **说明**：:696 | board_get_rtc_signature() == BOOT_RTC_SIGNATURE | RTC 备份寄存器 BK0R | 恒 false | BOOT_RTC_SIGNATURE 只在 #ifdef BOARD_BOOT_FAIL_DETECT 里被写（:767、:820），而全仓 grep BOARD_BOOT_FAIL_DETECT 只有这两处 #ifdef，没有任何 ┃ :719 | board_test_force_pin() | 跳线/strapping pin 投票 ≥90% | 恒 false | hw_config.h 里没有 BOARD_FORCE_BL_PIN / BOARD_FORCE_BL_PIN_IN/OUT ⇒ main.c:139 的整个函数体被预处理掉，只剩 return false（:191） |
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-139

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-197"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:197`](stm32-common-main-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-197)

```c
   194 │ #if INTERFACE_USART
   195 │ static bool board_test_usart_receiving_break(void)
   196 │ {
▶  197 │ #if !defined(SERIAL_BREAK_DETECT_DISABLED)
   198 │ 	/* (re)start the SysTick timer system */
   199 │ 	systick_interrupt_disable(); // Kill the interrupt if it is still active
   200 │ 	systick_counter_disable(); // Stop the timer
```
> **说明**：:734 | px4_arch_gpioread(BOARD_VBUS) != 0 | USB 已插入 | 编译期不存在 | hw_config.h:94 #define INTERFACE_USB 0 ⇒ main.c:723 整段被裁掉；BOARD_VBUS 也已在 hw_config.h:96 被注释掉 | ┃ :756 | board_test_usart_receiving_break() | 串口线上收到 break/常低 | 恒 false | hw_config.h:114 #define SERIAL_BREAK_DETECT_DISABLED 1 ⇒ main.c:197 的整段采样逻辑被裁掉，只剩 return false（:254） |
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-197

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-274"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:274`](stm32-common-main-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-274)

```c
   271 │ board_init(void)
   272 │ {
   273 │ 	/* fix up the max firmware size, we have to read memory to get this */
▶  274 │ 	board_info.fw_size = APP_SIZE_MAX;
   275 │ 
   276 │ #if defined(BOARD_POWER_PIN_OUT)
   277 │ 	/* Configure the Power pins */
```
> **说明**：main.c:274 board_info.fw_size = APP_SIZE_MAX ← board_init() 里赋值
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-274

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-276"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:276`](stm32-common-main-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-276)

```c
   273 │ 	/* fix up the max firmware size, we have to read memory to get this */
   274 │ 	board_info.fw_size = APP_SIZE_MAX;
   275 │ 
▶  276 │ #if defined(BOARD_POWER_PIN_OUT)
   277 │ 	/* Configure the Power pins */
   278 │ 	px4_arch_configgpio(BOARD_POWER_PIN_OUT);
   279 │ 	px4_arch_gpiowrite(BOARD_POWER_PIN_OUT, BOARD_POWER_ON);
```
> **说明**：main.c:508-512 flash_func_read_otp() | 恒 return 0 | PROTO_GET_OTP（bl.c:923）会恒定回 0 | ┃ main.c:682 board_init() 里 BOARD_POWER_PIN_OUT / BOARD_VBUS / BOARD_FORCE_BL_PIN* 段 | 本板全未定义 | main.c:276 里只剩 LED 配置生效 |
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-276

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-365"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:365`](stm32-common-main-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-365)

```c
   362 │ 	putreg32(0, STM32_RCC_AHB1ENR);
   363 │ }
   364 │ 
▶  365 │ inline void arch_systic_init(void)
   366 │ {
   367 │ 	/* (re)start the timer system */
   368 │ 	systick_set_clocksource(CLKSOURCE_PROCESOR);
```
> **说明**：关键认知：这一层跑的时候，NuttX 是活着的。 所以： ┃ arch_systic_init()（main.c:365）不是"从零配 SysTick"，而是和 NuttX 自己的 tick 对齐（重载值同样按 1 ms 算）；
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-365

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-467"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:467`](stm32-common-main-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-467)

```c
   464 │ #define FLASH_SECTOR_SIZE   (128u * 1024u)
   465 │ #endif
   466 │ 
▶  467 │ uint32_t
   468 │ flash_func_sector_size(unsigned sector)
   469 │ {
   470 │ 	if (sector <= BOARD_FLASH_SECTORS) {
```
> **说明**：APP_SIZE_MAX = fw_size | 2 MiB − 128 KiB = 1920 KiB（= flash 扇区 1..15） | main.c:86 / :274 | ┃ 擦除循环实际扫到 | flash_func_sector_size(i) != 0 时 i ≤ BOARD_FLASH_SECTORS(15)；flash_func_erase_sector 又跳过 i < BOARD_FIRST_FLASH_SECTOR_TO_ERASE(1) ⇒ 扇区 1..15 | bl.c:777、main.c:467、main.c:477、hw_config.h:104
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-467

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-477"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:477`](stm32-common-main-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-477)

```c
   474 │ 	return 0;
   475 │ }
   476 │ 
▶  477 │ void
   478 │ flash_func_erase_sector(unsigned sector, bool force)
   479 │ {
   480 │ 	if (sector > BOARD_FLASH_SECTORS || (int)sector < BOARD_FIRST_FLASH_SECTOR_TO_ERASE) {
```
> **说明**：APP_SIZE_MAX = fw_size | 2 MiB − 128 KiB = 1920 KiB（= flash 扇区 1..15） | main.c:86 / :274 | ┃ 擦除循环实际扫到 | flash_func_sector_size(i) != 0 时 i ≤ BOARD_FLASH_SECTORS(15)；flash_func_erase_sector 又跳过 i < BOARD_FIRST_FLASH_SECTOR_TO_ERASE(1) ⇒ 扇区 1..15 | bl.c:777、main.c:467、main.c:477、hw_config.h:104
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-477

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-646"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:646`](stm32-common-main-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-646)

```c
   643 │ 	 * on the MSP, so select it again before handing over -- otherwise the app
   644 │ 	 * keeps running on the bootloader's stack and faults once it is clobbered.
   645 │ 	 */
▶  646 │ 	asm volatile(
   647 │ 		"mrs %0, control  \n"
   648 │ 		"bic %0, %0, #2   \n"
   649 │ 		"msr control, %0  \n"
```
> **说明**：参数莫名回默认（即使没刷固件） | :689 check_ecc_errors() 静默擦坏扇区 | 02_code_twin/bootloader/ecc-scrub-c | ┃ app 一启动就跑在 PSP 上 / 进 app 后 hardfault | arch_do_jump 的 CONTROL 清位是否生效 | main.c:646 |
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-646

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-660"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:660`](stm32-common-main-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-660)

```c
   657 │ }
   658 │ 
   659 │ int
▶  660 │ bootloader_main(int argc, char *argv[])
   661 │ {
   662 │ 	bool try_boot = true;			/* try booting before we drop to the bootloader */
   663 │ 	unsigned timeout = BOOTLOADER_DELAY;	/* if nonzero, drop out of the bootloader after this time */
```
> **说明**：└─ 新任务 "bootloader_main" 开始执行 ← main.c:660
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-660

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-713"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:713`](stm32-common-main-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-713)

```c
   710 │ 		 * in the bootloader we'll try to boot next time.
   711 │ 		 */
   712 │ 		board_set_rtc_signature(0);
▶  713 │ 	}
   714 │ 
   715 │ 	/*
   716 │ 	 * Check if the force-bootloader pins are strapped; if strapped,
```
> **说明**：_FLASH_KBYTES 实际读到的值（见 §3 警告）。 ┃ main.c:713（RTC 签名分支内的几行）我只确认了 :712 board_set_rtc_signature(0) 与 :719 的位置关系，未逐行展开。
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-713

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-723"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:723`](stm32-common-main-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-723)

```c
   720 │ 		try_boot = false;
   721 │ 	}
   722 │ 
▶  723 │ #if INTERFACE_USB
   724 │ 
   725 │ 	/*
   726 │ 	 * Check for USB connection - if present, don't try to boot, but set a timeout after
```
> **说明**：:719 | board_test_force_pin() | 跳线/strapping pin 投票 ≥90% | 恒 false | hw_config.h 里没有 BOARD_FORCE_BL_PIN / BOARD_FORCE_BL_PIN_IN/OUT ⇒ main.c:139 的整个函数体被预处理掉，只剩 return false（:191） | ┃ :734 | px4_arch_gpioread(BOARD_VBUS) != 0 | USB 已插入 | 编译期不存在 | hw_config.h:94 #define INTERFACE_USB 0 ⇒ main.c:723 整段被裁掉；BOARD_VBUS 也已在 hw_config.h:96 被注释掉 |
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-723

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-766"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:766`](stm32-common-main-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-766)

```c
   763 │ 	if (try_boot) {
   764 │ 
   765 │ 		/* set the boot-to-bootloader flag so that if boot fails on reset we will stop here */
▶  766 │ #ifdef BOARD_BOOT_FAIL_DETECT
   767 │ 		board_set_rtc_signature(BOOT_RTC_SIGNATURE);
   768 │ #endif
   769 │ 
```
> **说明**：既有素材 work/PX4-bootloader主流程时序图.md:32/40 把它列成一个生效的决策点。 ┃ 回验结论：它在 #ifdef BOARD_BOOT_FAIL_DETECT 内（main.c:766、:819-821），
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-766
