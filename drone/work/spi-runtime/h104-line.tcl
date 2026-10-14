# 只读探测：H104 的连线（PA9=SYNC_IN, PA10=USART1_RX, PD0=CAN1_RX）有没有信号
# 做法：把引脚临时设成【输入】（不改复用），采样 IDR，看电平和跳变。
# 全部可逆：结束时恢复 MODER。
init
halt
echo "### H104-LINE BEGIN ###"
proc rdw {a} { mem2array v 32 $a 1; return $v(0) }

set GpioA 0x58020000
set GpioD 0x58020c00
set moderA [rdw [expr {$GpioA+0x00}]]
set moderD [rdw [expr {$GpioD+0x00}]]
echo "before: GPIOA_MODER=[format 0x%08X $moderA]  GPIOD_MODER=[format 0x%08X $moderD]"

# PA9(bits19:18) PA10(bits21:20) 设为输入 00；PD0(bits1:0) 设输入 00
set m [expr {($moderA & ~(0xF<<18))}]
mww [expr {$GpioA+0x00}] $m
set m2 [expr {($moderD & ~(0x3<<0))}]
mww [expr {$GpioD+0x00}] $m2

# 采样：每次统计 PA9/PA10/PD0 的值
set n 0; set cnt9 0; set cnt10 0; set cntD0 0; set prev 0
set ones9 0; set ones10 0; set onesD0 0
while {$n < 400} {
    set idrA [rdw [expr {$GpioA+0x10}]]
    set idrD [rdw [expr {$GpioD+0x10}]]
    set b9  [expr {($idrA>>9)&1}]
    set b10 [expr {($idrA>>10)&1}]
    set bD0 [expr {($idrD>>0)&1}]
    incr ones9 $b9; incr ones10 $b10; incr onesD0 $bD0
    if {$n > 0} {
        if {$b9  != [lindex $prev 0]} { incr cnt9 }
        if {$b10 != [lindex $prev 1]} { incr cnt10 }
        if {$bD0 != [lindex $prev 2]} { incr cntD0 }
    }
    set prev [list $b9 $b10 $bD0]
    mww 0x40013000 0x00001201
    incr n
}
echo "采样 400 次（每次夹了一条 SPI1 读，约几十 us 间隔）"
echo "  PA9  (SYNC_IN, H104->FC)  高电平次数=$ones9/400   跳变次数=$cnt9"
echo "  PA10 (USART1_RX, H104->FC)高电平次数=$ones10/400  跳变次数=$cnt10"
echo "  PD0  (CAN1_RX,  H104->FC) 高电平次数=$onesD0/400  跳变次数=$cntD0"

# 恢复
mww [expr {$GpioA+0x00}] $moderA
mww [expr {$GpioD+0x00}] $moderD
mww 0x40013000 0x00001001
echo "### H104-LINE END ###"
resume
shutdown
