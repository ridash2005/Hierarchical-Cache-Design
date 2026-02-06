# Getting Started Guide

## Prerequisites
- **Simulation**: SystemVerilog compatible simulator (Vivado XSim, Verilator, Questasim/ModelSim, or Icarus Verilog with v12+).
- **Synthesis**: Xilinx Vivado (2020.2 or later recommended).

## Directory Structure
```
.
├── docs/           # Documentation
├── rtl/            # Source Code
│   ├── common/     # Shared modules (Arbiter, SRAM)
│   ├── include/    # Packages and Interfaces
│   ├── l1_cache/   # L1 I/D Cache Logic
│   ├── l2_cache/   # L2 Unified Cache Logic
│   └── l3_cache/   # L3 Last Level Cache Logic
├── scripts/        # Build/Run Scripts
└── tb/             # Testbench Files
```

## Running Simulation
The testbench `tb_hierarchical_cache` verifies the end-to-end flow from CPU -> L1 -> L2 -> L3 -> Memory.

### Using Icarus Verilog (Recommended for quick testing)
Icarus Verilog has limited support for complex SystemVerilog hierarchies. To resolve this, use the provided `concat.py` script to generate a single-file version of the RTL and TB.

1.  **Generate Single File**:
    ```bash
    python concat.py
    ```
2.  **Compile and Run**:
    ```bash
    iverilog -g2012 -s tb_hierarchical_cache -o sim.vvp all_in_one.sv
    vvp sim.vvp
    ```

### Using Vivado XSim
1. Open Vivado.
2. In Tcl Console, add files:
    ```tcl
    add_files [glob rtl/include/*.sv rtl/common/*.sv rtl/l1_cache/*.sv rtl/hierarchical_cache_top.sv tb/*.sv]
    ```
3. Run Simulation -> Run Behavioral Simulation.

## Running Synthesis
To verify the design is synthesizable and check resource utilization:

1. Open a terminal (or Vivado Tcl Console).
2. Run the provided script:
   ```bash
   vivado -mode batch -source scripts/run_vivado_synth.tcl
   ```
3. Check `synthesis_utilization.rpt` for area results.

## Integration Guide (Black Box Usage)
1. Instantiate `hierarchical_cache_top` in your SoC wrapper.
2. Connect `clk` and `rst_n`.
3. Provide interface structs:
   - `cpu_l1i_req_i` / `cpu_l1i_resp_o` for Instruction Fetch.
   - `cpu_l1d_req_i` / `cpu_l1d_resp_o` for Data Access.
   - `mem_req_o` / `mem_resp_i` to your DDR Controller or Memory Model.
4. See `docs/INTERFACE.md` for signal details.
