# rangetest.tcl —— 只读+受控写：判定 (a) 突发读字节对齐 (b) ACC_RANGE 是否真的改变灵敏度
source [find interface/stlink.cfg]
transport select hla_swd
source [find target/stm32h7x_dual_bank.cfg]
adapter speed 1000
init
halt
echo "### RANGETEST BEGIN ###"
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
proc burst {cmd n} {
    cslo; dr; xf $cmd
    set s ""
    for {set i 0} {$i < $n} {incr i} { append s [format "%02X" [xf 0x00]] }
    cshi
    return $s
}
proc rd1 {reg} { return [burst [expr {$reg | 0x80}] 1] }
proc wr {reg val} { cslo; dr; xf $reg; xf $val; cshi }
proc rddata {} { return [burst 0x8C 12] }

echo "-- 对齐检查：从 0x0C 读 12 字节 vs 从 0x0D 读 11 字节 vs 从 0x0E 读 10 字节 --"
echo "  A(0x0C,12) = [rddata]"
echo "  B(0x0D,11) = [burst 0x8D 11]"
echo "  C(0x0E,10) = [burst 0x8E 10]"
echo "  D(0x12,6)  = [burst 0x92 6]"

echo "-- 基线 ACC_RANGE(0x41)=[rd1 0x41]  ACC_CONF(0x40)=[rd1 0x40] --"
set i 0
for {set i 0} {$i < 5} {incr i} { echo "  base$i [rddata]" }

foreach r {0x00 0x01 0x02 0x03 0x04} {
    wr 0x41 $r
    after 250
    echo "-- 写 0x41=$r 后回读 0x41=[rd1 0x41] --"
    for {set i 0} {$i < 4} {incr i} { echo "  r$r.$i [rddata]" }
}

echo "-- 恢复 0x41=0x03 --"
wr 0x41 0x03
after 250
echo "  0x41=[rd1 0x41]  0x40=[rd1 0x40]  0x42=[rd1 0x42]  0x7D=[rd1 0x7D]"
echo "### RANGETEST END ###"
resume
shutdown
