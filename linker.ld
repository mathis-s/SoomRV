_estack = 0x1FFFC;
MEMORY
{
    ram : ORIGIN = 0x00000000, LENGTH = 0x10000
}
SECTIONS
{
    .text : { *(.text*) } > ram
    .rodata : ALIGN(4) { *(.rodata*) } > ram
} 
