#!/usr/bin/env python3
"""Build and test the native Bend kernel against an independent integer oracle.

Python supplies fixtures and expected outcomes; all observed transitions run in
src/inventory.bend. This script is test orchestration, not a gameplay adapter.
"""
from __future__ import annotations

import argparse
from collections import Counter
from dataclasses import asdict, dataclass
import hashlib
import itertools
import json
import os
from pathlib import Path
import random
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
MAX_U32 = 2**32 - 1
KEYS = {
    1: ("minecraft:stone", "{}"),
    2: ("minecraft:dirt", "{}"),
    3: ("minecraft:stone", "{name:a}"),
    4: ("minecraft:stone", "{name:b}"),
    5: ("minecraft:stone", "{ }"),
    6: ("sentinel", "locked"),
    7: ("outside", "guard"),
}


@dataclass(frozen=True)
class Case:
    label: str
    mode: str = "transfer"
    sc: int = 32
    dc: int = 5
    limit: int = 64
    requested: int = 16
    si: int = 0
    di: int = 1
    sk: int = 1
    dk: int = 1
    mk: int = 1
    logical: int = 3
    shape: int = 0

    def argument(self) -> str:
        return "|".join(str(value) for value in asdict(self).values())

    def initial(self) -> list[tuple[int, int]]:
        slots = [(self.sk, self.sc if self.sk else 0),
                 (self.dk, self.dc if self.dk else 0), (6, 17), (7, 23)]
        return slots[:3] if self.shape in (1, 2) else slots[:1] if self.shape == 3 else slots


def item_totals(slots: list[tuple[int, int]]) -> Counter:
    total = Counter()
    for code, count in slots:
        if code:
            total[KEYS[code]] += count
    return +total


def oracle(case: Case) -> tuple[str, list[tuple[int, int]]]:
    """Integer specification: decide eligibility, then clamp a single transfer.

    No Bend implementation, Nat recurrence, wrapping arithmetic, or production
    parser is used to construct expected results.
    """
    slots = case.initial()
    reject = lambda reason: (f"rejected:{reason}", slots)
    valid_paths = {0, 1} if case.shape == 1 else {0} if case.shape in (2, 3) else {0, 1, 2, 3}
    addressable = {index for index in valid_paths if index < case.logical}

    if case.mode == "new":
        if case.requested > 16 or case.di > 2**case.requested:
            return reject("invalid_stack")
        return "moved:0", [(0, 0)] * 2**case.requested
    if case.mode == "read":
        if case.si not in addressable:
            return reject("bounds")
        return f"moved:{slots[case.si][1]}", slots
    if case.mode == "load":
        code = case.di
        valid_slot = (code == 0 or (KEYS[code] == KEYS[case.mk]
                      and 0 < case.requested <= case.limit))
        if case.si not in addressable or not valid_slot:
            return "moved:0", slots
        slots[case.si] = (code, case.requested if code else 0)
        return "moved:1", slots

    if case.si not in addressable or case.di not in addressable:
        return reject("bounds")
    if case.si == case.di:
        return reject("same_slot")
    source_code, source_count = slots[case.si]
    target_code, target_count = slots[case.di]
    if case.mode == "split" and target_code:
        return reject("split_needs_empty")
    if case.mode == "merge" and not target_code:
        return reject("merge_needs_stack")
    if not source_code:
        return reject("no_source")
    if target_code and target_count == 0:
        return reject("invalid_stack")
    if target_code and KEYS[source_code] != KEYS[target_code]:
        return reject("different_item")
    if KEYS[source_code] != KEYS[case.mk] or case.limit == 0:
        return reject("bad_metadata")
    if not (0 < source_count <= case.limit and target_count <= case.limit):
        return reject("invalid_stack")
    free = case.limit - target_count
    if free == 0:
        return reject("full")
    moved = min(source_count, case.requested, free)
    if moved:
        remainder = source_count - moved
        slots[case.si] = (source_code, remainder) if remainder else (0, 0)
        slots[case.di] = (source_code, target_count + moved)
    return f"moved:{moved}", slots


