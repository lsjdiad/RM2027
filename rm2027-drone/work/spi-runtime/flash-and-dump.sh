#!/usr/bin/env bash
# flash-and-dump.sh —— 烧写 → reset run → 【尽快】抓 console 整块环形缓冲区
#
# 为什么不能等：PX4 启动后 `health_and_arming_checks` 每秒刷一堆 WARN，
# 4096 字节的环形缓冲区在 ~1 分钟内就被刷满，驱动启动期（Configure() 的打印）
# 会被彻底覆盖。所以要在 boot 后 **几秒内** 抓。
#
# 用法： ./flash-and-dump.sh [等待秒数，默认 7]
#
# 行尾：Linux(bash)，LF。
set -u

PX4=/home/xien/桌面/RM2027/PX4-Autopilot
BUILD="$PX4/build/rm2027_fmu-h743_default"
HERE="$(cd "$(dirname "$0")" && pwd)"
WAIT="${1:-7}"

lsusb | grep -q 0483 || { echo "✗ 没找到 ST-Link"; exit 1; }
pgrep -a openocd >/dev/null && { echo "✗ 已有 openocd 在跑"; exit 1; }

echo "== 烧写（240 kHz）=="
cd "$BUILD" || exit 1
timeout 900 openocd -f interface/stlink.cfg -f target/stm32h7x_dual_bank.cfg \
	-c "adapter speed 240" -c "init" -c "reset halt" \
	-c "program rm2027_fmu-h743_default.elf verify" -c "reset run" -c "shutdown" \
	> /tmp/flash.log 2>&1
grep -q "Verified OK" /tmp/flash.log || { echo "✗ 烧写失败："; tail -15 /tmp/flash.log; exit 1; }
echo "  ✓ Verified OK"

echo "== 等 ${WAIT} s 后抓缓冲区（不等 PX4 刷屏）=="
sleep "$WAIT"
"$HERE/dumplog.sh"
