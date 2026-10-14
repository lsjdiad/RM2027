/**
 * @file    bsp_uart_telem.h
 * @brief   电调遥测串口【只收】：USART1 RX，115200 8N1
 *
 * 【为什么需要它】
 *   电调（AM32）的 USART_TX 会按 KISS 协议往外吐遥测帧（温度/电压/电流/转速）。
 *   这块 F1 测试台的职责是"冒充飞控"，所以必须**能收**这条线，
 *   否则只能看见自己发了什么、看不见电调回了什么。
 *
 * 【方向】电调 TX → F1 RX，单向。F1 不需要往电调发串口（命令都走 DShot）。
 *
 * 【引脚】★ 默认 PA10 = USART1_RX（USART1 默认映射，不需要 AFIO 重映射）
 *   要换脚：改 TELEM_UART_RX_PIN，并同时改 .c 里 CRL/CRH 的配置位与 USART 选择。
 *   对应电调板 U6 座子的【第 2 脚 USART_TX】。
 */
#pragma once
#include <stdint.h>
#include <stdbool.h>

/* 接收引脚（当前 = PA10；电平 3.3V，与电调同域） */
#define TELEM_UART_RX_PORT   GPIOA
#define TELEM_UART_RX_PIN    10u

/** 初始化：开时钟、配 PA10 为浮空输入、USART1 115200 8N1、开 RXNE 中断 */
void bsp_uart_telem_init(void);

/** 从环形缓冲取一个收到的字节；返回 false 表示缓冲空 */
bool bsp_uart_telem_read_byte(uint8_t *out);

/** 累计收到的字节数（用于判断"线到底接没接上"） */
uint32_t bsp_uart_telem_rx_bytes(void);

/** 累计溢出/错误计数（帧错误、溢出等，接线不良时会涨） */
uint32_t bsp_uart_telem_err_count(void);
