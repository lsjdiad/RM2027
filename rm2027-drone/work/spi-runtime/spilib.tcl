# spilib.tcl —— 共用原语（被 sens*.tcl source）
# ★ 2026-10-01 教训：xf 的轮询上限从 20000 降到 300。
#   正常时 RXP 在第 0~1 次就置位；不置位说明【真的】没有响应，
#   20000 次轮询会让每个字节耗 ~10 秒，一个脚本能挂 10 分钟。
set ::POLLMAX 300
proc r32 {addr} { mem2array v 32 $addr 1; return $v(0) }
proc w32 {addr val} { mww $addr $val }
proc srr {} { return [r32 0x40013014] }
proc dr {} { set n 0; while {$n<16 && ([srr]&1)!=0} { mem2array z 8 0x40013030 1; incr n } }
proc xf {b} {
    w32 0x40013000 0x00001201
    mwb 0x40013020 $b
    set n 0
    while {$n < $::POLLMAX} { if {([srr] & 1) != 0} { break }; incr n }
    mem2array v 8 0x40013030 1
    return [list $v(0) $n]
}
proc xfv {b} { return [lindex [xf $b] 0] }
proc cslo {} { w32 0x58020418 0x00100000 }
proc cshi {} { w32 0x58020418 0x00000010 }
# 每次会话开头调用：清 IFCR（含 MODF bit9 / SUSP bit11）+ 确保 SPE|SSI=1
proc spi_resync {} {
    w32 0x40013018 0x00001FFF
    dr
    w32 0x40013000 0x00001001
    after 2
}
proc burst {cmd n} { cslo; dr; xfv $cmd; set s ""
    for {set i 0} {$i < $n} {incr i} { append s [format "%02X" [xfv 0x00]] }
    cshi; return $s }
proc h2i {h} { return [expr {"0x$h" + 0}] }
proc rd1 {reg} { return [h2i [burst [expr {$reg | 0x80}] 1]] }
proc wr {reg val} { cslo; dr; xfv $reg; xfv $val; cshi; after 1 }
proc s16 {hi lo} {
    set v [expr {"0x$hi" * 256 + "0x$lo"}]
    if {$v >= 32768} { set v [expr {$v - 65536}] }
    return $v
}
proc one {} {
    set h [burst 0x8C 12]
    return [list [s16 [string range $h 0 1] [string range $h 2 3]] \
                 [s16 [string range $h 4 5] [string range $h 6 7]] \
                 [s16 [string range $h 8 9] [string range $h 10 11]] \
                 [s16 [string range $h 12 13] [string range $h 14 15]] \
                 [s16 [string range $h 16 17] [string range $h 18 19]] \
                 [s16 [string range $h 20 21] [string range $h 22 23]]]
}
proc sample {n} {
    set sx 0.0; set sy 0.0; set sz 0.0
    set qx 0.0; set qy 0.0; set qz 0.0
    set sm 0.0; set qm 0.0
    for {set i 0} {$i < $n} {incr i} {
        lassign [one] ax ay az gx gy gz
        set sx [expr {$sx + $ax}]; set sy [expr {$sy + $ay}]; set sz [expr {$sz + $az}]
        set qx [expr {$qx + $ax*$ax}]; set qy [expr {$qy + $ay*$ay}]; set qz [expr {$qz + $az*$az}]
        set m [expr {sqrt(($ax*$ax + $ay*$ay + $az*$az) * 1.0)}]
        set sm [expr {$sm + $m}]; set qm [expr {$qm + $m*$m}]
        after 2
    }
    set dn [expr {$n * 1.0}]
    set sdx [expr {sqrt(($qx - $sx*$sx/$dn)/($dn-1) * 1.0)}]
    set sdy [expr {sqrt(($qy - $sy*$sy/$dn)/($dn-1) * 1.0)}]
    set sdz [expr {sqrt(($qz - $sz*$sz/$dn)/($dn-1) * 1.0)}]
    set sdm [expr {sqrt(($qm - $sm*$sm/$dn)/($dn-1) * 1.0)}]
    return [list [expr {$sx/$dn}] [expr {$sy/$dn}] [expr {$sz/$dn}] $sdx $sdy $sdz [expr {$sm/$dn}] $sdm]
}
proc show {tag m} {
    echo [format "%s mean=(%.1f, %.1f, %.1f) sd=(%.1f, %.1f, %.1f) |a|=%.1f sd|a|=%.1f" \
        $tag [lindex $m 0] [lindex $m 1] [lindex $m 2] [lindex $m 3] [lindex $m 4] [lindex $m 5] \
        [lindex $m 6] [lindex $m 7]]
}
proc readcfg {} {
    return [format "0x40=%02X 0x41=%02X 0x42=%02X 0x43=%02X 0x45=%02X 0x7D=%02X 0x0B=%02X 0x08=%02X 0x6D=%02X 0x0A=%02X" \
        [rd1 0x40] [rd1 0x41] [rd1 0x42] [rd1 0x43] [rd1 0x45] [rd1 0x7D] [rd1 0x0B] [rd1 0x08] [rd1 0x6D] [rd1 0x0A]]
}
