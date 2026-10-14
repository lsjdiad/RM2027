#!/bin/bash
# 编译 test_pinwalk.c
#   ./build_pinwalk.sh             → 顺序走查版（9 个候选脚轮流驱动）
#   PIN_HOLD=2 ./build_pinwalk.sh  → 只驱动 2 号候选脚（PB1），反复翻转
set -e
cd "$(dirname "$0")"
CC=arm-none-eabi-gcc; OBJCOPY=arm-none-eabi-objcopy
CFLAGS="-mcpu=cortex-m0plus -mthumb -O1 -ffreestanding -nostdlib -nostartfiles -Wall"

DEFS=""; OUT=test_pinwalk
if [ -n "${PIN_HOLD:-}" ]; then
  DEFS="-DPIN_HOLD=$PIN_HOLD"
  OUT=test_pinwalk_hold$PIN_HOLD
fi

$CC $CFLAGS $DEFS -Wl,-T,app.ld -Wl,--gc-sections -o "$OUT.elf" test_pinwalk.c
$OBJCOPY -O binary "$OUT.elf" "$OUT.bin"
printf '%-30s %s 字节\n' "$OUT.bin" "$(stat -c%s "$OUT.bin")"
