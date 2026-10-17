# ESC 软件过零 —— 进展日志

> 配套：`ESC-plan-task_plan.md`、`ESC-plan-findings.md`　主责：Lead

---

## 2026-10-01（当日汇总）

### 已完成

| # | 事项 | 证据 |
|---|---|---|
| 1 | AM32 源码拉取、确认**官方支持 G071** | `g071makefile.mk` + `Mcu/g071/` |
| 2 | 打通构建（GCC13 需 `-Wno-error=array-bounds`） | AIKON_PRO_G071 编过 |
| 3 | **flash 布局确认** | `0x0000` 4 KB bootloader（实测 4092 B）；app `0x1000`；eeprom `0x1F800` |
| 4 | **备份 bootloader** | `esc-flash-backup-2026-10-01.bin` sha256 `b72d75aa…` |
| 5 | **引脚映射逐行核准** | 整符号渲染成图 + 数据手册交叉验证（PA0=IN0…PB15=CH3N 全中） |
| 6 | **发现"三相只有一相能进比较器"** | 数据手册 Additional Functions：PA4/PA5 无 COMP |
| 7 | 模拟前端参数算齐 | 60 mV/A、电压分压 110、相衰减 0.1754 |
| 8 | `CURRENT_OFFSET` 定案 = 0 | 高倍裁图确认 INA240 REF1/REF2 接 GND |
| 9 | **自研 target 写完** | `RM2027_ESC_G071` + `HARDWARE_GROUP_G0_RM2027` |
| 10 | **软件过零模块写完并编译通过** | `adc_bemf.c/.h`，产物 25584 B / 40.44% |

### 三次自我更正（都写进 `findings.md`）

| # | 原判断 | 更正 |
|---|---|---|
| 1 | "温度传感器 10.8 µs 是瓶颈" | ❌ 真凶是 **1 kHz 软触发**（`main.c:1439/2127`），差 167 倍 |
| 2 | "必须恒定 167 kHz 轮询" | ❌ CPU 8~17% ⇒ 改用 **AWD**（路线 C） |
| 3 | "精度靠采样率" | ❌ 精度由**信号本身**决定（∝ R²）⇒ 采样率应随转速分档 |

### 提交链（项目仓库）

```
04a7a9b  ESB 模拟前端参数
a8c8492  target 代码落盘
aadd04e  软件过零模块落盘（编译通过）
9d0bb95  ADC 集成设计（速率账）
185b9da  ★ 更正瓶颈归因：1kHz 软触发
（本轮）  ★ planning 文件 + AWD 技术路线
```

### 另修

- **PX4 主检出 HEAD 曾被切到 `teaching/minimal-path`**（非我方所为；reflog 两条 checkout）。
  核实：树 sha 与 `h104-protocol` **完全相同**、`git status` 0 项、固件完好 ⇒ **无损坏**。
  已 `git switch h104-protocol` 恢复（内容上的 no-op），消除"将来误提交到教学分支"的隐患。

### 2026-10-01 追加（P3 部分完成）

| # | 改动 | 状态 |
|---|---|---|
| 1 | `ADC.c`：缓冲区 7 路 / 回调映射 / 时钟 DIV2(32MHz) / 序列 7RANKS / DMA 长度 7 | ✅ **已完成并编译通过** |
| 2 | `adc_bemf.c`：**AWD 配置函数**（`adc_bemf_config_watchdog` + `adc_bemf_watchdog_for_phase`） | ✅ **已完成并编译通过** |
| 3 | 删掉 `main.c` 的 `StartConversion` | ⬜ 待做（**故意延后**，先保 1 kHz 触发便于台架验接线） |
| 4 | 换相处调用 `adc_bemf_watchdog_for_phase()` | ⬜ 待做 |
| 5 | 独立定时器触发 + AWD 中断接 `interruptRoutine()` | ⬜ 待做 |

代码快照：`ESC-AM32-代码快照.md`（4 个文件全部可复原）
产物：`AM32_RM2027_ESC_G071_2.21.bin`，FLASH 25764 B / 40.72%

### 下一步（P4 台架验证）

**按 `findings.md` §6.4 的五处改动动手**，先改 1/2/5（ADC + AWD + ISR），再改 3/4。
改完只做 P4 台架验证（**不接电机**）。

### 待用户/硬件队友回答

1. 硬件队友：PA4/PA5 当初是**有意**不用比较器，还是排引脚时没注意？**有没有参考固件？**
2. 用户：飞控那三条命令（`CAL_ACC0_PRIO 80` / `CAL_GYRO0_PRIO 80` / `param save`）

---

## 分支不变式：保险登记（2026-10-01）

