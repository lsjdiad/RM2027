# review-05 · 协处理器审计：飞控上的 STM32F103C8T6 到底需不需要

- 审计人：coproc-auditor（**纯静态**：只读原理图 PDF + 只读 PX4 源码，未修改任何 PX4 文件、未接 SWD、未烧写）
- 日期：本次会话
- 主证据：`references/硬件手册/FMU_飞控板_原理图_2026-09-24.pdf`（**单页**，`pdfinfo` 实测 `Pages: 1`，页面 1721.88 × 1246.68 pt，嘉立创EDA / V1.0）
- 代码树：`/home/xien/桌面/RM2027/PX4-Autopilot/`（分支 `teaching/minimal-path`，`HEAD 3b5de24`）
- 被审对象：`U12 = STM32F103C8T6`（**从原理图直读确认**，见 §1.1）

---

## 出处引用约定（全文通用）

| 写法 | 含义 |
|---|---|
| `SCH(x=…,y=…)` | 原理图 PDF 里**该文字块文本框左上角**的坐标（PostScript pt，原点在页左上；可复现，见 §0.3） |
| `SCH-pin|U12.12/PA2` | 「位号 \| 引脚号/引脚名」，引脚号与引脚名都从图上读出 |
| `<路径>:<n>` | PX4 源码，相对 PX4 树根的行号 |
| `README:64` 等 | 项目文档 `projects/competition/rm2027-drone/…` 的行号 |

**三层标注**（本文每条结论都标）：

- **【实测】** = 有可复现的数据 —— 本文里指**从原理图 PDF 量出来的坐标/文本**（§0.3 给了复现命令），或项目里**已经上板跑过**的日志
- **【源码】** = PX4 / NuttX 源码 `file:line`
- **【推理】** = 我明说的推测（器件行为、改板代价、工程量）

---

## 0. 结论摘要（先看这三条）

### ★ 结论（三选一）：**不需要**

> **以这块 V1.0 板子的实际接线为准：这颗 STM32F103C8T6 作为「协处理器」是不需要的。**
> 它不是 px4io，PX4 里没有一行代码引用它，而且**它的 20 个外设引脚在原理图上全部悬空** ——
> 就算给它写固件，它除了跟 H7 说串口以外**什么都做不了**。

**判据（三条，全部可复核）：**

| # | 判据 | 出处 | 层次 |
|---|---|---|---|
| 判据 1 | PX4 分支对第二颗 MCU **零引用**：整个 `boards/rm2027/` 里只有 2 处**注释**提到它，没有任何驱动 / 启动脚本 / 板级声明；`PX4IO_SERIAL_DEVICE`、`CONFIG_DRIVERS_PX4IO`、`CONFIG_BOARD_IO` **一个都没定义** | §2.1、§2.2 | 【源码】 |
| 判据 2 | 电气上它与外界**只有 1 条 UART**（H7 USART2 ↔ F103 USART2）。**没有复位线、没有中断线、没有使能线** ⇒ H7 无法复位 / 断电 / 引导它 | §1.3、§1.5 | 【实测】 |
| 判据 3 | 它的 **20 个外设网络名在全图各只出现 1 次**（= 该网络只有 1 个节点）= 真的悬空。**不是"没用到"，是"没接出去"** | §1.2 | 【实测】 |

**补强判据（不是必要条件，但很有说服力）：** H7 自己还有 **19 个未分配 IO**
（`PE2 PE3 PE6 PC13 PC15 PA4 PA5 PA7 PB0 PE9 PE10 PE12 PB14 PB15 PD10 PD11 PD4 PB5 PB9`，脚 1/2/5/7/9/28/29/31/34/39/40/42/53/54/57/58/85/91/96），
以及 **10 个只标了名没接出去的定时器网络**（`TIM1_CH1/CH4`、`TIM3_CH4`、`TIM5_CH1..CH3`、`TIM15_CH1/CH1N`、`TIM16_CH1`、`TIM17_CH1N`）
⇒ **"IO 不够用"这个保留协处理器的理由在本板上不成立。**（§1.2 表格）

### 三选一 + 代价

| 选项 | 判据 | 收益 | 代价 |
|---|---|---|---|
| **需要** | ❌ 不成立。三条判据全反：无代码、无控制线、无外设出口 | —— | —— |
| **不需要**（= 当前状态，不写 F103 固件、不接它） | ✅ 成立 | **零改动**；`USART2`/`ttyS1` 变成可用串口（当前是唯一没被功能占用的串口，见 §2.4） | **什么都不损失**（它现在本来就没在做事）。唯一"损失"是 BOM 上那颗 F103 白花钱、白占面积 |
| **可选**（保留 + 只用串口） | ⚠️ 只在一种前提下成立：把它当**纯串口从机**（遥测/日志/标定缓存的第二副本） | `ttyS1` 上多一个能做点事的 MCU；未来改板时固件已就绪 | 要写 F103 固件 + H7 侧 PX4 驱动 + 板级配置；且**它没有任何执行器输出**，所以**做不了**独立失效保护/舵机兜底（那是 px4io 的能力，见 §2.2） |

> **一句话给用户**：这块板子上的 F103 **现在是个"只挂了一条串口、别的脚全悬空"的空壳**。
> 飞控**不需要**它；如果要它有用，**先改板**（把它的 SPI/I2C/PWM 引到排针或连到 H7），再谈固件。

---

## 0.3 方法（可复现，这是本项目踩过坑的地方）

**坑 1（已知）：不许用 `pdftotext -layout` 读原理图。** 本文全程用 **`-bbox` 拿坐标 → 按坐标裁图 → 看图**。复现：

```bash
cd /tmp && mkdir -p coproc && cd coproc
PDF="/mnt/h/AI/shared/projects/competition/rm2027-drone/references/硬件手册/FMU_飞控板_原理图_2026-09-24.pdf"
pdftotext -bbox "$PDF" fmu_bbox.xml            # 每个词一个 <word xMin yMin xMax yMax>
# 裁图（-x -y -W -H 的像素 = pt × dpi/72）：
pdftoppm -r 400 -png -f 1 -l 1 -x 1277 -y 666 -W 2277 -H 1277 "$PDF" f103_sym
```

**坑 2（本项目第一次踩，写下来给后面的人）：LCEDA 里"线头的灰色小圆点"不能当"悬空"判据。**
我一开始想用灰点判断哪些脚吊着 —— **不成立**：`SWDIO1`（它确实接到 CN3）和 `SPI12_SCK`（它确实悬空）**图上长得一模一样**，线尾都有灰点。
⇒ **正确判据是"网络名在全图出现几次"**：EDA 的 net label **按名字连接**，同一个名字出现 N 次 = 这个网络有 N 个节点。
这个方法能自证：`USART12_TX` 出现 2 次，而它跨接的 `USART2_TX` 也出现 2 次 —— 与图上画的那条跨接完全对应（§1.3）。

**坑 3（对称，也记下）：本文引用的 pin↔label 配对规则是实测出来的，不是猜的。**
对 F103 的左侧引脚：`label 的 yMin = 该脚"引脚号"的 yMin − 0.66`（左列 24 脚逐条验证，误差 < 0.1 pt）。
H7 是同一规则（`label yMin = 引脚号 yMin − 0.66`）。**用这条规则才不会把 A 脚的信号对到 B 脚上。**

<!-- 出处：左列 24 脚逐条实测，例：pin5 号 yMin=176.98 / OSC1_IN yMin=176.32；pin12 号 227.38 / USART12_TX 226.72；pin19 号 277.78 / TIM31_CH4 277.12（差均为 −0.66） -->

---

# 第 1 部分 · A：它到底接了什么（原理图逐条）

## 1.0 结论一句话

**F103（`U12`）的全部连接 = {自己的 8MHz 晶振、自己的复位按钮、自己的 3.3V_F1 供电、BOOT0 下拉、1 条连 H7 的 USART2、1 个自己的 SWD 座} + {20 个悬空网络}。**
**它对外的唯一信号通道是 USART2；它没有任何独立外部接口（没有排针去接传感器/舵机/外设）。**

## 1.1 全 48 脚连接表（逐脚，已看图核对）

