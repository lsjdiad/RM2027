init
halt
echo "### FIFOTEST BEGIN ###"
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
proc rd {reg} {
    mww 0x58020418 0x00100000
    dr
    xf [expr {$reg | 0x80}]
    set d [xf 0x00]
    mww 0x58020418 0x00000010
    return $d
}
proc wr {reg val} {
    mww 0x58020418 0x00100000
    dr
    xf $reg
    xf $val
    mww 0x58020418 0x00000010
}
echo "--- 写前 ---"
echo "  0x40=[rd 0x40] 0x48=[rd 0x48] 0x49=[rd 0x49] 0x7D=[rd 0x7D]"
echo "--- 对照：写 0x40=0xA8（已知可写）---"
wr 0x40 0xA8
echo "  0x40 回读 = [rd 0x40]"
echo "--- 写 FIFO_CONFIG_0(0x48)=0x03 ---"
wr 0x48 0x03
echo "  0x48 回读 = [rd 0x48]"
echo "--- 写 FIFO_CONFIG_1(0x49)=0xD0 ---"
wr 0x49 0xD0
echo "  0x49 回读 = [rd 0x49]"
echo "--- flush + 观察 FIFO_LENGTH ---"
wr 0x7E 0xB0
after 200
echo "  t+0.2s  LEN0=[rd 0x24] LEN1=[rd 0x25]"
after 1000
echo "  t+1.2s  LEN0=[rd 0x24] LEN1=[rd 0x25]"
after 1000
echo "  t+2.2s  LEN0=[rd 0x24] LEN1=[rd 0x25]"
echo "--- 恢复 0x40 ---"
wr 0x40 0xAC
mww 0x40013000 0x00001001
echo "### FIFOTEST END ###"
resume
shutdown
