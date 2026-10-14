# `.msg` → 生成代码 的构建过程（`msg/`）

> **层**：`02_code_twin/`（代码孪生）
>
> | 想看什么 | 去哪 |
> |---|---|
> | `.msg` → 生成两半 的机制 | [`01_extracted/uorb/uorb-mechanism`](../../01_extracted/uorb/uorb-mechanism.md) |

---

## 标注源码### `msg/CMakeLists.txt`
<a id="src-msg-CMakeLists-txt-356"></a>
**↓ 文档在讲这里：**[`msg/CMakeLists.txt:356`](msg-build.md#^src-msg-CMakeLists-txt-356)

```c
   353 │ set(msg_files ${msg_files} PARENT_SCOPE)
   354 │ 
   355 │ # Generate uORB headers
▶  356 │ add_custom_command(
   357 │ 	OUTPUT
   358 │ 		${uorb_headers}
   359 │ 		${msg_out_path}/uORBTopics.hpp
```
> **说明**：消息（message） | 一个结构体定义（.msg 文件） | msg/SensorAccel.msg（device_id/x/y/z/temperature/error_count/clip_counter + ORB_QUEUE_LENGTH = 8） | msg/ 目录 | ┃ 话题（topic） | 这个结构体在内存里的一个实例，用 ORB_ID(sensor_accel) 指代 | sensor_accel（可有多条：sensor_accel_0、_1…） | Tools/msg/px_generate_uorb_topic_files.py 生成 build/.../uORB/topics/sensor_accel.h；生成规则 msg/CMakeLists.txt
> **说明**：msg/CMakeLists.txt:356（uORBTopics.hpp、uORBTopics.cpp）、:458（uorb_msgs 库）。
^src-msg-CMakeLists-txt-356