器件确认：`SCH(x=272.88,y=327.52)='STM32F103C8T6'`，位号 `SCH(x=272.88,y=140.32)='U12'`，引脚 1~48 编号与名（`VBAT/PC13-TAMPER-RTC/PC14-OSC32_IN/…/PB12`）**与 LQFP48 F103C8 的引脚表逐条一致**。
标注「✕」= 图上有绿色 no-connect 叉（**已按 1400 dpi 裁图肉眼确认**，例：pin1 的 ✕ 见 §1.6 的图证描述）。

| pin | MCU 名 | 图上网络名 | 去 哪 儿 | 层次 |
|:---:|---|---|---|---|
| 1 | VBAT | **（✕ 无连接）** | —— | 【实测】 |
| 2 | PC13-TAMPER-RTC | （✕ 无连接） | —— | 【实测】 |
| 3 | PC14-OSC32_IN | （✕ 无连接） | —— | 【实测】 |
| 4 | PC15-OSC32_OUT | （✕ 无连接） | —— | 【实测】 |
| 5 | PD0-OSC_IN | `OSC1_IN` | X2 = **8MHz 晶振** + C11 12pF | 【实测】 |
| 6 | PD1-OSC_OUT | `OSC1_OUT` | X2 + C12 12pF | 【实测】 |
| 7 | NRST | `NRST1` | R20 10K 上拉到 3.3V_F1 + **SW1 复位按钮** + 100nF 到 GND | 【实测】 |
| 8 | VSSA | GND | —— | 【实测】 |
| 9 | VDDA | 3.3V_F1 | + 去耦电容 | 【实测】 |
| 10 | PA0-WKUP | （✕ 无连接） | —— | 【实测】 |
| 11 | PA1 | （✕ 无连接） | —— | 【实测】 |
| 12 | PA2 | `USART12_TX` | **→ H7 PD5(86)**（经菱形串联元件，§1.3） | 【实测】 |
| 13 | PA3 | `USART12_RX` | **← H7 PA3(25)**（经菱形串联元件，§1.3） | 【实测】 |
| 14 | PA4 | （✕ 无连接） | —— | 【实测】 |
| 15 | PA5 | `SPI11_SCK` | **悬空**（全图只出现 1 次） | 【实测】 |
| 16 | PA6 | `TIM31_CH1` | **悬空** | 【实测】 |
| 17 | PA7 | `TIM31_CH2` | **悬空** | 【实测】 |
| 18 | PB0 | `TIM31_CH3` | **悬空** | 【实测】 |
| 19 | PB1 | `TIM31_CH4` | **悬空** | 【实测】 |
| 20 | PB2 | （✕ 无连接） | —— | 【实测】 |
| 21 | PB10 | `IIC12_SCL` | **悬空** + R4 4.7K 上拉 3.3V_F1 | 【实测】 |
| 22 | PB11 | `IIC12_SDA` | **悬空** + R5 4.7K 上拉 3.3V_F1 | 【实测】 |
| 23 | VSS_1 | GND | —— | 【实测】 |
| 24 | VDD_1 | 3.3V_F1 | —— | 【实测】 |
| 25 | PB12 | （✕ 无连接） | —— | 【实测】 |
| 26 | PB13 | `SPI12_SCK` | **悬空** | 【实测】 |
| 27 | PB14 | `SPI12_MISO` | **悬空** | 【实测】 |
| 28 | PB15 | `SPI12_MOSI` | **悬空** | 【实测】 |
| 29 | PA8 | `TIM11_CH1` | **悬空** | 【实测】 |
| 30 | PA9 | `TIM11_CH2` | **悬空** | 【实测】 |
| 31 | PA10 | `TIM11_CH3` | **悬空** | 【实测】 |
| 32 | PA11 | `TIM11_CH4` | **悬空** | 【实测】 |
| 33 | PA12 | （✕ 无连接） | —— | 【实测】 |
| 34 | PA13 | `SWDIO1` | **→ CN3**（F103 自己的 SWD 座，§1.4） | 【实测】 |
| 35 | VSS_2 | GND | —— | 【实测】 |
| 36 | VDD_2 | 3.3V_F1 | —— | 【实测】 |
| 37 | PA14 | `SWCLK1` | **→ CN3** | 【实测】 |
| 38 | PA15 | （✕ 无连接） | —— | 【实测】 |
| 39 | PB3 | （✕ 无连接） | —— | 【实测】 |
| 40 | PB4 | `SPI11_MISO` | **悬空** | 【实测】 |
| 41 | PB5 | `SPI11_MOSI` | **悬空** | 【实测】 |
| 42 | PB6 | `USART11_TX` | **悬空** | 【实测】 |
| 43 | PB7 | `USART11_RX` | **悬空** | 【实测】 |
| 44 | BOOT0 | R21 100K 下拉到 GND | **固定从 Flash 启动**（不能进 ROM bootloader） | 【实测】 |
| 45 | PB8 | `IIC11_SCL` | **悬空** + R6 4.7K 上拉 3.3V_F1 | 【实测】 |
| 46 | PB9 | `IIC11_SDA` | **悬空** + R7 4.7K 上拉 3.3V_F1 | 【实测】 |
| 47 | VSS_3 | GND | —— | 【实测】 |
| 48 | VDD_3 | 3.3V_F1 | —— | 【实测】 |

**网络名命名规律（就是从这张图反推出来的，用于确认配对没错）：**
`<外设><芯片号><实例号>`，芯片 1 = F103（`USART11`=F103 的 USART1、`USART12`=F103 的 USART2、`TIM11`=F103 的 TIM1、`TIM31`=F103 的 TIM3、`IIC11`=I2C1、`IIC12`=I2C2、`SPI11`=SPI1、`SPI12`=SPI2、`OSC1_*`、`NRST1`、`SWDIO1/SWCLK1`）；H7 侧不带这个后缀，唯一例外是 `NRST7`（`SCH(x=633.37,y=367.12)` → H7 脚 14）。**每一条都与 F103 的真实复用功能吻合**（PA5=SPI1_SCK、PB13=SPI2_SCK、PB8/PB9=I2C1、PB10/PB11=I2C2、PA6/PA7/PB0/PB1=TIM3_CH1..4、PA8..PA11=TIM1_CH1..4、PB6/PB7=USART1、PA2/PA3=USART2）⇒ **配对规则自证成立**。

## 1.2 ★ 关键发现：20 个"网络名全图只出现 1 次"的悬空网络（覆盖 20 个引脚）

**方法**：把 `fmu_bbox.xml` 里所有词按文本聚合计数（同一 net label 出现几次 = 该网络几个节点）。

**【实测】单次出现的信号网络（= 只有 1 个节点 = 悬空）：**

```text
SPI11_SCK  @SCH(244.08,248.32)   SPI11_MISO @SCH(395.28,205.12)   SPI11_MOSI @SCH(395.28,197.92)
SPI12_SCK  @SCH(395.28,305.92)   SPI12_MISO @SCH(395.28,298.72)   SPI12_MOSI @SCH(395.28,291.52)
IIC11_SCL  @SCH(395.28,169.12)   IIC11_SDA  @SCH(395.28,161.92)
IIC12_SCL  @SCH(244.08,291.52)   IIC12_SDA  @SCH(244.08,298.72)
USART11_TX @SCH(395.28,190.72)   USART11_RX @SCH(395.28,183.52)
TIM11_CH1..CH4 @SCH(395.28, 284.32/277.12/269.92/262.72)
TIM31_CH1..CH4 @SCH(244.08, 255.52/262.72/269.92/277.12)
```

**双侧对照（出现 2 次的，都找到了另一端）：**

| 网络名 | 出现 2 次的位置 | 另一端是什么 |
|---|---|---|
| `OSC1_IN` | `SCH(244.08,176.32)`(U12.5) + `SCH(66,238)` | X2 晶振 |
| `OSC1_OUT` | `SCH(244.08,183.52)`(U12.6) + `SCH(138,223)` | X2 晶振 |
| `NRST1` | `SCH(244.08,190.72)`(U12.7) + `SCH(118,374)` | R20/SW1 复位电路 |
| `SWDIO1` | `SCH(395.28,248.32)`(U12.34) + `SCH(1169.28,534.10)` | **CN3** |
| `SWCLK1` | `SCH(395.28,226.72)`(U12.37) + `SCH(1172.70,541.30)` | **CN3** |
| `USART12_TX` | `SCH(244.08,226.72)`(U12.12) + `SCH(492.48,323.92)` | 菱形串联元件 → `USART2_RX` |
| `USART12_RX` | `SCH(244.08,233.92)`(U12.13) + `SCH(492.48,313.12)` | 菱形串联元件 → `USART2_TX` |

