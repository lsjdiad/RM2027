# review-02 · 三问核查（H104 提频 / 陀螺量程 / 四路传感器健康）

- 审查人：code-auditor（**只读** PX4 源码；未运行 openocd、未烧写、未碰 ST-Link）
- 目标校准（用户）：**"让这套东西在 PX4 里真正能用"（能标定、能过 preflight、能解锁）**
> **【行号注记 · 本次更新】** 本文所有 PX4 源码行号已更新至 **`HEAD 9aeb3a0`**；
> 换算依据见 `PX4改造-索引与纪律.md` **§2 末的行号换算注**（该文档已并入原教学日志）。
> ⚠️ 漂移**随插入位置累积、不是加一个常数**：`HXY42688P.cpp`（基准 `363de64`，798 行）
> **≤580 行为 0、文件尾部最多 +41**；`rc.board_sensors` 第 62 行以后统一 **+23**；
> `HXY42688P_registers.hpp` 只有位域那两行 **+9**；
> 而 `default.px4board`、`IST8310.cpp`、`SPA06.cpp`、`af9838.cpp`、`H104IMU.cpp`、
> `h104_protocol.hpp` **零漂移**（可直接引用）。
> **本次只改行号**：条目中引用的代码/命令**文本**保持报告写作当时的样子
> （部分内容此后已被修复，如 `-R 0`→`-R 6`、位域 `Bit4`→`Bit3` 与 `0x17`→`0x0F`、
> 标度改用写入值、`GYR_CONF` 补写），**全部结论与判定仍以本文原有论证为准，未作改动。**

- 出处约定同 `review-01`：`HXY:<行>` / `IST:<行>` / `HIP:<行>` / PX4 源码 `<路径>:<行>`

---

# 第 0 部分 · 按"卡不卡飞行使用"排序的结论（先看这张表）

排序依据：① 标定过不了 ② preflight 报红/拒解锁 ③ 姿态/轴错；风格与可选优化放最后。

| 优先级 | 事项 | 卡在哪 | 证据 | 谁来修 |
|---|---|---|---|---|
| 🔴 **P0** | **加计/陀螺轴向（`-R`）没定死** | **①标定直接过不了** | 六面标定的六个面判定**只看符号、不看幅值**（`accelerometer_calibration.cpp:222-273`），所以报 `[cal] accel 0 invalid X-axis, check rotation`（`:231,239`）是**方向错**，**标度错（1.75 倍）不可能造成它**。而 `rc.board_sensors:61` 自己把 `-R 0` 标注为占位 TODO | Lead：用实物六个姿态逐个核对，定出 `-R`（枚举见 `src/lib/conversion/rotation.h:53-68`，如 `YAW_180=4`、`ROLL_180=8`、`PITCH_180=12`） |
| 🔴 **P0** | **标定三件套一次都没做** | **①②双双卡死** | `Accel 0 / Gyro 0 / Compass 0 uncalibrated`（`work/spi-runtime/README.md:26`）。未标定会直接触发 `Preflight Fail: Compass %u uncalibrated`（`magnetometerCheck.cpp:109-119`）与加计/陀螺的 arming check | Lead：`COM_ARM_IMU_ACC/GYR` 阈值只在标定之后才有意义 |
| 🟠 **P1** | **HXY 加计 Y 轴零点被 1.7512 放大到 1.20 m/s²** | **②preflight 贴线报红** | 实测零点 574 码（`定案-1.77倍…:28`）× 标称 0.0011971 = 0.687 m/s²，**乘 1.7512 后 1.203 m/s²**；两路差的一半 ≈ **0.69 m/s²**，紧贴 `COM_ARM_IMU_ACC = 0.7`（`commander_params.yaml:225-238`）| 标定（扣零点）即可解决；顺序必须是 **先定标度 → 再六面标定** |
| 🟠 **P1** | **HXY 加计标度 1.7512 未经独立验证** | ③姿态/EKF 观测量 | `review-01 §5.2`：证据未落盘、拿数的脚本没带净化、四档"否掉二倍"的推理数学上简并 | review-02 问题 2 的实验 B |
| 🟠 **P1** | **两路 IMU 的机体系差一个绕 Z 的 90° 旋转** | ②`Accel 0/1 inconsistent` | hxy 输出 `(x,−y,−z)`（`HXY42688P.cpp:607-608`）而 h104 输出 `(y,x,−z)`（`h104_protocol.hpp:248-250`）⇒ 水平分量互相旋转 90° | 六面标定会给每路解出各自的 T 矩阵 ⇒ **标定能吸收它**；但**标定完成前**这条会一直报 |
| 🟡 **P2** | **磁力计 `\|B\| ≈ 0.26 G` 只有当地地磁的 ~1/2** | ②（有 GNSS 时） | 见问题 3 的 §3.3 | 先测清是"场真的弱"还是"标度差 2 倍" |
| 🟡 **P2** | `af9838` 驱动不校验 ID，且被 Kconfig `select` 编进固件 | ②（可能被误启动） | `af9838.cpp:74-78`；`default.px4board:33-34,44-47` | 不要 `af9838 ... start`；或在 `rc.board_sensors` 里保持只启动 ist8310 |
| 🟡 **P2** | `h104_imu` **从不 `set_error_count`**，且**无器件身份校验** | ②健康度上报失真 | 全文件无 `set_error_count`（`H104IMU.cpp` grep 为空）；容器里任何 HiPNUC 模块只要发 HI91 就会被接受 | 加 identity（`LOG VERSION` 的 `PNAME`）与 error_count |
| 🟢 **P3** | H104 提频 100→200/400 Hz | 不卡能用，是性能 | 见问题 1 | 按问题 1 的步骤 |
| 🟢 **P3** | 陀螺量程档位扫描、FIFO、`>>4`、`Sensor_Time` 等 | 不卡能用 | `review-01` 漏项表 | 排期做 |

> 一句话：**先解 P0 的轴向 + 补标定，再谈标度精度。** 现在"1.75 倍"挡在路中间，但它**不是**标定失败的原因（下面 §2.6 有代码级证据）。

---

# 第 1 部分 · 问题 1：H104 有没有更高反馈频率的模式？

## 1.1 手册里"输出速率"相关条款全穷举

| 条款 | 内容（手册原文要点） | 出处 |
|---|---|---|
| 默认输出 | 出厂默认在 **COM1 与 COM2 以 100 Hz 输出 HI91** | `HIP:222`、`HIP:1404` |
| 帧类型 | 只有两种周期帧：**HI91**（定长浮点）与 **HI83**（可配置变长） | `HIP:243` |
| 设置命令 | `LOG [<COM>] <MSG> <TYPE> <VALUE>`；周期输出**仅支持 COM1 与 COM2** | `HIP:240-242` |
| 周期取值 | `ONTIME <秒>`：**推荐 `0.001`（1 kHz）~ `1`（1 Hz），`0` 关闭** | `HIP:245` |
| 示例 | `LOG HI91 ONTIME 0.01` = 100 Hz；`LOG COM2 HI91 ONTIME 0.002` = **500 Hz，须先把 COM2 提到 921600**；`LOG HI91 ONTIME 0` = 关闭 | `HIP:249-255` |
| 触发模式 | `ONMARK 1` = SYNC_IN 脉冲触发（每上升沿一帧）；`ONMARK ONCE` = 软件触发一次 | `HIP:246-247` |
| **带宽告警** | 「HI91 在 **115200 bps 下最高约 100 Hz**，500 Hz 需要 **460800 bps 以上**，建议 921600」；**超带宽的设置会被拒绝或造成丢帧** | `HIP:259-260` |
| 波特率档位 | `SERIALCONFIG [<COM>] <BAUD>`，10 档：4800 / 9600 / 19200 / 38400 / 57600 / 115200 / 230400 / 256000 / 460800 / 921600；改档步骤 1~4（记录→发命令（旧波特率回 OK）→主机切档→`LOG COMCONFIG` 确认→`SAVECONFIG`） | `HIP:224-238` |
| 带宽公式 | `最大帧率(Hz) ≈ (波特率/10) / 单帧字节数`；**建议再留 10~20% 余量** | `HIP:1381-1389` |
| **带宽表** | HI91 单帧 **82 字节**：9600→10 Hz、**115200→100 Hz**、230400→250 Hz、460800→500 Hz、921600→1000 Hz | `HIP:1391-1393` |
| HI83 帧长 | 固定头 8 字节 + 按 `data_bitmap` 选段；bit0=acc(12B)、bit1=gyr(12B)、bit2=mag(12B)、bit3=rpy(12B)、bit4=quat(16B)、bit5=sys_time(8B)…；公开掩码 `0x00000FFF` | `HIP:745-771` |
| 单位差异 | HI91：acc = **G**、gyr = **deg/s**；HI83：acc = **m/s²**、gyr = **rad/s** | `HIP:739` |
| 读回单位 | `LOG COMCONFIG` 的 `ONTIME` 单位是**毫秒**，设置命令是**秒** | `HIP:283-284` |
| 立即生效 | 数据帧输出开关/周期/触发方式"立即生效"（不用重启） | `HIP:206` |
| 保存 | 波特率/输出配置等需 `SAVECONFIG` 才掉电保持 | `HIP:236`、`HIP:207` |

