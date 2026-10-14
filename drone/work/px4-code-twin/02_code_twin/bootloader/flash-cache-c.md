# `common/lib/flash_cache.c` —— 为什么 H7 上"写一个 word"要先攒 8 个

> **源码**：`platforms/nuttx/src/bootloader/common/lib/flash_cache.c`（163 行）+ `flash_cache.h`（74 行）
> **层**：① 通用（但只在②层调用它）
> **谁调它**：②层 `main.c:447 fc_reset()`、`:493 fc_write()`、`:503 fc_read()`
> **它是 ① 与 ② 之间唯一的"隐形中间层"**：`bl.c` 完全不知道它的存在

---

## 1. 运行时它处在哪：在一次 `flash_func_write_word` 的内部

```
bl.c:873  flash_func_write_word(address, word)
   └─ main.c:490  address += APP_LOAD_ADDRESS            ← 从"相对偏移"变成"绝对地址"
        └─ main.c:493  fc_write(address, word)            ← ★ 控制权进到本文件
             ├─ fmc.c:94  fc_line_select(address)         ← 这个地址落在哪条缓存行？
             ├─ fmc.c:106 fc->words[index] = word         ← 【只写 RAM】
             ├─ fmc.c:110-127 若"回到首字"⇒ 刷两条缓存行并真正落盘
             └─ 返回（调用者以为"写完了"）
```

