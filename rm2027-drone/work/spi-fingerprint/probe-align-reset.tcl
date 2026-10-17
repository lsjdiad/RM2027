# probe-align-reset.tcl —— 判定字节对齐 + 试探软复位寄存器
# 1) 对齐判定：给 0x75/0x76/0x77 写不同值，再多字节读，看值出现在第几个字节
# 2) 复位试探：往 0x7E 写 0xB6（BMI160/270 的 CMD.softreset）、往 0x60 写 0xB0（QMI8658A 的 RESET）
#    判据：24bit 计数器(0x18-0x1a) 是否重启（值突然变小）
init
halt
echo "### ALIGN-RESET BEGIN ###"

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
proc ctr {} { return [expr {([rd 0x18] << 16) | ([rd 0x19] << 8) | [rd 0x1a]}] }
proc dump {} {
    set s ""
    for {set r 0} {$r < 128} {incr r} { append s [format "%02x" [rd $r]] }
    return $s
}
# 发 N 个字节，返回收到的 N 个字节
proc seq {bytes} {
    csl; drain
    set out {}
    foreach b $bytes { lappend out [format "%02x" [xfer $b]] }
    csh
    return $out
}

echo "BASE [dump]"
echo "BASE_BEFORE [dump]"

# ---- 1) 对齐判定 ----
wr 0x75 0x11
wr 0x76 0x22
wr 0x77 0x33
echo "ALIGN seq(F5,00,00,00,00): [seq [list 0xF5 0x00 0x00 0x00 0x00]]  <- 无延迟应为 ff 11 22 33 xx"
echo "ALIGN seq(F5,00,00): [seq [list 0xF5 0x00 0x00]]"
echo "ALIGN rd75/76/77: [list [rd 0x75] [rd 0x76] [rd 0x77]]  <- 应为 11 22 33"
wr 0x75 0x00
wr 0x76 0x00
wr 0x77 0x00

# ---- 2) 复位试探：BMI160/270 CMD(0x7E)=0xB6 ----
set c0 [ctr]
wr 0x7e 0xB6
sleep 50
set c1 [ctr]
echo [format {RESET_BOSCH_0x7E_B6 ctr_before=%d ctr_after=%d} $c0 $c1]
sleep 300
echo "AFTER_BOSCH_RESET [dump]"

# ---- 3) 复位试探：QMI8658A RESET(0x60)=0xB0 ----
set c2 [ctr]
wr 0x60 0xB0
sleep 50
set c3 [ctr]
echo [format {RESET_QMI_0x60_B0 ctr_before=%d ctr_after=%d} $c2 $c3]
sleep 300
echo "AFTER_QMI_RESET [dump]"

# ---- 4) 再试 QMI8658A 另一种已知复位写法: CTRL9(0x0A) 写 0x00 后写 0xB0? 以及 0x60=0x5A ----
set c4 [ctr]
wr 0x60 0x5A
sleep 50
set c5 [ctr]
echo [format {RESET_0x60_5A ctr_before=%d ctr_after=%d} $c4 $c5]

mww 0x40013000 0x00001001
csh
echo "### ALIGN-RESET END ###"
resume
shutdown
