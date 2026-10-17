init
halt
echo "### PROBE2 BEGIN ###"
proc srr {} { mem2array s 32 0x40013014 1; return $s(0) }
proc dr {} { set n 0; while {$n<16 && ([srr]&1)!=0} { mem2array z 8 0x40013030 1; incr n } }
proc xf {b} { mww 0x40013000 0x00001201; mwb 0x40013020 $b
    set n 0; while {$n<20000} { if {([srr]&1)!=0} {break}; incr n }
    mem2array v 8 0x40013030 1; return $v(0) }
proc rd {reg} { mww 0x58020418 0x00100000; dr; xf [expr {$reg|0x80}]; set d [xf 0x00]; mww 0x58020418 0x00000010; return $d }
proc wr {reg val} { mww 0x58020418 0x00100000; dr; xf $reg; xf $val; mww 0x58020418 0x00000010 }
proc dump_data {} { set s ""; foreach r {0x0C 0x0D 0x0E 0x0F 0x10 0x11 0x12 0x13 0x14 0x15 0x16 0x17} { append s [format "%02X" [rd $r]] }; return $s }
echo "-- 数据寄存器 0x0C-0x17 是否在真实变化 --"
echo "  T0: [dump_data]"
after 300
echo "  T1: [dump_data]"
after 500
echo "  T2: [dump_data]"
after 700
echo "  T3: [dump_data]"
echo "-- 写可写性扫描（写 0x5A 后回读）--"
set out ""
foreach r {0x3C 0x3D 0x3E 0x3F 0x44 0x45 0x46 0x47 0x48 0x49 0x4A 0x4B 0x4C 0x4D 0x4E} {
    set before [rd $r]; wr $r 0x5A; set after [rd $r]
    append out [format "%02X:%02X->%02X " $r $before $after]
}
echo "  $out"
echo "-- 恢复 --"
wr 0x40 0xAC; wr 0x42 0xEC; wr 0x7D 0x0E
echo "  0x40=[rd 0x40] 0x42=[rd 0x42] 0x7D=[rd 0x7D]"
mww 0x40013000 0x00001001
mww 0x58020418 0x00000010
echo "### PROBE2 END ###"
resume
shutdown
