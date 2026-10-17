/**
 * @file    bsp_uart_telem.c
 * @brief   电调遥测串口接收实现（USART1 RX / PA10，115200 8N1，中断 + 环形缓冲）
 *
 * 【为什么不走 HAL】
 *   本工程的 CubeMX 配置里没有开 USART 外设，hal_conf.h 也就没打开
 *   HAL_UART_MODULE_ENABLED、CMake 也没编 stm32f1xx_hal_uart.c。
 *   为了【不动 CubeMX 生成的文件】（重新 Generate 会被覆盖），这里直接操作寄存器 ——
 *   与本工程里 esc-fixed-test 那批固件的写法一致。
 *
 * 【时钟前提】SystemClock_Config 把 PCLK2 配成 72 MHz（HSE 8M × 9）。
 *   BRR = 72e6 / 115200 = 625（整除，无误差）⇒ 115200 波特率精确。
 */
#include "bsp_uart_telem.h"
#include "stm32f1xx.h"      /* CMSIS 寄存器定义（USART1/GPIOA/RCC/NVIC） */

#define TELEM_RX_BUF_SIZE   128u    /* 2 的幂，方便取模（这里直接用 % ） */
#define TELEM_BRR           625u    /* 72 MHz / 115200 */

static volatile uint8_t  s_buf[TELEM_RX_BUF_SIZE];
static volatile uint16_t s_head;          /* ISR 写 */
static volatile uint16_t s_tail;          /* 主循环读 */
static volatile uint32_t s_rx_bytes;
static volatile uint32_t s_errs;

void bsp_uart_telem_init(void)
{
    /* ① 时钟：GPIOA + USART1（都在 APB2） */
    RCC->APB2ENR |= RCC_APB2ENR_IOPAEN | RCC_APB2ENR_USART1EN;

    /* ② PA10 配成【浮空输入】（CNF=01, MODE=00 ⇒ 0b0100）
     *    PA10 在 CRH 里，占第 8..11 位（(10-8)*4 = 8） */
    GPIOA->CRH = (GPIOA->CRH & ~(0xFu << 8)) | (0x4u << 8);

    /* ③ 波特率与格式：115200 8N1，只开接收 */
    USART1->BRR = TELEM_BRR;
    USART1->CR2 = 0;                                   /* 1 个停止位 */
    USART1->CR3 = 0;                                   /* 无流控 */
    USART1->CR1 = USART_CR1_UE | USART_CR1_RE | USART_CR1_RXNEIE;

    /* ④ 中断使能（优先级默认，遥测不敏感） */
    NVIC_EnableIRQ(USART1_IRQn);
}

bool bsp_uart_telem_read_byte(uint8_t *out)
{
    if (s_head == s_tail) {
        return false;
    }
    *out = s_buf[s_tail];
    s_tail = (uint16_t)((s_tail + 1u) % TELEM_RX_BUF_SIZE);
    return true;
}

uint32_t bsp_uart_telem_rx_bytes(void) { return s_rx_bytes; }
uint32_t bsp_uart_telem_err_count(void) { return s_errs; }

/**
 * @brief USART1 中断：收到一个字节就丢进环形缓冲
 *
 * 说明：读 SR 再读 DR 会顺带清掉 ORE（溢出）/ FE（帧错）/ NE / PE。
 *   接线不良或波特率不匹配时，这些错误计数会涨 —— 是最快的"线有问题"判据。
 */
void USART1_IRQHandler(void)
{
    uint32_t sr = USART1->SR;

    if (sr & USART_SR_RXNE) {
        uint8_t b = (uint8_t)(USART1->DR & 0xFFu);
        uint16_t next = (uint16_t)((s_head + 1u) % TELEM_RX_BUF_SIZE);

        if (next != s_tail) {           /* 缓冲满了就丢新字节（不覆盖未读数据） */
            s_buf[s_head] = b;
            s_head = next;
        } else {
            s_errs++;                   /* 记一次溢出，便于发现"主循环没及时读" */
        }
        s_rx_bytes++;
    } else if (sr & (USART_SR_ORE | USART_SR_FE | USART_SR_NE | USART_SR_PE)) {
        (void)USART1->DR;               /* 读 DR 清错 */
        s_errs++;
    }
}
