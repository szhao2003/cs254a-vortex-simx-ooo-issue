# cs254a-vortex-simx-ooo-issue
A four-entry per-warp out-of-order issue window for Vortex SimX, with correctness tests and baseline performance comparisons.

## Baseline setup milestone

This milestone records the original Vortex SimX build and demo smoke test. The upstream source is Vortex v3.0 at commit `b447578d9f3bb116d658c614cf3407153f0536da`, including its pinned submodules. The run used WSL Ubuntu 22.04, the RV32 toolchain release v3.0.1, and the default SimX configuration.

## Reproduce the stock demo

Run these commands in Ubuntu. The toolchain installer is for a fresh toolchain directory. The recorded run used an existing installation of the same release.

```bash
sudo apt-get update
sudo apt-get install -y git python3 build-essential cmake ccache zlib1g-dev libtinfo-dev libncurses-dev uuid-dev libboost-serialization-dev libpng-dev libhwloc-dev pkg-config ca-certificates wget curl bzip2 xz-utils

git clone --no-checkout https://github.com/vortexgpgpu/vortex.git vortex-baseline
cd vortex-baseline
git checkout --detach b447578d9f3bb116d658c614cf3407153f0536da
git submodule update --init --recursive
git status --short

toolchain_dir="$HOME/vortex-tools-v3.0.1"
mkdir -p build
cd build
../configure --xlen=32 --tooldir="$toolchain_dir"
./ci/toolchain_install.sh --riscv32 --llvm --libc32 --libcrt32

make -C ../third_party softfloat
make -C ../third_party ramulator
make -C sim/simx -j4
make -C sw/kernel -j4
make -C sw/runtime/stub -j4
make -C sw/runtime/simx -j4
make -C tests/regression/demo -j4
./ci/blackbox.sh --driver=simx --app=demo
```

The stock demo verified 1,024 integer results with a 4×1 grid and 4×1 blocks. It printed `PASSED!` and reported 2,444 instructions and 6,448 simulated cycles. See the [recorded demo output](baseline/demo-smoke.log).

## Original SimX issue baseline (B0)

The probe places a load-dependent addition ahead of an independent address calculation in the same warp. Run it after building the stock demo. From this repository, pass the absolute paths to the stock Vortex checkout and its RV32 toolchain.

```bash
bash baseline/b0-probe/run.sh /path/to/vortex-baseline /path/to/vortex-tools-v3.0.1 ./b0-results
```

The debug and release runs both verify 16 outputs and report 180 instructions and 663 simulated cycles. In warp 0, the independent addition decodes at cycle 498 and issues at cycle 534, one cycle after the older load-dependent addition issues. See the [recorded trace excerpt](baseline/b0-probe/trace-excerpt.log) and [disassembly](baseline/b0-probe/kernel.disasm).

## Correctness tests

The [correctness tests](tests/correctness/README.md) cover register dependencies, lane masks, store ordering, and retry after an operand-input rejection.

## Checkpoint 2 implementation

Vortex already has a four-entry instruction buffer per warp. With out-of-order issue enabled, SimX checks younger entries when the head cannot issue. A younger single-uop integer ALU instruction can pass an older entry only if the register checks and ordering rules allow it. The existing scoreboard tracks instructions that have already issued. The window also checks for RAW, WAR, and WAW hazards against older instructions still in the buffer.

The design keeps Vortex's existing scoreboard, instruction buffer, and warp arbitration. sCROOGe uses a separate issue buffer and in-flight buffer. Here, the change is limited to how SimX picks an instruction within a warp.

| Mode | Source | Issue behavior |
| --- | --- | --- |
| B0 | Pinned stock Vortex checkout | Head of the buffer only |
| B1 | Patched checkout, `SIMX_OOO_WINDOW=0` | Head of the buffer only |
| O4 | Patched checkout, `SIMX_OOO_WINDOW=1` | Eligible younger instructions can issue early |

### Run the checkpoint tests

Keep the stock checkout from the baseline setup above. Create a second checkout at the same revision, apply the patch, and build it with the same RV32 toolchain. Run this from the root of this project repository in Ubuntu. Set the three paths for your machine.

```bash
stock="$HOME/vortex-baseline"
patched="$HOME/vortex-checkpoint"
tools="$HOME/vortex-tools-v3.0.1"

git clone --no-checkout https://github.com/vortexgpgpu/vortex.git "$patched"
git -C "$patched" checkout --detach b447578d9f3bb116d658c614cf3407153f0536da
git -C "$patched" submodule update --init --recursive
git -C "$patched" apply --check "$PWD/patches/simx_ooo_window.patch"
git -C "$patched" apply "$PWD/patches/simx_ooo_window.patch"

(
    set -e
    mkdir -p "$patched/build"
    cd "$patched/build"
    ../configure --xlen=32 --tooldir="$tools"
    make -C ../third_party softfloat
    make -C ../third_party ramulator
    make -C sw/kernel -j4
    make -C sw/runtime/stub -j4
)

bash tests/correctness/run_checkpoint.sh "$stock" "$patched" "$tools" ./checkpoint-results
```

The issue probe reports 180 instructions in all three modes. B0 and B1 take 663 cycles and have identical issue traces. O4 takes 661 cycles and records four bypasses. The retry check deliberately rejects the first bypass once and verifies that the instruction later issues exactly once. The lane-mask check verifies 32 masked bypasses and 32 cases where a younger XOR waits for an older store to issue. Each run saves its trace and release log under the output directory.
