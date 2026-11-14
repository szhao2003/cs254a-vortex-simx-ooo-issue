"""Build and run the controlled OOO matrix from WSL."""

import argparse
import csv
import hashlib
import os
import re
import subprocess
from pathlib import Path


COMMIT = "b447578d9f3bb116d658c614cf3407153f0536da"
GTO_COMMIT = "da55a516a48b49013724f697d3c12a48932b449f"
CASES = [(f"count{n}", n, 0) for n in (0, 1, 2, 4, 8)] + [
    ("position3", 1, 2),
    ("position5", 1, 4),
]
WARPS = (1, 2, 4)


def command(args, cwd, log=None, env=None):
    if log is None:
        return subprocess.check_output(args, cwd=cwd, env=env, text=True).strip()
    with log.open("w") as stream:
        result = subprocess.run(args, cwd=cwd, env=env, stdout=stream, stderr=subprocess.STDOUT)
    if result.returncode:
        raise RuntimeError(f"{args[0]} failed ({result.returncode}); see {log}")
    return log.read_text()


def kernel_source(count, preceding):
    # The position cases move the same four dependent fillers around the work.
    filler = "addi %[sum], %[sum], 0"
    independent = [f"xor %[work{i}], %[src0], %[src0]" for i in range(count)]
    consume = [f"or %[sum], %[sum], %[work{i}]" for i in range(count)]
    instructions = [
        "lw %[lhs], 0(%[src0])",
        "lw %[rhs], 0(%[src1])",
        "add %[sum], %[lhs], %[rhs]",
        *([filler] * preceding),
        *independent,
        *([filler] * (4 - preceding)),
        *consume,
        "sw %[sum], 0(%[dst])",
    ]
    outputs = [f'[{name}] "=&r"({name})' for name in ("lhs", "rhs", "sum")]
    outputs += [f'[work{i}] "=&r"(work{i})' for i in range(count)]
    extra = "".join(f", work{i}" for i in range(count))
    asm = "\n".join(f'            "{instruction}\\n\\t"' for instruction in instructions)
    return f'''#include <vx_spawn2.h>
#include "common.h"

__kernel void kernel_main(kernel_arg_t* __UNIFORM__ arg) {{
    auto src0 = reinterpret_cast<const TYPE*>(arg->src0_addr);
    auto src1 = reinterpret_cast<const TYPE*>(arg->src1_addr);
    auto dst = reinterpret_cast<TYPE*>(arg->dst_addr);
    const size_t x = blockIdx.x * blockDim.x + threadIdx.x;
    const size_t start = x * arg->task_size;
    for (size_t i = 0; i < arg->task_size; ++i) {{
        const size_t index = start + i;
        TYPE lhs, rhs, sum{extra};
        asm volatile(
{asm}
            : {", ".join(outputs)}
            : [src0] "r"(src0 + index), [src1] "r"(src1 + index),
              [dst] "r"(dst + index)
            : "memory");
    }}
}}
'''


def stage_app(repo):
    build = repo / "build"
    app = build / "tests/regression/window_matrix"
    app.mkdir(exist_ok=True)
    demo = repo / "tests/regression/demo"
    host = (demo / "main.cpp").read_text()
    old = "uint32_t num_blocks = (total_threads + threads_per_block - 1) / threads_per_block;"
    assert host.count(old) == 1
    host = host.replace(old, "uint32_t num_blocks = 8;")
    host = host.replace("uint32_t total_threads = num_cores * num_warps * num_threads;", "")
    host = host.replace(
        "  // determine 2D launch dimensions",
        '  std::cout << "CONFIG cores=" << num_cores << ", warps=" << num_warps\n'
        '            << ", threads=" << num_threads << std::endl;\n'
        "  // determine 2D launch dimensions",
    )
    (app / "main.cpp").write_text(host)
    (app / "common.h").write_bytes((demo / "common.h").read_bytes())
    makefile = (build / "tests/regression/demo/Makefile").read_text()
    makefile = makefile.replace("PROJECT := demo", "PROJECT := window_matrix")
    makefile = re.sub(r"^SRC_DIR := .*", "SRC_DIR := $(CURDIR)", makefile, flags=re.M)
    (app / "Makefile").write_text(makefile)
    return app


