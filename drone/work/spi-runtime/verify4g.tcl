init
halt
echo "### V4G BEGIN ###"
proc srr {} { mem2array s 32 0x40013014 1; return $s(0) }
proc dr {} { set n 0; while {$n<16 && ([srr]&1)!=0} { mem2array z 8 0x40013030 1; incr n } }
proc xf {b} { mww 0x40013000 0x00001201; mwb 0x40013020 $b
    set n 0; while {$n<20000} { if {([srr]&1)!=0} {break}; incr n }
    mem2array v 8 0x40013030 1; return $v(0) }
proc seq {bytes} { mww 0x58020418 0x00100000; dr; set o {}; foreach b $bytes { lappend o [xf $b] }; mww 0x58020418 0x00000010; return $o }
proc rd {reg} { return [lindex [seq [list [expr {$reg|0x80}] 0x00]] 1] }
echo [format "REG 0x40=%02X 0x41=%02X 0x42=%02X 0x43=%02X 0x7D=%02X 0x0B=%02X" [rd 0x40] [rd 0x41] [rd 0x42] [rd 0x43] [rd 0x7D] [rd 0x0B]]
for {set i 0} {$i<20} {incr i} {
    set v [seq [list 0x8C 0 0 0 0 0 0 0 0 0 0 0 0]]
    set s ""; foreach x [lrange $v 1 12] { append s [format "%02X" $x] }
    echo "D $s"
}
echo "### V4G END ###"
resume
shutdown
