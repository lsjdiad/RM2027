init
halt
echo "### FIFODUMP BEGIN ###"
proc srr {} { mem2array s 32 0x40013014 1; return $s(0) }
proc dr {} { set n 0; while {$n<16 && ([srr]&1)!=0} { mem2array z 8 0x40013030 1; incr n } }
proc xf {b} { mww 0x40013000 0x00001201; mwb 0x40013020 $b
    set n 0; while {$n<20000} { if {([srr]&1)!=0} {break}; incr n }
    mem2array v 8 0x40013030 1; return $v(0) }
proc seq {bytes} { mww 0x58020418 0x00100000; dr; set o {}; foreach b $bytes { lappend o [xf $b] }; mww 0x58020418 0x00000010; return $o }
proc rd {reg} { return [lindex [seq [list [expr {$reg|0x80}] 0x00]] 1] }
proc wr {reg val} { mww 0x58020418 0x00100000; dr; xf $reg; xf $val; mww 0x58020418 0x00000010 }
proc fss {} { return [expr {(([rd 0x1F] & 0x0F) << 8) | [rd 0x20]}] }

# 1) 关掉两个传感器，把 ODR 都设成 100Hz
wr 0x7D 0x00
after 5
wr 0x42 0xE8          ;# GYR_CONF: FILTER_PERF=1 NOISE_PERF=1 BWP=10 ODR=1000(100Hz)
wr 0x7D 0x0E
after 15
wr 0x40 0xA8          ;# ACC_CONF: FILTER_PERF=1 BWP=010 ODR=1000(100Hz)
after 5
echo [format "低速配置: ACC_CONF=%02X GYR_CONF=%02X PWR_CTRL=%02X" [rd 0x40] [rd 0x42] [rd 0x7D]]
# 2) 开 FIFO（FIFO 模式 + 头码）
wr 0x1C 0x07
wr 0x1D 0x20
after 300
echo "灌入后 FSS=[fss]"
# 3) 抽干并 dump
for {set k 0} {$k < 16} {incr k} {
    set v [seq [list 0xA1 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0]]
    set d ""
    foreach x [lrange $v 1 24] { append d [format "%02X" $x] }
    set f [fss]
    echo "F $k $f $d"
}
# 4) 恢复
wr 0x1C 0x00; wr 0x1D 0x07
wr 0x7D 0x00
after 5
wr 0x42 0xEC
wr 0x7D 0x0E
after 15
wr 0x40 0xAC
after 5
echo [format "恢复后 ACC_CONF=%02X GYR_CONF=%02X PWR_CTRL=%02X FIFO_STAT0=%02X" [rd 0x40] [rd 0x42] [rd 0x7D] [rd 0x1F]]
echo "### FIFODUMP END ###"
resume
shutdown
