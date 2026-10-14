#!/usr/bin/env bash
# dumplog.sh —— 只读：把 PX4 console 环形缓冲区【整体】按时间顺序 dump 出来
#
# 与 checklog.sh 的区别：
#   checklog.sh 只打"未读"区间（buf[tail:head]）—— QGC 一直抽，未读区间经常是空的。
#   本脚本打**整个 4096 字节**，按时间顺序（buf[head:] + buf[:head]）——
#   即使 QGC 已经把内容读走了，**字节还在环形缓冲区里**（直到被新输出覆盖）。
#   ⇒ 抓启动日志时这招比"抢未读窗口"可靠得多。
#
# 行尾：Linux(bash)，LF。
set -u

ELF=/home/xien/桌面/RM2027/PX4-Autopilot/build/rm2027_fmu-h743_default/rm2027_fmu-h743_default.elf
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HERE/console_dump.bin"

ADDR=$(arm-none-eabi-nm "$ELF" | awk '/g_console_buffer/{print "0x"$1; exit}')
if [ -z "$ADDR" ]; then echo "找不到 g_console_buffer 符号"; exit 1; fi

rm -f "$OUT"
timeout 60 openocd -f interface/stlink.cfg -f target/stm32h7x_dual_bank.cfg \
	-c "adapter speed 1000" -c "init" -c "halt" \
	-c "dump_image $OUT $ADDR 0x1008" -c "resume" -c "shutdown" >/dev/null 2>&1

python3 - "$OUT" <<'PYEOF'
import struct, sys
d = open(sys.argv[1], 'rb').read()
buf, head, tail = d[:0x1000], *struct.unpack_from('<ii', d, 0x1000)
head &= 0xFFF; tail &= 0xFFF
print("==== head=%d tail=%d  (未读 %d 字节) ====" % (head, tail, (head - tail) & 0xFFF))

unread = buf[tail:head] if head >= tail else buf[tail:] + buf[:head]
print("\n---- [A] 未读区间 ----")
print(unread.decode('utf-8', 'replace') if unread else "(空 —— QGC 已经抽干)")

chrono = buf[head:] + buf[:head]
print("\n---- [B] 整块缓冲（时间顺序，最后 %d 字节）----" % len(chrono))
print(chrono.decode('utf-8', 'replace'))

txt = chrono.decode('utf-8', 'replace')
print("\n---- [C] 关键行 ----")
for pat in ('GYR_CONF step', '0x42 read back', 'not accepted', 'hxy42688p #',
            'on SPI bus', 'ist8310 #', 'device did NOT accept', 'stale sample'):
    c = txt.count(pat)
    if c:
        print("  %-26s x%d" % (pat, c))
PYEOF
