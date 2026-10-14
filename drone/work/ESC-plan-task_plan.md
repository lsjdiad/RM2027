# ESC 软件过零 —— 任务计划

> 遵循 `planning-with-files` 技能（本机源：`projects/lab/repos/planning-with-files`）
> 配套：`ESC-plan-findings.md`（发现/技术路线）、`ESC-plan-progress.md`（进展日志）
> 建立 2026-10-01

## 目标（一句话）

**让这块自研电调（STM32G071 + FD6288Q）在没有硬件比较器通路的条件下，用软件实现三相无感 BEMF 过零检测，最终让电机稳定运转。**

## 约束（不可协商）

| # | 约束 | 来源 |
|---|---|---|
| C1 | **不改板**（PA4/PA5 无 COMP 功能是既成事实） | 用户 |
| C2 | **不接电机/不接 12V 做第一步验证** | 我 + 安全 |
| C3 | **CPU 不能吃太多** —— 目标中断占用 ≤5% | 用户（"你软件代码还剩多长时间"） |
| C4 | **每步可回滚**；动 flash 前必须已备份 | 本工作区铁律 |
| C5 | **不再"你说一出我改一出"** —— 先方案、后动手、方案变更要写进计划文件 | 用户本次明确要求 |

## 阶段

| 阶段 | 内容 | 产出 | 状态 |
|---|---|---|---|
| **P0** | 需求与约束固化：信号物理、速率账、CPU 预算 | `findings.md` §1-§3 | ✅ **complete** |
| **P1** | **技术路线选型**：3 条候选 + 判据 + 结论 | `findings.md` §4 | ✅ **complete**（选定 AWD 路线） |
| **P2** | 详细设计：AWD 路线的 5 处改动、阈值算法、分档策略 | `findings.md` §5-§6 | 🟡 **in_progress** |
| **P3** | 实现并编译通过 | `.bin` 产物 | ⬜ pending |
| **P4** | 台架验证（不接电机）：ADC 读数比例、过零点与波形对齐 | 实测记录 | ⬜ pending |
| **P5** | 上机验证：接电机低转 → 升速 | 实测记录 | ⬜ pending |
| **P6** | 参数调优：滞回窗口、分档阈值 | 定稿参数 | ⬜ pending |

## 关键决策记录

| # | 决策 | 依据 | 日期 |
|---|---|---|---|
| D1 | 放弃"恒定 167 kHz 轮询" | CPU 8~17%，且不必——比较可在硅片里做 | 10-01 |
| D2 | **采用 ADC 模拟看门狗 (AWD) 做硬件阈值比较** | G071 有 AWD1/2/3；中断只在过零时产生 | 10-01 |
| D3 | **过零阈值 = `ADC_raw_volts / 2`** | 六步换相下 V_C 过零 ⟺ V_C = VBAT/2（可推导） | 10-01 |
| D4 | 采样率随转速分档，不恒定 | 信号本身精度 ∝ 转速²；低速模糊达 100 µs | 10-01 |
| D5 | 先全软件跑通，**C 相换硬件比较器留作优化** | 避免"三相逻辑不对称"增加调试复杂度 | 10-01 |
| **D7** | **快通道 = [悬空相, VBAT] 两路，每次换相重设序列** | AWD 分辨率 = 通道转换间隔；6 通道只有 6 µs（findings §7.2） | 10-01 |
| D6 | `CURRENT_OFFSET = 0`、`DEAD_TIME = 60` | REF 接 GND（原理图）；FD6288Q 自带 200ns 死区 | 10-01 |

## 风险登记

| # | 风险 | 影响 | 缓解 | 状态 |
|---|---|---|---|---|
| R1 | 低速 BEMF 信噪比差（衰减 0.1754） | 低速过零判不准 | AWD 双阈值滞回 + 开环 ramp | 监控 |
| R2 | AWD 阈值随母线电压漂 | 误判/漏判 | 每次换相用 `ADC_raw_volts/2` 重算 | 设计已含 |
| R3 | AWD 只监视 1 个通道，换相时要重设 | 时序竞争 | 在换相函数里同步重设（42k/s 成本可忽略） | 设计已含 |
| R4 | DMA 高频占用总线 | 与 CPU 争 AHB | 算过：2 MB/s vs 256 MB/s ⇒ 0.8% | 已排除 |
| R5 | 触发定时器与现有 TIM6 冲突 | 破坏 10 kHz 任务 | **单独安排定时器，不复用 TIM6** | 待实现 |
| **R6** | **AWD 分辨率 = 通道转换间隔**，6 通道轮询只有 6 µs ⇒ 高速时电角度误差 ~15° | 高速换相偏晚 | **快通道只留 [悬空相, VBAT]** ⇒ 1~2 µs（见 findings §7.2） | 设计已改 |
| **R7** | 换相重设 AWD 通道期间可能误触发 | 假过零 | 复用 AM32 原有 mask/消隐窗口遮住重设期 | 设计已含 |

## 错误记录（技能铁律 5）

