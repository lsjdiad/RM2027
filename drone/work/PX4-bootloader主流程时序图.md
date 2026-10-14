# PX4 bootloader 主流程时序图（`common/bl.c` + `stm32_common/main.c`）

> **用途**：你要写 ③板级层（`bootloader_main.c` + `hw_config.h`，都在复刻的 25 文件里）。
> 本表只回答四件事：**①层在什么时机调 ②层的哪些函数 / 台架上能看到什么 / 失败落到哪 / 你那层要填什么**。
> **只写决策点 + 行号，不贴源码。** 行号前缀统一用 `bl.c:`（`common/bl.c`）与 `main.c:`（`stm/stm32_common/main.c`）。

---

## 0. 先分清：谁决定"跳不跳"

| 文件 | 层 | 职责 | 关键点 |
|---|---|---|---|
| `common/bl.c`（1175 行） | ① | **只管"等主机上传"**：讲协议、擦、写、算 CRC | **它不知道跳不跳** —— `bootloader()` 一 `return` 就表示"该跳了" |
| `stm32_common/main.c` | ② | **决定跳不跳**：force 引脚 / USB / 串口 break / 超时 | 调 `bootloader(timeout)`（`main.c:802`）；跳失败就 `timeout=0` 永久留下 |
| `boards/<板>/src/bootloader_main.c` + `hw_config.h` | ③ | 板级钩子与常量 | 参照上游板：`board_late_initialize()`、`board_timerhook()`；`BOOTLOADER_DELAY` |

> **`jump_to_app()` 定义在 ①（`bl.c:308`），但调用在 ②（`main.c:771`、`main.c:824`）** —— 这就是 ①/② 分工最直观的一处。

---

## 1. `main.c` 决策骨架（上电 → 跳 app / 等上传）

| 行号 | 决策点 | 含义 | 后果 |
|---|---|---|---|
| `main.c:689` | **`check_ecc_errors()`**（被 `#if defined(CONFIG_ARCH_CHIP_STM32H7)` 包住） | H7 专属：启动前清扫 flash ECC 坏扇区 | 见 §5"ECC 坏扇区" |
| `main.c:663` | `unsigned timeout = BOOTLOADER_DELAY` | 等上传的默认时长（本板 = **5000 ms**，`boards/rm2027/fmu-h743/src/hw_config.h:88`） | 超时后离开 bootloader |
| `main.c:712` | `board_set_rtc_signature(0)` | 清"启动到 bootloader"的 RTC 签名 | — |
| `main.c:719` | **`if (board_test_force_pin())`** | 跳线/引脚被拉 ⇒ **强制进 bootloader** | `try_boot = false` |
| `main.c:734` | **`if (px4_arch_gpioread(BOARD_VBUS) != 0)`** | USB 已插入 ⇒ 不急着启动，改为设超时等待 | 等主机 |
| `main.c:756` | **`if (board_test_usart_receiving_break())`** | 串口 RX 正在收 break ⇒ **强制进 bootloader** | `try_boot = false` |
| `main.c:763` | `if (try_boot)` | 判断结论：直接试着启动 | — |
| `main.c:767` | `board_set_rtc_signature(BOOT_RTC_SIGNATURE)` | 打标记："我是跳过去的" | 下次复位可据此停住 |
| **`main.c:771`** | **`jump_to_app()` ← 第 1 次尝试** | 通常路径：直接跳 app | 返回 = **没跳成** |
| `main.c:777` | `timeout = 0` | 跳失败 ⇒ **永久留在 bootloader** | 不再自动尝试 |
| `main.c:781` | `/* start the interface */` | 初始化 USB/串口通道 | — |
| `main.c:800` | `while (1)` | 主循环 | — |
| **`main.c:802`** | **`bootloader(timeout)`** | ★ 进入 ①：等主机上传 | `return` ⇒ 上传完 或 超时 |
| `main.c:805` | `if (board_test_force_pin())` | 跳线还插着 ⇒ 继续等 | `continue` |
| `main.c:812` | `if (board_test_usart_receiving_break())` | 还在收 break ⇒ 继续等 | `continue` |
| `main.c:820` | `board_set_rtc_signature(BOOT_RTC_SIGNATURE)` | 同上打标记 | — |
| **`main.c:824`** | **`jump_to_app()` ← 第 2 次尝试** | 上传完 / 超时后，试着跳 app | 返回 = 没跳成 |
| `main.c:827` | `timeout = 0` | 又失败 ⇒ **永久留在 bootloader** | 死等到重刷 |

