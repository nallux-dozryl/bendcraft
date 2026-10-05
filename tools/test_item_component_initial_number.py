#!/usr/bin/env python3
"""Focused executor-only observation of the actual initialized numeric gate."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ENTRY = ROOT / 'tests/item_component_initial_number.bend'
ALLOWED = ('0', '1', '6', '7.2000003')
REFUSED = (
    '', ' ', '\t', '\n', '00', '01', '06', '+0', '+1', '+6', '-0', '-1',
    '0.0', '1.0', '6.0', '0e0', '1e0', '6e0', '7.2', '7.20000030',
    '7.2000003000000001', '7.2000003e0', '7.2000003 ', ' 7.2000003',
    '0 ', ' 0', '1\n', '6\t', '7', '2', '64', 'NaN', 'Infinity', '-Infinity',
    'null', 'true', '"0"', '0,"injected":true', '0}', '0]', '０', '١', '6😀',
)


def suite(executor):
    """executor(label, args) returns (stdout, existing process receipt)."""
    cases = list(ALLOWED + REFUSED)
    assert len(set(cases)) == len(cases)
    output, process = executor('numeric-lexemes', cases)
    if isinstance(output, bytes):
        output = output.decode('utf-8')
    rows = [json.loads(line) for line in output.splitlines()]
    expected = [[raw, raw in ALLOWED] for raw in cases]
    assert rows == expected, (rows, expected)
    return {'cases': len(cases), 'allowed': len(ALLOWED), 'refused': len(REFUSED),
            'exact_ordered_outputs': rows, 'process': process}
