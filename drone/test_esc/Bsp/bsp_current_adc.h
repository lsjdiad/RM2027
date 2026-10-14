/**
 * @file    bsp_current_adc.h
 * @brief   电调【电流模拟量】采集：ADC1_IN1 = PA1
 *
 * 【为什么需要它】
 *   电调板把电流做成了两路输出：
 *     ① 数字：串口遥测帧里的 current 字段（模块 module_kiss 解）
 *     ② 模拟：INA240 放大器的输出电压，直接引到接插件上给飞控 ADC 采
 *   这条模拟线是飞控侧"电流"的来源，所以测试台必须能读它，
 *   而且可以和 ① 对比 —— 两条路对不上就说明其中一路有问题。
 *
 * 【换算】本板分流电阻 3 mΩ、INA240 增益 20 V/V ⇒ 灵敏度 60 mV/A。
 *   （依据：`work/ESC-引脚映射-已核对.md` §7.1；AM32 侧同值 MILLIVOLT_PER_AMP=60）
 *   INA240 REF1/REF2 接 GND ⇒ 单向、零点 0 V、满量程 ±27.5 A。
 *
 * 【引脚】★ 默认 PA1 = ADC1_IN1，对应电调板 U6 座子的第 1 脚 ADC_IN1。
 */
#pragma once
#include <stdint.h>

#define CURRENT_ADC_PIN              1u    /* PA1 */
#define CURRENT_MILLIVOLT_PER_AMP    60    /* 3 mΩ × 20 V/V */
#define CURRENT_OFFSET_MV            0     /* REF 接 GND ⇒ 零点 0 mV */

/** 初始化 ADC1（12 位、通道 1、软件触发、含自校准） */
void bsp_current_adc_init(void);

/** 采一次（阻塞约 6 µs），带 8 次滑动平均 */
void bsp_current_adc_sample(void);

uint16_t bsp_current_adc_raw(void);         /* 平均后的 12 位原始值 */
uint16_t bsp_current_adc_mv(void);          /* 引脚电压 mV */
int32_t  bsp_current_adc_centiamps(void);   /* 电流，单位 0.01 A（与遥测帧同口径） */
uint32_t bsp_current_adc_samples(void);     /* 累计采样次数 */
