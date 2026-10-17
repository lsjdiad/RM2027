# probe-deep.tcl —— 深度表征：自动增量块读 / 全量 R/W 图 / 计数器速率
# 全部可回退：写测试一律"先存原值 → 写 0x5A → 读 → 写 0xA5 → 读 → 还原原值"，末尾整片复读比对
init
halt
echo "### DEEP BEGIN ###"

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

# --- Phase A: 自动增量块读（单 CS 窗口，读 0x00 起 128 字节）---
csl; drain
xfer 0x80
set blk ""
for {set i 0} {$i < 128} {incr i} { append blk [format "%02x" [xfer 0x00]] }
csh
echo "BLOCKA $blk"

# --- Phase B: 逐地址 dump（与 A 对照，验证寻址线性）---
set pk1 ""
for {set r 0} {$r < 128} {incr r} { append pk1 [format "%02x" [rd $r]] }
echo "PK1 $pk1"

# --- Phase C: 计数器速率（用 openocd sleep 1000ms）---
proc ctr {} { return [expr {([rd 0x18] << 16) | ([rd 0x19] << 8) | [rd 0x1a]}] }
set c0 [ctr]
sleep 1000
set c1 [ctr]
echo [format {CTRRATE_MID c0=%d c1=%d delta=%d} $c0 $c1 [expr {$c1 - $c0}]]
set c2 [ctr]
sleep 2000
set c3 [ctr]
echo [format {CTRRATE_HIGH c2=%d c3=%d delta=%d} $c2 $c3 [expr {$c3 - $c2}]]

# --- Phase D: R/W 图（全 128 地址，可回退）---
echo "RWMAP_BEGIN addr orig w5a wA5 restored"
for {set r 0} {$r < 128} {incr r} {
    set orig [rd $r]
    wr $r 0x5A
    set w1 [rd $r]
    wr $r 0xA5
    set w2 [rd $r]
    wr $r $orig
    set back [rd $r]
    echo [format {RW %02x %02x %02x %02x %02x} $r $orig $w1 $w2 $back]
    if {($r % 16) == 15} {
        # 健康检查：0x01 与计数器是否还正常
        echo [format {HEALTH after %02x: r00=%02x r01=%02x ctr=%d} $r [rd 0x00] [rd 0x01] [ctr]]
    }
}
echo "RWMAP_END"

# --- Phase E: 末态整片复读（与 PK1 比对，验证"可回退"）---
set pk2 ""
for {set r 0} {$r < 128} {incr r} { append pk2 [format "%02x" [rd $r]] }
echo "PK2 $pk2"

# --- Phase F: 降速到 0.75MHz 再读一遍（对照）---
mww 0x40013000 0x00001000
mww 0x40013008 0x60070007
mww 0x40013000 0x00001001
set slow ""
for {set r 0} {$r < 128} {incr r} { append slow [format "%02x" [rd $r]] }
echo "SLOW $slow"
# 还原 24MHz
mww 0x40013000 0x00001000
mww 0x40013008 0x10070007
mww 0x40013000 0x00001001

mww 0x40013000 0x00001001
csh
echo "### DEEP END ###"
resume
shutdown
