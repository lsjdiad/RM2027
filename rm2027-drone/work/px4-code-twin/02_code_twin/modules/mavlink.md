# `src/modules/mavlink/` —— 对外通信＋本板唯一可用的遥控入口

> **运行时一句话**：它一边**把机上的 `vehicle_*` 话题按 MAVLink 消息流发出去**，
> 一边**把 QGC 发来的 `MANUAL_CONTROL` / `COMMAND_LONG` 变成 uORB 话题**。
> **⇒ 本板没有 RC 串口（`RC_PORT_CONFIG=0`），所以它是唯一的遥控入口，也是唯一的遥测出口。**
> 行号基准 `源码根（见 `tools/source-root.conf`）` HEAD `3b5de24`。

---

## 1. 它活在哪、怎么起来

| 项 | 值 | 出处 |
|---|---|---|
| 活法 | **每个实例一个自己的线程**（`px4_task_spawn_cmd("mavlink_main", ...)`） | [`mavlink_main.cpp:3288`](mavlink.md#^src-src-modules-mavlink-mavlink-main-cpp-3288) |
| 入口 | `mavlink_main()` | [`mavlink_main.cpp:3811`](mavlink.md#^src-src-modules-mavlink-mavlink-main-cpp-3811) → `Mavlink::start()` `:3252` |
| 实例数由谁定 | 参数 `<tag>_CONFIG`，由生成的 `rc.serial` 决定 | `build/rm2027_fmu-h743_default/etc/init.d/rc.serial` |
| **本板实例** | **`MAV_0_CONFIG = 101`** ⇒ 端口标签索引 101 = **TEL1 = `/dev/ttyS2`** | [`build/rm2027_fmu-h743_default/generated_params/serial_params.c:111`](mavlink.md#^src-build-rm2027-fmu-h743-default-generated-params-serial-params-c-111)；[`boards/rm2027/fmu-h743/default.px4board:3`](mavlink.md#^src-boards-rm2027-fmu-h743-default-px4board-3) |
| **本板模式** | **`MAV_0_MODE = 0`（Normal）** | [`module_params.c:13517`](mavlink.md#^src-build-rm2027-fmu-h743-default-generated-params-module-params-c-13517)；枚举 [`src/modules/mavlink/module.yaml:62`](mavlink.md#^src-src-modules-mavlink-module-yaml-62) |
| 本板串口波特率 | `SER_TEL1_BAUD = 57600` | [`serial_params.c:40`](mavlink.md#^src-build-rm2027-fmu-h743-default-generated-params-serial-params-c-40) |
| **无 USB** | `rcS:614-622` 的 `cdcacm_autostart` 分支本板不会成功（无 USB 外设） ⇒ 不会出现 `/dev/ttyACM0` | `rcS:614-622` |

> ⚠️ 生成目录时间戳 2026-09-28。以上 `serial_params.c` / `module_params.c` 的行号**来自构建产物**，
> 若之后改过 `default.px4board` 的串口声明，需要重新生成才对齐 —— 上板用 `param show MAV_0_CONFIG MAV_0_MODE` 复核一次即可。

---

## 2. 出口：哪些话题变成哪些 MAVLink 消息

流（stream）表在 `mavlink_messages.cpp` 里逐个登记，每个流是一个 `MavlinkStream*` 类（`streams/` 目录），
登记方式 `create_stream_list_item<MavlinkStreamXxx>()`：

| MAVLink 消息 | 流类 | 订阅的 uORB 话题 | 登记处 | 话题声明处 |
|---|---|---|---|---|
| `HIGHRES_IMU` | `MavlinkStreamHighresIMU` | **`vehicle_imu` ×4** + `vehicle_magnetometer` + `vehicle_air_data` + `estimator_sensor_bias` | [`mavlink_messages.cpp:277`](mavlink.md#^src-src-modules-mavlink-mavlink-messages-cpp-277) | `HIGHRES_IMU.hpp:66,71,72` |
| `ATTITUDE` | `MavlinkStreamAttitude` | `vehicle_attitude` | `:301-303` | [`ATTITUDE.hpp:59`](mavlink.md#^src-src-modules-mavlink-streams-ATTITUDE-hpp-59) |
| `ATTITUDE_QUATERNION` | — | `vehicle_attitude` | `:304-306` | [`ATTITUDE_QUATERNION.hpp:60`](mavlink.md#^src-src-modules-mavlink-streams-ATTITUDE-QUATERNION-hpp-60) |
| `RC_CHANNELS` | `MavlinkStreamRCChannels` | **`input_rc`** | `:392-394` | [`RC_CHANNELS.hpp:58`](mavlink.md#^src-src-modules-mavlink-streams-RC-CHANNELS-hpp-58) |
| `SERVO_OUTPUT_RAW` | `MavlinkStreamServoOutputRaw` | `actuator_outputs` | `:376-379` | `SERVO_OUTPUT_RAW.hpp` |
| （其余 ~几十个） | — | `vehicle_local_position`、`vehicle_status`、`battery_status`… | 同上 | 见 [`mavlink_messages.cpp:270`](mavlink.md#^src-src-modules-mavlink-mavlink-messages-cpp-270) 全表 |

**⇒ 出口链的形状**：
```
sensors/ekf2/… ──► vehicle_* 话题 ──► mavlink 某个 MavlinkStream ──► MAVLink 帧 ──► /dev/ttyS2 ──► 数传 ──► QGC
```
**关键性质**：mavlink **只读话题（订阅），不改任何数据**。
所以"QGC 上显示的 IMU 数据不对" 一定是**上游**问题，不是 mavlink 问题。

> ⚠️ 注意 `RC_CHANNELS` 订的是 **`input_rc`**（不是 `manual_control_*`）。
> 本板 `input_rc` 没有发布者 ⇒ **QGC 上 RC Channels 那一页永远是空的**。`[推理，依据 serial_params.c:69 + rc_update.h:171]`

---

## 3. 入口：QGC 发进来变成什么话题

| MAVLink 消息 | 变成的 uORB 话题 | 代码 | 谁消费 |
|---|---|---|---|
| `MANUAL_CONTROL`（虚拟摇杆） | **`manual_control_input`** | [`mavlink_receiver.h:402`](mavlink.md#^src-src-modules-mavlink-mavlink-receiver-h-402) 声明；组装 [`mavlink_receiver.cpp:2364`](mavlink.md#^src-src-modules-mavlink-mavlink-receiver-cpp-2364)（publish `:2401`） | [02_code_twin/modules/manual_control](manual_control.md)（[`ManualControl.hpp:108`](mavlink.md#^src-src-modules-manual-control-ManualControl-hpp-108)） |
| `COMMAND_LONG` / `COMMAND_INT`（ARM/DISARM/起飞…） | `vehicle_command` | `mavlink_receiver.h` 内的 `_vehicle_command_pub` | [02_code_twin/modules/commander](commander.md)（[`Commander.hpp:306`](mavlink.md#^src-src-modules-commander-Commander-hpp-306)） |
| `PARAM_SET` | 参数后端（不走 uORB 话题） | `mavlink_receiver.cpp` 的参数 handler | 参数系统 |
| `SET_MODE` / `SET_POSITION_TARGET_*` | `vehicle_command` / `offboard_control_mode` / `trajectory_setpoint` | [`mavlink_receiver.h:358`](mavlink.md#^src-src-modules-mavlink-mavlink-receiver-h-358) 等 | `commander` / `mc_pos_control` |
| `PING`、`TIMESYNC`、`V2_EXTENSION`… | 各类（`airspeed`、`battery_status`、`log_message`…） | [`mavlink_receiver.h:341`](mavlink.md#^src-src-modules-mavlink-mavlink-receiver-h-341) | 见该文件 |

**★ 本板的遥控链路因此是**（`[推理，证据齐]`，见 [03_moc/02-sensor-flow](../../03_moc/02-sensor-flow.md) §6.1）：
```
QGC 虚拟摇杆 → MAVLink MANUAL_CONTROL → mavlink_receiver → manual_control_input
   → manual_control 模块 → manual_control_setpoint
   → commander（解锁）/ mc_pos_control / mc_att_control / FMM
```
**注意 `MANUAL_CONTROL` 走的是 `manual_control_input`，和硬件遥控汇入的是同一个话题**
（[`rc_update.h:178`](rc_update.md#^src-src-modules-rc-update-rc-update-h-178) 也是 `manual_control_input`）—— 这正是 `manual_control` 模块要做仲裁的原因。

---

## 4. 判据

```sh
mavlink status                 # 每个实例：设备、模式、速率、收发字节
listener manual_control_input  # ★ QGC 推摇杆时应该动，data_source 是 MAVLINK_0
listener vehicle_command       # QGC 点 ARM 时应该出现
param show MAV_0_CONFIG MAV_0_MODE MAV_0_RATE SER_TEL1_BAUD
```
**分诊**：
- `mavlink status` 里 0 个实例 ⇒ `MAV_0_CONFIG` 没生效 / `rc.serial` 没跑到（`rcS:603`）。
- 链路通但 QGC 界面无数据 ⇒ 是**流速率**（`MAV_0_MODE`/`MAV_0_RATE`）或上游话题没发布。
- QGC 摇杆无反应但能收遥测 ⇒ 检查 `manual_control_input` 有没有；没有则 `mavlink_receiver` 的 `MANUAL_CONTROL` 处理没触发（需要 QGC 处于 Joystick 模式）。

---

## 5. 未核实

| 事项 | 说明 |
|---|---|
| `MAV_0_MODE = Normal` 下各流的**实际频率** | 流表里每个 `MavlinkStream` 有 `get_default_interval`-类的机制，本文**未逐个回读**；只核到"模式决定 stream 集合、速率由 `MAV_0_RATE` 封顶"（[`module.yaml:56`](mavlink.md#^src-src-modules-mavlink-module-yaml-56)） |
| `mavlink_receiver` 里 `MANUAL_CONTROL` 的"manual_control_input"实例号 | 只核到 `PublicationMulti`（[`mavlink_receiver.h:402`](mavlink.md#^src-src-modules-mavlink-mavlink-receiver-h-402)），实例分配未核 |
| 无 USB 时 `rcS:614-622` 的实际分支 | 只按"无 USB 外设"推断不会走通；未上板看日志 |
| `MAV_x_FORWARD` / `MAV_x_RADIO_CTL` 在本板的值 | 未回读 |

---

## 跳转

| 下一步 | 读哪篇 |
|---|---|
| 下游：`manual_control_input` 被谁仲裁 | [02_code_twin/modules/manual_control](manual_control.md) |
| 硬件遥控那条支线 | [02_code_twin/modules/rc_update](rc_update.md) |
| `vehicle_command` 被谁执行 | [02_code_twin/modules/commander](commander.md) |
| 出口数据的源头 | [02_code_twin/modules/sensors](sensors.md)、[02_code_twin/modules/ekf2](ekf2.md) |
| 六条流全景 | [03_moc/02-sensor-flow](../../03_moc/02-sensor-flow.md) §6 |

---

## 标注源码（代码 + 本文档对它的解释）

> **这是「代码孪生」层**：上面是代码原文（带行号），下面是**本文档针对这一段说的话**。
> 行号可点，直接跳到 PX4 源码那一行。
### `boards/rm2027/fmu-h743/default.px4board`
<a id="src-boards-rm2027-fmu-h743-default-px4board-3"></a>
**↓ 文档在讲这里：**[`boards/rm2027/fmu-h743/default.px4board:3`](mavlink.md#^src-boards-rm2027-fmu-h743-default-px4board-3)

```c
     1 │ CONFIG_BOARD_TOOLCHAIN="arm-none-eabi"
     2 │ CONFIG_BOARD_ARCHITECTURE="cortex-m7"
▶    3 │ CONFIG_BOARD_SERIAL_TEL1="/dev/ttyS2"   # USART3（本板唯一空闲串口）
     4 │ CONFIG_DRIVERS_ADC_BOARD_ADC=y
     5 │ CONFIG_DRIVERS_BAROMETER_GOERTEK_SPA06=y
     6 │ CONFIG_DRIVERS_DSHOT=y
```
> **说明**：实例数由谁定 | 参数 <tag>_CONFIG，由生成的 rc.serial 决定 | build/rm2027_fmu-h743_default/etc/init.d/rc.serial | ┃ 本板实例 | MAV_0_CONFIG = 101 ⇒ 端口标签索引 101 = TEL1 = /dev/ttyS2 | build/rm2027_fmu-h743_default/generated_params/serial_params.c:111；boards/rm2027/fmu-h743/default.px4board:3 |
^src-boards-rm2027-fmu-h743-default-px4board-3

### `build/rm2027_fmu-h743_default/generated_params/module_params.c`
<a id="src-build-rm2027-fmu-h743-default-generated-params-module-params-c-13517"></a>
**↓ 文档在讲这里：**[`build/rm2027_fmu-h743_default/generated_params/module_params.c:13517`](mavlink.md#^src-build-rm2027-fmu-h743-default-generated-params-module-params-c-13517)

```c
 13514 │  * @value 13 Low Bandwidth
 13515 │  * @reboot_required True
 13516 │  */
▶13517 │ PARAM_DEFINE_INT32(MAV_0_MODE, 0);
 13518 │ 
 13519 │ /**
 13520 │  * MAVLink Mode for instance 1
```
> **说明**：本板实例 | MAV_0_CONFIG = 101 ⇒ 端口标签索引 101 = TEL1 = /dev/ttyS2 | build/rm2027_fmu-h743_default/generated_params/serial_params.c:111；boards/rm2027/fmu-h743/default.px4board:3 | ┃ 本板模式 | MAV_0_MODE = 0（Normal） | module_params.c:13517；枚举 src/modules/mavlink/module.yaml:62 |
^src-build-rm2027-fmu-h743-default-generated-params-module-params-c-13517

### `build/rm2027_fmu-h743_default/generated_params/serial_params.c`
<a id="src-build-rm2027-fmu-h743-default-generated-params-serial-params-c-40"></a>
**↓ 文档在讲这里：**[`build/rm2027_fmu-h743_default/generated_params/serial_params.c:40`](mavlink.md#^src-build-rm2027-fmu-h743-default-generated-params-serial-params-c-40)

```c
    37 │  * @group Serial
    38 │  * @reboot_required true
    39 │  */
▶   40 │ PARAM_DEFINE_INT32(SER_TEL1_BAUD, 57600);
    41 │ 
    42 │ 
    43 │ /**
```
> **说明**：本板模式 | MAV_0_MODE = 0（Normal） | module_params.c:13517；枚举 src/modules/mavlink/module.yaml:62 | ┃ 本板串口波特率 | SER_TEL1_BAUD = 57600 | serial_params.c:40 |
^src-build-rm2027-fmu-h743-default-generated-params-serial-params-c-40

<a id="src-build-rm2027-fmu-h743-default-generated-params-serial-params-c-111"></a>
**↓ 文档在讲这里：**[`build/rm2027_fmu-h743_default/generated_params/serial_params.c:111`](mavlink.md#^src-build-rm2027-fmu-h743-default-generated-params-serial-params-c-111)

```c
   108 │  * @group MAVLink
   109 │  * @reboot_required true
   110 │  */
▶  111 │ PARAM_DEFINE_INT32(MAV_0_CONFIG, 101);
   112 │ 
   113 │ /**
   114 │  * Serial Configuration for MAVLink (instance 1)
```
> **说明**：实例数由谁定 | 参数 <tag>_CONFIG，由生成的 rc.serial 决定 | build/rm2027_fmu-h743_default/etc/init.d/rc.serial | ┃ 本板实例 | MAV_0_CONFIG = 101 ⇒ 端口标签索引 101 = TEL1 = /dev/ttyS2 | build/rm2027_fmu-h743_default/generated_params/serial_params.c:111；boards/rm2027/fmu-h743/default.px4board:3 |
^src-build-rm2027-fmu-h743-default-generated-params-serial-params-c-111

### `src/modules/commander/Commander.hpp`
<a id="src-src-modules-commander-Commander-hpp-306"></a>
**↓ 文档在讲这里：**[`src/modules/commander/Commander.hpp:306`](mavlink.md#^src-src-modules-commander-Commander-hpp-306)

```c
   303 │ 	uORB::Subscription					_iridiumsbd_status_sub{ORB_ID(iridiumsbd_status)};
   304 │ 	uORB::Subscription					_manual_control_setpoint_sub{ORB_ID(manual_control_setpoint)};
   305 │ 	uORB::Subscription					_system_power_sub{ORB_ID(system_power)};
▶  306 │ 	uORB::Subscription					_vehicle_command_sub{ORB_ID(vehicle_command)};
   307 │ 	uORB::Subscription					_vehicle_command_mode_executor_sub{ORB_ID(vehicle_command_mode_executor)};
   308 │ 	uORB::Subscription					_vehicle_land_detected_sub{ORB_ID(vehicle_land_detected)};
   309 │ 	uORB::Subscription					_vtol_vehicle_status_sub{ORB_ID(vtol_vehicle_status)};
```
> **说明**：MANUAL_CONTROL（虚拟摇杆） | manual_control_input | mavlink_receiver.h:402 声明；组装 mavlink_receiver.cpp:2364（publish :2401） | 02_code_twin/modules/manual_control（ManualControl.hpp:108） | ┃ COMMAND_LONG / COMMAND_INT（ARM/DISARM/起飞…） | vehicle_command | mavlink_receiver.h 内的 _vehicle_command_pub | 02_code_twin/modules/commander（Commander.hpp:306） |
^src-src-modules-commander-Commander-hpp-306

### `src/modules/manual_control/ManualControl.hpp`
<a id="src-src-modules-manual-control-ManualControl-hpp-108"></a>
**↓ 文档在讲这里：**[`src/modules/manual_control/ManualControl.hpp:108`](mavlink.md#^src-src-modules-manual-control-ManualControl-hpp-108)

```c
   105 │ 	void send_video_command();
   106 │ 
   107 │ 	uORB::SubscriptionCallbackWorkItem _manual_control_input_subs[MAX_MANUAL_INPUT_COUNT] {
▶  108 │ 		{this, ORB_ID(manual_control_input), 0},
   109 │ 		{this, ORB_ID(manual_control_input), 1},
   110 │ 		{this, ORB_ID(manual_control_input), 2},
   111 │ 	};
```
> **说明**：MANUAL_CONTROL（虚拟摇杆） | manual_control_input | mavlink_receiver.h:402 声明；组装 mavlink_receiver.cpp:2364（publish :2401） | 02_code_twin/modules/manual_control（ManualControl.hpp:108） |
^src-src-modules-manual-control-ManualControl-hpp-108

### `src/modules/mavlink/mavlink_main.cpp`
<a id="src-src-modules-mavlink-mavlink-main-cpp-3288"></a>
**↓ 文档在讲这里：**[`src/modules/mavlink/mavlink_main.cpp:3288`](mavlink.md#^src-src-modules-mavlink-mavlink-main-cpp-3288)

```c
  3285 │ 	// between the starting task and the spawned
  3286 │ 	// task - start_helper() only returns
  3287 │ 	// when the started task exits.
▶ 3288 │ 	px4_task_spawn_cmd("mavlink_main",
  3289 │ 			   SCHED_DEFAULT,
  3290 │ 			   SCHED_PRIORITY_DEFAULT,
  3291 │ 			   PX4_STACK_ADJUSTED(2896) + MAVLINK_NET_ADDED_STACK,
```
> **说明**：活法 | 每个实例一个自己的线程（px4_task_spawn_cmd("mavlink_main", ...)） | mavlink_main.cpp:3288 |
^src-src-modules-mavlink-mavlink-main-cpp-3288

<a id="src-src-modules-mavlink-mavlink-main-cpp-3811"></a>
**↓ 文档在讲这里：**[`src/modules/mavlink/mavlink_main.cpp:3811`](mavlink.md#^src-src-modules-mavlink-mavlink-main-cpp-3811)

```c
  3808 │ 
  3809 │ }
  3810 │ 
▶ 3811 │ extern "C" __EXPORT int mavlink_main(int argc, char *argv[])
  3812 │ {
  3813 │ 	if (argc < 2) {
  3814 │ 		usage();
```
> **说明**：活法 | 每个实例一个自己的线程（px4_task_spawn_cmd("mavlink_main", ...)） | mavlink_main.cpp:3288 | ┃ 入口 | mavlink_main() | mavlink_main.cpp:3811 → Mavlink::start() :3252 |
^src-src-modules-mavlink-mavlink-main-cpp-3811

### `src/modules/mavlink/mavlink_messages.cpp`
<a id="src-src-modules-mavlink-mavlink-messages-cpp-270"></a>
**↓ 文档在讲这里：**[`src/modules/mavlink/mavlink_messages.cpp:270`](mavlink.md#^src-src-modules-mavlink-mavlink-messages-cpp-270)

```c
   267 │ #if defined(COMMAND_LONG_HPP)
   268 │ 	create_stream_list_item<MavlinkStreamCommandLong>(),
   269 │ #endif // COMMAND_LONG_HPP
▶  270 │ #if defined(SYS_STATUS_HPP)
   271 │ 	create_stream_list_item<MavlinkStreamSysStatus>(),
   272 │ #endif // SYS_STATUS_HPP
   273 │ 	create_stream_list_item<MavlinkStreamBatteryStatus>(),
```
> **说明**：SERVO_OUTPUT_RAW | MavlinkStreamServoOutputRaw | actuator_outputs | :376-379 | SERVO_OUTPUT_RAW.hpp | ┃ （其余 ~几十个） | — | vehicle_local_position、vehicle_status、battery_status… | 同上 | 见 mavlink_messages.cpp:270 全表 |
^src-src-modules-mavlink-mavlink-messages-cpp-270

<a id="src-src-modules-mavlink-mavlink-messages-cpp-277"></a>
**↓ 文档在讲这里：**[`src/modules/mavlink/mavlink_messages.cpp:277`](mavlink.md#^src-src-modules-mavlink-mavlink-messages-cpp-277)

```c
   274 │ #if defined(BATTERY_INFO_HPP)
   275 │ 	create_stream_list_item<MavlinkStreamBatteryInfo>(),
   276 │ #endif // BATTERY_INFO_HPP
▶  277 │ #if defined(HIGHRES_IMU_HPP)
   278 │ 	create_stream_list_item<MavlinkStreamHighresIMU>(),
   279 │ #endif // HIGHRES_IMU_HPP
   280 │ #if defined(SCALED_IMU_HPP)
```
> **说明**：HIGHRES_IMU | MavlinkStreamHighresIMU | vehicle_imu ×4 + vehicle_magnetometer + vehicle_air_data + estimator_sensor_bias | mavlink_messages.cpp:277 | HIGHRES_IMU.hpp:66,71,72 |
^src-src-modules-mavlink-mavlink-messages-cpp-277

### `src/modules/mavlink/mavlink_receiver.cpp`
<a id="src-src-modules-mavlink-mavlink-receiver-cpp-2364"></a>
**↓ 文档在讲这里：**[`src/modules/mavlink/mavlink_receiver.cpp:2364`](mavlink.md#^src-src-modules-mavlink-mavlink-receiver-cpp-2364)

```c
  2361 │ 		return;
  2362 │ 	}
  2363 │ 
▶ 2364 │ 	manual_control_setpoint_s manual_control_setpoint{};
  2365 │ 
  2366 │ 	if (math::isInRange((int)mavlink_manual_control.x, -1000, 1000)) { manual_control_setpoint.pitch = mavlink_manual_control.x / 1000.f; }
  2367 │ 
```
> **说明**：MANUAL_CONTROL（虚拟摇杆） | manual_control_input | mavlink_receiver.h:402 声明；组装 mavlink_receiver.cpp:2364（publish :2401） | 02_code_twin/modules/manual_control（ManualControl.hpp:108） |
^src-src-modules-mavlink-mavlink-receiver-cpp-2364

### `src/modules/mavlink/mavlink_receiver.h`
<a id="src-src-modules-mavlink-mavlink-receiver-h-341"></a>
**↓ 文档在讲这里：**[`src/modules/mavlink/mavlink_receiver.h:341`](mavlink.md#^src-src-modules-mavlink-mavlink-receiver-h-341)

```c
   338 │ 	uint16_t _mavlink_status_last_packet_rx_drop_count{0};
   339 │ 
   340 │ 	// ORB publications
▶  341 │ 	uORB::Publication<airspeed_s>				_airspeed_pub{ORB_ID(airspeed)};
   342 │ 	uORB::Publication<battery_status_s>			_battery_pub{ORB_ID(battery_status)};
   343 │ 	uORB::Publication<camera_status_s>			_camera_status_pub{ORB_ID(camera_status)};
   344 │ 	uORB::Publication<cellular_status_s>			_cellular_status_pub{ORB_ID(cellular_status)};
```
> **说明**：SET_MODE / SET_POSITION_TARGET_* | vehicle_command / offboard_control_mode / trajectory_setpoint | mavlink_receiver.h:358 等 | commander / mc_pos_control | ┃ PING、TIMESYNC、V2_EXTENSION… | 各类（airspeed、battery_status、log_message…） | mavlink_receiver.h:341 | 见该文件 |
^src-src-modules-mavlink-mavlink-receiver-h-341

<a id="src-src-modules-mavlink-mavlink-receiver-h-358"></a>
**↓ 文档在讲这里：**[`src/modules/mavlink/mavlink_receiver.h:358`](mavlink.md#^src-src-modules-mavlink-mavlink-receiver-h-358)

```c
   355 │ 	uORB::Publication<mavlink_tunnel_s>			_esc_serial_passthru_pub{ORB_ID(esc_serial_passthru)};
   356 │ 	uORB::Publication<mavlink_tunnel_s>			_io_serial_passthru_pub{ORB_ID(io_serial_passthru)};
   357 │ 	uORB::Publication<obstacle_distance_s>			_obstacle_distance_pub{ORB_ID(obstacle_distance)};
▶  358 │ 	uORB::Publication<offboard_control_mode_s>		_offboard_control_mode_pub{ORB_ID(offboard_control_mode)};
   359 │ 	uORB::Publication<onboard_computer_status_s>		_onboard_computer_status_pub{ORB_ID(onboard_computer_status)};
   360 │ 	uORB::Publication<velocity_limits_s>			_velocity_limits_pub{ORB_ID(velocity_limits)};
   361 │ 	uORB::Publication<open_drone_id_basic_id_s>		_open_drone_id_basic_id_pub{ORB_ID(open_drone_id_basic_id)};
```
> **说明**：PARAM_SET | 参数后端（不走 uORB 话题） | mavlink_receiver.cpp 的参数 handler | 参数系统 | ┃ SET_MODE / SET_POSITION_TARGET_* | vehicle_command / offboard_control_mode / trajectory_setpoint | mavlink_receiver.h:358 等 | commander / mc_pos_control |
^src-src-modules-mavlink-mavlink-receiver-h-358

<a id="src-src-modules-mavlink-mavlink-receiver-h-402"></a>
**↓ 文档在讲这里：**[`src/modules/mavlink/mavlink_receiver.h:402`](mavlink.md#^src-src-modules-mavlink-mavlink-receiver-h-402)

```c
   399 │ 	uORB::PublicationMulti<aux_global_position_s>		_aux_global_position_pub{ORB_ID(aux_global_position)};
   400 │ 	uORB::PublicationMulti<rtcm_data_s>		_rtcm_corrections_pub{ORB_ID(rtcm_corrections)};
   401 │ 	uORB::PublicationMulti<input_rc_s>			_rc_pub{ORB_ID(input_rc)};
▶  402 │ 	uORB::PublicationMulti<manual_control_setpoint_s>	_manual_control_input_pub{ORB_ID(manual_control_input)};
   403 │ 	uORB::PublicationMulti<ping_s>				_ping_pub{ORB_ID(ping)};
   404 │ 	uORB::PublicationMulti<radio_status_s>			_radio_status_pub{ORB_ID(radio_status)};
   405 │ 	uORB::PublicationMulti<sensor_baro_s>			_sensor_baro_pub{ORB_ID(sensor_baro)};
```
> **说明**：MANUAL_CONTROL（虚拟摇杆） | manual_control_input | mavlink_receiver.h:402 声明；组装 mavlink_receiver.cpp:2364（publish :2401） | 02_code_twin/modules/manual_control（ManualControl.hpp:108） |
> **说明**：MAV_0_MODE = Normal 下各流的实际频率 | 流表里每个 MavlinkStream 有 get_default_interval-类的机制，本文未逐个回读；只核到"模式决定 stream 集合、速率由 MAV_0_RATE 封顶"（module.yaml:56） | ┃ mavlink_receiver 里 MANUAL_CONTROL 的"manual_control_input"实例号 | 只核到 PublicationMulti（mavlink_receiver.h:402），实例分配未核 |
^src-src-modules-mavlink-mavlink-receiver-h-402

### `src/modules/mavlink/module.yaml`
<a id="src-src-modules-mavlink-module-yaml-56"></a>
**↓ 文档在讲这里：**[`src/modules/mavlink/module.yaml:56`](mavlink.md#^src-src-modules-mavlink-module-yaml-56)

```c
    53 │       definitions:
    54 │         MAV_${i}_MODE:
    55 │             description:
▶   56 │                 short: MAVLink Mode for instance ${i}
    57 │                 long: |
    58 │                     The MAVLink Mode defines the set of streamed messages (for example the
    59 │                     vehicle's attitude) and their sending rates.
```
> **说明**：MAV_0_MODE = Normal 下各流的实际频率 | 流表里每个 MavlinkStream 有 get_default_interval-类的机制，本文未逐个回读；只核到"模式决定 stream 集合、速率由 MAV_0_RATE 封顶"（module.yaml:56） |
^src-src-modules-mavlink-module-yaml-56

<a id="src-src-modules-mavlink-module-yaml-62"></a>
**↓ 文档在讲这里：**[`src/modules/mavlink/module.yaml:62`](mavlink.md#^src-src-modules-mavlink-module-yaml-62)

```c
    59 │                     vehicle's attitude) and their sending rates.
    60 │ 
    61 │             type: enum
▶   62 │             values:
    63 │                 0: Normal
    64 │                 1: Custom
    65 │                 2: Onboard
```
> **说明**：本板实例 | MAV_0_CONFIG = 101 ⇒ 端口标签索引 101 = TEL1 = /dev/ttyS2 | build/rm2027_fmu-h743_default/generated_params/serial_params.c:111；boards/rm2027/fmu-h743/default.px4board:3 | ┃ 本板模式 | MAV_0_MODE = 0（Normal） | module_params.c:13517；枚举 src/modules/mavlink/module.yaml:62 |
^src-src-modules-mavlink-module-yaml-62

### `src/modules/mavlink/streams/ATTITUDE.hpp`
<a id="src-src-modules-mavlink-streams-ATTITUDE-hpp-59"></a>
**↓ 文档在讲这里：**[`src/modules/mavlink/streams/ATTITUDE.hpp:59`](mavlink.md#^src-src-modules-mavlink-streams-ATTITUDE-hpp-59)

```c
    56 │ private:
    57 │ 	explicit MavlinkStreamAttitude(Mavlink *mavlink) : MavlinkStream(mavlink) {}
    58 │ 
▶   59 │ 	uORB::Subscription _att_sub{ORB_ID(vehicle_attitude)};
    60 │ 	uORB::Subscription _angular_velocity_sub{ORB_ID(vehicle_angular_velocity)};
    61 │ 
    62 │ 	bool send() override
```
> **说明**：HIGHRES_IMU | MavlinkStreamHighresIMU | vehicle_imu ×4 + vehicle_magnetometer + vehicle_air_data + estimator_sensor_bias | mavlink_messages.cpp:277 | HIGHRES_IMU.hpp:66,71,72 | ┃ ATTITUDE | MavlinkStreamAttitude | vehicle_attitude | :301-303 | ATTITUDE.hpp:59 |
^src-src-modules-mavlink-streams-ATTITUDE-hpp-59

### `src/modules/mavlink/streams/ATTITUDE_QUATERNION.hpp`
<a id="src-src-modules-mavlink-streams-ATTITUDE-QUATERNION-hpp-60"></a>
**↓ 文档在讲这里：**[`src/modules/mavlink/streams/ATTITUDE_QUATERNION.hpp:60`](mavlink.md#^src-src-modules-mavlink-streams-ATTITUDE-QUATERNION-hpp-60)

```c
    57 │ private:
    58 │ 	explicit MavlinkStreamAttitudeQuaternion(Mavlink *mavlink) : MavlinkStream(mavlink) {}
    59 │ 
▶   60 │ 	uORB::Subscription _att_sub{ORB_ID(vehicle_attitude)};
    61 │ 	uORB::Subscription _angular_velocity_sub{ORB_ID(vehicle_angular_velocity)};
    62 │ 	uORB::Subscription _status_sub{ORB_ID(vehicle_status)};
    63 │ 
```
> **说明**：ATTITUDE | MavlinkStreamAttitude | vehicle_attitude | :301-303 | ATTITUDE.hpp:59 | ┃ ATTITUDE_QUATERNION | — | vehicle_attitude | :304-306 | ATTITUDE_QUATERNION.hpp:60 |
^src-src-modules-mavlink-streams-ATTITUDE-QUATERNION-hpp-60

### `src/modules/mavlink/streams/RC_CHANNELS.hpp`
<a id="src-src-modules-mavlink-streams-RC-CHANNELS-hpp-58"></a>
**↓ 文档在讲这里：**[`src/modules/mavlink/streams/RC_CHANNELS.hpp:58`](mavlink.md#^src-src-modules-mavlink-streams-RC-CHANNELS-hpp-58)

```c
    55 │ private:
    56 │ 	explicit MavlinkStreamRCChannels(Mavlink *mavlink) : MavlinkStream(mavlink) {}
    57 │ 
▶   58 │ 	uORB::Subscription _input_rc_sub{ORB_ID(input_rc)};
    59 │ 
    60 │ 	bool send() override
    61 │ 	{
```
> **说明**：ATTITUDE_QUATERNION | — | vehicle_attitude | :304-306 | ATTITUDE_QUATERNION.hpp:60 | ┃ RC_CHANNELS | MavlinkStreamRCChannels | input_rc | :392-394 | RC_CHANNELS.hpp:58 |
^src-src-modules-mavlink-streams-RC-CHANNELS-hpp-58

### `src/modules/rc_update/rc_update.h`
<a id="src-src-modules-rc-update-rc-update-h-178"></a>
**↓ 文档在讲这里：**[`src/modules/rc_update/rc_update.h:178`](mavlink.md#^src-src-modules-rc-update-rc-update-h-178)

```c
   175 │ 	uORB::Subscription _rc_parameter_map_sub{ORB_ID(rc_parameter_map)};
   176 │ 
   177 │ 	uORB::Publication<rc_channels_s> _rc_channels_pub{ORB_ID(rc_channels)};
▶  178 │ 	uORB::PublicationMulti<manual_control_setpoint_s> _manual_control_input_pub{ORB_ID(manual_control_input)};
   179 │ 	uORB::Publication<manual_control_switches_s> _manual_control_switches_pub{ORB_ID(manual_control_switches)};
   180 │ 
   181 │ 	manual_control_switches_s _manual_switches_previous{};
```
> **说明**：注意 MANUAL_CONTROL 走的是 manual_control_input，和硬件遥控汇入的是同一个话题 ┃ （rc_update.h:178 也是 manual_control_input）—— 这正是 manual_control 模块要做仲裁的原因。
^src-src-modules-rc-update-rc-update-h-178
