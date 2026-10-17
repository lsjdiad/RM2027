# uORB 内部实现（`platforms/common/uORB/`）

> **层**：`02_code_twin/`（代码孪生）
> **范围**：`uORB.h` · `Publication.cpp` · `Subscription.hpp` · `uORBDeviceNode.hpp` · `uORBDeviceMaster.cpp`
>
> | 想看什么 | 去哪 |
> |---|---|
> | uORB 机制与三个宏（通则） | [`01_extracted/uorb/uorb-mechanism`](../../01_extracted/uorb/uorb-mechanism.md) |
> | 传感器数据怎么流 | [`03_moc/02-sensor-flow`](../../03_moc/02-sensor-flow.md) |

---

## 标注源码### `platforms/common/uORB/Publication.cpp`
<a id="src-platforms-common-uORB-Publication-cpp-58"></a>
**↓ 文档在讲这里：**[`platforms/common/uORB/Publication.cpp:58`](uorb-internals.md#^src-platforms-common-uORB-Publication-cpp-58)

```c
    55 │ 	}
    56 │ }
    57 │ 
▶   58 │ bool PublicationBase::advertise()
    59 │ {
    60 │ 	if (!advertised()) {
    61 │ 		_handle = orb_advertise(get_topic(), nullptr);
```
> **说明**：第一次发布时自动 advertise | PublicationBase::advertise() → orb_advertise() | Publication.cpp:58 |
^src-platforms-common-uORB-Publication-cpp-58

### `platforms/common/uORB/Publication.cpp`
<a id="src-platforms-common-uORB-Publication-cpp-76"></a>
**↓ 文档在讲这里：**[`platforms/common/uORB/Publication.cpp:76`](uorb-internals.md#^src-platforms-common-uORB-Publication-cpp-76)

```c
    73 │ 	return (Manager::orb_publish(get_topic(), _handle, data) == PX4_OK);
    74 │ }
    75 │ 
▶   76 │ bool PublicationMultiBase::advertise()
    77 │ {
    78 │ 	if (!advertised()) {
    79 │ 		int instance = 0;
```
> **说明**：第一次发布时自动 advertise | PublicationBase::advertise() → orb_advertise() | Publication.cpp:58 | ┃ 多实例自动分配实例号（从 0 起找第一个空） | PublicationMultiBase::advertise()：int instance = 0; orb_advertise_multi(..., &instance) | Publication.cpp:76 |
^src-platforms-common-uORB-Publication-cpp-76

### `platforms/common/uORB/Subscription.hpp`
<a id="src-platforms-common-uORB-Subscription-hpp-99"></a>
**↓ 文档在讲这里：**[`platforms/common/uORB/Subscription.hpp:99`](uorb-internals.md#^src-platforms-common-uORB-Subscription-hpp-99)

```c
    96 │ 	/**
    97 │ 	 * Check if there is a new update.
    98 │ 	 */
▶   99 │ 	bool updated();
   100 │ 
   101 │ 	/**
   102 │ 	 * Update the struct
```
> **说明**：最大实例数 | ORB_MULTI_MAX_INSTANCES = 4（NuttX 上；POSIX 是 10） | platforms/common/uORB/uORB.h:66 | ┃ 订阅者"有没有新数据" | Subscription::updated() | Subscription.hpp:99 |
^src-platforms-common-uORB-Subscription-hpp-99

### `platforms/common/uORB/uORB.h`
<a id="src-platforms-common-uORB-uORB-h-66"></a>
**↓ 文档在讲这里：**[`platforms/common/uORB/uORB.h:66`](uorb-internals.md#^src-platforms-common-uORB-uORB-h-66)

```c
    63 │  * Maximum number of multi topic instances. This must be <= 10 (because it's the last char of the node path)
    64 │  */
    65 │ #if defined(CONSTRAINED_MEMORY)
▶   66 │ # define ORB_MULTI_MAX_INSTANCES 4
    67 │ #else
    68 │ # define ORB_MULTI_MAX_INSTANCES 10
    69 │ #endif
```
> **说明**：分配算法本体（按 /obj/<topic>_N 路径试） | uORB::DeviceMaster::advertise() | uORBDeviceMaster.cpp:88 | ┃ 最大实例数 | ORB_MULTI_MAX_INSTANCES = 4（NuttX 上；POSIX 是 10） | platforms/common/uORB/uORB.h:66 |
^src-platforms-common-uORB-uORB-h-66

### `platforms/common/uORB/uORBDeviceMaster.cpp`
<a id="src-platforms-common-uORB-uORBDeviceMaster-cpp-88"></a>
**↓ 文档在讲这里：**[`platforms/common/uORB/uORBDeviceMaster.cpp:88`](uorb-internals.md#^src-platforms-common-uORB-uORBDeviceMaster-cpp-88)

```c
    85 │ 		}
    86 │ 	}
    87 │ 
▶   88 │ 	SmartLock smart_lock(_lock);
    89 │ 
    90 │ 	do {
    91 │ 		/* if path is modifyable change try index */
```
> **说明**：多实例自动分配实例号（从 0 起找第一个空） | PublicationMultiBase::advertise()：int instance = 0; orb_advertise_multi(..., &instance) | Publication.cpp:76 | ┃ 分配算法本体（按 /obj/<topic>_N 路径试） | uORB::DeviceMaster::advertise() | uORBDeviceMaster.cpp:88 |
^src-platforms-common-uORB-uORBDeviceMaster-cpp-88

### `platforms/common/uORB/uORBDeviceNode.hpp`
<a id="src-platforms-common-uORB-uORBDeviceNode-hpp-198"></a>
**↓ 文档在讲这里：**[`platforms/common/uORB/uORBDeviceNode.hpp:198`](uorb-internals.md#^src-platforms-common-uORB-uORBDeviceNode-hpp-198)

```c
   195 │ 	 * We can get the correct value regardless of wrap-around or not.
   196 │ 	 * @param generation The generation of subscriber
   197 │ 	 */
▶  198 │ 	unsigned updates_available(unsigned generation) const { return _generation.load() - generation; }
   199 │ 
   200 │ 	/**
   201 │ 	 * Return the initial generation to the subscriber
```
> **说明**：px4::atomic<unsigned> _generation | 代次计数器；每 publish 一次 +1 | uORBDeviceNode.hpp:291 | ┃ updates_available(g) | _generation - g ⇒ 订阅者靠比代次判断"有没有新的" | uORBDeviceNode.hpp:198 |
^src-platforms-common-uORB-uORBDeviceNode-hpp-198

### `platforms/common/uORB/uORBDeviceNode.hpp`
<a id="src-platforms-common-uORB-uORBDeviceNode-hpp-241"></a>
**↓ 文档在讲这里：**[`platforms/common/uORB/uORBDeviceNode.hpp:241`](uorb-internals.md#^src-platforms-common-uORB-uORBDeviceNode-hpp-241)

```c
   238 │ 			return false;
   239 │ 		}
   240 │ 
▶  241 │ 		if (_meta->o_queue == 1) {
   242 │ 			memcpy(dst, _data, _meta->o_size);
   243 │ 			generation = _generation.load();
   244 │ 			ATOMIC_LEAVE;
```
> **说明**：uint8_t *_data | 真数据（o_size × o_queue 字节）；惰性分配 | uORBDeviceNode.hpp:289 | ┃ _meta->o_queue | 队列深度（默认 1；.msg 里写 ORB_QUEUE_LENGTH = n 就变 n） | uORBDeviceNode.hpp:241 |
^src-platforms-common-uORB-uORBDeviceNode-hpp-241

### `platforms/common/uORB/uORBDeviceNode.hpp`
<a id="src-platforms-common-uORB-uORBDeviceNode-hpp-289"></a>
**↓ 文档在讲这里：**[`platforms/common/uORB/uORBDeviceNode.hpp:289`](uorb-internals.md#^src-platforms-common-uORB-uORBDeviceNode-hpp-289)

```c
   286 │ 
   287 │ 	const orb_metadata *_meta; /**< object metadata information */
   288 │ 
▶  289 │ 	uint8_t *_data{nullptr};   /**< allocated object buffer, guarded by the node lock (ATOMIC_ENTER) */
   290 │ 	bool _data_valid{false}; /**< At least one valid data */
   291 │ 	px4::atomic<unsigned>  _generation{0};  /**< object generation count */
   292 │ 	List<uORB::SubscriptionCallback *>	_callbacks;
```
> **说明**：uint8_t *_data | 真数据（o_size × o_queue 字节）；惰性分配 | uORBDeviceNode.hpp:289 |
^src-platforms-common-uORB-uORBDeviceNode-hpp-289

### `platforms/common/uORB/uORBDeviceNode.hpp`
<a id="src-platforms-common-uORB-uORBDeviceNode-hpp-291"></a>
**↓ 文档在讲这里：**[`platforms/common/uORB/uORBDeviceNode.hpp:291`](uorb-internals.md#^src-platforms-common-uORB-uORBDeviceNode-hpp-291)

```c
   288 │ 
   289 │ 	uint8_t *_data{nullptr};   /**< allocated object buffer, guarded by the node lock (ATOMIC_ENTER) */
   290 │ 	bool _data_valid{false}; /**< At least one valid data */
▶  291 │ 	px4::atomic<unsigned>  _generation{0};  /**< object generation count */
   292 │ 	List<uORB::SubscriptionCallback *>	_callbacks;
   293 │ 
   294 │ 	const uint8_t _instance; /**< orb multi instance identifier */
```
> **说明**：_meta->o_queue | 队列深度（默认 1；.msg 里写 ORB_QUEUE_LENGTH = n 就变 n） | uORBDeviceNode.hpp:241 | ┃ px4::atomic<unsigned> _generation | 代次计数器；每 publish 一次 +1 | uORBDeviceNode.hpp:291 |
^src-platforms-common-uORB-uORBDeviceNode-hpp-291

### `platforms/common/uORB/uORBDeviceNode.hpp`
<a id="src-platforms-common-uORB-uORBDeviceNode-hpp-297"></a>
**↓ 文档在讲这里：**[`platforms/common/uORB/uORBDeviceNode.hpp:297`](uorb-internals.md#^src-platforms-common-uORB-uORBDeviceNode-hpp-297)

```c
   294 │ 	const uint8_t _instance; /**< orb multi instance identifier */
   295 │ 	px4::atomic_bool _advertised{false};  /**< has ever been advertised (not necessarily published data yet) */
   296 │ 
▶  297 │ 	int8_t _subscriber_count{0};
   298 │ 
   299 │ 
   300 │ // Determine the data range
```
> **说明**：updates_available(g) | _generation - g ⇒ 订阅者靠比代次判断"有没有新的" | uORBDeviceNode.hpp:198 | ┃ _subscriber_count | 引用计数（决定 node 能否释放） | uORBDeviceNode.hpp:297 |
^src-platforms-common-uORB-uORBDeviceNode-hpp-297

### `platforms/common/uORB/uORBDeviceMaster.cpp`
<a id="src-platforms-common-uORB-uORBDeviceMaster-cpp-90"></a>
**↓ 文档在讲这里：**[`platforms/common/uORB/uORBDeviceMaster.cpp:90`](uorb-internals.md#^src-platforms-common-uORB-uORBDeviceMaster-cpp-90)

```c
    87 │ 
    88 │ 	SmartLock smart_lock(_lock);
    89 │ 
▶   90 │ 	do {
    91 │ 		/* if path is modifyable change try index */
    92 │ 		if (instance != nullptr) {
    93 │ 			/* replace the number at the end of the string */
```
> **说明**：① 各自占一个 uORB 实例 | uORB::PublicationMulti 自动分配第一个空实例（Publication.cpp:76，instance 从 0 起试；uORBDeviceMaster.cpp:90）⇒ sensor_accel_0 / sensor_accel_1 | PX4Accelerometer.hpp:73 |
^src-platforms-common-uORB-uORBDeviceMaster-cpp-90
