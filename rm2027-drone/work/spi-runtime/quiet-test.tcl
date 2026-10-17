# quiet-test.tcl —— 验证"采集脏"的假说：halt 时 SPI1 可能还有 DMA/残留字节
#
# 发现（decode-proof.tcl）：静止板子上，陀螺 X 轴在 +253/−1/−255/+252/−4/0 之间跳
#   ⇒ 物理上不可能 ⇒ 是**读到的字节被污染**，不是解码错。
# 怀疑根因：PX4 的 SPI 走 DMA；halt CPU 时若正好有传输在飞，SPI 外设仍在把数据推进 RX FIFO，
#   或 FIFO 里残留着上一次的字节 ⇒ 我手工读到的流是错位的。
#
# 本脚本对比两种读法：
#   A) 老读法：cslo; dr; xf cmd; xf data; cshi        （不处理 DMA/残留）
#   B) 安静读法：先【停 SPE 但保持 SSI=1（SSM=1,SSI=1 ⇒ CR1=0x1200，绝不写 0）】，
#      清 DMA 使能 + 清 IFCR + 排空 RX FIFO，再开 SPE=1，然后才读；
#      并且**每个寄存器连读两次，两次不一致就重试**（最多 8 次），把"抖动"变成"可见"
#
# 用法： openocd -f quiet-test.tcl

source [find interface/stlink.cfg]
transport select hla_swd
source [find target/stm32h7x_dual_bank.cfg]
adapter speed 1000
init
halt

echo "### QUIET-TEST BEGIN ###"

proc r32 {a} { mem2array v 32 $a 1; return $v(0) }
proc w32 {a v} { mww $a $v }
proc srr {} { return [r32 0x40013014] }
proc dr {} { set n 0; while {$n<16 && ([srr]&1)!=0} { mem2array z 8 0x40013030 1; incr n } }
proc cslo {} { w32 0x58020418 0x00100000 }
proc cshi {} { w32 0x58020418 0x00000010 }

# ★ 安静前奏：不写 CR1=0（§3 的坑：SSM=1 时 SSI=0 会触发 MODF 打死 SPI1）
proc quiesce {} {
	# SSM=1(bit9) + SSI=1(bit12)，但 SPE=0(bit0) ⇒ 停下外设又不触发 MODF
	w32 0x40013000 0x00001200
	# 关掉 SPI 的 DMA 请求（CFG1 的 RXDMAEN/TXDMAEN，位 0/1）
	set cfg1 [r32 0x40013008]
	w32 0x40013008 [expr {$cfg1 & ~3}]
	after 2
	# 清所有标志（MODF/SUSP/OVR/...）
	w32 0x40013018 0x00001FFF
	# 排空 RX FIFO
	set n 0
	while {$n < 64 && ([srr] & 1) != 0} { mem2array z 8 0x40013030 1; incr n }
	# 重新上电（SPE=1）
	w32 0x40013000 0x00001201
	after 2
	return $n
}

proc xf_ {b} {
	w32 0x40013000 0x00001201
	mwb 0x40013020 $b
	set n 0
	while {$n<300} { if {([srr]&1)!=0} { break }; incr n }
	mem2array v 8 0x40013030 1
	return $v(0)
}

# A) 老读法
proc rd_old {reg} { cslo; dr; xf_ [expr {$reg | 0x80}]; set b [xf_ 0x00]; cshi; return $b }

# B) 安静 + 双读一致
proc rd_quiet {reg} {
	for {set t 0} {$t < 8} {incr t} {
		cslo
		dr
		xf_ [expr {$reg | 0x80}]
		set b1 [xf_ 0x00]
		# 再读一次（同一 CS 周期内把地址+数据再走一遍）
		xf_ [expr {$reg | 0x80}]
		set b2 [xf_ 0x00]
		cshi
		if {$b1 == $b2} { return [list $b1 $t] }
	}
	return [list -1 8]
}

