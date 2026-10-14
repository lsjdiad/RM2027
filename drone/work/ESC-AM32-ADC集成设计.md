# AM32 ADC 集成设计（软件过零的快通道）

> 2026-10-01　前置：[`ESC-AM32-ADC过零模块.md`](ESC-AM32-ADC过零模块.md)（模块已写完、编译通过）
> 本文解决**模块写完但还没接进去**的那两步：ADC 通道 + 中断触发。

---

## 1. 现状（实测）

```c
// Mcu/g071/Src/ADC.c
uint16_t ADCDataDMA[3];                        // [0]=电流 [1]=电压 [2]=温度
ADC_REG_InitStruct.TriggerSource = LL_ADC_REG_TRIG_SOFTWARE;   // ← 软件触发
ADC_REG_InitStruct.SequencerLength = LL_ADC_REG_SEQ_SCAN_ENABLE_3RANKS;
ADC_REG_InitStruct.ContinuousMode  = LL_ADC_REG_CONV_SINGLE;
LL_ADC_SetClock(ADC1, LL_ADC_CLOCK_ASYNC_DIV4);                // 64/4 = 16 MHz
LL_ADC_SetSamplingTimeCommonChannels(..., COMMON_1, 19CYCLES_5);   // 电流/电压
LL_ADC_SetSamplingTimeCommonChannels(..., COMMON_2, 160CYCLES_5);  // 温度
```
`bemf_adc_va/vb/vc/v0` 目前恒为初值 2048 —— **没有任何东西填它们**。

---

## 2. ★ 速率账（这决定设计，必须先算）

| 项 | 值 |
|---|---|
| 相分压源阻抗 | `47K ∥ 10K ≈ 8.3 kΩ` |
| 12 位精度所需最小采样时间 | `≈ R·C·ln(4096) ≈ 8.3k × 4p × 8.3 ≈ 0.27 µs` ⇒ 32 MHz 下约 **9 周期** |
| ⇒ 安全取值 | **19.5 周期**（**不能**压到 1.5 周期） |
| 每通道耗时 @16 MHz | `(19.5+12.5)/16M = 2.0 µs` |
| 温度传感器 | `(160.5+12.5)/16M = 10.8 µs` |
| **现状 7 通道合计** | **≈ 23 µs ⇒ 43 kHz** ❌ 远不够 |
| **把温度挪走后（6 通道）@16 MHz** | `6 × 2.0 = 12 µs ⇒ 83 kHz` |
| **再把 ADC 时钟提到 /2（32 MHz）** | `6 × 1.0 = 6 µs ⇒ 167 kHz` ✅ |

**⇒ 目标 167 kHz ⇒ 过零分辨率 6 µs。**
**对比最高转速时每步 ≈ 24 µs（14 极电机 @ 60k RPM）⇒ 每步约 4 个采样点。可用。**

---

## 3. 要改的四处（具体到行）

### 3.1 `Mcu/g071/Src/ADC.c`

```c
// ① 缓冲区扩到 7（保留温度位，但只在慢通道填）
uint16_t ADCDataDMA[7];      // [0]电流 [1]电压 [2]温度 [3]VA [4]VB [5]VC [6]V0

// ② ADC 时钟：16 MHz -> 32 MHz
LL_ADC_SetClock(ADC1, LL_ADC_CLOCK_ASYNC_DIV2);

// ③ 序列长度 7 + 追加 RANK_4..7（全部用 COMMON_1 = 19.5 周期）
ADC_REG_InitStruct.SequencerLength = LL_ADC_REG_SEQ_SCAN_ENABLE_7RANKS;
LL_ADC_REG_SetSequencerRanks(ADC1, LL_ADC_REG_RANK_4, BEMF_ADC_PHASE_A_CH);
LL_ADC_SetChannelSamplingTime(ADC1, BEMF_ADC_PHASE_A_CH, LL_ADC_SAMPLINGTIME_COMMON_1);
// ... RANK_5/6/7 同理（BEMF_ADC_PHASE_B_CH / C_CH / NEUTRAL_CH）

// ④ DMA 长度 3 -> 7
LL_DMA_SetDataLength(DMA1, LL_DMA_CHANNEL_2, 7);

// ⑤ 回调里填入 BEMF（ADC_DMA_Callback）
bemf_adc_va = ADCDataDMA[3];
bemf_adc_vb = ADCDataDMA[4];
bemf_adc_vc = ADCDataDMA[5];
bemf_adc_v0 = ADCDataDMA[6];

// ⑥ GPIO：把 PA2/PA3/PA4/PA5 配成模拟输入
```

### 3.2 触发源：**从软件触发改成定时器触发**

```c
// 目标 ~167 kHz。推荐用 TIM6（AM32 的 TEN_KHZ_TIMER）产 TRGO
ADC_REG_InitStruct.TriggerSource = LL_ADC_REG_TRIG_EXT_TIM6_TRGO;
LL_ADC_REG_SetTriggerEdge(ADC1, LL_ADC_REG_TRIG_EXT_RISING);
```
⚠️ 改动前先确认 TIM6 现被谁用（AM32 的 `TEN_KHZ_TIMER`）——**不要和现有 10 kHz 任务抢同一个定时器**，否则要么新建一个定时器，要么复用它并调频。

### 3.3 中断：**复用已有的 ADC-DMA 完成中断**

