# 06 · IMU（ICM-42688-P）起不来 —— 软件侧深度排查

> 日期：2026-09-29 晚（会话 3）
> 现象：`icm42688p status` → `INFO [SPI_I2C] Not running`；
>       `icm42688p -s -b 1 -R 0 start` → `ERROR [SPI_I2C] icm42688p: no instance started (no device on bus?)`
> **结论（一句话）**：飞控这一侧（MCU 引脚 / SPI1 / 时钟 / PX4 驱动 / 原理图）**全部被证明是好的**；
> 卡住的是**那颗 IMU 芯片本身** —— 它会正常响应 SPI，但**不实现 ICM-42688-P 的寄存器接口**：
> 真正的 ICM-42688-P 上 `0x75` 是**只读**的 WHO_AM_I（读出来必须是 `0x47`），
> 我们这颗 `0x75` **可读可写**、复位后读出来是 `0x00` ⇒ 驱动 probe 永远过不了。
> ⇒ **软件改不了这个，要换/查芯片**（见第七节）。

---

## 一、输入（我基于什么查的）

```text
板子源码   ~/桌面/RM2027/PX4-Autopilot/boards/rm2027/fmu-h743/
           src/spi.cpp、nuttx-config/include/board.h、nuttx-config/nsh/defconfig、src/init.c
PX4 源码   src/drivers/imu/invensense/icm42688p/（probe/寄存器表/CLI）
           platforms/common/i2c_spi_buses.cpp（"no instance started" 那条报错的出处）
           platforms/nuttx/src/px4/stm/stm32_common/spi/spi.cpp（CS 配置/选择）
           platforms/nuttx/NuttX/nuttx/arch/arm/src/stm32h7/stm32_spi.c（NuttX 驱动怎么发字节）
参考板     boards/radiolink/PIX6（H743，SPI1 = PB3/PA6/PD7 + ICM42688P CS=PB4 —— 与本板**完全相同**）
datasheet  references/硬件手册/ICM-42688-P_datasheet_extract.md（Table 10 引脚表 + 9.6 SPI + 寄存器表）
原理图     references/硬件手册/FMU_飞控板_原理图_2026-09-24.pdf（**渲染成图用眼睛看**，见 06-图-*.png）
芯片手册   STM32H743VI：RM0433 调试端口 / NuttX stm32h7 Kconfig & 寄存器位定义
工具       openocd 0.12.0 + ST-Link/V2（SWD）；所有脚本留在 work/spi-debug/
```

---

## 二、★ 决定性实验：绕过 PX4，用调试器直接跟芯片对话

思路：**把固件从等式里去掉**。如果我用调试器按 NuttX 驱动一模一样的时序手工发一笔 SPI 事务，
芯片还是不回正确数据，那问题就与固件无关。

### 2.1 先读寄存器（只读，确认 MCU 侧把引脚配对了）

命令（脚本 `work/spi-debug/regdump.cfg`，`pkill -x openocd` → `halt` → `mdw` → `resume`）：

