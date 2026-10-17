init
halt
echo "### FIFO2 BEGIN ###"
proc srr {} { mem2array s 32 0x40013014 1; return $s(0) }
proc dr {} { set n 0; while {$n<16 && ([srr]&1)!=0} { mem2array z 8 0x40013030 1; incr n } }
proc xf {b} { mww 0x40013000 0x00001201; mwb 0x40013020 $b
    set n 0; while {$n<20000} { if {([srr]&1)!=0} {break}; incr n }
    mem2array v 8 0x40013030 1; return $v(0) }
proc seq {bytes} { mww 0x58020418 0x00100000; dr; set o {}; foreach b $bytes { lappend o [xf $b] }; mww 0x58020418 0x00000010; return $o }
proc rd {reg} { return [lindex [seq [list [expr {$reg|0x80}] 0x00]] 1] }
proc wr {reg val} { mww 0x58020418 0x00100000; dr; xf $reg; xf $val; mww 0x58020418 0x00000010 }
proc fss {} { return [expr {(([rd 0x1F] & 0x0F) << 8) | [rd 0x20]}] }
echo "--- 可写性测试（写 0x5A 回读）---"
foreach r {0x1C 0x1D 0x1E 0x1F 0x20 0x21} {
    set b [rd $r]; wr $r 0x5A; set a [rd $r]
    echo [format "  W %02X: %02X -> %02X" $r $b $a]
}
wr 0x1C 0x00; wr 0x1D 0x07; wr 0x1E 0xFF
echo "--- 重试 1: Stream(FM=10) + 阈值调小 ---"
wr 0x1C 0x06      ;# ACC_EN|GYR_EN
wr 0x1D 0x40      ;# FM=10, FTH[10:8]=0
wr 0x1E 0x20      ;# FTH[7:0]=0x20 -> 阈值 32 组
echo [format "  回读 1C=%02X 1D=%02X 1E=%02X" [rd 0x1C] [rd 0x1D] [rd 0x1E]]
after 30
echo [format "  t=30ms  STAT0=%02X STAT1=%02X FSS=%d" [rd 0x1F] [rd 0x20] [fss]]
after 50
echo [format "  t=80ms  STAT0=%02X STAT1=%02X FSS=%d" [rd 0x1F] [rd 0x20] [fss]]
echo "--- 重试 2: FIFO 模式(FM=01) + 头码开 ---"
wr 0x1C 0x07      ;# ACC_EN|GYR_EN|HEADER_EN
wr 0x1D 0x20      ;# FM=01
echo [format "  回读 1C=%02X 1D=%02X" [rd 0x1C] [rd 0x1D]]
after 50
echo [format "  t=50ms  STAT0=%02X STAT1=%02X FSS=%d" [rd 0x1F] [rd 0x20] [fss]]
after 50
echo [format "  t=100ms STAT0=%02X STAT1=%02X FSS=%d" [rd 0x1F] [rd 0x20] [fss]]
echo "--- 恢复 ---"
wr 0x1C 0x00; wr 0x1D 0x07; wr 0x1E 0xFF
echo [format "  恢复后 1C=%02X 1D=%02X 1E=%02X STAT0=%02X" [rd 0x1C] [rd 0x1D] [rd 0x1E] [rd 0x1F]]
echo "### FIFO2 END ###"
resume
shutdown
