# 资料 · DShot 学习清单（自研 H743 飞控 + 自研 G071 电调）

> 2026-09-29 筛选 · 用途：10/3 调电调前预习，要"能上手"不要百科。
> 场景锁定：飞控 STM32H743，4 路 DShot = TIM1_CH1..CH4 = PA8/PE11/PE13/PE14；电调 STM32G071GBU6N + FD6288Q + INA240A1 + WS2812B，跑 PX4。
> 全部链接 **2026-09-29 逐条实测可打开**；打不开的、收费墙后面的、与 PX4 无关的都已剔除（见文末「筛掉清单」）。

---

## 结论先行：只有 3 个，先看这 3 个

| 顺序 | 看什么 | 为什么 |
|---|---|---|
| 1 | **《DSHOT – the missing Handbook》**（Brushless Whoop） | 全网唯一把 DShot + 双向 DShot + EDT 讲全的一篇：帧结构、CRC 怎么算、150/300/600/1200 的 µs 级时序表、回传帧编码。读完这一篇，协议层就没有黑洞了。 |
| 2 | **PX4 官方《Actuator Configuration and Testing》** | 10/3 那天你要做的每件事（定电机顺序、改转向、不装桨试转、选 DShot 档位）都在这一页，官方、有截图。 |
| 3 | **HPMicro《双向 DSHOT（BDShot）收发实现概要设计》**（中文） | 极难得的中文 BDShot 深水区文档：线序反相、CRC 取反、21 bit GCR 回传、30~70 µs 方向切换预算、bring-up 步骤与常见坑。双向遥测不上来时按它逐条对。 |

**"看完就能上手调"的答案：有。** 顺序是 —— 第 1 篇建立协议直觉（1 个晚上）→ 第 2 层 PX4 官方两页照着点（半天）→ 10/3 当天带第 4 层的 HPMicro + B 站那两个排错视频备用。

---

## ⚠️ 先纠正两个会浪费你半天的坑

你说的是 `MOT_PWM_TYPE` 和 `DSHOT_CONFIG` —— **这两个参数在你现在用的 PX4 里已经不存在了**（我逐版核对了官方参数表的 HTML：v1.12 / v1.13 / v1.14 / main，四个版本里都查不到 `MOT_PWM_TYPE`；`DSHOT_CONFIG` 只在 v1.12–v1.13 出现过，v1.14 起消失）。照老教程找参数会找不到。

现在的正确做法（v1.12 及以后）：

| 你要做的事 | 现在的参数 | 值 |
|---|---|---|
| 给某组 FMU 输出开 DShot | `PWM_AUX_TIM0` ~ `PWM_AUX_TIM3`（**按定时器组**，不是按通道） | `-5`=DShot150 `-4`=DShot300 `-3`=DShot600（v1.15 文档另有 `-2`=DShot1200） |
| 开**双向** DShot（BDShot） | 同上，选 BDShot 档 | `-8`=BDShot150 `-7`=BDShot300 `-6`=BDShot600（main 分支） |
| 串口遥测（温度/电压/电流那条线） | `DSHOT_TEL_CFG` | 选接遥测线的那路串口 |
| 双向遥测的转速换算 | v1.16：`DSHOT_MOT_POL1..12`（每电机极对数）；v1.15 及更早：`MOT_POLE_COUNT` | 默认 14 |
| 解锁后电机不转/转速太低 | `DSHOT_MIN`（默认 0.055） | 调高到电机稳定转 |
| 3D 模式（双向油门） | `DSHOT_3D_ENABLE`（**ESC 也必须配成 3D**） | 谨慎 |

另外：**DShot 只能接 FMU 输出**，不能接 IO/MAIN（官方原话）。你的 PA8/PE11/PE13/PE14 在 FMU 侧，方向是对的；但要注意 TIM1 的四路必须落在**同一个定时器组**，且这些通道要没被别的外设（UART/SPI 复用）占掉。

---

## 第 1 层 · DShot 协议本身（它到底是什么）