**⇒ 结论：F103 的 SPI1、SPI2、I2C1、I2C2、USART1、TIM1(CH1~4)、TIM3(CH1~4) 这 20 条信号（= 20 个引脚：15~19、21、22、26~32、40~43、45、46），在整张图上（全项目只有这一页）没有任何第二个端点，也没有任何排针/插座。**
**它被画了标签，但没被接出去。** 这也是图里给 I2C1/I2C2 都装了上拉电阻（R4/R5/R6/R7，各 4.7K 到 3.3V_F1，见 `SCH(211.68,316.72)`、`SCH(236.88,320.32)`、`SCH(427.68,136.72)`、`SCH(434.88,136.72)`）却只有悬空网络的原因 —— **说明设计意图是"要挂 I2C 外设"，但那条线没画完。**

**【推理】** 这 20 条最可能是"规划了但没画完/画漏了"（典型后果：网络表里是 1-pin 网络，PCB 上只能是一条从引脚出来的短 stub）。
**不管是"漏画"还是"故意留空"，对本问题结论一样：这些引脚在硬件上无法使用。**

**H7 侧同样有一批"只标了名、没接出去"的定时器网络**（说明 H7 自己也没把定时器用满，`资源汇总` 里写的是 `All Timer For H Bridge`）：

```text
TIM15_CH1  @SCH(737,172.72)   TIM15_CH1N @SCH(737,165.52)
TIM16_CH1  @SCH(928,187.78)   TIM17_CH1N @SCH(975,202.18)
TIM1_CH1   @SCH(975,389.44)   TIM1_CH4   @SCH(737,460.00)
TIM3_CH4   @SCH(737,395.98)   TIM5_CH1..CH3 @SCH(737, 302.38/309.58/316.72)
```

H7 **完全没有网络名**的引脚（= 图上既无 nc 标记也无 net label）：
`PE2(1) PE3(2) PE6(5) PC13(7) PC15(9) PA4(28) PA5(29) PA7(31) PB0(34) PE9(39) PE10(40) PE12(42) PB14(53) PB15(54) PD10(57) PD11(58) PD4(85) PB5(91) PB9(96)` —— **19 条**。
（提取脚本：对每个脚用 `label yMin = 脚号 yMin − 0.66` 在标签列里找词，找不到即为无标签。
⚠️ 该脚本对 `PC14/PC15` 这类紧邻晶振电路的脚有 ±1 脚的边界歧义，**清单允许有 1 脚误差，需硬件组复核**；但"**有十几到二十个空闲 IO**"这个量级结论不受影响。）

## 1.3 与 H7 的连线：只有一条 USART2，中间串了个菱形元件

**【实测】唯一的跨 MCU 信号**（图上画成两组"跨接"）：

```text
①  SCH(492.48,313.12) USART12_RX  ——[菱形 2 端元件]—— USART2_TX @SCH(535.68,313.12)
②  SCH(492.48,323.92) USART12_TX  ——[菱形 2 端元件]—— USART2_RX @SCH(535.68,323.92)
```

**方向核对（两端的另一端）：**

| 网 络 | F103 端 | H7 端 | H7 引脚名/号 | 判定 |
|---|---|---|---|---|
| `USART12_TX` = `USART2_RX` | U12.12 **PA2** = F103 **USART2_TX** | `SCH(737,324.56)` → H7 左侧 **脚 25** | **PA3** = USART2_RX（AF7） | ✅ TX→RX |
| `USART12_RX` = `USART2_TX` | U12.13 **PA3** = F103 **USART2_RX** | `SCH(975,252.6)` → H7 右侧 **脚 86** | **PD5** = USART2_TX（AF7） | ✅ RX←TX |

⇒ **交叉正确**（H743 LQFP100 的脚 25/86 分别是 PA3/PD5，与 H743VI 数据手册引脚表一致）。
⇒ 与板级源码的记载**完全吻合**：【源码】`boards/rm2027/fmu-h743/nuttx-config/include/board.h:380-386`
`USART2 = 连 F103 伴生 MCU  TX=PD5  RX=PA3`；`GPIO_USART2_RX_1`/`GPIO_USART2_TX_2`。

**★ 那个菱形元件是什么（必须说清，因为它决定了"能不能拔掉"）：**

- **【实测】** 它是**暗红色（元件色）的菱形 2 端符号**，两端各引出一段导线；**图上只有 2 个**（就是上面①②两处），并且**专用于把两个不同网络名的网络接起来**。它**没有可见位号**（全图位号只有 `U1..U21 / R1..R21 / C1..C46 / D1..D5 / F1..F5 / L1 / X1,X2 / Q17 / SW1,SW5 / CN1,CN2,CN3,CN6 / H1,H2,H14 / MH1..` —— 没有 `JP/SJ/NT/J` 之类）。
- **【实测】** 全图**其它地方没有这个符号**（我渲染并检查了 GYRO/CAN/MAG/BARO/SWD/SPI/UART/电源区；例如 CAN 端接用的是矩形 `R3/R2 120R`）。
- **【推理】** 按嘉立创EDA 的常见画法，这最可能是**网络短接点（NET-TIE）/ 0Ω 短接**；也不排除是磁珠或焊桥跳线。**我没法从 PDF 里确定它到底是哪一种**（无位号、无 BOM），所以我不硬下结论。
- **但结论不受影响**：它是"串联在两条走线上的实体元件" ⇒ **H7 ↔ F103 的 USART2 是板上真实铜箔连接**，不是靠网络名虚连。
- **对"能不能去掉 F103"的影响**：如果是 net-tie/0Ω，链路是永久的；如果是焊桥跳线，可以不焊。**这一条要问硬件组**（本文列为待确认项 §3.4-Q1）。

## 1.4 F103 有没有独立的外部接口？—— 有，但**只有一个**：它自己的 SWD 座 `CN3`

**【实测】** 全图有两个 SWD 座，**不是共用**：

| 座 | 位号/封装 | 引脚→网络 | 给谁 |
|---|---|---|---|
| `SCH(1145.34,525.39)` | **CN3**，`MH1.25-4AWB` | 1=`SWDIO1` `SCH(1169.28,534.10)`；2=`SWCLK1` `SCH(1172.70,541.30)`；3=GND；4=经 **F5**(SMD1206-1A 保险) → **3.3V_F1** `SCH(1228,552.98)`；另 D5=SMF3.3CA(TVS)、C14=100nF | **F103** |
| `SCH(1288.09,522.89)` | **CN6**，`MH1.25-4AWB` | 1=`SWDIO` `SCH(1315.45,531.60)`；2=`SWCLK` `SCH(1315.45,538.80)`；3=GND；4=经 **F4** → **3.3V_H7** `SCH(1370.46,550.48)`；D4/C41 | **H743** |

⇒ **硬件上明确给 F103 留了独立烧写口**（这本身就是"硬件组预期 F103 上会跑我们自己的固件"的证据）。
⇒ 两个座的 1/2/3/4 = SWDIO/SWCLK/GND/3V3 **顺序一致**，不会接反。
⇒ **【推理】注意两人点**：(a) **CN3 没引出 NRST**（只有 4 针），烧写只能靠 SWD 连接、必要时手按 SW1；(b) BOOT0 固定下拉 ⇒ **进不了 ROM bootloader**（F103 的 ROM bootloader 走 USART1，而 USART1(`PB6/PB7`) 还是悬空的，所以**即便想用串口烧也只能靠 SWD**）。

**除此之外，F103 没有任何其它对外接口**：没有排针、没有 LED、没有插座、没有按键（SW1 只是复位，不是用户键）。`【实测】`

## 1.5 供电与复位：**谁都不控谁**（无主从关系）

**【实测】电源（两块 3.3V 是独立的）：**

