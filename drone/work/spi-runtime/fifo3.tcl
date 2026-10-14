init
halt
echo "### FIFO3 BEGIN ###"
proc srr {} { mem2array s 32 0x40013014 1; return $s(0) }
proc dr {} { set n 0; while {$n<16 && ([srr]&1)!=0} { mem2array z 8 0x40013030 1; incr n } }
proc xf {b} { mww 0x40013000 0x00001201; mwb 0x40013020 $b
    set n 0; while {$n<20000} { if {([srr]&1)!=0} {break}; incr n }
    mem2array v 8 0x40013030 1; return $v(0) }
proc seq {bytes} { mww 0x58020418 0x00100000; dr; set o {}; foreach b $bytes { lappend o [xf $b] }; mww 0x58020418 0x00000010; return $o }
proc rd {reg} { return [lindex [seq [list [expr {$reg|0x80}] 0x00]] 1] }
proc wr {reg val} { mww 0x58020418 0x00100000; dr; xf $reg; xf $val; mww 0x58020418 0x00000010 }
proc fss {} { return [expr {(([rd 0x1F] & 0x0F) << 8) | [rd 0x20]}] }
proc times {} { set v [seq [list 0x98 0x00 0x00 0x00]]; return [expr {([lindex $v 1]<<16)|([lindex $v 2]<<8)|[lindex $v 3]}] }

# 开 FIFO 模式 + 头码
wr 0x1C 0x07
wr 0x1D 0x20
echo [format "1C=%02X 1D=%02X 1E=%02X" [rd 0x1C] [rd 0x1D] [rd 0x1E]]

echo "-- 测 A：速率（用 SENSORTIME 计精确时间）--"
after 60
set ta [times]; set fa [fss]
after 60
set tb [times]; set fb [fss]
after 60
set tc [times]; set fc [fss]
echo "A1 [list $ta $fa]"
echo "A2 [list $tb $fb]"
echo "A3 [list $tc $fc]"

echo "-- 测 B：FSS 的单位（读一批 FIFO_DATA 看 FSS 掉多少）--"
set f0 [fss]
set v [seq [list 0xA1 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0]]
set d ""
foreach x [lrange $v 1 24] { append d [format "%02X" $x] }
set f1 [fss]
echo "B_read24 [list $f0 $f1]"
echo "B_data $d"
# 再读一批
set v2 [seq [list 0xA1 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0]]
set d2 ""
foreach x [lrange $v2 1 24] { append d2 [format "%02X" $x] }
set f2 [fss]
echo "B_read24b [list $f1 $f2]"
echo "B_data2 $d2"
# 清空
set n 0
while {[fss] > 0 && $n < 60} { seq [list 0xA1 0 0 0 0 0 0 0 0 0 0 0 0]; incr n }
echo "flush_done fss=[fss] loops=$n"
wr 0x1C 0x00; wr 0x1D 0x07
echo [format "恢复后 1C=%02X 1D=%02X STAT0=%02X" [rd 0x1C] [rd 0x1D] [rd 0x1F]]
echo "### FIFO3 END ###"
resume
shutdown
