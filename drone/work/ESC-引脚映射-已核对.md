# RM2027 电调板（自研）—— 引脚映射（已核对）

> 来源：`references/硬件手册/ESC_电调板_原理图_2026-09-24.pdf`（单页原理图）
> 核对方式：**把 U1 符号整颗渲成图逐行读**，并用 `STM32G071GB_datasheet_extract.md` 的引脚表**逐条交叉验证**
> 核对日期：2026-10-01

---

## 0. 一句话

**主控 `STM32G071GBU6N`（Cortex-M0+ 64 MHz / 128 KB Flash / 36 KB RAM / UFQFPN28），
三相栅极驱动 `FD6288Q`，电流采样 `INA240A1PWR`，WS2812B 状态灯。
六路门极 = `TIM1` 的 CH1/2/3 + 互补 CH1N/2N/3N（标准互补 PWM）。**

---

## 1. U1 引脚映射（逐行已核）

| pin | GPIO | 外设 | 网络名 | 说明 |
|:---:|:---:|:---|:---|:---|
| 6 | **PA0** | ADC_IN0 | `VBAT_SENSE` | 电池电压采样（分压） |
| 7 | **PA1** | ADC_IN1 | `BAT_CURRENT` | 母线电流（INA240 输出） |
| 8 | **PA2** | ADC_IN2 | `VC_SENSE` | **相 C 电压** ⚠️ 也是 `COMP2_INM` |
| 9 | **PA3** | ADC_IN3 | `V0_SENSE` | **虚拟中性点** ⚠️ 也是 `COMP2_INP` |
| 10 | **PA4** | ADC_IN4 | `VB_SENSE` | **相 B 电压**（⚠️ **无 COMP 功能**；另有 DAC_OUT1） |
| 11 | **PA5** | ADC_IN5 | `VA_SENSE` | **相 A 电压**（⚠️ **无 COMP 功能**；另有 DAC_OUT2） |
| 12 | **PA6** | （TIM3_CH1 可用） | `ESC_DSHOT` | DShot 输入（输入捕获） |
| 13 | **PA7** | **TIM1_CH1N** | `C_LIN` | C 相下管 |
| 14 | **PB0** | **TIM1_CH2N** | `B_LIN` | B 相下管 |
| 15 | **PB15** | **TIM1_CH3N** | `A_LIN` | A 相下管 |
| 16 | **PA8** | **TIM1_CH1** | `C_HIN` | C 相上管 |
| 18 | **PA9** | **TIM1_CH2** | `B_HIN` | B 相上管（原理图符号写作 `PA11[PA9]`） |
| 19 | **PA10** | **TIM1_CH3** | `A_HIN` | A 相上管（原理图符号写作 `PA12[PA10]`） |
| 20 | PA13 | — | `SWDIO` | 调试 |
| 21 | PA14-BOOT0 | — | `SWCLK` | 调试（兼 BOOT0，接线注意） |
| 26 | **PB6** | USART1_TX | `USART_TX` | 串口（遥测/调试） |
| 28 | **PB8** | — | `LED_IN` | WS2812B 数据线 |

**未连接**：`PC14/PC15`(1,2)、`PB7`(27)、`PD0~PD3`(22~25)、`PC6`(17)。

### 1.1 关于 `PA11[PA9]` / `PA12[PA10]` 这个方括号

**这是 ST 官方数据手册自己的写法**（DS12232 引脚表里 `PA11 [PA9]`、`PA12 [PA10]`，脚注 (5)）。
⇒ 同一物理脚在不同封装下命名不同：**本板是 UFQFPN28，该脚就叫 PA9 / PA10。**
⇒ 而只有 **PA9 = TIM1_CH2、PA10 = TIM1_CH3** 成立（`PA11` 是 `TIM1_CH4`、`PA12` 是 `TIM1_ETR`）。
**⇒ 原理图标的 `TIM1_CH2/CH3` 与 GPI 命名自洽，映射成立。**

---

