#!/usr/bin/env bash
set -euo pipefail

repo=${1:?pass the absolute path to the Vortex source directory}
tooldir=${2:?pass the absolute path to the Vortex toolchain directory}
output=${3:?pass an output directory}
expected_commit=${VORTEX_BASE_COMMIT:-da55a516a48b49013724f697d3c12a48932b449f}
mode=${6:-b0}
if [[ $(git -C "$repo" rev-parse HEAD) != "$expected_commit" ]]; then
    echo "Expected Vortex base commit $expected_commit" >&2
    exit 1
fi
case "$mode" in
    b0|b1) export SIMX_OOO_WINDOW=0 ;;
    o4) export SIMX_OOO_WINDOW=1 ;;
    *) echo "Unknown mode: $mode (expected b0, b1, or o4)" >&2; exit 1 ;;
esac
if [[ $mode == b0 && -n $(git -C "$repo" status --porcelain) ]]; then
    echo "B0 requires a clean Vortex checkout at $expected_commit" >&2
    exit 1
fi
if [[ $mode != b0 ]] && ! grep -q 'SIMX_OOO_WINDOW' "$repo/sim/simx/core.cpp"; then
    echo "Apply patches/simx_ooo_window.patch before running $mode" >&2
    exit 1
fi

source_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
kernel=$(realpath -- "${4:-$source_dir/kernel.cpp}")
app_args=${5:--n1}
mkdir -p "$output"
output=$(cd "$output" && pwd)

cd "$repo/build"
../configure --xlen=32 --tooldir="$tooldir"
app=tests/regression/b0_probe
mkdir -p "$app"
cp "$kernel" "$app/kernel.cpp"
cp ../tests/regression/demo/common.h "$app/common.h"
sed 's|^VX_SRCS := .*|VX_SRCS := $(CURDIR)/kernel.cpp|' \
    tests/regression/demo/Makefile > "$app/Makefile"

make -C "$app" -j4 > "$output/build.log" 2>&1
"$tooldir/llvm-vortex/bin/llvm-objdump" -d "$app/kernel.elf" > "$output/kernel.disasm"
MAKEFLAGS=-j4 ./ci/blackbox.sh --driver=simx --app=b0_probe --args="$app_args" \
    --debug=4 --log=b0_probe.trace > "$output/trace_driver.log" 2>&1
cp b0_probe.trace "$output/trace.log"
MAKEFLAGS=-j4 ./ci/blackbox.sh --driver=simx --app=b0_probe --args="$app_args" \
    > "$output/${mode}_release.log" 2>&1
for log in "$output/trace.log" "$output/${mode}_release.log"; do
    grep -HF 'PASSED!' "$log"
    grep -HF 'PERF:' "$log"
done
