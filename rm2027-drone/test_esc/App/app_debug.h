/**
 * @file    app_debug.h
 * @brief   【观测黑匣子】给 Ozone / OpenOCD 看的全局变量集合
 *
 * 为什么要单独一层：
 *   调试时最怕"看不到内部状态"。把关键量集中放在一个结构体里，
 *   在 Ozone 里敲一个 g_dbg 就能看到全部，不用满地找变量。
 *
 * ⚠️ 全部 volatile：防止 -O2 下被优化掉（Ozone 就看不到了）。
 */
#pragma once
#include <stdint.h>

typedef enum {
    ESC_STATE_IDLE = 0,      /* 只发 disarm */
    ESC_STATE_SELFTEST,      /* 发 beep，验证协议 */
    ESC_STATE_RAMP,          /* 油门斜坡爬升 */
    ESC_STATE_HOLD,          /* 保持 */
    ESC_STATE_FAULT,         /* 出错 */
} esc_state_t;

typedef struct {
    /* ---- 调度 ---- */
    volatile uint32_t loop_count;        /* task 被调了几次 */
    volatile uint32_t now_ms;            /* 当前时间戳 */
    volatile uint32_t ms_in_state;       /* 在本状态待了多久 */

    /* ---- 状态机 ---- */
    volatile uint8_t  state;             /* esc_state_t */
    volatile uint16_t throttle_cmd;      /* 当前想发的油门/命令值 0..2047 */

    /* ---- 协议 ---- */
    volatile uint16_t frame;             /* 实际发出去的 16 位帧 */
    volatile uint16_t crc;               /* 算出来的 CRC-4 */

    /* ---- 波形 ---- */
    volatile uint16_t ccr_buf[16];       /* ★ 每个 bit 的 CCR 值（应为 180/90） */
    volatile uint32_t tx_sent;           /* 成功发出的帧数 */
    volatile uint32_t tx_drop;           /* 因忙丢帧数 */
    volatile uint8_t  tx_busy;           /* 当前是否在发 */

    /* ---- 遥测接收（电调 → F1，KISS 10 字节帧 / USART1 RX） ----
     * 判线三连：telem_rx_bytes 完全不涨 ⇒ 线没接上/接错脚；
     *           在涨但 telem_frames_ok 不涨 ⇒ 接了但内容不对（波特率/极性/没共地）；
     *           两者都涨 ⇒ 链路通了。 */
    volatile uint32_t telem_req_sent;     /* 我们发出去"带遥测请求位"的帧数 */
    volatile uint32_t telem_rx_bytes;     /* 收到的原始字节数 */
    volatile uint32_t telem_frames_ok;    /* CRC 通过且数值合理的帧数 */
    volatile uint32_t telem_bad_value;    /* CRC 过了但数值离谱（防误同步设置帧） */
    volatile uint32_t telem_err_count;    /* 串口错误（帧错/溢出）——接线不良时会涨 */

    volatile int8_t   telem_temp_c;       /* ℃ */
    volatile uint16_t telem_volts_cV;     /* 0.01 V */
    volatile uint16_t telem_current_cA;   /* 0.01 A */
    volatile uint16_t telem_consumed_mAh; /* mAh */
    volatile uint16_t telem_erpm_x100;    /* 100 eRPM */
    volatile uint8_t  telem_frame[10];    /* 最近收到的 10 个原始字节（肉眼判帧用） */

    /* ---- 电流模拟量（ADC1_IN1 / PA1） ----
     * 与上面 telem_current_cA 是同一颗 INA240 的两条不同路径，应当一致：
     * 对不上 ⇒ 要么 ADC 换算（分压/增益）错，要么遥测帧解析错。 */
    volatile uint16_t adc_raw;            /* 8 次平均后的 12 位原始值 */
    volatile uint16_t adc_mv;             /* 引脚电压 mV */
    volatile int32_t  adc_current_cA;     /* 电流 0.01 A */
    volatile uint32_t adc_samples;        /* 累计采样次数 */

    /* ---- 预留：以后接串口/遥控时用 ---- */
    volatile uint8_t  armed;
    volatile uint16_t throttle_target;

    /* ---- 台架控制位（可写）：非 0 = 强制"上锁/零油门"并守在那里 ----
     *   为什么需要它：AM32 电调解锁的充要条件是"油门连续为 0 约 1 秒"
     *   （AM32 `Src/main.c` 的 tenKhzRoutine：armed_timeout_count > LOOP_FREQUENCY_HZ
     *   且 zero_input_count > 30）。而本状态机只在【自己复位后的前 3 秒】发 0。
     *   一旦电调是在"已经在收油门"之后才复位/重烧（每次改电调固件都会发生），
     *   它就永远等不到那段零油门 ⇒ 永远不解锁（现象：电调侧 armed=0、running=0，
     *   但 newinput 明明收到了正确油门）。
     *   用法：写 1 → 本机立刻回到"发 DISARM(0)"并一直保持；写 0 → 立刻从斜坡起点给油。
     *   上电默认值见 App/app_esc_test.h 的 APP_ESC_TEST_HOLD_ZERO_DEFAULT。 */
    volatile uint8_t  hold_zero;
} app_debug_t;

extern volatile app_debug_t g_dbg;

void app_debug_init(void);
void app_debug_update(uint32_t now_ms);
