# 对照厂商手册读一遍活芯片（CPU halted，手工驱动 SPI1）
init
halt
echo "### READBACK BEGIN ###"
proc srr {} { mem2array s 32 0x40013014 1; return $s(0) }
proc dr {} { set n 0; while {$n<16 && ([srr]&1)!=0} { mem2array z 8 0x40013030 1; incr n } }
proc xf {b} { mww 0x40013000 0x00001201; mwb 0x40013020 $b
    set n 0; while {$n<20000} { if {([srr]&1)!=0} {break}; incr n }
    mem2array v 8 0x40013030 1; return $v(0) }
proc seq {bytes} { mww 0x58020418 0x00100000; dr; set o {}; foreach b $bytes { lappend o [xf $b] }; mww 0x58020418 0x00000010; return $o }
proc rd {reg} { return [lindex [seq [list [expr {$reg|0x80}] 0x00]] 1] }
echo "-- 配置寄存器 --"
set cfgregs {0x01 0x02 0x03 0x05 0x08 0x0B 0x1C 0x1D 0x1E 0x1F 0x20 0x22 0x23 0x40 0x41 0x42 0x43 0x45 0x4A 0x6D 0x6F 0x7D 0x7F}
set line ""
foreach r $cfgregs { append line [format "%02X " [rd $r]] }
echo "CFG $line"
echo "-- 数据 0x0C~0x17 连续 24 次（每次一个 CS 窗口突发读 12 字节）--"
for {set i 0} {$i < 24} {incr i} {
    set v [seq [list 0x8C 0 0 0 0 0 0 0 0 0 0 0 0]]
    set s ""
    foreach x [lrange $v 1 12] { append s [format "%02X" $x] }
    echo "D $s"
}
echo "### READBACK END ###"
resume
shutdown