```text
VBAT/V2S ─F3(30V/2A)─ U8 SY8303AAIC ──→ 5V                       @SCH(1215,808)
                                  ├─F1(SMD1206-100-30)─ U10 TLV75533PDBVR ──→ 3.3V_H7   （给 H7）
                                  └─F2(SMD1206-100-30)─ U9  TLV75533PDBVR ──→ 3.3V_F1   （给 F103）
```

- `U10` 的 EN（脚 3）**接在自己的 IN 上**（常使能）；`U9` 同样 ⇒ **两条 3.3V 同时上电，没有 H7 控制的电源门**。`【实测】`
- `3.3V_H7` 与 `3.3V_F1` 是**两个独立网络**（全图 `3.3V_H7` 出现 23 次、`3.3V_F1` 出现 11 次，**从不重合**）。`【实测】`
  ⇒ 与项目已有记述一致：`.planning/2026-09-30-供电与子代理策略/task_plan.md:53,65`

**⇒ 结论（对本问题的关键）：H7 对 F103 没有任何控制权：**

```text
复位：NRST1 只连 R20/SW1/100nF         → 没有来自 H7 的复位线      【实测】
启动：BOOT0 只连 R21 100K 到 GND       → 没有来自 H7 的 BOOT 控制  【实测】
电源：3.3V_F1 由 U9 独立产生，EN 常开  → 没有来自 H7 的使能/断电    【实测】
中断：全图无第三条跨 MCU 网络          → 没有 IRQ/握手线           【实测】
```

**【推理】** 这个架构意味着：**H7 只能"通过 USART2 跟它说话"**，既不能把它拉起来、也不能把它按下去、更不能在它跑飞时救它。（作为对比，Pixhawk 的 FMU↔IO 之间有 IO 的复位控制和 IO bootloader，见 §2.2。）

## 1.6 ★ 更正现有文档（两处，其中一处是硬错）

### （1）`硬件手册索引与关键参数.md:23,63` 的 "协处理 / IO / 通信" —— **描述不成立**

`references/硬件手册/硬件手册索引与关键参数.md:63` 写 F103 的"使用方式 = 协处理 / IO / 通信"。
**依据 §1.1/§1.2**：它没有 IO 出口（20 条悬空）、没有独立通信出口（只有 1 条对内 UART）、也没有在跑任何协同逻辑（PX4 侧零引用）。
⇒ **应改为："STM32F103C8T6 = 板上第二颗 MCU，仅经 USART2 连 H7（V1.0 未使用）；其 SPI1/SPI2/I2C1/I2C2/USART1/TIM1/TIM3 共 20 条网络（20 个引脚）悬空。"**
（同文档 `:97` 的 `H7 ↔ F103 → USART2` **是对的**，保留。）

### （2）`firmware/fmu-h743/引脚映射-F103.md` 的两处错

| 位置 | 现文档写法 | 实测 | 说明 |
|---|---|---|---|
| `引脚映射-F103.md:107` | `1 \| VBAT \| 3.3V_F1(VBAT) \| 电源` | ❌ **VBAT 是 NC（✕）** | 见下面图证 |
| `引脚映射-F103.md:95-96` | 38/39（PA15/PB3）"未连接 待核"（未标 ✕） | ✕ **有** | 图上有绿色 no-connect 叉 |

**VBAT 的图证（关键，因为它牵涉到一颗 MCU 能不能可靠工作）：**
裁图 `pdftoppm -r 1400 -x 4627 -y 2683 -W 1400 -H 777`（即 pt 238~310 × 138~178）可见：`U12` 符号左侧，
**引脚 1/2/3/4 每一条横线末端各有一个绿色 ✕**，第一条横线对应的引脚内名就是 `VBAT`。
⇒ **`VBAT`（脚 1）在图上被明确标为"不连接"。**

**【推理 · 风险，交硬件组确认】** ST 的 F103 数据手册 §2.3.9（`STM32F103C8_datasheet_extract.md:358`）
只写 `VBAT = 1.8~3.6V：VDD 不在时给 RTC / 32kHz 晶振 / 后备寄存器供电`，并让人参考 `Figure 14: Power supply scheme`（同文件 `:721` 的电源方案图里 VBAT 与 VDD 画在一起）；
**不用电池时的通行做法是把 VBAT 并到 VDD。** 悬空 VBAT **不会让 MCU 不跑**（内核/Flash 走 VDD），但**后备域悬空**，属于"偏离参考设计"的隐患。
**顺带：H743 的 VBAT（脚 6）也被同样标了 ✕**（裁图 `-x 5382 -y 1215`，即 pt 775~860 × 175~215）⇒ **是这块板的一贯画法，不是 F103 单独的问题**，一起交硬件组判定。
（这两条都**不改变**§0 的结论，只是"如果以后真要给 F103 写固件，先把这个确认掉"。）

---

# 第 2 部分 · B：PX4 这一侧用不用它

## 2.0 结论一句话

**PX4（我们的分支）对这颗 F103 零引用**：没有驱动、没有启动脚本、没有板级声明、没有参数。
**PX4 上游唯一的"H7 主控 + 协处理 MCU"机制是 `px4io`（Pixhawk 的独立 IO 板），它不是本板这个场景** —— 下面用源码把"为什么不是"说清。

## 2.1 我们的分支：板级目录里对第二颗 MCU 的所有引用（就这两条，且都是注释）

```bash
grep -rniE 'usart2|px4io|f103|coproc|uart.?2' boards/rm2027/
```

| 出处 | 内容 | 性质 |
|---|---|---|
| `boards/rm2027/fmu-h743/nuttx-config/include/board.h:380` | `*   USART2 = 连 F103 伴生 MCU        TX=PD5  RX=PA3` | **注释** |
| `boards/rm2027/fmu-h743/README.md:64,83` | `协处理  STM32F103C8T6 （伴生 MCU，经 USART2 连接；不是 PX4IO）` / `6. 无 I/O 协处理器 → 不存在 px4io 驱动；MAIN/AUX 之分在本板不适用` | **文档** |

**【源码】没有任何"能跑的东西"引用它**：

```text
boards/rm2027/fmu-h743/src/board_config.h      : 全 241 行 —— 无 PX4IO_SERIAL_DEVICE / PX4IO_SERIAL_BITRATE
                                                 （只有 RC_SERIAL_PORT "/dev/ttyS4"，:185）
boards/rm2027/fmu-h743/default.px4board        : 无 CONFIG_DRIVERS_PX4IO / 无 CONFIG_BOARD_IO
boards/rm2027/fmu-h743/init/rc.board_sensors   : 全脚本无 ttyS1 / 无 F103 相关命令
boards/rm2027/fmu-h743/init/rc.board_extras    : 同上
grep -rn 'ttyS1' boards/rm2027/                : (无命中)
```

**全 PX4 树搜 F103**：只有 `platforms/nuttx/src/px4/stm/stm32_common/version/board_mcu_version.c:72-76,112-128`
里的 **DEV_ID 常量**（`STM32F103_LD/MD/HD/XLD/CON`）—— 那是"识别主控芯片版本号"用的，**不是驱动**。`【源码】`

**⇒ 判据 1 成立：固件里根本没有一行代码会去打开 `USART2`/`/dev/ttyS1`。**

## 2.2 上游的 `px4io` 到底是不是这个场景？—— **不是，四点理由**

### px4io 是什么（源码事实）

