# task_plan · 让 QGC 连上飞控板

> 目标：**QGC 通过"串口3"连上自研飞控板**，为下一步陀螺仪/加计校准铺路
> 建计划：2026-09-29
> 用户决定：**暂时不使用串口1（console）** —— 日志不看了，反正 ST-Link 能直接看芯片

---

## 一、已查实的事实（不用再验）

| 事实 | 证据 |
|---|---|
| bootloader + app 已烧入板子 | openocd `Verified OK` ×2 |
| 板子在跑 PX4 | PC 采样落在 0x0802xxxx（app 区） |
| ★ **25MHz PLL 参数正确** | 能跑到 app 就说明时钟树没问题（原最大未知数，已排除） |
| 串口3 = USART3 = `/dev/ttyS2` = MAVLink TEL1 | `MAV_0_CONFIG=101`(=TELEM1) + `BOARD_SERIAL_TEL1="/dev/ttyS2"` |
| 串口1 = USART1 = console | `CONFIG_USART1_SERIAL_CONSOLE=y` |
| **串口1 的 RX 悬空 → 中断风暴** | `USART1 ISR=0x0de310fe`（ORE/NE/FE 全 1）；NVIC IRQ37 常挂；PC 4 次采样全在该 ISR |
| 8 个 UART 都在 NuttX 里启用了 | app 的 `.config` 第 419-426 行 |

## 二、根因链

```text
串口1（console）的 RX 脚悬空（那个座子上没插东西）
  → 浮空线持续产生帧错误/噪声
  → NuttX 的 RX 中断疯狂触发
  → CPU 绝大部分时间耗在 USART1 的 ISR 里
  → MAVLink（串口3）拿不到足够的运行时间 → QGC 连不上
```

**关键**：用户插的"串口3"位置**是对的**；捣乱的是**另一个空着的口（串口1）**。

## 三、阶段

| # | 阶段 | 状态 | 说明 |
|---|---|---|---|
| P0 | 定案修法 | ✅ 完成 | 用户已决定：暂时不用串口1 |
| P1 | 改 NuttX 配置：去掉 console | ✅ 完成 16:38 | 删 `CONFIG_USART1_SERIAL_CONSOLE=y`；`CONFIG_STM32H7_USART1=y` 保留 |
| P2 | 重建 app | ✅ 完成 16:39 | 单实例 `make`，EXIT=0，无假链接错误 |
| P3 | 重烧 app | ✅ 完成 16:40 | openocd **dual_bank**，Verified OK |
| P4 | 验证 | ✅ 完成 16:41 | ①②③④ 全过，见下「五、验收判据」结果 |
| P5 | QGC 真连一次 | ⬜ 待用户 | 需要用户开 QGC（GUI 只能人来开）★ 现在可以做了 |

## 四、具体改法（P1）

```text
文件：~/桌面/RM2027/PX4-Autopilot/boards/rm2027/fmu-h743/nuttx-config/nsh/defconfig
改动：删掉（或注释）CONFIG_USART1_SERIAL_CONSOLE=y
保留：CONFIG_STM32H7_USART1=y  ← ★ 必须保留！
```

**为什么必须保留 `STM32H7_USART1=y`**：

```text
NuttX 的 /dev/ttySx 编号按"已启用的 UART 顺序"排。
如果把 USART1 整个删掉，编号会整体前移：
   ttyS0=USART2  ttyS1=USART3  ttyS2=UART4 ...
而我们的 TEL1=/dev/ttyS2、RC=/dev/ttyS4 就会全部指错口！
所以：只去掉"当 console 用"这件事，USART1 这个设备本身保留。
```

## 五、验收判据（P4）—— 结果：全部通过 ✅

