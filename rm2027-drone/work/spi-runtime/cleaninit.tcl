# cleaninit.tcl —— 判定「静止 1g 只读到 ~1185 counts（手册应 2048）」是不是
#                  「初始化时序 / 量程重选」造成的配置半生效假象。
#
# 依据：华轩阳 HXY「ICM-42688P」手册
#   §5.45  0x7D 要先写 0x0E、延时 10ms，之后再做其它配置；配置完建议延时 1ms 再读
#   §5.39  GYR_NOISE_PERF 切换：先把 accel+gyro 关掉再配置，然后再打开
#   §5.37  非法 ODR/BWP 组合会自动回落到缺省 0xA8，并置 DATA_STAT.ACC_CONF_ERR=1
#   §5.8   DATA_STAT(0x0B)：B5 GYR_CONF_ERR / B4 ACC_CONF_ERR（可直接问芯片"配置生效了吗"）
#
# 判据：
#   某个组合下 |a| ≈ 2048 counts（ACC_RANGE=0x03） ⇒ 之前的 1185 是配置假象，
#                                                     驱动里的 1.7283 增益系数必须撤掉
#   所有组合都仍是 ~1185                        ⇒ 时序不是原因，回到"增益 vs 零偏"线
#
# 用法：openocd -f cleaninit.tcl
source [find interface/stlink.cfg]
transport select hla_swd
source [find target/stm32h7x_dual_bank.cfg]
adapter speed 1000
init
halt
echo "### CLEANINIT BEGIN ###"

proc srr {} { mem2array s 32 0x40013014 1; return $s(0) }
proc dr {} { set n 0; while {$n<16 && ([srr]&1)!=0} { mem2array z 8 0x40013030 1; incr n } }
proc xf {b} {
    mww 0x40013000 0x00001201
    mwb 0x40013020 $b
    set n 0
    while {$n < 20000} { if {([srr] & 1) != 0} { break }; incr n }
    mem2array v 8 0x40013030 1
    return $v(0)
}
proc cslo {} { mww 0x58020418 0x00100000 }
proc cshi {} { mww 0x58020418 0x00000010 }
proc burst {cmd n} { cslo; dr; xf $cmd; set s ""
    for {set i 0} {$i < $n} {incr i} { append s [format "%02X" [xf 0x00]] }
    cshi; return $s }
proc rd1 {reg} { return [h2i [burst [expr {$reg | 0x80}] 1]] }
proc h2i {h} { return [expr {"0x$h" + 0}] }
proc wr {reg val} { cslo; dr; xf $reg; xf $val; cshi }

# 取 N 个 12 字节样本，返回前 3 对的均值与 |a| 均值
proc sample {n} {
    set sx 0; set sy 0; set sz 0; set sm 0
    for {set i 0} {$i < $n} {incr i} {
        set h [burst 0x8C 12]
        set ax [s16 [string range $h 0 1] [string range $h 2 3]]
        set ay [s16 [string range $h 4 5] [string range $h 6 7]]
        set az [s16 [string range $h 8 9] [string range $h 10 11]]
        set sx [expr {$sx + $ax}]; set sy [expr {$sy + $ay}]; set sz [expr {$sz + $az}]
        set sm [expr {$sm + sqrt($ax*$ax + $ay*$ay + $az*$az)}]
        after 20
    }
    return [list [expr {$sx/double($n)}] [expr {$sy/double($n)}] [expr {$sz/double($n)}] [expr {$sm/double($n)}]]
}
proc s16 {hi lo} {
    set v [expr {"0x$hi" * 256 + "0x$lo"}]
    if {$v >= 32768} { set v [expr {$v - 65536}] }
    return $v
}
proc status {label} {
    set st [rd1 0x0B]
    echo [format "    0x0B(DATA_STAT)=0x%02X  GYR_CONF_ERR=%d ACC_CONF_ERR=%d DRDY_GYR=%d DRDY_ACC=%d" \
        $st [expr {($st>>5)&1}] [expr {($st>>4)&1}] [expr {($st>>1)&1}] [expr {$st&1}]]
    echo [format "    readback 0x40=%02X 0x41=%02X 0x42=%02X 0x43=%02X 0x7D=%02X" \
        [rd1 0x40] [rd1 0x41] [rd1 0x42] [rd1 0x43] [rd1 0x7D]]
}

