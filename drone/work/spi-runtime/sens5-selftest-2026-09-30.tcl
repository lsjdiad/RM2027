# sens5-selftest-2026-09-30.tcl —— 判决实验：区分「增益误差」与「零偏」
#
# 原理（不需要移动板子）：
#   ① 自测 Δ = P(正激励) − N(负激励) 是【差分】，天然免疫任何零偏 ⇒ Δ ∝ 真灵敏度 S
#   ② |a|(静止 1g) 含零偏
#   ③ 归一化 F = Δ / (2·|a|) 单位是 g，且【S 被约掉】⇒ F 反映的是自测力，不是灵敏度
#   ④ 关键：若某个配置只改"零偏"（比如关掉零偏补偿），|a| 会变但 Δ 不变
#         若只改"增益"，|a| 和 Δ 会同比例变
#      ⇒ 比较正常配置 vs ERR(ACC_CONF_ERR=1，读数翻倍的)配置的 |a| 与 Δ，一次定论
#   ⑤ 再用自测把输出打到饱和，看饱和码值是 ~32760（数字满量程=16bit）还是 ~18600
source [find interface/stlink.cfg]
transport select hla_swd
source [find target/stm32h7x_dual_bank.cfg]
adapter speed 1000
init
halt
source [file join [file dirname [info script]] spilib.tcl]
echo "### SENS5 BEGIN ###"
array set E {}
foreach r {0x40 0x41 0x42 0x43 0x45 0x08 0x7D 0x6D} { set E($r) [rd1 $r] }
echo "进入时: [readcfg]"

proc ameans {n} {
    set sx 0.0; set sy 0.0; set sz 0.0
    for {set i 0} {$i < $n} {incr i} {
        lassign [one] ax ay az gx gy gz
        set sx [expr {$sx+$ax}]; set sy [expr {$sy+$ay}]; set sz [expr {$sz+$az}]
        after 2
    }
    return [list [expr {$sx/$n}] [expr {$sy/$n}] [expr {$sz/$n}]]
}
proc maxabs {n} {
    set mx 0; set my 0; set mz 0
    for {set i 0} {$i < $n} {incr i} {
        lassign [one] ax ay az gx gy gz
        if {abs($ax) > $mx} { set mx [expr {abs($ax)}] }
        if {abs($ay) > $my} { set my [expr {abs($ay)}] }
        if {abs($az) > $mz} { set mz [expr {abs($az)}] }
        after 2
    }
    return [list $mx $my $mz]
}
# 一组自测：返回 {base|a| P|a| N|a| dx dy dz 饱和max}
proc sttest {n} {
    wr 0x6D 0x00; after 60
    set b [ameans $n]
    set mb [expr {sqrt([lindex $b 0]**2 + [lindex $b 1]**2 + [lindex $b 2]**2)}]
    wr 0x6D 0x09; after 60
    set n1 [ameans $n]
    set m1 [expr {sqrt([lindex $n1 0]**2 + [lindex $n1 1]**2 + [lindex $n1 2]**2)}]
    set mx1 [maxabs $n]
    wr 0x6D 0x0D; after 60
    set p1 [ameans $n]
    set m2 [expr {sqrt([lindex $p1 0]**2 + [lindex $p1 1]**2 + [lindex $p1 2]**2)}]
    set mx2 [maxabs $n]
    wr 0x6D 0x00; after 20
    set dx [expr {[lindex $p1 0]-[lindex $n1 0]}]
    set dy [expr {[lindex $p1 1]-[lindex $n1 1]}]
    set dz [expr {[lindex $p1 2]-[lindex $n1 2]}]
    return [list $mb $m1 $m2 $dx $dy $dz $mx1 $mx2]
}

echo ""
echo "== ① 正常配置 vs ERR 配置：|a| 与自测 Δ 对比 =="
foreach {conf tag} {0xAC "正常 0xAC(BWP010,ERR=0)" 0xCC "ERR 0xCC(BWP100,ERR=1)"} {
    wr 0x41 0x03
    wr 0x40 $conf
    set rb [rd1 0x40]
    set st [rd1 0x0B]
    after 50
    set r [sttest 8]
    set mb [lindex $r 0]; set m1 [lindex $r 1]; set m2 [lindex $r 2]
    set dx [lindex $r 3]; set dy [lindex $r 4]; set dz [lindex $r 5]
    echo [format "  %-26s 回读%02X ERR=%d  基线|a|=%7.1f  N|a|=%7.1f  P|a|=%7.1f" $tag $rb [expr {($st>>4)&1}] $mb $m1 $m2]
    echo [format "     自测 Δ = (%7.0f, %7.0f, %7.0f)  counts" $dx $dy $dz]
    echo [format "     F=Δ/(2·基线|a|) = (%.3f, %.3f, %.3f) g   ← 单位是 g，与灵敏度无关" \
        [expr {$dx/(2*$mb)}] [expr {$dy/(2*$mb)}] [expr {$dz/(2*$mb)}]]
    echo [format "     Δ/基线|a| 比 = (%.2f, %.2f, %.2f)   ← 若配置只是"去掉零偏"，这三个数不变" \
        [expr {$dx/$mb}] [expr {$dy/$mb}] [expr {$dz/$mb}]]
}

echo ""
echo "== ② 饱和扫描：正常配置下自测把输出打到饱和，看最大码值 =="
wr 0x40 0xAC
foreach r {0x00 0x01 0x02 0x03} {
    wr 0x41 $r
    set rb [rd1 0x41]
    after 30
    set b [ameans 5]
    set mb [expr {sqrt([lindex $b 0]**2 + [lindex $b 1]**2 + [lindex $b 2]**2)}]
    wr 0x6D 0x0D; after 60
    set mx [maxabs 8]
    wr 0x6D 0x00; after 20
    echo [format "  0x41=%02X(±%2dg)  基线|a|=%8.1f 自测正激励各轴最大码=(%6d,%6d,%6d)  理论满量程码=%6d" \
        $rb [expr {2 << $r}] $mb [lindex $mx 0] [lindex $mx 1] [lindex $mx 2] [expr {16384 >> $r}]]
}

echo ""
echo "== ③ ERR 配置下的量程阶梯（看 ERR 时是否还守 8:4:2:1）=="
wr 0x40 0xCC
foreach r {0x00 0x01 0x02 0x03} {
    wr 0x41 $r
    set rb [rd1 0x41]
    after 30
    set m [sample 12]
    echo [format "  0x41=%02X  |a|=%8.1f  手册应 %5d ⇒ ratio=%.4f" $rb [lindex $m 6] [expr {16384 >> $r}] [expr {[lindex $m 6]/double(16384 >> $r)}]]
}

foreach r {0x40 0x41 0x42 0x43 0x45 0x08 0x7D 0x6D} { wr $r $E($r); after 2 }
echo ""
echo "恢复后: [readcfg]"
show "恢复后" [sample 20]
echo "### SENS5 END ###"
resume
shutdown
