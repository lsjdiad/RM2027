# H104 波特率扫描：手工把 USART1(RX=PA10) 配起来，逐个波特率抓字节
# 全部只动 USART1 和 PA10；结束时恢复原状（CR1=0、PA10 回 analog）
init
halt
echo "### H104-BAUD BEGIN ###"
proc rdw {a} { mem2array v 32 $a 1; return $v(0) }
set A 0x58020000
set U 0x40011000
set moderA [rdw [expr {$A+0x00}]]
set afrhA  [rdw [expr {$A+0x24}]]

# PA10 -> AF (MODER=10) + AF7
mww [expr {$A+0x00}] [expr {($moderA & ~(0x3<<20)) | (0x2<<20)}]
mww [expr {$A+0x24}] [expr {($afrhA & ~(0xF<<8)) | (0x7<<8)}]

proc try_baud {label pclk baud} {
    global U
    set brr [expr {int(($pclk + $baud/2) / $baud)}]
    # 复位 USART1
    mww [expr {$U+0x00}] 0x00000000
    mww [expr {$U+0x0C}] $brr
    mww [expr {$U+0x08}] 0x00000000
    mww [expr {$U+0x20}] 0x0000001F   ;# ICR: 清 PE/FE/NE/ORE/IDLE
    mww [expr {$U+0x18}] 0x00000008   ;# RQR: RXFRQ 清 RX FIFO
    mww [expr {$U+0x00}] 0x00000005   ;# CR1: UE | RE
    set bytes {}; set fe 0; set ne 0; set ore 0; set i 0
    while {$i < 400} {
        set isr [rdw [expr {$U+0x1C}]]
        if {($isr & 0x2) != 0} { incr fe;  mww [expr {$U+0x20}] 0x2 }
        if {($isr & 0x4) != 0} { incr ne;  mww [expr {$U+0x20}] 0x4 }
        if {($isr & 0x8) != 0} { incr ore; mww [expr {$U+0x20}] 0x8 }
        if {($isr & 0x20) != 0} {
            set d [expr {[rdw [expr {$U+0x24}]] & 0xFF}]
            if {[llength $bytes] < 24} { lappend bytes [format %02X $d] }
        }
        incr i
    }
    mww [expr {$U+0x00}] 0x00000000
    echo [format "  %-28s BRR=%-6d FE=%-4d NE=%-3d ORE=%-4d bytes: %s" $label $brr $fe $ne $ore [join $bytes { }]]
}

echo "-- 假设 PCLK2 = 120 MHz（由 USART3@57600 BRR=0x824 实测反推）--"
foreach b {9600 19200 38400 57600 115200 230400 460800 921600 1000000 2000000 3000000} {
    try_baud "[expr {$b/1000.0}]k" 120000000 $b
}
echo "-- 假设 PCLK2 = 60 MHz --"
foreach b {115200 921600 1500000 2000000} {
    try_baud "[expr {$b/1000.0}]k@60M" 60000000 $b
}
# 恢复
mww [expr {$A+0x00}] $moderA
mww [expr {$A+0x24}] $afrhA
echo "### H104-BAUD END ###"
resume
shutdown
