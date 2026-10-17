# `src/drivers/dshot/` —— 4 路 DShot 输出（电机指令的最后一步）

> **运行时一句话**：它把 `actuator_motors` 里"每个电机 0~1 的值"按 **`PWM_MAIN_FUNC1..4`** 的通道映射，
> 打包成 DShot 位流，用 **DMA + TIM1** 打到 **PA8 / PE11 / PE13 / PE14**。
> **⇒ 它是"软件算出来的力矩"与"MOSFET 栅极"之间唯一的桥。**
> 行号基准 `源码根（见 `tools/source-root.conf`）` HEAD `3b5de24`。

---

## 1. 它是什么：一个 `OutputModuleInterface`（不是普通 module）

```cpp
class DShot final : public ModuleBase, public OutputModuleInterface          // DShot.h:76
DShot::DShot() :                                                             // DShot.cpp:44-45
    OutputModuleInterface(MODULE_NAME, px4::wq_configurations::hp_default)   // ★ 队列 = hp_default(-18)
{
    _mixing_output.setAllDisarmedValues(DSHOT_DISARM_VALUE);   // = 0        DShot.cpp:47
    _mixing_output.setAllMinValues(DSHOT_MIN_THROTTLE);        // = 1        :48
    _mixing_output.setAllMaxValues(DSHOT_MAX_THROTTLE);        // = 1999     :49
    _mixing_output.setAllFailsafeValues(UINT16_MAX);           // 不用 PWM 的 failsafe 参数  :52
    _esc_status_pub.advertise();                               // :55（提前 advertise，"beat uavcan"）
}

MixingOutput _mixing_output{PARAM_PREFIX, DSHOT_MAXIMUM_CHANNELS, *this,
                            MixingOutput::SchedulingPolicy::Auto, false, false};   // DShot.h:149
// PARAM_PREFIX 由构建期注入：src/drivers/dshot/CMakeLists.txt:34  set(PARAM_PREFIX PWM_MAIN)
//                             ⇒ -DPARAM_PREFIX="PWM_MAIN"                        CMakeLists.txt:44
```

