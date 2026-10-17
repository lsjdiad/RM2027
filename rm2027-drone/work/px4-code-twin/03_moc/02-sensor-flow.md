# 六类传感器的端到端信息流（本板 rm2027/fmu-h743）

> **视角**：程序运行时 —— 数据从哪块硅片进来，被谁读走，变成哪个 uORB 话题，谁在等它，最后喂给谁。
> **约定**：每个箭头都写清 **【发布者 → 话题 → 订阅者】**。行号基准 = `源码根（见 `tools/source-root.conf`）`（HEAD `3b5de24`，工作树干净）。
> **三层标注**：`[实测]` 有上板数据 / `[源码]` 有 file:line / `[推理]` 明说是推测。
> ⚠️ 本文所有行号已于交付前批量回验（见文末「自查记录」）。

### 缩写约定（本文在首次出现后使用短名，全路径如下，便于复核）

| 短名 | 全路径（相对 `源码根（见 `tools/source-root.conf`）`） |
|---|---|
| `spi.cpp` / `i2c.cpp` / `timer_config.cpp` | `boards/rm2027/fmu-h743/src/…` |
| `rc.board_sensors` / `rc.board_defaults` | `boards/rm2027/fmu-h743/init/…` |
| `default.px4board` | `boards/rm2027/fmu-h743/default.px4board` |
| `module_params.c` / `serial_params.c` | `build/rm2027_fmu-h743_default/generated_params/…`（★ 构建产物，行号会随重新构建漂移） |
| `px4_boardconfig.h` | `build/rm2027_fmu-h743_default/px4_boardconfig.h`（构建产物） |
| `rcS` / `rc.mc_apps` | `ROMFS/px4fmu_common/init.d/…` |
| `sensors.cpp` / `sensors.hpp` / `Vehicle*.cpp/hpp` | `src/modules/sensors/…` |
| `DShot.cpp` / `DShot.h` | `src/drivers/dshot/…` |
| `mixer_module.cpp/hpp` / `Function*.hpp` / `output_functions.yaml` | `src/lib/mixer_module/…` |
| `PX4Accelerometer.*` / `PX4Gyroscope.*` / `PX4Magnetometer.*` / `PX4Barometer.*` | `src/lib/drivers/{accelerometer,gyroscope,magnetometer,barometer}/…` |
| `WorkQueueManager.cpp` | `platforms/common/px4_work_queue/WorkQueueManager.cpp` |
| `i2c_spi_buses.cpp` / `i2c_spi_buses.h` | `platforms/common/i2c_spi_buses.cpp` / `platforms/common/include/px4_platform_common/i2c_spi_buses.h` |
| `drv_dshot.h` / `drv_sensor.h` | `src/drivers/…` |
| `logged_topics.cpp` | `src/modules/logger/logged_topics.cpp` |
| `rc_update.cpp/.h` | `src/modules/rc_update/…` |
| `Commander.hpp/.cpp` | `src/modules/commander/…` |
| `ControlAllocator.*` | `src/modules/control_allocator/…` |
| `EKF2.*` / `EKF2Selector.cpp` | `src/modules/ekf2/…` |
| `HIGHRES_IMU.hpp` / `ATTITUDE.hpp` / `RC_CHANNELS.hpp` | `src/modules/mavlink/streams/…` |
| `mavlink_receiver.cpp/.h` | `src/modules/mavlink/…` |
| `HIP2:` / `HI04:` / `HXY:` / `IST:` | 硬件手册行号，索引见 `work/PX4改造-索引与纪律.md` §2 |

---

## 0. 先看全局：六条流在哪汇合

```
 ┌───────────────────────── 硬件 ──────────────────────────┐
 │  HXY42688P(SPI1,CS=PB4)      H104 HI04M0(USART1/ttyS0)  │
 │  IST8310(I2C4,0x0C)          SPA06(I2C2,0x77)           │
 │  4×ESC DShot(TIM1 CH1..4)    RC 串口(**未配置**)         │
 └───────────┬──────────────────────────┬──────────────────┘
             │ 各驱动在自己的工作队列里轮询
 ┌───────────▼──────────────────────────▼──────────────────┐
 │ 原始话题（每个器件一条实例）                              │
 │   sensor_accel / sensor_gyro   ← hxy42688p、h104_imu     │
 │   sensor_mag                   ← ist8310                 │
 │   sensor_baro                  ← spa06                   │
 │   input_rc                     ← rc_input（本板没配串口） │
 └───────────┬──────────────────────────┬──────────────────┘
             │ ★ sensors 模块订阅（唯一消费者）
 ┌───────────▼──────────────────────────▼──────────────────┐
 │ sensors 模块（sensors.cpp:601-607）                       │
 │   sensor_combined            投票后的原始量（EKF2 用）     │
 │   vehicle_imu                每对(accel,gyro)一条，含积分  │
 │   vehicle_imu_status         误差计数（投票器的食料）      │
 │   vehicle_acceleration       滤波后的加速度                │
 │   vehicle_angular_velocity   滤波后的角速率（控制环用）     │
 │   vehicle_air_data           气压高度源                   │
 │   vehicle_magnetometer       磁罗盘（含硬铁/软铁修正）      │
 └───┬──────────────┬───────────────────┬──────────────────┘
     │              │                   │
 ┌───▼────────┐ ┌───▼──────────────┐ ┌──▼─────────────────┐
 │ EKF2       │ │ mc_rate_control  │ │ mavlink/logger     │
 │ (INS0)     │ │ 角速率环 (1kHz)   │ │ HIGHRES_IMU 等流    │
 │ vehicle_attitude               │ └────────────────────┘
 │ vehicle_local_position         │
 └───┬────────┘ └───┬──────────────┘
     │              │ vehicle_torque_setpoint / vehicle_thrust_setpoint
     │              ▼
     │        ┌─────────────────────┐
     │        │ control_allocator   │← CA_ROTOR_* 几何
     │        │ → actuator_motors   │
     │        └───┬─────────────────┘
     │            ▼
     │        ┌─────────────────────┐
     │        │ dshot / pwm_out     │← PWM_MAIN_FUNC1..4 = 101..104
     │        │ (MixingOutput)      │← PWM_MAIN_TIM0 = -3/-4
     │        └───┬─────────────────┘
     │            ▼  up_dshot_motor_command → DMA → TIM1
     └──────► 4 路 ESC：PA8 / PE11 / PE13 / PE14

 遥控支线：
   rc_input(未配) / MAVLink MANUAL_CONTROL
        → manual_control_input ─┐
   rc_update → rc_channels       ├→ manual_control 模块 → manual_control_setpoint
        → manual_control_switches┘         ├→ commander（解锁开关）
                                           ├→ mc_pos_control / mc_att_control / FMM
                                           └→ rc_update 回读（映射 RC_MAP_*）
```

**一句话**：**六条流全部在 `sensors` 模块被"归一化"，然后分成三路 —— 估计（EKF2）、控制（mc_*）、输出（control_allocator→DShot）。**

---