**背景**：`git reflog` 显示 PX4 主检出被切换过 4 次，其中 **22:40:56 那次不是 Lead 也不是 px4-tutor 做的**（Lead 在 22:38:49 切回 `h104-protocol` 后，2 分钟又被切回 `teaching/minimal-path`）。现场核实：无活跃 git 进程、worktree 仅 1 个、内容 0 差异。

**为什么这事要紧**：`teaching/*` 的**全部价值**就是下面这条不变式。

| 分支 | 期望 tip | 期望树 sha |
|---|---|---|
| `h104-protocol` | `9aeb3a0` | `97e843654c99a3ac7b14bb35e309fa486c7c235d` |
| `teaching/minimal-path` | `507471d` | `97e843654c99a3ac7b14bb35e309fa486c7c235d`（**必须与上面相同**） |
| `teaching/clean` | `d71e5ca` | `624b79c…`（少 bmi270 三个文件） |

**⛔ 铁律：永远不要在 `teaching/*` 上 `git commit`。** 一旦提交，上表第 2 行的等式当场失效，教学分支作为"学习路径的终点"就失去意义。

**自查一条命令**：
```bash
cd /home/xien/桌面/RM2027/PX4-Autopilot
git rev-parse HEAD^{tree} h104-protocol^{tree}    # 两行必须完全相同
```

**恢复原状的命令**（内容上是 no-op，因为两棵树 sha 相同）：
```bash
git switch h104-protocol        # 默认应待在这里（开发分支）
```
**要看教学历史请用 worktree，不要 switch 主检出**：
```bash
git worktree add /tmp/px4-teach teaching/minimal-path
```

---

## 2026-10-01 P4 第一步：实机验证（通过）

**方法**：电调只由 3.3V 供电（不接电机/12V），SWD 连 ST-Link；烧写后**用电调自己没连串口** ⇒ 改为**直接读 RAM 全局变量**（符号地址从 ELF 取）。

**烧写**：`AM32_RM2027_ESC_G071_2.21.bin` → `0x08001000`（59392 B，覆盖到 0x0800F7FF，未碰 bootloader）

### 结果

| 观测 | 值 | 判据 |
|---|---|---|
| app 向量表 | `SP=0x20004000` `reset=0x0800472d` | ✅ 已写入 |
| bootloader 区 | `20001000 08000105 08000155 …` | ✅ **未被破坏** |
| 手工装 SP/PC 后 | `pc = 0x08001270`（app 区） | ✅ **app 能跑** |
| **`bemf_adc_va/vb/vc/v0`** | **18 / 18 / 16 / 0** | ✅ **四路都被 DMA 填充（原为初值 2048）** |
| `ADC_raw_volts` / `ADC_raw_temp` | 333 / 949 | ✅ 原为 0 ⇒ 扫描正常 |
| `ADCDataDMA[0..6]` | 2, 333, 949, 18, 16, 18, 0 | ✅ **7 路顺序正确** |

**⇒ 结论：ADC 扩到 7 路 + 时钟 32 MHz + 回调映射 —— 全部正确。**

### ⚠️ 新发现的独立问题：bootloader 不主动跳 app

`reset run` 之后 `pc = 0x08000154`（bootloader 向量表里的**默认处理函数**），app 从不执行。

**已排除**：`checkDeviceInfo()` 读地址 `0x1000-32 = 0xFE0`（别名 `0x08000FE0`，即 bootloader 4 KB 的最后 32 字节）的 `devinfo`；**magic 不匹配时只是 `return`，不会崩**（`Src/main.c:1765-1783`）。

**待查方向**：
1. AM32 bootloader 的跳转条件（是否需要 DShot 线的特定电平 / 特定握手）
2. `0x08000FE0` 处的 `devinfo` 内容（是否 magic `0x5925e3da/0x4eb863d9`）
3. 当前这颗 bootloader 是否本来就要求"先由上位机在信号线上发升级指令"才会驻留

**⇒ 影响**：实机测试期间可用 SWD 手工装 SP/PC 启动绕过；**但飞行前必须解决**。

### ★ devinfo 实测（补 P4）

```
0x08000FE0: 5925e3da 4eb863d9 ...     ← magic1/magic2 完全匹配 ✅
deviceInfo[4] = 0x2b                  ⇒ 运行时 eeprom_address = 0x0801F800
```

**⇒ 两条结论：**
1. **这是一颗标准 AM32 bootloader**（支持 devinfo 握手），不是野的。
2. **★ 我先前加 `SIXTY_FOUR_KB_MEMORY` 是修错了方向** —— 我把宏对齐了**链接脚本**，
   而权威是 **bootloader 的运行时握手**（`checkDeviceInfo()` 会覆盖成 0x0801F800）。
   **已撤销该宏。**

**⇒ 教训（与飞控那条同源）**：**当"静态配置"和"运行时握手"打架时，以运行时为准** ——
这和处理"写入值 vs 回读值"、"手册 vs 实测"是同一条纪律。
