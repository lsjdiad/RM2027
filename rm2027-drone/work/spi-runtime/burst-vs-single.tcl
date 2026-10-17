# burst-vs-single.tcl —— ★ 判死"突发解码错位"：同一对寄存器，两种读法对比
#
# 用户质疑："这真的不是你解码问题吗？是你左移右移位数的识别问题吗？"
#   ⇒ 直接对比：
#       A) 单寄存器原子读（cmd + 2 哑字节，取后两个）—— 与已验证可用的读法一致
#       B) 驱动用的 15 字节突发（cmd=0x8B + 14 哑字节），再按驱动的 transfer() 规则做"右移一格"
#   若 A 与 B 对同一对寄存器给出不同值 ⇒ **突发解码错位**（我的代码问题）。
#   若一致 ⇒ 芯片确实就输出那个值（不是我解码）。
#
# 同时也把 0x0B~0x18 的**完整字节流**打出来，肉眼可核。
#
# 用法： openocd -f burst-vs-single.tcl

source [find interface/stlink.cfg]
transport select hla_swd
source [find target/stm32h7x_dual_bank.cfg]
adapter speed 1000
init
halt

echo "### BURST-VS-SINGLE BEGIN ###"

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

# ---------- A) 单寄存器原子读 ----------
proc rd16_single {reg} {
	cslo; dr
	xf_ [expr {$reg | 0x80}]
	set hi [xf_ 0x00]
	set lo [xf_ 0x00]
	cshi
	return [s16 [expr {($hi<<8) | $lo}]]
}

# ---------- B) 驱动的 15 字节突发（0x8B + 14 哑字节）----------
# 返回 o[0..14]，o[k] = 第 k 个发送字节期间收到的字节
# 线上： [0x8B][0x0B][0x0C]...[0x18]   ⇒ o[1]=0x0B, o[2]=0x0C, ..., o[14]=0x18
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

foreach pass {1 2 3} {
	echo "---------- PASS $pass ----------"
	set o [burst15]

	# 完整字节流（用于肉眼核对）
	set hex ""
	foreach k {1 2 3 4 5 6 7 8 9 10 11 12 13 14} {
		append hex [format "%02X " [lindex $o $k]]
	}
	echo "  突发原始字节 o(1..14) = $hex"

	# 驱动口径： data[i] = o[i+1] ⇒ accel_x=data[1,2]=o[2,3]; y=o[4,5]; z=o[6,7]
	set bx [s16 [expr {([lindex $o 2]<<8) | [lindex $o 3]}]]
	set by [s16 [expr {([lindex $o 4]<<8) | [lindex $o 5]}]]
	set bz [s16 [expr {([lindex $o 6]<<8) | [lindex $o 7]}]]

	# 单读同三对寄存器
	set sx [rd16_single 0x0C]
	set sy [rd16_single 0x0E]
	set sz [rd16_single 0x10]

	echo [format "  突发读 : X=%7d  Y=%7d  Z=%7d   |a|=%7.0f" $bx $by $bz [expr {sqrt(double($bx*$bx+$by*$by+$bz*$bz))}]]
	echo [format "  单寄存器: X=%7d  Y=%7d  Z=%7d   |a|=%7.0f" $sx $sy $sz [expr {sqrt(double($sx*$sx+$sy*$sy+$sz*$sz))}]]
	echo [format "  差     : dX=%7d  dY=%7d  dZ=%7d   %s" \
		[expr {$bx-$sx}] [expr {$by-$sy}] [expr {$bz-$sz}] \
		[expr {($bx==$sx && $by==$sy && $bz==$sz) ? "一致 ✓" : "!! 不一致 ⇒ 突发解码有问题 !!"}]]
	after 80
}

echo ""
echo "判读: 三次都不一致 ⇒ 突发解码错位（我的代码问题）；三次都一致 ⇒ 芯片确实输出该值。"

w32 0x40013000 0x00001001
w32 0x58020418 0x00000010
echo "### BURST-VS-SINGLE END ###"
resume
shutdown
