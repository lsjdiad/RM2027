/**
 * @file    app_esc_test.c
 * @brief   电调联调测试任务实现
 *
 * 状态机（时间全部按"时间戳差"算，不用 HAL_Delay，不阻塞）：
 *
 *   0 .. 3s   IDLE      发 DISARM(0)         电调不应有任何动作
 *   3 .. 5s   SELFTEST  发 BEEP1(1)          ★ 电调应"嘀"一声 ⇒ 证明协议/位序/CRC 全对
 *   5s +      RAMP      油门 48 → target     电机开环起转（需 ENABLE_MOTOR=1）
 *             HOLD      保持 target
 *
 * ★ 除了"发"，本任务还负责"收"：
 *     - USART1 RX  ← 电调的 USART_TX（KISS 遥测帧），交给 Module/module_kiss 解析
 *     - ADC1_IN1   ← 电调的电流模拟量（INA240 输出）
 *   两者都只是"读进来放进 g_dbg"，业务上不参与状态迁移 —— 所以链路断了也照常发 DShot。
 */
#include "app_esc_test.h"
#include "app_debug.h"
#include "module_dshot.h"
#include "module_kiss.h"
#include "bsp_dshot_tx.h"
#include "bsp_uart_telem.h"
#include "bsp_current_adc.h"

/* ★ 2026-10-09：本值现在【只管"没有守零油门"时的那条老路】（hold_zero 上电为 0 时）。
 *   台架实验走的是 g_dbg.hold_zero 那条路：hold_zero=1 ⇒ 一直停在 IDLE 发 0，
 *   直到调试器把它写 0，那一下【直接进 RAMP】、根本不经过 T_ARM_MS。
 *   所以这个 15 秒只是留作后备（它曾经是 3 秒，太短、赶不上电调上电/重烧的时机，
 *   会导致"怎么都解锁不了"）。 */
#define T_ARM_MS           15000u  /* 零油门窗口：电调解锁要求油门连续为 0 约 1 秒 */
#define T_SELFTEST_END_MS  0u      /* 自检阶段已取消（它会打断解锁）*/
#define T_RAMP_MS          3000u   /* 斜坡持续 3 秒 */

/* 每多少帧带一次"遥测请求位"。
 *   本任务 1 kHz 发帧；每帧都请求的话，电调会每毫秒回 10 字节 ⇒ 115200 下占用 ~87%，
 *   遥测会互相挤掉。20 帧一次 = 50 Hz，链路占用 ~4%，足够看清趋势。 */
#define TELEM_REQ_EVERY    20u

static uint32_t s_state_start_ms = 0;
static uint32_t s_frame_count    = 0;
static uint8_t  s_hold_zero_prev = 0;   /* 上一拍是否处于"守零油门"（用于认 1→0 的放行沿） */
static kiss_telem_t s_telem;      /* 最近一帧（供调试观察，业务不用） */

static void enter_state(esc_state_t st, uint32_t now_ms)
{
    g_dbg.state          = (uint8_t)st;
    g_dbg.ms_in_state    = 0u;
    s_state_start_ms     = now_ms;
}

void app_esc_test_init(void)
{
    app_debug_init();
    bsp_dshot_tx_init();
    bsp_uart_telem_init();      /* 收电调遥测：USART1 RX / PA10 */
    bsp_current_adc_init();     /* 收电流模拟量：ADC1_IN1 / PA1 */
    enter_state(ESC_STATE_IDLE, 0u);
    g_dbg.throttle_target = APP_ESC_TEST_RAMP_TARGET;
    g_dbg.hold_zero       = APP_ESC_TEST_HOLD_ZERO_DEFAULT;   /* 见 app_esc_test.h */
}

/* 组帧并发出；同时把观测值填好 */
static void send_value(uint16_t value)
{
    bool telem_req = ((++s_frame_count % TELEM_REQ_EVERY) == 0u);
    uint16_t frame = module_dshot_build(value, telem_req);

    if (telem_req) {
        g_dbg.telem_req_sent++;     /* 请求了几次，和 telem_frames_ok 对照着看 */
    }

    g_dbg.throttle_cmd = value;
    g_dbg.frame        = frame;
    g_dbg.crc          = (uint16_t)(frame & 0x000Fu);   /* 直接取帧里的 CRC，避免两处公式不一致 */

    (void)bsp_dshot_tx_send(frame);
}

