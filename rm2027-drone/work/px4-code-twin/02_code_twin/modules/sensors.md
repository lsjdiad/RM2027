# `src/modules/sensors/sensors.cpp` —— 传感器归一化与投票

> **运行时一句话**：它是**唯一**读器件级 `sensor_*` 话题的模块，也是**唯一**产出 `vehicle_imu` / `vehicle_air_data` / `vehicle_magnetometer` / `vehicle_acceleration` / `vehicle_angular_velocity` / `sensor_combined` 的地方。
> **⇒ 数据链上它是"分水岭"**：上游是"某某器件的读数"，下游是"飞行器能用的量"。
> 行号基准 `源码根（见 `tools/source-root.conf`）` HEAD `3b5de24`。

---

## 1. 它活在哪

| 项 | 值 | 出处 |
|---|---|---|
| 入口函数 | `sensors_main` | `src/modules/sensors/CMakeLists.txt`（px4_add_module MAIN sensors） |
| 队列 | **`wq:nav_and_controllers`**（本板优先级 **-13**） | [`sensors.cpp:50`](sensors.md#^src-src-modules-sensors-sensors-cpp-50)；优先级 [`build/rm2027_fmu-h743_default/px4_boardconfig.h:156`](sensors.md#^src-build-rm2027-fmu-h743-default-px4-boardconfig-h-156) |
| 调度 | `ScheduleDelayed(10_ms)` 兜底（被订阅回调提前唤醒） | [`sensors.cpp:617`](sensors.md#^src-src-modules-sensors-sensors-cpp-617) |
| 拉起 | `rcS:440` `sensors start` —— **在 rc.board_sensors(:424) 与 rc.sensors(:428) 之后** | `ROMFS/px4fmu_common/init.d/rcS` |
| 上限 | `MAX_SENSOR_COUNT = 4` | [`src/modules/sensors/voted_sensors_update.h:65`](sensors.md#^src-src-modules-sensors-voted-sensors-update-h-65) |

---

## 2. `Run()` 一步不差（[`sensors.cpp:502`](sensors.md#^src-src-modules-sensors-sensors-cpp-502)）

```c
void Sensors::Run()                                  // :502
{
    if (should_exit()) { ...; exit_and_cleanup(desc); return; }   // :~505-512
    perf_begin(_loop_perf);                          // :514  ← 计时开始

    // ★ 一次性分支：传感器数量变了就重建派生对象
    if (hrt_elapsed_time(&_last_config_update) > 1_s
        || (n_accel != _n_accel) || (n_gyro != _n_gyro)) {
        orb_group_count(ORB_ID(sensor_baro));        // :532
        orb_group_count(ORB_ID(sensor_mag));         // :552
        orb_group_count(ORB_ID(sensor_accel));       // :572
        orb_group_count(ORB_ID(sensor_gyro));        // :573
        parameters_update();                         // :579
        _voted_sensors_update.initializeSensors();   // :583  ← 建投票器
        InitializeVehicleIMU();                      // :584  ← 建 VehicleIMU
    } else if (_parameter_update_sub.updated()) { ... }

    _voted_sensors_update.sensorsPoll(_sensor_combined);   // :601
    if (_sensor_combined.timestamp != _sensor_combined_prev_timestamp) {
        _voted_sensors_update.setRelativeTimestamps(...);   // :605
        _sensor_pub.publish(_sensor_combined);              // :606 ★ 发 sensor_combined
    }

    ScheduleDelayed(10_ms);                          // :617
    perf_end(_loop_perf);                            // :619
}
```

**读这段要抓住两点：**

1. **`if (n_accel != _n_accel ...)` 是"热插拔检测"**：`orb_group_count()` 数的是话题实例数。
   驱动后启动 ⇒ 实例数变 ⇒ 触发重建。**这就是"驱动必须先起、`sensors` 最后起"的技术原因**（`rcS:440`）。
2. **`sensor_combined` 只有在"时间戳真的变了"才发**（`:603`）。时间戳不变 = 这一圈没有新样本 ⇒ 不发，避免下游把旧数据当新的。

---

## 3. `InitializeVehicleIMU()`：两个 IMU 怎么变成 `vehicle_imu #0 / #1`

```c
void Sensors::InitializeVehicleIMU()                       // sensors.cpp:435
{
    for (uint8_t i = 0; i < MAX_SENSOR_COUNT; i++) {        // :438
        if (_vehicle_imu_list[i] == nullptr) {              // :439
            uORB::Subscription accel_sub{ORB_ID(sensor_accel), i};   // :441
            uORB::Subscription gyro_sub {ORB_ID(sensor_gyro),  i};   // :442
            if (accel_sub.advertised() && gyro_sub.advertised()) {   // :444
                const bool multi_mode = (_param_sens_imu_mode.get() == 0);        // :447
                const px4::wq_config_t &wq_config =
                    multi_mode ? px4::ins_instance_to_wq(i)                        // :448
                               : px4::wq_configurations::INS0;
                VehicleIMU *imu = new VehicleIMU(i, i, i, wq_config);              // :450
                ...
            } else { return; }        // :462-465 ★ 第一个缺口就整体返回
        }
    }
}
```

**⇒ 三条硬结论：**

| # | 结论 | 依据 |
|---|---|---|
| 1 | **按"实例号"配对，不按 device_id**：第 i 个 `sensor_accel` 配第 i 个 `sensor_gyro` | `:441-442` |
| 2 | **本板 `SENS_IMU_MODE` 缺省 = 1** ⇒ `multi_mode=false` ⇒ **两个 VehicleIMU 都跑在 `wq:INS0`** | [`build/.../generated_params/module_params.c:21373`](sensors.md#^src-build-rm2027-fmu-h743-default-generated-params-module-params-c-21373)；`:447-448` |
| 3 | **实例必须从 0 连续**（`:462-465` 遇缺口 `return`）⇒ 若 `sensor_accel_0` 不存在而 `_1` 存在，则**一个 VehicleIMU 都不会建** | `:462-465` |

> ⚠️ 第 3 条是本板的一个真实风险：`hxy42688p`（先起）与 `h104_imu`（后起）谁拿到实例 0，
> 取决于 `rc.board_sensors` 的行序（`:85` 在 `:119` 之前 ⇒ hxy 拿 0）**以及 probe 是否成功**。
> 如果 hxy 的 probe 失败但 h104 成功，实例号会错位 —— 而 `CAL_ACCx_ID` 是按 device_id 记的，
> 所以**标定不会错配**，但"实例号 ↔ 器件"的对应关系会变。`sensors status` 能看出来。

---

## 4. 六个下游话题分别是谁产出的

| 话题 | 产出者（file:line） | 谁订 |
|---|---|---|
| `sensor_combined` | [`sensors.cpp:606`](sensors.md#^src-src-modules-sensors-sensors-cpp-606)（`_sensor_pub`，[`sensors.hpp:161`](sensors.md#^src-src-modules-sensors-sensors-hpp-161)） | `ekf2`([`EKF2.hpp:433`](sensors.md#^src-src-modules-ekf2-EKF2-hpp-433))、`attitude_estimator_q`、`local_position_estimator`、`logger`([`logged_topics.cpp:126`](sensors.md#^src-src-modules-logger-logged-topics-cpp-126)) |
| `vehicle_imu` | [`VehicleIMU.cpp:664`](sensors.md#^src-src-modules-sensors-vehicle-imu-VehicleIMU-cpp-664) —— **独立工作队列对象，不是 `Run()` 里产的** | `ekf2`([`EKF2.hpp:434`](sensors.md#^src-src-modules-ekf2-EKF2-hpp-434))、`mavlink`([`HIGHRES_IMU.hpp:66`](sensors.md#^src-src-modules-mavlink-streams-HIGHRES-IMU-hpp-66))、`logger`(`:233`) |
| `vehicle_imu_status` | [`VehicleIMU.cpp:638`](sensors.md#^src-src-modules-sensors-vehicle-imu-VehicleIMU-cpp-638)（**先于 vehicle_imu 发**，见 `:574-575` 注释：让误差计数"同步可用"） | `sensors` 自己的投票器、`vehicle_acceleration/angular_velocity`、`logger`(`:234`) |
| `vehicle_air_data` | [`VehicleAirData.hpp:97`](sensors.md#^src-src-modules-sensors-vehicle-air-data-VehicleAirData-hpp-97) | `ekf2`([`EKF2.hpp:373`](sensors.md#^src-src-modules-ekf2-EKF2-hpp-373))、`mavlink`([`HIGHRES_IMU.hpp:72`](sensors.md#^src-src-modules-mavlink-streams-HIGHRES-IMU-hpp-72))、`logger`(`:139`) |
| `vehicle_magnetometer` | [`VehicleMagnetometer.hpp:105`](sensors.md#^src-src-modules-sensors-vehicle-magnetometer-VehicleMagnetometer-hpp-105)（4 实例） | `ekf2`([`EKF2.hpp:324`](sensors.md#^src-src-modules-ekf2-EKF2-hpp-324))、`mavlink`、`logger`(`:152`) |
| `vehicle_acceleration` / `vehicle_angular_velocity` | [`VehicleAcceleration.hpp:80`](sensors.md#^src-src-modules-sensors-vehicle-acceleration-VehicleAcceleration-hpp-80) / [`VehicleAngularVelocity.hpp:101`](sensors.md#^src-src-modules-sensors-vehicle-angular-velocity-VehicleAngularVelocity-hpp-101) | `mc_att_control` / `mc_rate_control`([`MulticopterRateControl.hpp:107`](sensors.md#^src-src-modules-mc-rate-control-MulticopterRateControl-hpp-107)) |

> ★ **`vehicle_angular_velocity` 跑在 `wq:rate_ctrl`（优先级 0）**（[`VehicleAngularVelocity.cpp:47`](sensors.md#^src-src-modules-sensors-vehicle-angular-velocity-VehicleAngularVelocity-cpp-47)），
> 而不是 `sensors` 自己的 -13 —— 因为它是角速率环的直接输入。**同一队列上还有 `mc_rate_control`（`:50`）和 `control_allocator`（`:57`）**，
> 也就是说：**"角速率 → 力矩 → 电机"这三跳全在同一个最高优先级队列上串行完成。**

---

## 5. 投票与选源（`voted_sensors_update.cpp`）

| 步 | 做什么 | file:line |
|---|---|---|
| 建投票器 | `initSensorClass(_gyro, 4)` / `(_accel, 4)`，新传感器 = `voter.add_new_validator()` | [`voted_sensors_update.cpp:70`](sensors.md#^src-src-modules-sensors-voted-sensors-update-cpp-70)、`:368` |
| 初始优先级 | 全给 `DEFAULT_PRIORITY`（=50） | `:363-364` |
| 应用 `CAL_*_PRIO` | 读 `CAL_ACCx_PRIO`/`CAL_GYROx_PRIO`，把**差值**加到运行期优先级 | `:97`、`:106-108`、`:120`、`:129-131` |
| 故障降权 | 一致性/停滞失败 ⇒ `sensor.priority[failover_index] = 1` | `:341` |
| 投票 | `_accel/…voter`（`DataValidator`，`src/modules/sensors/data_validator/`） | `:146-147` 的 `imuPoll` 入口 |
| 产出选源 | `sensor_selection`（`accel_device_id`/`gyro_device_id`） | [`voted_sensors_update.h:155`](sensors.md#^src-src-modules-sensors-voted-sensors-update-h-155) |

**★ 缺省优先级不是 50 一律（这是本板双 IMU 的关键）**
`CAL_ACCx_PRIO` 缺省 `-1`（未初始化）⇒ 回落到 **`_external ? 75 : 50`**（[`Accelerometer.cpp:201`](sensors.md#^src-src-lib-sensor-calibration-Accelerometer-cpp-201)、[`Gyroscope.hpp:50`](sensors.md#^src-src-lib-sensor-calibration-Gyroscope-hpp-50)）。
本板：`hxy` 用 `-s` 拉起 ⇒ internal ⇒ **50**；`h104` 驱动里硬写 `external=true` ⇒ **75**（[`H104IMU.cpp:58`](sensors.md#^src-src-drivers-imu-hipnuc-h104-H104IMU-cpp-58)）。
⇒ **不设参数时，投票偏向 H104。**

---

## 6. 判据（不依赖 QGC）

```sh
sensors status          # selected gyro/accel 的 device_id + 每路优先级 + 投票器明细
listener sensor_combined
listener vehicle_imu    # 看 rate：hxy 应 ~1000Hz，h104 应 ~100Hz
listener vehicle_imu_status
uorb top vehicle_imu
```
- `sensors status` 里某一路 **priority = 0** ⇒ 被 `CAL_*_PRIO = 0` 显式禁用，或 `CAL_*_ID` 没写上。
- `vehicle_imu` 频率远低于 1000 Hz 而 `sensor_gyro` 是 1000 Hz ⇒ 卡在积分/发布条件（[`VehicleIMU.cpp:254`](sensors.md#^src-src-modules-sensors-vehicle-imu-VehicleIMU-cpp-254) 附近"accel & gyro 积分器都就绪才发"）。

---

## 7. 未核实

| 事项 | 说明 |
|---|---|
| `DataValidator` 的内部阈值 | 只引用到 `data_validator/` 目录与调用点；阈值源码未展开 |
| `vehicle_gps_position` / `vehicle_optical_flow` | 本板无 GPS/光流器件，未核其初始化分支是否真的不建对象 |
| 本板 `SENS_MAG_MODE` 的实际运行值 | 生成参数表里缺省 1（[`module_params.c:21550`](sensors.md#^src-build-rm2027-fmu-h743-default-generated-params-module-params-c-21550)），但运行时是否被板级脚本改过未核 |

---

## 跳转

| 下一步 | 读哪篇 |
|---|---|
| 上游：这些 `sensor_*` 是谁发的 | [02_code_twin/drivers/hxy42688p](../drivers/hxy42688p.md)、[02_code_twin/drivers/h104_imu](../drivers/h104_imu.md)、[02_code_twin/drivers/ist8310](../drivers/ist8310.md)、[02_code_twin/drivers/spa06](../drivers/spa06.md) |
| 下游：`vehicle_imu` 被谁吃 | [02_code_twin/modules/ekf2](ekf2.md)、[02_code_twin/modules/control_allocator](control_allocator.md) |
| 六条流全景 | [03_moc/02-sensor-flow](../../03_moc/02-sensor-flow.md) |
| 队列/画像总论 | [03_moc/03-module-map](../../03_moc/03-module-map.md) |

---

## 标注源码（代码 + 本文档对它的解释）

> **这是「代码孪生」层**：上面是代码原文（带行号），下面是**本文档针对这一段说的话**。
> 行号可点，直接跳到 PX4 源码那一行。
### `build/rm2027_fmu-h743_default/generated_params/module_params.c`
<a id="src-build-rm2027-fmu-h743-default-generated-params-module-params-c-21373"></a>
**↓ 文档在讲这里：**[`build/rm2027_fmu-h743_default/generated_params/module_params.c:21373`](sensors.md#^src-build-rm2027-fmu-h743-default-generated-params-module-params-c-21373)

```c
 21370 │  * @category System
 21371 │  * @reboot_required True
 21372 │  */
▶21373 │ PARAM_DEFINE_INT32(SENS_IMU_MODE, 1);
 21374 │ 
 21375 │ /**
 21376 │  * Minimum height above ground when reliant on optical flow
```
> **说明**：1 | 按"实例号"配对，不按 device_id：第 i 个 sensor_accel 配第 i 个 sensor_gyro | :441-442 | ┃ 2 | 本板 SENS_IMU_MODE 缺省 = 1 ⇒ multi_mode=false ⇒ 两个 VehicleIMU 都跑在 wq:INS0 | build/.../generated_params/module_params.c:21373；:447-448 |
^src-build-rm2027-fmu-h743-default-generated-params-module-params-c-21373

<a id="src-build-rm2027-fmu-h743-default-generated-params-module-params-c-21550"></a>
**↓ 文档在讲这里：**[`build/rm2027_fmu-h743_default/generated_params/module_params.c:21550`](sensors.md#^src-build-rm2027-fmu-h743-default-generated-params-module-params-c-21550)

```c
 21547 │  * @category System
 21548 │  * @reboot_required True
 21549 │  */
▶21550 │ PARAM_DEFINE_INT32(SENS_MAG_MODE, 1);
 21551 │ 
 21552 │ /**
 21553 │  * Magnetometer auto calibration
```
> **说明**：vehicle_gps_position / vehicle_optical_flow | 本板无 GPS/光流器件，未核其初始化分支是否真的不建对象 | ┃ 本板 SENS_MAG_MODE 的实际运行值 | 生成参数表里缺省 1（module_params.c:21550），但运行时是否被板级脚本改过未核 |
^src-build-rm2027-fmu-h743-default-generated-params-module-params-c-21550

### `build/rm2027_fmu-h743_default/px4_boardconfig.h`
<a id="src-build-rm2027-fmu-h743-default-px4-boardconfig-h-156"></a>
**↓ 文档在讲这里：**[`build/rm2027_fmu-h743_default/px4_boardconfig.h:156`](sensors.md#^src-build-rm2027-fmu-h743-default-px4-boardconfig-h-156)

```c
   153 │ #define CONFIG_WQ_I2C3_PRIORITY -11
   154 │ #define CONFIG_WQ_I2C4_PRIORITY -12
   155 │ #define CONFIG_WQ_NAV_AND_CONTROLLERS_STACKSIZE 2240
▶  156 │ #define CONFIG_WQ_NAV_AND_CONTROLLERS_PRIORITY -13
   157 │ #define CONFIG_WQ_VTE_STACKSIZE 6000
   158 │ #define CONFIG_WQ_VTE_PRIORITY -14
   159 │ #define CONFIG_WQ_INS_STACKSIZE 6000
```
> **说明**：入口函数 | sensors_main | src/modules/sensors/CMakeLists.txt（px4_add_module MAIN sensors） | ┃ 队列 | wq:nav_and_controllers（本板优先级 -13） | sensors.cpp:50；优先级 build/rm2027_fmu-h743_default/px4_boardconfig.h:156 |
^src-build-rm2027-fmu-h743-default-px4-boardconfig-h-156

### `src/drivers/imu/hipnuc_h104/H104IMU.cpp`
<a id="src-src-drivers-imu-hipnuc-h104-H104IMU-cpp-58"></a>
**↓ 文档在讲这里：**[`src/drivers/imu/hipnuc_h104/H104IMU.cpp:58`](sensors.md#^src-src-drivers-imu-hipnuc-h104-H104IMU-cpp-58)

```c
    55 │ 	_port(port),
    56 │ 	_device_id(device_id),
    57 │ 	_rotation(rotation),
▶   58 │ 	_px4_accel(device_id, rotation, true /* external：外挂模块 */),
    59 │ 	_px4_gyro(device_id, rotation, true /* external */),
    60 │ 	_perf_frames(perf_alloc(PC_COUNT, "h104_imu: frames")),
    61 │ 	_perf_crc_bad(perf_alloc(PC_COUNT, "h104_imu: crc bad")),
```
> **说明**：CAL_ACCx_PRIO 缺省 -1（未初始化）⇒ 回落到 _external ? 75 : 50（Accelerometer.cpp:201、Gyroscope.hpp:50）。 ┃ 本板：hxy 用 -s 拉起 ⇒ internal ⇒ 50；h104 驱动里硬写 external=true ⇒ 75（H104IMU.cpp:58）。
^src-src-drivers-imu-hipnuc-h104-H104IMU-cpp-58

### `src/lib/sensor_calibration/Accelerometer.cpp`
<a id="src-src-lib-sensor-calibration-Accelerometer-cpp-201"></a>
**↓ 文档在讲这里：**[`src/lib/sensor_calibration/Accelerometer.cpp:201`](sensors.md#^src-src-lib-sensor-calibration-Accelerometer-cpp-201)

```c
   198 │ 		}
   199 │ 
   200 │ 		// CAL_ACCx_PRIO
▶  201 │ 		_priority = GetCalibrationParamInt32(SensorString(), "PRIO", _calibration_index);
   202 │ 
   203 │ 		if ((_priority < 0) || (_priority > 100)) {
   204 │ 			// reset to default, -1 is the uninitialized parameter value
```
> **说明**：★ 缺省优先级不是 50 一律（这是本板双 IMU 的关键） ┃ CAL_ACCx_PRIO 缺省 -1（未初始化）⇒ 回落到 _external ? 75 : 50（Accelerometer.cpp:201、Gyroscope.hpp:50）。
^src-src-lib-sensor-calibration-Accelerometer-cpp-201

### `src/lib/sensor_calibration/Gyroscope.hpp`
<a id="src-src-lib-sensor-calibration-Gyroscope-hpp-50"></a>
**↓ 文档在讲这里：**[`src/lib/sensor_calibration/Gyroscope.hpp:50`](sensors.md#^src-src-lib-sensor-calibration-Gyroscope-hpp-50)

```c
    47 │ public:
    48 │ 	static constexpr int MAX_SENSOR_COUNT = 4;
    49 │ 
▶   50 │ 	static constexpr uint8_t DEFAULT_PRIORITY = 50;
    51 │ 	static constexpr uint8_t DEFAULT_EXTERNAL_PRIORITY = 75;
    52 │ 
    53 │ 	static constexpr const char *SensorString() { return "GYRO"; }
```
> **说明**：★ 缺省优先级不是 50 一律（这是本板双 IMU 的关键） ┃ CAL_ACCx_PRIO 缺省 -1（未初始化）⇒ 回落到 _external ? 75 : 50（Accelerometer.cpp:201、Gyroscope.hpp:50）。
^src-src-lib-sensor-calibration-Gyroscope-hpp-50

### `src/modules/ekf2/EKF2.hpp`
<a id="src-src-modules-ekf2-EKF2-hpp-324"></a>
**↓ 文档在讲这里：**[`src/modules/ekf2/EKF2.hpp:324`](sensors.md#^src-src-modules-ekf2-EKF2-hpp-324)

```c
   321 │ 
   322 │ 	hrt_abstime _status_mag_pub_last{0};
   323 │ 
▶  324 │ 	uORB::Subscription _magnetometer_sub{ORB_ID(vehicle_magnetometer)};
   325 │ 
   326 │ 	uORB::PublicationMulti<estimator_aid_source3d_s> _estimator_aid_src_mag_pub{ORB_ID(estimator_aid_src_mag)};
   327 │ #endif // CONFIG_EKF2_MAGNETOMETER
```
> **说明**：vehicle_air_data | VehicleAirData.hpp:97 | ekf2(EKF2.hpp:373)、mavlink(HIGHRES_IMU.hpp:72)、logger(:139) | ┃ vehicle_magnetometer | VehicleMagnetometer.hpp:105（4 实例） | ekf2(EKF2.hpp:324)、mavlink、logger(:152) |
^src-src-modules-ekf2-EKF2-hpp-324

<a id="src-src-modules-ekf2-EKF2-hpp-373"></a>
**↓ 文档在讲这里：**[`src/modules/ekf2/EKF2.hpp:373`](sensors.md#^src-src-modules-ekf2-EKF2-hpp-373)

```c
   370 │ 
   371 │ 	float _last_baro_bias_published{};
   372 │ 
▶  373 │ 	uORB::Subscription _airdata_sub{ORB_ID(vehicle_air_data)};
   374 │ 
   375 │ 	uORB::PublicationMulti<estimator_bias_s> _estimator_baro_bias_pub{ORB_ID(estimator_baro_bias)};
   376 │ 	uORB::PublicationMulti<estimator_aid_source1d_s> _estimator_aid_src_baro_hgt_pub {ORB_ID(estimator_aid_src_baro_hgt)};
```
> **说明**：vehicle_imu_status | VehicleIMU.cpp:638（先于 vehicle_imu 发，见 :574-575 注释：让误差计数"同步可用"） | sensors 自己的投票器、vehicle_acceleration/angular_velocity、logger(:234) | ┃ vehicle_air_data | VehicleAirData.hpp:97 | ekf2(EKF2.hpp:373)、mavlink(HIGHRES_IMU.hpp:72)、logger(:139) |
^src-src-modules-ekf2-EKF2-hpp-373

<a id="src-src-modules-ekf2-EKF2-hpp-433"></a>
**↓ 文档在讲这里：**[`src/modules/ekf2/EKF2.hpp:433`](sensors.md#^src-src-modules-ekf2-EKF2-hpp-433)

```c
   430 │ 	void handleSensorFusionCommand(const vehicle_command_s &cmd, vehicle_command_ack_s &ack);
   431 │ 	void syncSensEnParam();
   432 │ 
▶  433 │ 	uORB::SubscriptionCallbackWorkItem _sensor_combined_sub{this, ORB_ID(sensor_combined)};
   434 │ 	uORB::SubscriptionCallbackWorkItem _vehicle_imu_sub{this, ORB_ID(vehicle_imu)};
   435 │ 
   436 │ #if defined(CONFIG_EKF2_RANGE_FINDER)
```
> **说明**：sensor_combined | sensors.cpp:606（_sensor_pub，sensors.hpp:161） | ekf2(EKF2.hpp:433)、attitude_estimator_q、local_position_estimator、logger(logged_topics.cpp:126) |
^src-src-modules-ekf2-EKF2-hpp-433

<a id="src-src-modules-ekf2-EKF2-hpp-434"></a>
**↓ 文档在讲这里：**[`src/modules/ekf2/EKF2.hpp:434`](sensors.md#^src-src-modules-ekf2-EKF2-hpp-434)

```c
   431 │ 	void syncSensEnParam();
   432 │ 
   433 │ 	uORB::SubscriptionCallbackWorkItem _sensor_combined_sub{this, ORB_ID(sensor_combined)};
▶  434 │ 	uORB::SubscriptionCallbackWorkItem _vehicle_imu_sub{this, ORB_ID(vehicle_imu)};
   435 │ 
   436 │ #if defined(CONFIG_EKF2_RANGE_FINDER)
   437 │ 	hrt_abstime _status_rng_hgt_pub_last {0};
```
> **说明**：sensor_combined | sensors.cpp:606（_sensor_pub，sensors.hpp:161） | ekf2(EKF2.hpp:433)、attitude_estimator_q、local_position_estimator、logger(logged_topics.cpp:126) | ┃ vehicle_imu | VehicleIMU.cpp:664 —— 独立工作队列对象，不是 Run() 里产的 | ekf2(EKF2.hpp:434)、mavlink(HIGHRES_IMU.hpp:66)、logger(:233) |
^src-src-modules-ekf2-EKF2-hpp-434

### `src/modules/logger/logged_topics.cpp`
<a id="src-src-modules-logger-logged-topics-cpp-126"></a>
**↓ 文档在讲这里：**[`src/modules/logger/logged_topics.cpp:126`](sensors.md#^src-src-modules-logger-logged-topics-cpp-126)

```c
   123 │ 	add_topic("rtl_time_estimate", 1000);
   124 │ 	add_topic("rtl_status", 2000);
   125 │ 	add_optional_topic("sensor_airflow", 100);
▶  126 │ 	add_topic("sensor_combined");
   127 │ 	add_optional_topic("sensor_correction");
   128 │ 	add_optional_topic("sensor_gyro_fft", 50);
   129 │ 	add_topic("sensor_selection");
```
> **说明**：sensor_combined | sensors.cpp:606（_sensor_pub，sensors.hpp:161） | ekf2(EKF2.hpp:433)、attitude_estimator_q、local_position_estimator、logger(logged_topics.cpp:126) |
^src-src-modules-logger-logged-topics-cpp-126

### `src/modules/mavlink/streams/HIGHRES_IMU.hpp`
<a id="src-src-modules-mavlink-streams-HIGHRES-IMU-hpp-66"></a>
**↓ 文档在讲这里：**[`src/modules/mavlink/streams/HIGHRES_IMU.hpp:66`](sensors.md#^src-src-modules-mavlink-streams-HIGHRES-IMU-hpp-66)

```c
    63 │ private:
    64 │ 	explicit MavlinkStreamHighresIMU(Mavlink *mavlink) : MavlinkStream(mavlink) {}
    65 │ 
▶   66 │ 	uORB::SubscriptionMultiArray<vehicle_imu_s, 4> _vehicle_imu_subs{ORB_ID::vehicle_imu};
    67 │ 	uORB::Subscription _estimator_sensor_bias_sub{ORB_ID(estimator_sensor_bias)};
    68 │ 	uORB::Subscription _estimator_selector_status_sub{ORB_ID(estimator_selector_status)};
    69 │ 	uORB::Subscription _sensor_selection_sub{ORB_ID(sensor_selection)};
```
> **说明**：sensor_combined | sensors.cpp:606（_sensor_pub，sensors.hpp:161） | ekf2(EKF2.hpp:433)、attitude_estimator_q、local_position_estimator、logger(logged_topics.cpp:126) | ┃ vehicle_imu | VehicleIMU.cpp:664 —— 独立工作队列对象，不是 Run() 里产的 | ekf2(EKF2.hpp:434)、mavlink(HIGHRES_IMU.hpp:66)、logger(:233) |
^src-src-modules-mavlink-streams-HIGHRES-IMU-hpp-66

<a id="src-src-modules-mavlink-streams-HIGHRES-IMU-hpp-72"></a>
**↓ 文档在讲这里：**[`src/modules/mavlink/streams/HIGHRES_IMU.hpp:72`](sensors.md#^src-src-modules-mavlink-streams-HIGHRES-IMU-hpp-72)

```c
    69 │ 	uORB::Subscription _sensor_selection_sub{ORB_ID(sensor_selection)};
    70 │ 	uORB::Subscription _differential_pressure_sub{ORB_ID(differential_pressure)};
    71 │ 	uORB::Subscription _magnetometer_sub{ORB_ID(vehicle_magnetometer)};
▶   72 │ 	uORB::Subscription _air_data_sub{ORB_ID(vehicle_air_data)};
    73 │ 
    74 │ 	bool send() override
    75 │ 	{
```
> **说明**：vehicle_imu_status | VehicleIMU.cpp:638（先于 vehicle_imu 发，见 :574-575 注释：让误差计数"同步可用"） | sensors 自己的投票器、vehicle_acceleration/angular_velocity、logger(:234) | ┃ vehicle_air_data | VehicleAirData.hpp:97 | ekf2(EKF2.hpp:373)、mavlink(HIGHRES_IMU.hpp:72)、logger(:139) |
^src-src-modules-mavlink-streams-HIGHRES-IMU-hpp-72

### `src/modules/mc_rate_control/MulticopterRateControl.hpp`
<a id="src-src-modules-mc-rate-control-MulticopterRateControl-hpp-107"></a>
**↓ 文档在讲这里：**[`src/modules/mc_rate_control/MulticopterRateControl.hpp:107`](sensors.md#^src-src-modules-mc-rate-control-MulticopterRateControl-hpp-107)

```c
   104 │ 
   105 │ 	uORB::SubscriptionInterval _parameter_update_sub{ORB_ID(parameter_update), 1_s};
   106 │ 
▶  107 │ 	uORB::SubscriptionCallbackWorkItem _vehicle_angular_velocity_sub{this, ORB_ID(vehicle_angular_velocity)};
   108 │ 
   109 │ 	uORB::Publication<actuator_controls_status_s>	_actuator_controls_status_pub{ORB_ID(actuator_controls_status_0)};
   110 │ 	uORB::PublicationMulti<rate_ctrl_status_s>	_controller_status_pub{ORB_ID(rate_ctrl_status)};
```
> **说明**：vehicle_magnetometer | VehicleMagnetometer.hpp:105（4 实例） | ekf2(EKF2.hpp:324)、mavlink、logger(:152) | ┃ vehicle_acceleration / vehicle_angular_velocity | VehicleAcceleration.hpp:80 / VehicleAngularVelocity.hpp:101 | mc_att_control / mc_rate_control(MulticopterRateControl.hpp:107) |
^src-src-modules-mc-rate-control-MulticopterRateControl-hpp-107

### `src/modules/sensors/sensors.cpp`
<a id="src-src-modules-sensors-sensors-cpp-50"></a>
**↓ 文档在讲这里：**[`src/modules/sensors/sensors.cpp:50`](sensors.md#^src-src-modules-sensors-sensors-cpp-50)

```c
    47 │ 
    48 │ Sensors::Sensors(bool hil_enabled) :
    49 │ 	ModuleParams(nullptr),
▶   50 │ 	ScheduledWorkItem(MODULE_NAME, px4::wq_configurations::nav_and_controllers),
    51 │ 	_hil_enabled(hil_enabled),
    52 │ 	_loop_perf(perf_alloc(PC_ELAPSED, "sensors")),
    53 │ 	_voted_sensors_update(hil_enabled, _vehicle_imu_sub)
```
> **说明**：入口函数 | sensors_main | src/modules/sensors/CMakeLists.txt（px4_add_module MAIN sensors） | ┃ 队列 | wq:nav_and_controllers（本板优先级 -13） | sensors.cpp:50；优先级 build/rm2027_fmu-h743_default/px4_boardconfig.h:156 |
^src-src-modules-sensors-sensors-cpp-50

<a id="src-src-modules-sensors-sensors-cpp-502"></a>
**↓ 文档在讲这里：**[`src/modules/sensors/sensors.cpp:502`](sensors.md#^src-src-modules-sensors-sensors-cpp-502)

```c
   499 │ }
   500 │ #endif // CONFIG_SENSORS_VEHICLE_OPTICAL_FLOW
   501 │ 
▶  502 │ void Sensors::Run()
   503 │ {
   504 │ 	if (should_exit()) {
   505 │ 		// clear all registered callbacks
```
> **说明**：2. Run() 一步不差（sensors.cpp:502）
^src-src-modules-sensors-sensors-cpp-502

<a id="src-src-modules-sensors-sensors-cpp-606"></a>
**↓ 文档在讲这里：**[`src/modules/sensors/sensors.cpp:606`](sensors.md#^src-src-modules-sensors-sensors-cpp-606)

```c
   603 │ 	if (_sensor_combined.timestamp != _sensor_combined_prev_timestamp) {
   604 │ 
   605 │ 		_voted_sensors_update.setRelativeTimestamps(_sensor_combined);
▶  606 │ 		_sensor_pub.publish(_sensor_combined);
   607 │ 		_sensor_combined_prev_timestamp = _sensor_combined.timestamp;
   608 │ 	}
   609 │ 
```
> **说明**：sensor_combined | sensors.cpp:606（_sensor_pub，sensors.hpp:161） | ekf2(EKF2.hpp:433)、attitude_estimator_q、local_position_estimator、logger(logged_topics.cpp:126) |
^src-src-modules-sensors-sensors-cpp-606

<a id="src-src-modules-sensors-sensors-cpp-617"></a>
**↓ 文档在讲这里：**[`src/modules/sensors/sensors.cpp:617`](sensors.md#^src-src-modules-sensors-sensors-cpp-617)

```c
   614 │ #endif // CONFIG_SENSORS_VEHICLE_AIRSPEED
   615 │ 
   616 │ 	// backup schedule as a watchdog timeout
▶  617 │ 	ScheduleDelayed(10_ms);
   618 │ 
   619 │ 	perf_end(_loop_perf);
   620 │ }
```
> **说明**：队列 | wq:nav_and_controllers（本板优先级 -13） | sensors.cpp:50；优先级 build/rm2027_fmu-h743_default/px4_boardconfig.h:156 | ┃ 调度 | ScheduleDelayed(10_ms) 兜底（被订阅回调提前唤醒） | sensors.cpp:617 |
^src-src-modules-sensors-sensors-cpp-617

### `src/modules/sensors/sensors.hpp`
<a id="src-src-modules-sensors-sensors-hpp-161"></a>
**↓ 文档在讲这里：**[`src/modules/sensors/sensors.hpp:161`](sensors.md#^src-src-modules-sensors-sensors-hpp-161)

```c
   158 │ 	uORB::SubscriptionInterval _parameter_update_sub{ORB_ID(parameter_update), 1_s};
   159 │ 	uORB::Subscription _vcontrol_mode_sub{ORB_ID(vehicle_control_mode)};
   160 │ 
▶  161 │ 	uORB::Publication<sensor_combined_s> _sensor_pub{ORB_ID(sensor_combined)};
   162 │ 
   163 │ #if defined(CONFIG_SENSORS_VEHICLE_AIRSPEED)
   164 │ 	/**
```
> **说明**：sensor_combined | sensors.cpp:606（_sensor_pub，sensors.hpp:161） | ekf2(EKF2.hpp:433)、attitude_estimator_q、local_position_estimator、logger(logged_topics.cpp:126) |
^src-src-modules-sensors-sensors-hpp-161

### `src/modules/sensors/vehicle_acceleration/VehicleAcceleration.hpp`
<a id="src-src-modules-sensors-vehicle-acceleration-VehicleAcceleration-hpp-80"></a>
**↓ 文档在讲这里：**[`src/modules/sensors/vehicle_acceleration/VehicleAcceleration.hpp:80`](sensors.md#^src-src-modules-sensors-vehicle-acceleration-VehicleAcceleration-hpp-80)

```c
    77 │ 
    78 │ 	static constexpr int MAX_SENSOR_COUNT = 4;
    79 │ 
▶   80 │ 	uORB::Publication<vehicle_acceleration_s> _vehicle_acceleration_pub{ORB_ID(vehicle_acceleration)};
    81 │ 
    82 │ 	uORB::Subscription _estimator_selector_status_sub{ORB_ID(estimator_selector_status)};
    83 │ 	uORB::Subscription _estimator_sensor_bias_sub{ORB_ID(estimator_sensor_bias)};
```
> **说明**：vehicle_magnetometer | VehicleMagnetometer.hpp:105（4 实例） | ekf2(EKF2.hpp:324)、mavlink、logger(:152) | ┃ vehicle_acceleration / vehicle_angular_velocity | VehicleAcceleration.hpp:80 / VehicleAngularVelocity.hpp:101 | mc_att_control / mc_rate_control(MulticopterRateControl.hpp:107) |
^src-src-modules-sensors-vehicle-acceleration-VehicleAcceleration-hpp-80

### `src/modules/sensors/vehicle_air_data/VehicleAirData.hpp`
<a id="src-src-modules-sensors-vehicle-air-data-VehicleAirData-hpp-97"></a>
**↓ 文档在讲这里：**[`src/modules/sensors/vehicle_air_data/VehicleAirData.hpp:97`](sensors.md#^src-src-modules-sensors-vehicle-air-data-VehicleAirData-hpp-97)

```c
    94 │ 
    95 │ 	uORB::Publication<sensors_status_s> _sensors_status_baro_pub{ORB_ID(sensors_status_baro)};
    96 │ 
▶   97 │ 	uORB::Publication<vehicle_air_data_s> _vehicle_air_data_pub{ORB_ID(vehicle_air_data)};
    98 │ 
    99 │ 	uORB::SubscriptionInterval _parameter_update_sub{ORB_ID(parameter_update), 1_s};
   100 │ 
```
> **说明**：vehicle_imu_status | VehicleIMU.cpp:638（先于 vehicle_imu 发，见 :574-575 注释：让误差计数"同步可用"） | sensors 自己的投票器、vehicle_acceleration/angular_velocity、logger(:234) | ┃ vehicle_air_data | VehicleAirData.hpp:97 | ekf2(EKF2.hpp:373)、mavlink(HIGHRES_IMU.hpp:72)、logger(:139) |
^src-src-modules-sensors-vehicle-air-data-VehicleAirData-hpp-97

### `src/modules/sensors/vehicle_angular_velocity/VehicleAngularVelocity.cpp`
<a id="src-src-modules-sensors-vehicle-angular-velocity-VehicleAngularVelocity-cpp-47"></a>
**↓ 文档在讲这里：**[`src/modules/sensors/vehicle_angular_velocity/VehicleAngularVelocity.cpp:47`](sensors.md#^src-src-modules-sensors-vehicle-angular-velocity-VehicleAngularVelocity-cpp-47)

```c
    44 │ 
    45 │ VehicleAngularVelocity::VehicleAngularVelocity() :
    46 │ 	ModuleParams(nullptr),
▶   47 │ 	ScheduledWorkItem(MODULE_NAME, px4::wq_configurations::rate_ctrl)
    48 │ {
    49 │ 	_vehicle_angular_velocity_pub.advertise();
    50 │ }
```
> **说明**：★ vehicle_angular_velocity 跑在 wq:rate_ctrl（优先级 0）（VehicleAngularVelocity.cpp:47），
^src-src-modules-sensors-vehicle-angular-velocity-VehicleAngularVelocity-cpp-47

### `src/modules/sensors/vehicle_angular_velocity/VehicleAngularVelocity.hpp`
<a id="src-src-modules-sensors-vehicle-angular-velocity-VehicleAngularVelocity-hpp-101"></a>
**↓ 文档在讲这里：**[`src/modules/sensors/vehicle_angular_velocity/VehicleAngularVelocity.hpp:101`](sensors.md#^src-src-modules-sensors-vehicle-angular-velocity-VehicleAngularVelocity-hpp-101)

```c
    98 │ 
    99 │ 	static constexpr int MAX_SENSOR_COUNT = 4;
   100 │ 
▶  101 │ 	uORB::Publication<vehicle_angular_velocity_s>     _vehicle_angular_velocity_pub{ORB_ID(vehicle_angular_velocity)};
   102 │ 
   103 │ 	uORB::Subscription _estimator_selector_status_sub{ORB_ID(estimator_selector_status)};
   104 │ 	uORB::Subscription _estimator_sensor_bias_sub{ORB_ID(estimator_sensor_bias)};
```
> **说明**：vehicle_magnetometer | VehicleMagnetometer.hpp:105（4 实例） | ekf2(EKF2.hpp:324)、mavlink、logger(:152) | ┃ vehicle_acceleration / vehicle_angular_velocity | VehicleAcceleration.hpp:80 / VehicleAngularVelocity.hpp:101 | mc_att_control / mc_rate_control(MulticopterRateControl.hpp:107) |
^src-src-modules-sensors-vehicle-angular-velocity-VehicleAngularVelocity-hpp-101

### `src/modules/sensors/vehicle_imu/VehicleIMU.cpp`
<a id="src-src-modules-sensors-vehicle-imu-VehicleIMU-cpp-254"></a>
**↓ 文档在讲这里：**[`src/modules/sensors/vehicle_imu/VehicleIMU.cpp:254`](sensors.md#^src-src-modules-sensors-vehicle-imu-VehicleIMU-cpp-254)

```c
   251 │ 			continue;
   252 │ 		}
   253 │ 
▶  254 │ 		// publish if both accel & gyro integrators are ready
   255 │ 		if (_intervals_configured && _accel_integrator.integral_ready() && _gyro_integrator.integral_ready()) {
   256 │ 			if (Publish()) {
   257 │ 				break;
```
> **说明**：sensors status 里某一路 priority = 0 ⇒ 被 CAL_*_PRIO = 0 显式禁用，或 CAL_*_ID 没写上。 ┃ vehicle_imu 频率远低于 1000 Hz 而 sensor_gyro 是 1000 Hz ⇒ 卡在积分/发布条件（VehicleIMU.cpp:254 附近"accel & gyro 积分器都就绪才发"）。
^src-src-modules-sensors-vehicle-imu-VehicleIMU-cpp-254

<a id="src-src-modules-sensors-vehicle-imu-VehicleIMU-cpp-638"></a>
**↓ 文档在讲这里：**[`src/modules/sensors/vehicle_imu/VehicleIMU.cpp:638`](sensors.md#^src-src-modules-sensors-vehicle-imu-VehicleIMU-cpp-638)

```c
   635 │ 
   636 │ 				// publish
   637 │ 				_status.timestamp = hrt_absolute_time();
▶  638 │ 				_vehicle_imu_status_pub.publish(_status);
   639 │ 
   640 │ 				_publish_status = false;
   641 │ 
```
> **说明**：vehicle_imu | VehicleIMU.cpp:664 —— 独立工作队列对象，不是 Run() 里产的 | ekf2(EKF2.hpp:434)、mavlink(HIGHRES_IMU.hpp:66)、logger(:233) | ┃ vehicle_imu_status | VehicleIMU.cpp:638（先于 vehicle_imu 发，见 :574-575 注释：让误差计数"同步可用"） | sensors 自己的投票器、vehicle_acceleration/angular_velocity、logger(:234) |
^src-src-modules-sensors-vehicle-imu-VehicleIMU-cpp-638

<a id="src-src-modules-sensors-vehicle-imu-VehicleIMU-cpp-664"></a>
**↓ 文档在讲这里：**[`src/modules/sensors/vehicle_imu/VehicleIMU.cpp:664`](sensors.md#^src-src-modules-sensors-vehicle-imu-VehicleIMU-cpp-664)

```c
   661 │ 			imu.accel_calibration_count = _accel_calibration.calibration_count();
   662 │ 			imu.gyro_calibration_count = _gyro_calibration.calibration_count();
   663 │ 			imu.timestamp = hrt_absolute_time();
▶  664 │ 			_vehicle_imu_pub.publish(imu);
   665 │ 
   666 │ 			// reset clip counts
   667 │ 			_delta_angle_clipping = 0;
```
> **说明**：sensor_combined | sensors.cpp:606（_sensor_pub，sensors.hpp:161） | ekf2(EKF2.hpp:433)、attitude_estimator_q、local_position_estimator、logger(logged_topics.cpp:126) | ┃ vehicle_imu | VehicleIMU.cpp:664 —— 独立工作队列对象，不是 Run() 里产的 | ekf2(EKF2.hpp:434)、mavlink(HIGHRES_IMU.hpp:66)、logger(:233) |
^src-src-modules-sensors-vehicle-imu-VehicleIMU-cpp-664

### `src/modules/sensors/vehicle_magnetometer/VehicleMagnetometer.hpp`
<a id="src-src-modules-sensors-vehicle-magnetometer-VehicleMagnetometer-hpp-105"></a>
**↓ 文档在讲这里：**[`src/modules/sensors/vehicle_magnetometer/VehicleMagnetometer.hpp:105`](sensors.md#^src-src-modules-sensors-vehicle-magnetometer-VehicleMagnetometer-hpp-105)

```c
   102 │ 	uORB::Publication<sensor_preflight_mag_s> _sensor_preflight_mag_pub{ORB_ID(sensor_preflight_mag)};
   103 │ 
   104 │ 	uORB::PublicationMulti<vehicle_magnetometer_s> _vehicle_magnetometer_pub[MAX_SENSOR_COUNT] {
▶  105 │ 		{ORB_ID(vehicle_magnetometer)},
   106 │ 		{ORB_ID(vehicle_magnetometer)},
   107 │ 		{ORB_ID(vehicle_magnetometer)},
   108 │ 		{ORB_ID(vehicle_magnetometer)},
```
> **说明**：vehicle_air_data | VehicleAirData.hpp:97 | ekf2(EKF2.hpp:373)、mavlink(HIGHRES_IMU.hpp:72)、logger(:139) | ┃ vehicle_magnetometer | VehicleMagnetometer.hpp:105（4 实例） | ekf2(EKF2.hpp:324)、mavlink、logger(:152) |
^src-src-modules-sensors-vehicle-magnetometer-VehicleMagnetometer-hpp-105

### `src/modules/sensors/voted_sensors_update.cpp`
<a id="src-src-modules-sensors-voted-sensors-update-cpp-70"></a>
**↓ 文档在讲这里：**[`src/modules/sensors/voted_sensors_update.cpp:70`](sensors.md#^src-src-modules-sensors-voted-sensors-update-cpp-70)

```c
    67 │ 	parametersUpdate();
    68 │ }
    69 │ 
▶   70 │ void VotedSensorsUpdate::initializeSensors()
    71 │ {
    72 │ 	initSensorClass(_gyro, MAX_SENSOR_COUNT);
    73 │ 	initSensorClass(_accel, MAX_SENSOR_COUNT);
```
> **说明**：建投票器 | initSensorClass(_gyro, 4) / (_accel, 4)，新传感器 = voter.add_new_validator() | voted_sensors_update.cpp:70、:368 |
^src-src-modules-sensors-voted-sensors-update-cpp-70

### `src/modules/sensors/voted_sensors_update.h`
<a id="src-src-modules-sensors-voted-sensors-update-h-65"></a>
**↓ 文档在讲这里：**[`src/modules/sensors/voted_sensors_update.h:65`](sensors.md#^src-src-modules-sensors-voted-sensors-update-h-65)

```c
    62 │ namespace sensors
    63 │ {
    64 │ 
▶   65 │ static constexpr uint8_t MAX_SENSOR_COUNT = 4;
    66 │ 
    67 │ /**
    68 │  ** class VotedSensorsUpdate
```
> **说明**：拉起 | rcS:440 sensors start —— 在 rc.board_sensors(:424) 与 rc.sensors(:428) 之后 | ROMFS/px4fmu_common/init.d/rcS | ┃ 上限 | MAX_SENSOR_COUNT = 4 | src/modules/sensors/voted_sensors_update.h:65 |
^src-src-modules-sensors-voted-sensors-update-h-65

<a id="src-src-modules-sensors-voted-sensors-update-h-155"></a>
**↓ 文档在讲这里：**[`src/modules/sensors/voted_sensors_update.h:155`](sensors.md#^src-src-modules-sensors-voted-sensors-update-h-155)

```c
   152 │ 	hrt_abstime _last_error_message{0};
   153 │ 	orb_advert_t _mavlink_log_pub{nullptr};
   154 │ 
▶  155 │ 	uORB::Publication<sensor_selection_s> _sensor_selection_pub{ORB_ID(sensor_selection)};	/**< handle to the sensor selection uORB topic */
   156 │ 	uORB::Publication<sensors_status_imu_s> _sensors_status_imu_pub{ORB_ID(sensors_status_imu)};
   157 │ 
   158 │ 	uORB::SubscriptionCallbackWorkItem(&_vehicle_imu_sub)[MAX_SENSOR_COUNT];
```
> **说明**：投票 | _accel/…voter（DataValidator，src/modules/sensors/data_validator/） | :146-147 的 imuPoll 入口 | ┃ 产出选源 | sensor_selection（accel_device_id/gyro_device_id） | voted_sensors_update.h:155 |
^src-src-modules-sensors-voted-sensors-update-h-155
