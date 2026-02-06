
import os

files = [
    "rtl/include/cache_pkg.sv",
    "rtl/common/sram_array.sv",
    "rtl/common/unified_cache.sv",
    "rtl/common/mem_arbiter_2to1.sv",
    "rtl/l1_cache/l1_cache.sv",
    "rtl/hierarchical_cache_top.sv",
    "tb/tb_hierarchical_cache.sv",
]

with open("all_in_one.sv", "w") as fout:
    for f in files:
        if os.path.exists(f):
            with open(f, "r") as fin:
                fout.write(f"\n// --- START OF {f} ---\n")
                fout.write(fin.read())
                fout.write("\n")
        else:
            print(f"Warning: {f} not found")