## 1.2 理论带宽计算（115200 8N1，每字节 10 bit）

| 帧型 | 单帧字节 | 115200 理论上限 | 手册推荐值 | 200 Hz 需要 | 400 Hz 需要 |
|---|---|---|---|---|---|
| **HI91**（在用） | 82 | **140.5 Hz** | **100 Hz** | **230400 bps**（23.04 kB/s，占 66%） | **460800 bps**（占 71%） |
| HI83 `MAP=0x0000001F`（acc+gyr+mag+rpy+quat） | 6+8+64 = 78 | 147.7 Hz | — | 460800 | 921600 |
| HI83 `MAP=0x00000003`（**只留 acc+gyr**） | 6+8+24 = **38** | **303.2 Hz** | — | **115200 就够**（占 66%） | 230400 |
| HI83 `MAP=0x00000001`（只留 acc） | 6+8+12 = **26** | **443.1 Hz** | — | 115200（占 45%） | 115200（占 90%，不建议） |

> 结论：**当前 100 Hz 恰好就是 115200 bps 下 HI91 的天花板**（手册表给 100 Hz，理论上限 140 Hz，按"留 10~20% 余量"的规则也该停在 100 Hz）。
> ⇒ **要提频，必须动波特率；除非改走 HI83 精简 `MAP`。**

## 1.3 现有驱动的读取路径能不能跟上？

| 环节 | 现状 | 出处 | 更高频率下够不够 |
|---|---|---|---|
| 打开端口 / 波特率 | **硬编码 115200** | `H104IMU.cpp:104` | ❌ **提频必须改这里**（或加参数） |
| 读取周期 | `kRunIntervalUs = 2000`（2 ms ⇒ 500 Hz 轮询） | `H104IMU.cpp:49` | ✅ 200/400 Hz 都够（每轮只需处理 1~2 帧） |
| 单轮读取量 | 最多 4 次 × 256 B，且**读不满 256 就 break** | `H104IMU.cpp:50-51,217-241` | ⚠️ 有效吞吐上限 ≈ 256 B / 2 ms = **128 kB/s**。200 Hz（16.4 kB/s）余量 7.8×；400 Hz（32.8 kB/s）余量 3.9×；**1000 Hz（92 kB/s）只剩 1.4×，必须同时把周期调到 1 ms 或把 `kReadChunk` 调大** |
| NuttX RX 缓冲 | 600 字节（`CONFIG_USART1_RXBUFSIZE=600`） | `nuttx-config/nsh/defconfig:224`；驱动注释 `H104IMU.cpp:46-48` | ✅ 230400 下 600 B = 26 ms 余量（2 ms 轮询，13×）；921600 下 6.5 ms 余量（3×） |
| 解析器缓冲 | `kAccSize = 1024`，`feed()` 自动分片 | `h104_protocol.hpp:262`、`:147-163` | ✅ 与速率无关 |
| 丢字节/溢出计数 | **`_perf_overflow` 注册了但从不 `perf_count()`** | `H104IMU.cpp:66,292`（全文件无递增） | ❌ 提频后最该看的指标是空的（`review-01` L12） |
| 采样时间戳 | 用 `hrt` 时刻，不用模块 `system_time` | `H104IMU.cpp:164-173` | ⚠️ 提频后 jitter 占比升高；建议顺带把 `system_time` 的增量做成丢帧统计 |

## 1.4 结论

> **能提。瓶颈 = ①模块串口波特率（115200 就是 HI91@100 Hz 的硬上限）②驱动里硬编码的 115200；次要瓶颈 = 驱动的单轮读取量（128 kB/s 天花板，只影响 ≥500 Hz）。**

**需要改 Y（按优先级）：**

| Y | 内容 | 位置 |
|---|---|---|
| Y1 | 模块侧：`SERIALCONFIG` 升到 **230400**（→250 Hz）或 **460800**（→500 Hz） | 模块侧，用 `h104cap ask` 即可（**不需要 ST-Link**） |
| Y2 | 模块侧：`LOG HI91 ONTIME 0.005`（200 Hz）/ `0.0025`（400 Hz）/ `0.002`（500 Hz），再 `SAVECONFIG` | 同上 |
| Y3 | 驱动侧：`cfsetspeed(115200)` → 与模块一致（或用参数 `-b`） | `H104IMU.cpp:104` |
| Y4 | 驱动侧（≥500 Hz 才需要）：`kRunIntervalUs` 2000→1000，`kReadChunk` 256→512 | `H104IMU.cpp:49-51` |
| Y5 | 驱动侧：把 `_perf_overflow` 接上（或删掉），提频前先把观测口子打开 | `H104IMU.cpp:66,292` |
| Y6（可选，不改波特率） | 改走 HI83 `MAP=0x00000003`：帧长 38 B ⇒ **115200 下就能跑 200 Hz**。代价：解析器要按 `data_bitmap` 做变长解析（`HIP:745` 明确要求），并换单位 m/s²、rad/s（`HIP:739`） | `h104_protocol.hpp` |

对飞控的意义（写死成数字）：

| 用途 | 频率要求 | 出处 |
|---|---|---|
| 角速率环（内环）发布率上限 | `IMU_GYRO_RATEMAX` **缺省 400 Hz**，可选 100/250/400/800/1000/2000 Hz | `src/modules/sensors/vehicle_angular_velocity/imu_gyro_parameters.yaml:90-113` |
| EKF2 | 代码里**没有硬性最低频率**（`VehicleAngularVelocity.cpp:116-131` 只要求 10 Hz < rate < 10 kHz 才更新滤波器）；"≥50 Hz"是工程经验值，不是代码约束 | 同上 |
| ⇒ 结论 | **当前 100 Hz 会把内环压在 100 Hz**（若 h104 成为主导 IMU），远低于缺省 400 Hz；**提到 200~400 Hz 才有实际收益** | |

**可执行步骤清单（交给 Lead，全程不需要 ST-Link）**

前置：确认 SD 卡或 QGC 能落盘 console 输出；记录当前配置作回滚依据。

```text
# 0. 存档当前模块配置（回滚依据）
h104cap ask "LOG COMCONFIG"        # 期望: COM=COM1 BAUD=115200 MSG=HI91, ONTIME=10
h104cap ask "LOG VERSION"          # 期望: PNAME=HI04M0-000 ...

# 1. 先让驱动让开串口（否则驱动会把 ASCII 应答当二进制流吃掉）
h104_imu stop

# 2. 静流（不然命令应答被 100Hz 数据帧刷屏）
h104cap ask "LOG DISABLE"

# 3. 升波特率（/dev/ttyS0 = 模块当前连接口 = COM1，实测 LOG COMCONFIG 报 COM=COM1）
h104cap ask "SERIALCONFIG 230400"   # 模块在【旧波特率】回 OK，然后立即切换
# 4. 主机切到新波特率并确认
h104cap ask -b 230400 "LOG COMCONFIG"     # 期望: BAUD=230400
# 5. 设 200 Hz（ONTIME 单位是秒）
h104cap ask -b 230400 "LOG HI91 ONTIME 0.005"
# 6. 保存 + 读回确认
h104cap ask -b 230400 "SAVECONFIG"
h104cap ask -b 230400 "LOG COMCONFIG"     # 期望: ONTIME=5

# 7. 改驱动 cfsetspeed 到 230400，重编、烧写（Lead 负责）
# 8. 起来后看帧率
h104_imu start
h104_imu status      # 期望: 发布帧率 ≈ 200.0 Hz；CRC坏 = 0；"重同步跳字节"不随时间线性增长

# 回滚
h104cap ask -b 230400 "SERIALCONFIG 115200"
h104cap ask -b 115200 "LOG HI91 ONTIME 0.01"   # 注意：切回 115200 后主机也要切回
h104cap ask -b 115200 "SAVECONFIG"
```

