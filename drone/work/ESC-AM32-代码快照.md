# AM32 改造代码快照（RM2027_ESC_G071）

> 生成 2026-10-01　克隆位置：`/tmp/am32-1790861396`（**临时目录，会丢**）
> 状态：**编译通过**，产物 `obj/AM32_RM2027_ESC_G071_2.21.bin`（FLASH 25764 B / 40.72%，RAM 3760 B / 22.95%）

本文件是**当前全部改动的可复原快照**。改动共 4 个文件：
`Inc/targets.h` / `Mcu/g071/Src/ADC.c` / `Mcu/g071/Src/comparator.c` / `Mcu/g071/Inc+adc_bemf.h` / \`Mcu/g071/Src/adc_bemf.c`

## 1. `Inc/targets.h` —— 新增 target 与硬件组
```c
#ifdef RM2027_ESC_G071
#define FILE_NAME "RM2027_ESC_G071"
#define FIRMWARE_NAME "RM2027 ESC "
#define DEAD_TIME 60
#define MILLIVOLT_PER_AMP 60          /* 3mΩ × 20V/V = 60 mV/A */
#define CURRENT_OFFSET 0              /* 待确认 INA240 REF 接法 */
#define TARGET_STALL_PROTECTION_INTERVAL 9000
#define TARGET_VOLTAGE_DIVIDER 110    /* (47K+4.7K)/4.7K = 11.0 -> ×10 */
#define HARDWARE_GROUP_G0_RM2027
#define USE_SERIAL_TELEMETRY
#define USE_LED_STRIP

#define VOLTAGE_ADC_PIN LL_GPIO_PIN_0
#define VOLTAGE_ADC_CHANNEL LL_ADC_CHANNEL_0    /* PA0 = VBAT_SENSE */
#define CURRENT_ADC_PIN LL_GPIO_PIN_1
#define CURRENT_ADC_CHANNEL LL_ADC_CHANNEL_1    /* PA1 = BAT_CURRENT */
#endif

#ifdef HARDWARE_GROUP_G0_RM2027
/* RM2027 自研电调板 —— STM32G071GBU6N + FD6288Q + INA240A1
 * 引脚依据：references/硬件手册/ESC_电调板_原理图_2026-09-24.pdf（已逐行核对 + 手册交叉验证）
 * 本组 = AM32 原生 HARDWARE_GROUP_G0_K，仅两处不同：
 *   ① PHASE_A_LOW: PB1 -> PB15（本板 TIM1_CH3N 走 PB15）
 *   ② DShot 输入 : PB4 -> PA6 （同为 TIM3_CH1）
 */
#define MCU_G071
#define USE_TIMER_3_CHANNEL_1
#define INPUT_PIN LL_GPIO_PIN_6
#define INPUT_PIN_PORT GPIOA
#define IC_TIMER_CHANNEL LL_TIM_CHANNEL_CH1
#define IC_TIMER_REGISTER TIM3
#define IC_TIMER_POINTER htim3

#define INPUT_DMA_CHANNEL LL_DMA_CHANNEL_1
#define DMA_HANDLE_TYPE_DEF hdma_tim3_ch1
#define IC_DMA_IRQ_NAME DMA1_Channel1_IRQn

/* 六路门极：TIM1 CH1/2/3 + 互补 CH1N/2N/3N */
#define PHASE_C_GPIO_LOW  LL_GPIO_PIN_7
#define PHASE_C_GPIO_PORT_LOW  GPIOA
#define PHASE_C_GPIO_HIGH LL_GPIO_PIN_8
#define PHASE_C_GPIO_PORT_HIGH GPIOA

#define PHASE_B_GPIO_LOW  LL_GPIO_PIN_0
#define PHASE_B_GPIO_PORT_LOW  GPIOB
#define PHASE_B_GPIO_HIGH LL_GPIO_PIN_9
#define PHASE_B_GPIO_PORT_HIGH GPIOA

#define PHASE_A_GPIO_LOW  LL_GPIO_PIN_15
#define PHASE_A_GPIO_PORT_LOW  GPIOB
#define PHASE_A_GPIO_HIGH LL_GPIO_PIN_10
#define PHASE_A_GPIO_PORT_HIGH GPIOA

/* ★ 本板【没有可用的比较器通路】：
 *     PA2=VC_SENSE(COMP2_INM)、PA3=V0_SENSE(COMP2_INP) 能进比较器，
 *     但 PA4=VB_SENSE、PA5=VA_SENSE 【没有 COMP 功能】⇒ 三相无感必须软件过零。
 *   ⇒ 走新增的 ADC-BEMF 路径，不定义 PHASE_x_COMP。
 */
#define USE_ADC_BEMF
#define BEMF_ADC_PHASE_A_CH LL_ADC_CHANNEL_5   /* PA5 = VA_SENSE */
#define BEMF_ADC_PHASE_B_CH LL_ADC_CHANNEL_4   /* PA4 = VB_SENSE */
#define BEMF_ADC_PHASE_C_CH LL_ADC_CHANNEL_2   /* PA2 = VC_SENSE */
#define BEMF_ADC_NEUTRAL_CH LL_ADC_CHANNEL_3   /* PA3 = V0_SENSE  */
/* AWD（模拟看门狗）用的通道编码，与上面一一对应 */
#define BEMF_AWD_PHASE_A_CH LL_ADC_AWD_CHANNEL_5_REG
#define BEMF_AWD_PHASE_B_CH LL_ADC_AWD_CHANNEL_4_REG
#define BEMF_AWD_PHASE_C_CH LL_ADC_AWD_CHANNEL_2_REG
#endif

```
## 2. `Mcu/g071/Inc/adc_bemf.h`
```c
/*
 * adc_bemf.h —— 软件过零检测（ADC 版 BEMF）
 *
 * 仅在本板（RM2027 自研电调）使用：定义 USE_ADC_BEMF 时生效。
 * 与 comparator.h 提供【完全同名】的接口，故 Src/main.c 的换相状态机无需改动。
 */
#pragma once

#include <stdint.h>

/* ADC 原始码（由 ADC DMA 扫描序列填入） */
extern volatile uint16_t bemf_adc_va;   /* PA5 = VA_SENSE */
extern volatile uint16_t bemf_adc_vb;   /* PA4 = VB_SENSE */
extern volatile uint16_t bemf_adc_vc;   /* PA2 = VC_SENSE */
extern volatile uint16_t bemf_adc_v0;   /* PA3 = V0_SENSE  */

void     adc_bemf_set_hysteresis(uint16_t hyst_lsb);
uint16_t adc_bemf_get_hysteresis(void);
int16_t  adc_bemf_get_delta(void);      /* 当前悬空相 − V0（有符号） */

/* ★ AWD：把"相电压 vs 阈值"的比较交给 ADC 硬件，只在跨越时中断 */
void adc_bemf_config_watchdog(uint32_t awd_channel, uint16_t center, uint16_t hyst);
void adc_bemf_watchdog_for_phase(void);  /* 按当前 step 选悬空相并重设窗口 */
```
## 3. `Mcu/g071/Src/adc_bemf.c`
```c
/*
 * adc_bemf.c —— 软件过零检测（ADC 版 BEMF，带施密特滞回）
 *
 * 为什么需要它：
 *   本板主控 STM32G071GBU6N 上，三相电压只有 VC 落在比较器输入脚
 *   （PA2 = COMP2_INM，V0 在 PA3 = COMP2_INP），而 VB(PA4) / VA(PA5) 【没有 COMP 功能】
 *   ⇒ 三相比比较的硬件方案物理不可行 ⇒ 过零必须由软件判。
 *   （这正是硬件设计方所说"本该硬件做、要靠软件实现"的那一项。）
 *
 * 设计要点：
 *   1. 接口与 comparator.c 完全同名 ⇒ main.c 一行不改。
 *   2. getCompOutputLevel() 内部是【施密特滞回】比较器：越过 +H 才置 1、越过 −H 才置 0，
 *      中间保持 ⇒ 零点附近的噪声不会来回翻转（这是软件过零最关键的一招）。
 *   3. 触发源不再是比较器 EXTI，而是定时器/ADC-DMA 中断（见 stm32g0xx_it.c）。
 */
#include "adc_bemf.h"
#include "comparator.h"   /* 只为了 step / rising 等 extern 声明 */
#include "common.h"
#include "targets.h"

#ifdef USE_ADC_BEMF

/* ---- ADC 扫描结果（DMA 目标；上电初值取中点，避免未采样时乱跳） ---- */
volatile uint16_t bemf_adc_va = 2048;
volatile uint16_t bemf_adc_vb = 2048;
volatile uint16_t bemf_adc_vc = 2048;
volatile uint16_t bemf_adc_v0 = 2048;

/* ---- 施密特滞回阈值（ADC 码，12 位） ----
 * 1 LSB ≈ 3.3V/4096 = 0.806 mV；相电压衰减 10/57 = 0.1754
 * ⇒ 8 LSB(ADC) ≈ 6.4 mV ⇒ 折算到相电压侧 ≈ 37 mV
 * 初值 8，上机按波形再调（低速往下调、噪声大往上调）。
 */
static uint16_t bemf_hyst  = 8;
static uint8_t  bemf_state = 0;      /* 滞回后的稳定状态 */
static uint8_t  active_phase = 0;    /* 0=A(PA5)  1=B(PA4)  2=C(PA2) */

void adc_bemf_set_hysteresis(uint16_t hyst_lsb) { bemf_hyst = hyst_lsb; }
uint16_t adc_bemf_get_hysteresis(void)          { return bemf_hyst; }

/* 选当前【悬空】相 —— 判据与 comparator.c 的 step 映射完全一致：
 *   step 1/4 → C 悬空 ; 2/5 → A 悬空 ; 3/6 → B 悬空
 */
void changeCompInput(void)
{
    if (step == 1 || step == 4) {
        active_phase = 2;

    } else if (step == 2 || step == 5) {
        active_phase = 0;

    } else if (step == 3 || step == 6) {
        active_phase = 1;
    }
}

int16_t adc_bemf_get_delta(void)
{
    int16_t vph;

    switch (active_phase) {
    case 0:  vph = (int16_t)bemf_adc_va; break;

    case 1:  vph = (int16_t)bemf_adc_vb; break;

    default: vph = (int16_t)bemf_adc_vc; break;
    }

    return (int16_t)(vph - (int16_t)bemf_adc_v0);
}

/* ★ 施密特滞回比较器（取代 active_COMP->CSR >> 30 & 1）
 * 注意极性：Src/main.c 里用的是 `!getCompOutputLevel()`，此处沿用 comparator.c 的约定。
 */
uint8_t getCompOutputLevel(void)
{
    int16_t d = adc_bemf_get_delta();

    if (d > (int16_t)bemf_hyst) {
        bemf_state = 1;

    } else if (d < -(int16_t)bemf_hyst) {
        bemf_state = 0;
    }

    /* 落在 ±hyst 之间 ⇒ 保持原状态（这就是滞回） */
    return bemf_state;
}

/* ★★ AWD（模拟看门狗）：把阈值比较放进 ADC 硬件
 *   center = 悬空相的过零阈值 = ADC_raw_volts / 2（六步换相下 V_C 过零 ⟺ V_C = VBAT/2）
 *   hyst   = 滞回半宽，天然构成施密特（上下沿两个阈值）
 *   ⇒ 只有真正跨越窗口才中断；采样一万次里没跨越就一次都不打扰 CPU。
 */
void adc_bemf_config_watchdog(uint32_t awd_channel, uint16_t center, uint16_t hyst)
{
    uint32_t low  = (center > hyst) ? (uint32_t)(center - hyst) : 0u;
    uint32_t high = (uint32_t)center + hyst;

    if (high > 4095u) { high = 4095u; }

    LL_ADC_SetAnalogWDMonitChannels(ADC1, LL_ADC_AWD1, awd_channel);
    LL_ADC_ConfigAnalogWDThresholds(ADC1, LL_ADC_AWD1, high, low);
    LL_ADC_ClearFlag_AWD1(ADC1);
    LL_ADC_EnableIT_AWD1(ADC1);
}

/* 按当前 step 选悬空相 ⇒ 换监视通道 + 重算阈值（每次换相调用一次） */
void adc_bemf_watchdog_for_phase(void)
{
    extern uint16_t ADC_raw_volts;
    uint32_t center = (uint32_t)ADC_raw_volts / 2u;   /* 与 ADC 同一码域 */

    switch (active_phase) {
    case 0:  adc_bemf_config_watchdog(BEMF_AWD_PHASE_A_CH, center, bemf_hyst); break;

    case 1:  adc_bemf_config_watchdog(BEMF_AWD_PHASE_B_CH, center, bemf_hyst); break;

    default: adc_bemf_config_watchdog(BEMF_AWD_PHASE_C_CH, center, bemf_hyst); break;
    }
}

/* 触发源改为定时器 / ADC-DMA 中断 ⇒ 不再需要 EXTI 使能/屏蔽 */
void enableCompInterrupts(void) { }
void maskPhaseInterrupts(void) { }

#endif /* USE_ADC_BEMF */
```
## 4. `Mcu/g071/Src/ADC.c` 的改动（5 处）
```
① DMA 缓冲区 3 -> 7（USE_ADC_BEMF 分支）
② ADC_DMA_Callback 里映射 bemf_adc_va/vb/vc/v0 = ADCDataDMA[3..6]
③ ADC 时钟 DIV4 -> DIV2（16 -> 32 MHz）
④ 序列 3RANKS -> 7RANKS，追加 RANK_4..7 = VA/VB/VC/V0（全用 COMMON_1=19.5 周期）
⑤ DMA 长度 3 -> 7
```
## 5. `Mcu/g071/Src/comparator.c`
```c
#include "targets.h" 之后插入：
#include "common.h"
#include "targets.h"

#ifdef USE_ADC_BEMF
/* 本板走 adc_bemf.c 的软件过零，整个比较器实现不参与编译 */
#else

...
文件末尾：#endif /* !USE_ADC_BEMF */
```

## 6. ⚠️ 还没做的（计划 P3 的改动 3/4/5）

| # | 待办 | 为什么现在没做 |
|---|---|---|
| 3 | 删掉 `Src/main.c` 里的 `LL_ADC_REG_StartConversion(ADC1)` | **故意保留 1 kHz 软件触发**，好让第一次台架验证只验"接线对不对"，不动时间架构 |
| 4 | `adc_bemf_watchdog_for_phase()` 在换相处被调用 | 依赖 5 |
| 5 | **独立定时器**产生 ADC 触发（~60-150 kHz 分档）+ AWD 中断接 `interruptRoutine()` | 依赖台架先确认 A1/A2 假设 |

## 7. 台架验证要用到的两个接口（已就绪、可直接调）
```c
adc_bemf_config_watchdog(BEMF_AWD_PHASE_A_CH, center, hyst);  // 配 AWD 窗口
adc_bemf_watchdog_for_phase();                                 // 按当前 step 自动选相+重算
bemf_adc_va / bemf_adc_vb / bemf_adc_vc / bemf_adc_v0;         // 4 路原始码
```
