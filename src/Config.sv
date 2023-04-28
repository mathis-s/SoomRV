
// Branch Target Buffer
`define BTB_ENTRIES 128
`define BTB_ASSOC 8
`define BTB_TAG_SIZE 16

// Tage Base Predictor
`define BP_BASEP_ID_LEN 8



// IFetch
`define DEC_WIDTH 4

// Issue
`define IQ_0_SIZE 8
`define IQ_1_SIZE 8
`define IQ_2_SIZE 8
`define IQ_3_SIZE 10

// Memory
`define SQ_SIZE 24
`define LB_SIZE 16

// ROB Size
`define ROB_SIZE_EXP 6



// PC at reset
`define ENTRY_POINT (32'h8000_0000)
//`define ENTRY_POINT (32'h8000_0000 + 2247620)


// PMAs
`define IS_MMIO_PMA(addr) \
    ((addr) < 32'h8000_0000)
    
`define IS_MMIO_PMA_W(addr) \
    `IS_MMIO_PMA({addr, 2'b0})

`define SERIAL_ADDR 32'h1000_0000
`define SYSCON_ADDR 32'h1110_0000
`define MTIME_ADDR 32'h1100_bff8
`define MTIMECMP_ADDR 32'h1100_4000

// 64 MiB main memory (TODO: make adjustable!)
`define IS_LEGAL_ADDR(addr) \
    ((addr >= 32'h80000000 && addr < 32'h84000000) || \
    (`IS_MMIO_PMA(addr) && addr >= 32'h10000000 && addr < 32'h12000000))
