#!/usr/bin/env bash
set -euo pipefail

repo=${1:?pass the absolute path to the Vortex source directory}
tooldir=${2:?pass the absolute path to the Vortex toolchain directory}
output=${3:?pass an output directory}
expected_commit=b447578d9f3bb116d658c614cf3407153f0536da
if [[ $(git -C "$repo" rev-parse HEAD) != "$expected_commit" ||
      -n $(git -C "$repo" status --porcelain) ]]; then
    echo "B0 requires a clean Vortex checkout at $expected_commit" >&2
    exit 1
fi

source_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
mkdir -p "$output"
output=$(cd "$output" && pwd)

cd "$repo/build"
../configure --xlen=32 --tooldir="$tooldir"
app=tests/regression/b0_probe
mkdir -p "$app"
cp "$source_dir/kernel.cpp" "$app/kernel.cpp"
cp ../tests/regression/demo/common.h "$app/common.h"
sed 's|^VX_SRCS := .*|VX_SRCS := $(CURDIR)/kernel.cpp|' \
    tests/regression/demo/Makefile > "$app/Makefile"

make -C "$app" -j4 > "$output/build.log" 2>&1
"$tooldir/llvm-vortex/bin/llvm-objdump" -d "$app/kernel.elf" > "$output/kernel.disasm"
MAKEFLAGS=-j4 ./ci/blackbox.sh --driver=simx --app=b0_probe --args=-n1 \
    --debug=4 --log=b0_probe.trace > "$output/trace_driver.log" 2>&1
cp b0_probe.trace "$output/trace.log"
MAKEFLAGS=-j4 ./ci/blackbox.sh --driver=simx --app=b0_probe --args=-n1 \
    > "$output/b0_release.log" 2>&1
for log in "$output/trace.log" "$output/b0_release.log"; do
    grep -HF 'PASSED!' "$log"
    grep -HF 'PERF:' "$log"
done