## 2. ★ 比较器能力：**三相里只有一相能进 COMP**

G071 的 COMP 输入脚（数据手册 Additional Functions 列）：

| 引脚 | COMP 功能 |
|:---|:---|
| PA0 | `COMP1_INM` |
| PA1 | `COMP1_INP` |
| **PA2** | **`COMP2_INM`** |
| **PA3** | **`COMP2_INP`** |
| PA4 | ❌ 无 |
| PA5 | ❌ 无 |
| PB1/PB2 | `COMP1_INM/INP`（28 脚封装未引出） |
| PB3/PB4/PB6/PB7 | `COMP2_INM/INP`（28 脚封装未引出） |

**⇒ 本板把 `VC`(PA2) 与 `V0`(PA3) 放在了比较器脚上，而 `VB`(PA4)/`VA`(PA5) 进不了比较器
⇒ 三相无感 BEMF 的「硬件比较器」方案在这颗芯片 + 这个封装上**物理不可行**。**

**⇒ 结论：过零检测必须由软件做（读 ADC 比较 `相电压 vs V0`）。这就是硬件队友所说的"本该硬件做、要靠软件实现"的那一项。**

---

## 3. FD6288Q（U2）连接

```text
LIN1/2/3 ← A_LIN / B_LIN / C_LIN
HIN1/2/3 ← A_HIN / B_HIN / C_HIN
HO1/2/3  → A_HO / B_HO / C_HO   （上管门极）
LO1/2/3  → 下管门极
VB1/2/3  = 自举（B5819WS + 电容）
VS1/2/3  = 开关节点
MOTORA/B/C = 电机三相
```
**关键：FD6288Q 内置 200 ns 死区 ⇒ 死区由硬件保证，固件不必管。**（但互补 PWM 的配置仍要正确）

---

## 4. Flash 布局（实测确认）

```text
0x08000000 ~ 0x08000FFF   4 KB     【已烧】AM32 bootloader（实测 4092 B，正好卡在边界）
0x08001000 ~               app     AM32 application（APPLICATION_ADDRESS = 0x08001000）
0x0801F800 ~               eeprom  EEPROM_START_ADD（128 KB 片，不用 SIXTY_FOUR_KB_MEMORY）
```

**实测佐证**：`arm-none-eabi` 链接 AIKON_PRO_G071 target 时输出
`FLASH: 25360 B / 63264 B`、`EEPROM_START_ADD = 0x0801F800` ⇒ 区间与上表一致。

**备份**：`work/esc-flash-backup-2026-10-01.bin`
（65536 B，sha256 `b72d75aa808d4e6adfcec06b1af5c115087e12651632d506ac57f73fc26a1f9c`）

---

## 5. 与 AM32 target 字段的对应关系

| AM32 字段 | 本板取值 |
|:---|:---|
| `MCU_G071` | ✓ |
| （不定义）`SIXTY_FOUR_KB_MEMORY` | 本片 128 KB ⇒ 不定义 |
| `PHASE_A/B/C_GPIO_HIGH` | `PA10` / `PA9` / `PA8` |
| `PHASE_A/B/C_GPIO_LOW` | `PB15` / `PB0` / `PA7` |
| `INPUT_PIN`（DShot） | `PA6`（TIM3_CH1） |
| `VOLTAGE_ADC_PIN / CH` | `PA0` / `LL_ADC_CHANNEL_0` |
| `CURRENT_ADC_PIN / CH` | `PA1` / `LL_ADC_CHANNEL_1` |
| **BEMF** | ⚠️ **不能用 `PHASE_x_COMP`** —— 需新增 ADC 路径（见 §2） |
| 电机极对数/方向等 | 待定 |

---

## 6. 待办

- [ ] **上电用示波器验证六路门极**（PA7/PB0/PB15/PA8/PA9/PA10 依次翻转）—— 引脚表的最终确认
- [ ] 电压分压比（`TARGET_VOLTAGE_DIVIDER`）、电流采样比例（`MILLIVOLT_PER_AMP`）需从原理图电阻值算出
- [ ] 电机 KV/极对数、旋转方向

