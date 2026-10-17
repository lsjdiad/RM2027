# `common/lib/uart.c`（+ `cdcacm.c`）—— 上传通道到底怎么收发字节

> **源码**：`platforms/nuttx/src/bootloader/common/lib/uart.c`（130 行）、`common/lib/cdcacm.c`（135 行）、
> `common/uart.h`（45 行）、`common/cdcacm.h`（46 行）
> **层**：① 通用（平台无关的"收发字节"抽象）
> **谁用它**：①层 [`bl.c:174`](uart-c.md#^src-platforms-nuttx-src-bootloader-common-bl-c-174) 的 `cinit/cfini/cin/cout`
> **本板结论**：**只有 `uart.c` 被编进来并生效**（`hw_config.h:94 INTERFACE_USB 0`）

---

## 1. 运行时它处在哪：②层开了口之后，①层才开始收发

```
main.c:783  cinit(BOARD_INTERFACE_CONFIG_USART, USART)      ← BOARD_INTERFACE_CONFIG_USART 来自
                                                              main.c:91 = INTERFACE_USART_CONFIG
                                                              = hw_config.h:100 "/dev/ttyS0,57600"
   └─ bl.c:185-187  if (interface == USART) return uart_cinit(config);
        └─ uart.c:51  uart_cinit()
             :53-65   把 "/dev/ttyS0,57600" 按逗号切成 device / baud
             :67      open(device, O_RDWR | O_NONBLOCK)     ← ★ 走 NuttX 的 POSIX 设备节点
             :72-78   tcgetattr → 8N1 → cfsetspeed(baud) → tcsetattr
             :71      g_uart_df = fd

之后每次收字节：
bl.c:540  cin(board_get_devices())
   └─ bl.c:217-223  (bl_type == NONE || USART) && (devices & SERIAL0_DEV)
        └─ uart.c:89  uart_cin()  →  read(fd, &b, 1) == 1 ?
每次回字节：
bl.c:491  cout(data, 2)
   └─ bl.c:242-244  (bl_type == USART)
        └─ uart.c:108 uart_cout(buf, len)  →  write(fd, &buf[i], 1)，每个字节最多重试 1000 次
```

### ★ 这是本层最重要的认知

**这个 bootloader 的"串口"不是裸寄存器，而是 NuttX 的 `/dev/ttyS0`。**
⇒ 因此：
- 波特率 57600 是**通过 `tcsetattr` 配到 NuttX 串口驱动**上的，不是直接写 BRR；
- `uart_cout` 里 `write()` 失败会**重试 1000 次**（[`uart.c:120`](uart-c.md#^src-src-lib-drivers-device-qurt-uart-c-120) 每次成功后重置 `timeout = 1000`，`:124` 递减到 0 才放弃）
  ⇒ **输出永不阻塞但也可能悄悄丢字节**（`:125 return`）；
- `uart_cin` 用 `O_NONBLOCK`（[`uart.c:67`](uart-c.md#^src-src-lib-drivers-device-qurt-uart-c-67)）⇒ 单次 `read` 拿不到就是 -1，由 `bl.c:531 cin_wait()` 的 `do/while` 兜住。

---

## 2. 两个通道的实现对照

| | USART（**本板生效**） | USB CDC/ACM（本板**不编**） |
|---|---|---|
| 文件 | `common/lib/uart.c` | `common/lib/cdcacm.c` |
| `cinit` | [`uart.c:51`](uart-c.md#^src-src-lib-drivers-device-qurt-uart-c-51) —— `open` + `termios` | [`cdcacm.c:63`](uart-c.md#^src-platforms-nuttx-src-bootloader-common-lib-cdcacm-c-63) |
| 依赖 | NuttX 串口驱动（`CONFIG_USART1_SERIALDRIVER=y`，bootloader `.config:871`） | `CONFIG_USBDEV`（bootloader `.config:888` = **not set**） |
| 设备节点 | `/dev/ttyS0`（[`hw_config.h:100`](uart-c.md#^src-boards-rm2027-fmu-h743-src-hw-config-h-100)） | `/dev/ttyACM0`（[`hw_config.h:95`](uart-c.md#^src-boards-rm2027-fmu-h743-src-hw-config-h-95) 被注释） |
| 波特率 | **57600**（[`hw_config.h:100`](uart-c.md#^src-boards-rm2027-fmu-h743-src-hw-config-h-100)；[`uart.c:56`](uart-c.md#^src-src-lib-drivers-device-qurt-uart-c-56) 的兜底默认是 115200） | USB 无此概念 |
| ①层怎么选 | `bl.c:183 #if INTERFACE_USART` | `bl.c:176 #if INTERFACE_USB` |
| 本板？ | ✅ | ❌ 整个 `#if` 段被裁掉 ⇒ [`bl.c:202`](uart-c.md#^src-platforms-nuttx-src-bootloader-common-bl-c-202)、`:233-239` 不参与编译 |

**⇒ 上位机与本板 bootloader 握手时必须以 57600 8N1 连接**（不是 PX4 常见的 115200）。
[`uart.c:56`](uart-c.md#^src-src-lib-drivers-device-qurt-uart-c-56) 那个 115200 只是"配置串里没写波特率"时的兜底，本板串里写了 57600 ⇒ **走 57600**。

> ⚠️ 这和 ③层另一处可能不一致：`nuttx-config/bootloader/defconfig:70` 打开了 `CONFIG_STM32H7_USART1`，
> 构建产物 `.config:878` 里 `CONFIG_USART1_BAUD=115200`。
> **但 bootloader 的 `uart_cinit()` 会在 `open` 之后用 `cfsetspeed()` 覆盖它**（[`uart.c:77`](uart-c.md#^src-src-lib-drivers-device-qurt-uart-c-77)）
> ⇒ **最终 57600 生效**。这是"defconfig 115200 / 运行期 57600"的双值现象，台架上别被 defconfig 骗到。
> 标：**源码级推理**（未上板用串口分析仪核实）。

---

## 3. `cin()` 的分派逻辑（[`bl.c:200`](uart-c.md#^src-platforms-nuttx-src-bootloader-common-bl-c-200)）

| 行号 | 条件 | 说明 |
|---|---|---|
| `:204` | `(bl_type == NONE \|\| bl_type == USB) && (devices & USB0_DEV)` | **本板整段被 `#if INTERFACE_USB` 裁掉** |
| `:208` | `last_input = USB` | 同上 |
| `:217` | `(bl_type == NONE \|\| bl_type == USART) && (devices & SERIAL0_DEV)` | **本板唯一生效分支** |
| `:221` | `last_input = USART` | ★ [`bl.c:1150`](uart-c.md#^src-platforms-nuttx-src-bootloader-common-bl-c-1150) 用它锁定 `bl_type` |

`devices` 由 ②层 `board_get_devices()`（[`main.c:258`](uart-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-258)）给出：
`BOOT_DEVICES_SELECTION = USB0_DEV|SERIAL0_DEV|SERIAL1_DEV`（[`hw_config.h:133`](uart-c.md#^src-boards-rm2027-fmu-h743-src-hw-config-h-133)）
——`usb_connected`（[`main.c:111`](uart-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-111)）只在 `INTERFACE_USB` 下才会被置真（[`main.c:735`](uart-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-735)）⇒ **本板恒为 `0x07`**。

**⇒ `SERIAL0_DEV`(0x02) 之外的位在本板上没有任何作用**（没有第二路串口给 bootloader）。

---

## 4. 已定义但本板不会执行的路径

| 行号 | 内容 | 状态 |
|---|---|---|
| `bl.c:174-190 cinit()` | 按 `interface` 参数二选一 | 本板只会走 USART 分支（`:185`） |
| `bl.c:191-199 cfini()` | 关两个通道 | 本板只关 UART（[`bl.c:420`](uart-c.md#^src-platforms-nuttx-src-bootloader-common-bl-c-420) 调用） |
| `cdcacm.c` 全部 | USB CDC/ACM | `INTERFACE_USB=0` ⇒ `bl.c:176/193/202/233` 四处都不编 |
| `bl.c:283-305 buf_put/buf_get` | 中断驱动收字节的环形缓冲 | **全仓无调用者**（见 [02_code_twin/bootloader/bl-h](bl-h.md) §2.3） |

---

## 5. "我看到的现象由谁产生"

| 现象 | 行号 | 说明 |
|---|---|---|
| 上位机 115200 连不上、57600 能连上 | [`hw_config.h:100`](uart-c.md#^src-boards-rm2027-fmu-h743-src-hw-config-h-100) + [`uart.c:77`](uart-c.md#^src-src-lib-drivers-device-qurt-uart-c-77) | `cfsetspeed` 覆盖 defconfig 的 115200 |
| 刷固件时偶发 "丢应答/校验失败" | [`uart.c:110`](uart-c.md#^src-src-lib-drivers-device-qurt-uart-c-110) | `write` 失败重试耗尽后**静默 `return`**（`:125`） |
| 板上电后**没有任何文本日志** | `bl.c:113-... ` | ①层全篇无 `printf`；bootloader 的 `.config:870 CONFIG_NO_SERIAL_CONSOLE=y` 也没有控制台 |
| 上位机发命令没反应（但板子活着） | `bl.c:660 cin_wait(0)` | 0 ms 超时纯轮询；且 [`bl.c:655`](uart-c.md#^src-platforms-nuttx-src-bootloader-common-bl-c-655) 在 `timeout=0` 时**永不返回** |
| `PROTO_BOOT` 之后板子立刻重启 | `bl.c:1131 delay(100)` | 那 100 ms 是"让最后那个 sync 字节真的发出去"的等待 |

---

## 跳转

- **执行序上一步**（谁调它）：[02_code_twin/bootloader/bl-c](bl-c.md) §2/§3；②层 [`main.c:783`](uart-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-783)。
- **执行序下一步**（谁处理收到的字节）：`bl.c:669 switch(c)` ⇒ [02_code_twin/bootloader/bl-c](bl-c.md) §3。
- **`/dev/ttyS0` 是谁注册的**（NuttX 串口驱动 + ROMFS 里的 `rc.serial`）→ [01_extracted/nuttx/00-poweron-chain](../../01_extracted/nuttx/00-poweron-chain.md)；
  注意 bootloader 侧**没有 ROMFS**（见 [01_extracted/nuttx/romfs](../../01_extracted/nuttx/romfs.md)）⇒ 它的 `/dev/ttyS0` 来自 NuttX 编译期注册的 USART1 驱动。
- **如果想改成 115200 或更高**：只需改 [`hw_config.h:100`](uart-c.md#^src-boards-rm2027-fmu-h743-src-hw-config-h-100) 这一个字符串（`uart.c` 会解析它），**不用改 ①②层**。
  这一条对"H104 提频"那类串口需求也适用（参见本项目 `work/review-03-H104提频.md`，但那是 app 侧的 `/dev/ttyS*`，与此无关）。

---

## 未核实

- `uart_cout` 的 `write()` 在 NuttX 的 USART1 驱动上**阻塞还是立即返回**，我未查驱动实现，故"重试 1000 次"在实机上的含义标"未核实"。
- 57600 vs defconfig 115200 谁最终生效，我按"`cfsetspeed` 在 `open` 之后执行"推理，**未上板用逻辑分析仪核实**。

---

## 标注源码（代码 + 本文档对它的解释）

> **这是「代码孪生」层**：上面是代码原文（带行号），下面是**本文档针对这一段说的话**。
> 行号可点，直接跳到 PX4 源码那一行。
### `boards/rm2027/fmu-h743/src/hw_config.h`
<a id="src-boards-rm2027-fmu-h743-src-hw-config-h-95"></a>
**↓ 文档在讲这里：**[`boards/rm2027/fmu-h743/src/hw_config.h:95`](uart-c.md#^src-boards-rm2027-fmu-h743-src-hw-config-h-95)

```c
    92 │  *   PX4 bootloader 支持 USART 上传（见 platforms/.../bootloader/common/bl.c 的 INTERFACE_USART）
    93 │  */
    94 │ #define INTERFACE_USB                  0
▶   95 │ // #define INTERFACE_USB_CONFIG        "/dev/ttyACM0"
    96 │ // #define BOARD_VBUS                  MK_GPIO_INPUT(GPIO_OTGFS_VBUS)   /* 本板无 VBUS 检测脚 */
    97 │ 
    98 │ //#define USE_VBUS_PULL_DOWN
```
> **说明**：依赖 | NuttX 串口驱动（CONFIG_USART1_SERIALDRIVER=y，bootloader .config:871） | CONFIG_USBDEV（bootloader .config:888 = not set） | ┃ 设备节点 | /dev/ttyS0（hw_config.h:100） | /dev/ttyACM0（hw_config.h:95 被注释） |
^src-boards-rm2027-fmu-h743-src-hw-config-h-95

<a id="src-boards-rm2027-fmu-h743-src-hw-config-h-100"></a>
**↓ 文档在讲这里：**[`boards/rm2027/fmu-h743/src/hw_config.h:100`](uart-c.md#^src-boards-rm2027-fmu-h743-src-hw-config-h-100)

```c
    97 │ 
    98 │ //#define USE_VBUS_PULL_DOWN
    99 │ #define INTERFACE_USART                1
▶  100 │ #define INTERFACE_USART_CONFIG         "/dev/ttyS0,57600"
   101 │ /* ★ 必须与 firmware.prototype 的 board_id 一致（本板 = 2027） */
   102 │ #define BOARD_TYPE                     2027
   103 │ #define _FLASH_KBYTES                  (*(uint32_t *)0x1FF1E880)
```
> **说明**：依赖 | NuttX 串口驱动（CONFIG_USART1_SERIALDRIVER=y，bootloader .config:871） | CONFIG_USBDEV（bootloader .config:888 = not set） | ┃ 设备节点 | /dev/ttyS0（hw_config.h:100） | /dev/ttyACM0（hw_config.h:95 被注释） |
> **说明**：设备节点 | /dev/ttyS0（hw_config.h:100） | /dev/ttyACM0（hw_config.h:95 被注释） | ┃ 波特率 | 57600（hw_config.h:100；uart.c:56 的兜底默认是 115200） | USB 无此概念 |
^src-boards-rm2027-fmu-h743-src-hw-config-h-100

<a id="src-boards-rm2027-fmu-h743-src-hw-config-h-133"></a>
**↓ 文档在讲这里：**[`boards/rm2027/fmu-h743/src/hw_config.h:133`](uart-c.md#^src-boards-rm2027-fmu-h743-src-hw-config-h-133)

```c
   130 │ #endif
   131 │ 
   132 │ #ifndef BOOT_DEVICES_SELECTION
▶  133 │ #  define BOOT_DEVICES_SELECTION USB0_DEV|SERIAL0_DEV|SERIAL1_DEV
   134 │ #endif
   135 │ 
   136 │ #ifndef BOOT_DEVICES_FILTER_ONUSB
```
> **说明**：devices 由 ②层 board_get_devices()（main.c:258）给出： ┃ BOOT_DEVICES_SELECTION = USB0_DEV|SERIAL0_DEV|SERIAL1_DEV（hw_config.h:133）
^src-boards-rm2027-fmu-h743-src-hw-config-h-133

### `platforms/nuttx/src/bootloader/common/bl.c`
<a id="src-platforms-nuttx-src-bootloader-common-bl-c-174"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:174`](uart-c.md#^src-platforms-nuttx-src-bootloader-common-bl-c-174)

```c
   171 │ 	return len;
   172 │ }
   173 │ 
▶  174 │ inline void cinit(void *config, uint8_t interface)
   175 │ {
   176 │ #if INTERFACE_USB
   177 │ 
```
> **说明**：层：① 通用（平台无关的"收发字节"抽象） ┃ 谁用它：①层 bl.c:174 的 cinit/cfini/cin/cout
^src-platforms-nuttx-src-bootloader-common-bl-c-174

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-185"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:185`](uart-c.md#^src-platforms-nuttx-src-bootloader-common-bl-c-185)

```c
   182 │ #endif
   183 │ #if INTERFACE_USART
   184 │ 
▶  185 │ 	if (interface == USART) {
   186 │ 		return uart_cinit(config);
   187 │ 	}
   188 │ 
```
> **说明**：└─ bl.c:185-187 if (interface == USART) return uart_cinit(config);
^src-platforms-nuttx-src-bootloader-common-bl-c-185

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-200"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:200`](uart-c.md#^src-platforms-nuttx-src-bootloader-common-bl-c-200)

```c
   197 │ 	uart_cfini();
   198 │ #endif
   199 │ }
▶  200 │ inline int cin(uint32_t devices)
   201 │ {
   202 │ #if INTERFACE_USB
   203 │ 
```
> **说明**：3. cin() 的分派逻辑（bl.c:200）
^src-platforms-nuttx-src-bootloader-common-bl-c-200

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-202"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:202`](uart-c.md#^src-platforms-nuttx-src-bootloader-common-bl-c-202)

```c
   199 │ }
   200 │ inline int cin(uint32_t devices)
   201 │ {
▶  202 │ #if INTERFACE_USB
   203 │ 
   204 │ 	if ((bl_type == NONE || bl_type == USB) && (devices & USB0_DEV) != 0) {
   205 │ 		int usb_in = usb_cin();
```
> **说明**：①层怎么选 | bl.c:183 #if INTERFACE_USART | bl.c:176 #if INTERFACE_USB | ┃ 本板？ | ✅ | ❌ 整个 #if 段被裁掉 ⇒ bl.c:202、:233-239 不参与编译 |
^src-platforms-nuttx-src-bootloader-common-bl-c-202

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-217"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:217`](uart-c.md#^src-platforms-nuttx-src-bootloader-common-bl-c-217)

```c
   214 │ 
   215 │ #if INTERFACE_USART
   216 │ 
▶  217 │ 	if ((bl_type == NONE || bl_type == USART) && (devices & SERIAL0_DEV) != 0) {
   218 │ 		int uart_in = uart_cin();
   219 │ 
   220 │ 		if (uart_in >= 0) {
```
> **说明**：└─ bl.c:217-223 (bl_type == NONE || USART) && (devices & SERIAL0_DEV)
^src-platforms-nuttx-src-bootloader-common-bl-c-217

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-242"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:242`](uart-c.md#^src-platforms-nuttx-src-bootloader-common-bl-c-242)

```c
   239 │ #endif
   240 │ #if INTERFACE_USART
   241 │ 
▶  242 │ 	if (bl_type == USART) {
   243 │ 		uart_cout(buf, len);
   244 │ 	}
   245 │ 
```
> **说明**：└─ bl.c:242-244 (bl_type == USART)
^src-platforms-nuttx-src-bootloader-common-bl-c-242

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-420"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:420`](uart-c.md#^src-platforms-nuttx-src-bootloader-common-bl-c-420)

```c
   417 │ 	arch_systic_deinit();
   418 │ 
   419 │ 	/* deinitialise the interface */
▶  420 │ 	cfini();
   421 │ 
   422 │ 	/* reset the clock */
   423 │ 	clock_deinit();
```
> **说明**：bl.c:174-190 cinit() | 按 interface 参数二选一 | 本板只会走 USART 分支（:185） | ┃ bl.c:191-199 cfini() | 关两个通道 | 本板只关 UART（bl.c:420 调用） |
^src-platforms-nuttx-src-bootloader-common-bl-c-420

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-491"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:491`](uart-c.md#^src-platforms-nuttx-src-bootloader-common-bl-c-491)

```c
   488 │ 		PROTO_OK  // "OK"
   489 │ 	};
   490 │ 
▶  491 │ 	cout(data, sizeof(data));
   492 │ }
   493 │ 
   494 │ #if defined(TARGET_HW_PX4_FMU_V4)
```
> **说明**：bl.c:491 cout(data, 2)
^src-platforms-nuttx-src-bootloader-common-bl-c-491

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-540"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:540`](uart-c.md#^src-platforms-nuttx-src-bootloader-common-bl-c-540)

```c
   537 │ 	timer[TIMER_CIN] = timeout;
   538 │ 
   539 │ 	do {
▶  540 │ 		c = cin(board_get_devices());
   541 │ 
   542 │ 		if (c >= 0) {
   543 │ 			cin_count++;
```
> **说明**：bl.c:540 cin(board_get_devices())
^src-platforms-nuttx-src-bootloader-common-bl-c-540

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-655"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:655`](uart-c.md#^src-platforms-nuttx-src-bootloader-common-bl-c-655)

```c
   652 │ 
   653 │ 		do {
   654 │ 			/* if we have a timeout and the timer has expired, return now */
▶  655 │ 			if (timeout && !timer[TIMER_BL_WAIT]) {
   656 │ 				return;
   657 │ 			}
   658 │ 
```
> **说明**：板上电后没有任何文本日志 | bl.c:113-... | ①层全篇无 printf；bootloader 的 .config:870 CONFIG_NO_SERIAL_CONSOLE=y 也没有控制台 | ┃ 上位机发命令没反应（但板子活着） | bl.c:660 cin_wait(0) | 0 ms 超时纯轮询；且 bl.c:655 在 timeout=0 时永不返回 |
^src-platforms-nuttx-src-bootloader-common-bl-c-655

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-1150"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:1150`](uart-c.md#^src-platforms-nuttx-src-bootloader-common-bl-c-1150)

```c
  1147 │ 		}
  1148 │ 
  1149 │ 		// Set the bootloader port based on the port from which we received the first valid command
▶ 1150 │ 		if (bl_type == NONE) {
  1151 │ 			bl_type = last_input;
  1152 │ 		}
  1153 │ 
```
> **说明**：:217 | (bl_type == NONE \|\| bl_type == USART) && (devices & SERIAL0_DEV) | 本板唯一生效分支 | ┃ :221 | last_input = USART | ★ bl.c:1150 用它锁定 bl_type |
^src-platforms-nuttx-src-bootloader-common-bl-c-1150

### `platforms/nuttx/src/bootloader/common/lib/cdcacm.c`
<a id="src-platforms-nuttx-src-bootloader-common-lib-cdcacm-c-63"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/lib/cdcacm.c:63`](uart-c.md#^src-platforms-nuttx-src-bootloader-common-lib-cdcacm-c-63)

```c
    60 │ char out_trace[TRACE_SIZE];
    61 │ #endif
    62 │ 
▶   63 │ void usb_cinit(void *config)
    64 │ {
    65 │ #if defined(SERIAL_TRACE)
    66 │ 	in = 0;
```
> **说明**：文件 | common/lib/uart.c | common/lib/cdcacm.c | ┃ cinit | uart.c:51 —— open + termios | cdcacm.c:63 |
^src-platforms-nuttx-src-bootloader-common-lib-cdcacm-c-63

### `platforms/nuttx/src/bootloader/stm/stm32_common/main.c`
<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-91"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:91`](uart-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-91)

```c
    88 │ 
    89 │ /* context passed to cinit */
    90 │ #if INTERFACE_USART
▶   91 │ # define BOARD_INTERFACE_CONFIG_USART	INTERFACE_USART_CONFIG
    92 │ #endif
    93 │ #if INTERFACE_USB
    94 │ # define BOARD_INTERFACE_CONFIG_USB  INTERFACE_USB_CONFIG
```
> **说明**：main.c:91 = INTERFACE_USART_CONFIG
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-91

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-111"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:111`](uart-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-111)

```c
   108 │ #define BOOT_RTC_REG                MMIO32(RTC_BASE + 0x50)
   109 │ 
   110 │ /* State of an inserted USB cable */
▶  111 │ static bool usb_connected = false;
   112 │ 
   113 │ static uint32_t board_get_rtc_signature(void)
   114 │ {
```
> **说明**：BOOT_DEVICES_SELECTION = USB0_DEV|SERIAL0_DEV|SERIAL1_DEV（hw_config.h:133） ┃ ——usb_connected（main.c:111）只在 INTERFACE_USB 下才会被置真（main.c:735）⇒ 本板恒为 0x07。
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-111

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-258"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:258`](uart-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-258)

```c
   255 │ }
   256 │ #endif
   257 │ 
▶  258 │ uint32_t
   259 │ board_get_devices(void)
   260 │ {
   261 │ 	uint32_t devices = BOOT_DEVICES_SELECTION;
```
> **说明**：devices 由 ②层 board_get_devices()（main.c:258）给出：
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-258

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-735"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:735`](uart-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-735)

```c
   732 │ #if defined(BOARD_VBUS)
   733 │ 
   734 │ 	if (px4_arch_gpioread(BOARD_VBUS) != 0) {
▶  735 │ 		usb_connected = true;
   736 │ 		/* don't try booting before we set up the bootloader */
   737 │ 		try_boot = false;
   738 │ 	}
```
> **说明**：BOOT_DEVICES_SELECTION = USB0_DEV|SERIAL0_DEV|SERIAL1_DEV（hw_config.h:133） ┃ ——usb_connected（main.c:111）只在 INTERFACE_USB 下才会被置真（main.c:735）⇒ 本板恒为 0x07。
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-735

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-783"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:783`](uart-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-783)

```c
   780 │ 
   781 │ 	/* start the interface */
   782 │ #if INTERFACE_USART
▶  783 │ 	cinit(BOARD_INTERFACE_CONFIG_USART, USART);
   784 │ #endif
   785 │ #if INTERFACE_USB
   786 │ 	cinit(BOARD_INTERFACE_CONFIG_USB, USB);
```
> **说明**：main.c:783 cinit(BOARD_INTERFACE_CONFIG_USART, USART) ← BOARD_INTERFACE_CONFIG_USART 来自
> **说明**：执行序上一步（谁调它）：02_code_twin/bootloader/bl-c §2/§3；②层 main.c:783。
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-783

### `src/lib/drivers/device/qurt/uart.c`
<a id="src-src-lib-drivers-device-qurt-uart-c-51"></a>
**↓ 文档在讲这里：**[`src/lib/drivers/device/qurt/uart.c:51`](uart-c.md#^src-src-lib-drivers-device-qurt-uart-c-51)

```c
    48 │ {
    49 │ 	int port_number = qurt_uart_get_port(dev);
    50 │ 
▶   51 │ 	if (_callbacks_configured && (port_number >= 0)) {
    52 │ 
    53 │ 		return _open_uart((uint8_t) port_number, speed);
    54 │ 
```
> **说明**：文件 | common/lib/uart.c | common/lib/cdcacm.c | ┃ cinit | uart.c:51 —— open + termios | cdcacm.c:63 |
^src-src-lib-drivers-device-qurt-uart-c-51

<a id="src-src-lib-drivers-device-qurt-uart-c-56"></a>
**↓ 文档在讲这里：**[`src/lib/drivers/device/qurt/uart.c:56`](uart-c.md#^src-src-lib-drivers-device-qurt-uart-c-56)

```c
    53 │ 		return _open_uart((uint8_t) port_number, speed);
    54 │ 
    55 │ 	} else {
▶   56 │ 		PX4_ERR("Cannot open uart until callbacks have been configured");
    57 │ 	}
    58 │ 
    59 │ 	return -1;
```
> **说明**：设备节点 | /dev/ttyS0（hw_config.h:100） | /dev/ttyACM0（hw_config.h:95 被注释） | ┃ 波特率 | 57600（hw_config.h:100；uart.c:56 的兜底默认是 115200） | USB 无此概念 |
> **说明**：⇒ 上位机与本板 bootloader 握手时必须以 57600 8N1 连接（不是 PX4 常见的 115200）。 ┃ uart.c:56 那个 115200 只是"配置串里没写波特率"时的兜底，本板串里写了 57600 ⇒ 走 57600。
^src-src-lib-drivers-device-qurt-uart-c-56

<a id="src-src-lib-drivers-device-qurt-uart-c-67"></a>
**↓ 文档在讲这里：**[`src/lib/drivers/device/qurt/uart.c:67`](uart-c.md#^src-src-lib-drivers-device-qurt-uart-c-67)

```c
    64 │ 	if (fd < 0) {
    65 │ 		PX4_ERR("invalid fd %d for %s", fd, __FUNCTION__);
    66 │ 		return -1;
▶   67 │ 	}
    68 │ 
    69 │ 	if (buf == NULL) {
    70 │ 		PX4_ERR("NULL buffer pointer in %s", fd, __FUNCTION__);
```
> **说明**：⇒ 输出永不阻塞但也可能悄悄丢字节（:125 return）； ┃ uart_cin 用 O_NONBLOCK（uart.c:67）⇒ 单次 read 拿不到就是 -1，由 bl.c:531 cin_wait() 的 do/while 兜住。
^src-src-lib-drivers-device-qurt-uart-c-67

<a id="src-src-lib-drivers-device-qurt-uart-c-77"></a>
**↓ 文档在讲这里：**[`src/lib/drivers/device/qurt/uart.c:77`](uart-c.md#^src-src-lib-drivers-device-qurt-uart-c-77)

```c
    74 │ 	if (len == 0) {
    75 │ 		PX4_ERR("Zero length buffer in %s", __FUNCTION__);
    76 │ 		return -1;
▶   77 │ 	}
    78 │ 
    79 │ 	if (_callbacks_configured) {
    80 │ 		return _write_uart(fd, buf, len);
```
> **说明**：构建产物 .config:878 里 CONFIG_USART1_BAUD=115200。 ┃ 但 bootloader 的 uart_cinit() 会在 open 之后用 cfsetspeed() 覆盖它（uart.c:77）
> **说明**：上位机 115200 连不上、57600 能连上 | hw_config.h:100 + uart.c:77 | cfsetspeed 覆盖 defconfig 的 115200 |
^src-src-lib-drivers-device-qurt-uart-c-77

<a id="src-src-lib-drivers-device-qurt-uart-c-110"></a>
**↓ 文档在讲这里：**[`src/lib/drivers/device/qurt/uart.c:110`](uart-c.md#^src-src-lib-drivers-device-qurt-uart-c-110)

```c
   107 │ 		uint32_t interval_counter = (timeout_us + (UART_READ_POLL_INTERVAL_US - 1)) / UART_READ_POLL_INTERVAL_US;
   108 │ 		// PX4_INFO("UART interval counter = %d", interval_counter);
   109 │ 		int read_len = 0;
▶  110 │ 
   111 │ 		do {
   112 │ 			read_len = _read_uart(fd, buf, len);
   113 │ 
```
> **说明**：上位机 115200 连不上、57600 能连上 | hw_config.h:100 + uart.c:77 | cfsetspeed 覆盖 defconfig 的 115200 | ┃ 刷固件时偶发 "丢应答/校验失败" | uart.c:110 | write 失败重试耗尽后静默 return（:125） |
^src-src-lib-drivers-device-qurt-uart-c-110

<a id="src-src-lib-drivers-device-qurt-uart-c-120"></a>
**↓ 文档在讲这里：**[`src/lib/drivers/device/qurt/uart.c:120`](uart-c.md#^src-src-lib-drivers-device-qurt-uart-c-120)

```c
   117 │ 			px4_usleep(UART_READ_POLL_INTERVAL_US);
   118 │ 		} while (interval_counter);
   119 │ 
▶  120 │ 		// if (read_len <= 0) PX4_INFO("Warning, UART read timed out");
   121 │ 		// else PX4_INFO("UART read %d bytes, counter = %d", read_len, interval_counter);
   122 │ 		return read_len;
   123 │ 
```
> **说明**：波特率 57600 是通过 tcsetattr 配到 NuttX 串口驱动上的，不是直接写 BRR； ┃ uart_cout 里 write() 失败会重试 1000 次（uart.c:120 每次成功后重置 timeout = 1000，:124 递减到 0 才放弃）
^src-src-lib-drivers-device-qurt-uart-c-120
