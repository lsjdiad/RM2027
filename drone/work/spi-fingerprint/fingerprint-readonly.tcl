# fingerprint-readonly.tcl —— 只读全量寄存器 dump（0x00-0x7F），多趟以判稳定性
# 用法：openocd -f interface/stlink.cfg -f target/stm32h7x.cfg -c "$(cat fingerprint-readonly.tcl)"
# 手法来自 work/spi-debug/（已验证可用）：手工驱动 SPI1 + GPIOB CS
#   SPI1 CR1=0x40013000  SR=0x40013014  CFG1=0x40013008  CFG2=0x4001300C  TXDR=0x40013020  RXDR=0x40013030
#   GPIOB BSRR=0x58020418  (低16位=置位→写0x00100000 拉低PB4=选中; 高16位=复位→写0x00000010 拉高PB4=释放)
#   CR1 写 0x00001201 = SPE|CSTART|SSI；0x00001001 = SPE|SSI（还原用）
# 读帧：先发 0x80|addr（地址帧，从机不驱动 → 我们读到 0xff），再发 0x00（数据帧 → 寄存器值）
# 写帧：先发 addr(bit7=0)，再发 value

init
halt
echo "### FINGERPRINT-READONLY BEGIN ###"
mem2array _cr1  32 0x40013000 1
mem2array _cfg1 32 0x40013008 1
mem2array _cfg2 32 0x4001300C 1
mem2array _odr  32 0x58020414 1
echo [format {STATE_BEGIN CR1=%08x CFG1=%08x CFG2=%08x ODR=%08x} $_cr1(0) $_cfg1(0) $_cfg2(0) $_odr(0)]

proc srr {} { mem2array s 32 0x40013014 1; return $s(0) }

proc xfer {b} {
    mww 0x40013000 0x00001201
    mwb 0x40013020 $b
    set n 0
    while {$n < 20000} {
        if {([srr] & 1) != 0} { break }
        incr n
    }
    mem2array v 8 0x40013030 1
    return $v(0)
}

proc drain {} {
    set n 0
    while {$n < 16 && ([srr] & 1) != 0} {
        mem2array z 8 0x40013030 1
        incr n
    }
    return $n
}

proc rd {r} {
    mww 0x58020418 0x00100000
    drain
    xfer [expr {0x80 | $r}]
    set v [xfer 0x00]
    mww 0x58020418 0x00000010
    return $v
}

set r0 [rd 0x00]
echo [format {SANITY rd(0x00)=%02x} $r0]

foreach pass {1 2 3} {
    set line ""
    for {set r 0} {$r < 128} {incr r} {
        append line [format "%02x" [rd $r]]
    }
    echo "PASS$pass $line"
}

# 还原：CR1 回 SPE|SSI，CS 释放为高
mww 0x40013000 0x00001001
mww 0x58020418 0x00000010
mem2array _odr2 32 0x58020414 1
mem2array _cr12 32 0x40013000 1
echo [format {STATE_END CR1=%08x ODR=%08x} $_cr12(0) $_odr2(0)]
echo "### FINGERPRINT-READONLY END ###"
resume
shutdown
