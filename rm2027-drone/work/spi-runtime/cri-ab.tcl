# cri-ab.tcl —— A/B 测两种 CR1 值下手工 SPI 读的结果
#   目的：分清"芯片读不出来"和"我这条手工读路径本身不对"
#   背景：老脚本用 CR1=0x1201，`结论文档-器件身份与锁死真相.md` §2 的恢复操作用 0x1001。
#         两者差 bit9。本脚本把两者都试一遍，看哪个能读出 WHO_AM_I=0x6A。

source [find interface/stlink.cfg]
transport select hla_swd
source [find target/stm32h7x_dual_bank.cfg]
adapter speed 1000
init
halt

proc r32 {a} { mem2array v 32 $a 1; return $v(0) }
proc w32 {a v} { mww $a $v }
proc srr {} { return [r32 0x40013014] }
proc dr {} { set n 0; while {$n<16 && ([srr]&1)!=0} { mem2array z 8 0x40013030 1; incr n } }
proc xf {b} {
    mwb 0x40013020 $b
    set n 0
    while {$n<300} { if {([srr]&1)!=0} { break }; incr n }
    mem2array v 8 0x40013030 1
    return $v(0)
}
proc cslo {} { w32 0x58020418 0x00100000 }
proc cshi {} { w32 0x58020418 0x00000010 }

proc readone {cr1 reg} {
    w32 0x40013018 0x00001FFF
    w32 0x40013000 $cr1
    after 2
    cslo
    dr
    xf [expr {$reg | 0x80}]
    set b [xf 0x00]
    cshi
    after 2
    return $b
}

echo "### CRI-AB BEGIN ###"
foreach cr1 {0x00001001 0x00001201} {
    set who [readone $cr1 0x01]
    set pwr [readone $cr1 0x7D]
    set ds  [readone $cr1 0x0B]
    set ac  [readone $cr1 0x40]
    set gyr [readone $cr1 0x42]
    echo [format "CR1=%08X  ->  WHO_AM_I=%02X  0x7D=%02X  0x0B=%02X  0x40=%02X  0x42=%02X" \
        $cr1 $who $pwr $ds $ac $gyr]
}
# 恢复固件自己的配置
w32 0x40013018 0x00001FFF
w32 0x40013000 0x00001001
w32 0x58020418 0x00000010
echo "### CRI-AB END ###"
resume
shutdown
