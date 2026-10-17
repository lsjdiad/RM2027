#!/usr/bin/env bash
# run-regression.sh —— H104 协议/驱动解析器 **一键离线回归**（不需要板子、不需要 ST-Link）
#
# 用法（就一条命令）：
#   work/spi-runtime/h104/run-regression.sh
#
# 它跑三层，全绿才算过（任一失败 → 退出码非 0）：
#   1) Python 解析器对手册示例帧自检（证明与手册一致）
#   2) Python 判决器跑真实抓包（组帧 / 偏移平移扫描 / 物理自检 / 姿态自洽）
#   3) ★ C++ 驱动解析器（h104_protocol.hpp）编译后跑**同一份真实抓包**
#      —— 这是"改驱动前先离线回归"的那一层，能省掉大量上板往返
#
# 行尾：Linux(bash)，LF。
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
PX4="${PX4_DIR:-/home/xien/桌面/RM2027/PX4-Autopilot}"
CAP="$HERE/h104-cap.bin"
SRC="$PX4/src/drivers/imu/hipnuc_h104"

fail=0
hline() { printf '\n======== %s ========\n' "$1"; }

if [ ! -f "$CAP" ]; then
	echo "✗ 找不到黄金抓包 $CAP"
	echo "  （它应该跟本脚本一起在 h104/ 下；没有它这层就失去意义）"
	exit 2
fi

hline "1/3 Python 解析器自检（手册示例帧）"
python3 "$HERE/h104_parse.py" --selftest || fail=1

hline "2/3 Python 判决器（真实抓包：组帧 + 偏移扫描 + 物理/姿态自检）"
python3 "$HERE/h104_verify.py" "$CAP" || fail=1

hline "3/3 C++ 驱动解析器（h104_protocol.hpp）跑真实抓包"
if [ ! -f "$SRC/test_h104_protocol.cpp" ]; then
	echo "✗ 找不到 $SRC/test_h104_protocol.cpp"
	echo "  PX4 树不在默认位置？用 PX4_DIR=... 指定；"
	echo "  或把 src/drivers/imu/hipnuc_h104/{h104_protocol.hpp,test_h104_protocol.cpp} 拷到同目录再跑。"
	fail=1
else
	TMP=$(mktemp -d)
	if g++ -std=c++17 -Wall -Wextra -O2 -I"$SRC" \
		-o "$TMP/t_h104" "$SRC/test_h104_protocol.cpp"; then
		"$TMP/t_h104" "$CAP" || fail=1
	else
		echo "✗ C++ 编译失败"
		fail=1
	fi
	rm -rf "$TMP"
fi

hline "结果"
if [ "$fail" -eq 0 ]; then
	echo "✅ 离线回归全部通过 —— 可以上板了"
else
	echo "❌ 有失败项，**不要上板**，先修到全绿"
fi

exit "$fail"
