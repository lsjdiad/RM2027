#!/usr/bin/env bash
# h104-dump-console.sh —— 取证：把 PX4 的 console 环形缓冲**整块** dump 下来并 grep H104 相关行
#
# 为什么不能只用 checklog.sh：
#   checklog.sh 只读 tail→head 的"未读窗口"。而 QGC 的 MAVLink console 会持续把这个窗口抽干，
#   结果往往只剩 1 个字节。**但被消费掉的数据在环形缓冲里被覆盖之前还在**，
#   所以要看整块 4096 字节缓冲（本脚本干的就是这个）。
#
# 为什么要在"刚打完自检行"的时刻停机：
#   开机后 health_and_arming_checks 会每秒刷几百字节告警，4 KB 缓冲很快被覆盖。
#   h104_imu 第一帧行约在开机后 0.1~1 s，300 帧统计行约在首帧后 3 s。
#   ⇒ 本脚本先 `reset run`，再 `sleep $WAIT`，然后 halt 抓取。默认 WAIT=4（抓 300 帧那行）。
#
# 用法： ./h104-dump-console.sh [等待秒数，默认 4]
#
# 行尾：Linux(bash)，LF。
set -u

WAIT="${1:-4}"
PX4=/home/xien/桌面/RM2027/PX4-Autopilot
ELF="$PX4/build/rm2027_fmu-h743_default/rm2027_fmu-h743_default.elf"
OCD_CFG=(-f interface/stlink.cfg -f target/stm32h7x_dual_bank.cfg)
OUT=/tmp/h104-console.bin

[ -f "$ELF" ] || { echo "✗ 找不到 ELF: $ELF"; exit 1; }
pgrep -a openocd >/dev/null && { echo "✗ 已有 openocd 在跑："; pgrep -a openocd; exit 1; }
command -v arm-none-eabi-nm >/dev/null || { echo "✗ 缺 arm-none-eabi-nm"; exit 1; }

ADDR=$(arm-none-eabi-nm "$ELF" | awk '/g_console_buffer/{print "0x"$1; exit}')
[ -n "$ADDR" ] || { echo "✗ 找不到 g_console_buffer 符号"; exit 1; }
echo "g_console_buffer = $ADDR ; 复位后等 ${WAIT}s 再停机"

# 1) 复位并让板子跑起来
timeout 90 openocd "${OCD_CFG[@]}" -c "adapter speed 1800" -c "init" -c "reset run" -c "shutdown" >/dev/null 2>&1
sleep "$WAIT"

# 2) 停机，整块 dump（char[4096] + head(4) + tail(4)）
rm -f "$OUT"
if ! timeout 90 openocd "${OCD_CFG[@]}" -c "adapter speed 1800" -c "init" -c "halt" \
	-c "dump_image $OUT $ADDR 0x1008" -c "resume" -c "shutdown" >/dev/null 2>&1; then
	echo "✗ dump 失败"; exit 1
fi

python3 - "$OUT" <<'PY'
import re, struct, sys
d = open(sys.argv[1], 'rb').read()
buf, head, tail = d[:0x1000], *struct.unpack_from('<ii', d, 0x1000)
print("未读窗口 head=%d tail=%d (%d 字节) —— QGC 会把它抽干，所以下面看整块" % (head, tail, head - tail))
txt = buf.decode('utf-8', 'replace')
hits = [m.group(0).strip() for m in re.finditer(r'[^\n\x00]{0,10}h104[^\n\x00]*', txt)]
print("\n=== 整块缓冲里含 h104 的行（%d 行）===" % len(hits))
for h in hits:
    print("  |", h)
if not hits:
    print("  (没抓到 —— 可能等待时间不对：首帧行约 0.1~1s，300 帧行约首帧后 3s；"
          "或告警把缓冲冲刷掉了)")
print("\n=== Accel/Gyro 相关（去重）===")
for s in sorted(set(re.findall(r'[^\n\x00]{0,55}(?:Accel|Gyro) [01][^\n\x00]*', txt))):
    print("  |", s.strip())
PY
