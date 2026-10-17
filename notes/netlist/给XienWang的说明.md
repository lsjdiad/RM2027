# rm2027 / FMU 板：4 路 ESC 的定时器与引脚分配修正

- 提交：`fix(board/rm2027): 修正 4 路 ESC 的定时器/引脚分配 —— 依据网表实际连线`
- 补丁：`0001-fix-board-rm2027-4-ESC.patch` —— 可直接 `git am` 到你的 `teaching/clean`
  （已用 `git diff remotes/rm2027/teaching/clean main -- <这两个文件>` 核实：两分支上这两个文件逐字节一致，所以补丁基底通用、不会冲突）
- 影响文件：`boards/rm2027/fmu-h743/src/timer_config.cpp`、`src/board_config.h`

## 一句话

原来 4 路 ESC 的引脚**全配错了**：**1、4 号电机没有输出，2、3 号错位**。已按 FMU 板网表的实际连线改正；编译通过，**尚未上板验证**。

## 问题

| | 原代码（错） | 实际连线（网表） |
|---|---|---|
| 电机 1 | PA8 | **PE11** = TIM1_CH2 |
| 电机 2 | PE11 | **PE13** = TIM1_CH3 |
| 电机 3 | PE13 | **PC8** = TIM8_CH3 |
| 电机 4 | PE14 | **PC9** = TIM8_CH4 |

`PA8` 与 `PE14` 在网表里**各自只有 U1 一个成员** —— 悬空、不连任何座子，所以电机 1/4 的指令发到空脚上。

## 原因：把原理图上的表**读反了**

`board_config.h` 原注释写：

> 预留：TIM8_CH3/CH4 = PC8 / PC9（原理图资源表列了，但未接 ESC 座）

但那张表的原文是（用客户端 API 从图面上读出来的）：

```
资源汇总
All Timer For H Bridge        ← 「供 H 桥（电机驱动）使用的所有定时器」
  Timer1 CH1  CH2  CH3
  Timer8  CH3 CH4             ← TIM8_CH3/CH4 就在这张表里
  Timer15 CH1/N   Timer16 CH1   TIM17 CH1/N
  Timer5 CH1 CH2 CH3   Timer3 CH4
```

表头是 **"All Timer For H Bridge"**，即"这些都是给电机用的"，**TIM8_CH3/CH4 从未被标为"预留/未接"**。所以原注释与它自己引用的表原意相反，也与实际连线相反。

## 座子编号是怎么定的（三路证据交叉）

板上有 4 个 ESC 座，丝印位号依次是 `U13 / U11 / U14 / U15`，三者顺序一致地都指向 ESC1..4：

| 证据 | ESC1(U13) | ESC2(U11) | ESC3(U14) | ESC4(U15) |
|---|---|---|---|---|
| 信号网 | `ESC_DSHOT1` | `ESC_DSHOT2` | `ESC_DSHOT3` | `ESC_DSHOT4` |
| 电流采样 | `ADC1_IN10`(PC0) | `ADC1_IN11`(PC1) | `ADC1_IN4`(PC4) | `ADC2_IN8`(PC5) |
| 遥测串口 | `UART4_RX` | `USART6_RX` | `UART7_RX` | `UART8_RX` |

其中电流采样那行与 `board_config.h` 里已有的 `ADC_ESC1..4 = PC0/PC1/PC4/PC5` 完全一致，遥测串口那行与 `rc.board_extras` 里已有的 `ESC1=UART4 ESC2=USART6 ESC3=UART7 ESC4=UART8` 完全一致 —— 也就是说**这两处原本就写对了**，只有 PWM 引脚那一处写错。

## 修改内容

### 1. `src/timer_config.cpp`