**⇒ 台架结论：`main.c` 是"跳不跳"的唯一裁判；`bl.c` 只在裁判说"去等上传"时才上场。**

---

## 2. `bl.c` 主循环（`bootloader()`：`:624` → 末尾）

| 行号 | 决策点 | 调用的 ②/板级实现 | 可见判据 |
|---|---|---|---|
| `bl.c:624` | `bootloader(unsigned timeout)` 入口 | — | — |
| `bl.c:629` | `uint32_t first_word = 0xffffffff` | — | 见 §6（**app 有效标志**） |
| `bl.c:632` | `arch_systic_init()` | `main.c:365` | — |
| `bl.c:635-637` | `if (timeout)` ⇒ 设 `timer[TIMER_BL_WAIT]` | — | — |
| **`bl.c:640`** | **`led_set(LED_BLINK)`** | `main.c:609`（`led_toggle`） | ★ **LED 开始闪 = 空闲等主机** |
| `bl.c:642` | `while (true)` 主循环 | — | — |
| **`bl.c:654-656`** | **超时：`if (timeout && !timer[TIMER_BL_WAIT]) return;`** | — | LED 闪了 `timeout` ms 后不闪 ⇒ 走人 |
| `bl.c:659` | 等主机字节（`buf_get`/`cin`） | `bl.c:295`/`bl.c:200` | — |
| `bl.c:676` | `case PROTO_GET_SYNC` | — | 回 sync 应答 |
| `bl.c:696` | `case PROTO_GET_DEVICE`（子项 `:709/:713/:717/:721/:725`） | `cout` 回 `bl_proto_rev`/`board_type`/`board_rev`/`fw_size`/版本 | — |
| `bl.c:760` | `if (check_silicon())` ⇒ `goto bad_silicon`(`bl.c:761`) | `main.c:559` | 回 bad_silicon 应答 |
| `bl.c:747`/`bl.c:751` | `PROTO_CHIP_FULL_ERASE` / `PROTO_CHIP_ERASE` | — | — |
| `bl.c:766-767` | 先查 `bl_state & STATE_ALLOWS_ERASE`，不足 ⇒ `cmd_bad` | — | 回 invalid 应答 |
| **`bl.c:772`** | **`led_set(LED_ON)`** | `main.c:573`（`led_on`） | ★ **LED 常亮 = 正在擦除** |
| `bl.c:777-778` | `flash_func_sector_size(i)` / `flash_func_erase_sector(i, full)` | `main.c:468` / `main.c:478` | — |
| **`bl.c:782`** | **`led_set(LED_OFF)`** | `main.c:591` | ★ **擦完 LED 灭** |
| **`bl.c:785-787`** | **擦后校验**：逐字读回，非 `0xffffffff` ⇒ `cmd_fail` | `flash_func_read_word` → `main.c:496` | 失败回 failure 应答 |
| **`bl.c:795`** | **`led_set(LED_BLINK)`** | — | ★ **回到闪 = 擦干净了，继续等** |
| `bl.c:805` | `case PROTO_PROG_MULTI`（写数据） | `flash_func_write_word` → `main.c:490` | — |
| `bl.c:853`/`bl.c:866` | 若写入的是 app 向量表首字 ⇒ **只暂存进 `first_word`，不立刻写** | — | 见 §6 |
| `bl.c:892` | `case PROTO_GET_CRC` | — | 回 CRC（`:915` `cout_word`） |
| `bl.c:905-906` | 算 CRC 时**用暂存的 `first_word` 代替读值** | — | 保证 CRC 对应"完整镜像" |
| `bl.c:1025` | `case PROTO_SET_DELAY` | — | 见下 |
| `bl.c:1062-1080` | **提交首字**：`flash_func_write_word`(`:1074`) → **立即读回校验**(`:1076`) → 复位 `first_word`(`:1080`) | `main.c:490`/`main.c:496` | 校验不过 ⇒ `cmd_fail` |
| `bl.c:1053` | `case PROTO_VERIFY_SIG` | `crypto.c` | — |
| **`bl.c:1106`** | **`case PROTO_BOOT`（主机下令"启动"）** | — | — |
| `bl.c:1113` | 再次校验"允许重启"状态，不足 ⇒ `cmd_bad` | — | — |
| `bl.c:1118-1126` | 同样流程提交首字 + 读回校验 | `main.c:490`/`main.c:496` | — |
| **`bl.c:1130`** | **`sync_response()`** | — | ★ 主机收到 sync = **可以跳了** |
| `bl.c:1131` | `delay(100)` | `bl.c:454` | — |
| **`bl.c:1134`** | **`return;`** ⇒ 交回 ②，由 `main.c:824` 跳 app | — | ★ **LED 停闪 / 主机动起来** |