### 1.1 DSHOT – The new kid on the block（blck.mn，2016-11）
- **讲什么**：DShot 的"出生公告"——由 KISS 的 Felix 主设计、Betaflight 的 Boris 团队与 BLHeli 的 Steffen 共同实现；讲清为什么它是**数字**协议（每一位的"高电平时间占比"定 0/1），以及相对 Oneshot/Multishot 的抖动、未知量程、需校准等痛点。
- **为什么推荐它**：这是**离原作者最近的一手说明**，不是二手转述。想搞懂"为什么 DShot 比 PWM 好"而不是背结论，看这篇；它还点明 DShot 的脉宽编码和 WS2811/WS2812 是同一类思路（你板上有 WS2812B，正好对得上）。
- **什么时候看**：预习第一晚，建立"为什么"。
- **可信度**：社区原文（Betaflight 圈子当年的官方发布渠道）。
- <https://blck.mn/2016/11/dshot-the-new-kid-on-the-block/>

### 1.2 DSHOT – the missing Handbook（Brushless Whoop）★ 最该看
- **讲什么**：事实上的 DShot 协议手册。帧结构 `SSSSSSSSSSSTCCCC`（11 位油门 + 1 位遥测请求 + 4 位 CRC）、1/0 判据（T1H 是 T0H 的两倍）、**完整时序表**（150/300/600/1200 的 T1H/T0H/位宽/整帧 µs）、**CRC 计算**、特殊命令、解锁序列、单向遥测、双向 DShot 的校验与帧结构、EDT 扩展遥测。
- **为什么推荐它**：唯一一处把协议讲全且**给得出数字**的资料；作者是因为自己写电调固件找不到手册才整理的，来源逐条标注（文末 Sources 列出 RCGroups 原帖、BLHeli issue、Betaflight PR）。缺点：英文。
- **什么时候看**：预习核心，协议层只看这一篇就够；调电调当天也要开着（对时序、对 CRC）。
- **可信度**：社区教程（但被广泛引用，去事实标准；数字与 Betaflight/BLHeli 源码一致）。
- <https://brushlesswhoop.com/dshot-and-bidirectional-dshot/>

### 1.3 Betaflight 源码 `src/main/drivers/dshot.c`（+ 特殊命令表）
- **讲什么**：协议的"代码真相"。编码、CRC、双向遥测解码、油门端点映射（`dshotInitEndpoints`）都在这里；文件头注释直接指向 EDT 规范仓库。
- **为什么推荐它**：以后你要在 H743 上自己写 DShot 收发（或改 PX4 驱动）时，任何"文档里没写清"的细节都以它为准。配合附件里的 **DShot 特殊命令规范**（1~47 号命令：beep、反转转向、请求遥测、保存设置……）一起看。
  - 特殊命令表（Betaflight 仓库文件）：<https://github.com/betaflight/betaflight/files/2704888/Digital_Cmd_Spec.txt>
- **什么时候看**：以后自己写电调 / 改飞控驱动时；预习阶段可略读。
- **可信度**：开源项目源码（Betaflight，GPLv3）。
- <https://github.com/betaflight/betaflight/blob/master/src/main/drivers/dshot.c>

### 1.4 DSHOT 指南（elmagnifico，2020，中文）
- **讲什么**：中文世界里少有的"真去用过 STM32 + HAL 发 DShot"的记录：协议历史、PWM/Oneshot/Multishot/DShot 的延迟对比、STM32 定时器怎么配、踩了哪些坑，并附**示波器实测波形**。
- **为什么推荐它**：作者开篇就吐槽"DSHOT 没有详细的介绍手册，基本全靠几个帖子和博客"——他做的正是你现在要做的事。中文、有波形、有配置细节，和你的 H743 用 TIM1 发 DShot 是同一类问题。
- **什么时候看**：预习（配合 1.2 看，中文对照）；自己配 TIM1 四通道时当操作手册。
- **可信度**：个人技术博客（非官方，但内容具体、可验证）。
- <https://elmagnifico.tech/2020/06/03/Dshot-STM32-PWM-HAL/>

