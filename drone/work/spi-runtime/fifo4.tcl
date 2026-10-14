init
halt
echo "### FIFO4 BEGIN ###"
proc srr {} { mem2array s 32 0x40013014 1; return $s(0) }
proc dr {} { set n 0; while {$n<16 && ([srr]&1)!=0} { mem2array z 8 0x40013030 1; incr n } }
proc xf {b} { mww 0x40013000 0x00001201; mwb 0x40013020 $b
    set n 0; while {$n<20000} { if {([srr]&1)!=0} {break}; incr n }
    mem2array v 8 0x40013030 1; return $v(0) }
proc seq {bytes} { mww 0x58020418 0x00100000; dr; set o {}; foreach b $bytes { lappend o [xf $b] }; mww 0x58020418 0x00000010; return $o }
proc wr {reg val} { mww 0x58020418 0x00100000; dr; xf $reg; xf $val; mww 0x58020418 0x00000010 }
# 一次 SWD 事务：读 0x18 起 3 字节 + 0x1F 起 2 字节
proc snap {} {
    set v [seq [list 0x98 0 0 0]]
    set t [expr {([lindex $v 1]<<16)|([lindex $v 2]<<8)|[lindex $v 3]}]
    set w [seq [list 0x9F 0 0]]
    set s0 [lindex $w 1]; set s1 [lindex $w 2]
    return [list $t [expr {(($s0 & 0x0F)<<8) | $s1}] $s0]
}
wr 0x1C 0x00; wr 0x1D 0x07       ;# 先关，清空
after 10
wr 0x1C 0x07; wr 0x1D 0x20       ;# FM=01 + HEADER_EN 开
echo "S1 [snap]"
echo "S2 [snap]"
echo "S3 [snap]"
echo "S4 [snap]"
wr 0x1C 0x00; wr 0x1D 0x07
echo "### FIFO4 END ###"
resume
shutdown
