# SoomRV
## Description
SoomRV is a simple superscalar Out-of-Order RISC-V microprocessor. It can execute 2 Instructions per cycle completely out of order,
and also supports speculative execution and precise exceptions.

## Features
- RV32IMZbaZbb Instruction Set (other instructions can be emulated via traps)
- 2 IPC for simple Int-Ops, 1 IPC Load/Store
- Fully Out-of-Order Load/Store
- Local Adaptive Branch Predictor combined with 16 Entry Branch Target Buffer
- Tag-based OoO Execution with 32 speculative registers (in addition to the 32 architectural registers)
- 30 Entry Reorder Buffer allows executing code after skipping up to 30 Instructions
- 4KiB ICache + 4KiB DCache
