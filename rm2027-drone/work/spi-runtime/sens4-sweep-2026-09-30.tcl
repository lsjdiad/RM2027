# sens4-sweep-2026-09-30.tcl —— 灵敏度排查 第 4 步（正式扫描版）
# 规矩：只用 ≤13 字节的突发（与 PX4 驱动同规模，不会卡住读指针）；绝不写 CR1=0
source [find interface/stlink.cfg]
transport select hla_swd
source [find target/stm32h7x_dual_bank.cfg]
adapter speed 1000
init
halt
source [file join [file dirname [info script]] spilib.tcl]
echo "### SENS4 BEGIN ###"
array set E {}
foreach r {0x40 0x41 0x42 0x43 0x45 0x08 0x7D} { set E($r) [rd1 $r] }
echo "进入时: [readcfg]"
w32 0x40013018 0x00001FFF
dr
echo "闸门: WHO_AM_I=[format %02X [rd1 0x01]]  (需 6A)"

echo ""
echo "== A. 0x70~0x7F 逆序读（验 0x71~0x73 的值是不是真绑在地址上）=="
set line "  逆序 "
for {set r 0x7F} {$r >= 0x70} {incr r -1} { append line [format "%02X " [rd1 $r]] }
echo $line
set line "  正序 "
for {set r 0x70} {$r <= 0x7F} {incr r} { append line [format "%02X " [rd1 $r]] }
echo $line

wr 0x41 0x03
after 30
echo ""
echo "== B. ACC_CONF 扫描（±16g，手册 2048 counts/g）=="
proc cfg {val tag {exp 2048}} {
    wr 0x40 $val
    set rb [rd1 0x40]
    after 30
    set m [sample 20]
    set a [lindex $m 6]
    set st [rd1 0x0B]
    echo [format "  %-30s 写%02X 回%02X ERR=%d |a|=%7.1f sd=%5.1f ratio=%.4f" \
        $tag $val $rb [expr {($st>>4)&1}] $a [lindex $m 7] [expr {$a/$exp}]]
}
cfg 0xAC "BWP010 ODR1600 (基线)"
cfg 0x8C "BWP000 OSR4_AVG1"
cfg 0x9C "BWP001 OSR2_AVG2"
cfg 0xAC "BWP010 NORM_AVG4"
cfg 0xBC "BWP011 CIC_AVG8"
echo "  -- 手册 Reserved（高功耗模式下非法）--"
cfg 0xCC "BWP100 RES_AVG16"
cfg 0xDC "BWP101 RES_AVG32"
cfg 0xEC "BWP110 RES_AVG64"
cfg 0xFC "BWP111 RES_AVG128"
echo "  -- ACC_ODR 扫描（BWP=010）--"
foreach o {0xA5 0xA6 0xA7 0xA8 0xA9 0xAA 0xAB 0xAC} {
    cfg $o [format "ODR=%X" [expr {$o & 0xF}]]
}
echo "  -- FILTER_PERF=0 低功耗 --"
cfg 0x08 "PERF0 BWP000 ODR100"
cfg 0x0B "PERF0 BWP000 ODR800"
cfg 0x28 "PERF0 BWP010 ODR100"
cfg 0x2B "PERF0 BWP010 ODR800"
cfg 0x2C "PERF0 BWP010 ODR1600(非法)"

echo ""
echo "== C. 0x08 HPF&LPF_CFG 扫描（BWP010 ODR1600 ±16g）=="
wr 0x40 0xAC
foreach v {0x80 0x00 0x40 0xC0 0x84 0x87 0xA0} {
    wr 0x08 $v
    set rb [rd1 0x08]
    after 30
    set m [sample 20]
    echo [format "  0x08 写%02X 回%02X  FDS=%d DLPF_EN=%d HPCF=%d  |a|=%7.1f ratio=%.4f" \
        $v $rb [expr {($v>>5)&1}] [expr {($v>>2)&1}] [expr {($v>>6)&3}] [lindex $m 6] [expr {[lindex $m 6]/2048.0}]]
}
# ★ HPF 判决：HP_RESET 后立刻连采样，看是否"先高后衰减"（若衰减 ⇒ 高通在吃 1g 直流）
echo "  -- ★ HPF 判决：写 0xB0(FDS=1+HP_RESET) 再 0xA0(FDS=1)，随后每 100ms 采一次，共 40 次 --"
wr 0x08 0xB0
wr 0x08 0xA0
set ser ""
for {set i 0} {$i < 40} {incr i} {
    set m [sample 3]
    append ser [format "%.0f " [lindex $m 6]]
    after 100
}
echo "  |a| 序列: $ser"
wr 0x08 0x80
after 30
show "  恢复 0x80 后" [sample 20]

echo ""
echo "== D. FIFO_DOWNS(0x45) 扫描（BWP010 ODR1600）=="
foreach v {0x88 0x00 0x07 0x80 0xFF} {
    wr 0x45 $v
    set rb [rd1 0x45]
    after 30
    set m [sample 20]
    echo [format "  0x45 写%02X 回%02X  |a|=%7.1f ratio=%.4f" $v $rb [lindex $m 6] [expr {[lindex $m 6]/2048.0}]]
}
wr 0x45 $E(0x45)

echo ""
echo "== E. 量程阶梯（每档 20 样本）=="
foreach r {0x00 0x01 0x02 0x03} {
    wr 0x41 $r
    set rb [rd1 0x41]
    after 30
    set m [sample 20]
    echo [format "  0x41 写%02X 回%02X  |a|=%8.1f  手册应 %5d counts/g ⇒ ratio=%.4f" \
        $r $rb [lindex $m 6] [expr {16384 >> $r}] [expr {[lindex $m 6]/double(16384 >> $r)}]]
}
echo ""
foreach r {0x40 0x41 0x42 0x43 0x45 0x08 0x7D} { wr $r $E($r); after 2 }
echo "恢复后: [readcfg]"
show "恢复后" [sample 20]
echo "### SENS4 END ###"
resume
shutdown
