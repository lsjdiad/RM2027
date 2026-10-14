# 在 115200 下尽量连续地抓一段字节流，看帧结构
init
halt
echo "### H104-CAP BEGIN ###"
set A 0x58020000
set U 0x40011000
proc rdw {a} { mem2array v 32 $a 1; return $v(0) }
set moderA [rdw [expr {$A+0x00}]]
set afrhA  [rdw [expr {$A+0x24}]]
mww [expr {$A+0x00}] [expr {($moderA & ~(0x3<<20)) | (0x2<<20)}]
mww [expr {$A+0x24}] [expr {($afrhA & ~(0xF<<8)) | (0x7<<8)}]

mww [expr {$U+0x00}] 0x00000000
mww [expr {$U+0x0C}] 1042          ;# 120MHz/115200
mww [expr {$U+0x08}] 0x00000000
mww [expr {$U+0x20}] 0x0000001F
mww [expr {$U+0x18}] 0x00000008
mww [expr {$U+0x00}] 0x00000005    ;# UE|RE

# 每次一条 12 字节块读：ISR(1C) RDR(24)，减少 SWD 次数
set out ""
set i 0
while {$i < 700} {
    mem2array blk 8 [expr {$U+0x1C}] 12
    set isr $blk(0)
    if {($isr & 0x20) != 0} {
        append out [format "%02X " [expr {$blk(8) & 0xFF}]]
    }
    if {($isr & 0x0F) != 0} { mww [expr {$U+0x20}] 0x0000000F }
    incr i
}
mww [expr {$U+0x00}] 0x00000000
mww [expr {$A+0x00}] $moderA
mww [expr {$A+0x24}] $afrhA
echo "抓到的字节（按顺序，可能丢字节）："
echo $out
echo "### H104-CAP END ###"
resume
shutdown
