#!/usr/bin/env python3
"""Shared-artifact comparisons for bounded custom superflat generation.

Python supplies geometry/format fixtures and compares actual pinned Java column
states. It runs no compiler, native build, game simulation or Java process.
"""
from __future__ import annotations
import argparse, hashlib, json, struct
from pathlib import Path
from reference_inventory import ROOT, canonical, fingerprint, write_json

SOURCE = ROOT / 'src/superflat_world.bend'
SCENE = ROOT / 'src/local_player_scene.bend'
HARNESS = ROOT / 'tests/superflat_world.bend'
REFERENCE = ROOT / 'reference/superflat_world.json'
WORK = ROOT / 'build/superflat-world'
OFFICIAL = ROOT / 'generated/reference_blocks.tsv'

def unsigned(value): return value & 0xffffffff
def float_bits(value): return struct.unpack('>I', struct.pack('>f', value))[0]
def words64(value):
    raw = struct.unpack('>Q', struct.pack('>d', value))[0]
    return [raw >> 32, raw & 0xffffffff]

def fixture_view(position, *, sentinel=False, cache=False):
    x,y,z=position
    width=struct.unpack('>f',struct.pack('>f',.6))[0]
    height=struct.unpack('>f',struct.pack('>f',1.8))[0]
    values=(x-width/2,y,z-width/2,x+width/2,y+height,z+width/2)
    box=','.join(str(word) for value in values for word in words64(value))
    velocity=(.125,-.25,.5) if sentinel else (0,0,0)
    velocity_text=','.join(str(word) for value in velocity for word in words64(value))
    flags=(0,1,1,1) if sentinel else (1,0,0,0)
    dimensions=','.join(map(str,(float_bits(.6),float_bits(1.8),*flags)))
    angles=','.join(map(str,(float_bits(1.25),float_bits(-.5)) if sentinel else (0,0)))
    region=','.join(map(str,map(unsigned,(-3,-64,-3,8,8,8))))
    cached='999/'+region+'/0,1,10,15/0,4294967235,0,19,1,1;' if cache else 'none'
    return [box,velocity_text,dimensions,angles,'0,1,10,15',cached]

def load():
    reference = json.loads(REFERENCE.read_text())
    assert reference['pin'] == '26.3' and len(reference['cases']) == 16
    assert hashlib.sha256(canonical(reference['cases'])).hexdigest() == reference['cases_sha256']
    assert all(len(c['column']) == 10 and len(c['heights']) == 6
               for c in reference['cases'])
    assert reference['installed_source_entries']['data/minecraft/dimension_type/overworld.json']['json']['min_y'] == -64
    return reference

def section_digests(reference, profile, edited=False):
    # Entire section layout comes from the fixed public section format (x,z,y)
    # and actual Java column states, never from production Bend helper calls.
    column = {cell['y']: cell['state'] for cell in next(
        c for c in reference['cases'] if c['profile'] == profile)['column']}
    expected = {}
    for sx in range(-2, 3):
        for sz in range(-2, 3):
            for sy in range(-5, -2):
                digest = 2166136261
                for index in range(4096):
                    y = sy * 16 + index // 256
                    state = column.get(y, 0)
                    if edited and sx == sz == 0 and y == -61 and index % 256 == 0:
                        state = 0
                    digest = ((digest ^ state) * 16777619) & 0xffffffff
                key = f'minecraft:overworld/{unsigned(sx)}/{unsigned(sy)}/{unsigned(sz)}'
                expected[key] = digest
    return expected

def parse_sections(text):
    rows = [row.split('=') for row in text.split(';') if row]
    result = {key: int(value) for key, value in rows}
    assert len(rows) == len(result), 'Duplicate section keys'
    return result

def state_count():
    return sum(int(row.split('\t')[3]) for row in OFFICIAL.read_text().splitlines()[1:] if row)