---

## 7. 模拟前端参数（已从原理图读出）

### 7.1 电流采样

```text
VBAT ─F1(32V/30A 保险丝)─ U5【3 mΩ 采样电阻】─ VIN
                              └─ U3 INA240A1PWR（增益 20 V/V）
                                 OUT ─R37(1K)─ BAT_CURRENT     ← R37+C31 构成 RC 滤波，不影响直流增益
```

| 量 | 值 | 推导 |
|---|---|---|
| 灵敏度 | **60 mV/A** | `3 mΩ × 20 V/V = 0.06 V/A` |
| 满量程 | **±27.5 A** | `±1.65 V ÷ 0.06` ⇒ 与 30 A 保险丝匹配 ✓ |
| ⇒ AM32 `MILLIVOLT_PER_AMP` | **60** | `Src/main.c:2171` 的口径就是 mV/A |
| ⇒ AM32 `CURRENT_OFFSET` | **0（待确认）** | 取决于 INA240 的 `REF1/REF2` 接法：接 GND ⇒ 单向、零点 0 mV ⇒ 0；接中点 ⇒ 双向、约 1650 mV |

### 7.2 相电压分压（BEMF）

```text
MOTORA ──R1(47K)──┬── VA_SENSE
                  R2(10K)
                  └── V0_SENSE  ← 三个 10K 星形接法 = 虚拟中性点
MOTORB ──R3(47K)──┬── VB_SENSE     R4(10K) ─┘
MOTORC ──R5(47K)──┬── VC_SENSE     R6(10K) ─┘
```

| 量 | 值 |
|---|---|
| 衰减系数 | **10/(47+10) = 0.1754** |
| BEMF 在 ADC 上的摆幅（6S） | ±2.21 V（`12.6 V × 0.1754`）在 3.3 V 内 ✓ |
| ⚠️ **低速信噪比** | 低速时 BEMF 只剩几 mV × 0.1754，而 ADC = 0.8 mV/LSB ⇒ **低速过零信噪比差**。这是软件过零要调的第一个坑（比较器在这一点上确实更优） |

### 7.3 电池电压分压

```text
VBAT ──R32(47K)──┬── VBAT_SENSE ──→ PA0
                 R33(4.7K)
                 └── GND
```

| 量 | 值 |
|---|---|
| 分压比 | **4.7/(47+4.7) = 0.09091** ⇒ **衰减 11.0 倍** |
| 满量程 | 3.3 V × 11 = **36.3 V**（6S/8S 都够） |
| ⇒ AM32 `TARGET_VOLTAGE_DIVIDER` | **110**（口径 = 比值 × 10，见 `Src/main.c:386` 注释） |

---

## 8. target 参数汇总（除 BEMF 外已齐）

| AM32 字段 | 本板取值 | 依据 |
|:---|:---|:---|
| `MCU_G071` | ✓ | |
| `SIXTY_FOUR_KB_MEMORY` | **不定义**（128 KB 片） | |
| `TARGET_VOLTAGE_DIVIDER` | **110** | R32/R33 = 47K/4.7K |
| `MILLIVOLT_PER_AMP` | **60** | 3 mΩ × 20 V/V |
| `CURRENT_OFFSET` | **0（待确认 REF 接法）** | |
| `DEAD_TIME` | **待定**（FD6288Q 内置 200 ns） | |
| `PHASE_A_GPIO_HIGH/LOW` | `PA10` / `PB15` | |
| `PHASE_B_GPIO_HIGH/LOW` | `PA9` / `PB0` | |
| `PHASE_C_GPIO_HIGH/LOW` | `PA8` / `PA7` | |
| `INPUT_PIN`（DShot） | `PA6` | |
| **BEMF** | ⚠️ **不能用 `PHASE_x_COMP`**，需新增 ADC 路径 | §2 |
