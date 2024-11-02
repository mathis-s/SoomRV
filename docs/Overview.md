# General
SoomRV is a tag-based OoO architecture. During rename, every instruction that writes to an architectural (i.e. virtual) register is given a tag. This tag is used both as the destination register
for the instruction itself, and as a source register for all instructions depending on the computed value. A tag is freed again only once a new instruction writing to the same virtual register commits. The current speculative as well as committed mappings from virtual to physical registers are stored in the [RenameTable](../src/RenameTable.sv).

After instructions are renamed, they await their execution in various issue queues. Within issue queues, availability of instruction operands is tracked using the operands' tags. Once all operands are available, the instruction is issued, even if older instructions are still waiting.
The actual value of operands is not kept within IQs yet (except immediates). Operand registers are only loaded in the following "Load" pipeline stage after the instruction is issued.

Instructions are executed speculatively and out of order. As such, a recovery mechanism is required in case a misspeculation is made. SoomRV uses a reorder buffer to track all post-rename instructions. If a misspeculation occurs, a global `branch` signal fires. This signal invalidates all post-misspeculation in-flight instructions at every stage in the pipeline and in the ROB. To check whether a given instruction came before or after the misspeculation, every instruction carries a sequence number.

Additionally, after misspeculation, recovery of rename state is necessary. In SoomRV, rename state is reset to committed state when a misspeculation fires. Then, not-yet-committed instructions are "re-played" from the ROB to recover the last correct rename state. (Another possible approach would be snapshotting rename state in every cycle.)

# UOps
Most of SoomRV is built around different Modules passing various `UOp` or other structs between them.
The definitions for these structs (and other data types) are in [src/Include.sv](../src/Include.sv).
Shown below is `EX_UOp` ("Execute-UOp"), which is the UOp that functional units are given in the execute pipeline stage.

```systemverilog
typedef struct packed
{
    logic[31:0] srcA;
    logic[31:0] srcB;
    logic[31:0] pc;
    FetchOff_t fetchOffs;
    FetchOff_t fetchStartOffs;
    FetchOff_t fetchPredOffs;
    logic[31:0] imm;
    logic[5:0] opcode;
    Tag tagDst;
    SqN sqN;
    FetchID_t fetchID;
    BranchPredInfo bpi;
    SqN storeSqN;
    SqN loadSqN;
    FuncUnit fu;
    logic compressed;
    logic valid;
} EX_UOp;

```
What follows are short explanations of the most important fields. While `EX_UOp` is shown as an example, these fields can be found in almost all UOp structs.

### `sqN` (sequence number)
During rename, all instructions are given a unique identifier in the form of a sequence number.

The sequence number is one bit longer than an index into the reorder buffer,
which allows us to use two's complement arithmetic to compare the order of
any two in-flight instructions.
This is commonly used to invalidate uOps during a branch or other mispredict, using code similar to what's shown below.

```systemverilog
if (IN_uop.valid && (!IN_branch.taken || $signed(IN_uop.sqN - IN_branch.sqN) <= 0)) begin
    // Valid UOp
end
```

The lower sequence number bits are used as an index into the reorder buffer when emplacing or modifying the instruction's entry.
As such, in the ROB, only the most significant `SqN` bit is stored explicitly. All others are implicitly given by the index.


### `loadSqN`, `storeSqN` (load and store sequence numbers)
Similar to `sqN`, which is used as an index into the ROB, these are used as indices into the LoadBuffer and StoreQueue respectively.

### `tagDst` (destination register tag)
In addition to sequence numbers, rename also allocates a destination register for instructions to store their result in. This is similar to `rd` in RISC-V, but refers to an actual physical register instead of a virtual one.

### `fetchID`
The fetch ID is similar to sequence numbers, though it is assigned during fetch; as opposed to SqNs, which are assigned significantly later in rename.
Fetch IDs are used to access the fetch state backup stored in the PCFile for every fetch bundle.

Specifically, we access the fetch state backup when we want to know the program counter
or branch prediction information for an instruction. These are only stored in the PCFile, thus saving area.
In the case of `EX_UOp`, this access has already been performed by the immediately preceding pipeline stage (Load) for us to use during execution.

In addition, the ROB will access PCFile using an instructions's `fetchID` if the instruction is an exception or a predicted branch. In both cases, we need access to the original program counter after commit.


# Modules
What follows are short descriptions of some important modules in SoomRV.
Most of the following modules are themselves instantiated within the [Core](../src/Core.sv) module.

### [IFetch](../src/IFetch.sv)
IFetch is a large module which handles the first few pipeline stages, all related to instruction fetching. It also includes all branch prediction modules.
IFetch outputs a fetch bundle (`IF_Instr`), which (depending on alignment and branches) contains up to 8 halfwords of instruction data (16 bytes).

#### [BranchPredictor](../src/BranchPredictor.sv)
In each cycle, the next program counter is predicted based on the current program counter and branch prediction state. We predict at most one branch per cycle, taken or not.
Branch prediction handles both target prediction ([`BranchTargetBuffer`](../src/BranchTargetBuffer.sv)) and direction prediction ([`TagePredictor`](../src/TagePredictor.sv)). In addition, [`ReturnStack`](../src/ReturnStack.sv) handles return prediction.