# 顺序 A：模拟 PX4 现在的写法（一口气写完、不延时；且先写本片不存在的 0x7C）
proc initA {range gyrconf} {
    wr 0x7C 0x00; wr 0x7D 0x0E; wr 0x40 0xAC; wr 0x42 $gyrconf; wr 0x41 $range
    after 50
}
# 顺序 B：严格按手册（先关 → PWR_CTRL=0x0E +10ms → 各项配置各留 2ms → 再等 1ms 才读）
proc initB {range gyrconf} {
    wr 0x7D 0x00; after 10
    wr 0x7D 0x0E; after 10
    wr 0x40 0xAC; after 2
    wr 0x42 $gyrconf; after 2
    wr 0x41 $range; after 2
    after 5
}
# 顺序 C：手册顺序 + 先切到别的量程再切回来（测"重选量程"本身是否触发重新锁存）
proc initC {range gyrconf} {
    wr 0x7D 0x00; after 10
    wr 0x7D 0x0E; after 10
    wr 0x40 0xAC; after 2
    wr 0x41 0x00; after 2
    wr 0x42 $gyrconf; after 2
    wr 0x41 $range; after 2
    after 5
}

foreach cell {
    {A 0x00 0xEC} {A 0x02 0xEC} {A 0x03 0xEC}
    {B 0x00 0xEC} {B 0x02 0xEC} {B 0x03 0xEC}
    {B 0x03 0xAC} {C 0x03 0xEC} {C 0x00 0xEC}
} {
    lassign $cell seq range gyrconf
    if {$seq eq "A"} { initA $range $gyrconf }
    if {$seq eq "B"} { initB $range $gyrconf }
    if {$seq eq "C"} { initC $range $gyrconf }
    set m [sample 20]
    echo [format "顺序%s ACC_RANGE=%s GYR_CONF=%s → ACC均值=(%.1f, %.1f, %.1f)  |a|=%.1f counts" \
        $seq $range $gyrconf [lindex $m 0] [lindex $m 1] [lindex $m 2] [lindex $m 3]]
    status $seq
}

# ── 附加探针：用本片 FIFO 直接量【真实生效的 ODR】 ────────────────────────────
# 为什么重要：如果 ACC_CONF(0xAC)/GYR_CONF(0xEC) 其实没锁存进去（回读是影子），
# 芯片就还停在缺省 ACC 100Hz / GYR 200Hz，而驱动按 1kHz 轮询 ⇒ 会重复读同一个样本
# （EKF 看到 dt>0 而数值不变 = 虚假零角速度），比 1.73x 更致命。
# 手册 §5.16/§5.17：FIFO_CFG0(0x1C) B2 FIFO_ACC_EN / B1 FIFO_GYR_EN；
#                   FIFO_CFG1(0x1D) FM[1:0]：00=By-Pass、10=Stream；
#                   组数 FSS 在 FIFO_STAT0(0x1F) 低 4 位(高 4 位) + FIFO_STAT1(0x20)。
proc odrprobe {ms} {
    wr 0x1D 0x00            ;# 先回 By-Pass 清干净
    wr 0x1F 0x00
    wr 0x1C 0x06            ;# FIFO_ACC_EN | FIFO_GYR_EN（不带 header）
    wr 0x1D 0x20            ;# FM=10 Stream 模式
    after $ms
    set hi [rd1 0x1F]
    set lo [rd1 0x20]
    set groups [expr {(($hi & 0x0F) << 8) | $lo}]
    wr 0x1D 0x00            ;# 手册要求：读完切回 By-Pass
    return [list $groups $hi $lo]
}

echo ""
echo "-- 附加探针：FIFO 实测组速率（每 100ms 的组数；1600Hz 应≈160、100Hz≈10、200Hz≈20）--"
initB 0x03 0xEC
set r1 [odrprobe 100]
echo [format "  配置=手册顺序(0xAC/0xEC)    100ms 组数=%d  (0x1F=0x%02X 0x20=0x%02X)  ⇒ 估算 ODR≈%d Hz" \
    [lindex $r1 0] [lindex $r1 1] [lindex $r1 2] [expr {[lindex $r1 0] * 10}]]
set r2 [odrprobe 100]
echo [format "  同上，第二次取样             100ms 组数=%d                          ⇒ 估算 ODR≈%d Hz" \
    [lindex $r2 0] [expr {[lindex $r2 0] * 10}]]
initA 0x03 0xEC
set r3 [odrprobe 100]
echo [format "  配置=模拟 PX4 现写法          100ms 组数=%d                          ⇒ 估算 ODR≈%d Hz" \
    [lindex $r3 0] [expr {[lindex $r3 0] * 10}]]
echo "  （若组数明显小于 160 ⇒ ACC_CONF/GYR_CONF 没有真正锁存，ODR 还在缺省值）"

echo "-- 恢复 PX4 的配置（0x40=0xAC 0x41=0x03 0x42=0xEC 0x7D=0x0E）--"
initB 0x03 0xEC
echo "### CLEANINIT END ###"
resume
shutdown
