#!/bin/bash
# 编译两个版本：A 下管 1 kHz 翻转 / A 下管常通
set -e
cd "$(dirname "$0")"

CC=arm-none-eabi-gcc
OBJCOPY=arm-none-eabi-objcopy
CFLAGS="-mcpu=cortex-m0plus -mthumb -O1 -ffreestanding -nostdlib -nostartfiles -Wall"

build() {
  local hz="$1" out="$2"
  $CC $CFLAGS -DA_TOGGLE_HZ=$hz -Wl,-T,app.ld -Wl,--gc-sections \
      -Wl,-Map="$out.map" -o "$out.elf" test_low_side.c
  $OBJCOPY -O binary "$out.elf" "$out.bin"
  printf '%-28s A_TOGGLE_HZ=%-6s bin=%s 字节\n' "$out.bin" "$hz" "$(stat -c%s "$out.bin")"
}

build 1000 test_a_low_1khz     # 示波器用：A 下管 1 kHz 方波
build 0    test_a_low_static   # 万用表用：A 下管常通

echo "OK"
