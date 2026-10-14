# cfgtest.tcl —— 受控写 + 只读：为 3 组候选配置各取 24 个完整 12 字节样本，比较灵敏度与噪声
source [find interface/stlink.cfg]
transport select hla_swd
source [find target/stm32h7x_dual_bank.cfg]
adapter speed 1000
init
halt
echo "### CFGTEST BEGIN ###"
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
proc wr {reg val} { cslo; dr; xf $reg; xf $val; cshi }

foreach cfg {{0xAC 0x03} {0x0C 0x03} {0x8C 0x03} {0xAC 0x02} {0x0C 0x00}} {
    lassign $cfg accconf accrange
    wr 0x40 $accconf; wr 0x41 $accrange; wr 0x7D 0x0E; wr 0x7C 0x00
    after 500
    echo [format "=== cfg 0x40=0x%02X 0x41=0x%02X  (readback 0x40=%s 0x41=%s 0x7D=%s) ===" \
        $accconf $accrange [rd1 0x40] [rd1 0x41] [rd1 0x7D]]
    for {set i 0} {$i < 24} {incr i} {
        echo "  D$i [burst 0x8C 12]"
        after 20
    }
}

echo "-- 恢复 PX4 配置 0x40=0xAC 0x41=0x03 --"
wr 0x40 0xAC; wr 0x41 0x03
after 300
echo "  0x40=[rd1 0x40] 0x41=[rd1 0x41] 0x42=[rd1 0x42] 0x7D=[rd1 0x7D] 0x7C=[rd1 0x7C]"
echo "### CFGTEST END ###"
resume
shutdown