| 错误/误判 | 尝试 | 解决 |
|---|---|---|
| 归因"温度传感器 10.8 µs 是瓶颈" | 1 | ❌ 错。真凶是 1 kHz 软触发（§7 已更正） |
| 方案设"恒定 167 kHz 轮询" | 1 | ❌ CPU 8~17%。改用 AWD（D1/D2） |
| 认为"精度靠采样率" | 1 | ❌ 精度由**信号本身**决定（§3），采样率应随转速分档 |
| PDF 文字层行错位，误判引脚表 | 1 | ✅ 改"整符号渲染成图逐行读 + 手册交叉验证"解决 |

---

# ★ 明日计划（2026-10-02）：让电机转起来

## 核心判断：**"转起来"和"闭环能用"是两件事，别混**

**AM32 的启动流程是"开环 ramp → 切闭环"**，而**开环阶段完全不用 BEMF**。
⇒ **所以不必等 BEMF 做完 —— 用今天已有的固件就能让电机开环转起来。**

**⇒ 这把明天拆成了两条互不阻塞的路：**
```
路线 I （快，验证硬件）：开环起转   → 验 DShot / 门极 / MOSFET / 相序 / 电流
路线 II（慢，闭环）：    BEMF 接线   → 验 AWD + 过零 → 切闭环
```

## 阶段 A —— 前提清点（10 分钟，**卡住就没法往下走**）

| # | 需要 | 有没有 | 没了怎么办 |
|---|---|---|---|
| A1 | **可调限流电源**（3S/4S 等效，限流 1~2 A 起） | ❓ **未确认** | ⛔ **没有就别上电**。这是唯一不可省的安全件 |
| A2 | **DShot 信号源**（飞控的 DShot 输出，或信号发生器） | ❓ 未确认 | 用飞控（但飞控在另一块板上）；或先用示波器看门极不接电机 |
| A3 | **电机**（不装桨） | ✅ 你说有 | — |
| A4 | **示波器** | ✅ 你说有 | — |
| A5 | 12V 电源/电池 | ❓ | 用可调电源代替 |

**⇒ 只有 A1 是硬门槛。A2 没电调也能验一半（门极波形）。**

## 阶段 B —— 开环起转（1 小时）★ 明天的主目标

| 步 | 做什么 | 判据 |
|---|---|---|
| B1 | 烧**今天这个固件**（有 ADC、BEMF 未接线不影响开环） | 烧进 0x08001000 |
| B2 | SWD 手工装 SP/PC 启动（绕开 bootloader 问题） | `pc` 落在 app 区 |
| B3 | **限流电源上电**（限流 1 A 起） | 电流 <100 mA 空载 |
| B4 | 示波器看 6 路门极（`PA7/PB0/PB15/PA8/PA9/PA10`） | 有互补 PWM、有死区 |
| B5 | **DShot 给最小油门** | **电机起转** ← 明天的成功判据 |
| B6 | 逐步加油门 | 相序对（不抖不反转）、电流合理 |

**⇒ B5 过了 = 明天目标达成。**（哪怕是开环转，也证明**硬件全通**）

**失败分支**（按可能性排序）：
| 现象 | 最可能原因 | 下一步 |
|---|---|---|
| 完全不动 | DShot 没解出来 / 门极使能没开 | 示波器看 PA6(DShot) 有没有波形 |
| 抖/不走 | **相序错** | 交换任意两相的 HIN/LIN 定义，重烧 |
| 起转后失步 | **正常** —— 开环 ramp 结束切闭环时没有 BEMF 可用 | 这正是阶段 C 要解决的 |
| 电流飙 | 直通 / 死区不足 | **立即断电**，检查 `DEAD_TIME` 与 FD6288Q 接线 |

## 阶段 C —— 接上 BEMF（1.5 小时，可与 B 并行）

按 `findings.md` §7.4：
1. 改 3：删 `Src/main.c` 里 `LL_ADC_REG_StartConversion(ADC1)`
2. 改 5：**独立定时器 → ADC TRGO**（**不复用 TIM6**）+ AWD 中断接 `interruptRoutine()`
3. 改 4：换相处调 `adc_bemf_watchdog_for_phase()`
4. 快通道改成 `[悬空相, VBAT]` 两路（分辨率 1~2 µs）

## 阶段 D —— 示波器验两个假设（30 分钟）

| 假设 | 怎么验 | 不过怎么办 |
|---|---|---|
| **A1** 悬空相过零在 `VBAT/2` | 示波器同看悬空相与 `VBAT/2` 线 | 改用 V0(PA3) 作阈值来源 |
| **A2** AWD 在 DMA 循环下能中断 | 人为扫过阈值看是否进中断 | 退回"2 通道路由 + 软件插值"路线 B |

## 阶段 E —— 切闭环升速（时间不定）

**⇒ 这是唯一"可能拖"的一段**（高速换相精度）。但**B 阶段已经拿到"电机能转"的结果**，所以 E 拖不影响明天的结论。

## 阶段 F —— bootloader 问题（不急，但飞行前必须）

`reset run` 后停在 `0x08000154`，不跳 app。怀疑 `.file_name`(0x0800F7E0) 校验。
**台架期用 SWD 手工启动绕过即可。**