**判据（写死）**
1. 实测帧率 = 设定值 **±1%**（200 Hz 时 `h104_imu status` 报 198~202）；
2. `CRC坏 = 0` 且 `重同步跳字节` 在 60 s 内增长 < 100（正常应为个位数，只在开机同步时跳）；
3. 两路 `sensor_gyro` 的 `timestamp_sample` 差值分布无长尾（>20 ms 的间隔应 < 1%）。

---

# 第 2 部分 · 问题 2：陀螺仪量程是否准确、有没有正常工作

## 2.1 手册逐条核对（`GYR_RANGE` / `GYR_CONF` / 规格）

| 项 | 手册 | 出处 | 驱动 | 判定 |
|---|---|---|---|---|
| `GYR_RANGE(0x43)` 位图 | `OIS_RANGE` 在 **B3**（列对齐实测），`FS[2:0]` = B2:B0 | `HXY:1790-1793` | `registers.hpp:202` 写 `Bit4`、`:209` mask=`Bit4+Bit2+Bit1+Bit0` | ❌ **位与手册不符**（当前无后果，见 review-01 L3） |
| FS 编码 | `000`=±2000dps、`001`=±1000、`010`=±500、`011`=±250、`100`=±125 | `HXY:1795-1801` | `registers.hpp:203-208`；`HXY42688P.cpp:724-744` | ✅ 一致 |
| 灵敏度 | `GSo4` = **61 mdps/LSB**（±2000dps 档） | `HXY:252` | `HXY42688P.cpp:747` `radians(2000)/32768` = 0.0010654 rad/s/LSB = **16.384 LSB/dps** | ✅ `32768/2000dps = 16.384` 与 61.04 mdps/LSB 自洽 |
| 灵敏度误差 | `GSERR` = **±1.5%**（±2000dps **加校准**） | `HXY:256` | 无校验 | ⚠️ 未使用 ⇒ **这是陀螺增益验收该用的门限** |
| 零漂 | `GTyOff` = **±0.2 dps**；温漂 ±0.05 dps/℃ | `HXY:257-262` | 无校验 | ⚠️ 未使用 ⇒ 静态零偏门限 |
| 噪声密度 | `GN` = 6（单位在提取文本里乱码） | `HXY:267-269` | 无校验 | ⚠️ 量级参考 |
| `GYR_CONF(0x42)` 位图 | B7 FILTER_PERF / B6 NOISE_PERF / B5:B4 BWP[1:0] / B3:B0 ODR[3:0] | `HXY:1735-1739` | `registers.hpp:174-187` | ✅ 一致 |
| ODR 表 | `0110`=25Hz … `1100`=1600Hz、`1101`=3200Hz；**200Hz 以上不支持低功耗模式** | `HXY:1772-1781` | 用 `1100`（1600 Hz） | ✅ |
| BWP 表 | 只有 `00/01/10`；`00`=OSR4_AVG1（平均次数=3.2kHz/ODR ⇒ 1600Hz 时 2 次） | `HXY:1754-1769` | 用 `00` | ✅ |
| **备注①** | `GYR_NOISE_PERF` 切换**必须先把 ACC+GYR 关掉**再配，然后再打开 | `HXY:1750-1751` | `HXY42688P.cpp:340-343` 照做 | ⚠️ 照做了但仍读回 `0xA9` ⇒ 根因未定位（review-01 R1） |
| **备注②** | 表外组合会被**自动转成默认 `0xA9` 并置 `GYR_CONF_ERR=1` | `HXY:1782` | `CheckDataStat()` `:511-532` 会报 | ⚠️ **这条才是"0x42 读回 0xA9"的现成解释**，项目"假说已被否证"的结论不成立 |
| 读数正确性 | 数据是 2 的补码、高字节在前 | `HXY:1083-1093` | `combine()` `:76-79` | ✅ |

## 2.2 `SetGyroScale()` 与 `SetAccelScaleAndRange()` 的差别（Lead 点名要核）

```cpp
// 陀螺：HXY42688P.cpp:710-753
const uint8_t GYR_RANGE = RegisterRead(Register::GYR_RANGE) & GYR_RANGE_BIT::gyr_fs_mask;  // & 0x07
float range_rad_s = math::radians(2000.f);      // 缺省/未知都落到 2000dps
switch (GYR_RANGE) { case 1000/500/250/125 ...; case 2000: default: break; }
_px4_gyro.set_range(range_rad_s);
_px4_gyro.set_scale(range_rad_s / 32768.f);
```

**核对结论（三点，都有代码出处）：**

1. **是的，它只按"算出来的标称值"定标**——一旦 `range_rad_s` 确定，`scale = range/32768` 就是纯算术，**没有**加计的 `ACCEL_GAIN_CORRECTION` 那种修正常数。这与加计那边的结构**不同**（加计会乘一个实测修正），风险方向也不同：陀螺的风险是"**量程档位读错 ⇒ 标度差 2 的幂次**"。
2. **`& gyr_fs_mask`(0x07) 之后 `5/6/7` 和 `0xFF` 都会落到 `default:` ⇒ 静默当成 ±2000dps**（`:705-707`）。所以一次坏读不会被发现，只会让标度**悄悄差 2/4/8 倍**。
3. **而且这次读取完全没有被校验**：`GYR_RANGE` 的 `set_bits = 0x00`（`registers.hpp:203`），`CheckRegisterConfig()` 的判据是 `(set_bits == 0) || ...`（`HXY42688P.cpp:483`）⇒ **`0x43` 永远判 OK**（只要不是 `0xFF`）。这是加计那个坑的同类，但**更严重**（加计至少 `set_bits=0x01`，能挡住一半）。
4. 顺带核实：`set_range()` 与 `set_scale()` 的调用顺序**不会**造成 clip 阈值错误——`PX4Gyroscope::set_scale()` 内部会在更新 `_scale` 后调 `UpdateClipLimit()`（`PX4Gyroscope.cpp:119-132`），`_clip_limit = |_range/_scale*0.999|`（`:225-229`）。加计同理（`PX4Accelerometer.cpp:119-132,226-230`）。所以**裁剪阈值这一项陀螺是干净的**；加计那边的问题只在"忘了把 range 一起乘 1.7512"（已修）。

## 2.3 为什么不走"和手册比差多少"

- 项目的"与手册只差 0.06%"是拿 `32768/2000` 这个**算术恒等式**去比手册的**圆整 typ 值 61 mdps/LSB**（`HXY:252`）——这两个量之间根本不存在"误差"，比出来的 0.06% 不是证据（`review-01` 矛盾 #4）。
- 加计上，"手册为基准"已被证伪（实测偏 43% ≫ 手册 ASERR ±2%）。同一套逻辑不能只用在陀螺上。

## 2.4 验证方案 A：量程档位扫描（判"档位译码/写入对不对"，**不能用它判绝对增益**）

**原理**：同一段转动下 `∫raw dt = θ · 32768 / FS_dps`。所以 `FS_dps` 改一档，`∫raw dt` 应成反比变化；且 `∫raw dt × FS_dps` 应为常数。

