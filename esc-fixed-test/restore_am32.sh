#!/bin/bash
# 测完把 AM32 恢复回去
set -e
cd "$(dirname "$0")"

AM32=/home/lpl/RM2027/rm2027-drone/work/esc-artifacts/AM32_RM2027_ESC_G071_2.21.bin
EEPROM=/home/lpl/RM2027/rm2027-drone/work/esc-artifacts/eeprom_fixed.bin
[ -f "$AM32" ]   || { echo "❌ 找不到 AM32 bin: $AM32"; exit 1; }
[ -f "$EEPROM" ] || { echo "❌ 找不到 eeprom_fixed.bin: $EEPROM"; exit 1; }

sudo openocd -f interface/stlink.cfg -f target/stm32g0x.cfg \
  -c "adapter speed 500" -c "init" -c "halt" \
  -c "flash write_image erase $AM32 0x08001000" \
  -c "verify_image $AM32 0x08001000" \
  -c "flash write_image erase $EEPROM 0x0801F800" \
  -c "reset run" -c "shutdown"
echo "✅ AM32 已恢复（并重写了 0x0801F800 的 bootloader 跳转标志）"

# 另：本目录的 backup_before_test.bin 是烧测试固件之前的整片 128KB 备份，
#     需要时可以整体回写：
#     sudo openocd -f interface/stlink.cfg -f target/stm32g0x.cfg \
#       -c "init" -c "halt" -c "flash write_image erase backup_before_test.bin 0x08000000" -c "shutdown"
