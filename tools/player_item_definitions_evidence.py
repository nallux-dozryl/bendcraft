#!/usr/bin/env python3
"""Derive equipment admission from pinned component observations, not names.

Reads primary extractor receipts and the exact admitted generated table. This
static provenance tool does not execute Java, Bend, a build or game semantics.
"""
import csv
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def derive():
    source_path = ROOT / 'reference/item_stacks.json'
    source = json.loads(source_path.read_text())
    table_path = ROOT / 'generated/reference_item_metadata.tsv'
    raw = table_path.read_bytes()
    assert hashlib.sha256(raw).hexdigest() == source['table']['sha256']
    rows = list(csv.DictReader(raw.decode().splitlines(), delimiter='\t'))
    observation = source['observations']
    sets, values = observation['component_sets'], observation['component_values']
    slots = {'feet': 36, 'legs': 37, 'chest': 38, 'head': 39,
             'offhand': 40, 'body': 41, 'saddle': 42}
    equipment = {}
    components = {}
    for number, row in enumerate(rows):
        assert int(row['item_id']) == number
        entry = sets[int(row['default_component_set_id'])]
        encoded = {values[value_number]['identifier']: values[value_number]['encoded_value'] for _, value_number in entry['members']}
        identity = hashlib.sha256(json.dumps(encoded, sort_keys=True, separators=(',', ':'), ensure_ascii=False).encode()).hexdigest()
        assert identity == row['default_components_sha256']
        for type_number, value_number in entry['members']:
            value = values[value_number]
            assert value['type_id'] == type_number
            if value['identifier'] == 'minecraft:equippable':
                actual = value['encoded_value']
                equipment[row['identifier']] = slots[actual['slot']]
                components[row['identifier']] = actual
    implementation = (ROOT / 'src/player_item_definitions.bend').read_text()
    found = {name: int(slot) for name, slot in re.findall(r'case "([^"]+)": Some\{(\d+)\}', implementation)}
    assert equipment == found, 'equipment definitions differ from observed components'
    return {'schema_version': 1, 'status': 'static-provenance-verified',
            'table_sha256': hashlib.sha256(raw).hexdigest(), 'table_bytes': len(raw),
            'reference_sha256': hashlib.sha256(source_path.read_bytes()).hexdigest(),
            'registry_rows': len(rows), 'enabled_non_air': sum(r['enabled_default_flags'] == 'True' and r['identifier'] != 'minecraft:air' for r in rows),
            'default_limits': sorted(set(int(r['default_stack_max_stack_size']) for r in rows)),
            'equippable_defaults': len(equipment), 'equipment': equipment,
            'equippable_components': components,
            'native_or_java_execution': False}


if __name__ == '__main__':
    print(json.dumps(derive(), sort_keys=True, indent=2))