/* 把"收"这一侧的东西都读一遍（不阻塞、不参与状态迁移） */
static void poll_inputs(void)
{
    uint8_t b;

    while (bsp_uart_telem_read_byte(&b)) {
        (void)module_kiss_push_byte(b, &s_telem);   /* 内部自己统计 ok / bad_value */
    }

    bsp_current_adc_sample();
}

void app_esc_test_task(uint32_t now_ms)
{
    uint32_t t;

    g_dbg.loop_count++;

    poll_inputs();

    /* ---------- 台架"守零油门"：给电调解锁留出确定的窗口 ----------
     *  AM32 电调解锁的充要条件是"油门连续为 0 约 1 秒"（AM32 Src/main.c 的
     *  tenKhzRoutine：armed_timeout_count > LOOP_FREQUENCY_HZ 且 zero_input_count > 30），
     *  而只要有非零油门，armed_timeout_count 每一拍都被清零 ⇒ 永远到不了 1 秒。
     *  本状态机原先只在【自己复位后的前 3 秒】发 0，于是"电调在 F1 之后才复位/重烧"
     *  就必然解锁失败（这正是排查过很久的"怎么都解锁不了"）。
     *  ⇒ 用 g_dbg.hold_zero 把这个窗口变成可控的：写 1 立刻回到发 0 并一直保持；
     *    写 0 的那一刻直接进斜坡（守卫期间电调已经解锁）。 */
    if (g_dbg.hold_zero) {
        s_hold_zero_prev = 1;
        enter_state(ESC_STATE_IDLE, now_ms);   /* 每拍重置计时 ⇒ 一直停在 IDLE 发 0 */
        send_value(DSHOT_VALUE_DISARM);
        app_debug_update(now_ms);
        return;
    }
    if (s_hold_zero_prev) {
        s_hold_zero_prev = 0;
        enter_state(ESC_STATE_RAMP, now_ms);   /* 放行后直接爬坡，不必再等 3 秒 */
    }

    t = now_ms - s_state_start_ms;
    g_dbg.ms_in_state = t;

    switch ((esc_state_t)g_dbg.state) {

    /* ---------- 阶段 1：上锁 ---------- */
    case ESC_STATE_IDLE:
        send_value(DSHOT_VALUE_DISARM);

        if (t >= T_ARM_MS) {
            enter_state(ESC_STATE_SELFTEST, now_ms);
        }
        break;

    /* ---------- 阶段 2：自检（已取消，保留分支以免状态机缺格）---------- */
    case ESC_STATE_SELFTEST:
        /* ⚠️ 原设计在这里发 BEEP1(1)。但 AM32 的解锁要求【油门持续为 0】，
           中间插一个"1"会把解锁流程打断 ⇒ 电调永远不解锁（不亮绿灯）。
           所以这段不再发送 BEEP，直接过渡到爬坡。 */
#if APP_ESC_TEST_ENABLE_MOTOR
        enter_state(ESC_STATE_RAMP, now_ms);
#else
        send_value((uint16_t)DSHOT_CMD_BEEP1);     /* 不转电机时才发 beep 做协议自检 */
        if (t >= 2000u) enter_state(ESC_STATE_IDLE, now_ms);
#endif
        break;

    /* ---------- 阶段 3：油门斜坡 ---------- */
    case ESC_STATE_RAMP: {
        uint32_t span = (uint32_t)g_dbg.throttle_target - DSHOT_VALUE_MIN;
        uint16_t v    = (uint16_t)(DSHOT_VALUE_MIN + (span * t) / T_RAMP_MS);

        if (v >= g_dbg.throttle_target) {
            v = g_dbg.throttle_target;
        }
        send_value(v);

        if (t >= T_RAMP_MS) {
            enter_state(ESC_STATE_HOLD, now_ms);
        }
        break;
    }

    /* ---------- 阶段 4：保持 ---------- */
    case ESC_STATE_HOLD:
        send_value(g_dbg.throttle_target);
        break;

    default:
        send_value(DSHOT_VALUE_DISARM);
        break;
    }

    app_debug_update(now_ms);
}
