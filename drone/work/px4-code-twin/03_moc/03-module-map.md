# module 层怎么理解（本板 rm2027/fmu-h743）

> **回答的是这一问**：「软件运行的逻辑大头，module 层如何理解？」
> **视角**：程序运行时 —— 一个 module 什么时候被创建、跑在哪个线程、它跟别人的唯一接口是什么。
> **行号基准** = `源码根（见 `tools/source-root.conf`）`（HEAD `3b5de24`，`git status` 干净）。
> **三层标注**：`[实测]` / `[源码]` / `[推理]`。

### 缩写约定（同 [03_moc/02-sensor-flow](02-sensor-flow.md)，便于复核）

| 短名 | 全路径（相对 `源码根（见 `tools/source-root.conf`）`） |
|---|---|
| `module.h` | `platforms/common/include/px4_platform_common/module.h` |
| `WorkQueueManager.cpp` / `WorkQueueManager.hpp` | `platforms/common/px4_work_queue/…` / `platforms/common/include/px4_platform_common/px4_work_queue/…` |
| `ScheduledWorkItem.hpp` | `platforms/common/include/px4_platform_common/px4_work_queue/ScheduledWorkItem.hpp` |
| `uORBDeviceNode.hpp` / `Publication.cpp` / `Subscription.hpp` / `uORB.h` / `i2c_spi_buses.h` | `platforms/common/uORB/…`（`i2c_spi_buses.h` 在 `platforms/common/include/px4_platform_common/`） |
| `px4_add_module.cmake` | `cmake/px4_add_module.cmake` |
| `platforms/nuttx/NuttX/CMakeLists.txt` | 同左（builtin 表生成处） |
| `px4.bdat` / `px4_boardconfig.h` | `build/rm2027_fmu-h743_default/NuttX/px4.bdat`、`build/rm2027_fmu-h743_default/px4_boardconfig.h`（★ 构建产物） |
| `rcS` / `rc.mc_apps` | `ROMFS/px4fmu_common/init.d/…` |
| `rc.board_sensors` | `boards/rm2027/fmu-h743/init/rc.board_sensors` |
| `sensors.cpp` / `VehicleIMU.cpp` / `VehicleAngularVelocity.cpp` | `src/modules/sensors/…` |
| `ControlAllocator.cpp` / `mc_att_control_main.cpp` / `MulticopterPositionControl.cpp` / `MulticopterRateControl.cpp` | `src/modules/{control_allocator,mc_att_control,mc_pos_control,mc_rate_control}/…` |
| `DShot.cpp` / `H104IMU.cpp` / `HXY42688P.cpp` / `IST8310.cpp` / `SPA06.cpp` / `EKF2Selector.cpp` / `EKF2.cpp` | 对应驱动/模块目录（全路径见各孪生篇） |
| `msg/*.msg` | `msg/`（话题结构体定义） |

---

## 1. 一句话：PX4 的"逻辑大头"是 78 个小程序 + 一条内存总线

`[实测，构建产物]` 本板固件里一共 **78 个可独立启停的入口**：

```sh
$ sed 's/.*{ "\([a-z0-9_]*\)".*/\1/' build/rm2027_fmu-h743_default/NuttX/px4.bdat | sort | wc -l
78
```

它们**互不链接调用**（`sensors` 不会 `#include` `hxy42688p`），
**唯一的沟通方式是一条叫 uORB 的内存总线**。

> ⇒ 所以"理解 module 层"= 理解三件事：
> **① module 怎么被造出来（谁给它任务/线程）**
> **② module 之间怎么说话（uORB 话题）**
> **③ module 谁先谁后（启动顺序 = 依赖顺序）**

本文就按这三件写。逐 module 的细节在 [03_moc/02-sensor-flow](02-sensor-flow.md) 与 `02_code_twin/modules/`。

---

## 2. module 是什么（能独立启停的功能块）

### 2.1 从一行 shell 命令说起：`hxy42688p -s -b 1 -R 6 start`

这一行能敲，是因为构建期生成了**一张"命令 → 函数"表**：

```
cmake/px4_add_module.cmake:214-215
    target_compile_definitions(${MODULE} PRIVATE PX4_MAIN=${MAIN}_app_main)
    target_compile_definitions(${MODULE} PRIVATE MODULE_NAME="${MAIN}")
                        │
                        ▼
platforms/nuttx/NuttX/CMakeLists.txt:92-100   ← 遍历所有 module 的 MAIN/STACK_MAIN/PRIORITY
    "{ \"${MAIN}\", ${PRIORITY}, ${STACK_MAIN}, ${MAIN}_main },\n"
    "int ${MAIN}_main(int argc, char *argv[]);\n"
                        │
        configure_file(px4.bdat.in → px4.bdat)      :137-138
        拷进 apps/builtin/registry/ → 让 NuttX 重建 builtin 表  :154-157
                        ▼
build/rm2027_fmu-h743_default/NuttX/px4.bdat
    { "hxy42688p", SCHED_PRIORITY_DEFAULT, 2048 * (__SIZEOF_POINTER__ >> 2), hxy42688p_main },
```