| 寄存器 | 值 | 解读 |
|---|---|---|
| `DBGMCU_IDCODE` 0x5C001000 | `0x20036450` | DEV_ID=0x450 = STM32H743/753 ✅ |
| `SPI1_CR1` 0x40013000 | `0x00001001` | SPE=1（SPI 已启用）、SSI=1（内部 NSS 高）✅ |
| `SPI1_CFG1` 0x40013008 | `0x10070007` | DSIZE=7（8bit）、MBR=1 → **SCK=96MHz/4=24MHz** ✅ |
| `SPI1_CFG2` 0x4001300C | `0x87400000` | MASTER=1、CPOL=1、CPHA=1 → **MODE 3**、SSM=1、SSOE=0、AFCNTR=1 ✅ |
| `SPI1_SR` 0x40013014 | `0x00001802` | TXP=1、SUSP=1、TXC=1、RX FIFO 空 → 空闲、上一笔已完成 ✅ |
| `GPIOB_MODER` 0x58020400 | `0xfa0ffdbf` | **PB3=AF（SCK）、PB4=输出（CS）** ✅ |
| `GPIOB_AFRL` 0x58020420 | `0x00005000` | **PB3 = AF5 = SPI1_SCK** ✅ |
| `GPIOB_ODR` 0x58020414 | `0x00000c10` | **bit4=1 → CS 空闲高** ✅ |
| `GPIOA_MODER` 0x58020000 | `0xabfeefff` | **PA6=AF（MISO）** ✅ |
| `GPIOA_AFRL` 0x58020020 | `0x05000000` | **PA6 = AF5 = SPI1_MISO** ✅ |
| `GPIOD_MODER` 0x58020C00 | `0xf05abfea` | **PD7=AF（MOSI）、PD6=模拟（**未配置**，见 §6）** |
| `GPIOD_AFRL` 0x58020C20 | `0x50000899` | **PD7 = AF5 = SPI1_MOSI** ✅ |
| `RCC_CR` 0x58024400 | `0x3f03c035` | HSE on+ready ✅、**PLL2 on+ready** ✅ |
| `RCC_D2CCIP1R` 0x58024450 | `0x00011000` | bits[14:12]=1 → **SPI123 时钟源 = PLL2** ✅；bit16 → SPI45 = PLL2 |
| `RCC_PLL2DIVR` 0x58024438 | `0x0404085f` | N2=95(×96)、P2 域=4 → 因 `RCC_PLL2DIVR_P2(x)=((x)-1)<<9` ⇒ **PLL2P=480/5=96MHz** ✅ |
| `RCC_APB2ENR` 0x580244F0 | `0x00001031` | **SPI1EN=1（SPI1 时钟已开）** ✅ |

**⇒ MCU 侧全部正确**：PB3/PA6/PD7 都进了 AF5，PB4 是推挽输出且空闲为高，SPI1 是主机、MODE 3、24MHz、
时钟源 96MHz 且已使能。（`CFG1` 的 MBR 和 `CFG2` 的 MODE 只可能由驱动写进去 —— 这也**反过来证明
PX4 驱动的“开总线+设参数”路径确实跑到了**。）

### 2.2 手工复刻驱动 `probe()` 的那两笔事务

驱动 `ICM42688P::probe()` 做的事：`SelectRegisterBank(0, force)` → 写 `REG_BANK_SEL(0x76)=0`，
再读 `WHO_AM_I(0x75)`。我用调试器按 NuttX `spi_putreg8/spi_getreg8`（**字节访问**）的时序复刻：

```text
① 写：CS 低 → CSTART+TX 0x76 → 读 RX → CSTART+TX 0x00 → 读 RX → CS 高
② 读：CS 低 → CSTART+TX 0xF5 → 读 RX → CSTART+TX 0x00 → 读 RX → CS 高
       0xF5 = 0x80|0x75 = 读寄存器 0x75，第 2 个字节就是 WHO_AM_I
```

**结果（raw）**：

```text
== T2 READ WHO_AM_I(0x75) : 期望 0x47 ==
0x40013014: 00003807     ← SR: RXP=1 TXP=1 DXP=1 SUSP=1 TXC=1 → 全双工帧正常完成
0x40013030: ff           ← 地址帧（从机此时不驱动 SDO，高阻→读到 1）
0x40013014: 00003807
0x40013030: 00           ← ★ 数据帧 = 0x00  （不是 0x47）
```

重复读、换地址读、换速率（把 `CFG1.MBR` 从 1 改成 6 → **0.75MHz**）读，结果全是 **0x00**：

```text
T4 再读 0x75（24MHz） → 0x00
0.75MHz 下读 0x75     → 0x00
0.75MHz 下读 0x76     → 0x00
```

