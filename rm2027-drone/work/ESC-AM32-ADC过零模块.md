# AM32 软件过零模块（adc_bemf）—— RM2027 自研电调

> 生成 2026-10-01　依据：`work/ESC-引脚映射-已核对.md`
> 状态：**已编译通过**，产物 `obj/AM32_RM2027_ESC_G071_2.21.bin`（FLASH 25584 B / 40.44%）

## 0. 为什么需要它

本板主控 STM32G071GBU6N 上，三相电压只有 **VC** 落在比较器输入脚（`PA2=COMP2_INM`，`V0=PA3=COMP2_INP`），
而 **VB(PA4) / VA(PA5) 没有 COMP 功能** ⇒ 三相比比较的硬件方案**物理不可行** ⇒ 过零必须软件判。

## 1. 新增 `Mcu/g071/Inc/adc_bemf.h`
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
```

## 2. 新增 `Mcu/g071/Src/adc_bemf.c`
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

/* 触发源改为定时器 / ADC-DMA 中断 ⇒ 不再需要 EXTI 使能/屏蔽 */
void enableCompInterrupts(void) { }
void maskPhaseInterrupts(void) { }

#endif /* USE_ADC_BEMF */
```

## 3. `Mcu/g071/Src/comparator.c` 加守卫
```c
/*
 * comparator.c
 *
 *  Created on: Sep. 26, 2020
 *      Author: Alka
 */

#include "comparator.h"

#include "common.h"
#include "targets.h"

#ifdef USE_ADC_BEMF
/* 本板走 adc_bemf.c 的软件过零，整个比较器实现不参与编译 */
#else
...
#endif /* !USE_ADC_BEMF */   ← 文件末尾
```

## 4. ★ 与 AM32 原逻辑的对应关系（关键：main.c 一行不改）

| AM32 原实现（comparator.c） | 本模块（adc_bemf.c） |
|---|---|
| `getCompOutputLevel()` 读 `active_COMP->CSR>>30&1` | **施密特滞回**比较 `相−V0` 与 ±阈值 |
| `changeCompInput()` 用 `LL_COMP_ConfigInputs` 切比较器输入 | 按 `step` 切换**读取哪个 ADC 通道** |
| `enableCompInterrupts()` 使能 EXTI 17/18 | 空实现（触发源改为定时器/ADC-DMA 中断） |
| `maskPhaseInterrupts()` 关 EXTI | 空实现 |

**step → 悬空相**（与 comparator.c 完全一致）：`1/4→C`、`2/5→A`、`3/6→B`

## 5. 中断入口（已勘察，是替换点）

```c
// Mcu/g071/Src/stm32g0xx_it.c:237  ADC1_COMP_IRQHandler（G0 上 ADC 与 COMP 共用向量）
if (INTERVAL_TIMER->CNT > (average_interval >> 1)) {
    interruptRoutine();                    // ← 真正做换相
} else if (getCompOutputLevel() == rising) { return; }   // ← 已内置"太早的边沿丢弃"
```

⇒ 新 ISR 只需：轮询 `getCompOutputLevel()`，检测到**跳变**就调用**同一个** `interruptRoutine()`，
并**保留它原有的太早丢弃保护**。施密特滞回 + 原有保护 = 双重抗噪。

## 6. ⚠️ 当前**还没做完**的部分（重要，别误读成能转了）

1. **ADC 通道没接进去** —— `bemf_adc_va/vb/vc/v0` 现在恒为初值 2048，因为还没加进 ADC 扫描序列。
   现有扫描是 3 路（温度/电压/电流），要扩到 7 路。
2. **定时器 ISR 没挂** —— 触发源还是空的。
   ⇒ 候选：复用已有的 ADC-DMA 完成中断（`DMA1_Channel1_IRQHandler`），**不必新增定时器**。
3. **滞回阈值 8 LSB 是估计值**，上机按波形调。

⇒ **现在的状态：能编、能烧、能跑 bootloader，但电机转不过开环阶段。**
   这两步（1、2）做完才能上机。