---

## 第 2 层 · PX4 侧的配置与使用（★ 你最需要）

### 2.1 PX4 官方《DShot ESCs》
- **讲什么**：官方 DShot 主文档。接线（只能接 FMU/AUX）、按定时器组选 DShot/BDShot 档位、串口遥测 `DSHOT_TEL_CFG` 怎么接怎么开、极对数 `DSHOT_MOT_POL1..12` 对转速的影响、EDT（`DSHOT_BIDIR_EDT`）能额外给温度/电压/电流、以及 PX4 能通过 MAVLink **读写 AM32 电调的 EEPROM 配置**（对你自研 AM32 风格电调有直接参考价值）。
- **为什么推荐它**：官方、且是唯一把"PX4 侧 DShot 全貌"写在一页的文档；你 10/3 遇到的参数名全部以此为准。
- **什么时候看**：预习通读一遍；调电调当天当字典查。
- **可信度**：**官方文档**（docs.px4.io；`main` = 开发分支，双向 DShot/EDT 相关小节标的是 PX4 v1.16）。
- <https://docs.px4.io/main/en/peripherals/dshot.html>

### 2.2 PX4 官方《Actuator Configuration and Testing》（QGC → Actuators）★ 当天主力
- **讲什么**：QGC 里 `Vehicle Setup → Actuators` 三个分区的完整说明：**Geometry**（就是 `CA_ROTOR0_PX/PY/PZ`、`CA_ROTOR0_KM` 等机架几何参数，含 FRD 坐标系与"原点在重心不是飞控"的坑）、**Actuator Outputs**（把电机分到哪个输出、选 DShot 档位）、**Actuator Testing**（**不装桨**逐个测电机转向/顺序）。
- **为什么推荐它**：10/3 那天你的大部分操作就在这一页上；特别是 `Set Spin Direction`（改转向不用重焊线）和 Actuator Testing 的用法，官方写得很直白。`CA_ROTOR*` 与机架几何的关系也在这一页讲清（几何 → 控制分配 → 混控）。
- **什么时候看**：预习（先认识界面）；**调电调当天必开**。
- **可信度**：**官方文档**。
- <https://docs.px4.io/main/en/config/actuators.html>

### 2.3 PX4 源码里的参数定义（`module.yaml`）
- **讲什么**：参数的**真源**。`src/drivers/dshot/module.yaml` = 所有 `DSHOT_*` 参数（含默认值、取值范围、是否需重启）；`src/drivers/pwm_out/module.yaml` = 每个定时器组的输出协议枚举（`-8 BDShot150` … `-3 DShot600` … `50 PWM 50Hz`）。
- **为什么推荐它**：官方文档偶尔滞后于源码。你自研板子做移植/裁剪时，"这个版本到底有没有这个参数"以 `module.yaml` 为准——比如 `DSHOT_BIDIR_EDT`、`DSHOT_ESC_TYPE`、`DSHOT_MOT_POL1..12` 都是较新才进 main 的。
- **什么时候看**：预习扫一遍参数名；改驱动/移植板子时精确查。
- **可信度**：**官方源码**（PX4-Autopilot）。
- <https://github.com/PX4/PX4-Autopilot/blob/main/src/drivers/dshot/module.yaml>
- <https://github.com/PX4/PX4-Autopilot/blob/main/src/drivers/pwm_out/module.yaml>

### 2.4 中文视频：超维小课堂（十五）PX4 使用 Dshot 协议
- **讲什么**：一个成体系的中文 PX4 教程系列里的一集，演示在 PX4 上把 DShot 跑起来；同系列还有《（十二）Control Allocate》讲控制分配（`CA_ROTOR*` 的来龙去脉）。
- **为什么推荐它**：**中文 + 界面演示**，比啃文档快。适合预习时先把"在 PX4 里点哪里"建立直觉，再回官方文档抠细节。注意它是 2023 年的，参数名与你现在的新版本会有出入——细节一律回 2.1/2.3 核对。
- **什么时候看**：预习（先看视频建立直觉）。
- **可信度**：社区教程（B 站，UP"南京超维空间科技"，约 3.2k 播放）。
- <https://www.bilibili.com/video/BV17u411M7fy/>

