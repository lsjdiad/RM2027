# datadump.tcl —— 只读：让板子静止，连续快速突发读 0x0C~0x17（一次 CS，保证同一采样）
# 输出每行一条：T<idx> <12 字节 hex> ST<3 字节 sensortime> R<acc_range> C<0x40> G<0x42> P<0x7D>
# 用法：openocd -f datadump.tcl   （CPU 处于 halted，PX4 不碰 SPI，芯片自己继续采样）
source [find interface/stlink.cfg]
transport select hla_swd
source [find target/stm32h7x_dual_bank.cfg]
adapter speed 1000
init
halt
echo "### DATADUMP BEGIN ###"
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

# 一次 CS 内突发读：先发命令字节，再连读 n 个字节，返回 hex
proc burst {cmd n} {
    cslo
    dr
    xf $cmd
    set s ""
    for {set i 0} {$i < $n} {incr i} { append s [format "%02X" [xf 0x00]] }
    cshi
    return $s
}
proc rd1 {reg} { return [burst [expr {$reg | 0x80}] 1] }

echo "ACC_RANGE(0x41)=[rd1 0x41]  ACC_CONF(0x40)=[rd1 0x40]  GYR_CONF(0x42)=[rd1 0x42]  PWR_CTRL(0x7D)=[rd1 0x7D]  PWR_CONF(0x7C)=[rd1 0x7C]  CHIP_ID(0x00)=[rd1 0x00]"

set N 64
for {set i 0} {$i < $N} {incr i} {
    set d [burst 0x8C 12]
    set st [burst 0x98 3]
    echo "T$i $d ST$st"
}

echo "--- 再取一组（间隔 50ms，看时间上的连续性）---"
for {set i 0} {$i < 20} {incr i} {
    set d [burst 0x8C 12]
    set st [burst 0x98 3]
    echo "S$i $d ST$st"
    after 50
}
echo "### DATADUMP END ###"
resume
shutdown