def fixtures(seed: int, fuzz_count: int) -> list[Case]:
    cases: list[Case] = []

    def add(**changes):
        cases.append(Case(label=f"c{len(cases):06d}", **changes))

    # Exhaust the count/request clipping boundaries for multiple supplied limits.
    for limit in (1, 2, 16, 64, 99, 128):
        values = sorted({0, 1, max(0, limit-1), limit, limit+1})
        requests = sorted({0, 1, max(0, limit-1), limit, limit+1, MAX_U32})
        for sc, dc, requested, mode in itertools.product(values, values, requests,
                                                        ("transfer", "split", "merge")):
            for dk in (0, 1, 3):
                add(sc=sc, dc=dc, requested=requested, mode=mode, limit=limit, dk=dk)

    # Exact item and component identity includes distinct payload strings.
    for sk, dk, mk in itertools.product(range(8), range(8), range(1, 8)):
        add(sk=sk, dk=dk, mk=mk)

    # Logical and physical array bounds, including forged logical > capacity.
    for logical, si, di, mode in itertools.product((0, 1, 2, 3, 4, 5, MAX_U32),
                                                  (0, 1, 2, 3, 4, MAX_U32),
                                                  (0, 1, 2, 3, 4, MAX_U32),
                                                  ("transfer", "split", "merge")):
        add(logical=logical, si=si, di=di, mode=mode)

    for mode in ("transfer", "split", "merge"):
        for requested in (0, 1, 2, 64, MAX_U32):
            add(mode=mode, limit=0, requested=requested)
            add(mode=mode, sk=0, dk=0, requested=requested)
        add(mode=mode, sc=MAX_U32, dc=MAX_U32-1, limit=MAX_U32, requested=1)
        add(mode=mode, sc=MAX_U32, dk=0, limit=MAX_U32, requested=1)
        add(mode=mode, sc=1, dc=MAX_U32-1, limit=MAX_U32, requested=MAX_U32)
        add(mode=mode, sc=64, dk=0, limit=MAX_U32, requested=MAX_U32)
        add(mode=mode, sc=MAX_U32, dc=MAX_U32, limit=MAX_U32, requested=MAX_U32)

    # Constructor, checked state loading, and read-only access.
    for depth in (0, 1, 2, 3, 6, 17, MAX_U32):
        for length in (0, 1, 2, 3, 4, 65, MAX_U32):
            add(mode="new", requested=depth, di=length)
    for logical, index in itertools.product((0, 1, 2, 3, 4, 5),
                                           (0, 1, 2, 3, 4, MAX_U32)):
        add(mode="read", logical=logical, si=index)
    for index, code, count, limit, mk in itertools.product((0, 3, 4, MAX_U32),
                                                          (0, 1, 3),
                                                          (0, 1, 64, 65),
                                                          (0, 1, 64), (1, 3)):
        add(mode="load", si=index, di=code, requested=count, limit=limit, mk=mk)

    # Single-leaf backing arrays must reject every index beyond physical slot 0.
    for shape, logical, si, di, mode in itertools.product((3,),
                                                         (0, 1, 2, 3, 4, 5),
                                                         (0, 1, 2, 3, 4),
                                                         (0, 1, 2, 3, 4),
                                                         ("transfer", "split", "merge", "read")):
        add(shape=shape, logical=logical, si=si, di=di, mode=mode)
    for shape, index in itertools.product((3,), range(5)):
        add(mode="load", shape=shape, logical=4, si=index, di=1, requested=8)

    # Deterministic adversarial generation is separate from the boundary grid.
    rng = random.Random(seed)
    for _ in range(fuzz_count):
        limit = rng.choice((0, 1, 2, 3, 16, 32, 64, 99, 128, 255))
        add(mode=rng.choice(("transfer", "split", "merge")),
            sc=rng.randrange(0, max(limit, 1)+3),
            dc=rng.randrange(0, max(limit, 1)+3), limit=limit,
            requested=rng.choice((0, 1, MAX_U32, rng.randrange(300))),
            si=rng.choice((0, 1, 2, 3, 4, MAX_U32)),
            di=rng.choice((0, 1, 2, 3, 4, MAX_U32)),
            sk=rng.randrange(8), dk=rng.randrange(8), mk=rng.randrange(1, 8),
            logical=rng.choice((0, 1, 2, 3, 4, 5, MAX_U32)))
    return cases