（另有两次对照：不先发“读地址”而只发 dummy，MISO 一直读到 `0xff` —— 说明总线空闲是高、
只有“读命令”之后从机才把线拉下来 ⇒ **那颗芯片确实在回应 SPI 命令**，不是断线/浮空假象。）

### 2.3 ★ 写→回读：证明写通路、读通路、地址译码都是好的

```text
写 0x76 = 0xA5  → 读 0x76 = 0xA5      ✅ 写进去了、也读回来了
写 0x76 = 0x5A  → 读 0x76 = 0x5A      ✅
写 0x76 = 0x00  → 读 0x76 = 0x00      ✅
写 0x75 = 0x5A  → 读 0x75 = 0x5A      ☠️
写 0x75 = 0x00  → 读 0x75 = 0x00      ☠️
```

**☠️ 这就是根因所在**：

```text
datasheet 提取文本 L3750（bank0 寄存器表）：  75  117  WHO_AM_I  R  WHOAMI
                                            ↑寄存器地址  ↑十进制  ↑名字   ↑★访问属性=R（只读）

真正的 ICM-42688-P：0x75 = WHO_AM_I，只读，读出来必须 0x47（-P；-686 是 0x44）
我们这颗芯片：      0x75 是个普通读写寄存器，复位后读 0x00
                    0x76 也是普通读写寄存器（写 0xA5 就回 0xA5）
                    —— 真芯片的 0x76 = REG_BANK_SEL，只有 3 bit，写 0xA5 应回 0x05、写 0x5A 应回 0x02
```

### 2.4 全寄存器扫描（bank0，只读，128 个地址）

| 地址 | 值 | | 地址 | 值 | | 地址 | 值 |
|---|---|---|---|---|---|---|---|
| 00 | 00 | | 0b | 01 | | 1d | 07 |
| 01 | 6a | | 0c | ff | | 1e | ff |
| 02 | 11 | | 0d | d2 | | 1f | 40 |
| 05 | 50 | | 0f | 2e | | 3a | 08 |
| 08 | 80 | | 10 | 08 | | 40 | a8 |
| | | | 11 | da/dd/d6（**会变**） | | 41 | 02 |
| | | | 18 | e3 | | 42 | a9 |
| | | | 19 | 14 | | 44 | 46 |
| | | | 1a | 58 | | 45 | 88 |
| | | | | | | 68/6c/74/7d | 05/70/e7/05 |

其余地址全 `00`。**整个 128 个地址里没有任何一个返回 `0x47`/`0x44`/`0x42`/`0x67`。**

另外：写 `0x76` = 0..7 逐个“切 bank”，`0x75`/`0x0b`/`0x1d` 的值**一个都没变** ⇒ 这颗芯片上不存在
ICM-42688-P 那种 bank 机制（或者说它不认）。反向印证：`0x11` 的值会自己变（`dd → da → d6`），
说明芯片内部有“活”的寄存器在跑（有硅片在工作），不是死片。

---

## 三、根因判断（证据链）

