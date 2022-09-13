# SoomRV
## Description
SoomRV is a simple superscalar Out-of-Order RISC-V microprocessor. It can execute 2 Instructions per cycle completely out of order,
and also supports speculative execution and precise exceptions.

## Features
- RV32IMZbaZbb Instruction Set (other instructions can be emulated via traps)
- 2 IPC for simple Int-Ops, 1 IPC Load/Store
- Fully Out-of-Order Load/Store
- Local Adaptive Branch Predictor
- Tag-based OoO Execution with 32 speculative registers (in addition to the 32 architectural registers)

## Basic Architecture
![soomrv](https://user-images.githubusercontent.com/39701487/189920766-0fa0f296-ef00-4983-acc0-1c024d90e1f4.svg)
