# AM32 target：RM2027_ESC_G071（待并入 targets.h）

> 生成日期 2026-10-01　依据：work/ESC-引脚映射-已核对.md
> 用途：这段要**插入 AM32 源码的 `Inc/targets.h`**（两处：G071 targets 段 + hardware groups 段）

## 一、插到 `G071 Targets` 段（放在 `#ifdef RRIOT_G071` 之前）
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
```

## 二、插到 hardware groups 段（放在 `#ifdef HARDWARE_GROUP_G0_L` 之前）
```c
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
#endif
```

## 三、当前编译状态
```
target 已被识别；编译一路走到 Mcu/g071/Src/comparator.c 才停，报：
  comparator.c:56: error: 'PHASE_A_COMP' undeclared
  comparator.c:64: error: 'PHASE_B_COMP' undeclared
⇒ 这正是"第三条分支"要替换的地方（本板无可用比较器通路）。
```