def run_case(app, build, mode, warps, out, gto=False):
    env = os.environ.copy()
    env.update(
        LD_LIBRARY_PATH=str(build / "sw/runtime"),
        VORTEX_DRIVER="simx",
        SIMX_GTO="1" if gto and mode != "b0" else "0",
        SIMX_OOO_WINDOW="1" if mode == "o4" else "0",
        SIMX_OOO_STATS="1",
        SIMX_OOO_REJECT_FIRST_BYPASS="0",
    )
    reports = []
    for repeat in (1, 2):
        log = out / f"{mode}_{repeat}.log"
        report = command(["./window_matrix", "-n4", "-x4", "-y1"], app, log, env)
        assert "PASSED!" in report and "number of points: 128" in report, log
        assert f"CONFIG cores=1, warps={warps}, threads=4" in report, log
        assert "grid_dim=8x1, block_dim=4x1" in report, log
        perf = re.search(r"^PERF: instrs=(\d+), cycles=(\d+),", report, re.M)
        assert perf, log
        stats = re.findall(r"^WINDOW_STATS .*", report, re.M)
        if mode == "b0":
            assert not stats, log
            counters = {}
        else:
            assert len(stats) == 1 and f"mode={mode}" in stats[0], log
            counters = {key: int(val) for key, val in re.findall(r"(\w+)=(\d+)", stats[0])}
        reports.append(dict(instrs=int(perf[1]), cycles=int(perf[2]), **counters))
    assert reports[0] == reports[1], out
    return reports[0]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("b0", "modified", "tooldir", "logs", "results"):
        parser.add_argument(name, type=Path)
    parser.add_argument("--warps", nargs="+", type=int, choices=WARPS, default=WARPS)
    parser.add_argument("--gto", action="store_true", help="Use RTL-style GTO on the updated patched checkout")
    args = parser.parse_args()
    revision = GTO_COMMIT if args.gto else COMMIT
    for repo in (args.b0, args.modified):
        assert command(["git", "rev-parse", "HEAD"], repo) == revision
    assert not command(["git", "status", "--porcelain"], args.b0)
    assert "SIMX_OOO_WINDOW" in (args.modified / "sim/simx/core.cpp").read_text()
    if args.gto:
        assert "SIMX_GTO" in (args.modified / "sim/simx/core.cpp").read_text()
    args.logs.mkdir(parents=True, exist_ok=True)
    args.results.parent.mkdir(parents=True, exist_ok=True)
    b0_build, modified_build = (repo / "build" for repo in (args.b0, args.modified))
    for name, build in (("b0", b0_build), ("modified", modified_build)):
        command(["../configure", "--xlen=32", f"--tooldir={args.tooldir}"], build,
                args.logs / f"{name}_configure.log")
        command(["make", "-C", "sw/runtime/stub", "-j4"], build, args.logs / f"{name}_stub.log")
    app = stage_app(args.modified)
    objdump = args.tooldir / "llvm-vortex/bin/llvm-objdump"
    fields = ["warps", "case", "independent", "preceding_fillers", "kernel_sha256", "mode",
              "instrs", "cycles", "issued", "bypassed", "blocked_no_candidate",
              "blocked_dependency", "blocked_fu", "blocked_ready", "operand_rejects",
              "bypass_operand_rejects"]
    with args.results.open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields)
        writer.writeheader()
        for warps in args.warps:
            warps_dir = args.logs / f"w{warps}"
            warps_dir.mkdir(exist_ok=True)
            config = f"CONFIGS=-DVX_CFG_NUM_WARPS={warps}"
            for name, build in (("b0", b0_build), ("modified", modified_build)):
                print(f"Building {name}, {warps} warps", flush=True)
                command(["make", "-C", "sw/runtime/simx", "-j4", config], build,
                        warps_dir / f"{name}_runtime.log")
            command(["make", "-C", "sw/kernel", "-j4", config], modified_build,
                    warps_dir / "kernel_runtime.log")
            for name, independent, preceding in CASES:
                out = warps_dir / name
                out.mkdir(exist_ok=True)
                source = kernel_source(independent, preceding)
                (app / "kernel.cpp").write_text(source)
                (out / "kernel.cpp").write_text(source)
                command(["make", "-j4", config], app, out / "build.log")
                command([str(objdump), "-d", "kernel.elf"], app, out / "kernel.disasm")
                sha = hashlib.sha256((app / "kernel.vxbin").read_bytes()).hexdigest()
                runs = {mode: run_case(app, b0_build if mode == "b0" else modified_build,
                                       mode, warps, out, args.gto) for mode in ("b0", "b1", "o4")}
                if not args.gto:
                    assert runs["b0"] == {key: runs["b1"][key] for key in ("instrs", "cycles")}, out
                assert runs["o4"]["instrs"] == runs["b1"]["instrs"] == runs["b0"]["instrs"], out
                for mode, result in runs.items():
                    writer.writerow(dict(warps=warps, case=name, independent=independent,
                                         preceding_fillers=preceding, kernel_sha256=sha, mode=mode,
                                         **result))
                stream.flush()
                print(f"w{warps} {name}: " + ", ".join(
                    f"{mode}={result['cycles']}" for mode, result in runs.items()), flush=True)


if __name__ == "__main__":
    main()
