#!/usr/bin/env python3
"""Focused durable metadata comparisons through an existing shared artifact.

This helper performs no compiler, native build, Java probe or game simulation.
The harness runs the actual production encoder/decoder; this side compares each
returned field, including seed words, ordered properties and structure requests.
"""
from __future__ import annotations
import argparse, json
from pathlib import Path
from reference_inventory import ROOT, fingerprint, write_json

REFERENCE = ROOT / 'reference/world_generation_settings.json'
HARNESS = ROOT / 'tests/world_generation_settings_roundtrip.bend'
SOURCES = [ROOT / 'src/world_generation_settings.bend',
           ROOT / 'src/world_generation_settings_codec.bend', HARNESS]
LONG = 'bendex:' + 'abcdefghijklmnopqrstuvwxyz' * 4


def stone_dirt_root(seed=0):
    """Independent ordered metadata fixture for the actual format3 client save."""
    import test_nbt as N
    import test_world_codec as WC
    assert isinstance(seed, int) and 0 <= seed < 1 << 64
    layers = [WC.compound([
        ('height', WC.integer(height)), ('block', WC.txt('minecraft:' + block)),
        ('properties', WC.listing([]))])
        for height, block in ((1, 'stone'), (2, 'dirt'), (1, 'stone'))]
    generator = WC.compound([
        ('kind', WC.txt('flat')), ('payload', WC.compound([
            ('profile', WC.txt('bendex:stone-dirt-superflat')),
            ('biome', WC.txt('minecraft:plains')),
            ('layers', WC.listing(layers)), ('features', WC.byte(0)),
            ('lakes', WC.byte(0)), ('structures', WC.compound([
                ('specified', WC.byte(1)), ('entries', WC.listing([], 8))]))]))])
    return N.RootTag(N.text('bendex:world-generation-settings'), WC.compound([
        ('format', WC.integer(1)), ('kind', WC.txt('settings')),
        ('payload', WC.compound([
            ('dimension', WC.txt('minecraft:overworld')),
            ('min_y', WC.integer((-64) & 0xffffffff)),
            ('height', WC.integer(384)), ('seed', N.Value(4, seed)),
            ('generator', generator)]))]))


def stone_dirt_bytes(seed=0):
    import test_nbt as N
    root = stone_dirt_root(seed)
    data = N.encode_root(root)
    assert len(data) <= 16384
    assert N.parse(data) == root
    return data


def expected():
    flat = lambda profile, layers, features, lakes, structures: (
        f'flat|{profile}|minecraft:plains|{layers}|{features}|{lakes}|{structures}')
    base = lambda seed, tail: f'decoded|minecraft:overworld|4294967232|384|{seed}|{tail}'
    long = flat(LONG, '0,minecraft:air,/4,minecraft:oak_log,axis=z;/', 1, 1, '')
    return {
        'legacy': 'decoded|unspecified',
        'custom': base('4294967295,4294967295', flat('bendex:stone-dirt-superflat',
             '1,minecraft:stone,/2,minecraft:dirt,/1,minecraft:stone,/', 0, 0, 'specified:')),
        'classic': base('2147483648,0', flat('minecraft:classic_flat',
             '1,minecraft:bedrock,/2,minecraft:dirt,/1,minecraft:grass_block,/', 0, 0, 'specified:minecraft:villages')),
        'normal': base('0,4294967295', 'noise|minecraft:overworld|multi_noise_preset,minecraft:overworld'),
        'long-unspecified': base('2147483648,4294967295', long + 'unspecified'),
        'long-empty': base('2147483648,4294967295', long + 'specified:'),
        'long-ordered': base('2147483648,4294967295', long + 'specified:minecraft:villages,minecraft:strongholds'),
        'invalid': 'fail|invalid world generator settings',
    }


def compare(stdout):
    lines = stdout.splitlines()
    assert len(lines) == 8, lines
    actual = {}
    for line in lines:
        name, value = line.split('|', 1)
        assert name not in actual, name
        actual[name] = value
    assert actual == expected(), (actual, expected())
    return {'cases': 8, 'complete_field_comparison': True,
            'seed64_words_retained': True, 'long_identifier_over_64_chars': True,
            'absent_vs_explicit_empty_structures': True, 'ordered_properties_and_sets': True}


def prepare():
    reference = json.loads(REFERENCE.read_text())
    normal = reference['entries']['data/minecraft/worldgen/world_preset/normal.json']['json']
    generator = normal['dimensions']['minecraft:overworld']['generator']
    assert generator == {'type': 'minecraft:noise', 'settings': 'minecraft:overworld',
                         'biome_source': {'type': 'minecraft:multi_noise', 'preset': 'minecraft:overworld'}}
    assert reference['classic_flat_reused']['json']['settings']['structure_overrides'] == 'minecraft:villages'
    fake = '\n'.join(name + '|' + value for name, value in expected().items())
    compare(fake)
    corruptions = [fake.replace('4294967295,4294967295', '0,0', 1),
                   fake.replace(LONG, LONG[:64], 1),
                   fake.replace('unspecified\nlong-empty', 'specified:\nlong-empty', 1),
                   fake.replace('villages,minecraft:strongholds', 'strongholds,minecraft:villages', 1),
                   fake + '\nlegacy|decoded|unspecified']
    for bad in corruptions:
        try: compare(bad)
        except AssertionError: pass
        else: raise AssertionError('Corruption was accepted')
    result = {'status': 'prepared-only', 'native_executed': False,
              'scope': 'Actual production settings encode/decode through shared artifact only; no generation/region persistence claim',
              'sources': [fingerprint(p) for p in SOURCES],
              'helper': fingerprint(Path(__file__).resolve()),
              'reference': fingerprint(REFERENCE), 'cases': len(expected()),
              'injected_corruptions_refused': len(corruptions),
              'shared_artifact_mode': 'generation-settings-cases'}
    import hashlib
    fixture = stone_dirt_bytes()
    result['host_stone_dirt_seed0_fixture'] = {
        'bytes': len(fixture), 'sha256': hashlib.sha256(fixture).hexdigest(),
        'ordered_host_nbt_roundtrip': True,
        'production_decode_executed': False}
    write_json(ROOT / 'evidence/world-generation-settings-preparation.json', result)
    return result


def suite(executor):
    stdout, process = executor('generation-settings-roundtrip', [])
    result = compare(stdout)
    return {'status': 'passed', 'comparison': result, 'process': process,
            'sources': [fingerprint(p) for p in SOURCES]}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--prepare', action='store_true', required=True)
    parser.parse_args()
    print(json.dumps(prepare(), sort_keys=True))