```text
① PX4 的报错语义（platforms/common/i2c_spi_buses.cpp L765）：
   "no instance started (no device on bus?)" = 总线找到了，但驱动 instantiate() 返回空
   ⇒ 对 SPI 驱动而言就是 probe() 失败（WHO_AM_I 不等于 0x47）

② 驱动 probe() 的判据（src/drivers/imu/invensense/icm42688p/ICM42688P.cpp L125-142）：
   连试 3 次，每次先写 REG_BANK_SEL=0，再读 WHO_AM_I(0x75)；3 次都不是 0x47 → 返回 PX4_ERROR

③ MCU/固件侧被证明是好的：
   · 引脚：PB3=AF5(SCK)、PA6=AF5(MISO)、PD7=AF5(MOSI)、PB4=推挽输出空闲高(CS)
   · 外设：SPI1 已使能、主机、MODE 3、24MHz、时钟源 PLL2(96MHz)、PLL2 已锁定
   · 时序：手工复刻驱动的事务，SR 显示全双工帧正常完成（DXP/TXC/RXP 都对）
   · 写/读/地址译码：写 0x76=0xA5 读回 0xA5；写 0x75=0x5A 读回 0x5A

④ 原理图被证明是对的（渲染成图逐脚看，见 06-图-U5原理图.png / 06-图-U5-VDD.png）：
   U5 pin1=SPI1_MISO、pin4=GYRO_INT1、pin5=VDDIO→3.3V_H7(+C3)、pin6=GND、
   pin8=VDD→3.3V_H7(+C38)、pin9/10/11(FSYNC/RESV)→GND、pin12=GYRO_CS、
   pin13=SPI1_SCK、pin14=SPI1_MOSI。这 4 根信号线上**没有串阻/上下拉**（网络只出现两次：
   MCU 端 + U5 端），与本板 board.h 的宏一一对得上。

⑤ 实测：那颗芯片在 0x75 上**不是只读的 WHO_AM_I**（可读可写，复位读 0x00），
   0x76 也不是 3bit 的 REG_BANK_SEL；换速率、换地址、切 bank、软复位都改不出 0x47。

★ 结论：卡点不在软件，在**这颗 IMU 器件本身**（不是正品/不是 ICM-42688-P，或已损坏到
  寄存器接口都不对）。
```

---

## 四、用户点名的 8 个问题 —— 逐条回答

### Q1 · NuttX 的 stm32h7 有没有 JTAG/SWD 的 Kconfig 开关？有没有 SWJ_CFG 处理？

**没有。**

```text
grep -rn -i "jtag|swd|swj|trace" arch/arm/src/stm32h7/Kconfig   → 0 命中（空）
grep -rn -i "swj|afio"        arch/arm/src/stm32h7/*.c           → 0 命中
对照 stm32f1：arch/arm/src/stm32/Kconfig L3752-3764 有
   prompt "JTAG Configuration" / STM32_JTAG_DISABLE / STM32_JTAG_FULL_ENABLE /
   STM32_JTAG_NOJNTRST_ENABLE（注释还写着 "by default JTAG-DP and SW-DP are disabled"）
```

原因不是 NuttX 漏了，而是 **H7（以及 F4/F7/L4/G4 之后的家族）根本没有 F1 那种
`AFIO_MAPR` 的 `SWJ_CFG` 字段**：F1 要“关 JTAG 才能拿回 PB3/PB4/PA15”，H7 不需要 ——
H7 的调试脚复位后就是普通 GPIO/AF，软件重新配置即可。所以 stm32h7 里没有这个开关可开。

### Q2 · STM32H743 到底需不需要关 JTAG 才能用 PB3/PB4？

**不需要。** 四条独立证据：

```text
a) 寄存器实测：GPIOB_MODER = 0xfa0ffdbf → PB3=AF、PB4=输出(01)，PB4 的 ODR bit4=1。
   如果 JTAG 还占着，这两位不可能是这个样子。
b) 本板自己的事务已经跑起来了：PB3 当 SCK 在发时钟（SR 里 DXP/TXC=1，帧完成），
   PB4 当 CS 在拉低/拉高（我手工控制时读到的数据跟着变）—— 也就是这两个脚
   **确实在被当普通 SPI 功能使用**，没有任何 JTAG 占用的迹象。
c) 现成反例（同一颗 MCU、同一种用法，PX4 官方板在跑）：
   · boards/radiolink/PIX6（H743）：SPI1 SCK=PB3、MOSI=PD7、MISO=PA6，
     并且 spi.cpp 就是 `initSPIDevice(DRV_IMU_DEVTYPE_ICM42688P, SPI::CS{GPIO::PortB, GPIO::Pin4})`
     —— **跟本板一字不差的组合**，那块板能跑。
   · boards/aedrox/aedroxh7：GPIO_SPI1_SCK_2(PB3) + GPIO_SPI1_MISO_2(PB4) 一起用。
   · boards/px4/fmu-v5x（H753）、modalai/fc-v1、sky-drones/smartap-airlink：PB4 当 SPI1_MISO。
d) 本板 ARM 侧也把 PA15 当普通 GPIO 用（SYNC_OUT），同理没有问题。
```

