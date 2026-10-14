source [find interface/stlink.cfg]
transport select hla_swd
source [find target/stm32h7x_dual_bank.cfg]
adapter speed 1000
init
halt
echo "### DIAG3 BEGIN ###"
proc r32 {addr} { mem2array v 32 $addr 1; return $v(0) }
proc w32 {addr val} { mww $addr $val }
proc srr {} { return [r32 0x40013014] }
proc dr {} { set n 0; while {$n<16 && ([srr]&1)!=0} { mem2array z 8 0x40013030 1; incr n } }
proc xf {b} {
    w32 0x40013000 0x00001201
    mwb 0x40013020 $b
    set n 0
    while {$n < 20000} { if {([srr] & 1) != 0} { break }; incr n }
    mem2array v 8 0x40013030 1
    return [list $v(0) $n]
}
proc cslo {} { w32 0x58020418 0x00100000 }
proc cshi {} { w32 0x58020418 0x00000010 }
proc rd1 {reg} { cslo; dr; set a [xf [expr {$reg | 0x80}]]; set b [xf 0x00]; cshi
    return [format "0x%02X (wait1=%d wait2=%d)" [lindex $b 0] [lindex $a 1] [lindex $b 1]] }

echo "-- 引脚状态 --"
echo [format "GPIOB MODER=%08X ODR=%08X IDR=%08X AFRL=%08X" [r32 0x58020400] [r32 0x58020414] [r32 0x58020410] [r32 0x58020420]]
echo [format "GPIOA MODER=%08X IDR=%08X AFRL=%08X (PA6=MISO 应 AF5)" [r32 0x58020000] [r32 0x58020010] [r32 0x58020020]]
echo [format "GPIOD MODER=%08X AFRL=%08X (PD7=MOSI 应 AF5)" [r32 0x58020c00] [r32 0x58020c20]]
echo [format "SPI1 SR=%08X CR1=%08X CFG1=%08X CFG2=%08X CR2=%08X" [srr] [r32 0x40013000] [r32 0x40013008] [r32 0x4001300C] [r32 0x40013004]]

echo "-- CS 拉低前后 GPIOB IDR 的 bit4（应 1 -> 0）--"
echo [format "  CS 高: IDR=%08X bit4=%d" [r32 0x58020410] [expr {([r32 0x58020410]>>4)&1}]]
cslo
echo [format "  CS 低: IDR=%08X bit4=%d" [r32 0x58020410] [expr {([r32 0x58020410]>>4)&1}]]
cshi

echo "-- 尝试 A：现状直接读 WHO_AM_I(0x01) --"
echo "   0x01 = [rd1 0x01]"

echo "-- 尝试 B：先软复位 SPI1 寄存器到已知状态，再读 --"
w32 0x40013000 0x00000000
dr
w32 0x40013018 0x00001FFF
w32 0x40013008 0x30070007
w32 0x4001300C 0x87400000
w32 0x40013010 0x00000000
w32 0x40013004 0x00000000
w32 0x40013000 0x00001001
after 5
echo [format "   复位后 SPI1 SR=%08X CR1=%08X" [srr] [r32 0x40013000]]
echo "   0x01 = [rd1 0x01]"
echo "   0x40 = [rd1 0x40]"

echo "-- 尝试 C：清掉 SUSP（写 IFCR 的 SUSP 位 bit11?? 用全清）后重试 --"
w32 0x40013018 0x00001FFF
echo "   SR=$[format %08X [srr]]"
echo "   0x01 = [rd1 0x01]"

echo "-- 尝试 D：手工只发 1 个字节 0x81（不做 2 字节序列）看 RXDR --"
cslo; dr
set a [xf 0x81]
cshi
echo [format "   第1字节后 RXDR=%02X wait=%d" [lindex $a 0] [lindex $a 1]]

echo "### DIAG3 END ###"
resume
shutdown
