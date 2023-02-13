# SoomRV
## Description
SoomRV is a simple superscalar Out-of-Order RISC-V microprocessor. It can execute up to 4 instructions per cycle completely out of order, and also supports speculative execution and precise exceptions.

## Features
- RV32IMCZbaZbb Instruction Set (other instructions can be emulated via traps)
- 2 IPC for simple Int-Ops, 1 IPC Load/Store
- Fully Out-of-Order Load/Store
- Local Adaptive Branch Predictor
- Tag-based OoO Execution with 32 speculative registers (in addition to the 32 architectural registers)
- Fuses `aui(pc)`+`addi` as well as `addi`+branch
- Currently scores 4.5 DMIPS/MHz with 1.499 IPC (GCC 11.1.0, `-O2 -finline-limit=128`)

## Simulating
1. Install the [RV32 toolchain](https://github.com/riscv-collab/riscv-gnu-toolchain) as well as Verilator.
2. Run `make` to build a binary with Verilator.
3. Run `./obj_dir/VTop <assembly file>` to execute the code in `<assembly file>`. For example, run `./obj_dir/VCore test_programs/dhry_1.s` to run Dhrystone.
4. Open `view.gtkw` for a waveform view of the core's internals.

## Basic Architecture
![SoomRV](https://user-images.githubusercontent.com/39701487/218574949-e18bcb51-5050-4f99-82a6-c8ea58c11a93.png)