> 附（官方速查，可选）：协议横向对比《ESC Protocols》<https://docs.px4.io/main/en/esc/esc_protocols.html>；支持的 ESC 列表《ESCs & Motors》<https://docs.px4.io/main/en/peripherals/esc_motors.html>。

---

## 第 3 层 · 电调固件生态（自研前先看清别人怎么写的）

### 3.1 AM32 —— 你最该抄的参考实现（**明确支持 STM32G071**）
- **讲什么**：面向 STM32/ARM 的开源电调固件。支持 DShot300/600、**双向 DShot**、KISS 标准遥测、可变 PWM 频率、正弦启动；仓库里有 `Mcu/g071` 目录，即**你的 G071 就在官方支持列表里**（其余支持 STM32F051 / STSPIN32F0 / GD32E230 / AT32F415 / AT32F421 等）。带 bootloader、配置器（网页版 + 桌面版）、Keil 工程与 Makefile，还有 `SITL` 目录。
- **为什么推荐它**：这是"自研 G071 电调"最短的路——either 直接刷 AM32 验证你的 FD6288Q + INA240A1 硬件，or 拿它的 DShot 解码、换相、遥测代码当模板。GPLv3 开源，能读源码。
- **什么时候看**：预习时先看 README 估工作量；**10/3 调电调当天大概率要用它的工具链**；以后自己写固件时精读源码。
- **可信度**：**开源项目原 README / 源码**（GPLv3）。
- <https://github.com/AM32-firmware/AM32>

### 3.2 AM32 官方 Wiki
- **讲什么**：目标板兼容表、引脚/bootloader 选择、编译与配置流程、升级方式（Betaflight passthrough / 单线串口 / Arduino）。
- **为什么推荐它**：从"仓库 README"到"真的点亮一块板子"之间的那几步，在这。你要给自研板做 G071 target，先照它的 target 结构抄。
- **什么时候看**：10/3 前一周（准备工具链）；调电调当天。
- **可信度**：**项目官方 Wiki**。
- <https://wiki.am32.ca/>

### 3.3 Bluejay —— 开源固件的"另一种形态"（8 位，不能搬到你板子上）
- **讲什么**：BLHeli_S 16.7 的开源后继，主打 DShot150/300/600、双向 DShot RPM 遥测、24/48/96 kHz PWM、PWM dithering。**只跑 SiLabs EFM8BB（Busy Bee）8 位 MCU**。
- **为什么推荐它**：它是"开源电调固件生态"里最活跃的项目之一，读它能理解开源固件的边界与取舍（为什么 8 位也能跑 96k、为什么它只支持数字协议）。**但它 100% 不能用于 G071** —— 列在这里是为了让你别把时间花错地方。
- **什么时候看**：预习时花 10 分钟了解生态即可。
- **可信度**：**开源项目原 README**。
- <https://github.com/mathiasvr/bluejay>

### 3.4 bitdump/BLHeli —— 一页看清"谁开源、谁闭源"
- **讲什么**：BLHeli 原作者（Steffen Skaug）的仓库首页，一段话讲清三代关系：BLHeli（Atmel/SiLabs 8 位，汇编，**GPLv3 开源**）、BLHeli_S（SiLabs 8 位，汇编，**GPLv3 开源**）、BLHeli_32（32 位，**闭源**）。
- **为什么推荐它**：很多人以为 BLHeli_32 是开源的（因为 Bluejay 常和它并提）。这一页是一手澄清，避免你在"能不能改 BLHeli_32"上浪费时间。同时 BLHeli_S 的开源汇编是理解换相/无感启动的经典读物。
- **什么时候看**：预习时 5 分钟，明确生态边界。
- **可信度**：**原作者仓库 README**。
- <https://github.com/bitdump/BLHeli>