#### [BranchHandler](../src/BranchHandler.sv)
As soon as instructions are loaded from ICache, the BranchHandler corrects earlier predictions by comparing them to the actual instructions. For example, if a jump target is wrong due to branch aliasing, the BranchHandler corrects it. Almost everything can be corrected,
except conditional branch direction and indirect branch destinations, which are instead handled during execute. Everything else, notably direct jump targets & conditional branch targets are guaranteed to be correct after the BranchHandler, and do not have to be checked downstream.

#### PCFile \& BPFile
The PCFile stores every fetch bundle's source program counter, the BPFile its branch prediction state. Branch prediction state includes branch history, and which one of the instructions in the bundle was predicted to be a branch (if any). The files are used to reset front-end state after mispredict. A fetch bundle's PCFile and BPFile entries are freed after all of its instruction have been committed.

### [PreDecode](../src/PreDecode.sv)
PreDecode is a buffer, and also splits IFetch's instruction bundles into one or more discrete
16 or 32-bit instructions (in RISC-V, this is based on the lower two instruction bits).
The individual instructions are then distributed to decoder ports.

### [InstrDecoder](../src/InstrDecoder.sv)
In the decoder, RISC-V's instruction format is decoded to SoomRV's internal format.

### [Rename](../src/Rename.sv)
In the Rename module, we assign `sqN`s and `tagDst` to instructions. Operand registers are also renamed to corresponding tags using the RenameTable.
Some instructions are even eliminated, i.e. executed entirely within rename. This includes, for example, NOPs or loads of small immediates.

### [IssueQueue](../src/IssueQueue.sv)
Instructions from rename are placed into an issue queue. There, instructions wait until all operands and functional units are ready for their execution. Once ready, uOps are issued, i.e. dequeued from the issue queue.

Possibly, an instruction from rename is placed into _multiple_ issue queues,
to generate multiple uOps. This is currently only used by read-modify-write atomic instructions.
This makes `IssueQueue` the official transition from instruction to uOp, though we use these terms very lightly.

### [Load](../src/Load.sv)
After a uOp is issued, its operands have to be loaded.
This is done by Load, which accesses the register file and/or forwarded operands.
To reduce duplicate opcodes, Load can be instructed to use the immediate value as the second operand (instead of a register) using the `immB` field.

Load also accesses the PCFile, in case instructions need to known their program counter or branch prediction state during execution.
By re-loading this information from the PCFile in Load, we do not have to store it in the issue queues.

### Execute
Execution happens in a variety of functional units. Generally, these just compute a result and write it to the register file. In addition, some FUs also handle branches and memory access.

#### [IntALU](../src/IntALU.sv)
This is the go-to place for integer computation. It also handles all branches,
except immediate jumps without a link register. These are handled by the decoder, as they do not read from or write to registers.

Branch target information is sent from `IntALU`s to the branch predictor in the `BTUpdate` struct.
Sending of branch _direction_ information is deferred until commit, to avoid pollution with speculatively executed branches.

#### [AGU](../src/AGU.sv)
AGUs perform address calculation and translation. Afterwards, they forward load/store uOps to responsible functional units of the memory subsystem.

### [ROB](../src/ROB.sv)
After their execution completes, instructions are marked as completed in the ROB. If all previous instructions have been committed, and no misprediction was made, the ROB will then eventually commit the instructions.

While an instruction's ROB entry only becomes ready to commit after execution of the instruction, the entry is already created after rename. This is required as the ROB is used to recover Rename state after a mispredict.

The ROB also stores flags for every instruction. A flag may be set during the execution of an instruction to adjust commit behavior. For example, `FLAGS_ILLEGAL_INSTR` can be set to trigger an exception after commit; while `FLAGS_ORDERING` will flush the pipeline before continuing execution.

### [LoadBuffer](../src/LoadBuffer.sv)
The load buffer stores every executed but not-yet-committed load. This is used for detecting load order mispredicts (if a load has been executed before a store on which it depends).
We also use the LoadBuffer to store deferred loads until they become ready for execution.

### [StoreQueue](../src/StoreQueue.sv)
The store queue stores every executed store. After a store commits, it is handed over to the StoreQueueBackend.
In addition, the store queue forwards stored data to loads. All non-MMIO loads do a lookup in the store queue simultaneously to reading from cache.

### [StoreQueueBackend](../src/StoreQueueBackend.sv)
The SQB essentially acts as an issue queue for stores, the difference to other issue queues being that stores may one be executed _after_ commit as there's no rollback mechanism for them. The SQB receives committed stores from the SQ, then fuses and executes them. All stores going to the same 16-byte region are fused as cache write ports are 16-byte wide. This conveniently also removes the need for store alias checking.

### [LoadStoreUnit](../src/LoadStoreUnit.sv)
The LSU handles memory access at a low level. It executes loads and stores by accessing cache, and also handles cache misses if they occur.
All stores entering the LSU come from the StoreQueue. Loads commonly enter directly from the load AGU, but may also come from the LoadBuffer or PageWalker.

#### [BypassLSU](../src/BypassLSU.sv)
The BLSU handles external MMIO. Instead of reading cache, it communicates with the memory controller directly to access MMIO devices. It may also be used to implement regular loads/stores which bypass cache in the future.

### [MemoryController](../src/MemoryController.sv)
The memory controller handles transfers of cache lines between cache and main memory.
Unlike all other modules, it is implemented outside of the SoomRV `Core` module.
Currently, a custom 32-bit bidirectional memory bus is used, which was implemented because of limited IO count on the OpenMPW shuttles. This bus will be replaced by a standard Wishbone or AXI bus.
