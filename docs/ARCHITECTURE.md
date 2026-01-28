# Architectural Specification

## Overview
The Hierarchical Cache Design provides a 3-level memory hierarchy to bridge the latency gap between a high-speed CPU and off-chip DRAM.

## Microarchitecture
### L1 Cache (Instruction & Data)
- **Parameters**: 32KB per cache, 4-Way Set Associative.
- **Write Policy**: Write-Back, Write-Allocate.
- **Replacement**: Pseudo-LRU (Counter-based Victim Selection).
- **FSM States**:
  - `IDLE`: Waits for CPU Request.
  - `COMPARE`: Checks Tag Arrays for Hit.
    - **Hit**: Read data from Data Array or Write to Data Array (and set Dirty).
    - **Miss**: Check Victim. If Dirty, `WRITEBACK`. Else `ALLOCATE`.
  - `WRITEBACK`: Evict victim line to L2.
  - `ALLOCATE_WAIT`: Fetch new line from L2.

### L2 Cache (Unified)
- **Parameters**: 256KB, 8-Way Set Associative.
- **Role**: Backing store for L1s. Handles both Instruction and Data misses.
- **Flow**: Similar to L1, but capable of handling Burst Transactions (Line-wide).

### L3 Cache (LLC)
- **Parameters**: 1024KB (1MB) or larger.
- **Role**: Last Level Cache interacting with Main Memory.

## Data Structures
Each Cache Way consists of two SRAM arrays:
1.  **Tag Array**: Stores Tag bits, Valid bit, and Dirty bit.
    - Width = `TAG_WIDTH + 2`
2.  **Data Array**: Stores the entire Cache Line.
    - Width = `CACHE_LINE_SIZE` (512 bits)
    - *Future Optimization*: Split Loop for Byte Enable or Banked Architecture.

## Interface Protocol (Cache-to-Cache)
The `mem_if` interface simplifies connections:
- Lower Level (Master) -> Upper Level (Slave) : `req` Channel
- Upper Level (Slave) -> Lower Level (Master) : `resp` Channel

This allows `l1_cache` to be a Master on its `mem_port` (connecting to L2) and a Slave on its `cpu_port`.

## Synthesis Notes
- **SRAM**: Inferred as Distributed RAM or Block RAM depending on size and tool settings.
- **FSM**: Standard formatting for FSM extraction.
- **Arbitration**: `mem_arbiter_2to1` uses a fixed priority or round-robin locking mechanism to ensure fairness.
