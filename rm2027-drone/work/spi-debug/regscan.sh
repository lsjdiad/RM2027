#!/bin/bash
pkill -x openocd 2>/dev/null || true
sleep 1
exec openocd -f interface/stlink.cfg -f target/stm32h7x.cfg \
 -c "init" -c "halt" \
 -c "mdb 0x40013030" -c "mdb 0x40013030" -c "mdb 0x40013030" -c "mdb 0x40013030" \
 -c "echo {#### bank0 全寄存器扫描（只读） ####}" \
 -c "for {set r 0} {\$r < 128} {incr r} {
        mww 0x58020418 0x00100000
        mww 0x40013000 0x00001201
        mwb 0x40013020 [expr {0x80 | \$r}]
        mem2array d 8 0x40013030 1
        mww 0x40013000 0x00001201
        mwb 0x40013020 0x00
        mem2array v 8 0x40013030 1
        echo [format {r%02x=%02x} \$r \$v(0)]
        mww 0x58020418 0x00000010
      }" \
 -c "mww 0x40013000 0x00001001" -c "mdw 0x58020414" \
 -c "resume" -c "shutdown"