## 明天的一句话目标

> **阶段 A 前提齐 ⇒ B5 电机起转 ⇒ 明天就算成功。**
> C/D/E 是"能不能飞"，B 是"硬件通不通"。

---

# ★ 代码仓库位置（2026-10-02 定址）

| 仓库 | 位置 | 说明 |
|---|---|---|
| **AM32 电调固件** | **`/home/xien/RM2027/AM32`** | **✅ 永久位置（原在 `/tmp/am32-<epoch>`，重启会丢，已迁移）** |
| 上游 | `https://github.com/am32-firmware/AM32` | clone 的 origin |
| 本板提交 | `521d3d4` | `RM2027_ESC_G071: G071 target + ADC-BEMF software zero-crossing` |
| F103 测试固件 | `/home/xien/RM2027/test_esc` | DShot 发送器（分层 Bsp/Module/App） |

## 编译
```bash
cd /home/xien/RM2027/AM32
make ARM_SDK_PREFIX=arm-none-eabi- RM2027_ESC_G071
# 产物: obj/AM32_RM2027_ESC_G071_2.21.bin
# 占用: FLASH 25764 B (40.72%) / RAM 3760 B (22.95%)
```

## 备份（即使仓库丢了也能复原）
`work/esc-artifacts/AM32-RM2027.patch`（完整补丁）+ 各改动文件 + 固件 + 参数区镜像。
复原：`git clone <上游> && git apply AM32-RM2027.patch`

---

# ★ 接飞控时必须配的参数（下一阶段用，已实测确认）

**来源：本板生成参数表 `build/rm2027_fmu-h743_default/generated_params/module_params.c`**

## ⚠️ 头号坑：4 路输出默认是关的

```
PARAM_DEFINE_INT32(PWM_MAIN_FUNC1, 0);   ← 全 0 = Disabled
PARAM_DEFINE_INT32(PWM_MAIN_FUNC2, 0);
PARAM_DEFINE_INT32(PWM_MAIN_FUNC3, 0);
PARAM_DEFINE_INT32(PWM_MAIN_FUNC4, 0);
```
**⇒ 板级已声明 `CONFIG_DRIVERS_DSHOT=y`（驱动编进去了），但**不配这几个参数，4 路 DShot 一个脉冲都不发**。**

## 功能编号（`src/lib/mixer_module/output_functions.yaml`）

```
Disabled = 0     Constant_Min = 1     Constant_Max = 2
Motor:  start = 101, count = 12   ⇒  Motor1..Motor4 = 101/102/103/104
Servo:  start = 201, count = 15
```

**⇒ 配置值：**
```
PWM_MAIN_FUNC1 = 101    (Motor 1)
PWM_MAIN_FUNC2 = 102    (Motor 2)
PWM_MAIN_FUNC3 = 103    (Motor 3)
PWM_MAIN_FUNC4 = 104    (Motor 4)
```

## DShot 相关参数（已生成，默认合理）

| 参数 | 默认 | 说明 |
|---|---|---|
| `DSHOT_ESC_TYPE` | 0 | ESC 类型 |
| `DSHOT_MIN` | 0.055 | 最小油门 |
| **`DSHOT_BIDIR_EDT`** | **0** | **双向 DShot 遥测 —— 默认关** ⇒ 与"我们用单向"的决定一致 ✓ |
| `DSHOT_3D_ENABLE` | 0 | 3D 模式 |
| `DSHOT_MOT_POL1..8` | 14 | 电机转向极性 |
| `PWM_MAIN_TIM0` | 400 | DShot 速率档 |
| `PWM_MAIN_DIS1..4` / `MIN1..4` | 1000 | 输出上下限 |

## 其余要点（px4-tutor 查证，我已复核）

| 项 | 结论 |
|---|---|
| 机型 | **Generic Quadcopter = `SYS_AUTOSTART` 4001**（`docs/en/airframes/airframe_reference.md:377-378`）；`4001_quad_x` 用 `CA_ROTOR*_PX/PY/KM` 定义 X 形几何 |
| QGC 连接 | **走 MAVLink**（USB 的 `/dev/ttyACM0`，或 TEL1 `/dev/ttyS2`=USART3）—— **不是 ST-Link**；本板用 `MAV_0_*` 参数（不是老版 `MAV_x_CONFIG`） |
| 换陀螺 / 换引脚 | 属**板级移植（编译期）**，QGC 做不到：`default.px4board` 选驱动、`src/spi.cpp` 配 CS/DRDY、`rc.board_sensors` 拉起、`-R` 定安装方向 |
| 混控管线 | `control_allocator` → `actuator_motors`/`actuator_servos` → 输出驱动（继承 `OutputModuleInterface`，只实现 `updateOutputs()`）；文档 `docs/en/concept/control_allocation.md` + `docs/assets/concepts/control_allocation_pipeline.png` |
| 执行器测试 | `actuator_test` 是 uORB 消息（`msg/ActuatorTest.msg`），由共享库 `src/lib/mixer_module/` 统一订阅并**覆盖**输出（不是每个驱动各自订阅） |

