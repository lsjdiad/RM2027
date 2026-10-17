/**
 * @file    module_kiss.h
 * @brief   KISS 电调遥测协议（纯计算，不碰硬件）
 *
 * 【它是什么】AM32 打开串口遥测后，按 KISS 协议往 USART_TX 上吐的 10 字节帧。
 *   本模块只负责"把字节流变成结构体"，不知道 USART1/PA10 的存在 ⇒ 可在 PC 上单测。
 *
 * 【帧格式】来源：AM32 `Inc/kiss_telemetry.h`（kiss_telem_pkt_t）+ `Src/kiss_telemetry.c`
 *   offset 0     : 温度   int8_t   ℃
 *   offset 1..2  : 电压   uint16   大端，单位 0.01 V（厘伏）
 *   offset 3..4  : 电流   uint16   大端，单位 0.01 A（厘安）
 *   offset 5..6  : 累计耗电 uint16  大端，单位 mAh
 *   offset 7..8  : 电转速 uint16   大端，单位 100 eRPM
 *   offset 9     : CRC8（多项式 0x07，初值 0，对前 9 字节）
 *
 * ⚠️ 单位是"厘"不是"毫"：AM32 的算法是 (mV × 100) / MILLOVLT_PER_AMP ⇒ 结果是厘安。
 *    （见 AM32 `Src/main.c:2173-2175`）
 */
#pragma once
#include <stdint.h>
#include <stdbool.h>

#define KISS_FRAME_LEN   10u

typedef struct {
    int8_t   temp_c;          /* ℃ */
    uint16_t volts_cV;        /* 0.01 V */
    uint16_t current_cA;      /* 0.01 A */
    uint16_t consumed_mAh;    /* mAh */
    uint16_t erpm_x100;       /* 100 eRPM */
    uint8_t  crc;             /* 帧里带的 CRC */
} kiss_telem_t;

/** CRC8：与 AM32 `Src/functions.c` 的 update_crc8 完全一致（poly 0x07，init 0，无反转） */
uint8_t module_kiss_crc8(const uint8_t *buf, uint8_t len);

/**
 * @brief 送入一个收到的字节（字节流式，不需要外部做帧同步）
 * @return true = 就是这一个字节刚好凑成一整帧且校验通过（此时 *out 有效）
 */
bool module_kiss_push_byte(uint8_t b, kiss_telem_t *out);

/** 取最近一次成功解出的帧；返回 false 表示还没收到过 */
bool module_kiss_last(kiss_telem_t *out);

/** 统计：ok = 成功帧数；bad_value = CRC 过了但数值不合理（防止误同步到设置帧里） */
void module_kiss_get_stats(uint32_t *ok, uint32_t *bad_value);

/** 最近收到的 10 个原始字节（帧同步没成功时，用来肉眼判断"到底收到的是什么"） */
const uint8_t *module_kiss_window(void);
