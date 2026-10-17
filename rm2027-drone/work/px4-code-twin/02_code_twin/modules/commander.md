# `src/modules/commander/Commander.cpp` —— 指挥：解锁、模式、失效保护

> **运行时一句话**：它**不采数据、不算控制**，它管的是"**允不允许**"：
> 允许解锁吗（一堆 Arming Check）、现在是哪个飞行模式、出故障了怎么失效保护。
> **⇒ 它是 `actuator_armed` 的唯一发布者，而 `actuator_armed` 是"电机能不能动"的总闸。**
> 行号基准 `源码根（见 `tools/source-root.conf`）` HEAD `3b5de24`。

---

## 1. 它活在哪

| 项 | 值 |
|---|---|
| 活法 | **自己的线程**（`ModuleBase`，`Commander.cpp` 里没有 `wq_configurations` —— 对比 `mc_rate_control`） |
| 拉起 | `rcS:551` `commander start`（真机分支；HITL 是 `:543`） |
| 位置 | 在 `rc_update`(:509) / `manual_control`(:510) **之后**、`dshot/pwm_out`(:559-560) **之前** |
| 为什么必须在 rc_update 之后 | 解锁开关要走 `manual_control_switches → manual_control → action_request`（见 §3） |
| 为什么必须在 dshot 之前 | DShot 的 `MixingOutput` 要读 `actuator_armed` 才给油门（[`mixer_module.cpp:424`](commander.md#^src-src-lib-mixer-module-mixer-module-cpp-424)） |

---

## 2. 订阅 / 发布

| 方向 | 话题 | 声明处 | 干什么 |
|---|---|---|---|
| 订 | `action_request` | [`Commander.hpp:301`](commander.md#^src-src-modules-commander-Commander-hpp-301) | ★ 解锁/模式/终止请求；处理 [`Commander.cpp:2108`](commander.md#^src-src-modules-commander-Commander-cpp-2108)，分派 `:1862-1864` |
| 订 | `manual_control_setpoint` | [`Commander.hpp:304`](commander.md#^src-src-modules-commander-Commander-hpp-304) | 手动控制状态（[`Commander.cpp:3129`](commander.md#^src-src-modules-commander-Commander-cpp-3129)） |
| 订 | `vehicle_command` | [`Commander.hpp:306`](mavlink.md#^src-src-modules-commander-Commander-hpp-306) | MAVLink 来的 `COMMAND_LONG`（含 ARM/DISARM，`:1114`） |
| 订 | `vehicle_land_detected` | [`Commander.hpp:308`](commander.md#^src-src-modules-commander-Commander-hpp-308) | 落地判定（影响自动上锁） |
| 订 | `system_power` | [`Commander.hpp:305`](commander.md#^src-src-modules-commander-Commander-hpp-305) | **本板无发布者** ⇒ `powerCheck` 必报（`work/PX4接电调-QGC配置清单.md` §4） |
| 订 | `telemetry_status`（×n） | [`Commander.hpp:313`](commander.md#^src-src-modules-commander-Commander-hpp-313) | 数传链路 |
| 订 | `cpuload` / `mission_result` / `offboard_control_mode` / `power_button_state` | `:302 / :319 / :320 / :316` | |
| 订 | `vehicle_command_mode_executor` / `vehicle_land_detected` / `vtol_vehicle_status` | `:307 / :308 / :309` | |
| **发** | **`actuator_armed`** | `:323`；发布 [`Commander.cpp:2141`](commander.md#^src-src-modules-commander-Commander-cpp-2141) | ★★ **电机总闸** |
| **发** | `vehicle_status` | `:328`；发布 `:2150` | 含 `arming_state`（`:738` ARMED / `:779,812` DISARMED） |
| **发** | `vehicle_control_mode` | `:327`；发布 `:2787` | 手动/自动/offboard 标志位 |
| 发 | `vehicle_command_ack` | `:325` | 命令回执 |
| 发 | `vehicle_command` | `:326` | commander 主动下发的命令 |
| 发 | `actuator_test` | `:324` | QGC 滑块测试 |

---

## 3. ★「RC 解锁开关」到底谁处理（三条话题接力，别找错文件）

很多人的第一反应是"commander 读 `manual_control_switches`" —— **不对**。真实链路是：

```
【rc_update】发布 manual_control_switches（含 arm_switch 字段）
        rc_update.h:179
              │
              ▼
【manual_control】订阅 manual_control_switches
        ManualControl.hpp:112   消费 ManualControl.cpp:214-267
              │  判定 SWITCH_POS_ON/OFF、模式槽位、kill 开关
              ▼
【manual_control】发布 action_request
        ManualControl.hpp:116；sendActionRequest() ManualControl.cpp:497，publish :509
        例：:224 ACTION_ARM / :227 ACTION_DISARM / :234 ACTION_SWITCH_MODE
              │
              ▼
【commander】订阅 action_request
        Commander.hpp:301；处理 Commander.cpp:2108-2114
        分派：:1864 case ACTION_ARM → arm()；:1862 ACTION_DISARM → disarm()
              │
              ▼
【commander】arm()  Commander.cpp:664
        → :738 _vehicle_status.arming_state = ARMING_STATE_ARMED
        → :2141 _actuator_armed_pub.publish(_actuator_armed)
              │
              ▼
【dshot / pwm_out】MixingOutput 读 actuator_armed → 决定给不给油门
        mixer_module.hpp:270；消费 mixer_module.cpp:424
```

**⇒ 口诀**：`RC 开关 → rc_update 翻译 → manual_control 决策 → action_request → commander 执行 → actuator_armed`。
**这条链上任何一环没起来，`actuator_armed.armed` 永远是 false。**

> ⚠️ **本板特殊性**：`RC_PORT_CONFIG = 0`（[`serial_params.c:69`](rc_update.md#^src-build-rm2027-fmu-h743-default-generated-params-serial-params-c-69)）⇒ 没有硬件 RC 输入
> ⇒ `manual_control_switches` 没有发布者 ⇒ **RC 解锁开关这条路本板走不通**。
> 本板目前只能靠 MAVLink（QGC 的 Arm 按钮 → `vehicle_command` → [`Commander.cpp:1114`](commander.md#^src-src-modules-commander-Commander-cpp-1114)）。

---

## 4. 解锁前会被什么拦住（HealthAndArmingChecks）

检查项在 `src/modules/commander/HealthAndArmingChecks/checks/`（每个一个 .cpp/.hpp）。与本项目直接相关的：

| check | 拦什么 | 阈值/出处 |
|---|---|---|
| `imuConsistencyCheck.cpp` | **两路 IMU 不一致** | `COM_ARM_IMU_ACC` 缺省 **0.7 m/s²**（判断在 `:57`）；`COM_ARM_IMU_GYR` 缺省 **0.25 rad/s**（`:88`）；参数定义 [`commander_params.yaml:225`](commander.md#^src-src-modules-commander-commander-params-yaml-225) |
| `accelerometerCheck.cpp` / `gyroCheck.cpp` | 标定缺失、零偏过大 | — |
| `baroCheck.cpp` / `estimatorCheck.cpp` | 气压/估计器不健康 | — |
| `escCheck.cpp` | ESC 状态（订 `actuator_motors`，[`escCheck.hpp:66`](commander.md#^src-src-modules-commander-HealthAndArmingChecks-checks-escCheck-hpp-66)） | — |
| `batteryCheck.cpp` | 电池；**读 `CBRK_SUPPLY_CHK`**（[`batteryCheck.cpp:77`](commander.md#^src-src-modules-commander-HealthAndArmingChecks-checks-batteryCheck-cpp-77)） | 本板刻意不设 `BAT1_V_DIV`（`rc.board_defaults:8-12`） |
| `armPermissionCheck.cpp` | 通用许可 | — |

> ★ `imuConsistencyCheck` 是**本板最可能拦解锁的**：`hxy` 与 `h104` 未标定时逐轴差 11~22%
> （见 `work/PX4接电调-QGC配置清单.md` §4 与 `work/review-02-三问核查.md`）
> ⇒ **必须先把六面标定做完**，否则 `COM_ARM_IMU_ACC` 直接拦。

---

## 5. 判据

```sh
commander status                 # arming_state / 已注册的 checks / 失败项
listener actuator_armed          # ★ armed / prearmed / lockdown
listener vehicle_status
listener vehicle_control_mode
listener action_request          # 看解锁请求有没有进来（谁发的 SOURCE_*）
param show COM_ARM_IMU_ACC COM_ARM_IMU_GYR CBRK_SUPPLY_CHK
```
**分诊**：
- `action_request` 有 `ACTION_ARM`，但 `actuator_armed.armed` 仍 false ⇒ **被 Arming Check 拦**（`commander status` 里能看到是哪一条）。
- `action_request` 一帧都没有 ⇒ 上游断了（`manual_control` 没起 / 没有遥控输入 / QGC 没点）。

---

## 6. 未核实

| 事项 | 说明 |
|---|---|
| `HealthAndArmingChecks` 的注册与遍历机制 | 只核到目录与几个 check 的阈值；未展开 `HealthAndArmingChecks.cpp` |
| `commander` 线程的周期 | 未核 `Commander.cpp` 主循环的 `ScheduleDelayed` 周期 |
| `vehicle_command`(MAVLink) 与 `action_request` 两条入口的优先级/去重 | 只核到两条都通到 `arm()`/`disarm()`（`:1114`、`:1864`） |
| `vtol_vehicle_status` 等本板不适用项 | 只按 `Commander.hpp` 声明列出，未逐个确认在本板是否恒为空 |

---

## 跳转

| 下一步 | 读哪篇 |
|---|---|
| 上游：解锁请求怎么产生 | [02_code_twin/modules/rc_update](rc_update.md) → [02_code_twin/modules/manual_control](manual_control.md) |
| 下游：谁读 `actuator_armed` | [02_code_twin/drivers/dshot](../drivers/dshot.md)（`MixingOutput`）、[02_code_twin/modules/control_allocator](control_allocator.md) |
| MAVLink 入口 | [02_code_twin/modules/mavlink](mavlink.md) |
| 六条流全景 | [03_moc/02-sensor-flow](../../03_moc/02-sensor-flow.md) §6 |

---

## 标注源码（代码 + 本文档对它的解释）

> **这是「代码孪生」层**：上面是代码原文（带行号），下面是**本文档针对这一段说的话**。
> 行号可点，直接跳到 PX4 源码那一行。
### `build/rm2027_fmu-h743_default/generated_params/serial_params.c`
<a id="src-build-rm2027-fmu-h743-default-generated-params-serial-params-c-69"></a>
**↓ 文档在讲这里：**[`build/rm2027_fmu-h743_default/generated_params/serial_params.c:69`](commander.md#^src-build-rm2027-fmu-h743-default-generated-params-serial-params-c-69)

```c
    66 │  * @group Serial
    67 │  * @reboot_required true
    68 │  */
▶   69 │ PARAM_DEFINE_INT32(RC_PORT_CONFIG, 0);
    70 │ 
    71 │ /**
    72 │  * Serial Configuration for FrSky Telemetry
```
> **说明**：⚠️ 本板特殊性：RC_PORT_CONFIG = 0（serial_params.c:69）⇒ 没有硬件 RC 输入
^src-build-rm2027-fmu-h743-default-generated-params-serial-params-c-69

### `src/lib/mixer_module/mixer_module.cpp`
<a id="src-src-lib-mixer-module-mixer-module-cpp-424"></a>
**↓ 文档在讲这里：**[`src/lib/mixer_module/mixer_module.cpp:424`](commander.md#^src-src-lib-mixer-module-mixer-module-cpp-424)

```c
   421 │ bool MixingOutput::update()
   422 │ {
   423 │ 	// check arming state
▶  424 │ 	if (_armed_sub.update(&_armed)) {
   425 │ 		_armed.in_esc_calibration_mode &= _support_esc_calibration;
   426 │ 
   427 │ 		if (_ignore_lockdown) {
```
> **说明**：为什么必须在 rc_update 之后 | 解锁开关要走 manual_control_switches → manual_control → action_request（见 §3） | ┃ 为什么必须在 dshot 之前 | DShot 的 MixingOutput 要读 actuator_armed 才给油门（mixer_module.cpp:424） |
^src-src-lib-mixer-module-mixer-module-cpp-424

### `src/modules/commander/Commander.cpp`
<a id="src-src-modules-commander-Commander-cpp-1114"></a>
**↓ 文档在讲这里：**[`src/modules/commander/Commander.cpp:1114`](commander.md#^src-src-modules-commander-Commander-cpp-1114)

```c
  1111 │ 				if (arming_action == vehicle_command_s::ARMING_ACTION_ARM) {
  1112 │ 					arming_res = arm(arm_disarm_reason, cmd.from_external || !forced);
  1113 │ 
▶ 1114 │ 				} else if (arming_action == vehicle_command_s::ARMING_ACTION_DISARM) {
  1115 │ 					arming_res = disarm(arm_disarm_reason, forced);
  1116 │ 
  1117 │ 				}
```
> **说明**：⇒ manual_control_switches 没有发布者 ⇒ RC 解锁开关这条路本板走不通。 ┃ 本板目前只能靠 MAVLink（QGC 的 Arm 按钮 → vehicle_command → Commander.cpp:1114）。
^src-src-modules-commander-Commander-cpp-1114

<a id="src-src-modules-commander-Commander-cpp-2108"></a>
**↓ 文档在讲这里：**[`src/modules/commander/Commander.cpp:2108`](commander.md#^src-src-modules-commander-Commander-cpp-2108)

```c
  2105 │ 			}
  2106 │ 		}
  2107 │ 
▶ 2108 │ 		if (_action_request_sub.updated()) {
  2109 │ 			const unsigned last_generation = _action_request_sub.get_last_generation();
  2110 │ 			action_request_s action_request;
  2111 │ 
```
> **说明**：订 | action_request | Commander.hpp:301 | ★ 解锁/模式/终止请求；处理 Commander.cpp:2108，分派 :1862-1864 |
^src-src-modules-commander-Commander-cpp-2108

<a id="src-src-modules-commander-Commander-cpp-2141"></a>
**↓ 文档在讲这里：**[`src/modules/commander/Commander.cpp:2141`](commander.md#^src-src-modules-commander-Commander-cpp-2141)

```c
  2138 │ 
  2139 │ 			// publish actuator_armed first (used by output modules)
  2140 │ 			_actuator_armed.timestamp = hrt_absolute_time();
▶ 2141 │ 			_actuator_armed_pub.publish(_actuator_armed);
  2142 │ 
  2143 │ 			// update and publish vehicle_control_mode
  2144 │ 			updateControlMode();
```
> **说明**：订 | vehicle_command_mode_executor / vehicle_land_detected / vtol_vehicle_status | :307 / :308 / :309 | | ┃ 发 | actuator_armed | :323；发布 Commander.cpp:2141 | ★★ 电机总闸 |
^src-src-modules-commander-Commander-cpp-2141

<a id="src-src-modules-commander-Commander-cpp-3129"></a>
**↓ 文档在讲这里：**[`src/modules/commander/Commander.cpp:3129`](commander.md#^src-src-modules-commander-Commander-cpp-3129)

```c
  3126 │ void Commander::manualControlCheck()
  3127 │ {
  3128 │ 	manual_control_setpoint_s manual_control_setpoint;
▶ 3129 │ 	const bool manual_control_updated = _manual_control_setpoint_sub.update(&manual_control_setpoint);
  3130 │ 
  3131 │ 	if (manual_control_updated && manual_control_setpoint.valid) {
  3132 │ 
```
> **说明**：订 | action_request | Commander.hpp:301 | ★ 解锁/模式/终止请求；处理 Commander.cpp:2108，分派 :1862-1864 | ┃ 订 | manual_control_setpoint | Commander.hpp:304 | 手动控制状态（Commander.cpp:3129） |
^src-src-modules-commander-Commander-cpp-3129

### `src/modules/commander/Commander.hpp`
<a id="src-src-modules-commander-Commander-hpp-301"></a>
**↓ 文档在讲这里：**[`src/modules/commander/Commander.hpp:301`](commander.md#^src-src-modules-commander-Commander-hpp-301)

```c
   298 │ 	vtol_vehicle_status_s	_vtol_vehicle_status{};
   299 │ 
   300 │ 	// Subscriptions
▶  301 │ 	uORB::Subscription					_action_request_sub{ORB_ID(action_request)};
   302 │ 	uORB::Subscription					_cpuload_sub{ORB_ID(cpuload)};
   303 │ 	uORB::Subscription					_iridiumsbd_status_sub{ORB_ID(iridiumsbd_status)};
   304 │ 	uORB::Subscription					_manual_control_setpoint_sub{ORB_ID(manual_control_setpoint)};
```
> **说明**：订 | action_request | Commander.hpp:301 | ★ 解锁/模式/终止请求；处理 Commander.cpp:2108，分派 :1862-1864 |
^src-src-modules-commander-Commander-hpp-301

<a id="src-src-modules-commander-Commander-hpp-304"></a>
**↓ 文档在讲这里：**[`src/modules/commander/Commander.hpp:304`](commander.md#^src-src-modules-commander-Commander-hpp-304)

```c
   301 │ 	uORB::Subscription					_action_request_sub{ORB_ID(action_request)};
   302 │ 	uORB::Subscription					_cpuload_sub{ORB_ID(cpuload)};
   303 │ 	uORB::Subscription					_iridiumsbd_status_sub{ORB_ID(iridiumsbd_status)};
▶  304 │ 	uORB::Subscription					_manual_control_setpoint_sub{ORB_ID(manual_control_setpoint)};
   305 │ 	uORB::Subscription					_system_power_sub{ORB_ID(system_power)};
   306 │ 	uORB::Subscription					_vehicle_command_sub{ORB_ID(vehicle_command)};
   307 │ 	uORB::Subscription					_vehicle_command_mode_executor_sub{ORB_ID(vehicle_command_mode_executor)};
```
> **说明**：订 | action_request | Commander.hpp:301 | ★ 解锁/模式/终止请求；处理 Commander.cpp:2108，分派 :1862-1864 | ┃ 订 | manual_control_setpoint | Commander.hpp:304 | 手动控制状态（Commander.cpp:3129） |
^src-src-modules-commander-Commander-hpp-304

<a id="src-src-modules-commander-Commander-hpp-305"></a>
**↓ 文档在讲这里：**[`src/modules/commander/Commander.hpp:305`](commander.md#^src-src-modules-commander-Commander-hpp-305)

```c
   302 │ 	uORB::Subscription					_cpuload_sub{ORB_ID(cpuload)};
   303 │ 	uORB::Subscription					_iridiumsbd_status_sub{ORB_ID(iridiumsbd_status)};
   304 │ 	uORB::Subscription					_manual_control_setpoint_sub{ORB_ID(manual_control_setpoint)};
▶  305 │ 	uORB::Subscription					_system_power_sub{ORB_ID(system_power)};
   306 │ 	uORB::Subscription					_vehicle_command_sub{ORB_ID(vehicle_command)};
   307 │ 	uORB::Subscription					_vehicle_command_mode_executor_sub{ORB_ID(vehicle_command_mode_executor)};
   308 │ 	uORB::Subscription					_vehicle_land_detected_sub{ORB_ID(vehicle_land_detected)};
```
> **说明**：订 | vehicle_land_detected | Commander.hpp:308 | 落地判定（影响自动上锁） | ┃ 订 | system_power | Commander.hpp:305 | 本板无发布者 ⇒ powerCheck 必报（work/PX4接电调-QGC配置清单.md §4） |
^src-src-modules-commander-Commander-hpp-305

<a id="src-src-modules-commander-Commander-hpp-306"></a>
**↓ 文档在讲这里：**[`src/modules/commander/Commander.hpp:306`](commander.md#^src-src-modules-commander-Commander-hpp-306)

```c
   303 │ 	uORB::Subscription					_iridiumsbd_status_sub{ORB_ID(iridiumsbd_status)};
   304 │ 	uORB::Subscription					_manual_control_setpoint_sub{ORB_ID(manual_control_setpoint)};
   305 │ 	uORB::Subscription					_system_power_sub{ORB_ID(system_power)};
▶  306 │ 	uORB::Subscription					_vehicle_command_sub{ORB_ID(vehicle_command)};
   307 │ 	uORB::Subscription					_vehicle_command_mode_executor_sub{ORB_ID(vehicle_command_mode_executor)};
   308 │ 	uORB::Subscription					_vehicle_land_detected_sub{ORB_ID(vehicle_land_detected)};
   309 │ 	uORB::Subscription					_vtol_vehicle_status_sub{ORB_ID(vtol_vehicle_status)};
```
> **说明**：订 | manual_control_setpoint | Commander.hpp:304 | 手动控制状态（Commander.cpp:3129） | ┃ 订 | vehicle_command | Commander.hpp:306 | MAVLink 来的 COMMAND_LONG（含 ARM/DISARM，:1114） |
^src-src-modules-commander-Commander-hpp-306

<a id="src-src-modules-commander-Commander-hpp-308"></a>
**↓ 文档在讲这里：**[`src/modules/commander/Commander.hpp:308`](commander.md#^src-src-modules-commander-Commander-hpp-308)

```c
   305 │ 	uORB::Subscription					_system_power_sub{ORB_ID(system_power)};
   306 │ 	uORB::Subscription					_vehicle_command_sub{ORB_ID(vehicle_command)};
   307 │ 	uORB::Subscription					_vehicle_command_mode_executor_sub{ORB_ID(vehicle_command_mode_executor)};
▶  308 │ 	uORB::Subscription					_vehicle_land_detected_sub{ORB_ID(vehicle_land_detected)};
   309 │ 	uORB::Subscription					_vtol_vehicle_status_sub{ORB_ID(vtol_vehicle_status)};
   310 │ 
   311 │ 	uORB::SubscriptionInterval				_parameter_update_sub{ORB_ID(parameter_update), 1_s};
```
> **说明**：订 | vehicle_command | Commander.hpp:306 | MAVLink 来的 COMMAND_LONG（含 ARM/DISARM，:1114） | ┃ 订 | vehicle_land_detected | Commander.hpp:308 | 落地判定（影响自动上锁） |
^src-src-modules-commander-Commander-hpp-308

<a id="src-src-modules-commander-Commander-hpp-313"></a>
**↓ 文档在讲这里：**[`src/modules/commander/Commander.hpp:313`](commander.md#^src-src-modules-commander-Commander-hpp-313)

```c
   310 │ 
   311 │ 	uORB::SubscriptionInterval				_parameter_update_sub{ORB_ID(parameter_update), 1_s};
   312 │ 
▶  313 │ 	uORB::SubscriptionMultiArray<telemetry_status_s>	_telemetry_status_subs{ORB_ID::telemetry_status};
   314 │ 
   315 │ #if defined(BOARD_HAS_POWER_CONTROL)
   316 │ 	uORB::Subscription					_power_button_state_sub {ORB_ID(power_button_state)};
```
> **说明**：订 | system_power | Commander.hpp:305 | 本板无发布者 ⇒ powerCheck 必报（work/PX4接电调-QGC配置清单.md §4） | ┃ 订 | telemetry_status（×n） | Commander.hpp:313 | 数传链路 |
^src-src-modules-commander-Commander-hpp-313

### `src/modules/commander/HealthAndArmingChecks/checks/batteryCheck.cpp`
<a id="src-src-modules-commander-HealthAndArmingChecks-checks-batteryCheck-cpp-77"></a>
**↓ 文档在讲这里：**[`src/modules/commander/HealthAndArmingChecks/checks/batteryCheck.cpp:77`](commander.md#^src-src-modules-commander-HealthAndArmingChecks-checks-batteryCheck-cpp-77)

```c
    74 │ 
    75 │ void BatteryChecks::checkAndReport(const Context &context, Report &reporter)
    76 │ {
▶   77 │ 	if (circuit_breaker_enabled_by_val(_param_cbrk_supply_chk.get(), CBRK_SUPPLY_CHK_KEY)) {
    78 │ 		// Reset related failsafe flags otherwise failures from before disabling the check cause failsafes without reported reason
    79 │ 		reporter.failsafeFlags().battery_unhealthy = false;
    80 │ 		reporter.failsafeFlags().battery_low_remaining_time = false;
```
> **说明**：escCheck.cpp | ESC 状态（订 actuator_motors，escCheck.hpp:66） | — | ┃ batteryCheck.cpp | 电池；读 CBRK_SUPPLY_CHK（batteryCheck.cpp:77） | 本板刻意不设 BAT1_V_DIV（rc.board_defaults:8-12） |
^src-src-modules-commander-HealthAndArmingChecks-checks-batteryCheck-cpp-77

### `src/modules/commander/HealthAndArmingChecks/checks/escCheck.hpp`
<a id="src-src-modules-commander-HealthAndArmingChecks-checks-escCheck-hpp-66"></a>
**↓ 文档在讲这里：**[`src/modules/commander/HealthAndArmingChecks/checks/escCheck.hpp:66`](commander.md#^src-src-modules-commander-HealthAndArmingChecks-checks-escCheck-hpp-66)

```c
    63 │ 	static constexpr hrt_abstime ESC_TIMEOUT_US = 400_ms;
    64 │ 
    65 │ 	uORB::Subscription _esc_status_sub{ORB_ID(esc_status)};
▶   66 │ 	uORB::Subscription _actuator_motors_sub{ORB_ID(actuator_motors)};
    67 │ 
    68 │ 	const hrt_abstime _start_time{hrt_absolute_time()};
    69 │ 
```
> **说明**：baroCheck.cpp / estimatorCheck.cpp | 气压/估计器不健康 | — | ┃ escCheck.cpp | ESC 状态（订 actuator_motors，escCheck.hpp:66） | — |
^src-src-modules-commander-HealthAndArmingChecks-checks-escCheck-hpp-66

### `src/modules/commander/commander_params.yaml`
<a id="src-src-modules-commander-commander-params-yaml-225"></a>
**↓ 文档在讲这里：**[`src/modules/commander/commander_params.yaml:225`](commander.md#^src-src-modules-commander-commander-params-yaml-225)

```c
   222 │         6: Terminate
   223 │         7: Disarm
   224 │       default: 0
▶  225 │     COM_ARM_IMU_ACC:
   226 │       description:
   227 │         short: Max accelerometer inconsistency for arming
   228 │         long: Maximum accelerometer inconsistency between IMU units that will allow
```
> **说明**：imuConsistencyCheck.cpp | 两路 IMU 不一致 | COM_ARM_IMU_ACC 缺省 0.7 m/s²（判断在 :57）；COM_ARM_IMU_GYR 缺省 0.25 rad/s（:88）；参数定义 commander_params.yaml:225 |
^src-src-modules-commander-commander-params-yaml-225