### Q3 · PX4 里有没有别的板子也用 PB3 做 SPI1_SCK / PB4 做 CS？它额外配了什么？

有，而且**有一条与本板完全一致的先例**：

```bash
grep -rn "GPIO_SPI1_SCK_2"  boards/*/*/nuttx-config/include/board.h
   → aedrox/aedroxh7、radiolink/PIX6、（本板 rm2027/fmu-h743）
grep -rn "GPIO_SPI1_MISO_2" boards/*/*/nuttx-config/include/board.h
   → aedrox/aedroxh7、modalai/fc-v1、px4/fmu-v5x、sky-drones/smartap-airlink
grep -rn "SPI::CS{GPIO::PortB, GPIO::Pin4}" boards/*/*/src/spi.cpp
   → bitcraze…（F4 板）、radiolink/PIX6、本板
```

对照 `boards/radiolink/PIX6`（H743）：`GPIO_SPI1_MISO=PA6 / MOSI=PD7 / SCK=PB3`，
`src/spi.cpp` 里 `initSPIDevice(DRV_IMU_DEVTYPE_ICM42688P, SPI::CS{PortB,Pin4})`，
`init/rc.board_sensors` 里 `icm42688p -R 2 -s start`。
**它没有为本板这种组合额外配置任何东西**（defconfig 里也只有 `CONFIG_STM32H7_SPI1=y` +
`CONFIG_STM32H7_SPI1_DMA=y`；本板 defconfig 与之相同，且 `board_dma_map.h` 与 matek/h743-slim
逐字节相同）。⇒ **“别人多配了什么”这个方向没有可抄的差额 ⇒ 本板不缺配置。**

### Q4 · `-b 1` 是否真对应 `SPI::Bus::SPI1`？

**是。**

```text
platforms/common/module.cpp L104-131（CLI 帮助，权威定义）：
   -s = "Internal SPI bus(es) (onboard sensors; shared bus only if -b is given)"
   -b = "board-specific bus (default=all) (external SPI: n-th bus (default=1))"
   -c = chip-select pin、-m = SPI mode、-f = bus frequency in kHz、-q = quiet
src/spi.cpp: initSPIBus(SPI::Bus::SPI1, …) → 数组第 0 项、bus=1（Internal）
⇒ `-s -b 1` = 内部 SPI 总线 1 = SPI1 ✅（其它板同写法：matek/h743 `icm42688p -R 12 -b 1 -s start`、
  accton/ga1 `-b 1/-b 2` 两块 IMU、cubepilot/cubeorangeplus `-s -b 4`。）
另外 PIX6 只写 `-s`（不带 -b）也能起来，说明 `-s` 已经覆盖“内部总线”，`-b 1` 是显式指定同一条。
```

顺带：**要打印真实 WHO_AM_I 值，可以加 `-d`**（`DEVICE_DEBUG` 受 `_debug_enabled` 控制）：

```text
icm42688p -s -b 1 -R 0 -d start
   → 驱动会打印 3 次 "unexpected WHO_AM_I 0x00"（本板实测值应为 0x00）
```

### Q5 · SPI 模式（CPOL/CPHA）对不对？

**对，MODE 3。** 现场读到 `SPI1_CFG2 = 0x87400000` → `CPOL(bit25)=1、CPHA(bit24)=1、MASTER(bit22)=1、
SSM(bit26)=1、SSOE(bit29)=0`。datasheet 9.6：数据在 SCLK 上升沿被锁存、下降沿翻转 ⇒ MODE 0/MODE 3
都可以；PX4 驱动与 NuttX 用的是 MODE 3，全家族板子都这样。
**本板不需要额外配 CPOL/CPHA。**

