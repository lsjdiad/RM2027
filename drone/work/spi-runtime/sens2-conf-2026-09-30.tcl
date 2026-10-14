# sens2-conf-2026-09-30.tcl —— 灵敏度 1.77 倍排查 · 第 2 步
#   ① 手册 §5.37 ACC_CONF 的 ACC_BWP[2:0] / ACC_ODR[3:0] / ACC_FILTER_PERF 逐组合
#   ② 只读：全寄存器图 0x00~0x7F（找手册没列的偏置/修调寄存器，如 BMI270 的 0x71~0x77）
#   每个组合：写 → 回读确认 → 等 30ms → 20 样本 → 打印 |a| 与"除以手册应有值"的比值
#   主量程用 ±16g(0x41=0x03)，与手册 ASo3=0.488mg/digit(2048 counts/g) 对齐
source [find interface/stlink.cfg]
transport select hla_swd
source [find target/stm32h7x_dual_bank.cfg]
adapter speed 1000
init
halt
source [file join [file dirname [info script]] spilib.tcl]
echo "### SENS2 BEGIN ###"

# ── 记录进入时配置，结束原样恢复 ────────────────────────────────────────────────
array set E {}
foreach r {0x40 0x41 0x42 0x43 0x45 0x08 0x7D} { set E($r) [rd1 $r] }
echo "进入时配置: [readcfg]"
echo "  （原样恢复用）0x40=$E(0x40) 0x41=$E(0x41) 0x42=$E(0x42) 0x43=$E(0x43) 0x45=$E(0x45) 0x08=$E(0x08) 0x7D=$E(0x7D)"

# ── ① 全寄存器图：先长突发(一次 CS 读 128 字节)，再逐寄存器单读，互相校验 ────────
echo ""
echo "== ①-a 长突发读 0x00~0x7F（一次 CS，128 字节，验地址自增）=="
set whole [burst 0x00 128]
for {set base 0} {$base <= 0x70} {incr base 16} {
    set line [format "B %02X:" $base]
    for {set i 0} {$i < 16} {incr i} {
        append line " [string range $whole [expr {($base+$i)*2}] [expr {($base+$i)*2+1}]]"
    }
    echo $line
}
echo "== ①-b 逐寄存器单读同一段（对照 a）=="
for {set base 0} {$base <= 0x70} {incr base 16} {
    set line [format "S %02X:" $base]
    for {set r $base} {$r < $base + 16} {incr r} { append line [format " %02X" [rd1 $r]] }
    echo $line
}

# ── ② ACC_CONF 扫描 ─────────────────────────────────────────────────────────────
wr 0x41 0x03
echo ""
echo [format "== ② 量程设为 ±16g：0x41 写03 回读%02X，手册应 2048 counts/g ==" [rd1 0x41]]
after 30

proc cfg {val tag exp} {
    wr 0x40 $val
    set rb [rd1 0x40]
    after 30
    set m [sample 20]
    set a [lindex $m 6]
    set st [rd1 0x0B]
    echo [format "  %-34s 写%02X 回读%02X  ACC_CONF_ERR=%d |a|=%7.1f  sd=%5.1f  counts/g=%.1f  比值(实测/手册)=%.4f" \
        $tag $val $rb [expr {($st>>4)&1}] $a [lindex $m 7] $a [expr {$a/$exp}]]
}

echo "-- ②-a 基线（PERF=1 BWP=010 NORM_AVG4 ODR=1600Hz）--"
cfg 0xAC "AC=BWP010/ODR-C(1600)" 2048

echo "-- ②-b ACC_BWP[2:0] 扫描（FILTER_PERF=1, ODR=0xC 固定）--"
cfg 0x8C "BWP=000 OSR4_AVG1" 2048
cfg 0x9C "BWP=001 OSR2_AVG2" 2048
cfg 0xAC "BWP=010 NORM_AVG4" 2048
cfg 0xBC "BWP=011 CIC_AVG8" 2048
echo "  （下面是手册说的 Reserved：高性能模式下非法，应回落 0xA8 且置 ACC_CONF_ERR=1）"
cfg 0xCC "BWP=100 RES_AVG16" 2048
cfg 0xDC "BWP=101 RES_AVG32" 2048
cfg 0xEC "BWP=110 RES_AVG64" 2048
cfg 0xFC "BWP=111 RES_AVG128" 2048

echo "-- ②-c ACC_ODR[3:0] 扫描（FILTER_PERF=1, BWP=010 固定；手册平均次数=1.6kHz/(ODR*4)）--"
cfg 0xA5 "ODR=0101 12.5Hz" 2048
cfg 0xA6 "ODR=0110 25Hz" 2048
cfg 0xA7 "ODR=0111 50Hz" 2048
cfg 0xA8 "ODR=1000 100Hz(缺省)" 2048
cfg 0xA9 "ODR=1001 200Hz" 2048
cfg 0xAA "ODR=1010 400Hz" 2048
cfg 0xAB "ODR=1011 800Hz" 2048
cfg 0xAC "ODR=1100 1600Hz" 2048

echo "-- ②-d ACC_FILTER_PERF=0（低功耗模式；LPM 最高 ODR=800Hz）--"
cfg 0x08 "PERF=0 BWP000 ODR=100Hz" 2048
cfg 0x0B "PERF=0 BWP000 ODR=800Hz" 2048
cfg 0x28 "PERF=0 BWP010 ODR=100Hz" 2048
cfg 0x2B "PERF=0 BWP010 ODR=800Hz" 2048
cfg 0x2C "PERF=0 BWP010 ODR=1600Hz(非法)" 2048

# ── 恢复 ───────────────────────────────────────────────────────────────────────
echo ""
foreach r {0x40 0x41 0x42 0x43 0x45 0x08 0x7D} { wr $r $E($r); after 2 }
echo "恢复后配置: [readcfg]"
show "恢复后 20 样本" [sample 20]
echo "### SENS2 END ###"
resume
shutdown
