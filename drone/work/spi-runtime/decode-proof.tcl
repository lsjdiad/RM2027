# decode-proof.tcl —— ★ 独立验证数据解码是否正确（不靠"看起来合理"）
#
# 用户质疑："你确定你正确解码数据了对吗?" —— 本脚本逐条给出**可判决**的证据。
#
# 四步解码，各自的独立判据：
#   ① 命令帧：读命令 = 地址|0x80（RW 位在 bit0、先发）
#       判据：WHO_AM_I(0x01) 读回 0x6A。
#       若芯片其实用 (地址<<1)|RW 的帧法，那同一串 0x81 会被解成"读寄存器 0x40"，
#       而 0x40 是 ACC_CONF，值是 0x8C ⇒ 会读回 0x8C 而不是 0x6A。**实测 0x6A ⇒ 帧法正确。**
#   ② 寄存器窗口：ACC = 0x0C~0x11，GYR = 0x12~0x17
#       判据：**静止时陀螺必须≈0**。若窗口错开，陀螺位置读到的就是别的寄存器，
#       静止时不会≈0。见下面的 GYRO 一段。
#   ③ 字节序：H 在前（(H<<8)|L）还是 L 在前（(L<<8)|H）
#       判据：**同一个"静止陀螺≈0"**。错的那种拼法会给出几百~几千码的假零偏，
#       而且会在几帧之间乱跳 —— 物理上不可能。
#       顺带：加速度计的 |a| 在正确拼法下必须稳定（静止 1g）。
#   ④ 标度：这一条**本脚本不判决**，必须靠外部参照（H104）。
#
# 用法： openocd -f decode-proof.tcl

source [find interface/stlink.cfg]
transport select hla_swd
source [find target/stm32h7x_dual_bank.cfg]
adapter speed 1000
init
halt

echo "### DECODE-PROOF BEGIN ###"

proc r32 {a} { mem2array v 32 $a 1; return $v(0) }
proc w32 {a v} { mww $a $v }
proc srr {} { return [r32 0x40013014] }
proc dr {} { set n 0; while {$n<16 && ([srr]&1)!=0} { mem2array z 8 0x40013030 1; incr n } }
proc xf {b} {
	w32 0x40013000 0x00001201
	mwb 0x40013020 $b
	set n 0
	while {$n<300} { if {([srr]&1)!=0} { break }; incr n }
	mem2array v 8 0x40013030 1
	return $v(0)
}
proc cslo {} { w32 0x58020418 0x00100000 }
proc cshi {} { w32 0x58020418 0x00000010 }
proc rd1 {reg} { cslo; dr; xf [expr {$reg | 0x80}]; set b [xf 0x00]; cshi; return $b }
proc s16 {v} { if {$v > 32767} { return [expr {$v - 65536}] }; return $v }

w32 0x40013018 0x00001FFF
after 2

# ---- ① 命令帧 ----
set who [rd1 0x01]
set acc_cfg [rd1 0x40]
echo [format "① 命令帧: WHO_AM_I(0x01)=0x%02X   ACC_CONF(0x40)=0x%02X" $who $acc_cfg]
echo [format "   判据: 期望 0x6A（手册 §5.1）。若帧法错成 (addr<<1)|RW，读 0x01 会命中 0x40 ⇒ 会读到 0x%02X" $acc_cfg]
echo [format "   ⇒ %s" [expr {$who == 0x6A ? "帧法正确" : "帧法可疑！"}]]

echo ""
echo "② ③ 寄存器窗口 + 字节序（读 6 帧看稳定性；静止时陀螺必须≈0）"
echo [format "%-4s | %-28s | %-28s | %s" "帧" "H-first (H<<8)|L" "L-first (L<<8)|H" "|a| 两种拼法"]

for {set k 1} {$k <= 6} {incr k} {
	set ax [s16 [expr {([rd1 0x0C]<<8) | [rd1 0x0D]}]]
	set ay [s16 [expr {([rd1 0x0E]<<8) | [rd1 0x0F]}]]
	set az [s16 [expr {([rd1 0x10]<<8) | [rd1 0x11]}]]
	set gx [s16 [expr {([rd1 0x12]<<8) | [rd1 0x13]}]]
	set gy [s16 [expr {([rd1 0x14]<<8) | [rd1 0x15]}]]
	set gz [s16 [expr {([rd1 0x16]<<8) | [rd1 0x17]}]]

	# L-first 拼法 = 同一对字节反过来
	set abx [s16 [expr {(($ax & 0xFF)<<8) | (($ax>>8)&0xFF)}]]
	set aby [s16 [expr {(($ay & 0xFF)<<8) | (($ay>>8)&0xFF)}]]
	set abz [s16 [expr {(($az & 0xFF)<<8) | (($az>>8)&0xFF)}]]
	set gbx [s16 [expr {(($gx & 0xFF)<<8) | (($gx>>8)&0xFF)}]]
	set gby [s16 [expr {(($gy & 0xFF)<<8) | (($gy>>8)&0xFF)}]]
	set gbz [s16 [expr {(($gz & 0xFF)<<8) | (($gz>>8)&0xFF)}]]

	set magA [expr {sqrt(double($ax*$ax + $ay*$ay + $az*$az))}]
	set magB [expr {sqrt(double($abx*$abx + $aby*$aby + $abz*$abz))}]

	echo [format "ACC%-2d | X=%7d Y=%7d Z=%7d | X=%8d Y=%8d Z=%8d | %7.0f / %8.0f" \
		$k $ax $ay $az $abx $aby $abz $magA $magB]
	echo [format "GYR%-2d | X=%7d Y=%7d Z=%7d | X=%8d Y=%8d Z=%8d |  (dps: %6.1f / %8.1f)" \
		$k $gx $gy $gz $gbx $gby $gbz [expr {sqrt(double($gx*$gx+$gy*$gy+$gz*$gz))/16.384}] \
		[expr {sqrt(double($gbx*$gbx+$gby*$gby+$gbz*$gbz))/16.384}]]
	after 40
}

echo ""
echo "判读:"
echo "  · 静止陀螺必须 ≈ 0 dps  ⇒ 哪种拼法给出≈0，哪种就是对的"
echo "  · 静止 |a| 必须恒定 1g   ⇒ 哪种拼法给出稳定的同一数量级，哪种就是对的"
echo "  · 错的那种拼法会在帧间乱跳（物理上不可能）"

w32 0x40013000 0x00001001
w32 0x58020418 0x00000010
echo "### DECODE-PROOF END ###"
resume
shutdown
