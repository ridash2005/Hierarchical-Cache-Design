# Architectural Specification

## Overview
The Hierarchical Cache Design provides a 3-level memory hierarchy to bridge the latency gap between a high-speed CPU and off-chip DRAM.

```mermaid
graph LR;
    CPU((CPU)) -- "Word Req" --> L1[L1 I/D Cache];
    L1 -- "Line Req" --> Arb{Arbiter};
    Arb --> L2[L2 Unified Cache];
    L2 -- "Line Req" --> L3[L3 LLC];
    L3 -- "Line Req" --> DRAM[Main Memory];
```


## Microarchitecture
### L1 Cache (Instruction & Data)
- **Parameters**: 32KB per cache, 4-Way Set Associative.
- **Write Policy**: Write-Back, Write-Allocate.
- **Replacement**: Pseudo-LRU (Counter-based Victim Selection).
  - `UPDATE`: Post-refill synchronization cycle to allow SRAM output to settle before re-comparing.

#### L1 FSM Visualization
```mermaid
stateDiagram-v2
    [*] --> IDLE
    IDLE --> COMPARE: cpu_req_valid
    COMPARE --> IDLE: Hit (Done)
    COMPARE --> WRITEBACK: Miss & Victim Dirty
    COMPARE --> ALLOCATE_WAIT: Miss & Victim Clean
    WRITEBACK --> ALLOCATE_WAIT: mem_resp_ready
    ALLOCATE_WAIT --> UPDATE: mem_resp_valid
    UPDATE --> COMPARE: Re-sync
```


- **FSM States**: `IDLE`, `COMPARE`, `WRITEBACK_START` (Wait for Grant), `WRITEBACK_WAIT` (Wait for ACK), `FILL_REQ`, `FILL_WAIT`, `UPDATE`.

#### Unified FSM Visualization
```mermaid
stateDiagram-v2
    [*] --> IDLE
    IDLE --> COMPARE: prev_req_valid
    COMPARE --> IDLE: Hit
    COMPARE --> WRITEBACK_START: Miss & Dirty
    COMPARE --> FILL_REQ: Miss & Clean
    WRITEBACK_START --> FILL_REQ: accepted
    WRITEBACK_START --> WRITEBACK_WAIT: !accepted
    WRITEBACK_WAIT --> FILL_REQ: accepted
    FILL_REQ --> FILL_WAIT: accepted
    FILL_WAIT --> UPDATE: next_resp_valid
    UPDATE --> COMPARE: Re-sync
```


### L3 Cache (LLC)
- **Parameters**: 8MB (8192KB).
- **Role**: Last Level Cache interacting with Main Memory. Uses the same unified cache microarchitecture as L2.

## Data Structures
Each Cache Way consists of two SRAM arrays:
1.  **Tag Array**: Stores Tag bits, Valid bit, and Dirty bit.
    - Width = `TAG_WIDTH + 2`
2.  **Data Array**: Stores the entire Cache Line.
    - Width = `CACHE_LINE_SIZE` (512 bits)
    - *Future Optimization*: Split Loop for Byte Enable or Banked Architecture.

## Interface Protocol
For maximum tool compatibility (specifically **Icarus Verilog**), the hardware uses **Packed Structs** (`cache_req_t` and `cache_resp_t`) for all inter-module communication.

- **Request Channel**: Master drives `addr`, `data`, `line_data`, `cmd`, `valid`, `is_burst`.
- **Response Channel**: Slave drives `ready` (acceptance), `valid` (data return), `data`, `line_data`, `error`.

Modules unroll these structs into local logic signals within their `always` blocks to avoid simulator-specific limitations with direct struct member indexing.

## Transaction Flow (Read Miss Example)
```mermaid
sequenceDiagram
    participant CPU
    participant L1
    participant L2/L3
    participant MEM

    CPU->>L1: Word READ (Valid)
    L1->>L1: COMPARE (Miss)
    L1->>L2/L3: Line READ (Request)
    L2/L3->>MEM: Line READ (Refill)
    MEM-->>L2/L3: Line DATA (Valid)
    L2/L3->>L1: Line DATA (Valid)
    L1->>L1: UPDATE (Fill SRAM)
    L1-->>CPU: Word DATA (Valid)
```


## Synthesis Notes
- **SRAM**: Inferred as Distributed RAM or Block RAM depending on size and tool settings.
- **FSM**: Standard formatting for FSM extraction.
- **Arbitration**: `mem_arbiter_2to1` uses a fixed priority or round-robin locking mechanism to ensure fairness.
