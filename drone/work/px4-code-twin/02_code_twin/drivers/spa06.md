# `src/drivers/barometer/goertek/spa06/` —— 气压计（I2C2，0x77）

> **运行时一句话**：**32 Hz** 轮询 I2C2，读 `PSR_B2..B0` 与温度，换算出 `baro_pressure_pa`，
> 发 `sensor_baro`。它是本板**唯一的高度观测源**（没有 GPS）。
> **⇒ 它决定了"飞机认为自己多高"；它漂了，定高就漂了。**
> 行号基准 `源码根（见 `tools/source-root.conf`）` HEAD `3b5de24`。

---

## 1. 运行时序

```
① 总线登记：boards/rm2027/fmu-h743/src/i2c.cpp:78   initI2CBusInternal(2)

② 拉起：boards/rm2027/fmu-h743/init/rc.board_sensors:110
      spa06 -I -b 2 -a 0x77 start
   ★ 必须 -a 0x77：驱动缺省 0x76（spa06_main.cpp:52 PRINT_MODULE_USAGE_PARAMS_I2C_ADDRESS(0x76)；:111 cli.i2c_address = 0x76）
   -I = Internal（platforms/common/i2c_spi_buses.cpp:183-185）；-b 2 = I2C2

③ 对象：SPA06.cpp:38-42
      _px4_baro{interface->get_device_id(), config.external}
      perf: sample / measure / comms errors
   队列：I2CSPIDriverBase → device_bus_to_wq(devid) → I2C2(WQ)   WorkQueueManager.cpp:146-157

④ 初始化（SPA06.cpp:150-193）—— 这一段做得很规矩，值得看
      set_reg(VALUE_RESET, ADDR_RESET); usleep(10ms)                      :152-153
      ★ 校验 ID：get_reg(SPA06_ADDR_ID) != SPA06_VALUE_ID ⇒ return -EIO   :156-159
      ★ 等校准系数就绪：轮询 MEAS_CFG 的 bit7|bit6，最多 5 次 ×10 ms        :161-174
      calibrate()（读出厂系数）                                            :177
      set PRS_CFG / TMP_CFG（推荐档），kp=253952 / kt=524288                :180-183
      使能 FIFO(CFG_REG bit2)；MEAS_CFG=7（连续压力+温度）                   :186-188
      Start() → ScheduleNow()                                              :190/199

⑤ 周期：SPA06.hpp:116-117
      _sample_rate = 32      ⇒ _measure_interval = 1e6/32 = 31250 us
      RunImpl(): collect() → ScheduleDelayed(_measure_interval)            SPA06.cpp:203-208

⑥ 发布：SPA06.cpp:239-241
      _px4_baro.set_error_count(perf_event_count(_comms_errors))   :239
      _px4_baro.set_temperature(temperature)                       :240
      _px4_baro.update(timestamp_sample, fp)                       :241
      PX4Barometer → PublicationMulti<sensor_baro_s>（PX4Barometer.hpp:61）
```

---

## 2. 话题链

```
SPA06.cpp:241  →  sensor_baro（实例 0）
   ▼
【订阅者 = sensors 模块】sensors.cpp:409-413  new VehicleAirData() → Start()
   VehicleAirData.hpp:106-109 订 sensor_baro 实例 0..3
   ★ 它还订：vehicle_gps_position(:112 本板无) / differential_pressure(:101 本板无) /
             estimator_status_flags(:103)
   ▼
vehicle_air_data（VehicleAirData.hpp:97）+ sensors_status_baro（:95）
   ▼
【订阅者 = ekf2】EKF2.hpp:373 _airdata_sub → 消费 EKF2.cpp:2363
   ⇒ estimator_aid_src_baro_hgt（EKF2.hpp:376）
【订阅者 = mavlink / logger】（HIGHRES_IMU.hpp:72、logged_topics.cpp:139）
```

---

## 3. 判据

