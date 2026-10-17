/* 链接脚本：测试固件放在 AM32 的 app 槽 0x08001000 */
ENTRY(Reset_Handler)

MEMORY
{
  FLASH (rx)  : ORIGIN = 0x08001000, LENGTH = 124K
  RAM   (rwx) : ORIGIN = 0x20000000, LENGTH = 36K
}

_estack = ORIGIN(RAM) + LENGTH(RAM);

SECTIONS
{
  .vectors : { KEEP(*(.vectors)) } > FLASH
  .text    : { *(.text*) *(.rodata*) } > FLASH
  .data    : { *(.data*) } > RAM AT> FLASH
  .bss     : { *(.bss*) *(COMMON) } > RAM
}
