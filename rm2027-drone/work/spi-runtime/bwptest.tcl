# bwptest.tcl —— 受控写 + 只读：扫描 ACC_CONF(0x40) 的 bwp 半字节 / ODR 半字节，
# 看"静止 1g"对应的原始码值是否随滤波配置改变（判定 ~1.73x 增益偏差是滤波伪影还是硅片增益）
source [find interface/stlink.cfg]
transport select hla_swd
source [find target/stm32h7x_dual_bank.cfg]
adapter speed 1000
init
halt
echo "### BWPTEST BEGIN ###"
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
proc burst {cmd n} { cslo; dr; xf $cmd; set s ""
    for {set i 0} {$i < $n} {incr i} { append s [format "%02X" [xf 0x00]] }
    cshi; return $s }
proc rd1 {reg} { return [burst [expr {$reg | 0x80}] 1] }
proc h2i {h} { return [expr {"0x$h" + 0}] }
proc wr {reg val} { cslo; dr; xf $reg; xf $val; cshi }
proc zval {} {
    # 返回 Z 轴原始码值（0x10=MSB,0x11=LSB），MSB-first
    set h [burst 0x8C 12]
    set msb [expr {[scan [string range $h 8 9] %x]}]
    set lsb [expr {[scan [string range $h 10 11] %x]}]
    set v [expr {($msb << 8) | $lsb}]
    if {$v >= 32768} { set v [expr {$v - 65536}] }
    return $v
}
proc avg3 {} { set s 0; for {set i 0} {$i < 3} {incr i} { set s [expr {$s + [zval]}] }; return [expr {$s / 3.0}] }

echo "基线: 0x40=[rd1 0x40]  0x41=[rd1 0x41]  Z均值=[avg3]"

echo "-- 扫描 ACC_CONF 高半字节 (bwp) 0x0..0xF，低半字节固定 0xC(ODR 1600Hz) --"
foreach u {0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15} {
    set val [expr {($u << 4) | 0x0C}]
    wr 0x40 $val
    after 200
    set rb [h2i [rd1 0x40]]
    set z1 [avg3]
    echo [format "  bwp=0x%X  write=0x%02X readback=0x%02X  Zavg=%s" $u $val $rb $z1]
}

echo "-- 扫描 ODR 半字节 0x0..0xF，高半字节固定 0xA --"
foreach o {0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15} {
    set val [expr {(0xA << 4) | $o}]
    wr 0x40 $val
    after 300
    set rb [h2i [rd1 0x40]]
    set z1 [avg3]
    echo [format "  odr=0x%X  write=0x%02X readback=0x%02X  Zavg=%s" $o $val $rb $z1]
}

echo "-- 恢复 0x40=0xAC --"
wr 0x40 0xAC
after 300
echo "  0x40=[rd1 0x40] 0x41=[rd1 0x41] 0x42=[rd1 0x42] 0x7D=[rd1 0x7D] Zavg=[avg3]"
echo "### BWPTEST END ###"
resume
shutdown