### Q6 · CS（PB4）有没有真的被配成输出？

**有，而且选择逻辑是通的。**

```text
platforms/nuttx/src/px4/stm/stm32_common/spi/spi.cpp:
  stm32_spiinitialize() → spi_bus_configgpio_cs(该 bus) → px4_arch_configgpio(devices[i].cs_gpio)
  stm32_spixselect()    → devid 匹配时 stm32_gpiowrite(cs_gpio, !selected)
现场：GPIOB_MODER PB4=01（输出）、GPIOB_ODR bit4=1（CS 空闲高）；
      我手工拉低/拉高 CS 时 RX 数据随之变化 ⇒ 这条线确实在受控。
⇒ CS 不需要额外进 PX4_GPIO_INIT_LIST，由上面这套机制自动配置（现状正确）。
```

### Q7 · DRDY（PD6）会不会跟别的东西撞？

**没有撞，但现场 PD6 是“未配置”（模拟态）—— 这是 probe 失败的后果，不是原因。**

```text
现场：GPIOD_MODER PD6 = 11（analog，即 H7 的复位默认值）→ 说明没人配过它
原因：DRDY 的配置发生在 probe 成功之后（ICM42688P::init() → SPI::init() 里先 probe；
      DataReadyInterruptDisable/Enable 那套是之后 Configure 阶段的事）→ probe 挂了就没走到
占用检查：board.h 里 PD6 只出现在 GYRO_INT1；
      USART2 的 RX 用的是 GPIO_USART2_RX_1 = PA3（不是 PD6 那档），PD5 是 TX；
      defconfig 里 USART2 虽 enable，但现场 PA3/PD5 MODER 仍是模拟 ⇒ 没被别的驱动抢走
⇒ 结论：PD6 无冲突。等换了好芯片、probe 过了，驱动会自己把它配成中断输入。
```

### Q8 · 用 ST-Link 读寄存器（已做，见第二节）

已读：`SPI1 CR1/CFG1/CFG2/SR`、`GPIOB MODER/AFR/ODR`、`GPIOA MODER/AFR`、`GPIOD MODER/AFR`、
`RCC CR/D2CCIP1R/PLL2DIVR/APB2ENR`。**并在只读之外，另做了三组“可回退”的写操作来定位根因**
（写 SPI1 的 CR1/CFG1 以发事务、写 GPIOB BSRR 控制 CS、写芯片的 0x75/0x76 做写回读）——
见第八节的“后悔药”。

---

## 五、修复方案

### 5.1 软件侧：**没有可修的**（不是“暂不修”，是“改软件救不了”）

理由：调试器绕过 PX4、按驱动的时序直接跟芯片说话，同样拿不到 `0x47`；
而且这颗芯片连 `0x75` 的“只读 WHO_AM_I”属性都不具备。
**越是改固件（换频率、换模式、换 CS、重试），越能确认这颗器件不实现 ICM-42688-P 的寄存器接口。**

### 5.2 硬件侧：照这个顺序查/换（人来做，见交接文档的清单）

```text
1) 量 U5 供电（万用表，上电，黑笔 GND）：pin5 VDDIO 和 pin8 VDD 都应是 3.3V
   （原理图要求都接 3.3V_H7；用户此前只确认过 pin5/pin12~14 的图面连法）
2) 断电量通断：U5 pin1↔PA6、pin13↔PB3、pin14↔PD7、pin12↔PB4、pin4↔PD6（应蜂鸣）
3) 放大看焊接：U5 是 2.5×3mm 14 脚 LGA（0.4mm 间距），优先看 pin1 的 SDO、
   pin8 的 VDD、pin12 的 CS、pin13 的 SCLK 有没有虚焊；确认 **pin1 圆点方向**没贴反
4) 换一颗**渠道可靠**的 ICM-42688-P（这类器件市场上重标/翻新很多；本板这颗的表现
   就是“SPI 通、寄存器接口不对”的典型），换完直接再跑一次
     icm42688p -s -b 1 -R 0 -d start
   期望打印 "icm42688p #0 on SPI bus 1"；否则把 -d 打出来的 WHO_AM_I 值发回来
5) 若换了正品仍读不到 0x47，再回到软件侧（那时才值得怀疑速度/走线，可用
   `icm42688p -s -b 1 -R 0 -f 1000 -m 0 start` 之类降速/换模式试）
```