proc s16 {v} { if {$v > 32767} { return [expr {$v - 65536}] }; return $v }

set drained [quiesce]
echo [format "安静前奏: 排空 RX FIFO %d 字节; CR1=%08X SR=%08X" $drained [r32 0x40013000] [r32 0x40013014]]

echo ""
echo "== A) 老读法（不安静、不双读）—— 应当复现 X 轴乱跳 =="
for {set k 1} {$k <= 6} {incr k} {
	set ax [s16 [expr {([rd_old 0x0C]<<8) | [rd_old 0x0D]}]]
	set ay [s16 [expr {([rd_old 0x0E]<<8) | [rd_old 0x0F]}]]
	set az [s16 [expr {([rd_old 0x10]<<8) | [rd_old 0x11]}]]
	set gx [s16 [expr {([rd_old 0x12]<<8) | [rd_old 0x13]}]]
	set gy [s16 [expr {([rd_old 0x14]<<8) | [rd_old 0x15]}]]
	set gz [s16 [expr {([rd_old 0x16]<<8) | [rd_old 0x17]}]]
	set mag [expr {sqrt(double($ax*$ax+$ay*$ay+$az*$az))}]
	set gmag [expr {sqrt(double($gx*$gx+$gy*$gy+$gz*$gz))/16.384}]
	echo [format "  %d: ACC(%6d %7d %6d) |a|=%6.0f   GYR(%5d %4d %4d) %6.2f dps" $k $ax $ay $az $mag $gx $gy $gz $gmag]
	after 40
}

echo ""
echo "== B) 安静 + 双读一致 —— 抖动应当消失 =="
set retries 0
for {set k 1} {$k <= 6} {incr k} {
	foreach {v t} [rd_quiet 0x0C] { set xh $v }; incr retries $t
	foreach {v t} [rd_quiet 0x0D] { set xl $v }; incr retries $t
	foreach {v t} [rd_quiet 0x0E] { set yh $v }; incr retries $t
	foreach {v t} [rd_quiet 0x0F] { set yl $v }; incr retries $t
	foreach {v t} [rd_quiet 0x10] { set zh $v }; incr retries $t
	foreach {v t} [rd_quiet 0x11] { set zl $v }; incr retries $t
	foreach {v t} [rd_quiet 0x12] { set gxh $v }; incr retries $t
	foreach {v t} [rd_quiet 0x13] { set gxl $v }; incr retries $t
	foreach {v t} [rd_quiet 0x14] { set gyh $v }; incr retries $t
	foreach {v t} [rd_quiet 0x15] { set gyl $v }; incr retries $t
	foreach {v t} [rd_quiet 0x16] { set gzh $v }; incr retries $t
	foreach {v t} [rd_quiet 0x17] { set gzl $v }; incr retries $t

	set ax [s16 [expr {($xh<<8) | $xl}]] ; set ay [s16 [expr {($yh<<8) | $yl}]] ; set az [s16 [expr {($zh<<8) | $zl}]]
	set gx [s16 [expr {($gxh<<8) | $gxl}]] ; set gy [s16 [expr {($gyh<<8) | $gyl}]] ; set gz [s16 [expr {($gzh<<8) | $gzl}]]
	set mag [expr {sqrt(double($ax*$ax+$ay*$ay+$az*$az))}]
	set gmag [expr {sqrt(double($gx*$gx+$gy*$gy+$gz*$gz))/16.384}]
	echo [format "  %d: ACC(%6d %7d %6d) |a|=%6.0f   GYR(%5d %4d %4d) %6.2f dps" $k $ax $ay $az $mag $gx $gy $gz $gmag]
	after 40
}
echo [format "双读总重试次数 = %d（0 = 每次两读都一致）" $retries]

w32 0x40013000 0x00001001
w32 0x58020418 0x00000010
echo "### QUIET-TEST END ###"
resume
shutdown
