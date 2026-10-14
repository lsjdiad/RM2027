#!/bin/bash
set -e
cd "$(dirname "$0")"
CC=arm-none-eabi-gcc; OBJCOPY=arm-none-eabi-objcopy
CFLAGS="-mcpu=cortex-m0plus -mthumb -O1 -ffreestanding -nostdlib -nostartfiles -Wall"
build(){ $CC $CFLAGS -DMODE=$1 -Wl,-T,app.ld -Wl,--gc-sections -o "$2.elf" test_3low.c
         $OBJCOPY -O binary "$2.elf" "$2.bin"
         printf '%-26s MODE=%s  %s 字节\n' "$2.bin" "$1" "$(stat -c%s "$2.bin")"; }
build 1 test_3low_1khz      # 三路同步翻转，示波器对比
build 0 test_3low_static    # 三路常通，万用表/上拉测试
