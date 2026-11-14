"""Check the divergent store-boundary probe against its own disassembly."""

import re
import sys
from collections import defaultdict
from pathlib import Path


def main():
    output = Path(sys.argv[1])
    disasm = (output / "kernel.disasm").read_text()
    store_xor, legal_xor = re.findall(r"^([0-9a-f]+):.*\bxor\b", disasm, re.M)
    store_pc = f"{int(store_xor, 16) - 4:x}"
    assert re.search(rf"^{store_pc}:.*\bsw\b", disasm, re.M)
    trace = (output / "trace.log").read_text()
    assert "PASSED!" in trace and "number of points: 128" in trace
    event = re.compile(
        r"^TRACE\s+(\d+): .*?-(pipeline decode|pipeline issue|pipeline commit|window bypass):"
        r".*?wid=(\d+), cta_id=(\d+), tmask=([01]+), PC=0x([0-9a-f]+),.*\(#(\d+)\)$",
        re.M,
    )
    by_id = defaultdict(dict)
    stores = defaultdict(list)
    blocked_xors = defaultdict(list)
    bypasses = []
    for cycle, stage, warp, cta, mask, pc, uuid in event.findall(trace):
        by_id[uuid][stage] = (int(cycle), mask)
        key = warp, cta
        if pc == store_pc and stage == "pipeline issue":
            stores[key].append(int(cycle))
        if pc == store_xor and stage == "pipeline issue":
            blocked_xors[key].append(uuid)
        if stage == "window bypass":
            assert pc == legal_xor
            bypasses.append(uuid)
    assert len(bypasses) == len(set(bypasses)) == 32
    for uuid in bypasses:
        row = by_id[uuid]
        assert {row[stage][1] for stage in (
            "pipeline decode", "pipeline issue", "pipeline commit", "window bypass"
        )} == {"0101"}
    assert stores.keys() == blocked_xors.keys()
    observed_waits = 0
    for key, store_cycles in stores.items():
        assert len(store_cycles) == len(blocked_xors[key])
        for store_cycle, uuid in zip(store_cycles, blocked_xors[key]):
            row = by_id[uuid]
            assert store_cycle < row["pipeline issue"][0]
            observed_waits += row["pipeline decode"][0] < store_cycle
    assert observed_waits > 0
    print(f"PASS: 32 bypasses preserved a partial lane mask through commit; "
          f"{observed_waits} decoded XORs waited for an older store to issue.")


if __name__ == "__main__":
    main()
