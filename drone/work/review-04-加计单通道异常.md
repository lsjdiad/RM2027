# review-04 · hxy 加计"单通道 3.6 倍"异常：根因穷举 + 判决实验 + 处置

- 审查人：code-auditor（**只读** PX4 源码 + 手册；未跑 openocd、未烧写、未改 PX4 源码）
- 目标：解开卡住六面标定的头号问题（`ERROR: invalid orientation`），并给出可执行的判决实验与处置选项
- 出处：PX4 源码路径相对 `/home/xien/桌面/RM2027/PX4-Autopilot/`；手册沿用 `HXY:<行>`（`华轩阳HXY_ICM-42688P_手册_文字提取.txt`）

---

> **【行号注记 · 本次更新】** 本文引用的行号对应 **`363de64`** 那一版源码
> （写作时间虽晚于 `9aeb3a0`，但引的是更早一版的行号）；现已更新至 **`HEAD 9aeb3a0`**，共改 **4 处**：
> `HXY42688P.cpp:630,661`→`655,690`、`:630`→`:655`、`:762-782`→`803-823`、`rc.board_sensors:62`→`85`。
> ⚠️ 漂移**随插入位置累积、不是加一个常数**：`HXY42688P.cpp` **≤580 行为 0、文件尾部最多 +41**
> （`ACCEL_GAIN_CORRECTION` 630→655 是 +25，`transfer` 762→803 是 +41 —— 同一文件里就横跨多个值）；
> `rc.board_sensors` 第 62 行以后统一 **+23**。换算依据见 `PX4改造-索引与纪律.md` **§2 末**。
> **本次只改行号**：条目中引用的代码**文本**保持写作当时的样子（部分内容此后已被修复），
> **全部结论与判定仍以本文原有论证为准，未作改动。**

# 第 0 部分 · 结论摘要（先看这三条）

### ★ 结论 1（**必须先查的前置事实**）：`detect_orientation` 看的**不是**每路的 `sensor_accel`

```cpp
// src/modules/commander/calibration_routines.cpp:90
uORB::SubscriptionBlocking<vehicle_acceleration_s> vehicle_acceleration_sub{ORB_ID(vehicle_acceleration)};
```

- `detect_orientation()`（`:66`）读的是 **`vehicle_acceleration`** —— 这是
  **「被选中那一路」的加计，且已经过标定矩阵修正 + 30 Hz 低通**：
  - 只有被选中的那一路会被订阅：`VehicleAcceleration::SensorSelectionUpdate()` → `_sensor_sub.ChangeInstance(i)`，
    `i` 来自 `sensor_selection.accel_device_id`（`VehicleAcceleration.cpp:158-190`）
  - 数据经过标定：`const Vector3f accel_corrected = _calibration.Correct(accel_raw) - _bias;`
    再 `_lp_filter.apply(...)`（`VehicleAcceleration.cpp:243-248`）
- **而六面标定的"取数"与"符号判定"读的是每路的 `sensor_accel`（原始、未标定、全部实例）**：
  `read_accelerometer_avg()` 里 `uORB::SubscriptionBlocking<sensor_accel_s> accel_sub[4]`（`accelerometer_calibration.cpp:172-177`）
- ✅ **【两次实测后定案】标定真正看的源是 H104。**
  第一次引的是**陈旧 topic**（`listener sensor_selection` 的 `timestamp` 已过期 661 s），第二次是现况：
  ```
  # 现况：sensors status
  selected gyro:  3735562 (0)          ← 投票器(voter)选的是 hxy
  selected accel: 3735562 (0)          ← 投票器选的也是 hxy
  [vehicle_acceleration]     selected sensor: 1677721613, rate: 100.0 Hz   ← 实际用的是 H104！
  [vehicle_angular_velocity] selected sensor: 1677721613, rate: 100.0 Hz   ← 也是 H104
  ```
  - `1677721613 = 0x6400000D` = **H104**（`DRV_IMU_DEVTYPE_HIPNUC_HI04 = 0x64`，`src/drivers/drv_sensor.h:110`）
  - `3735562 = 0x0039000A` = **hxy**（`DRV_IMU_DEVTYPE_HXY42688P = 0x39`，`drv_sensor.h:109`）
  - **`vehicle_acceleration` 才是 `detect_orientation` 读的东西**（`calibration_routines.cpp:90`）
    ⇒ **标定在看 H104（100 Hz 那一路）。**
- ⚠️ **由此得到一条新的结构性事实：PX4 里有两条互相独立的"选源"路径，本机实测不一致**

  | 路径 | 谁决定 | 本机实测 |
  |---|---|---|
  | ① 投票器 → `sensor_selection` 话题 | `VotedSensorsUpdate`：`DataValidatorGroup::get_best()` + **`CAL_ACCx_PRIO` 参数**（机制见 §2.5） | **hxy** |
  | ② `vehicle_acceleration` 实际订阅的源 | `VehicleAcceleration::SensorSelectionUpdate()` 的 `_calibration.device_id()`（**latch 住**，只在 `sensor_selection` 更新时才重评，`VehicleAcceleration.cpp:158-190`） | **H104** |

  **⇒ 要判断"标定在看谁"，只能看 `sensors status` 的 `[vehicle_acceleration] selected sensor:`（以及 `rate:`），不能看 `sensor_selection`。**
  ⇒ 我此前"被选中的是 hxy ⇒ 标定看 hxy"的推断**作废**（错在把投票器当成了 `vehicle_acceleration`）；
  而**我最初的 ①（标定看的很可能是 H104）成立**，虽然当时给的理由（外部优先级 75 > 内部 50）是错的 —— 真正机制见 §2.5。

### ★ 结论 2：**"4/6 完成、2 格卡住"这个模式本身就能把根因锁到唯一一类**（代码级推导，见 §2.3）