- 板子怎么摆：桌面平放，**绕垂直轴（Z）转**（比绕水平轴容易保持不倾倒）。板子下垫一张纸画 0° 标记，每次转到同一标记（转整圈数 3 圈）。
- 怎么改量程（二选一，**推荐 (a)**）：
  - **(a) 让 Lead 在 `hxy42688p` 加一个临时 CLI 参数**（他正在改这个驱动），如 `-G <0..4>` 映射到 `GYR_RANGE` 的 `FS[2:0]`，并让 `SetGyroScale()` 用**写入值**而不是回读值。这样数据全程走 DMA 路径，`listener` 直接可读，**干净**。
  - **(b) ST-Link 手写 `0x43`**：必须先做净化前奏（`SPI1_CR1 = 0x00001200`：停 `SPE` 但 `SSM=1,SSI=1`；关 SPI 的 DMA 请求位；清 `IFCR`；排空 RX FIFO；再写回 `0x00001201`），每个寄存器**连读两次不一致就重试**，且**绝不写 `CR1=0`**。参考 `work/spi-runtime/quiet-test.tcl:26-42`。改完要**重启驱动**才会重新定标。
- 敲什么命令：每档 `hxy42688p stop && hxy42688p -s -b 1 -G <n> start`，然后 `listener -n 1200 sensor_gyro`（或用 logger 抓 ULog），手工转 3 圈。
- 期望看到：`codes(FS=000) : codes(FS=011) = 8.00 : 1`（2000/250）；`∫raw dt × FS_dps` 五档相对散差 ≤ 2%。
- 判据：
  - **通过**：所有相邻档比值与标称比值偏差 ≤ 2%，且各档回读 = 写入值；
  - **不通过**：任一档偏差 2~5% → 存疑；>5% → 该档的写入/译码有问题，先把 `GYR_RANGE` 掩码（B3 vs B4）和"信任回读"两个问题修掉再测。
- ⚠️ **这条测不出绝对增益**：一个统一的乘性增益误差会在比值里完全抵消。所以必须配 B。

## 2.5 验证方案 B：两路积分比对（判**绝对**增益，H104 当参照）★ 主实验

- 板子怎么摆：平放桌面，绕**垂直轴 Z** 转；转速 ~1 rev/s（≈360 dps，远低于 ±2000dps，避免饱和）；每次转 **≥3 整圈**（≥1080°）以摊薄零偏。**不要手拿倾斜**（H104 在机架上、两路是独立器件，倾斜会串进水平轴）。
- 两路怎么同时取：**必须走 PX4 的 DMA 路径，不要用 ST-Link 读原始码**（本项目已证 ST-Link 手工读脏：静止陀螺 X 轴跳 ±253、`|a|` 两次差 11%）。
  - 首选：`logger start` → 转 → `logger stop`，取 `.ulg`（ULog 里两个 `sensor_gyro` 实例时间轴一致）。
  - 没有 SD 卡时：QGC MAVLink Console 里 `listener -n 3000 sensor_gyro`，把输出**落盘成文本**再离线积分。
- 期望看到：
  - 每路 z 轴 `θ = ∫ω_z dt`；转的圈数相同 ⇒ 两路 θ 应几乎相等；
  - 起止各 2 s 静止时 `|ω| < 0.02 rad/s`（静止门）。
- 判据（写死）：
  | 结果 | 判定 |
  |---|---|
  | `\|θ_hxy/θ_h104 − 1\| ≤ 0.02` | ✅ **准**（2% 门限 ≈ 手册 GSERR ±1.5% 的两倍余量，`HXY:256`） |
  | `0.02 < ... ≤ 0.05` | ⚠️ 存疑，需加转圈数/换轴复测 |
  | `> 0.05` | ❌ **不准**：查 `GYR_RANGE` 回读、`SetGyroScale` 是否用了回读值、以及 `0x42` 是否真是 `0xCC` |
  | 两路 `timestamp_sample` 差 > 5 ms 的样本 | 该样本作废（插值到 1 kHz 公共栅格再积分） |
  | 60 s 静止 `|mean(ω)| > 0.2 dps`（=0.0035 rad/s） | 先修零偏（陀螺标定）再谈增益，`HXY:258` |
- 反证用（把"如果陀螺也有加计那个 1.75 倍错"变成可判决的量）：若陀螺真带 1.7512 倍错，`θ_hxy/θ_h104` 会是 **1.75**；若陀螺只有倒数的 0.5665 倍，会是 **0.57**。两者都远离 1.00 ⇒ 本实验**一眼可判**，且不依赖"手册为基准"。
  （注：项目此前用 `listener` 两条报文比 z 分量得到 1.104，但两条 `timestamp_sample` 差 42 ms、手转时角速度在变 —— 那是"不同时刻的两个数"，不是积分比对，证据强度不足。本实验用积分就是为了消掉这一项。）

## 2.6 附带：六面标定报 `accel 0 invalid X-axis` 的**真因不是标度**（重要更正）

`accelerometer_calibration.cpp:222-273` 的六个面判定**只看符号**：

```cpp
case ORIENTATION_TAIL_DOWN:     // 期望 [ g, 0, 0]
    if (accel_ref[i][TAIL_DOWN][0] < 0.f) { "[cal] accel %d invalid X-axis, check rotation" -> error }
case ORIENTATION_NOSE_DOWN:     // 期望 [-g, 0, 0]
    if (accel_ref[i][NOSE_DOWN][0] > 0.f) { ...invalid X-axis... }
... (Y/Z 同理)
```
（`accelerometer_calibration.cpp:229-273`）

⇒ **幅值完全不参与判定**，所以"加计标度少报 1.76 倍"**不可能**造成 `invalid X/Y/Z-axis`。
⇒ `work/spi-runtime/README.md:42-43`("上次失败时加计标度还是错的，现在修好了，很可能 front 面就过了")**在代码层面不成立**：那条报错是**方向**问题（`-R` / 挂装轴向），只能靠核对姿态或改 `-R` 解决。
⇒ **这是当前最该先解的一件事**（P0）。

---

# 第 3 部分 · 问题 3：两路 IMU + 磁力计 + 气压计是否都正常

## 3.1 逐路"证据 + 判定"

### 3.1.1 IMU #0 = `hxy42688p`（SPI1, CS=PB4, DRDY=PD6）

| 检查项 | 证据 | 判定 |
|---|---|---|
| 驱动存在 | `src/drivers/imu/hxy/hxy42688p/{HXY42688P.cpp,.hpp,_registers.hpp,hxy42688p_main.cpp,CMakeLists.txt,Kconfig}` | ✅ |
| 编进固件 | `default.px4board:22` `CONFIG_DRIVERS_IMU_HXY_HXY42688P=y`；`src/drivers/imu/hxy/CMakeLists.txt` → `add_subdirectory(hxy42688p)`；`CMakeLists.txt` 里 `px4_add_module(MODULE drivers__imu__hxy__hxy42688p MAIN hxy42688p ...)` | ✅ |
| 板级登记 | `boards/rm2027/fmu-h743/src/spi.cpp:107` `initSPIDevice(DRV_IMU_DEVTYPE_HXY42688P, CS{PB,4}, DRDY{PD,6})`（SPI1 只此一颗真正 probe 成功） | ✅ |
| 拉起命令 | `rc.board_sensors:85` `hxy42688p -s -b 1 -R 0 start` | ✅ |
| **probe 校验 ID** | `HXY42688P.cpp:195-200`：读 `WHO_AM_I(0x01)`，`!= 0x6A` 即 `PX4_ERROR` | ✅ **真校验** |
| 启动日志 | `hxy42688p #0 on SPI bus 1`；`0x40=0x8C 0x41=0x01 0x42=0xCC 0x43=0x00 0x7D=0x0E 0x08=0x80 0x05=0x50`；`DATA_STAT(0x0B)=0x07` | ✅ |
| 活体/停滞保护 | `STALE_SAMPLE_LIMIT=100` 拍（`HXY42688P.hpp:92`）；连续无新样本 ⇒ 计数 + `Reset()`（`HXY42688P.cpp:290-316`） | ✅ 有 |
| `error_count` 上报 | `:319-322` = `bad_register + bad_transfer + stale_sample` | ✅ 有（`duplicate`/`no_new_data` 未计入，属正常操作计数） |
| 未决问题 | ① 加计标度 1.7512 未独立验证（§2/问题 2）② `-R` 已从 0 改成 **6**（`ROTATION_YAW_270`，已上板）③ `GYR_CONF` 写不进去的根因（review-01 R1）④ `GYR_RANGE` 掩码与手册不符 + 该寄存器永不校验（L3/L4）⑤ **新增（2026-10-01 实测）：hxy 与 H104 逐轴比 = 1.007 / 0.888 / 0.779（三轴增益差 11~22%，见 §3.4）** | ⚠️ |
| **实测（2026-10-01）** | `[vehicle_imu] 0`：accel 间隔 **1000.0 us、SD 11.7 us**（抖动 1.2%）；`accel/gyro generation gap = 1`；driver `error_count = 2` | ✅ 时序好；⚠️ **注意：`error_count = 2` 是 `bad_register/bad_transfer/stale` 累计，说明 hxy 这路启动后出现过 2 次寄存器/传输类异常** |

