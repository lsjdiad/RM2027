/**
 * @file    app_debug.c
 */
#include "app_debug.h"
#include "bsp_dshot_tx.h"
#include "bsp_uart_telem.h"
#include "bsp_current_adc.h"
#include "module_kiss.h"
#include <string.h>

volatile app_debug_t g_dbg;

void app_debug_init(void)
{
    memset((void *)&g_dbg, 0, sizeof(g_dbg));
}

void app_debug_update(uint32_t now_ms)
{
    const uint16_t *ccr = bsp_dshot_tx_ccr_buffer();
    const uint8_t  *win = module_kiss_window();
    kiss_telem_t    t;

    g_dbg.now_ms  = now_ms;
    g_dbg.tx_sent = bsp_dshot_tx_sent_count();
    g_dbg.tx_drop = bsp_dshot_tx_busy_drop();
    g_dbg.tx_busy = bsp_dshot_tx_is_busy() ? 1u : 0u;

    for (uint32_t i = 0; i < 16u; i++) {
        g_dbg.ccr_buf[i] = ccr[i];       /* 波形对不对，看这 16 个数 */
    }

    /* ---- 遥测接收链路 ---- */
    {
        uint32_t ok = 0, bad = 0;
        module_kiss_get_stats(&ok, &bad);
        g_dbg.telem_frames_ok = ok;
        g_dbg.telem_bad_value = bad;
    }
    g_dbg.telem_rx_bytes  = bsp_uart_telem_rx_bytes();
    g_dbg.telem_err_count = bsp_uart_telem_err_count();

    for (uint32_t i = 0; i < KISS_FRAME_LEN; i++) {
        g_dbg.telem_frame[i] = win[i];   /* 帧同步不上时，看一眼原始字节 */
    }

    if (module_kiss_last(&t)) {
        g_dbg.telem_temp_c       = t.temp_c;
        g_dbg.telem_volts_cV     = t.volts_cV;
        g_dbg.telem_current_cA   = t.current_cA;
        g_dbg.telem_consumed_mAh = t.consumed_mAh;
        g_dbg.telem_erpm_x100    = t.erpm_x100;
    }

    /* ---- 电流模拟量 ---- */
    g_dbg.adc_raw         = bsp_current_adc_raw();
    g_dbg.adc_mv          = bsp_current_adc_mv();
    g_dbg.adc_current_cA  = bsp_current_adc_centiamps();
    g_dbg.adc_samples     = bsp_current_adc_samples();
}
