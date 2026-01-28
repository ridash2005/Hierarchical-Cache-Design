# Hierarchical Cache Design Interface Specification

This document defines the interface signals and protocols for the `hierarchical_cache_top` module. The design uses SystemVerilog Interfaces and Structs for a clean, modular connection, but can be viewed as standard bus protocols.

## Top Level Interface

### Clocks and Resets
| Signal | Direction | Width | Description |
|--------|-----------|-------|-------------|
| `clk` | Input | 1 | System Clock. All logic is positive-edge triggered. |
| `rst_n` | Input | 1 | Active Low Asynchronous Reset. |

### CPU Interface (L1)
The top module exposes two ports for the CPU: Instruction Cache (L1I) and Data Cache (L1D). Both share the same request/response protocol.

**Instruction Port (`cpu_l1i_req_i` / `cpu_l1i_resp_o`)**
**Data Port (`cpu_l1d_req_i` / `cpu_l1d_resp_o`)**

#### Request Struct (`cache_req_t`)
| Field | Width | Description |
|-------|-------|-------------|
| `addr` | 32 | Physical Address. |
| `data` | 32 | Write Data (for Single Word Writes). |
| `cmd` | 2 | Command: `READ` (00), `WRITE` (01), `FLUSH` (10). |
| `valid` | 1 | Master indicates request is valid. |
| `is_burst`| 1 | `0` for Word Access, `1` for Line Access (Internal/DMA). CPU typically uses 0. |
| `byte_en` | 4 | Byte Enable for writes (Not fully supported in current demo version). |

#### Response Struct (`cache_resp_t`)
| Field | Width | Description |
|-------|-------|-------------|
| `data` | 32 | Read Data (for Word Reads). |
| `ready` | 1 | Slave indicates it is ready to accept a request. Handshake completes when `valid` && `ready`. |
| `valid` | 1 | Slave indicates Read Data is valid or Write is complete. |
| `error` | 1 | Indicates error response (e.g., bus error). |

### Main Memory Interface
The L3 Cache acts as the master to the Main Memory (DRAM).

**Memory Port (`mem_req_o` / `mem_resp_i`)**

#### Request (Master: L3 -> Slave: Memory)
- **Commands**: READ, WRITE.
- **Bursts**: Always Line Access (`is_burst=1`).
- **Data**: `line_data` (512-bit) used for Writebacks.

#### Response (Slave: Memory -> Master: L3)
- **Data**: `line_data` (512-bit) return for Reads.
- **Latency**: Variable. Cache waits for `valid`.

## Handshake Protocol
The interface uses a simplified handshake similar to AXI-Lite/AXI-Stream.
1. **Request**: Master asserts `req.valid` and stable control signals/data.
2. **Acceptance**: Slave asserts `resp.ready` when it can accept. Transaction is "Accepted" on posedge `clk` where `req.valid && resp.ready` is high.
3. **Completion**:
   - For **Write**: Slave asserts `resp.valid` (and `resp.ready`) usually immediately or after operation.
   - For **Read**: Slave asserts `resp.valid` and provides `resp.data` when data is available. Master must capture data when `resp.valid` is high.

## Parameters
See `rtl/include/cache_pkg.sv` for system parameters.
- `DATA_WIDTH`: 32 bits
- `CACHE_LINE_SIZE`: 512 bits (64 Bytes)
- `ADDR_WIDTH`: 32 bits
