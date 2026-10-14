# probe-bosch-test.tcl —— 功能测试：这颗片子是不是 Bosch BMI 家族（BMI270/BMI160）？
# 判据：按 BMI270 的 PWR_CONF/PWR_CTRL/PWR_CTRL 序列开传感器后，
#       数据寄存器（BMI270: 0x0C..0x17 = DATA_0..DATA_11）是否出现"活数据"
#       另试 BMI160 的 CMD(0x7E) 模式开法
# 可回退：所有写都是"先存原值，末尾还原"
init
halt
echo "### BOSCH-TEST BEGIN ###"

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
proc seq {bytes} {
    csl; drain
    set out {}
    foreach b $bytes { lappend out [format "%02x" [xfer $b]] }
    csh
    return $out
}
proc blob {a n} { set s ""; for {set i 0} {$i < $n} {incr i} { append s [format "%02x" [rd [expr {$a+$i}]]] }; return $s }
proc watch {a n k} { for {set i 0} {$i < $k} {incr i} { echo [format {WATCH %02x+%d %s} $a $n [blob $a $n]] } }


echo "CHIPIDHUNT rd00 x3: [list [rd 0x00] [rd 0x00] [rd 0x00]]"
echo "CHIPIDSEQ2: [seq [list 0x80 0x00]]"
echo "CHIPIDSEQ6: [seq [list 0x80 0x00 0x00 0x00 0x00 0x00]]"
echo "CHIPID_FROM01: [seq [list 0x81 0x00 0x00 0x00]]"
echo "BMI270_STATUS: 00=[rd 0x00] 02=[rd 0x02] 03=[rd 0x03] 21(INTERNAL_STATUS)=[rd 0x21] 22=[rd 0x22] 23=[rd 0x23] 24=[rd 0x24] 25=[rd 0x25]"
echo "BMI270_IDCOORDS: 0B=[rd 0x0b] 1C=[rd 0x1c] 1D=[rd 0x1d] 1E=[rd 0x1e] 1F=[rd 0x1f] 3A=[rd 0x3a] 52=[rd 0x52] 6B=[rd 0x6b] 6C=[rd 0x6c] 70=[rd 0x70]"

echo "MAP_RICH [blob 0x00 0x50]"
echo "MAP_RICH2 [blob 0x50 0x30]"

# 先备份我们将要改的寄存器
set o40 [rd 0x40]; set o41 [rd 0x41]; set o42 [rd 0x42]; set o43 [rd 0x43]
set o7c [rd 0x7c]; set o7d [rd 0x7d]; set o7e [rd 0x7e]
echo [format {BACKUP 40=%02x 41=%02x 42=%02x 43=%02x 7c=%02x 7d=%02x 7e=%02x} $o40 $o41 $o42 $o43 $o7c $o7d $o7e]

echo "=== 试 BMI270 序列 ==="
wr 0x7c 0x00
wr 0x7d 0x02
wr 0x40 0xA8
wr 0x41 0x02
wr 0x42 0xA9
wr 0x43 0x00
wr 0x7d 0x0E
sleep 200
echo "BMI270_READBACK 40=[rd 0x40] 41=[rd 0x41] 42=[rd 0x42] 43=[rd 0x43] 7c=[rd 0x7c] 7d=[rd 0x7d]"
watch 0x0c 12 4
echo "BMI270_TEMP 22=[rd 0x22] 23=[rd 0x23] 24=[rd 0x24] 25=[rd 0x25] 26=[rd 0x26]"
watch 0x18 3 3

echo "=== 试 BMI160 序列 (CMD 0x7E: 0x11=acc normal, 0x15=gyro normal) ==="
wr 0x7d 0x00
wr 0x40 0x28
wr 0x41 0x03
wr 0x42 0x28
wr 0x43 0x00
wr 0x7e 0x11
sleep 100
wr 0x7e 0x15
sleep 200
echo "BMI160_READBACK 40=[rd 0x40] 41=[rd 0x41] 42=[rd 0x42] 43=[rd 0x43]"
watch 0x0c 12 4
watch 0x18 3 3

echo "=== 试探：写 0x11 到 0x7D(PWR_CTRL) / 0x0E 到 0x7C 等组合后看 0x18 计数是否重启 ==="
set c0 [expr {([rd 0x18] << 16) | ([rd 0x19] << 8) | [rd 0x1a]}]
wr 0x7e 0xB6
sleep 100
set c1 [expr {([rd 0x18] << 16) | ([rd 0x19] << 8) | [rd 0x1a]}]
echo [format {AFTER_CMD_B6 c0=%d c1=%d} $c0 $c1]

# 还原
wr 0x40 $o40; wr 0x41 $o41; wr 0x42 $o42; wr 0x43 $o43
wr 0x7c $o7c; wr 0x7d $o7d; wr 0x7e $o7e
echo "MAP_FINAL [blob 0x00 0x50]"
mww 0x40013000 0x00001001
csh
echo "### BOSCH-TEST END ###"
resume
shutdown
