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
