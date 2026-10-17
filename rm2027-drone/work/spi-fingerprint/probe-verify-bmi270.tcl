# probe-verify-bmi270.tcl —— 收尾确认：BMI270 的配置上传寄存器是否可写 + ID 复查
init
halt
echo "### VERIFY-BMI270 BEGIN ###"
proc srr {} { mem2array s 32 0x40013014 1; return $s(0) }
proc xfer {b} {
    mww 0x40013000 0x00001201
    mwb 0x40013020 $b
    set n 0
    while {$n < 20000} { if {([srr] & 1) != 0} { break }; incr n }
    mem2array v 8 0x40013030 1
    return $v(0)
}
proc drain {} { set n 0; while {$n < 16 && ([srr] & 1) != 0} { mem2array z 8 0x40013030 1; incr n }; return $n }
proc csl {} { mww 0x58020418 0x00100000 }
proc csh {} { mww 0x58020418 0x00000010 }
proc rd {r} { csl; drain; xfer [expr {0x80|$r}]; set v [xfer 0x00]; csh; return $v }
proc wr {r val} { csl; drain; xfer [expr {$r & 0x7f}]; xfer $val; csh; return 0 }
proc rwtest {a} {
    set o [rd $a]
    wr $a 0x11
    set r1 [rd $a]
    wr $a 0x22
    set r2 [rd $a]
    wr $a $o
    set b [rd $a]
    echo [format {RWT %02x orig=%02x w11=%02x w22=%02x back=%02x} $a $o $r1 $r2 $b]
}
echo "--- BMI270 配置上传/控制寄存器 ---"
foreach a {0x59 0x5A 0x5B 0x5C 0x5E 0x46 0x47 0x48 0x49 0x53 0x54 0x58 0x6B 0x6D 0x6E 0x70 0x7C 0x7D} { rwtest $a }
echo "--- BMI270 CMD(0x7E) 是只写？---"
rwtest 0x7E
echo "--- ID 复查（含"先读一次做 CSB 上升沿"的驱动写法）---"
rd 0x00
echo [format {ID_AFTER_DUMMY 00=%02x 01=%02x 02=%02x 03=%02x 21=%02x} [rd 0x00] [rd 0x01] [rd 0x02] [rd 0x03] [rd 0x21]]
echo "--- ACC_CONF/GYR_CONF 复位值复查 ---"
echo [format {CONF 40=%02x 41=%02x 42=%02x 43=%02x 44=%02x 45=%02x} [rd 0x40] [rd 0x41] [rd 0x42] [rd 0x43] [rd 0x44] [rd 0x45]]
echo "--- INTERNAL_STATUS(0x21) 原始值 ---"
echo [format {INTERNAL_STATUS=%02x (BMI270: 0=not initialized,1=initialized,2=init err)} [rd 0x21]]
mww 0x40013000 0x00001001
csh
echo "### VERIFY-BMI270 END ###"
resume
shutdown
