
// Branch Target Buffer
`define BTB_ENTRIES 4096
`define BTB_TAG_SIZE 16

// TAGE Predictor
`define BP_BASEP_ID_LEN 10
`define TAGE_CLEAR_ENABLE
`define TAGE_CLEAR_INTERVAL 20
`define TAGE_BASE 4
`define TAGE_STAGES 6
`define TAGE_TABLE_SIZE 256
`define RETURN_SIZE 32
`define RETURN_RQ_SIZE 8

// IFetch
`define FSIZE_E 4
`define DEC_WIDTH 4
`define PD_BUF_SIZE 4
`define WFI_DELAY 1024

// Memory
`define SQ_SIZE 16
`define LB_SIZE 16
`define LRB_SIZE 4

`define ITLB_SIZE 8
`define ITLB_ASSOC 4

`define DTLB_SIZE 8
`define DTLB_ASSOC 4
`define DTLB_MISS_QUEUE_SIZE 4

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

`define VIRT_IDX_LEN 12 // at most 12
`define CASSOC 4
`define CACHE_SIZE_E (`VIRT_IDX_LEN + $clog2(`CASSOC))
`define CLSIZE_E 6

`define CBANKS 4
`define CWIDTH 4

`define AXI_NUM_TRANS 4
`define AXI_WIDTH 128
`define AXI_ID_LEN $clog2(`AXI_NUM_TRANS)

`define ENABLE_EXT_MMIO 1
`define EXT_MMIO_START_ADDR 32'h1000_0000
`define EXT_MMIO_END_ADDR   32'h1100_0000

`define IS_MEM_PMA(addr) \
    ((addr) >= 32'h80000000 && (addr) < 32'h90000000)

// 256 MiB main memory or MMIO
`define IS_LEGAL_ADDR(addr) \
    (`IS_MEM_PMA(addr) || \
    (`IS_MMIO_PMA(addr) && (addr) >= 32'h10000000))


// Enable floating point (zfinx) support
//`define ENABLE_FP

`define NUM_TAGS 64

`define ENABLE_INT_DIV
`define ENABLE_INT_MUL
`define ENABLE_ZCB

`define DEBUG

parameter NUM_AGUS = 2;
parameter NUM_ALUS = 3;
parameter NUM_PORTS = NUM_AGUS + NUM_ALUS;
parameter NUM_PORTS_TOTAL = NUM_ALUS + 2 * NUM_AGUS;

// How many of the ALU ports support branches?
parameter NUM_BRANCH_PORTS = 2;

parameter NUM_RF_READS = NUM_ALUS * 2 + NUM_AGUS * 2;
parameter NUM_RF_WRITES = NUM_ALUS + NUM_AGUS;

parameter int PORT_IQ_SIZE[NUM_PORTS-1:0] = '{
    8,
    8,
    8,
    8,
    8
};

// verilator lint_off WIDTHEXPAND
parameter logic[15:0] PORT_FUS[NUM_PORTS-1:0] = '{

    // NUM_ALUS x AGU Ports
    FU_AGU_OH|FU_ATOMIC_OH,
    FU_AGU_OH|FU_ATOMIC_OH,

    // NUM_ALUS x ALU Ports
    FU_INT_OH|FU_MUL_OH|FU_BITMANIP_OH,
    FU_INT_OH|FU_BRANCH_OH|FU_BITMANIP_OH|FU_MUL_OH|FU_FDIV_OH|FU_FMUL_OH|FU_ATOMIC_OH,
    FU_INT_OH|FU_BRANCH_OH|FU_BITMANIP_OH|FU_DIV_OH|FU_FPU_OH|FU_CSR_OH|FU_ATOMIC_OH
};
// verilator lint_on WIDTHEXPAND
