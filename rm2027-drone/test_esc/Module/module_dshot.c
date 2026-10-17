/**
 * @file    module_dshot.c
 * @brief   DShot 协议层实现
 */
#include "module_dshot.h"

uint16_t module_dshot_crc4(uint16_t frame12)
{
    /* 标准 DShot CRC：
     *   crc = (v ^ (v>>4) ^ (v>>8)) & 0x0F      （v = 低 12 位）
     *
     * ★ 来源已核实（2026-10-06）：AM32 `Src/dshot.c:computeDshotDMA()` 里的校验是
     *     bit 级逐位异或：
     *       calcCRC.bit3 = b15^b11^b7 ; bit2 = b14^b10^b6
     *       calcCRC.bit1 = b13^b9^b5  ; bit0 = b12^b8^b4
     *     把它按 12 位 packet 展开，正好等于 (P ^ (P>>4) ^ (P>>8)) & 0xF。
     *
     * ★ 逐值验证（主机侧跑过）：把 module_dshot_build() 对【2048 个油门值 × 2 种遥测位】
     *   共 4096 帧全部生成，再用 AM32 的上述 bit 级判据逐帧复核
     *   ⇒ **4096/4096 全部通过**。所以这里的公式与位序可以确认无误。
     *
     * 历史坑（留档）：早期版本少了 (v>>8) 项，症状是"油门 0 的帧电调收（全零帧 CRC 恒为 0），
     *   油门 200 的帧被拒"，示波器实测帧为 0x1909 而正确值应为 0x1908 —— 只差 CRC 最低位。 */
    return (uint16_t)((frame12 ^ (frame12 >> 4) ^ (frame12 >> 8)) & 0x000Fu);
}

uint16_t module_dshot_build(uint16_t value, bool telemetry_request)
{
    /* ★ DShot 帧布局（依据 AM32 解码器 Src/dshot.c:computeDshotDMA）：
     *     bit15..5 = 11 位油门/命令
     *     bit4     = 遥测请求位
     *     bit3..0  = CRC
     *
     * ★★ CRC 的输入是【12 位的 packet】= (油门<<1 | 遥测)，不是移位后的 16 位帧。
     *
     * 上机证据链（三条互相独立）：
     *   ① AM32 的 calcCRC 展开后即 (P ^ (P>>4) ^ (P>>8)) & 0xF，其中 P 是 12 位；
     *   ② 示波器实测我们发出的帧是 0001100100001001 (0x1909)，
     *      而按 12 位公式应为 0001100100001000 (0x1908) —— 只差 CRC 最低位；
     *   ③ 电调行为：油门 0 的帧（全零）被接受 ⇒ 解锁亮绿灯；
     *      油门 200 的帧被拒绝 ⇒ input 停在 0、running=0、三相不驱动。
     *      【全零帧无论公式对错 CRC 都算 0 ⇒ 必然通过】，
     *      所以"0 能过、200 过不了"只能由 CRC 差异解释。
     */
    uint16_t packet = (uint16_t)((value & 0x07FFu) << 1);

    if (telemetry_request) {
        packet |= 0x0001u;
    }

    return (uint16_t)((packet << 4) | module_dshot_crc4(packet));
}

uint16_t module_dshot_build_cmd(module_dshot_cmd_t cmd)
{
    return module_dshot_build((uint16_t)cmd, false);
}

bool module_dshot_is_valid_throttle(uint16_t value)
{
    return (value >= DSHOT_VALUE_MIN) && (value <= DSHOT_VALUE_MAX);
}