### 3.1.2 IMU #1 = `h104_imu`（/dev/ttyS0 = USART1）

| 检查项 | 证据 | 判定 |
|---|---|---|
| 驱动存在 | `src/drivers/imu/hipnuc_h104/{H104IMU.cpp,.hpp,h104_protocol.hpp,h104_imu_main.cpp,test_h104_protocol.cpp}` | ✅ |
| 编进固件 | `default.px4board:24` `CONFIG_DRIVERS_IMU_HIPNUC_H104=y` | ✅ |
| 拉起命令 | `rc.board_sensors:119` `h104_imu start` | ✅ |
| **probe 是否校验 ID** | ❌ **没有 probe，也没有任何器件身份校验**：驱动只按 `SOF 5A A5` + `LEN` + `CRC-16/XMODEM` + `tag=0x91` 组帧（`h104_protocol.hpp:167-220`）。**任何 HiPNUC 模块只要在 100 Hz 发 HI91 就会被接受**；型号（HI04M0）此前是靠人工跑 `LOG VERSION` 读 `PNAME=HI04M0-000BU` 确认的（`work/spi-runtime/h104/h104-report.print.txt`） | ❌ **"只探应答、不验身份"**（与 `af9838` 同族问题） |
| 启动日志 | 第一帧 OK、`device_id=0x6400000d`、`uORB 实例 accel=1 gyro=1`、300 帧 CRC 好 300 / 坏 0、`24600/300 = 82.0 B/帧` | ✅ |
| 活体保护 | 连续 ~2 s 一个字节都没有 ⇒ 关掉重开端口（`H104IMU.cpp:245-260`） | ⚠️ 只防"串口死"，**不防"模块送常量帧/停更"**（无 stale 检测） |
| `error_count` 上报 | ❌ **全文件没有 `set_error_count`**（grep 为空）⇒ `sensor_gyro/sensor_accel` 实例 1 的 `error_count` **恒为 0** | ❌ **健康度上报失真** |
| 未决问题 | ① X/Y 符号未用实物转动验证（`rc.board_sensors:118`）② 与 hxy 的机体系差（`-r 0` 未验证）③ `_perf_overflow` 从不递增 ④ 提频（问题 1）⑤ **新增（2026-10-01 实测）：`[vehicle_imu] 1` 间隔 10000.0 us 但 SD 高达 562.2 us（抖动 5.6%）** | ⚠️ |
| **⚠️ `error_count = 0` 不能当"干净"的证据** | 该驱动的 `error_count` **恒为 0（因为它从不调用 `set_error_count`）** ⇒ **不要拿"H104 error_count=0 / hxy error_count=2"来比较两路谁干净**（上一行已列）。要比就比：`vehicle_imu` 的 generation gap、`h104_imu status` 的 `CRC坏/重同步跳字节`、`hxy42688p status` 的 `bad register/bad transfer/stale` | ❌ 这个对比目前**无效** |

### 3.1.3 磁力计 = `ist8310`（I2C4, 7bit 0x0C）

| 检查项 | 证据 | 判定 |
|---|---|---|
| 驱动存在 / 编进固件 | `src/drivers/magnetometer/isentek/ist8310/`；`default.px4board:47` + `CONFIG_COMMON_MAGNETOMETER=y`（`:33`，会 `select` 全部磁罗盘驱动） | ✅ |
| 总线声明 | `boards/rm2027/fmu-h743/src/i2c.cpp:76-79`：`initI2CBusInternal(2)`/`(4)` ⇒ **必须 `-I -b 4`**；`-X` 时 `I2CBusIterator` 不遍历 Internal 总线，循环体一次都不执行 | ✅ 与 `rc.board_sensors:90-98` 的分析一致 |
| 拉起命令 | `rc.board_sensors:105` `ist8310 -I -b 4 -a 0x0C -R 0 start`（**必须带 `-a 0x0C`**：驱动缺省 0x0E，见 `ist8310_main.cpp:52,111`） | ✅ |
| **probe 校验 ID** | `IST8310.cpp:95-115`：50 ms 内反复读 `WAI(0x00)`，必须 `== 0x10`（或 `0xA3`）；否则对 0x0C~0x0F 逐个写软复位再试 | ✅ **真校验**（`0xA3` 无手册出处：`IST:657-663` 只有 `10`） |
| 配置与手册一致 | `PDCNTL=0xC0`（手册 §3.1.1 建议，`IST:312`）；`AVGCNTL=0x24`（手册 §3.1.1 建议，`IST:313-315`）；`CNTL1=0x01` 单次测量（`IST:757-759`） | ✅ |
| **CNTL3 写没写？能不能回读？** | **写了，而且驱动自己回读校验**：`IST8310.hpp:106-112` 的 `_register_cfg` 第 2 条 = （`Register::CNTL3`，`set_bits` = `Z_16BIT`/`Y_16BIT`/`X_16BIT` 三位全置 = 0x70）；`Configure()` 先 `RegisterSetAndClearBits`（`IST8310.cpp:260-262`）、再 `RegisterCheck`（`:267-271`），读回值来自 **`CNTL3 = 0x0D`**（`registers.hpp:77`），要求 `(value & 0x70) == 0x70`（`:284-287`）。**因为 `Configure()` 返回 false 就不会进 `MEASURE`（`:160-176`），而实测该实例能出 `\|B\|` ⇒ 这 4 条 check（含 CNTL3）当时都是过的** | ✅ **Lead 的更正成立：CNTL3 确实写了** |
| ⚠️ 但这条回读**很脆** | ① `RegisterCheck` 失败只打 **`PX4_DEBUG`**（`IST8310.cpp:285,290`）⇒ 发布版日志里**看不见**；② **没有 `0xFF` 假通过保护**：`0xFF & 0x70 == 0x70` ⇒ 一次总线毛刺（MISO 恒高）也算"CNTL3 校验通过"（对比 hxy 驱动已修这一条：`HXY42688P.cpp:478-483`）；③ `RegisterRead` 单次读、无重试（`:297-306`）；④ `RegisterSetAndClearBits` 只在 `orig_val != val` 时才写（`:319-321`） | ❌ 需加固 |
| 手册缺口 | **`IST` 全文没有 `CNTL3(0x0D)` 的描述**（`IST:635-654` 的寄存器表里没有 0x0D，§6.4.x 也没有），也**没有"1320 LSB/Gauss"这个数**；手册只有 `SEN = 3.3 LSB/uT`、`RESO = 0.3 uT/LSB`（`IST:457-458`） | ⚠️ `1320` 只能靠 PX4 的注释（`IST8310.hpp` / `IST8310.cpp:273`）与"16 位 ⇒ 4× 分辨率"的推算自洽 |
| `error_count` | `IST8310.cpp:210` = `bad_register + bad_transfer` | ✅ |
| 活体保护 | `_failure_count > 10` ⇒ `Reset()`（`:224-232`）；每 100 ms 抽查一个配置寄存器（`:234-246`） | ✅ |

### 3.1.4 气压计 = `spa06`（I2C2, 0x77）

