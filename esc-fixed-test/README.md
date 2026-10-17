# esc-fixed-test —— A 相下管固定状态测试

**目的**：完全脱离 AM32 的状态机/EEPROM/DShot 输入，把 MCU 的六路门极输入钉死在一个固定状态，
单独验证 **A 相下管** 这一路硬件到底通不通：

```
PB15(A_LIN) → U2 pin1(LIN1) → U2 pin11(LO1) → R23 → Q2 栅极 → MOTORA
```

## 输出状态（烧进去之后）

| 引脚 | 板上网络 | 状态 |
|---|---|---|
| **PB15** (U1 pin15) | A_LIN → U2 LIN1 | **约 1 kHz 方波**（用 `A_TOGGLE_HZ=0` 编译则常高） |
| PB0 (U1 pin14) | B_LIN → U2 LIN2 | 低（**B 相下管完全不通**） |
| PA7 (U1 pin13) | C_LIN → U2 LIN3 | 低 |
| PA10 (U1 pin19) | A_HIN → U2 HIN1 | 低 ┐ |
| PA9 (U1 pin18) | B_HIN → U2 HIN2 | 低 ├ 上管全关，避免直通 |
| PA8 (U1 pin16) | C_HIN → U2 HIN3 | 低 ┘ |

## ⚠️ 前提：必须给板子加电（VBAT）

FD6288Q 的 VCC(6.5V) 由板载 buck 从 VIN 产生。只靠 ST-Link 的 3.3V 供电时，
驱动芯片没电，**LO/栅极一律没有输出**（而且未上电芯片的输入脚 ESD 钳位会把 MCU 引脚拉低）。
所以量栅极之前先确认 **6.5V 和 3.3V 都在**。

## 测点与预期

示波器地夹夹板子 GND（下管这一路是接地参考的，安全）。

| # | 测点 | 预期 |
|---|---|---|
| 1 | U1 pin15 (PB15) | 0 ↔ 3.3V 方波 |
| 2 | U2 pin1 (LIN1) | 与①同相，0 ↔ 3.3V |
| 3 | U2 pin11 (LO1) | 与①同相，0 ↔ **6.5V** |
| 4 | R23 靠 Q2 那端 / Q2 pin4（栅极） | 与①同相，0 ↔ 6.5V |
| 5 | Q2 漏极 (MOTORA) | ①为高时被拉到 ≈0V |
| 6 | U2 pin2 (LIN2, B_LIN) / pin10 (LO2) | **一直低，没有波** ← B 相确认不通 |

**判据**：①→④ 在哪一级开始没有方波，问题就在那一级
（MCU 焊点 / A_LIN 走线 / U2 通道1 低侧驱动 / R23 栅极电阻 / Q2）。

## 用法

```bash
./build.sh            # 编译两个版本
./flash.sh            # 烧 1kHz 翻转版并运行（示波器用）
./flash.sh static     # 烧常通版（万用表量通断用）
./restore_am32.sh     # 测完恢复 AM32
```

需要 sudo（USB 设备节点属 root）。本机 openocd 已安装（`apt install openocd`）。

## 文件

- `test_low_side.c` —— 固件源码（直接寄存器操作，不依赖任何库，复位后跑 HSI 16MHz）
- `app.ld` —— 链接脚本，固件放 0x08001000（AM32 的 app 槽）
- `test_a_low_1khz.bin` / `test_a_low_static.bin` —— 编译产物
- `backup_before_test.bin` —— **烧测试固件之前的整片 128KB flash 备份**

寄存器偏移来源：`AM32-rm2027/Mcu/g071/Drivers/CMSIS/Device/ST/STM32G0xx/Include/stm32g071xx.h`
（`RCC_IOPENR=0x40021034`，`GPIOB=0x50000400`，MODER=0x00 / IDR=0x10 / ODR=0x14 / BSRR=0x18 / BRR=0x28）
