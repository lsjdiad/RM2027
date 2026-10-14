# flash 扇区布局：bootloader 区 / app 区 / 参数区

> **层**：01 提炼知识
> **素材**：`nuttx-config/scripts/bootloader_script.ld`、`nuttx-config/scripts/script.ld`、
> `boards/rm2027/fmu-h743/src/{hw_config.h,board_config.h,init.c}`、
> `platforms/nuttx/src/bootloader/{common/bl.c,stm/stm32_common/main.c,stm/stm32h7/ecc_scrub.c}`、
> `nuttx/arch/arm/src/stm32h7/stm32h743xx_flash.c`
> **一句话**：**三个地方各自声明了"flash 怎么分"，而它们**并不完全一致** —— 本篇把三个说法都摆出来。**

---

## 1. 物理事实（芯片）

| 项 | 值 | 依据 |
|---|---|---|
| 芯片 | STM32H743VIT6，**2 MiB** flash，双 bank | NuttX `.config` 两个构建都是 `CONFIG_STM32H7_FLASH_CONFIG_I=y`（bl `.config:265`、app `.config:298`） |
| 扇区 | **128 KiB**，共 **16** 个（每 bank 8 个） | `stm32h743xx_flash.c:85 FLASH_SECTOR_SIZE = _K(128)`、`:130-134 CONFIG_STM32H7_FLASH_CONFIG_I → STM32_FLASH_NBLOCKS 16`、`:150 PROGMEM_NBLOCKS` |
| 编程粒度 | **32 字节**（= 8 word） | `stm32h743xx_flash.c:86 FLASH_PAGE_SIZE 32`；ECC 块见 [02_code_twin/bootloader/flash-cache-c](../../02_code_twin/bootloader/flash-cache-c.md) |
| 基址 | `0x08000000`（bank1），bank2 从 `0x08100000` 起（sector 8） | `stm32h743xx_flash.c:751 STM32_FLASH_BANK1 + block*FLASH_SECTOR_SIZE` |

**⇒ 16 个扇区的绝对地址**：

| 扇区 | 起址 | 止址 | 本板用途 |
|---|---|---|---|
| 0 | `0x08000000` | `0x0801FFFF` | **bootloader** |
| 1 | `0x08020000` | `0x0803FFFF` | app |
| … | … | … | app |
| 7 | `0x080E0000` | `0x080FFFFF` | app（bank1 末） |
| 8 | `0x08100000` | `0x0811FFFF` | app（bank2 首） |
| … | … | … | app |
| 14 | `0x081C0000` | `0x081DFFFF` | app（末） |
| **15** | **`0x081E0000`** | **`0x081FFFFF`** | **参数区**（PX4 flashfs） |

---

## 2. 说法 A：bootloader 侧（②层）怎么看

