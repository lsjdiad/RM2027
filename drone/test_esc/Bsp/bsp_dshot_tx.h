/**
 * @file    bsp_dshot_tx.h
 * @brief   DShot 波形发生器（TIM3_CH1 + DMA1_Ch3/TIM3_UP）
 *
 * 【分层职责】本层只懂"波形"：一个 16 位帧 → PA6 上的 DShot 位流。
 *   它【不了解】油门、CRC、协议语义 —— 那些在 Module 层。
 *   对外接口只收"帧"，不收"油门"。
 */
#pragma once
#include <stdint.h>
#include <stdbool.h>

/** 初始化（含：给 DMA 设外设地址、启动 PWM）。返回 true 表示就绪 */
bool bsp_dshot_tx_init(void);

/** 发一帧。忙则返回 false（不阻塞、不等待） */
bool bsp_dshot_tx_send(uint16_t frame);

bool bsp_dshot_tx_is_busy(void);
void bsp_dshot_tx_abort(void);

/* ---- 以下仅供观测（Ozone / OpenOCD 看） ---- */
const uint16_t *bsp_dshot_tx_ccr_buffer(void);   /**< 16 个 CCR 值（180/90） */
uint32_t bsp_dshot_tx_sent_count(void);          /**< 累计成功发出的帧数 */
uint32_t bsp_dshot_tx_busy_drop(void);           /**< 因忙而丢帧的次数 */
