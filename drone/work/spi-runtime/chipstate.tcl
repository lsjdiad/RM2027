# 只读+可选 FIFO flush：看芯片在 PX4 停住时的真实状态
init
halt
echo "### CHIPSTATE BEGIN ###"
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
proc rd {reg} { return [lindex [seq2 [expr {$reg | 0x80}]] 0] }
proc seq2 {cmd} {
    mww 0x58020418 0x00100000
    dr
    set r [xf $cmd]
    set d [xf 0x00]
    mww 0x58020418 0x00000010
    return [list $d]
}
proc wr {reg val} {
    mww 0x58020418 0x00100000
    dr
    xf $reg
    xf $val
    mww 0x58020418 0x00000010
}
proc show {label regs} {
    set s ""
    foreach r $regs { append s [format "%02X=%02X " $r [rd $r]] }
    echo "$label $s"
}
echo "-- PX4 停住时芯片状态 --"
show "regs:" [list 0x00 0x21 0x22 0x23 0x24 0x25 0x26 0x40 0x42 0x48 0x49 0x7C 0x7D 0x7E]
set s ""
foreach r {0x0C 0x0D 0x0E 0x0F 0x10 0x11 0x12 0x13 0x14 0x15 0x16 0x17} { append s [format "%02X " [rd $r]] }
echo "DATA 0x0C-0x17: $s"
echo "-- flush FIFO (0x7E=0xB0) 后观察 0x24/0x25 是否增长 --"
wr 0x7E 0xB0
after 100
echo "t+0.1s  LEN=[rd 0x24] [rd 0x25]"
after 500
echo "t+0.6s  LEN=[rd 0x24] [rd 0x25]"
after 1000
echo "t+1.6s  LEN=[rd 0x24] [rd 0x25]"
echo "-- 再读一次配置寄存器（确认驱动写没落下去）--"
show "cfg:" [list 0x40 0x42 0x48 0x49 0x7C 0x7D]
mww 0x40013000 0x00001001
mww 0x58020418 0x00000010
echo "### CHIPSTATE END ###"
resume
shutdown
