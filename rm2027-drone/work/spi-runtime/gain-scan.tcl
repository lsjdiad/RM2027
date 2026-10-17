# gain-scan.tcl —— ★ 高精度标度扫描（回答"到底是 2 倍还是 1.757 倍"）
#
# 上一版 `fs-scan.tcl` 只读 Z 轴、每档只取 3 个样本的中位 ⇒ 噪声 ~12%，
# 结果把 ±8g 那档的离群点平均掉了（用户当场指出）。本版修正：
#   ① **读三轴**，用 |平均值| = sqrt(mx²+my²+mz²) 求重力矢量长度（消除板子倾斜的影响）
#   ② **每档 64 个样本**，先对各轴求平均再取模（噪声按 1/√N 收敛）
#   ③ 同时打印标准差，**让噪声自己现形**，而不是藏在数字里
#   ④ 每档之间留 500ms 稳定，并且用"关 ACC → 改 FS → 开 ACC"的时序
#
# 判读：板子**静止平放、别手拿**。|平均| 就是 1g 对应的原始码 = 该档真实 LSB/g。
#
# 用法： openocd -f gain-scan.tcl

source [find interface/stlink.cfg]
transport select hla_swd
source [find target/stm32h7x_dual_bank.cfg]
adapter speed 1000
init
halt

echo "### GAIN-SCAN BEGIN ###"

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
proc wr1 {reg val} { cslo; dr; xf $reg; xf $val; cshi }
proc s16 {v} { if {$v > 32767} { return [expr {$v - 65536}] }; return $v }

# 采 N 个样本，返回 {mx my mz stdev_mag}
proc sample {n} {
	set sx 0; set sy 0; set sz 0
	set mags {}
	for {set i 0} {$i < $n} {incr i} {
		set x [s16 [expr {([rd1 0x0C]<<8) | [rd1 0x0D]}]]
		set y [s16 [expr {([rd1 0x0E]<<8) | [rd1 0x0F]}]]
		set z [s16 [expr {([rd1 0x10]<<8) | [rd1 0x11]}]]
		incr sx $x; incr sy $y; incr sz $z
		lappend mags [expr {sqrt(double($x*$x + $y*$y + $z*$z))}]
	}
	set mx [expr {double($sx)/$n}]
	set my [expr {double($sy)/$n}]
	set mz [expr {double($sz)/$n}]
	set mag [expr {sqrt($mx*$mx + $my*$my + $mz*$mz)}]
	# 幅值的样本标准差
	set s 0.0
	foreach m $mags { set s [expr {$s + ($m-$mag)*($m-$mag)}] }
	set sd [expr {sqrt($s/$n)}]
	return [list $mx $my $mz $mag $sd]
}

w32 0x40013018 0x00001FFF
after 2

echo [format "WHO_AM_I=%02X  ACC_CONF(0x40)=%02X  PWR_CTRL=%02X" [rd1 0x01] [rd1 0x40] [rd1 0x7D]]

# 手册 §5.38 + 规格表第 186-190 行： 32768 / 量程g
array set IDEAL {0 16384 1 8192 2 4096 3 2048}

foreach fs {0 1 2 3} {
	wr1 0x7D 0x00
	after 20
	wr1 0x41 $fs
	after 20
	wr1 0x7D 0x0E
	after 500

	set rb [rd1 0x41]
	set r [sample 64]

	set mx [lindex $r 0]; set my [lindex $r 1]; set mz [lindex $r 2]
	set mag [lindex $r 3]; set sd [lindex $r 4]
	set ideal $IDEAL($fs)
	set stepup [expr {double($ideal)/2}]

	echo [format "FS=%d 回读=0x%02X  均= ( %8.1f %8.1f %8.1f )  |a|=%8.1f 码  sd=%5.1f" \
		$fs $rb $mx $my $mz $mag $sd]
	echo [format "        |a|/手册=%7.4f    |a|/(手册/2)=%7.4f    手册=%d  手册/2=%d" \
		[expr {$mag/double($ideal)}] [expr {$mag/$stepup}] $ideal [expr {$ideal/2}]]
}

# 恢复驱动配置
wr1 0x41 0x01
wr1 0x7D 0x0E
after 300
echo [format "restored: 0x41=%02X 0x7D=%02X" [rd1 0x41] [rd1 0x7D]]

w32 0x40013000 0x00001001
w32 0x58020418 0x00000010
echo "### GAIN-SCAN END ###"
resume
shutdown
