# fs-scan.tcl —— ★ 决定性实验：直接扫 ACC_RANGE(0x41) 四档，看量程到底生不生效
#
# 背景（`rawbyte-dump.tcl` 实测）：
#   板子平放、静止，加速度计原始码 X=47 Y=500 Z≈4637  ⇒ |a| ≈ 4664 码
#   而手册 §5.38 + 规格表说 FS=01(±4g) 应该是 8192 码/g，FS=10(±8g) 才是 4096 码/g。
#   ⇒ 4664 更像 ±8g（4096）而不是 ±4g（8192）。
#
# 本实验回答三个问题：
#   ① ACC_RANGE 写下去到底生不生效？（对比 GYR_CONF 那种"写了不生效"）
#   ② 生效的话，真实 FS 编码是什么？（00/01/10/11 各对应多少码/g）
#   ③ 生不生效跟 PWR_CTRL（ACC 开/关）有没有关系？（§5.39 那条备注的同类问题）
#
# 判读：板子必须**静止平放**，重力在 Z 轴上，Z 码值直接就是 1g 的码值。
#
# 用法： openocd -f fs-scan.tcl

source [find interface/stlink.cfg]
transport select hla_swd
source [find target/stm32h7x_dual_bank.cfg]
adapter speed 1000
init
halt

echo "### FS-SCAN BEGIN ###"

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
proc wr1 {reg val} { cslo; dr; xf $reg; xf $val; cshi; after 2 }
proc s16 {v} { if {$v > 32767} { return [expr {$v - 65536}] }; return $v }

proc zcount {} {
	# 读 3 遍取中位，压噪声
	set zs {}
	foreach i {1 2 3} {
		set h [rd1 0x10]; set l [rd1 0x11]
		lappend zs [s16 [expr {($h<<8) | $l}]]
		after 5
	}
	return [lindex [lsort -integer $zs] 1]
}

# --- 安全前奏 ---
w32 0x40013018 0x00001FFF
after 2

set who [rd1 0x01]
echo [format "WHO_AM_I=%02X  PWR_CTRL(0x7D)=%02X  ACC_CONF(0x40)=%02X  ACC_RANGE(0x41)=%02X" \
	$who [rd1 0x7D] [rd1 0x40] [rd1 0x41]]
echo [format "ACC 开时的 Z 码值基线 = %d" [zcount]]

echo ""
echo "== A) ACC 保持开启（PWR_CTRL=0x0E），直接改 ACC_RANGE =="
foreach fs {0x00 0x01 0x02 0x03} {
	wr1 0x41 $fs
	after 300
	set rb [rd1 0x41]
	set z [zcount]
	echo [format "  FS=0x%02X  回读 0x41=0x%02X  Z=%6d 码   (= 该档的 LSB/g，静止 1g)" $fs $rb $z]
}
echo "(判读：Z 应该随 FS 按 2 的幂次变化；若 Z 几乎不动 ⇒ ACC_RANGE 写下去不生效)"

echo ""
echo "== B) 关掉 ACC（PWR_CTRL=0x00）→ 写 FS → 再打开（0x0E），复现 §5.39 那条时序 =="
foreach fs {0x00 0x01 0x02 0x03} {
	wr1 0x7D 0x00
	after 20
	wr1 0x41 $fs
	after 20
	wr1 0x7D 0x0E
	after 300
	set rb [rd1 0x41]
	set z [zcount]
	echo [format "  FS=0x%02X  回读 0x41=0x%02X  Z=%6d 码" $fs $rb $z]
}

echo ""
echo "== C) 恢复驱动原本的配置（FS=0x01, PWR_CTRL=0x0E）=="
wr1 0x41 0x01
wr1 0x7D 0x0E
after 300
echo [format "  0x41=%02X  0x7D=%02X  Z=%d" [rd1 0x41] [rd1 0x7D] [zcount]]

# --- 收尾 ---
w32 0x40013000 0x00001001
w32 0x58020418 0x00000010
echo "### FS-SCAN END ###"
resume
shutdown