| 项 | 值 | 出处 |
|---|---|---|
| 驱动缺省地址 | 0x76（**必须被 `-a 0x77` 覆盖**） | `spa06_main.cpp:52,111` |
| 本片地址 | **0x77** | `rc.board_sensors:110` `[实测]` |
| 采样率 | **32 Hz** | [`SPA06.hpp:116`](spa06.md#^src-src-drivers-barometer-goertek-spa06-SPA06-hpp-116) |
| ID 校验 | 有（`SPA06_ADDR_ID != SPA06_VALUE_ID` ⇒ `-EIO`） | [`SPA06.cpp:156`](spa06.md#^src-src-drivers-barometer-goertek-spa06-SPA06-cpp-156) |
| 错误上报 | 有（`set_error_count`） | [`SPA06.cpp:239`](spa06.md#^src-src-drivers-barometer-goertek-spa06-SPA06-cpp-239) |

```sh
spa06 status
listener sensor_baro            # 频率应 ≈32 Hz；pressure 单位 Pa，海平面附近 ~101325
listener vehicle_air_data       # baro_pressure_pa / baro_alt_meter / ambient_temperature
ekf2 status
```
**分诊**：
- `sensor_baro` 有值但 `vehicle_air_data.baro_alt_meter` 不动 ⇒ 卡在 `VehicleAirData` 的融合/滤波。
- `sensor_baro` 频率不对 ⇒ 检查 `spa06 status` 的 perf（`comms errors` 增长 = I2C 有问题）。
- `vehicle_air_data` 有、EKF2 不用 ⇒ 看 `estimator_aid_src_baro_hgt` 的 fuse 状态（可能被 `EKF2_BARO_CTRL` 关了）。

---

## 4. 本板特殊点

| 点 | 说明 |
|---|---|
| **没有 GPS** | `vehicle_gps_position` 永不发布 ⇒ EKF2 的高度**没有绝对参照**，只能靠气压 + 加速度积分 `[推理]` |
| **没有空速管** | `differential_pressure` 无发布者 ⇒ `vehicle_air_data` 不用做静压/动压修正 |
| **32 Hz 偏慢** | 对定高够用（气压本身噪声大），但**不能用来做快速高度环的微分** |

---

## 5. 未核实

| 事项 | 说明 |
|---|---|
| `_curr_prs_cfg` / `_curr_tmp_cfg` 的具体档位（过采样率） | [`SPA06.cpp:180`](spa06.md#^src-src-drivers-barometer-goertek-spa06-SPA06-cpp-180) 只核到 `kp=253952`（注释"refer to scale_factor()"），档位常量未回读 |
| `collect()` 的 FIFO 读取路径（[`SPA06.cpp:210`](spa06.md#^src-src-drivers-barometer-goertek-spa06-SPA06-cpp-210)） | 只核到 5 个关键行，中段换算未逐行读 |
| 器件上电后 `MEAS_CFG` 的稳定时间 | 代码给 5×10 ms；实测是否够未核 |
| `SPA06_SPI.cpp` / `SPA06_I2C.cpp` 的分派 | 本板走 I2C；SPI 分支未核 |

---

## 跳转

| 下一步 | 读哪篇 |
|---|---|
| 下游：`sensor_baro` 变成 `vehicle_air_data` | [02_code_twin/modules/sensors](../modules/sensors.md) §4 |
| 再下游：EKF2 怎么用气压高度 | [02_code_twin/modules/ekf2](../modules/ekf2.md) §3 |
| 对照：同样"必须显式给地址"的磁罗盘 | [02_code_twin/drivers/ist8310](ist8310.md) |
| 六条流全景 §5 | [03_moc/02-sensor-flow](../../03_moc/02-sensor-flow.md) |

---

## 标注源码（代码 + 本文档对它的解释）

> **这是「代码孪生」层**：上面是代码原文（带行号），下面是**本文档针对这一段说的话**。
> 行号可点，直接跳到 PX4 源码那一行。
### `src/drivers/barometer/goertek/spa06/SPA06.cpp`
<a id="src-src-drivers-barometer-goertek-spa06-SPA06-cpp-156"></a>
**↓ 文档在讲这里：**[`src/drivers/barometer/goertek/spa06/SPA06.cpp:156`](spa06.md#^src-src-drivers-barometer-goertek-spa06-SPA06-cpp-156)

```c
   153 │ 	usleep(10000);
   154 │ 
   155 │ 	// check id
▶  156 │ 	if (_interface->get_reg(SPA06_ADDR_ID) != SPA06_VALUE_ID) {
   157 │ 		PX4_DEBUG("id of your baro is not: 0x%02x", SPA06_VALUE_ID);
   158 │ 		return -EIO;
   159 │ 	}
```
> **说明**：采样率 | 32 Hz | SPA06.hpp:116 | ┃ ID 校验 | 有（SPA06_ADDR_ID != SPA06_VALUE_ID ⇒ -EIO） | SPA06.cpp:156 |
^src-src-drivers-barometer-goertek-spa06-SPA06-cpp-156

<a id="src-src-drivers-barometer-goertek-spa06-SPA06-cpp-180"></a>
**↓ 文档在讲这里：**[`src/drivers/barometer/goertek/spa06/SPA06.cpp:180`](spa06.md#^src-src-drivers-barometer-goertek-spa06-SPA06-cpp-180)

```c
   177 │ 	calibrate();
   178 │ 
   179 │ 	// set config, recommended settings
▶  180 │ 	_interface->set_reg(_curr_prs_cfg, SPA06_ADDR_PRS_CFG);
   181 │ 	kp = 253952.0f; // refer to scale_factor()
   182 │ 	_interface->set_reg(_curr_tmp_cfg, SPA06_ADDR_TMP_CFG);
   183 │ 	kt = 524288.0f;
```
> **说明**：_curr_prs_cfg / _curr_tmp_cfg 的具体档位（过采样率） | SPA06.cpp:180 只核到 kp=253952（注释"refer to scale_factor()"），档位常量未回读 |
^src-src-drivers-barometer-goertek-spa06-SPA06-cpp-180

<a id="src-src-drivers-barometer-goertek-spa06-SPA06-cpp-210"></a>
**↓ 文档在讲这里：**[`src/drivers/barometer/goertek/spa06/SPA06.cpp:210`](spa06.md#^src-src-drivers-barometer-goertek-spa06-SPA06-cpp-210)

```c
   207 │ 	ScheduleDelayed(_measure_interval);
   208 │ }
   209 │ int
▶  210 │ SPA06::collect()
   211 │ {
   212 │ 	perf_begin(_sample_perf);
   213 │ 
```
> **说明**：_curr_prs_cfg / _curr_tmp_cfg 的具体档位（过采样率） | SPA06.cpp:180 只核到 kp=253952（注释"refer to scale_factor()"），档位常量未回读 | ┃ collect() 的 FIFO 读取路径（SPA06.cpp:210） | 只核到 5 个关键行，中段换算未逐行读 |
^src-src-drivers-barometer-goertek-spa06-SPA06-cpp-210

<a id="src-src-drivers-barometer-goertek-spa06-SPA06-cpp-239"></a>
**↓ 文档在讲这里：**[`src/drivers/barometer/goertek/spa06/SPA06.cpp:239`](spa06.md#^src-src-drivers-barometer-goertek-spa06-SPA06-cpp-239)

```c
   236 │ 	float temperature = (float)_cal.c0 * 0.5f + (float)_cal.c1 * ftsc;
   237 │ 
   238 │ 
▶  239 │ 	_px4_baro.set_error_count(perf_event_count(_comms_errors));
   240 │ 	_px4_baro.set_temperature(temperature);
   241 │ 	_px4_baro.update(timestamp_sample, fp);
   242 │ 
```
> **说明**：ID 校验 | 有（SPA06_ADDR_ID != SPA06_VALUE_ID ⇒ -EIO） | SPA06.cpp:156 | ┃ 错误上报 | 有（set_error_count） | SPA06.cpp:239 |
^src-src-drivers-barometer-goertek-spa06-SPA06-cpp-239

### `src/drivers/barometer/goertek/spa06/SPA06.hpp`
<a id="src-src-drivers-barometer-goertek-spa06-SPA06-hpp-116"></a>
**↓ 文档在讲这里：**[`src/drivers/barometer/goertek/spa06/SPA06.hpp:116`](spa06.md#^src-src-drivers-barometer-goertek-spa06-SPA06-hpp-116)

```c
   113 │ 	perf_counter_t		_measure_perf;
   114 │ 	perf_counter_t		_comms_errors;
   115 │ 
▶  116 │ 	static constexpr uint32_t _sample_rate{32};
   117 │ 	static constexpr uint32_t _measure_interval{1000000 / _sample_rate};
   118 │ };
   119 │ 
```
> **说明**：本片地址 | 0x77 | rc.board_sensors:110 [实测] | ┃ 采样率 | 32 Hz | SPA06.hpp:116 |
^src-src-drivers-barometer-goertek-spa06-SPA06-hpp-116
