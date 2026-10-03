#!/usr/bin/env python3
"""Exercise extraction reproducibility and real table corruption failures."""
from __future__ import annotations

import hashlib
import json
import pathlib
import shutil
import subprocess
import sys
import tempfile

from reference_inventory import ROOT, write_json


def snapshot() -> dict[str, str]:
    paths = sorted(list((ROOT / "reference").glob("*.json")) + list((ROOT / "generated").glob("reference_*.tsv")))
    return {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest() for path in paths}


def main() -> None:
    before = snapshot()
    commands = ["reference_inventory.py", "reference_verify.py", "reference_tick_probe.py", "reference_structures.py", "reference_coverage.py"]
    for name in commands:
        subprocess.run([sys.executable, str(ROOT / "tools" / name)], cwd=ROOT, capture_output=True, text=True, check=True)
    after = snapshot()
    if before != after:
        changed = sorted(path for path in before.keys() | after.keys() if before.get(path) != after.get(path))
        raise ValueError(f"Non-reproducible extraction output: {changed}")
    rejection_checks = []
    with tempfile.TemporaryDirectory(prefix="minecraft-26.3-reference-check-") as tmp:
        temporary = pathlib.Path(tmp)
        for name in ["generated", "evidence", "reference"]:
            (temporary / name).mkdir()
        (temporary / "reference/reports").symlink_to(ROOT / "reference/reports", target_is_directory=True)
        for original in (ROOT / "generated").glob("reference_*.tsv"):
            if original.name == "reference_blocks.tsv":
                shutil.copy2(original, temporary / "generated" / original.name)
            else:
                (temporary / "generated" / original.name).symlink_to(original)
        evidence_path = temporary / "evidence/reference_inventory.json"
        shutil.copy2(ROOT / "evidence/reference_inventory.json", evidence_path)
        blocks_path = temporary / "generated/reference_blocks.tsv"
        original = blocks_path.read_text()
        needle = "0\tminecraft:air\t0\t1\t0\t[]\n"
        replacement = "0\tminecraft:air\t1\t1\t0\t[]\n"
        if needle not in original:
            raise ValueError("Pinned air row is different from corruption fixture")
        blocks_path.write_text(original.replace(needle, replacement, 1))
        verify = [sys.executable, str(ROOT / "tools/reference_verify.py"), "--root", str(temporary)]
        result = subprocess.run(verify, capture_output=True, text=True)
        if result.returncode == 0 or "Table hash mismatch" not in result.stderr:
            raise ValueError("Verifier failed to reject a table with corrupted state ID")
        rejection_checks.append({"mutation": "air first_state_id changed from 0 to 1", "expected_rejection": "table_hash_mismatch", "rejected": True})
        # Reseal the checksum deliberately. The state-vs-reference check must
        # still fail; transport integrity alone cannot prove semantic mapping.
        evidence = json.loads(evidence_path.read_text())
        data = blocks_path.read_bytes()
        evidence["generated_tables"]["generated/reference_blocks.tsv"].update({"bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()})
        evidence_path.write_text(json.dumps(evidence))
        result = subprocess.run(verify, capture_output=True, text=True)
        if result.returncode == 0 or "State reconstruction mismatch" not in result.stderr:
            raise ValueError("Verifier accepted an incorrect block state mapping after checksum resealing")
        rejection_checks.append({"mutation": "same incorrect air state ID with checksum updated", "expected_rejection": "state_reconstruction_mismatch", "rejected": True})
    output = {"pin": "26.3", "kind": "extraction_tool_failure_and_reproducibility_checks", "commands_repeated": commands,
              "tracked_reference_outputs_compared": len(before), "all_output_bytes_reproduced": True,
              "snapshot_tree_sha256": hashlib.sha256("".join(path + "\t" + sha + "\n" for path, sha in sorted(after.items())).encode()).hexdigest(),
              "corruption_checks": rejection_checks, "behavioral_parity_established": False}
    write_json(ROOT / "evidence/reference_selftest.json", output)
    print(json.dumps({"outputs_reproduced": len(before), "corruption_failures_rejected": len(rejection_checks)}, sort_keys=True))


if __name__ == "__main__":
    main()
