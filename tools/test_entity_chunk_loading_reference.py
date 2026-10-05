#!/usr/bin/env python3
"""Compare actual Bend ticket/math calls with pinned Java observations.

--mode prepare writes only the input/oracle files. Python converts signed Java
words and groups already observed callbacks; it does not implement transitions,
timers, source minima, or the distance graph. Native compilation is explicit.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import sys

from build_native import file_digest, foreign_paths, guard_route
from test_player_look import imports
from test_player_block_inside_stuck import run
from test_local_player_cooking_edit import source_check
import reference_entity_chunk_loading as R

ROOT = Path(__file__).resolve().parents[1]
ENTRY = ROOT / "tests/entity_chunk_loading_reference.bend"
REFERENCE = ROOT / "reference/entity_chunk_loading.json"


def require(value, message):
    if not value:
        raise AssertionError(message)


def pin(path):
    path = Path(path)
    return {"path": str(path), "bytes": path.stat().st_size, "sha256": file_digest(path)}


def words(value):
    value = int(value) & ((1 << 64) - 1)
    return [value >> 32, value & 0xFFFFFFFF]


def word_pair(value):
    return ":".join(map(str, words(value)))


def reference_data():
    result = json.loads(REFERENCE.read_text())
    require(result["pin"] == "26.3" and result["run"]["returncode"] == 0,
            "actual Java reference did not succeed")
    require(result["probe_sha256"] == file_digest(Path(R.__file__)),
            "Java reference producer changed")
    require(result["java_source_sha256"] == hashlib.sha256(R.SOURCE.encode()).hexdigest(),
            "controlled Java scenario inputs changed")
    observed = result["observations"]
    canonical = json.dumps(observed, sort_keys=True, separators=(",", ":")).encode()
    require(result["observations_sha256"] == hashlib.sha256(canonical).hexdigest(),
            "Java observed outputs changed")
    require(result["provenance"]["client"]["sha256"] ==
            "4508d006323f24fa02876310c192d739af56516eb259000ac50f0909a68c9a2d",
            "Java reference used a different pinned client")
    return result


class Inputs:
    def __init__(self):
        self.lines = []
        self.expected = []
        self.cursor = 0

    def command(self, mode, *, key=(0, 0), identity="unused", timeout=0,
                flags=0, level=0, holder=0):
        index = self.cursor
        self.cursor += 1
        hi, lo = words(timeout)
        x, z = (v & 0xFFFFFFFF for v in key)
        self.lines.append(" ".join(map(str, [mode, index, x, z, identity, hi, lo,
                                             flags, level & 0xFFFFFFFF, holder])))
        return index

    def expect(self, kind, indexes, wanted, label):
        self.expected.append({"kind": kind, "indexes": indexes, "wanted": wanted,
                              "label": label})


def callback_projection(events):
    # The callbacks were observed independently in Java. This conversion only
    # maps their recorded fields to the native test's line representation.
    return [f"{e['kind']}:{e['level']}:{int(e['decrease'])}" for e in events]


def prepare_inputs(result, work):
    observed = result["observations"]
    source = Inputs()
    types = {t["name"]: t for t in observed["ticket_types"]}

    def ticket(mode, name, level, key=(-2, 3), timeout=None, flags=None):
        kind = types.get(name)
        return source.command(mode, key=key, identity=name, level=level,
                              timeout=kind["timeout"] if timeout is None else timeout,
                              flags=kind["flags"] if flags is None else flags)

    for row in observed["level_cases"]:
        index = source.command("level", level=row["level"])
        source.expect("level", [index], [row["status"], row["visibility"], str(int(row["ticking"]))],
                      f"actual Java full level {row['level']}")
    for row in observed["ticket_types"]:
        index = source.command("type", identity=row["name"], timeout=row["timeout"], flags=row["flags"])
        wanted = [str(int(row[key])) for key in ("persist", "loads", "simulates",
                                                  "keeps_dimension_active", "can_expire_unloaded")]
        # TicketType.hasTimeout's exact bytecode comparison is timeout != 0.
        wanted.append(str(int(int(row["timeout"]) != 0)))
        source.expect("type", [index], wanted, f"actual Java ticket type {row['name']}")
    for row in observed["tickets"]["signed_timer_boundaries"]:
        index = source.command("timer", identity="custom-timer", timeout=row["timeout"], flags=18, level=31)
        wanted = [word_pair(row["before"]["ticks_left"]), str(int(row["before"]["timed_out"])),
                  word_pair(row["after_one_decrement"]["ticks_left"]),
                  str(int(row["after_one_decrement"]["timed_out"]))]
        source.expect("timer", [index], wanted, f"actual Java signed timer {row['timeout']}")

    source.command("clear")
    steps = observed["tickets"]["storage_steps"]
    store_inputs = [
        [ticket("add", "PLAYER_LOADING", 33)],
        [ticket("add", "PLAYER_SIMULATION", 31)],
        [ticket("add", "PLAYER_SIMULATION", 31)],
        [ticket("remove", "PLAYER_SIMULATION", 31)],
        # Java constructs distinct TicketType records with identical (7,6)
        # values. Distinct fixture identity strings represent those references.
        [ticket("add", "custom-A", 30, timeout=7, flags=6),
         ticket("add", "custom-B", 30, timeout=7, flags=6)],
        [ticket("add", "FORCED", 29)],
        [ticket("remove", "FORCED", 29)],
    ]
    for java, indexes in zip(steps, store_inputs):
        wanted = {}
        for key in ("loading_level", "simulation_level", "count"):
            if key in java:
                wanted[key] = java[key]
        for key in ("added", "removed"):
            if key in java:
                wanted["changed"] = java[key]
        wanted["events"] = callback_projection(java["events"])
        source.expect("store", indexes, wanted, "actual Java " + java["action"])

    source.command("clear")
    ttl = observed["tickets"]["unknown_timeout_steps"]
    for index, java in enumerate(ttl):
        if index in (0, 2):
            ticket("graph-add", "UNKNOWN", 34)
        else:
            source.command("lifetime-purge", key=(-2, 3))
        peek = source.command("life", key=(-2, 3))
        # Java also retains a reference to an expired object after the store
        # removes it. Compare the current store's owner projection only.
        wanted = [str(java["count"]),
                  word_pair(java["ticket"]["ticks_left"]) if java["count"] else "-",
                  str(int(java["ticket"]["timed_out"])) if java["count"] else "0"]
        source.expect("life", [peek], wanted, "actual Java " + java["action"])

    source.command("clear")
    ticket("graph-add", "custom-untimed-both", 31, timeout=0, flags=6)
    ticket("graph-add", "custom-timed-both", 34, timeout=1, flags=22)
    purge = observed["tickets"]["purge_listener_order"]
    first = source.command("purge", key=(-2, 3))
    source.expect("store", [first], {"events": callback_projection(purge["first_purge_events"])},
                  "actual Java first purge has no removal callback")
    second = source.command("purge", key=(-2, 3))
    source.expect("store", [second], {"count": purge["remaining_count"],
                  "loading_level": purge["loading_level"], "simulation_level": purge["simulation_level"],
                  "events": callback_projection(purge["second_purge_events"])},
                  "actual Java bulk expiry listener order with unchanged minima")

    source.command("clear")
    graph = observed["simulation_graph"]
    cap = graph[0]["levels"][0]["level"]
    for stage in graph:
        action = stage["action"]
        if action == "loading_only_has_no_simulation_source":
            ticket("graph-add", "PLAYER_LOADING", 20, key=(0, 0))
        elif action == "simulation31_at_origin":
            ticket("graph-add", "PLAYER_SIMULATION", 31, key=(0, 0))
        elif action == "competing_forced30_at_4_0":
            ticket("graph-add", "FORCED", 30, key=(4, 0))
        elif action == "remove_origin_source_recomputes":
            ticket("graph-remove", "PLAYER_SIMULATION", 31, key=(0, 0))
        elif action == "remove_all_simulation_sources":
            ticket("graph-remove", "FORCED", 30, key=(4, 0))
        else:
            require(action == "empty", "unknown actual Java graph input action")
        for cell in stage["levels"]:
            index = source.command("graph", key=cell["position"], flags=1, level=cap)
            source.expect("graph", [index], [str(cell["level"])],
                          f"actual Java {action} at {cell['position']}")
    (work / "inputs.txt").write_text("\n".join(source.lines) + "\n")
    (work / "expected.json").write_text(json.dumps(source.expected, indent=2) + "\n")
    return source.expected


def parsed_output(output):
    rows = {}
    for line in output.decode().splitlines():
        kind, index, *fields = line.split()
        identity = int(index)
        require(identity not in rows, "duplicate native fixture output identity")
        if kind == "store":
            require(len(fields) == 5, "native store output shape changed")
            require(fields[0] in {"0", "1"}, "native store changed flag is malformed")
            fields = {"changed": fields[0] == "1", "loading_level": int(fields[1]),
                      "simulation_level": int(fields[2]), "count": int(fields[3]),
                      "events": [] if fields[4] == "-" else fields[4].split(",")}
        rows[identity] = {"kind": kind, "fields": fields}
    return rows


def compare(output, expected):
    rows = parsed_output(output)
    consumed = set()
    for item in expected:
        selected = [rows[index] for index in item["indexes"]]
        require(all(row["kind"] == item["kind"] for row in selected), item["label"])
        consumed.update(item["indexes"])
        if item["kind"] == "store":
            actual = dict(selected[-1]["fields"])
            actual["events"] = [event for row in selected for event in row["fields"]["events"]]
            projection = {key: actual[key] for key in item["wanted"]}
        else:
            require(len(selected) == 1, "unexpected multirow scalar oracle")
            projection = selected[0]["fields"]
        require(projection == item["wanted"], {"label": item["label"], "actual": projection,
                                             "expected": item["wanted"]})
    require(set(rows) == consumed, "unexpected native output has no Java oracle")
    return {"compared_cases": len(expected), "compared_rows": len(consumed)}


def frozen_entry(work):
    sources = imports([ENTRY])
    before = dict(sources)
    for name in before:
        path = ROOT / name
        for effect in foreign_paths(path.read_text()):
            if effect.endswith(".c"):
                actual = (path.parent / effect).resolve()
                sources[str(actual.relative_to(ROOT))] = file_digest(actual)
    for name, digest in sources.items():
        data = (ROOT / name).read_bytes()
        require(hashlib.sha256(data).hexdigest() == digest, "source drift during snapshot")
        destination = work / "source" / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(data)
    require(imports([ENTRY]) == before, "Bend graph changed during snapshot")
    require(all(file_digest(ROOT / name) == digest for name, digest in sources.items()),
            "source/effect changed during snapshot")
    (work / "sources.json").write_text(json.dumps(sources, indent=2) + "\n")
    return work / "source/tests/entity_chunk_loading_reference.bend"


def native_check(work, entry, expected):
    prepare = ROOT / "tools/player_crafting_authority_native.py"
    _, emission = run([sys.executable, prepare, entry, "--report", work / "prepared.json"],
                      work, "prepare", 600)
    prepared = json.loads((work / "prepared.json").read_text())
    emitted = Path(prepared["emitted_file"])
    require(file_digest(emitted) == prepared["emitted_c_sha256"], "guarded C changed")
    guard_route(emitted.read_text())
    require(prepared["context"]["compiler"]["flags"] ==
            ["-std=c11", "-O3", "<emitted.c>", "-lpthread", "-lm", "-o", "<native>"],
            "ordinary CPU compiler flags changed")
    binary = work / "reference-tests"
    _, clang = run([prepared["context"]["compiler"]["path"], "-std=c11", "-O3", emitted,
                   "-lpthread", "-lm", "-o", binary], work, "clang", 600)
    _, checked = run([sys.executable, prepare, entry, "--report", work / "prepared-after.json"],
                     work, "prepare-after", 600)
    after = json.loads((work / "prepared-after.json").read_text())
    require(after["cache_key"] == prepared["cache_key"] and
            after["emitted_c_sha256"] == prepared["emitted_c_sha256"], "dependency drift")
    output, native = run([binary, "--gpu", "off", "--threads", "2", work / "inputs.txt"],
                         work, "native", 30)
    require(not (work / "native.stderr").read_bytes(), "unexpected native stderr")
    comparison = compare(output, expected)
    return {"emission": emission, "clang": clang, "dependency_check": checked,
            "native": native, "binary": pin(binary), "comparison": comparison}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", choices=["prepare", "source", "native"], default="prepare")
    parser.add_argument("--work", type=Path, required=True)
    args = parser.parse_args()
    work = args.work.resolve()
    work.mkdir(parents=True, exist_ok=False)
    try:
        result = reference_data()
        expected = prepare_inputs(result, work)
        checks = {}
        if args.mode != "prepare":
            entry = frozen_entry(work)
            checks["source"] = source_check(work, entry)
            if args.mode == "native":
                checks["native"] = native_check(work, entry, expected)
        report = {"status": "prepared" if args.mode == "prepare" else "pass", "mode": args.mode,
                  "reference": pin(REFERENCE), "fixture": pin(ENTRY), "runner": pin(Path(__file__)),
                  "expected": pin(work / "expected.json"), "inputs": pin(work / "inputs.txt"),
                  "oracle_cases": len(expected), "checks": checks,
                  "boundary": "Actual Bend production math/ticket mutations, source levels, settled simulation graph and signed countdowns compared with recorded Java. Controlled type identity strings represent Java type object identities. No lifecycle/cache future execution, world/dimension/epoch callbacks, physical persistence, renderer, or native Java bootstrap replay claimed."}
        (work / "result.json").write_text(json.dumps(report, indent=2) + "\n")
        print(json.dumps({"status": report["status"], "mode": args.mode,
                          "oracle_cases": report["oracle_cases"], "result": str(work / "result.json")}))
    except BaseException as error:
        (work / "failure.json").write_text(json.dumps({"status": "failed", "mode": args.mode,
                  "error": repr(error), "fixture": pin(ENTRY), "runner": pin(Path(__file__))}, indent=2) + "\n")
        raise


if __name__ == "__main__":
    main()
