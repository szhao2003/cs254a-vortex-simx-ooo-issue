# Vortex SimX four-entry issue window

This project adds restricted out-of-order issue to Vortex SimX. Each warp can issue an independent integer ALU instruction while an older instruction waits. The project also includes an optional RTL-style GTO arbiter and a standalone RTL window for estimating hardware costs.

## 1. Set up Ubuntu

Use Ubuntu 22.04, including Ubuntu under WSL 2. Run the commands below in Bash. Keep the Vortex checkouts in the Linux home directory.

```bash
sudo apt-get update
sudo apt-get install -y git python3 build-essential cmake ccache pkg-config \
    zlib1g-dev libtinfo-dev libncurses-dev uuid-dev libboost-serialization-dev \
    libpng-dev libhwloc-dev ca-certificates wget curl bzip2 xz-utils unzip
git clone --branch final-evaluation https://github.com/szhao2003/cs254a-vortex-simx-ooo-issue.git
cd cs254a-vortex-simx-ooo-issue
```

## 2. Build stock and patched Vortex

Run this block from the project repository root. It creates two checkouts at the same upstream revision and installs the pinned RV32 toolchain.

```bash
set -e
project="$PWD"
base=da55a516a48b49013724f697d3c12a48932b449f
stock="$HOME/vortex-stock-da55a516"
patched="$HOME/vortex-ooo-da55a516"
tools="$HOME/vortex-tools-v3.0.2"

for checkout in "$stock" "$patched"; do
    git init "$checkout"
    git -C "$checkout" fetch --depth=1 https://github.com/vortexgpgpu/vortex.git "$base"
    git -C "$checkout" checkout --detach FETCH_HEAD
    git -C "$checkout" submodule update --init --recursive --depth 1
    mkdir -p "$checkout/build"
    (cd "$checkout/build" && ../configure --xlen=32 --tooldir="$tools")
done

git -C "$patched" apply --check "$project/patches/simx_ooo_window_da55a516_gto.patch"
git -C "$patched" apply "$project/patches/simx_ooo_window_da55a516_gto.patch"

(cd "$stock/build" && ./ci/toolchain_install.sh --riscv32 --llvm --libc32 --libcrt32)

for checkout in "$stock" "$patched"; do
    (
        cd "$checkout/build"
        make -C ../third_party softfloat
        make -C ../third_party ramulator
        make -C sw/kernel -j4
        make -C sw/runtime/stub -j4
    )
done
```

## 3. Check the implementation

Run this from the project repository root in the same Bash session as setup. If you opened a new terminal, set `stock`, `patched`, and `tools` to the paths from Step 2 first. Run one experiment at a time because the scripts rebuild the simulator in the same build directory.

```bash
SIMX_GTO=0 bash tests/correctness/run_checkpoint.sh "$stock" "$patched" "$tools" ./validation-output
```

The quick check uses stock warp arbitration to check that disabling the window reproduces the stock issue trace. Expect 168 instructions in all three runs. The stock and patched in-order runs take 622 cycles, and the out-of-order run takes 619 cycles. The script also checks retry after an injected rejection, register hazards, lane masks, and store ordering. See the trace and release logs in each output subdirectory.

## 4. Reproduce performance results

Use the same paths from setup. In the GTO experiments, B1 is patched in-order issue and O4 enables the four-entry window. Both use GTO. B0 in the controlled matrix uses upstream arbitration.

```bash
python3 tests/b0_probe/run_matrix.py "$stock" "$patched" "$tools" \
    ./matrix-logs ./matrix.csv --gto
bash scripts/run_gto_sgemm.sh "$patched" "$tools" ./sgemm-logs
bash scripts/run_gto_memory.sh "$patched" "$tools" ./memory-logs
```

The matrix fixes the number of outputs and varies independent instruction count, position, and warp count. The SGEMM script compares GreedyRR and GTO at one and four cores. The memory script reports D-cache and off-chip memory counters for SGEMM and a fixed-workload probe. The matrix reference is in [results/gto_window_matrix.csv](results/gto_window_matrix.csv).

For the paper-listed OpenCL workloads, install the OpenCL headers and loader and add the pinned PoCL package.

```bash
sudo apt-get install -y opencl-headers ocl-icd-opencl-dev
(cd "$patched/build" && ./ci/toolchain_install.sh --pocl)
bash scripts/run_gto_opencl.sh "$patched" "$tools" ./opencl-logs
```

The OpenCL runs use 32 configured warps per core and four lanes per warp. The input sizes come from the defaults in the upstream revision cited by the paper. The artifact's exact launch arguments are unverified. For example, four-core GTO `sgemm2` takes 13,271 cycles in order and 12,593 with the window enabled. See [application cycle counts](results/gto_app_cycles.csv).

To run the three-launch regression, select `cores=1` or `cores=4` and run the following from the project repository root.

```bash
cores=4
(
    cd "$patched/build"
    export CONFIGS="-DVX_CFG_NUM_CORES=$cores" MAKEFLAGS=-j4 SIMX_GTO=1 SIMX_OOO_STATS=1
    make -C tests/regression/multikernel
    for window in 0 1; do
        SIMX_OOO_WINDOW=$window ./ci/blackbox.sh --driver=simx --app=multikernel --args=-n256
    done
)
```

## 5. Reproduce the RTL cost estimate

Install Verilator with `--binary` and timing support, Yosys with ABC, and OpenSTA. Use the [Nangate45 typical Liberty file](https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts/blob/master/flow/platforms/nangate45/lib/NangateOpenCellLibrary_typical.lib). Its SHA-256 for the recorded run is `8d540a4d4cf6d09d27c87ad067857a9c0c2eeb023ab7a56e058cd3113db4e9b1`.

The runner looks for `verilator`, `yosys`, and `sta` on your PATH. If you installed them elsewhere, set `VERILATOR`, `YOSYS`, and `STA` to the corresponding executable paths.

```bash
bash scripts/run_rtl_window.sh ./rtl-output /absolute/path/to/NangateOpenCellLibrary_typical.lib
```

The script runs the Verilator testbench, maps both variants with Yosys, and reports OpenSTA setup slack at a 2 ns clock period. The reference used Verilator 5.028, Yosys 0.57+157, and OpenSTA 2.0.17. See [results/rtl_window_cost.csv](results/rtl_window_cost.csv). The estimates apply to the standalone window before layout.
