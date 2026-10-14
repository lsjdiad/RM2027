#!/usr/bin/env bash
# checklog.sh —— 只读：通过 ST-Link 把运行中 PX4 的 console 环形缓冲区抓出来并打印
#
# 为什么不直接读 /dev/ttyUSB0：QGC 常占着那个口；而 PX4 的 dmesg 内容就存在
# RAM 里的 g_console_buffer（本板当前构建在 0x2400a404），用 SWD 直接读最省事。
#
# 注意：地址随构建变化。若失效，用下面命令重新拿地址：
#   arm-none-eabi-nm build/rm2027_fmu-h743_default/rm2027_fmu-h743_default.elf | grep g_console_buffer
#
# 行尾：本脚本在 Linux(bash) 下运行；若从 Windows 侧复制请确保 LF 行尾。
set -u

ELF=/home/xien/桌面/RM2027/PX4-Autopilot/build/rm2027_fmu-h743_default/rm2027_fmu-h743_default.elf
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HERE/console_now.bin"

# g_console_buffer 地址（char[4096] + int _head + int _tail）
ADDR=$(arm-none-eabi-nm "$ELF" | awk '/g_console_buffer/{print "0x"$1; exit}')
if [ -z "$ADDR" ]; then echo "找不到 g_console_buffer 符号"; exit 1; fi

rm -f "$OUT"
timeout 60 openocd -f interface/stlink.cfg -f target/stm32h7x_dual_bank.cfg \
	-c "adapter speed 1000" -c "init" -c "halt" \
	-c "dump_image $OUT $ADDR 0x1008" -c "resume" -c "shutdown" >/dev/null 2>&1

python3 - "$OUT" <<'PYEOF'
import struct, sys, re
d = open(sys.argv[1], 'rb').read()
buf, head, tail = d[:0x1000], *struct.unpack_from('<ii', d, 0x1000)
data = buf[tail:head] if head >= tail else buf[tail:] + buf[:head]
txt = data.decode('utf-8', 'replace')
print("==== console buffer (%d 字节未读) ====" % len(data))
print(txt)
print("==== 关键行统计 ====")
n = txt.count('Skipping BMI270 microcode upload')
print("'Skipping BMI270 microcode upload' 出现 %d 次  (==1 正常；>5 说明仍在重启循环)" % n)
for pat in ('bmi270 #', 'on SPI bus', 'BMI270-compatible', 'no instance started'):
    c = txt.count(pat)
    if c: print("  %-28s x%d" % (pat, c))
PYEOF
