# hold-steady.tcl —— 等板子"端稳"后连续记录 25 秒（用来定轴映射）
#
# 为什么不用 watch-rotate：那次用户是在**转**，静止样本全落在"平放"上，没覆盖到 X/Y。
# 本脚本的触发条件是**静止**（不是转动）：等 |陀螺| 连续 20 次 < 3 dps，就从那一刻起记 25 秒。
#
# 目的：让用户在**侧放（一个侧面朝下）**的姿态下端稳，看重力落在**哪根轴**、**什么符号**。
#   · 重力落在 Y、且与 H104 的符号一致 ⇒ 轴是对的
#   · 重力落在 Y、但符号相反             ⇒ Y 反号
#   · 重力仍落在 Z（或比例不对）          ⇒ 轴串了
#
# ⚠️ 本脚本**不做过滤**，原样打出来，由 Lead 判读。

source [find interface/stlink.cfg]
transport select hla_swd
source [find target/stm32h7x_dual_bank.cfg]
adapter speed 1000
init
halt

echo "### HOLD-STEADY BEGIN ###"

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
proc rd16 {reg} { cslo; dr; xf_ [expr {$reg | 0x80}]; set h [xf_ 0x00]; set l [xf_ 0x00]; cshi; return [s16 [expr {($h<<8) | $l}]] }
proc rd1x {reg} { cslo; dr; xf_ [expr {$reg | 0x80}]; set b [xf_ 0x00]; cshi; return $b }
proc rdcfg {reg} { for {set t 0} {$t<6} {incr t} { set a [rd1x $reg]; set b [rd1x $reg]; if {$a==$b} { return $a } }; return -1 }

w32 0x40013000 0x00001200 ; after 2
w32 0x40013018 0x00001FFF
set n 0
while {$n < 64 && ([srr] & 1) != 0} { mem2array z 8 0x40013030 1; incr n }
w32 0x40013000 0x00001201 ; after 2

echo [format "前置: WHO_AM_I=%d ACC_RANGE=%d GYR_RANGE=%d PWR_CTRL=%d" [rdcfg 0x01] [rdcfg 0x41] [rdcfg 0x43] [rdcfg 0x7D]]
echo ">>> 等你把板子【端稳不动】（陀螺连续 20 拍 < 3dps），然后连续记录 25 秒 <<<"

# 阶段 1：等静止（最多 8 分钟）
set tw [clock milliseconds]
set still 0
while {$still < 20} {
	set gx [rd16 0x12]; set gy [rd16 0x14]; set gz [rd16 0x16]
	set gm [expr {sqrt(double($gx*$gx+$gy*$gy+$gz*$gz))/16.384}]
	if {$gm < 3.0} { incr still } else { set still 0 }
	if {([clock milliseconds] - $tw) > 480000} { echo "!! 等 8 分钟没等到静止，退出"; break }
	after 250
}

echo "t(s) |    X       Y       Z      |a|码  | 陀螺(dps) gx/gy/gz"
set t0 [clock milliseconds]
while {1} {
	set el [expr {([clock milliseconds] - $t0)/1000.0}]
	if {$el > 25.0} { break }
	set ax [rd16 0x0C]; set ay [rd16 0x0E]; set az [rd16 0x10]
	set gx [expr {[rd16 0x12]/16.384}]
	set gy [expr {[rd16 0x14]/16.384}]
	set gz [expr {[rd16 0x16]/16.384}]
	set mag [expr {sqrt(double($ax*$ax+$ay*$ay+$az*$az))}]
	echo [format "%5.1f | %7d %7d %7d %7.0f | %6.2f %6.2f %6.2f" $el $ax $ay $az $mag $gx $gy $gz]
	after 200
}

w32 0x40013000 0x00001001
w32 0x58020418 0x00000010
echo "### HOLD-STEADY END ###"
resume
shutdown
