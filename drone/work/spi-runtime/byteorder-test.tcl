# byteorder-test.tcl —— ★ 判死字节序：H-first(手册) vs L-first(BMI270 家族)
#
# 起因：用户质疑"这真的不是你解码问题吗？是左移右移位数的识别问题吗？"
#   · 已排除：突发解码错位（burst-vs-single.tcl 两种读法一致）、配置侧问题（OIS/SAT/FIFO 全缺省）
#   · 剩下的硬约束：**静止时 |a| 必须恒定 ≈ 1g**（与姿态无关）。哪个字节序满足它，哪个就是对的。
#
# 现有两姿势的线索（H-first 比值 3.62×、L-first 比值 1.30×）⇒ **L-first 好得多，但还不完美**。
#   ⇒ 需要**多姿态连续采样**才能拟合。本脚本边转边记，两种拼法同时打印。
#
# 同时打**陀螺**：静止时陀螺三轴必须 ≈0（无论哪种拼法），这是独立旁证；
#   而且 |ω| 与姿态无关 ⇒ 也能用来判字节序。
#
# 用法：先启动脚本，然后**慢慢把板子转一圈**（平放→侧→机头上下→倒扣→回平放）。
#       脚本等你开始转（|陀螺|>30dps）后连续记 40 秒。
#       openocd -f byteorder-test.tcl

source [find interface/stlink.cfg]
transport select hla_swd
source [find target/stm32h7x_dual_bank.cfg]
adapter speed 1000
init
halt

echo "### BYTEORDER BEGIN ###"

proc r32 {a} { mem2array v 32 $a 1; return $v(0) }
proc w32 {a v} { mww $a $v }
proc srr {} { return [r32 0x40013014] }
proc dr {} { set n 0; while {$n<16 && ([srr]&1)!=0} { mem2array z 8 0x40013030 1; incr n } }
proc cslo {} { w32 0x58020418 0x00100000 }
proc cshi {} { w32 0x58020418 0x00000010 }
proc xf_ {b} {
	w32 0x40013000 0x00001201
	mwb 0x40013020 $b
	set n 0
	while {$n<300} { if {([srr]&1)!=0} { break }; incr n }
	mem2array v 8 0x40013030 1
	return $v(0)
}
proc s16 {v} { if {$v > 32767} { return [expr {$v - 65536}] }; return $v }

# 一次 15 字节突发（与驱动完全相同的读法）
proc burst15 {} {
	cslo; dr
	set o {}
	lappend o [xf_ 0x8B]
	for {set i 0} {$i < 14} {incr i} { lappend o [xf_ 0x00] }
	cshi
	return $o
}

w32 0x40013000 0x00001200 ; after 2
w32 0x40013018 0x00001FFF
set n 0
while {$n < 64 && ([srr] & 1) != 0} { mem2array z 8 0x40013030 1; incr n }
w32 0x40013000 0x00001201 ; after 2

echo ">>> 等你把板子转起来（|陀螺|>30dps）后连续记录 40 秒；慢慢转，尽量覆盖各种朝向 <<<"

# 阶段1：等转动
set tw [clock milliseconds]
while {1} {
	set g [burst15]
	set gx [s16 [expr {([lindex $g 8]<<8) | [lindex $g 9]}]]
	set gy [s16 [expr {([lindex $g 10]<<8) | [lindex $g 11]}]]
	set gz [s16 [expr {([lindex $g 12]<<8) | [lindex $g 13]}]]
	set gm [expr {sqrt(double($gx*$gx+$gy*$gy+$gz*$gz))/16.384}]
	if {$gm > 30.0} { break }
	if {([clock milliseconds] - $tw) > 480000} { echo "!! 等 8 分钟没等到转动，退出"; break }
	after 200
}

# 阶段2：记录 40 秒
echo "t(s) |    H-first        |a|H  |    L-first        |a|L | 陀螺dps"
set t0 [clock milliseconds]
while {1} {
	set el [expr {([clock milliseconds] - $t0)/1000.0}]
	if {$el > 40.0} { break }
	set o [burst15]

	# H-first（手册：H 在前）
	set hx [s16 [expr {([lindex $o 2]<<8) | [lindex $o 3]}]]
	set hy [s16 [expr {([lindex $o 4]<<8) | [lindex $o 5]}]]
	set hz [s16 [expr {([lindex $o 6]<<8) | [lindex $o 7]}]]
	# L-first（BMI270：L 在前，同一对字节反过来）
	set lx [s16 [expr {([lindex $o 3]<<8) | [lindex $o 2]}]]
	set ly [s16 [expr {([lindex $o 5]<<8) | [lindex $o 4]}]]
	set lz [s16 [expr {([lindex $o 7]<<8) | [lindex $o 6]}]]

	set gm [expr {sqrt(double([lindex $o 8]*[lindex $o 8]+[lindex $o 10]*[lindex $o 10]+[lindex $o 12]*[lindex $o 12]))/16.384}]
	set mh [expr {sqrt(double($hx*$hx+$hy*$hy+$hz*$hz))}]
	set ml [expr {sqrt(double($lx*$lx+$ly*$ly+$lz*$lz))}]

	echo [format "%5.1f | %6d %6d %6d %7.0f | %6d %6d %6d %7.0f | %5.1f" \
		$el $hx $hy $hz $mh $lx $ly $lz $ml $gm]
	after 120
}

w32 0x40013000 0x00001001
w32 0x58020418 0x00000010
echo "### BYTEORDER END ###"
resume
shutdown
