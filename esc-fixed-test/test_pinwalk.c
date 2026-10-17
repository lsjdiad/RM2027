/*
 * test_pinwalk.c —— 六路门极"单脚走查"固件（完全脱离 AM32）
 *
 * 目的：一次烧写，把 9 个候选引脚【轮流】【每次只驱动一个】输出约 2 Hz 方波。
 *       拿示波器/万用表在 FD6288Q 的 LIN1/LIN2/LIN3 + HIN1/HIN2/HIN3
 *       （或直接在 MCU 焊盘上）看：哪一个槽位动、哪一路跟着动，
 *       就能把"寄存器位 ↔ 门极网络"全部对上号。
 *
 * 为什么需要它：原理图符号把 28 脚封装的两个变体（GP / N）的引脚名混着标了，
 *   第 15 脚在 GP 变体上是 PB1、在 N 变体上是 PB15；第 14 脚（B_LIN）只有 GP 变体才有。
 *   照符号上的名字写固件，就会有两个脚"怎么调都不动"。走查一遍即可定案。
 *
 * ⚠️ 安全性：任何时刻【只有一个】候选脚为高，其余全部拉低
 *   ⇒ 同一相的 HIN 与 LIN 不可能同时为高 ⇒ 不可能发生上下管直通。
 *   （但确认完六路之前不要上电机：见 README 的测量顺序。）
 *
 * 槽位顺序（固定，从 0 开始数）：
 *   0: PA7   (pin13, 板上 C_LIN → U2 LIN3)
 *   1: PB0   (pin14, 板上 B_LIN → U2 LIN2)   ← 只有 GP 变体有这个脚
 *   2: PB1   (pin15 候选①, GP 变体名 → U2 LIN1)
 *   3: PB15  (pin15 候选②, N 变体名  → U2 LIN1)
 *   4: PA8   (pin16, 板上 C_HIN → U2 HIN3)
 *   5: PA9   (pin18 候选①, 先置 PA11_RMP=1)
 *   6: PA11  (pin18 候选②, 不置重映射)
 *   7: PA10  (pin19 候选①, 先置 PA12_RMP=1)
 *   8: PA12  (pin19 候选②, 不置重映射)
 *
 * 每个槽位：先 1 秒全低（分界标记），再用 2 Hz 翻转 4 秒，然后进下一槽，循环。
 *
 * 编译：
 *   ./build_pinwalk.sh            → 顺序走查版
 *   PIN_HOLD=n ./build_pinwalk.sh → 只驱动第 n 号候选脚（反复翻转），其余全低
 *
 * 寄存器偏移来源：AM32-rm2027/Mcu/g071/Drivers/CMSIS/Device/ST/STM32G0xx/Include/stm32g071xx.h
 *   RCC_IOPENR   = 0x40021034 (bit0=GPIOA bit1=GPIOB)
 *   RCC_APBENR2  = 0x40021040 (bit0=SYSCFGEN)
 *   SYSCFG_CFGR1 = 0x40010000 (bit3=PA11_RMP bit4=PA12_RMP bit9=UCPD1_STROBE)
 *   GPIOA=0x50000000 / GPIOB=0x50000400，偏移 MODER=0x00 BSRR=0x18 BRR=0x28
 */

typedef unsigned int u32;

#ifndef APP_BASE
#define APP_BASE 0x08001000u        /* AM32 的 app 槽 */
#endif

#define RCC_IOPENR   (*(volatile u32 *)0x40021034u)
#define RCC_APBENR2  (*(volatile u32 *)0x40021040u)
#define SYSCFG_CFGR1 (*(volatile u32 *)0x40010000u)
#define GPIOA_MODER  (*(volatile u32 *)0x50000000u)
#define GPIOA_BSRR   (*(volatile u32 *)0x50000018u)
#define GPIOA_BRR    (*(volatile u32 *)0x50000028u)
#define GPIOB_MODER  (*(volatile u32 *)0x50000400u)
#define GPIOB_BSRR   (*(volatile u32 *)0x50000418u)
#define GPIOB_BRR    (*(volatile u32 *)0x50000428u)
#define SCB_VTOR     (*(volatile u32 *)0xE000ED08u)

#define PA11_RMP_BIT 0x00000008u    /* SYSCFG_CFGR1 bit3 */
#define PA12_RMP_BIT 0x00000010u    /* SYSCFG_CFGR1 bit4 */
#define UCPD1_STROBE 0x00000200u    /* SYSCFG_CFGR1 bit9 */

/* 时间参数
 * delay_loops 的每次空转 ≈ 11 个周期（-O1 下内层循环 7 条指令 + 取指开销）
 * ⇒ 16 MHz HSI 下 ≈ 0.69 µs/次 ⇒ 1 ms ≈ 1450 次。
 * （注意：test_3low.c 里"delay_loops(2000) ≈ 500 µs / 1 kHz"的注释偏乐观，
 *   按同一份反汇编算是 ≈ 1.4 ms / 约 360 Hz。这里的常数按实际算过。）
 * 这个走查测试对时间的精度不敏感，差一两倍不影响判读。 */
