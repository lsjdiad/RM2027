init
halt
echo "### CLOCKS BEGIN ###"
proc rdw {a} { mem2array v 32 $a 1; return $v(0) }
foreach {name base} {USART1 0x40011000 USART2 0x40004400 USART3 0x40004800 UART4 0x40004C00 UART5 0x40005000 USART6 0x40011400} {
    set cr1 [rdw [expr {$base+0x00}]]
    set brr [rdw [expr {$base+0x0C}]]
    set psc [rdw [expr {$base+0x08}]]
    echo "  $name CR1=[format 0x%08X $cr1] BRR=[format 0x%08X $brr] (=$brr) CR3/PSC=[format 0x%08X $psc]"
}
echo "-- 由 USART3 BRR 反推 PCLK1（USART3 实测 57600 能跑通 MAVLink）--"
echo "### CLOCKS END ###"
resume
shutdown