| 量 | 值 | 依据 |
|---|---|---|
| bootloader 自己的范围 | `0x08000000` + **128 KiB** | `bootloader_script.ld:113 flash ORIGIN=0x08000000, LENGTH=128K` |
| app 基址 | **`0x08020000`** | `hw_config.h:87 APP_LOAD_ADDRESS` |
| 总 flash | `_FLASH_KBYTES * 1024` | `hw_config.h:103/105` |
| 预留给自己 | `128 * 1024` | `stm32_common/main.c:29 BOOTLOADER_RESERVATION_SIZE` |
| app 预留 | `APP_RESERVATION_SIZE`，默认 **0** | [`hw_config.h:120`](../../02_code_twin/bootloader/board-layer.md#^src-boards-rm2027-fmu-h743-src-hw-config-h-120)；且 `compile_commands.json` 里**没有** `-DAPP_RESERVATION_SIZE` |
| ⇒ **`fw_size`** | `BOARD_FLASH_SIZE − 128 KiB` | `main.c:86 APP_SIZE_MAX` → [`main.c:274`](../../02_code_twin/bootloader/stm32-common-main-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-274) |
| 扇区上界 | `BOARD_FLASH_SECTORS = 15` | [`hw_config.h:104`](../../02_code_twin/bootloader/stm32-common-main-c.md#^src-boards-rm2027-fmu-h743-src-hw-config-h-104) |
| 擦除下界 | `BOARD_FIRST_FLASH_SECTOR_TO_ERASE = 1` | [`hw_config.h:124`](../../02_code_twin/bootloader/stm32-common-main-c.md#^src-boards-rm2027-fmu-h743-src-hw-config-h-124) |
| ⇒ **bootloader 认为的 app 区** | **`0x08020000` .. `0x081FFFFF`（1920 KiB，扇区 1..15）** | 上面两条合起来（**推理**：`_FLASH_KBYTES` 取 2048） |

**bootloader 遍历/擦除/算 CRC 的范围全部由 `fw_size` 决定**：
- CRC：`bl.c:902 for (p = 0; p < board_info.fw_size; p += 4)`
- 擦后校验：`bl.c:785 for (address = 0; address < board_info.fw_size; address += 4)`
- 写入边界检查：`bl.c:818 if ((address + arg) > board_info.fw_size) goto cmd_bad;`
- 但**擦除循环的终止条件不是 `fw_size`**，是 `bl.c:777 for (int i = 0; flash_func_sector_size(i) != 0; i++)`
  ⇒ `i` 到 15 为止；再由 [`main.c:480`](../../02_code_twin/bootloader/board-layer.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-480) 跳过 `i < 1` ⇒ **扇区 1..15 都在候选内**。

---

## 3. 说法 B：app 链接脚本怎么看

| 量 | 值 | 依据 |
|---|---|---|
| app 范围 | `0x08020000` + **1792 KiB** | `script.ld:113 FLASH (rx) : ORIGIN = 0x08020000, LENGTH = 1792K` |
| 同行的注释 | *"★ 最后 1 个 128K 扇区(0x081E0000)让给 flash 参数存储，见 src/init.c"* | [`script.ld:113`](../../02_code_twin/bootloader/stm32-common-main-c.md#^src-boards-rm2027-fmu-h743-nuttx-config-scripts-script-ld-113) |
| ⇒ **app 认为的 app 区** | **扇区 1..14** | — |

---

## 4. 说法 C：app 的板级代码怎么看（参数放哪）

| 量 | 值 | 依据 |
|---|---|---|
| 用片内 flash 存参数 | `#define FLASH_BASED_PARAMS` | [`board_config.h:60`](../../02_code_twin/params/param-system.md#^src-boards-rm2027-fmu-h743-src-board-config-h-60)（注释在 `:58`） |
| 参数扇区表 | `{{15, 128*1024, 0x081E0000}, {0,0,0}}` | [`init.c:200`](flash-layout.md#^src-boards-rm2027-fmu-h743-src-init-c-200)（★ 注释 `:187-199` 把理由写得很清楚） |
| 初始化 | `parameter_flashfs_init(params_sector_map, NULL, 0)` | [`init.c:206`](flash-layout.md#^src-boards-rm2027-fmu-h743-src-init-c-206) |
| ⇒ **参数区** | **扇区 15 = `0x081E0000`** | — |

[`init.c:196`](flash-layout.md#^src-boards-rm2027-fmu-h743-src-init-c-196) 的注释直接把"配套要求"写出来了：
> *"配套要求：script.ld 的 FLASH LENGTH 必须从 1920K 缩到 1792K，把 0x081E0000 这个扇区让出来，否则链接器可能把代码放进去、参数写入就会打烂代码。"*

---

## 5. ★★ 三处同源不一致（**这是本板的一条真实欠账**）

| 谁 | app 区到哪 | 扇区 |
|---|---|---|
| **bootloader（`fw_size`）** | `0x081FFFFF` | 1..**15** |
| **app 链接脚本** | `0x081DFFFF` | 1..**14** |
| **app 参数表** | 参数在 `0x081E0000` | **15** |

**⇒ 差别正好一个 128 KiB 扇区：bootloader 把"参数扇区"也当成自己的可写/可擦范围。**

**它会造成什么（按严重度）**

1. **刷固件时参数扇区会被擦**：[`bl.c:777`](../../02_code_twin/bootloader/stm32-common-main-c.md#^src-platforms-nuttx-src-bootloader-common-bl-c-777) 会遍历到扇区 15，
   [`main.c:484`](flash-layout.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-484) 的条件是 `force || up_progmem_ispageerased(sector) != 0`，
   而 `up_progmem_ispageerased()` 返回**非 0xFF 字节数**（[`stm32h743xx_flash.c:717`](flash-layout.md#^src-platforms-nuttx-NuttX-nuttx-arch-arm-src-stm32h7-stm32h743xx-flash-c-717)）
   ⇒ 参数扇区里**有数据 ⇒ 返回非 0 ⇒ 被擦掉**。
2. **`PROTO_GET_CRC` 的校验范围包含参数区**（[`bl.c:902`](../../02_code_twin/bootloader/bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-c-902) 到 `fw_size`）⇒
   上位机算出的 CRC 会随参数变化 ⇒ **同版本固件刷两次，CRC 可能不同**（若参数写过）。
3. **擦后逐字校验也覆盖参数区**（[`bl.c:785`](../../02_code_twin/bootloader/bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-c-785)）⇒ 若参数扇区擦不干净，上传会 `cmd_bad`。

**⇒ 这条必须上板判，判据（不需要改任何代码）**：

| 判据 | 期望 | 说明 |
|---|---|---|
| ① 上位机 `GET_DEVICE / arg=4` 回的 4 字节 | `1920×1024` ⇒ bootloader 视角与我一致；`1792×1024` ⇒ 我漏了某个 `-DAPP_RESERVATION_SIZE` | 已查 `compile_commands.json`，**没有**这个 define |
| ② **改一个参数 → 记下值 → 用上位机刷同一个固件 → 上电读该参数** | **若参数丢了** ⇒ 判据成立（参数区被擦）；**若还在** ⇒ 我的擦除范围推理错了 | 最直接、最硬的一条 |
| ③ 刷完后立刻 `listener sensor_accel` / `param show` 看是否回默认 | 回默认 = 参数区被擦 | — |

> **这与"PX4 刷固件不丢参数"的一般印象冲突** —— 所以我没有直接下结论，
> 而是把它列为**本板待判的欠账**。可能解释（**都未核实**）：
> PX4 参数有 `/fs/mtd`（另一个 MTD 分区）里的 `parameters_backup.bson` 兜底
> （`rcS:131` `PARAM_BACKUP_FILE="${BOARD_ROOT_PATH}/parameters_backup.bson"`，`rcS:204/220` 用它）；
> 或上位机在固件上传时跳过了 `CHIP_ERASE`。
> **⇒ 但注意：`rcS` 只在 `param load-or-init` 失败时才去用备份**（`rcS:204/220`），
> 属于"补救"而非"预防"。这条属于参数体系的范畴 → [03_moc/04-params-map](../../03_moc/04-params-map.md)（task-12）。

---

## 6. ECC scrub 的扫描范围（和参数区直接相关）

```
ecc_scrub.c:137  last_sector = up_progmem_neraseblocks() - 1     = 16 - 1 = 15   ← 已由 CONFIG_STM32H7_FLASH_CONFIG_I=y 坐实
ecc_scrub.c:139  for (sector = BOARD_FIRST_FLASH_SECTOR_TO_ERASE(1) .. 15)
ecc_scrub.c:142-145  发现 DBECCERR ⇒ up_progmem_eraseblock(sector)
```

**⇒ 扫描范围 = 扇区 1..15，含参数扇区。**
⇒ **参数"莫名其妙回默认"的一条可能原因是 ECC scrub 把扇区 15 擦了**（详见 [02_code_twin/bootloader/ecc-scrub-c](../../02_code_twin/bootloader/ecc-scrub-c.md) §3）。

> ⚠️ [`ecc_scrub.c:135`](../../02_code_twin/bootloader/ecc-scrub-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32h7-ecc-scrub-c-135) 的注释说"parameter sectors sit past `BOARD_FLASH_SECTORS`"，
> **与本板 `BOARD_FLASH_SECTORS=15` / 参数在扇区 15 的事实对不上**（本板上参数扇区并没有"超出"）。
> 但它的**循环写法**（用 `up_progmem_neraseblocks()` 而不是 `BOARD_FLASH_SECTORS`）依然覆盖了扇区 15。
> **标：注释与本板配置不一致，原因未核实。**

---

## 7. 一张总图

```
0x08000000 ┌──────────────────────────┐ 扇区 0   ← bootloader（128K, bootloader_script.ld:113）
           │  bootloader  __start      │          _vectors @0x08000000
           │  bl.c / main.c / ecc_scrub│
0x08020000 ├──────────────────────────┤ 扇区 1
           │                          │
           │      APP                  │  ← script.ld:113 FLASH LENGTH=1792K（扇区 1..14）
           │  _vectors @0x08020000     │
           │  ROMFS（cromfs 数组）      │
           │  NuttX + px4 modules      │
           │                          │
0x081E0000 ├──────────────────────────┤ 扇区 15
           │  PX4 参数 flashfs         │  ← init.c:200-203 {15, 128K, 0x081E0000}
           │  （FLASH_BASED_PARAMS）    │
0x08200000 └──────────────────────────┘

bootloader 眼里的"app 区"： 0x08020000 .. 0x081FFFFF  (fw_size = 1920K)   ← 多算了扇区 15
app 链接脚本眼里的"app 区"：0x08020000 .. 0x081DFFFF  (1792K)             ← 正确
参数表眼里的"参数区"：      0x081E0000 .. 0x081FFFFF                      ← 正确
```

---

## 8. "我看到的现象由谁产生"

| 现象 | 由谁 | 依据 |
|---|---|---|
| 刷完固件参数回默认 | [`bl.c:777`](../../02_code_twin/bootloader/stm32-common-main-c.md#^src-platforms-nuttx-src-bootloader-common-bl-c-777) 擦到扇区 15 + [`main.c:484`](flash-layout.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-484) 的判定 | §5（**推理，待上板判 ②**） |
| 参数毫无原因回默认（没刷固件） | ECC scrub 擦了扇区 15 | [02_code_twin/bootloader/ecc-scrub-c](../../02_code_twin/bootloader/ecc-scrub-c.md) |
| 同版本固件刷两次，上位机校验值的 CRC 不同 | [`bl.c:902`](../../02_code_twin/bootloader/bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-c-902) 的 CRC 范围含参数区 | §5 第 2 条 |
| bootloader 上传被拒（"超出 flash 范围"） | [`bl.c:818`](flash-layout.md#^src-platforms-nuttx-src-bootloader-common-bl-c-818) 用 `fw_size` 做上界 | — |
| 改了 `script.ld` 却"没变化" | 只影响 app 链接，不影响 bootloader 的 `fw_size` | §2 vs §3 |
| 用调试器读 `0x081E0000` 能看到参数 | [`init.c:201`](flash-layout.md#^src-boards-rm2027-fmu-h743-src-init-c-201) | — |

---

## 跳转

- **执行序上一步**（谁决定 `fw_size`）→ [02_code_twin/bootloader/stm32-common-main-c](../../02_code_twin/bootloader/stm32-common-main-c.md) §3。
- **执行序下一步**（擦除/写入怎么落到 flash）→ [02_code_twin/bootloader/flash-cache-c](../../02_code_twin/bootloader/flash-cache-c.md)。
- **那个静默擦扇区的补丁** → [02_code_twin/bootloader/ecc-scrub-c](../../02_code_twin/bootloader/ecc-scrub-c.md)。
- **参数"定义了、落盘了、被谁读"整套机制** → [03_moc/04-params-map](../../03_moc/04-params-map.md)（task-12）。
- **两个 linker script 的完整内容（含 RAM 布局）** → [02_code_twin/board](../../02_code_twin/board/README.md)（task-12 负责）。
- **`_FLASH_KBYTES` 读到的值到底是多少** → 见下方"未核实"的判据。

---

## 未核实

- **`_FLASH_KBYTES = *(uint32_t *)0x1FF1E880`（[`hw_config.h:103`](../../02_code_twin/bootloader/00-overview.md#^src-boards-rm2027-fmu-h743-src-hw-config-h-103)）用 32 位读一个 16 位 flash size 寄存器**
  （STM32H743 的 flash size 在 `0x1FF1E880`，值为 0x0800 = 2048 KiB）。高 16 位读数**未核实**。
  ⇒ 因此本文 §2 的 `fw_size`（1920 KiB）是**"按 2048 推"**，标**推理**。
  判据：上位机 `GET_DEVICE / arg=4` 回读的值 ÷ 1024。
- **本板 flash 的实际擦除行为**（§5 的三条后果）**全部未上板验证**。
- **PX4 参数备份 `/fs/mtd` 的物理位置**（在 flash 的哪个扇区、还是 RAM/其他 MTD）**未核实** —— 属 task-12 范围。
- `stm32h743xx_flash.c:703-704 up_progmem_getaddress()` 里 `priv->stpage` 对对 H743 双 bank 的取值我只看了函数体，
  **没有**追 `stm32h7_flash_bank()` 的实现 ⇒ "`ispageerased(sector)` 读的是扇区头 32 字节"这一条**标推理**。

---

## 标注源码（代码 + 本文档对它的解释）

> **这是「代码孪生」层**：上面是代码原文（带行号），下面是**本文档针对这一段说的话**。
> 行号可点，直接跳到 PX4 源码那一行。
### `boards/rm2027/fmu-h743/nuttx-config/scripts/script.ld`
<a id="src-boards-rm2027-fmu-h743-nuttx-config-scripts-script-ld-113"></a>
**↓ 文档在讲这里：**[`boards/rm2027/fmu-h743/nuttx-config/scripts/script.ld:113`](flash-layout.md#^src-boards-rm2027-fmu-h743-nuttx-config-scripts-script-ld-113)

```c
   110 │ MEMORY
   111 │ {
   112 │ 	ITCM_RAM  (rwx) : ORIGIN = 0x00000000, LENGTH =   64K
▶  113 │ 	FLASH      (rx) : ORIGIN = 0x08020000, LENGTH = 1792K /* ★ 最后 1 个 128K 扇区(0x081E0000)让给 flash 参数存储，见 src/init.c */
   114 │ 
   115 │ 	DTCM1_RAM (rwx) : ORIGIN = 0x20000000, LENGTH =   64K
   116 │ 	DTCM2_RAM (rwx) : ORIGIN = 0x20010000, LENGTH =   64K
```
> **说明**：app 范围 | 0x08020000 + 1792 KiB | script.ld:113 FLASH (rx) : ORIGIN = 0x08020000, LENGTH = 1792K | ┃ 同行的注释 | *"★ 最后 1 个 128K 扇区(0x081E0000)让给 flash 参数存储，见 src/init.c"* | script.ld:113 |
^src-boards-rm2027-fmu-h743-nuttx-config-scripts-script-ld-113

### `boards/rm2027/fmu-h743/src/board_config.h`
<a id="src-boards-rm2027-fmu-h743-src-board-config-h-60"></a>
**↓ 文档在讲这里：**[`boards/rm2027/fmu-h743/src/board_config.h:60`](flash-layout.md#^src-boards-rm2027-fmu-h743-src-board-config-h-60)

```c
    57 │ //   不开这个 ⇒ 每次上电参数全丢、标定白做。故开启片内 flash 存参数，
    58 │ //   占用最后一个 128K 扇区 0x081E0000（配套 script.ld 的 FLASH LENGTH 1792K）。
    59 │ //   详见 src/init.c 里 params_sector_map 的注释。
▶   60 │ #define FLASH_BASED_PARAMS
    61 │ 
    62 │ 
    63 │ /* ============================================================================
```
> **说明**：用片内 flash 存参数 | #define FLASH_BASED_PARAMS | board_config.h:60（注释在 :58） |
^src-boards-rm2027-fmu-h743-src-board-config-h-60

### `boards/rm2027/fmu-h743/src/hw_config.h`
<a id="src-boards-rm2027-fmu-h743-src-hw-config-h-103"></a>
**↓ 文档在讲这里：**[`boards/rm2027/fmu-h743/src/hw_config.h:103`](flash-layout.md#^src-boards-rm2027-fmu-h743-src-hw-config-h-103)

```c
   100 │ #define INTERFACE_USART_CONFIG         "/dev/ttyS0,57600"
   101 │ /* ★ 必须与 firmware.prototype 的 board_id 一致（本板 = 2027） */
   102 │ #define BOARD_TYPE                     2027
▶  103 │ #define _FLASH_KBYTES                  (*(uint32_t *)0x1FF1E880)
   104 │ #define BOARD_FLASH_SECTORS            (15)
   105 │ #define BOARD_FLASH_SIZE               (_FLASH_KBYTES * 1024)
   106 │ 
```
> **说明**：_FLASH_KBYTES = *(uint32_t *)0x1FF1E880（hw_config.h:103）用 32 位读一个 16 位 flash size 寄存器
^src-boards-rm2027-fmu-h743-src-hw-config-h-103

<a id="src-boards-rm2027-fmu-h743-src-hw-config-h-104"></a>
**↓ 文档在讲这里：**[`boards/rm2027/fmu-h743/src/hw_config.h:104`](flash-layout.md#^src-boards-rm2027-fmu-h743-src-hw-config-h-104)

```c
   101 │ /* ★ 必须与 firmware.prototype 的 board_id 一致（本板 = 2027） */
   102 │ #define BOARD_TYPE                     2027
   103 │ #define _FLASH_KBYTES                  (*(uint32_t *)0x1FF1E880)
▶  104 │ #define BOARD_FLASH_SECTORS            (15)
   105 │ #define BOARD_FLASH_SIZE               (_FLASH_KBYTES * 1024)
   106 │ 
   107 │ #define OSC_FREQ                       8
```
> **说明**：⇒ fw_size | BOARD_FLASH_SIZE − 128 KiB | main.c:86 APP_SIZE_MAX → main.c:274 | ┃ 扇区上界 | BOARD_FLASH_SECTORS = 15 | hw_config.h:104 |
^src-boards-rm2027-fmu-h743-src-hw-config-h-104

<a id="src-boards-rm2027-fmu-h743-src-hw-config-h-120"></a>
**↓ 文档在讲这里：**[`boards/rm2027/fmu-h743/src/hw_config.h:120`](flash-layout.md#^src-boards-rm2027-fmu-h743-src-hw-config-h-120)

```c
   117 │ # define ARCH_SN_MAX_LENGTH 12
   118 │ #endif
   119 │ 
▶  120 │ #if !defined(APP_RESERVATION_SIZE)
   121 │ #  define APP_RESERVATION_SIZE 0
   122 │ #endif
   123 │ 
```
> **说明**：预留给自己 | 128 * 1024 | stm32_common/main.c:29 BOOTLOADER_RESERVATION_SIZE | ┃ app 预留 | APP_RESERVATION_SIZE，默认 0 | hw_config.h:120；且 compile_commands.json 里没有 -DAPP_RESERVATION_SIZE |
^src-boards-rm2027-fmu-h743-src-hw-config-h-120

<a id="src-boards-rm2027-fmu-h743-src-hw-config-h-124"></a>
**↓ 文档在讲这里：**[`boards/rm2027/fmu-h743/src/hw_config.h:124`](flash-layout.md#^src-boards-rm2027-fmu-h743-src-hw-config-h-124)

```c
   121 │ #  define APP_RESERVATION_SIZE 0
   122 │ #endif
   123 │ 
▶  124 │ #if !defined(BOARD_FIRST_FLASH_SECTOR_TO_ERASE)
   125 │ #  define BOARD_FIRST_FLASH_SECTOR_TO_ERASE 1
   126 │ #endif
   127 │ 
```
> **说明**：扇区上界 | BOARD_FLASH_SECTORS = 15 | hw_config.h:104 | ┃ 擦除下界 | BOARD_FIRST_FLASH_SECTOR_TO_ERASE = 1 | hw_config.h:124 |
^src-boards-rm2027-fmu-h743-src-hw-config-h-124

### `boards/rm2027/fmu-h743/src/init.c`
<a id="src-boards-rm2027-fmu-h743-src-init-c-196"></a>
**↓ 文档在讲这里：**[`boards/rm2027/fmu-h743/src/init.c:196`](flash-layout.md#^src-boards-rm2027-fmu-h743-src-init-c-196)

```c
   193 │ 	 *   cbunmanned/h753-som）全都是【只用一个扇区 {15, 128K, 0x081E0000}】。
   194 │ 	 *   flashfs 的 get_next_sector_descriptor() 在只有一项时会回到自己，
   195 │ 	 *   所以单扇区是合法配置（代价：没有扇区级磨损均衡）。
▶  196 │ 	 *   配套要求：script.ld 的 FLASH LENGTH 必须从 1920K 缩到 1792K，
   197 │ 	 *   把 0x081E0000 这个扇区让出来，否则链接器可能把代码放进去、
   198 │ 	 *   参数写入就会打烂代码。
   199 │ 	 */
```
> **说明**：init.c:196 的注释直接把"配套要求"写出来了：
^src-boards-rm2027-fmu-h743-src-init-c-196

<a id="src-boards-rm2027-fmu-h743-src-init-c-200"></a>
**↓ 文档在讲这里：**[`boards/rm2027/fmu-h743/src/init.c:200`](flash-layout.md#^src-boards-rm2027-fmu-h743-src-init-c-200)

```c
   197 │ 	 *   把 0x081E0000 这个扇区让出来，否则链接器可能把代码放进去、
   198 │ 	 *   参数写入就会打烂代码。
   199 │ 	 */
▶  200 │ 	static sector_descriptor_t params_sector_map[] = {
   201 │ 		{15, 128 * 1024, 0x081E0000},
   202 │ 		{0, 0, 0},
   203 │ 	};
```
> **说明**：用片内 flash 存参数 | #define FLASH_BASED_PARAMS | board_config.h:60（注释在 :58） | ┃ 参数扇区表 | {{15, 128*1024, 0x081E0000}, {0,0,0}} | init.c:200（★ 注释 :187-199 把理由写得很清楚） |
^src-boards-rm2027-fmu-h743-src-init-c-200

<a id="src-boards-rm2027-fmu-h743-src-init-c-201"></a>
**↓ 文档在讲这里：**[`boards/rm2027/fmu-h743/src/init.c:201`](flash-layout.md#^src-boards-rm2027-fmu-h743-src-init-c-201)

```c
   198 │ 	 *   参数写入就会打烂代码。
   199 │ 	 */
   200 │ 	static sector_descriptor_t params_sector_map[] = {
▶  201 │ 		{15, 128 * 1024, 0x081E0000},
   202 │ 		{0, 0, 0},
   203 │ 	};
   204 │ 
```
> **说明**：改了 script.ld 却"没变化" | 只影响 app 链接，不影响 bootloader 的 fw_size | §2 vs §3 | ┃ 用调试器读 0x081E0000 能看到参数 | init.c:201 | — |
^src-boards-rm2027-fmu-h743-src-init-c-201

<a id="src-boards-rm2027-fmu-h743-src-init-c-206"></a>
**↓ 文档在讲这里：**[`boards/rm2027/fmu-h743/src/init.c:206`](flash-layout.md#^src-boards-rm2027-fmu-h743-src-init-c-206)

```c
   203 │ 	};
   204 │ 
   205 │ 	/* Initialize the flashfs layer to use heap allocated memory */
▶  206 │ 	int result = parameter_flashfs_init(params_sector_map, NULL, 0);
   207 │ 
   208 │ 	if (result != OK) {
   209 │ 		syslog(LOG_ERR, "[boot] FAILED to init params in FLASH %d\n", result);
```
> **说明**：参数扇区表 | {{15, 128*1024, 0x081E0000}, {0,0,0}} | init.c:200（★ 注释 :187-199 把理由写得很清楚） | ┃ 初始化 | parameter_flashfs_init(params_sector_map, NULL, 0) | init.c:206 |
^src-boards-rm2027-fmu-h743-src-init-c-206

### `platforms/nuttx/NuttX/nuttx/arch/arm/src/stm32h7/stm32h743xx_flash.c`
<a id="src-platforms-nuttx-NuttX-nuttx-arch-arm-src-stm32h7-stm32h743xx-flash-c-717"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/NuttX/nuttx/arch/arm/src/stm32h7/stm32h743xx_flash.c:717`](flash-layout.md#^src-platforms-nuttx-NuttX-nuttx-arch-arm-src-stm32h7-stm32h743xx-flash-c-717)

```c
   714 │   return true;
   715 │ }
   716 │ 
▶  717 │ ssize_t up_progmem_ispageerased(size_t page)
   718 │ {
   719 │   size_t addr;
   720 │   size_t count;
```
> **说明**：main.c:484 的条件是 force || up_progmem_ispageerased(sector) != 0， ┃ 而 up_progmem_ispageerased() 返回非 0xFF 字节数（stm32h743xx_flash.c:717）
^src-platforms-nuttx-NuttX-nuttx-arch-arm-src-stm32h7-stm32h743xx-flash-c-717

### `platforms/nuttx/src/bootloader/common/bl.c`
<a id="src-platforms-nuttx-src-bootloader-common-bl-c-777"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:777`](flash-layout.md#^src-platforms-nuttx-src-bootloader-common-bl-c-777)

```c
   774 │ 			// erase all sectors
   775 │ 			arch_flash_unlock();
   776 │ 
▶  777 │ 			for (int i = 0; flash_func_sector_size(i) != 0; i++) {
   778 │ 				flash_func_erase_sector(i, full_erase);
   779 │ 			}
   780 │ 
```
> **说明**：1. 刷固件时参数扇区会被擦：bl.c:777 会遍历到扇区 15，
> **说明**：刷完固件参数回默认 | bl.c:777 擦到扇区 15 + main.c:484 的判定 | §5（推理，待上板判 ②） |
^src-platforms-nuttx-src-bootloader-common-bl-c-777

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-785"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:785`](flash-layout.md#^src-platforms-nuttx-src-bootloader-common-bl-c-785)

```c
   782 │ 			led_set(LED_OFF);
   783 │ 
   784 │ 			// verify the erase
▶  785 │ 			for (address = 0; address < board_info.fw_size; address += 4) {
   786 │ 				if (flash_func_read_word(address) != 0xffffffff) {
   787 │ 					goto cmd_fail;
   788 │ 				}
```
> **说明**：上位机算出的 CRC 会随参数变化 ⇒ 同版本固件刷两次，CRC 可能不同（若参数写过）。 ┃ 3. 擦后逐字校验也覆盖参数区（bl.c:785）⇒ 若参数扇区擦不干净，上传会 cmd_bad。
^src-platforms-nuttx-src-bootloader-common-bl-c-785

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-818"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:818`](flash-layout.md#^src-platforms-nuttx-src-bootloader-common-bl-c-818)

```c
   815 │ 				goto cmd_bad;
   816 │ 			}
   817 │ 
▶  818 │ 			if ((address + arg) > board_info.fw_size) {
   819 │ 				goto cmd_bad;
   820 │ 			}
   821 │ 
```
> **说明**：同版本固件刷两次，上位机校验值的 CRC 不同 | bl.c:902 的 CRC 范围含参数区 | §5 第 2 条 | ┃ bootloader 上传被拒（"超出 flash 范围"） | bl.c:818 用 fw_size 做上界 | — |
^src-platforms-nuttx-src-bootloader-common-bl-c-818

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-902"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:902`](flash-layout.md#^src-platforms-nuttx-src-bootloader-common-bl-c-902)

```c
   899 │ 			// compute CRC of the programmed area
   900 │ 			uint32_t sum = 0;
   901 │ 
▶  902 │ 			for (unsigned p = 0; p < board_info.fw_size; p += 4) {
   903 │ 				uint32_t bytes;
   904 │ 
   905 │ 				if ((p == APP_VECTOR_OFFSET) && (first_word != 0xffffffff)) {
```
> **说明**：⇒ 参数扇区里有数据 ⇒ 返回非 0 ⇒ 被擦掉。 ┃ 2. PROTO_GET_CRC 的校验范围包含参数区（bl.c:902 到 fw_size）⇒
> **说明**：参数毫无原因回默认（没刷固件） | ECC scrub 擦了扇区 15 | 02_code_twin/bootloader/ecc-scrub-c | ┃ 同版本固件刷两次，上位机校验值的 CRC 不同 | bl.c:902 的 CRC 范围含参数区 | §5 第 2 条 |
^src-platforms-nuttx-src-bootloader-common-bl-c-902

### `platforms/nuttx/src/bootloader/stm/stm32_common/main.c`
<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-274"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:274`](flash-layout.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-274)

```c
   271 │ board_init(void)
   272 │ {
   273 │ 	/* fix up the max firmware size, we have to read memory to get this */
▶  274 │ 	board_info.fw_size = APP_SIZE_MAX;
   275 │ 
   276 │ #if defined(BOARD_POWER_PIN_OUT)
   277 │ 	/* Configure the Power pins */
```
> **说明**：app 预留 | APP_RESERVATION_SIZE，默认 0 | hw_config.h:120；且 compile_commands.json 里没有 -DAPP_RESERVATION_SIZE | ┃ ⇒ fw_size | BOARD_FLASH_SIZE − 128 KiB | main.c:86 APP_SIZE_MAX → main.c:274 |
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-274

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-480"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:480`](flash-layout.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-480)

```c
   477 │ void
   478 │ flash_func_erase_sector(unsigned sector, bool force)
   479 │ {
▶  480 │ 	if (sector > BOARD_FLASH_SECTORS || (int)sector < BOARD_FIRST_FLASH_SECTOR_TO_ERASE) {
   481 │ 		return;
   482 │ 	}
   483 │ 
```
> **说明**：但擦除循环的终止条件不是 fw_size，是 bl.c:777 for (int i = 0; flash_func_sector_size(i) != 0; i++) ┃ ⇒ i 到 15 为止；再由 main.c:480 跳过 i < 1 ⇒ 扇区 1..15 都在候选内。
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-480

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-484"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:484`](flash-layout.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-484)

```c
   481 │ 		return;
   482 │ 	}
   483 │ 
▶  484 │ 	if (force || (up_progmem_ispageerased(sector) != 0)) {
   485 │ 		up_progmem_eraseblock(sector);
   486 │ 	}
   487 │ }
```
> **说明**：1. 刷固件时参数扇区会被擦：bl.c:777 会遍历到扇区 15， ┃ main.c:484 的条件是 force || up_progmem_ispageerased(sector) != 0，
> **说明**：刷完固件参数回默认 | bl.c:777 擦到扇区 15 + main.c:484 的判定 | §5（推理，待上板判 ②） |
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-484

### `platforms/nuttx/src/bootloader/stm/stm32h7/ecc_scrub.c`
<a id="src-platforms-nuttx-src-bootloader-stm-stm32h7-ecc-scrub-c-135"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32h7/ecc_scrub.c:135`](flash-layout.md#^src-platforms-nuttx-src-bootloader-stm-stm32h7-ecc-scrub-c-135)

```c
   132 │ 	px4_arch_gpiowrite(ECC_SCRUB_TIMING_GPIO, true);
   133 │ #endif
   134 │ 
▶  135 │ 	/* scan to the last physical sector: parameter sectors sit past
   136 │ 	 * BOARD_FLASH_SECTORS, and boards may have more than one */
   137 │ 	const unsigned last_sector = up_progmem_neraseblocks() - 1;
   138 │ 
```
> **说明**：⚠️ ecc_scrub.c:135 的注释说"parameter sectors sit past BOARD_FLASH_SECTORS"，
^src-platforms-nuttx-src-bootloader-stm-stm32h7-ecc-scrub-c-135
