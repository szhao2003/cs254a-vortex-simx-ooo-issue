"""Verify the B1/O4 probe and the debug build's one-shot issue rejection."""

import re
import sys
from collections import Counter
from pathlib import Path


def events(trace, marker):
    pattern = rf"^TRACE\s+(\d+): [^\n]*{marker}[^\n]*\(#(\d+)\)$"
    return [(int(cycle), int(uuid)) for cycle, uuid in re.findall(pattern, trace, re.M)]


def load_run(path, instructions):
    trace = (path / "trace.log").read_text()
    assert "PASSED!" in trace, path
    report = next(line for line in trace.splitlines() if line.startswith("WINDOW_STATS "))
    counters = {key: int(value) for key, value in re.findall(r"(\w+)=(\d+)", report)}
    issued = events(trace, "pipeline issue:")
    bypassed = events(trace, "window bypass:")
    assert len(issued) == counters["issued"] == instructions, path
    assert len(bypassed) == counters["bypassed"], path
    assert len({uuid for _, uuid in issued}) == len(issued), path
    assert len(events(trace, "operand reject:")) == counters["operand_rejects"], path
    return trace, issued, bypassed, counters


def main():
    root = Path(sys.argv[1])
    b0 = (Path(sys.argv[2]) / "trace.log").read_text()
    instructions = int(sys.argv[3]) if len(sys.argv) > 3 else 180
    b1, b1_issues, b1_bypasses, b1_stats = load_run(root / "b1", instructions)
    o4, o4_issues, o4_bypasses, o4_stats = load_run(root / "o4", instructions)
    retry, retry_issues, retry_bypasses, retry_stats = load_run(root / "retry", instructions)

    assert events(b0, "pipeline issue:") == b1_issues
    assert f"cycles={sys.argv[4] if len(sys.argv) > 4 else 663}" in b1 and not b1_bypasses and b1_stats["blocked_ready"] > 0
    assert f"cycles={sys.argv[5] if len(sys.argv) > 5 else 661}" in o4 and len(o4_bypasses) == 4 and o4_stats["blocked_ready"] > 0
    expected = Counter(uuid for _, uuid in b1_issues)
    assert Counter(uuid for _, uuid in o4_issues) == expected
    assert Counter(uuid for _, uuid in retry_issues) == expected

    [(rejected_at, rejected_uuid)] = events(retry, "operand reject: injected=1")
    assert retry_stats["bypass_operand_rejects"] >= 1
    assert any(uuid == rejected_uuid for _, uuid in o4_bypasses)
    [(accepted_at, _)] = [event for event in retry_bypasses if event[1] == rejected_uuid]
    assert accepted_at > rejected_at
    assert (accepted_at, rejected_uuid) in retry_issues
    [(operands_at, _)] = [
        event for event in events(retry, "pipeline operands:") if event[1] == rejected_uuid
    ]
    assert operands_at > accepted_at
    print(f"PASS: #{rejected_uuid} rejected at {rejected_at}, issued once at {accepted_at}, "
          f"operands at {operands_at}. All three runs issued the same {instructions} UUIDs.")


if __name__ == "__main__":
    main()