| 检查项 | 证据 | 判定 |
|---|---|---|
| 驱动 / 编进固件 | `src/drivers/barometer/goertek/spa06/`；`default.px4board:5` `CONFIG_DRIVERS_BAROMETER_GOERTEK_SPA06=y` | ✅ |
| 拉起命令 | `rc.board_sensors:110` `spa06 -I -b 2 -a 0x77 start`（驱动缺省 0x76：`spa06_main.cpp:52,111` ⇒ **必须显式 `-a 0x77`**） | ✅ |
| **probe 校验 ID** | `SPA06.cpp:156-157`：`get_reg(SPA06_ADDR_ID=0x0d) != SPA06_VALUE_ID=0x11` 即失败（`spa06.h:43,54`） | ✅ **真校验**（但失败只打 `PX4_DEBUG`，`:157`） |
| 启动日志 | `spa06 #0 on I2C bus 2 address 0x77`；`SCALED_PRESSURE` 0.8 Hz | ✅ |
| `error_count` | `SPA06.cpp:239` = `perf_event_count(_comms_errors)` | ✅ |
| **✅ 实测正常（2026-10-01 用户实测）** | `pressure 101965 Pa (1019.65 hPa)`、`temp 38.2 ℃`、`altitude -53.2 m`；`spa06: comms errors 0`；采样周期 **853.85 us 均值（min 849 / max 915，抖动 ±4%）** | ✅ **判定：正常，结案**（1019.65 hPa 属合理海平面气压；38.2 ℃ 偏高但与板温一致；采样抖动 4% 可接受） |
| 未决 | 采样率 0.8 Hz（`SPA06.hpp:117` `_measure_interval`）—— 高度融合偏低频，但够用，不卡 | 🟢 |

### 3.1.5 反面样板：`af9838`（**不校验 ID**，同族坑的实证）

| 项 | 证据 | 判定 |
|---|---|---|
| `af9838.cpp:67-86`：`probe()` 循环 3 次 `transfer(&REG_PCODE, 1, &id, 1)`，**只要传输成功就 `return PX4_OK`；读到的 `id` 从未与任何期望值比较**（`id` 甚至没参与判断） | `src/drivers/magnetometer/voltafield/af9838/af9838.cpp:74-78` | ❌ **只探应答，不验身份**（项目结论正确） |
| 是否可能被误启动 | `default.px4board:33-34,44-47`：`CONFIG_COMMON_MAGNETOMETER=y` 会 `select` 全部磁罗盘驱动（含 af9838）⇒ **它一定编在固件里**；目前没被 `rc.board_sensors` 拉起 | ⚠️ 只要有人敲 `af9838 -I -b 4 start` 就会再次认错 | 

### 3.1.6 probe 严格性总表（`review-01`/`review-02` 的共同结论）

| 驱动 | probe / 身份校验 | 失败日志可见性 | 0xFF 假通过保护 |
|---|---|---|---|
| `hxy42688p` | ✅ 校验 `WHO_AM_I==0x6A`（`HXY42688P.cpp:195-200`） | ✅ `PX4_ERR`（`:228,497`） | ✅ 有（`:481`） |
| `ist8310` | ✅ 校验 `WAI==0x10`（`IST8310.cpp:100`） | ❌ `PX4_DEBUG`（`:285,290`） | ❌ 无 |
| `spa06` | ✅ 校验 ID==0x11（`SPA06.cpp:156`） | ❌ `PX4_DEBUG`（`:157`） | ❌ 无 |
| `h104_imu` | ❌ **无身份校验**（只验 CRC+tag，`h104_protocol.hpp:167-220`） | ✅ 有（`PX4_ERR`） | — |
| `af9838` | ❌ **不校验 ID**（`af9838.cpp:74-78`） | ✅ `PX4_ERR` | — |

## 3.2 跨路一致性检查在 PX4 里由谁做、阈值多少

| 项 | 位置 | 说明 |
|---|---|---|
| 计算 | `src/modules/sensors/voted_sensors_update.cpp:449-472` | `_accel_diff[i] = 0.95*_accel_diff[i] + 0.05*(accel_i − 所有 IMU 均值)`（一阶低通）；陀螺同法（`:474+`） |
| 上报 | `voted_sensors_update.cpp:415-429` | `sensors_status_imu` 的 `accel_inconsistency_m_s_s[]` / `gyro_inconsistency_rad_s[]`（取 `norm()`） |
| 判定（加计） | `imuConsistencyCheck.cpp:50-76` | `worst_accel > COM_ARM_IMU_ACC` ⇒ `Preflight Fail: Accel %u inconsistent - check cal` |
| 判定（陀螺） | `imuConsistencyCheck.cpp:81-107` | `worst_gyro > COM_ARM_IMU_GYR` ⇒ `Preflight Fail: Gyro %u inconsistent - check cal` |
| **阈值** | `commander_params.yaml:225-253` | **`COM_ARM_IMU_ACC = 0.7 m/s²`**（范围 0.1~1.0）；**`COM_ARM_IMU_GYR = 0.25 rad/s`**（范围 0.02~0.3） |
| 只在未解锁时检查 | `imuConsistencyCheck.cpp:40` | `context.isArmed()` ⇒ 只影响 preflight |

**对"只报 Accel、从不报 Gyro"的解释（写清强度）：**
- 一致性判据是"与**均值**的偏差"。两个传感器互相不一致时**两个都会被点名**（各偏一半）⇒ 报 `Accel 0` 和 `Accel 1` 两条 = 两路真的不一致，不是某一个坏。
- 加计：hxy 的**零点**在静止平放时是 `(56, 574, 4642)` 码（`定案-1.77倍…:28`）⇒ 乘 1.7512 后 `(0.117, −1.203, −9.73) m/s²`；h104 约 `(0.02, 0.17, −9.83)`；两者差 `|Δ| ≈ 1.38`，**各自偏离均值 0.69 m/s²**，而门限是 0.7 ⇒ **贴线通过/轻微倾斜即报红**。
- 陀螺：静止时两路都 ≈ 0 ⇒ 差值本来就小；"从未报 Gyro inconsistent"**只证明了两路在静止时一致**，而静止时陀螺恒为 0 ⇒ 这条证据几乎不含信息量（真正的检验要在转动中做，即问题 2 的实验 B）。
- ⇒ **结论**：`Accel 0/1 inconsistent` 与"1.75 倍标度"和"零点未标定"都直接相关，**优先级高于陀螺**；并且在六面标定完成前它会一直存在（标定会给每路解出 offset + 3×3 矩阵，把那 90° 框架差和零点一起吸收）。

## 3.3 ✅ 磁力计：**已结案 —— 硬铁偏移，不是标度问题**（2026-10-01 实测）

> **标题与结论已按实测更新**（用户授权本轮修改本文件）。
> 原判"`|B|` 偏低约 2 倍 ⇒ 标度存疑"**作废**：那是**硬铁偏移未扣**造成的，标定后一切正常。

### 3.3.0 结案证据（用户实测）

```
sensor_mag 三轴: 0.1681, 0.0271, -0.4186   (Gauss)  ⇒ |B| = 0.452 G   ✅ 正常（当地 ~0.45~0.55 G）
已存在的标定:   offset [-0.060  0.027  0.184] (Gauss)
                scale  [ 0.932  0.987  1.058]
ist8310 计数器: bad register 0 / bad transfer 0                       ✅ 读取稳定
```

- **标定前 raw ≈ 0.25 G 是"硬铁未扣"**：驱动发布的 `sensor_mag` 是**未标定**值，
  板载铁磁件/电流回路形成的硬铁偏移会把三轴零点整体推偏，使 `|B|` 明显偏离真值；
  经 `offset [-0.060 0.027 0.184]` 修正后 = **0.452 G**，落在地磁场正常区间。
- ⇒ §3.3.2 里"标度差 2 倍"的假设 **(b) 排除**，"环境/偏移类"假设 **(a) 成立**，
  并进一步明确为**硬铁偏移**（不是"当地磁场低"，而是"没扣零点"）。
- ⇒ `review-01` §2.2 L9 与 §3 矛盾清单 #11 的相关表述按此结案；
  `rc.board_sensors:103-104` 那句"|B| 比中国地表偏低约 2× 但已落进标定窗口"应改为
  **"未标定时 |B| 偏低是硬铁偏移；标定后 0.452 G"**。