| 假设 | 会看到几格通过 | 与"4/6 完成"是否相容 |
|---|---|---|
| 某一个轴的**大零偏** | **0/6**（该轴在所有姿势都读 ≈offset，六个面都会有一个轴 >5 m/s²） | ❌ |
| **全局**倍数错（2×/4×，即量程回读错那种） | **0/6**（每个面都读 3.6g） | ❌ |
| 挂装/**框架偏转**（含 H104 的 `[y,x,−z]`、或 45° 歪装） | 小角度 ⇒ 6/6；大角度 ⇒ **2/6 或 0/6** | ❌（**产生不了 4/6**） |
| 纯运动/采集噪声 | 失败面**随机**、不固定 | ❌（Lead 观察到的是固定两格） |
| **单通道（单轴）增益异常** | **4/6**（只有"重力 ∥ 该轴"的两个面失败，其余四个面该轴读 ≈0 不受影响） | ✅ **唯一自洽** |

**并且 `-R 6` 的矩阵能直接指出是哪一轴错了** —— 见 §2.4 的可判决预言：
**失败的两格必须落在同一个"对面"上，且该对面直接对应出问题的芯片轴。**

### ★ 结论 3：Lead 点名的 A.4（15 字节突发布局）**已排除，不是根因**

- 逐字节推演（§4.1）+ SPI 传输实现证据（§4.2）⇒ `data[1..6]` **确实** = `0x0C..0x11`，与手册 §5.9~§5.14 一致；
- 并且**用 Lead 给的原始字节枚举所有可能的字节配对，没有任何一种能还原出 ~4678 码（1g）**（§1.2）
  ⇒ **异常发生在"器件交给总线的码值"这一层，不在驱动的解码/配对层。**

---

# 第 1 部分 · 把 Lead 给的原始数据重新算一遍

## 1.1 两组数字其实是同一件事

Lead 给的原始字节（姿势：重力在板 −X，`-R` 尚未修正时）：

```
XH=00 XL=36 | YH=BE YL=6D | ZH=02 ZL=3F
```

按驱动同样的拼法（H 在前、2 的补码，`HXY42688P.cpp:76-79`）：

| 轴 | 拼接 | 十进制 |
|---|---|---|
| X | 0x0036 | **54** |
| Y | 0xBE6D | **−16787** |
| Z | 0x023F | **575** |

`|a| = √(54² + 16787² + 575²) = 16797` 码

- 若该档 1g = 4678 码（`定案-1.77倍是纯增益…md:28`）⇒ 本姿势 **3.59 g**
- 驱动当前标度（含 1.7512 修正）= `0.0020964 m/s²/码`（`HXY42688P.cpp:655,690`）
  ⇒ `16797 × 0.0020964 = 35.21 m/s²`
- Lead 说的 "≈17143 码 ⇒ 35.9 m/s²"：`17143 × 0.0020964 = 35.94` ✓

⇒ **"raw |a| ≈ 17143 码"与"|a| = 35.9 m/s²"是同一现象的两种表述，不是两个独立证据。**
比值：`35.9 / 9.80665 = 3.66`；`16787 / 4678 = 3.59`（差 2%，在测量波动内）。

## 1.2 枚举所有字节配对 —— 排除"配对/边界"类根因

把 6 个 accel 字节按**任何**方式配成 3 个 int16（H 在前 / L 在前 / 整体错一格 / 交叉配对）：

| 配对方案 | 结果 | \|a\| |
|---|---|---|
| 正确：(00,36) (BE,6D) (02,3F) | 54 / −16787 / 575 | **16797** |
| L 在前：(36,00) (6D,BE) (3F,02) | 13824 / 28094 / 16130 | ~35000 |
| 错一格：(36,BE) (6D,02) (3F,? ) | 14014 / 27906 / … | **≥14014** |
| 交叉：(00,36) (6D,BE) (2F,3F) 类 | 54 / 28094 / … | **≥28000** |

**⇒ 没有任何配对能把 |a| 拉回 ~4678 码。**
再加上 `WHO_AM_I(0x01)` 稳定读回 `0x6A`（`HXY42688P.cpp:195-200`，probe 通过才启动），
⇒ **驱动发出去的命令帧法与 3 字节读路径是正确的**（若帧法是 `(addr<<1)|RW`，读 `0x01` 会命中 `0x40` 并读到 `0x8C`）。

**⇒ 结论：异常值就在器件给出的字节里。** 这直接排除了 A.4。

---

# 第 2 部分 · A：候选根因穷举（每条都给"看到什么就成立/不成立"）

## 2.1 先明确判据来自哪里（这一步很关键）

`detect_orientation()` 的判据（`calibration_routines.cpp:66-207`）：

| 量 | 值 | 出处 |
|---|---|---|
| 静止判定阈值（每轴方差） | `still_thr2 = 0.25²`（宽松模式 ×3） | `:73-74` |
| **静止时长要求** | **1.3 s**（宽松模式 0.5 s） | `:76` |
| **姿态容差** | `accel_err_thr = 5.0 m/s²`：期望轴必须落在 `g ± 5`，**另两轴必须 `< 5`** | `:75`、`:168-202` |
| 失败消息 | `ERROR: invalid orientation` | `:204` |
| EMA 时间常数 | 0.5 s | `:72` |
| 数据来源 | **`vehicle_acceleration`**（被选中 + 已标定 + 30 Hz 低通） | `:90` |

⚠️ **由 `:76` + `:137` 得到一个很强的排除**：**只有当板子静止 ≥1.3 s，才会进入姿态判定**。
如果那一刻真的是"手在动"，代码会先打 `[cal] detected motion, hold still...`（`:148`）并重置计时，
**根本走不到 `invalid orientation`**。⇒ 报出 `invalid orientation` 说明那一刻 **EMA 后的向量在 1.3 s 静止窗口里都没能匹配任何一面**。

**⇒ 纯运动（H1）作为 `invalid orientation` 的解释，与代码流程不相容。**
（但它**仍可能**解释 Lead 在另一次 `listener` 里看到的 35.9 —— 两者可能不是同一瞬间。见 §3.2 的 C2 判据。）

## 2.2 候选表

| # | 假设 | 成立会看到什么 | 不成立会看到什么 | 当前证据 |
|---|---|---|---|---|
| **H1** | **纯运动**（37 ms 差、手在动） | 同一姿势重复测，`\|a\|` 每次不同；静置 5 s 后恢复正常 ≈9.8；10 次采样内 std 大 | 静置后仍然 3.6× 且 std 小 | ⚠️ 对 `invalid orientation` **不相容**（§2.1 的 1.3 s 静止门）；对"35.9"未排除 |
| **H2** ★ | **单通道（单轴）真增益异常** | **只有 2 个面失败（同一对面）**；其他 4 面 `\|a\|≈9.8`；沿该轴的姿势 `\|a\|≈3.6×9.8`；std 与正常轴同比例（≈3.6× 正常噪声） | 失败面不固定；或所有面都失败；或该轴在非激励姿势也偏 | ✅ **唯一同时解释"4/6"与"35.9"的假设** |
| **H3** | **某轴大零偏** | 每个姿势下该轴都读一个**常数**；`\|a\|` 随姿势变化但模式是"某轴恒偏" | 该轴在垂直姿势读≈0 | ❌ 与大零偏不相容：`offset ≥6 m/s²` 会让**六个面全失败**（该轴在任何姿势都 >5）；`offset ≈4.8~5.0` 才有可能给出 4/6，但那样沿轴姿势只到 ~14.7 m/s²，**解释不了 35.9** |
| **H4** | **字节/寄存器布局**（A.4） | 配错 ⇒ 轴混合、方向余弦不是单一轴、`\|a\|` 在**所有**姿势都异常 | — | ❌ **已排除**：§1.2 的配对枚举 + §4 的逐字节推演 + §4.2 的 SPI 实现证据 |
| **H5** | **全局量程回读错**（`SetAccelScaleAndRange` 用一次性回读定标） | 所有姿势 `\|a\|` 都差同一个 2 的幂次 ⇒ **0/6** | 有的面通过 ⇒ 不是全局 | ❌ 与 4/6 不相容；**但它是已被 Lead 实测证明的真 bug**（见 §5），必须确认当前固件已改掉 |
| **H6** | **安装/框架偏转** | 方向余弦不是 1.0（重力分成两轴，各 ~0.7） | 方向余弦 ≈1.0（重力稳落单轴） | ❌ 与 4/6 不相容：45° 绕 Z 偏转 ⇒ 只有 ±Z 两面通过（**2/6**）；绕 X/Y 偏转 ≥30° ⇒ 只有 ±X 或 ±Y 两面通过（**2/6**）；小角度 ⇒ **6/6**。**产生不了 4/6** |
| **H7** ★ | **被选中的不是 hxy** | `sensors status` 的 selected accel = `0x6400000d`（H104）⇒ 失败的 2 面是 H104 的问题 | selected = hxy 的 device_id | ⚠️ **未确认，且代码倾向 H104（外部 75 > 内部 50）** ⇒ **必须最先查** |
| **H8** | **残留/部分标定**（`CAL_ACC*` 有脏值） | `param show CAL_ACC0_SCALE*` ≠ 1.0 或 `CAL_ACC0_ID` 非 0；`vehicle_acceleration` 与 `sensor_accel` 的比例在某轴 ≈3.6 | 全是缺省（SCALE=1、ID=0） | ⚠️ 代码倾向"不太可能"：**只有六面全部成功才会写参数**（`accelerometer_calibration.cpp:337-405`，`ParametersSave` 在 `:395`，前提是 `calibrate_from_orientation(...) == calibrate_return_ok`）。而本机从未 6/6 成功 ⇒ 应无脏值。**但一条 `param show` 就能定死** |
| **H9** | **器件饱和/自检状态** | `DATA_SAT(0x0A)` 对应轴 SAT 位 = **0（手册语义：0=已饱和）** 而码值只有 17k ⇒ 器件自相矛盾（强器件故障证据）；`GYR_MEMS_OK`=0 也算异常 | 所有 SAT=1（未饱和） | ⚠️ **驱动完全没读这个寄存器**（`review-01` L1）⇒ 只能用 ST-Link 单独读（§3.4） |
| **H10** | **器件行为（量程自切档）** | 手册里存在"自动换档"机制，且 `DATA_STAT` 的 `ACC_CONF_ERR` 置起 | 手册无此机制、`ACC_CONF_ERR`=0 | ❌ 手册**没有**任何 accel 自动换档条款；唯一"自动回退"是 §5.37 备注的 Reserved ODR ⇒ 回退到 `0xA8` 并置 `ACC_CONF_ERR=1`（`HXY:1698`）。实测 `DATA_STAT(0x0B)=0x07` ⇒ **两个 CONF_ERR 都是 0** ⇒ 器件自己认为配置合法 |

## 2.3 为什么"4/6"能把根因锁到单通道增益（推导）

`detect_orientation` 的六个面判据（`:168-202`）可以写成：设被选中那一路的向量为 `v`，

- **通过某个面** ⇔ 存在轴 `k` 使 `|v_k ∓ g| < 5` **且** 另外两轴 `|v_j| < 5`（`g = 9.80665`）

代入各种假设（设正常 1g ⇒ `v` 各轴 ≈ 0 或 ±9.8）：

| 假设 | 6 个面各会怎样 | 通过数 |
|---|---|---|
| 大零偏 `b`（`\|b\| ≥ 6`） | 该轴在所有姿势都读 `≈ b` ⇒ 每个面都有一轴 `>5` | **0** |
| 全局增益 `k=3.6` | 每个面都有轴读 35.3，`\|35.3−9.8\|=25.5>5` | **0** |
| 全局增益 `k` 使 `\|k·9.8−9.8\|<5` 且 `k·0=0` | 即 `0.49<k<1.51` ⇒ 全部通过 | **6** |
| **单轴增益 `k_Y=3.6`** | 重力∥Y 的 2 个面：该轴读 35.3 ⇒ 失败；其余 4 个面：Y 轴读 `≈0`（×3.6 仍是 0）⇒ 通过 | **4** ✅ |
| 挂装偏转 | §2.2 H6：只有 6/2/0 | **6 / 2 / 0** |

**⇒ 只有"单轴增益异常"能给出 4/6。** 这与 Lead 的观察**完全吻合**，并且与 §1 的 3.6× 一致。

> ⚠️ **这张表与"识别源是哪一路"无关**（它只依赖 `detect_orientation` 的判据形式）：无论源是 hxy 还是 H104，
> "大零偏/全局倍数/挂装偏转"都产生不出 4/6，而"**某一个轴**的增益异常"总是恰好产生 4/6。
> 所以现在源已定案是 H104，**结论变成：要查的是 H104 有没有单轴增益异常**（而不是 hxy）。
> 但注意：**单轴增益异常必定同时打掉"一对相反面"**（重力 +A 与 −A 时 |k·g| 同样错）。
> ⇒ **若实测卡住的 2 格不是一对相反面 ⇒ "单轴增益"被推翻**，此时最像的解释是 §2.5 的"选源抖动/刀锋混合"（见 §3.4）。

## 2.5 ★ 选源到底由什么决定（更正我上一轮的推断）+ 处置 B 的两个新风险

### 2.5.1 为什么"外部 75 > 内部 50"没生效（我上一轮错在哪）

`Accelerometer.cpp:214` / `:244` 那个 `_priority = _external ? 75 : 50` 是**标定对象自己的**优先级，
**投票器根本不读它**。投票器用的 `sensor_data.priority[i]` 只有两个来源：

1. `initSensorClass()`：注册时给**所有**实例 `priority[i] = priority_configured[i] = DEFAULT_PRIORITY`（**50**，`voted_sensors_update.cpp:363-364`、`voted_sensors_update.h:107`）——**不分内外**；
2. `parametersUpdate()`：用 **`CAL_ACCx_PRIO` 参数**做**相对增量**调整（`voted_sensors_update.cpp:96-115`）：
   ```cpp
   int32_t accel_priority_old = _accel.priority_configured[uorb_index];                 // 先取旧值
   _accel.priority_configured[uorb_index] = GetCalibrationParamInt32("ACC","PRIO",idx); // params 里的真值
   if (old != new) {
       if (new == 0)      _accel.priority[i] = 0;                                       // 0 = 禁用
       else { int change = new - old; _accel.priority[i] = constrain(_accel.priority[i] + change, 1, 100); }
   }
   ```
   而 **`CAL_ACC0_PRIO` / `CAL_ACC1_PRIO` 的出厂缺省是 `-1`**（`build/rm2027_fmu-h743_default/generated_params/module_params.c:18566,18584`）
   ⇒ 第一次 `parametersUpdate()`：`old=50`、`new=-1` ⇒ `change = -51` ⇒ **`priority = constrain(50-51,1,100) = 1`**，
   **两路都被压到 1** ⇒ 平票。
3. 平票时由 `DataValidatorGroup::get_best()` 裁决：它先拿 `_curr_best` 作种子（`_curr_best` 初值 **-1**，`DataValidatorGroup.hpp:141`），
   只有当"置信度明显更高"或"置信度几乎相同**且优先级更高**"时才切换（`DataValidatorGroup.cpp:154-228`，判据在 `:210-218`）
   ⇒ **同优先级同置信度 ⇒ 不退位** ⇒ **先注册的 index 0（`rc.board_sensors:85` 先起 hxy）胜出** ✓
   **⇒ 这正好解释了"投票器选 hxy"**（以及为什么 75/50 从来没起作用）。

### 2.5.2 那要让投票器改选 H104，该设哪个参数

**设 H104 所在标定索引的 `CAL_ACCx_PRIO` 即可**（x 由 `CAL_ACCx_ID == 0x6400000D` 决定，见下）：
- 只设 H104 的（hxy 保持 -1）：`old=-1, new=80` ⇒ `change = 80-(-1) = 81` ⇒ `priority = constrain(1+81) = 100`；hxy 仍为 1 ⇒ **H104 胜出**
- 或两个都显式设：`CAL_ACC0_PRIO 50` + `CAL_ACC1_PRIO 80` ⇒ hxy = 50、H104 = 80 ⇒ H104 胜出
- ⚠️ **不要**用 `CAL_ACCx_PRIO 0`（= 禁用）：`priority 0` 会被 `get_best()` **完全排除**（`DataValidatorGroup.cpp:199-204`），
  且 `imuPoll()` 也会跳过它（`voted_sensors_update.cpp:146`）⇒ 那一路 IMU 直接从 `sensor_combined`/`vehicle_imu` 消失（等于选项 C）。

**先确认索引**：`param show CAL_ACC*_ID`，与 `sensor_selection`/`sensors status` 里的两个 id 对照
（hxy = `3735562`、H104 = `1677721613`）。H104 的索引通常是 **1**（hxy 先注册占 0），但务必用 ID 核实。

**⚠️ 但仅改 PRIO 不保证改掉 `vehicle_acceleration` 的源**：那条路是 `VehicleAcceleration` **latch** 的
（§0 结论 1 的表）⇒ **改完 PRIO 要重启，然后用 `sensors status` 的 `[vehicle_acceleration] selected sensor:` 复核**。

### 2.5.3 🔴 处置 B 的两个新风险（**必须先验，否则会把好的一路彻底搞坏**）

1. **姿态标签的"框架"来自被选中那一路，而矩阵解算对每一路都做**
   - `detect_orientation` 用**源设备**的框架给出 6 个标签；`read_accelerometer_avg()` 却**为所有实例**填 `accel_ref[实例][标签]`
     （`accelerometer_calibration.cpp:172-177`）；矩阵按标签行组装：`mat_A.row(0)=tail−off`、`row(1)=left−off`、`row(2)=upside−off`
     （`:363-367`），再 `accel_T = mat_A.I() * CONSTANTS_ONE_G`，`set_scale(diag)`（`:370-379`）。
   - ⇒ 若**两路的 published 框架不一致**（例如差 90°），那么对"不是源那一颗"的设备来说，
     `mat_A` 会变成一个**带符号的置换矩阵**，而置换矩阵的**对角元 ≈ 0** ⇒ `set_scale(≈0)`
     ⇒ `Accelerometer::Correct() = R*((data-offset).emult(scale))`（`Accelerometer.hpp:84-87`）⇒ **该路输出直接变 0**（灾难，不是"差一点"）。
   - 而**符号判定拦不住它**：`:222-273` 只查期望轴的符号，框架错位时那一轴的读数 ≈0（`0 < 0` 为假）⇒ **静默通过**。
   - ⇒ **⇒ 在走 B 之前，必须先证明"两路的 published 框架一致"**（§3.4 的多姿态对照就是干这个的：
     同一姿势下两路的单位向量必须指向同一轴、同一符号）。
2. **选源本身在抖**：用户实测 `validator: best: 0, prev best: 0, failsafe: YES (2 events)`、
   `vehicle_angular_velocity: gyro filter reset: 3, gyro selection changed: 3`
   ⇒ 源的切换会让 `detect_orientation` 的 0.5 s EMA 窗口**混进另一路的框架**，
   混出来的向量可能是 (6.9, 6.9, 0) 这种"两个分量都 >5"的形态 ⇒ **正是 `invalid orientation`**（详见 §3.4）。
   ⇒ **先把这个抖动治好（或确认它不影响 accel），再做标定。**

## 2.6 ★ 可判决预言（**不要看截图，看 console 的 `pending:` 行**）

> ⚠️ 我**无法**读 QGC 的 QML：这台机器上没有 QGC 源码，我的沙箱里 web 检索也不可用。
> 所以**不要用截图判**。PX4 自己就会把"还缺哪几个面"用**标准名字**打出来。

`calibrate_from_orientation()`（`calibration_routines.cpp:262-272`）：

```cpp
for (cur_orientation = 0; cur_orientation < 6; cur_orientation++)
    if (!side_data_collected[cur_orientation]) { strncat(pendingStr, " ", ...); strncat(pendingStr, detect_orientation_str(cur_orientation), ...); }
calibration_log_info(mavlink_log_pub, "[cal] pending:%s", pendingStr);
```

⇒ **console 里每轮都会打 `[cal] pending: <还缺的面名>`**，名字来自 `detect_orientation_str()`
（`:209-221`，顺序 = 枚举顺序 `calibration_routines.h:43-51`）：

| 枚举 | 名字 | 含义 | 反面 |
|---|---|---|---|
| `ORIENTATION_TAIL_DOWN` | `back` | 尾朝下 ⇒ 重力沿 **+X** | `front` |
| `ORIENTATION_NOSE_DOWN` | `front` | 头朝下 ⇒ 重力沿 **−X** | `back` |
| `ORIENTATION_LEFT` | `left` | 重力沿 **+Y** | `right` |
| `ORIENTATION_RIGHT` | `right` | 重力沿 **−Y** | `left` |
| `ORIENTATION_UPSIDE_DOWN` | **`up`** | 倒扣 ⇒ 重力沿 **+Z** | `down` |
| `ORIENTATION_RIGHTSIDE_UP` | **`down`** | 正放 ⇒ 重力沿 **−Z** | `up` |

⚠️ **命名陷阱**：`"up"` 是**倒扣**、`"down"` 是**正放**（`calibration_routines.cpp:214,216` 的注释）。

**判决规则（写死）**：
- `pending` 里剩 **`left`+`right`** ⇒ 卡的是 **±Y 一对** ⇒ 源的 **X 轴**异常；
- 剩 **`back`+`front`** ⇒ **±X 一对** ⇒ 源的 **Y 轴**异常（若源是 hxy，则呼应 §1 的 `Y=−16787`）；
- 剩 **`up`+`down`** ⇒ **±Z 一对** ⇒ 源的 **Z 轴**异常；
- **剩的不是一对**（例如 `front` + `left`） ⇒ **"单轴增益"被推翻** ⇒ 转查 §3.4 的"选源抖动/刀锋混合"。

**另外两个必须知道的机制（都影响现场判读）**：
1. **`ORIENTATION_ERROR` 被当成"检测到运动"计数**（`calibration_routines.cpp:276-281`）：
   `if (orient == ORIENTATION_ERROR) { orientation_failures++; log("[cal] detected motion, hold still..."); }`
   ⇒ 你会同时看到 `ERROR: invalid orientation`（关键）**和** `[cal] detected motion, hold still...`（**误导性文案**）。
2. **连续 5 次就整体放弃**：`if (orientation_failures > 4) { ... "[cal] timeout: no motion" }`（`:240-243`）。
   ⇒ "4/6 完成、2 格卡住"能停在 4/6，说明用户在中间成功过别的面（成功会 `orientation_failures = 0`，`:298`）；
   **否则整个标定会在 5 次失败后直接 abort**（这也解释了为什么现场看起来"卡住"而不是"继续等"）。

---

# 第 3 部分 · B：判决实验设计（给 Lead 可直接执行）

## 3.1 第 0 步（**必须最先做，10 分钟**）：确认"标定到底在看哪一路"

> 这一步决定后面所有结论属于哪颗器件。**在跑它之前不要动硬件。**

```text
# ① 标定到底在看哪一路 —— 只认 [vehicle_acceleration] 那一行
sensors status
#   → 【权威】"[vehicle_acceleration] selected sensor: <id>, rate: <Hz>"
#        1677721613 (0x6400000D) = H104；3735562 (0x0039000A) = hxy
#        rate 也是一个活体指示器：100 Hz ⇒ H104；~1000 Hz ⇒ hxy
#   → 【仅供参考、可能陈旧/不一致】"selected accel: <id>"（那是投票器，与上面那条实测可以不同）
#   → ⚠️ 不要用 listener sensor_selection 判：本机就踩过"它 661 s 没更新"的坑

# ② 标定参数有没有脏值（H8）
param show CAL_ACC*
#   → 重点看 CAL_ACC0_ID / CAL_ACC1_ID（0 = 未标定；用它确认哪组属于 H104）
#           CAL_ACC0_PRIO / CAL_ACC1_PRIO（★ 缺省是 **-1**，不是 50/75！见 §2.5.1）
#           CAL_ACC0_ROT / CAL_ACC1_ROT（外部件的旋转；-1 ⇒ 回落到 ROTATION_NONE）
#           CAL_ACCx_SCALE{X,Y,Z}（应全 = 1.0）、CAL_ACCx_OFF{X,Y,Z}（应全 = 0.0）

# ③ 标定真吃的那路数据 vs 每路原始数据
listener vehicle_acceleration      # ★ 话题名必须在最前（本版 listener 取 argv[1] 作话题名）
listener sensor_accel              # 会打出所有实例，可区分两路
```

> ⚠️ **命令写法更正（Lead 实测 + 源码已核）**：本版 `listener` 把 **`argv[1]` 直接当话题名**
> （`listener_main.cpp:178 char *topic_name = argv[1];`），而 `px4_getopt` 会先 `reorder()` 重排 argv
> （`platforms/common/px4_getopt.c:147-152`）⇒ 写 `listener -n 3 sensor_mag` 时 `topic_name` 抓到的是 **`-n`**，
> 于是报 `Topic -n did not match any known topics`（同一报错在 `listener_main.cpp:239`）。
> ⇒ **正确形式：`listener <topic>` 或 `listener <topic> -n N -i I`（话题名放最前）。**
> 本报告（以及 `review-02`/`review-03`）此前命令清单里的 `listener -n N <topic>` 都要按此改正。
> 另外：`vehicle_acceleration` 的**消息里没有 device_id 字段**（`msg/VehicleAcceleration.msg` 只有
> `timestamp/timestamp_sample/xyz`）⇒ 想知源只能靠 `sensors status` 那一行或**输出行速率**。

**判读**：
- `[vehicle_acceleration] selected sensor` = **1677721613（H104）** ⇒ **识别源是 H104**（本机现况）
  ⇒ `invalid orientation` 要按 H104 查（§3.4），而 hxy 的 3.6 倍是**另一个**问题（但它在
  `read_accelerometer_avg` + 符号判定里仍会参与；符号判定只看符号 ⇒ 3.6× 不会让它失败）。
- `= 3735562（hxy）` ⇒ 识别源是 hxy ⇒ 按 §1 + §2.6 的预言查。
- `CAL_ACC*_SCALE` 非 1.0 ⇒ H8（残留标定）成立，先 `param reset CAL_ACC0_*`（或对应那组）再标定。

## 3.2 多姿态静置 + 方向余弦（主实验）

**板子怎么摆（10 个姿势，比六面更能分离"轴"与"框架"）**

| 组 | 姿势 | 目的 |
|---|---|---|
| A1~A6 | 六个正对面朝下/朝上（TAIL/NOSE/LEFT/RIGHT/UP/DOWN） | 复现标定的六个面；每个芯片轴各被激励 2 次 |
| B1~B2 | 平放，然后绕垂直轴原地**转 90°**再放平 | 区分"芯片轴增益"与"板轴挂装偏转"：纯增益下 `\|a\|` 不变、方向随板转；挂装偏转下方向会跑偏 |
| C1~C2 | 45° 靠墙/靠垫（重力分成两轴） | 直接看方向余弦（H6） |

**每个姿势的操作（严格）**

```text
1) 放稳后【不碰板子】等 5 s（标定自己要 1.3 s 静止；留 4× 余量）
2) listener sensor_accel -n 200            # 两个实例都要，落盘
3) listener vehicle_acceleration -n 200    # 标定真正吃的那个信号
4) hxy42688p status                        # 配置回读 + bad_register/bad_transfer/stale 计数
5) h104_imu status                         # 对照（CRC/帧率）
```
> 上面 4 条命令**都够用，不需要 QGC 截图、不需要 ST-Link**。

**每个姿势要算的统计量（离线，用一段小脚本）**

| 量 | 定义 | 用途 |
|---|---|---|
| `m` | 200 个样本的**逐轴均值** | 主判据 |
| `\|m\|` | 均值向量的模 | 1g 是否成立 |
| `sd_i` | 逐轴**样本标准差** | 运动 vs 器件（H1 vs H2） |
| `u = m/\|m\|` | **方向余弦** | 判断重力落在单轴还是分裂（H6） |
| `gain_k` | 沿轴 `k` 的姿势下 `\|m\|/9.80665` | 逐轴表观增益（H2/H3 的分辨） |

**把 6 个 A 组姿势排成一张表（关键输出）**

| 姿势（重力方向） | 对应芯片轴 | `\|m\|`（hxy） | `gain` | `sd` | 方向余弦 | `\|m\|`（H104） |
|---|---|---|---|---|---|---|
| 平放 Z 朝上 | Z | ? | ? | ? | (0,0,1)? | ? |
| 倒放 Z 朝下 | Z | ? | ? | ? | | |
| 板 +X 朝下 | X | ? | ? | ? | | |
| 板 −X 朝下 | X | ? | ? | ? | | |
| 板 +Y 朝下 | Y | ? | ? | ? | | |
| 板 −Y 朝下 | Y | ? | ? | ? | | |

## 3.3 判据（决策树，写死）

```
Step 1  先看 sd（每个姿势 200 样本）
        sd 全部 < 0.05 m/s² 且两次重复测量（间隔 30 s）的 |m| 差 < 0.1 m/s²
            ⇒ 数据是"静止"的 ⇒ 【排除 H1 运动】 → Step 2
        sd 大 / 两次重复差 > 0.3 m/s²
            ⇒ 【H1 运动/不可复现成立】 → 结论：之前那个 35.9 是瞬态，
               重测时把手拿开、等 5 s 再说；若仍复现则回到 Step 2

Step 2  看方向余弦 u
        所有姿势都有某个 |u_i| > 0.99（重力稳落单轴）
            ⇒ 【排除 H6 挂装偏转】 → Step 3
        某个姿势出现两个 |u_i| ≈ 0.7
            ⇒ 【H6 成立】 → 该轴的 -R/挂装错了，先修 -R（与本报告 §2.4 的映射表核对）

Step 3  看逐轴 gain
        所有 gain ∈ [0.94, 1.06]
            ⇒ 全部正常 ⇒ 【H2/H3 都不成立】：回到 §3.1，八成是选中的设备搞错了，
               或者卡住的 2 格另有原因（把 QGC 里那两个面的名字贴出来，按 §2.4 反查）
        某一个轴 gain ≈ 3.6（且只有该轴）
            ⇒ 【H2 单通道增益异常 成立】★ → §4 处置
        某个轴在所有姿势都读一个常数（垂直姿势也不为 0）
            ⇒ 【H3 零偏 成立】 → 按 §4 选项 A' 处理（用 offset 而不是 gain）

Step 4  对照 vehicle_acceleration 与 sensor_accel
        两者比值在某轴 ≈ 3.6
            ⇒ 【H8 残留标定 成立】 → param show CAL_ACC* 确认后 param reset
        两者一致
            ⇒ H8 排除
```

## 3.4 可选（交给 Lead，需要 ST-Link）：读 `DATA_SAT(0x0A)`

驱动**从未读**这个寄存器（`review-01` L1）。手册语义（`HXY:1011-1039`，列对齐实测）：

| 位 | 名称 | 语义 |
|---|---|---|
| B6 | `GYR_MEMS_OK` | **1 = 陀螺自检正常**（`HXY:1019-1021`） |
| B5/B4/B3 | `SAT_GYR_Z/Y/X` | **0 = 已饱和；1 = 未饱和**（`HXY:1022-1030`） |
| B2/B1/B0 | `SAT_ACC_Z/Y/X` | **0 = 已饱和；1 = 未饱和**（`HXY:1031-1039`） |

**判据**：在"重力沿异常轴"的姿势下读 `0x0A`：
- 若该轴 SAT 位 = **1（未饱和）** ⇒ 器件认为码值正常 ⇒ 与 3.6× 相辅相成，坐实"标度/增益在器件内部就错了"；
- 若该轴 SAT 位 = **0（已饱和）** 而码值只有 17k（远未到 32767） ⇒ **器件自相矛盾** ⇒ 强器件故障证据（应返修/换件）。

⚠️ 用 ST-Link 读时必须带 `work/spi-runtime/quiet-test.tcl:26-42` 的净化前奏
（`SPI1_CR1 = 0x00001200`：停 SPE 保 SSI、关 DMA 请求、清 IFCR、排空 FIFO，再写回 `0x00001201`；
**绝不写 `CR1=0`**）+ **每寄存器连读两次、不一致就重试**。

---

## 3.4 ★ 在卡住的那个姿势下、**只靠 `listener vehicle_acceleration`** 的判据（Lead 点名要）

> 这条专治"识别源是 H104 但六面识别仍然失败"的情形。**一条命令、一个姿势、判到底。**
> 唯一的坑：`vehicle_acceleration` 的消息**不带 device_id**（`msg/VehicleAcceleration.msg` 只有 xyz+时间戳）
> ⇒ 源的判断只能靠 `sensors status` 那一行 **或输出行速率**。

```text
# 【操作】把板子摆到卡住的那个姿势，静止 5 s 不碰它，然后：
listener vehicle_acceleration                 # 不带参数 = 只打 1 条；要看一串就 listener vehicle_acceleration -r 100 -n 200
#   ⚠️ 话题名必须在最前（见 §3.1 的命令写法更正）
sensors status                                # 看 [vehicle_acceleration] selected sensor / rate
```

**三个可判的量（全部来自上面两条命令）**

| 量 | 怎么读 | 它说明什么 |
|---|---|---|
| ① 每行 xyz | 逐行看 | 向量是否"轴对齐" |
| ② 输出行速率 | 1 s 内数行数（或看 `sensors status` 的 `rate:`） | **100 Hz ⇒ 源=H104；≈1000 Hz ⇒ 源=hxy**（H104 帧率 100 Hz、hxy 轮询 1 kHz） |
| ③ 逐行波动 | 同一次录制里逐行比较 | 源在切换（churn）⇒ 行与行之间会**整段换成另一个框架** |

**判据（写死，一次录制取 20~100 行即可）**

| 观察 | 判定 | 依据 |
|---|---|---|
| **恰好一个分量 ∈ [4.81, 14.81]，另两个 `< 5`**，且整段稳定 | 向量**是**一个合法面 ⇒ 若标定仍报 `invalid orientation`，则**失败发生在别的时刻**（→ 看 ③ 是否有波动；或当时并非该姿势） | `calibration_routines.cpp:75,168-202` |
| 两个分量都是 **~6.9 ± 1**（两个都 >5） | **非轴对齐**：稳定复现 ⇒ **挂装/框架偏转**（>30°）；间歇出现 ⇒ **选源抖动/刀锋混合** | `:75`（两轴都 >5 ⇒ 无面匹配） |
| 一个分量 **> 14.81**（例如 35.9） | 该源的**标度/增益**问题 | 同上 |
| **所有 \|分量\| < 4.81** | 源是**另一路且框架转过去了**（两路框架不一致），或姿势根本不是六个面之一 | 同上 |
| 整段录制里**行速率在 100 Hz 与 ~1000 Hz 之间跳**，或 xyz 出现**两种固定模式交替** | ✅ **选源抖动（churn）确认** —— 这是"4/6 且卡的不是一对相反面"的最可能解释 | §2.5.3-2；`validator ... failsafe: YES (2 events)`（用户实测） |
| 同一姿势**重复 3 次**，判定结果**翻转** | 同上（抖动/刀锋），**不是**稳定的单轴增益 | — |

**为什么"非成对失败"会指向 churn 而不是单轴增益**：
- 单轴增益 `k_A`：重力沿 **+A** 和 **−A** 时读数都是 `k_A·g`（同样错）⇒ **必然同时打掉一对相反面**；
- churn：0.5 s EMA（`calibration_routines.cpp:72`）在切换瞬间会把两路**不同框架**的向量混起来
  （例如 (9.8,0,0) 与 (0,±9.8,0) 各半 ⇒ (4.9,±4.9,0)：恰好两个都 <5 ⇒ **通过**；比例稍偏 ⇒ 第二个 >5 ⇒ **失败**）
  ⇒ **刀锋效应**：每个面独立地"过/不过"，**不要求成对**，且重复测量会翻转 ✓

**先做的两件"排除"（都能用上面同一条命令完成）**

| 候选 | 用 `listener vehicle_acceleration` 如何排除 |
|---|---|
| **姿态本身不是六个面之一**（手持角度） | 若每行都是"两个分量 ≈6.9"且**极其稳定**、重复 3 次完全一致 ⇒ 这是**固定偏转**（挂装/手持），不是随机失败 |
| **`vehicle_acceleration` 被标定修正/减 bias 顶出界** | **可以用算术排除**：用户实测 `offset [0.002 −0.003 −0.020]`、`scale [1 1 1]`、`estimated bias [0.0374 −0.3067 −0.0238]` ⇒ 修正量 `&#124;Δ&#124; ≤ 0.32 m/s²`（`Accelerometer::Correct` = `R*((data−off).emult(scale))`，`Accelerometer.hpp:84-87`；bias 与 offset 相加最多 0.32）⇒ **不可能把 9.81 推到 ±5 m/s² 的窗口之外** ⇒ **该项排除** |

**⇒ 若 ①（合法面 + 稳定）成立，那就是 §2.5.3-1/2 的情形：识别源与"取数/符号判定"用的源不是同一条路，
或源在抖 ⇒ 先解抖动与选源一致性，再谈 hxy 的 3.6 倍。**

## 3.5 ★ "抖动是谁引起的" + 钉哪一路 —— 判据与协议（Lead 点名要）

> 计划（Lead）：把选源钉死再加标定。**方向对**，但顺序要改一下：
> **先查清"谁在 failover、为什么"，再决定钉哪一路** —— 因为"钉住"只是把抖动变成"稳定地用一个源"，
> 如果被钉的那一路本身有毛病，就会变成"稳定地喂坏数据"。

### 3.5.1 第一优先：让 PX4 自己说出"谁 failover 了、为什么"

投票器在切换时会打**带原因标志**的日志（`voted_sensors_update.cpp:303-315`）：

```c
mavlink_log_emergency(..., "%s #%i fail: %s%s%s%s%s!", sensor_name, failover_index,
                      OFF / " STALE" / " TIMEOUT" / " ERR CNT" / " ERR DNST");
```

⇒ **在 console / ULog / QGC 的消息栏里搜 `fail:`**，就能直接看到形如
`Accel #1 fail:  ERR CNT!` 的条目（还有配套的 `events` 记录 `"{1} sensor #{2} failure: {3}"`）。

| 看到 | 含义 | 该钉哪一路 |
|---|---|---|
| `Accel #1 fail: ...` / `Gyro #1 fail: ...` | **H104（index 1）被降权** | 钉 **hxy**（0） |
| `Accel #0 fail: ...` / `Gyro #0 fail: ...` | **hxy 被降权** | 钉 **H104**（1） |
| 两种都出现 | 两边都被判过故障 | 先修故障源，**不要急着钉** |
| 一条都没有 | 抖动不是由 failover 引起的 | 转 §3.5.2 的 A/B 实测判"谁引起的" |

原因标志的读法：`ERR CNT` = 该路 `error_count` 飙升；`STALE`/`TIMEOUT` = 数据停滞/超时；
`ERR DNST` = 错误密度高；`OFF` = 无数据。**这比看最终选源有用得多。**

⚠️ **一个必须记住的坑**：`h104_imu` 的 `error_count` **恒为 0**（它从不调用 `set_error_count`，见 `review-01`/`review-02`）。
⇒ **不能用"H104 error_count=0、hxy error_count=2"比较两路谁干净**。要比就比：
`[vehicle_imu] N` 的 **generation gap 计数**、`h104_imu status` 的 `CRC坏/重同步跳字节`、`hxy42688p status` 的 `bad register/bad transfer/stale`。

### 3.5.2 A/B 实测：钉住一路 → 重启 → 记录（协议）

每轮只改一件事，**改完必须重启**（`VehicleAcceleration` 的源是 latch 的，§2.5.2），然后：

```text
# 每轮都做同样三件事
sensors status                                  # ① 确认 [vehicle_acceleration] 的源与 rate（100 Hz=H104 / ~1 kHz=hxy）
listener vehicle_acceleration -n 300            # ② 3 s 数据（话题名在前！）
sensors status                                   # ③ 再看一次（确认中途没换源）
```

**要算的 4 个量**
1. **输出行速率**（条数 ÷ 秒数）：应与 `①` 的 `rate` 一致。
2. **到达间隔直方图**（相邻 `timestamp` 之差）：正常应集中在 **1 ms（hxy）或 10 ms（H104）**。
   ⇒ **出现"两个峰"（1 ms 与 10 ms 同时存在）就是 churn 的铁证**（两路帧率差 10 倍，混样骗不了人）。
3. **轴对齐计数 `N_bad`**：一帧里"两个分量都 >5 m/s²"或"全部分量 <4.81"的帧数。
4. **逐轴 mean / SD**（静止时 SD 应 < 0.05 m/s²；H104 的 interval SD 已达 562 µs，见 §3.1.2 注，别把它当噪声）。

**判据（写死）**

| 观察 | 判定 | 行动 |
|---|---|---|
| 两轮都 `N_bad = 0`、间隔单峰 | **没有 churn**，之前的失败是姿势/运动 | 按"质量"选：见 §3.5.3 |
| 只在钉 hxy 那轮 `N_bad > 0` 或间隔双峰 | **hxy 是抖动源** | **钉 H104**；hxy 的毛病（`error_count`、gap）单独立案 |
| 只在钉 H104 那轮出问题 | **H104 是抖动源** | **钉 hxy** |
| **两轮都出问题** | 抖动在**投票器/上位**，不在被钉的那一路 | 用 §3.5.1 的 `fail:` 日志定位；不要急着标定 |
| 钉了 A 但 `rate` 仍是 B 的速率 | **pin 没生效**（latch 没吃到新 `sensor_selection`） | 检查 `CAL_ACCx_ID` 是否指对了索引；确认真的重启了 |

### 3.5.3 若两轮都干净：钉哪一路？

| 维度 | 钉 hxy（index 0） | 钉 H104（index 1） |
|---|---|---|
| 采样率 | **1000.0 us / SD 11.7 us**（抖动 1.2%） | 10000.0 us / **SD 562.2 us**（抖动 5.6%） |
| 对**内环**（`IMU_GYRO_RATEMAX`，缺省 400 / MC 机型 800） | ✅ **够用（1 kHz）** | ❌ 只有 100 Hz，内环被压到 100 Hz |
| 对 EKF2（`IMU_INTEG_RATE` 缺省 200） | ✅ 每 8 样本一个 delta | ⚠️ 每样本一个 delta（正好 200 vs 100 不齐） |
| 已知毛病 | `error_count: 2`、generation gap 1、`GYR_CONF` 写不进、逐轴比 0.779/0.888/1.007 | `error_count` 恒 0（**不可观测**）、无身份校验、`_perf_overflow` 无统计 |
| 结论 | **首选目标**（板载 1 kHz 本该是主 IMU） | 只作为"hxy 已证有问题"时的过渡 |

**⇒ 我的建议**：
1. **先用 §3.5.1 的 `fail:` 日志**判定谁被降权 —— 这一步零成本、信息量最大；
2. **若日志说 hxy 没问题** ⇒ 按 A/B 协议确认两轮都干净后，**钉 hxy 作为主 IMU**（内环 1 kHz，H104 留作 EKF 辅助）；
3. **若日志点名 hxy** ⇒ 钉 H104 先把标定跑完（过渡），同时把 hxy 的 `error_count/gap/GYR_CONF` 立案修；
   —— 但注意：**"过渡"不等于"可以一直这样飞"**，H104 只有 100 Hz/80~200 Hz 带宽（`review-03` §1.3），内环会明显变差。

### 3.5.4 补充：新时序数据其实**加强**了 churn 假设

`detect_orientation` 的 EMA 权重是 `w = dt / ema_len`，`ema_len = 0.5 s`（`calibration_routines.cpp:72,103`）：

| 源 | dt | 每个样本的 `w` | 收敛所需样本 |
|---|---|---|---|
| hxy | 1 ms | **0.002** | ~500 |
| H104 | 10 ms | **0.02** | ~50 |

⇒ 两路的"混合速度"差 **10 倍**：切换时**当前喂数据的那一路会迅速主导 EMA**，另一路要很久才被冲掉
⇒ **同一姿势下、不同切换时刻，EMA 结果会落在完全不同的位置** ⇒ 这就是"刀锋效应"的机制。
再加上 H104 的 562 µs 间隔抖动（相对 10 ms 是 5.6%），混样时的相位差会更大。

# 第 4 部分 · A.4 的正式答复：15 字节突发布局逐字节核对

## 4.1 布局推演（结论：**正确**）

**结构体**（`HXY42688P.hpp:127-133`）：
```cpp
struct DataReadBuffer { uint8_t cmd{0x0B | 0x80}; uint8_t dummy{0}; uint8_t data[13]{}; };
static_assert(sizeof(DataReadBuffer) == 15);
```

**线上字节**（手册 §3.2.1 `HXY:639-650`；§3.2 `HXY:619-630`：
"Bit0=RW、Bit1-7=地址、Bit8-15=数据…如果是读，则电路会在 bit8 开始驱动 SDO"）：

| 线上序号 | 内容 | 说明 |
|---|---|---|
| 字节 0 | `0x8B`（=`0x0B｜0x80`） | 命令；此时器件尚未驱动 SDO |
| 字节 1 | `r1` = **0x0B DATA_STAT** | 器件从 bit8 起驱动 ⇒ 第 2 个字节才是数据 |
| 字节 2 | `r2` = 0x0C ACC_XH | 手册 §5.9（`HXY:1071-1073`） |
| 字节 3 | `r3` = 0x0D ACC_XL | 同上 |
| 字节 4 | `r4` = 0x0E ACC_YH | §5.10（`HXY:1075-1077`） |
| 字节 5 | `r5` = 0x0F ACC_YL | 同上 |
| 字节 6 | `r6` = 0x10 ACC_ZH | §5.11（`HXY:1079-1081`） |
| 字节 7 | `r7` = 0x11 ACC_ZL | 同上 |
| 字节 8~13 | `r8..r13` = 0x12~0x17 | §5.12~§5.14 陀螺三轴 H/L |
| 字节 14 | `r14` = 0x18 TIME_H | 读回但本缓冲用不到（右移后落在 struct 的第 15 字节，被丢弃） |

**`transfer()` 的右移补丁**（`HXY42688P.cpp:803-823`）：`recv[i] = recv[i-1]`（i 从 14 到 2），`recv[1] = 0`
⇒ 变换后 `recv[k] = r(k-1)`（k≥2）。
**结构体字段映射**：`cmd = recv[0]`、`dummy = recv[1]`、`data[i] = recv[2+i] = r(1+i)`
⇒ **`data[0] = r1 = 0x0B`、`data[1] = r2 = 0x0C` … `data[12] = r13 = 0x17`** ✓

**驱动取值**（`HXY42688P.cpp:572-578`）：

| 行 | 代码 | 实际寄存器 | 手册 |
|---|---|---|---|
| `:572` | `combine(data[1], data[2])` | 0x0C, 0x0D = ACC_XH/XL | ✓ §5.9 |
| `:573` | `combine(data[3], data[4])` | 0x0E, 0x0F = ACC_YH/YL | ✓ §5.10 |
| `:574` | `combine(data[5], data[6])` | 0x10, 0x11 = ACC_ZH/ZL | ✓ §5.11 |
| `:576` | `combine(data[7], data[8])` | 0x12, 0x13 = GYR_XH/XL | ✓ §5.12 |
| `:577` | `combine(data[9], data[10])` | 0x14, 0x15 = GYR_YH/YL | ✓ §5.13 |
| `:578` | `combine(data[11], data[12])` | 0x16, 0x17 = GYR_ZH/ZL | ✓ §5.14 |

⇒ **逐字节对得上，`data[1..6]` 确实 = 0x0C..0x11，没有任何"某轴跨寄存器边界"。**
（另外 `README`/`HXY42688P.hpp:124` 里写的"线上 15 字节以 `[0x18]` 结尾"也是对的：r14=0x18 被右移挤出缓冲。）

## 4.2 为什么传输层也不可能造成"按轴异常"（三条实现证据）

| 证据 | 内容 | 结论 |
|---|---|---|
| ① 全双工原语 | `SPI::transfer` → `SPI::_transfer` → `SPI_EXCHANGE(dev, send, recv, len)`，**恰发 len 字节、不插字节**（`src/lib/drivers/device/nuttx/SPI.cpp:167-179`） | 线上字节数 = `len`，无额外占位 |
| ② **in-place 别名危险不存在** | STM32H7 的 DMA `spi_exchange` 为**每个 SPI 口静态分配了内部 txbuf/rxbuf**（`platforms/nuttx/NuttX/nuttx/arch/arm/src/stm32h7/stm32_spi.c:392-412`），先把调用者的 tx **memcpy 进内部缓冲**（`:2089-2106`），再把内部 rx **memcpy 回调用者缓冲**（`:2159-2160`）。⇒ 驱动用 `send == recv` 就地传参**安全** | "RX DMA 覆盖未发出的 TX 字节"这个经典隐患**在本板不存在**；也顺带否掉了"`RegisterWrite` 被就地覆盖 ⇒ 写不落地"这条对 `GYR_CONF` 的猜测 |
| ③ **PIO/DMA 分界** | `CONFIG_STM32H7_SPI_DMATHRESHOLD = 8`（`boards/rm2027/fmu-h743/nuttx-config/nsh/defconfig:190`）：`nbytes <= 8` 走 **非 DMA**（`stm32_spi.c:2066-2073`）；SPI1 的 DMA 缓冲 = 2048 B（`defconfig:188-189`） | ⇒ **2 字节的 `RegisterWrite`、3 字节的 `RegisterRead` 走 PIO；15 字节突发走 DMA**。两种路径都不可能引入"按轴"的差异 |

## 4.3 驱动标度层也不可能造成"按轴"差异

`PX4Accelerometer::update()`（`src/lib/drivers/accelerometer/PX4Accelerometer.cpp:137-153`）：

```cpp
rotate_3f(_rotation, x, y, z);   // 旋转 = 置换 + 变号，不改模长
report.x = x * _scale;           // ★ 三个轴共用同一个标量
report.y = y * _scale;
report.z = z * _scale;
```

⇒ **标度是单一标量**（`_scale`），旋转只做置换/变号（`rotation.h:106-113` 的欧拉表）
⇒ **驱动在数学上不可能产生"某一个轴 3.6×"的效果** ⇒ 若 C3 判出单轴增益，它**必然来自原始码**。

---

# 第 5 部分 · 处置选项（若坐实"单通道增益异常"）

**先记住两件事（决定了处置顺序）：**

1. **PX4 的六面标定本身就会解出一个完整的 3×3 矩阵**（含每轴标度）：
   `mat_A.row(0)=tail−off`、`row(1)=left−off`、`row(2)=upside−off`；
   `accel_T = mat_A.I() * CONSTANTS_ONE_G`；`set_scale(sensor_frame_scale.diag())`
   （`accelerometer_calibration.cpp:363-379`）⇒ **单轴增益异常正是标定要吸收的东西**。
2. **但标定必须先通过"姿态识别"这道 ±5 m/s² 的门**（§2.1）⇒ 这就是**自举死锁**：
   增益错得离谱 ⇒ 识别不了 ⇒ 永远走不到"解矩阵"那一步。

⇒ **处置的本质就是"先给一个临时的正确标度让识别过关，再让标定去解真正的矩阵"。**

| 选项 | 做法 | 代价 / 风险 | 评价 |
|---|---|---|---|
| **A ★ 驱动里加"按轴"增益常数** | 把 `ACCEL_GAIN_CORRECTION`（`HXY42688P.cpp:655`）从单标量扩成 3 分量 `{gx, gy, gz}`，`SetAccelScaleAndRange()` 里按轴相乘；系数由 §3.2 的 `gain_k` 实测填 | 改驱动（Lead 已在改这个文件）；必须在**标定前**确定并在**标定后**复核 —— 标定会再乘一个矩阵，若 `CAL_ACC0_SCALE{k}` 明显偏离 1，说明**重复修正**，此时应把驱动常数撤掉并重标（**顺序：先定常数 → 再标定**） | ✅ **推荐**。代价最低、立刻解锁标定，且最终真源仍是标定 |
| **B 让"姿态识别"改看健康那一路**（Lead 已采纳） | 设 **`CAL_ACCx_PRIO`**（H104 所在索引设 80，hxy 留 -1 或设 50，机制见 §2.5.2），**重启**，再用 `sensors status` 的 **`[vehicle_acceleration] selected sensor:`** 复核源是否真换了 | ⚠️ **三条本轮实测暴露的风险，必须先验**：<br>**(R1) 标签框架来自"源"，但矩阵对每一路都解** ⇒ 若两路 published 框架不一致，非源那一颗的 `mat_A` 变成**带符号置换矩阵**，其对角元 ≈0 ⇒ `set_scale(≈0)` ⇒ 该路输出**直接归零**（`Accelerometer::Correct` 是乘法：`Accelerometer.hpp:84-87`），而**符号判定拦不住**（错位轴上读数≈0，`0 < 0` 为假 ⇒ 静默通过）<br>**(R2) 选源在抖**（用户实测 `failsafe: YES (2 events)`、`gyro selection changed: 3`）⇒ 光改 PRIO 不保证稳定<br>**(R3)** 取数与符号判定对**所有**实例都做（`:172-177`、`:222-273`），最后为**每一路**解矩阵存参数（`:343-405`）⇒ 坏的那一路**会被标定吸收**（这正是 B 的价值） | ✅ **仍是最划算的备选**，但**前提是先证明两路框架一致 + 源不抖**（§2.5.3、§3.4） |
| **C 只信 H104 / 屏蔽 hxy** | 不启动 `hxy42688p`，只用 H104 | ① 只剩一路 IMU，**EKF 的双 IMU 一致性检查失效**（`imuConsistencyCheck.cpp:44-45` 注释明说"单 IMU 时被判量恒为 0 ⇒ 该检查永远通过"）⇒ 失去冗余/故障检测；② **H104 的 3 dB 带宽只有 80~200 Hz、输出 100 Hz**（`review-03` §1.3）⇒ 姿态/内环质量下降；③ 陀螺也只剩一路 | ❌ **不推荐**（用降低冗余和质量换一个本可修的标度问题） |
| **D 该轴降级（丢一个轴）** | 不用异常轴，改用另一路的对应轴拼 | PX4 **没有**"丢一个轴"的机制；混两路的轴 ⇒ 框架/时延不一致，EKF 会报不一致 | ❌ **不推荐** |
| **A' 若判出的是零偏（H3）而非增益** | 不要动 `_scale`，改为在驱动里加按轴 offset（或直接靠标定的 `CAL_ACC*_OFF`） | 标定本来就会解 offset（`:351-361`）；死锁同样存在 ⇒ 也需要临时补偿 | 与 A 同源，只是修的是 offset |

---

# 第 6 部分 · 顺带并入 `review-01`：两条实测证据（已改）

已在 `work/review-01-手册逐条对照.md` 落地（见该文件 §1.2 的 R1/R2 与新增的 §1.2.1）：

1. **`-R 0 → 6`（`ROTATION_YAW_270`）已上板**：六面从 **0/6** 变 **4/6**
   ⇒ 与 `review-01` 里"六面判定只看符号 ⇒ `invalid X-axis` 是轴向问题"的结论方向一致，
   但**更正一半**：**姿态识别这道门（`detect_orientation`）确实用幅值**（±5 m/s²，`calibration_routines.cpp:75`），
   所以轴向不是唯一因素；本次把这条写清并升级为实测证据。
2. **"用一次性运行时回读定标度"的坑真的发生了**（`review-01` R2 升级）：
   开机第一次 `Configure()` 抓到 `ACC_RANGE applied=0x01 readback=0x00`、
   `GYR_RANGE applied=0x00 readback=0x04` ⇒ 旧代码会把**陀螺标度设成 1/16**、加计标度差 2 的幂次。
   现已改为用**写入值**定标。

---

# 第 7 部分 · Lead 额外问的两件事

## 7.1 `IMU_INTEG_RATE` / `IMU_GYRO_RATEMAX` 本板现值

| 参数 | 代码缺省 | 板级/airframe 覆盖 | 本板预计值 |
|---|---|---|---|
| `IMU_INTEG_RATE` | **200 Hz**（`src/modules/sensors/vehicle_imu/imu_parameters.yaml:5-25`；代码硬约束 50~1000，`VehicleIMU.cpp:150`） | ❌ 在 `boards/rm2027/`、`ROMFS/px4fmu_common/init.d/airframes/` 里**没有**任何覆盖（只有 SITL 的 `px4-rc.simulator:7` 设 250） | **200 Hz** |
| `IMU_GYRO_RATEMAX` | **400 Hz**（`imu_gyro_parameters.yaml:90-113`；代码硬约束 50~10000，`VehicleAngularVelocity.cpp:397-401`） | ⚠️ **`ROMFS/px4fmu_common/init.d/rc.mc_defaults:13-15`**：<br>`if param compare IMU_GYRO_RATEMAX 400` → `param set-default IMU_GYRO_RATEMAX 800` | **若跑的是多旋翼机型 ⇒ 800 Hz**；否则 400 |

> ⚠️ 这两条**必须用一条命令定死**（我无法从源码确定机上值）：
> `param show IMU_INTEG_RATE IMU_GYRO_RATEMAX`
> 另外：`rc.mc_defaults` 只有在机型（`SYS_AUTOSTART`）被识别为 MC 时才会跑到那个分支。

## 7.2 对"现在 100 Hz 的 H104 到底喂不喂得饱 EKF"的回答

- EKF2 吃的不是 `sensor_accel`，而是 `vehicle_imu` 的 **delta angle/velocity**（`EKF2.cpp:500-505`、`:633-651`），
  由 `VehicleIMU` 按 `IMU_INTEG_RATE` 的间隔**把 N 个样本合并成一个 delta**：
  `gyro_integral_samples = max(1, round(积分间隔 / 样本间隔))`（`VehicleIMU.cpp:689`）。
- **hxy**：1600 Hz 输入、200 Hz 积分 ⇒ 每 8 个样本一个 delta ⇒ 吃得很饱；
- **H104**：100 Hz 输入（10 ms/样本）、`IMU_INTEG_RATE`=200（5 ms/间隔）
  ⇒ `round(5000/10000) = round(0.5) = 1` ⇒ **每个样本一个 delta**，即 **H104 的 `vehicle_imu` 实际是 100 Hz**。
- ⇒ 结论：**H104 在 EKF 里就是一路 100 Hz 的辅助 IMU**（主导是 hxy）。
  它**不"喂不饱"到出错**，但也没有富余：**100 Hz 恰好是"每样本一个 delta"的下限**，
  抖动/丢帧会直接变成 EKF 的采样间隔抖动。这与 `review-03` 的建议一致：
  **标定打通后，把 H104 提到 200 Hz（与 `IMU_INTEG_RATE` 缺省对齐）是性价比最高的一档。**

---

# 第 8 部分 · 我不能判定、必须上板的清单（诚实标注）

| # | 事项 | 需要的动作 |
|---|---|---|
| 1 | ~~标定看的是哪一路 IMU~~ **已定案：H104**（`sensors status` 的 `[vehicle_acceleration] selected sensor: 1677721613`） | 仍需复核：投票器与 `vehicle_acceleration` 为什么会不一致（§0 结论 1） |
| 2 | 卡住的是哪两个面（决定是"成对失败"还是"乱失败"） | **看 console 的 `[cal] pending:` 行**（§2.6；不要看 QGC 截图，我无法核 QGC 的格子顺序） |
| 3 | 异常是否可复现且静止（H1 vs H2） | §3.2 的 10 姿势静置 + sd/重复性判据 |
| 4 | 逐轴表观增益 `gain_k`（H2 vs H3） | §3.2 的 A 组 6 姿势 |
| 5 | `CAL_ACC*` 是否有脏值（H8） | `param show CAL_ACC*` |
| 6 | `DATA_SAT` 的 SAT 位与 `GYR_MEMS_OK`（H9） | ST-Link（Lead 执行，带净化前奏） |
| 7 | 上表两个参数的机上值（§7.1） | `param show IMU_INTEG_RATE IMU_GYRO_RATEMAX` |

> 以上全部写成了可直接执行的命令/判据；本报告不含任何需要我操作 ST-Link 或烧写的内容。

---

# 第 9 部分 · 本轮新增实测事实（并入 / 结案）

| # | 事实（用户实测） | 处理 |
|---|---|---|
| 1 | **`vehicle_acceleration` / `vehicle_angular_velocity` 的源 = H104**（`1677721613`，100.0 Hz）；而投票器 `selected accel` = hxy | ⇒ **识别源已定案 = H104**（§0 结论 1）；由此新增"两条选源路径会不一致"的结构性发现（§2.5） |
| 2 | **磁力计正常，`\|B\| = 0.452 G`**（raw 0.1681/0.0271/−0.4186），`offset [−0.060 0.027 0.184]`、`scale [0.932 0.987 1.058]`，`ist8310` bad register 0 / bad transfer 0 | ✅ **`review-02` §3.3 的"2 倍偏低"结案：那是硬铁偏移/环境，不是标度问题。** 建议把 `review-02` §3.3 的结论由"待验证"改为"已结案：硬铁偏移，标定后 0.452 G"（该文件本轮未授权我改） |
| 3 | 气压计正常：`101965 Pa`、`38.2 ℃`、`altitude −53.2 m`；`spa06` comms errors 0；采样周期 853.85 us 平均（min 849 / max 915） | ✅ 无需动作（`review-02` §3.1.4 的判定维持） |
| 4 | **选源在抖**：`validator: best: 0, prev best: 0, failsafe: YES (2 events)`；`vehicle_angular_velocity: gyro filter reset: 3, gyro selection changed: 3` | ⚠️ **升级为新的候选根因**（§2.5.3-2、§3.4）：识别窗口内混两路框架 ⇒ `invalid orientation`。**在标定前先解这个** |
| 5 | `CAL_ACC0_PRIO` / `CAL_ACC1_PRIO` 的**出厂缺省是 `-1`**（不是 50/75） | ⇒ 解释了"外部 75 > 内部 50 为什么没生效"，也给出 B 的正确参数（§2.5.2） |
| 6 | `listener` 必须"话题名在前" | ⇒ 全报告命令已改；`review-02`/`review-03` 的 `listener -n N <topic>` 形式应同步更正 |

> 关于 `vehicle_acceleration` 消息：`msg/VehicleAcceleration.msg` 只有 `timestamp / timestamp_sample / xyz`
> ⇒ **协议层不带 device_id**；判断源只有两条路：`sensors status` 的 `[vehicle_acceleration] selected sensor:` 行，
> 或 `rate:`／输出行速率（100 Hz = H104，~1 kHz = hxy）。
