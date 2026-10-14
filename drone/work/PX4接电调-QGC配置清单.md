# PX4 接电调 · QGC 配置清单（本板 rm2027/fmu-h743）

> **用途**：接线之后，在 QGC 里**按顺序点**，让 **4 路 DShot 出脉冲**。
> **一切以本板固件生成出来的参数表为准**：`build/rm2027_fmu-h743_default/generated_params/module_params.c`。
> ⚠️ 引脚/驱动等"编译期"的事不在这里 —— 见 `PX4改造-索引与纪律.md` §1。
> ⚠️ **第 1 步之前不要装螺旋桨。**

---

## 0. 前置

| | |
|---|---|
| 接线 | 4 个电调信号线接 **PWM MAIN 的第 1~4 路**（对应参数 `PWM_MAIN_FUNC1..4`） |
| 要求 | 共地；电调供电正常；**拆桨**（`docs/en/config/actuators.md:447`、`docs/en/peripherals/dshot.md:38`） |
| 本板 MAIN 分组 | **只有 1 个 timer group**（参数表里只有 `PWM_MAIN_TIM0`）⇒ 4 路**必须同协议同速率**（`docs/en/config/actuators.md:338-339`） |

---

## 1. Airframe：选 4001 Generic Quadcopter

| 步骤 | 说明 |
|---|---|
| QGC → **Airframe** | 选 **Quadrotor X → Generic Quadcopter** |
| 写入的参数 | `SYS_AUTOSTART = 4001`（出处 `docs/en/airframes/airframe_reference.md:377-378`） |
| 机型脚本 | `ROMFS/px4fmu_common/init.d/airframes/4001_quad_x:14-24`（`CA_ROTOR_COUNT 4` + 四电机几何） |
| **要不要重启** | **要**。`SYS_AUTOSTART` 的 `reboot_required: true`（`src/lib/systemlib/system_params.yaml:5-16`） |
| 复核 | `param show SYS_AUTOSTART` → 4001 |

> **你不需要改那份几何**（PX/PY/KM 就是标准 X 形）。除非你要非对称布局。

---

## 2. ★ Actuators 页（核心，决定"出不出脉冲"）

### 2.1 把 4 路功能映射配出来 —— **本板默认全是 `0`（Disabled）**

| 输出 | 参数 | 要设成 | 功能号 |
|---|---|---|---|
| MAIN 第 1 路 | `PWM_MAIN_FUNC1` | `Motor 1` | **101** |
| MAIN 第 2 路 | `PWM_MAIN_FUNC2` | `Motor 2` | **102** |
| MAIN 第 3 路 | `PWM_MAIN_FUNC3` | `Motor 3` | **103** |
| MAIN 第 4 路 | `PWM_MAIN_FUNC4` | `Motor 4` | **104** |

- **功能号出处**：`src/lib/mixer_module/output_functions.yaml:5,10-12`（`Disabled: 0`；`Motor: start 101, count 12`；`Servo: start 201`）
- ⚠️ **本板实测缺省全是 0**：`module_params.c:2243 / 2322 / 2401 / 2480` 四行都是 `PARAM_DEFINE_INT32(PWM_MAIN_FUNCn, 0)`
  ⇒ **不配这一步，4 路输出不会出任何脉冲**（哪怕解锁了）
- **QGC 路径**：`Actuator` → `Actuator Outputs` → **PWM MAIN** 选项卡 → 每路下拉选 `Motor 1..4`
- **复核**：`param show PWM_MAIN_FUNC1 PWM_MAIN_FUNC2 PWM_MAIN_FUNC3 PWM_MAIN_FUNC4` → 101/102/103/104

### 2.2 协议切成 DShot —— 底层就是 `PWM_MAIN_TIM0`

| 目标 | `PWM_MAIN_TIM0` 取值 |
|---|---|
| **DShot600** | **-3** |
| **DShot300** | **-4** |
| DShot150 | -5 |
| OneShot | -1 |
| PWM 400/200/100/50 Hz | 400 / 200 / 100 / 50 |
| **本板缺省** | **400（= PWM 400 Hz，不是 DShot）** |