**仍保留的两条非阻塞项**：① `CNTL3(0x0D)` 与 `1320 LSB/Gauss` 在这本手册里查不到（手册缺口，见 §3.3.1）；
② `RegisterCheck` 无 `0xFF` 假通过保护、失败只打 `PX4_DEBUG`（`review-01` §2.2 L9 已列）。

### 3.3.1 先更正一条旧结论（Lead 指出的那条，我已按代码复核）

- ❌ 旧结论"PX4 的 ist8310 驱动从来没写过 CNTL3 ⇒ 停在 14 位 ⇒ 与 1320 LSB/G 差 4 倍"——**作废**。
- ✅ 事实：`IST8310.hpp:109` 里 `_register_cfg` 第 2 条就是 `{CNTL3, Z_16BIT|Y_16BIT|X_16BIT, 0}`；`Configure()`（`IST8310.cpp:257-276`）先写后读回校验；`CNTL3 = 0x0D`（`registers.hpp:77`）；`CNTL3_BIT::Z/Y/X_16BIT = Bit6/5/4`（`registers.hpp:130-132`）⇒ 写 `0x70`。
- ✅ 并且**可观测**：`Configure()` 未通过就不会进 `MEASURE`（`IST8310.cpp:160-176`），而实测该实例能持续发布 `|B|` ⇒ **CNTL3 的回读校验当时是过的**。
- ✅ 因此"16 位模式 ⇒ 0.3/4 = 0.075 µT/LSB ⇒ 13.3 LSB/µT ⇒ ≈1320 LSB/G"这条链与 `set_scale(1.f/1320.f)`（`IST8310.cpp:273`）**自洽**，那个"4 倍分歧点"**不是分歧点**。
- ⚠️ 但两点要标在案：**(a)** 手上这本手册**根本没有 CNTL3 的描述**（`IST:635-654` 无 0x0D），所以 1320 这个数**无法用手册复核**，只能靠"16 位=4× 分辨率"的推算与 PX4 上游注释；**(b)** 该回读是"单次 + 无 0xFF 保护 + 失败只打 DEBUG"（见 §3.1.3），**能过 ≠ 强证据**。

### 3.3.2 `|B| ≈ 0.26 G` 到底能不能解释

先把数摆清楚（`sensor_mag` 单位是 Gauss，`PX4Magnetometer.cpp:98-100` `report.x = x * _scale`）：

| 假设 | 真实 LSB/G | 由 `\|B\|=0.26 G` 反推的真实场强 | 与当地 ~0.45–0.55 G 比较 |
|---|---|---|---|
| **CNTL3 生效（16 位，1320 LSB/G）** | 1320 | `0.26 G` ⇒ **~26 µT** | **低 ~1.9 倍** |
| CNTL3 未生效（14 位，330 LSB/G） | 330 | `0.26 × 1320/330 = 1.04 G` ⇒ ~104 µT | 高 ~2 倍 |
| 真实灵敏度恰为 660 LSB/G | 660 | `0.26 × 1320/660 = 0.52 G` ⇒ ~52 µT | **完全吻合** |

⇒ 数学上，"**2 倍偏低**"和"**CNTL3 没生效**"**不是同一件事**：CNTL3 没生效会造成 4 倍（`0.26→1.04 G`，偏高 2 倍），与观测的"偏低 2 倍"方向相反。
⇒ 能同时解释"偏低 2 倍"的只有两类：
1. **现场磁场真的只有 ~26 µT**（室内钢构 / 工字钢 / 桌下电机 / 板子附近的铁磁件把场吸走或反向叠加）；
2. **真实 LSB/G ≈ 660**（即 16 位模式的灵敏度是驱动假设的一半，或 CNTL3 只对部分轴生效 / 该册手册的 4× 推算不成立）。

**⇒ 判定实验（不需要 ST-Link，不需要改代码）：**

```text
# A. 换环境复测（判"场真的弱"）
1. 把整机搬到室外空旷处（远离钢筋、车辆、扬声器、电机），离地 ~1 m，静置 60 s。
2. QGC 里:  listener -n 200 sensor_mag
3. 读 |B| = sqrt(x²+y²+z²)（Gauss）。
   判据: 室外读到 0.45~0.55 G ⇒ 原来的 0.26 是【环境】，标度没问题，收工。
        室外仍读到 0.24~0.28 G ⇒ 【标度】问题（正好 2 倍），进 B。

# B. 与独立参照对照（判标度）
4. 同一位置、同一高度，用手机的磁力计 App（多数直接显示 µT）读一次，
   或用一个已知良好的外置磁罗盘。
5. 判据: |B_px4 / B_phone − 1| ≤ 0.15 ⇒ 标度可信；
        ≈ 0.5  ⇒ 标度差 2 倍，需查 CNTL3 是否被别的东西改写 / 该器件的 16 位灵敏度口径。

# C. 器件自检（判磁路健康，不做标度）
6. STR(0x0C) bit6 = 1（iSentek 手册 §3.1.3）后三轴输出应【极性翻转、绝对值基本不变】。
   判据: 翻转前后 |B| 差 ≤ 5% ⇒ 磁路健康。

# D. 交叉验证"是不是 0x0C 这颗地址上的器件真的被读到了"
7. ist8310 status 看 error_count 与 bad_transfer 是否增长；不增长 ⇒ 读得稳。
```

**⇒ 它卡不卡"能用"（Lead 要的明确回答）：**

| 环节 | 结论 | 证据 |
|---|---|---|
| 罗盘标定能否通过 | ✅ **能过，2 倍偏差不会让它失败** | `lm_mag_fit` **自己解算半径**（`lm_fit.cpp:316-355` 迭代含 `params.radius`，只要 `0.2 < radius < 0.7` 即成功），`mag_calibration.cpp:648` 也只查这个窗口；`get_sphere_radius()` 的 WMM/GPS 值只是**初值**（`:169-186`、`:576-597`）；`0.4` 是缺省初值（`:74`）。**⇒ 标定会把错误半径照单全收** |
| 航向会不会错 | ❌ **不会**（均匀 2 倍是各向同性的，不改变磁场矢量方向） | `report.x = x*_scale`（`PX4Magnetometer.cpp:98-100`），三轴同比例 |
| 无 GNSS 时 EKF2 会不会拒磁 | ✅ 不会 | 无 WMM 时用硬编码门限 `average_earth_mag_field_strength=0.45 G`、`gate=0.40 G`（`mag_control.cpp:538-541`，`isMeasuredMatchingExpected` 见 `:577-580`）⇒ 允许 **0.05~0.85 G**，0.26 通过 |
| **有 GNSS/WMM 时会不会拒磁** | ⚠️ **会** | 门限变成 `WMM ± EKF2_MAG_CHK_STR(缺省 0.2 G)`（`params_magnetometer.yaml:101-131`）⇒ 例如 0.50±0.20 = **[0.30, 0.70] G**，0.26 **落在窗口外** ⇒ `mag_field_disturbed=true`（`mag_control.cpp:525-535`）⇒ 磁被拒 ⇒ 航向/位置估计受影响 |
| 会不会拒解锁 | ⚠️ 取决于参数：`COM_ARM_MAG_STR` 缺省 **2 = 仅告警**（`commander_params.yaml:260-271`），报 `Preflight: Strong magnetic interference`（`estimatorCheck.cpp:209-243`）；**若被设成 1 = DenyArming 就直接拒解锁** | 同上 |
| **⇒ 对飞行的净影响** | **目前（无 GNSS）不卡解锁、不卡标定、不卡航向**；一旦引入 GNSS/WMM 判定（或把 `COM_ARM_MAG_STR` 调成 1），**会卡 preflight**。⇒ 归 **P2**，不是 P0 | |

---

## 3.4 ★ 两路加计逐轴比 1.007 / 0.888 / 0.779 —— 它改变了什么、**没**改变什么（2026-10-01 新增）

> 用户从 4 次 `listener sensor_accel` 算出 hxy/H104 的逐轴比 = **1.007 / 0.888 / 0.779**。
> Lead 问它是否推翻"单通道增益"的推理。**答：它推翻的是"11~22% 这一量级能造成识别失败"，但没推翻推理本身。**