def command(args: list[str], *, timeout: int = 120) -> subprocess.CompletedProcess:
    result = subprocess.run(args, cwd=ROOT, text=True, capture_output=True,
                            timeout=timeout, check=False)
    if result.returncode:
        raise RuntimeError(f"Command failed ({result.returncode}): {args}\n"
                           f"{result.stdout}\n{result.stderr}")
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bend", default=os.environ.get("BEND", "/Users/chuah/.bend/bin/bend"))
    parser.add_argument("--seed", type=int, default=2630103)
    parser.add_argument("--fuzz", type=int, default=5000)
    parser.add_argument("--verdict", action="store_true")
    parser.add_argument("--evidence", default="evidence/inventory-oracle.json")
    options = parser.parse_args()
    binary = ROOT / "build/inventory_test"
    binary.parent.mkdir(exist_ok=True)
    checks = [options.bend, "src/inventory_proof.bend"]
    if options.verdict:
        checks.append("--verdict")
    checked = command(checks)
    if "ALL PROOFS CHECK" not in checked.stdout:
        raise RuntimeError(f"Proof checker did not confirm success: {checked.stdout}")
    command([options.bend, "tests/inventory.bend", "-o", "build/inventory_test"])

    malformed_rejections = []
    for shape in (1, 2):
        probe = Case(label=f"unsupported_array_shape_{shape}", shape=shape,
                     logical=4, si=2, di=3, requested=1, mk=6)
        rejected = subprocess.run([str(binary), "--gpu", "off", "--threads", "1",
                                   "--", probe.argument()], cwd=ROOT, text=True,
                                  capture_output=True, timeout=30, check=False)
        if rejected.returncode == 0 or "runtime fail-stop" not in rejected.stderr:
            raise AssertionError(f"Uneven Array construction was not rejected: {rejected}")
        malformed_rejections.append({"shape": shape, "exit_code": rejected.returncode,
                                     "stderr": rejected.stderr.strip(),
                                     "result": "rejected during native Array construction"})

    cases = fixtures(options.seed, options.fuzz)
    digest = hashlib.sha256("\n".join(c.argument() for c in cases).encode()).hexdigest()
    outcomes = Counter()
    rejections = Counter()
    max_moved = 0
    start = time.perf_counter()
    for first in range(0, len(cases), 128):
        batch = cases[first:first+128]
        result = command([str(binary), "--gpu", "off", "--threads", "1",
                          "--", *(case.argument() for case in batch)], timeout=30)
        lines = result.stdout.splitlines()
        if len(lines) != len(batch):
            raise AssertionError(f"Expected {len(batch)} rows, got {len(lines)}: {result.stdout[:500]}")
        for case, line in zip(batch, lines, strict=True):
            label, status, *raw_slots = line.split("|")
            slots = [tuple(map(int, slot.split(":"))) for slot in raw_slots]
            expected_status, expected_slots = oracle(case)
            if label != case.label or (status, slots) != (expected_status, expected_slots):
                raise AssertionError(json.dumps({"case": asdict(case),
                    "expected": [expected_status, expected_slots], "actual": [status, slots]}, indent=2))
            outcomes[f"{case.mode}:{status.split(':')[0]}"] += 1
            if status.startswith("rejected:"):
                rejections[status.split(":", 1)[1]] += 1
            if case.mode in ("transfer", "split", "merge"):
                if item_totals(slots) != item_totals(case.initial()):
                    raise AssertionError(f"Per-item conservation failed for {case}")
                if status.startswith("rejected:") and slots != case.initial():
                    raise AssertionError(f"Rejected operation mutated state for {case}")
                if status.startswith("moved:"):
                    moved = int(status.split(":")[1])
                    max_moved = max(max_moved, moved)
                    if not 0 <= moved <= case.requested:
                        raise AssertionError(f"Requested-count limit failed for {case}")
                    if moved:
                        for index in (case.si, case.di):
                            if not 0 <= slots[index][1] <= case.limit:
                                raise AssertionError(f"Stack limit failed for {case}")
    elapsed = time.perf_counter()-start
    sources = ("src/inventory.bend", "src/inventory_laws.bend",
               "src/inventory_proof.bend", "tests/inventory.bend", "tools/test_inventory.py")
    evidence = {
        "schema": 1, "result": "pass", "implementation": "pure typed Bend owned inventory kernel",
        "compiler": command([options.bend, "version"]).stdout.strip(),
        "commands": [checks, [options.bend, "tests/inventory.bend", "-o", "build/inventory_test"],
                     ["python3", "tools/test_inventory.py", "--seed", str(options.seed), "--fuzz", str(options.fuzz), *(["--verdict"] if options.verdict else [])]],
        "proof_checker_output": checked.stdout.strip(), "kernel_verdict_requested": options.verdict,
        "checked_law_count": sum(line.startswith("law ") for line in (ROOT/"src/inventory_laws.bend").read_text().splitlines()),
        "native_binary_sha256": hashlib.sha256(binary.read_bytes()).hexdigest(),
        "native_backend": "CPU; --gpu off --threads 1", "case_count": len(cases),
        "deterministic_fuzz_cases": options.fuzz, "seed": options.seed,
        "fixture_sha256": digest, "outcomes": dict(sorted(outcomes.items())),
        "rejection_reasons": dict(sorted(rejections.items())),
        "unsupported_array_construction_probes": malformed_rejections,
        "maximum_observed_moved_count": max_moved, "native_oracle_wall_seconds": round(elapsed, 6),
        "properties": ["exact full state matches independent Python integer oracle",
                       "per-item counts conserved for all transfer/split/merge fixtures",
                       "all rejected transfers preserve every backing slot",
                       "moved counts respect requests and injected stack limits",
                       "logical and physical bounds cannot invoke wrapping access",
                       "uneven Array trees are rejected by native construction before transfer",
                       "immutable item ID and components determine compatibility",
                       "constructor, load validation, read bounds, and zero-transfer identity"],
        "limits": ["Foundation arithmetic and slot eligibility; no Minecraft container/creative/crafting parity claim",
                   "Conservation proof covers the actual Nat count kernel; U32 conversions and array commits are tested",
                   "Timing includes native process startup and serialization; not a Minecraft performance comparison"],
        "source_sha256": {path: hashlib.sha256((ROOT/path).read_bytes()).hexdigest() for path in sources},
    }
    destination = ROOT / options.evidence
    destination.parent.mkdir(exist_ok=True)
    destination.write_text(json.dumps(evidence, indent=2)+"\n")
    print(json.dumps({"result": "pass", "cases": len(cases), "fuzz": options.fuzz,
                      "seconds": round(elapsed, 3), "evidence": str(destination)}, indent=2))


if __name__ == "__main__":
    main()