- **出处**：生成参数表 `module_params.c:2154-2164`（取值表与缺省都在参数注释里）；驱动侧 `src/drivers/dshot/DShot.cpp:1086` 用 `"%s_TIM%u"` 拼这个名字
- **QGC 路径**：`Actuator Outputs` → 该输出组的 **Protocol / Rate** 下拉选 DShot（`docs/en/peripherals/dshot.md:41`：*Enable DShot for your required outputs in the Actuator Configuration*）
- ⚠️ **`reboot_required: true`**（`module_params.c:2162`）⇒ 改完**必须重启**才生效
- **速率怎么选**：取电调支持的最高（`dshot.md:43-44`）。**不确定就先 300**

### 2.3 用 sliders 逐个验证（不装桨）

1. `Actuator Testing` → 打开 **Enable Sliders**（`docs/en/config/actuators.md:409`）
2. ⚠️ 打开后**不动滑块，电机不会转**（安全设计，`actuators.md:413-415`）
3. 拖到最底（disarmed 值）⇒ **电机必须不转**
4. 慢慢上推 ⇒ 电机"勉强转"
5. 继续推 ⇒ 验证**转向**与"**推力朝上**"（DShot 不需要调 min/max，`actuators.md:526-527`）

### 2.4 **Identify & Assign Motors**（半自动认电机，推荐）

- QGC：`Actuator` → 选 **PWM** 选项卡 → 点 **Identify & Assign Motors**
- 流程（`docs/en/config/actuators.md:439-467`）：
  1. 点按钮 → **某一个电机会转**
  2. 在几何图上**点"是它"** → 自动切下一个电机（转太快可点 **Spin Motor Again**）
  3. 4 个都认完，工具会**自动写好输出映射**并退出
- 限制：**只支持多旋翼 + PWM 输出**（`actuators.md:442`）—— 本板符合
- ⚠️ **必须拆桨**（`actuators.md:447`）

### 2.5 转向不对怎么改（你要的"正负号校准"）

| 做法 | 说明 | 出处 |
|---|---|---|
| **UI 永久反向** | DShot 才有的 **Set Spin Direction** 按钮（在滑块下方，选中 DShot 并分配电机后才出现） | `docs/en/config/actuators.md:690-703`、`docs/en/peripherals/dshot.md:49` |
| **底层参数** | **`DSHOT_MOT_POL1..4`**（每电机一个极性） | `src/drivers/dshot/DShot.cpp:1009`（`snprintf(..., "DSHOT_MOT_POL%d", i+1)`） |
| ⚠️ 注意 | **当前方向无法回读** ⇒ 可能要"两个值都试" | `docs/en/config/actuators.md:703` |
| 非 DShot（PWM） | 只能**换两条电机线** | `docs/en/config/actuators.md:701-703` |

---

## 3. 参数保存：**不需要手动 `param save`**

- **PX4 改参数是自动保存的**，原文：`src/systemcmds/param/param.cpp:109-110`
  > *"Parameters are automatically saved when changed, eg. with `param set`."*
  后端：本板开了**片内 flash 参数存储**（`be9f428`）；启用 FLASH 后端后 `param select` 无效、默认就是 FLASH（`param.cpp:113-115`）
- **真正要防的坑是"持久化到底生效了没"** —— 本板参数持久化**从未端到端验收**
  （见 `PX4改造-索引与纪律.md` §6 欠账 #5）
- **唯一可靠的验收动作**：
  ```
  配好 → 断电 → 上电 → param show PWM_MAIN_FUNC1 PWM_MAIN_TIM0 SYS_AUTOSTART
  ```
  还在 ⇒ 持久化 OK；丢了 ⇒ 不是靠 `param save` 补救，要去查 flash 参数区
  （`script.ld` 的 FLASH LENGTH + `FLASH_BASED_PARAMS` + `init.c` 三处必须同源）
- `param save` 仍可用，但语义是"存到文件 / 存默认后端"，不是日常必需（`param.cpp:77, 205-213`）

---

## 4. Preflight 会拦什么（本板）

### ✅ 属于"可以忽略"的

| 提示 | 为什么正常 | 依据 |
|---|---|---|
| `Preflight Fail: system power unavailable` | 本板**没有电池电压分压/电源模块**，`system_power` 话题不发布 ⇒ 走 `else` 分支**必然报** | `powerCheck.cpp:196-208` |
| 想让它别拦 | 把 **`CBRK_SUPPLY_CHK = 894281`**（熔断魔数） | `src/lib/circuit_breaker/circuit_breaker.h:54`；`powerCheck.cpp:49` |
| `USB connected` | 只在 `usb_connected=true` 时报；本板无 USB ⇒ **不会触发** | `systemCheck.cpp:57-72`（魔数 `CBRK_USB_CHK = 197848`，同名头文件 `:57`） |