### 3.4.1 先给出"能过/不能过"的**定量窗口**（这是本轮最有用的一条）

`detect_orientation` 的判据是（`calibration_routines.cpp:75,168-202`）：
期望轴 `|v_k ∓ g| < 5`、另两轴 `|v_j| < 5`，其中 `g = CONSTANTS_ONE_G = 9.80665`。

设某轴的**表观增益**为 `g_k`（真值 1.0 = 准）。重力落该轴时 `v_k = g_k · 9.80665`，另两轴 ≈0，于是：

```
该面通过  ⇔  4.81 < g_k · 9.80665 < 14.81
          ⇔  0.490 < g_k < 1.510          ← 【通过窗口】
```

| 各轴 `g_k` 的情况 | 6 个面里通过几个 |
|---|---|
| 三轴全在 (0.490, 1.510) 内 | **6/6**（全过） |
| 三轴全在外 | **0/6**（全挂） |
| **恰好一个轴在外** | **4/6** ✅（正是现场观察） |
| 两个轴在外 | 2/6 |

**⇒ 实测的 0.779 / 0.888 / 1.007 三轴全在 (0.490, 1.510) 内 ⇒ 这个量级的逐轴差
"一个面都不会打掉"，因此它**不是** `invalid orientation` 的原因。**

⇒ 反过来，由"4/6 完成"可以**反解出目标**：**要卡住 2 个面，必须有一个轴的 `g_k ≥ 1.51`（+51%）或 `≤ 0.490`（−51%）**。
**⇒ 所以下一步不要再找 11~22%，要找的是"某一个轴偏 ≥51%"**（这与 §1 里 **3.6×** 的量级吻合，与 1.007/0.888/0.779 不吻合）。

### 3.4.2 那 11~22% 是什么？它卡不卡"能用"？

- **它不卡标定**（在窗口内，见上），**但它卡 preflight**：
  `voted_sensors_update.cpp:449-472` 算的是"每路与**均值**的偏差"，门限 `COM_ARM_IMU_ACC = 0.7 m/s²`（`commander_params.yaml:225-238`）。
  逐轴差 22% ⇒ `0.22 × 9.80665 = 2.16 m/s²` 的**两路差** ⇒ 各自偏离均值 **≈1.08 m/s² ≫ 0.7**
  ⇒ **`Preflight Fail: Accel N inconsistent` 会（持续）报红。**
  ⚠️ 这与"标定前零点未扣"是两个独立原因，**都指向同一件事：先过标定**。
- **好消息（对处置 B）**：三个比值都**接近 1**（0.78~1.01）。若两路 published 框架差 90°/45°，
  逐轴比会接近 **0 或极大**。⇒ **实测说明两路框架大致是逐轴对齐的** ⇒
  `review-04` §2.5.3 里最危险的 R1（`mat_A` 变置换矩阵 ⇒ `set_scale(≈0)` ⇒ 整路归零）**风险显著降低**。
  **但仍要逐姿势带符号复核**（比值是均值和模，不带符号、也不区分姿势）。
- **⚠️ 测量本身的警告**：hxy 是 ~1 kHz、H104 是 100 Hz（0~10 ms 样本龄差）。
  若那 4 次采样不是"同姿势 + 静止 + 同一时刻窗"，**手动的动态加速度本身就能造出两位数百分比差异**。
  ⇒ 这条比值**必须在静止姿势下逐姿势重测**才算数（见 §3.2/`review-04` §3.4 的协议）。
- **21% 这一类的偏差最终由标定吸收**：六面标定给**每一路**解一个 3×3 矩阵含逐轴 scale
  （`accelerometer_calibration.cpp:363-379`）⇒ 标定完成后两路应当明显趋近。
  ⇒ **所以顺序是：先让识别过关 → 跑完标定 → 再回看这组比值。**

# 第 4 部分 · 交回 Lead 的"上板可执行步骤清单"（汇总）

> 全部**不需要我碰 ST-Link**；涉及 ST-Link 的只有"净化后手写寄存器"那一条，由 Lead 执行。

| 编号 | 目的 | 前置 | 步骤要点 | 判据 |
|---|---|---|---|---|
| **步骤 A**（P0） | 定死加计/陀螺轴向 | 无 | 全流程六个姿态（平放/倒放/左/右/抬头/低头），每个姿态静置 10 s，QGC `listener sensor_accel`；同时看 h104 的同一姿态；必要时改 `-R`（`ROTATION_YAW_180=4` 等，`src/lib/conversion/rotation.h:53-80`）后重试 | 六个面在**未标定**状态下符号全部正确（`accelerometer_calibration.cpp:222-273` 的判据）；两路 IMU 的同一姿态符号一致 |
| **步骤 B**（P0） | 跑通加计标定 | 步骤 A 通过、标度确定（至少用当前 1.7512） | QGC 六面标定（`COM_ARM_IMU_ACC` 保持缺省 0.7） | `[cal] calibration done`；`CAL_ACC0_ID != 0`；`Preflight Fail: Accel %u inconsistent` 消失 |
| **步骤 C**（P1） | 陀螺增益绝对验证 | 标定完成 | 见 §2.5 实验 B（logger + 手工绕 Z 转 ≥3 圈 + 离线积分） | `\|θ_hxy/θ_h104 − 1\| ≤ 0.02` |
| **步骤 D**（P1） | 陀螺量程档位扫描（可选，判 FS 译码） | 需要临时 CLI 参数或 ST-Link 净化写 | 见 §2.4 实验 A | 各档比值偏差 ≤ 2% |
| **步骤 E**（P1） | 复核加计 1.7512 是否需要撤 | 步骤 B 之后看 `CAL_ACC0_XSCALE/YSCALE/ZSCALE` | 六面标定输出的 scale 若已接近 1/1.7512 ≈ 0.571，说明常数在重复修正 ⇒ 应把驱动常数设回 1.0 并重标（**顺序：先定常数 → 再标定**） | `CAL_ACC0_*SCALE ∈ [0.9, 1.1]` 才算常数与标定不冲突 |
| **步骤 F**（P2） | 磁力计 2 倍判定 | 无 | 见 §3.3.2 的 A/B/C | 室外 \|B\| ∈ [0.45,0.55] G 或与手机读数差 ≤ 15% |
| **步骤 G**（P2） | 给 h104 加身份校验 + error_count（或至少 status 里报 `PNAME`） | — | 建议改 `src/drivers/imu/hipnuc_h104/`（Lead 决策） | 换一个非 HI04M0 的 HI91 源时应能被识别/告警 |
| **步骤 H**（P3） | H104 提频到 200/400 Hz | — | 见 §1.4 的步骤清单 | 帧率 ±1%、CRC 坏 0、resync 不增长 |
| **步骤 I**（P3） | HXY 驱动加固（`DATA_SAT` 读取、`GYR_RANGE` 掩码 B3、`set_bits=0` 的校验、定标不信任回读、自检） | — | review-01 L1/L2/L3/L4/R2 | 见 review-01 漏项表 |

---

# 第 5 部分 · 本次核查中"我不能判定、必须上板"的清单（诚实标注）

| 事项 | 为什么不能只靠纸面判定 |
|---|---|
| 1.7512 的正确性 | 四档量程数据对"纯增益"与"档位偏移+残余增益"是**数学简并**的（review-01 §5.1）；必须引入不随标称码线性缩放的外部参照 |
| 陀螺绝对增益 | 手册只有圆整的 typ 值；必须做积分比对 |
| `\|B\|` 偏低 2 倍的原因 | 现场磁场是未知量；必须换环境/换参照 |
| `-R` 的真值 | 取决于实物贴装；必须用六面姿态核对 |
| `GYR_CONF` 写不进去的根因 | 涉及 DMA 时序；纸面只能给出手册的两条候选解释（`HXY:1750-1751`、`HXY:1782`） |
| H104 的 X/Y 符号 | 必须是实物转动 |

> 以上全部已落成 §4 的可执行步骤，未包含任何需要我操作 ST-Link / 烧写的内容。
