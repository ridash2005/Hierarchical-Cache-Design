![Cache System](https://img.shields.io/badge/SystemVerilog-Synthesizable-blue) ![License](https://img.shields.io/badge/License-MIT-green) ![Status](https://img.shields.io/badge/Status-Verified-success)

# Hierarchical Cache System (L1/L2/L3)

A professional, industry-grade, and modular 3-level cache memory subsystem design written in SystemVerilog. This project implements a fully synthesizable memory hierarchy featuring split L1 I/D caches, centralized L2, and Last-Level L3 cache, abstracting complexity behind a simple transactional interface.

---

## Key Features
*   **Modular Architecture**: Plug-and-play components for L1, L2, L3, and Arbiters.
*   **Synthesizable Design**: optimized for FPGA (Vivado) and ASIC flows.
*   **Configurable**: Parameters for Cache Size, Associativity, and Line Size.
*   **Standard Interface**: Simple Request/Ready/Valid handshake protocol (similar to AXI-Lite).
*   **Coherence Support**: Includes framework for MESI/MOESI (Basic Write-Back/Write-Allocate implemented).

## System Architecture

```mermaid
graph TD;
    CPU_L1I[CPU Instruction Port] --> L1I[L1 I-Cache];
    CPU_L1D[CPU Data Port] --> L1D[L1 D-Cache];
    L1I --> Arbiter;
    L1D --> Arbiter;
    Arbiter --> L2[L2 Unified Cache];
    L2 --> L3[L3 Last Level Cache];
    L3 --> MEM[Main Memory / DDR];
```

## Quick Links
*   [Getting Started](docs/GETTING_STARTED.md) - Simulation and Synthesis instructions.
*   [Interface Spec](docs/INTERFACE.md) - Signal definitions and Protocol details.
*   [Architecture](docs/ARCHITECTURE.md) - Deep dive into internal FSMs and Tag Arrays.

## Usage
This module is designed to be treated as a Black Box IP.

```systemverilog
hierarchical_cache_top u_cache_sys (
    .clk(system_clk),
    .rst_n(system_rst_n),
    .cpu_l1i_req_i(instr_bus_req),
    .cpu_l1i_resp_o(instr_bus_resp),
    .cpu_l1d_req_i(data_bus_req),
    .cpu_l1d_resp_o(data_bus_resp),
    .mem_req_o(ddr_req),
    .mem_resp_i(ddr_resp)
);
```

## Verification
The design includes a self-checking testbench (`tb/tb_hierarchical_cache.sv`) covering:
1.  Read/Write Hits.
2.  Cold Misses & Allocation.
3.  Write-Back mechanism verifying data integrity.
4.  End-to-End latency checks.

## Synthesis
Verified with Xilinx Vivado 2023.x.
Run `scripts/run_vivado_synth.tcl` to validate.

---
*Maintained by the Advanced Cache Design Team*