## 1. 流①：电机（唯一一条"从软件算到 MOSFET 栅极"的链）

这是**唯一一条反向流**：别的流是"硬件→软件"，这条是"软件→硬件"。

### 1.1 链路（每一跳都写清发布/订阅）

| # | 控制在哪（工作队列） | 动作 | 发布者（file:line） | 话题 | 订阅者（file:line） |
|---|---|---|---|---|---|
| 1 | `wq:rate_ctrl`（**优先级 0**） | 角速率环算出力矩/推力 | **`mc_rate_control`** `.cpp:260 / :264`（话题名在 `MulticopterRateControl.cpp:51`；队列绑定 `:50`） | `vehicle_torque_setpoint` / `vehicle_thrust_setpoint` | `control_allocator`（[`ControlAllocator.hpp:201`](../02_code_twin/modules/control_allocator.md#^src-src-modules-control-allocator-ControlAllocator-hpp-201)） |
| 2 | `wq:rate_ctrl`（同一队列！） | 把力矩/推力分配到 4 个电机 | **`control_allocator`** [`ControlAllocator.cpp:757`](../02_code_twin/modules/control_allocator.md#^src-src-modules-control-allocator-ControlAllocator-cpp-757)（队列绑定 `:57`） | `actuator_motors` | **`dshot`/`pwm_out` 的 `FunctionMotors`**（[`FunctionMotors.hpp:52`](../02_code_twin/build/drivers-build.md#^src-src-lib-mixer-module-functions-FunctionMotors-hpp-52)） |
| 3 | `wq:hp_default`（优先级 -18） | 把归一化值映射成通道号 → DShot 帧 | **`MixingOutput::update()`** [`mixer_module.cpp:421`](../02_code_twin/build/drivers-build.md#^src-src-lib-mixer-module-mixer-module-cpp-421) | 内部：`_current_output_value[]` | `DShot::updateOutputs()`（[`DShot.cpp:125`](../02_code_twin/drivers/dshot.md#^src-src-drivers-dshot-DShot-cpp-125)） |
| 4 | `hp_default` | 打包成 DShot 位流 | `up_dshot_motor_command()`（声明 [`drv_dshot.h:116`](../02_code_twin/drivers/loose.md#^src-src-drivers-drv-dshot-h-116)）+ `up_dshot_trigger()`（[`drv_dshot.h:124`](../02_code_twin/drivers/loose.md#^src-src-drivers-drv-dshot-h-124)） | — | STM32 HAL 层（`platforms/nuttx/src/px4/stm/stm32_common/dshot/dshot.c`） |
| 5 | 硬件 | DMA 打 TIM1 CCR1..4 | — | — | **PA8 / PE11 / PE13 / PE14**（`boards/rm2027/fmu-h743/src/timer_config.cpp:57`） |

### 1.2 三个"必须同时成立"的开关

| 开关 | 本板缺省 | 出处 | 不配会怎样 |
|---|---|---|---|
| `PWM_MAIN_FUNC1..4` | **0 = Disabled** `[源码]`（[`build/rm2027_fmu-h743_default/generated_params/module_params.c:2243`](../02_code_twin/build/artifacts.md#^src-build-rm2027-fmu-h743-default-generated-params-module-params-c-2243) 等四行） | 功能号表 `src/lib/mixer_module/output_functions.yaml:5,10-12`（Motor: start 101, count 12） | **一路脉冲都不出**，哪怕解锁 |
| `PWM_MAIN_TIM0` | **400**（= PWM 400Hz，**不是 DShot**）`[源码]`（[`module_params.c:2164`](../02_code_twin/drivers/dshot.md#^src-build-rm2027-fmu-h743-default-generated-params-module-params-c-2164)） | 取值表 [`DShot.h:59`](../02_code_twin/drivers/dshot.md#^src-src-drivers-dshot-DShot-h-59)（-3=DSHOT600 / -4=DSHOT300 / -5=DSHOT150） | `dshot init` 返回 false（[`DShot.cpp:1126`](../02_code_twin/modules/control_allocator.md#^src-src-drivers-dshot-DShot-cpp-1126)：`if (dshot_timer_channels == 0) { ... return false; }`），`pwm_out` 接手出 PWM |
| `DSHOT_MOT_POL1..4` | 14 | 参数名拼接 [`DShot.cpp:1009`](../02_code_twin/drivers/dshot.md#^src-src-drivers-dshot-DShot-cpp-1009) | 转向反 |

> **`dshot` 与 `pwm_out` 都被 rcS 拉起**（`rcS:559-560`），靠 `PWM_MAIN_TIM0` 的值分流：
> `DShot::initialize_dshot()` 读 `<PARAM_PREFIX>_TIM<n>`（[`DShot.cpp:1086`](../02_code_twin/build/drivers-build.md#^src-src-drivers-dshot-DShot-cpp-1086)，前缀 `PWM_MAIN` 来自 [`src/drivers/dshot/CMakeLists.txt:34`](../02_code_twin/build/drivers-build.md#^src-src-drivers-dshot-CMakeLists-txt-34)），
> 值落进 DShot 档才继续；`pwm_out` 用**同一个前缀**（[`src/drivers/pwm_out/CMakeLists.txt:34`](../02_code_twin/build/drivers-build.md#^src-src-drivers-pwm-out-CMakeLists-txt-34)）但走 PWM 档。两者不会同时占住同一路输出。

### 1.3 参数名是怎么拼出来的（这就是"板型 → 参数 → 源码"那一跳）

```
"PWM_MAIN" (CMake -DPARAM_PREFIX, dshot/CMakeLists.txt:34)
   + "_FUNC" + (i+1)  →  mixer_module.cpp:117  →  PWM_MAIN_FUNC1
   + "_TIM"  + timer   →  DShot.cpp:1086       →  PWM_MAIN_TIM0
OutputFunction::Motor1 = 101                →  output_functions.yaml:11
motor_index = func - Motor1                 →  DShot.h:116
```

### 1.4 旁路产物（同一条链上的"观察窗"）

| 话题 | 谁发 | file:line | 用途 |
|---|---|---|---|
| `actuator_outputs` | `MixingOutput` | [`mixer_module.cpp:534`](../02_code_twin/build/drivers-build.md#^src-src-lib-mixer-module-mixer-module-cpp-534) → `:659` | `listener actuator_outputs` 看每路最终值 |
| `actuator_armed` | `commander` | `Commander.hpp:323` | DShot 靠它决定"给不给油门"（[`mixer_module.cpp:424`](../02_code_twin/modules/commander.md#^src-src-lib-mixer-module-mixer-module-cpp-424)） |
| `esc_status` | `dshot`（遥测回读） | 只在吃掉遥测帧后才发：[`DShot.cpp:100`](../02_code_twin/drivers/dshot.md#^src-src-drivers-dshot-DShot-cpp-100)（advertise 在 `:55`） | `vehicle_angular_velocity`(`:106`)、`logger`(`:71`) —— 本板 `DSHOT_TEL_CFG = 0`（[`serial_params.c:55`](../02_code_twin/drivers/dshot.md#^src-build-rm2027-fmu-h743-default-generated-params-serial-params-c-55)）且 `PWM_MAIN_TIM0` 非 BDShot 档 ⇒ **话题被 advertise 但永远不 publish** |

**判据**：拆桨，`commander arm`，然后
```
listener actuator_motors     # 看 control_allocator 有没有在发
listener actuator_outputs    # 看 MixingOutput 有没有把值给驱动
dshot status                 # 看驱动是否认为自己配置成功
```
`actuator_motors` 有值而 `actuator_outputs` 无值 ⇒ 卡在 `PWM_MAIN_FUNC*`（功能号 = 0）。

---

## 2. 流②：陀螺仪① `hxy42688p`（SPI1，1 kHz，内部器件）

### 2.1 链路

```
HXY ICM-42688P（SPI1，CS=PB4=GYRO_CS，DRDY=PD6）
  │  ① 登记：boards/rm2027/fmu-h743/src/spi.cpp:107  initSPIDevice(DRV_IMU_DEVTYPE_HXY42688P, CS{PB,4}, DRDY{PD,6})
  │     （同一 CS 上还登记了 5 个"候选型号"，SPI_BUS_MAX_DEVICES==6 正好占满：spi.cpp:94-112）
  │  ② 拉起：rc.board_sensors:85  `hxy42688p -s -b 1 -R 6 start`
  │        -s = SPIInternal（platforms/common/i2c_spi_buses.cpp:201-203）⇒ external=false
  │        -b 1 = SPI1；-R 6 = ROTATION_YAW_270（rc.board_sensors:61-78 的实测定标）
  │  ③ 模块入口：hxy42688p_main.cpp:49 hxy42688p_main() → :74 ThisDriver::module_start(cli, iterator)
  │  ④ 对象生存：I2CSPIDriverBase(config)（i2c_spi_buses.h:272-276）
  │        work queue = device_bus_to_wq(devid) = wq:SPI1（WorkQueueManager.cpp:159-163）
  │  ⑤ 状态机：Reset()(HXY42688P.cpp:117) → ScheduleNow → RESET→CONFIGURE→DATA_READ
  │        Configure 完切 1kHz：ScheduleOnInterval(POLL_INTERVAL_US, ...)  HXY42688P.cpp:269
  │        POLL_INTERVAL_US = 1000  HXY42688P.hpp:86
  │  ⑥ 取数：轮询 0x0B~0x17，DRDY 当新样本门 → DataReadPublish（HXY42688P.cpp:273-276）
  │  ⑦ 落话题：→_px4_accel.update(...) / →_px4_gyro.update(...)  HXY42688P.cpp:607-608
  │        PX4Accelerometer::update → _sensor_pub.publish  sensor_accel_s（PX4Accelerometer.hpp:73）
  │        PX4Gyroscope::update    → _sensor_pub.publish  sensor_gyro_s （PX4Gyroscope.hpp:71）
  ▼
【发布者 = hxy42688p】话题 sensor_accel / sensor_gyro（各 1 个实例）
  ▼  唯一消费者
【订阅者 = sensors 模块】sensors.cpp:441-442（Subscription{sensor_accel,i} / {sensor_gyro,i}）→ InitializeVehicleIMU()
  ▼
VehicleIMU（每对 accel/gyro 一个实例）→ 发布 vehicle_imu（VehicleIMU.cpp:664）+ vehicle_imu_status（:638）
  ▼
sensor_combined（sensors.cpp:606）+ vehicle_angular_velocity + vehicle_acceleration
  ▼
EKF2（EKF2.hpp:434 _vehicle_imu_sub / :433 _sensor_combined_sub）
mc_rate_control（MulticopterRateControl.hpp:107 _vehicle_angular_velocity_sub）
logger（logged_topics.cpp:233 add_topic_multi("vehicle_imu", 500, 4)）
```

### 2.2 两个易错点（本项目踩过）

1. **DRDY 只是"登记项"，这个驱动全程轮询**（`spi.cpp:83`）。所以 `listener sensor_gyro` 的频率 = 1 kHz 减掉 stale/duplicate 的拍。
2. **`-R 6` 是实测定出来的，不是查表**（`rc.board_sensors:61-84` 有完整推导：拿 H104 当参照比六面签名 ⇒ 板 +X→hxy +Y、板 +Y→hxy −X ⇒ YAW_90 的逆 = `ROTATION_YAW_270`）。

---

## 3. 流③：双陀螺仪 —— `h104_imu`（USART1，100 Hz，外挂器件）

### 3.1 链路

```
HiPNUC HI04M0（USART1 = /dev/ttyS0，115200 8N1，HI91 帧 82B，CRC-16/XMODEM）
  │  ① 拉起：rc.board_sensors:119  `h104_imu start`（默认 -p /dev/ttyS0，h104_imu_main.cpp:104）
  │  ② 模块入口：手写的 h104_imu_main（**不继承 ModuleBase**，所以 start/stop/status 全是手工分支）
  │  ③ 周期：ScheduleDelayed(2000us)（H104IMU.cpp:49,136,262）——500 Hz 调度，但**只在解析出完整帧时发布**
  │  ④ 端口在**工作队列里**打开（H104IMU.cpp:130-137 的注释解释了为什么不能在 Start() 里 open：
  │        NuttX 的 fd 表按任务隔离，跨任务用 fd 直接 EBADF）
  │  ⑤ 工作队列：px4::wq_configurations::INS0（H104IMU.cpp:54）——**和 EKF2/VehicleIMU 同一个队列**
  │  ⑥ 波特率**硬编码 115200**：H104IMU.cpp:104 cfsetspeed(&t, 115200)
  │  ⑦ 发布：解析回调 → H104IMU::Publish（H104IMU.cpp:162）→ _px4_accel.update / _px4_gyro.update（:172-173）
  │        ★ external=true（H104IMU.cpp:58-59 显式传 true）
  ▼
【发布者 = h104_imu】话题 sensor_accel / sensor_gyro（**与 hxy 不同实例**）
  ▼  同一套消费者
【订阅者 = sensors 模块】→ VehicleIMU #1 → vehicle_imu #1 → EKF2 / mc_rate_control / logger
```

### 3.2 ★ 两个 IMU 怎么"同时存在"、EKF2 怎么选

这是本问的核心，四步：

| 步 | 机制 | 出处 |
|---|---|---|
| ① 各自占一个 uORB 实例 | `uORB::PublicationMulti` 自动分配第一个空实例（[`Publication.cpp:76`](../02_code_twin/uorb/uorb-internals.md#^src-platforms-common-uORB-Publication-cpp-76)，`instance` 从 0 起试；[`uORBDeviceMaster.cpp:90`](../02_code_twin/uorb/uorb-internals.md#^src-platforms-common-uORB-uORBDeviceMaster-cpp-90)）⇒ `sensor_accel_0 / sensor_accel_1` | `PX4Accelerometer.hpp:73` |
| ② `sensors` 按实例号配对 | 第 i 个 `sensor_accel` + 第 i 个 `sensor_gyro` ⇒ `VehicleIMU(i, i, i, wq)` | `sensors.cpp:438` |
| ③ 器件身份靠 **device_id** 绑定到标定槽 | `CAL_ACCx_ID` / `CAL_GYROx_ID` = device_id；`FindCurrentCalibrationIndex()` 用 device_id 找槽 | `Accelerometer.cpp:272`、`Utilities.cpp` 的 `FindCurrentCalibrationIndex` |
| ④ **"选哪一路"由优先级投票决定** | `CAL_ACCx_PRIO` / `CAL_GYROx_PRIO`（缺省 -1 = 未初始化）⇒ 回落到"内部 50 / 外部 75" | [`Accelerometer.cpp:201`](../02_code_twin/modules/sensors.md#^src-src-lib-sensor-calibration-Accelerometer-cpp-201)、[`Gyroscope.hpp:50`](../02_code_twin/modules/sensors.md#^src-src-lib-sensor-calibration-Gyroscope-hpp-50)、`Barometer.hpp:48`、`Magnetometer.hpp:51` |

**⇒ ★ 一个可以立刻证的推论 `[推理，但有源码链]`：**
`hxy` 以 `-s` 拉起 ⇒ `external=false` ⇒ 缺省优先级 **50**；
`h104` 驱动里写死 `external=true`（[`H104IMU.cpp:58`](../02_code_twin/modules/sensors.md#^src-src-drivers-imu-hipnuc-h104-H104IMU-cpp-58)）⇒ 缺省优先级 **75**。
**⇒ 在没设过 `CAL_ACC0_PRIO/CAL_ACC1_PRIO` 的情况下，`sensors` 投票会偏袒 H104。**
这正好解释本项目「未结案 #1」里那句"`sensors status` 报 H104，但修 hxy 的 chip Y 才让标定走通"的**第一层**（第二层是六面标定到底读哪一路，仍未结案）。

> 优先级是**相对量**，不是绝对值：`voted_sensors_update.cpp:97,106-108` 读 `CAL_ACCx_PRIO` 后
> 把"新配置值 − 旧配置值"这个**差值**加到运行期 `priority[]` 上（运行期还会因故障掉到 1，`:341`）。

### 3.3 两路的差异一览（为什么"双陀螺"不是简单冗余）

| | hxy42688p | h104_imu |
|---|---|---|
| 总线 / 位置 | SPI1，板载（internal） | USART1，外挂（external） |
| 速率 | **1 kHz**（[`HXY42688P.hpp:86`](../02_code_twin/drivers/hxy42688p.md#^src-src-drivers-imu-hxy-hxy42688p-HXY42688P-hpp-86)） | **100 Hz**（模块输出；驱动 500 Hz 轮询） |
| 工作队列 | `wq:SPI1` | `wq:INS0` |
| 时间戳 | `hrt`（[`HXY42688P.cpp:274`](../02_code_twin/build/drivers-build.md#^src-src-drivers-imu-hxy-hxy42688p-HXY42688P-cpp-274) 传 `now` → `:537 DataReadPublish(timestamp_sample)` → `:607-608`） | 模块时间只做诊断，`timestamp` 用 `hrt`（[`H104IMU.cpp:164`](../02_code_twin/build/drivers-build.md#^src-src-drivers-imu-hipnuc-h104-H104IMU-cpp-164)） |
| 阻塞风险 | SPI 传输（`transfer()` 补丁，见 `[02_code_twin/drivers/hxy42688p](../02_code_twin/drivers/hxy42688p.md)`） | `::read()` 非阻塞 + `kReadsPerRun=4` |
| 已知未决 | chip Y 增益 3.629 倍（已打补丁）、UE 标度 ±10% | X/Y 符号未用实物转动验证（`rc.board_sensors:118`）、`set_error_count()` 从不调用 |
| 缺省优先级 | 50 | 75 |

**判据**（不依赖 QGC）：
```
sensors status              # 看 selected gyro/accel 的 device_id
listener sensor_gyro        # 两个实例各自看
listener vehicle_imu        # 看 rate 是不是 1000Hz / 100Hz
ekf2 status
```
**EKF2 用什么**：`EKF2_MULTI_IMU`（缺省 0 = 只用选中的那一路，[`EKF2.cpp:3007`](../02_code_twin/modules/ekf2.md#^src-src-modules-ekf2-EKF2-cpp-3007) 起会读它并 clamp）；
单实例时 EKF2 靠 `sensor_selection`（[`EKF2.cpp:740`](../02_code_twin/modules/ekf2.md#^src-src-modules-ekf2-EKF2-cpp-740)）跟着 `sensors` 的投票结果换 `vehicle_imu` 实例（`EKF2.cpp:400` `ChangeInstance`）。

---

## 4. 流④：磁力计 `ist8310`（I2C4，0x0C）

```
iSentek IST8310（I2C4，SCL=PD12 SDA=PD13；7bit 地址 0x0C，CAD1=CAD0=VSS）[实测]
  │  ① 总线登记：boards/rm2027/fmu-h743/src/i2c.cpp:77  initI2CBusInternal(4)
  │  ② 拉起：rc.board_sensors:105  `ist8310 -I -b 4 -a 0x0C -R 0 start`
  │        ★ 必须 -a 0x0C：驱动缺省 0x0E（ist8310_main.cpp:45）
  │        ★ 必须 -I（internal）：I2CBusIterator 在 -X 下不遍历 Internal 总线（i2c.cpp:57-60 有完整踩坑记录）
  │  ③ 工作队列 = wq:I2C4（WorkQueueManager.cpp:146-157）
  │  ④ probe 只校验 WAI：IST8310.cpp:98-104（`wai == IST8310_Device_ID`），失败才软复位重试
  │  ⑤ 周期 20 ms（50 Hz）：IST8310.cpp:183,250  ScheduleDelayed(20_ms)
  │  ⑥ 落话题：_px4_mag.update(now, x, y, z)（IST8310.cpp:211）
  │        PX4Magnetometer → PublicationMulti<sensor_mag_s>（PX4Magnetometer.hpp:63）
  │        标度 1320 LSB/Gauss：IST8310.cpp:273
  ▼
【发布者 = ist8310】sensor_mag（实例 0）
  ▼
【订阅者 = sensors 模块】VehicleMagnetometer（sensors.cpp:474-478）
  │   它同时要：vehicle_thrust_setpoint（补偿电机磁干扰，VehicleMagnetometer.hpp:113）、
  │             battery_status（:114）、magnetometer_bias_estimate（:115）
  ▼
vehicle_magnetometer（VehicleMagnetometer.hpp:105-108 四个实例）+ sensor_preflight_mag（:102）+ sensors_status_mag（:100）
  ▼
EKF2：EKF2.hpp:324 _magnetometer_sub → EKF2.cpp:2708 消费，出 estimator_aid_src_mag（EKF2.hpp:326）
MagBiasEstimator（rcS:583 附近由 MBE_ENABLE 拉起）用同一话题
mavlink / logger（logged_topics.cpp:152 add_topic("vehicle_magnetometer", 200)）
```

**判据**：`ist8310 status`（看 `|B|`）、`listener sensor_mag`、`listener vehicle_magnetometer`。
**已知未决**：`|B|` 实测 0.259 G（≈26 µT），比中国地表 ~50 µT 低约 2×，但落进 `lm_mag_fit` 的半径窗口 (0.2, 0.7) ⇒ 能标定；标度由标定自己估 `[实测]`（`rc.board_sensors:103-104`）。

---

## 5. 流⑤：气压计 `spa06`（I2C2，0x77）

```
Goertek SPA06-003（I2C2，SCL=PB10 SDA=PB11；7bit 地址 0x77）[实测]
  │  ① 总线登记：boards/rm2027/fmu-h743/src/i2c.cpp:78  initI2CBusInternal(2)
  │  ② 拉起：rc.board_sensors:110  `spa06 -I -b 2 -a 0x77 start`
  │        ★ 必须 -a 0x77：驱动缺省 0x76（spa06_main.cpp:52,111）
  │  ③ 工作队列 = wq:I2C2（WorkQueueManager.cpp:152）
  │  ④ 采样 32 Hz：SPA06.hpp:116-117（_sample_rate=32 ⇒ _measure_interval=31250us）
  │        ScheduleDelayed(_measure_interval)（SPA06.cpp:207）
  │  ⑤ 落话题：_px4_baro.update(timestamp_sample, fp)（SPA06.cpp:241）
  │        PX4Barometer → PublicationMulti<sensor_baro_s>（PX4Barometer.hpp:61）
  ▼
【发布者 = spa06】sensor_baro（实例 0）
  ▼
【订阅者 = sensors 模块】VehicleAirData（sensors.cpp:409-413）
  │   它还读 vehicle_gps_position（VehicleAirData.hpp:112）、differential_pressure（:101）、
  │          estimator_status_flags（:103）
  ▼
vehicle_air_data（VehicleAirData.hpp:97）+ sensors_status_baro（:95）
  ▼
EKF2：EKF2.hpp:373 _airdata_sub → EKF2.cpp:2363，出 estimator_aid_src_baro_hgt（EKF2.hpp:376）
mavlink / logger（logged_topics.cpp:139 add_topic("vehicle_air_data", 200)）
```

**判据**：`spa06 status`、`listener sensor_baro`、`listener vehicle_air_data`。
**注意**：本板**没有** GPS，所以 `vehicle_air_data` 的气压高度没有 GNSS 做参照 —— EKF2 的高度只能靠气压 + 加速度积分 `[推理]`。

---

## 6. 流⑥：遥控（本板**没有配 RC 串口**）

### 6.1 ★ 先给本板的实测结论

| 项 | 值 | 出处 |
|---|---|---|
| `RC_PORT_CONFIG` | **0** | [`build/rm2027_fmu-h743_default/generated_params/serial_params.c:69`](../02_code_twin/modules/rc_update.md#^src-build-rm2027-fmu-h743-default-generated-params-serial-params-c-69) |
| 结果 | `rc.serial` 里 `RC_PORT_CONFIG` 分支不成立 ⇒ `RC_INPUT_ARGS` 保持空（`rcS:33` 初始化） | `build/rm2027_fmu-h743_default/etc/init.d/rc.serial` |
| `rcS:611` | `rc_input start $RC_INPUT_ARGS` ⇒ **无 `-d`** ⇒ 只能走 PPM/单线，本板 `board_config.h` 未定义 `GPIO_PPM_IN` | `rcS:611` |
| `uxrce_dds` | `UXRCE_DDS_CFG = 0` | [`serial_params.c:153`](../02_code_twin/build/artifacts.md#^src-build-rm2027-fmu-h743-default-generated-params-serial-params-c-153) |
| MAVLink | `MAV_0_CONFIG = 101`（101 = TEL1 = `/dev/ttyS2`）、`MAV_0_MODE = 0`（Normal） | [`serial_params.c:111`](../02_code_twin/modules/mavlink.md#^src-build-rm2027-fmu-h743-default-generated-params-serial-params-c-111)、[`module_params.c:13517`](../02_code_twin/modules/mavlink.md#^src-build-rm2027-fmu-h743-default-generated-params-module-params-c-13517) |

**⇒ `[推理，证据齐]` 本板当前唯一的遥控入口是 MAVLink（QGC 虚拟摇杆 → `MANUAL_CONTROL`）**，走 `TEL1=/dev/ttyS2`。
要在硬件遥控器上接 SBUS/CRSF，需要**先给板子声明一个 RC 串口**（板级 `CONFIG_BOARD_SERIAL_RC` → 生成 `RC_PORT_CONFIG`），这一步本板**没做**。

### 6.2 两条支线各自的链路

**支线 A：MAVLink（本板可用）**
```
QGC 虚拟摇杆 → MAVLink MANUAL_CONTROL
  ▼
【发布者 = mavlink 模块的 receiver】manual_control_input
     mavlink_receiver.h:402  _manual_control_input_pub{ORB_ID(manual_control_input)}
     组装：mavlink_receiver.cpp:2364-2401（x→pitch、y→roll、z→throttle、r→yaw，data_source 标 MAVLINK_0+n）
  ▼
【订阅者 = manual_control 模块】ManualControl.hpp:108-110（3 个实例的 manual_control_input）
```

**支线 B：硬件 RC（本板未配）**
```
SBUS/CRSF/DSM/PPM 串口
  ▼
【发布者 = rc_input 驱动】input_rc
     RCInput.hpp:147 _input_rc_pub{ORB_ID(input_rc)}；协议分支 RCInput.cpp:516/558/608/660/677
  ▼
【订阅者 = rc_update】rc_update.h:171（SubscriptionCallbackWorkItem _input_rc_sub）
     rc_update.cpp:363 起：把 µs 值映射成 [-1,1]，读 rc_parameter_map、判 failsafe
  ▼
【发布者 = rc_update】
     manual_control_input    rc_update.h:178（PublicationMulti）
     manual_control_switches rc_update.h:179（模式/解锁开关槽位）
     rc_channels             rc_update.h:177（给 MAVLink RC_CHANNELS 流看）
  ▼
【订阅者 = manual_control 模块】ManualControl.hpp:108-112
  ▼
【发布者 = manual_control 模块】manual_control_setpoint
     ManualControl.hpp:118 _manual_control_setpoint_pub{ORB_ID(manual_control_setpoint)}
     （它还会发 action_request :116、landing_gear :117、vehicle_command `ManualControl.cpp:528/542/562`）
  ▼
【订阅者 = 四个人】
     commander          Commander.hpp:304  （解锁/上锁开关、failsafe）
     mc_att_control     mc_att_control.hpp:109
     mc_rate_control    MulticopterRateControl.hpp:99
     flight_mode_manager（FMM 决定手动/自动/offboard）
```

### 6.3 启动顺序不是随便定的

`rcS` 里这三行是**有依赖方向**的：

| 行 | 命令 | 为什么在这个位置 |
|---|---|---|
| `rcS:509-510` | `rc_update start` / `manual_control start` | 必须在 `commander`(:551) **之前**（rcS:507 的注释原话："start before commander"） |
| `rcS:611` | `rc_input start` | 必须在 `. rc.serial`(:603) **之后**（rcS:610 注释："Must be started after the serial config is read"） |
| `rcS:551` | `commander start` | 解锁检查要能读到 `manual_control_setpoint` |

**判据**：
```
listener manual_control_setpoint   # 有没有在发、valid 是不是 1、data_source 是谁
listener manual_control_switches
listener input_rc                  # 本板预期：没有发布者
```

---

## 7. ★ 汇合点：六条流最后去哪了

### 7.1 汇合图（"谁等谁"）

```
                         ┌────────────────────┐
  sensor_combined ──────►│                    │
  vehicle_imu(0/1) ─────►│       EKF2         │──► vehicle_attitude
  vehicle_mag ──────────►│  (wq:INS0)         │──► vehicle_local_position
  vehicle_air_data ─────►│                    │──► vehicle_global_position / wind
  vehicle_gps_position ─►└────────────────────┘
                                │  EKF2Selector 选实例（EKF2Selector.cpp）
                                ▼
  manual_control_setpoint ──► flight_mode_manager ──► trajectory_setpoint
                                │                      + vehicle_control_mode
                                ▼
                        mc_pos_control（位置环）
                                │ vehicle_attitude_setpoint
                                ▼
                        mc_att_control（姿态环）
                                │ vehicle_rates_setpoint
                                ▼
                        mc_rate_control（角速率环，吃 vehicle_angular_velocity）
                                │ vehicle_torque_setpoint + vehicle_thrust_setpoint
                                ▼
                        control_allocator（吃 CA_ROTOR_* 几何）
                                │ actuator_motors
                                ▼
                        dshot / pwm_out → TIM1 CH1..4
```

**★ 关键认知（也是用户问"module 层怎么理解"的答案）：**
`EKF2` 只吃"**已经归一化过**的话题"（`vehicle_imu` / `vehicle_air_data` / `vehicle_magnetometer`），
**从不直接读器物级的 `sensor_*`**。做归一化和投票的那个模块叫 `sensors`，它在 rcS 里比 `ekf2` **早 6 行**启动（`rcS:440` vs `rcS:446`）——**顺序就是依赖**。

### 7.2 一张总表：「谁发布 → 话题 → 谁订阅（本板）」

| 话题 | 发布者 | 发布点 file:line | 本板的订阅者 |
|---|---|---|---|
| `sensor_accel` / `sensor_gyro` | hxy42688p(0)、h104_imu(1) | [`HXY42688P.cpp:607`](../02_code_twin/build/drivers-build.md#^src-src-drivers-imu-hxy-hxy42688p-HXY42688P-cpp-607)、[`H104IMU.cpp:172`](../02_code_twin/build/drivers-build.md#^src-src-drivers-imu-hipnuc-h104-H104IMU-cpp-172) | `sensors`（`sensors.cpp:441`） |
| `sensor_mag` | ist8310 | [`IST8310.cpp:211`](../02_code_twin/build/drivers-build.md#^src-src-drivers-magnetometer-isentek-ist8310-IST8310-cpp-211) | `sensors`（VehicleMagnetometer，`VehicleMagnetometer.hpp:130`） |
| `sensor_baro` | spa06 | `SPA06.cpp:241` | `sensors`（VehicleAirData，`VehicleAirData.hpp:106`） |
| `sensor_combined` | `sensors` | [`sensors.cpp:606`](../02_code_twin/modules/sensors.md#^src-src-modules-sensors-sensors-cpp-606) | `ekf2`([`EKF2.hpp:433`](../02_code_twin/modules/sensors.md#^src-src-modules-ekf2-EKF2-hpp-433))、`logger`([`logged_topics.cpp:126`](../02_code_twin/modules/sensors.md#^src-src-modules-logger-logged-topics-cpp-126))、`local_position_estimator` |
| `vehicle_imu` | `sensors`/VehicleIMU | [`VehicleIMU.cpp:664`](../02_code_twin/modules/sensors.md#^src-src-modules-sensors-vehicle-imu-VehicleIMU-cpp-664) | `ekf2`([`EKF2.hpp:434`](../02_code_twin/modules/sensors.md#^src-src-modules-ekf2-EKF2-hpp-434))、`mc_rate_control`(间接)、`mavlink`([`HIGHRES_IMU.hpp:66`](../02_code_twin/modules/sensors.md#^src-src-modules-mavlink-streams-HIGHRES-IMU-hpp-66))、`logger`(`:233`) |
| `vehicle_imu_status` | 同上 | [`VehicleIMU.cpp:638`](../02_code_twin/modules/sensors.md#^src-src-modules-sensors-vehicle-imu-VehicleIMU-cpp-638) | `sensors` 投票器、`vehicle_acceleration/angular_velocity`(`:92`/`:106`)、`logger`(`:234`) |
| `vehicle_angular_velocity` | VehicleAngularVelocity | [`VehicleAngularVelocity.hpp:101`](../02_code_twin/modules/sensors.md#^src-src-modules-sensors-vehicle-angular-velocity-VehicleAngularVelocity-hpp-101) | `mc_rate_control`([`MulticopterRateControl.hpp:107`](../02_code_twin/modules/sensors.md#^src-src-modules-mc-rate-control-MulticopterRateControl-hpp-107)) |
| `vehicle_acceleration` | VehicleAcceleration | [`VehicleAcceleration.hpp:80`](../02_code_twin/modules/sensors.md#^src-src-modules-sensors-vehicle-acceleration-VehicleAcceleration-hpp-80) | `mc_att_control` 等、`logger`(`:138`) |
| `vehicle_air_data` | VehicleAirData | [`VehicleAirData.hpp:97`](../02_code_twin/modules/sensors.md#^src-src-modules-sensors-vehicle-air-data-VehicleAirData-hpp-97) | `ekf2`([`EKF2.hpp:373`](../02_code_twin/modules/sensors.md#^src-src-modules-ekf2-EKF2-hpp-373))、`mavlink`([`HIGHRES_IMU.hpp:72`](../02_code_twin/modules/sensors.md#^src-src-modules-mavlink-streams-HIGHRES-IMU-hpp-72))、`logger`(`:139`) |
| `vehicle_magnetometer` | VehicleMagnetometer | [`VehicleMagnetometer.hpp:105`](../02_code_twin/modules/sensors.md#^src-src-modules-sensors-vehicle-magnetometer-VehicleMagnetometer-hpp-105) | `ekf2`([`EKF2.hpp:324`](../02_code_twin/modules/sensors.md#^src-src-modules-ekf2-EKF2-hpp-324))、`mavlink`(`HIGHRES_IMU.hpp:71`)、`logger`(`:152`) |
| `sensor_selection` | `sensors`/VotedSensorsUpdate | [`voted_sensors_update.h:155`](../02_code_twin/modules/sensors.md#^src-src-modules-sensors-voted-sensors-update-h-155) | `ekf2`([`EKF2.hpp:404`](../02_code_twin/modules/ekf2.md#^src-src-modules-ekf2-EKF2-hpp-404))、`vehicle_acceleration/angular_velocity`(`:87`/`:112`) |
| `input_rc` | `rc_input`（本板未配） | [`RCInput.hpp:147`](../02_code_twin/drivers/rc_input.md#^src-src-drivers-rc-input-RCInput-hpp-147) | `rc_update`([`rc_update.h:171`](../02_code_twin/modules/rc_update.md#^src-src-modules-rc-update-rc-update-h-171))、`mavlink`([`RC_CHANNELS.hpp:58`](../02_code_twin/modules/mavlink.md#^src-src-modules-mavlink-streams-RC-CHANNELS-hpp-58)) |
| `manual_control_input` | `rc_update` / `mavlink receiver` | [`rc_update.h:178`](../02_code_twin/modules/rc_update.md#^src-src-modules-rc-update-rc-update-h-178)、[`mavlink_receiver.h:402`](../02_code_twin/modules/mavlink.md#^src-src-modules-mavlink-mavlink-receiver-h-402) | `manual_control`([`ManualControl.hpp:108`](../02_code_twin/modules/mavlink.md#^src-src-modules-manual-control-ManualControl-hpp-108)) |
| `manual_control_switches` | `rc_update` | [`rc_update.h:179`](../02_code_twin/modules/rc_update.md#^src-src-modules-rc-update-rc-update-h-179) | `manual_control`(`:112`) |
| `manual_control_setpoint` | `manual_control` | [`ManualControl.hpp:118`](../02_code_twin/modules/manual_control.md#^src-src-modules-manual-control-ManualControl-hpp-118) | `commander`([`Commander.hpp:304`](../02_code_twin/modules/commander.md#^src-src-modules-commander-Commander-hpp-304))、`mc_att_control`(`:109`)、`mc_rate_control`(`:99`)、FMM、`mavlink`(`logged_topics.cpp:99`) |
| `vehicle_attitude` | `ekf2` | [`EKF2.cpp:57`](../02_code_twin/modules/ekf2.md#^src-src-modules-ekf2-EKF2-cpp-57) | `mc_att_control`(`:115`)、`mavlink`([`ATTITUDE.hpp:59`](../02_code_twin/modules/mavlink.md#^src-src-modules-mavlink-streams-ATTITUDE-hpp-59))、`logger`(`:141`) |
| `vehicle_local_position` | `ekf2` | `EKF2.cpp:58` | `mc_pos_control`([`MulticopterPositionControl.hpp:104`](../02_code_twin/modules/ekf2.md#^src-src-modules-mc-pos-control-MulticopterPositionControl-hpp-104))、FMM(`:150`)、`logger`(`:150`) |
| `vehicle_torque_setpoint` / `vehicle_thrust_setpoint` | `mc_rate_control` | `MulticopterRateControl.cpp:51-52,260,264` | `control_allocator`([`ControlAllocator.hpp:201`](../02_code_twin/modules/control_allocator.md#^src-src-modules-control-allocator-ControlAllocator-hpp-201)) |
| `actuator_motors` | `control_allocator` | [`ControlAllocator.cpp:757`](../02_code_twin/modules/control_allocator.md#^src-src-modules-control-allocator-ControlAllocator-cpp-757) | `dshot`/`pwm_out`([`FunctionMotors.hpp:52`](../02_code_twin/build/drivers-build.md#^src-src-lib-mixer-module-functions-FunctionMotors-hpp-52))、`logger`(`:241`) |
| `actuator_servos` | `control_allocator` | `ControlAllocator.hpp:211` | `dshot`/`pwm_out`([`FunctionServos.hpp:50`](../02_code_twin/build/drivers-build.md#^src-src-lib-mixer-module-functions-FunctionServos-hpp-50)) |
| `actuator_armed` | `commander` | `Commander.hpp:323` | `MixingOutput`([`mixer_module.hpp:270`](../02_code_twin/build/drivers-build.md#^src-src-lib-mixer-module-mixer-module-hpp-270))、`commander` 自己、[`escCheck.hpp:66`](../02_code_twin/modules/commander.md#^src-src-modules-commander-HealthAndArmingChecks-checks-escCheck-hpp-66) 等 |
| `actuator_outputs` | `dshot`/`pwm_out`（MixingOutput） | [`mixer_module.cpp:534`](../02_code_twin/build/drivers-build.md#^src-src-lib-mixer-module-mixer-module-cpp-534) → `:659` | `logger`、`mavlink`（SERVO_OUTPUT_RAW） |
| `esc_status` | `dshot` 遥测（仅在收到遥测帧时发） | [`DShot.cpp:100`](../02_code_twin/drivers/dshot.md#^src-src-drivers-dshot-DShot-cpp-100) | `vehicle_angular_velocity`(`:106`)、`logger`(`:71`) —— 本板无遥测 ⇒ 话题被 advertise 但从不 publish |

---

## 8. 未核实 / 边界

| # | 事项 | 为什么没定 |
|---|---|---|
| 1 | `hxy` 与 `h104` **实际**各自被 `sensors` 投票成第几号实例 | 需要上板 `sensors status` / `listener sensor_gyro`；本文只给出"缺省优先级 50 vs 75"这一层可推的结论 |
| 2 | 六面标定到底读哪一路（本项目未结案 #1） | 与本篇的选源链有关但不是同一问题；判决实验见 `work/PX4改造-索引与纪律.md` §8 |
| 3 | 本板 RC 的**实际**接入方式 | `RC_PORT_CONFIG=0` 是从**生成参数表**读的（[`serial_params.c:69`](../02_code_twin/modules/rc_update.md#^src-build-rm2027-fmu-h743-default-generated-params-serial-params-c-69)）；生成目录时间戳 2026-09-28，晚于此的板级改动未覆盖，**上板 `param show RC_PORT_CONFIG` 复核一次即可定案** |
| 4 | `SPA06._sample_rate=32` 是"驱动轮询率"还是"器件 ODR" | 只核到 [`SPA06.hpp:116`](../02_code_twin/drivers/spa06.md#^src-src-drivers-barometer-goertek-spa06-SPA06-hpp-116) 与 `ScheduleDelayed`；器件侧 `MEAS_CFG` 的值未逐位展开 |
| 5 | `vehicle_acceleration/angular_velocity` 的**完整**消费者名单 | 只列了主控制链 + logger；`airspeed_selector`、`gyro_fft` 等次要消费者未穷举 |
| 6 | `EKF2_MULTI_IMU` 在本板的实际取值 | 缺省在 `params_multi.yaml`，未从生成参数表回读；本文按"未设 = 0"叙述 |

---

## 9. 自查记录（本项目硬纪律：交付前批量回验）

**批量回验**：本任务交付的 15 个文件（本目录 2 篇 + `02_code_twin/modules/` 7 篇 + `02_code_twin/drivers/` 6 篇）里
所有 `文件名:行号` 形式的引用，用脚本统一抽取 → 解析到真实文件 → 逐条比对该文件总行数，
**共 759 条，越界 0 条**（脚本同时对 5 处"写作时引错"当场改正）。

| 检查项 | 方法 | 结果 |
|---|---|---|
| 所有 `file:line` | 脚本抽取 + 真实文件行数比对 | **759 条，越界 0** |
| 语义抽查 | 关键 40 条逐条 `sed -n '<n>p'` 回读原文 | 通过；工作过程中当场改正 5 处：`DShot.cpp:1146→1126`（`dshot_timer_channels==0` 的实际行）、`HXY42688P.cpp:552→274/537`（时间戳传递路径）、`ControlAllocator.cpp` publish 调用点补上 `:454`、`control_allocator` 队列 `nav_and_controllers→rate_ctrl`、`af9838.cpp` 路径 `vtrantech→voltafield` |
| 短名歧义 | 首次出现给全路径 + 文首「缩写约定」表 | 5 个仍有歧义的短名（`spi.cpp`/`i2c.cpp`/`module.yaml`/`Subscription.hpp`/`CMakeLists.txt`）已在缩写表中固定全路径 |
| 所有话题名 | 与 `msg/*.msg` + `ORB_ID(...)` 逐个比对 | 通过 |
| 「实测」类断言 | 只保留 `rc.board_sensors` 文件头与 `work/review-*.md` 已记录的实测 | 通过 |
| 「推理」类断言 | 全部显式标 `[推理]` | 通过 |
| 构建产物行号 | 生成目录时间戳 **2026-09-28**，晚于它的板级改动不覆盖 | 已在相关处逐条标注「构建产物，重新构建会漂移」 |

> ⚠️ **一个必须交代的边界**：`module_params.c` / `serial_params.c` / `px4_boardconfig.h` / `px4.bdat` 是**构建产物**，
> 本文引用的行号来自 `build/rm2027_fmu-h743_default/`（时间戳 2026-09-28）。
> 这几处结论（`PWM_MAIN_FUNC*=0`、`PWM_MAIN_TIM0=400`、`RC_PORT_CONFIG=0`、`MAV_0_CONFIG=101`、工作队列优先级）
> **都应由上板 `param show` / `uorb top` 复核一次**才算实测。

---

## 跳转

| 想去哪 | 读哪篇 |
|---|---|
| 想知道"六条流背后的 module 是什么、uORB 内存里长什么样、工作队列怎么排队" | [03_moc/03-module-map](03-module-map.md) |
| 想逐源文件看 `sensors` 模块怎么把上面这些话题做出来 | [02_code_twin/modules/sensors](../02_code_twin/modules/sensors.md) |
| 想逐源文件看 EKF2 怎么选源、怎么出 `vehicle_attitude` | [02_code_twin/modules/ekf2](../02_code_twin/modules/ekf2.md) |
| 想看 `control_allocator` 怎么把力矩分配到 4 个电机 | [02_code_twin/modules/control_allocator](../02_code_twin/modules/control_allocator.md) |
| 想看遥控/手动控制的完整 module 侧 | [02_code_twin/modules/rc_update](../02_code_twin/modules/rc_update.md)、[02_code_twin/modules/commander](../02_code_twin/modules/commander.md)、[02_code_twin/modules/mavlink](../02_code_twin/modules/mavlink.md) |
| 想看六个驱动的源码结构 | [02_code_twin/drivers/hxy42688p](../02_code_twin/drivers/hxy42688p.md)、[02_code_twin/drivers/h104_imu](../02_code_twin/drivers/h104_imu.md)、[02_code_twin/drivers/ist8310](../02_code_twin/drivers/ist8310.md)、[02_code_twin/drivers/spa06](../02_code_twin/drivers/spa06.md)、[02_code_twin/drivers/dshot](../02_code_twin/drivers/dshot.md)、[02_code_twin/drivers/bmi270](../02_code_twin/drivers/bmi270.md) |
| 想从"开机第一行"开始执行序 | [03_moc/01-poweron-walkthrough](01-poweron-walkthrough.md) |
| 想知道这条链上的参数怎么生成、怎么读 | [03_moc/04-params-map](04-params-map.md) |

---

## 源码在哪（本篇只讲流程；代码与逐行解释已归位到 02 层）

> ★ **本篇每一条 `文件:行` 都能点** —— 它跳到 `02_code_twin/` 里对应的篇，代码旁边就是解释。
> 三层各司其职：**01 讲语法/机制通则 · 02 讲某个文件的行号在干什么 · 03 只讲流程**。

| 代码在 | 02 层的篇 |
|---|---|
| `02_code_twin/bootloader/00-overview.md` | [`02_code_twin/bootloader/00-overview.md`](../02_code_twin/bootloader/00-overview.md) |
| `02_code_twin/build/artifacts.md` | [`02_code_twin/build/artifacts.md`](../02_code_twin/build/artifacts.md) |
| `02_code_twin/build/drivers-build.md` | [`02_code_twin/build/drivers-build.md`](../02_code_twin/build/drivers-build.md) |
| `02_code_twin/drivers/dshot.md` | [`02_code_twin/drivers/dshot.md`](../02_code_twin/drivers/dshot.md) |
| `02_code_twin/drivers/loose.md` | [`02_code_twin/drivers/loose.md`](../02_code_twin/drivers/loose.md) |
| `02_code_twin/drivers/rc_input.md` | [`02_code_twin/drivers/rc_input.md`](../02_code_twin/drivers/rc_input.md) |
| `02_code_twin/drivers/spa06.md` | [`02_code_twin/drivers/spa06.md`](../02_code_twin/drivers/spa06.md) |
| `02_code_twin/modules/commander.md` | [`02_code_twin/modules/commander.md`](../02_code_twin/modules/commander.md) |
| `02_code_twin/modules/control_allocator.md` | [`02_code_twin/modules/control_allocator.md`](../02_code_twin/modules/control_allocator.md) |
| `02_code_twin/modules/ekf2.md` | [`02_code_twin/modules/ekf2.md`](../02_code_twin/modules/ekf2.md) |
| `02_code_twin/modules/manual_control.md` | [`02_code_twin/modules/manual_control.md`](../02_code_twin/modules/manual_control.md) |
| `02_code_twin/modules/mavlink.md` | [`02_code_twin/modules/mavlink.md`](../02_code_twin/modules/mavlink.md) |
| `02_code_twin/modules/sensors.md` | [`02_code_twin/modules/sensors.md`](../02_code_twin/modules/sensors.md) |
| `02_code_twin/uorb/uorb-internals.md` | [`02_code_twin/uorb/uorb-internals.md`](../02_code_twin/uorb/uorb-internals.md) |