### 5.3 若软件侧需要留个“诊断入口”（可选，没做）

不建议现在改任何板级代码：`-d`（打印 WHO_AM_I）和 `-f`（改总线频率）都是现成 CLI，够用。

---

## 六、负结果（试过 / 不通 / 已排除，别再花时间）

| # | 曾经怀疑 | 结论 | 依据 |
|---|---|---|---|
| N-01 | JTAG 占着 PB3/PB4 | **❌ 排除** | stm32h7 Kconfig 无 JTAG 项；寄存器显示 PB3=AF5/PB4=输出；PIX6 同样接法在跑 |
| N-02 | 引脚定义写错 | **❌ 排除** | pinmap 宏逐个核对：SCK_2=PB3/AF5、MISO_1=PA6/AF5、MOSI_3=PD7/AF5，与 board.h 注释一致 |
| N-03 | 原理图接错（含 VDD/VDDIO/RESV/FSYNC） | **❌ 排除** | 渲染成图逐脚看：pin8 VDD 也接了 3.3V_H7（+C38），FSYNC/RESV 都接 GND |
| N-04 | 25MHz PLL/PLL2 算错导致 SPI1 无时钟 | **❌ 排除** | RCC：HSE ready、PLL2 on+ready、SPI123SEL=PLL2、APB2ENR.SPI1EN=1、SCK 实测 24MHz |
| N-05 | SPI 模式/CPOL/CPHA 不对 | **❌ 排除** | CFG2 = MODE 3；datasheet 9.6 明确 MODE0/3 都支持 |
| N-06 | CS 没配成输出 / 没被拉低 | **❌ 排除** | MODER=输出、ODR=1；手工拉低后 RX 随命令变化 |
| N-07 | `-b 1` 不是 SPI1 | **❌ 排除** | CLI 帮助 + 各板用法 + `initSPIBus(SPI::Bus::SPI1)` |
| N-08 | PD6/DRDY 被别的外设占了 | **❌ 排除** | 无人占用；现场是模拟态只是因为 probe 没成功 |
| N-09 | 24MHz 太快 / 走线不行 | **❌ 排除** | 降到 0.75MHz 结果一样（0x00）⇒ 与速率无关 |
| N-10 | 从机没接 / MISO 断了 | **❌ 排除** | 不读命令时 MISO 恒 1，一发读命令从机就把线拉下来；且写/回读全能对上 |
| N-11 | 芯片是“死片” | **❌ 排除（但更有意思）** | 写进去能读回来、`0x11` 的值会自己变化 ⇒ 硅片活着、SPI 从机在跑 |
| N-12 | 芯片复位后 bank 不对（真芯片 bank 未知） | ❌ 排除 | 写 `0x76`=0..7 逐个切、写 `0x11=0x01` 软复位，`0x75` 恒 0x00；且本芯片 0x76 不是 3bit bank 寄存器 |

> ★ 特别注明 **N-13（我自己的弯路）**：第一次手工事务我把“写 bank 选择”和“读 WHO_AM_I”
> 放在**同一个 CS 低电平窗口**里（中间没抬 CS）。对 ICM 这类芯片，连续字节会被当成
> **一笔 4 字节 burst 写**（自动地址递增），根本不会产生“读”，从机全程不驱动 SDO ——
> 于是读到全 1，差点误判成“芯片没接”。**教训：SPI 事务之间必须抬 CS；读某个寄存器时
> 地址帧与数据帧要同处一次 CS 低电平内，但不同事务之间必须断开。**