> 附（以后自己写电调时用）：**Extended DShot Telemetry (EDT) 规范**——双向 DShot 上再叠温度/电压/电流的官方规范（帧结构、eRPM 归一化、前缀编码、校验和）。PX4 的 `DSHOT_BIDIR_EDT` 就要求 ESC 侧支持 EDT（如 AM32）。<https://github.com/bird-sanctuary/extended-dshot-telemetry>

---

## 第 4 层 · 动手 / 排错（10/3 当天）

### 4.1 双向 DSHOT（BDShot）收发实现概要设计（HPMicro 知识库，中文）★ 排错首选
- **讲什么**：把 BDShot 讲透的中文长文：命令帧**线序反相**（空闲高、低脉冲有效）、**CRC 取反**（`crc = ~(v ^ (v>>4) ^ (v>>8)) & 0xF`，命令帧与回传帧通用）、回传帧 21 bit GCR 编码与 eRPM 载荷、**ESC 收到命令后标称 ~30 µs（慢速固件可达 ~70 µs）才开始回传** 的时序预算、两种接收采集方案（DMA 过采样 / 定时器捕获）、**Bring-up 步骤与常见坑**。
- **为什么推荐它**：双向 DShot 的时序与反相细节在英文资料里也零散，这篇是罕见的系统整理；虽然是 HPMicro 芯片的实现，但**协议层完全通用**，正对你 H743 侧要做的"发命令 + 收 eRPM"。双向遥测不上来时，逐条对着它的 bring-up 清单查。
- **什么时候看**：预习（第二遍读）；**双向遥测出问题时第一站**。
- **可信度**：芯片厂商技术文档（协议描述通用，寄存器部分仅适用于其自家芯片）。
- <https://kb.hpmicro.com/2026/08/11/%e5%8f%8c%e5%90%91-dshot%ef%bc%88bdshot%ef%bc%89%e6%94%b6%e5%8f%91%e5%ae%9e%e7%8e%b0%e6%a6%82%e8%a6%81%e8%ae%be%e8%ae%a1/>

### 4.2 视频：STM32 配置电调 DSHOT 协议驱动（B 站，2025-09）
- **讲什么**：UP 用 **STM32H7 + TIM 的 DMA 功能**驱动 DShot 协议电调，视频里就是配置过程（芯片、定时器、DMA、输出验证）。
- **为什么推荐它**：**这是全网离你最近的资料**——同样是 H7、同样走定时器 DMA 发 DShot。你要在 H743 的 TIM1 上发 4 路 DShot，看别人怎么配能省掉大量试错。
- **什么时候看**：预习（自己动手配 TIM1 之前）；10/3 当天备用。
- **可信度**：社区视频（B 站，2025-09-19 发布，约 4.8k 播放）。
- <https://www.bilibili.com/video/BV1cTWNz4Eag/>

### 4.3 视频：双向 dshot 打开电机不转 / RPM 滤波器问题解决分享（B 站）
- **讲什么**：开了双向 DShot 之后**电机不转**的完整排查过程（含电调地面站、固件、参数），最后定位到问题。
- **为什么推荐它**：这是双向 DShot 最典型的一类症状。视频把"从哪一步开始怀疑"演示了一遍，比读文档快。注意它讲的是穿越机（Betaflight/BLHeli 系）流程，PX4 侧对应的是 `PWM_AUX_TIMx` 选 BDShot 档 + 定时器是否支持 DMA 捕获。
- **什么时候看**：调电调当天，真遇到"开了 BDShot 电机不转"时。
- **可信度**：社区视频（B 站，2.2 万播放）。
- <https://www.bilibili.com/video/BV1hS4y1k7op/>

