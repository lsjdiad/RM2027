/* 整片起始版：没有 bootloader 的新芯片，复位即运行 */
ENTRY(Reset_Handler)
MEMORY
{
  FLASH (rx)  : ORIGIN = 0x08000000, LENGTH = 128K
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
