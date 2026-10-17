init
halt
echo "### PULLUP-TEST BEGIN ###"
proc rdw {a} { mem2array v 32 $a 1; return $v(0) }
set A 0x58020000
set moderA [rdw [expr {$A+0x00}]]
set pupdrA [rdw [expr {$A+0x0c}]]
echo "GPIOA MODER=[format 0x%08X $moderA] PUPDR=[format 0x%08X $pupdrA]"

proc sample {label} {
    set ones 0; set tr 0; set prev -1; set n 0
    while {$n < 300} {
        set v [expr {(([rdw 0x58020010])>>10)&1}]
        incr ones $v
        if {$prev >= 0 && $v != $prev} { incr tr }
        set prev $v
        incr n
    }
    echo "  $label : 高=$ones/300  跳变=$tr"
}
# A: 输入 + 不上拉（默认）
mww [expr {$A+0x00}] [expr {$moderA & ~(0x3<<20)}]
mww [expr {$A+0x0c}] [expr {$pupdrA & ~(0x3<<20)}]
sample "无上拉"
# B: 输入 + 内部上拉  (PUPDR 01)
mww [expr {$A+0x00}] [expr {$moderA & ~(0x3<<20)}]
mww [expr {$A+0x0c}] [expr {($pupdrA & ~(0x3<<20)) | (0x1<<20)}]
sample "内部上拉"
# C: 输入 + 内部下拉  (PUPDR 10)
mww [expr {$A+0x0c}] [expr {($pupdrA & ~(0x3<<20)) | (0x2<<20)}]
sample "内部下拉"
# 恢复
mww [expr {$A+0x00}] $moderA
mww [expr {$A+0x0c}] $pupdrA

echo "-- RCC 相关（算 USART1 内核时钟用）--"
echo "  D1CFGR  =[format 0x%08X [rdw 0x58024428]]"
echo "  D2CFGR  =[format 0x%08X [rdw 0x5802442C]]"
echo "  D2CCIP2R=[format 0x%08X [rdw 0x58024454]]   (bits1:0 = USART1SEL)"
echo "  APB2ENR =[format 0x%08X [rdw 0x580244F0]]"
echo "### PULLUP-TEST END ###"
resume
shutdown