> ★ 另一个坑 **N-14**：用 `mdw/mww`（32 位）访问 H7 的 `TXDR/RXDR` 会**一次搬 4 帧**
> （FIFO 打包）。NuttX 用 `spi_putreg8/spi_getreg8`（**字节**访问）正是为了避免这个。
> 想复刻 NuttX 的时序，必须用 `mwb/mdb`。

---

## 七、我动过的东西 / 后悔药

```text
只动过 SPI1 的 CR1(0x40013000)、CFG1(0x40013008)、TXDR/RXDR，以及 GPIOB 的 BSRR（手动 CS）。
· CFG1 已还原为驱动留下的 0x10070007；CFG2 全程没改；CS 全程还原为高（GPIOB_ODR=0x0c10 ✅）
· CR1 现值 0x00001201（比原始 0x00001001 多了 CSTART=1）。该位由硬件在传输结束时清、
  或下次驱动把 SPE 翻转时清（NuttX 每条 DMA 路径都会 spi_enable(false)→(true)），
  **对功能无影响**；要 100% 复原现场，给板子断电重上电即可（顺带也会复位那颗 IMU）。
· 对那颗 IMU 写过：0x76（bank 选择）、0x77/0x78（第一次弯路误写的 0xF5/0x00）、
  0x11（软复位）、0x75（写回读测试）。这些对真 ICM-42688-P 都是无害操作
  （0x77/0x78 未定义、0x11 写 1 就是软复位、0x75 是只读）；
  对**这颗**芯片它们是普通读写寄存器，掉电即复原。**没有任何 flash/option byte 被写。**
· 没有跑任何构建、没有烧写固件、没有改 PX4 仓库里的任何文件。
```

---

## 八、复现命令（脚本都在 `work/spi-debug/`）

```bash
# 0) 先确保没有别的 openocd 占着
pkill -x openocd

# 1) 只读寄存器现场
sudo openocd -f interface/stlink.cfg -f target/stm32h7x.cfg \
  -c "init" -c "halt" -c "mdw 0x40013000 4" -c "mdw 0x58020400 2" -c "mdw 0x58020420" \
  -c "resume" -c "shutdown"
# （脚本版：work/spi-debug/regdump.cfg，注意：脚本(-f)模式下 mdw 不会打印，要用 -c）

# 2) 手工复刻驱动 probe 事务（字节访问 + 每笔事务独立 CS 窗口）
sudo bash work/spi-debug/spi_probe3.sh      # 读到 0x00
# 3) 写→回读（证明写/读通路）
sudo bash work/spi-debug/banktest.sh        # 0x76/0x75 都是普通读写寄存器
# 4) 全寄存器扫描
sudo bash work/spi-debug/regscan.sh
# 5) 软复位 + bank 逐一切换
sudo bash work/spi-debug/softreset.sh
```

---

## 九、待确认 / 我不确定的

```text
❓ 这颗芯片到底是什么：我没能识别出它的型号（不是 ICM-42688-P，也不是 ICM-42605/42670-P
   那种“同族但 WHO_AM_I 值不同”的情况——它在 0x75 上连只读 ID 都没有）。
   最可能：翻新/重标器件，或运输/焊接损伤过的 die。**不排除**是别的型号被贴错。
   要做的话：把它 128 个寄存器里可写的地址扫一遍当“指纹”，再逐个查候选 datasheet ——
   但这不影响处置动作（换件），所以我没继续。
❓ 我在调试器上做的这些写操作，理论上会不会是“我把芯片搞坏了”？
   时间线可排除：用户最早那次 `icm42688p start` 失败发生在**我碰芯片之前**；
   驱动 probe 自己也会写 0x76=0（bank0，无害）。我全部的写操作都在那之后。
❓ U5 的焊接/贴装我没法隔着屏幕判断 —— 需要万用表和放大镜（清单见 5.2）。
```
