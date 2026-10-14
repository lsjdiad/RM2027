# `src/modules/rc_update/rc_update.cpp` —— 原始 RC → 手动控制

> **运行时一句话**：它把 `input_rc` 里的"通道 µs 值"翻译成 PX4 认识的
> **归一化摇杆**（`manual_control_input`）、**开关位置**（`manual_control_switches`）和 **`rc_channels`**（给 MAVLink 看）。
> **⇒ 它是遥控这条链的"翻译层"；它自己不决定飞什么，只决定"遥控器现在说了什么"。**
> 行号基准 `源码根（见 `tools/source-root.conf`）` HEAD `3b5de24`。

---

## 1. 它活在哪

| 项 | 值 | 出处 |
|---|---|---|
| 队列 | **`wq:hp_default`**（本板优先级 **-18**） | [`rc_update.cpp:71`](rc_update.md#^src-src-modules-rc-update-rc-update-cpp-71) |
| 拉起 | `rcS:509` `rc_update start` —— 注释在 `rcS:506-508`：**"start before commander"** | `ROMFS/px4fmu_common/init.d/rcS:506-509` |
| 驱动方式 | **`input_rc` 的订阅回调**（数据来了才跑），不是定时器 | [`rc_update.h:171`](rc_update.md#^src-src-modules-rc-update-rc-update-h-171) `SubscriptionCallbackWorkItem`；注册 [`rc_update.cpp:117`](rc_update.md#^src-src-modules-rc-update-rc-update-cpp-117) |
| 队列同伴有 | `dshot`（[`DShot.cpp:45`](rc_update.md#^src-src-drivers-dshot-DShot-cpp-45)）、`manual_control`（[`ManualControl.cpp:44`](rc_update.md#^src-src-modules-manual-control-ManualControl-cpp-44)） | |

> ⚠️ 注意 `rcS` 里有两件事都叫 "RC"：
> - `rcS:509` `rc_update start`（**模块**，翻译层）
> - `rcS:611` `rc_input start`（**驱动**，出 `input_rc`）
> 而且 **驱动的启动反而更晚**（`:611` 在 `:603 . rc.serial` 之后）。
> 这没问题：`rc_update` 只是订阅，发布者晚点来也能收到。

---

## 2. 订阅 / 发布

| 方向 | 话题 | 声明处 | 备注 |
|---|---|---|---|
| 订 | `input_rc` | [`rc_update.h:171`](rc_update.md#^src-src-modules-rc-update-rc-update-h-171)（callback） | ★ 触发源；消费 [`rc_update.cpp:361`](rc_update.md#^src-src-modules-rc-update-rc-update-cpp-361) |
| 订 | `parameter_update` | [`rc_update.h:173`](rc_update.md#^src-src-modules-rc-update-rc-update-h-173)（1 s） | 参数变了要重算映射 |
| 订 | `rc_parameter_map` | [`rc_update.h:175`](rc_update.md#^src-src-modules-rc-update-rc-update-h-175) | `RC_MAP_PARAM1..6` 的**遥控调参**映射 |
| **发** | `rc_channels` | [`rc_update.h:177`](rc_update.md#^src-src-modules-rc-update-rc-update-h-177)；发布 [`rc_update.cpp:474`](rc_update.md#^src-src-modules-rc-update-rc-update-cpp-474) | **即使信号无效也发**（`:473` 注释："for debug"） |
| **发** | `manual_control_input` | [`rc_update.h:178`](rc_update.md#^src-src-modules-rc-update-rc-update-h-178)（`PublicationMulti`）；发布 [`rc_update.cpp:687`](rc_update.md#^src-src-modules-rc-update-rc-update-cpp-687) | 归一化摇杆 |
| **发** | `manual_control_switches` | [`rc_update.h:179`](rc_update.md#^src-src-modules-rc-update-rc-update-h-179)；发布 [`rc_update.cpp:658`](rc_update.md#^src-src-modules-rc-update-rc-update-cpp-658) | 开关位置（**变化时立即发，否则 ~1 Hz 心跳**，`:646-647`） |

---

## 3. `Run()` 主线（[`rc_update.cpp:361`](rc_update.md#^src-src-modules-rc-update-rc-update-cpp-361)）

```c
input_rc_s input_rc;
if (_input_rc_sub.update(&input_rc)) {                    // :363  ★ 有新 RC 帧
    if (!input_rc.rc_lost) { ... 通道数/输入源变化的告警 ... }   // :366-382

    const uint8_t channel_count_limited = min(input_rc.channel_count, RC_MAX_CHAN_COUNT);  // :384

    // 校验
    if (input_rc.rc_lost || input_rc.rc_failsafe || input_rc.channel_count < 4) { ... }    // :394
    else if ((input_rc.input_source == ..._PPM) && input_rc.channel_count == 16) { ... }    // :398-400
    else {
        // ★ failsafe 阈值判定（RC_MAP_FAILSAFE，逐通道）
        if ((_param_rc_fails_thr.get() < _parameters.min[fs_ch] && input_rc.values[fs_ch] < _param_rc_fails_thr.get())
         || (_param_rc_fails_thr.get() > _parameters.max[fs_ch] && input_rc.values[fs_ch] > _param_rc_fails_thr.get())) { ... }  // :431-432
    }

    _rc.channel_count = input_rc.channel_count;             // :467
    _rc.rssi = input_rc.rssi;                               // :468
    _rc.timestamp = input_rc.timestamp_last_signal;         // :470

    // ★ "数值变了才算有效更新" —— 防止把静止当活跃
    if ((input_rc.timestamp_last_signal > _last_timestamp_signal) && ...) { ... }   // :479-480
        if (rc_updated || hrt_elapsed_time(&_last_manual_control_input_publish) > 300_ms) {
            UpdateManualControlInput(input_rc.timestamp_last_signal);   // :496 → :665
        }
        UpdateManualSwitches(input_rc.timestamp_last_signal);           // :499 → :561
}
```

**两个设计要点：**

| 要点 | 为什么 | 出处 |
|---|---|---|
| **`manual_control_input` 至少 300 ms 发一次** | 下游（`manual_control`）靠"有没有新帧"判遥控是否在线；不发会被判失控 | `:495` |
| **`manual_control_switches` 变化时立即发，否则 1 Hz 心跳** | 开关是**边沿事件**（解锁/切模式），漏一帧就漏一次动作 | `:646-647` |

---

## 4. 映射表（`RC_MAP_*`：通道号 → 功能号）

`UpdateParameters()`（[`rc_update.cpp:195`](rc_update.md#^src-src-modules-rc-update-rc-update-cpp-195)）把参数写进 `_rc.function[]`：

| 参数 | 功能槽 | 出处 |
|---|---|---|
| `RC_MAP_THROTTLE` / `ROLL` / `PITCH` / `YAW` | 四个基本通道 | `:195-198` |
| `RC_MAP_ARM_SW` | `FUNCTION_ARMSWITCH` | `:205` |
| `RC_MAP_KILL_SW` / `TERM_SW` | kill / 终止 | `:203-204` |
| `RC_MAP_RETURN_SW` / `LOITER_SW` / `OFFB_SW` | 模式开关 | `:200-202` |
| `RC_MAP_FLTMODE` / `FLTM_BTN` | 6 段模式 / 按钮 | `:164-167`（`RC_MAP_MODE_SW` 已**弃用**并会 `PX4_WARN`） |
| `RC_MAP_AUX1..6` | 用户自定义 | `:211-213` |
| `RC_MAP_PARAM1..6` | 遥控在线调参（配合 `rc_parameter_map`） | `:98` |

参数声明集中在 [`rc_update.h:212`](rc_update.md#^src-src-modules-rc-update-rc-update-h-212) 的 `DEFINE_PARAMETERS` 块。

### ★ 关键：功能号 → 槽位的转换

```
manual_control_switches.arm_switch
    ← rc_channels_s::FUNCTION_ARMSWITCH 对应的那个通道
    ← _rc.function[FUNCTION_ARMSWITCH] = _param_rc_map_arm_sw.get() - 1     （rc_update.cpp:205）
```
**⇒ 参数是"通道号 = 1 起"，数组下标是"0 起"** —— 所以到处都能看到 `- 1`。
设 `RC_MAP_ARM_SW = 0` = 不映射；设错通道号会静默不生效。

---

## 5. 判据

```sh
listener input_rc                 # ★ 第一道：驱动有没有在发
listener rc_channels              # 第二道：翻译有没有在做
listener manual_control_input     # 第三道：归一化摇杆有没有在发
listener manual_control_switches  # 第四道：开关
param show RC_MAP_ARM_SW RC_MAP_THROTTLE RC_MAP_ROLL RC_MAP_PITCH RC_MAP_YAW
rc_update status
```
**分诊**：
- `input_rc` 没有人发 ⇒ **上游问题**（本板 `RC_PORT_CONFIG = 0`，[`serial_params.c:69`](rc_update.md#^src-build-rm2027-fmu-h743-default-generated-params-serial-params-c-69) ⇒ 根本没有 RC 串口）。
- `input_rc` 有、`manual_control_input` 没有 ⇒ 帧被 `:394` 的 failsafe/通道数校验挡了。
- `manual_control_input` 有、`manual_control_setpoint` 没有 ⇒ 问题在 `manual_control`（[02_code_twin/modules/manual_control](manual_control.md)）。

---

## 6. 未核实

| 事项 | 说明 |
|---|---|
| `UpdateManualSwitches()` 的完整槽位映射（`:561-660`） | 只核到发布点与心跳逻辑，未逐槽展开 |
| `RC_*` 参数在本板的实际值 | 生成参数表未逐个回读；本板 `rc.board_defaults` **没有**写任何 RC 参数 |
| `input_rc.input_source` 的取值枚举 | 只在 `RCInput.cpp:516/558/608/660` 见到赋值，未列全 |

---

## 跳转

| 下一步 | 读哪篇 |
|---|---|
| 上游：`input_rc` 是谁发的 | `src/drivers/rc_input/RCInput.cpp`（本板**不会**启动成功，见 [03_moc/02-sensor-flow](../../03_moc/02-sensor-flow.md) §6.1）；MAVLink 支线见 [02_code_twin/modules/mavlink](mavlink.md) |
| 下游：谁吃 `manual_control_input` | [02_code_twin/modules/manual_control](manual_control.md) |
| 再下游：解锁怎么发生 | [02_code_twin/modules/commander](commander.md) §3 |
| 六条流全景 | [03_moc/02-sensor-flow](../../03_moc/02-sensor-flow.md) §6 |

---

## 标注源码（代码 + 本文档对它的解释）

> **这是「代码孪生」层**：上面是代码原文（带行号），下面是**本文档针对这一段说的话**。
> 行号可点，直接跳到 PX4 源码那一行。
### `build/rm2027_fmu-h743_default/generated_params/serial_params.c`
<a id="src-build-rm2027-fmu-h743-default-generated-params-serial-params-c-69"></a>
**↓ 文档在讲这里：**[`build/rm2027_fmu-h743_default/generated_params/serial_params.c:69`](rc_update.md#^src-build-rm2027-fmu-h743-default-generated-params-serial-params-c-69)

```c
    66 │  * @group Serial
    67 │  * @reboot_required true
    68 │  */
▶   69 │ PARAM_DEFINE_INT32(RC_PORT_CONFIG, 0);
    70 │ 
    71 │ /**
    72 │  * Serial Configuration for FrSky Telemetry
```
> **说明**：input_rc 没有人发 ⇒ 上游问题（本板 RC_PORT_CONFIG = 0，serial_params.c:69 ⇒ 根本没有 RC 串口）。
^src-build-rm2027-fmu-h743-default-generated-params-serial-params-c-69

### `src/drivers/dshot/DShot.cpp`
<a id="src-src-drivers-dshot-DShot-cpp-45"></a>
**↓ 文档在讲这里：**[`src/drivers/dshot/DShot.cpp:45`](rc_update.md#^src-src-drivers-dshot-DShot-cpp-45)

```c
    42 │ px4::atomic_bool DShot::_request_telemetry_init{false};
    43 │ 
    44 │ DShot::DShot() :
▶   45 │ 	OutputModuleInterface(MODULE_NAME, px4::wq_configurations::hp_default)
    46 │ {
    47 │ 	_mixing_output.setAllDisarmedValues(DSHOT_DISARM_VALUE);
    48 │ 	_mixing_output.setAllMinValues(DSHOT_MIN_THROTTLE);
```
> **说明**：驱动方式 | input_rc 的订阅回调（数据来了才跑），不是定时器 | rc_update.h:171 SubscriptionCallbackWorkItem；注册 rc_update.cpp:117 | ┃ 队列同伴有 | dshot（DShot.cpp:45）、manual_control（ManualControl.cpp:44） | |
^src-src-drivers-dshot-DShot-cpp-45

### `src/modules/manual_control/ManualControl.cpp`
<a id="src-src-modules-manual-control-ManualControl-cpp-44"></a>
**↓ 文档在讲这里：**[`src/modules/manual_control/ManualControl.cpp:44`](rc_update.md#^src-src-modules-manual-control-ManualControl-cpp-44)

```c
    41 │ 
    42 │ ManualControl::ManualControl() :
    43 │ 	ModuleParams(nullptr),
▶   44 │ 	ScheduledWorkItem(MODULE_NAME, px4::wq_configurations::hp_default)
    45 │ {
    46 │ 	updateParams();
    47 │ }
```
> **说明**：驱动方式 | input_rc 的订阅回调（数据来了才跑），不是定时器 | rc_update.h:171 SubscriptionCallbackWorkItem；注册 rc_update.cpp:117 | ┃ 队列同伴有 | dshot（DShot.cpp:45）、manual_control（ManualControl.cpp:44） | |
^src-src-modules-manual-control-ManualControl-cpp-44

### `src/modules/rc_update/rc_update.cpp`
<a id="src-src-modules-rc-update-rc-update-cpp-71"></a>
**↓ 文档在讲这里：**[`src/modules/rc_update/rc_update.cpp:71`](rc_update.md#^src-src-modules-rc-update-rc-update-cpp-71)

```c
    68 │ 
    69 │ RCUpdate::RCUpdate() :
    70 │ 	ModuleParams(nullptr),
▶   71 │ 	WorkItem(MODULE_NAME, px4::wq_configurations::hp_default)
    72 │ {
    73 │ 	// initialize parameter handles
    74 │ 	for (unsigned i = 0; i < RC_MAX_CHAN_COUNT; i++) {
```
> **说明**：队列 | wq:hp_default（本板优先级 -18） | rc_update.cpp:71 |
^src-src-modules-rc-update-rc-update-cpp-71

<a id="src-src-modules-rc-update-rc-update-cpp-117"></a>
**↓ 文档在讲这里：**[`src/modules/rc_update/rc_update.cpp:117`](rc_update.md#^src-src-modules-rc-update-rc-update-cpp-117)

```c
   114 │ 
   115 │ bool RCUpdate::init()
   116 │ {
▶  117 │ 	if (!_input_rc_sub.registerCallback()) {
   118 │ 		PX4_ERR("callback registration failed");
   119 │ 		return false;
   120 │ 	}
```
> **说明**：拉起 | rcS:509 rc_update start —— 注释在 rcS:506-508："start before commander" | ROMFS/px4fmu_common/init.d/rcS:506-509 | ┃ 驱动方式 | input_rc 的订阅回调（数据来了才跑），不是定时器 | rc_update.h:171 SubscriptionCallbackWorkItem；注册 rc_update.cpp:117 |
^src-src-modules-rc-update-rc-update-cpp-117

<a id="src-src-modules-rc-update-rc-update-cpp-195"></a>
**↓ 文档在讲这里：**[`src/modules/rc_update/rc_update.cpp:195`](rc_update.md#^src-src-modules-rc-update-rc-update-cpp-195)

```c
   192 │ void RCUpdate::update_rc_functions()
   193 │ {
   194 │ 	/* update RC function mappings */
▶  195 │ 	_rc.function[rc_channels_s::FUNCTION_THROTTLE] = _param_rc_map_throttle.get() - 1;
   196 │ 	_rc.function[rc_channels_s::FUNCTION_ROLL] = _param_rc_map_roll.get() - 1;
   197 │ 	_rc.function[rc_channels_s::FUNCTION_PITCH] = _param_rc_map_pitch.get() - 1;
   198 │ 	_rc.function[rc_channels_s::FUNCTION_YAW] = _param_rc_map_yaw.get() - 1;
```
> **说明**：UpdateParameters()（rc_update.cpp:195）把参数写进 _rc.function[]：
^src-src-modules-rc-update-rc-update-cpp-195

<a id="src-src-modules-rc-update-rc-update-cpp-361"></a>
**↓ 文档在讲这里：**[`src/modules/rc_update/rc_update.cpp:361`](rc_update.md#^src-src-modules-rc-update-rc-update-cpp-361)

```c
   358 │ 	rc_parameter_map_poll();
   359 │ 
   360 │ 	/* read low-level values from FMU or IO RC inputs (PPM, Spektrum, S.Bus) */
▶  361 │ 	input_rc_s input_rc;
   362 │ 
   363 │ 	if (_input_rc_sub.update(&input_rc)) {
   364 │ 
```
> **说明**：订 | input_rc | rc_update.h:171（callback） | ★ 触发源；消费 rc_update.cpp:361 |
> **说明**：3. Run() 主线（rc_update.cpp:361）
^src-src-modules-rc-update-rc-update-cpp-361

<a id="src-src-modules-rc-update-rc-update-cpp-474"></a>
**↓ 文档在讲这里：**[`src/modules/rc_update/rc_update.cpp:474`](rc_update.md#^src-src-modules-rc-update-rc-update-cpp-474)

```c
   471 │ 		_rc.frame_drop_count = input_rc.rc_lost_frame_count;
   472 │ 
   473 │ 		/* publish rc_channels topic even if signal is invalid, for debug */
▶  474 │ 		_rc_channels_pub.publish(_rc);
   475 │ 
   476 │ 		// only publish manual control if the signal is present and regularly updating
   477 │ 		if (input_source_stable && channel_count_stable && !_rc_signal_lost_hysteresis.get_state()) {
```
> **说明**：订 | rc_parameter_map | rc_update.h:175 | RC_MAP_PARAM1..6 的遥控调参映射 | ┃ 发 | rc_channels | rc_update.h:177；发布 rc_update.cpp:474 | 即使信号无效也发（:473 注释："for debug"） |
^src-src-modules-rc-update-rc-update-cpp-474

<a id="src-src-modules-rc-update-rc-update-cpp-658"></a>
**↓ 文档在讲这里：**[`src/modules/rc_update/rc_update.cpp:658`](rc_update.md#^src-src-modules-rc-update-rc-update-cpp-658)

```c
   655 │ 			_manual_switches_last_publish.switch_changes = switch_changes;
   656 │ 			_manual_switches_last_publish.timestamp_sample = _manual_switches_previous.timestamp_sample;
   657 │ 			_manual_switches_last_publish.timestamp = hrt_absolute_time();
▶  658 │ 			_manual_control_switches_pub.publish(_manual_switches_last_publish);
   659 │ 		}
   660 │ 	}
   661 │ 
```
> **说明**：发 | manual_control_input | rc_update.h:178（PublicationMulti）；发布 rc_update.cpp:687 | 归一化摇杆 | ┃ 发 | manual_control_switches | rc_update.h:179；发布 rc_update.cpp:658 | 开关位置（变化时立即发，否则 ~1 Hz 心跳，:646-647） |
^src-src-modules-rc-update-rc-update-cpp-658

<a id="src-src-modules-rc-update-rc-update-cpp-687"></a>
**↓ 文档在讲这里：**[`src/modules/rc_update/rc_update.cpp:687`](rc_update.md#^src-src-modules-rc-update-rc-update-cpp-687)

```c
   684 │ 
   685 │ 	// publish manual_control_input topic
   686 │ 	manual_control_input.timestamp = hrt_absolute_time();
▶  687 │ 	_manual_control_input_pub.publish(manual_control_input);
   688 │ 	_last_manual_control_input_publish = manual_control_input.timestamp;
   689 │ }
   690 │ 
```
> **说明**：发 | rc_channels | rc_update.h:177；发布 rc_update.cpp:474 | 即使信号无效也发（:473 注释："for debug"） | ┃ 发 | manual_control_input | rc_update.h:178（PublicationMulti）；发布 rc_update.cpp:687 | 归一化摇杆 |
^src-src-modules-rc-update-rc-update-cpp-687

### `src/modules/rc_update/rc_update.h`
<a id="src-src-modules-rc-update-rc-update-h-171"></a>
**↓ 文档在讲这里：**[`src/modules/rc_update/rc_update.h:171`](rc_update.md#^src-src-modules-rc-update-rc-update-h-171)

```c
   168 │ 								because these parameters are never read. */
   169 │ 	} _parameter_handles{};
   170 │ 
▶  171 │ 	uORB::SubscriptionCallbackWorkItem _input_rc_sub{this, ORB_ID(input_rc)};
   172 │ 
   173 │ 	uORB::SubscriptionInterval _parameter_update_sub{ORB_ID(parameter_update), 1_s};
   174 │ 
```
> **说明**：拉起 | rcS:509 rc_update start —— 注释在 rcS:506-508："start before commander" | ROMFS/px4fmu_common/init.d/rcS:506-509 | ┃ 驱动方式 | input_rc 的订阅回调（数据来了才跑），不是定时器 | rc_update.h:171 SubscriptionCallbackWorkItem；注册 rc_update.cpp:117 |
> **说明**：订 | input_rc | rc_update.h:171（callback） | ★ 触发源；消费 rc_update.cpp:361 |
^src-src-modules-rc-update-rc-update-h-171

<a id="src-src-modules-rc-update-rc-update-h-173"></a>
**↓ 文档在讲这里：**[`src/modules/rc_update/rc_update.h:173`](rc_update.md#^src-src-modules-rc-update-rc-update-h-173)

```c
   170 │ 
   171 │ 	uORB::SubscriptionCallbackWorkItem _input_rc_sub{this, ORB_ID(input_rc)};
   172 │ 
▶  173 │ 	uORB::SubscriptionInterval _parameter_update_sub{ORB_ID(parameter_update), 1_s};
   174 │ 
   175 │ 	uORB::Subscription _rc_parameter_map_sub{ORB_ID(rc_parameter_map)};
   176 │ 
```
> **说明**：订 | input_rc | rc_update.h:171（callback） | ★ 触发源；消费 rc_update.cpp:361 | ┃ 订 | parameter_update | rc_update.h:173（1 s） | 参数变了要重算映射 |
^src-src-modules-rc-update-rc-update-h-173

<a id="src-src-modules-rc-update-rc-update-h-175"></a>
**↓ 文档在讲这里：**[`src/modules/rc_update/rc_update.h:175`](rc_update.md#^src-src-modules-rc-update-rc-update-h-175)

```c
   172 │ 
   173 │ 	uORB::SubscriptionInterval _parameter_update_sub{ORB_ID(parameter_update), 1_s};
   174 │ 
▶  175 │ 	uORB::Subscription _rc_parameter_map_sub{ORB_ID(rc_parameter_map)};
   176 │ 
   177 │ 	uORB::Publication<rc_channels_s> _rc_channels_pub{ORB_ID(rc_channels)};
   178 │ 	uORB::PublicationMulti<manual_control_setpoint_s> _manual_control_input_pub{ORB_ID(manual_control_input)};
```
> **说明**：订 | parameter_update | rc_update.h:173（1 s） | 参数变了要重算映射 | ┃ 订 | rc_parameter_map | rc_update.h:175 | RC_MAP_PARAM1..6 的遥控调参映射 |
^src-src-modules-rc-update-rc-update-h-175

<a id="src-src-modules-rc-update-rc-update-h-177"></a>
**↓ 文档在讲这里：**[`src/modules/rc_update/rc_update.h:177`](rc_update.md#^src-src-modules-rc-update-rc-update-h-177)

```c
   174 │ 
   175 │ 	uORB::Subscription _rc_parameter_map_sub{ORB_ID(rc_parameter_map)};
   176 │ 
▶  177 │ 	uORB::Publication<rc_channels_s> _rc_channels_pub{ORB_ID(rc_channels)};
   178 │ 	uORB::PublicationMulti<manual_control_setpoint_s> _manual_control_input_pub{ORB_ID(manual_control_input)};
   179 │ 	uORB::Publication<manual_control_switches_s> _manual_control_switches_pub{ORB_ID(manual_control_switches)};
   180 │ 
```
> **说明**：订 | rc_parameter_map | rc_update.h:175 | RC_MAP_PARAM1..6 的遥控调参映射 | ┃ 发 | rc_channels | rc_update.h:177；发布 rc_update.cpp:474 | 即使信号无效也发（:473 注释："for debug"） |
^src-src-modules-rc-update-rc-update-h-177

<a id="src-src-modules-rc-update-rc-update-h-178"></a>
**↓ 文档在讲这里：**[`src/modules/rc_update/rc_update.h:178`](rc_update.md#^src-src-modules-rc-update-rc-update-h-178)

```c
   175 │ 	uORB::Subscription _rc_parameter_map_sub{ORB_ID(rc_parameter_map)};
   176 │ 
   177 │ 	uORB::Publication<rc_channels_s> _rc_channels_pub{ORB_ID(rc_channels)};
▶  178 │ 	uORB::PublicationMulti<manual_control_setpoint_s> _manual_control_input_pub{ORB_ID(manual_control_input)};
   179 │ 	uORB::Publication<manual_control_switches_s> _manual_control_switches_pub{ORB_ID(manual_control_switches)};
   180 │ 
   181 │ 	manual_control_switches_s _manual_switches_previous{};
```
> **说明**：发 | rc_channels | rc_update.h:177；发布 rc_update.cpp:474 | 即使信号无效也发（:473 注释："for debug"） | ┃ 发 | manual_control_input | rc_update.h:178（PublicationMulti）；发布 rc_update.cpp:687 | 归一化摇杆 |
^src-src-modules-rc-update-rc-update-h-178

<a id="src-src-modules-rc-update-rc-update-h-179"></a>
**↓ 文档在讲这里：**[`src/modules/rc_update/rc_update.h:179`](rc_update.md#^src-src-modules-rc-update-rc-update-h-179)

```c
   176 │ 
   177 │ 	uORB::Publication<rc_channels_s> _rc_channels_pub{ORB_ID(rc_channels)};
   178 │ 	uORB::PublicationMulti<manual_control_setpoint_s> _manual_control_input_pub{ORB_ID(manual_control_input)};
▶  179 │ 	uORB::Publication<manual_control_switches_s> _manual_control_switches_pub{ORB_ID(manual_control_switches)};
   180 │ 
   181 │ 	manual_control_switches_s _manual_switches_previous{};
   182 │ 	manual_control_switches_s _manual_switches_last_publish{};
```
> **说明**：发 | manual_control_input | rc_update.h:178（PublicationMulti）；发布 rc_update.cpp:687 | 归一化摇杆 | ┃ 发 | manual_control_switches | rc_update.h:179；发布 rc_update.cpp:658 | 开关位置（变化时立即发，否则 ~1 Hz 心跳，:646-647） |
^src-src-modules-rc-update-rc-update-h-179

<a id="src-src-modules-rc-update-rc-update-h-212"></a>
**↓ 文档在讲这里：**[`src/modules/rc_update/rc_update.h:212`](rc_update.md#^src-src-modules-rc-update-rc-update-h-212)

```c
   209 │ 
   210 │ 	DEFINE_PARAMETERS(
   211 │ 
▶  212 │ 		(ParamInt<px4::params::RC_MAP_ROLL>) _param_rc_map_roll,
   213 │ 		(ParamInt<px4::params::RC_MAP_PITCH>) _param_rc_map_pitch,
   214 │ 		(ParamInt<px4::params::RC_MAP_YAW>) _param_rc_map_yaw,
   215 │ 		(ParamInt<px4::params::RC_MAP_THROTTLE>) _param_rc_map_throttle,
```
> **说明**：参数声明集中在 rc_update.h:212 的 DEFINE_PARAMETERS 块。
^src-src-modules-rc-update-rc-update-h-212
