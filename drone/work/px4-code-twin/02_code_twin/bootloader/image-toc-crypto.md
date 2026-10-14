# `image_toc.c` + `crypto.c` —— 编进去了、但**控制流不走它**的那部分

> **源码**：`platforms/nuttx/src/bootloader/common/image_toc.c`（125 行）、`common/crypto.c`（94 行）、
> `common/image_toc.h`、`common/crypto.h`
> **层**：① 通用
> **本板状态**：**代码被编译进 `bootloader` 库，但所有调用点都在未定义的宏里 ⇒ 运行时完全不参与控制流**

---

## 1. 先证明"本板没启用"（不是猜，是可查的）

| 宏 | 定义处 | 本板 | 证据 |
|---|---|---|---|
| `BOOTLOADER_USE_TOC` | [`bl.c:321`](image-toc-crypto.md#^src-platforms-nuttx-src-bootloader-common-bl-c-321) 的 `#ifdef`；全仓 grep 只有 `#ifdef`，**无任何 `#define`** | **未定义** | `git grep BOOTLOADER_USE_TOC` 只出现在 `#ifdef/#ifndef` 行 |
| `BOOTLOADER_USE_SECURITY` | [`bl.c:54`](image-toc-crypto.md#^src-platforms-nuttx-src-bootloader-common-bl-c-54)、`:323`、`:409`、`:1039`；同样只有 `#ifdef` | **未定义** | 同上 |

**⇒ 因此下面这些代码段全部被预处理掉（不会进 flash）：**

| 位置 | 被裁掉的内容 |
|---|---|
| [`bl.c:321`](image-toc-crypto.md#^src-platforms-nuttx-src-bootloader-common-bl-c-321) → `:391`（整段） | `jump_to_app()` 里"从 TOC 找 app / 验签 / 解密 / 拷到 RAM"的全部分支 |
| [`bl.c:1039`](image-toc-crypto.md#^src-platforms-nuttx-src-bootloader-common-bl-c-1039) | `case PROTO_VERIFY_SIG`（⇒ 该 opcode 落到 `:1140 default`，**一个字节都不回**） |
| [`bl.c:323`](image-toc-crypto.md#^src-platforms-nuttx-src-bootloader-common-bl-c-323) / `:409-411` | `crypto_init()` / `crypto_deinit()` 调用 |
| [`bl.c:54`](image-toc-crypto.md#^src-platforms-nuttx-src-bootloader-common-bl-c-54) | 包含 `crypto_backend.h` |

**⇒ 结果：本板走的是 `bl.c:391 #else` 那条最简分支，判"app 有没有效"只靠两件事：**
1. 首字 != `0xffffffff`（[`bl.c:317`](image-toc-crypto.md#^src-platforms-nuttx-src-bootloader-common-bl-c-317)）
2. 复位向量落在 `[APP_LOAD_ADDRESS, APP_LOAD_ADDRESS + fw_size)` 内（[`bl.c:399`](image-toc-crypto.md#^src-platforms-nuttx-src-bootloader-common-bl-c-399) / `:403`）

---

## 2. 但它们仍然被编译——因为 `common/CMakeLists.txt` 无条件列出

```
platforms/nuttx/src/bootloader/common/CMakeLists.txt:34-38
add_library(bootloader
    bl.c
    image_toc.c
    crypto.c
)
```

**⇒ `image_toc.c` / `crypto.c` 的**目标文件**一定在 `bootloader` 库里。**
至于最终镜像里有没有它们的机器码，取决于链接器是否把它们拉进来：

| 情形 | 链接结果 |
|---|---|
| `bl.c` 里所有调用点都被 `#ifdef` 裁掉 | `image_toc.o` / `crypto.o` 里的符号**无人引用** ⇒ 链接器可以丢弃（用 `--gc-sections` 或"未被引用的 .o 不参与链接"时） |
| 真的被引用 | 才会进 flash |

**⇒ 可核实的判据**：`build/rm2027_fmu-h743_bootloader/rm2027_fmu-h743_bootloader.map` 里 grep
`image_toc` / `crypto` / `find_toc` / `verify_app`，看它们有没有被分配地址。

**★ 实测（已回验）**：

```sh
$ arm-none-eabi-nm build/rm2027_fmu-h743_bootloader/rm2027_fmu-h743_bootloader.elf \
    | grep -E "crypto_init|crypto_deinit|find_toc|verify_app|get_base_addr|decrypt_app"
（无输出）
$ grep -nE "image_toc|find_toc|verify_app" build/.../rm2027_fmu-h743_bootloader.map
（无输出。唯一 "crypto" 命中是 NuttX 无关的 libcrypto.a）
```

⇒ **`image_toc.c` / `crypto.c` 的机器码确实没进本板 bootloader 镜像。**
（链接器丢弃了未被引用的 `.o`。）

---

## 3. `image_toc.c` 是干什么的（只在安全启动版才有意义）

| 概念 | 说明 |
|---|---|
| **TOC**（table of contents） | 一个放在 flash 里的描述表：列出"这个镜像里有哪些段、各自的起止地址、要不要验签/解密/拷到 RAM/当向量表/可启动" |
| [`bl.c:327`](image-toc-crypto.md#^src-platforms-nuttx-src-bootloader-common-bl-c-327) | `find_toc()` 找到 TOC 与条目数 |
| [`bl.c:341`](image-toc-crypto.md#^src-platforms-nuttx-src-bootloader-common-bl-c-341) | 先验第 0 条（TOC 自己） |
| [`bl.c:347`](image-toc-crypto.md#^src-platforms-nuttx-src-bootloader-common-bl-c-347) | 逐条：按 `TOC_FLAG1_CHECK_SIGNATURE` / `TOC_FLAG1_DECRYPT` / `TOC_FLAG1_COPY` / `TOC_FLAG1_BOOT` / `TOC_FLAG1_VTORS` 决定动作 |
| [`bl.c:371`](image-toc-crypto.md#^src-platforms-nuttx-src-bootloader-common-bl-c-371) | **`BOOT` 标志决定 `app_base`，`VTORS` 标志决定 `vec_base`** ⇒ 安全版下"跳哪里"来自 TOC，而不是链接期常量 |

**⇒ 一句对照**：本板（无 TOC）的"app 在哪"是**编译期常量** `APP_LOAD_ADDRESS`（[`hw_config.h:87`](image-toc-crypto.md#^src-boards-rm2027-fmu-h743-src-hw-config-h-87)）；
有 TOC 的板是**运行期从 flash 读出来的**。这是两者在"控制流"上的根本差别。

---

## 4. `crypto.c` 是什么

| 位置 | 作用 |
|---|---|
| [`bl.c:324`](image-toc-crypto.md#^src-platforms-nuttx-src-bootloader-common-bl-c-324) / `:1087` | `crypto_init()` —— 初始化验签后端（只有安全版调） |
| [`bl.c:410`](image-toc-crypto.md#^src-platforms-nuttx-src-bootloader-common-bl-c-410) / `:1091` / `:1095` | `crypto_deinit()` |
| [`common/CMakeLists.txt:49`](image-toc-crypto.md#^src-CMakeLists-txt-49) | `if (DEFINED PX4_CRYPTO)` 才把 `crypto_backend` 链进来 |
| [`bl.c:54`](image-toc-crypto.md#^src-platforms-nuttx-src-bootloader-common-bl-c-54) | 只有 `BOOTLOADER_USE_SECURITY` 时才包含 `px4_platform_common/crypto_backend.h` |

**⇒ 两处开关的关系**：`BOOTLOADER_USE_SECURITY` 决定"①层要不要用签名"；
`PX4_CRYPTO` 决定"链接期给不给那个后端"。本板两个都没有。

### ★ `crypto.h` 里一个值得记住的退化设计

```
crypto.h:44-45   #if defined(BOOTLOADER_USE_SECURITY) → # define BOOTLOADER_USE_TOC
crypto.h:52-54   （安全版）声明真的 verify_app() / decrypt_app()
crypto.h:56-68   #else / # if defined(BOOTLOADER_USE_TOC)
crypto.h:62        static inline bool verify_app(...) {return true;}    ← ★ 永远"验签通过"
crypto.h:66        static inline bool decrypt_app(...) {return false;}  ← ★ 永远"不用解密"
crypto.h:70      #endif // BOOTLOADER_USE_SECURITY
```

**⇒ 也就是说："只用 TOC、不开签名"是一种合法组合**，此时：
- 表格（TOC）里的**地址信息照用**（`bl.c:372/377` 决定跳哪）；
- 但**签名检查恒通过**（`bl.c:341 verify_app(0,…)`、`:351`），`decrypt_app` 恒 false ⇒ `bl.c:357-361 continue` 永远不触发。

**本板是"既无 TOC 也无签名"⇒ `crypto.h` 那两段 `#if` 都不成立 ⇒ 一个符号都不产生**（已由上面的 nm 实测坐实）。

---

## 5. "我看到的现象由谁产生"

| 现象 | 由谁 | 依据 |
|---|---|---|
| 上位机发 `PROTO_VERIFY_SIG (0x39)` **完全没回应** | [`bl.c:1039`](image-toc-crypto.md#^src-platforms-nuttx-src-bootloader-common-bl-c-1039) 那段被裁 ⇒ 落 `:1140 default: continue` | 见 [02_code_twin/bootloader/bl-c](bl-c.md) §4.1 |
| 上传固件时**没有任何签名校验/解密动作** | [`bl.c:1053`](image-toc-crypto.md#^src-platforms-nuttx-src-bootloader-common-bl-c-1053) 被裁 | 上面 §1 |
| 首字 + 复位向量两个检查就是"app 有效"的全部 | [`bl.c:317`](image-toc-crypto.md#^src-platforms-nuttx-src-bootloader-common-bl-c-317) / `:399` / `:403` | 上面 §1 |
| 想改用 TOC 安全启动 | 需要**在 ③层 `hw_config.h` 里 `#define BOOTLOADER_USE_TOC` 并实现 TOC 生成**（本项目没做） | [`bl.c:321`](image-toc-crypto.md#^src-platforms-nuttx-src-bootloader-common-bl-c-321) / `:336` |

---

## 跳转

- **执行序回到主线的位置**：本文件在正常运行中**一个函数都不会被执行**；
  控制流始终在 `bl.c:391 #else` → `:399` → `:429` → `:432` 这条线上。
  ⇒ 回到 [02_code_twin/bootloader/bl-c](bl-c.md) §6。
- **"编译进库但不进镜像"这件事在 CMake 层怎么发生** → [02_code_twin/bootloader/cmakelists](cmakelists.md)。
- **同一套 CMake 里 `PX4_CRYPTO` 分支的上下游** → [01_extracted/cmake（px4-add-library / px4_add_module 的组织）](../../01_extracted/cmake/01-px4-cmake-organization.md)（由 task-10 负责；若尚未存在，本套以本篇为准）。

---

## 未核实

- `image_toc.h` / `crypto.h` 的**完整字段布局**未逐行展开（本板用不到）；
  `crypto.h` 的四段条件编译（`:44` / `:56` / `:58` / `:70`）与两个退化实现（`:62` / `:66`）**已逐行回验**。
- "链接器为什么丢弃了它们"的确切机制（`--gc-sections`？还是从未被拉入链接）**未核实**——
  我只实测了"最终镜像里没有这些符号"这一结果。

---

## 标注源码（代码 + 本文档对它的解释）

> **这是「代码孪生」层**：上面是代码原文（带行号），下面是**本文档针对这一段说的话**。
> 行号可点，直接跳到 PX4 源码那一行。
### `CMakeLists.txt`
<a id="src-CMakeLists-txt-49"></a>
**↓ 文档在讲这里：**[`CMakeLists.txt:49`](image-toc-crypto.md#^src-CMakeLists-txt-49)

```c
    46 │ # ---------------------------------------------------------------------------
    47 │ #
    48 │ # * Use hard indents to match the px4 source code.
▶   49 │ #
    50 │ # * All function and script arguments are upper case.
    51 │ #
    52 │ # * All local variables are lower case.
```
> **说明**：bl.c:410 / :1091 / :1095 | crypto_deinit() | ┃ common/CMakeLists.txt:49 | if (DEFINED PX4_CRYPTO) 才把 crypto_backend 链进来 |
^src-CMakeLists-txt-49

### `boards/rm2027/fmu-h743/src/hw_config.h`
<a id="src-boards-rm2027-fmu-h743-src-hw-config-h-87"></a>
**↓ 文档在讲这里：**[`boards/rm2027/fmu-h743/src/hw_config.h:87`](image-toc-crypto.md#^src-boards-rm2027-fmu-h743-src-hw-config-h-87)

```c
    84 │ #define SERIAL0_DEV    0x02
    85 │ #define SERIAL1_DEV    0x04
    86 │ 
▶   87 │ #define APP_LOAD_ADDRESS               0x08020000
    88 │ #define BOOTLOADER_DELAY               5000
    89 │ /* ★ 本板（rm2027/fmu-h743）**没有 USB 硬件**
    90 │  *   → 关掉 USB 上传通道，只用串口通道上传固件
```
> **说明**：⇒ 一句对照：本板（无 TOC）的"app 在哪"是编译期常量 APP_LOAD_ADDRESS（hw_config.h:87）；
^src-boards-rm2027-fmu-h743-src-hw-config-h-87

### `platforms/nuttx/src/bootloader/common/bl.c`
<a id="src-platforms-nuttx-src-bootloader-common-bl-c-54"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:54`](image-toc-crypto.md#^src-platforms-nuttx-src-bootloader-common-bl-c-54)

```c
    51 │ #include "cdcacm.h"
    52 │ #include "uart.h"
    53 │ 
▶   54 │ #ifdef BOOTLOADER_USE_SECURITY
    55 │ #include <px4_platform_common/crypto_backend.h>
    56 │ #endif
    57 │ 
```
> **说明**：BOOTLOADER_USE_TOC | bl.c:321 的 #ifdef；全仓 grep 只有 #ifdef，无任何 #define | 未定义 | git grep BOOTLOADER_USE_TOC 只出现在 #ifdef/#ifndef 行 | ┃ BOOTLOADER_USE_SECURITY | bl.c:54、:323、:409、:1039；同样只有 #ifdef | 未定义 | 同上 |
> **说明**：bl.c:323 / :409-411 | crypto_init() / crypto_deinit() 调用 | ┃ bl.c:54 | 包含 crypto_backend.h |
^src-platforms-nuttx-src-bootloader-common-bl-c-54

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-317"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:317`](image-toc-crypto.md#^src-platforms-nuttx-src-bootloader-common-bl-c-317)

```c
   314 │ 	 * We refuse to program the first word of the app until the upload is marked
   315 │ 	 * complete by the host.  So if it's not 0xffffffff, we should try booting it.
   316 │ 	 */
▶  317 │ 	if (app_base[APP_VECTOR_OFFSET_WORDS] == 0xffffffff) {
   318 │ 		return;
   319 │ 	}
   320 │ 
```
> **说明**：⇒ 结果：本板走的是 bl.c:391 #else 那条最简分支，判"app 有没有效"只靠两件事： ┃ 1. 首字 != 0xffffffff（bl.c:317）
> **说明**：上传固件时没有任何签名校验/解密动作 | bl.c:1053 被裁 | 上面 §1 | ┃ 首字 + 复位向量两个检查就是"app 有效"的全部 | bl.c:317 / :399 / :403 | 上面 §1 |
^src-platforms-nuttx-src-bootloader-common-bl-c-317

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-321"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:321`](image-toc-crypto.md#^src-platforms-nuttx-src-bootloader-common-bl-c-321)

```c
   318 │ 		return;
   319 │ 	}
   320 │ 
▶  321 │ #ifdef BOOTLOADER_USE_TOC
   322 │ 
   323 │ #ifdef BOOTLOADER_USE_SECURITY
   324 │ 	crypto_init();
```
> **说明**：BOOTLOADER_USE_TOC | bl.c:321 的 #ifdef；全仓 grep 只有 #ifdef，无任何 #define | 未定义 | git grep BOOTLOADER_USE_TOC 只出现在 #ifdef/#ifndef 行 |
> **说明**：bl.c:321 → :391（整段） | jump_to_app() 里"从 TOC 找 app / 验签 / 解密 / 拷到 RAM"的全部分支 |
^src-platforms-nuttx-src-bootloader-common-bl-c-321

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-323"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:323`](image-toc-crypto.md#^src-platforms-nuttx-src-bootloader-common-bl-c-323)

```c
   320 │ 
   321 │ #ifdef BOOTLOADER_USE_TOC
   322 │ 
▶  323 │ #ifdef BOOTLOADER_USE_SECURITY
   324 │ 	crypto_init();
   325 │ #endif
   326 │ 
```
> **说明**：bl.c:1039 | case PROTO_VERIFY_SIG（⇒ 该 opcode 落到 :1140 default，一个字节都不回） | ┃ bl.c:323 / :409-411 | crypto_init() / crypto_deinit() 调用 |
^src-platforms-nuttx-src-bootloader-common-bl-c-323

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-324"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:324`](image-toc-crypto.md#^src-platforms-nuttx-src-bootloader-common-bl-c-324)

```c
   321 │ #ifdef BOOTLOADER_USE_TOC
   322 │ 
   323 │ #ifdef BOOTLOADER_USE_SECURITY
▶  324 │ 	crypto_init();
   325 │ #endif
   326 │ 
   327 │ 	const image_toc_entry_t *toc_entries;
```
> **说明**：bl.c:324 / :1087 | crypto_init() —— 初始化验签后端（只有安全版调） |
^src-platforms-nuttx-src-bootloader-common-bl-c-324

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-327"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:327`](image-toc-crypto.md#^src-platforms-nuttx-src-bootloader-common-bl-c-327)

```c
   324 │ 	crypto_init();
   325 │ #endif
   326 │ 
▶  327 │ 	const image_toc_entry_t *toc_entries;
   328 │ 	uint8_t len;
   329 │ 	uint8_t i = 0;
   330 │ 
```
> **说明**：TOC（table of contents） | 一个放在 flash 里的描述表：列出"这个镜像里有哪些段、各自的起止地址、要不要验签/解密/拷到 RAM/当向量表/可启动" | ┃ bl.c:327 | find_toc() 找到 TOC 与条目数 |
^src-platforms-nuttx-src-bootloader-common-bl-c-327

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-341"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:341`](image-toc-crypto.md#^src-platforms-nuttx-src-bootloader-common-bl-c-341)

```c
   338 │ 	}
   339 │ 
   340 │ 	/* Verify the first entry, containing the TOC itself */
▶  341 │ 	if (!verify_app(0, toc_entries)) {
   342 │ 		/* Image verification failed, stay in btl */
   343 │ 		return;
   344 │ 	}
```
> **说明**：bl.c:327 | find_toc() 找到 TOC 与条目数 | ┃ bl.c:341 | 先验第 0 条（TOC 自己） |
^src-platforms-nuttx-src-bootloader-common-bl-c-341

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-347"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:347`](image-toc-crypto.md#^src-platforms-nuttx-src-bootloader-common-bl-c-347)

```c
   344 │ 	}
   345 │ 
   346 │ 	/* TOC is verified, loop through all the apps and perform crypto ops */
▶  347 │ 	for (i = 0; i < len; i++) {
   348 │ 		/* Verify app, if needed. i == 0 is already verified */
   349 │ 		if (i != 0 &&
   350 │ 		    toc_entries[i].flags1 & TOC_FLAG1_CHECK_SIGNATURE &&
```
> **说明**：bl.c:341 | 先验第 0 条（TOC 自己） | ┃ bl.c:347 | 逐条：按 TOC_FLAG1_CHECK_SIGNATURE / TOC_FLAG1_DECRYPT / TOC_FLAG1_COPY / TOC_FLAG1_BOOT / TOC_FLAG1_VTORS 决定动作 |
^src-platforms-nuttx-src-bootloader-common-bl-c-347

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-371"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:371`](image-toc-crypto.md#^src-platforms-nuttx-src-bootloader-common-bl-c-371)

```c
   368 │ 		}
   369 │ 
   370 │ 		/* Check if this app is bootable, if so set the app_base */
▶  371 │ 		if (toc_entries[i].flags1 & TOC_FLAG1_BOOT) {
   372 │ 			app_base = get_base_addr(&toc_entries[i]);
   373 │ 		}
   374 │ 
```
> **说明**：bl.c:347 | 逐条：按 TOC_FLAG1_CHECK_SIGNATURE / TOC_FLAG1_DECRYPT / TOC_FLAG1_COPY / TOC_FLAG1_BOOT / TOC_FLAG1_VTORS 决定动作 | ┃ bl.c:371 | BOOT 标志决定 app_base，VTORS 标志决定 vec_base ⇒ 安全版下"跳哪里"来自 TOC，而不是链接期常量 |
^src-platforms-nuttx-src-bootloader-common-bl-c-371

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-399"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:399`](image-toc-crypto.md#^src-platforms-nuttx-src-bootloader-common-bl-c-399)

```c
   396 │ 	 * The second word of the app is the entrypoint; it must point within the
   397 │ 	 * flash area (or we have a bad flash).
   398 │ 	 */
▶  399 │ 	if (app_base[APP_VECTOR_OFFSET_WORDS + 1] < APP_LOAD_ADDRESS) {
   400 │ 		return;
   401 │ 	}
   402 │ 
```
> **说明**：1. 首字 != 0xffffffff（bl.c:317） ┃ 2. 复位向量落在 [APP_LOAD_ADDRESS, APP_LOAD_ADDRESS + fw_size) 内（bl.c:399 / :403）
^src-platforms-nuttx-src-bootloader-common-bl-c-399

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-410"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:410`](image-toc-crypto.md#^src-platforms-nuttx-src-bootloader-common-bl-c-410)

```c
   407 │ #endif
   408 │ 
   409 │ #ifdef BOOTLOADER_USE_SECURITY
▶  410 │ 	crypto_deinit();
   411 │ #endif
   412 │ 
   413 │ 	/* just for paranoia's sake */
```
> **说明**：bl.c:324 / :1087 | crypto_init() —— 初始化验签后端（只有安全版调） | ┃ bl.c:410 / :1091 / :1095 | crypto_deinit() |
^src-platforms-nuttx-src-bootloader-common-bl-c-410

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-1039"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:1039`](image-toc-crypto.md#^src-platforms-nuttx-src-bootloader-common-bl-c-1039)

```c
  1036 │ 			 */
  1037 │ 			goto cmd_bad;
  1038 │ 
▶ 1039 │ #ifdef BOOTLOADER_USE_SECURITY
  1040 │ 
  1041 │ 		// verify the signature of the programmed image
  1042 │ 		//
```
> **说明**：bl.c:321 → :391（整段） | jump_to_app() 里"从 TOC 找 app / 验签 / 解密 / 拷到 RAM"的全部分支 | ┃ bl.c:1039 | case PROTO_VERIFY_SIG（⇒ 该 opcode 落到 :1140 default，一个字节都不回） |
> **说明**：上位机发 PROTO_VERIFY_SIG (0x39) 完全没回应 | bl.c:1039 那段被裁 ⇒ 落 :1140 default: continue | 见 02_code_twin/bootloader/bl-c §4.1 |
^src-platforms-nuttx-src-bootloader-common-bl-c-1039

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-1053"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:1053`](image-toc-crypto.md#^src-platforms-nuttx-src-bootloader-common-bl-c-1053)

```c
  1050 │ 		// keeps a non-secure bootloader byte-for-byte equivalent to an older
  1051 │ 		// one for this opcode, so the uploader's unconditional probe never
  1052 │ 		// disturbs the command stream before BOOT.
▶ 1053 │ 		case PROTO_VERIFY_SIG:
  1054 │ 			if (!wait_for_eoc(2)) {
  1055 │ 				goto cmd_bad;
  1056 │ 			}
```
> **说明**：上位机发 PROTO_VERIFY_SIG (0x39) 完全没回应 | bl.c:1039 那段被裁 ⇒ 落 :1140 default: continue | 见 02_code_twin/bootloader/bl-c §4.1 | ┃ 上传固件时没有任何签名校验/解密动作 | bl.c:1053 被裁 | 上面 §1 |
^src-platforms-nuttx-src-bootloader-common-bl-c-1053

### `platforms/nuttx/src/bootloader/common/crypto.h`
<a id="src-platforms-nuttx-src-bootloader-common-crypto-h-44"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/crypto.h:44`](image-toc-crypto.md#^src-platforms-nuttx-src-bootloader-common-crypto-h-44)

```c
    41 │ #pragma once
    42 │ 
    43 │ /* Using security always needs TOC (but TOC could be used without security) */
▶   44 │ #if defined(BOOTLOADER_USE_SECURITY)
    45 │ # define BOOTLOADER_USE_TOC
    46 │ 
    47 │ #include <stdlib.h>
```
> **说明**：crypto.h:44-45 #if defined(BOOTLOADER_USE_SECURITY) → # define BOOTLOADER_USE_TOC
^src-platforms-nuttx-src-bootloader-common-crypto-h-44

<a id="src-platforms-nuttx-src-bootloader-common-crypto-h-52"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/crypto.h:52`](image-toc-crypto.md#^src-platforms-nuttx-src-bootloader-common-crypto-h-52)

```c
    49 │ #include "hw_config.h"
    50 │ #include "image_toc.h"
    51 │ 
▶   52 │ bool verify_app(uint16_t idx, const image_toc_entry_t *toc_entries);
    53 │ 
    54 │ bool decrypt_app(uint16_t idx, const image_toc_entry_t *toc_entries);
    55 │ 
```
> **说明**：crypto.h:52-54 （安全版）声明真的 verify_app() / decrypt_app()
^src-platforms-nuttx-src-bootloader-common-crypto-h-52

<a id="src-platforms-nuttx-src-bootloader-common-crypto-h-56"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/crypto.h:56`](image-toc-crypto.md#^src-platforms-nuttx-src-bootloader-common-crypto-h-56)

```c
    53 │ 
    54 │ bool decrypt_app(uint16_t idx, const image_toc_entry_t *toc_entries);
    55 │ 
▶   56 │ #else
    57 │ 
    58 │ # if defined(BOOTLOADER_USE_TOC)
    59 │ 
```
> **说明**：crypto.h:56-68 #else / # if defined(BOOTLOADER_USE_TOC)
^src-platforms-nuttx-src-bootloader-common-crypto-h-56

<a id="src-platforms-nuttx-src-bootloader-common-crypto-h-62"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/crypto.h:62`](image-toc-crypto.md#^src-platforms-nuttx-src-bootloader-common-crypto-h-62)

```c
    59 │ 
    60 │ /* No security, application verification passes always */
    61 │ 
▶   62 │ static inline bool verify_app(uint16_t idx, const image_toc_entry_t *toc_entries) {return true;}
    63 │ 
    64 │ /* No security, decrypting is not possible */
    65 │ 
```
> **说明**：crypto.h:62 static inline bool verify_app(...) {return true;} ← ★ 永远"验签通过"
^src-platforms-nuttx-src-bootloader-common-crypto-h-62

<a id="src-platforms-nuttx-src-bootloader-common-crypto-h-66"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/crypto.h:66`](image-toc-crypto.md#^src-platforms-nuttx-src-bootloader-common-crypto-h-66)

```c
    63 │ 
    64 │ /* No security, decrypting is not possible */
    65 │ 
▶   66 │ static inline bool decrypt_app(uint16_t idx, const image_toc_entry_t *toc_entries) {return false;}
    67 │ 
    68 │ # endif
    69 │ 
```
> **说明**：crypto.h:66 static inline bool decrypt_app(...) {return false;} ← ★ 永远"不用解密"
^src-platforms-nuttx-src-bootloader-common-crypto-h-66

<a id="src-platforms-nuttx-src-bootloader-common-crypto-h-70"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/crypto.h:70`](image-toc-crypto.md#^src-platforms-nuttx-src-bootloader-common-crypto-h-70)

```c
    67 │ 
    68 │ # endif
    69 │ 
▶   70 │ #endif // BOOTLOADER_USE_SECURITY
    71 │ 
```
> **说明**：crypto.h:70 #endif // BOOTLOADER_USE_SECURITY
^src-platforms-nuttx-src-bootloader-common-crypto-h-70
