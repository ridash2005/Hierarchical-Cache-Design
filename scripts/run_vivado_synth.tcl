# Vivado Synthesis Script
# Usage: vivado -mode batch -source scripts/run_vivado_synth.tcl

# 1. Settings
set project_name "hierarchical_cache"
set top_module "hierarchical_cache_top"
set part "xc7z020clg400-1" ;# Example Part (Zynq-7000)

# 2. Setup
create_project -force $project_name ./vivado_project -part $part

# 3. Add Sources
# Note regarding file order: Packages first!
add_files -norecurse {
    rtl/include/cache_pkg.sv
    rtl/include/mem_if.sv
    rtl/common/sram_array.sv
    rtl/common/mem_arbiter_2to1.sv
    rtl/common/unified_cache.sv
    rtl/l1_cache/l1_cache.sv
    rtl/l2_cache/l2_cache.sv
    rtl/l3_cache/l3_cache.sv
    rtl/hierarchical_cache_top.sv
}

# 4. Set Top
set_property top $top_module [current_fileset]
update_compile_order -fileset sources_1

# 5. Run Synthesis
puts "--- Starting Synthesis ---"
synth_design -top $top_module -part $part -flatten_hierarchy rebuilt

# 6. Report Utilization and Timing
report_utilization -file synthesis_utilization.rpt
report_timing_summary -file synthesis_timing.rpt

puts "--- Synthesis Complete ---"
# exit
