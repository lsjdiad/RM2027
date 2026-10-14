# rawbyte-dump.tcl —— 读 HXY 芯片的**原始十六进制字节**（绕开驱动的标度/轴映射）
#
# 目的：一次定死三件事
#   ① 字节序：手册 §5.9~§5.14 写的是 H 在前（(H<<8)|L）；BMI270 家族是 L 在前
#   ② 轴映射：重力落在哪一对寄存器上（对比 H104 在同一姿态的 X）
#   ③ 真实 LSB/g：直接用原始码算，不经过驱动的 _scale
#
# 安全规矩（依据 `结论文档-器件身份与锁死真相.md` §3 + `cri-ab.tcl` 的 A/B）：
#   · **手工 GPIO 拉 CS ⇒ CR1 必须是 0x00001201**（bit9 SSM=1）；用 0x1001 会读出全 0x00
#   · 会话开头先清 IFCR（MODF/SUSP），否则读到陈旧 RXDR
#   · xf 轮询上限 300
#   · **不用长突发**（本目录踩过"长突发把芯片读指针卡死"的坑）⇒ 全部逐寄存器单读
#
# 用法： openocd -f rawbyte-dump.tcl

source [find interface/stlink.cfg]
transport select hla_swd
source [find target/stm32h7x_dual_bank.cfg]
adapter speed 1000
init
halt

echo "### RAWBYTE BEGIN ###"

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
proc s16r {v} { if {$v > 32767} { return [expr {$v - 65536}] }; return $v }

# --- 安全前奏 ---
w32 0x40013018 0x00001FFF
after 2

set who [rd1 0x01]
echo [format "SPI1 CR1=%08X   WHO_AM_I(0x01)=%02X %s" [r32 0x40013000] $who \
	[expr {$who == 0x6A ? "(OK)" : "(!! 不是 0x6A)"}]]

# --- 配置寄存器（驱动写的那些，用第三方读法复核）---
echo [format "CFG: 0x40=%02X  0x41=%02X  0x42=%02X  0x43=%02X  0x7D=%02X  0x08=%02X  0x05=%02X" \
	[rd1 0x40] [rd1 0x41] [rd1 0x42] [rd1 0x43] [rd1 0x7D] [rd1 0x08] [rd1 0x05]]

# --- 逐寄存器单读数据区 3 遍，看稳定性 ---
for {set pass 1} {$pass <= 3} {incr pass} {
	set b {}
	foreach r {0x0B 0x0C 0x0D 0x0E 0x0F 0x10 0x11 0x12 0x13 0x14 0x15 0x16 0x17} {
		lappend b [rd1 $r]
	}
	echo [format "PASS%d bytes: 0B=%02X | XH=%02X XL=%02X | YH=%02X YL=%02X | ZH=%02X ZL=%02X | GXH=%02X GXL=%02X GYH=%02X GYL=%02X GZH=%02X GZL=%02X" \
		$pass [lindex $b 0] [lindex $b 1] [lindex $b 2] [lindex $b 3] [lindex $b 4] \
		[lindex $b 5] [lindex $b 6] [lindex $b 7] [lindex $b 8] [lindex $b 9] [lindex $b 10] [lindex $b 11] [lindex $b 12]]

	set XH [lindex $b 1]; set XL [lindex $b 2]
	set YH [lindex $b 3]; set YL [lindex $b 4]
	set ZH [lindex $b 5]; set ZL [lindex $b 6]

	# 手册 §5.9~§5.14 口径：H 在前
	set axB [s16 [expr {($XH<<8) | $XL}]]
	set ayB [s16 [expr {($YH<<8) | $YL}]]
	set azB [s16 [expr {($ZH<<8) | $ZL}]]
	# BMI270 家族口径：L 在前
	set axL [s16 [expr {($XL<<8) | $XH}]]
	set ayL [s16 [expr {($YL<<8) | $YH}]]
	set azL [s16 [expr {($ZL<<8) | $ZH}]]

	echo [format "  H-first(手册): X=%6d Y=%6d Z=%6d" $axB $ayB $azB]
	echo [format "  L-first(BMI270): X=%6d Y=%6d Z=%6d" $axL $ayL $azL]
	after 60
}

# --- 收尾：CR1 交还固件侧配置 + CS 拉高 ---
w32 0x40013000 0x00001001
w32 0x58020418 0x00000010
echo "### RAWBYTE END ###"
resume
shutdown