```diff
 constexpr io_timers_t io_timers[MAX_IO_TIMERS] = {
 	initIOTimer(Timer::Timer1, DMA{DMA::Index1}),
+	initIOTimer(Timer::Timer8, DMA{DMA::Index1}),	/* ESC3/ESC4 在 TIM8 上 */
 };

 constexpr timer_io_channels_t timer_io_channels[MAX_TIMER_IO_CHANNELS] = {
-	initIOTimerChannel(io_timers, {Timer::Timer1, Timer::Channel1}, {GPIO::PortA, GPIO::Pin8}),   /* ESC1 */
-	initIOTimerChannel(io_timers, {Timer::Timer1, Timer::Channel2}, {GPIO::PortE, GPIO::Pin11}),  /* ESC2 */
-	initIOTimerChannel(io_timers, {Timer::Timer1, Timer::Channel3}, {GPIO::PortE, GPIO::Pin13}),  /* ESC3 */
-	initIOTimerChannel(io_timers, {Timer::Timer1, Timer::Channel4}, {GPIO::PortE, GPIO::Pin14}),  /* ESC4 */
+	initIOTimerChannel(io_timers, {Timer::Timer1, Timer::Channel2}, {GPIO::PortE, GPIO::Pin11}),  /* ESC1 = 座 U13 */
+	initIOTimerChannel(io_timers, {Timer::Timer1, Timer::Channel3}, {GPIO::PortE, GPIO::Pin13}),  /* ESC2 = 座 U11 */
+	initIOTimerChannel(io_timers, {Timer::Timer8, Timer::Channel3}, {GPIO::PortC, GPIO::Pin8}),   /* ESC3 = 座 U14 */
+	initIOTimerChannel(io_timers, {Timer::Timer8, Timer::Channel4}, {GPIO::PortC, GPIO::Pin9}),   /* ESC4 = 座 U15 */
 };
```

**关键点：四路 ESC 横跨两个高级定时器**（TIM1 两路 + TIM8 两路），所以 `io_timers[]` 里必须同时登记 TIM8。

这样可行是有实装依据的：`boards/aedrox/aedroxh7` 用的引脚组合与我们需要的一模一样（`TIM8_CH4=PC9`、`TIM8_CH3=PC8`、`TIM1_CH2=PE11`、`TIM1_CH3=PE13`），它在 PX4 里正是 `TIM1 + TIM8` 混用、DMA 都是 `DMA::Index1`。而且 DShot 驱动本身按定时器组遍历（`src/drivers/dshot/DShot.cpp`：`for (timer_index = 0; timer_index < MAX_IO_TIMERS; ...)`），每组有独立速率参数（`<prefix>_TIM<n>`）。

### 2. `src/board_config.h`

修正 PWM/DShot 段注释，按实际连线列出 4 路，写明跨两个定时器、`PA8/PE14` 悬空。

## 验证

- ✅ `make rm2027_fmu-h743_default` 通过；FLASH 占用 `1555240 B`（84.75%），与修改前完全一致
- ❌ **未上板验证** —— 需要你们用 `actuator_test` 逐个通道确认"到底哪个座子上的电机在动"（`default.px4board` 里 `CONFIG_SYSTEMCMDS_ACTUATOR_TEST=y` 已开）

## ⚠️ 需要你确认的两件事

原理图上还有你手写的、**带问号的未决批注**：

```
pa7  pA8  改成timer1ch1一对互补？spi去，用spi2
UsART1 砍，换timer8
```

1. **这两条批注会不会在后续版本落地？** 如果会（比如真的"USART1 砍掉换 TIM8" —— 那会动到 H104 的串口），引脚还会变，这个补丁就需要跟着更新。
2. 顺带说明：这也解释了 `PA8` 为什么有个 `TIM1_CH1` 的网络名却完全悬空 —— 你当时在考虑把 PA7/PA8 做成"一对互补"输出，所以没接到 ESC 座上。

## 顺带发现（另一个"照表抄"的后果）

`board_config.h` 里挂着一个未决问题「待硬件确认电压来自哪里（ESC 板经 UART 上报？还是需要飞线？）」。拉电调板网表后可以回答：

- **电流**：电调板上用 `3 mΩ` 分流电阻（`U5 = 3W-3mR-1%`）+ 放大器做好后，**从接插件脚 1 送出模拟电压**给飞控的 PC0/PC1/PC4/PC5
- **电压**：电调板的接插件上**没有**把 VBAT 分压送出来（脚 1 只有电流）⇒ 电池总电压**只能从 ESC 遥测拿**（接插件脚 2 的那 4 路 UART，AM32 那类固件会上报电压/电流/转速/温度）

所以**不需要飞线**；`ADC_BATTERY_VOLTAGE_CHANNEL` 现在指向 ESC1 的电流通道那个占位是拿不到电压的，正解是走 ESC 遥测接进 `battery_status`。

## 证据文件

```
FMU.net                FMU 板网表（Protel 2.0，从客户端导出）
ESC.net                ESC 板网表
FMU-原理图文字.json     FMU 图面上全部 44 条文字（含资源汇总表与两条批注的原文 + 坐标）
parsed.json            FMU 网表解析结果（U1 引脚 → 网络 映射）
```
