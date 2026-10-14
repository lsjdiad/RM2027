/**
 * @file    module_dshot.h
 * @brief   DShot 协议层（纯计算，不碰任何硬件寄存器）
 *
 * 【分层职责】把"油门/命令"变成"16 位帧"。
 *   它【不知道】TIM3、DMA、PA6 的存在 —— 所以可以在 PC 上单独编译、单独测。
 *
 * DShot 帧格式（16 位，MSB 先发）：
 *   bit15..5 (11 位) : 油门值 0..2047
 *   bit4             : 遥测请求位
 *   bit3..0  (4 位)  : CRC
 */
#pragma once
#include <stdint.h>
#include <stdbool.h>

#define DSHOT_VALUE_DISARM   0u      /* 上锁 */
#define DSHOT_VALUE_MIN      48u     /* 有效油门下限 */
#define DSHOT_VALUE_MAX      2047u   /* 有效油门上限 */

/** 特殊命令（用 1..47 的"油门值"承载） */
typedef enum {
    DSHOT_CMD_MOTOR_STOP     = 0,   /* 上锁 */
    DSHOT_CMD_BEEP1          = 1,   /* 响一声 —— 自检协议是否被电调解码 */
    DSHOT_CMD_ESC_INFO       = 2,
    DSHOT_CMD_SPIN_DIRECTION = 3,   /* 需第二个参数（7=正转 8=反转） */
    DSHOT_CMD_3D_MODE_OFF    = 4,
    DSHOT_CMD_3D_MODE_ON     = 5,
    DSHOT_CMD_SETTINGS_REQ   = 6,
    DSHOT_CMD_SAVE_SETTINGS  = 7,
    DSHOT_CMD_EXT_TELEMETRY  = 8,
} module_dshot_cmd_t;

/** CRC-4。输入是【12 位的 packet】(= 油门<<1 | 遥测)，已对照 AM32 解码器核实 */
uint16_t module_dshot_crc4(uint16_t frame12);

/** 组帧：油门/命令值 + 遥测位 → 16 位完整帧（CRC 算在 12 位 packet 上） */
uint16_t module_dshot_build(uint16_t value, bool telemetry_request);

/** 组一个特殊命令帧 */
uint16_t module_dshot_build_cmd(module_dshot_cmd_t cmd);

/** 校验：这个值算不算有效油门 */
bool module_dshot_is_valid_throttle(uint16_t value);