---

## 3. 命令协议分派表（上位机 → bootloader）

| 行号 | 命令 | 干什么 |
|---|---|---|
| `bl.c:676` | `PROTO_GET_SYNC` | 握手（也是"允许后续操作"状态位） |
| `bl.c:696` | `PROTO_GET_DEVICE` | 报设备信息（`:709` BL 版本 / `:713` 板 ID / `:717` 板版本 / `:721` 固件大小 / `:725` 向量区） |
| `bl.c:747` | `PROTO_CHIP_FULL_ERASE` | 全片擦除 |
| `bl.c:751` | `PROTO_CHIP_ERASE` | 只擦 app 区 |
| `bl.c:805` | `PROTO_PROG_MULTI` | 写 flash 数据（**首字延迟提交**） |
| `bl.c:892` | `PROTO_GET_CRC` | 回 app 区 CRC（主机校验用） |
| `bl.c:923` | `PROTO_GET_OTP` | 读 OTP |
| `bl.c:945` | `PROTO_GET_SN` | 读唯一序列号 |
| `bl.c:975` | `PROTO_GET_CHIP` | 读芯片 ID |
| `bl.c:990` | `PROTO_GET_CHIP_DES` | 读芯片描述 |
| `bl.c:1010` | `PROTO_GET_VERSION` | 读版本字符串 |
| `bl.c:1025` | `PROTO_SET_DELAY` | ⚠️ **已废弃：`bl.c:1037` 直接 `goto cmd_bad`（NACK），不做任何事**（注释原话：*"It never worked correctly on modern FMUs … so it has been removed"*；`:107` 的宏定义也标着 `deprecated; always NACKed`） |
| `bl.c:1053` | `PROTO_VERIFY_SIG` | 签名校验 |
| `bl.c:1106` | `PROTO_BOOT` | ★ 提交首字 → 应答 → **返回去跳 app** |
| `bl.c:1136` | `PROTO_DEBUG` | 调试命令 |

---

## 4. ★ 台架可见性总表（你唯一的"眼睛"）

> ⚠️ **先记住一件事：bootloader 里没有任何 `printf`/文本日志。** 我查了 `bl.c` 与 `main.c` —— 唯一的输出是 **LED** 和 **二进制协议应答**（`cout`，`bl.c:231` → USB `:236` / 串口 `:243`）。所以台架上**看不到可读文字**，只能看灯 + 上位机的反应。

### 4.1 LED（`led_set`，`bl.c:463`）

| 现象 | 触发处 | 含义 |
|---|---|---|
| **约 10 Hz 闪烁** | `bl.c:640` 设 `LED_BLINK`；闪烁由 `sys_tick_handler` `bl.c:447-449` 实现（每 50 个 tick 翻转一次 ⇒ 50 ms） | **空闲，正在等主机命令** |
| **常亮** | `bl.c:772` `LED_ON` | **正在擦除**（批量写 flash 期间） |
| **熄灭** | `bl.c:782` `LED_OFF` | 擦除动作结束 |
| **恢复闪烁** | `bl.c:795` `LED_BLINK` | 擦干净并校验通过，回到等待 |
| **一直闪、然后停** | `bl.c:654-656` 超时返回 ⇒ 交给 `main.c:824` | 超时后要么跳 app（灯被 app 接管），要么永久停 bootloader（见 §5） |