```c
// Mcu/g071/Src/stm32g0xx_it.c:210  DMA1_Channel2_3_IRQHandler
void DMA1_Channel2_3_IRQHandler(void)
{
    if (LL_DMA_IsActiveFlag_TC2(DMA1) == 1) {
        LL_DMA_ClearFlag_GI2(DMA1);
        ADC_DMA_Callback();          // 原有：更新 电流/电压/温度 + 新增的三相/V0

#ifdef USE_ADC_BEMF
        /* ★ 软件过零：轮询 getCompOutputLevel()，检测到跳变才动作；
           并保留 AM32 原有的"半周期内假边沿丢弃"保护 */
        uint8_t s = getCompOutputLevel();
        if (s != bemf_prev) {
            bemf_prev = s;
            if (INTERVAL_TIMER->CNT > (average_interval >> 1)) {
                interruptRoutine();
            }
        }
#endif
    }
    ...
}
```
**⇒ 不需要新增定时器做中断源** —— ADC 的 DMA 完成中断天然就是"每次采样完成"的节拍。

### 3.4 温度传感器：挪到慢通道

温度那 10.8 µs 会直接吃掉速率。建议：
- **方案 A（简单）**：把温度从序列里**移出**，另用一个低频软件触发通道偶尔采一次（AM32 本来也只需要 ~1 Hz 的温度）。
- **方案 B（更简单）**：保留在序列里，但**把 COMMON_2 的 160.5 周期降到能满足的最低值**（先查 G071 数据手册对 TS 的最小采样时间要求，不要拍脑袋）。

**⇒ 先做 A，风险最低。**

---

## 4. 上机验证顺序（**每一步都要过，别跳**）

| 步 | 做什么 | 判据 |
|---|---|---|
| 0 | 不接电机、不接 12V，只给 3.3V | 能烧、能起来 |
| 1 | 在 DMA 回调里把 `ADCDataDMA[3..6]` 通过遥测打出来 | 四路读数**随外部电压变化**（拿电阻分压或用万用表加电压试） |
| 2 | 用示波器同时看 **相电压** 与**软件算出的 `adc_bemf_get_delta()` 符号** | 两者过零点**对齐**；不对齐先查极性与 `active_phase` 映射 |
| 3 | 调滞回阈值 `adc_bemf_set_hysteresis()` | 低速能稳定过零、且不误触发 |
| 4 | 接电机低转 | 能起转、不失步 |
| 5 | 逐步升速 | 看高转速下换相是否偏晚（偏晚 ⇒ 采样率还要提） |

---

## 5. 已知风险

| # | 风险 | 缓解 |
|---|---|---|
| R1 | **低速 BEMF 信噪比差**（相衰减 0.1754 ⇒ 信号只剩几 mV，而 ADC 0.8 mV/LSB） | 施密特滞回 + 低速开环 ramp（AM32 本来就有）+ 必要时低速用更长滤波窗口 |
| R2 | **ISR 负载**：167 kHz × ~1 µs ≈ **17% CPU**（M0+ @64MHz） | 可只在"接近过零窗口"时提高采样率 |
| R3 | **DMA 与 AM32 现有 ADC 用途冲突** | `ADCDataDMA` 是同一块缓冲，改长度后要复核 `ADC_DMA_Callback()` 的索引映射 |
| R4 | 触发源与 TIM6 现有用途抢资源 | 改前先查 TIM6 的 TRGO 有没有被用 |

---

## 6. 未解的前置问题（需要硬件队友）

**PA4/PA5 无 COMP 功能 ⇒ 软件过零是唯一路**——但请顺便问他：
1. 当初是不是**有意**这么设计（他说过"要靠软件实现"），还是排引脚时没注意？
2. **有没有参考固件 / 已验证过的换相逻辑？**

---

## 7. ★★ 重要更正：真正的瓶颈是"1 kHz 软件触发"，不是温度传感器

**本节推翻了 §2 的归因。** 实测：

```c
// Src/main.c:1439-1440
if (one_khz_loop_counter > PID_LOOP_DIVIDER) {   // 1khz PID loop
    PROCESS_ADC_FLAG = 1;   // set flag to do new adc read at lower priority
}

// Src/main.c:2127-2136
if (PROCESS_ADC_FLAG == 1) {   // 注释原话："at 1khz loop rate"
    ADC_DMA_Callback();
    LL_ADC_REG_StartConversion(ADC1);   // ← 软件触发
}
```

**⇒ ADC 实际节奏 = 1 kHz（由 1 kHz PID 循环置标志、主循环执行）。**
**⇒ 软件过零需要 ~167 kHz —— 差 167 倍。**

### 这条改动比"加通道"大得多

| # | 改动 | 影响面 |
|---|---|---|
| 1 | **触发源：软件 → 硬件定时器 TRGO** | 这是**必须做**的，不是优化 |
| 2 | **删掉主循环里的 `LL_ADC_REG_StartConversion(ADC1)`** | 否则会和定时器触发打架 |
| 3 | **DMA 完成中断变成 167 kHz 高频 ISR** | 把现在主循环里做的 `ADC_DMA_Callback()` 语义挪到 ISR；主循环只读最新值（这一条**结构上反而更简单**） |
| 4 | 温度传感器挪出快通道 | 仍是需要的（省 5~10 µs），但**不再是主要矛盾** |
| 5 | 新增 BEMF 四通道 | 原计划不变 |

### 好消息
`ADC_DMA_Callback()` 本身就是"把 DMA 缓冲搬到全局变量"。
**⇒ DMA 跑到 167 kHz 后，`ADC_raw_volts/current/temp` 会自动以 167 kHz 刷新，主循环照旧读最新值即可 —— 不需要改主循环逻辑。**

### 需要确认的一件事
**TIM6（`TEN_KHZ_TIMER`）现在被 10 kHz 任务占着** ⇒ **不要复用它做 ADC 的 TRGO**，应为 ADC 单独安排一个定时器（或用它的某个通道），避免和现有 10 kHz 节奏互相干扰。

