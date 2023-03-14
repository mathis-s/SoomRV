_estack = 0x1FFFC;
MEMORY
{
    ram : ORIGIN = 0x00000000, LENGTH = 0x100000
}
SECTIONS
{
    .text : { *(.text*) } > ram
    .data : ALIGN(4) { *(.rodata*); *(.data*); *(.sdata*); *(.srodata*) } > ram
} 
