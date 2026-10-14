/**
 * @file    module_kiss.c
 * @brief   KISS 遥测帧解析实现（字节流式，滚动窗口 + CRC + 合理性筛）
 */
#include "module_kiss.h"

/* 合理性闸门：CRC 只有 8 位，随机字节有 1/256 概率"碰巧"通过校验。
 * 电调的设置帧是 49 字节，窗口在它里面滑动时可能误命中，所以再加一道数值范围筛。
 * 范围按本板实际情况定：6S~8S 电池、2.3 A 保险丝、常温 —— 留足余量。 */
#define KISS_TEMP_MIN_C     (-40)
#define KISS_TEMP_MAX_C     (125)
#define KISS_VOLTS_MAX_cV   (6000u)   /* 60.00 V */
#define KISS_CURRENT_MAX_cA (5000u)   /* 50.00 A */

static uint8_t  s_win[KISS_FRAME_LEN];   /* 最近 10 个字节，s_win[9] = 最新 */
static kiss_telem_t s_last;
static bool     s_has_last;
static uint32_t s_ok;
static uint32_t s_bad_value;

uint8_t module_kiss_crc8(const uint8_t *buf, uint8_t len)
{
    uint8_t crc = 0;

    for (uint8_t i = 0; i < len; i++) {
        /* 与 AM32 的 update_crc8(crc_data, crc_seed) 等价：
         *   crc ^= data; 然后 8 次：crc = (crc & 0x80) ? ((crc << 1) ^ 0x07) : (crc << 1); */
        crc ^= buf[i];
        for (uint8_t b = 0; b < 8u; b++) {
            crc = (uint8_t)((crc & 0x80u) ? ((crc << 1) ^ 0x07u) : (crc << 1));
        }
    }
    return crc;
}

static bool decode(const uint8_t *f, kiss_telem_t *out)
{
    int8_t   temp = (int8_t)f[0];
    uint16_t volts = (uint16_t)((f[1] << 8) | f[2]);
    uint16_t cur   = (uint16_t)((f[3] << 8) | f[4]);
    uint16_t cons  = (uint16_t)((f[5] << 8) | f[6]);
    uint16_t erpm  = (uint16_t)((f[7] << 8) | f[8]);

    if (temp < KISS_TEMP_MIN_C || temp > KISS_TEMP_MAX_C)  return false;
    if (volts > KISS_VOLTS_MAX_cV)                         return false;
    if (cur > KISS_CURRENT_MAX_cA)                         return false;

    out->temp_c       = temp;
    out->volts_cV     = volts;
    out->current_cA   = cur;
    out->consumed_mAh = cons;
    out->erpm_x100    = erpm;
    out->crc          = f[9];
    return true;
}

bool module_kiss_push_byte(uint8_t b, kiss_telem_t *out)
{
    /* 滚动窗口 */
    for (uint8_t i = 1; i < KISS_FRAME_LEN; i++) {
        s_win[i - 1] = s_win[i];
    }
    s_win[KISS_FRAME_LEN - 1] = b;

    if (module_kiss_crc8(s_win, KISS_FRAME_LEN - 1u) != s_win[KISS_FRAME_LEN - 1u]) {
        return false;                       /* CRC 不过：绝大多数字节落到这里，正常 */
    }

    kiss_telem_t t;
    if (!decode(s_win, &t)) {
        s_bad_value++;                      /* CRC 过了但数值离谱 ⇒ 误同步，丢弃 */
        return false;
    }

    s_last     = t;
    s_has_last = true;
    s_ok++;

    if (out != 0) {
        *out = t;
    }
    return true;
}

bool module_kiss_last(kiss_telem_t *out)
{
    if (!s_has_last || out == 0) {
        return false;
    }
    *out = s_last;
    return true;
}

void module_kiss_get_stats(uint32_t *ok, uint32_t *bad_value)
{
    if (ok != 0)        { *ok = s_ok; }
    if (bad_value != 0) { *bad_value = s_bad_value; }
}

const uint8_t *module_kiss_window(void)
{
    return s_win;
}
