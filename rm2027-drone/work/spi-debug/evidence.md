# 原始证据 · 2026-09-29 · IMU(ICM-42688-P) 软件侧排查

全部由 ST-Link + openocd 直接读/写芯片寄存器得到。脚本见同目录 `*.sh`。
**注意**：脚本模式(-f)下 openocd 的 mdw/mdb 不会打印，必须用 `-c "mdw …"` 传命令。

## 1. 只读现场（regdump.cfg 改成 -c 形式执行）

```
### DBGMCU_IDCODE
0x5c001000: 20036450                     ← DEV_ID 0x450 = STM32H743/753

### SPI1 CR1 CR2 CFG1 CFG2
0x40013000: 00001001 00000000 10070007 87400000
           ↑CR1     ↑CR2     ↑CFG1    ↑CFG2
### SPI1 IER SR IFCR TXDR
0x40013010: 00000000 00001802 00000000 00000000
### SPI1 RXDR
0x40013030: 00000000

### RCC CR CFGR D1CFGR D2CFGR
0x58024400: 3f03c035 400006f8 0000014d 20000083
### RCC D2CCIP1R D2CCIP2R
0x58024450: 00011000 00202000
### RCC PLL2DIVR
0x58024438: 0404085f
### RCC APB2ENR / AHB4ENR / AHB1ENR / AHB2ENR
0x580244f0: 00001031        ← bit12 = SPI1EN
0x580244e0: 1120009f
0x580244d8: 00000023
0x580244dc: 00000000

### GPIOB MODER OTYPER OSPEEDR PUPDR IDR ODR AFRL AFRH
0x58020400: fa0ffdbf 00000000 0a000000 00000000 00003c18 00000c10 00000000 00000000
0x58020420: 00005000 00990000
### GPIOA MODER IDR AFRL
0x58020000: abfeefff
0x58020010: 00004040
0x58020020: 05000000
### GPIOD MODER ODR AFRL
0x58020c00: f05abfea
0x58020c14: 00003c00
0x58020c20: 50000899
```

解码（NuttX 位定义 hardware/stm32h7x3xx_spi.h / rcc.h）：
- CFG1 0x10070007：DSIZE[3:0]=7（8bit）、**MBR[30:28]=1 → f/4 = 96/4 = 24MHz**
- CFG2 0x87400000：bit22 MASTER=1、bit24 CPHA=1、bit25 CPOL=1 → **MODE 3**、bit26 SSM=1、bit31 AFCNTR=1
- CR1 0x1001：SPE=1、SSI=1
- D2CCIP1R：SPI123SEL（bits[14:12]）=1 → PLL2 ⇒ SPI1 内核时钟 96MHz
- PLL2DIVR 0x0404085f：N2=95（×96）、P2 域=4，且 `RCC_PLL2DIVR_P2(x)=((x)-1)<<9` ⇒ /5 → 480/5=96MHz
- GPIOB_MODER：PB3[7:6]=10(AF)、PB4[9:8]=01(输出)；AFRL PB3[15:12]=5(AF5)
- GPIOA_MODER：PA6[13:12]=10(AF)；AFRL PA6[27:24]=5(AF5)
- GPIOD_MODER：PD7[15:14]=10(AF)、**PD6[13:12]=11(analog = 复位默认，没人配过)**；AFRL PD7[31:28]=5(AF5)
- GPIOB_ODR bit4=1 ⇒ CS 空闲高

## 2. 手工复刻驱动 probe()（v1 有 framing bug，v2/v3 修正）

### v1（错）：写 bank 与读 WHOAMI 放在同一个 CS 低窗口 → 被当成一笔 4 字节 burst 写
```
A1..A4 全部 0x40013030: ffffffff     ← 写事务中从机不驱动 SDO，全 1（会误导！）
```

