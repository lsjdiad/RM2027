# `rc_input` —— 代码孪生

> **层**：`02_code_twin/`（代码孪生）
> | 想看什么 | 去哪 |
> |---|---|
> | 驱动层机制 | [`01_extracted/`](../../01_extracted/) |

---

## 标注源码### `src/drivers/rc_input/RCInput.hpp`
<a id="src-src-drivers-rc-input-RCInput-hpp-147"></a>
**↓ 文档在讲这里：**[`src/drivers/rc_input/RCInput.hpp:147`](rc_input.md#^src-src-drivers-rc-input-RCInput-hpp-147)

```c
   144 │ 	uORB::Subscription	_vehicle_cmd_sub{ORB_ID(vehicle_command)};
   145 │ 	uORB::Subscription	_vehicle_status_sub{ORB_ID(vehicle_status)};
   146 │ 
▶  147 │ 	uORB::PublicationMulti<input_rc_s> _input_rc_pub{ORB_ID(input_rc)};
   148 │ 
   149 │ 	float		_analog_rc_rssi_volt{-1.0f};
   150 │ 	bool		_analog_rc_rssi_stable{false};
```
> **说明**：sensor_selection | sensors/VotedSensorsUpdate | voted_sensors_update.h:155 | ekf2(EKF2.hpp:404)、vehicle_acceleration/angular_velocity(:87/:112) | ┃ input_rc | rc_input（本板未配） | RCInput.hpp:147 | rc_update(rc_update.h:171)、mavlink(RC_CHANNELS.hpp:58) |
^src-src-drivers-rc-input-RCInput-hpp-147