| 事实 | 出处 【源码】 |
|---|---|
| IO 板是一块**独立的板级目标**，MCU = **STM32F100C8**（Cortex-M3） | `boards/px4/io-v2/nuttx-config/nsh/defconfig:20-22`；固件源码 `src/modules/px4iofirmware/` |
| IO 侧与 FMU 的连接是 **USART2 + 1.5 Mbps** | `boards/px4/io-v2/src/board_config.h:58-65`（`PX4FMU_SERIAL_BASE=STM32_USART2_BASE`、`PX4FMU_SERIAL_BITRATE 1500000`） |
| 协议 = **私有二进制"虚拟寄存器"协议**：16-bit 寄存器、每页 255 个、`PKT_CODE_READ/WRITE` 0x00/0x40、CRC | `src/modules/px4iofirmware/protocol.h:45-46, 218, 234-244`；`PX4IO_PROTOCOL_VERSION 5` 同文件 `:80` |
| FMU 侧要**板级声明**：`PX4IO_SERIAL_DEVICE` / `_BITRATE` / `_TX_GPIO` / `_RX_GPIO` / `_BASE` | 例 `boards/px4/fmu-v6x/src/board_config.h:61-65` |
| 还要在 `default.px4board` 里开 `CONFIG_DRIVERS_PX4IO=y` | 全树 34 个板子这么写（例 `boards/px4/fmu-v6x/default.px4board:41`） |
| 还要 `CONFIG_BOARD_IO="<io 板名>"` 才能把 IO 固件编进 ROMFS + 支持 FMU 给 IO 升级固件 | `src/drivers/px4io/CMakeLists.txt:53-75`；**全树只有 3 个板子有**（`boards/cubepilot/cubeorange/default.px4board:3` 等） |
| 开 `CONFIG_DRIVERS_PX4IO` 而没定义 `PX4IO_SERIAL_DEVICE` ⇒ **直接编译报错** | `src/drivers/px4io/px4io_uploader.cpp:81-82` `#error Must define PX4IO_SERIAL_DEVICE...` |

### 我们的板子：四项声明全无 ⇒ **px4io 编不进来，也不该编**

```text
❌ PX4IO_SERIAL_DEVICE              (board_config.h 无)
❌ PX4IO_SERIAL_BITRATE / _TX_GPIO  (board_config.h 无)
❌ CONFIG_DRIVERS_PX4IO=y           (default.px4board 无)
❌ CONFIG_BOARD_IO="…"              (default.px4board 无；且 F103 上不可能跑 io-v2 固件)
```

### 为什么"不是这个场景"（逐条）

1. **芯片都不是**：io-v2 固件是给 **STM32F100C8** 写的板级目标（`defconfig:22`），**不是 F103C8**。
   F100 与 F103 同属 Cortex-M3，但外设/引脚/时钟不同 ⇒ 要复刻必须**新写一个 IO 板级目标 + NuttX defconfig + timer_config + PX4IO 外设映射**。`【推理】`
2. **IO 的能力来自它的专属外设**：px4io 的全部价值是"FMU 挂了 IO 还能自己按 failsafe 混合输出 PWM/DShot、接管 RC 输入、管安全开关、读 ADC"（`src/modules/px4iofirmware/` 里的 `mixer.cpp / controls.cpp / safety_button.cpp / adc.cpp`）。
   **而本板 F103 的 TIM1(4CH)+TIM3(4CH) 全悬空 ⇒ 它一根舵机线都驱动不了。**（§1.2）`【实测】`
3. **架构形态不同**：Pixhawk 的 IO 是**第二块 PCB、独立排针（MAIN/AUX）、独立供电域**；本板 F103 与 H7 同板、无对外引线。
4. **连"第二个通用 MCU"这一类通用支持，上游也没有**：全树搜 `second mcu|secondary mcu|companion mcu|co-processor mcu` **零命中** `【源码】`。
   上游与"另一台计算机"打交道的正规路径是 **companion computer**（板外的 Linux 机，走 MAVLink / uXRCE-DDS，见 `docs/en/flight_modes/offboard.md:17`、`docs/en/middleware/uxrce_dds.md`）—— **那是板外的事，不是板载第二颗 MCU**。

> **一句话**：`px4io` 与"板上第二颗通用 MCU"**共享同一个外形**（第二颗 MCU + 一条 UART），
> 所以很容易混；但它是**固定功能的 IO 板协议**，需要 IO 专属外设 + 一整套板级声明。
> **本板两样都没有**（F103 的定时器悬空、四项声明全无）⇒ **不是这个场景。**

## 2.3 如果 F103 上没跑任何固件，PX4 会有什么后果？—— **编译能过、启动不卡、不报错**

| 问题 | 答案 | 依据 | 层次 |
|---|---|---|---|
| 编译能过吗？ | **能**。没有任何文件引用它；`CONFIG_STM32H7_USART2=y` 只管 H7 自己的 UART 驱动 | `nuttx-config/nsh/defconfig:202` 存在，但板级/驱动无人使用 | 【源码】 |
| 启动会卡吗？ | **不会**。`rc.board_sensors` 拉起的全是 I2C/SPI/UART 上的**传感器**（`ist8310`/`spa06`/`hxy42688p`/`h104_imu`/`board_adc`），没有一条涉及 F103 | `init/rc.board_sensors:55,85,105,110,119` | 【源码】 |
| 会报什么错？ | **不会报错**。没有任何代码去 open `/dev/ttyS1` ⇒ 没有超时/没有 "no instance started" | `grep -rn 'ttyS1' boards/rm2027/` 无命中 | 【源码】 |
| 那 `/dev/ttyS1` 存在吗？ | **存在**（`CONFIG_STM32H7_USART2=y` + `CONFIG_STM32H7_SERIAL_DISABLE_REORDERING=y` ⇒ 按 `g_uart_devs[]` 下标顺序注册，USART1→ttyS0、**USART2→ttyS1**、USART3→ttyS2…） | NuttX `stm32_serial.c:1481-1497`（`g_uart_devs[]` 表）、`:3930-3956`（注册循环）；`defconfig:185-186,197-204` | 【源码】 |
| 物理上有副作用吗？ | **理论上有一个小隐患（未上板验证）**：H7 的 `PA3`(USART2_RX) 与 F103 的 `PA2` 直连，F103 无固件时其 PA2 复位后是**浮空输入**，而本板 USART2 两条线**没有外部上拉**（上拉只加在 I2C 上，R4~R7）⇒ 该 RX 线悬空。**只要 PX4 不打开这个口就不会有影响** | 无上拉：§1.1 全表；不打开：§2.1 | 【推理】 |

**⇒ 判据 1 的推论：把 F103 从 BOM 上拿掉（或用空片），PX4 的行为不会有任何变化。**

## 2.4 顺带更正一处文档：`/dev/ttySx` 占用表

**【源码】`default.px4board:3` 的注释写 `CONFIG_BOARD_SERIAL_TEL1="/dev/ttyS2"   # USART3（本板唯一空闲串口）` —— 这句不准确。**

实测占用（按 NuttX 注册顺序，`SERIAL_DISABLE_REORDERING=y` ⇒ 下标 0..7 依次为 ttyS0..ttyS7）：

| /dev | 外设 | 用途 | 依据 |
|---|---|---|---|
| `ttyS0` | USART1 | **H104 外置陀螺** | `default.px4board:24`；`rc.board_sensors:112` |
| `ttyS1` | **USART2** | **↔ F103（硬连线，PX4 不打开）** | `board.h:380-386`；`defconfig:202` |
| `ttyS2` | USART3 | TEL1 | `default.px4board:3` |
| `ttyS3` | UART4 | ESC1 遥测 | `rc.board_extras:11-12` |
| `ttyS4` | UART5 | **DBUS 遥控** | `board_config.h:185` |
| `ttyS5` | USART6 | ESC2 遥测 | `rc.board_extras:11-12` |
| `ttyS6` | UART7 | ESC3 遥测 | 同上 |
| `ttyS7` | UART8 | ESC4 遥测 | 同上 |

⇒ **`ttyS1` 才是那个"物理上被 F103 占住的空闲口"**。`ttyS2` 是"被分配成 TEL1 的口"。
**建议把注释改成**：`# USART3 → ttyS2（TEL1）；ttyS1 = USART2 硬连 F103，不写 F103 固件时它是唯一可改作他用的串口`。

---

# 第 3 部分 · C：结论与成本

## 3.0 三选一（重复 §0，附完整判据表）

**结论：不需要。**（完整判据见 §0；若目标是"独立失效保护 / 舵机兜底"，答案是 **"可选，但必须先改板"**，见 §3.2）

## 3.1 保留 / 去掉 / 改造：收益与代价

### A. 保留（现状：焊着、不给它写固件）

