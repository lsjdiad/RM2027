#!/bin/bash
pkill -x openocd 2>/dev/null || true
sleep 1
# helper: 每笔事务独立 CS 窗口；写 2 字节 / 读 2 字节
W2() { echo "-c \"mww 0x58020418 0x00100000\" -c \"mww 0x40013000 0x00001201\" -c \"mwb 0x40013020 $1\" -c \"mdb 0x40013030\" -c \"mww 0x40013000 0x00001201\" -c \"mwb 0x40013020 $2\" -c \"mdb 0x40013030\" -c \"mww 0x58020418 0x00000010\""; }
exec openocd -f interface/stlink.cfg -f target/stm32h7x.cfg \
 -c "init" -c "halt" \
 -c "echo {== 0x76 是否 3bit 寄存器(REG_BANK_SEL)? 写 0xA5 读回 =} " \
 -c "mww 0x58020418 0x00100000" -c "mww 0x40013000 0x00001201" -c "mwb 0x40013020 0x76" -c "mdb 0x40013030" -c "mww 0x40013000 0x00001201" -c "mwb 0x40013020 0xA5" -c "mdb 0x40013030" -c "mww 0x58020418 0x00000010" \
 -c "mww 0x58020418 0x00100000" -c "mww 0x40013000 0x00001201" -c "mwb 0x40013020 0xF6" -c "mdb 0x40013030" -c "mww 0x40013000 0x00001201" -c "mwb 0x40013020 0x00" -c "mdb 0x40013030" -c "mww 0x58020418 0x00000010" \
 -c "echo {== 写 0x5A 读回 =}" \
 -c "mww 0x58020418 0x00100000" -c "mww 0x40013000 0x00001201" -c "mwb 0x40013020 0x76" -c "mdb 0x40013030" -c "mww 0x40013000 0x00001201" -c "mwb 0x40013020 0x5A" -c "mdb 0x40013030" -c "mww 0x58020418 0x00000010" \
 -c "mww 0x58020418 0x00100000" -c "mww 0x40013000 0x00001201" -c "mwb 0x40013020 0xF6" -c "mdb 0x40013030" -c "mww 0x40013000 0x00001201" -c "mwb 0x40013020 0x00" -c "mdb 0x40013030" -c "mww 0x58020418 0x00000010" \
 -c "echo {== 逐 bank 扫: 写 0x76=b 后读 r75/r0b/r1d =}" \
 -c "for {set b 0} {\$b < 8} {incr b} {
      mww 0x58020418 0x00100000
      mww 0x40013000 0x00001201
      mwb 0x40013020 0x76
      mem2array k 8 0x40013030 1
      mww 0x40013000 0x00001201
      mwb 0x40013020 \$b
      mem2array k2 8 0x40013030 1
      mww 0x58020418 0x00000010
      foreach pa {0xF5 0x8B 0x9D} {
        mww 0x58020418 0x00100000
        mww 0x40013000 0x00001201
        mwb 0x40013020 \$pa
        mem2array a1 8 0x40013030 1
        mww 0x40013000 0x00001201
        mwb 0x40013020 0x00
        mem2array a2 8 0x40013030 1
        mww 0x58020418 0x00000010
        echo [format {bank%d reg%02x = %02x} \$b [expr {\$pa & 0x7f}] \$a2(0)]
      }
    }" \
 -c "echo {== 还原 0x76=0 =}" \
 -c "mww 0x58020418 0x00100000" -c "mww 0x40013000 0x00001201" -c "mwb 0x40013020 0x76" -c "mdb 0x40013030" -c "mww 0x40013000 0x00001201" -c "mwb 0x40013020 0x00" -c "mdb 0x40013030" -c "mww 0x58020418 0x00000010" \
 -c "mww 0x40013000 0x00001001" -c "resume" -c "shutdown"
