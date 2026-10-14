# 资料 · HI04 外置 UART IMU 接 PX4 调研

> 2026-09 调研 · 背景：评估"超核/成品 UART IMU（HI04 类）能否接自研飞控的 PX4"。
> 结论先行：**能写驱动接入（PX4 支持自定义串口传感器驱动），但 PX4 的 IMU 时间戳架构不为"外置 UART IMU"优化；求稳用 SPI 裸 IMU。**

---

## 一、HI04 是什么（Hipnuc）

- **Hipnuc（新诺）通用型 IMU/VRU/AHRS 模块**，数据手册 HI04_Data_Sheet1.4_CN.pdf（已读）
- 接口：**UART**（最高 921600）/ 部分型号 CAN；**无 SPI/I2C**
- 输出：**能出原始 6 轴**（gyr_x/y/z + acc_x/y/z，CSV 说明确认），也能出姿态（EKF 融合 roll/pitch/yaw/四元数）
- 频率：传感器数据 **1~1000Hz** 可选（1000Hz 姿态、原始数据按型号）
- 出厂标定：全温补、陀螺零偏 1.6°/h（R2）、加计 18ug
- 型号：HI04M0/M3/R2/R3；MI0=UART、MI1=UART+CAN
- 同步：IO1=SYNC_IN(输入/PPS)、IO2=SYNC_OUT(输出/Data Ready)、IO6=SOUT_DIV(分频触发雷达/相机)
- 用途定位：精密仪器/平台稳定/低速无人载具的"高品质成品 IMU"

## 二、PX4 对 IMU 的架构要求（为什么外置 UART IMU 特殊）

PX4 的 IMU 设计 = **SPI/I2C 裸 6 轴芯片 + 硬件时间戳**：
1. 要**原始角速度/加速度**（不是成品姿态）——PX4 用 EKF2 自己融合
2. 要 **SPI/I2C**（采样完成瞬间读 = 硬件精确打 hrt 时间戳）
3. PX4 官方支持列表全是裸芯片（MPU6500/ICM42688/BMI088 等）

**外置 UART IMU 的问题**：时间戳 = "收到时刻"，不是"采样时刻"，有传输延迟/抖动 → EKF 对 IMU 时间戳敏感 → 姿态漂。这是 PX4 不用 UART IMU 的根本原因（源码看 tfmini/GPS 等 UART 传感器都是"read 后打收到时刻"）。

## 三、关键概念（hrt / DMA / EXTI Data Ready）

### hrt 时间戳
- hrt = PX4 高精度单调时钟（µs），`hrt_absolute_time()`
- IMU 每帧要盖"采样时刻"章；SPI 硬件同步准，UART 收到时刻不准

### UART read 底层
- NuttX 串口驱动默认**中断收字节进内核缓冲**（部分板配 DMA），`read()` 从缓冲取
- **DMA 触发 = UART RX 每字节**（硬件自动，初始化配好即挂机）；不用手动重使能的是 **circular 循环模式**（normal 单次要 DMA 完成中断重使能）

### Data Ready（HI04 IO2）
- 每帧就绪拉脉冲（与帧率同频，如 1000Hz）→ 接 MCU EXTI → ISR 打 hrt 戳（帧就绪时刻，比 read 完成时刻准）
- 时间戳 = 靠"EXTI 打戳 + 数据线程 read 配对"，不是数据自带

### 最优读取方案
```
IO2 Data Ready → EXTI ISR：打 hrt 戳（帧就绪瞬间，准）
UART → DMA(circular) 收数据（不占 CPU）
驱动线程：read 缓冲找帧 + 配对 ISR 戳 → updateFIFO(sensor_gyro/accel)
```
原则：**时间戳在就绪瞬间打（早），数据慢慢取（DMA）没关系**。

## 四、PX4 支持性的查证结论（源码 + 外部）

| 层面 | 支持？ | 证据 |
|------|--------|------|
| **PX4 自定义串口传感器驱动** | ✅ 官方支持 | CSDN《PX4 二次开发：从零构建自定义串口传感器驱动》：串口配置→采集→解析→发布 uORB，照 tfmini/GPS 改 |
| 用 UART 数据发布 sensor_gyro/sensor_accel | ⚠️ uORB 层允许 | 源码 `src/examples/fake_imu`（217 行，`updateFIFO` 注入传感器）|
| 开箱即用接 HI04 当飞控主 IMU | ❌ 无现成 | PX4 无 HI04 驱动 |
| 精准时间戳（Data Ready EXTI）| ⚠️ 要自己造 | PX4 应用层不碰 NuttX DMA/EXTI，要深挖 NuttX 或 PX4 模块注册 GPIO 中断 |

**核心结论**：
1. **"PX4 支持你写串口驱动"** = 官方支持，有教程，照 tfmini 改就能读 HI04
2. **但要当飞控主 IMU**：时间戳/稳定性要自己打磨（PX4 不帮你），没成熟先例，是 DIY 路线
3. **HI04 接 PX4 最优做法**：read 数据 + IO2 Data Ready EXTI ISR 打戳配对（比纯 read 准）；用前要把 IO2 经 CHCenter GUI 配置成 SYNC_OUT（PMUX2）
4. **权衡**：求比赛稳 → SPI 裸 IMU（MPU6500/ICM42688，PX4 原生驱动、硬件时间戳免费）；看重 HI04 出厂标定精度/不想自己校准 → 可走 DIY 驱动

## 五、HI04 接入 PX4 的工程要点（如果走）

1. **PCB**：HI04 UART(RX/TX)+IO2+VCC/GND 全引出，UART 加 0 欧/跳线断 MCU（配置用）
2. **配置**：CHCenter GUI 或串口指令，把 IO2 配成 SYNC_OUT(PMUX2)，掉电保存
3. **接线**：HI04 UART→MCU UART；IO2→MCU EXTI；3.3V 电平
4. **驱动**：照 tfmini 模板写 UART 驱动 + 注册 GPIO 中断打戳 + 戳队列配对 + updateFIFO
5. **IO2 不是"接上就行"**：PMUX 可配引脚，先配置成 SYNC_OUT 才有 Data Ready

## 六、相关链接/参考
- CSDN《PX4 二次开发实战指南：从零构建自定义串口传感器驱动》（关键词搜索可见，核心=照 tfmini 改）
- PX4 源码：`src/examples/fake_imu`（注入传感器模板）、`src/drivers/distance_sensor/tfmini`（UART 驱动模板）、`src/drivers/imu/`（裸 IMU）
- HI04 数据手册/资料：微信收到（HI04.zip + Data_Sheet）

## 七、待决策
- [ ] 是否走"HI04 + 自写 PX4 驱动"（接受 DIY 时间戳）vs "SPI 裸 IMU"（PX4 原生）
- [ ] 若走 HI04：向厂商要"编程手册"确认 IO2 配置指令；写驱动前先拿 CHCenter 配好 IO2