| 项 | 内容 |
|---|---|
| 收益 | 基本为零。唯一"收益"是：将来改板后固件可以马上开工；以及 CN3 提供了一个可用的 SWD 调试口（但它挂在**独立的 3.3V_F1** 上，见 §1.4） |
| 代价 | BOM 一颗 F103C8T6 + 一个 8MHz 晶振 + 2 个 12pF + 4 个 4.7K + 1 个 100nF + 1 个复位键 + 1 个 4p 座 + **一整套独立 3.3V LDO 支路（F2+U9+D3+C6+C8）**；PCB 面积；以及**一颗我们在上面没法观测、没法复位、无法控制的 MCU**（§1.5） |
| 隐藏成本 | **串口被占**：`ttyS1`(USART2) 被硬连线占住（§2.4） |
| 隐藏风险 | VBAT 悬空（§1.6-2）；F103 若将来自己跑飞，H7 **无法复位它**（§1.5） |

### B. 去掉（不焊 F103，或焊了当不存在）

| 项 | 内容 |
|---|---|
| 会损失什么 | **PX4 侧什么都不损失**（§2.1/§2.3）。硬件上损失 20 条本来就悬空的网络（§1.2）—— 它们现在也没接任何东西 |
| 反而得到 | **`ttyS1`(USART2) 可改作它用**（e.g. 第二个 MAVLink/遥测口、OSD、外部日志、XRCE-DDS）；
若 F103 不上件，`USART2` 的两根线仍然走到**空焊盘**上，可以直接在焊盘上引线当测试/遥测口（【推理】需硬件组确认丝印/测试点） |
| 代价 | 与"保留"对称；**但如果 PCB 已投产，删 BOM 不省板子钱**，只省单板物料与故障面 |
| 附带好处 | 消掉两个隐患：VBAT 悬空的空片（§1.6-2）、以及在 `ttyS1` 上误配 `MAV_x_CONFIG` 时的困惑 |

### C. 改造（保留 + 真正让它干活）

**⇒ 关键结论：在当前 V1.0 接线约束下，"改造"几乎没有落地项。**
因为 F103 **没有任何执行器/传感器出口**（§1.2），它能做的只有"通过 USART2 跟 H7 说话"。而凡是"通过 USART2 跟 H7 说话"能做的事，**H7 自己都能做**（H7 还有 20+ 空闲引脚和 8 个没接出去的定时器网络，§1.2）。

**【推理】逐条筛"值得让它干什么"：**

| 想法 | 在 V1.0 上可行吗 | 原因 |
|---|---|---|
| px4io 那套独立失效保护（FMU 挂了 IO 维持舵面） | ❌ **不可行** | ①F103 的 TIM1/TIM3 全悬空，**没有舵机/DShot 输出** ⇒ 拿什么维持？②H7 挂了不关 F103 的事，但 F103 也没线去驱动执行器 |
| 独立看门狗（H7 跑飞时复位 H7） | ❌/⚠️ | 需要一根 H7 复位线，**图上没有**（NRST7 只有 R14/SW5/C7）。要用只能靠 USART2 心跳 + 自己再加一根线 ⇒ 改板 |
| DShot 并发 / 多路 PWM 扩展 | ❌ | 需要把 F103 的 PWM 引到 ESC 连接器 ⇒ 改板 |
| ESC 遥测聚合（4 路串口汇 1 路给 H7） | ❌ 现状 | 4 路 ESC 遥测现在**直接接 H7**（UART4/USART6/UART7/UART8，§2.4）；要改到 F103 也是改板 |
| 遥测/日志二级缓存、标定数据备份 | ⚠️ **可行（唯一可行项）** | 只需要 USART2。但 H7 有 SD 吗？——**本板无 microSD**（`README.md:79`），所以"多一份存储"确实有点价值 |
| 传感器 I2C/SPI 扩展（挂更多 IMU/磁力计） | ❌ 现状 | F103 的 I2C1/I2C2/SPI1/SPI2 **全悬空** ⇒ 挂不上任何器件 |
| 作为"第二套独立飞控"（应急降落） | ❌ | 同上：它没有执行器输出，也没有自己的 IMU/气压计总线 |

**⇒ 因此"改造"的真实前置条件是【改板】：至少要有**
**① 一组执行器输出（TIM1/TIM3 引到 ESC/舵机连接器）；② 与 H7 的控制线（H7→F103 复位；H7←F103 失效告警）；③ 若做传感器冗余，把一组 I2C/SPI 从 H7 引到 F103。**
**在这三条落地之前，"协处理器"这个概念在本板上无法成立。**

## 3.2 如果保留，最值得让它干什么（含所需改板项）

**【推理】排序（按"收益/工作量"）：**

| 优先 | 让它干 | 需要在硬件上补什么 | 软件工作量 |
|---|---|---|---|
| ① | **独立失效保护 / 安全舵面兜底**（≈ px4io 的核心价值） | **必须改板**：至少 4 路 PWM/DShot 从 F103 引出；1 根 H7→F103 复位线（或"FMU 心跳丢失"判定 + F103 自己接管） | 最大：F103 固件（含 failsafe 混合）+ H7 侧 PX4 驱动 + 板级配置。**若照抄 px4io，还要写一个新的 IO 板级目标**（`boards/<x>/<y>/`，因为现有 io-v2 只针对 STM32F100C8） |
| ② | **传感器冗余 / 独立 IMU 总线** | 改板：一组 I2C 或 SPI 从 H7 侧引到 F103 | 中：F103 采集 + 协议 + H7 侧 uORB 驱动 |
| ③ | **遥测 / 日志二级缓存**（本板无 SD 的唯一补救） | **不用改板** | 中：F103 固件 + 协议 + H7 侧驱动。⚠️ F103C8 只有 **64KB Flash / 20KB RAM**（`硬件手册索引与关键参数.md:63`），"缓存"能存的东西很少 ⇒ 收益可疑 |
| ④ | 纯"从机应答机"（给 H7 一个可控的 UART 对端，做协议实验/自检回路） | 不用改板 | 小。**但这就是 §3.0 的"可选"项，谈不上"协处理器"** |

## 3.3 成本对比（保留值不值？）【推理】

| 成本项 | 量级 | 说明 |
|---|---|---|
| F103 固件（裸机/HAL/寄存器 + 协议 + 失效保护逻辑） | **人周级 ~ 人月级** | 若只做"串口从机应答"：几天；若做 failsafe 混合 + 看门狗 + 与 H7 的握手/超时状态机：数周 |
| H7 侧 PX4 驱动（uORB 发布 + 参数 + 健康度 + 启动脚本 + 板级声明） | **周级** | 参考本项目的 `hxy42688p` / `h104_imu` 两个自研驱动的实际工作量 |
| 板级改动（若走 px4io 路线：新 IO 板级目标 + NuttX defconfig + timer_config + ROMFS 打包 + 升级链路） | **数周**，且**必须改板** | `boards/px4/io-v2/` + `src/modules/px4iofirmware/` 的规模摆在那里 |
| 硬件改板（PCB 改版） | **一次投板周期** | 这是真正的成本大头 |
| 调试/验证（CN3 烧写、SWD、协议一致性） | 数天 | 注意 CN3 **无 NRST**、BOOT0 固定（§1.4） |

**⇒ 回报对比：**

- 若**只为"提高可靠性"** ⇒ **不值**。同样的可靠性收益，改 H7 侧（EKF/失效检测/参数化 failsafe）成本低一个数量级，而且不依赖一颗我们无法复位的 MCU（§1.5）。
- 若**目标是"给 H7 减负"** ⇒ **不值**。H7 目前的主要负载是 EKF + 4 路 ESC 遥测 + H104@100Hz；本板 H7 还有 20+ 空闲引脚（§1.2）。
- 若**目标是"学习/教学（两块 MCU 协同 + 自定义协议）"** ⇒ **值**（这是唯一站得住的理由），但请明说这是教学需求，不要包装成"飞控需要"。

## 3.4 建议（给 Lead 的落地动作）

| # | 动作 | 为什么 |
|---|---|---|
| D1 | **本板 config 里明确写清"F103 不使用"**（`README.md:64` 已经在写"不是 PX4IO"，可以再加一句"V1.0 未使用；USART2/ttyS1 保留未开"），并把 `default.px4board:3` 的"唯一空闲串口"注释按 §2.4 更正 | 防止后来人以为 F103 在干活，或误把 `ttyS1` 当普通串口 |
| D2 | **不要在 `ttyS1` 上配 MAVLink/遥测**（除非确定不焊 F103） | 那根线上挂着一颗 MCU。若不焊 F103，则可用（§3.1-B） |
| D3 | **向硬件组提 3 个待确认项（本文的未决点）** | 见下 |
| D4 | 若用户最终要"协处理器"：**先立项改板**（§3.1-C 的三条），**固件随后** | 否则写了固件也无处可用 |

