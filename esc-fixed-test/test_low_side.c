/*
 * test_low_side.c —— 固定输出状态测试固件（完全脱离 AM32）
 *
 * 目的：把 MCU 的六路门极输入钉死在一个固定状态，用来单独验证
 *       【A 相下管】这一路的硬件是否完好：
 *
 *         PB15(A_LIN) -> U2 pin1(LIN1) -> U2 pin11(LO1) -> R23 -> Q2 栅极 -> MOTORA
 *
 * 输出状态：
 *   PB15  A_LIN  = 以 A_TOGGLE_HZ 的频率翻转（默认 1 kHz，示波器上是一条干净方波）
 *                  A_TOGGLE_HZ = 0 时改为「常高」——A 下管持续导通，可用万用表量通断
 *   PB0   B_LIN  = 低    // B 相下管「完全不通」
 *   PA7   C_LIN  = 低    // C 相下管也不通
 *   PA10  A_HIN  = 低  ┐
 *   PA9   B_HIN  = 低  ├ 三个上管全部关断（避免上下管直通）
 *   PA8   C_HIN  = 低  ┘
 *
 * 烧录地址 0x08001000（AM32 的 app 槽）。测完用 AM32 的 .bin 覆盖回去即可。
 *
 * 注意：量 LO / 栅极需要 VBAT 接上 —— FD6288Q 的 VCC(6.5V) 由板载 buck 产生，
 *       只靠 ST-Link 的 3.3V 供电时 LO 不会有输出。
 *
 * 寄存器偏移来源：Mcu/g071/Drivers/CMSIS/Device/ST/STM32G0xx/Include/stm32g071xx.h
 *   RCC_BASE  = 0x40021000, RCC_IOPENR 偏移 0x34
 *   GPIOA_BASE= 0x50000000, GPIOB_BASE  = 0x50000400
 *   MODER=0x00 OTYPER=0x04 OSPEEDR=0x08 PUPDR=0x0C IDR=0x10 ODR=0x14 BSRR=0x18 BRR=0x28
 */

typedef unsigned int u32;

#ifndef A_TOGGLE_HZ
#define A_TOGGLE_HZ 1000      /* A 下管翻转频率(Hz)；0 = 常通 */
#endif

/* ---- 外设寄存器（直接地址访问，不依赖任何库） ---- */
#define RCC_IOPENR  (*(volatile u32 *)0x40021034u)
#define GPIOA_MODER (*(volatile u32 *)0x50000000u)
#define GPIOA_IDR   (*(volatile u32 *)0x50000010u)
#define GPIOA_BSRR  (*(volatile u32 *)0x50000018u)
#define GPIOA_BRR   (*(volatile u32 *)0x50000028u)
#define GPIOB_MODER (*(volatile u32 *)0x50000400u)
#define GPIOB_IDR   (*(volatile u32 *)0x50000410u)
#define GPIOB_BSRR  (*(volatile u32 *)0x50000418u)
#define GPIOB_BRR   (*(volatile u32 *)0x50000428u)
#define SCB_VTOR    (*(volatile u32 *)0xE000ED08u)

/* ---- 引脚号（对应原理图网络） ---- */
#define PIN_A_LIN 15u   /* PA? -> 是 PB15 = A_LIN（FD6288Q 的 LIN1） */
#define PIN_B_LIN  0u   /* PB0  = B_LIN               (LIN2)   */
#define PIN_C_LIN  7u   /* PA7  = C_LIN               (LIN3)   */
#define PIN_A_HIN 10u   /* PA10 = A_HIN               (HIN1)   */
#define PIN_B_HIN  9u   /* PA9  = B_HIN               (HIN2)   */
#define PIN_C_HIN  8u   /* PA8  = C_HIN               (HIN3)   */

static void delay_loops(u32 n)
{
    volatile u32 i;
    for (i = 0; i < n; i++) {
        __asm volatile("nop");
    }
}

/* 复位后跑在 HSI 16 MHz 上，无需配置时钟和 Flash 等待周期 */
int main(void)
{
    /* 1) 打开 GPIOA / GPIOB 的时钟（G0 系列在 RCC_IOPENR 的 bit0/bit1） */
    RCC_IOPENR |= (1u << 0) | (1u << 1);

    /* 2) 六个门极输入脚全部配成推挽输出（MODER 每脚 2 bit，01 = 输出） */
    GPIOA_MODER = (GPIOA_MODER & ~((3u << (2u * PIN_A_HIN)) | (3u << (2u * PIN_B_HIN))
                                 | (3u << (2u * PIN_C_HIN)) | (3u << (2u * PIN_C_LIN))))
                | (1u << (2u * PIN_A_HIN)) | (1u << (2u * PIN_B_HIN))
                | (1u << (2u * PIN_C_HIN)) | (1u << (2u * PIN_C_LIN));

    GPIOB_MODER = (GPIOB_MODER & ~((3u << (2u * PIN_A_LIN)) | (3u << (2u * PIN_B_LIN))))
                | (1u << (2u * PIN_A_LIN)) | (1u << (2u * PIN_B_LIN));

    /* 3) 先把所有脚写 0：三个上管关、B/C 下管关 */
    GPIOA_BRR = (1u << PIN_A_HIN) | (1u << PIN_B_HIN) | (1u << PIN_C_HIN) | (1u << PIN_C_LIN);
    GPIOB_BRR = (1u << PIN_B_LIN) | (1u << PIN_A_LIN);

#if A_TOGGLE_HZ > 0
    /* 4) A 下管以 A_TOGGLE_HZ 翻转；B/C 保持不通 */
    const u32 half = 16000000u / (2u * A_TOGGLE_HZ * 4u);   /* 约 4 周期/次迭代 */
    for (;;) {
        GPIOB_BSRR = (1u << PIN_A_LIN);   /* A_LIN = 1 -> A 下管导通 */
        delay_loops(half);
        GPIOB_BRR  = (1u << PIN_A_LIN);   /* A_LIN = 0 -> A 下管关断 */
        delay_loops(half);
    }
#else
    /* 4') A 下管持续导通（静态高）；B/C 保持不通 */
    GPIOB_BSRR = (1u << PIN_A_LIN);
    for (;;) {
        __asm volatile("nop");
    }
#endif
}

/* ---- 向量表（只需要栈顶 + 复位入口；本测试不用中断） ---- */
extern u32 _estack;
void Reset_Handler(void);

__attribute__((section(".vectors"), used))
const void *const vectors[2] = { (const void *)&_estack, (const void *)Reset_Handler };

void Reset_Handler(void)
{
    SCB_VTOR = 0x08001000u;
    main();
    for (;;) {
        __asm volatile("nop");
    }
}
