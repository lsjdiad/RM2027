#!/usr/bin/env bash
# flash-and-verify.sh —— 一键：烧写新固件 → 等启动 → 读 console 验证
#
# 用法： ./flash-and-verify.sh
#
# 前置检查（脚本会自己查）：
#   1) ST-Link 在 USB 上（lsusb 里能看到 0483）
#   2) 没有别的 openocd 在跑（同一时间只允许一个 agent 用 ST-Link）
#
# 行尾：本脚本在 Linux(bash) 下运行；若从 Windows 侧复制请确保 LF 行尾。
set -u

PX4=/home/xien/桌面/RM2027/PX4-Autopilot
BUILD="$PX4/build/rm2027_fmu-h743_default"
ELF="$BUILD/rm2027_fmu-h743_default.elf"
HERE="$(cd "$(dirname "$0")" && pwd)"

echo "== 1. 检查 ST-Link =="
if ! lsusb | grep -q 0483; then
	echo "  ✗ 没找到 ST-Link（0483:xxxx）。请把 ST-Link 的 USB 线【物理拔插一次】。"
	exit 1
fi
lsusb | grep 0483 | sed 's/^/  /'

echo "== 2. 检查是否有别的 openocd 在跑 =="
if pgrep -a openocd >/dev/null; then
	echo "  ✗ 已有 openocd 在运行，先杀掉再跑本脚本（同一时间只能一个会话用 ST-Link）："
	pgrep -a openocd | sed 's/^/     /'
	exit 1
fi
echo "  OK"

echo "== 3. 确认固件是最新的 =="
ls -l --time-style=+%m-%d\ %H:%M "$BUILD/rm2027_fmu-h743_default.bin" | sed 's/^/  /'

echo "== 4. 烧写（必须 dual_bank，否则 Verify Failed）=="
# ⚠️ adapter speed 实测阶梯（2026-09-30，同一块 ST-Link V2 clone「STLINK V2J46S7」）：
#    1800 kHz → 擦除阶段就失败（Error reading 0x52002110 / erase time-out sector 3）
#     500 kHz → 连接稳定，但**长传输不稳**：一次 checksum mismatch / Verify Failed，
#               一次 "error writing to flash at offset 0x00020000" 直接 Programming Failed
#     240 kHz → ✅ program + verify 全部通过（可靠档）
#    ⇒ 长写用 240；只做小 dump（几百字节~几十 KB）时 500 就够。
cd "$BUILD" || exit 1
if ! timeout 900 openocd -f interface/stlink.cfg -f target/stm32h7x_dual_bank.cfg \
	-c "adapter speed 240" -c "init" -c "reset halt" \
	-c "program rm2027_fmu-h743_default.elf verify" -c "reset run" -c "shutdown" \
	2>&1 | tee /tmp/flash.log | tail -8; then
	echo "  ✗ 烧写失败，看 /tmp/flash.log"
	exit 1
fi
grep -q "Verified OK" /tmp/flash.log || { echo "  ✗ 没有 Verified OK"; exit 1; }
echo "  ✓ 烧写并校验通过"

echo "== 5. 等 30 s 让 PX4 启动完成 =="
sleep 30

echo "== 6. 读 console 环形缓冲区（dmesg）=="
"$HERE/checklog.sh"

echo
echo "== 7. 下一步（人工）=="
echo "   /dev/ttyUSB0 被 QGC 占着，pymavlink 抢不到，所以请在 QGC 的 MAVLink Console 里敲："
echo "     listener sensor_accel     # 静止时合矢量应 ≈ 9.8，NED 下 z ≈ -9.8"
echo "     listener sensor_gyro      # 静止时三轴应接近 0"
