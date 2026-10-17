# sens1-scan-2026-10-01.tcl —— 灵敏度 1.7 倍排查 · 第 1 步：只读扫描 + 量程阶梯 + 读法自检
#
# 目的：
#   1) 把 0x00~0x7F 全寄存器读两遍 —— 找出手册没列出的、非零的、可写的寄存器
#      （重点：BMI270 在 0x71~0x77 有 ACC_OFFSET/GYR_OFFSET；华轩阳手册把 0x70~0x7C
#        整段列为保留 —— 如果这里有非零值，极可能就是"读数偏低"的真凶）
#   2) 复验四档量程 counts/g 阶梯（8:4:2:1）
#   3) 读法自检：0x0C/0x0D/0x0E 三个起点的突发窗口对齐；0x0A DATA_SAT
#   4) 基线 20 样本（均值 + sd + |a|），供后面所有组合对比
#
# 写入原则：本脚本【只写 0x41 ACC_RANGE】（手册 §5.38 明确给出该寄存器），
#   绝不碰 0x7C，也不碰手册未列出的 0x70~0x7C 段。
#   结束时把 0x41 恢复成进入时的值（PX4 当前是 0x01 ±4g）。
#
# 用法： openocd -f sens1-scan-2026-10-01.tcl   （本文件自带 interface/target 配置）
source [find interface/stlink.cfg]
transport select hla_swd
source [find target/stm32h7x_dual_bank.cfg]
adapter speed 1000
init
halt
echo "### SENS1 BEGIN ###"

# ── SPI1 裸驱动（沿用 verify4g.tcl / cleaninit.tcl 已验证可用的原语）──────────────
proc srr {} { mem2array s 32 0x40013014 1; return $s(0) }
proc dr {} { set n 0; while {$n<16 && ([srr]&1)!=0} { mem2array z 8 0x40013030 1; incr n } }
proc xf {b} {
    mww 0x40013000 0x00001201
    mwb 0x40013020 $b
    set n 0
    while {$n < 20000} { if {([srr] & 1) != 0} { break }; incr n }
    mem2array v 8 0x40013030 1
    return $v(0)
}
proc cslo {} { mww 0x58020418 0x00100000 }
proc cshi {} { mww 0x58020418 0x00000010 }
proc burst {cmd n} { cslo; dr; set s ""
    for {set i 0} {$i < $n} {incr i} { append s [format "%02X" [xf 0x00]] }
    cshi; return $s }
proc h2i {h} { return [expr {"0x$h" + 0}] }
proc rd1 {reg} { return [h2i [burst [expr {$reg | 0x80}] 1]] }
proc wr {reg val} { cslo; dr; xf $reg; xf $val; cshi }
proc s16 {hi lo} {
    set v [expr {"0x$hi" * 256 + "0x$lo"}]
    if {$v >= 32768} { set v [expr {$v - 65536}] }
    return $v
}
# 一次 12 字节突发，返回 {ax ay az gx gy gz}（高字节在前）
proc one {} {
    set h [burst 0x8C 12]
    return [list [s16 [string range $h 0 1] [string range $h 2 3]] \
                 [s16 [string range $h 4 5] [string range $h 6 7]] \
                 [s16 [string range $h 8 9] [string range $h 10 11]] \
                 [s16 [string range $h 12 13] [string range $h 14 15]] \
                 [s16 [string range $h 16 17] [string range $h 18 19]] \
                 [s16 [string range $h 20 21] [string range $h 22 23]]]
}
# N 个样本：返回 "meanX meanY meanZ sdX sdY sdZ mean|a| sd|a|"
proc sample {n} {
    set sx 0.0; set sy 0.0; set sz 0.0
    set qx 0.0; set qy 0.0; set qz 0.0
    set sm 0.0; set qm 0.0
    for {set i 0} {$i < $n} {incr i} {
        lassign [one] ax ay az gx gy gz
        set sx [expr {$sx + $ax}]; set sy [expr {$sy + $ay}]; set sz [expr {$sz + $az}]
        set qx [expr {$qx + $ax*$ax}]; set qy [expr {$qy + $ay*$ay}]; set qz [expr {$qz + $az*$az}]
        set m [expr {sqrt(double($ax*$ax + $ay*$ay + $az*$az))}]
        set sm [expr {$sm + $m}]; set qm [expr {$qm + $m*$m}]
        after 3
    }
    set dn [double($n)]
    set sdx [expr {sqrt(($qx - $sx*$sx/$dn)/($dn-1))}]
    set sdy [expr {sqrt(($qy - $sy*$sy/$dn)/($dn-1))}]
    set sdz [expr {sqrt(($qz - $sz*$sz/$dn)/($dn-1))}]
    set sdm [expr {sqrt(($qm - $sm*$sm/$dn)/($dn-1))}]
    return [list [expr {$sx/$dn}] [expr {$sy/$dn}] [expr {$sz/$dn}] $sdx $sdy $sdz [expr {$sm/$dn}] $sdm]
}
proc show {tag m} {
    echo [format "%s  mean=(%.1f, %.1f, %.1f)  sd=(%.1f, %.1f, %.1f)  |a|=%.1f  sd|a|=%.1f" \
        $tag [lindex $m 0] [lindex $m 1] [lindex $m 2] [lindex $m 3] [lindex $m 4] [lindex $m 5] \
        [lindex $m 6] [lindex $m 7]]
}

