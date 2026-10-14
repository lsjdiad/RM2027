#!/usr/bin/env bash
# h104-dump.sh —— 只读：用 ST-Link 把 h104cap 写进固定 RAM 的报告与原始字节流取出来
#
# 为什么不用 console：本板 console 环形缓冲只有 4 KB（BOARD_ENABLE_CONSOLE_BUFFER），
#   8 KB 抓包 / 4 KB 报告走 console 必被覆盖。走 SWD 直接 dump 内存，一个字节都不丢。
#
# 前置：板上跑过一次 `h104cap all`（本分支临时挂在 rc.board_extras 里，开机自动跑）。
#
# 行尾：Linux(bash)，LF。
set -u

PX4=/home/xien/桌面/RM2027/PX4-Autopilot
ELF="$PX4/build/rm2027_fmu-h743_default/rm2027_fmu-h743_default.elf"
HERE="$(cd "$(dirname "$0")" && pwd)"
REP="$HERE/h104-report.txt"      # 二进制原样 dump
CAP="$HERE/h104-cap.bin"         # 二进制原样 dump
OUT="$HERE/h104-report.print.txt" # 解析后的报告文本

echo "== 1. 前置检查 =="
if ! lsusb | grep -q 0483; then
	echo "  ✗ 没找到 ST-Link（0483:xxxx）—— 需要物理拔插"
	exit 1
fi
if pgrep -a openocd >/dev/null; then
	echo "  ✗ 已有 openocd 在跑（同一时间只允许一个）："
	pgrep -a openocd | sed 's/^/     /'
	exit 1
fi
echo "  OK（ST-Link 空闲）"

echo "== 2. 取符号地址 =="
sym() { arm-none-eabi-nm "$ELF" | awk -v s="$1" '$3==s {print "0x"$1; exit}'; }
A_REP=$(sym g_h104_report);    [ -n "$A_REP" ] || { echo "  ✗ 找不到 g_h104_report —— 固件不是本分支编的？"; exit 1; }
A_CAP=$(sym g_h104_cap_buf);   [ -n "$A_CAP" ] || { echo "  ✗ 找不到 g_h104_cap_buf"; exit 1; }
A_RPL=$(sym g_h104_report_len)
A_CPL=$(sym g_h104_cap_len)
echo "  g_h104_report     = $A_REP"
echo "  g_h104_cap_buf    = $A_CAP"
echo "  g_h104_report_len = ${A_RPL:-?}"
echo "  g_h104_cap_len    = ${A_CPL:-?}"

echo "== 3. dump（halt → dump_image → resume）=="
rm -f "$REP" "$CAP"
if ! timeout 90 openocd -f interface/stlink.cfg -f target/stm32h7x_dual_bank.cfg \
	-c "adapter speed 1000" -c "init" -c "halt" \
	-c "dump_image $REP $A_REP 0x4000" \
	-c "dump_image $CAP $A_CAP 0x2000" \
	${A_RPL:+-c "mdw $A_RPL 1"} ${A_CPL:+-c "mdw $A_CPL 1"} \
	-c "resume" -c "shutdown" 2>&1 | tee /tmp/h104dump.log | grep -Ev "^$" | tail -12; then
	echo "  ✗ openocd 失败，看 /tmp/h104dump.log"
	exit 1
fi

echo "== 4. 解析报告 =="
python3 - "$REP" "$CAP" "$OUT" <<'PYEOF'
import sys, re
rep_bin, cap_bin, out_txt = sys.argv[1], sys.argv[2], sys.argv[3]
raw = open(rep_bin, 'rb').read()
# 报告是 NUL 结尾的 ASCII；len 变量也可以从这里反推
nul = raw.find(b'\x00')
txt = raw[:nul if nul >= 0 else len(raw)].decode('utf-8', 'replace')
open(out_txt, 'w', encoding='utf-8').write(txt)
print(txt)
print("==== 报告 %d 字节，已存 %s ====" % (len(txt), out_txt))
cap = open(cap_bin, 'rb').read()
nz = len(cap.rstrip(b'\x00'))
print("==== 原始抓包缓冲区 8192 B，其中非零/已写 %d 字节，已存 %s ====" % (nz, cap_bin))
if nz == 0:
    print("!! 抓包缓冲区全 0 ⇒ h104cap all 没跑到，或抓包阶段没数据（注意 buffer 全 0 也可能是没执行）")
PYEOF

echo
echo "== 5. 下一步：解协议 =="
echo "  python3 $HERE/h104_parse.py -f $CAP --stats"
echo "  python3 $HERE/h104_parse.py -f $CAP"