### 4.2 协议应答（4 种，`cout` 出去的原始字节）

| 应答函数 | 定义 / 发送处 | 什么时候发 |
|---|---|---|
| `sync_response` | `bl.c:484`（发送 `:491`） | 命令成功、或 `PROTO_BOOT` 收尾（`bl.c:1130`） |
| `bad_silicon_response` | `bl.c:496`（发送 `:503`） | 芯片型号不匹配（`bl.c:761` 等） |
| `invalid_response` | `bl.c:508`（发送 `:515`） | 命令非法 / 状态序列不对（`cmd_bad`，`bl.c:1157`） |
| `failure_response` | `bl.c:519`（发送 `:526`） | 操作失败（`cmd_fail`，`bl.c:1163`） |

**⇒ 判据写对没写对：**
1. **上电灯在闪** ⇒ bootloader 跑起来了、且在等你（而不是已经跳进 app）→ 若你的板"上电灯不闪"，优先查 ③层的 LED 定义与 force 引脚
2. **上位机 `GET_SYNC` 能收到 sync 应答** ⇒ ③层的 USB/串口通道对了
3. **擦除时灯常亮、擦完恢复闪** ⇒ ②层 flash 擦除实现可用
4. **写完 + `PROTO_BOOT` 后收到 sync，灯停、app 起来** ⇒ 端到端成功

---

## 5. 失败路径落点

| 失败情形 | 在哪判 | 落到哪 | 台架现象 |
|---|---|---|---|
| **app 未写完**（首字仍是 `0xffffffff`） | `bl.c:317-318` | `jump_to_app()` **直接 `return`** | 灯继续闪 = 留在 bootloader |
| **镜像目录找不到** | `bl.c:336-337` | `return` | 同上 |
| **镜像校验失败（TOC/CRC）** | `bl.c:341-343` | `return`（注释原文：*stay in btl*） | 同上 |
| **签名校验失败** | `bl.c:351-352` | **跳过该 app** | 同上 |
| **解密失败** | `bl.c:358-359` | 跳过该 app | 同上 |
| **向量表越界**（高于 `APP_LOAD_ADDRESS + fw_size`） | `bl.c:399-404` | `return` | 同上 |
| **上传超时** | `bl.c:654-656` | `return` ⇒ `main.c:824` 再试跳 app | 灯停 ⇒ app 起来；跳不成 ⇒ **永久停** |
| **命令非法 / 序列不对** | `cmd_bad` `bl.c:1157-1161` | 回 `invalid_response()` + `bl_state=0` + `continue` | **不杀超时**（可能是垃圾字节） |
| **写/擦失败（读回校验不过）** | `cmd_fail` `bl.c:1163-1166` | 回 `failure_response()` + `continue` | 同上 |
| **芯片不匹配** | `bad_silicon` `bl.c:1169` | 回 `bad_silicon_response()` | — |
| **跳 app 后又回到 bootloader** | `main.c:777` / `main.c:827` | **`timeout = 0` ⇒ 永久留在 bootloader** | 灯一直闪，不再自动跳 ⇒ **必须重刷** |
| **ECC 坏扇区（H7）** | `main.c:689` → `ecc_scrub.c:125` | 坏扇区被**擦掉**：参数区坏 ⇒ 回默认；app 区坏 ⇒ 校验失败 ⇒ 留在 bootloader | 见下 |

> **ECC 那条读法**：它**不报错、不打印**，只是"把坏扇区擦掉" —— 所以现象是"参数莫名其妙回默认了"或"app 突然过不了校验"，而不是一条错误信息。这也是"静默失败"的典型。

---

## 6. ★ 纪律（Lead 要的那一条）