### 4.4 台架工具：dshot-esc-tester（ESP32，开源）
- **讲什么**：用 ESP32 直接以 **DShot600** 驱动一颗 ESC 并读回遥测，算电机 KV、可接称重传感器测推力，数据走串口、结果显示在 OLED 上。
- **为什么推荐它**：**让"自研电调"先脱离飞控单独被验证**——不接飞控、不写一行飞控代码，就能确认你的 G071 板子能收 DShot、能回遥测、能驱动电机。10/3 最怕的是"飞控和电调同时有嫌疑"，这个工具能先把电调那一半钉死。README 里给了 PCB 和 BOM。
- **什么时候看**：调电调前 1~2 天（要打板/接线的话更早）；10/3 当天做交叉验证。
- **可信度**：开源项目原 README（个人项目，ESP32 + BLHeli_32 场景验证过）。
- <https://github.com/LeadFingers/dshot-esc-tester>

### 4.5 关于"示波器/逻辑分析仪抓 DShot 波形"（先说结论，省得你找工具）
- **没有现成的一键解码器**：我查了 sigrok/PulseView 的官方协议解码器清单，以及 `libsigrokdecode` 的 `decoders/` 目录（最可能有 DShot 的就是它），**确认没有 DShot 解码器**。所以别把时间花在"装个软件自动出结果"上。
- **正确姿势**：用示波器/逻辑分析仪抓一帧，**量高电平时间**再对照第 1 层 1.2 的时序表——DShot600 的 T1H≈1.25 µs、T0H≈0.625 µs、整帧≈26.7 µs；DShot300 是它的 2 倍，DShot150 是 4 倍。这个"量高电平判 0/1"的方法和 WS2812B 完全一样，你应该很熟。
- **触发技巧**：帧间有较长空闲，用**下降沿触发（单向）**抓一帧很稳；**双向 DShot 空闲电平是高**，要用上升沿触发，且命令帧与回传帧在同一根线上交替出现（间隔约 30 µs 起，见 4.1）。1.4 的 elmagnifico 文里有他抓到的实测波形可以对照。

> 不装桨测顺序与转向：直接照 **2.2 PX4 官方 Actuator Testing** 做（QGC → Actuators → Actuator Testing，逐个给小油门看转向、看顺序），这是官方指定流程，不需要额外资料。**永远先拆桨。**

> DShot 不发动的三个最高频原因（依据 PX4 官方文档归纳）：① 信号接在了 IO/MAIN 上（DShot 只支持 FMU/AUX）；② 对应**定时器组**的协议参数没设成 DShot（只改了 UI 没写入/没重启）；③ `DSHOT_MIN` 偏低或 `DSHOT_3D_ENABLE` 开了但 ESC 没配 3D，导致解锁后电机不转。双向 DShot 另加一条：该定时器必须支持 DMA 捕获。

---

## 按时间线排序的阅读顺序

| 时间 | 读什么 | 目的 | 预计 |
|---|---|---|---|
| **现在（9 月底预习）D1** | 1.2 Handbook（配合 1.1 blck.mn） | 协议层打通：帧格式 / CRC / 四种速率 / 为什么比 PWM 好 | 1 个晚上 |
| **D1（中文对照）** | 1.4 elmagnifico《DSHOT 指南》 | 中文再看一遍，顺便看 STM32 侧怎么发、波形长什么样 | 1 小时 |
| **D2** | 2.1 PX4《DShot ESCs》 | 记住 PX4 侧全貌与参数名（**并纠正 `MOT_PWM_TYPE`/`DSHOT_CONFIG` 的老印象**） | 1 小时 |
| **D2** | 2.2 PX4《Actuator Configuration and Testing》 | 认熟 QGC 界面：几何 / 输出分配 / 不装桨测试 | 1 小时 |
| **D3** | 2.4 超维小课堂（十五）中文视频 | 用中文视频把"点哪里"建立直觉 | 20 分钟 |
| **D3** | 2.3 PX4 源码 `module.yaml` ×2 | 把参数名落到源码，确认版本差异 | 40 分钟 |
| **D4** | 4.2 B 站 H7 + TIM DMA 发 DShot 视频 | 提前看别人怎么用 H7 定时器发 DShot（你的 TIM1 四通道） | 30 分钟 |
| **D4** | 3.1 AM32 README + 3.2 AM32 Wiki + 3.4 BLHeli 一页 | 决定电调固件路线（刷 AM32 还是自研），看清开源边界 | 1.5 小时 |
| **D5** | 4.1 HPMicro BDShot 长文 | 双向 DShot 的时序/反相/GCR 与 bring-up 坑 | 1.5 小时 |
| **D6（准备日）** | 4.4 dshot-esc-tester + 4.3 排错视频 + 4.5 波形方法 | 准备台架交叉验证 + 排错预案 + 想清楚怎么抓波形 | 1 小时 |
| **10/3 当天** | 手边常开：2.2（操作）、1.2（时长/CRC 对照）、4.1（BDShot 时序）、4.3（症状排查） | 干活 | — |
| **以后（自研电调固件）** | 3.1 AM32 源码精读 + 3.3 Bluejay 作对照 + 1.3 Betaflight `dshot.c` + EDT 规范 | 自己写 G071 固件（DShot 解码 → 换相 → 遥测回传） | 周级 |

