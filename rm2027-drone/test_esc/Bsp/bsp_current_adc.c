/**
 * @file    bsp_current_adc.c
 * @brief   电流模拟量采集实现（ADC1_IN1 / PA1，直接操作寄存器）
 *
 * 【为什么不走 HAL】同 bsp_uart_telem.c：CubeMX 没开 ADC，hal_conf 与 CMake 里
 *   都没有 ADC 的 HAL 模块，为了不动 CubeMX 生成的文件，这里直接写寄存器。
 *
 * 【F1 的 ADC 顺序（照 RM0008）】
 *   ① 开 ADC1 时钟（APB2）、配 ADCPRE = PCLK2/6 ⇒ 12 MHz（F1 上限 14 MHz）
 *   ② PA1 配成模拟输入（CRL 对应位清零）
 *   ③ ADON=1 上电 → 等 tSTAB → RSTCAL 复位校准 → CAL 校准
 *   ④ 规则组：SQR3 第一个转换 = 通道 1；SQR1 长度 = 1 个转换
 *   ⑤ 触发源 = SWSTART（EXTTRIG=1, EXTSEL=111）
 *   ⑥ 每次采样：SWSTART → 等 EOC → 读 DR
 */
#include "bsp_current_adc.h"
#include "stm32f1xx.h"

#define ADC_SAMPLE_AVG_N   8u
#define ADC_VREF_MV        3300u
#define ADC_FULL_SCALE     4095u

static uint16_t s_avg[ADC_SAMPLE_AVG_N];
static uint8_t  s_avg_idx;
static uint16_t s_avg_raw;
static uint16_t s_mv;
static int32_t  s_centiamps;
static uint32_t s_samples;

void bsp_current_adc_init(void)
{
    /* ① 时钟：GPIOA + ADC1；并把 ADC 时钟分频设成 /6（12 MHz）
     *    （CubeMX 没配 ADC 时 ADCPRE 默认是 /2 = 36 MHz，会超规格 ⇒ 必须显式设） */
    RCC->APB2ENR |= RCC_APB2ENR_IOPAEN | RCC_APB2ENR_ADC1EN;
    RCC->CFGR = (RCC->CFGR & ~RCC_CFGR_ADCPRE) | RCC_CFGR_ADCPRE_DIV6;

    /* ② PA1 模拟输入：CRL 中占第 4..7 位，CNF=00 + MODE=00 */
    GPIOA->CRL &= ~(0xFu << (CURRENT_ADC_PIN * 4u));

    /* ③ 上电 + 校准 */
    ADC1->CR1 = 0;
    ADC1->CR2 = ADC_CR2_ADON;
    for (volatile uint32_t i = 0; i < 2000u; i++) { __asm volatile("nop"); }

    ADC1->CR2 |= ADC_CR2_RSTCAL;
    while (ADC1->CR2 & ADC_CR2_RSTCAL) { }
    ADC1->CR2 |= ADC_CR2_CAL;
    while (ADC1->CR2 & ADC_CR2_CAL) { }

    /* ④ 规则组：通道 1、1 个转换、采样时间 55.5 周期 */
    ADC1->SMPR2 = (5u << ((CURRENT_ADC_PIN % 10u) * 3u));
    ADC1->SQR1  = 0;
    ADC1->SQR3  = CURRENT_ADC_PIN;

    /* ⑤ 软件触发 */
    ADC1->CR2 |= ADC_CR2_EXTTRIG | ADC_CR2_EXTSEL;
}

void bsp_current_adc_sample(void)
{
    uint32_t raw;
    uint32_t sum = 0;
    uint32_t guard;

    ADC1->CR2 |= ADC_CR2_SWSTART;

    /* ★ 等待加超时：这是 1 kHz 任务里的阻塞点，万一 EOC 不来（配置错/硬件坏），
     *   死等会把整个任务连同 DShot 发送一起卡死 —— 宁可丢一次采样。 */
    guard = 200000u;
    while (((ADC1->SR & ADC_SR_EOC) == 0u) && (guard != 0u)) {
        guard--;
    }
    if (guard == 0u) {
        return;                 /* 超时：保留上一次的值，等下次 */
    }
    raw = ADC1->DR & 0x0FFFu;

    /* 8 次滑动平均：抑制开关噪声，读数稳定 */
    s_avg[s_avg_idx] = (uint16_t)raw;
    s_avg_idx = (uint8_t)((s_avg_idx + 1u) % ADC_SAMPLE_AVG_N);
    for (uint8_t i = 0; i < ADC_SAMPLE_AVG_N; i++) {
        sum += s_avg[i];
    }
    s_avg_raw = (uint16_t)(sum / ADC_SAMPLE_AVG_N);
    s_samples++;

    /* 原始值 → mV → 厘安（与 AM32 遥测帧同口径，便于两条路对比）
     *   mV  = raw × 3300 / 4095
     *   厘安 = (mV - 零点) × 100 / (mV per A) */
    s_mv = (uint16_t)(((uint32_t)s_avg_raw * ADC_VREF_MV + ADC_FULL_SCALE / 2u) / ADC_FULL_SCALE);

    if (CURRENT_MILLIVOLT_PER_AMP > 0) {
        s_centiamps = (((int32_t)s_mv - CURRENT_OFFSET_MV) * 100) / CURRENT_MILLIVOLT_PER_AMP;
        if (s_centiamps < 0) {
            s_centiamps = 0;        /* 单向采样：负值只可能是零点噪声 */
        }
    }
}

uint16_t bsp_current_adc_raw(void)        { return s_avg_raw; }
uint16_t bsp_current_adc_mv(void)         { return s_mv; }
int32_t  bsp_current_adc_centiamps(void)  { return s_centiamps; }
uint32_t bsp_current_adc_samples(void)    { return s_samples; }
