# `src/modules/manual_control/ManualControl.cpp` —— 把"好几路输入"合并成一个 `manual_control_setpoint`

> **运行时一句话**：它站在 `rc_update`（硬件遥控）和 MAVLink（虚拟摇杆）**中间**：
> 谁先动听谁的、谁失效切下一个，最后**统一成一个** `manual_control_setpoint`，
> 并把开关/按钮翻译成 `action_request`（解锁、切模式、kill）。
> **⇒ 它是"手动控制"这条链唯一的出口；`commander` 和所有控制器都只看它的输出。**
> 行号基准 `源码根（见 `tools/source-root.conf`）` HEAD `3b5de24`。

---

## 1. 它活在哪

| 项 | 值 | 出处 |
|---|---|---|
| 队列 | **`wq:hp_default`**（本板优先级 **-18**） | [`ManualControl.cpp:44`](rc_update.md#^src-src-modules-manual-control-ManualControl-cpp-44) |
| 拉起 | `rcS:510` `manual_control start`（紧接着 `rc_update` 的 `:509`） | `rcS:509-510` |
| 调度 | 由**多个来源的订阅回调**驱动 + `ScheduleDelayed(200_ms)` 心跳 | `:174`（`registerCallback`）、`:84` |
| 多来源上限 | `MAX_MANUAL_INPUT_COUNT` | [`ManualControl.hpp:107`](manual_control.md#^src-src-modules-manual-control-ManualControl-hpp-107)（`_manual_control_input_subs[]`） |

---

## 2. 订阅 / 发布

| 方向 | 话题 | 声明处 | 消费/发布点 |
|---|---|---|---|
| 订 | `manual_control_input` **×N**（多实例） | [`ManualControl.hpp:108`](mavlink.md#^src-src-modules-manual-control-ManualControl-hpp-108)（数组） | [`ManualControl.cpp:116`](manual_control.md#^src-src-modules-manual-control-ManualControl-cpp-116) 逐个 `update()` |
| 订 | `manual_control_switches` | [`ManualControl.hpp:112`](manual_control.md#^src-src-modules-manual-control-ManualControl-hpp-112)（callback） | `:200` |
| 订 | `vehicle_status` | [`ManualControl.hpp:114`](manual_control.md#^src-src-modules-manual-control-ManualControl-hpp-114) | 决定哪些模式可用 |
| 订 | `parameter_update` | [`ManualControl.hpp:113`](manual_control.md#^src-src-modules-manual-control-ManualControl-hpp-113)（1 s） | `:351 updateParams()` |
| **发** | **`manual_control_setpoint`** | [`ManualControl.hpp:118`](manual_control.md#^src-src-modules-manual-control-ManualControl-hpp-118) | `:156`、`:179` |
| **发** | `action_request` | [`ManualControl.hpp:116`](manual_control.md#^src-src-modules-manual-control-ManualControl-hpp-116) | `:497 sendActionRequest()` → `:509 publish` |
| **发** | `landing_gear` | [`ManualControl.hpp:117`](manual_control.md#^src-src-modules-manual-control-ManualControl-hpp-117) | 按钮控制起落架 |

---

## 3. ★ 多来源仲裁（`ManualControlSelector`）

```c
// :116  逐个来源更新；返回 true 的是"这一拍有新数据的那个"
for (i in inputs) { if (_manual_control_input_subs[i].update(&manual_control_input)) { ... } }

// :156  由 Selector 决定"现在该用哪一路"并把结果发出去
_manual_control_setpoint_pub.publish(_selector.setpoint());            // :156（变化时立即发）

// :164-168  切换来源时把回调搬过去（保证被打断时不漏帧）
_manual_control_input_subs[_previous_..._instance].unregisterCallback();
_manual_control_input_subs[instance].registerCallback();

// :174  switches 也走回调
_manual_control_switches_sub.registerCallback();

// :179  心跳
_manual_control_setpoint_pub.publish(_selector.setpoint());
```

仲裁逻辑在 `ManualControlSelector.cpp`／`ManualControlSelector.hpp`（含专门的 `ManualControlSelectorTest.cpp`）。
`[源码]` 本文只核到"由 `_selector` 决定"和切换回调这两个动作；**选优的判据（超时时间、优先级）未展开**，见 §6。

---

## 4. ★ 开关 → 动作（`action_request` 的产生地）

[`ManualControl.cpp:214`](manual_control.md#^src-src-modules-manual-control-ManualControl-cpp-214) 是整段 switch 分发。**这就是 `commander` 收到的解锁请求的源头**：

| 输入 | 产生的 `action_request` | 出处 |
|---|---|---|
| `switches.arm_switch == SWITCH_POS_ON` | `ACTION_ARM`（`SOURCE_RC_SWITCH`） | `:222-224` |
| `switches.arm_switch == SWITCH_POS_OFF` | `ACTION_DISARM` | `:226-227` |
| 按钮（带迟滞） | `ACTION_TOGGLE_ARMING`（`SOURCE_RC_BUTTON`） | `:214`（`_button_arm_hysteresis`）、`:217` |
| 模式槽位 | `ACTION_SWITCH_MODE`（`SOURCE_RC_MODE_SLOT` / `SOURCE_RC_SWITCH`） | `:234/244/254`、`:462` |
| kill 开关 | `ACTION_KILL` / `ACTION_UNKILL` | `:264/267` |
| 终止开关 | `ACTION_TERMINATION` | `:273` |
| **摇杆手势** | `ACTION_ARM` / `ACTION_DISARM` / `ACTION_KILL`（`SOURCE_STICK_GESTURE`） | `:421/431/446` |

**★ 一个易忘的联动**：[`ManualControl.cpp:365`](manual_control.md#^src-src-modules-manual-control-ManualControl-cpp-365) ——
**只要配了 `RC_MAP_ARM_SW`，就会主动禁用"摇杆手势解锁"**（`param_find("RC_MAP_ARM_SW")`，`:366`）。
⇒ 配了解锁开关之后，摇杆打 V 字就不会解锁了。这是**故意**的（`:381` 有 event 说明）。

**摇杆手势与开关的优先级**（`[源码]` `:214-292` 与 `:421-446` 并列存在）：
两者都会产生 `ACTION_ARM`；`commander` 收到即执行（[`Commander.cpp:1864`](manual_control.md#^src-src-modules-commander-Commander-cpp-1864)），**没有去重**，
所以同时触发会打两条 —— 实际后果需要上板观察，**未核实**。

---

## 5. 判据

```sh
listener manual_control_input      # 上游（rc_update 或 mavlink）
listener manual_control_switches
listener manual_control_setpoint   # ★ 这个模块的产物
listener action_request            # 开关动作有没有产生
manual_control status              # 当前选中的来源、各来源超时状态
param show RC_MAP_ARM_SW
```
**分诊**：
- 有 `manual_control_input`、没 `manual_control_setpoint` ⇒ 卡在 `_selector`（来源被判失效 / 超时）。
- `manual_control_setpoint` 有值但 `valid=false` ⇒ 仲裁过但判无效。
- QGC 虚拟摇杆能用 = MAVLink 支线通（[`mavlink_receiver.h:402`](mavlink.md#^src-src-modules-mavlink-mavlink-receiver-h-402) 发的 `manual_control_input`）。

---

## 6. 未核实

| 事项 | 说明 |
|---|---|
| `ManualControlSelector` 的选优/超时判据 | 只核到调用点 `:156/179` 与文件存在；算法未展开 |
| `MAX_MANUAL_INPUT_COUNT` 的实际值 | [`ManualControl.hpp:107`](manual_control.md#^src-src-modules-manual-control-ManualControl-hpp-107) 的数组用了它，值未核 |
| 摇杆手势与开关"同时触发"的实际后果 | 只核到两条路都会发 `ACTION_ARM`；`commander` 侧未见到去重 |
| `landing_gear` 在本板是否有消费者 | 本板无起落架机构，未核下游 |

---

## 跳转

| 下一步 | 读哪篇 |
|---|---|
| 上游：硬件遥控支线 | [02_code_twin/modules/rc_update](rc_update.md) |
| 上游：MAVLink 虚拟摇杆支线 | [02_code_twin/modules/mavlink](mavlink.md) |
| 下游：`action_request` 被谁执行 | [02_code_twin/modules/commander](commander.md) §3 |
| 下游：`manual_control_setpoint` 被谁吃 | [02_code_twin/modules/ekf2](ekf2.md)（不）、`mc_att_control`、`mc_rate_control`、`flight_mode_manager` |
| 六条流全景 | [03_moc/02-sensor-flow](../../03_moc/02-sensor-flow.md) §6 |

---

## 标注源码（代码 + 本文档对它的解释）

> **这是「代码孪生」层**：上面是代码原文（带行号），下面是**本文档针对这一段说的话**。
> 行号可点，直接跳到 PX4 源码那一行。
### `src/modules/commander/Commander.cpp`
<a id="src-src-modules-commander-Commander-cpp-1864"></a>
**↓ 文档在讲这里：**[`src/modules/commander/Commander.cpp:1864`](manual_control.md#^src-src-modules-commander-Commander-cpp-1864)

```c
  1861 │ 	switch (action_request.action) {
  1862 │ 	case action_request_s::ACTION_DISARM: disarm(arm_disarm_reason); break;
  1863 │ 
▶ 1864 │ 	case action_request_s::ACTION_ARM: arm(arm_disarm_reason); break;
  1865 │ 
  1866 │ 	case action_request_s::ACTION_TOGGLE_ARMING:
  1867 │ 		if (isArmed()) {
```
> **说明**：摇杆手势与开关的优先级（[源码] :214-292 与 :421-446 并列存在）： ┃ 两者都会产生 ACTION_ARM；commander 收到即执行（Commander.cpp:1864），没有去重，
^src-src-modules-commander-Commander-cpp-1864

### `src/modules/manual_control/ManualControl.cpp`
<a id="src-src-modules-manual-control-ManualControl-cpp-44"></a>
**↓ 文档在讲这里：**[`src/modules/manual_control/ManualControl.cpp:44`](manual_control.md#^src-src-modules-manual-control-ManualControl-cpp-44)

```c
    41 │ 
    42 │ ManualControl::ManualControl() :
    43 │ 	ModuleParams(nullptr),
▶   44 │ 	ScheduledWorkItem(MODULE_NAME, px4::wq_configurations::hp_default)
    45 │ {
    46 │ 	updateParams();
    47 │ }
```
> **说明**：队列 | wq:hp_default（本板优先级 -18） | ManualControl.cpp:44 |
^src-src-modules-manual-control-ManualControl-cpp-44

<a id="src-src-modules-manual-control-ManualControl-cpp-116"></a>
**↓ 文档在讲这里：**[`src/modules/manual_control/ManualControl.cpp:116`](manual_control.md#^src-src-modules-manual-control-ManualControl-cpp-116)

```c
   113 │ 	for (int i = 0; i < MAX_MANUAL_INPUT_COUNT; i++) {
   114 │ 		manual_control_setpoint_s manual_control_input;
   115 │ 
▶  116 │ 		if (_manual_control_input_subs[i].update(&manual_control_input)) {
   117 │ 			_selector.updateWithNewInputSample(now, manual_control_input, i);
   118 │ 		}
   119 │ 	}
```
> **说明**：订 | manual_control_input ×N（多实例） | ManualControl.hpp:108（数组） | ManualControl.cpp:116 逐个 update() |
^src-src-modules-manual-control-ManualControl-cpp-116

<a id="src-src-modules-manual-control-ManualControl-cpp-214"></a>
**↓ 文档在讲这里：**[`src/modules/manual_control/ManualControl.cpp:214`](manual_control.md#^src-src-modules-manual-control-ManualControl-cpp-214)

```c
   211 │ 				if (_param_com_arm_swisbtn.get()) {
   212 │ 					// Arming button
   213 │ 					const bool previous_button_arm_hysteresis = _button_arm_hysteresis.get_state();
▶  214 │ 					_button_arm_hysteresis.set_state_and_update(switches.arm_switch == manual_control_switches_s::SWITCH_POS_ON, now);
   215 │ 
   216 │ 					if (!previous_button_arm_hysteresis && _button_arm_hysteresis.get_state()) {
   217 │ 						sendActionRequest(action_request_s::ACTION_TOGGLE_ARMING, action_request_s::SOURCE_RC_BUTTON);
```
> **说明**：ManualControl.cpp:214 是整段 switch 分发。这就是 commander 收到的解锁请求的源头：
^src-src-modules-manual-control-ManualControl-cpp-214

<a id="src-src-modules-manual-control-ManualControl-cpp-365"></a>
**↓ 文档在讲这里：**[`src/modules/manual_control/ManualControl.cpp:365`](manual_control.md#^src-src-modules-manual-control-ManualControl-cpp-365)

```c
   362 │ 
   363 │ 	// MAN_ARM_GESTURE
   364 │ 	if (_param_man_arm_gesture.get() == 1) {
▶  365 │ 		// RC_MAP_ARM_SW & MAN_ARM_GESTURE: disable arm gesture if an arm switch is configured
   366 │ 		param_t param_rc_map_arm_sw = param_find("RC_MAP_ARM_SW");
   367 │ 
   368 │ 		if (param_rc_map_arm_sw != PARAM_INVALID) {
```
> **说明**：★ 一个易忘的联动：ManualControl.cpp:365 ——
^src-src-modules-manual-control-ManualControl-cpp-365

### `src/modules/manual_control/ManualControl.hpp`
<a id="src-src-modules-manual-control-ManualControl-hpp-107"></a>
**↓ 文档在讲这里：**[`src/modules/manual_control/ManualControl.hpp:107`](manual_control.md#^src-src-modules-manual-control-ManualControl-hpp-107)

```c
   104 │ 	void send_photo_command();
   105 │ 	void send_video_command();
   106 │ 
▶  107 │ 	uORB::SubscriptionCallbackWorkItem _manual_control_input_subs[MAX_MANUAL_INPUT_COUNT] {
   108 │ 		{this, ORB_ID(manual_control_input), 0},
   109 │ 		{this, ORB_ID(manual_control_input), 1},
   110 │ 		{this, ORB_ID(manual_control_input), 2},
```
> **说明**：调度 | 由多个来源的订阅回调驱动 + ScheduleDelayed(200_ms) 心跳 | :174（registerCallback）、:84 | ┃ 多来源上限 | MAX_MANUAL_INPUT_COUNT | ManualControl.hpp:107（_manual_control_input_subs[]） |
> **说明**：ManualControlSelector 的选优/超时判据 | 只核到调用点 :156/179 与文件存在；算法未展开 | ┃ MAX_MANUAL_INPUT_COUNT 的实际值 | ManualControl.hpp:107 的数组用了它，值未核 |
^src-src-modules-manual-control-ManualControl-hpp-107

<a id="src-src-modules-manual-control-ManualControl-hpp-108"></a>
**↓ 文档在讲这里：**[`src/modules/manual_control/ManualControl.hpp:108`](manual_control.md#^src-src-modules-manual-control-ManualControl-hpp-108)

```c
   105 │ 	void send_video_command();
   106 │ 
   107 │ 	uORB::SubscriptionCallbackWorkItem _manual_control_input_subs[MAX_MANUAL_INPUT_COUNT] {
▶  108 │ 		{this, ORB_ID(manual_control_input), 0},
   109 │ 		{this, ORB_ID(manual_control_input), 1},
   110 │ 		{this, ORB_ID(manual_control_input), 2},
   111 │ 	};
```
> **说明**：订 | manual_control_input ×N（多实例） | ManualControl.hpp:108（数组） | ManualControl.cpp:116 逐个 update() |
^src-src-modules-manual-control-ManualControl-hpp-108

<a id="src-src-modules-manual-control-ManualControl-hpp-112"></a>
**↓ 文档在讲这里：**[`src/modules/manual_control/ManualControl.hpp:112`](manual_control.md#^src-src-modules-manual-control-ManualControl-hpp-112)

```c
   109 │ 		{this, ORB_ID(manual_control_input), 1},
   110 │ 		{this, ORB_ID(manual_control_input), 2},
   111 │ 	};
▶  112 │ 	uORB::SubscriptionCallbackWorkItem _manual_control_switches_sub{this, ORB_ID(manual_control_switches)};
   113 │ 	uORB::SubscriptionInterval _parameter_update_sub{ORB_ID(parameter_update), 1_s};
   114 │ 	uORB::Subscription _vehicle_status_sub{ORB_ID(vehicle_status)};
   115 │ 
```
> **说明**：订 | manual_control_input ×N（多实例） | ManualControl.hpp:108（数组） | ManualControl.cpp:116 逐个 update() | ┃ 订 | manual_control_switches | ManualControl.hpp:112（callback） | :200 |
^src-src-modules-manual-control-ManualControl-hpp-112

<a id="src-src-modules-manual-control-ManualControl-hpp-113"></a>
**↓ 文档在讲这里：**[`src/modules/manual_control/ManualControl.hpp:113`](manual_control.md#^src-src-modules-manual-control-ManualControl-hpp-113)

```c
   110 │ 		{this, ORB_ID(manual_control_input), 2},
   111 │ 	};
   112 │ 	uORB::SubscriptionCallbackWorkItem _manual_control_switches_sub{this, ORB_ID(manual_control_switches)};
▶  113 │ 	uORB::SubscriptionInterval _parameter_update_sub{ORB_ID(parameter_update), 1_s};
   114 │ 	uORB::Subscription _vehicle_status_sub{ORB_ID(vehicle_status)};
   115 │ 
   116 │ 	uORB::Publication<action_request_s> _action_request_pub{ORB_ID(action_request)};
```
> **说明**：订 | vehicle_status | ManualControl.hpp:114 | 决定哪些模式可用 | ┃ 订 | parameter_update | ManualControl.hpp:113（1 s） | :351 updateParams() |
^src-src-modules-manual-control-ManualControl-hpp-113

<a id="src-src-modules-manual-control-ManualControl-hpp-114"></a>
**↓ 文档在讲这里：**[`src/modules/manual_control/ManualControl.hpp:114`](manual_control.md#^src-src-modules-manual-control-ManualControl-hpp-114)

```c
   111 │ 	};
   112 │ 	uORB::SubscriptionCallbackWorkItem _manual_control_switches_sub{this, ORB_ID(manual_control_switches)};
   113 │ 	uORB::SubscriptionInterval _parameter_update_sub{ORB_ID(parameter_update), 1_s};
▶  114 │ 	uORB::Subscription _vehicle_status_sub{ORB_ID(vehicle_status)};
   115 │ 
   116 │ 	uORB::Publication<action_request_s> _action_request_pub{ORB_ID(action_request)};
   117 │ 	uORB::Publication<landing_gear_s> _landing_gear_pub{ORB_ID(landing_gear)};
```
> **说明**：订 | manual_control_switches | ManualControl.hpp:112（callback） | :200 | ┃ 订 | vehicle_status | ManualControl.hpp:114 | 决定哪些模式可用 |
^src-src-modules-manual-control-ManualControl-hpp-114

<a id="src-src-modules-manual-control-ManualControl-hpp-116"></a>
**↓ 文档在讲这里：**[`src/modules/manual_control/ManualControl.hpp:116`](manual_control.md#^src-src-modules-manual-control-ManualControl-hpp-116)

```c
   113 │ 	uORB::SubscriptionInterval _parameter_update_sub{ORB_ID(parameter_update), 1_s};
   114 │ 	uORB::Subscription _vehicle_status_sub{ORB_ID(vehicle_status)};
   115 │ 
▶  116 │ 	uORB::Publication<action_request_s> _action_request_pub{ORB_ID(action_request)};
   117 │ 	uORB::Publication<landing_gear_s> _landing_gear_pub{ORB_ID(landing_gear)};
   118 │ 	uORB::Publication<manual_control_setpoint_s> _manual_control_setpoint_pub{ORB_ID(manual_control_setpoint)};
   119 │ 
```
> **说明**：发 | manual_control_setpoint | ManualControl.hpp:118 | :156、:179 | ┃ 发 | action_request | ManualControl.hpp:116 | :497 sendActionRequest() → :509 publish |
^src-src-modules-manual-control-ManualControl-hpp-116

<a id="src-src-modules-manual-control-ManualControl-hpp-117"></a>
**↓ 文档在讲这里：**[`src/modules/manual_control/ManualControl.hpp:117`](manual_control.md#^src-src-modules-manual-control-ManualControl-hpp-117)

```c
   114 │ 	uORB::Subscription _vehicle_status_sub{ORB_ID(vehicle_status)};
   115 │ 
   116 │ 	uORB::Publication<action_request_s> _action_request_pub{ORB_ID(action_request)};
▶  117 │ 	uORB::Publication<landing_gear_s> _landing_gear_pub{ORB_ID(landing_gear)};
   118 │ 	uORB::Publication<manual_control_setpoint_s> _manual_control_setpoint_pub{ORB_ID(manual_control_setpoint)};
   119 │ 
   120 │ 	ManualControlSelector _selector;
```
> **说明**：发 | action_request | ManualControl.hpp:116 | :497 sendActionRequest() → :509 publish | ┃ 发 | landing_gear | ManualControl.hpp:117 | 按钮控制起落架 |
^src-src-modules-manual-control-ManualControl-hpp-117

<a id="src-src-modules-manual-control-ManualControl-hpp-118"></a>
**↓ 文档在讲这里：**[`src/modules/manual_control/ManualControl.hpp:118`](manual_control.md#^src-src-modules-manual-control-ManualControl-hpp-118)

```c
   115 │ 
   116 │ 	uORB::Publication<action_request_s> _action_request_pub{ORB_ID(action_request)};
   117 │ 	uORB::Publication<landing_gear_s> _landing_gear_pub{ORB_ID(landing_gear)};
▶  118 │ 	uORB::Publication<manual_control_setpoint_s> _manual_control_setpoint_pub{ORB_ID(manual_control_setpoint)};
   119 │ 
   120 │ 	ManualControlSelector _selector;
   121 │ 
```
> **说明**：订 | parameter_update | ManualControl.hpp:113（1 s） | :351 updateParams() | ┃ 发 | manual_control_setpoint | ManualControl.hpp:118 | :156、:179 |
^src-src-modules-manual-control-ManualControl-hpp-118

### `src/modules/mavlink/mavlink_receiver.h`
<a id="src-src-modules-mavlink-mavlink-receiver-h-402"></a>
**↓ 文档在讲这里：**[`src/modules/mavlink/mavlink_receiver.h:402`](manual_control.md#^src-src-modules-mavlink-mavlink-receiver-h-402)

```c
   399 │ 	uORB::PublicationMulti<aux_global_position_s>		_aux_global_position_pub{ORB_ID(aux_global_position)};
   400 │ 	uORB::PublicationMulti<rtcm_data_s>		_rtcm_corrections_pub{ORB_ID(rtcm_corrections)};
   401 │ 	uORB::PublicationMulti<input_rc_s>			_rc_pub{ORB_ID(input_rc)};
▶  402 │ 	uORB::PublicationMulti<manual_control_setpoint_s>	_manual_control_input_pub{ORB_ID(manual_control_input)};
   403 │ 	uORB::PublicationMulti<ping_s>				_ping_pub{ORB_ID(ping)};
   404 │ 	uORB::PublicationMulti<radio_status_s>			_radio_status_pub{ORB_ID(radio_status)};
   405 │ 	uORB::PublicationMulti<sensor_baro_s>			_sensor_baro_pub{ORB_ID(sensor_baro)};
```
> **说明**：manual_control_setpoint 有值但 valid=false ⇒ 仲裁过但判无效。 ┃ QGC 虚拟摇杆能用 = MAVLink 支线通（mavlink_receiver.h:402 发的 manual_control_input）。
^src-src-modules-mavlink-mavlink-receiver-h-402
