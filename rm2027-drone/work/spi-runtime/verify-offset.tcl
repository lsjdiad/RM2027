# 只读：核验 0x70~0x77（BMI270 ACC_OFF/GYR_OFF）与 0x7C
# 用逐寄存器单读，不用长突发（长突发会把读指针卡死，已踩过）
init
halt
echo "### VERIFY-OFFSET BEGIN ###"
proc srr {} { mem2array s 32 0x40013014 1; return $s(0) }
proc dr {} { set n 0; while {$n<16 && ([srr]&1)!=0} { mem2array z 8 0x40013030 1; incr n } }
proc xf {b} { mww 0x40013000 0x00001201; mwb 0x40013020 $b
    set n 0; while {$n<300} { if {([srr]&1)!=0} {break}; incr n }
    mem2array v 8 0x40013030 1; return $v(0) }
proc seq {bytes} { mww 0x58020418 0x00100000; dr; set o {}; foreach b $bytes { lappend o [xf $b] }; mww 0x58020418 0x00000010; return $o }
proc rd {reg} { return [lindex [seq [list [expr {$reg|0x80}] 0x00]] 1] }
echo [format "CHK 01=%02X 40=%02X 41=%02X 42=%02X 43=%02X 45=%02X 70=%02X 71=%02X 72=%02X 73=%02X 74=%02X 75=%02X 76=%02X 77=%02X 7C=%02X 7D=%02X" \
    [rd 0x01] [rd 0x40] [rd 0x41] [rd 0x42] [rd 0x43] [rd 0x45] [rd 0x70] [rd 0x71] [rd 0x72] [rd 0x73] [rd 0x74] [rd 0x75] [rd 0x76] [rd 0x77] [rd 0x7C] [rd 0x7D]]
resume
shutdown
