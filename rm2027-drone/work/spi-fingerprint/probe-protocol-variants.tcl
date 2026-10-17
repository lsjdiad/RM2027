# probe-protocol-variants.tcl —— 判定"读命令的格式"是否真的对
# 目的：如果地址/读标志的假设错了，换几种格式读同一个地址应该能看出差别
# 全部只读（不写任何寄存器）；只做 SPI 读帧格式的对照

init
halt
echo "### PROTO-VARIANTS BEGIN ###"

proc srr {} { mem2array s 32 0x40013014 1; return $s(0) }
proc xfer {b} {
    mww 0x40013000 0x00001201
    mwb 0x40013020 $b
    set n 0
    while {$n < 20000} {
        if {([srr] & 1) != 0} { break }
        incr n
    }
    mem2array v 8 0x40013030 1
    return $v(0)
}
proc drain {} {
    set n 0
    while {$n < 16 && ([srr] & 1) != 0} { mem2array z 8 0x40013030 1; incr n }
    return $n
}
# 通用：发 1..4 字节，返回每一字节的收数
proc seq {bytes} {
    mww 0x58020418 0x00100000
    drain
    set out {}
    foreach b $bytes { lappend out [xfer $b] }
    mww 0x58020418 0x00000010
    return $out
}

echo "-- 地址 0x00 的多种读格式（每行: 发送字节 -> 收到字节）--"
echo "A: read-flag 0x80|0x00, dummy        : [seq [list 0x80 0x00]]"
echo "B: no-flag 0x00, dummy               : [seq [list 0x00 0x00]]"
echo "C: 0x80|0x00, dummy, extra dummy     : [seq [list 0x80 0x00 0x00]]"
echo "D: 0x00, 0x00, extra dummy           : [seq [list 0x00 0x00 0x00]]"
echo "E: 0x80|0x00, extra dummy x2         : [seq [list 0x80 0x00 0x00 0x00]]"

echo "-- 地址 0x0F 的多种读格式 --"
echo "A: 0x8F, dummy                       : [seq [list 0x8f 0x00]]"
echo "B: 0x0F, dummy                       : [seq [list 0x0f 0x00]]"
echo "C: 0x8F, dummy, dummy                : [seq [list 0x8f 0x00 0x00]]"

echo "-- 地址 0x75 的多种读格式（已知可写寄存器，作对照）--"
echo "A: 0xF5, dummy                       : [seq [list 0xf5 0x00]]"
echo "B: 0x75, dummy                       : [seq [list 0x75 0x00]]"

echo "-- 疑似的 24bit 计数器 0x18/0x19/0x1a：不同读法是否一致 --"
proc r3 {} { return [list [lindex [seq [list 0x98 0x00]] 1] [lindex [seq [list 0x99 0x00]] 1] [lindex [seq [list 0x9a 0x00]] 1]] }
for {set i 0} {$i < 6} {incr i} {
    set t [mem2array dummy 32 0x5C001004 1]
    echo "sample$i 18/19/1a = [r3]"
}

echo "-- 连续读 0x18 看低字节如何变（25 次）--"
set s ""
for {set i 0} {$i < 25} {incr i} { append s [format "%02x " [lindex [seq [list 0x98 0x00]] 1]] }
echo "0x18x25: $s"

mww 0x40013000 0x00001001
mww 0x58020418 0x00000010
echo "### PROTO-VARIANTS END ###"
resume
shutdown