**待确认项（我无法从静态资料判定）：**

- **Q1（本文最关键的未知）**：`USART12_*` 与 `USART2_*` 之间那个**菱形 2 端元件是哪一类**（net-tie / 0Ω / 焊桥 / 磁珠）？
  **影响**：决定"不焊它能不能断掉 H7↔F103 链路"。**这是唯一的"能不能物理去掉 F103 而不断线"的问题。**
- **Q2**：F103 的 20 条悬空网络是**故意留白**还是**画漏**？若是画漏，V2 是否会引到排针？
- **Q3**：`VBAT`（F103 脚 1 与 H743 脚 6）留 NC 是**有意**还是**疏漏**？（§1.6-2）

---

# 第 4 部分 · 外部对照（网络检索）：别人怎么解决"第二颗 MCU"

> **检索条件说明（诚实标注）**：本次会话的 `web_search` 后端**没有 API key，不可用**；
> `duckduckgo / github.com / raw.githubusercontent.com` 在本机**网络不可达**（`fetch failed`）。
> 实际能读到的只有 **ardupilot.org**（全文可读）、**docs.px4.io**（只读到标题与导航，正文被截断）、**cn.bing.com**（可用但结果被污染，几乎没给出有效技术页）。
> ⇒ **本节所有结论都标了可点开的来源；凡是我只看到标题、没读到正文的，我会明说。**

## 4.1 结论：业界只有两种"第二颗 MCU"，**没有第三种**