#define LOOPS_PER_MS 1450u
#define GAP_MS       1000u          /* 换槽前的全低分界 */
#define DRIVE_MS     4000u          /* 每个候选脚驱动 4 秒 */
#define HALF_MS      250u           /* 2 Hz：高 250 ms / 低 250 ms */

#define N_CAND 9
/* 端口：0 = GPIOA，1 = GPIOB */
static const u32 cand_port[N_CAND] = { 0, 1, 1, 1,   0, 0, 0,  0,  0 };
static const u32 cand_bit [N_CAND] = { 7, 0, 1, 15,  8, 9, 11, 10, 12 };
static const u32 cand_rmp [N_CAND] = { 0, 0, 0, 0,   0,
                                       PA11_RMP_BIT, 0, PA12_RMP_BIT, 0 };

static void delay_loops(u32 n)
{
    volatile u32 i;
    for (i = 0; i < n; i++) {
        __asm volatile("nop");
    }
}

static void delay_ms(u32 ms)
{
    while (ms--) {
        delay_loops(LOOPS_PER_MS);
    }
}

/* 把候选表里所有脚都配成推挽输出，并全部拉低 */
static void all_candidates_low(void)
{
    u32 m;

    /* GPIOA: PA7 PA8 PA9 PA10 PA11 PA12 */
    m = GPIOA_MODER;
    m &= ~((3u << (2u * 7)) | (3u << (2u * 8)) | (3u << (2u * 9))
           | (3u << (2u * 10)) | (3u << (2u * 11)) | (3u << (2u * 12)));
    m |= (1u << (2u * 7)) | (1u << (2u * 8)) | (1u << (2u * 9))
         | (1u << (2u * 10)) | (1u << (2u * 11)) | (1u << (2u * 12));
    GPIOA_MODER = m;

    /* GPIOB: PB0 PB1 PB15 */
    m = GPIOB_MODER;
    m &= ~((3u << (2u * 0)) | (3u << (2u * 1)) | (3u << (2u * 15)));
    m |= (1u << (2u * 0)) | (1u << (2u * 1)) | (1u << (2u * 15));
    GPIOB_MODER = m;

    /* 全部拉低：注意 PA13/PA14(SWD) 不在候选表里，绝不动它们 */
    GPIOA_BRR = (1u << 7) | (1u << 8) | (1u << 9) | (1u << 10) | (1u << 11) | (1u << 12);
    GPIOB_BRR = (1u << 0) | (1u << 1) | (1u << 15);
}

static void set_rmp(u32 bits)
{
    SYSCFG_CFGR1 = (SYSCFG_CFGR1 & ~(PA11_RMP_BIT | PA12_RMP_BIT)) | bits;
}

static void drive_slot(u32 idx)
{
    set_rmp(cand_rmp[idx]);                     /* 先定下这个脚是 PA9 还是 PA11 */

    delay_ms(GAP_MS);                           /* 分界：全低 1 秒 */

    {
        u32 on = 1u << cand_bit[idx];
        u32 t  = DRIVE_MS / (2u * HALF_MS);     /* 翻转多少个整周期 */
        while (t--) {
            if (cand_port[idx] == 0) { GPIOA_BSRR = on; } else { GPIOB_BSRR = on; }
            delay_ms(HALF_MS);
            if (cand_port[idx] == 0) { GPIOA_BRR  = on; } else { GPIOB_BRR  = on; }
            delay_ms(HALF_MS);
        }
    }

    /* 离开这个槽位：拉低 + 清重映射，保证下一槽干净 */
    all_candidates_low();
    set_rmp(0);
}

int main(void)
{
    /* ★ 关掉 PA8 / PB15 的 UCPD 死电池下拉（数据手册 DS12232 注释(4)）：
     *   复位后这些脚可能带一个下拉电阻，必须给 SYSCFG_CFGR1.UCPD1_STROBE 一个脉冲。
     *   AM32 从来没做这一步 —— 这会让 PB15 看起来"驱动不了"。 */
    RCC_APBENR2 |= 1u;                          /* SYSCFGEN */
    SYSCFG_CFGR1 |= UCPD1_STROBE;
    { volatile u32 w; for (w = 0; w < 2000u; w++) { __asm volatile("nop"); } }
    SYSCFG_CFGR1 &= ~UCPD1_STROBE;

    RCC_IOPENR |= 1u | 2u;                      /* GPIOA + GPIOB 时钟 */

    all_candidates_low();

#ifdef PIN_HOLD
    /* 只驱动第 PIN_HOLD 号候选脚，2 Hz 翻转，其余全低 —— 给万用表用 */
    for (;;) {
        drive_slot(PIN_HOLD);
    }
#else
    for (;;) {
        u32 i;
        for (i = 0; i < N_CAND; i++) {
            drive_slot(i);
        }
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