**⇒ 两个名字要分清**：
- 模块名 `dshot`（[`CMakeLists.txt:41`](dshot.md#^src-CMakeLists-txt-41) `MODULE drivers__dshot` / `MAIN dshot`）—— shell 里敲的那个。
- 参数前缀 **`PWM_MAIN`**（[`CMakeLists.txt:34`](dshot.md#^src-CMakeLists-txt-34)）—— 所有参数名都长这样：`PWM_MAIN_FUNC1`、`PWM_MAIN_TIM0`。

---

## 2. ★ `dshot` 和 `pwm_out` 都起来了，谁真在干活？

`rcS:559-560` **两个都拉**：
```
dshot start
pwm_out start
```
**分流靠 `PWM_MAIN_TIM0` 的值**：

```c
bool DShot::initialize_dshot()                                    // DShot.cpp:1071
{
    for (each timer group) {
        snprintf(param_name, ..., "%s_TIM%u", _mixing_output.paramPrefix(), timer_index);   // :1086  ⇒ "PWM_MAIN_TIM0"
        param_get(handle, &tim_config);
        switch (tim_config) {
        case TIM_CONFIG_DSHOT150/300/600:      freq = ...; break;    // -5 / -4 / -3     DShot.h:59-61
        case TIM_CONFIG_BDSHOT150/300/600:     freq = ...; is_bdshot = true; break;  // -8/-7/-6  DShot.h:62-64
        default: break;                                              // ← 本板缺省 400 落这里
        }
        if (freq > 0) { dshot_timer_channels |= timer_channels; ... }
    }
    if (dshot_timer_channels == 0) { PX4_INFO("No channels configured"); return false; }   // :1126-1129
    ...
}
```
- `PWM_MAIN_TIM0 = 400`（本板缺省，[`build/.../generated_params/module_params.c:2164`](dshot.md#^src-build-rm2027-fmu-h743-default-generated-params-module-params-c-2164)）⇒ `dshot init()` 返回 `PX4_ERROR`（[`DShot.cpp:72`](dshot.md#^src-src-drivers-dshot-DShot-cpp-72)）⇒ **dshot 不干活**，`pwm_out` 接手出 PWM。
- 设成 **-3 / -4 / -5** 才轮到 DShot。改完**必须重启**（`reboot_required: true`，[`module_params.c:2162`](dshot.md#^src-build-rm2027-fmu-h743-default-generated-params-module-params-c-2162)）。

---

## 3. 数据怎么流进来（`MixingOutput` 的三步）

```
【发布者 = control_allocator】actuator_motors           ControlAllocator.cpp:757
   ▼ 订阅
【FunctionMotors】uORB::SubscriptionCallbackWorkItem _topic{&context.work_item, ORB_ID(actuator_motors)}
                                                    FunctionMotors.hpp:52
   ▼
【DShot::Run() 每拍调】DShot.cpp:95  _mixing_output.update()          → mixer_module.cpp:421
      :424  读 actuator_armed         ⇒ 决定"给不给油门"（总闸，来自 commander）
      :440-441 _function_allocated[i]->update()  ⇒ 把 actuator_motors / actuator_servos 的最新值取回
      :532  _interface.updateOutputs(...)        ⇒ 回到 DShot.cpp:125 DShot::updateOutputs()
      :534  setAndPublishActuatorOutputs(...)    ⇒ 发 actuator_outputs（:659 函数体）
```

**`DShot::updateOutputs()`（[`DShot.cpp:125`](dshot.md#^src-src-drivers-dshot-DShot-cpp-125)）做什么**：

| 步 | 动作 | 行 |
|---|---|---|
| 1 | 把 float 值四舍五入成 `uint16_t hw_outputs[]` | `:131-135` |
| 2 | 算 `esc_armed_flags`（判断哪些通道被"武装"） | `:137`（`esc_armed_mask()` 定义在 `:452`） |
| 3 | 瞄准模式 / 遥测初始化 / 正常输出三条分支 | `:142-165` |
| 4 | 正常输出 → `update_motor_outputs(hw_outputs, n)` | `:165`（定义 `:372`） |
| 5 | 特殊命令（ESC 配置/反转/保存参数）→ `update_motor_commands()` | `:158`（定义 `:409`） |

---

## 4. ★ 参数名 → 通道 → 电机（这一跳是"不出脉冲"的高发区）

```
PWM_MAIN_FUNC1 = 101  （output_functions.yaml:5,10-12：Disabled=0；Motor: start 101, count 12）
        │  mixermodule 按前缀+序号拼参数名
        │  mixer_module.cpp:117  snprintf("%s_%s%d", prefix, "FUNC", i+1)  ⇒ "PWM_MAIN_FUNC1"
        ▼
MixingOutput 为每个通道建一个 FunctionProvider（`FunctionMotors`）          mixer_module.cpp:440-441
        ▼
motor_index_from_output(channel)  = outputFunction(channel) − OutputFunction::Motor1   DShot.h:112-118
        ▼
up_dshot_motor_command(motor_index, value, telemetry)   ← 声明 src/drivers/drv_dshot.h:116
up_dshot_trigger()                                      ← 声明 src/drivers/drv_dshot.h:124
        ▼  实现：platforms/nuttx/src/px4/stm/stm32_common/dshot/dshot.c（DMA 缓冲 + 定时器触发）
        ▼
TIM1 CH1..4 → PA8 / PE11 / PE13 / PE14        boards/rm2027/fmu-h743/src/timer_config.cpp:57-60
                                              （文件头 :39-48 说明为什么必须用 TIM1：高级定时器）
```

**⇒ 本板最常见的三个"不出脉冲"原因**（按发生概率）：

| # | 原因 | 判据 | 出处 |
|---|---|---|---|
| 1 | **`PWM_MAIN_FUNC1..4` 全是 0（本板缺省就是 0）** | `param show PWM_MAIN_FUNC1` → 0；`listener actuator_motors` 有值但 `listener actuator_outputs` 无 | `module_params.c:2243/2322/2401/2480`；[`output_functions.yaml:5`](dshot.md#^src-src-lib-mixer-module-output-functions-yaml-5) |
| 2 | **`PWM_MAIN_TIM0` 不是 DShot 档** | `param show PWM_MAIN_TIM0` → 400（缺省）；`dshot status` 报 No channels configured | [`module_params.c:2164`](dshot.md#^src-build-rm2027-fmu-h743-default-generated-params-module-params-c-2164)；[`DShot.cpp:1126`](../modules/control_allocator.md#^src-src-drivers-dshot-DShot-cpp-1126) |
| 3 | **`actuator_armed.armed = false`** | `listener actuator_armed` | [`mixer_module.cpp:424`](../modules/commander.md#^src-src-lib-mixer-module-mixer-module-cpp-424)；源头 [02_code_twin/modules/commander](../modules/commander.md) |

---

## 5. 遥测：本板**没有**

| 项 | 本板 | 出处 |
|---|---|---|
| DShot 遥测串口 | `DSHOT_TEL_CFG = 0` ⇒ 没配 | [`build/.../generated_params/serial_params.c:55`](dshot.md#^src-build-rm2027-fmu-h743-default-generated-params-serial-params-c-55) |
| BDShot（双向 DShot） | 需要 `PWM_MAIN_TIM0 ∈ {-6,-7,-8}` ⇒ 本板不是 | [`DShot.h:62`](dshot.md#^src-src-drivers-dshot-DShot-h-62) |
| 后果 | `esc_status` 话题被 `advertise`（[`DShot.cpp:55`](dshot.md#^src-src-drivers-dshot-DShot-cpp-55)）但**永远不会 `publish`**（只在 `:100-105` 的"收到遥测"分支里发） | [`DShot.cpp:100`](dshot.md#^src-src-drivers-dshot-DShot-cpp-100) |
| ⇒ | `esc_status` 的消费者（[`VehicleAngularVelocity.hpp:106`](dshot.md#^src-src-modules-sensors-vehicle-angular-velocity-VehicleAngularVelocity-hpp-106)、`logger` `:71`）**永远收不到东西** | |

**eRPM 遥测**（`esc_rpm`，`:690`）也需要 BDShot ⇒ 本板拿不到转速。

---

## 6. 判据

```sh
dshot status                 # 频率、通道、遥测状态；"No channels configured" ⇒ TIM 参数不对
param show PWM_MAIN_TIM0 PWM_MAIN_FUNC1 PWM_MAIN_FUNC2 PWM_MAIN_FUNC3 PWM_MAIN_FUNC4
listener actuator_motors     # control_allocator 有没有在发
listener actuator_outputs    # MixingOutput 有没有把值交出去（:534 / :659）
listener actuator_armed      # 总闸
actuator_test --motor 1 0.2  # 绕过控制链直测（走 MixingOutput 的 actuator_test 分支 mixer_module.cpp:449）
```
**示波器/万用表口径**：`actuator_outputs` 有值但引脚无波形 ⇒ 问题在 `dshot.c`（DMA/定时器）或硬件，
见 `work/ESC-测量地图与预期电压.md`。

---

## 7. 未核实

| 事项 | 说明 |
|---|---|
| `dshot.c` 的 DMA/定时器细节（缓冲区大小、基间隔） | 只核到 `platforms/nuttx/src/px4/stm/stm32_common/dshot/dshot.c` 的存在与 `DMA_SCR_*` 宏；具体寄存器配置未逐行读 |
| `DSHOT_MOT_POL1..4` 缺省 14 的语义 | 只核到参数名拼接（[`DShot.cpp:1009`](dshot.md#^src-src-drivers-dshot-DShot-cpp-1009)）与缺省值（[`module_params.c:1917`](dshot.md#^src-build-rm2027-fmu-h743-default-generated-params-module-params-c-1917)）；14 的位含义未核 |
| `PWM_MAIN_TIM0` 的完整取值-行为对应 | 只核到 DShot 侧（[`DShot.h:59`](dshot.md#^src-src-drivers-dshot-DShot-h-59)）与参数注释块（[`module_params.c:2154`](dshot.md#^src-build-rm2027-fmu-h743-default-generated-params-module-params-c-2154)）；`pwm_out` 侧的配置未核 |
| 本板电调支持的最高 DShot 速率 | 属电调硬件侧（AM32/G071），不在本文范围 |

---

## 跳转

| 下一步 | 读哪篇 |
|---|---|
| 上游：`actuator_motors` 是谁发的 | [02_code_twin/modules/control_allocator](../modules/control_allocator.md) |
| 上游：`actuator_armed` 是谁发的 | [02_code_twin/modules/commander](../modules/commander.md) |
| 参数怎么生成/怎么落盘 | [03_moc/04-params-map](../../03_moc/04-params-map.md)、`work/PX4接电调-QGC配置清单.md` |
| 六条流全景 §1 | [03_moc/02-sensor-flow](../../03_moc/02-sensor-flow.md) |

---

## 标注源码（代码 + 本文档对它的解释）

> **这是「代码孪生」层**：上面是代码原文（带行号），下面是**本文档针对这一段说的话**。
> 行号可点，直接跳到 PX4 源码那一行。
### `CMakeLists.txt`
<a id="src-CMakeLists-txt-34"></a>
**↓ 文档在讲这里：**[`CMakeLists.txt:34`](dshot.md#^src-CMakeLists-txt-34)

```c
    31 │ #
    32 │ ############################################################################
    33 │ 
▶   34 │ #=============================================================================
    35 │ # CMAKE CODING STANDARD FOR PX4
    36 │ #
    37 │ # Structure
```
> **说明**：模块名 dshot（CMakeLists.txt:41 MODULE driversdshot / MAIN dshot）—— shell 里敲的那个。 ┃ 参数前缀 PWM_MAIN（CMakeLists.txt:34）—— 所有参数名都长这样：PWM_MAIN_FUNC1、PWM_MAIN_TIM0。
^src-CMakeLists-txt-34

<a id="src-CMakeLists-txt-41"></a>
**↓ 文档在讲这里：**[`CMakeLists.txt:41`](dshot.md#^src-CMakeLists-txt-41)

```c
    38 │ # ---------------------------------------------------------------------------
    39 │ #
    40 │ # * Common functions should be included in px_base.cmake.
▶   41 │ #
    42 │ # * OS/ board specific fucntions should be include in
    43 │ #	px_impl_${PX4_PLATFORM}.cmake
    44 │ #
```
> **说明**：模块名 dshot（CMakeLists.txt:41 MODULE driversdshot / MAIN dshot）—— shell 里敲的那个。
^src-CMakeLists-txt-41

### `build/rm2027_fmu-h743_default/generated_params/module_params.c`
<a id="src-build-rm2027-fmu-h743-default-generated-params-module-params-c-1917"></a>
**↓ 文档在讲这里：**[`build/rm2027_fmu-h743_default/generated_params/module_params.c:1917`](dshot.md#^src-build-rm2027-fmu-h743-default-generated-params-module-params-c-1917)

```c
  1914 │  * @min 2
  1915 │  * @max 400
  1916 │  */
▶ 1917 │ PARAM_DEFINE_INT32(DSHOT_MOT_POL1, 14);
  1918 │ 
  1919 │ /**
  1920 │  * Number of magnetic poles of motor 2
```
> **说明**：dshot.c 的 DMA/定时器细节（缓冲区大小、基间隔） | 只核到 platforms/nuttx/src/px4/stm/stm32_common/dshot/dshot.c 的存在与 DMA_SCR_* 宏；具体寄存器配置未逐行读 | ┃ DSHOT_MOT_POL1..4 缺省 14 的语义 | 只核到参数名拼接（DShot.cpp:1009）与缺省值（module_params.c:1917）；14 的位含义未核 |
^src-build-rm2027-fmu-h743-default-generated-params-module-params-c-1917

<a id="src-build-rm2027-fmu-h743-default-generated-params-module-params-c-2154"></a>
**↓ 文档在讲这里：**[`build/rm2027_fmu-h743_default/generated_params/module_params.c:2154`](dshot.md#^src-build-rm2027-fmu-h743-default-generated-params-module-params-c-2154)

```c
  2151 │  * @value -8 BDShot150
  2152 │  * @value -7 BDShot300
  2153 │  * @value -6 BDShot600
▶ 2154 │  * @value -5 DShot150
  2155 │  * @value -4 DShot300
  2156 │  * @value -3 DShot600
  2157 │  * @value -1 OneShot
```
> **说明**：DSHOT_MOT_POL1..4 缺省 14 的语义 | 只核到参数名拼接（DShot.cpp:1009）与缺省值（module_params.c:1917）；14 的位含义未核 | ┃ PWM_MAIN_TIM0 的完整取值-行为对应 | 只核到 DShot 侧（DShot.h:59）与参数注释块（module_params.c:2154）；pwm_out 侧的配置未核 |
^src-build-rm2027-fmu-h743-default-generated-params-module-params-c-2154

<a id="src-build-rm2027-fmu-h743-default-generated-params-module-params-c-2162"></a>
**↓ 文档在讲这里：**[`build/rm2027_fmu-h743_default/generated_params/module_params.c:2162`](dshot.md#^src-build-rm2027-fmu-h743-default-generated-params-module-params-c-2162)

```c
  2159 │  * @value 100 PWM 100 Hz
  2160 │  * @value 200 PWM 200 Hz
  2161 │  * @value 400 PWM 400 Hz
▶ 2162 │  * @reboot_required True
  2163 │  */
  2164 │ PARAM_DEFINE_INT32(PWM_MAIN_TIM0, 400);
  2165 │ 
```
> **说明**：PWM_MAIN_TIM0 = 400（本板缺省，build/.../generated_params/module_params.c:2164）⇒ dshot init() 返回 PX4_ERROR（DShot.cpp:72）⇒ dshot 不干活，pwm_out 接手出 PWM。 ┃ 设成 -3 / -4 / -5 才轮到 DShot。改完必须重启（reboot_required: true，module_params.c:2162）。
^src-build-rm2027-fmu-h743-default-generated-params-module-params-c-2162

<a id="src-build-rm2027-fmu-h743-default-generated-params-module-params-c-2164"></a>
**↓ 文档在讲这里：**[`build/rm2027_fmu-h743_default/generated_params/module_params.c:2164`](dshot.md#^src-build-rm2027-fmu-h743-default-generated-params-module-params-c-2164)

```c
  2161 │  * @value 400 PWM 400 Hz
  2162 │  * @reboot_required True
  2163 │  */
▶ 2164 │ PARAM_DEFINE_INT32(PWM_MAIN_TIM0, 400);
  2165 │ 
  2166 │ /**
  2167 │  * PWM Main 1 Output Function
```
> **说明**：PWM_MAIN_TIM0 = 400（本板缺省，build/.../generated_params/module_params.c:2164）⇒ dshot init() 返回 PX4_ERROR（DShot.cpp:72）⇒ dshot 不干活，pwm_out 接手出 PWM。
> **说明**：1 | PWM_MAIN_FUNC1..4 全是 0（本板缺省就是 0） | param show PWM_MAIN_FUNC1 → 0；listener actuator_motors 有值但 listener actuator_outputs 无 | module_params.c:2243/2322/2401/2480；output_functions.yaml:5 | ┃ 2 | PWM_MAIN_TIM0 不是 DShot 档 | param show PWM_MAIN_TIM0 → 400（缺省）；dshot status 报 No channels configured | module_params.c:2164；DShot.cpp:1126 |
^src-build-rm2027-fmu-h743-default-generated-params-module-params-c-2164

### `build/rm2027_fmu-h743_default/generated_params/serial_params.c`
<a id="src-build-rm2027-fmu-h743-default-generated-params-serial-params-c-55"></a>
**↓ 文档在讲这里：**[`build/rm2027_fmu-h743_default/generated_params/serial_params.c:55`](dshot.md#^src-build-rm2027-fmu-h743-default-generated-params-serial-params-c-55)

```c
    52 │  * @group DShot
    53 │  * @reboot_required true
    54 │  */
▶   55 │ PARAM_DEFINE_INT32(DSHOT_TEL_CFG, 0);
    56 │ 
    57 │ /**
    58 │  * Serial Configuration for RC Input Driver
```
> **说明**：DShot 遥测串口 | DSHOT_TEL_CFG = 0 ⇒ 没配 | build/.../generated_params/serial_params.c:55 |
^src-build-rm2027-fmu-h743-default-generated-params-serial-params-c-55

### `src/drivers/dshot/DShot.cpp`
<a id="src-src-drivers-dshot-DShot-cpp-55"></a>
**↓ 文档在讲这里：**[`src/drivers/dshot/DShot.cpp:55`](dshot.md#^src-src-drivers-dshot-DShot-cpp-55)

```c
    52 │ 	_mixing_output.setAllFailsafeValues(UINT16_MAX);
    53 │ 
    54 │ 	// Advertise early to ensure we beat uavcan
▶   55 │ 	_esc_status_pub.advertise();
    56 │ }
    57 │ 
    58 │ DShot::~DShot()
```
> **说明**：BDShot（双向 DShot） | 需要 PWM_MAIN_TIM0 ∈ {-6,-7,-8} ⇒ 本板不是 | DShot.h:62 | ┃ 后果 | esc_status 话题被 advertise（DShot.cpp:55）但永远不会 publish（只在 :100-105 的"收到遥测"分支里发） | DShot.cpp:100 |
^src-src-drivers-dshot-DShot-cpp-55

<a id="src-src-drivers-dshot-DShot-cpp-72"></a>
**↓ 文档在讲这里：**[`src/drivers/dshot/DShot.cpp:72`](dshot.md#^src-src-drivers-dshot-DShot-cpp-72)

```c
    69 │ 	perf_free(_serial_telem_allsampled_perf);
    70 │ }
    71 │ 
▶   72 │ int DShot::init()
    73 │ {
    74 │ 	update_params();
    75 │ 
```
> **说明**：PWM_MAIN_TIM0 = 400（本板缺省，build/.../generated_params/module_params.c:2164）⇒ dshot init() 返回 PX4_ERROR（DShot.cpp:72）⇒ dshot 不干活，pwm_out 接手出 PWM。
^src-src-drivers-dshot-DShot-cpp-72

<a id="src-src-drivers-dshot-DShot-cpp-100"></a>
**↓ 文档在讲这里：**[`src/drivers/dshot/DShot.cpp:100`](dshot.md#^src-src-drivers-dshot-DShot-cpp-100)

```c
    97 │ 	bool serial_updated = process_serial_telemetry();
    98 │ 	bool bdshot_updated = process_bdshot_telemetry();
    99 │ 
▶  100 │ 	if (serial_updated || bdshot_updated) {
   101 │ 		_esc_status.timestamp = hrt_absolute_time();
   102 │ 		_esc_status.esc_count = _motor_count;
   103 │ 		_esc_status.counter++;
```
> **说明**：BDShot（双向 DShot） | 需要 PWM_MAIN_TIM0 ∈ {-6,-7,-8} ⇒ 本板不是 | DShot.h:62 | ┃ 后果 | esc_status 话题被 advertise（DShot.cpp:55）但永远不会 publish（只在 :100-105 的"收到遥测"分支里发） | DShot.cpp:100 |
^src-src-drivers-dshot-DShot-cpp-100

<a id="src-src-drivers-dshot-DShot-cpp-125"></a>
**↓ 文档在讲这里：**[`src/drivers/dshot/DShot.cpp:125`](dshot.md#^src-src-drivers-dshot-DShot-cpp-125)

```c
   122 │ 	perf_end(_cycle_perf);
   123 │ }
   124 │ 
▶  125 │ bool DShot::updateOutputs(float *outputs, unsigned num_outputs, unsigned num_control_groups_updated)
   126 │ {
   127 │ 	if (!_hardware_initialized || !_motor_count) {
   128 │ 		return false;
```
> **说明**：DShot::updateOutputs()（DShot.cpp:125）做什么：
^src-src-drivers-dshot-DShot-cpp-125

<a id="src-src-drivers-dshot-DShot-cpp-1009"></a>
**↓ 文档在讲这里：**[`src/drivers/dshot/DShot.cpp:1009`](dshot.md#^src-src-drivers-dshot-DShot-cpp-1009)

```c
  1006 │ 	// Update per-motor pole count param handles and cached values
  1007 │ 	for (int i = 0; i < DSHOT_MAX_MOTORS; i++) {
  1008 │ 		char name[20];
▶ 1009 │ 		snprintf(name, sizeof(name), "DSHOT_MOT_POL%d", i + 1);
  1010 │ 		_param_pole_count_handles[i] = param_find(name);
  1011 │ 
  1012 │ 		int32_t pole_count = 14;
```
> **说明**：dshot.c 的 DMA/定时器细节（缓冲区大小、基间隔） | 只核到 platforms/nuttx/src/px4/stm/stm32_common/dshot/dshot.c 的存在与 DMA_SCR_* 宏；具体寄存器配置未逐行读 | ┃ DSHOT_MOT_POL1..4 缺省 14 的语义 | 只核到参数名拼接（DShot.cpp:1009）与缺省值（module_params.c:1917）；14 的位含义未核 |
^src-src-drivers-dshot-DShot-cpp-1009

<a id="src-src-drivers-dshot-DShot-cpp-1126"></a>
**↓ 文档在讲这里：**[`src/drivers/dshot/DShot.cpp:1126`](dshot.md#^src-src-drivers-dshot-DShot-cpp-1126)

```c
  1123 │ 		}
  1124 │ 	}
  1125 │ 
▶ 1126 │ 	if (dshot_timer_channels == 0) {
  1127 │ 		PX4_INFO("No channels configured");
  1128 │ 		return false;
  1129 │ 	}
```
> **说明**：1 | PWM_MAIN_FUNC1..4 全是 0（本板缺省就是 0） | param show PWM_MAIN_FUNC1 → 0；listener actuator_motors 有值但 listener actuator_outputs 无 | module_params.c:2243/2322/2401/2480；output_functions.yaml:5 | ┃ 2 | PWM_MAIN_TIM0 不是 DShot 档 | param show PWM_MAIN_TIM0 → 400（缺省）；dshot status 报 No channels configured | module_params.c:2164；DShot.cpp:1126 |
^src-src-drivers-dshot-DShot-cpp-1126

### `src/drivers/dshot/DShot.h`
<a id="src-src-drivers-dshot-DShot-h-59"></a>
**↓ 文档在讲这里：**[`src/drivers/dshot/DShot.h:59`](dshot.md#^src-src-drivers-dshot-DShot-h-59)

```c
    56 │ static constexpr uint32_t DSHOT600 = 600000u;
    57 │ 
    58 │ /// Timer config values from PWM_TIM param (matches pwm_out/module.yaml enum)
▶   59 │ static constexpr int32_t TIM_CONFIG_DSHOT150  = -5;
    60 │ static constexpr int32_t TIM_CONFIG_DSHOT300  = -4;
    61 │ static constexpr int32_t TIM_CONFIG_DSHOT600  = -3;
    62 │ static constexpr int32_t TIM_CONFIG_BDSHOT150 = -8;
```
> **说明**：DSHOT_MOT_POL1..4 缺省 14 的语义 | 只核到参数名拼接（DShot.cpp:1009）与缺省值（module_params.c:1917）；14 的位含义未核 | ┃ PWM_MAIN_TIM0 的完整取值-行为对应 | 只核到 DShot 侧（DShot.h:59）与参数注释块（module_params.c:2154）；pwm_out 侧的配置未核 |
^src-src-drivers-dshot-DShot-h-59

<a id="src-src-drivers-dshot-DShot-h-62"></a>
**↓ 文档在讲这里：**[`src/drivers/dshot/DShot.h:62`](dshot.md#^src-src-drivers-dshot-DShot-h-62)

```c
    59 │ static constexpr int32_t TIM_CONFIG_DSHOT150  = -5;
    60 │ static constexpr int32_t TIM_CONFIG_DSHOT300  = -4;
    61 │ static constexpr int32_t TIM_CONFIG_DSHOT600  = -3;
▶   62 │ static constexpr int32_t TIM_CONFIG_BDSHOT150 = -8;
    63 │ static constexpr int32_t TIM_CONFIG_BDSHOT300 = -7;
    64 │ static constexpr int32_t TIM_CONFIG_BDSHOT600 = -6;
    65 │ 
```
> **说明**：DShot 遥测串口 | DSHOT_TEL_CFG = 0 ⇒ 没配 | build/.../generated_params/serial_params.c:55 | ┃ BDShot（双向 DShot） | 需要 PWM_MAIN_TIM0 ∈ {-6,-7,-8} ⇒ 本板不是 | DShot.h:62 |
^src-src-drivers-dshot-DShot-h-62

### `src/lib/mixer_module/mixer_module.cpp`
<a id="src-src-lib-mixer-module-mixer-module-cpp-424"></a>
**↓ 文档在讲这里：**[`src/lib/mixer_module/mixer_module.cpp:424`](dshot.md#^src-src-lib-mixer-module-mixer-module-cpp-424)

```c
   421 │ bool MixingOutput::update()
   422 │ {
   423 │ 	// check arming state
▶  424 │ 	if (_armed_sub.update(&_armed)) {
   425 │ 		_armed.in_esc_calibration_mode &= _support_esc_calibration;
   426 │ 
   427 │ 		if (_ignore_lockdown) {
```
> **说明**：2 | PWM_MAIN_TIM0 不是 DShot 档 | param show PWM_MAIN_TIM0 → 400（缺省）；dshot status 报 No channels configured | module_params.c:2164；DShot.cpp:1126 | ┃ 3 | actuator_armed.armed = false | listener actuator_armed | mixer_module.cpp:424；源头 02_code_twin/modules/commander |
^src-src-lib-mixer-module-mixer-module-cpp-424

### `src/lib/mixer_module/output_functions.yaml`
<a id="src-src-lib-mixer-module-output-functions-yaml-5"></a>
**↓ 文档在讲这里：**[`src/lib/mixer_module/output_functions.yaml:5`](dshot.md#^src-src-lib-mixer-module-output-functions-yaml-5)

```c
     2 │   # Note: do not change the index of existing functions, as it will break
     3 │   # existing setups using it
     4 │   common:
▶    5 │     Disabled: 0
     6 │ 
     7 │     Constant_Min: 1
     8 │     Constant_Max: 2
```
> **说明**：1 | PWM_MAIN_FUNC1..4 全是 0（本板缺省就是 0） | param show PWM_MAIN_FUNC1 → 0；listener actuator_motors 有值但 listener actuator_outputs 无 | module_params.c:2243/2322/2401/2480；output_functions.yaml:5 |
^src-src-lib-mixer-module-output-functions-yaml-5

### `src/modules/sensors/vehicle_angular_velocity/VehicleAngularVelocity.hpp`
<a id="src-src-modules-sensors-vehicle-angular-velocity-VehicleAngularVelocity-hpp-106"></a>
**↓ 文档在讲这里：**[`src/modules/sensors/vehicle_angular_velocity/VehicleAngularVelocity.hpp:106`](dshot.md#^src-src-modules-sensors-vehicle-angular-velocity-VehicleAngularVelocity-hpp-106)

```c
   103 │ 	uORB::Subscription _estimator_selector_status_sub{ORB_ID(estimator_selector_status)};
   104 │ 	uORB::Subscription _estimator_sensor_bias_sub{ORB_ID(estimator_sensor_bias)};
   105 │ #if !defined(CONSTRAINED_FLASH)
▶  106 │ 	uORB::Subscription _esc_status_sub {ORB_ID(esc_status)};
   107 │ 	uORB::Subscription _sensor_gyro_fft_sub {ORB_ID(sensor_gyro_fft)};
   108 │ #endif // !CONSTRAINED_FLASH
   109 │ 
```
> **说明**：后果 | esc_status 话题被 advertise（DShot.cpp:55）但永远不会 publish（只在 :100-105 的"收到遥测"分支里发） | DShot.cpp:100 | ┃ ⇒ | esc_status 的消费者（VehicleAngularVelocity.hpp:106、logger :71）永远收不到东西 | |
^src-src-modules-sensors-vehicle-angular-velocity-VehicleAngularVelocity-hpp-106
