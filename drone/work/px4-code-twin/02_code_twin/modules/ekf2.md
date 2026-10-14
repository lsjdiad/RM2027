# `src/modules/ekf2/EKF2.cpp` —— 状态估计器（六条流的第一个汇合点）

> **运行时一句话**：它**不直接读任何 `sensor_*`**。它只吃 `sensors` 归一化过的 `vehicle_imu` / `vehicle_air_data` / `vehicle_magnetometer` / `sensor_combined`，吐出**姿态、位置、速度、状态标志**。
> **⇒ 它是"传感器数据"变成"飞行器状态"的那一跳。**
> 行号基准 `源码根（见 `tools/source-root.conf`）` HEAD `3b5de24`。

---

## 1. 它活在哪（单实例 vs 多实例）

| 模式 | 对象 | 队列 | 出处 |
|---|---|---|---|
| **单实例（本板缺省）** | 一个 `EKF2` 直接建在 `wq:INS0` | `wq:INS0`（本板优先级 **-14**） | [`EKF2.cpp:3142`](ekf2.md#^src-src-modules-ekf2-EKF2-cpp-3142) `new EKF2(false, px4::wq_configurations::INS0, replay_mode)` |
| 多实例（`EKF2_MULTI_IMU > 0`） | 一个 `EKF2Selector` + 每个 IMU 一个 `EKF2` | selector 在 `wq:nav_and_controllers`；每个 `EKF2` 在 `ins_instance_to_wq(imu)` | [`EKF2.cpp:3055`](ekf2.md#^src-src-modules-ekf2-EKF2-cpp-3055)、`:3094`；selector 队列 [`EKF2Selector.cpp:44`](ekf2.md#^src-src-modules-ekf2-EKF2Selector-cpp-44) |

```
EKF2.hpp:135   class EKF2 final : public ModuleParams, public px4::ScheduledWorkItem
EKF2.cpp:51-53 EKF2::EKF2(...) : ScheduledWorkItem(MODULE_NAME, config)
EKF2.cpp:2984  EKF2::task_spawn(int argc, char *argv[])      ← `ekf2 start` 落到这里
EKF2.cpp:3012  读 EKF2_MULTI_IMU（超 3 会 clamp 并 PX4_WARN）  ← :3007 起
EKF2.cpp:3142  单实例路径
```

**拉起**：`rcS:446-449` `if param compare -s EKF2_EN 1 → ekf2 start &`
（`EKF2_EN` 本板缺省 **1**，[`build/rm2027_fmu-h743_default/generated_params/module_params.c:8216`](ekf2.md#^src-build-rm2027-fmu-h743-default-generated-params-module-params-c-8216)）

---

## 2. 谁驱动它跑（不是定时器，是"数据来了"）

```c
void EKF2::Run()                                   // EKF2.cpp:448
{
    if (should_exit()) { 注销回调; ... }             // :451-452
    ...
    if (无回调) {
        _callback_registered = _vehicle_imu_sub.registerCallback();      // :500  ★
        // 没 IMU 数据时才退回 sensor_combined
        _callback_registered = _sensor_combined_sub.registerCallback();  // :505
        ScheduleDelayed(10_ms);                                       // :509  兜底
    }
    ...
    ScheduleDelayed(100_ms);                                          // :890  长间隔兜底
}
```

**⇒ 关键语义**：`registerCallback()` = **"这个订阅有更新就把我排进工作队列"**。
所以 EKF2 的更新率 = `vehicle_imu` 的发布率（本板：hxy 1000 Hz / h104 100 Hz），不是固定周期。
`ScheduleDelayed` 只是"万一回调没来"的保命心跳。

> ⚠️ 这解释了本项目欠账中的一句：**「不提 `IMU_INTEG_RATE` 则提频白提」**。
> `vehicle_imu` 的发布率还受 `IMU_INTEG_RATE` 约束（[`src/modules/sensors/vehicle_imu/imu_parameters.yaml:5`](ekf2.md#^src-src-modules-sensors-vehicle-imu-imu-parameters-yaml-5)），
> 所以 H104 从 100 Hz 提到 200 Hz，只有 EKF2 侧真的按新频率吃才有意义。

---

## 3. 订阅清单（它到底吃什么）

| 话题 | 声明处 | 消费处 | 备注 |
|---|---|---|---|
| `sensor_combined` | [`EKF2.hpp:433`](sensors.md#^src-src-modules-ekf2-EKF2-hpp-433)（`SubscriptionCallbackWorkItem`） | `Run()` | 兜底源 |
| `vehicle_imu` | [`EKF2.hpp:434`](sensors.md#^src-src-modules-ekf2-EKF2-hpp-434)（同上） | [`EKF2.cpp:635`](ekf2.md#^src-src-modules-ekf2-EKF2-cpp-635) | **主源**；`:400 ChangeInstance(imu)` 换实例 |
| `vehicle_air_data` | [`EKF2.hpp:373`](sensors.md#^src-src-modules-ekf2-EKF2-hpp-373) | [`EKF2.cpp:2363`](ekf2.md#^src-src-modules-ekf2-EKF2-cpp-2363) | 气压高度 |
| `vehicle_magnetometer` | [`EKF2.hpp:324`](sensors.md#^src-src-modules-ekf2-EKF2-hpp-324) | [`EKF2.cpp:2708`](ekf2.md#^src-src-modules-ekf2-EKF2-cpp-2708) | 磁航向；`:404 ChangeInstance(mag)` |
| `vehicle_gps_position` | [`EKF2.hpp:501`](ekf2.md#^src-src-modules-ekf2-EKF2-hpp-501) | — | **本板永远没有发布者** ⇒ GPS 相关更新恒不触发 |
| `airspeed` / `airspeed_validated` | [`EKF2.hpp:385`](ekf2.md#^src-src-modules-ekf2-EKF2-hpp-385) | [`EKF2.cpp:2246`](ekf2.md#^src-src-modules-ekf2-EKF2-cpp-2246) 起 | 多旋翼不用 |
| `vehicle_optical_flow` | [`EKF2.hpp:358`](ekf2.md#^src-src-modules-ekf2-EKF2-hpp-358) | — | 本板无 |
| `sensor_selection` | [`EKF2.hpp:404`](ekf2.md#^src-src-modules-ekf2-EKF2-hpp-404) | [`EKF2.cpp:740`](ekf2.md#^src-src-modules-ekf2-EKF2-cpp-740) | ★ **"跟着 sensors 的投票结果换 IMU"** |
| `vehicle_status` | [`EKF2.hpp:405`](ekf2.md#^src-src-modules-ekf2-EKF2-hpp-405) | — | 上锁/解锁 |
| `vehicle_command` | [`EKF2.hpp:409`](ekf2.md#^src-src-modules-ekf2-EKF2-hpp-409) | — | 起飞/降落命令 |

**★ `sensor_selection` 这一跳是"双陀螺"的落点**（[`EKF2.cpp:740`](ekf2.md#^src-src-modules-ekf2-EKF2-cpp-740)）：
```c
if (_sensor_selection_sub.updated() || (_device_id_accel == 0 || _device_id_gyro == 0)) {
    if (_sensor_selection_sub.copy(&sensor_selection)) {
        if (_device_id_accel != sensor_selection.accel_device_id) { ...  }
        if (_device_id_gyro  != sensor_selection.gyro_device_id)  { ...  }
```
⇒ **EKF2 自己不选源，它照抄 `sensors` 的投票结论**（[`voted_sensors_update.h:155`](sensors.md#^src-src-modules-sensors-voted-sensors-update-h-155) 发布）。

---

## 4. 发布清单（它吐出什么、谁在等）

| 话题 | 声明/发布处 | 模式相关的名字 | 谁订 |
|---|---|---|---|
| `vehicle_attitude` | [`EKF2.hpp:478`](ekf2.md#^src-src-modules-ekf2-EKF2-hpp-478)（`_attitude_pub`）；构造 [`EKF2.cpp:57`](ekf2.md#^src-src-modules-ekf2-EKF2-cpp-57) 决定名字；发布 `EKF2.cpp:1187/1193` | 多实例时改叫 `estimator_attitude` | `mc_att_control`([`mc_att_control.hpp:115`](ekf2.md#^src-src-modules-mc-att-control-mc-att-control-hpp-115))、`mavlink`([`ATTITUDE.hpp:59`](mavlink.md#^src-src-modules-mavlink-streams-ATTITUDE-hpp-59))、`logger`(`:141`) |
| `vehicle_local_position` | [`EKF2.hpp:479`](ekf2.md#^src-src-modules-ekf2-EKF2-hpp-479)；发布 [`EKF2.cpp:1818`](ekf2.md#^src-src-modules-ekf2-EKF2-cpp-1818) | 多实例 → `estimator_local_position` | `mc_pos_control`([`MulticopterPositionControl.hpp:104`](ekf2.md#^src-src-modules-mc-pos-control-MulticopterPositionControl-hpp-104))、FMM(`:150`)、`logger`(`:150`) |
| `vehicle_global_position` | [`EKF2.hpp:480`](ekf2.md#^src-src-modules-ekf2-EKF2-hpp-480)；发布 [`EKF2.cpp:1377`](ekf2.md#^src-src-modules-ekf2-EKF2-cpp-1377) | → `estimator_global_position` | `commander`(HomePosition)、`navigator` |
| `vehicle_odometry` | [`EKF2.hpp:481`](ekf2.md#^src-src-modules-ekf2-EKF2-hpp-481) | → `estimator_odometry` | `mavlink`(ODOMETRY) |
| `wind` | [`EKF2.hpp:484`](ekf2.md#^src-src-modules-ekf2-EKF2-hpp-484)；构造 [`EKF2.cpp:62`](ekf2.md#^src-src-modules-ekf2-EKF2-cpp-62) | → `estimator_wind` | `logger` |
| `estimator_status` / `estimator_status_flags` | [`EKF2.hpp:472`](ekf2.md#^src-src-modules-ekf2-EKF2-hpp-472) / `:470` | — | `commander` 的 estimatorCheck、`logger` |
| `estimator_innovations` 三兄弟 | [`EKF2.hpp:465`](ekf2.md#^src-src-modules-ekf2-EKF2-hpp-465) | — | 排障用 |
| `estimator_aid_src_*`（baro_hgt / mag / gnss…） | `EKF2.hpp:330-376,505-519` | — | 看"哪一路观测被接受了"的唯一入口 |
| `estimator_sensor_bias` | [`EKF2.hpp:468`](ekf2.md#^src-src-modules-ekf2-EKF2-hpp-468) | — | `VehicleAcceleration/AngularVelocity` 用它做偏置补偿（[`VehicleAcceleration.hpp:83`](ekf2.md#^src-src-modules-sensors-vehicle-acceleration-VehicleAcceleration-hpp-83)） |

---

## 5. 参数：本板至少要认识的几个

| 参数 | 作用 | 定义处 |
|---|---|---|
| `EKF2_EN` | 1 = rcS 拉起 ekf2 | 生成参数 [`module_params.c:8216`](ekf2.md#^src-build-rm2027-fmu-h743-default-generated-params-module-params-c-8216) |
| `EKF2_MULTI_IMU` | 0 = 单实例（缺省）；>0 = 多实例 + selector | [`src/modules/ekf2/params_multi.yaml:5`](ekf2.md#^src-src-modules-ekf2-params-multi-yaml-5)；运行时读 [`EKF2.cpp:3007`](ekf2.md#^src-src-modules-ekf2-EKF2-cpp-3007) |
| `EKF2_MAG_TYPE` / `EKF2_BARO_CTRL` / `EKF2_GPS_CTRL` | 决定各观测源怎么用 | `src/modules/ekf2/params_magnetometer.yaml`、`params_barometer.yaml`、`params_gnss.yaml` |
| `EKF2_SEL_*` | selector 的容差/超时 | `src/modules/ekf2/params_selector.yaml` |

**⇒ 本板特殊点**：没有 GPS、没有光流、没有空速 ⇒ EKF2 实际只有 **IMU + 磁 + 气压** 三路观测。
气压定高没有 GNSS 校准，所以 `vehicle_local_position.z` 会缓慢漂 `[推理]`。

---

## 6. 判据

```sh
ekf2 status                 # 实例、队列、模式
listener estimator_status   # 看 flags / 各 aid source 的 fuse 状态
listener estimator_aid_src_baro_hgt
listener estimator_aid_src_mag
listener vehicle_attitude   # 有没有在发、频率多少
listener sensor_selection   # 它选中的 device_id
uorb top vehicle_imu estimator_status
```
- `estimator_status` 有值但 `vehicle_attitude` 不动 ⇒ 卡在姿态发布条件（[`EKF2.cpp:1187`](ekf2.md#^src-src-modules-ekf2-EKF2-cpp-1187) 附近）。
- `estimator_aid_src_mag` 一直 `fused=false` ⇒ 磁没被用（标定/fitness 问题）。

---

## 7. 未核实

| 事项 | 说明 |
|---|---|
| `EKF2.cpp:1187/1193` 两次 `_attitude_pub.publish` 的区别 | 只核到两个发布点，未展开上下文（可能是"有新样本 vs 心跳"） |
| `EKF2_MULTI_IMU` 在本板的实际取值 | 只核到缺省与 clamp 逻辑（`:3007-3013`），未从生成参数表回读 |
| `estimator_aid_src_*` 的完整清单 | 只列了与六条流相关的一部分（[`EKF2.hpp:326`](ekf2.md#^src-src-modules-ekf2-EKF2-hpp-326) 内还有 GNSS/EV/测距等） |
| `EKF2Selector` 的切换判据 | 只核到队列与 100ms 周期（`EKF2Selector.cpp:44,730,872`），未展开选优算法 |

---

## 跳转

| 下一步 | 读哪篇 |
|---|---|
| 上游：`vehicle_imu` 是谁产出的 | [02_code_twin/modules/sensors](sensors.md) |
| 下游：`vehicle_attitude` 被谁吃 | [02_code_twin/modules/control_allocator](control_allocator.md)（先经 mc_* 控制器）、[02_code_twin/modules/commander](commander.md) |
| 六条流全景 | [03_moc/02-sensor-flow](../../03_moc/02-sensor-flow.md) §7 汇合点 |
| 队列/画像总论 | [03_moc/03-module-map](../../03_moc/03-module-map.md) §4 |

---

## 标注源码（代码 + 本文档对它的解释）

> **这是「代码孪生」层**：上面是代码原文（带行号），下面是**本文档针对这一段说的话**。
> 行号可点，直接跳到 PX4 源码那一行。
### `build/rm2027_fmu-h743_default/generated_params/module_params.c`
<a id="src-build-rm2027-fmu-h743-default-generated-params-module-params-c-8216"></a>
**↓ 文档在讲这里：**[`build/rm2027_fmu-h743_default/generated_params/module_params.c:8216`](ekf2.md#^src-build-rm2027-fmu-h743-default-generated-params-module-params-c-8216)

```c
  8213 │  * @group EKF2
  8214 │  * @boolean
  8215 │  */
▶ 8216 │ PARAM_DEFINE_INT32(EKF2_EN, 1);
  8217 │ 
  8218 │ /**
  8219 │  * Verbose logging
```
> **说明**：拉起：rcS:446-449 if param compare -s EKF2_EN 1 → ekf2 start & ┃ （EKF2_EN 本板缺省 1，build/rm2027_fmu-h743_default/generated_params/module_params.c:8216）
> **说明**：EKF2_EN | 1 = rcS 拉起 ekf2 | 生成参数 module_params.c:8216 |
^src-build-rm2027-fmu-h743-default-generated-params-module-params-c-8216

### `src/modules/ekf2/EKF2.cpp`
<a id="src-src-modules-ekf2-EKF2-cpp-57"></a>
**↓ 文档在讲这里：**[`src/modules/ekf2/EKF2.cpp:57`](ekf2.md#^src-src-modules-ekf2-EKF2-cpp-57)

```c
    54 │ 	_replay_mode(replay_mode && !multi_mode),
    55 │ 	_multi_mode(multi_mode),
    56 │ 	_instance(multi_mode ? -1 : 0),
▶   57 │ 	_attitude_pub(multi_mode ? ORB_ID(estimator_attitude) : ORB_ID(vehicle_attitude)),
    58 │ 	_local_position_pub(multi_mode ? ORB_ID(estimator_local_position) : ORB_ID(vehicle_local_position)),
    59 │ 	_global_position_pub(multi_mode ? ORB_ID(estimator_global_position) : ORB_ID(vehicle_global_position)),
    60 │ 	_odometry_pub(multi_mode ? ORB_ID(estimator_odometry) : ORB_ID(vehicle_odometry)),
```
> **说明**：vehicle_attitude | EKF2.hpp:478（_attitude_pub）；构造 EKF2.cpp:57 决定名字；发布 EKF2.cpp:1187/1193 | 多实例时改叫 estimator_attitude | mc_att_control(mc_att_control.hpp:115)、mavlink(ATTITUDE.hpp:59)、logger(:141) |
^src-src-modules-ekf2-EKF2-cpp-57

<a id="src-src-modules-ekf2-EKF2-cpp-62"></a>
**↓ 文档在讲这里：**[`src/modules/ekf2/EKF2.cpp:62`](ekf2.md#^src-src-modules-ekf2-EKF2-cpp-62)

```c
    59 │ 	_global_position_pub(multi_mode ? ORB_ID(estimator_global_position) : ORB_ID(vehicle_global_position)),
    60 │ 	_odometry_pub(multi_mode ? ORB_ID(estimator_odometry) : ORB_ID(vehicle_odometry)),
    61 │ #if defined(CONFIG_EKF2_WIND)
▶   62 │ 	_wind_pub(multi_mode ? ORB_ID(estimator_wind) : ORB_ID(wind)),
    63 │ #endif // CONFIG_EKF2_WIND
    64 │ 	_params(_ekf.getParamHandle()),
    65 │ 	_fc(*_ekf.getFusionControlHandle()),
```
> **说明**：vehicle_odometry | EKF2.hpp:481 | → estimator_odometry | mavlink(ODOMETRY) | ┃ wind | EKF2.hpp:484；构造 EKF2.cpp:62 | → estimator_wind | logger |
^src-src-modules-ekf2-EKF2-cpp-62

<a id="src-src-modules-ekf2-EKF2-cpp-635"></a>
**↓ 文档在讲这里：**[`src/modules/ekf2/EKF2.cpp:635`](ekf2.md#^src-src-modules-ekf2-EKF2-cpp-635)

```c
   632 │ 	if (_multi_mode) {
   633 │ 		const unsigned last_generation = _vehicle_imu_sub.get_last_generation();
   634 │ 		vehicle_imu_s imu;
▶  635 │ 		imu_updated = _vehicle_imu_sub.update(&imu);
   636 │ 
   637 │ 		if (imu_updated && (_vehicle_imu_sub.get_last_generation() != last_generation + 1)) {
   638 │ 			perf_count(_msg_missed_imu_perf);
```
> **说明**：sensor_combined | EKF2.hpp:433（SubscriptionCallbackWorkItem） | Run() | 兜底源 | ┃ vehicle_imu | EKF2.hpp:434（同上） | EKF2.cpp:635 | 主源；:400 ChangeInstance(imu) 换实例 |
^src-src-modules-ekf2-EKF2-cpp-635

<a id="src-src-modules-ekf2-EKF2-cpp-740"></a>
**↓ 文档在讲这里：**[`src/modules/ekf2/EKF2.cpp:740`](ekf2.md#^src-src-modules-ekf2-EKF2-cpp-740)

```c
   737 │ 			}
   738 │ 		}
   739 │ 
▶  740 │ 		if (_sensor_selection_sub.updated() || (_device_id_accel == 0 || _device_id_gyro == 0)) {
   741 │ 			sensor_selection_s sensor_selection;
   742 │ 
   743 │ 			if (_sensor_selection_sub.copy(&sensor_selection)) {
```
> **说明**：vehicle_optical_flow | EKF2.hpp:358 | — | 本板无 | ┃ sensor_selection | EKF2.hpp:404 | EKF2.cpp:740 | ★ "跟着 sensors 的投票结果换 IMU" |
> **说明**：★ sensor_selection 这一跳是"双陀螺"的落点（EKF2.cpp:740）：
^src-src-modules-ekf2-EKF2-cpp-740

<a id="src-src-modules-ekf2-EKF2-cpp-1187"></a>
**↓ 文档在讲这里：**[`src/modules/ekf2/EKF2.cpp:1187`](ekf2.md#^src-src-modules-ekf2-EKF2-cpp-1187)

```c
  1184 │ 
  1185 │ 		_ekf.get_quat_reset(&att.delta_q_reset[0], &att.quat_reset_counter);
  1186 │ 		att.timestamp = _replay_mode ? timestamp : hrt_absolute_time();
▶ 1187 │ 		_attitude_pub.publish(att);
  1188 │ 
  1189 │ 	}  else if (_replay_mode) {
  1190 │ 		// in replay mode we have to tell the replay module not to wait for an update
```
> **说明**：estimator_status 有值但 vehicle_attitude 不动 ⇒ 卡在姿态发布条件（EKF2.cpp:1187 附近）。
^src-src-modules-ekf2-EKF2-cpp-1187

<a id="src-src-modules-ekf2-EKF2-cpp-1377"></a>
**↓ 文档在讲这里：**[`src/modules/ekf2/EKF2.cpp:1377`](ekf2.md#^src-src-modules-ekf2-EKF2-cpp-1377)

```c
  1374 │ 					    || _ekf.control_status_flags().wind_dead_reckoning;
  1375 │ 
  1376 │ 		global_pos.timestamp = _replay_mode ? timestamp : hrt_absolute_time();
▶ 1377 │ 		_global_position_pub.publish(global_pos);
  1378 │ 	}
  1379 │ }
  1380 │ 
```
> **说明**：vehicle_local_position | EKF2.hpp:479；发布 EKF2.cpp:1818 | 多实例 → estimator_local_position | mc_pos_control(MulticopterPositionControl.hpp:104)、FMM(:150)、logger(:150) | ┃ vehicle_global_position | EKF2.hpp:480；发布 EKF2.cpp:1377 | → estimator_global_position | commander(HomePosition)、navigator |
^src-src-modules-ekf2-EKF2-cpp-1377

<a id="src-src-modules-ekf2-EKF2-cpp-1818"></a>
**↓ 文档在讲这里：**[`src/modules/ekf2/EKF2.cpp:1818`](ekf2.md#^src-src-modules-ekf2-EKF2-cpp-1818)

```c
  1815 │ 
  1816 │ 	// publish vehicle local position data
  1817 │ 	lpos.timestamp = _replay_mode ? timestamp : hrt_absolute_time();
▶ 1818 │ 	_local_position_pub.publish(lpos);
  1819 │ }
  1820 │ 
  1821 │ void EKF2::PublishOdometry(const hrt_abstime &timestamp, const imuSample &imu_sample)
```
> **说明**：vehicle_attitude | EKF2.hpp:478（_attitude_pub）；构造 EKF2.cpp:57 决定名字；发布 EKF2.cpp:1187/1193 | 多实例时改叫 estimator_attitude | mc_att_control(mc_att_control.hpp:115)、mavlink(ATTITUDE.hpp:59)、logger(:141) | ┃ vehicle_local_position | EKF2.hpp:479；发布 EKF2.cpp:1818 | 多实例 → estimator_local_position | mc_pos_control(MulticopterPositionControl.hpp:104)、FMM(:150)、logger(:150) |
^src-src-modules-ekf2-EKF2-cpp-1818

<a id="src-src-modules-ekf2-EKF2-cpp-2246"></a>
**↓ 文档在讲这里：**[`src/modules/ekf2/EKF2.cpp:2246`](ekf2.md#^src-src-modules-ekf2-EKF2-cpp-2246)

```c
  2243 │ void EKF2::UpdateAirspeedSample(ekf2_timestamps_s &ekf2_timestamps)
  2244 │ {
  2245 │ 	// EKF airspeed sample
▶ 2246 │ 	// prefer ORB_ID(airspeed_validated) if available, otherwise fallback to raw airspeed ORB_ID(airspeed)
  2247 │ 	if (_airspeed_validated_sub.updated()) {
  2248 │ 		airspeed_validated_s airspeed_validated;
  2249 │ 
```
> **说明**：vehicle_gps_position | EKF2.hpp:501 | — | 本板永远没有发布者 ⇒ GPS 相关更新恒不触发 | ┃ airspeed / airspeed_validated | EKF2.hpp:385 | EKF2.cpp:2246 起 | 多旋翼不用 |
^src-src-modules-ekf2-EKF2-cpp-2246

<a id="src-src-modules-ekf2-EKF2-cpp-2363"></a>
**↓ 文档在讲这里：**[`src/modules/ekf2/EKF2.cpp:2363`](ekf2.md#^src-src-modules-ekf2-EKF2-cpp-2363)

```c
  2360 │ 	// EKF baro sample
  2361 │ 	vehicle_air_data_s airdata;
  2362 │ 
▶ 2363 │ 	if (_airdata_sub.update(&airdata)) {
  2364 │ 
  2365 │ 		bool reset = false;
  2366 │ 
```
> **说明**：vehicle_imu | EKF2.hpp:434（同上） | EKF2.cpp:635 | 主源；:400 ChangeInstance(imu) 换实例 | ┃ vehicle_air_data | EKF2.hpp:373 | EKF2.cpp:2363 | 气压高度 |
^src-src-modules-ekf2-EKF2-cpp-2363

<a id="src-src-modules-ekf2-EKF2-cpp-2708"></a>
**↓ 文档在讲这里：**[`src/modules/ekf2/EKF2.cpp:2708`](ekf2.md#^src-src-modules-ekf2-EKF2-cpp-2708)

```c
  2705 │ {
  2706 │ 	vehicle_magnetometer_s magnetometer;
  2707 │ 
▶ 2708 │ 	if (_magnetometer_sub.update(&magnetometer)) {
  2709 │ 
  2710 │ 		bool reset = false;
  2711 │ 
```
> **说明**：vehicle_air_data | EKF2.hpp:373 | EKF2.cpp:2363 | 气压高度 | ┃ vehicle_magnetometer | EKF2.hpp:324 | EKF2.cpp:2708 | 磁航向；:404 ChangeInstance(mag) |
^src-src-modules-ekf2-EKF2-cpp-2708

<a id="src-src-modules-ekf2-EKF2-cpp-3007"></a>
**↓ 文档在讲这里：**[`src/modules/ekf2/EKF2.cpp:3007`](ekf2.md#^src-src-modules-ekf2-EKF2-cpp-3007)

```c
  3004 │ 		multi_mode = true;
  3005 │ 
  3006 │ 		// IMUs (1 - MAX_NUM_IMUS supported)
▶ 3007 │ 		param_get(param_find("EKF2_MULTI_IMU"), &imu_instances);
  3008 │ 
  3009 │ 		if (imu_instances < 1 || imu_instances > MAX_NUM_IMUS) {
  3010 │ 			const int32_t imu_instances_limited = math::constrain(imu_instances, static_cast<int32_t>(1),
```
> **说明**：EKF2_EN | 1 = rcS 拉起 ekf2 | 生成参数 module_params.c:8216 | ┃ EKF2_MULTI_IMU | 0 = 单实例（缺省）；>0 = 多实例 + selector | src/modules/ekf2/params_multi.yaml:5；运行时读 EKF2.cpp:3007 |
^src-src-modules-ekf2-EKF2-cpp-3007

<a id="src-src-modules-ekf2-EKF2-cpp-3055"></a>
**↓ 文档在讲这里：**[`src/modules/ekf2/EKF2.cpp:3055`](ekf2.md#^src-src-modules-ekf2-EKF2-cpp-3055)

```c
  3052 │ 	if (multi_mode && !replay_mode) {
  3053 │ 		// Start EKF2Selector if it's not already running
  3054 │ 		if (_ekf2_selector.load() == nullptr) {
▶ 3055 │ 			EKF2Selector *inst = new EKF2Selector();
  3056 │ 
  3057 │ 			if (inst) {
  3058 │ 				_ekf2_selector.store(inst);
```
> **说明**：单实例（本板缺省） | 一个 EKF2 直接建在 wq:INS0 | wq:INS0（本板优先级 -14） | EKF2.cpp:3142 new EKF2(false, px4::wq_configurations::INS0, replay_mode) | ┃ 多实例（EKF2_MULTI_IMU > 0） | 一个 EKF2Selector + 每个 IMU 一个 EKF2 | selector 在 wq:nav_and_controllers；每个 EKF2 在 ins_instance_to_wq(imu) | EKF2.cpp:3055、:3094；selector 队列 EKF2Selector.cpp:44 |
^src-src-modules-ekf2-EKF2-cpp-3055

<a id="src-src-modules-ekf2-EKF2-cpp-3142"></a>
**↓ 文档在讲这里：**[`src/modules/ekf2/EKF2.cpp:3142`](ekf2.md#^src-src-modules-ekf2-EKF2-cpp-3142)

```c
  3139 │ 
  3140 │ 	{
  3141 │ 		// otherwise launch regular
▶ 3142 │ 		EKF2 *ekf2_inst = new EKF2(false, px4::wq_configurations::INS0, replay_mode);
  3143 │ 
  3144 │ 		if (ekf2_inst) {
  3145 │ 			_objects[0].store(ekf2_inst);
```
> **说明**：单实例（本板缺省） | 一个 EKF2 直接建在 wq:INS0 | wq:INS0（本板优先级 -14） | EKF2.cpp:3142 new EKF2(false, px4::wq_configurations::INS0, replay_mode) |
^src-src-modules-ekf2-EKF2-cpp-3142

### `src/modules/ekf2/EKF2.hpp`
<a id="src-src-modules-ekf2-EKF2-hpp-324"></a>
**↓ 文档在讲这里：**[`src/modules/ekf2/EKF2.hpp:324`](ekf2.md#^src-src-modules-ekf2-EKF2-hpp-324)

```c
   321 │ 
   322 │ 	hrt_abstime _status_mag_pub_last{0};
   323 │ 
▶  324 │ 	uORB::Subscription _magnetometer_sub{ORB_ID(vehicle_magnetometer)};
   325 │ 
   326 │ 	uORB::PublicationMulti<estimator_aid_source3d_s> _estimator_aid_src_mag_pub{ORB_ID(estimator_aid_src_mag)};
   327 │ #endif // CONFIG_EKF2_MAGNETOMETER
```
> **说明**：vehicle_air_data | EKF2.hpp:373 | EKF2.cpp:2363 | 气压高度 | ┃ vehicle_magnetometer | EKF2.hpp:324 | EKF2.cpp:2708 | 磁航向；:404 ChangeInstance(mag) |
^src-src-modules-ekf2-EKF2-hpp-324

<a id="src-src-modules-ekf2-EKF2-hpp-326"></a>
**↓ 文档在讲这里：**[`src/modules/ekf2/EKF2.hpp:326`](ekf2.md#^src-src-modules-ekf2-EKF2-hpp-326)

```c
   323 │ 
   324 │ 	uORB::Subscription _magnetometer_sub{ORB_ID(vehicle_magnetometer)};
   325 │ 
▶  326 │ 	uORB::PublicationMulti<estimator_aid_source3d_s> _estimator_aid_src_mag_pub{ORB_ID(estimator_aid_src_mag)};
   327 │ #endif // CONFIG_EKF2_MAGNETOMETER
   328 │ 
   329 │ #if defined(CONFIG_EKF2_EXTERNAL_VISION)
```
> **说明**：EKF2_MULTI_IMU 在本板的实际取值 | 只核到缺省与 clamp 逻辑（:3007-3013），未从生成参数表回读 | ┃ estimator_aid_src_* 的完整清单 | 只列了与六条流相关的一部分（EKF2.hpp:326 内还有 GNSS/EV/测距等） |
^src-src-modules-ekf2-EKF2-hpp-326

<a id="src-src-modules-ekf2-EKF2-hpp-358"></a>
**↓ 文档在讲这里：**[`src/modules/ekf2/EKF2.hpp:358`](ekf2.md#^src-src-modules-ekf2-EKF2-hpp-358)

```c
   355 │ #endif // CONFIG_EKF2_RANGING_BEACON
   356 │ 
   357 │ #if defined(CONFIG_EKF2_OPTICAL_FLOW)
▶  358 │ 	uORB::Subscription _vehicle_optical_flow_sub {ORB_ID(vehicle_optical_flow)};
   359 │ 	uORB::PublicationMulti<vehicle_optical_flow_vel_s> _estimator_optical_flow_vel_pub{ORB_ID(estimator_optical_flow_vel)};
   360 │ 
   361 │ 	uORB::PublicationMulti<estimator_aid_source2d_s> _estimator_aid_src_optical_flow_pub{ORB_ID(estimator_aid_src_optical_flow)};
```
> **说明**：airspeed / airspeed_validated | EKF2.hpp:385 | EKF2.cpp:2246 起 | 多旋翼不用 | ┃ vehicle_optical_flow | EKF2.hpp:358 | — | 本板无 |
^src-src-modules-ekf2-EKF2-hpp-358

<a id="src-src-modules-ekf2-EKF2-hpp-373"></a>
**↓ 文档在讲这里：**[`src/modules/ekf2/EKF2.hpp:373`](ekf2.md#^src-src-modules-ekf2-EKF2-hpp-373)

```c
   370 │ 
   371 │ 	float _last_baro_bias_published{};
   372 │ 
▶  373 │ 	uORB::Subscription _airdata_sub{ORB_ID(vehicle_air_data)};
   374 │ 
   375 │ 	uORB::PublicationMulti<estimator_bias_s> _estimator_baro_bias_pub{ORB_ID(estimator_baro_bias)};
   376 │ 	uORB::PublicationMulti<estimator_aid_source1d_s> _estimator_aid_src_baro_hgt_pub {ORB_ID(estimator_aid_src_baro_hgt)};
```
> **说明**：vehicle_imu | EKF2.hpp:434（同上） | EKF2.cpp:635 | 主源；:400 ChangeInstance(imu) 换实例 | ┃ vehicle_air_data | EKF2.hpp:373 | EKF2.cpp:2363 | 气压高度 |
^src-src-modules-ekf2-EKF2-hpp-373

<a id="src-src-modules-ekf2-EKF2-hpp-385"></a>
**↓ 文档在讲这里：**[`src/modules/ekf2/EKF2.hpp:385`](ekf2.md#^src-src-modules-ekf2-EKF2-hpp-385)

```c
   382 │ #endif // CONFIG_EKF2_DRAG_FUSION
   383 │ 
   384 │ #if defined(CONFIG_EKF2_AIRSPEED)
▶  385 │ 	uORB::Subscription _airspeed_sub {ORB_ID(airspeed)};
   386 │ 	uORB::Subscription _airspeed_validated_sub{ORB_ID(airspeed_validated)};
   387 │ 
   388 │ 	float _airspeed_scale_factor{1.0f}; ///< scale factor correction applied to airspeed measurements
```
> **说明**：vehicle_gps_position | EKF2.hpp:501 | — | 本板永远没有发布者 ⇒ GPS 相关更新恒不触发 | ┃ airspeed / airspeed_validated | EKF2.hpp:385 | EKF2.cpp:2246 起 | 多旋翼不用 |
^src-src-modules-ekf2-EKF2-hpp-385

<a id="src-src-modules-ekf2-EKF2-hpp-404"></a>
**↓ 文档在讲这里：**[`src/modules/ekf2/EKF2.hpp:404`](ekf2.md#^src-src-modules-ekf2-EKF2-hpp-404)

```c
   401 │ 
   402 │ 	uORB::SubscriptionInterval _parameter_update_sub{ORB_ID(parameter_update), 1_s};
   403 │ 
▶  404 │ 	uORB::Subscription _sensor_selection_sub{ORB_ID(sensor_selection)};
   405 │ 	uORB::Subscription _status_sub{ORB_ID(vehicle_status)};
   406 │ 	uORB::Subscription _vehicle_land_detected_sub{ORB_ID(vehicle_land_detected)};
   407 │ 	uORB::Subscription _launch_detection_status_sub{ORB_ID(launch_detection_status)};
```
> **说明**：vehicle_optical_flow | EKF2.hpp:358 | — | 本板无 | ┃ sensor_selection | EKF2.hpp:404 | EKF2.cpp:740 | ★ "跟着 sensors 的投票结果换 IMU" |
^src-src-modules-ekf2-EKF2-hpp-404

<a id="src-src-modules-ekf2-EKF2-hpp-405"></a>
**↓ 文档在讲这里：**[`src/modules/ekf2/EKF2.hpp:405`](ekf2.md#^src-src-modules-ekf2-EKF2-hpp-405)

```c
   402 │ 	uORB::SubscriptionInterval _parameter_update_sub{ORB_ID(parameter_update), 1_s};
   403 │ 
   404 │ 	uORB::Subscription _sensor_selection_sub{ORB_ID(sensor_selection)};
▶  405 │ 	uORB::Subscription _status_sub{ORB_ID(vehicle_status)};
   406 │ 	uORB::Subscription _vehicle_land_detected_sub{ORB_ID(vehicle_land_detected)};
   407 │ 	uORB::Subscription _launch_detection_status_sub{ORB_ID(launch_detection_status)};
   408 │ 
```
> **说明**：sensor_selection | EKF2.hpp:404 | EKF2.cpp:740 | ★ "跟着 sensors 的投票结果换 IMU" | ┃ vehicle_status | EKF2.hpp:405 | — | 上锁/解锁 |
^src-src-modules-ekf2-EKF2-hpp-405

<a id="src-src-modules-ekf2-EKF2-hpp-409"></a>
**↓ 文档在讲这里：**[`src/modules/ekf2/EKF2.hpp:409`](ekf2.md#^src-src-modules-ekf2-EKF2-hpp-409)

```c
   406 │ 	uORB::Subscription _vehicle_land_detected_sub{ORB_ID(vehicle_land_detected)};
   407 │ 	uORB::Subscription _launch_detection_status_sub{ORB_ID(launch_detection_status)};
   408 │ 
▶  409 │ 	uORB::Subscription _vehicle_command_sub{ORB_ID(vehicle_command)};
   410 │ 	uORB::Publication<vehicle_command_ack_s> _vehicle_command_ack_pub{ORB_ID(vehicle_command_ack)};
   411 │ 
   412 │ 	enum SensEn : uint16_t {
```
> **说明**：vehicle_status | EKF2.hpp:405 | — | 上锁/解锁 | ┃ vehicle_command | EKF2.hpp:409 | — | 起飞/降落命令 |
^src-src-modules-ekf2-EKF2-hpp-409

<a id="src-src-modules-ekf2-EKF2-hpp-433"></a>
**↓ 文档在讲这里：**[`src/modules/ekf2/EKF2.hpp:433`](ekf2.md#^src-src-modules-ekf2-EKF2-hpp-433)

```c
   430 │ 	void handleSensorFusionCommand(const vehicle_command_s &cmd, vehicle_command_ack_s &ack);
   431 │ 	void syncSensEnParam();
   432 │ 
▶  433 │ 	uORB::SubscriptionCallbackWorkItem _sensor_combined_sub{this, ORB_ID(sensor_combined)};
   434 │ 	uORB::SubscriptionCallbackWorkItem _vehicle_imu_sub{this, ORB_ID(vehicle_imu)};
   435 │ 
   436 │ #if defined(CONFIG_EKF2_RANGE_FINDER)
```
> **说明**：sensor_combined | EKF2.hpp:433（SubscriptionCallbackWorkItem） | Run() | 兜底源 |
^src-src-modules-ekf2-EKF2-hpp-433

<a id="src-src-modules-ekf2-EKF2-hpp-434"></a>
**↓ 文档在讲这里：**[`src/modules/ekf2/EKF2.hpp:434`](ekf2.md#^src-src-modules-ekf2-EKF2-hpp-434)

```c
   431 │ 	void syncSensEnParam();
   432 │ 
   433 │ 	uORB::SubscriptionCallbackWorkItem _sensor_combined_sub{this, ORB_ID(sensor_combined)};
▶  434 │ 	uORB::SubscriptionCallbackWorkItem _vehicle_imu_sub{this, ORB_ID(vehicle_imu)};
   435 │ 
   436 │ #if defined(CONFIG_EKF2_RANGE_FINDER)
   437 │ 	hrt_abstime _status_rng_hgt_pub_last {0};
```
> **说明**：sensor_combined | EKF2.hpp:433（SubscriptionCallbackWorkItem） | Run() | 兜底源 | ┃ vehicle_imu | EKF2.hpp:434（同上） | EKF2.cpp:635 | 主源；:400 ChangeInstance(imu) 换实例 |
^src-src-modules-ekf2-EKF2-hpp-434

<a id="src-src-modules-ekf2-EKF2-hpp-465"></a>
**↓ 文档在讲这里：**[`src/modules/ekf2/EKF2.hpp:465`](ekf2.md#^src-src-modules-ekf2-EKF2-hpp-465)

```c
   462 │ 
   463 │ 	uORB::PublicationMulti<ekf2_timestamps_s>            _ekf2_timestamps_pub{ORB_ID(ekf2_timestamps)};
   464 │ 	uORB::PublicationMultiData<estimator_event_flags_s>  _estimator_event_flags_pub{ORB_ID(estimator_event_flags)};
▶  465 │ 	uORB::PublicationMulti<estimator_innovations_s>      _estimator_innovation_test_ratios_pub{ORB_ID(estimator_innovation_test_ratios)};
   466 │ 	uORB::PublicationMulti<estimator_innovations_s>      _estimator_innovation_variances_pub{ORB_ID(estimator_innovation_variances)};
   467 │ 	uORB::PublicationMulti<estimator_innovations_s>      _estimator_innovations_pub{ORB_ID(estimator_innovations)};
   468 │ 	uORB::PublicationMulti<estimator_sensor_bias_s>      _estimator_sensor_bias_pub{ORB_ID(estimator_sensor_bias)};
```
> **说明**：estimator_status / estimator_status_flags | EKF2.hpp:472 / :470 | — | commander 的 estimatorCheck、logger | ┃ estimator_innovations 三兄弟 | EKF2.hpp:465 | — | 排障用 |
^src-src-modules-ekf2-EKF2-hpp-465

<a id="src-src-modules-ekf2-EKF2-hpp-468"></a>
**↓ 文档在讲这里：**[`src/modules/ekf2/EKF2.hpp:468`](ekf2.md#^src-src-modules-ekf2-EKF2-hpp-468)

```c
   465 │ 	uORB::PublicationMulti<estimator_innovations_s>      _estimator_innovation_test_ratios_pub{ORB_ID(estimator_innovation_test_ratios)};
   466 │ 	uORB::PublicationMulti<estimator_innovations_s>      _estimator_innovation_variances_pub{ORB_ID(estimator_innovation_variances)};
   467 │ 	uORB::PublicationMulti<estimator_innovations_s>      _estimator_innovations_pub{ORB_ID(estimator_innovations)};
▶  468 │ 	uORB::PublicationMulti<estimator_sensor_bias_s>      _estimator_sensor_bias_pub{ORB_ID(estimator_sensor_bias)};
   469 │ 	uORB::PublicationMulti<estimator_states_s>           _estimator_states_pub{ORB_ID(estimator_states)};
   470 │ 	uORB::PublicationMulti<estimator_status_flags_s>     _estimator_status_flags_pub{ORB_ID(estimator_status_flags)};
   471 │ 	uORB::PublicationMulti<estimator_fusion_control_s>   _estimator_fc_pub{ORB_ID(estimator_fusion_control)};
```
> **说明**：estimator_aid_src_*（baro_hgt / mag / gnss…） | EKF2.hpp:330-376,505-519 | — | 看"哪一路观测被接受了"的唯一入口 | ┃ estimator_sensor_bias | EKF2.hpp:468 | — | VehicleAcceleration/AngularVelocity 用它做偏置补偿（VehicleAcceleration.hpp:83） |
^src-src-modules-ekf2-EKF2-hpp-468

<a id="src-src-modules-ekf2-EKF2-hpp-472"></a>
**↓ 文档在讲这里：**[`src/modules/ekf2/EKF2.hpp:472`](ekf2.md#^src-src-modules-ekf2-EKF2-hpp-472)

```c
   469 │ 	uORB::PublicationMulti<estimator_states_s>           _estimator_states_pub{ORB_ID(estimator_states)};
   470 │ 	uORB::PublicationMulti<estimator_status_flags_s>     _estimator_status_flags_pub{ORB_ID(estimator_status_flags)};
   471 │ 	uORB::PublicationMulti<estimator_fusion_control_s>   _estimator_fc_pub{ORB_ID(estimator_fusion_control)};
▶  472 │ 	uORB::PublicationMulti<estimator_status_s>           _estimator_status_pub{ORB_ID(estimator_status)};
   473 │ 
   474 │ 	uORB::PublicationMulti<estimator_aid_source1d_s> _estimator_aid_src_fake_hgt_pub{ORB_ID(estimator_aid_src_fake_hgt)};
   475 │ 	uORB::PublicationMulti<estimator_aid_source2d_s> _estimator_aid_src_fake_pos_pub{ORB_ID(estimator_aid_src_fake_pos)};
```
> **说明**：wind | EKF2.hpp:484；构造 EKF2.cpp:62 | → estimator_wind | logger | ┃ estimator_status / estimator_status_flags | EKF2.hpp:472 / :470 | — | commander 的 estimatorCheck、logger |
^src-src-modules-ekf2-EKF2-hpp-472

<a id="src-src-modules-ekf2-EKF2-hpp-478"></a>
**↓ 文档在讲这里：**[`src/modules/ekf2/EKF2.hpp:478`](ekf2.md#^src-src-modules-ekf2-EKF2-hpp-478)

```c
   475 │ 	uORB::PublicationMulti<estimator_aid_source2d_s> _estimator_aid_src_fake_pos_pub{ORB_ID(estimator_aid_src_fake_pos)};
   476 │ 
   477 │ 	// publications with topic dependent on multi-mode
▶  478 │ 	uORB::PublicationMulti<vehicle_attitude_s>           _attitude_pub;
   479 │ 	uORB::PublicationMulti<vehicle_local_position_s>     _local_position_pub;
   480 │ 	uORB::PublicationMulti<vehicle_global_position_s>    _global_position_pub;
   481 │ 	uORB::PublicationMulti<vehicle_odometry_s>           _odometry_pub;
```
> **说明**：vehicle_attitude | EKF2.hpp:478（_attitude_pub）；构造 EKF2.cpp:57 决定名字；发布 EKF2.cpp:1187/1193 | 多实例时改叫 estimator_attitude | mc_att_control(mc_att_control.hpp:115)、mavlink(ATTITUDE.hpp:59)、logger(:141) |
^src-src-modules-ekf2-EKF2-hpp-478

<a id="src-src-modules-ekf2-EKF2-hpp-479"></a>
**↓ 文档在讲这里：**[`src/modules/ekf2/EKF2.hpp:479`](ekf2.md#^src-src-modules-ekf2-EKF2-hpp-479)

```c
   476 │ 
   477 │ 	// publications with topic dependent on multi-mode
   478 │ 	uORB::PublicationMulti<vehicle_attitude_s>           _attitude_pub;
▶  479 │ 	uORB::PublicationMulti<vehicle_local_position_s>     _local_position_pub;
   480 │ 	uORB::PublicationMulti<vehicle_global_position_s>    _global_position_pub;
   481 │ 	uORB::PublicationMulti<vehicle_odometry_s>           _odometry_pub;
   482 │ 
```
> **说明**：vehicle_attitude | EKF2.hpp:478（_attitude_pub）；构造 EKF2.cpp:57 决定名字；发布 EKF2.cpp:1187/1193 | 多实例时改叫 estimator_attitude | mc_att_control(mc_att_control.hpp:115)、mavlink(ATTITUDE.hpp:59)、logger(:141) | ┃ vehicle_local_position | EKF2.hpp:479；发布 EKF2.cpp:1818 | 多实例 → estimator_local_position | mc_pos_control(MulticopterPositionControl.hpp:104)、FMM(:150)、logger(:150) |
^src-src-modules-ekf2-EKF2-hpp-479

<a id="src-src-modules-ekf2-EKF2-hpp-480"></a>
**↓ 文档在讲这里：**[`src/modules/ekf2/EKF2.hpp:480`](ekf2.md#^src-src-modules-ekf2-EKF2-hpp-480)

```c
   477 │ 	// publications with topic dependent on multi-mode
   478 │ 	uORB::PublicationMulti<vehicle_attitude_s>           _attitude_pub;
   479 │ 	uORB::PublicationMulti<vehicle_local_position_s>     _local_position_pub;
▶  480 │ 	uORB::PublicationMulti<vehicle_global_position_s>    _global_position_pub;
   481 │ 	uORB::PublicationMulti<vehicle_odometry_s>           _odometry_pub;
   482 │ 
   483 │ #if defined(CONFIG_EKF2_WIND)
```
> **说明**：vehicle_local_position | EKF2.hpp:479；发布 EKF2.cpp:1818 | 多实例 → estimator_local_position | mc_pos_control(MulticopterPositionControl.hpp:104)、FMM(:150)、logger(:150) | ┃ vehicle_global_position | EKF2.hpp:480；发布 EKF2.cpp:1377 | → estimator_global_position | commander(HomePosition)、navigator |
^src-src-modules-ekf2-EKF2-hpp-480

<a id="src-src-modules-ekf2-EKF2-hpp-481"></a>
**↓ 文档在讲这里：**[`src/modules/ekf2/EKF2.hpp:481`](ekf2.md#^src-src-modules-ekf2-EKF2-hpp-481)

```c
   478 │ 	uORB::PublicationMulti<vehicle_attitude_s>           _attitude_pub;
   479 │ 	uORB::PublicationMulti<vehicle_local_position_s>     _local_position_pub;
   480 │ 	uORB::PublicationMulti<vehicle_global_position_s>    _global_position_pub;
▶  481 │ 	uORB::PublicationMulti<vehicle_odometry_s>           _odometry_pub;
   482 │ 
   483 │ #if defined(CONFIG_EKF2_WIND)
   484 │ 	uORB::PublicationMulti<wind_s>              _wind_pub;
```
> **说明**：vehicle_global_position | EKF2.hpp:480；发布 EKF2.cpp:1377 | → estimator_global_position | commander(HomePosition)、navigator | ┃ vehicle_odometry | EKF2.hpp:481 | → estimator_odometry | mavlink(ODOMETRY) |
^src-src-modules-ekf2-EKF2-hpp-481

<a id="src-src-modules-ekf2-EKF2-hpp-484"></a>
**↓ 文档在讲这里：**[`src/modules/ekf2/EKF2.hpp:484`](ekf2.md#^src-src-modules-ekf2-EKF2-hpp-484)

```c
   481 │ 	uORB::PublicationMulti<vehicle_odometry_s>           _odometry_pub;
   482 │ 
   483 │ #if defined(CONFIG_EKF2_WIND)
▶  484 │ 	uORB::PublicationMulti<wind_s>              _wind_pub;
   485 │ #endif // CONFIG_EKF2_WIND
   486 │ 
   487 │ #if defined(CONFIG_EKF2_GNSS)
```
> **说明**：vehicle_odometry | EKF2.hpp:481 | → estimator_odometry | mavlink(ODOMETRY) | ┃ wind | EKF2.hpp:484；构造 EKF2.cpp:62 | → estimator_wind | logger |
^src-src-modules-ekf2-EKF2-hpp-484

<a id="src-src-modules-ekf2-EKF2-hpp-501"></a>
**↓ 文档在讲这里：**[`src/modules/ekf2/EKF2.hpp:501`](ekf2.md#^src-src-modules-ekf2-EKF2-hpp-501)

```c
   498 │ 
   499 │ 	float _last_gnss_hgt_bias_published{};
   500 │ 
▶  501 │ 	uORB::Subscription _vehicle_gps_position_sub{ORB_ID(vehicle_gps_position)};
   502 │ 
   503 │ 	uORB::PublicationMulti<estimator_bias_s> _estimator_gnss_hgt_bias_pub{ORB_ID(estimator_gnss_hgt_bias)};
   504 │ 	uORB::PublicationMulti<estimator_gps_status_s> _estimator_gps_status_pub{ORB_ID(estimator_gps_status)};
```
> **说明**：vehicle_magnetometer | EKF2.hpp:324 | EKF2.cpp:2708 | 磁航向；:404 ChangeInstance(mag) | ┃ vehicle_gps_position | EKF2.hpp:501 | — | 本板永远没有发布者 ⇒ GPS 相关更新恒不触发 |
^src-src-modules-ekf2-EKF2-hpp-501

### `src/modules/ekf2/EKF2Selector.cpp`
<a id="src-src-modules-ekf2-EKF2Selector-cpp-44"></a>
**↓ 文档在讲这里：**[`src/modules/ekf2/EKF2Selector.cpp:44`](ekf2.md#^src-src-modules-ekf2-EKF2Selector-cpp-44)

```c
    41 │ 
    42 │ EKF2Selector::EKF2Selector() :
    43 │ 	ModuleParams(nullptr),
▶   44 │ 	ScheduledWorkItem("ekf2_selector", px4::wq_configurations::nav_and_controllers)
    45 │ {
    46 │ 	_estimator_selector_status_pub.advertise();
    47 │ 	_sensor_selection_pub.advertise();
```
> **说明**：单实例（本板缺省） | 一个 EKF2 直接建在 wq:INS0 | wq:INS0（本板优先级 -14） | EKF2.cpp:3142 new EKF2(false, px4::wq_configurations::INS0, replay_mode) | ┃ 多实例（EKF2_MULTI_IMU > 0） | 一个 EKF2Selector + 每个 IMU 一个 EKF2 | selector 在 wq:nav_and_controllers；每个 EKF2 在 ins_instance_to_wq(imu) | EKF2.cpp:3055、:3094；selector 队列 EKF2Selector.cpp:44 |
^src-src-modules-ekf2-EKF2Selector-cpp-44

### `src/modules/ekf2/params_multi.yaml`
<a id="src-src-modules-ekf2-params-multi-yaml-5"></a>
**↓ 文档在讲这里：**[`src/modules/ekf2/params_multi.yaml:5`](ekf2.md#^src-src-modules-ekf2-params-multi-yaml-5)

```c
     2 │ parameters:
     3 │ - group: EKF2
     4 │   definitions:
▶    5 │     EKF2_MULTI_IMU:
     6 │       description:
     7 │         short: Multi-EKF IMUs
     8 │         long: Maximum number of IMUs to use for Multi-EKF. Set 0 to disable. Requires
```
> **说明**：EKF2_EN | 1 = rcS 拉起 ekf2 | 生成参数 module_params.c:8216 | ┃ EKF2_MULTI_IMU | 0 = 单实例（缺省）；>0 = 多实例 + selector | src/modules/ekf2/params_multi.yaml:5；运行时读 EKF2.cpp:3007 |
^src-src-modules-ekf2-params-multi-yaml-5

### `src/modules/mavlink/streams/ATTITUDE.hpp`
<a id="src-src-modules-mavlink-streams-ATTITUDE-hpp-59"></a>
**↓ 文档在讲这里：**[`src/modules/mavlink/streams/ATTITUDE.hpp:59`](ekf2.md#^src-src-modules-mavlink-streams-ATTITUDE-hpp-59)

```c
    56 │ private:
    57 │ 	explicit MavlinkStreamAttitude(Mavlink *mavlink) : MavlinkStream(mavlink) {}
    58 │ 
▶   59 │ 	uORB::Subscription _att_sub{ORB_ID(vehicle_attitude)};
    60 │ 	uORB::Subscription _angular_velocity_sub{ORB_ID(vehicle_angular_velocity)};
    61 │ 
    62 │ 	bool send() override
```
> **说明**：vehicle_attitude | EKF2.hpp:478（_attitude_pub）；构造 EKF2.cpp:57 决定名字；发布 EKF2.cpp:1187/1193 | 多实例时改叫 estimator_attitude | mc_att_control(mc_att_control.hpp:115)、mavlink(ATTITUDE.hpp:59)、logger(:141) |
^src-src-modules-mavlink-streams-ATTITUDE-hpp-59

### `src/modules/mc_att_control/mc_att_control.hpp`
<a id="src-src-modules-mc-att-control-mc-att-control-hpp-115"></a>
**↓ 文档在讲这里：**[`src/modules/mc_att_control/mc_att_control.hpp:115`](ekf2.md#^src-src-modules-mc-att-control-mc-att-control-hpp-115)

```c
   112 │ 	uORB::Subscription _vehicle_local_position_sub{ORB_ID(vehicle_local_position)};
   113 │ 	uORB::Subscription _vehicle_status_sub{ORB_ID(vehicle_status)};
   114 │ 
▶  115 │ 	uORB::SubscriptionCallbackWorkItem _vehicle_attitude_sub{this, ORB_ID(vehicle_attitude)};
   116 │ 
   117 │ 	uORB::Publication<vehicle_rates_setpoint_s>     _vehicle_rates_setpoint_pub{ORB_ID(vehicle_rates_setpoint)};    /**< rate setpoint publication */
   118 │ 	uORB::Publication<vehicle_attitude_setpoint_s>  _vehicle_attitude_setpoint_pub;
```
> **说明**：vehicle_attitude | EKF2.hpp:478（_attitude_pub）；构造 EKF2.cpp:57 决定名字；发布 EKF2.cpp:1187/1193 | 多实例时改叫 estimator_attitude | mc_att_control(mc_att_control.hpp:115)、mavlink(ATTITUDE.hpp:59)、logger(:141) |
^src-src-modules-mc-att-control-mc-att-control-hpp-115

### `src/modules/mc_pos_control/MulticopterPositionControl.hpp`
<a id="src-src-modules-mc-pos-control-MulticopterPositionControl-hpp-104"></a>
**↓ 文档在讲这里：**[`src/modules/mc_pos_control/MulticopterPositionControl.hpp:104`](ekf2.md#^src-src-modules-mc-pos-control-MulticopterPositionControl-hpp-104)

```c
   101 │ 	uORB::Publication<vehicle_attitude_setpoint_s>	     _vehicle_attitude_setpoint_pub{ORB_ID(vehicle_attitude_setpoint)};
   102 │ 	uORB::Publication<vehicle_local_position_setpoint_s> _local_pos_sp_pub{ORB_ID(vehicle_local_position_setpoint)};	/**< vehicle local position setpoint publication */
   103 │ 
▶  104 │ 	uORB::SubscriptionCallbackWorkItem _local_pos_sub{this, ORB_ID(vehicle_local_position)};	/**< vehicle local position */
   105 │ 
   106 │ 	uORB::SubscriptionInterval _parameter_update_sub{ORB_ID(parameter_update), 1_s};
   107 │ 
```
> **说明**：vehicle_attitude | EKF2.hpp:478（_attitude_pub）；构造 EKF2.cpp:57 决定名字；发布 EKF2.cpp:1187/1193 | 多实例时改叫 estimator_attitude | mc_att_control(mc_att_control.hpp:115)、mavlink(ATTITUDE.hpp:59)、logger(:141) | ┃ vehicle_local_position | EKF2.hpp:479；发布 EKF2.cpp:1818 | 多实例 → estimator_local_position | mc_pos_control(MulticopterPositionControl.hpp:104)、FMM(:150)、logger(:150) |
^src-src-modules-mc-pos-control-MulticopterPositionControl-hpp-104

### `src/modules/sensors/vehicle_acceleration/VehicleAcceleration.hpp`
<a id="src-src-modules-sensors-vehicle-acceleration-VehicleAcceleration-hpp-83"></a>
**↓ 文档在讲这里：**[`src/modules/sensors/vehicle_acceleration/VehicleAcceleration.hpp:83`](ekf2.md#^src-src-modules-sensors-vehicle-acceleration-VehicleAcceleration-hpp-83)

```c
    80 │ 	uORB::Publication<vehicle_acceleration_s> _vehicle_acceleration_pub{ORB_ID(vehicle_acceleration)};
    81 │ 
    82 │ 	uORB::Subscription _estimator_selector_status_sub{ORB_ID(estimator_selector_status)};
▶   83 │ 	uORB::Subscription _estimator_sensor_bias_sub{ORB_ID(estimator_sensor_bias)};
    84 │ 
    85 │ 	uORB::SubscriptionInterval _parameter_update_sub{ORB_ID(parameter_update), 1_s};
    86 │ 
```
> **说明**：estimator_aid_src_*（baro_hgt / mag / gnss…） | EKF2.hpp:330-376,505-519 | — | 看"哪一路观测被接受了"的唯一入口 | ┃ estimator_sensor_bias | EKF2.hpp:468 | — | VehicleAcceleration/AngularVelocity 用它做偏置补偿（VehicleAcceleration.hpp:83） |
^src-src-modules-sensors-vehicle-acceleration-VehicleAcceleration-hpp-83

### `src/modules/sensors/vehicle_imu/imu_parameters.yaml`
<a id="src-src-modules-sensors-vehicle-imu-imu-parameters-yaml-5"></a>
**↓ 文档在讲这里：**[`src/modules/sensors/vehicle_imu/imu_parameters.yaml:5`](ekf2.md#^src-src-modules-sensors-vehicle-imu-imu-parameters-yaml-5)

```c
     2 │ parameters:
     3 │ - group: Sensors
     4 │   definitions:
▶    5 │     IMU_INTEG_RATE:
     6 │       description:
     7 │         short: IMU integration rate
     8 │         long: |-
```
> **说明**：⚠️ 这解释了本项目欠账中的一句：「不提 IMU_INTEG_RATE 则提频白提」。 ┃ vehicle_imu 的发布率还受 IMU_INTEG_RATE 约束（src/modules/sensors/vehicle_imu/imu_parameters.yaml:5），
^src-src-modules-sensors-vehicle-imu-imu-parameters-yaml-5

### `src/modules/sensors/voted_sensors_update.h`
<a id="src-src-modules-sensors-voted-sensors-update-h-155"></a>
**↓ 文档在讲这里：**[`src/modules/sensors/voted_sensors_update.h:155`](ekf2.md#^src-src-modules-sensors-voted-sensors-update-h-155)

```c
   152 │ 	hrt_abstime _last_error_message{0};
   153 │ 	orb_advert_t _mavlink_log_pub{nullptr};
   154 │ 
▶  155 │ 	uORB::Publication<sensor_selection_s> _sensor_selection_pub{ORB_ID(sensor_selection)};	/**< handle to the sensor selection uORB topic */
   156 │ 	uORB::Publication<sensors_status_imu_s> _sensors_status_imu_pub{ORB_ID(sensors_status_imu)};
   157 │ 
   158 │ 	uORB::SubscriptionCallbackWorkItem(&_vehicle_imu_sub)[MAX_SENSOR_COUNT];
```
> **说明**：⇒ EKF2 自己不选源，它照抄 sensors 的投票结论（voted_sensors_update.h:155 发布）。
^src-src-modules-sensors-voted-sensors-update-h-155