def expected_cell(reference, profile, x, y, z):
    if not (-32 <= x <= 47 and -32 <= z <= 47 and -80 <= y <= -33):
        return 'fail:missing-section:minecraft:overworld/' + '/'.join(
            str(unsigned(value // 16)) for value in (x, y, z))
    return str(next(cell['state'] for c in reference['cases']
                    if c['profile'] == profile and c['x'] == x and c['z'] == z
                    for cell in c['column'] if cell['y'] == y))

def compare_generated(stdout, profile, reference=None):
    reference = reference or load()
    lines = [line.split('|') for line in stdout.splitlines()]
    generated = [line for line in lines if line[0] == 'generated']
    assert len(generated) == 1 and generated[0][1] == profile
    assert generated[0][2] == f'0,0,1,1,1,{state_count()}', 'Generation must not tick or unpause'
    assert parse_sections(generated[0][3]) == section_digests(reference, profile), 'Complete section digests differ'
    assert generated[0][4:] == ['', 'applied,0,0,0,1;']
    view = next(line for line in lines if line[0] == 'generated-view')
    assert view[1:3] == [','.join(map(str,map(unsigned,(-3,-64,-3,8,8,8)))),'0']
    assert list(map(int,view[3].split(','))) == words64(.5)+words64(-60)+words64(.5)
    assert view[4:] == fixture_view((.5,-60,.5))
    cells = [line for line in lines if line[0] == 'cell']
    assert len(cells) == 83 and len({c[1] for c in cells}) == 83
    for _, position, state in cells:
        x, y, z = (n if n < 0x80000000 else n - 0x100000000
                   for n in map(int, position.split(',')))
        assert state == expected_cell(reference, profile, x, y, z), (position, state)
    before = next(line for line in lines if line[0] == 'edited-before')
    after = next(line for line in lines if line[0] == 'edited-after')
    assert before[1:] == after[1:], 'Existing Core changed during initialize'
    assert before[1] == f'0,57,0,0,2,{state_count()}'
    assert parse_sections(before[2]) == section_digests(reference, profile, edited=True)
    assert before[3] == '5,7,9,block,minecraft:overworld,1,4294967235,0,1;'
    assert before[4] == 'applied,0,7,1,2;applied,0,0,0,1;'
    edited_view=next(line for line in lines if line[0] == 'edited-view-before')
    assert edited_view[4:] == fixture_view((.5,-60,.5),sentinel=True,cache=True)
    assert edited_view[2] == '1'
    assert edited_view[1:] == next(
        line[1:] for line in lines if line[0] == 'edited-view-after')
    assert len(lines) == 89, 'Unexpected harness output'
    return {'profile': profile, 'complete_sections': 75, 'loaded_cells': 307200,
            'actual_column_probes': 80, 'outside_probes': 3,
            'full_section_digests_match': True, 'edited_Core_retained': True,
            'time_pause_daylight_pending_events_and_view_retained': True,
            'generated_feet_exact': True}

BOUNDS = {
    'spawn': ((0,-60,0),(-3,-64,-3,8,8,8)),
    'negative-chunk': ((-16,-60,-16),(-19,-64,-19,8,8,8)),
    'low': ((-32,-80,-32),(-31,-79,-31,8,8,8)),
    'high': ((47,-33,47),(39,-41,39,8,8,8)),
    'top-neighbor': ((0,-37,0),(-3,-41,-3,8,8,8)),
    'min-x': ((-2147483648,-60,0),None),
    'min-y': ((0,-2147483648,0),None),
    'max-z': ((0,-60,2147483647),None),
    'loaded-fixture': ((0,1,0),None),
    'outside-x': ((48,-60,0),None),
    'outside-low-y': ((0,-81,0),None),
}

def bounds_commands():
    commands = ['bounds|' + id + '|' + '|'.join(str(unsigned(v)) for v in xyz)
                for id,(xyz,expected) in BOUNDS.items()]
    commands += ['bounds-float|negative-fraction|' + '|'.join(str(float_bits(v)) for v in (-.1,-60,-16.0001))]
    return commands

def compare_bounds(stdout):
    rows = [line.split('|') for line in stdout.splitlines()]
    expected = {id: ('fail|unsupported-superflat-view:outside-generated-region' if box is None
                     else ','.join(map(str, map(unsigned,box)))) for id,(_,box) in BOUNDS.items()}
    expected['negative-fraction'] = ','.join(map(str,map(unsigned,(-4,-64,-20,8,8,8))))
    assert len(rows) == len(expected)
    actual = {row[1]: '|'.join(row[2:]) for row in rows if row[0] == 'bounds'}
    assert actual == expected, (actual, expected)
    return {'cases': len(expected), 'signed_INT_MIN_refused': True,
            'negative_fraction_floor': True, 'complete_neighbor_halo': True,
            'unrelated_loaded_body_explicitly_refused': True}

def compare_follow(stdout):
    rows = [line.split('|') for line in stdout.splitlines()]
    assert len(rows) == 5 and [r[0] for r in rows] == ['follow-before','follow-same','follow-crossing-before','follow-moved','follow-core']
    assert rows[0][1:] == rows[1][1:], 'Unchanged region changed complete View'
    assert rows[1][1:3] == [','.join(map(str,map(unsigned,(-3,-64,-3,8,8,8)))),'1']
    assert rows[1][4:] == fixture_view((0,-60,0),sentinel=True,cache=True)
    assert rows[3][1:3] == [','.join(map(str,map(unsigned,(-2,-64,-3,8,8,8)))),'0']
    assert rows[2][3:9] == rows[3][3:9], 'Changed region changed Body/yaw/pitch/palette'
    assert rows[3][9] == 'none'
    assert list(map(int,rows[1][3].split(','))) == words64(0)+words64(-60)+words64(0)
    assert list(map(int,rows[3][3].split(','))) == words64(1)+words64(-60)+words64(0)
    assert rows[4][1:] == [f'0,0,1,1,0,{state_count()}','','',''], 'View follow mutated Core'
    return {'same_cell_cache_retained': True, 'crossing_cell_cache_invalidated': True,
            'authoritative_body_and_Core_retained': True}

def jobs():
    return [('superflat-custom',['custom']),('superflat-classic-core-only',['classic']),
            ('superflat-aperture',bounds_commands()),('superflat-follow',['follow'])]

def fixture_stdout(reference,profile):
    sections = lambda edited: ''.join(key+'='+str(value)+';' for key,value in section_digests(reference,profile,edited).items())
    region = ','.join(map(str,map(unsigned,(-3,-64,-3,8,8,8))))
    position = ','.join(map(str,words64(.5)+words64(-60)+words64(.5)))
    details='|'.join(fixture_view((.5,-60,.5)))
    rows = [f'generated|{profile}|0,0,1,1,1,{state_count()}|{sections(False)}||applied,0,0,0,1;',
            f'generated-view|{region}|0|{position}|{details}']
    for c in reference['cases']:
        if c['profile'] != profile: continue
        for y in (-81,-80,-65,-64,-63,-62,-61,-60,-33,-32):
            x,z=c['x'],c['z']
            rows.append('cell|'+','.join(map(str,map(unsigned,(x,y,z))))+'|'+expected_cell(reference,profile,x,y,z))
    for x,y,z in ((-33,-64,0),(48,-64,0),(0,-64,48)):
        rows.append('cell|'+','.join(map(str,map(unsigned,(x,y,z))))+'|'+expected_cell(reference,profile,x,y,z))
    core = f'0,57,0,0,2,{state_count()}|{sections(True)}|5,7,9,block,minecraft:overworld,1,4294967235,0,1;|applied,0,7,1,2;applied,0,0,0,1;'
    sentinel_details='|'.join(fixture_view((.5,-60,.5),sentinel=True,cache=True))
    rows += ['edited-before|'+core,f'edited-view-before|{region}|1|{position}|{sentinel_details}',
             'edited-after|'+core,f'edited-view-after|{region}|1|{position}|{sentinel_details}']
    return '\n'.join(rows)+'\n'

def comparator_controls(reference):
    profile='bendex:stone-dirt-superflat'
    baseline=fixture_stdout(reference,profile)
    compare_generated(baseline,profile,reference)
    faults={
        'layer-cell':baseline.replace('cell|0,4294967235,16|1','cell|0,4294967235,16|0',1),
        'section-digest':baseline.replace('minecraft:overworld/4294967294/4294967291/4294967294=',
                                       'minecraft:overworld/4294967294/4294967291/4294967294=1',1),
        'missing-outside':baseline.replace('cell|48,4294967232,0|fail:missing-section:minecraft:overworld/3/4294967292/0',
                                          'cell|48,4294967232,0|0',1),
        'loaded-clock':baseline.replace('edited-after|0,57,0,0,2,','edited-after|1,57,0,0,2,',1),
        'duplicate-response':baseline+baseline.splitlines()[2]+'\n',
    }
    reports=[]
    for label,mutated in faults.items():
        assert mutated != baseline, 'Corruption did not change fixture: '+label
        try: compare_generated(mutated,profile,reference)
        except (AssertionError,ValueError,StopIteration): reports.append(label)
        else: raise AssertionError('Comparator admitted corruption: '+label)
    return {'synthetic_comparator_baseline_passed':True,'corruptions_refused':reports,
            'scope':'Host comparator sensitivity only; no native execution implied.'}

def suite(executor):
    reference = load(); reports = []; receipts = []
    for label,args in jobs():
        stdout, receipt = executor(label,args,{'MC_BLOCK_REGISTRY':str(OFFICIAL)})
        if args == ['custom']: report = compare_generated(stdout,'bendex:stone-dirt-superflat',reference)
        elif args == ['classic']: report = compare_generated(stdout,'minecraft:classic_flat',reference)
        elif args == ['follow']: report = compare_follow(stdout)
        else: report = compare_bounds(stdout)
        reports.append({'label':label,**report}); receipts.append(receipt)
    return {'reports':reports,'receipts':receipts,
            'scope':'Actual base-column cells, entire bounded section digests, edited Core preservation and transient view ownership; ClassicFlat Core generation only.'}

def prepare():
    reference = load()
    assert len(section_digests(reference,'bendex:stone-dirt-superflat')) == 75
    assert len(section_digests(reference,'minecraft:classic_flat')) == 75
    result = {'status':'prepared-native-unverified','sources':{str(p.relative_to(ROOT)):fingerprint(p) for p in (SOURCE,SCENE,HARNESS)},
              'driver':fingerprint(Path(__file__)),'reference':fingerprint(REFERENCE),
              'registry':fingerprint(OFFICIAL),'jobs':[{'label':label,'args':args} for label,args in jobs()],
              'shared_dispatch':'superflat-cases','worst_source_quads':8*8*8*6,
              'comparator_controls':comparator_controls(reference),
              'native_plan':'Root shared playable artifact only; no standalone build or hidden process mode.'}
    WORK.mkdir(parents=True,exist_ok=True)
    write_json(WORK/'plan.json',result)
    write_json(ROOT/'evidence/superflat-world-preparation.json',result)
    return result

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--prepare',action='store_true',required=True)
    parser.parse_args()
    print(json.dumps(prepare(),indent=2))

if __name__ == '__main__': main()