---

## 筛掉清单（说明为什么没给你，省得你自己去踩）

| 被筛掉的 | 原因 |
|---|---|
| `MOT_PWM_TYPE` / `DSHOT_CONFIG` 相关的老教程 | **参数已废**：`MOT_PWM_TYPE` 在 v1.12 及以后的官方参数表里查不到；`DSHOT_CONFIG` 只在 v1.12–v1.13 存在。照老教程走会找不到参数。 |
| `github.com/betaflight/betaflight/wiki/DSHOT-ESC-Protocol` | **已失效**：Betaflight 的 GitHub Wiki 已下线，该 URL 现在被重定向到仓库首页，拿不到 DShot 内容（我用协议手册里的替代方案 + Betaflight 源码取代）。 |
| `betaflight.com/docs/...` 下的 DShot / Motor-Protocol 页面 | **拿不到**：官网文档站改版，这些路径全部 404，站点内容靠 JS 渲染，无法稳定定位到协议说明页。 |
| `speedgoat.com` 的 DShot 协议说明页 | **403 拒绝访问**（该公司把帮助文档挡在墙外），无法验证，弃。 |
| 知乎文章（如《DSHOT 协议进阶实现-1 通道 DMA 发 4 路波》《穿越机 BLHelis/32 电调 Dshot 协议是什么？》） | **403 拒绝访问**，无法确认可打开（知乎对未登录抓取拦截）。内容可能有用，但按你的要求"验证过能打开才给"，弃。想看的话自己浏览器搜标题即可。 |
| CSDN 上的中文 DShot 详解（如 `zhengningwei` 2018 那篇） | 内容其实不错（有示波器实拍帧、讲 CRC），但该站对抓取返回 521 风控，**无法稳定验证"能打开、没被墙"**；中文替代已给 1.4 elmagnifico。 |
| 微信公号上的《DSHOT 手册》中文翻译（`mp.weixin.qq.com/s/I5PclfGJ9Lp3vJ3oW-RKWg`） | 抓取时被**验证码页**拦截，无法确认正文可读。若你有微信，可自行搜"DSHOT 手册"看中文版（它是 1.2 的翻译）。 |
| ArduPilot / 零一飞行等非 PX4 的 DShot 文档 | 平台不同（参数体系完全不一样），对你这套 PX4 是干扰项。 |
| Betaflight《Motors》标签页教程 | 你是 PX4，不装桨测电机用 QGC 的 Actuator Testing（2.2）即可，不必引入 Betaflight 流程。 |

---

## 一句话总结

**协议看 1.2（英文手册）+ 1.4（中文对照），PX4 操作看 2.1/2.2，双向 DShot 排错看 4.1 —— 这四篇吃透，10/3 就能上手；电调固件路线先看 3.1 AM32（它支持你的 G071）。**
