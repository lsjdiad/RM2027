# measure-point.tcl —— ★ 干净的一次"单姿态测量"（用于平放/翻过来的差分法定标度）
#
# 为什么要它：`gain-scan.tcl` 用 |a| 定标度，而 |a| 会被**零偏污染**（零偏让 |a| 随姿态变）；
#   且 ST-Link 手工读曾被怀疑会脏（静止陀螺 X 跳到 ±253 码；|a| 两次 4678 vs 5200）。
#
# ── 三次踩坑记录（都写在这里，免得下次再踩）──────────────────────────────
#   ① **绝不要动 SPI1_CFG1 的 DMA 使能位（bit0/1）**。第一版清了没恢复 ⇒ 固件侧 SPI 坏掉，
#      之后读什么都恒为 0x1F（连 WHO_AM_I 都是），看着像"芯片挂了"，其实又是主机侧。
#      **恢复：`reset run`**，之后 WHO_AM_I=0x6A 立刻回来。
#   ② **"双读一致"不能用在数据寄存器上**。加速度计/陀螺 0x0C~0x17 是**活动数据**，
#      ODR=1600Hz 下两次读天生就不同 ⇒ 判据必然失败、retries 爆表、返回值全是垃圾。
#      双读一致只适用于**配置寄存器**（0x40/0x41/0x42/0x43/0x7D）。
#   ③ **一轴一次 CS 周期读 16 位**（发 cmd + 2 个哑字节，收 3 字节取后 2 个），
#      这才是原子的；分成两次单字节读更容易被中间更新撕开。
#
# 方法：板子**静止**（用"陀螺≈0"当静止门），单姿态采 N 个样本，报各轴均值/极差。
# 用法：
#     openocd -f measure-point.tcl          # 平放（Z 朝下）跑一次
#     ……把板子翻过来（Z 朝上）……
#     openocd -f measure-point.tcl          # 再跑一次
#   ⇒ S = (Z_down - Z_up) / 2   ← 真实 counts/g
#   ⇒ b = (Z_down + Z_up) / 2   ← 零偏（码）
#   ⚠️ 这里报的是**原始码**；驱动 publish 时 z 取了反（FLU→FRD），别混。

source [find interface/stlink.cfg]
transport select hla_swd
source [find target/stm32h7x_dual_bank.cfg]
adapter speed 1000
init
halt

echo "### MEASURE-POINT BEGIN ###"

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

# 净化前奏（⚠️ 不碰 CFG1）
proc quiesce {} {
	w32 0x40013000 0x00001200              ;# SPE=0, SSM=1, SSI=1  —— 绝不写 0
	after 2
	w32 0x40013018 0x00001FFF              ;# 清 MODF/SUSP/OVR/...
	set n 0
	while {$n < 64 && ([srr] & 1) != 0} { mem2array z 8 0x40013030 1; incr n }
	w32 0x40013000 0x00001201              ;# 重新开 SPE
	after 2
	return $n
}

# 单字节读（配置寄存器用，配双读校验）
proc rd1x {reg} { cslo; dr; xf_ [expr {$reg | 0x80}]; set b [xf_ 0x00]; cshi; return $b }

# 配置寄存器：两次独立 CS 周期，不一致就重试
proc rd_cfg {reg} {
	for {set t 0} {$t < 8} {incr t} {
		set b1 [rd1x $reg]
		set b2 [rd1x $reg]
		if {$b1 == $b2} { return $b1 }
	}
	return -1
}

# ★ 数据寄存器：**一次 CS 周期读 16 位**（cmd + 2 哑字节，收 3 字节，取第 2、3 个）
proc rd16 {reg} {
	cslo
	dr
	xf_ [expr {$reg | 0x80}]
	set hi [xf_ 0x00]
	set lo [xf_ 0x00]
	cshi
	return [s16 [expr {($hi<<8) | $lo}]]
}

set drained [quiesce]
echo [format "前置: 排空 %d 字节; WHO_AM_I=%d  ACC_RANGE=%d  GYR_RANGE=%d  PWR_CTRL=%d" \
	$drained [rd_cfg 0x01] [rd_cfg 0x41] [rd_cfg 0x43] [rd_cfg 0x7D]]

set N 64
set ax0 0; set ay0 0; set az0 0
set gx0 0; set gy0 0; set gz0 0
set n_ok 0; set n_moving 0
set axs {}; set ays {}; set azs {}

while {$n_ok < $N} {
	set ax [rd16 0x0C]
	set ay [rd16 0x0E]
	set az [rd16 0x10]
	set gx [rd16 0x12]
	set gy [rd16 0x14]
	set gz [rd16 0x16]

	# 静止门：|ω| < 3 dps 才采信
	set g2 [expr {double($gx*$gx + $gy*$gy + $gz*$gz)}]
	if {sqrt($g2) > 3.0 * 16.384} {
		incr n_moving
		if {$n_moving > 3000} { echo "!! 板子一直在动，放弃"; break }
		after 5
		continue
	}

	incr ax0 $ax; incr ay0 $ay; incr az0 $az
	incr gx0 $gx; incr gy0 $gy; incr gz0 $gz
	lappend axs $ax; lappend ays $ay; lappend azs $az
	incr n_ok
	after 3
}

if {$n_ok > 0} {
	set mx [expr {double($ax0)/$n_ok}]
	set my [expr {double($ay0)/$n_ok}]
	set mz [expr {double($az0)/$n_ok}]
	set amag [expr {sqrt($mx*$mx + $my*$my + $mz*$mz)}]
	set gmx [expr {double($gx0)/$n_ok/16.384}]
	set gmy [expr {double($gy0)/$n_ok/16.384}]
	set gmz [expr {double($gz0)/$n_ok/16.384}]
	set gmag [expr {sqrt($gmx*$gmx + $gmy*$gmy + $gmz*$gmz)}]

	# 各轴极差 —— 用来看读数有多干净
	set rx [expr {[lindex [lsort -integer $axs] end] - [lindex [lsort -integer $axs] 0]}]
	set ry [expr {[lindex [lsort -integer $ays] end] - [lindex [lsort -integer $ays] 0]}]
	set rz [expr {[lindex [lsort -integer $azs] end] - [lindex [lsort -integer $azs] 0]}]

	echo [format "POINT ok=%d moving=%d" $n_ok $n_moving]
	echo [format "POINT acc_raw X=%9.1f Y=%9.1f Z=%9.1f  abs=%9.1f   极差 X=%d Y=%d Z=%d" \
		$mx $my $mz $amag $rx $ry $rz]
	echo [format "POINT gyr_dps X=%7.3f Y=%7.3f Z=%7.3f  abs=%7.3f" $gmx $gmy $gmz $gmag]
	echo "POINT  (判读: moving 应≈0；极差 应是几十码量级(噪声)；gyr abs 应<1 dps；abs 应≈4650@±4g)"
}

w32 0x40013000 0x00001001
w32 0x58020418 0x00000010
echo "### MEASURE-POINT END ###"
resume
shutdown
