# `common/bl.c` —— 协议机："等主机上传"这件事的全套逻辑

> **源码**：`platforms/nuttx/src/bootloader/common/bl.c`（1175 行）
> **层**：① 通用（文档注释 [`bl.c:34`](bl-h.md#^src-platforms-nuttx-src-bootloader-common-bl-c-34) 原话：*"should have no board-specific logic"*）
> **被谁调**：②层 [`main.c:802`](bl-h.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-802) `bootloader(timeout)`；③层不直接碰它
> **对外只暴露 3 个函数**：`bootloader()`（`:624`）、`jump_to_app()`（`:308`）、`delay()`（`:453`）+ 那几个响应函数

---

## 1. 运行时它处在哪

`bl.c` 的代码**不是在 CPU 复位时开始的**，而是：

```
②层 main.c:771 第一次 jump_to_app() 失败（app 无效 / 向量表越界 / 跳不过去）
   ↓ 返回
②层 main.c:777 timeout = 0
②层 main.c:783 cinit("/dev/ttyS0,57600", USART)   ← 这时串口才被打开
②层 main.c:802 bootloader(0)                       ← ★ ①层在这里开始
```

**⇒ 所以 `bl.c` 里"一进来就 `led_set(LED_BLINK)`"（`:640`）的含义是：
"裁判告诉我这次跳不成了，我在这里等人来重刷"。**

在这个位置上，NuttX 依然活着（SysTick / 串口驱动 / 工作队列都在跑），
`bl.c` 只是个**跑在 NuttX 任务里的死循环**。

---

## 2. 主循环骨架（`:624` → `:1174`）

| 行号 | 动作 | 说明 |
|---|---|---|
| `:626` | `bl_type = NONE` | **通道还没定**——由"第一个有效命令从哪个口进来"决定（`:1150-1152`） |
| `:627` | `volatile uint32_t bl_state = 0` | **状态机**：必须按顺序看到某些命令才允许擦/才允许提交首字（状态位定义 `:136-157`） |
| `:628` | `address = board_info.fw_size` | ★ 故意设成越界值 ⇒ **"必须先擦除才能上传"**（写操作会撞 `:818` 的边界检查） |
| `:629` | `first_word = 0xffffffff` | ★ 被延迟提交的 app 首字，见 §5 |
| `:632` | `arch_systic_init()` | ②层 [`main.c:365`](stm32-common-main-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-365)：把 SysTick 配成 1 ms |
| `:635-637` | 若 `timeout` 非 0 ⇒ `timer[TIMER_BL_WAIT] = timeout` | 超时计时开始 |
| **`:640`** | **`led_set(LED_BLINK)`** | ★ 外围可见：**灯开始闪 = 空闲等主机** |
| `:642` | `while (true)` | 主循环开始 |
| `:651` / `:664` | `led_off/led_on(LED_ACTIVITY)` | 收字节期间的"活动"心跳 |
| `:653-662` | 内层 do-while 等一个命令字节 | 每圈先查超时（`:655`），再 `cin_wait(0)`（`:660`，0 ms 超时 = 纯轮询） |
| `:669` | `switch (c)` | 命令分派（§3） |
| **`:1145-1147`** | 若已同时见过 `GET_SYNC` + `GET_DEVICE` ⇒ **`timeout = 0`** | ★ "确认对面是正规上位机了，就别再超时跑了" |
| **`:1150-1152`** | `if (bl_type == NONE) bl_type = last_input;` | ★ **通道锁定**：第一次那个字节从哪来，之后所有应答就只走那条路 |
| `:1155` | `sync_response()` | 每条成功的命令统一回 `0x12 0x10` |
| `:1157-1161` | `cmd_bad:` → `invalid_response()` + `bl_state = 0` + `continue` | ★ `bl_state` 清零 ⇒ **状态机被打回原点**（防止乱序命令） |
| `:1163-1166` | `cmd_fail:` → `failure_response()` + `continue` | ★ **不清 `bl_state`**（写失败 ≠ 命令乱序） |

---

## 3. 命令分派表（含本版代码的**真实**行为）

| 行号 | 命令 | ①层行为 | `bl_state` 置位 |
|---|---|---|---|
| `:676` | `PROTO_GET_SYNC (0x21)` | 校验 EOC ⇒ 回 sync | `STATE_PROTO_GET_SYNC`（`:683`） |
| `:696` | `PROTO_GET_DEVICE (0x22)` | 带 1 字节子参数（`:698` `cin_wait(1000)`），回 BL 版本 / board_id / board_rev / fw_size / 向量区 7-10 | `STATE_PROTO_GET_DEVICE`（`:738`） |
| `:747` | `PROTO_CHIP_FULL_ERASE (0x40)` | `full_erase = true` 后**落穿**到 `:751` | — |
| `:751` | `PROTO_CHIP_ERASE (0x23)` | 校验状态（`:766`）→ 灯常亮（`:772`）→ **逐扇区擦**（`:777-779`）→ 灯灭（`:782`）→ **逐字读回验证全 `0xffffffff`**（`:785-789`）→ `address = 0`（`:791`）→ 灯回闪（`:795`） | `STATE_PROTO_CHIP_ERASE` |
| `:805` | `PROTO_PROG_MULTI (0x27)` | 读长度（`:807`）→ 5 项合法性检查（`:814/:818/:822`）→ 收数据（`:826-834`）→ 等 EOC（`:836`）→ **首字拦截**（`:840-858`）→ 逐字写 flash + **立即读回校验**（`:861-881`） | `STATE_PROTO_PROG_MULTI`（`:883`） |
| `:892` | `PROTO_GET_CRC (0x29)` | 遍历 `0..fw_size/4`，**首字位置用暂存的 `first_word` 顶替**（`:905-906`），回 4 字节 CRC | `STATE_PROTO_GET_CRC`（`:916`） |
| `:923` | `PROTO_GET_OTP (0x2a)` | ②层 `flash_func_read_otp` 恒返回 0（[`main.c:508`](bl-h.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-508)）⇒ **本板恒回 0** | — |
| `:945` | `PROTO_GET_SN (0x2b)` | 读 96 位 UID（[`main.c:564`](bl-h.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-564) `STM32_SYSMEM_UID`） | `STATE_PROTO_GET_SN` |
| `:975` | `PROTO_GET_CHIP (0x2c)` | 读 `STM32_DEBUGMCU_BASE`（[`main.c:514`](bl-h.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-514)） | `STATE_PROTO_GET_CHIP` |
| `:990` | `PROTO_GET_CHIP_DES (0x2e)` | 芯片型号 + 版本字母（[`main.c:519`](bl-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-519)），本板命中表项 `"STM32H7[4\|5]x"`（[`main.c:59`](bl-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-59)） | `STATE_PROTO_GET_CHIP_DES` |
| `:1010` | `PROTO_GET_VERSION (0x2f)` | 回 `BOOTLOADER_VERSION`（= `PX4BLv<major>.<minor>.<patch>g<git>`，[`common/CMakeLists.txt:41`](../drivers/dshot.md#^src-CMakeLists-txt-41) 注入） | `STATE_PROTO_GET_VERSION` |
| **`:1025-1037`** | **`PROTO_SET_DELAY (0x2d)`** | ★★ **本版已废弃**：`goto cmd_bad`，**直接回 INVALID，什么都不做** | 不置位 |
| `:1053` | `PROTO_VERIFY_SIG (0x39)` | 只在 `#ifdef BOOTLOADER_USE_SECURITY` 内。**本板没编进去** ⇒ 落到 `:1140 default` → `continue`（连 INVALID 都不回！） | — |
| **`:1106`** | **`PROTO_BOOT (0x30)`** | 校验状态（`:1113`）→ **提交首字 + 读回校验**（`:1118-1127`）→ `sync_response()`（`:1130`）→ `delay(100)`（`:1131`）→ **`return`**（`:1134`） | — |
| `:1136` | `PROTO_DEBUG (0x31)` | **空的**（`break`），但会走到 `:1155` 回一次 sync | — |
| `:1140` | `default:` | `continue`，**一个字节都不回** | — |

### 3.1 ★ 对既有素材的一处订正（已回验）

> 既有素材 `work/PX4-bootloader主流程时序图.md:101` 写：
> 「[`bl.c:1025`](bl-c.md#^src-platforms-nuttx-src-bootloader-common-bl-c-1025) `PROTO_SET_DELAY` —— 主机设超时（**顺带提交首字**）」

**回验结论：错。** 本版 [`bl.c:1025`](bl-c.md#^src-platforms-nuttx-src-bootloader-common-bl-c-1025) 的实际代码是：

- `:1026-1036` 一段注释，说明**为什么废弃**（签名位置不对、H7 flash 粒度不允许单字改、flash cache 不刷写）；
- `:1037` `goto cmd_bad;` ⇒ **回 `INSYNC/INVALID`，且 `bl_state` 被清零**。

⇒ 于是"提交首字"的地方**只有两处**：`PROTO_VERIFY_SIG`（`:1073-1081`，本板不编）和 `PROTO_BOOT`（`:1118-1127`）。
既有素材 §6 表格里把 `PROTO_SET_DELAY` 列为写首字的时机之一，**同样应删掉**。

---

## 4. 响应函数：全部是 2 字节

| 响应 | 定义 | 发出 | 内容 |
|---|---|---|---|
| sync | [`bl.c:484`](bl-c.md#^src-platforms-nuttx-src-bootloader-common-bl-c-484) | `:491` | `0x12 0x10` |
| invalid | [`bl.c:508`](bl-c.md#^src-platforms-nuttx-src-bootloader-common-bl-c-508) | `:515` | `0x12 0x13` |
| failure | [`bl.c:519`](bl-c.md#^src-platforms-nuttx-src-bootloader-common-bl-c-519) | `:526` | `0x12 0x11` |
| bad_silicon | [`bl.c:496`](bl-c.md#^src-platforms-nuttx-src-bootloader-common-bl-c-496) | `:503` | `0x12 0x14`，**整段在 `#if defined(TARGET_HW_PX4_FMU_V4)` 内 ⇒ 本板不编** |

⇒ **台架上"bootloader 到底怎么了"只能看这 3 种 2 字节应答 + 灯**。①层没有任何 `printf`。

### 4.1 ★ 一个反直觉的点：`PROTO_VERIFY_SIG` 在本板会**超时**而不是回错

`:1053` 的 `case` 整段在 `#ifdef BOOTLOADER_USE_SECURITY` 里。本板没定义 ⇒ 该 opcode 落到 `:1140 default: continue;`
⇒ **不回任何字节**。[`bl.c:1039`](image-toc-crypto.md#^src-platforms-nuttx-src-bootloader-common-bl-c-1039) 的注释把这件事写明白了（故意保持"与非安全版逐字节等价"）。
⇒ 上位机若发 `0x39`，看到的不是 `INVALID`，而是**静默无响应**。

---

## 5. ★★ 首字延迟提交（本文件最核心的设计）

### 5.1 为什么

ARM 的复位向量表第 0 个字是**初始 SP**，第 1 个字是**复位向量**。
`jump_to_app()` 判"app 有效"的唯一依据就是 **[`bl.c:317`](image-toc-crypto.md#^src-platforms-nuttx-src-bootloader-common-bl-c-317) 首字 != `0xffffffff`**。
⇒ 如果上传过程中就写了首字，**传一半掉电 = 板上出现一个"看起来有效"的半成品 app**。
⇒ 所以：**首字被扣在 RAM 里，直到"整个镜像校验完 + 主机下令启动"才落盘。**

### 5.2 三处代码

| 阶段 | 行号 | 干了什么 |
|---|---|---|
| **拦截** | `:840-858` | 只有当 `address == APP_VECTOR_OFFSET`（本板 = 0）时：把真值存进 `first_word`（`:853`），**把要写进 flash 的那个字改成 `0xffffffff`**（`:855`） |
| **CRC 时顶替** | `:905-910` | 算 CRC 时若走到首字位置、且 `first_word != 0xffffffff`，用 RAM 里的真值代替读回值 ⇒ 上位机算出的 CRC 对应**完整镜像** |
| **提交** | `:1118-1127` | 收到 `PROTO_BOOT` 后：`flash_func_write_word`（`:1119`）→ **立即读回校验**（`:1121`，不等 ⇒ `cmd_fail`）→ `first_word = 0xffffffff`（`:1126`，失败时回退） |

### 5.3 掉电三种情形（都在代码里能读出来）

| 掉电时刻 | flash 里首字 | 复位后会发生什么 |
|---|---|---|
| 擦除后、`PROG_MULTI` 中途 | `0xffffffff` | [`bl.c:317`](image-toc-crypto.md#^src-platforms-nuttx-src-bootloader-common-bl-c-317) 直接 return ⇒ **留在 bootloader 等人重刷**（`:771`/`:824` 那条路） |
| `PROTO_BOOT` 提交首字**那一瞬间** | H7 上该字所属的 8 字页（见 [02_code_twin/bootloader/flash-cache-c](flash-cache-c.md)）要么全写要么全不写 | 要么完整 app，要么留 bootloader ⇒ **不存在"半有效"态** |
| app 已在跑（跳成功了） | 有效值 | 正常启动 |

**⇒ 这就是"凡是靠 flash 一个标志位决定启动行为的固件，必须交代：谁写它 / 何时写 / 写失败或掉电了怎么办"的正例。**
反驳例证是本项目自己的 G071 电调 bootloader（app 有效标志只有写了 1 才启动，而文档没交代 ⇒ 现象是"每次上电停在 bootloader"，看起来像硬件坏）。

### 5.4 `first_word` 跟 `flash_cache` 的耦合（★ 容易忽略）

②层的 `flash_func_write_word`（[`main.c:489`](bl-h.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-489)）**不是真的写 flash**，而是调 `fmc.c:92 fc_write()`：
它会**把 8 个连续 word 攒在 RAM 缓存里，直到第 8 个才真写**。
同理 `flash_func_read_word`（[`main.c:496`](bl-h.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-496)）走 `fmc.c:135 fc_read()`，**命中缓存时读的是 RAM**。

⇒ 所以 [`bl.c:876`](flash-cache-c.md#^src-platforms-nuttx-src-bootloader-common-bl-c-876) 那句"写完立即读回校验"在 H7 上**是在和缓存对话**，不是和 flash 对话。
**为什么这样仍然是安全的**：`fmc.c:150-159` 里"读缓存行最后一个 word"会顺手 `fc_flush()`，写失败时把返回值按位取反
⇒ 上层的"读回校验"一定会失败。这条设计把"8 字缓冲"对上层透明化了。

---

## 6. `jump_to_app()`（`:308` → `:433`）：跳 app 的完整校验链

| 行号 | 检查 / 动作 | 不过就 |
|---|---|---|
| `:310-311` | `app_base = APP_LOAD_ADDRESS`（本板 `0x08020000`）；`vec_base = app_base + APP_VECTOR_OFFSET`（本板 = `app_base`） | — |
| **`:317-319`** | **首字 == `0xffffffff` ⇒ `return`** | **留在 bootloader** |
| `:321` | `#ifdef BOOTLOADER_USE_TOC` —— **本板没编** | 直接落到 `:391` 的 `#else` |
| `:399-401` | `app_base[1]`（复位向量）**< `APP_LOAD_ADDRESS`** ⇒ return | 坏镜像 |
| `:403-405` | `app_base[1]` **≥ `APP_LOAD_ADDRESS + board_info.fw_size`** ⇒ return | 坏镜像 |
| `:409-411` | `crypto_deinit()`（仅安全版） | — |
| `:414` | `arch_flash_lock()` | — |
| **`:417`** | **`arch_systic_deinit()`** —— 关掉 SysTick 中断 | 不关 ⇒ 跳过去后 SysTick 还指向 bootloader 的 `sys_tick_handler` |
| **`:420`** | **`cfini()`** —— 关掉 `/dev/ttyS0` | — |
| **`:423`** | **`clock_deinit()`** —— RCC 打回 HSI（[`main.c:406`](bl-h.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-406)） | 不带 480 MHz 的 PLL 配置进 app，让 app 自己重建 |
| **`:426`** | **`board_deinit()`** —— LED 脚切回输入、清 RCC 复位/使能位（[`main.c:317`](bl-h.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-317)） | — |
| **`:429`** | **`arch_setvtor(vec_base)`** ⇒ `main.c:459 putreg32(addr, NVIC_VECTAB)` | ★ 见 [01_extracted/stm32/vtor-vector-tables](../../01_extracted/stm32/vtor-vector-tables.md) |
| **`:432`** | **`arch_do_jump(app_base)`** ⇒ [`main.c:632`](bl-h.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-632)：SP = `app_base[0]`，PC = `app_base[1]`，先把 CONTROL.SPSEL 清 0 回 MSP | 不返回 |

**⇒ `jump_to_app()` 只要返回，含义**只有一个**：没跳成。**②层据此把 `timeout = 0`（`:777`/`:827`）。

### 6.1 `BOOTLOADER_USE_TOC` / `BOOTLOADER_USE_SECURITY` 分支（本板全关）

`:321-389` 是"安全启动"版本：从 TOC 找 app、验签、解密、拷到 RAM。
本板没定义这两个宏 ⇒ **这段不参与编译**（证明见 [02_code_twin/bootloader/image-toc-crypto](image-toc-crypto.md)）。
**⇒ 本板的"app 有效性"只由两件事决定：首字 + 复位向量落在 flash 范围内。**

---

## 7. 失败落点总表

| 失败情形 | 判在哪 | 落到哪 | 台架现象 |
|---|---|---|---|
| app 未写完（首字 `0xffffffff`） | `:317` | `jump_to_app` return | 留 bootloader，灯闪 |
| app 向量表越界 | `:399` / `:403` | return | 同上 |
| 命令乱序 / 非法 | `cmd_bad:1157` | 回 `0x12 0x13`，**`bl_state=0`**，continue | 上位机看到 INVALID，**超时不取消** |
| 写 flash / 读回校验失败 | `cmd_fail:1163` | 回 `0x12 0x11`，continue | 上位机看到 FAILED |
| 上传超时 | `:655` | `bootloader()` return ⇒ ②层 [`main.c:824`](bl-h.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-824) 再试跳 | 灯停；跳不成 ⇒ `timeout=0` 永久留 |
| 擦除后读回不是 `0xffffffff` | `:785-789` | `cmd_fail` | FAILED |

---

## 8. "我看到的现象由谁产生"

| 现象 | 行号 | 机制 |
|---|---|---|
| 绿 LED 约 10 Hz 闪 | `:640` + `:447-450` | `LED_BLINK` 态下每 50 ms `led_toggle(LED_BOOTLOADER)`；**本板该脚悬空 ⇒ 看不到** |
| 绿 LED 常亮（擦除中） | `:772` | `led_set(LED_ON)` |
| 擦完灯灭一下再恢复闪 | `:782` → `:795` | 先 OFF 做读回验证，验证通过再 BLINK |
| 上位机 `GET_SYNC` 得到 `12 10` | `:676` → `:484` → `:231` → [`uart.c:108`](bl-c.md#^src-src-lib-drivers-device-qurt-uart-c-108) | `bl_type` 已在 `:1150` 锁定为 USART |
| **上传过程中超时被取消**（"我明明设了 5 秒它却一直等"） | `:1145-1147` | 一旦 `GET_SYNC` + `GET_DEVICE` 都见过，`timeout` 被强制置 0 |
| 发 `PROTO_VERIFY_SIG` **没有任何回应** | `:1039-1052` 注释 + `:1140` | 本板没编这个 `case` |
| 发 `PROTO_SET_DELAY` 收到 **INVALID** | `:1037` | 本版已废弃它 |
| 上传成功、最后收到一个 sync 后灯停、板子重启进 app | `:1130` → `:1131` → `:1134` → [`main.c:824`](bl-h.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-824) | — |

---

## 跳转

- **执行序下一步**：`bl.c:1134 return` ⇒ ②层 `main.c:824 jump_to_app()` ⇒ ③/app 侧。
  app 侧第一步 → [01_extracted/nuttx/bootloader-vs-app](../../01_extracted/nuttx/bootloader-vs-app.md)。
- 想搞清 `:317`"首字"和 H7 flash 8 字页的关系 → [02_code_twin/bootloader/flash-cache-c](flash-cache-c.md)。
- 想搞清 `:429 arch_setvtor` 改了哪个寄存器、为什么必要 → [01_extracted/stm32/vtor-vector-tables](../../01_extracted/stm32/vtor-vector-tables.md)。
- 想搞清 `:937 flash_func_read_otp`、`:965 flash_func_read_sn` 在 ②层读的是芯片哪个地址 → [02_code_twin/bootloader/stm32-common-main-c](stm32-common-main-c.md)。
- 想搞清"上位机命令是怎么变成 USB/串口字节的" → [02_code_twin/bootloader/uart-c](uart-c.md)。

---

## 未核实

- `bl.c:83 BL_PROTOCOL_REVISION = 5` 与上位机（`Tools/px_uploader.py`）实际校验的协议版本我没对照，标"未核实"。
- `bl.c:126 PROTO_READ_MULTI_MAX 255` 全仓grep 未见使用者，标"未核实用途"。
- `bl.c:1136 PROTO_DEBUG` 之后到 `:1140 default` 之间的分支已逐行确认（只有一个空 `break`），但**它的历史用途**未核实。

---

## 标注源码（代码 + 本文档对它的解释）

> **这是「代码孪生」层**：上面是代码原文（带行号），下面是**本文档针对这一段说的话**。
> 行号可点，直接跳到 PX4 源码那一行。
### `CMakeLists.txt`
<a id="src-CMakeLists-txt-41"></a>
**↓ 文档在讲这里：**[`CMakeLists.txt:41`](bl-c.md#^src-CMakeLists-txt-41)

```c
    38 │ # ---------------------------------------------------------------------------
    39 │ #
    40 │ # * Common functions should be included in px_base.cmake.
▶   41 │ #
    42 │ # * OS/ board specific fucntions should be include in
    43 │ #	px_impl_${PX4_PLATFORM}.cmake
    44 │ #
```
> **说明**：:990 | PROTO_GET_CHIP_DES (0x2e) | 芯片型号 + 版本字母（main.c:519），本板命中表项 "STM32H7[4\|5]x"（main.c:59） | STATE_PROTO_GET_CHIP_DES | ┃ :1010 | PROTO_GET_VERSION (0x2f) | 回 BOOTLOADER_VERSION（= PX4BLv<major>.<minor>.<patch>g<git>，common/CMakeLists.txt:41 注入） | STATE_PROTO_GET_VERSION |
^src-CMakeLists-txt-41

### `platforms/nuttx/src/bootloader/common/bl.c`
<a id="src-platforms-nuttx-src-bootloader-common-bl-c-34"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:34`](bl-c.md#^src-platforms-nuttx-src-bootloader-common-bl-c-34)

```c
    31 │  *
    32 │  ****************************************************************************/
    33 │ 
▶   34 │ /**
    35 │  * @file bl.c
    36 │  *
    37 │  * Common bootloader logic.
```
> **说明**：源码：platforms/nuttx/src/bootloader/common/bl.c（1175 行） ┃ 层：① 通用（文档注释 bl.c:34 原话：*"should have no board-specific logic"*）
^src-platforms-nuttx-src-bootloader-common-bl-c-34

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-317"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:317`](bl-c.md#^src-platforms-nuttx-src-bootloader-common-bl-c-317)

```c
   314 │ 	 * We refuse to program the first word of the app until the upload is marked
   315 │ 	 * complete by the host.  So if it's not 0xffffffff, we should try booting it.
   316 │ 	 */
▶  317 │ 	if (app_base[APP_VECTOR_OFFSET_WORDS] == 0xffffffff) {
   318 │ 		return;
   319 │ 	}
   320 │ 
```
> **说明**：ARM 的复位向量表第 0 个字是初始 SP，第 1 个字是复位向量。 ┃ jump_to_app() 判"app 有效"的唯一依据就是 bl.c:317 首字 != 0xffffffff。
> **说明**：擦除后、PROG_MULTI 中途 | 0xffffffff | bl.c:317 直接 return ⇒ 留在 bootloader 等人重刷（:771/:824 那条路） |
^src-platforms-nuttx-src-bootloader-common-bl-c-317

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-484"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:484`](bl-c.md#^src-platforms-nuttx-src-bootloader-common-bl-c-484)

```c
   481 │ }
   482 │ 
   483 │ static void
▶  484 │ sync_response(void)
   485 │ {
   486 │ 	uint8_t data[] = {
   487 │ 		PROTO_INSYNC, // "in sync"
```
> **说明**：sync | bl.c:484 | :491 | 0x12 0x10 |
^src-platforms-nuttx-src-bootloader-common-bl-c-484

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-496"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:496`](bl-c.md#^src-platforms-nuttx-src-bootloader-common-bl-c-496)

```c
   493 │ 
   494 │ #if defined(TARGET_HW_PX4_FMU_V4)
   495 │ static void
▶  496 │ bad_silicon_response(void)
   497 │ {
   498 │ 	uint8_t data[] = {
   499 │ 		PROTO_INSYNC,     // "in sync"
```
> **说明**：failure | bl.c:519 | :526 | 0x12 0x11 | ┃ bad_silicon | bl.c:496 | :503 | 0x12 0x14，整段在 #if defined(TARGET_HW_PX4_FMU_V4) 内 ⇒ 本板不编 |
^src-platforms-nuttx-src-bootloader-common-bl-c-496

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-508"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:508`](bl-c.md#^src-platforms-nuttx-src-bootloader-common-bl-c-508)

```c
   505 │ #endif
   506 │ 
   507 │ static void
▶  508 │ invalid_response(void)
   509 │ {
   510 │ 	uint8_t data[] = {
   511 │ 		PROTO_INSYNC, // "in sync"
```
> **说明**：sync | bl.c:484 | :491 | 0x12 0x10 | ┃ invalid | bl.c:508 | :515 | 0x12 0x13 |
^src-platforms-nuttx-src-bootloader-common-bl-c-508

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-519"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:519`](bl-c.md#^src-platforms-nuttx-src-bootloader-common-bl-c-519)

```c
   516 │ }
   517 │ 
   518 │ static void
▶  519 │ failure_response(void)
   520 │ {
   521 │ 	uint8_t data[] = {
   522 │ 		PROTO_INSYNC, // "in sync"
```
> **说明**：invalid | bl.c:508 | :515 | 0x12 0x13 | ┃ failure | bl.c:519 | :526 | 0x12 0x11 |
^src-platforms-nuttx-src-bootloader-common-bl-c-519

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-876"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:876`](bl-c.md#^src-platforms-nuttx-src-bootloader-common-bl-c-876)

```c
   873 │ 				flash_func_write_word(address, flash_buffer.w[i]);
   874 │ 
   875 │ 				// do immediate read-back verify
▶  876 │ 				if (flash_func_read_word(address) != flash_buffer.w[i]) {
   877 │ 					goto cmd_fail;
   878 │ 				}
   879 │ 
```
> **说明**：⇒ 所以 bl.c:876 那句"写完立即读回校验"在 H7 上是在和缓存对话，不是和 flash 对话。
^src-platforms-nuttx-src-bootloader-common-bl-c-876

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-1025"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:1025`](bl-c.md#^src-platforms-nuttx-src-bootloader-common-bl-c-1025)

```c
  1022 │ 			}
  1023 │ 			break;
  1024 │ 
▶ 1025 │ 		case PROTO_SET_DELAY:
  1026 │ 			/*
  1027 │ 			 * Boot delay used to let the bootloader pause before
  1028 │ 			 * starting the app by writing a signature next to the
```
> **说明**：既有素材 work/PX4-bootloader主流程时序图.md:101 写： ┃ 「bl.c:1025 PROTO_SET_DELAY —— 主机设超时（顺带提交首字）」
> **说明**：回验结论：错。 本版 bl.c:1025 的实际代码是：
^src-platforms-nuttx-src-bootloader-common-bl-c-1025

<a id="src-platforms-nuttx-src-bootloader-common-bl-c-1039"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/common/bl.c:1039`](bl-c.md#^src-platforms-nuttx-src-bootloader-common-bl-c-1039)

```c
  1036 │ 			 */
  1037 │ 			goto cmd_bad;
  1038 │ 
▶ 1039 │ #ifdef BOOTLOADER_USE_SECURITY
  1040 │ 
  1041 │ 		// verify the signature of the programmed image
  1042 │ 		//
```
> **说明**：:1053 的 case 整段在 #ifdef BOOTLOADER_USE_SECURITY 里。本板没定义 ⇒ 该 opcode 落到 :1140 default: continue; ┃ ⇒ 不回任何字节。bl.c:1039 的注释把这件事写明白了（故意保持"与非安全版逐字节等价"）。
^src-platforms-nuttx-src-bootloader-common-bl-c-1039

### `platforms/nuttx/src/bootloader/stm/stm32_common/main.c`
<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-59"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:59`](bl-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-59)

```c
    56 │ // There for new silicon will result in STM32F4..,?
    57 │ mcu_des_t mcu_descriptions[] = {
    58 │ 	{ STM32_UNKNOWN,	"STM32???????",		'?'},
▶   59 │ 	{ STM32H74xx_75xx, 	"STM32H7[4|5]x",	'?'},
    60 │ };
    61 │ 
    62 │ typedef struct mcu_rev_t {
```
> **说明**：:975 | PROTO_GET_CHIP (0x2c) | 读 STM32_DEBUGMCU_BASE（main.c:514） | STATE_PROTO_GET_CHIP | ┃ :990 | PROTO_GET_CHIP_DES (0x2e) | 芯片型号 + 版本字母（main.c:519），本板命中表项 "STM32H7[4\|5]x"（main.c:59） | STATE_PROTO_GET_CHIP_DES |
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-59

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-317"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:317`](bl-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-317)

```c
   314 │ #endif
   315 │ }
   316 │ 
▶  317 │ void
   318 │ board_deinit(void)
   319 │ {
   320 │ 
```
> **说明**：:423 | clock_deinit() —— RCC 打回 HSI（main.c:406） | 不带 480 MHz 的 PLL 配置进 app，让 app 自己重建 | ┃ :426 | board_deinit() —— LED 脚切回输入、清 RCC 复位/使能位（main.c:317） | — |
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-317

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-365"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:365`](bl-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-365)

```c
   362 │ 	putreg32(0, STM32_RCC_AHB1ENR);
   363 │ }
   364 │ 
▶  365 │ inline void arch_systic_init(void)
   366 │ {
   367 │ 	/* (re)start the timer system */
   368 │ 	systick_set_clocksource(CLKSOURCE_PROCESOR);
```
> **说明**：:629 | first_word = 0xffffffff | ★ 被延迟提交的 app 首字，见 §5 | ┃ :632 | arch_systic_init() | ②层 main.c:365：把 SysTick 配成 1 ms |
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-365

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-406"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:406`](bl-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-406)

```c
   403 │   *            - Peripheral clocks
   404 │   *            - LSI, LSE and RTC clocks
   405 │   */
▶  406 │ void
   407 │ clock_deinit(void)
   408 │ {
   409 │ 	uint32_t regval;
```
> **说明**：:420 | cfini() —— 关掉 /dev/ttyS0 | — | ┃ :423 | clock_deinit() —— RCC 打回 HSI（main.c:406） | 不带 480 MHz 的 PLL 配置进 app，让 app 自己重建 |
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-406

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-489"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:489`](bl-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-489)

```c
   486 │ 	}
   487 │ }
   488 │ 
▶  489 │ void
   490 │ flash_func_write_word(uintptr_t address, uint32_t word)
   491 │ {
   492 │ 	address += APP_LOAD_ADDRESS;
```
> **说明**：②层的 flash_func_write_word（main.c:489）不是真的写 flash，而是调 fmc.c:92 fc_write()：
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-489

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-496"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:496`](bl-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-496)

```c
   493 │ 	fc_write(address, word);
   494 │ }
   495 │ 
▶  496 │ uint32_t flash_func_read_word(uintptr_t address)
   497 │ {
   498 │ 
   499 │ 	if (address & 3) {
```
> **说明**：它会把 8 个连续 word 攒在 RAM 缓存里，直到第 8 个才真写。 ┃ 同理 flash_func_read_word（main.c:496）走 fmc.c:135 fc_read()，命中缓存时读的是 RAM。
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-496

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-508"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:508`](bl-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-508)

```c
   505 │ }
   506 │ 
   507 │ 
▶  508 │ uint32_t
   509 │ flash_func_read_otp(uintptr_t address)
   510 │ {
   511 │ 	return 0;
```
> **说明**：:892 | PROTO_GET_CRC (0x29) | 遍历 0..fw_size/4，首字位置用暂存的 first_word 顶替（:905-906），回 4 字节 CRC | STATE_PROTO_GET_CRC（:916） | ┃ :923 | PROTO_GET_OTP (0x2a) | ②层 flash_func_read_otp 恒返回 0（main.c:508）⇒ 本板恒回 0 | — |
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-508

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-514"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:514`](bl-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-514)

```c
   511 │ 	return 0;
   512 │ }
   513 │ 
▶  514 │ uint32_t get_mcu_id(void)
   515 │ {
   516 │ 	return *(uint32_t *)STM32_DEBUGMCU_BASE;
   517 │ }
```
> **说明**：:945 | PROTO_GET_SN (0x2b) | 读 96 位 UID（main.c:564 STM32_SYSMEM_UID） | STATE_PROTO_GET_SN | ┃ :975 | PROTO_GET_CHIP (0x2c) | 读 STM32_DEBUGMCU_BASE（main.c:514） | STATE_PROTO_GET_CHIP |
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-514

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-519"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:519`](bl-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-519)

```c
   516 │ 	return *(uint32_t *)STM32_DEBUGMCU_BASE;
   517 │ }
   518 │ 
▶  519 │ int get_mcu_desc(int max, uint8_t *revstr)
   520 │ {
   521 │ 	uint32_t idcode = (*(uint32_t *) STM32_DEBUGMCU_BASE);
   522 │ 	int32_t mcuid = idcode & DEVID_MASK;
```
> **说明**：:975 | PROTO_GET_CHIP (0x2c) | 读 STM32_DEBUGMCU_BASE（main.c:514） | STATE_PROTO_GET_CHIP | ┃ :990 | PROTO_GET_CHIP_DES (0x2e) | 芯片型号 + 版本字母（main.c:519），本板命中表项 "STM32H7[4\|5]x"（main.c:59） | STATE_PROTO_GET_CHIP_DES |
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-519

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-564"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:564`](bl-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-564)

```c
   561 │ 	return 0;
   562 │ }
   563 │ 
▶  564 │ uint32_t
   565 │ flash_func_read_sn(uintptr_t address)
   566 │ {
   567 │ 	// read a byte out from unique chip ID area
```
> **说明**：:923 | PROTO_GET_OTP (0x2a) | ②层 flash_func_read_otp 恒返回 0（main.c:508）⇒ 本板恒回 0 | — | ┃ :945 | PROTO_GET_SN (0x2b) | 读 96 位 UID（main.c:564 STM32_SYSMEM_UID） | STATE_PROTO_GET_SN |
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-564

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-632"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:632`](bl-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-632)

```c
   629 │ #endif
   630 │ 
   631 │ /* Make the actual jump to app */
▶  632 │ void
   633 │ arch_do_jump(const uint32_t *app_base)
   634 │ {
   635 │ 	/* extract the stack and entrypoint from the app vector table and go */
```
> **说明**：:429 | arch_setvtor(vec_base) ⇒ main.c:459 putreg32(addr, NVIC_VECTAB) | ★ 见 01_extracted/stm32/vtor-vector-tables | ┃ :432 | arch_do_jump(app_base) ⇒ main.c:632：SP = app_base[0]，PC = app_base[1]，先把 CONTROL.SPSEL 清 0 回 MSP | 不返回 |
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-632

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-771"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:771`](bl-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-771)

```c
   768 │ #endif
   769 │ 
   770 │ 		/* try to boot immediately */
▶  771 │ 		jump_to_app();
   772 │ 
   773 │ 		// If it failed to boot, reset the boot signature and stay in bootloader
   774 │ 		board_set_rtc_signature(BOOT_RTC_SIGNATURE);
```
> **说明**：②层 main.c:771 第一次 jump_to_app() 失败（app 无效 / 向量表越界 / 跳不过去）
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-771

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-777"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:777`](bl-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-777)

```c
   774 │ 		board_set_rtc_signature(BOOT_RTC_SIGNATURE);
   775 │ 
   776 │ 		/* booting failed, stay in the bootloader forever */
▶  777 │ 		timeout = 0;
   778 │ 	}
   779 │ 
   780 │ 
```
> **说明**：②层 main.c:777 timeout = 0
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-777

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-783"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:783`](bl-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-783)

```c
   780 │ 
   781 │ 	/* start the interface */
   782 │ #if INTERFACE_USART
▶  783 │ 	cinit(BOARD_INTERFACE_CONFIG_USART, USART);
   784 │ #endif
   785 │ #if INTERFACE_USB
   786 │ 	cinit(BOARD_INTERFACE_CONFIG_USB, USB);
```
> **说明**：②层 main.c:783 cinit("/dev/ttyS0,57600", USART) ← 这时串口才被打开
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-783

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-802"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:802`](bl-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-802)

```c
   799 │ 
   800 │ 	while (1) {
   801 │ 		/* run the bootloader, come back after an app is uploaded or we time out */
▶  802 │ 		bootloader(timeout);
   803 │ 
   804 │ 		/* if the force-bootloader pins are strapped, just loop back */
   805 │ 		if (board_test_force_pin()) {
```
> **说明**：层：① 通用（文档注释 bl.c:34 原话：*"should have no board-specific logic"*） ┃ 被谁调：②层 main.c:802 bootloader(timeout)；③层不直接碰它
> **说明**：②层 main.c:802 bootloader(0) ← ★ ①层在这里开始
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-802

<a id="src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-824"></a>
**↓ 文档在讲这里：**[`platforms/nuttx/src/bootloader/stm/stm32_common/main.c:824`](bl-c.md#^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-824)

```c
   821 │ #endif
   822 │ 
   823 │ 		/* look to see if we can boot the app */
▶  824 │ 		jump_to_app();
   825 │ 
   826 │ 		/* launching the app failed - stay in the bootloader forever */
   827 │ 		timeout = 0;
```
> **说明**：写 flash / 读回校验失败 | cmd_fail:1163 | 回 0x12 0x11，continue | 上位机看到 FAILED | ┃ 上传超时 | :655 | bootloader() return ⇒ ②层 main.c:824 再试跳 | 灯停；跳不成 ⇒ timeout=0 永久留 |
> **说明**：发 PROTO_SET_DELAY 收到 INVALID | :1037 | 本版已废弃它 | ┃ 上传成功、最后收到一个 sync 后灯停、板子重启进 app | :1130 → :1131 → :1134 → main.c:824 | — |
^src-platforms-nuttx-src-bootloader-stm-stm32-common-main-c-824

### `src/lib/drivers/device/qurt/uart.c`
<a id="src-src-lib-drivers-device-qurt-uart-c-108"></a>
**↓ 文档在讲这里：**[`src/lib/drivers/device/qurt/uart.c:108`](bl-c.md#^src-src-lib-drivers-device-qurt-uart-c-108)

```c
   105 │ 
   106 │ 	if (_callbacks_configured) {
   107 │ 		uint32_t interval_counter = (timeout_us + (UART_READ_POLL_INTERVAL_US - 1)) / UART_READ_POLL_INTERVAL_US;
▶  108 │ 		// PX4_INFO("UART interval counter = %d", interval_counter);
   109 │ 		int read_len = 0;
   110 │ 
   111 │ 		do {
```
> **说明**：擦完灯灭一下再恢复闪 | :782 → :795 | 先 OFF 做读回验证，验证通过再 BLINK | ┃ 上位机 GET_SYNC 得到 12 10 | :676 → :484 → :231 → uart.c:108 | bl_type 已在 :1150 锁定为 USART |
^src-src-lib-drivers-device-qurt-uart-c-108
