# watch-rotate.tcl —— ★ 60 秒连续记录：转动板子，看 |a| 到底恒不恒定、ACC_RANGE 会不会自己变
#
# 背景（两次独立测量互相矛盾）：
#   姿势 A 平放（重力在 Z）: |a| = 4694.6 码  ⇒ 若真实是 ±8g(4096码/g) 则 = 1.14 g
#   姿势 C 机头朝上(重力在 Y): |a| = 16837.8 码 ⇒ 若真实是 ±2g(16384码/g) 则 = 1.03 g
#   同一个 1g 却指向两个不同的满量程，**中间差 4 倍** ⇒ 必须查"满量程是不是在变"。
#
# 本脚本连续采 60s，每 250ms 打一行：
#   AR = ACC_RANGE(0x41) 回读（配置寄存器，配双读校验）
#   PD = PWR_CTRL(0x7D)
#   |a| = 三轴 H-first 原始码的模
#   g   = 三轴陀螺 (dps)
# 判读：
#   · |a| 在转动过程中**基本恒定** ⇒ 器件正常，之前两个数是我两次测量之间的状态差异
#   · |a| 明显随姿态变（几倍）      ⇒ 器件/读数真有问题
#   · AR 中途变了                    ⇒ 满量程被人改了（那就是根因）
#
# 用法：先启动本脚本，**在 60 秒里把板子慢慢转一圈**（平放 → 侧放 → 机头朝上 → 机头朝下 → 平放）
#       openocd -f watch-rotate.tcl

source [find interface/stlink.cfg]
transport select hla_swd
source [find target/stm32h7x_dual_bank.cfg]
adapter speed 1000
init
halt

echo "### WATCH BEGIN ###"

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

# 净化前奏（不碰 CFG1）
w32 0x40013000 0x00001200 ; after 2
w32 0x40013018 0x00001FFF
set n 0
while {$n < 64 && ([srr] & 1) != 0} { mem2array z 8 0x40013030 1; incr n }
w32 0x40013000 0x00001201 ; after 2

echo [format "前置: WHO_AM_I=%d  ACC_RANGE=%d  GYR_RANGE=%d  PWR_CTRL=%d" [rdcfg 0x01] [rdcfg 0x41] [rdcfg 0x43] [rdcfg 0x7D]]
echo ">>> 等你自己开始转：只要你把板子转起来（|陀螺| > 30 dps），就从那一刻起连续记录 60 秒 <<<"

# ── 阶段 1：等用户开始转动（最多等 10 分钟）──
set tw [clock milliseconds]
while {1} {
	set gm [expr {sqrt(double([rd16 0x12]*[rd16 0x12] + [rd16 0x14]*[rd16 0x14] + [rd16 0x16]*[rd16 0x16]))/16.384}]
	if {$gm > 30.0} { break }
	if {([clock milliseconds] - $tw) > 600000} { echo "!! 等 10 分钟没等到转动，退出"; break }
	after 300
}

echo "t(s) | AR  PD |   X      Y      Z     |a|   | gx     gy     gz  (dps)"

set t0 [clock milliseconds]
set k 0
while {1} {
	set el [expr {([clock milliseconds] - $t0) / 1000.0}]
	if {$el > 60.0} { break }

	set ax [rd16 0x0C]; set ay [rd16 0x0E]; set az [rd16 0x10]
	set gx [expr {[rd16 0x12]/16.384}]
	set gy [expr {[rd16 0x14]/16.384}]
	set gz [expr {[rd16 0x16]/16.384}]
	set mag [expr {sqrt(double($ax*$ax + $ay*$ay + $az*$az))}]

	# 每 8 次才回读一次配置寄存器（回读慢）
	if {($k % 8) == 0} {
		set ar [rdcfg 0x41]
		set pd [rdcfg 0x7D]
	} else {
		set ar "-"; set pd "-"
	}

	echo [format "%5.1f | %2s %2s | %6d %6d %6d %7.0f | %6.2f %6.2f %6.2f" \
		$el $ar $pd $ax $ay $az $mag $gx $gy $gz]
	incr k
	after 200
}

w32 0x40013000 0x00001001
w32 0x58020418 0x00000010
echo "### WATCH END ###"
resume
shutdown