### ⚠️ 属于"必须解决"的

| 提示 | 为什么 | 依据 / 出路 |
|---|---|---|
| **`Preflight Fail: Missing FMU SD Card`** | 本板**没有**定义 `CONFIG_BOARD_NO_SDCARD` ⇒ SD 检查**被编进固件**，没卡就拦解锁 | `sdcardCheck.cpp:50-70`。对照别的无卡板：`boards/holybro/kakuteh7mini/default.px4board:4`（`CONFIG_BOARD_NO_SDCARD=y`）<br>**两条路**：① 插卡；② 板级加该宏 **重编固件** |
| 电池类提示（`Battery 1 unhealthy` 等） | 本板**刻意不设** `BAT1_V_DIV`/`BAT1_A_PER_V`（`init/rc.board_defaults:8-12`）⇒ 是否报取决于是否有分压；报了同样用 `CBRK_SUPPLY_CHK` 或补分压 | `batteryCheck.cpp:77` 也读 `CBRK_SUPPLY_CHK` |
| `Accel/Gyro N inconsistent`、`High Accelerometer Bias` | **传感器一致性问题**，必须先过六面标定（本板 hxy/H104 逐轴差 11~22% 要靠标定吸收） | `IMU` 一致性阈值 `COM_ARM_IMU_ACC = 0.7 m/s²`（`commander_params.yaml:225-238`） |

> ⚠️ **SD 卡那条要动板级配置 + 重编固件** ⇒ 与当前电调功率级调试会互相干扰，**要单独安排，别顺手做**。

---

## 5. 一页速查

```
① 拆桨、接 4 路信号线
② QGC → Airframe → Quadrotor X / Generic Quadcopter (4001) → 重启
③ Actuator Outputs → PWM MAIN：4 路设 Motor 1..4        （= PWM_MAIN_FUNC1..4 = 101..104）
④ 同页 Protocol → DShot300/600                          （= PWM_MAIN_TIM0 = -4 / -3）→ 重启
⑤ Actuator Testing → Enable Sliders → 逐个验证：不转 / 慢转 / 转向对
⑥ 转向不对 → Set Spin Direction                          （= DSHOT_MOT_POL1..4）
⑦ 断电 → 上电 → 复核参数还在
⑧ 接桨前最后一遍：param show PWM_MAIN_FUNC1 PWM_MAIN_TIM0 SYS_AUTOSTART
```

---

## 未核实 / 边界

- **QGC 那个 "Protocol" 下拉具体写哪些参数** —— 我只核到 **DShot 驱动侧**用 `<前缀>_TIM<n>`（`DShot.cpp:1086`），**QGC 侧代码不在本仓库**。若 UI 写的参数不止 `PWM_MAIN_TIM0`，**以 `param show` 的实际变化为准**。
- **本板电调支持的最高 DShot 速率** —— 属电调硬件侧，不在本文范围。
- **本板是否真有 SD 卡槽** —— 本文按"无 SD"处理（依据 Lead 说明），**未在原理图上逐脚核实**。
- `DSHOT_MIN` / `DSHOT_ESC_TYPE` 本板缺省值我未逐项展开（前者是 DShot 最小油门，DShot 下通常不用手调；需要时再查 `src/drivers/dshot/module.yaml`）。

## 参考出处汇总

| 类型 | 位置 |
|---|---|
| QGC 操作步骤 | `docs/en/config/actuators.md`（:409 sliders、:439-467 认电机、:690-701 反向）；`docs/en/peripherals/dshot.md`（:38/:41/:49） |
| 机型 | `docs/en/airframes/airframe_reference.md:377-378`；`ROMFS/px4fmu_common/init.d/airframes/4001_quad_x:14-24` |
| 参数语义 | `src/lib/mixer_module/output_functions.yaml:5,10-12`；`src/lib/systemlib/system_params.yaml:5-16` |
| 参数实际值/缺省 | `build/rm2027_fmu-h743_default/generated_params/module_params.c`（:701、:2154-2164、:2243/2322/2401/2480） |
| 驱动实现 | `src/drivers/dshot/DShot.cpp:1009,1086` |
| 参数保存 | `src/systemcmds/param/param.cpp:109-115` |
| Preflight | `powerCheck.cpp:49,196-208`；`systemCheck.cpp:57-72`；`sdcardCheck.cpp:50-70`；`src/lib/circuit_breaker/circuit_breaker.h:54,57` |
