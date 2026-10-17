/*
 * test_3low.c —— 三相下管"同代码路径"对照测试固件（完全脱离 AM32）
 *
 * 目的：把 A(PB15) / B(PB0) / C(PA7) 三路下管用【完全相同的方式】驱动，
 *       这样硬件上直接对比，就能分清 "PB15 引脚坏" 还是 "代码问题"。
 *
 * 输出（三个上管始终全关，避免直通）：
 *   MODE = 1 : PB15 / PB0 / PA7 三路【同时】以约 1kHz 翻转 —— 示波器对比用
 *   MODE = 0 : PB15 / PB0 / PA7 三路【常通】(静态高)  —— 万用表 / 上拉测试用
 *
 * 引脚与板上网络：
 *   PB15 = A_LIN -> U2 pin1(LIN1) -> U2 pin11(LO1) -> R23 -> Q2 栅极
 *   PB0  = B_LIN -> U2 pin2(LIN2) -> U2 pin10(LO2) -> R25 -> Q4 栅极
 *   PA7  = C_LIN -> U2 pin3(LIN3) -> U2 pin9 (LO3) -> R30 -> Q6 栅极
 *   PA8/PA9/PA10 = C_HIN/B_HIN/A_HIN ，全部拉低
 *
 * 无看门狗、无定时器、无状态机、不读 EEPROM —— 状态恒定，不会自己复位。
 * 烧录地址 0x08001000（AM32 的 app 槽）。测完用 restore_am32.sh 还原。
 *
 * 寄存器偏移来源：Mcu/g071/.../stm32g071xx.h
 *   RCC_IOPENR = 0x40021034 (bit0=GPIOA bit1=GPIOB)
 *   GPIOA_BASE = 0x50000000, GPIOB_BASE = 0x50000400
 *   MODER=0x00 IDR=0x10 ODR=0x14 BSRR=0x18 BRR=0x28
 */

typedef unsigned int u32;

#ifndef MODE
#define MODE 1          /* 1 = 三路同步翻转; 0 = 三路常通 */
#endif

/* 固件被烧到哪里就填哪里：
 *   0x08000000 = 整片起始（新芯片没有 bootloader 时用这个，复位即运行）
 *   0x08001000 = AM32 的 app 槽（保留 bootloader 时用这个） */
#ifndef APP_BASE
#define APP_BASE 0x08001000u
#endif

#define RCC_IOPENR  (*(volatile u32 *)0x40021034u)
#define RCC_APBENR2 (*(volatile u32 *)0x40021040u)
#define SYSCFG_CFGR1 (*(volatile u32 *)0x40010000u)
#define GPIOA_MODER (*(volatile u32 *)0x50000000u)
#define GPIOA_BSRR  (*(volatile u32 *)0x50000018u)
#define GPIOA_BRR   (*(volatile u32 *)0x50000028u)
#define GPIOB_MODER (*(volatile u32 *)0x50000400u)
#define GPIOB_BSRR  (*(volatile u32 *)0x50000418u)
#define GPIOB_BRR   (*(volatile u32 *)0x50000428u)
#define SCB_VTOR    (*(volatile u32 *)0xE000ED08u)

#define A_LIN 1u    /* ★ PB1 -> LIN1（原理图第15脚，符号误标成 PB15） */
#define B_LIN  0u   /* PB0  -> LIN2 */
#define C_LIN  7u   /* PA7  -> LIN3 */
#define A_HIN 10u   /* PA10 -> HIN1 */
#define B_HIN  9u   /* PA9  -> HIN2 */
#define C_HIN  8u   /* PA8  -> HIN3 */

#define A_LIN_M (1u << A_LIN)
#define B_LIN_M (1u << B_LIN)
#define C_LIN_M (1u << C_LIN)

static void delay_loops(u32 n)
{
    volatile u32 i;
    for (i = 0; i < n; i++) {
        __asm volatile("nop");
    }
}

int main(void)
{
    /* ★ 关键：关掉 PB15 / PA8 的 UCPD 死电池下拉
     *   数据手册 DS12232 注释(4)：复位后 PA8 / PB15（= UCPD1_CC1 / CC2）
     *   可能带一个下拉电阻，必须 strobe SYSCFG_CFGR1 的 UCPD1_STROBE 才关得掉。
     *   AM32 从来没有做这一步。 */
    RCC_APBENR2 |= (1u << 0);          /* SYSCFGEN 时钟 */
    SYSCFG_CFGR1 |= (1u << 9);         /* UCPD1_STROBE (bit9) */

    /* 打开 GPIOA / GPIOB 时钟 */
    RCC_IOPENR |= (1u << 0) | (1u << 1);

    /* GPIOA: PA7 / PA8 / PA9 / PA10 配成输出 */
    GPIOA_MODER = (GPIOA_MODER
                   & ~((3u << (2u * A_HIN)) | (3u << (2u * B_HIN))
                     | (3u << (2u * C_HIN)) | (3u << (2u * C_LIN))))
                | (1u << (2u * A_HIN)) | (1u << (2u * B_HIN))
                | (1u << (2u * C_HIN)) | (1u << (2u * C_LIN));

    /* GPIOB: PB0 / PB15 配成输出 */
    GPIOB_MODER = (GPIOB_MODER & ~((3u << (2u * A_LIN)) | (3u << (2u * B_LIN))))
                | (1u << (2u * A_LIN)) | (1u << (2u * B_LIN));

    /* 三个上管先全部关掉 */
    GPIOA_BRR = (1u << A_HIN) | (1u << B_HIN) | (1u << C_HIN);

#if MODE == 0
    /* 三路下管常通（静态高） */
    GPIOA_BSRR = C_LIN_M;                 /* PA7  */
    GPIOB_BSRR = A_LIN_M | B_LIN_M;   /* PB15 + PB2 + PB0 */
    for (;;) {
        __asm volatile("nop");
    }
#else
    /* 三路下管同时以约 1kHz 翻转 */
    for (;;) {
        GPIOA_BSRR = C_LIN_M;
        GPIOB_BSRR = A_LIN_M | B_LIN_M;
        delay_loops(2000);                /* 半周期 ~500us @16MHz */

        GPIOA_BRR = C_LIN_M;
        GPIOB_BRR = A_LIN_M | B_LIN_M;
        delay_loops(2000);
    }
#endif
}

/* 向量表：只需要栈顶 + 复位入口 */
extern u32 _estack;
void Reset_Handler(void);

__attribute__((section(".vectors"), used))
const void *const vectors[2] = { (const void *)&_estack, (const void *)Reset_Handler };

void Reset_Handler(void)
{
    SCB_VTOR = APP_BASE;
    main();
    for (;;) {
        __asm volatile("nop");
    }
}