```text
① 读寄存器（ST-Link）：
   USART1 CR1 应为 0x00000000 或至少 RXNEIE 位为 0  ← 不再有中断风暴
   USART3 CR1 应被置位（UE/TE/RE）                  ← MAVLink 起来了
   两者都满足 = 修好了

   ★ 实测 16:40：
     USART1 CR1 = 0x00000000  ✅（RXNEIE=0，整个 USART1 未启用）
     USART1 ISR = 0x000000c0  ✅（只有 TXE/TC；ORE/NE/FE 全为 0，帧错误消失）
     USART3 CR1 = 0x2000002d  ✅（UE=1 RE=1 TE=1 RXNEIE=1）
     USART3 ISR = 0x08e000d0  ✅（低 4 位 = 0，无 PE/FE/NE/ORE）
     NVIC ISER1 = 0x1f208088  ✅（IRQ37=USART1 已不在挂起表；原 0x1f008028）
     PC = 0x0802c390（app 区，PX4 在跑）

② 读串口（我在电脑侧读 /dev/ttyUSB0）：
   能看到 MAVLink 帧（十六进制以 FD 或 FE 开头）
   = QGC 一定能连上

   ★ 实测 16:41：6s 抓 608 B，帧头 fd…；含 HEARTBEAT（fd09 0000 … msgid=0x00）
     复测数据率 5s / 535 B ≈ 107 B/s，5s 内 6 个 HEARTBEAT（≈1.2 Hz）→ 持续稳定

③ PC 采样 3 次确认不再长期停在同一个中断里
   ★ 实测 16:41：0x0802c390 / 0x0802c390 / 0x080239d4 → 会变，不卡在 ISR

④ 用户开 QGC 实际连一次（GUI 只能人开）→ ⬜ P5 待做
```

## 六、备选方案（万一 P1 不行）

```text
B1  把 console 换到别的 UART（会动 ttyS 编号，要同步改 TEL1/RC 设置，麻烦）
B2  给串口1 的 RX 加物理上拉 / 接地（要飞线，属于硬件）
B3  保留 console 但关掉它的 RX 缓冲（NuttX 支持度未知）
```

## 七、决策记录

| # | 日期 | 决策 | 依据 | 回退 |
|---|---|---|---|---|
| D1 | 2026-09-29 | 暂时不使用串口1（去掉 console） | 用户决定；我们已有 ST-Link 可直接查芯片状态，不依赖串口日志 | 把 `CONFIG_USART1_SERIAL_CONSOLE=y` 加回去即可 |

## 八、遇到的错误

| 错误 | 次数 | 解决 |
|---|---|---|
| app 烧录 Verify Failed（跨 1MB 边界） | 1 | 改用 `target/stm32h7x_dual_bank.cfg` |
| bootloader 首次不进 app | 1 | RTC 备份寄存器残留 BL 签名 → 再复位一次 |
| 链接报 USB 符号未定义 | 4 | 旧归档 `.a` 残留；build 树与主 NuttX 树**两处都要清** |
| 误读 bootloader 的 NuttX `.config` | 1 | 应用 `build/<board>_default/NuttX/nuttx/.config` |
| 担心「只删 defconfig 一行不会生效」 | 0（未发生，事前查明） | PX4 把 defconfig 注册为 `CMAKE_CONFIGURE_DEPENDS`，make 自动 reconfigure + olddefconfig（`platforms/nuttx/cmake/init.cmake` L56-84）。**无需**手删 `.config`，**无需** distclean |

## 九、结论（2026-09-29 16:41，会话 2）

```text
✅ 根因已消除：USART1 中断风暴没了（CR1=0，ISR 无错误位，NVIC IRQ37 已摘）
✅ MAVLink 已起来：USART3 CR1=0x2000002d，PC 侧持续收到 fd 开头帧 + HEARTBEAT
✅ 用户插线位置本来就是对的（串口3）
→ 只剩 P5：用户开 QGC 点连接。波特率 57600。
```

### 验收标准（本任务"修好了"的定义）

| # | 判据 | 结果 |
|---|---|---|
| 1 | USART1 `CR1` 的 RXNEIE 位 = 0 | ✅ `0x00000000` |
| 2 | USART3 `CR1` 的 UE/TE/RE 置位 | ✅ `0x2000002d` |
| 3 | PC 侧 `/dev/ttyUSB0` 收到 `fd/fe` 开头帧 | ✅ 含 HEARTBEAT，≈107 B/s |
| 4 | PC 采样 3 次不在同一中断 | ✅ |