### v3（对：字节访问 mwb/mdb + 每笔事务独立 CS 窗口）
```
==== 清空 RX FIFO ====   mdb RX ×4 = 00 00 00 00 ; SR=00001802
==== T1 WRITE REG_BANK_SEL(0x76)=0 ====
  SR=00003807  RX=ff
  SR=00003807  RX=ff
  SR=00001802                ← CS 抬高后回空闲
==== T2 READ WHO_AM_I(0x75) → 数据帧 = 00（应 0x47）====
  SR=00003807  RX=ff          ← 地址帧（从机不驱动）
  SR=00003807  RX=00          ← ★ 数据帧 = 0x00
==== T3 READ reg0x00 ====
  RX=ff / RX=00
==== T4 再读 0x75 ====
  RX=ff / RX=00               ← 可重复
```
SR=0x3807 解：RXP(0)=1、TXP(1)=1、DXP(2)=1、SUSP(11)=1、TXC(12)=1、RXPLVL(13)=1
⇒ 全双工帧正常完成 ⇒ **主机的 SCK/MOSI 在动、从机把 MISO 拉下来了**。

### v4：对照实验（无写地址 vs 有写地址）
```
A(burst 0x75, dummy=0x00)：RX = ff, 00,00,00,00,00,00
   地址帧后 CS 仍低时 PA6 电平(IDR bit6)：0x58020010=00004040 → 高
   第一帧后：0x58020010=00004000 → 低
B(同样读 0x75, dummy=0xFF)：RX = ff, 00,00,00,00,00,00    ← 数据不跟 MOSI 变
C(不发读地址, dummy 00/FF 交替)：RX = ff, ff, ff           ← 无读命令时线恒高
⇒ 排除“浮空/串扰假象”：线的行为由“是否发过读命令”决定。
```

### 降速对照（CFG1.MBR 1→6，24MHz→0.75MHz）
```
0x40013008: 60070007
读 0x75 → 00 ；读 0x76 → 00      ← 与速率无关
```

## 3. 写→回读（证明写通路/读通路/地址译码都正常）

```
写 0x76=0xA5 → 读 0x76 = a5      ✅（真芯片此处是 3bit REG_BANK_SEL，应回 05）
写 0x76=0x5A → 读 0x76 = 5a      ✅（真芯片应回 02）
写 0x75=0x5A → 读 0x75 = 5a      ☠️ 真芯片 0x75 = WHO_AM_I，访问属性 R（只读）！
写 0x75=0x00 → 读 0x75 = 00      ☠️
```

datasheet 提取文本 L3750：`75  117  WHO_AM_I  R  WHOAMI`

## 4. bank0 全寄存器扫描（只读，128 地址）

```
r00=00 r01=6a r02=11 r03=00 r04=00 r05=50 r06=00 r07=00
r08=80 r09=00 r0a=00 r0b=01 r0c=ff r0d=d2 r0e=00 r0f=2e
r10=08 r11=dd r12=00 r13=00 r14=00 r15=00 r16=00 r17=00
r18=e3 r19=14 r1a=58 r1b=00 r1c=00 r1d=07 r1e=ff r1f=40
r20..r39 = 00（r3a=08）
r40=a8 r41=02 r42=a9 r43=00 r44=46 r45=88 r46..r67=00
r68=05 r69..r6b=00 r6c=70 r6d..r73=00 r74=e7 r75=00 r76=00 r77..r7c=00 r7d=05 r7e=00 r7f=00
```
**128 个地址里没有任何一个返回 0x47 / 0x44 / 0x42 / 0x67。**
`r11` 会随时间变（0xdd → 0xda → 0xd6）⇒ 芯片内部有活动（不是死片）。

## 5. 逐 bank 切换 + 软复位

```
写 0x76=b (b=0..7) 后读 r75/r0b/r1d：
  bank0..bank7 全部 = r75=00, r0b=01, r1d=07     ← 完全不变 ⇒ 无 bank 机制在起作用
写 0x11=0x01（真芯片的 DEVICE_CONFIG.SOFT_RESET）后：
  r75=00, r0b=01, r1d=07, r11: da → d6           ← 没变出 0x47
```

## 6. 收尾现场

```
SPI1 CFG1 CFG2 = 10070007 87400000   ← 已还原
SPI1 CR1       = 00001201            ← 比原始 00001001 多 CSTART=1（无影响，见开发日志 06 第七节）
GPIOB ODR      = 00000c10            ← CS 已还原为高
PC = 0x080239d4（PX4 在跑）
```
