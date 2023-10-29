
// Branch Target Buffer
`define BTB_ENTRIES 1024
`define BTB_TAG_SIZE 16

// TAGE Predictor
`define BP_BASEP_ID_LEN 10
`define TAGE_CLEAR_ENABLE
`define TAGE_CLEAR_INTERVAL 20

// IFetch
`define DEC_WIDTH 4
`define PD_BUF_SIZE 4

// Issue
`define IQ_0_SIZE 8
`define IQ_1_SIZE 8
`define IQ_2_SIZE 8
`define IQ_3_SIZE 8

// Memory
`define SQ_SIZE 32
`define LB_SIZE 16

// ROB Size
`define ROB_SIZE_EXP 6

// PC at reset
`define ENTRY_POINT (32'h8000_0000)


// PMAs
`define IS_MMIO_PMA(addr) \
    ((addr) < 32'h8000_0000)
    
`define IS_MMIO_PMA_W(addr) \
    `IS_MMIO_PMA({(addr), 2'b0})

// Internal MMIO mappings
`define SYSCON_ADDR 32'h1110_0000
`define MTIME_ADDR 32'h1100_bff8
`define MTIMECMP_ADDR 32'h1100_4000

`define CACHE_SIZE_E 14
`define CLSIZE_E 6
`define CASSOC 4

`define CBANKS 4
`define CWIDTH 4

`define AXI_NUM_TRANS 4
`define AXI_ID_LEN $clog2(`AXI_NUM_TRANS)

// External MMIO
// - IS_MMIO_PMA must be true for this range.
// - The upper three bits are not passed on to
//   the external memory controller.
`define ENABLE_EXT_MMIO 1
`define EXT_MMIO_START_ADDR 32'h1000_0000
`define EXT_MMIO_END_ADDR   32'h1100_0000

// 64 MiB main memory (TODO: make adjustable!) or MMIO
`define IS_LEGAL_ADDR(addr) \
    (((addr) >= 32'h80000000 && (addr) < 32'h84000000) || \
    (`IS_MMIO_PMA(addr) && (addr) >= 32'h10000000 && (addr) < 32'h12000000))

// Un-defining this disables synchronous reset for some memories.
// This is useful for mapping to FPGA memories, which are reset
// after programming anyways.
`define SYNC_RESET
