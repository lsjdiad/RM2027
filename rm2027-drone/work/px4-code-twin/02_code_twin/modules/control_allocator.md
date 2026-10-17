# `src/modules/control_allocator/ControlAllocator.cpp` —— 力矩/推力 → 4 个电机

> **运行时一句话**：它把"飞行器想要的三个力矩 + 一个推力"（`vehicle_torque_setpoint` / `vehicle_thrust_setpoint`）
> 按**机型几何**（`CA_ROTOR_*` 参数）解算成"每个电机出多少"（`actuator_motors`）。
> **⇒ 它是软件侧的最后一步；出了它，数据就变成"电机指令"。**
> 行号基准 `源码根（见 `tools/source-root.conf`）` HEAD `3b5de24`。

---

## 1. 它活在哪

| 项 | 值 | 出处 |
|---|---|---|
| 队列 | **`wq:rate_ctrl`**（本板优先级 **0**，最高） | [`ControlAllocator.cpp:57`](control_allocator.md#^src-src-modules-control-allocator-ControlAllocator-cpp-57) |
| 拉起 | `rc.mc_apps:11` `control_allocator start`（`VEHICLE_TYPE=mc`） | `ROMFS/px4fmu_common/init.d/rc.mc_apps:11`；经 `rcS:580 → rc.vehicle_setup` |
| 调度 | 由 `vehicle_torque_setpoint` 的 **`SubscriptionCallbackWorkItem`** 驱动（不是定时器） | [`ControlAllocator.hpp:201`](control_allocator.md#^src-src-modules-control-allocator-ControlAllocator-hpp-201) |
| 家族 | `ActuatorEffectiveness` 一族（`VehicleActuatorEffectiveness/`），按机型选一个 | `ControlAllocator.cpp:208-287 update_effectiveness_source()` |

> ★ **它在优先级 0 的队列上，和 `VehicleAngularVelocity`（[`VehicleAngularVelocity.cpp:47`](sensors.md#^src-src-modules-sensors-vehicle-angular-velocity-VehicleAngularVelocity-cpp-47)）、`mc_rate_control`（[`MulticopterRateControl.cpp:50`](control_allocator.md#^src-src-modules-mc-rate-control-MulticopterRateControl-cpp-50)）同队列。**
> 三者在**同一个线程里串行**跑完 —— 这是"角速率环 → 分配 → 输出"能保持低延迟的原因，
> 也是"任何一跳阻塞都会拖垮整条控制链"的原因（见 [03_moc/03-module-map](../../03_moc/03-module-map.md) §4.3）。

---

## 2. 订阅 / 发布

| 方向 | 话题 | 声明处 | 备注 |
|---|---|---|---|
| 订 | `vehicle_torque_setpoint` | [`ControlAllocator.hpp:201`](control_allocator.md#^src-src-modules-control-allocator-ControlAllocator-hpp-201) | ★ **触发源**（callback） |
| 订 | `vehicle_thrust_setpoint` | `:202` | 被动轮询（注释就写着 "polled when torque is triggered"） |
| 订 | `vehicle_torque_setpoint` **实例 1** | `:204` | 双实例机型（VTOL）用 |
| 订 | `vehicle_thrust_setpoint` **实例 1** | `:205` | 同上 |
| 订 | `vehicle_status` | `:216` | 机型/上锁状态 |
| 订 | `vehicle_control_mode` | `:217` | 手动/自动 |
| 订 | `failure_detector_status` | `:218` | 故障时降级 |
| 订 | `parameter_update` | `:214` | 1 s 周期 |
| **发** | `actuator_motors` | `:210`；发布 [`ControlAllocator.cpp:757`](control_allocator.md#^src-src-modules-control-allocator-ControlAllocator-cpp-757) | 4 个电机（`control[0..3]`） |
| **发** | `actuator_servos` | `:211` | 本板无舵机 ⇒ 全 `NAN`（`:728`） |
| **发** | `actuator_servos_trim` | `:212` | |
| **发** | `control_allocator_status` ×2 | `:208` | `mc_rate_control` 订它做饱和保护（[`MulticopterRateControl.hpp:98`](control_allocator.md#^src-src-modules-mc-rate-control-MulticopterRateControl-hpp-98)） |

---

## 3. `Run()` 的主线（`ControlAllocator.cpp`）

```c
if (_vehicle_torque_setpoint_sub.update(&vehicle_torque_setpoint)) {   // :383 ★ 触发
    ...
    _actuator_effectiveness->stopMotorsBasedOnThrustSetpoint(_thrust_sp);   // :394
    update_effectiveness_matrix_if_needed(...);                             // :403
    ...
    for (int i = 0; i < _num_control_allocation; i++) {
        _control_allocation[i]->allocate();                                // :435 ★ 解算
        _actuator_effectiveness->allocateAuxilaryControls(...);            // :436
        _actuator_effectiveness->updateSetpoint(c[i], i, ...);             // :437
    }
    ...
    publish_actuator_controls();       // :454 调用 → 函数体 :717 起，组包 :723-755，publish actuator_motors :757
}
```

**有效性矩阵（effectiveness matrix）怎么来的**（这是"机型 → 电机分配"的机制）：

| 步 | 做什么 | 出处 |
|---|---|---|
| 1 | 从参数读电机数 | [`ActuatorEffectivenessRotors.cpp:87`](control_allocator.md#^src-src-modules-control-allocator-VehicleActuatorEffectiveness-ActuatorEffectivenessRotors-cpp-87) `_geometry.num_rotors = min(NUM_ROTORS_MAX, CA_ROTOR_COUNT)` |
| 2 | 逐电机读位置/方向/系数 | `:89` 起循环 |
| 3 | 组装矩阵 | `:143 computeEffectivenessMatrix(...)` |
| 4 | 把电机登记成"执行器" | `:128 addActuators(Configuration &)` |
| 5 | 有变化才重建（限速 100 ms） | [`ControlAllocator.cpp:472`](control_allocator.md#^src-src-modules-control-allocator-ControlAllocator-cpp-472) |

**⇒ 本板对应**：`SYS_AUTOSTART=4001` ⇒ 机型脚本 `ROMFS/px4fmu_common/init.d/airframes/4001_quad_x:14-24` 写入 `CA_ROTOR_COUNT=4` 与四个电机的 `CA_ROTORn_PX/PY/KM`。见 `work/PX4接电调-QGC配置清单.md` §1。

---

## 4. ★ 出了 `actuator_motors` 之后（接上 DShot）

```
control_allocator  ── actuator_motors（control[0..11]，本板只用 0..3；未用的填 NAN :753-755）
      ▼
dshot / pwm_out 的 MixingOutput（FunctionMotors.hpp:52 订阅 actuator_motors）
      ▼  mixer_module.cpp:421 update()
         :424 读 actuator_armed  → 决定给不给油门
         :440-441 _function_allocated[i]->update()  ← 取回每个通道的值
         :532 _interface.updateOutputs(...)          ← 交给 DShot 打包
         :534 setAndPublishActuatorOutputs(...)      → 发 actuator_outputs
      ▼
PWM_MAIN_FUNCn（=101..104 ⇒ Motor1..4，output_functions.yaml:10-12）
      ▼
up_dshot_motor_command(...)（drv_dshot.h:116）→ up_dshot_trigger（:124）
      ▼  DMA → TIM1 CCR1..4
PA8 / PE11 / PE13 / PE14（boards/rm2027/fmu-h743/src/timer_config.cpp:57-60）
```

**⇒ 一个著名的"看起来没输出"故障点**：`PWM_MAIN_FUNC1..4` 缺省全是 **0 = Disabled**
（`build/rm2027_fmu-h743_default/generated_params/module_params.c:2243/2322/2401/2480`）。
`control_allocator` **照样在发** `actuator_motors`，但 `MixingOutput` 找不到任何"已分配功能的通道"
⇒ `updateOutputs` 拿到的全是 disarmed 值 ⇒ **4 路一点脉冲都没有**。

---

## 5. 判据

```sh
control_allocator status        # 有效性来源、控制分配矩阵数、饱和情况
listener actuator_motors        # ★ 这一路有没有值
listener control_allocator_status
actuator_test --motor 1 0.2     # 绕过控制链直接测输出（会走 MixingOutput 的 actuator_test 分支 :449）
```
**分诊表**：

| 现象 | 卡在哪 |
|---|---|
| `actuator_motors` 全 `NAN` | `control_allocator` 没收到 `vehicle_torque_setpoint`（上游 `mc_rate_control` 没起 / 没解锁） |
| `actuator_motors` 有值，`actuator_outputs` 无 | `PWM_MAIN_FUNC*` = 0 |
| `actuator_outputs` 有值，示波器无 | `PWM_MAIN_TIM0` 不是 DShot 档（`dshot init` 失败，[`DShot.cpp:1126`](control_allocator.md#^src-src-drivers-dshot-DShot-cpp-1126)）；或硬件 |

---

## 6. 未核实

| 事项 | 说明 |
|---|---|
| `_num_control_allocation > 1` 时多个分配矩阵的语义 | 只核到 `:164` 取 `numMatrices()`；双实例/VTOL 场景未展开 |
| `ControlAllocationPseudoInverse` 的数值方法 | 只核到 `_control_allocation[i]->allocate()` 调用点 `:435` |
| `CA_AIRFRAME` 本板实际值 | 由机型脚本的 `CA_*` 决定；未从生成参数表回读 |

---

## 跳转

| 下一步 | 读哪篇 |
|---|---|
| 下游：`actuator_motors` 怎么变成 DShot 位流 | [02_code_twin/drivers/dshot](../drivers/dshot.md) |
| 上游：`vehicle_torque_setpoint` 是谁算的 | [02_code_twin/modules/sensors](sensors.md)（`vehicle_angular_velocity`）、[03_moc/02-sensor-flow](../../03_moc/02-sensor-flow.md) §1 |
| 解锁开关从哪来 | [02_code_twin/modules/commander](commander.md) |
| 六条流全景 | [03_moc/02-sensor-flow](../../03_moc/02-sensor-flow.md) |

---

## 标注源码（代码 + 本文档对它的解释）

> **这是「代码孪生」层**：上面是代码原文（带行号），下面是**本文档针对这一段说的话**。
> 行号可点，直接跳到 PX4 源码那一行。
### `src/drivers/dshot/DShot.cpp`
<a id="src-src-drivers-dshot-DShot-cpp-1126"></a>
**↓ 文档在讲这里：**[`src/drivers/dshot/DShot.cpp:1126`](control_allocator.md#^src-src-drivers-dshot-DShot-cpp-1126)

```c
  1123 │ 		}
  1124 │ 	}
  1125 │ 
▶ 1126 │ 	if (dshot_timer_channels == 0) {
  1127 │ 		PX4_INFO("No channels configured");
  1128 │ 		return false;
  1129 │ 	}
```
> **说明**：actuator_motors 有值，actuator_outputs 无 | PWM_MAIN_FUNC* = 0 | ┃ actuator_outputs 有值，示波器无 | PWM_MAIN_TIM0 不是 DShot 档（dshot init 失败，DShot.cpp:1126）；或硬件 |
^src-src-drivers-dshot-DShot-cpp-1126

### `src/modules/control_allocator/ControlAllocator.cpp`
<a id="src-src-modules-control-allocator-ControlAllocator-cpp-57"></a>
**↓ 文档在讲这里：**[`src/modules/control_allocator/ControlAllocator.cpp:57`](control_allocator.md#^src-src-modules-control-allocator-ControlAllocator-cpp-57)

```c
    54 │ 
    55 │ ControlAllocator::ControlAllocator() :
    56 │ 	ModuleParams(nullptr),
▶   57 │ 	ScheduledWorkItem(MODULE_NAME, px4::wq_configurations::rate_ctrl),
    58 │ 	_loop_perf(perf_alloc(PC_ELAPSED, MODULE_NAME": cycle"))
    59 │ {
    60 │ 	_control_allocator_status_pub[0].advertise();
```
> **说明**：队列 | wq:rate_ctrl（本板优先级 0，最高） | ControlAllocator.cpp:57 |
^src-src-modules-control-allocator-ControlAllocator-cpp-57

<a id="src-src-modules-control-allocator-ControlAllocator-cpp-472"></a>
**↓ 文档在讲这里：**[`src/modules/control_allocator/ControlAllocator.cpp:472`](control_allocator.md#^src-src-modules-control-allocator-ControlAllocator-cpp-472)

```c
   469 │ }
   470 │ 
   471 │ void
▶  472 │ ControlAllocator::update_effectiveness_matrix_if_needed(EffectivenessUpdateReason reason)
   473 │ {
   474 │ 	ActuatorEffectiveness::Configuration config{};
   475 │ 
```
> **说明**：4 | 把电机登记成"执行器" | :128 addActuators(Configuration &) | ┃ 5 | 有变化才重建（限速 100 ms） | ControlAllocator.cpp:472 |
^src-src-modules-control-allocator-ControlAllocator-cpp-472

<a id="src-src-modules-control-allocator-ControlAllocator-cpp-757"></a>
**↓ 文档在讲这里：**[`src/modules/control_allocator/ControlAllocator.cpp:757`](control_allocator.md#^src-src-modules-control-allocator-ControlAllocator-cpp-757)

```c
   754 │ 		actuator_motors.control[i] = NAN;
   755 │ 	}
   756 │ 
▶  757 │ 	_actuator_motors_pub.publish(actuator_motors);
   758 │ 
   759 │ 	// servos
   760 │ 	if (_num_actuators[1] > 0) {
```
> **说明**：订 | parameter_update | :214 | 1 s 周期 | ┃ 发 | actuator_motors | :210；发布 ControlAllocator.cpp:757 | 4 个电机（control[0..3]） |
^src-src-modules-control-allocator-ControlAllocator-cpp-757

### `src/modules/control_allocator/ControlAllocator.hpp`
<a id="src-src-modules-control-allocator-ControlAllocator-hpp-201"></a>
**↓ 文档在讲这里：**[`src/modules/control_allocator/ControlAllocator.hpp:201`](control_allocator.md#^src-src-modules-control-allocator-ControlAllocator-hpp-201)

```c
   198 │ 	//   - https://github.com/PX4/PX4-Autopilot/pull/24955
   199 │ 	//   - https://github.com/PX4/PX4-Autopilot/issues/24230
   200 │ 	//   - https://github.com/PX4/PX4-Autopilot/issues/26971
▶  201 │ 	uORB::SubscriptionCallbackWorkItem _vehicle_torque_setpoint_sub{this, ORB_ID(vehicle_torque_setpoint)};  /**< vehicle torque setpoint subscription */
   202 │ 	uORB::Subscription _vehicle_thrust_setpoint_sub{ORB_ID(vehicle_thrust_setpoint)};  /**< vehicle thrust setpoint subscription, polled when torque is triggered*/
   203 │ 
   204 │ 	uORB::Subscription _vehicle_torque_setpoint1_sub{ORB_ID(vehicle_torque_setpoint), 1};  /**< vehicle torque setpoint subscription (2. instance) */
```
> **说明**：拉起 | rc.mc_apps:11 control_allocator start（VEHICLE_TYPE=mc） | ROMFS/px4fmu_common/init.d/rc.mc_apps:11；经 rcS:580 → rc.vehicle_setup | ┃ 调度 | 由 vehicle_torque_setpoint 的 SubscriptionCallbackWorkItem 驱动（不是定时器） | ControlAllocator.hpp:201 |
> **说明**：订 | vehicle_torque_setpoint | ControlAllocator.hpp:201 | ★ 触发源（callback） |
^src-src-modules-control-allocator-ControlAllocator-hpp-201

### `src/modules/control_allocator/VehicleActuatorEffectiveness/ActuatorEffectivenessRotors.cpp`
<a id="src-src-modules-control-allocator-VehicleActuatorEffectiveness-ActuatorEffectivenessRotors-cpp-87"></a>
**↓ 文档在讲这里：**[`src/modules/control_allocator/VehicleActuatorEffectiveness/ActuatorEffectivenessRotors.cpp:87`](control_allocator.md#^src-src-modules-control-allocator-VehicleActuatorEffectiveness-ActuatorEffectivenessRotors-cpp-87)

```c
    84 │ {
    85 │ 	ModuleParams::updateParams();
    86 │ 
▶   87 │ 	_geometry.num_rotors = math::min(NUM_ROTORS_MAX, static_cast<int>(_param_ca_rotor_count.get()));
    88 │ 
    89 │ 	for (int i = 0; i < _geometry.num_rotors; ++i) {
    90 │ 		Vector3f &position = _geometry.rotors[i].position;
```
> **说明**：1 | 从参数读电机数 | ActuatorEffectivenessRotors.cpp:87 _geometry.num_rotors = min(NUM_ROTORS_MAX, CA_ROTOR_COUNT) |
^src-src-modules-control-allocator-VehicleActuatorEffectiveness-ActuatorEffectivenessRotors-cpp-87

### `src/modules/mc_rate_control/MulticopterRateControl.cpp`
<a id="src-src-modules-mc-rate-control-MulticopterRateControl-cpp-50"></a>
**↓ 文档在讲这里：**[`src/modules/mc_rate_control/MulticopterRateControl.cpp:50`](control_allocator.md#^src-src-modules-mc-rate-control-MulticopterRateControl-cpp-50)

```c
    47 │ 
    48 │ MulticopterRateControl::MulticopterRateControl(bool vtol) :
    49 │ 	ModuleParams(nullptr),
▶   50 │ 	WorkItem(MODULE_NAME, px4::wq_configurations::rate_ctrl),
    51 │ 	_vehicle_thrust_setpoint_pub(vtol ? ORB_ID(vehicle_thrust_setpoint_virtual_mc) : ORB_ID(vehicle_thrust_setpoint)),
    52 │ 	_vehicle_torque_setpoint_pub(vtol ? ORB_ID(vehicle_torque_setpoint_virtual_mc) : ORB_ID(vehicle_torque_setpoint)),
    53 │ 	_loop_perf(perf_alloc(PC_ELAPSED, MODULE_NAME": cycle"))
```
> **说明**：★ 它在优先级 0 的队列上，和 VehicleAngularVelocity（VehicleAngularVelocity.cpp:47）、mc_rate_control（MulticopterRateControl.cpp:50）同队列。
^src-src-modules-mc-rate-control-MulticopterRateControl-cpp-50

### `src/modules/mc_rate_control/MulticopterRateControl.hpp`
<a id="src-src-modules-mc-rate-control-MulticopterRateControl-hpp-98"></a>
**↓ 文档在讲这里：**[`src/modules/mc_rate_control/MulticopterRateControl.hpp:98`](control_allocator.md#^src-src-modules-mc-rate-control-MulticopterRateControl-hpp-98)

```c
    95 │ 	RateControl _rate_control; ///< class for rate control calculations
    96 │ 
    97 │ 	uORB::Subscription _battery_status_sub{ORB_ID(battery_status)};
▶   98 │ 	uORB::Subscription _control_allocator_status_sub{ORB_ID(control_allocator_status)};
    99 │ 	uORB::Subscription _manual_control_setpoint_sub{ORB_ID(manual_control_setpoint)};
   100 │ 	uORB::Subscription _vehicle_control_mode_sub{ORB_ID(vehicle_control_mode)};
   101 │ 	uORB::Subscription _vehicle_land_detected_sub{ORB_ID(vehicle_land_detected)};
```
> **说明**：发 | actuator_servos_trim | :212 | | ┃ 发 | control_allocator_status ×2 | :208 | mc_rate_control 订它做饱和保护（MulticopterRateControl.hpp:98） |
^src-src-modules-mc-rate-control-MulticopterRateControl-hpp-98

### `src/modules/sensors/vehicle_angular_velocity/VehicleAngularVelocity.cpp`
<a id="src-src-modules-sensors-vehicle-angular-velocity-VehicleAngularVelocity-cpp-47"></a>
**↓ 文档在讲这里：**[`src/modules/sensors/vehicle_angular_velocity/VehicleAngularVelocity.cpp:47`](control_allocator.md#^src-src-modules-sensors-vehicle-angular-velocity-VehicleAngularVelocity-cpp-47)

```c
    44 │ 
    45 │ VehicleAngularVelocity::VehicleAngularVelocity() :
    46 │ 	ModuleParams(nullptr),
▶   47 │ 	ScheduledWorkItem(MODULE_NAME, px4::wq_configurations::rate_ctrl)
    48 │ {
    49 │ 	_vehicle_angular_velocity_pub.advertise();
    50 │ }
```
> **说明**：★ 它在优先级 0 的队列上，和 VehicleAngularVelocity（VehicleAngularVelocity.cpp:47）、mc_rate_control（MulticopterRateControl.cpp:50）同队列。
^src-src-modules-sensors-vehicle-angular-velocity-VehicleAngularVelocity-cpp-47