**⇒ 关键认知：[`bl.c:876`](flash-cache-c.md#^src-platforms-nuttx-src-bootloader-common-bl-c-876) 那句"写完立即读回校验"在这个平台上读的是 RAM 缓存，不是 flash。**
真正落盘发生在两个时机：
1. 某条缓存行的**第 8 个 word** 被写入时（`fc_write` 会在下一次换行前 flush）；
2. **回到 `APP_LOAD_ADDRESS` 的首字**（`fmc.c:110-127`）——这是"上传结束"的信号。

---

## 2. 为什么必须有这一层（[`flash_cache.h:35`](flash-cache-c.md#^src-platforms-nuttx-src-bootloader-common-lib-flash-cache-h-35) 的注释 + 代码）

| 约束 | 后果 | 本文件的对策 |
|---|---|---|
| H7 flash 控制器按 **256 bit = 32 B = 8 word** 为单位做 ECC 编程 | 不能单字写 | `FC_NUMBER_WORDS = 8`（[`flash_cache.h:55`](flash-cache-c.md#^src-platforms-nuttx-src-bootloader-common-lib-flash-cache-h-55)，非 i.MXRT 时） |
| bootloader 协议是"逐 word 下发"的（[`bl.c:861`](flash-cache-c.md#^src-platforms-nuttx-src-bootloader-common-bl-c-861) 每 4 字节一次） | 上层语义 ≠ 硬件语义 | 加一层 RAM 缓存做**翻译** |
| 读回校验必须在缓存里也能得到正确答案 | 否则"写失败"会被判成功 | `fc_read()` 命中缓存时返回缓存值（`fmc.c:143-149`），并在**读最后一个 word** 时 flush（`:152-159`）；flush 失败则把返回值**按位取反**（`:154`）⇒ 上层校验必然失败 |

**⇒ 一句话：这一层把"H7 必须成块写"这件事，对 ①层的逐字写/逐字读接口完全隐藏了。**

---

## 3. 两条缓存行的语义（`FC_NUMBER_LINES = 2`，[`flash_cache.h:57`](flash-cache-c.md#^src-platforms-nuttx-src-bootloader-common-lib-flash-cache-h-57)）

| 缓存行 | 什么时候被选中 | 用途 |
|---|---|---|
| `flash_cache[0]` | **首字所在的那 8 个 word**（`fmc.c:60` 在 `fc_reset()` 里把它的 `start_address` 预置为 `APP_LOAD_ADDRESS + APP_VECTOR_OFFSET`） | 让 `bl.c` 的"首字延迟提交"能工作 |
| `flash_cache[1]` | 任何**新的 8 字块**（`fc_write` 里 `index == 0` 且没命中时 `fc = fc1`，`fmc.c:99-102`） | 顺序上传时的滚动缓冲 |

### ★ 与 `bl.c` 首字延迟提交的配合（这是本文件最妙的地方）

```
bl.c:855  把首字在 buffer 里改成 0xffffffff 然后才交给 fc_write
          ⇒ 首字所在缓存行被写成 "0xffffffff + 后续 7 个真 word"
             —— 但这一行【不会落盘】，因为 bl.c:842 的 address == APP_VECTOR_OFFSET 判断
                只在"上传到首字那一刻"成立；之后上传继续往 fc1 里走
bl.c:1119 收到 PROTO_BOOT 才用真值再写一次首字
   └─ fmc.c:110  "回到首字 + 缓存行已满" ⇒ 先把 fc1（上一个不满的尾巴）flush，再 flush fc0
      ⇒ 【首字和它后面 7 个 word 在同一个不可分割的 ECC 块里落盘】
      ⇒ 掉电时要么全有效要么全无效，不存在"半有效 app"
```

> `fmc.c:110` 的判断条件是 `fc == &flash_cache[0] && index == 0 && fc->index == FC_LAST_WORD`
> ⇒ 只有当**首字那一行已经写满 8 个**、且**现在又回来写首字**时才触发。这和 `bl.c` 的调用序正好吻合。

---

## 4. `fc_reset()`：谁在什么时候调

| 行号 | 调用点 | 意义 |
|---|---|---|
| [`main.c:447`](flash-cache-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-447) | `arch_flash_unlock()` 里 | ★ 每次**擦除前**把缓存行全部置 `0xff`，并重新把 `flash_cache[0]` 指向 `APP_LOAD_ADDRESS + APP_VECTOR_OFFSET` |
| [`bl.c:775`](flash-cache-c.md#^src-platforms-nuttx-src-bootloader-common-bl-c-775) | `PROTO_CHIP_ERASE` 分支 | 擦除前 → 见上 |

**⇒ "擦除"这个动作在软件里同时要干三件事**：解锁 flash（[`main.c:448`](flash-cache-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-448)）、清缓存（[`main.c:447`](flash-cache-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-447)）、切状态位（[`bl.c:792`](flash-cache-c.md#^src-platforms-nuttx-src-bootloader-common-bl-c-792)）。
第三件归 ①层，前两件归 ②层。

---

## 5. "我看到的现象由谁产生"

| 现象 | 由谁 | 依据 |
|---|---|---|
| [`bl.c:876`](flash-cache-c.md#^src-platforms-nuttx-src-bootloader-common-bl-c-876) 的"读回校验"没抓到某次写失败 | `fc_read` 在缓存命中时读 RAM | `fmc.c:143-149` |
| 上传到"首字"位置时**体感卡一下** | 回到首字会触发**连带 flush 两条缓存行** | `fmc.c:110-127` |
| 首字写失败时报的是 `INSYNC/FAILED` 而不是"数据错" | flush 失败 ⇒ 返回值取反 ⇒ 上层校验失败 ⇒ `bl.c:877 cmd_fail` | `fmc.c:154` |
| H7 上偶发的 `DBECCERR`（不可纠错 ECC） | 半页写入被掉电打断 | → [02_code_twin/bootloader/ecc-scrub-c](ecc-scrub-c.md) |

---

## 跳转

- **执行序上一步**（谁调它）：[02_code_twin/bootloader/bl-c](bl-c.md) §3 `PROTO_PROG_MULTI` / §5 首字延迟提交。
- **执行序下一步**（它调谁）：`main.c:452 arch_flash_write()` ⇒ `up_progmem_write()`（NuttX STM32H7 flash 驱动）。
  这属于 NuttX 内核层，本套不展开；如需追则读 `nuttx/arch/arm/src/stm32h7/stm32_flash.c`。
- **为什么 H7 会有 ECC 坏扇区、怎么被静默修掉** → [02_code_twin/bootloader/ecc-scrub-c](ecc-scrub-c.md)。
- **flash 扇区布局** → [01_extracted/stm32/flash-layout](../../01_extracted/stm32/flash-layout.md)。

---

## 未核实

- [`flash_cache.h:52`](flash-cache-c.md#^src-platforms-nuttx-src-bootloader-common-lib-flash-cache-h-52) 里 `CONFIG_ARCH_CHIP_IMXRT` 分支（64 word/行）与本次无关，未展开。
- `fmc.c:110` 那条触发条件我只做了**代码级路径分析**（bl.c 的调用序 → fc 状态），**未上板用调试器验证**。

---

## 标注源码（代码 + 本文档对它的解释）

> **这是「代码孪生」层**：上面是代码原文（带行号），下面是**本文档针对这一段说的话**。
> 行号可点，直接跳到 PX4 源码那一行。
### `platforms/nuttx/src/bootloader/common/bl.c`
<a id="src-platforms-nuttx-src-bootloader-common-bl-c-775"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:775`](flash-cache-c.md#^src-platforms-nuttx-src-bootloader-common-bl-c-775)

```c
   772 │ 			led_set(LED_ON);
   773 │ 
   774 │ 			// erase all sectors
▶  775 │ 			arch_flash_unlock();
   776 │ 
   777 │ 			for (int i = 0; flash_func_sector_size(i) != 0; i++) {
   778 │ 				flash_func_erase_sector(i, full_erase);
```
> **说明**：main.c:447 | arch_flash_unlock() 里 | ★ 每次擦除前把缓存行全部置 0xff，并重新把 flash_cache[0] 指向 APP_LOAD_ADDRESS + APP_VECTOR_OFFSET | ┃ bl.c:775 | PROTO_CHIP_ERASE 分支 | 擦除前 → 见上 |
^src-platforms-nuttx-src-bootloader-common-bl-c-775

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-792"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:792`](flash-cache-c.md#^src-platforms-nuttx-src-bootloader-common-bl-c-792)

```c
   789 │ 			}
   790 │ 
   791 │ 			address = 0;
▶  792 │ 			SET_BL_STATE(STATE_PROTO_CHIP_ERASE);
   793 │ 
   794 │ 			// resume blinking
   795 │ 			led_set(LED_BLINK);
```
> **说明**：⇒ "擦除"这个动作在软件里同时要干三件事：解锁 flash（main.c:448）、清缓存（main.c:447）、切状态位（bl.c:792）。
^src-platforms-nuttx-src-bootloader-common-bl-c-792

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-842"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:842`](flash-cache-c.md#^src-platforms-nuttx-src-bootloader-common-bl-c-842)

```c
   839 │ 
   840 │ #if APP_VECTOR_OFFSET == 0
   841 │ 
▶  842 │ 			if (address == APP_VECTOR_OFFSET) {
   843 │ 
   844 │ #  if defined(TARGET_HW_PX4_FMU_V4)
   845 │ 
```
> **说明**：—— 但这一行【不会落盘】，因为 bl.c:842 的 address == APP_VECTOR_OFFSET 判断
^src-platforms-nuttx-src-bootloader-common-bl-c-842

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-855"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:855`](flash-cache-c.md#^src-platforms-nuttx-src-bootloader-common-bl-c-855)

```c
   852 │ 				// save the first word and don't program it until everything else is done
   853 │ 				first_word = flash_buffer.w[0];
   854 │ 				// replace first word with bits we can overwrite later
▶  855 │ 				flash_buffer.w[0] = 0xffffffff;
   856 │ 			}
   857 │ 
   858 │ #endif
```
> **说明**：bl.c:855 把首字在 buffer 里改成 0xffffffff 然后才交给 fc_write
^src-platforms-nuttx-src-bootloader-common-bl-c-855

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-861"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:861`](flash-cache-c.md#^src-platforms-nuttx-src-bootloader-common-bl-c-861)

```c
   858 │ #endif
   859 │ 			arg /= 4;
   860 │ 
▶  861 │ 			for (int i = 0; i < arg; i++) {
   862 │ #if APP_VECTOR_OFFSET != 0
   863 │ 
   864 │ 				if (address == APP_VECTOR_OFFSET) {
```
> **说明**：H7 flash 控制器按 256 bit = 32 B = 8 word 为单位做 ECC 编程 | 不能单字写 | FC_NUMBER_WORDS = 8（flash_cache.h:55，非 i.MXRT 时） | ┃ bootloader 协议是"逐 word 下发"的（bl.c:861 每 4 字节一次） | 上层语义 ≠ 硬件语义 | 加一层 RAM 缓存做翻译 |
^src-platforms-nuttx-src-bootloader-common-bl-c-861

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-873"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:873`](flash-cache-c.md#^src-platforms-nuttx-src-bootloader-common-bl-c-873)

```c
   870 │ 
   871 │ #endif
   872 │ 				// program the word
▶  873 │ 				flash_func_write_word(address, flash_buffer.w[i]);
   874 │ 
   875 │ 				// do immediate read-back verify
   876 │ 				if (flash_func_read_word(address) != flash_buffer.w[i]) {
```
> **说明**：bl.c:873 flash_func_write_word(address, word)
^src-platforms-nuttx-src-bootloader-common-bl-c-873

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-876"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:876`](flash-cache-c.md#^src-platforms-nuttx-src-bootloader-common-bl-c-876)

```c
   873 │ 				flash_func_write_word(address, flash_buffer.w[i]);
   874 │ 
   875 │ 				// do immediate read-back verify
▶  876 │ 				if (flash_func_read_word(address) != flash_buffer.w[i]) {
   877 │ 					goto cmd_fail;
   878 │ 				}
   879 │ 
```
> **说明**：⇒ 关键认知：bl.c:876 那句"写完立即读回校验"在这个平台上读的是 RAM 缓存，不是 flash。
> **说明**：bl.c:876 的"读回校验"没抓到某次写失败 | fc_read 在缓存命中时读 RAM | fmc.c:143-149 |
^src-platforms-nuttx-src-bootloader-common-bl-c-876

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-1119"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:1119`](flash-cache-c.md#^src-platforms-nuttx-src-bootloader-common-bl-c-1119)

```c
  1116 │ 
  1117 │ 			// program the deferred first word
  1118 │ 			if (first_word != 0xffffffff) {
▶ 1119 │ 				flash_func_write_word(APP_VECTOR_OFFSET, first_word);
  1120 │ 
  1121 │ 				if (flash_func_read_word(APP_VECTOR_OFFSET) != first_word) {
  1122 │ 					goto cmd_fail;
```
> **说明**：bl.c:1119 收到 PROTO_BOOT 才用真值再写一次首字
^src-platforms-nuttx-src-bootloader-common-bl-c-1119

### `platforms/nuttx/src/bootloader/common/lib/flash_cache.h`
<a id="src-platforms-nuttx-src-bootloader-common-lib-flash-cache-h-35"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/lib/flash_cache.h:35`](flash-cache-c.md#^src-platforms-nuttx-src-bootloader-common-lib-flash-cache-h-35)

```c
    32 │  ****************************************************************************/
    33 │ #pragma once
    34 │ 
▶   35 │ /* The modern flash controllers manage flash for ECC
    36 │  * On the H7 there is a block size (256) bits
    37 │  * This code translates between the bootloaders word read/write
    38 │  * interface and the H7 need for block based writes.
```
> **说明**：2. 为什么必须有这一层（flash_cache.h:35 的注释 + 代码）
^src-platforms-nuttx-src-bootloader-common-lib-flash-cache-h-35

<a id="src-platforms-nuttx-src-bootloader-common-lib-flash-cache-h-52"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/lib/flash_cache.h:52`](flash-cache-c.md#^src-platforms-nuttx-src-bootloader-common-lib-flash-cache-h-52)

```c
    49 │  * On a imxrt the ROM API supports 256 byte writes.
    50 │  */
    51 │ 
▶   52 │ #if defined(CONFIG_ARCH_CHIP_IMXRT)
    53 │ #define FC_NUMBER_WORDS  64                                  // Number of words per page
    54 │ #else
    55 │ #define FC_NUMBER_WORDS  8                                  // Number of words per cache line.
```
> **说明**：flash_cache.h:52 里 CONFIG_ARCH_CHIP_IMXRT 分支（64 word/行）与本次无关，未展开。
^src-platforms-nuttx-src-bootloader-common-lib-flash-cache-h-52

<a id="src-platforms-nuttx-src-bootloader-common-lib-flash-cache-h-55"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/lib/flash_cache.h:55`](flash-cache-c.md#^src-platforms-nuttx-src-bootloader-common-lib-flash-cache-h-55)

```c
    52 │ #if defined(CONFIG_ARCH_CHIP_IMXRT)
    53 │ #define FC_NUMBER_WORDS  64                                  // Number of words per page
    54 │ #else
▶   55 │ #define FC_NUMBER_WORDS  8                                  // Number of words per cache line.
    56 │ #endif
    57 │ #define FC_NUMBER_LINES  2                                  // Number of cache lines.
    58 │ #define FC_LAST_WORD     FC_NUMBER_WORDS-1                  // The index of the last word in cache line.
```
> **说明**：H7 flash 控制器按 256 bit = 32 B = 8 word 为单位做 ECC 编程 | 不能单字写 | FC_NUMBER_WORDS = 8（flash_cache.h:55，非 i.MXRT 时） |
^src-platforms-nuttx-src-bootloader-common-lib-flash-cache-h-55

<a id="src-platforms-nuttx-src-bootloader-common-lib-flash-cache-h-57"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/lib/flash_cache.h:57`](flash-cache-c.md#^src-platforms-nuttx-src-bootloader-common-lib-flash-cache-h-57)

```c
    54 │ #else
    55 │ #define FC_NUMBER_WORDS  8                                  // Number of words per cache line.
    56 │ #endif
▶   57 │ #define FC_NUMBER_LINES  2                                  // Number of cache lines.
    58 │ #define FC_LAST_WORD     FC_NUMBER_WORDS-1                  // The index of the last word in cache line.
    59 │ #define FC_ADDRESS_MASK  ~(sizeof(flash_cache[0].words)-1)  // Cache tag from address
    60 │ #define FC_ADDR2INDX(a)   (((a) / sizeof(flash_cache[0].words[0])) % FC_NUMBER_WORDS) // index from address
```
> **说明**：3. 两条缓存行的语义（FC_NUMBER_LINES = 2，flash_cache.h:57）
^src-platforms-nuttx-src-bootloader-common-lib-flash-cache-h-57

### `platforms/nuttx/src/bootloader/stm/stm32_common/main.c`
<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-447"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:447`](flash-cache-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-447)

```c
   444 │ 
   445 │ void arch_flash_unlock(void)
   446 │ {
▶  447 │ 	fc_reset();
   448 │ 	stm32h7_flash_unlock(STM32_FLASH_BANK1);
   449 │ 	stm32h7_flash_unlock(STM32_FLASH_BANK2);
   450 │ }
```
> **说明**：main.c:447 | arch_flash_unlock() 里 | ★ 每次擦除前把缓存行全部置 0xff，并重新把 flash_cache[0] 指向 APP_LOAD_ADDRESS + APP_VECTOR_OFFSET |
> **说明**：⇒ "擦除"这个动作在软件里同时要干三件事：解锁 flash（main.c:448）、清缓存（main.c:447）、切状态位（bl.c:792）。
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-447

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-448"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:448`](flash-cache-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-448)

```c
   445 │ void arch_flash_unlock(void)
   446 │ {
   447 │ 	fc_reset();
▶  448 │ 	stm32h7_flash_unlock(STM32_FLASH_BANK1);
   449 │ 	stm32h7_flash_unlock(STM32_FLASH_BANK2);
   450 │ }
   451 │ 
```
> **说明**：⇒ "擦除"这个动作在软件里同时要干三件事：解锁 flash（main.c:448）、清缓存（main.c:447）、切状态位（bl.c:792）。
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-448

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-490"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:490`](flash-cache-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-490)

```c
   487 │ }
   488 │ 
   489 │ void
▶  490 │ flash_func_write_word(uintptr_t address, uint32_t word)
   491 │ {
   492 │ 	address += APP_LOAD_ADDRESS;
   493 │ 	fc_write(address, word);
```
> **说明**：└─ main.c:490 address += APP_LOAD_ADDRESS ← 从"相对偏移"变成"绝对地址"
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-490

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-493"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:493`](flash-cache-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-493)

```c
   490 │ flash_func_write_word(uintptr_t address, uint32_t word)
   491 │ {
   492 │ 	address += APP_LOAD_ADDRESS;
▶  493 │ 	fc_write(address, word);
   494 │ }
   495 │ 
   496 │ uint32_t flash_func_read_word(uintptr_t address)
```
> **说明**：└─ main.c:493 fc_write(address, word) ← ★ 控制权进到本文件
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-493
