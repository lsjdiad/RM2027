# sens3-conf2-2026-09-30.tcl —— 灵敏度排查 第 3 步（修正版）
#   · 只用逐寄存器单读（长突发已证明会把后续读搞乱）
#   · 每个组合：写 → 回读确认 → 等 30ms → 20 样本 → |a| 与 /手册应有值
#   · 开头有健全性闸门：基线不在合理区间就报警（防止在坏状态下继续解读数据）
source [find interface/stlink.cfg]
transport select hla_swd
source [find target/stm32h7x_dual_bank.cfg]
adapter speed 1000
init
halt
source [file join [file dirname [info script]] spilib.tcl]
echo "### SENS3 BEGIN ###"

array set E {}
foreach r {0x40 0x41 0x42 0x43 0x45 0x08 0x7D} { set E($r) [rd1 $r] }
echo "进入时配置: [readcfg]"

echo ""
echo "== 0. 健全性闸门 =="
for {set i 1} {$i <= 5} {incr i} {
    w32 0x40013018 0x00001FFF
    dr
    set who [rd1 0x01]
    if {$who == 0x6A} { break }
}
echo "  WHO_AM_I(0x01)=[format %02X $who]  (尝试 $i 次)"
show "  ±4g 基线" [sample 20]
set base4 [rd1 0x41]
echo "  ACC_RANGE(0x41)=[format %02X $base4]"

echo ""
echo "== 0b. 0x70~0x7F 连读 3 遍（验证 0x71~0x73 的非零值是真的、不是读串了）=="
for {set pass 1} {$pass <= 3} {incr pass} {
    set line [format "  P%d " $pass]
    for {set r 0x70} {$r <= 0x7F} {incr r} { append line [format "%02X " [rd1 $r]] }
    echo $line
    after 20
}

wr 0x41 0x03
echo ""
echo [format "== 1. 量程设为 ±16g：0x41 写03 回读%02X（手册 2048 counts/g）==" [rd1 0x41]]
after 30
proc cfg {val tag exp} {
    wr 0x40 $val
    set rb [rd1 0x40]
    after 30
    set m [sample 20]
    set a [lindex $m 6]
    set st [rd1 0x0B]
    echo [format "  %-32s 写%02X 回读%02X ERR=%d |a|=%7.1f sd=%5.1f counts/g=%.1f 实测/手册=%.4f" \
        $tag $val $rb [expr {($st>>4)&1}] $a [lindex $m 7] $a [expr {$a/$exp}]]
}
echo "-- a) 基线 --"
cfg 0xAC "PERF1 BWP010 NORM_AVG4 ODR1600" 2048
echo "-- b) ACC_BWP sweep (FILTER_PERF=1, ODR=0xC) --"
cfg 0x8C "BWP000 OSR4_AVG1" 2048
cfg 0x9C "BWP001 OSR2_AVG2" 2048
cfg 0xAC "BWP010 NORM_AVG4" 2048
cfg 0xBC "BWP011 CIC_AVG8" 2048
echo "-- b2) 手册说高性能模式下 Reserved 的 BWP（应回落 0xA8 且 ERR=1）--"
cfg 0xCC "BWP100 RES_AVG16" 2048
cfg 0xDC "BWP101 RES_AVG32" 2048
cfg 0xEC "BWP110 RES_AVG64" 2048
cfg 0xFC "BWP111 RES_AVG128" 2048
echo "-- c) ACC_ODR sweep (FILTER_PERF=1, BWP=010) --"
cfg 0xA5 "ODR 12.5Hz" 2048
cfg 0xA6 "ODR 25Hz" 2048
cfg 0xA7 "ODR 50Hz" 2048
cfg 0xA8 "ODR 100Hz (缺省)" 2048
cfg 0xA9 "ODR 200Hz" 2048
cfg 0xAA "ODR 400Hz" 2048
cfg 0xAB "ODR 800Hz" 2048
cfg 0xAC "ODR 1600Hz" 2048
echo "-- d) ACC_FILTER_PERF=0 低功耗模式 --"
cfg 0x08 "PERF0 BWP000 ODR100" 2048
cfg 0x0B "PERF0 BWP000 ODR800" 2048
cfg 0x28 "PERF0 BWP010 ODR100" 2048
cfg 0x2B "PERF0 BWP010 ODR800" 2048
cfg 0x2C "PERF0 BWP010 ODR1600(非法)" 2048
echo "-- e) 回到 ±4g 用最佳/基线再看一次（排除量程本身的影响）--"
wr 0x40 0xAC
wr 0x41 0x01
after 30
show "  ±4g PERF1 BWP010 ODR1600" [sample 20]
wr 0x40 0xA8
after 30
show "  ±4g PERF1 BWP010 ODR100" [sample 20]

echo ""
foreach r {0x40 0x41 0x42 0x43 0x45 0x08 0x7D} { wr $r $E($r); after 2 }
echo "恢复后配置: [readcfg]"
show "恢复后" [sample 20]
echo "### SENS3 END ###"
resume
shutdown
