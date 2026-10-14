init
halt
echo "### ODR BEGIN ###"
proc srr {} { mem2array s 32 0x40013014 1; return $s(0) }
proc dr {} { set n 0; while {$n<16 && ([srr]&1)!=0} { mem2array z 8 0x40013030 1; incr n } }
proc xf {b} { mww 0x40013000 0x00001201; mwb 0x40013020 $b
    set n 0; while {$n<20000} { if {([srr]&1)!=0} {break}; incr n }
    mem2array v 8 0x40013030 1; return $v(0) }
proc seq {bytes} { mww 0x58020418 0x00100000; dr; set o {}; foreach b $bytes { lappend o [xf $b] }; mww 0x58020418 0x00000010; return $o }
proc rd {reg} { return [lindex [seq [list [expr {$reg|0x80}] 0x00]] 1] }
proc wr {reg val} { mww 0x58020418 0x00100000; dr; xf $reg; xf $val; mww 0x58020418 0x00000010 }
proc times {} { set v [seq [list 0x98 0x00 0x00 0x00]]; return [expr {([lindex $v 1]<<16)|([lindex $v 2]<<8)|[lindex $v 3]}] }
proc fss {} { return [expr {(([rd 0x1F] & 0x0F) << 8) | [rd 0x20]}] }

echo "--- A) SENSORTIME 增量粒度（>200 次快读）---"
echo "T [times]"
for {set i 0} {$i < 200} {incr i} { echo "T [times]" }
echo "--- B) FIFO Stream 模式下的真实数据率 ---"
echo "FIFOFG0(0x1C)=[format %02X [rd 0x1C]] FIFO_CFG1(0x1D)=[format %02X [rd 0x1D]] FSS=[fss]"
wr 0x1C 0x06          ;# ACC_EN | GYR_EN, 无头码
wr 0x1D 0x47          ;# FM=10 (Stream) + FTH[10:8]=111
after 5
set t0 [times]; set f0 [fss]
after 20
set t1 [times]; set f1 [fss]
after 20
set t2 [times]; set f2 [fss]
after 20
set t3 [times]; set f3 [fss]
echo "S1 [list $t0 $f0]"
echo "S2 [list $t1 $f1]"
echo "S3 [list $t2 $f2]"
echo "S4 [list $t3 $f3]"
wr 0x1C 0x00
wr 0x1D 0x07
echo "恢复 FIFO_CFG0=[format %02X [rd 0x1C]] FIFO_CFG1=[format %02X [rd 0x1D]] FSS=[fss]"
echo "### ODR END ###"
resume
shutdown
