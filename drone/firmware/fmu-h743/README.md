# fmu-h743 · 自研飞控板 PX4 移植

> 状态：**骨架 / 未完成** — 2026-09-28
> 位置：`~/桌面/RM2027/PX4-Autopilot/boards/rm2027/fmu-h743/`（分支 `board/fmu-h743`）

## 一、这块板子是什么

```text
主控    STM32H743VIT6     ← 跑 PX4
协处理  STM32F103C8T6     ← 伴生 MCU（我们自己的逻辑），经 USART2 连主控
IMU     ICM-42688-P        SPI1
磁罗盘  IST8310            IIC4
气压计  SPA06-003          IIC2
外置陀螺 H104              CAN1 / USART1
收发器  SIT3051TK ×2       CAN1 / CAN2
```

原理图：`references/硬件手册/FMU_飞控板_原理图_2026-09-24.pdf`（V1.0，更新 2026-09-21）

## 二、为什么叫 fmu-h743（暂定名）

团队还没给板子定英文名。当前用 `fmu-h743` 占位，
**改名的成本极低**（目录名 + `CONFIG_ARCH_BOARD` 字符串），
但改名时必须同步本目录所有文档里的引用。见 `开发日志/03-决策记录.md` D-01。

## 三、迁移进度

| 文件 | 状态 | 依据 |
|---|---|---|
| `README.md` | ✅ | — |
| `引脚映射-H743.md` | ✅ 完成 | 原理图图面 + datasheet AF 交叉校验（用户人工复核 100% 正确） |
| `引脚映射-F103.md` | ✅ 完成 | 同上 |
| `init/rc.board_sensors` | ✅ 完成 | 三颗传感器启动行 |
| `init/rc.board_defaults` | ✅ 完成 | 电池参数故意留空（见 Q-02b） |
| `init/rc.board_extras` | ✅ 完成 | 去掉模板的 atxxxx OSD |
| `src/board_config.h` | ✅ 完成 | 4 路 ESC 电流 ADC；无 USB/SD/蜂鸣器 |
| `src/spi.cpp` `i2c.cpp` | ✅ 完成 | SPI1=ICM-42688；I2C2+I2C4 |
| `src/timer_config.cpp` | ✅ 完成 | TIM1_CH1..4（DShot） |
| `nuttx-config/` | ✅ 完成 | **HSE 25MHz PLL 手算**（见 D-08） |
| `default.px4board` | ✅ 完成 | 只剩 ICM42688P + IST8310 + SPA06 |
| `firmware.prototype` | ✅ 完成 | board_id = **2027** |
| **编译** | ✅ **通过** | `.px4` 1.45MB，Flash 77% |

### ✅ 编译产物

```text
~/桌面/RM2027/PX4-Autopilot/build/rm2027_fmu-h743_default/
  rm2027_fmu-h743_default.elf   34.6 MB（含调试符号）
  rm2027_fmu-h743_default.bin    1.45 MB
  rm2027_fmu-h743_default.px4    1.45 MB   ← QGC/上传工具烧这个
```

命令：`make rm2027_fmu-h743_default`

> 📖 完整移植过程、7 个编译错误的修法、上板前 6 项确认清单 →
> [`开发日志/05-板级移植实录.md`](开发日志/05-板级移植实录.md)

## 四、✅ 引脚号已解决（2026-09-28）

**结论：不用向硬件组要网表 —— 原理图图上本来就有，渲染成图读出来即可。**

| | |
|---|---|
| 方法 | `pdftoppm` 渲染成图**看着读**，+ 用「**引脚号**」当锚按 y 关联网络名 |
| 交叉校验 | 48 个信号引脚**逐条**对照 datasheet Alternate function 表 → **100% 命中** |
| 产出 | [`引脚映射-H743.md`](引脚映射-H743.md) |
| 可复现步骤 | `开发日志/02-原理图信息提取.md` 第 3.3 节 |

> ⚠️ 中途我曾得出错误结论「引脚无法从 PDF 提取，要向硬件组要网表」——
> 原因是**只做坐标匹配、没有看图**。用户提醒后已推翻，教训留在开发日志里。

**仍然需要硬件组确认的**（不影响开工，但影响正确性）：

```text
[ ] 1. 图面批注是否落实？
       已查：PA8(67)=TIM1_CH1 接了 ✅ ；PA7(31)=✗ 未连接 ❌
             USART1(PB6/PA10) 仍然接了 →「砍 USART1」没执行
       → 即「互补的 CH1N 没引出来」
[ ] 2. 电池电压采样在哪？
       全图只有 4 路 ESC 电流（PC0/PC1/PC4/PC5），没找到 VBAT 分压
       → 影响 PX4 电池模块是否启用
```

## 五、已经可靠的部分（不需要引脚号）

外设级分配来自**原理图自带的「资源汇总」表**（硬件组自己写的），可信度高：

```text
SPI1  → ICM-42688-P (GYRO)      IIC4 → IST8310 (Mag)
IIC2  → SPA06-003 (Baro)        UART5 → DBUS (遥控器)
USART2 → F103 (伴生 MCU)         CAN1 → H104 (外置陀螺)
```

详见 `资源与引脚映射.md`。
