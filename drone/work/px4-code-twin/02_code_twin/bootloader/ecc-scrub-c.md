# `stm/stm32h7/ecc_scrub.c` —— H7 的"防砖"补丁：静默擦掉坏扇区

> **源码**：`platforms/nuttx/src/bootloader/stm/stm32h7/ecc_scrub.c`（155 行）+ `ecc_scrub.h`（13 行）
> **层**：② 芯片族（**只属于 H7**；由 [`stm32h7/CMakeLists.txt:36`](ecc-scrub-c.md#^src-CMakeLists-txt-36) 追加进 `arch_bootloader`）
> **状态**：`git cat-file -e upstream/main:...ecc_scrub.c` ⇒ **存在** ⇒ 这是**上游 PX4 代码，不是本项目的补丁**

---

## 1. 运行时它处在哪：`bootloader_main` 里**第一个**动作

```
main.c:660 bootloader_main()
main.c:666 SCB_CPACR |= ...           ← 开 FPU
main.c:682 board_init()               ← fw_size = APP_SIZE_MAX
main.c:685 clock_init()               ← 【空】
main.c:687 #if defined(CONFIG_ARCH_CHIP_STM32H7)
main.c:689     check_ecc_errors();    ← ★ 控制权进本文件
main.c:690 #endif
main.c:696 之后才开始判"跳不跳"
```

**⇒ 它在任何决策之前跑，而且每！次！上电！都！跑！**
（不是只在"要刷固件"时才跑。）

---

## 2. 它到底干了什么（[`ecc_scrub.c:125`](ecc-scrub-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32h7-ecc-scrub-c-125)）

```
check_ecc_errors():
  :127-128  开 DMA1 时钟（ECC 靠 DMA 读触发）
  :137      last_sector = up_progmem_neraseblocks() - 1     ← 扫到【最后一个物理扇区】
  :139      for sector = BOARD_FIRST_FLASH_SECTOR_TO_ERASE .. last_sector:
  :140          base = APP_LOAD_ADDRESS + (sector - BOARD_FIRST_FLASH_SECTOR_TO_ERASE) * FLASH_SECTOR_SIZE
  :142          if flash_region_has_ecc_error(base, FLASH_SECTOR_SIZE):
  :143              ecc_flags_clear()
  :144              up_progmem_eraseblock(sector)            ← ★★ 直接擦掉整个扇区
  :149-150  收尾：停 DMA、清 ECC 标志
```

**⇒ 现象上它是完全静默的：没有打印、没有返回值、没有状态位。**
它的唯一外部可观测效果 = **某个 128 KiB 扇区的内容变成了全 `0xff`**。

### 2.1 怎么"读"出 ECC 错误（[`ecc_scrub.c:84`](ecc-scrub-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32h7-ecc-scrub-c-84)）

| 步骤 | 行号 | 为什么这么写 |
|---|---|---|
| 分块扫（每块 1 KiB = 256 word） | `:56` `ECC_CHUNK_WORDS 256`、`:86` 循环 | 一次性读完整个扇区会把 512 B 的 DMA 缓冲撑爆；且分块能定位到"哪一块坏了" |
| 用 **DMA1 内存→内存** 搬运 | `:96-103` | H7 的 flash ECC 错误是**读操作触发**的；用 DMA 读才能又快又不占 CPU |
| 目的地放 `.bss`（AXI SRAM `0x24000000`） | `:62-63` 注释 + `:99` | DMA1 到不了 DTCM |
| 查 `FLASH_SR1/SR2` 的 `DBECCERR (bit 26)` | `:111-113` | 双位错 = 不可纠错 = 必须擦掉重写 |
| **要求 `TCIF` 置位才算"干净"** | `:117-119` | 注释原文：流也可能因**非 ECC 总线错误**而停 ⇒ 那样必须"跳过扫描"而不是"判定通过" |
| DMA 加超时上限 | `:73` `ECC_DMA_TIMEOUT 2000000`、`:91`/`:106` | 注释原文：*"bounded so a misbehaving DMA can never hang the bootloader"* |

---

## 3. 它扫哪些扇区？（和 app 的参数区直接相关）

| 量 | 值 | 依据 |
|---|---|---|
| 起点 | `BOARD_FIRST_FLASH_SECTOR_TO_ERASE` | 本板 [`hw_config.h:124`](stm32-common-main-c.md#^src-boards-rm2027-fmu-h743-src-hw-config-h-124) ⇒ **1**（跳过扇区 0 = bootloader 自己） |
| 终点 | `up_progmem_neraseblocks() - 1` | [`ecc_scrub.c:137`](ecc-scrub-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32h7-ecc-scrub-c-137)；`up_progmem_neraseblocks()` 返回 `PROGMEM_NBLOCKS`（[`stm32h743xx_flash.c:707`](ecc-scrub-c.md#^src-platforms-nuttx-NuttX-nuttx-arch-arm-src-stm32h7-stm32h743xx-flash-c-707)）= `STM32_FLASH_NBLOCKS` |
| ⇒ 终点实测值 | **15** | `STM32_FLASH_NBLOCKS = 16`（[`stm32h743xx_flash.c:130`](ecc-scrub-c.md#^src-platforms-nuttx-NuttX-nuttx-arch-arm-src-stm32h7-stm32h743xx-flash-c-130)）← **由 `CONFIG_STM32H7_FLASH_CONFIG_I=y` 选中**，该键在两个构建的 `.config` 里都是 `y`（bl `.config:265`、app `.config:298`） |
| 每扇区跨度 | `FLASH_SECTOR_SIZE` | 定义在 [`ecc_scrub.h:9`](ecc-scrub-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32h7-ecc-scrub-h-9) = **128 KiB**（[`main.c:463`](ecc-scrub-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-463) 的兜底默认值不会生效，因为 [`main.c:23`](ecc-scrub-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-23) 已经 `#include "ecc_scrub.h"`） |

**⇒ 扫描范围 = 扇区 1..15 = `0x08020000` .. `0x081FFFFF`，包含参数扇区。**

### ★ 由此得到一条重要的失败模式

| 坏在哪 | 会发生什么 |
|---|---|
| **app 区**（扇区 1..14） | 该扇区被擦 ⇒ app 首字可能变 `0xffffffff` ⇒ [`bl.c:317`](image-toc-crypto.md#^src-platforms-nuttx-src-bootloader-common-bl-c-317) 判 app 无效 ⇒ **留在 bootloader** |
| **参数扇区**（扇区 15） | 整个扇区被擦 ⇒ **参数静默回默认值**（下一步 `rcS` 的 `param load-or-init` 会走"空白存储首次播种"分支，见 [01_extracted/nuttx/nsh-and-rcS](../../01_extracted/nuttx/nsh-and-rcS.md)） |

**⇒ 用户视角的现象是"参数莫名其妙回默认了"，而不是任何一条错误日志。这就是它的危险之处。**

---

## 4. 为什么 H7 需要它

### 4.1 先搞清"擦除"到底怎么判（回验后与直觉相反，这里给出准确语义）

```c
main.c:477-487
void flash_func_erase_sector(unsigned sector, bool force)
{
    if (sector > BOARD_FLASH_SECTORS || (int)sector < BOARD_FIRST_FLASH_SECTOR_TO_ERASE) return;  // :480-482
    if (force || (up_progmem_ispageerased(sector) != 0)) {                                        // :484
        up_progmem_eraseblock(sector);
    }
}
```

`up_progmem_ispageerased()` 在 NuttX H7 上的实现是**数"非 0xFF 的字节个数"**：

```
nuttx/arch/arm/src/stm32h7/stm32h743xx_flash.c:717-740
  for (addr = up_progmem_getaddress(page), count = up_progmem_pagesize(page); count; count--, addr++)
      if (getreg8(addr) != FLASH_ERASEDVALUE) bwritten++;
  return bwritten;
```

且 `FLASH_PAGE_SIZE = 32`（同名文件 `:86`）、`FLASH_NPAGES = FLASH_SIZE/32`（`:151`）、
`up_progmem_pagesize()` 恒返回 32（`:676-679`）。

**⇒ 含义翻转**：
- 返回值 **0** = 该"页"全 `0xff` ⇒ bootloader **跳过**（不擦，省寿命）；
- 返回值 **≠0** = **有数据** ⇒ **擦掉它**。

**⇒ 所以普通 `PROTO_CHIP_ERASE`（[`bl.c:778`](ecc-scrub-c.md#^src-platforms-nuttx-src-bootloader-common-bl-c-778) 传 `full_erase = false`，默认值定义在 [`bl.c:666`](ecc-scrub-c.md#^src-platforms-nuttx-src-bootloader-common-bl-c-666)）
不是"什么都不擦"，而是"把有数据的扇区擦掉、空白扇区跳过"。**

> ⚠️ 顺带一个小事实（**赋值给 [01_extracted/stm32/flash-layout](../../01_extracted/stm32/flash-layout.md)**）：
> bootloader 传进去的 `sector`（0..15）被 `up_progmem_ispageerased()` 当成**页号**用，
> 而 H7 上"页" = 32 B ⇒ **它实际只检查了该扇区的头 32 字节**，不是整个 128 KiB。
> 这是"用头部 32 B 代表整个扇区"的启发式，对顺序写入的固件几乎总成立，但**不是严格判据**。

### 4.2 那为什么还需要 ECC scrub

1. H7 flash 按 8 word（32 B）为一个 ECC 块（引用上游注释 [`flash_cache.h:35`](flash-cache-c.md#^src-platforms-nuttx-src-bootloader-common-lib-flash-cache-h-35)，见 [02_code_twin/bootloader/flash-cache-c](flash-cache-c.md)）。
2. 一次"写在 ECC 块中间被打断"的编程会留下**单/双位错**块；这类块被读到就置 `DBECCERR`，
   **而这正好发生在 4.1 那套判断之前**（`getreg8(addr)` 读头部 32 B 本身就会触发）。
3. `check_ecc_errors()` 先用 **DMA** 把整个扇区读一遍（DMA 出错不会让 CPU 取指崩），
   发现 `DBECCERR` 就**立刻 `up_progmem_eraseblock()` 把该扇区擦干净**（[`ecc_scrub.c:142`](ecc-scrub-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32h7-ecc-scrub-c-142)），
   再清 ECC 标志（`:143`）。
4. ⇒ 它把"读一下就崩/报错的脏扇区"在**任何人读它之前**变成"干净空扇区"。

> **第 1-4 条里，第 2、3 条是推理**；第 1 条是上游注释；[`ecc_scrub.c:142`](ecc-scrub-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32h7-ecc-scrub-c-142) 的行为是代码事实。
> 可验证的观测口子：
> - 用 [`ecc_scrub.c:58`](ecc-scrub-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32h7-ecc-scrub-c-58) 那个被注释掉的 `ECC_SCRUB_TIMING_GPIO`（PI0）打开，示波器量扫描窗口；
> - 上板判据（区分"scrub 在起作用"和"没起作用"）：
>   **在上传 `PROG_MULTI` 中途断电一次 → 再上电 → 看能不能立刻重新上传成功**。
>   有 scrub ⇒ 脏扇区被自动擦掉 ⇒ 能刷；无 scrub ⇒ 该扇区读/写都会报 ECC 错，需要先整片擦。

### 4.1 一个可选的观测口子（代码里现成的）

[`ecc_scrub.c:58`](ecc-scrub-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32h7-ecc-scrub-c-58) 留了一个被注释掉的引脚定义：

```c
// #define ECC_SCRUB_TIMING_GPIO   /* PI0 = FMU_CH1 */
```

打开它（[`ecc_scrub.c:130`](ecc-scrub-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32h7-ecc-scrub-c-130) / `:152-154` 就会生效），就能用**示波器量出扫描耗时**。
⇒ 这是"想确认 scrub 真的在跑、跑了多久"的现成手段，**不需要改动逻辑**。

---

## 5. "我看到的现象由谁产生"

| 现象 | 由 `ecc_scrub.c` 的哪一行 | 说明 |
|---|---|---|
| 参数莫名回默认 | `:144` | 参数扇区被判定有 ECC 错 ⇒ 整个扇区被擦 |
| 刷完固件第一次启动特别慢 | `:139` 循环全扫 | 扫 15 个扇区 × 每扇区 128 KiB，全程 DMA |
| 上传中途断电后还能重刷 | `:142-145` | 坏扇区被自动擦掉 |
| 上电后 app "突然过不了校验" | `:144` 擦到了 app 区 | 首字被擦成 `0xff` |
| 扫描根本没发生（DMA 卡住时） | `:93` / `:108` | 返回 `false` ⇒ **跳过**该扇区扫描，"回退到普通启动"（注释原话） |
| 只量到一次 128 KiB 的毛刺 | `:131` / `:153` | `ECC_SCRUB_TIMING_GPIO` 打开后，引脚在整个扫描期间为高 |

---

## 跳转

- **执行序下一步**：`ecc_scrub.c` 返回 ⇒ 回到 [`main.c:696`](ecc-scrub-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-696)，开始 4 个决策点 ⇒ [02_code_twin/bootloader/stm32-common-main-c](stm32-common-main-c.md)。
- **执行序上一步**（谁把它编进来）：[02_code_twin/bootloader/cmakelists](cmakelists.md)（[`stm32h7/CMakeLists.txt:36`](ecc-scrub-c.md#^src-CMakeLists-txt-36) 追加 `ecc_scrub.c` 到 `arch_bootloader`）。
- **它为什么能"读到"ECC 错**（H7 8 字 ECC 块）→ [02_code_twin/bootloader/flash-cache-c](flash-cache-c.md)。
- **它擦掉的参数扇区后来怎么被重新播种** → [01_extracted/nuttx/nsh-and-rcS](../../01_extracted/nuttx/nsh-and-rcS.md)（`param load-or-init`）。
- **flash 布局（哪个扇区是什么）** → [01_extracted/stm32/flash-layout](../../01_extracted/stm32/flash-layout.md)。

---

## 未核实

- **H7 的 ECC 块大小到底是 256 bit 还是别的**：我只引用了上游注释 [`flash_cache.h:35`](flash-cache-c.md#^src-platforms-nuttx-src-bootloader-common-lib-flash-cache-h-35)（*"On the H7 there is a block size (256) bits"*），
  **未**回 ST 参考手册核实。标记为"引用上游注释"。
- §4.2 的"第 2、3 条"（ECC 块被打断 ⇒ 读就报错 ⇒ 必须擦）是**推理**；[`ecc_scrub.c:142`](ecc-scrub-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32h7-ecc-scrub-c-142) 的行为本身是代码事实。
- [`ecc_scrub.c:135`](ecc-scrub-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32h7-ecc-scrub-c-135) 注释说"参数扇区在 `BOARD_FLASH_SECTORS` 之外"——
  **实际上本板参数扇区 15 恰好在 `BOARD_FLASH_SECTORS=15` 之内**，所以这句注释和本板配置**对不上**。
  我**没有**去找上游是否改过 `BOARD_FLASH_SECTORS` 的定义；标"注释与本板配置不一致，原因未核实"。

---

## 标注源码（代码 + 本文档对它的解释）

> **这是「代码孪生」层**：上面是代码原文（带行号），下面是**本文档针对这一段说的话**。
> 行号可点，直接跳到 PX4 源码那一行。
### `CMakeLists.txt`
<a id="src-CMakeLists-txt-36"></a>
**↓ 文档在讲这里：**[`CMakeLists.txt:36`](ecc-scrub-c.md#^src-CMakeLists-txt-36)

```c
    33 │ 
    34 │ #=============================================================================
    35 │ # CMAKE CODING STANDARD FOR PX4
▶   36 │ #
    37 │ # Structure
    38 │ # ---------------------------------------------------------------------------
    39 │ #
```
> **说明**：源码：platforms/nuttx/src/bootloader/stm/stm32h7/ecc_scrub.c（155 行）+ ecc_scrub.h（13 行） ┃ 层：② 芯片族（只属于 H7；由 stm32h7/CMakeLists.txt:36 追加进 arch_bootloader）
> **说明**：执行序下一步：ecc_scrub.c 返回 ⇒ 回到 main.c:696，开始 4 个决策点 ⇒ 02_code_twin/bootloader/stm32-common-main-c。 ┃ 执行序上一步（谁把它编进来）：02_code_twin/bootloader/cmakelists（stm32h7/CMakeLists.txt:36 追加 ecc_scrub.c 到 arch_bootloader）。
^src-CMakeLists-txt-36

### `boards/rm2027/fmu-h743/src/hw_config.h`
<a id="src-boards-rm2027-fmu-h743-src-hw-config-h-124"></a>
**↓ 文档在讲这里：**[`boards/rm2027/fmu-h743/src/hw_config.h:124`](ecc-scrub-c.md#^src-boards-rm2027-fmu-h743-src-hw-config-h-124)

```c
   121 │ #  define APP_RESERVATION_SIZE 0
   122 │ #endif
   123 │ 
▶  124 │ #if !defined(BOARD_FIRST_FLASH_SECTOR_TO_ERASE)
   125 │ #  define BOARD_FIRST_FLASH_SECTOR_TO_ERASE 1
   126 │ #endif
   127 │ 
```
> **说明**：起点 | BOARD_FIRST_FLASH_SECTOR_TO_ERASE | 本板 hw_config.h:124 ⇒ 1（跳过扇区 0 = bootloader 自己） |
^src-boards-rm2027-fmu-h743-src-hw-config-h-124

### `platforms/nuttx/NuttX/nuttx/arch/arm/src/stm32h7/stm32h743xx_flash.c`
<a id="src-platforms-nuttx-NuttX-nuttx-arch-arm-src-stm32h7-stm32h743xx-flash-c-130"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/NuttX/nuttx/arch/arm/src/stm32h7/stm32h743xx_flash.c:130`](ecc-scrub-c.md#^src-platforms-nuttx-NuttX-nuttx-arch-arm-src-stm32h7-stm32h743xx-flash-c-130)

```c
   127 │ #  define STM32_FLASH_NBLOCKS      8
   128 │ #  define STM32_FLASH_SIZE        _K(8 * 128)
   129 │ 
▶  130 │ #elif defined(CONFIG_STM32H7_FLASH_CONFIG_I)
   131 │ 
   132 │ #  define STM32_FLASH_NBLOCKS      16
   133 │ #  define STM32_FLASH_SIZE        _K(16 * 128)
```
> **说明**：终点 | up_progmem_neraseblocks() - 1 | ecc_scrub.c:137；up_progmem_neraseblocks() 返回 PROGMEM_NBLOCKS（stm32h743xx_flash.c:707）= STM32_FLASH_NBLOCKS | ┃ ⇒ 终点实测值 | 15 | STM32_FLASH_NBLOCKS = 16（stm32h743xx_flash.c:130）← 由 CONFIG_STM32H7_FLASH_CONFIG_I=y 选中，该键在两个构建的 .config 里都是 y（bl .config:265、app .config:298） |
^src-platforms-nuttx-NuttX-nuttx-arch-arm-src-stm32h7-stm32h743xx-flash-c-130

<a id="src-platforms-nuttx-NuttX-nuttx-arch-arm-src-stm32h7-stm32h743xx-flash-c-707"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/NuttX/nuttx/arch/arm/src/stm32h7/stm32h743xx_flash.c:707`](ecc-scrub-c.md#^src-platforms-nuttx-NuttX-nuttx-arch-arm-src-stm32h7-stm32h743xx-flash-c-707)

```c
   704 │   return priv->base + (page - priv->stpage) * FLASH_PAGE_SIZE;
   705 │ }
   706 │ 
▶  707 │ size_t up_progmem_neraseblocks(void)
   708 │ {
   709 │   return PROGMEM_NBLOCKS;
   710 │ }
```
> **说明**：起点 | BOARD_FIRST_FLASH_SECTOR_TO_ERASE | 本板 hw_config.h:124 ⇒ 1（跳过扇区 0 = bootloader 自己） | ┃ 终点 | up_progmem_neraseblocks() - 1 | ecc_scrub.c:137；up_progmem_neraseblocks() 返回 PROGMEM_NBLOCKS（stm32h743xx_flash.c:707）= STM32_FLASH_NBLOCKS |
^src-platforms-nuttx-NuttX-nuttx-arch-arm-src-stm32h7-stm32h743xx-flash-c-707

### `platforms/nuttx/src/bootloader/common/bl.c`
<a id="src-platforms-nuttx-src-bootloader-common-bl-c-317"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:317`](ecc-scrub-c.md#^src-platforms-nuttx-src-bootloader-common-bl-c-317)

```c
   314 │ 	 * We refuse to program the first word of the app until the upload is marked
   315 │ 	 * complete by the host.  So if it's not 0xffffffff, we should try booting it.
   316 │ 	 */
▶  317 │ 	if (app_base[APP_VECTOR_OFFSET_WORDS] == 0xffffffff) {
   318 │ 		return;
   319 │ 	}
   320 │ 
```
> **说明**：app 区（扇区 1..14） | 该扇区被擦 ⇒ app 首字可能变 0xffffffff ⇒ bl.c:317 判 app 无效 ⇒ 留在 bootloader |
^src-platforms-nuttx-src-bootloader-common-bl-c-317

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-666"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:666`](ecc-scrub-c.md#^src-platforms-nuttx-src-bootloader-common-bl-c-666)

```c
   663 │ 
   664 │ 		led_on(LED_ACTIVITY);
   665 │ 
▶  666 │ 		bool full_erase = false;
   667 │ 
   668 │ 		// handle the command byte
   669 │ 		switch (c) {
```
> **说明**：⇒ 所以普通 PROTO_CHIP_ERASE（bl.c:778 传 full_erase = false，默认值定义在 bl.c:666）
^src-platforms-nuttx-src-bootloader-common-bl-c-666

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-778"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:778`](ecc-scrub-c.md#^src-platforms-nuttx-src-bootloader-common-bl-c-778)

```c
   775 │ 			arch_flash_unlock();
   776 │ 
   777 │ 			for (int i = 0; flash_func_sector_size(i) != 0; i++) {
▶  778 │ 				flash_func_erase_sector(i, full_erase);
   779 │ 			}
   780 │ 
   781 │ 			// disable the LED while verifying the erase
```
> **说明**：⇒ 所以普通 PROTO_CHIP_ERASE（bl.c:778 传 full_erase = false，默认值定义在 bl.c:666）
^src-platforms-nuttx-src-bootloader-common-bl-c-778

### `platforms/nuttx/src/bootloader/common/lib/flash_cache.h`
<a id="src-platforms-nuttx-src-bootloader-common-lib-flash-cache-h-35"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/lib/flash_cache.h:35`](ecc-scrub-c.md#^src-platforms-nuttx-src-bootloader-common-lib-flash-cache-h-35)

```c
    32 │  ****************************************************************************/
    33 │ #pragma once
    34 │ 
▶   35 │ /* The modern flash controllers manage flash for ECC
    36 │  * On the H7 there is a block size (256) bits
    37 │  * This code translates between the bootloaders word read/write
    38 │  * interface and the H7 need for block based writes.
```
> **说明**：1. H7 flash 按 8 word（32 B）为一个 ECC 块（引用上游注释 flash_cache.h:35，见 02_code_twin/bootloader/flash-cache-c）。
> **说明**：H7 的 ECC 块大小到底是 256 bit 还是别的：我只引用了上游注释 flash_cache.h:35（*"On the H7 there is a block size (256) bits"*），
^src-platforms-nuttx-src-bootloader-common-lib-flash-cache-h-35

### `platforms/nuttx/src/bootloader/stm/stm32_common/main.c`
<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-23"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:23`](ecc-scrub-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-23)

```c
    20 │ #include "uart.h"
    21 │ 
    22 │ #if defined(CONFIG_ARCH_CHIP_STM32H7)
▶   23 │ #include "ecc_scrub.h"
    24 │ #endif
    25 │ 
    26 │ 
```
> **说明**：⇒ 终点实测值 | 15 | STM32_FLASH_NBLOCKS = 16（stm32h743xx_flash.c:130）← 由 CONFIG_STM32H7_FLASH_CONFIG_I=y 选中，该键在两个构建的 .config 里都是 y（bl .config:265、app .config:298） | ┃ 每扇区跨度 | FLASH_SECTOR_SIZE | 定义在 ecc_scrub.h:9 = 128 KiB（main.c:463 的兜底默认值不会生效，因为 main.c:23 已经 #include "ecc_scrub.h"） |
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-23

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-463"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:463`](ecc-scrub-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-463)

```c
   460 │ }
   461 │ 
   462 │ /* the chip code may provide its own sector size (see stm32h7/ecc_scrub.h) */
▶  463 │ #if !defined(FLASH_SECTOR_SIZE)
   464 │ #define FLASH_SECTOR_SIZE   (128u * 1024u)
   465 │ #endif
   466 │ 
```
> **说明**：⇒ 终点实测值 | 15 | STM32_FLASH_NBLOCKS = 16（stm32h743xx_flash.c:130）← 由 CONFIG_STM32H7_FLASH_CONFIG_I=y 选中，该键在两个构建的 .config 里都是 y（bl .config:265、app .config:298） | ┃ 每扇区跨度 | FLASH_SECTOR_SIZE | 定义在 ecc_scrub.h:9 = 128 KiB（main.c:463 的兜底默认值不会生效，因为 main.c:23 已经 #include "ecc_scrub.h"） |
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-463

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-477"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:477`](ecc-scrub-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-477)

```c
   474 │ 	return 0;
   475 │ }
   476 │ 
▶  477 │ void
   478 │ flash_func_erase_sector(unsigned sector, bool force)
   479 │ {
   480 │ 	if (sector > BOARD_FLASH_SECTORS || (int)sector < BOARD_FIRST_FLASH_SECTOR_TO_ERASE) {
```
> **说明**：main.c:477-487
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-477

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-660"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:660`](ecc-scrub-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-660)

```c
   657 │ }
   658 │ 
   659 │ int
▶  660 │ bootloader_main(int argc, char *argv[])
   661 │ {
   662 │ 	bool try_boot = true;			/* try booting before we drop to the bootloader */
   663 │ 	unsigned timeout = BOOTLOADER_DELAY;	/* if nonzero, drop out of the bootloader after this time */
```
> **说明**：main.c:660 bootloader_main()
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-660

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-666"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:666`](ecc-scrub-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-666)

```c
   663 │ 	unsigned timeout = BOOTLOADER_DELAY;	/* if nonzero, drop out of the bootloader after this time */
   664 │ 
   665 │ 	/* Enable the FPU before we hit any FP instructions */
▶  666 │ 	SCB_CPACR |= ((3UL << 10 * 2) | (3UL << 11 * 2)); /* set CP10 Full Access and set CP11 Full Access */
   667 │ 
   668 │ #if defined(BOARD_POWER_PIN_OUT)
   669 │ 
```
> **说明**：main.c:666 SCB_CPACR |= ... ← 开 FPU
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-666

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-682"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:682`](ecc-scrub-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-682)

```c
   679 │ #endif
   680 │ 
   681 │ 	/* do board-specific initialisation */
▶  682 │ 	board_init();
   683 │ 
   684 │ 	/* configure the clock for bootloader activity */
   685 │ 	clock_init();
```
> **说明**：main.c:682 board_init() ← fw_size = APP_SIZE_MAX
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-682

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-685"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:685`](ecc-scrub-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-685)

```c
   682 │ 	board_init();
   683 │ 
   684 │ 	/* configure the clock for bootloader activity */
▶  685 │ 	clock_init();
   686 │ 
   687 │ #if defined(CONFIG_ARCH_CHIP_STM32H7)
   688 │ 	/* scrub any uncorrectable flash ECC errors before we try to run the app */
```
> **说明**：main.c:685 clock_init() ← 【空】
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-685

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-687"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:687`](ecc-scrub-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-687)

```c
   684 │ 	/* configure the clock for bootloader activity */
   685 │ 	clock_init();
   686 │ 
▶  687 │ #if defined(CONFIG_ARCH_CHIP_STM32H7)
   688 │ 	/* scrub any uncorrectable flash ECC errors before we try to run the app */
   689 │ 	check_ecc_errors();
   690 │ #endif
```
> **说明**：main.c:687 #if defined(CONFIG_ARCH_CHIP_STM32H7)
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-687

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-689"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:689`](ecc-scrub-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-689)

```c
   686 │ 
   687 │ #if defined(CONFIG_ARCH_CHIP_STM32H7)
   688 │ 	/* scrub any uncorrectable flash ECC errors before we try to run the app */
▶  689 │ 	check_ecc_errors();
   690 │ #endif
   691 │ 
   692 │ 	/*
```
> **说明**：main.c:689 check_ecc_errors(); ← ★ 控制权进本文件
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-689

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-690"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:690`](ecc-scrub-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-690)

```c
   687 │ #if defined(CONFIG_ARCH_CHIP_STM32H7)
   688 │ 	/* scrub any uncorrectable flash ECC errors before we try to run the app */
   689 │ 	check_ecc_errors();
▶  690 │ #endif
   691 │ 
   692 │ 	/*
   693 │ 	 * Check the force-bootloader register; if we find the signature there, don't
```
> **说明**：main.c:690 #endif
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-690

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-696"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:696`](ecc-scrub-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-696)

```c
   693 │ 	 * Check the force-bootloader register; if we find the signature there, don't
   694 │ 	 * try booting.
   695 │ 	 */
▶  696 │ 	if (board_get_rtc_signature() == BOOT_RTC_SIGNATURE) {
   697 │ 
   698 │ 		/*
   699 │ 		 * Don't even try to boot before dropping to the bootloader.
```
> **说明**：main.c:696 之后才开始判"跳不跳"
> **说明**：执行序下一步：ecc_scrub.c 返回 ⇒ 回到 main.c:696，开始 4 个决策点 ⇒ 02_code_twin/bootloader/stm32-common-main-c。
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-696

### `platforms/nuttx/src/bootloader/stm/stm32h7/ecc_scrub.c`
<a id="src-platforms-nuttx-src-bootloader-stm-stm32h7-ecc-scrub-c-58"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32h7/ecc_scrub.c:58`](ecc-scrub-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32h7-ecc-scrub-c-58)

```c
    55 │ 
    56 │ #define ECC_CHUNK_WORDS   256u   /* 1 KiB per DMA transfer */
    57 │ 
▶   58 │ /* Optional: define to an output pinset (e.g. a spare FMU channel pad) to
    59 │  * measure the scan time on a scope - driven high for the duration. */
    60 │ // #define ECC_SCRUB_TIMING_GPIO   /* PI0 = FMU_CH1 */ (GPIO_OUTPUT|GPIO_PUSHPULL|GPIO_SPEED_50MHz|GPIO_OUTPUT_CLEAR|GPIO_PORTI|GPIO_PIN0)
    61 │ 
```
> **说明**：- 用 ecc_scrub.c:58 那个被注释掉的 ECC_SCRUB_TIMING_GPIO（PI0）打开，示波器量扫描窗口；
> **说明**：ecc_scrub.c:58 留了一个被注释掉的引脚定义：
^src-platforms-nuttx-src-bootloader-stm-stm32h7-ecc-scrub-c-58

<a id="src-platforms-nuttx-src-bootloader-stm-stm32h7-ecc-scrub-c-84"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32h7/ecc_scrub.c:84`](ecc-scrub-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32h7-ecc-scrub-c-84)

```c
    81 │ 	return timeout != 0;
    82 │ }
    83 │ 
▶   84 │ static bool flash_region_has_ecc_error(uintptr_t base, uint32_t size)
    85 │ {
    86 │ 	for (uint32_t ofs = 0; ofs < size; ofs += ECC_CHUNK_WORDS * sizeof(uint32_t)) {
    87 │ 		ecc_flags_clear();
```
> **说明**：2.1 怎么"读"出 ECC 错误（ecc_scrub.c:84）
^src-platforms-nuttx-src-bootloader-stm-stm32h7-ecc-scrub-c-84

<a id="src-platforms-nuttx-src-bootloader-stm-stm32h7-ecc-scrub-c-125"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32h7/ecc_scrub.c:125`](ecc-scrub-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32h7-ecc-scrub-c-125)

```c
   122 │ 	return false;
   123 │ }
   124 │ 
▶  125 │ void check_ecc_errors(void)
   126 │ {
   127 │ 	ECC_RCC_AHB1ENR |= ECC_RCC_DMA1EN;
   128 │ 	(void)ECC_RCC_AHB1ENR;
```
> **说明**：2. 它到底干了什么（ecc_scrub.c:125）
^src-platforms-nuttx-src-bootloader-stm-stm32h7-ecc-scrub-c-125

<a id="src-platforms-nuttx-src-bootloader-stm-stm32h7-ecc-scrub-c-130"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32h7/ecc_scrub.c:130`](ecc-scrub-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32h7-ecc-scrub-c-130)

```c
   127 │ 	ECC_RCC_AHB1ENR |= ECC_RCC_DMA1EN;
   128 │ 	(void)ECC_RCC_AHB1ENR;
   129 │ 
▶  130 │ #if defined(ECC_SCRUB_TIMING_GPIO)
   131 │ 	px4_arch_configgpio(ECC_SCRUB_TIMING_GPIO);
   132 │ 	px4_arch_gpiowrite(ECC_SCRUB_TIMING_GPIO, true);
   133 │ #endif
```
> **说明**：打开它（ecc_scrub.c:130 / :152-154 就会生效），就能用示波器量出扫描耗时。
^src-platforms-nuttx-src-bootloader-stm-stm32h7-ecc-scrub-c-130

<a id="src-platforms-nuttx-src-bootloader-stm-stm32h7-ecc-scrub-c-135"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32h7/ecc_scrub.c:135`](ecc-scrub-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32h7-ecc-scrub-c-135)

```c
   132 │ 	px4_arch_gpiowrite(ECC_SCRUB_TIMING_GPIO, true);
   133 │ #endif
   134 │ 
▶  135 │ 	/* scan to the last physical sector: parameter sectors sit past
   136 │ 	 * BOARD_FLASH_SECTORS, and boards may have more than one */
   137 │ 	const unsigned last_sector = up_progmem_neraseblocks() - 1;
   138 │ 
```
> **说明**：§4.2 的"第 2、3 条"（ECC 块被打断 ⇒ 读就报错 ⇒ 必须擦）是推理；ecc_scrub.c:142 的行为本身是代码事实。 ┃ ecc_scrub.c:135 注释说"参数扇区在 BOARD_FLASH_SECTORS 之外"——
^src-platforms-nuttx-src-bootloader-stm-stm32h7-ecc-scrub-c-135

<a id="src-platforms-nuttx-src-bootloader-stm-stm32h7-ecc-scrub-c-137"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32h7/ecc_scrub.c:137`](ecc-scrub-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32h7-ecc-scrub-c-137)

```c
   134 │ 
   135 │ 	/* scan to the last physical sector: parameter sectors sit past
   136 │ 	 * BOARD_FLASH_SECTORS, and boards may have more than one */
▶  137 │ 	const unsigned last_sector = up_progmem_neraseblocks() - 1;
   138 │ 
   139 │ 	for (unsigned sector = BOARD_FIRST_FLASH_SECTOR_TO_ERASE; sector <= last_sector; sector++) {
   140 │ 		uintptr_t base = APP_LOAD_ADDRESS + (sector - BOARD_FIRST_FLASH_SECTOR_TO_ERASE) * FLASH_SECTOR_SIZE;
```
> **说明**：起点 | BOARD_FIRST_FLASH_SECTOR_TO_ERASE | 本板 hw_config.h:124 ⇒ 1（跳过扇区 0 = bootloader 自己） | ┃ 终点 | up_progmem_neraseblocks() - 1 | ecc_scrub.c:137；up_progmem_neraseblocks() 返回 PROGMEM_NBLOCKS（stm32h743xx_flash.c:707）= STM32_FLASH_NBLOCKS |
^src-platforms-nuttx-src-bootloader-stm-stm32h7-ecc-scrub-c-137

<a id="src-platforms-nuttx-src-bootloader-stm-stm32h7-ecc-scrub-c-142"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32h7/ecc_scrub.c:142`](ecc-scrub-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32h7-ecc-scrub-c-142)

```c
   139 │ 	for (unsigned sector = BOARD_FIRST_FLASH_SECTOR_TO_ERASE; sector <= last_sector; sector++) {
   140 │ 		uintptr_t base = APP_LOAD_ADDRESS + (sector - BOARD_FIRST_FLASH_SECTOR_TO_ERASE) * FLASH_SECTOR_SIZE;
   141 │ 
▶  142 │ 		if (flash_region_has_ecc_error(base, FLASH_SECTOR_SIZE)) {
   143 │ 			ecc_flags_clear();
   144 │ 			up_progmem_eraseblock(sector);
   145 │ 		}
```
> **说明**：3. check_ecc_errors() 先用 DMA 把整个扇区读一遍（DMA 出错不会让 CPU 取指崩）， ┃ 发现 DBECCERR 就立刻 up_progmem_eraseblock() 把该扇区擦干净（ecc_scrub.c:142），
> **说明**：第 1-4 条里，第 2、3 条是推理；第 1 条是上游注释；ecc_scrub.c:142 的行为是代码事实。
^src-platforms-nuttx-src-bootloader-stm-stm32h7-ecc-scrub-c-142

### `platforms/nuttx/src/bootloader/stm/stm32h7/ecc_scrub.h`
<a id="src-platforms-nuttx-src-bootloader-stm-stm32h7-ecc-scrub-h-9"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32h7/ecc_scrub.h:9`](ecc-scrub-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32h7-ecc-scrub-h-9)

```c
     6 │ #pragma once
     7 │ 
     8 │ /* All supported H7 parts have uniform 128 KiB sectors. */
▶    9 │ #if !defined(FLASH_SECTOR_SIZE)
    10 │ #define FLASH_SECTOR_SIZE   (128u * 1024u)
    11 │ #endif
    12 │ 
```
> **说明**：⇒ 终点实测值 | 15 | STM32_FLASH_NBLOCKS = 16（stm32h743xx_flash.c:130）← 由 CONFIG_STM32H7_FLASH_CONFIG_I=y 选中，该键在两个构建的 .config 里都是 y（bl .config:265、app .config:298） | ┃ 每扇区跨度 | FLASH_SECTOR_SIZE | 定义在 ecc_scrub.h:9 = 128 KiB（main.c:463 的兜底默认值不会生效，因为 main.c:23 已经 #include "ecc_scrub.h"） |
^src-platforms-nuttx-src-bootloader-stm-stm32h7-ecc-scrub-h-9