> ### 凡是用 flash 里一个标志位决定启动行为的固件，必须交代三件事：**谁写它、何时写、写失败或掉电了怎么办。**

**正例 —— 就是这份代码（`bl.c`）：**

| 三问 | PX4 H7 bootloader 的答案 | 证据 |
|---|---|---|
| **标志是什么** | **app 向量表的第一个字**（`APP_VECTOR_OFFSET`）；无效态 = `0xffffffff` | 检查：`bl.c:317`；初值：`bl.c:629` |
| **谁写它** | **bootloader**（`flash_func_write_word` → ②层 `main.c:490`） | `bl.c:1074`、`bl.c:1119` |
| **何时写** | **全部数据写完 + 状态序列合法（`STATE_ALLOWS_REBOOT`）+ 收到 `PROTO_BOOT` 之后**，作为**最后一步**提交。**⚠️ 只有两处**：`bl.c:1073-1081`（VERIFY_SIG，**本板未编**）与 `bl.c:1118-1127`（PROTO_BOOT）。**`PROTO_SET_DELAY` 不是提交点** —— 它已废弃（`bl.c:1037 goto cmd_bad`） | `bl.c:1113`、`bl.c:1118`；状态定义 `bl.c:150`/`bl.c:154`，注释 `bl.c:627` |
| **写失败怎么办** | **写完立即读回校验**，不一致 ⇒ `cmd_fail`（回 failure 应答） | `bl.c:1076`、`bl.c:1121` |
| **掉电怎么办** | 首字仍是 `0xffffffff` ⇒ `jump_to_app()` 判"app 无效" ⇒ **留在 bootloader 等重刷**（永不跳半成品） | `bl.c:317-318` |

**同类的反面例子（我们自己的 G071 电调）**：app 有效标志在第 0 字节，**只有写回 1 才启动** —— 现象是"每次上电停在 bootloader、app 不跑"，看起来像硬件坏了，实际是协议层；**电调 bootloader 的文档没交代"它需要那个标志"**（漏的正是第 3 件："失败/掉电了怎么办"）。

> **⇒ 可推广的一句话**：**任何"flash 一个字节决定板子能不能用"的设计，都必须把"失败/掉电后如何自证"写进文档，否则它的失败模式一定是静默的**（P X4 用"最后写 + 读回校验 + 无效态即安全态"三招把它变成可见、可恢复的）。

---

## 7. 你在 ③板级层要填什么 + 怎么判断写对了

| 要填的东西 | 上游参照 | 判断写对了 |
|---|---|---|
| `board_late_initialize()` | `boards/matek/h743-slim/src/bootloader_main.c:66` | 板子上电能进 bootloader（LED 闪 / 上位机能握手） |
| `board_timerhook()` | 同上 `:72` | 1 ms 计时正常 ⇒ LED 闪烁频率稳定、超时按预期触发 |
| `BOOTLOADER_DELAY` | 本板 `boards/rm2027/fmu-h743/src/hw_config.h:88`（= **5000**） | 上电后"闪灯等待"的时长符合预期（改大 ⇒ 等更久，方便手忙脚乱时抢救） |

**建议的读码顺序**：`main.c:700-830`（决策骨架）→ `bl.c:624-660`（进循环 + 超时）→ `bl.c:1106-1134`（上传收尾）→ `bl.c:308-433`（跳 app 的校验链）。

---

## 未核实 / 边界

- `bl.c:1-17` 等纯注释区段、`bl.c:255-272` 那段"自带默认宏"（守卫是 `#if defined(TARGET_HW_PX4_PIO_V1)`，`bl.c:252` → `bl.c:272`，即**只给 PX4IO 板用**；本板走 ②层实现）我只标了作用，未逐行展开。
- `PROTO_DEBUG`(`bl.c:1136`) 之后到 `cmd_bad`(`bl.c:1157`) 之间的分支未逐条列。
- `main.c:713-718` 之间（RTC 签名与 force 检查之间的几行）未逐行核实，只标了关键决策行。
- `BOOTLOADER_DELAY` 的值取自**本板** `hw_config.h:88`；不同板可能不同（上游多为 5000）。
