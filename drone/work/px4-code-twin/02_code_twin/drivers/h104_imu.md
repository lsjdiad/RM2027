# `src/drivers/imu/hipnuc_h104/` —— 外挂串口 IMU（USART1，100 Hz）

> **运行时一句话**：它是**唯一不经过 `I2CSPIDriver` 框架的自定义 IMU 驱动**（手写 `main` + 手写工作队列项），
> 从 `/dev/ttyS0` 收 **HI91 定长帧（82 B，CRC-16/XMODEM）**，把载体系 RFU 换算成 PX4 的 FRD，
> 以 `external=true` 的身份发 `sensor_accel` / `sensor_gyro`。
> **⇒ 它是本板"第二路 IMU"，也是唯一以 100 Hz 进入估计器的慢源。**
> 行号基准 `源码根（见 `tools/source-root.conf`）` HEAD `3b5de24`。

---

## 1. 它跟 hxy 最大的区别：**不是一个"标准 driver"**

| | hxy42688p | **h104_imu** |
|---|---|---|
| 基类 | `device::SPI` + `I2CSPIDriver<HXY42688P>` | **无**。`class H104IMU : public px4::ScheduledWorkItem`（[`H104IMU.hpp:65`](h104_imu.md#^src-src-drivers-imu-hipnuc-h104-H104IMU-hpp-65)） |
| 模块框架 | `ModuleBase`（`module_start/module_stop/module_status`） | **手写** `h104_imu_main()`，`start/stop/status` 三个分支自己写（[`h104_imu_main.cpp:100`](h104_imu.md#^src-src-drivers-imu-hipnuc-h104-h104-imu-main-cpp-100) 起） |
| probe | `probe()`（SPI 框架检查 ID） | **没有 probe**（串口没有"握手 ID"这一步）⇒ 见 §5 的代价 |
| device_id | 由 SPI 框架拼 | **手拼**：[`h104_imu_main.cpp:64`](h104_imu.md#^src-src-drivers-imu-hipnuc-h104-h104-imu-main-cpp-64) |

`device_id` 拼法（[`h104_imu_main.cpp:57`](h104_imu.md#^src-src-drivers-imu-hipnuc-h104-h104-imu-main-cpp-57) 的注释直接给了位布局）：
```
devtype(8) | address(8) | bus(5) | bus_type(3)
   DRV_IMU_DEVTYPE_HIPNUC_HI04 = 0x64          （src/drivers/drv_sensor.h:110）
   address = 0
   bus     = kBusUSART1 = 1
   bus_type= kBusTypeSerial = 5
```

---

## 2. 运行时序

```
① 拉起：boards/rm2027/fmu-h743/init/rc.board_sensors:119   `h104_imu start`
      默认 -p /dev/ttyS0、-r 0（h104_imu_main.cpp:104-105；用法说明 :90-95）

② 构造：H104IMU.cpp:53-70
      ScheduledWorkItem(MODULE_NAME, px4::wq_configurations::INS0)      :54  ★ 队列写死 INS0
      _px4_accel(device_id, rotation, true /* external */)              :58  ★ 关键！
      _px4_gyro (device_id, rotation, true /* external */)              :59
      _parser.setCallback(&H104IMU::SampleTrampoline, this)             :69

③ Start()：H104IMU.cpp:128-138
      ★ 不在这里 open 端口（注释 :130-134 解释：fd 表按任务隔离，跨任务用会 EBADF）
      ScheduleDelayed(kRunIntervalUs = 2000us)                          :136

④ Run()：H104IMU.cpp:200-263
      if (_fd < 0) { OpenPort() ... }                 :202-213   ← ★ 工作队列线程里才 open
      OpenPort(): cfsetspeed(115200)                  :104       ← ★ 波特率硬编码
                  O_RDWR | O_NONBLOCK | O_NOCTTY      :87        ← ★ 非阻塞（不能堵住 wq:INS0）
                  CS8 | CLOCAL | CREAD                :105       （注释 :101-103：漏 CS8 会 10 档波特率全 EINVAL）
      最多读 4 次 × 256 B：kReadsPerRun / kReadChunk  :217-241（常量 :50-51）
      _parser.feed(buf, n)                            :238       ← 逐字节喂解析器
      连续 2 s 无数据 ⇒ 重开端口                        :245-256（阈值 :249）
      ScheduleDelayed(2000us)                          :262

⑤ 解析出完整帧 → 回调 → Publish()：H104IMU.cpp:162-198
      now = hrt_absolute_time()                       :166       ← ★ 时间戳用 hrt，不用模块的 UTC
      _px4_accel.update(now, ...)                     :172
      _px4_gyro.update(now, ...)                      :173
      ★ 发布率 = **帧率**（不是 500 Hz 调度率）
⑥ 一次性自检日志：第一帧打 device_id + 实例号（:181-189）；约 300 帧后打帧率与 CRC 统计（:191-197）
```

**周期常量**（[`H104IMU.cpp:46`](h104_imu.md#^src-src-drivers-imu-hipnuc-h104-H104IMU-cpp-46)，注释还给了缓冲区余量估算）：
`kRunIntervalUs = 2000`（500 Hz 轮询）、`kReadsPerRun = 4`、`kReadChunk = 256`。
注释里的推算：**115200 8N1 下 HI91@100Hz = 8200 B/s，NuttX USART1 RX 缓冲 600 B（≈73 ms），2 ms 一轮最坏积压 ~16 B，余量 ~35 倍**。

---

## 3. 话题链

```
H104IMU.cpp:172-173
   ▼  (external = true)
PX4Accelerometer / PX4Gyroscope  →  sensor_accel / sensor_gyro（与 hxy 不同实例）
   ▼
【订阅者 = sensors 模块】sensors.cpp:441-442 → InitializeVehicleIMU() :435-468
   ▼
vehicle_imu（实例号 = 该对 accel/gyro 的 uORB 实例号）
   ▼
ekf2 / mc_rate_control / mavlink(HIGHRES_IMU) / logger
```

**★ 为什么 `external=true` 是个"会影响选源结果"的决定**（不是随手写的）：
`external` 决定 `CAL_GYROx_PRIO` / `CAL_ACCx_PRIO` 未设置时的**缺省优先级**：
```
Accelerometer.cpp:201-215   _priority = _external ? DEFAULT_EXTERNAL_PRIORITY(75) : DEFAULT_PRIORITY(50)
Gyroscope.hpp:50-51         同上
```
⇒ 本板：hxy（`-s` ⇒ internal）**50**、h104（代码写死 true）**75**
⇒ **不设参数时 `sensors` 投票偏 h104**。这与本项目「`sensors status` 报 H104」的现象一致。
（详见 [02_code_twin/modules/sensors](../modules/sensors.md) §5 与 [03_moc/02-sensor-flow](../../03_moc/02-sensor-flow.md) §3.2）

---

## 4. 协议层（`h104_protocol.hpp`）

| 项 | 值 | 依据 |
|---|---|---|
| 帧类型 | **HI91**，定长 **82 字节** | 手册 `HIP2:727-732,793,797`；索引见 `work/PX4改造-索引与纪律.md` §2 |
| 校验 | **CRC-16/XMODEM** | `h104_protocol.hpp:78,84-98` |
| 字段偏移 | tag@0 / 温度@3 / 时间@8 / acc@12 / gyr@24 … | [`h104_protocol.hpp:46`](h104_imu.md#^src-src-drivers-imu-hipnuc-h104-h104-protocol-hpp-46)；手册 `HIP2:738-751` |
| 单位 | acc 用 `G`、gyr 用 `deg/s` ⇒ 驱动换算成 m/s²、rad/s | [`h104_protocol.hpp:248`](h104_imu.md#^src-src-drivers-imu-hipnuc-h104-h104-protocol-hpp-248)；手册 `HIP2:754` |
| 坐标系 | 模块 RFU → PX4 FRD，映射 `[y, x, −z]` | 手册 `HIP2:78-79,94,312` |
| 单测 | 解析器**在主机上**用真实抓包做过单测 | `test_h104_protocol.cpp`；CMake 里已列（[`CMakeLists.txt:37`](h104_imu.md#^src-CMakeLists-txt-37)） |

**⇒ 优点**：协议层是可单测的纯函数（`test_h104_protocol.cpp` 不依赖硬件），这是这个驱动设计得好的地方。
**⇒ 缺点**：`MAIN_STATUS` 状态字未解析（`work/PX4改造-索引与纪律.md` §3 第 19 条，标 ⚠️）。

---

## 5. 已知欠账（本项目明确登记的）

| # | 欠账 | 后果 | 出处 |
|---|---|---|---|
| 1 | **不调 `set_error_count()`** | 投票器拿不到 `ERR CNT`；**这路坏透了，`sensors status` 也显示正常** | `work/PX4改造-索引与纪律.md` §6 #4；对比 hxy 会调（[`HXY42688P.cpp:309`](hxy42688p.md#^src-src-drivers-imu-hxy-hxy42688p-HXY42688P-cpp-309)） |
| 2 | **`_perf_overflow` 分配了、打印了、从不递增** | 串口溢出**永远计不到** | 同上 §4 第 13 条；[`H104IMU.cpp:66`](h104_imu.md#^src-src-drivers-imu-hipnuc-h104-H104IMU-cpp-66) 分配 |
| 3 | **无身份校验**（没有 probe） | 串口接错设备/帧格式不符时，靠 CRC 统计发现，不能"启动即拒" | 同上 §6 #4 |
| 4 | **X/Y 符号未用实物转动验证** | `rc.board_sensors:118` 自己标了"放飞前必须解决" | `work/PX4改造-索引与纪律.md` §8 #4 |
| 5 | **波特率硬编码 115200** | 提到 200/500/1000 Hz 必须先改这里 + 模块侧 `SERIALCONFIG` | [`H104IMU.cpp:104`](h104_imu.md#^src-src-drivers-imu-hipnuc-h104-H104IMU-cpp-104)；提频上限见 `work/review-03-H104提频.md` |
| 6 | 内部采样 1 kHz，但**带宽仅 80~200 Hz** | "提到 1000 Hz"得到的是**相关样本**，不是 1000 份独立信息 | `HI04:515,601 / 511,598 / 721-725`（见提频报告） |

---

## 6. 判据

```sh
h104_imu status
#   看：fd、device_id、uORB 实例号（accel/gyro）、运行秒数、帧率、CRC好/CRC坏/长度错/重同步跳字节
listener sensor_gyro 1        # 100 Hz
listener sensor_accel 1
perf                          # h104_imu: frames / crc bad / len bad / resync bytes / read errors / port reopens
sensors status                # 看这路有没有拿到优先级、被不被选中
```
**分诊**：
- `status` 里 **帧率不是 ~100 Hz** ⇒ 模块侧 `LOG COMCONFIG` 的 `ONTIME` 不对，或波特率被改过。
- **`CRC坏` 持续增长** ⇒ 波特率/线序/地线问题（不是软件）。
- **`重同步跳字节` 增长而 `帧` 不增** ⇒ 帧头对不上（模块输出的是别的帧类型）。
- 完全没数据 ⇒ 看 `port reopens`（驱动 2 s 无数据会重开，`:249`）。

---

## 7. 未核实

| 事项 | 说明 |
|---|---|
| HI91 帧在**本板实测**的逐字段正确性 | 协议层有单测（`test_h104_protocol.cpp`）与主机抓包；**上板逐字段核对未做** |
| 模块输出的是否就是 HI91（而非 HI83） | 依赖 `LOG COMCONFIG` 日志；驱动注释记录为 HI91@100Hz |
| `-r` 旋转在实物上的正确值 | 解析器已换算 RFU→FRD（`rc.board_sensors:116`），`-r 0`；**实物转动验证未做** |
| `_no_data_rounds` 阈值算式的含义 | `:249` `(2000 / (kRunIntervalUs / 1000))` = 1000 轮；与"2 s"一致，但写法绕 |
| `MAIN_STATUS` 状态字位表 | 手册未公开位定义（`work/PX4改造-索引与纪律.md` §3 第 19 条） |

---

## 跳转

| 下一步 | 读哪篇 |
|---|---|
| 对照：板载 1 kHz 那一路 | [02_code_twin/drivers/hxy42688p](hxy42688p.md) |
| 下游：两路怎么变成 `vehicle_imu #0/#1`、EKF2 怎么选 | [02_code_twin/modules/sensors](../modules/sensors.md)、[02_code_twin/modules/ekf2](../modules/ekf2.md) |
| 提频专项（上限 / 改哪几处） | `work/review-03-H104提频.md` |
| 六条流全景 §3 | [03_moc/02-sensor-flow](../../03_moc/02-sensor-flow.md) |

---

## 标注源码（代码 + 本文档对它的解释）

> **这是「代码孪生」层**：上面是代码原文（带行号），下面是**本文档针对这一段说的话**。
> 行号可点，直接跳到 PX4 源码那一行。
### `CMakeLists.txt`
<a id="src-CMakeLists-txt-37"></a>
**↓ 文档在讲这里：**[`CMakeLists.txt:37`](h104_imu.md#^src-CMakeLists-txt-37)

```c
    34 │ #=============================================================================
    35 │ # CMAKE CODING STANDARD FOR PX4
    36 │ #
▶   37 │ # Structure
    38 │ # ---------------------------------------------------------------------------
    39 │ #
    40 │ # * Common functions should be included in px_base.cmake.
```
> **说明**：坐标系 | 模块 RFU → PX4 FRD，映射 [y, x, −z] | 手册 HIP2:78-79,94,312 | ┃ 单测 | 解析器在主机上用真实抓包做过单测 | test_h104_protocol.cpp；CMake 里已列（CMakeLists.txt:37） |
^src-CMakeLists-txt-37

### `src/drivers/imu/hipnuc_h104/H104IMU.cpp`
<a id="src-src-drivers-imu-hipnuc-h104-H104IMU-cpp-46"></a>
**↓ 文档在讲这里：**[`src/drivers/imu/hipnuc_h104/H104IMU.cpp:46`](h104_imu.md#^src-src-drivers-imu-hipnuc-h104-H104IMU-cpp-46)

```c
    43 │ #include <px4_platform_common/log.h>
    44 │ #include <px4_platform_common/posix.h>
    45 │ 
▶   46 │ /* 每轮读多少个字节 / 多久跑一次：
    47 │  * 115200 8N1 下 HI91@100Hz = 8200 B/s；NuttX 的 USART1 RX 缓冲是 600 字节（≈73 ms）。
    48 │  * 2 ms 一轮 ⇒ 最坏积压约 16 字节，余量 ~35 倍，不可能溢出。 */
    49 │ static constexpr uint32_t kRunIntervalUs = 2000;
```
> **说明**：周期常量（H104IMU.cpp:46，注释还给了缓冲区余量估算）：
^src-src-drivers-imu-hipnuc-h104-H104IMU-cpp-46

<a id="src-src-drivers-imu-hipnuc-h104-H104IMU-cpp-66"></a>
**↓ 文档在讲这里：**[`src/drivers/imu/hipnuc_h104/H104IMU.cpp:66`](h104_imu.md#^src-src-drivers-imu-hipnuc-h104-H104IMU-cpp-66)

```c
    63 │ 	_perf_resync(perf_alloc(PC_COUNT, "h104_imu: resync bytes")),
    64 │ 	_perf_read_errors(perf_alloc(PC_COUNT, "h104_imu: read errors")),
    65 │ 	_perf_reopens(perf_alloc(PC_COUNT, "h104_imu: port reopens")),
▶   66 │ 	_perf_overflow(perf_alloc(PC_COUNT, "h104_imu: rx overflow")),
    67 │ 	_start_time(hrt_absolute_time())
    68 │ {
    69 │ 	_parser.setCallback(&H104IMU::SampleTrampoline, this);
```
> **说明**：1 | 不调 set_error_count() | 投票器拿不到 ERR CNT；这路坏透了，sensors status 也显示正常 | work/PX4改造-索引与纪律.md §6 #4；对比 hxy 会调（HXY42688P.cpp:309） | ┃ 2 | _perf_overflow 分配了、打印了、从不递增 | 串口溢出永远计不到 | 同上 §4 第 13 条；H104IMU.cpp:66 分配 |
^src-src-drivers-imu-hipnuc-h104-H104IMU-cpp-66

<a id="src-src-drivers-imu-hipnuc-h104-H104IMU-cpp-104"></a>
**↓ 文档在讲这里：**[`src/drivers/imu/hipnuc_h104/H104IMU.cpp:104`](h104_imu.md#^src-src-drivers-imu-hipnuc-h104-H104IMU-cpp-104)

```c
   101 │ 	/* ★ 与 NuttX H7 驱动对齐（stm32_serial.c 的 case TCSETS 硬校验）：
   102 │ 	 *   (c_cflag & CSIZE) 必须是 CS8，否则 tcsetattr 一律 -EINVAL。
   103 │ 	 *   曾经漏了 CS8 ⇒ 10 个波特率全 EINVAL，看起来像"H104 没在答"。 */
▶  104 │ 	cfsetspeed(&t, static_cast<speed_t>(115200));   /* NuttX 的 cfsetspeed 接受原始波特率整数 */
   105 │ 	t.c_cflag = CS8 | CLOCAL | CREAD;
   106 │ 	t.c_iflag = 0;
   107 │ 	t.c_oflag = 0;
```
> **说明**：4 | X/Y 符号未用实物转动验证 | rc.board_sensors:118 自己标了"放飞前必须解决" | work/PX4改造-索引与纪律.md §8 #4 | ┃ 5 | 波特率硬编码 115200 | 提到 200/500/1000 Hz 必须先改这里 + 模块侧 SERIALCONFIG | H104IMU.cpp:104；提频上限见 work/review-03-H104提频.md |
^src-src-drivers-imu-hipnuc-h104-H104IMU-cpp-104

### `src/drivers/imu/hipnuc_h104/H104IMU.hpp`
<a id="src-src-drivers-imu-hipnuc-h104-H104IMU-hpp-65"></a>
**↓ 文档在讲这里：**[`src/drivers/imu/hipnuc_h104/H104IMU.hpp:65`](h104_imu.md#^src-src-drivers-imu-hipnuc-h104-H104IMU-hpp-65)

```c
    62 │ #include <px4_platform_common/px4_config.h>
    63 │ #include <px4_platform_common/px4_work_queue/ScheduledWorkItem.hpp>
    64 │ 
▶   65 │ class H104IMU : public px4::ScheduledWorkItem
    66 │ {
    67 │ public:
    68 │ 	H104IMU(const char *port, uint32_t device_id, enum Rotation rotation);
```
> **说明**：基类 | device::SPI + I2CSPIDriver<HXY42688P> | 无。class H104IMU : public px4::ScheduledWorkItem（H104IMU.hpp:65） |
^src-src-drivers-imu-hipnuc-h104-H104IMU-hpp-65

### `src/drivers/imu/hipnuc_h104/h104_imu_main.cpp`
<a id="src-src-drivers-imu-hipnuc-h104-h104-imu-main-cpp-57"></a>
**↓ 文档在讲这里：**[`src/drivers/imu/hipnuc_h104/h104_imu_main.cpp:57`](h104_imu.md#^src-src-drivers-imu-hipnuc-h104-h104-imu-main-cpp-57)

```c
    54 │ #include <px4_platform_common/log.h>
    55 │ #include <px4_platform_common/module.h>
    56 │ 
▶   57 │ /* device_id 的位布局（见 src/lib/drivers/device/Device.hpp 的 DeviceStructure）：
    58 │  *     devtype(8) | address(8) | bus(5) | bus_type(3)
    59 │  * 这里直接按布局拼，不依赖 device::Device 的可见性。
    60 │  * bus_type: 0=UNKNOWN 1=I2C 2=SPI 3=UAVCAN 4=SIMULATION 5=SERIAL 6=MAVLINK */
```
> **说明**：device_id 拼法（h104_imu_main.cpp:57 的注释直接给了位布局）：
^src-src-drivers-imu-hipnuc-h104-h104-imu-main-cpp-57

<a id="src-src-drivers-imu-hipnuc-h104-h104-imu-main-cpp-64"></a>
**↓ 文档在讲这里：**[`src/drivers/imu/hipnuc_h104/h104_imu_main.cpp:64`](h104_imu.md#^src-src-drivers-imu-hipnuc-h104-h104-imu-main-cpp-64)

```c
    61 │ static constexpr uint32_t kBusTypeSerial = 5;
    62 │ static constexpr uint8_t  kBusUSART1 = 1;
    63 │ 
▶   64 │ static uint32_t make_h104_device_id()
    65 │ {
    66 │ 	return (static_cast<uint32_t>(DRV_IMU_DEVTYPE_HIPNUC_HI04) << 24)
    67 │ 	       | (static_cast<uint32_t>(0) << 16)                 /* address */
```
> **说明**：probe | probe()（SPI 框架检查 ID） | 没有 probe（串口没有"握手 ID"这一步）⇒ 见 §5 的代价 | ┃ device_id | 由 SPI 框架拼 | 手拼：h104_imu_main.cpp:64 |
^src-src-drivers-imu-hipnuc-h104-h104-imu-main-cpp-64

<a id="src-src-drivers-imu-hipnuc-h104-h104-imu-main-cpp-100"></a>
**↓ 文档在讲这里：**[`src/drivers/imu/hipnuc_h104/h104_imu_main.cpp:100`](h104_imu.md#^src-src-drivers-imu-hipnuc-h104-h104-imu-main-cpp-100)

```c
    97 │ 
    98 │ extern "C" __EXPORT int h104_imu_main(int argc, char *argv[]);
    99 │ 
▶  100 │ int h104_imu_main(int argc, char *argv[])
   101 │ {
   102 │ 	const char *verb = (argc > 1) ? argv[1] : nullptr;
   103 │ 
```
> **说明**：基类 | device::SPI + I2CSPIDriver<HXY42688P> | 无。class H104IMU : public px4::ScheduledWorkItem（H104IMU.hpp:65） | ┃ 模块框架 | ModuleBase（module_start/module_stop/module_status） | 手写 h104_imu_main()，start/stop/status 三个分支自己写（h104_imu_main.cpp:100 起） |
^src-src-drivers-imu-hipnuc-h104-h104-imu-main-cpp-100

### `src/drivers/imu/hipnuc_h104/h104_protocol.hpp`
<a id="src-src-drivers-imu-hipnuc-h104-h104-protocol-hpp-46"></a>
**↓ 文档在讲这里：**[`src/drivers/imu/hipnuc_h104/h104_protocol.hpp:46`](h104_imu.md#^src-src-drivers-imu-hipnuc-h104-h104-protocol-hpp-46)

```c
    43 │  *   SOF 5A A5 | LEN u16 LE(1..512, 不含头/长度/CRC) | CRC u16 LE (CRC-16/XMODEM)
    44 │  *   | 数据域：tag 开头，HI91 tag=0x91，定长 76，整帧 82
    45 │  *
▶   46 │  * HI91 数据域（偏移相对数据域起点，全部小端）：
    47 │  *   0  tag u8 = 0x91
    48 │  *   1  main_status u16   ⚠️ 实测**不是**状态位（是 system_time 的确定性函数），本驱动不使用
    49 │  *   3  temperature i8    °C
```
> **说明**：校验 | CRC-16/XMODEM | h104_protocol.hpp:78,84-98 | ┃ 字段偏移 | tag@0 / 温度@3 / 时间@8 / acc@12 / gyr@24 … | h104_protocol.hpp:46；手册 HIP2:738-751 |
^src-src-drivers-imu-hipnuc-h104-h104-protocol-hpp-46

<a id="src-src-drivers-imu-hipnuc-h104-h104-protocol-hpp-248"></a>
**↓ 文档在讲这里：**[`src/drivers/imu/hipnuc_h104/h104_protocol.hpp:248`](h104_imu.md#^src-src-drivers-imu-hipnuc-h104-h104-protocol-hpp-248)

```c
   245 │ 		const float ax = read_f32(p + 12);      /* 右, G */
   246 │ 		const float ay = read_f32(p + 16);      /* 前, G */
   247 │ 		const float az = read_f32(p + 20);      /* 上, G */
▶  248 │ 		s.acc_m_s2[0] = ay * kStandardGravity;
   249 │ 		s.acc_m_s2[1] = ax * kStandardGravity;
   250 │ 		s.acc_m_s2[2] = -az * kStandardGravity;
   251 │ 
```
> **说明**：字段偏移 | tag@0 / 温度@3 / 时间@8 / acc@12 / gyr@24 … | h104_protocol.hpp:46；手册 HIP2:738-751 | ┃ 单位 | acc 用 G、gyr 用 deg/s ⇒ 驱动换算成 m/s²、rad/s | h104_protocol.hpp:248；手册 HIP2:754 |
^src-src-drivers-imu-hipnuc-h104-h104-protocol-hpp-248

### `src/drivers/imu/hxy/hxy42688p/HXY42688P.cpp`
<a id="src-src-drivers-imu-hxy-hxy42688p-HXY42688P-cpp-309"></a>
**↓ 文档在讲这里：**[`src/drivers/imu/hxy/hxy42688p/HXY42688P.cpp:309`](h104_imu.md#^src-src-drivers-imu-hxy-hxy42688p-HXY42688P-cpp-309)

```c
   306 │ 						(unsigned)SAMPLE_RATE_HZ,
   307 │ 						perf_event_count(_stale_sample_perf));
   308 │ 
▶  309 │ 					_px4_accel.set_error_count(perf_event_count(_bad_register_perf) + perf_event_count(_bad_transfer_perf)
   310 │ 								   + perf_event_count(_stale_sample_perf));
   311 │ 					_px4_gyro.set_error_count(perf_event_count(_bad_register_perf) + perf_event_count(_bad_transfer_perf)
   312 │ 								  + perf_event_count(_stale_sample_perf));
```
> **说明**：1 | 不调 set_error_count() | 投票器拿不到 ERR CNT；这路坏透了，sensors status 也显示正常 | work/PX4改造-索引与纪律.md §6 #4；对比 hxy 会调（HXY42688P.cpp:309） |
^src-src-drivers-imu-hxy-hxy42688p-HXY42688P-cpp-309