| 形态 | 谁在做 | 它靠什么活 | 与本板 F103 的关系 |
|---|---|---|---|
| ① **固定功能 IO / 失效保护 MCU** | Pixhawk 系列（ArduPilot 称其为 **"32-bit failsafe co-processor"**，见 [Pixhawk Overview](https://ardupilot.org/copter/docs/common-pixhawk-overview.html#specifications)） | **它自己有一整排舵机/DShot 输出引脚**、RC 输入、安全开关、ADC；FMU 挂了它还能按 failsafe 自己输出 | ❌ **不是**。本板 F103 的 TIM1/TIM3（= 8 路 PWM）**全悬空**（§1.2），一根舵机线都驱动不了 |
| ② **板外伴生计算机（Companion Computer）** | 所有做视觉/算力的 | 板外 Linux 机，走 MAVLink / uXRCE-DDS；ArduPilot 定义为 *"an on-board Linux-based computer that communicates with the autopilot over a fast link using MAVLink messages"*（[Companion Computers](https://ardupilot.org/copter/docs/common-companion-computers.html)） | ❌ **不是**。F103 是 MCU、不是 Linux 机，且没有对外接口 |
| ③ **"只有一条 UART、别的脚全悬空"的第二颗 MCU** | **没有人在做** | —— | ⚠️ **本板这一颗就是③** |

**⇒ 这就是"别人有没有用"的答案：F103 这颗片子业界用得很凶，但用法和本板不一样。**

## 4.2 ★ 关键发现：STM32F103 **正是**业界"第二颗 MCU"的经典选择 —— 但它是 **DroneCAN 节点**

ArduPilot 的 [DroneCAN Adapter Node](https://ardupilot.org/copter/docs/common-uavcan-adapter-node.html) 页明确写着：

- **"F103 Based"** 固件变体就是官方预编译的一档：`f103-GPS`（串口 GPS + I2C 罗盘 + I2C RGB LED）、`f103-ADSB`、`f103-Rangefinder`；
  原文还写了演进原因：*"The first generation was based on the f103 processor, while the current generation uses an f303 for more memory … The L431 processor is now supported"* ⇒ **F103 是"第一代"，后来因为内存不够换 F303/L431。**
- 这个节点的职责是把 **UART / SPI / I2C / GPIO 外设翻译成 CAN 上的 DroneCAN 设备**，支持：GPS、磁力计、气压计、空速、测距、ADS-B、LED、**安全开关与蜂鸣器**、**PWM 与 DShot 输出**、串口透传。
- 节点固件（`Tools/AP_Periph`）自带：动态/静态 CAN 节点分配、**固件上传、自动生成 bootloader、参数存 flash、watchdog + CRC + 板级检查**。

**⇒ 业界的"第二颗 MCU"是这么用的：**

```text
   不是：  H7 ──UART──> 第二颗 MCU（没有别的脚）        ← 本板 F103 现在的样子
   而是：  H7 ──CAN───> 第二颗 MCU（自带 GPS/I2C/PWM/DShot/安全开关）──> 外设
```

**这条对我们特别重要，因为本板的 CAN2 是空着的、而且引到了连接器上：**

- **【实测】** `CN2`（`WAFER-GH1.25-2PWB`，`SCH(x=1630.08,y=863.92)`）：pin1 = `CAN2_L` `SCH(1576.08,878.32)`、pin2 = `CAN2_H` `SCH(1576.08,885.52)`、pin3 = GND；
  对应 CAN2 收发器 `U4 = SIT3051TK`（`CAN2_H/L @SCH(1526,196/252)`）← H7 脚 52/51（`CAN2_TX/CAN2_RX`）。
- 另一路 `CN1`（`SCH(1540.08,863.92)`）是 `CAN1_H/L`，已被 H104 占用（`资源汇总`：`CAN1 For HI04(GYRO)`）。
- **【源码】** PX4 侧本来就有 DroneCAN 支持：`src/drivers/uavcan/`、`src/drivers/uavcannode/`（本仓库实测存在）；
  但**本板 `default.px4board` 里没有任何 UAVCAN/CAN 配置**（实测 `grep` 无命中）⇒ 要用得自己打开。

**⇒ 可操作建议（比"给 F103 写固件"便宜得多）**：
**想要"多一个 MCU 帮我干活"，正确姿势是买现成的 DroneCAN 节点（如 MatekL431-* / ARK CANnode / mRo）插到本板的 CN2 上** ——
固件社区维护、PX4 已经会说这个协议、不需要改板、不需要自己写协议栈。
（⚠️【推理】本板走的是 **CAN1/CAN2 两路独立的 1 Mbps CAN**，不是同一路；DroneCAN 要求同一总线上的节点在同一条 CAN 上 —— 用 CN2 就用 H7 的 CAN2，没问题。）

## 4.3 PX4 上游：IO MCU 已经是"少数派"

**【源码】** 在我们这棵 PX4 树里实测统计：

| 统计 | 数量 | 说明 |
|---|---|---|
| 有 `default.px4board` 的板级目标 | **121** | 全部分支 |
| 其中定义 `CONFIG_BOARD_IO="…"`（= 真的挂一块 IO 板） | **3** | **全部是 CubePilot**：`cubeorange / cubeyellow / cubeorangeplus`，值都是 `cubepilot_io-v2_default` |
| 其中定义 `CONFIG_DRIVERS_PX4IO=y`（= FMU 侧带 px4io 驱动） | **33** | 含老款 Pixhawk 兼容板 |

**⇒ 121 个目标里只有 3 个真的带 IO 板。**（这也解释了本项目 `README.md:83` 那句"无 I/O 协处理器 → 不存在 px4io 驱动"为什么是对的 —— 绝大多数新板子都没有。）
**⇒ 新板子的 IO 扩展路线已经换成 CAN 节点（§4.2），而不是"板上再放一颗 MCU"。**

## 4.4 与 `review-05` 主结论的关系

- 主结论（§0"不需要"）**不变**：以本板现状，F103 无代码、无控制线、无外设出口。
- 但**"想要协处理能力"这件事有正解**：不是给 F103 写固件，而是 **CN2 上挂 DroneCAN 节点**（或改板把 F103 的 PWM/I2C 引出来做成自研节点）。
- 【推理】如果一定要**自研**那个节点，那么 **F103（甚至就用板上这颗）反而可以当节点 MCU 的候选** —— 但那要求**改板**：把它接到 CAN 收发器（本板已有 SIT3051TK ×2，可再加/复用），并把它的 PWM/I2C 引出去。这与 §3.2 的"改造前置条件是改板"是同一句话，只是现在给了一条业界已经验证过的具体路线。

---

# 第 5 部分 · 外部对照：地面站 ↔ 无人机 的无线链路怎么解决

> 数据来源：ArduPilot 官方文档（全文可读）。PX4 的对应页面是 <https://docs.px4.io/main/en/telemetry/>，但**本机只能读到它的标题与导航、正文被截断**，所以我**不引用它的正文**，只当指针给。

## 5.1 一张表：四类链路（按距离/带宽分）

| 类别 | 典型方案 | 关键参数（原文） | 适合 |
|---|---|---|---|
| **短距数传**（最常用） | **SiK 无线电** 433 / 915 MHz | 开源自研固件（[SiK Radio](https://ardupilot.org/copter/docs/common-sik-telemetry-radio.html)）：**透明串口**、**MAVLink 组帧 + 状态上报**、**FHSS 跳频**、自适应 TDM、**空中速率最高 250 kbps**、发射 ≤20 dBm(100 mW)、灵敏度 −121 dBm、**默认配置典型约 500 m**、地面换增益天线可达数 km（原文有 3 km / 4.5 km 的实测曲线）；对拷即用，**GCS 端当串口 57600 连** | 比赛现场、几百米内、要稳 |
| **WiFi 数传** | **ESP8266 / ESP32**（MAVESP8266 / DroneBridge） | [ESP8266 wifi telemetry](https://ardupilot.org/copter/docs/common-esp8266-telemetry.html)：飞控侧 `SERIALx_PROTOCOL=2`、`SERIALx_BAUD=921`（921600），模块起 AP（默认 SSID `ArduPilot` 密码 `ardupilot`），**地面站用 UDP 连** `192.168.4.1`；带宽比数传大得多 | 场地内、需要带宽（日志/参数/多机）、成本极低 |
| **4G / LTE** | Airlink、XBStation、UAVCast | [ArduPilot Long Range 列表](https://ardupilot.org/copter/docs/common-telemetry-landingpage.html#long-range)：全球覆盖，但**延迟/抖动大、依赖公网**；适合远程监控，不适合手动操控 | 跨城市、超视距 |
| **RC + 遥测合一** | **CRSF / ELRS**（900M/2.4G） | [TBS Crossfire / CRSF](https://ardupilot.org/copter/docs/common-crsf-telemetry.html)：RC 与遥测**同一对收发**；ELRS 接收机还能直接跑 **Mavlink 模式**提供**双向 MAVLink 遥测 + RC**；发射机可开 WiFi 把遥测**转成 MAVLink 给地面站** | 想省一套链路、手动飞为主 |
| **卫 星** | RockBLOCK / SPL | [Telemetry landing page](https://ardupilot.org/copter/docs/common-telemetry-landingpage.html#long-range)：极远、极低速、高延迟 | 应急/远洋 |

## 5.2 关键做法（比选型更重要）

1. **链路是"一条串口 + 一个协议"，不神秘。**
   ArduPilot 原文：*"most pure telemetry radios connect to the autopilot via a serial UART using MAVLink 1 or 2 protocol."*（[Telemetry landing page](https://ardupilot.org/copter/docs/common-telemetry-landingpage.html)）
   ⇒ 飞控侧要做的就是把某一路 UART 配成 MAVLink 端口。**PX4 这边同理**：`MAV_x_CONFIG` 指到 `/dev/ttySx`。
2. **★ 冗余链路（高价值做法）。**
   [Redundant Telemetry Links](https://ardupilot.org/copter/docs/common-redundant-telemetry.html) 原文：单一链路同时承担 RC + 遥测时，链路挂了 GCS failsafe 能把飞机飞回来，但**可能无法安全降落**；建议 **"primary LTE + secondary 900M/433"**，甚至再加一条 WiFi 用于返航后近距离接管。
   MAVProxy 可以**按链路质量自动切换**（`link list` / `set link x` 手动强制）；Mission Planner 也能挂多条链路。
3. **不要把"图传"和"数传"混为一谈。** 数传要的是**低延迟小包**；图传要的是**带宽**。Herelink 这类一体机是一条链同时给视频+遥测（[列表](https://ardupilot.org/copter/docs/common-telemetry-landingpage.html#long-range)），但价格和合规代价都高。
4. **频段合规**：433/915 和 2.4/5.8 的选择要看地区法规（ArduPilot 专门有一页 [Telemetry Radio Regional Regulations](https://ardupilot.org/copter/docs/common-telemetry-radio-regional-regulations.html)）。**RoboMaster 是赛事现场，还多一层"组委会频段/遥控器规定"，必须按当届规则来。**

## 5.3 落到本板：我们有哪几路可以做无线

**【实测】按 §2.4 的 `/dev/ttySx` 占用表**，本板可以拿来做无线数传的串口只有：

| 串口 | 现状 | 能不能做无线 |
|---|---|---|
| `/dev/ttyS2`（USART3） | 已配为 `TEL1`（`default.px4board:3`） | ✅ **首选**：直接接 SiK 数传 / ESP8266 / LTE 模块 |
| `/dev/ttyS1`（USART2） | 硬连 F103（§1.2） | ⚠️ 只有在**不用 F103**（不焊或不做）时才可用 —— 这正是 §3.1-B "去掉 F103 释放 ttyS1" 的实际用途 |
| `ttyS0` / `ttyS3` / `ttyS4` / `ttyS5` / `ttyS6` / `ttyS7` | H104 / 4 路 ESC 遥测 / DBUS | ❌ 已被占用（DBUS 是遥控，不是地面站） |

**⇒ 无线方案落地清单（建议顺序）：**

```text
① 主链路：ttyS2 (TEL1) + SiK 433/915 数传（最省事、最稳、几百米）
     · 飞控侧：MAV_x_CONFIG → /dev/ttyS2（或 CONFIG_BOARD_SERIAL_TEL1 已指向它）
     · 地面：USB 数传 → QGC 选串口 57600
② 备链路（推荐加）：CN2 上挂 DroneCAN 节点，或再加一路 4G/WiFi —— 实现"冗余链路"（§5.2-2）
③ 若需要带宽（日志/参数/多机）：ttyS2 换 ESP8266/ESP32，地面站走 UDP
④ 若 F103 不用：ttyS1 可以再挂第二套（例如 WiFi 备链路）
⑤ 图传单独走（5.8G 模拟/数字），不要和数传抢一条链路
```

**⚠️ 提醒（与本报告主体呼应）**：本板**没有 USB**（`README.md:78-79`：`本板无 USB`、`本板无 microSD`）⇒
**参数/日志不能靠插 U 盘或网线拿**，所以"至少一条稳定的无线数传"对这个板子**不是可选，而是必需** —— 这也是把 `ttyS2` 留给 TEL1 的原因。
若把 F103 去掉，`ttyS1` 就是**唯一的备份无线口**，价值很高。

---

## 附：本次审计未覆盖 / 明确不做的部分

- **未上板**：不接 SWD、不烧写、不跑 openocd（任务约束）。§2.3 里"浮空 RX 线的影响"是【推理】，需要上板用 `listener`/示波器才能坐实。
- **未查 F103 的 PCB 走线**：本文的"悬空"是**原理图/网络表层面**的结论。理论上这些网络可能在 PCB 上被引到测试点/焊盘（原理图画不出）。**这一条同样要问硬件组**（已并入 Q2）。
- **未做 BOM 成本核算**：不知道板子是否已投产，所以"去掉能省多少钱"没有数（§3.1-B 的"若已投产，删 BOM 不省板子钱"也只是推理）。
- **未审 ESC 侧的 DShot/电流采样网络**：`ESC_DSHOT1..4`、`BAT_CURRENT1..4`、`TIM1_CH2/CH3`、`TIM8_CH3/CH4` 在 4 个 `WAFER-GH1.25-4PWB` 连接器上的对应关系与本文无关，我只在核对"F103 的网络是否在这里落地"时扫过一遍（结论：没有）。
- **未评价** `h104_imu` / `hxy42688p` / `ist8310` / `spa06` 的现状（那是 `review-01~04` 的范围）。
