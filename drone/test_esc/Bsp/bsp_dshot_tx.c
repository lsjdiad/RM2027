/**
 * @file    bsp_dshot_tx.c
 * @brief   DShot 波形发生器实现
 *
 * 原理：用 TIM3 的一个 PWM 通道，把【比较寄存器 CCR1】的值按位逐个改掉，
 *       每个值对应一个 DShot 位的占空比。DMA 负责"逐个改"这件事。
 *
 *   DShot300 @ TIM3 = 72 MHz：
 *     1 tick          = 13.89 ns
 *     位周期 ARR+1    = 240 tick = 3.333 µs
 *     '1' = 高 75%    = 180 tick
 *     '0' = 高 37.5%  =  90 tick
 *   帧长 16 bit = 53.3 µs
 */
#include "bsp_dshot_tx.h"
#include "tim.h"        /* htim3 */
#include "dma.h"

/* ⚠️ CubeMX 把 hdma_tim3_ch4_up 定义在 Core/Src/tim.c:28，但【没有】在头文件里 extern
 *    （Core/Src/stm32f1xx_it.c:58 也是自己局部 extern 的）—— 这里照同样做法，
 *    免得改 CubeMX 生成的头（重新 Generate 会被覆盖）。 */
extern DMA_HandleTypeDef hdma_tim3_ch4_up;

#define DSHOT_BIT_LEN    16u
#define DSHOT_CCR_ONE   180u   /* 75.0%  of 240 */
#define DSHOT_CCR_ZERO   90u   /* 37.5%  of 240 */

/* ★ 帧首补 1 个空闲值（0）：
 *   定时器自由运行，DMA 被武装的那一刻落在周期内的【任意相位】。
 *   第 1 次搬运因此会落在一个残缺的周期里（上机实测：该位只有 ~450ns，
 *   而完整位周期是 3333ns）⇒ 那个位既不像 '0' 也不像 '1'，会被接收端数漏。
 *
 *   在缓冲区前面补一个 0 之后：
 *     第 1 次搬运 → 写 0   ⇒ 那个残缺周期是【低电平】，无害
 *     第 2 次搬运起（正常 UPDATE 边界）→ bit15、bit14 … bit0，都是完整周期
 *   ⇒ 16 个位全部落在完整周期里。
 */
#define DSHOT_LEAD_LEN    1u
#define DSHOT_DMA_LEN   (DSHOT_LEAD_LEN + DSHOT_BIT_LEN)   /* 17 */

static uint16_t s_ccr[DSHOT_DMA_LEN];
static volatile bool s_busy = false;
static uint32_t s_sent = 0;
static uint32_t s_drop = 0;

/* DMA 传输完成 → 这一帧发完了 */
static void dshot_tx_dma_done(DMA_HandleTypeDef *hdma)
{
    (void)hdma;

    /* ★★ 关键：发完立刻把比较值清 0 ⇒ 信号线回到【空闲低电平】。
     *
     * 为什么必须做：
     *   定时器是自由运行的，16 个值发完后 DMA 停止，
     *   CCR1 会【停留在最后一个位的值】。若最后一位是 '1'（CCR=180=75%），
     *   则两帧之间的 1ms 会变成 75% 占空比的连续方波 ——
     *   上机实测现象："目之所及都是高电平"。
     *
     *   后果：DShot 的帧同步依赖【帧之间的低电平空隙】，
     *         没有空隙 ⇒ 电调数满 32 个边沿时会跨帧 ⇒ 位全部错位 ⇒ 解不出帧。
     *
     *   清 0 后：CCR1=0 ⇒ 输出恒低 ⇒ 帧间是干净的低电平 ⇒ 帧边界清晰。
     *   （预装载已在 init 里关掉，所以这里写 CCR1 立即生效。）
     */
    TIM3->CCR1 = 0;

    s_busy = false;
}

bool bsp_dshot_tx_init(void)
{
    /* ★ 关键一步：DMA 的目标地址 = CH1 的比较寄存器。
     *   CubeMX 只配了"方向/宽度/模式/NVIC"，【不会】设外设地址 —— 必须在这里手设。
     */
    hdma_tim3_ch4_up.Instance->CPAR = (uint32_t)&TIM3->CCR1;

    /* 传输完成回调（用 DMA 自己的回调，不依赖 PWM-DMA 的转发链） */
    hdma_tim3_ch4_up.XferCpltCallback = dshot_tx_dma_done;

    /* ★ 触发源 = 更新事件（每周期一次），不是 CC1/CC4 比较匹配 */
    __HAL_TIM_ENABLE_DMA(&htim3, TIM_DMA_UPDATE);

    if (HAL_TIM_PWM_Start(&htim3, TIM_CHANNEL_1) != HAL_OK) {
        return false;
    }

    /* ★ 关掉 CH1 的【预装载】(CCMR1.OC1PE)。
     *
     * CubeMX 的 HAL_TIM_PWM_ConfigChannel 会置 OC1PE=1，含义是：
     *   写 CCR1 只写进影子寄存器，要等【下一个 UPDATE 事件】才搬进活性寄存器。
     * 而我们的 DMA 正是在 UPDATE 事件上写 CCR1
     *   ⇒ 每个值都推迟一个周期才生效 ⇒ 整帧错开一位。
     *
     * 上机实测（示波器）：帧长 50.0us = 15 位，而正确应为 16 位 × 3.333us = 53.3us。
     * 关掉后 UPDATE #1 写的值本周期立即生效 ⇒ 正好 16 位。
     *
     * 旁证：AM32 操作同一外设时写 CCMR1 = 0x60（OC1PE = 0）。
     */
    TIM3->CCMR1 &= ~TIM_CCMR1_OC1PE;

    return true;
}

bool bsp_dshot_tx_send(uint16_t frame)
{
    if (s_busy) {
        s_drop++;          /* 上一帧还没发完 —— 丢帧，不阻塞调用者 */
        return false;
    }

    /* 帧首那个空闲值：吸收 DMA 起始相位的不确定 */
    s_ccr[0] = 0;

    /* MSB 先发（从 DSHOT_LEAD_LEN 开始放 16 个位） */
    for (uint32_t i = 0; i < DSHOT_BIT_LEN; i++) {
        s_ccr[DSHOT_LEAD_LEN + i] =
            ((frame >> (15u - i)) & 1u) ? DSHOT_CCR_ONE : DSHOT_CCR_ZERO;
    }

    s_busy = true;

    if (HAL_DMA_Start_IT(&hdma_tim3_ch4_up,
                         (uint32_t)s_ccr,
                         (uint32_t)&TIM3->CCR1,
                         DSHOT_DMA_LEN) != HAL_OK) {
        s_busy = false;
        return false;
    }

    s_sent++;
    return true;
}

bool bsp_dshot_tx_is_busy(void)        { return s_busy; }
void bsp_dshot_tx_abort(void)          { HAL_DMA_Abort_IT(&hdma_tim3_ch4_up); s_busy = false; }
const uint16_t *bsp_dshot_tx_ccr_buffer(void) { return &s_ccr[DSHOT_LEAD_LEN]; } /* 跳过帧首空闲值 */
uint32_t bsp_dshot_tx_sent_count(void) { return s_sent; }
uint32_t bsp_dshot_tx_busy_drop(void)  { return s_drop; }