set range0 [rd1 0x41]
echo [format "== 0. 进入时的配置 == 0x40=%02X 0x41=%02X 0x42=%02X 0x43=%02X 0x45=%02X 0x7D=%02X 0x0B=%02X 0x08=%02X 0x6D=%02X" \
    [rd1 0x40] $range0 [rd1 0x42] [rd1 0x43] [rd1 0x45] [rd1 0x7D] [rd1 0x0B] [rd1 0x08] [rd1 0x6D]]

# ── 1. 全寄存器扫描两遍 ─────────────────────────────────────────────────────────
echo ""
echo "== 1. 全寄存器扫描 0x00~0x7F（PASS1 后间隔 200ms 再 PASS2；两遍不同的就是数据类寄存器）=="
for {set pass 1} {$pass <= 2} {incr pass} {
    for {set base 0} {$base <= 0x70} {incr base 16} {
        set line [format "P%d %02X:" $pass $base]
        for {set r $base} {$r < $base + 16} {incr r} {
            append line [format " %02X" [rd1 $r]]
        }
        echo $line
    }
    if {$pass == 1} { after 200 }
}

# ── 2. DATA_SAT(0x0A) 逐位解码 ──────────────────────────────────────────────────
set sat [rd1 0x0A]
echo [format "== 2. DATA_SAT(0x0A)=0x%02X  手册§5.7: B7 GYR_MEMS_OK, B6..B1 SAT_GYR_Z/Y/X SAT_ACC_Z/Y/X (1=未饱和) ==" $sat]
echo [format "   SAT_ACC_X=%d SAT_ACC_Y=%d SAT_ACC_Z=%d  SAT_GYR_X=%d SAT_GYR_Y=%d SAT_GYR_Z=%d  GYR_MEMS_OK=%d" \
    [expr {($sat>>1)&1}] [expr {($sat>>2)&1}] [expr {($sat>>3)&1}] \
    [expr {($sat>>4)&1}] [expr {($sat>>5)&1}] [expr {($sat>>6)&1}] [expr {($sat>>7)&1}]]

# ── 3. 基线 ────────────────────────────────────────────────────────────────────
echo ""
echo "== 3. 基线（进入时的配置，20 样本）=="
show "BASE" [sample 20]

# ── 4. 四档量程阶梯 ────────────────────────────────────────────────────────────
echo ""
echo "== 4. 量程阶梯（0x41 写入后回读确认；每档 20 样本）=="
foreach r {0x00 0x01 0x02 0x03} {
    wr 0x41 $r
    set rb [rd1 0x41]
    after 30
    set m [sample 20]
    set za [lindex $m 2]
    echo [format "  0x41 写%02X 回读%02X  |a|=%.1f  AZ=%.1f   若按手册±%sg 应有 %.0f counts/g ⇒ 比值 %.4f" \
        $r $rb [lindex $m 6] $za [expr {2 << $r}] [expr {16384 >> $r}] \
        [expr {[lindex $m 6] / double(16384 >> $r)}]]
}
wr 0x41 $range0
echo [format "  恢复 0x41=%02X（回读 %02X）" $range0 [rd1 0x41]]

# ── 5. 读法自检：突发窗口对齐 ──────────────────────────────────────────────────
echo ""
echo "== 5. 读法自检：从 0x0C / 0x0D / 0x0E / 0x10 各起一个突发窗口（同一次 CS 内多次调用，时刻接近）=="
# 把 0x41 设回 ±16g，让 1g 的码值不受量程影响地最大化信噪比
wr 0x41 0x03
after 30
set a [burst 0x8C 12]
set b [burst 0x8D 11]
set c [burst 0x8E 10]
set d [burst 0x90 8]
echo "  A(0x0C,12)=$a"
echo "  B(0x0D,11)=$b"
echo "  C(0x0E,10)=$c"
echo "  D(0x10, 8)=$d"
# 逐字节单点读（每次都重新发地址），与突发对比 —— 若两者一致 ⇒ 突发自增可信
set sb ""
for {set r 0x0C} {$r <= 0x17} {incr r} { append sb [format "%02X" [rd1 $r]] }
echo "  E(逐寄存器单读 0x0C..0x17)=$sb"
echo "  F(再次突发)=[burst 0x8C 12]"
wr 0x41 $range0

echo ""
echo "== 6. 结束前回读确认 =="
echo [format "  0x40=%02X 0x41=%02X 0x42=%02X 0x43=%02X 0x45=%02X 0x7D=%02X 0x08=%02X 0x6D=%02X" \
    [rd1 0x40] [rd1 0x41] [rd1 0x42] [rd1 0x43] [rd1 0x45] [rd1 0x7D] [rd1 0x08] [rd1 0x6D]]
echo "### SENS1 END ###"
resume
shutdown