⇒ **一个 module = 一个 nsh 命令 + 一个 C 入口函数 `<MAIN>_main` + 一个栈大小 + 一个调度优先级。**
⇒ `nsh` 敲 `hxy42688p ... start` 时，NuttX 直接调 `hxy42688p_main(argc, argv)`（[`hxy42688p_main.cpp:49`](../02_code_twin/build/drivers-build.md#^src-src-drivers-imu-hxy-hxy42688p-hxy42688p-main-cpp-49)）。

### 2.2 `start` 之后发生什么（两种活法）

```c
// 每个 module 的 Main 末尾都是同一套（H104 是手写的，其余走 ModuleBase）
if (!strcmp(verb, "start")) { return ThisDriver::module_start(cli, iterator); }
```

| 活法 | 谁在用 | 机制 | 判定标志 |
|---|---|---|---|
| **A. 自己开一个线程** | `mavlink`、`ekf2`？→ 见下注、`commander`、`navigator` 等 | `ModuleBase::start_command()` → `desc.task_spawn()` → `run_trampoline_impl()` 里 `px4_task_spawn_cmd()` | `desc.task_id != -1` |
| **B. 挂到工作队列** | `sensors`、`hxy42688p`、`ist8310`、`spa06`、`dshot`、`h104_imu` | 对象继承 `px4::ScheduledWorkItem`，`ScheduleNow/ScheduleDelayed/ScheduleOnInterval` 把自己排进某个 wq | `task_id == ModuleBase::task_id_is_work_queue (-2)`（[`module.h:174`](../02_code_twin/build/others.md#^src-platforms-common-include-px4-platform-common-module-h-174)） |

`[源码]`：`ModuleBase` 的接口在 [`platforms/common/include/px4_platform_common/module.h:76`](../02_code_twin/build/others.md#^src-platforms-common-include-px4-platform-common-module-h-76)
（`main` `:102`、`start_command` `:107`、`stop_command` `:112`、`status_command` `:117`、`run_trampoline_impl` `:141`、`run()` `:147`、`task_id_is_work_queue` `:174`）。

> **为什么大头是 B（工作队列）而不是 A（线程）？**
> NuttX 线程有独立的栈；78 个 module 各开一个线程，RAM 直接爆。工作队列 = **固定几个线程**（本板实际起 9 个 wq，见 §4），
> 几十个 module 把"要跑一次"排进队列（`WorkItem`），谁先谁后由**优先级**和**轮询**决定。

### 2.3 module / driver / library 的区别

| | 判定标准 | 例子（本板） | 区别的实际后果 |
|---|---|---|---|
| **module** | 有 `MAIN`，进 `px4.bdat` ⇒ **能敲命令启停** | `sensors` `ekf2` `dshot` `hxy42688p` | 可以被 rcS 单独拉起来／单独 `stop` |
| **driver** | module 的一个**子集**：跟硬件打交道、实现 `probe()` | `hxy42688p` `ist8310` `spa06` | `probe()` 失败 ⇒ 实例被 `delete`（[`i2c_spi_buses.h:365`](../02_code_twin/build/others.md#^src-platforms-common-include-px4-platform-common-i2c-spi-buses-h-365)）⇒ 安静地不发布话题 |
| **library** | 没有 `MAIN`，编成静态库，被链接进别人 | `src/lib/drivers/accelerometer/PX4Accelerometer.cpp`、`src/lib/mixer_module/`、`src/lib/sensor_calibration/` | **不能独立启停**，只能被 module 调用 |

**⇒ 一句话记法**：`library` 是**代码**，`module` 是**进程/任务**，`driver` 是**会 probe 硬件的 module**。

> ⚠️ 反例（本项目血泪）：`bmi270` 的 ~1400 行代码**活着、编译得动，但从没被链接进固件**
> —— 因为 [`boards/rm2027/fmu-h743/default.px4board:26`](../02_code_twin/drivers/bmi270.md#^src-boards-rm2027-fmu-h743-default-px4board-26) 是**注释掉的**。
> 「能跑通/没被删」≠「在工作」。见 [02_code_twin/drivers/bmi270](../02_code_twin/drivers/bmi270.md)。

---

## 3. uORB 是什么（module 之间唯一的那条总线）

### 3.1 话题 vs 消息

| 词 | 指什么 | 例子 | 出处 |
|---|---|---|---|
| **消息（message）** | 一个**结构体定义**（`.msg` 文件） | `msg/SensorAccel.msg`（`device_id/x/y/z/temperature/error_count/clip_counter` + `ORB_QUEUE_LENGTH = 8`） | `msg/` 目录 |
| **话题（topic）** | 这个结构体在内存里的**一个实例**，用 `ORB_ID(sensor_accel)` 指代 | `sensor_accel`（可有多条：`sensor_accel_0`、`_1`…） | `Tools/msg/px_generate_uorb_topic_files.py` 生成 `build/.../uORB/topics/sensor_accel.h`；生成规则 [`msg/CMakeLists.txt:356`](../02_code_twin/uorb/msg-build.md#^src-msg-CMakeLists-txt-356) |

`.msg` → C 结构的这一步发生在构建期，产物是：
```
build/rm2027_fmu-h743_default/uORB/topics/sensor_accel.h        ← 结构体
build/rm2027_fmu-h743_default/uORB/topics/uORBTopics.hpp/.cpp   ← 全话题总表（orb_metadata 数组）
```
[`msg/CMakeLists.txt:356`](../02_code_twin/uorb/msg-build.md#^src-msg-CMakeLists-txt-356)（`uORBTopics.hpp`、`uORBTopics.cpp`）、`:458`（`uorb_msgs` 库）。

### 3.2 发布 / 订阅怎么工作

```
【发布者】                                    【订阅者】
 uORB::Publication<T> _pub{ORB_ID(theme)}      uORB::Subscription _sub{ORB_ID(theme)};
   或 PublicationMulti<T>（多实例）               或 SubscriptionData<T>（自己带缓存）
        │                                             │
   _pub.publish(&data)                             _sub.update(&dst) / copy(&dst)
        │                                             │
        └──────────► uORB::DeviceNode ◄───────────────┘
                     （一条话题 = 一个 node）
```

关键 API（都在 `platforms/common/uORB/`，本板 NuttX 是**单地址空间**，所以"发布"实际是往共享内存里拷 + 递增代次）：

| 动作 | 代码 | file:line |
|---|---|---|
| 第一次发布时自动 advertise | `PublicationBase::advertise()` → `orb_advertise()` | [`Publication.cpp:58`](../02_code_twin/uorb/uorb-internals.md#^src-platforms-common-uORB-Publication-cpp-58) |
| 多实例自动分配实例号（从 0 起找第一个空） | `PublicationMultiBase::advertise()`：`int instance = 0; orb_advertise_multi(..., &instance)` | [`Publication.cpp:76`](../02_code_twin/uorb/uorb-internals.md#^src-platforms-common-uORB-Publication-cpp-76) |
| 分配算法本体（按 `/obj/<topic>_N` 路径试） | `uORB::DeviceMaster::advertise()` | [`uORBDeviceMaster.cpp:88`](../02_code_twin/uorb/uorb-internals.md#^src-platforms-common-uORB-uORBDeviceMaster-cpp-88) |
| 最大实例数 | `ORB_MULTI_MAX_INSTANCES = 4`（NuttX 上；POSIX 是 10） | [`platforms/common/uORB/uORB.h:66`](../02_code_twin/uorb/uorb-internals.md#^src-platforms-common-uORB-uORB-h-66) |
| 订阅者"有没有新数据" | `Subscription::updated()` | [`Subscription.hpp:99`](../02_code_twin/uorb/uorb-internals.md#^src-platforms-common-uORB-Subscription-hpp-99) |
| 订阅者取数据 | `Subscription::update()` / `copy()` / `ChangeInstance()` | `Subscription.hpp:105/111/117` |

### 3.3 ★ 数据在内存里怎么落地（这是"uORB 不是消息队列"的关键）

一条话题在内存里就是 `uORB::DeviceNode` 里的一块缓冲：

| 字段 | 作用 | file:line |
|---|---|---|
| `uint8_t *_data` | **真数据**（`o_size × o_queue` 字节）；惰性分配 | [`uORBDeviceNode.hpp:289`](../02_code_twin/uorb/uorb-internals.md#^src-platforms-common-uORB-uORBDeviceNode-hpp-289) |
| `_meta->o_queue` | 队列深度（默认 1；`.msg` 里写 `ORB_QUEUE_LENGTH = n` 就变 n） | [`uORBDeviceNode.hpp:241`](../02_code_twin/uorb/uorb-internals.md#^src-platforms-common-uORB-uORBDeviceNode-hpp-241) |
| `px4::atomic<unsigned> _generation` | **代次计数器**；每 publish 一次 +1 | [`uORBDeviceNode.hpp:291`](../02_code_twin/uorb/uorb-internals.md#^src-platforms-common-uORB-uORBDeviceNode-hpp-291) |
| `updates_available(g)` | `_generation - g` ⇒ 订阅者靠**比代次**判断"有没有新的" | [`uORBDeviceNode.hpp:198`](../02_code_twin/uorb/uorb-internals.md#^src-platforms-common-uORB-uORBDeviceNode-hpp-198) |
| `_subscriber_count` | 引用计数（决定 node 能否释放） | [`uORBDeviceNode.hpp:297`](../02_code_twin/uorb/uorb-internals.md#^src-platforms-common-uORB-uORBDeviceNode-hpp-297) |

**⇒ 两个立刻能用的推论：**
1. **话题不是"队列"**（`o_queue=1` 时：后写覆盖前写，订阅者只拿到最新值）。要"不丢帧"必须把 `ORB_QUEUE_LENGTH` 调大，而 `SensorAccel.msg` 恰好写了 `8`。
2. **多实例是"同一个名字 + 不同后缀"**，`sensor_gyro_0` 与 `sensor_gyro_1` 是两个 `DeviceNode`，各自有 `_data` 和 `_generation`，互不干扰。

**判据（上板自证）**：
```
uorb top            # 看每个话题的发布频率与订阅者数
listener sensor_gyro 0    # 指定实例号（第 0 条）
listener -n 1 sensor_gyro
sensors status            # 看 selected gyro/accel 是谁
```

---

## 4. 工作队列是什么（为什么驱动不能阻塞）

### 4.1 机制：`WorkItem` = "往队列里排队"

```
px4::WorkItem                 （一个可排队的对象）
   └── px4::ScheduledWorkItem （多了"延迟/周期"语义，ScheduledWorkItem.hpp:43）
          ├── ScheduleNow()            立即排一次          （继承自 WorkItem）
          ├── ScheduleDelayed(us)      延迟 us 后跑一次     ScheduledWorkItem.hpp:56
          ├── ScheduleOnInterval(us)   每 us 跑一次         ScheduledWorkItem.hpp:64
          └── ScheduleClear()          取消                ScheduledWorkItem.hpp:76
```

`[源码]` `platforms/common/include/px4_platform_common/px4_work_queue/ScheduledWorkItem.hpp:43,56,64,76`。

### 4.2 本板实际起哪些队列、什么优先级 `[实测，构建产物]`

[`build/rm2027_fmu-h743_default/px4_boardconfig.h:139`](../02_code_twin/build/artifacts.md#^src-build-rm2027-fmu-h743-default-px4-boardconfig-h-139)（由 `platforms/common/px4_work_queue/Kconfig` 生成）：

| 队列 | 优先级 | 栈字节 | 本板上跑什么 |
|---|---|---|---|
| `wq:rate_ctrl` | **0**（最高） | 3150 | ★ **控制链本体**：`VehicleAngularVelocity`（[`VehicleAngularVelocity.cpp:47`](../02_code_twin/modules/sensors.md#^src-src-modules-sensors-vehicle-angular-velocity-VehicleAngularVelocity-cpp-47)）、`mc_rate_control`（[`MulticopterRateControl.cpp:50`](../02_code_twin/modules/control_allocator.md#^src-src-modules-mc-rate-control-MulticopterRateControl-cpp-50)）、`control_allocator`（[`ControlAllocator.cpp:57`](../02_code_twin/modules/control_allocator.md#^src-src-modules-control-allocator-ControlAllocator-cpp-57)） |
| `wq:SPI1` | -2 | 2392 | **hxy42688p**（[`WorkQueueManager.cpp:163`](../02_code_twin/framework/work-queue.md#^src-platforms-common-px4-work-queue-WorkQueueManager-cpp-163)） |
| `wq:I2C2` | -10 | 2336 | **spa06**（`:152`） |
| `wq:I2C4` | -12 | 2336 | **ist8310**（`:156`） |
| `wq:nav_and_controllers` | -13 | 2240 | **sensors 模块**（[`sensors.cpp:50`](../02_code_twin/modules/sensors.md#^src-src-modules-sensors-sensors-cpp-50)）、`mc_att_control`（`mc_att_control_main.cpp:61`）、`mc_pos_control`（`MulticopterPositionControl.cpp:48`）、`ekf2_selector`（[`EKF2Selector.cpp:44`](../02_code_twin/modules/ekf2.md#^src-src-modules-ekf2-EKF2Selector-cpp-44)）、`navigator` |
| `wq:INS0` | -14 | 6000 | **ekf2**、**VehicleIMU**、**h104_imu**（[`H104IMU.cpp:54`](../02_code_twin/build/drivers-build.md#^src-src-drivers-imu-hipnuc-h104-H104IMU-cpp-54)） |
| `wq:INS1..3` | -15…-17 | 6000 | 只在 `SENS_IMU_MODE=0` 时用（`sensors.cpp:448`） |
| `wq:hp_default` | -18 | 2800 | **dshot**（[`DShot.cpp:45`](../02_code_twin/modules/rc_update.md#^src-src-drivers-dshot-DShot-cpp-45)）、`rc_update`（[`rc_update.cpp:71`](../02_code_twin/modules/rc_update.md#^src-src-modules-rc-update-rc-update-cpp-71)）、`manual_control`（[`ManualControl.cpp:44`](../02_code_twin/modules/rc_update.md#^src-src-modules-manual-control-ManualControl-cpp-44)） |
| `wq:ttyS0` | -21 | 2048 | `h104_imu` 的 `::read()` **不在这里** —— 它在 INS0（见下） |
| `wq:ttyS2` | -23 | 2048 | TEL1 上的 MAVLink |
| `wq:lp_default` | -50 | 3500 | 低优先级杂活（`logger` 等） |

> **★ 看这个优先级就知道"控制链的实时性从哪来"**：
> `sensor_gyro`(SPI1, -2) → `vehicle_angular_velocity`(rate_ctrl, 0) → `mc_rate_control`(rate_ctrl, 0)
> → `control_allocator`(rate_ctrl, 0) → `dshot`(hp_default, -18)。
> **前三跳在最高优先级队列上连成一条线**，最后一跳降到 -18 是因为 DShot 要等 DMA 发送窗口。
> `commander` / `flight_mode_manager` / `mavlink` / `logger` **不在任何 wq 上** —— 它们是 `ModuleBase` 自己的线程（低频、允许慢）。

映射规则：`WorkQueueManager.cpp:137-179 device_bus_to_wq(devid)` ——
`I2C bus n → wq:I2C n`（`:146-157`）、`SPI bus n → wq:SPI n`（`:159-174`）、**别的都落 `hp_default`**（`:177-178`）。
串口另有 `serial_port_to_wq()`（`:181-224`，按 `/dev/ttySn` 字面匹配）。

> ⚠️ **一个容易搞错的点**：`h104_imu` 挂在 `/dev/ttyS0`，但它**不在** `wq:ttyS0`。
> 它是**手写的 `ScheduledWorkItem`**，构造时写死 `px4::wq_configurations::INS0`（[`H104IMU.cpp:54`](../02_code_twin/build/drivers-build.md#^src-src-drivers-imu-hipnuc-h104-H104IMU-cpp-54)）。
> `serial_port_to_wq` 只对"用 `SerialIO`/`px4_task_spawn` 的串口驱动"生效。

### 4.3 为什么驱动**不能阻塞**（这是设计约束，不是风格问题）

同一个队列上排着**多个 module**（例如 `wq:INS0` 上同时有 `ekf2` + `VehicleIMU#0` + `VehicleIMU#1` + `h104_imu`）。

| 如果在驱动里干这个 | 后果 |
|---|---|
| `px4_usleep(1000)` 等 DRDY | 整个 `wq:SPI1` 停 1 ms ⇒ 1 kHz 采样的**下一个拍**直接丢 |
| 阻塞式 `::read()`（无 `O_NONBLOCK`） | `wq:INS0` 上 `ekf2` 永远拿不到 CPU |
| 忙等寄存器 | 同队列别人的延迟全被顶高 |

⇒ PX4 的标准解法就是 **`ScheduleDelayed(下次再来)`**：把"等"变成"让出队列"。
- `hxy42688p`：`ScheduleOnInterval(POLL_INTERVAL_US, ...)`（[`HXY42688P.cpp:269`](../02_code_twin/build/drivers-build.md#^src-src-drivers-imu-hxy-hxy42688p-HXY42688P-cpp-269)，1 kHz）
- `h104_imu`：`ScheduleDelayed(2000us)` + 非阻塞 `read`（`H104IMU.cpp:136,219`，`O_NONBLOCK` 在 `:87`）
- `ist8310`：`ScheduleDelayed(20_ms)`（[`IST8310.cpp:183`](../02_code_twin/build/drivers-build.md#^src-src-drivers-magnetometer-isentek-ist8310-IST8310-cpp-183)）
- `spa06`：`ScheduleDelayed(_measure_interval)`（`SPA06.cpp:207`）
- `sensors`：`ScheduleDelayed(10_ms)` 兜底（[`sensors.cpp:617`](../02_code_twin/modules/sensors.md#^src-src-modules-sensors-sensors-cpp-617)）

**同一队列被一个模块堵住** 是真实故障模式，本项目也踩过一次：
[`H104IMU.cpp:130`](../02_code_twin/build/drivers-build.md#^src-src-drivers-imu-hipnuc-h104-H104IMU-cpp-130) 的注释记录 —— 一开始在 `Start()`（模块任务）里 `open()` 串口，
但 `Run()` 在工作队列线程执行，NuttX 的 fd 表**按任务隔离** ⇒ `read()` 直接 `EBADF`。
**结论：端口必须在真正读它的那个任务里开。**

---

## 5. 启动依赖：`rcS` 的顺序**就是**依赖顺序

`rcS` 是 NuttX shell 跑的第一个脚本，797 行。**没有"依赖声明"，顺序即依赖**（详见 `work/PX4-rcS执行时序表.md`）。

### 5.1 本板真机的执行序（只列"会启动 module"的行）

| rcS 行 | 命令 | 为什么必须在这个位置 `[推理：rcS 注释 + 机制]` |
|---|---|---|
| `:58` | `ver all` | 先打版本，便于串口取证 |
| `:64` | `. rc.board_early`（**本板没有此文件** ⇒ 跳过） | 存储挂载之前 |
| `:179-255` | `param load-or-init` | ★ **所有依赖参数的 module 都在它之后** |
| `:270` | `. rc.board_arch_defaults`（平台层，非板级） | 参数加载后、机型前 |
| `:278-281` | `. rc.board_defaults`（**本板有**） | 机型加载**之前** |
| `:297-319` | `. rc.autostart`（按 `SYS_AUTOSTART=4001`） | 决定 `VEHICLE_TYPE=mc` |
| `:343` | `tone_alarm start` | 受 `CBRK_BUZZER`，必须在参数加载之后 |
| `:356` | `dataman start` | 航点存储 |
| `:363` | `send_event start` | socket 事件 |
| `:376` | `load_mon start` | 资源监控 |
| **`:424`** | **`. rc.board_sensors`（本板 5 个 module）** | 见 §5.2 |
| `:428` | `. rc.sensors` | 可选传感器（本板 `SENS_EN_*` 全关 ⇒ 不做事） |
| `:437` | `battery_status start` | `BAT1_SOURCE != 1` |
| **`:440`** | **`sensors start`** | ★ **必须晚于所有 `sensor_*` 发布者** |
| **`:448`** | **`ekf2 start &`**（**后台**） | 必须晚于 `sensors` |
| `:509-510` | `rc_update start` / `manual_control start` | rcS:507 注释：「start before commander」 |
| **`:551`** | **`commander start`** | 解锁检查要读 `manual_control_setpoint` |
| `:559-560` | `dshot start` / `pwm_out start` | 必须在 `commander` 之后（要 `actuator_armed`） |
| `:580` | `. rc.vehicle_setup` | 按 `VEHICLE_TYPE` 分发 |
| `:603` | `. rc.serial`（**自动生成**） | ★ MAVLink/RC 端口在这里才配好 |
| `:611` | `rc_input start $RC_INPUT_ARGS` | rcS:610 注释：「Must be started after the serial config is read」 |
| `:636` | `navigator start` | |
| `:696` | `. rc.board_extras`（**本板有**，内容是注释） | |
| `:716` | `. rc.logging`（→ `logger start`） | 收敛阶段 |

`rc.mc_apps`（由 `:580` 间接拉起，`VEHICLE_TYPE=mc`）的顺序：

| 行 | 命令 |
|---|---|
| `rc.mc_apps:11` | **`control_allocator start`** ← 必须早于所有控制器（控制器要读 `control_allocator_status`） |
| `:16` | `mc_rate_control start` |
| `:21` | `mc_att_control start` |
| `:40` | `mc_hover_thrust_estimator start` |
| `:41` | `flight_mode_manager start` |
| `:42` | `mc_pos_control start` |
| `:47` | `land_detector start multicopter` |

### 5.2 本板 `rc.board_sensors` 拉起的 5 个（`rc.board_sensors:55-119`）

| 顺序 | 命令 | 行 |
|---|---|---|
| 1 | `board_adc start` | `:55` |
| 2 | `hxy42688p -s -b 1 -R 6 start` | `:85` |
| 3 | `ist8310 -I -b 4 -a 0x0C -R 0 start` | `:105` |
| 4 | `spa06 -I -b 2 -a 0x77 start` | `:110` |
| 5 | `h104_imu start` | `:119` |

> 这 5 个**顺序无所谓**（互不依赖，都只是往 uORB 发话题），
> 但**都必须在 `rcS:440 sensors start` 之前** —— 因为 `sensors` 靠 `accel_sub.advertised()`
> 来判断"这个实例存不存在"（`sensors.cpp:438`）：
> **先有发布者，`sensors` 才会为它建 `VehicleIMU`。**

### 5.3 依赖图（提炼成 4 层）

```
第0层  参数 / 机型（rcS:179-319）
          │
第1层  硬件驱动（rc.board_sensors:424 → 5 个）
          │  sensor_accel / sensor_gyro / sensor_mag / sensor_baro
第2层  sensors（:440）  ← ★ 唯一做"归一化 + 投票"的
          │  sensor_combined / vehicle_imu / vehicle_air_data / vehicle_magnetometer
第3层  ekf2（:448） + rc_update/manual_control（:509-510） + commander（:551）
          │  vehicle_attitude / vehicle_local_position / manual_control_setpoint / actuator_armed
第4层  控制器（rc.mc_apps） + 输出（dshot/pwm_out :559-560） + 通信（:603+）
```

**⇒ 排错口诀**：故障现象在**哪一层**，就往上找一层。
`ekf2 status` 里 IMU 是 0 Hz ⇒ 别查 EKF2，去查第 1/2 层（`hxy42688p status`、`sensors status`）。

---

## 6. 本板会跑哪些 module（清单）

### 6.1 编进固件的 78 个 `[实测，px4.bdat]`

```
actuator_test af9838 ak09916 ak8963 attitude_estimator_q battery_status bmm150 bmm350
board_adc bst commander control_allocator dataman dmesg dshot ekf2 flight_mode_manager
frsky_telemetry fw_att_control fw_lat_lon_control fw_mode_manager fw_rate_control gpio
gyro_calibration gyro_fft h104cap h104_imu hardfault_log hmc5883 hott_sensors hott_telemetry
hxy42688p i2cdetect icm42605 icm42670p icm42688p icm45686 iis2mdc ist8308 ist8310
land_detector landing_target_estimator lis3mdl listener load_mon local_position_estimator
logger lsm303agr lsm6dsv mag_bias_estimator manual_control mavlink mc_att_control
mc_hover_thrust_estimator mc_pos_control mc_rate_control mmc5983ma navigator nshterm param
perf pwm_out qmc5883l qmc5883p rc_input rc_update reboot rm3100 send_event sensors spa06
system_time top uorb uxrce_dds_client ver vtol_att_control work_queue
```

> ⚠️ **编进去 ≠ 会跑**。
> `af9838`、`ak09916`、`bmm150`… 这一堆磁罗盘之所以都在，是因为 `default.px4board:33 CONFIG_COMMON_MAGNETOMETER=y`
> 会 `select` 全部磁驱动（`src/drivers/magnetometer/Kconfig`；板级注释在 `default.px4board:44`）。
> 它们**没有**出现在 `rc.board_sensors` 里 ⇒ 不会启动。这正是"错驱动 `af9838` 认错芯片"那次事故能发生的前提。

### 6.2 真机会跑的（按 rcS/rc.board_*/rc.mc_apps 实际行）

| 类别 | module | 依据 |
|---|---|---|
| 板级驱动（5） | `board_adc` `hxy42688p` `ist8310` `spa06` `h104_imu` | `rc.board_sensors:55,85,105,110,119` |
| 聚合/估计 | `sensors`、`ekf2` | `rcS:440,448` |
| 电池/存储/监控 | `battery_status`、`dataman`、`load_mon`、`send_event`、`tone_alarm` | `rcS:437,356,376,363,343` |
| 手动/遥控 | `rc_update`、`manual_control`、`rc_input` | `rcS:509,510,611` |
| 指挥 | `commander` | `rcS:551` |
| 控制（mc） | `control_allocator`、`mc_rate_control`、`mc_att_control`、`mc_hover_thrust_estimator`、`flight_mode_manager`、`mc_pos_control`、`land_detector` | `rc.mc_apps:11,16,21,40,41,42,47` |
| 输出 | `dshot`、`pwm_out`（靠 `PWM_MAIN_TIM0` 分流，见 [03_moc/02-sensor-flow](02-sensor-flow.md) §1.2） | `rcS:559-560` |
| 通信 | `mavlink`（`MAV_0_CONFIG=101` ⇒ `/dev/ttyS2`） | `rcS:603` → 生成的 `rc.serial`；[`serial_params.c:111`](../02_code_twin/modules/mavlink.md#^src-build-rm2027-fmu-h743-default-generated-params-serial-params-c-111) |
| 导航/记录 | `navigator`、`logger` | `rcS:636,716` |
| **编了但不会起** | `uxrce_dds_client`（`UXRCE_DDS_CFG=0`，[`serial_params.c:153`](../02_code_twin/build/artifacts.md#^src-build-rm2027-fmu-h743-default-generated-params-serial-params-c-153)）、`vtol_att_control`、`fw_*`、`attitude_estimator_q`、`local_position_estimator`（后两者靠 `ATT_EN`/`LPE_EN`，本板缺省 0；`rcS:451-459`）、`mag_bias_estimator`（`MBE_ENABLE`） | |

---

## 7. 未核实 / 边界

| # | 事项 | 为什么没定 |
|---|---|---|
| 1 | `ekf2` 的**单/多实例**路径各自落在哪个队列 | 单实例走 `wq:INS0`（[`EKF2.cpp:3142`](../02_code_twin/modules/ekf2.md#^src-src-modules-ekf2-EKF2-cpp-3142)）；多实例走 `EKF2Selector`(nav_and_controllers, [`EKF2.cpp:3055`](../02_code_twin/modules/ekf2.md#^src-src-modules-ekf2-EKF2-cpp-3055)) + 每个 IMU 一个 `EKF2`(`ins_instance_to_wq(imu)`, `EKF2.cpp:3094`)。**本板实际走哪条取决于 `EKF2_MULTI_IMU` 的运行值**，未上板核 |
| 2 | `logger` 在本板（**无 SD 卡、无 USB**）的实际行为 | `LOGGER_BUF` 与落盘路径未核；"无卡 ⇒ 只打错误不落盘"是 `[推理]`，未上板验证 |
| 3 | `dshot` 的 `Run()` 为什么在 `hp_default` 而不是 `rate_ctrl` | 只核到绑定点（[`DShot.cpp:45`](../02_code_twin/modules/rc_update.md#^src-src-drivers-dshot-DShot-cpp-45)）；注释/设计理由未追 |
| 4 | `px4_boardconfig.h` 的生成链 | 本文只引用**值**（`:139-182`），从哪个板级/Kconfig 文件合成**未追**（属 [03_moc/00-build-walkthrough](00-build-walkthrough.md) 的范围） |
| 5 | 78 个 builtin 里哪些在 `CONFIG_MODULES_*` 里、哪些是被 `select` 带进来的 | 只抽查了磁罗盘这一类；未逐个归类 |
| 6 | `SubscriptionCallbackWorkItem` 的"回调即调度"细节 | `VehicleIMU.cpp:54`、[`MulticopterRateControl.hpp:107`](../02_code_twin/modules/sensors.md#^src-src-modules-mc-rate-control-MulticopterRateControl-hpp-107) 都用了它；本文只说"订阅更新会触发工作队列"，**没有**展开 `registerCallback()` 的源码 |
| 7 | `ekf2 start &` 里的 `&` 语义 | 只核到「rcS 注释写作"后台"」；`&` 是 POSIX 后台还是无意义，未在 NuttX nsh 源码里确认 |

---

## 8. 自查记录

| 检查项 | 方法 | 结果 |
|---|---|---|
| `rcS` / `rc.mc_apps` 全部行号 | 逐条 `grep -n "" file \| sed -n 'Np'` | 通过 |
| `WorkQueueManager.cpp` 映射行号 | 逐条回读 | 通过 |
| [`px4_boardconfig.h:139`](../02_code_twin/build/artifacts.md#^src-build-rm2027-fmu-h743-default-px4-boardconfig-h-139) | 全量打印核对 | 通过 |
| `px4.bdat` 条目数与内容 | `sed` 提取排序计数 | 78 条，通过 |
| `default.px4board` 行号 | 逐条回读 | 通过 |

---

## 跳转

| 想去哪 | 读哪篇 |
|---|---|
| **看六条流怎么用这个总线跑起来** | [03_moc/02-sensor-flow](02-sensor-flow.md) ★ 配套篇 |
| 看 `sensors` 这个"归一化 + 投票"模块的内部 | [02_code_twin/modules/sensors](../02_code_twin/modules/sensors.md) |
| 看 `ekf2` 怎么订阅、怎么选实例 | [02_code_twin/modules/ekf2](../02_code_twin/modules/ekf2.md) |
| 看 `control_allocator` 怎么把力矩变成 `actuator_motors` | [02_code_twin/modules/control_allocator](../02_code_twin/modules/control_allocator.md) |
| 看遥控两条支线（MAVLink / 硬件 RC） | [02_code_twin/modules/rc_update](../02_code_twin/modules/rc_update.md)、[02_code_twin/modules/mavlink](../02_code_twin/modules/mavlink.md)、[02_code_twin/modules/commander](../02_code_twin/modules/commander.md) |
| 看驱动怎么"活"在工作队列里 | [02_code_twin/drivers/hxy42688p](../02_code_twin/drivers/hxy42688p.md)、[02_code_twin/drivers/dshot](../02_code_twin/drivers/dshot.md) |
| 往回退一步：上电到 rcS | [03_moc/01-poweron-walkthrough](01-poweron-walkthrough.md) |
| 这些 `CONFIG_*` 是怎么变成 module 的 | [03_moc/00-build-walkthrough](00-build-walkthrough.md) |

---

## 源码在哪（本篇只讲流程；代码与逐行解释已归位到 02 层）

> ★ **本篇每一条 `文件:行` 都能点** —— 它跳到 `02_code_twin/` 里对应的篇，代码旁边就是解释。
> 三层各司其职：**01 讲语法/机制通则 · 02 讲某个文件的行号在干什么 · 03 只讲流程**。

| 代码在 | 02 层的篇 |
|---|---|
| `02_code_twin/bootloader/00-overview.md` | [`02_code_twin/bootloader/00-overview.md`](../02_code_twin/bootloader/00-overview.md) |
| `02_code_twin/build/artifacts.md` | [`02_code_twin/build/artifacts.md`](../02_code_twin/build/artifacts.md) |
| `02_code_twin/build/drivers-build.md` | [`02_code_twin/build/drivers-build.md`](../02_code_twin/build/drivers-build.md) |
| `02_code_twin/build/others.md` | [`02_code_twin/build/others.md`](../02_code_twin/build/others.md) |
| `02_code_twin/drivers/dshot.md` | [`02_code_twin/drivers/dshot.md`](../02_code_twin/drivers/dshot.md) |
| `02_code_twin/drivers/spa06.md` | [`02_code_twin/drivers/spa06.md`](../02_code_twin/drivers/spa06.md) |
| `02_code_twin/framework/work-queue.md` | [`02_code_twin/framework/work-queue.md`](../02_code_twin/framework/work-queue.md) |
| `02_code_twin/modules/control_allocator.md` | [`02_code_twin/modules/control_allocator.md`](../02_code_twin/modules/control_allocator.md) |
| `02_code_twin/modules/ekf2.md` | [`02_code_twin/modules/ekf2.md`](../02_code_twin/modules/ekf2.md) |
| `02_code_twin/modules/manual_control.md` | [`02_code_twin/modules/manual_control.md`](../02_code_twin/modules/manual_control.md) |
| `02_code_twin/modules/mavlink.md` | [`02_code_twin/modules/mavlink.md`](../02_code_twin/modules/mavlink.md) |
| `02_code_twin/uorb/msg-build.md` | [`02_code_twin/uorb/msg-build.md`](../02_code_twin/uorb/msg-build.md) |
| `02_code_twin/uorb/uorb-internals.md` | [`02_code_twin/uorb/uorb-internals.md`](../02_code_twin/uorb/uorb-internals.md) |
