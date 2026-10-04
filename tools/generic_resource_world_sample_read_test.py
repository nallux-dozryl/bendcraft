#!/usr/bin/env python3
"""Prepare and optionally execute the actual Core sampler and Wire observer.

Default preparation starts no Bend, Java, kernel, emitter, clang, or native job.
The explicit execution flags require the team's actual process coordination.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import math
import os
from pathlib import Path
import struct
import sys

PYTHON = Path.home()/'.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3'
if Path(sys.executable).resolve() != PYTHON.resolve():
    os.execv(str(PYTHON), [str(PYTHON), __file__, *sys.argv[1:]])

import resource_block_catalog_test as Catalog
import test_registry

ROOT = Path(__file__).resolve().parents[1]
ENTRY = ROOT/'tests/generic_resource_world_sample_read.bend'
EVIDENCE = ROOT/'evidence/generic_resource_world_sample_read_native.json'
WORK = ROOT/'build/generic-resource-world-sample-read-tests'
MASK = 0xffffffff
DEFAULT = [[], MASK, 0, 0, False, 128]
SCOPE = ('Actual arbitrary Core block reads through Read.snapshot, exact section-array/trie topology '
         'and all Core fields compared through existing core_refusal world_image/worlds_equal, all six '
         'View fields and actual official Registry.identity observed before/after, returned owner reused '
         'for subsequent reads and edits, independent host traversal/seed/appearance oracle, actual '
         'direct catalog sample codec and full reply text codec. No simulation ticking, legacy palette '
         'sampling, resource binding, model geometry, shader/GPU/render/frame, UI-loop or Java parity claim.')


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=False).encode()


def pin(path):
    path = Path(path)
    return {'path': str(path), 'bytes': path.stat().st_size, 'sha256': Catalog.sha(path)}


def configure(number):
    global WORK
    assert 1 <= number <= 999
    if number != 1:
        WORK = WORK/f'generation-{number:03d}'
    Catalog.ENTRY, Catalog.WORK, Catalog.BINARY = ENTRY, WORK, WORK/'native'
    Catalog.PRIVATE, Catalog.EVIDENCE = WORK/'private-001', EVIDENCE


def f32(value):
    return struct.unpack('>I', struct.pack('>f', value))[0]


def f64(value):
    return list(struct.unpack('>II', struct.pack('>d', value)))


def origin(x=0, y=0, z=0):
    return [*f64(x), *f64(y), *f64(z)]


def u32(value):
    return value & MASK


def signed(value):
    return value if value < 0x80000000 else value - 0x100000000


def pos(x, y, z, state):
    return {'x': u32(x), 'y': u32(y), 'z': u32(z), 'state': state}


def region(x=0, y=0, z=0, width=1, height=1, depth=1):
    return dict(x=u32(x), y=u32(y), z=u32(z), width=width, height=height, depth=depth)


def state_id(records, name, properties=None):
    block = next(b for b in records if b['name'] == 'minecraft:'+name)
    if properties is None:
        return block['default']
    assert set(properties) == {p['name'] for p in block['properties']}
    return block['first'] + sum(p['values'].index(properties[p['name']])*p['stride'] for p in block['properties'])


def tint(color, **changes):
    value = [[[0, color]], MASK, 0, 0, False, 128]
    for key, index in [('light', 1), ('address', 2), ('cull', 3), ('nether', 4), ('threshold', 5)]:
        if key in changes:
            value[index] = changes[key]
    return value


def corpus(records, identity):
    air, stone = state_id(records, 'air'), state_id(records, 'stone')
    slab = state_id(records, 'oak_slab', {'type':'top', 'waterlogged':'false'})
    stairs = state_id(records, 'oak_stairs', {'facing':'east', 'half':'top', 'shape':'outer_right', 'waterlogged':'false'})
    cases = []
    def add(name, **fields):
        case = {'name': name, 'registry': str(Catalog.REGISTRY), 'identity': identity,
                'region': region(), 'origin': origin(37.25, 10.27, -13.5),
                'yaw': f32(.5), 'pitch': f32(-.25), 'palette': 'none', 'cache': 'none',
                'sections': [pos(0,0,0,air)], 'writes': [], 'policy': {'seed': 0},
                'observations': [{'name': name}], **fields}
        cases.append(case)
        return case
    sections = [pos(x,0,z,air) for z in (-1,0) for x in (-1,0)]
    writes = [pos(-1,0,-1,slab), pos(0,0,-1,stairs), pos(-1,1,-1,air), pos(0,1,-1,stone),
              pos(-1,0,0,0xffffffff), pos(0,0,0,air), pos(-1,1,0,slab), pos(0,1,0,stairs)]
    base = dict(region=region(-1,0,-1,2,2,2), sections=sections, writes=writes)
    add('signed-raw-air-slab-stairs-unknown', **base,
        observations=[{'name':'signed-first'}, {'name':'signed-repeated'}])
    add('aliased-palette-invalid-cache-ignored', **base, palette='aliases', cache='bad')
    add('absent-palette-invalid-cache-ignored', **base, cache='bad')
    add('matching-stale-cache-and-raw-change', **base, palette='normal', cache='stale',
        observations=[{'name':'stale-first'}, {'name':'stale-after-change','writes':[pos(-1,0,-1,stairs)]},
                      {'name':'stale-repeated'}])
    defaults = tint(0xff010203, light=0xff112233, address=1, cull=1, nether=True, threshold=7)
    state_surface = tint(0xffa0b0c0, light=0xff445566, threshold=64)
    cell_surface = tint(0xff987654, address=1, threshold=255)
    add('default-state-cell-appearance-precedence', **base,
        policy={'seed': MASK, 'default': defaults, 'states':[{'state':slab,'appearance':state_surface}],
                'cells':[{'x':u32(-1),'y':0,'z':u32(-1),'appearance':cell_surface},
                         {'x':0,'y':1,'z':u32(-1),'appearance':tint(0xffabcd00)}]})
    add('first-missing-section', **{**base, 'sections':[], 'writes':[]})
    add('late-missing-section', **{**base, 'sections':[sections[0]], 'writes':[writes[0]]})
    add('all-air-still-read', region=region(0,0,0,2,2,2))
    add('nonempty-custom-registry-token-retained', identity='test:registry-vx')
    add('empty-registry-token', identity='', sections=[])
    add('zero-width-before-missing', region=region(width=0), sections=[])
    add('axis-above-sixteen', region=region(width=17), sections=[])
    add('signed-positive-axis-overflow', region=region(2147483647,0,0,2,1,1), sections=[])
    add('region-before-origin-camera-identity', region=region(width=0), origin=origin(math.inf),
        yaw=0x7f800000, identity='', sections=[])
    add('infinite-origin-before-camera', origin=origin(math.inf), yaw=0x7f800000, sections=[])
    add('nan-origin', origin=origin(math.nan), sections=[])
    add('origin-at-positive-outside', origin=origin(2147483648), sections=[])
    add('origin-below-negative-outside', origin=origin(-2147483649), sections=[])
    add('yaw-infinity', yaw=0x7f800000, sections=[])
    add('pitch-nan', pitch=0x7fc00000, sections=[])
    add('finite-yaw-too-large', yaw=f32(65537), sections=[])
    add('finite-camera-limit-inclusive', yaw=f32(65536), pitch=f32(-65536))
    add('fractional-origin-near-positive-limit', origin=origin(2147483647.75))
    add('signed-minimum-cell', region=region(-2147483648,0,0), sections=[pos(-2147483648,0,0,slab)])
    add('invalid-appearance-after-valid-reads', policy={'default':[[],MASK,0,0,False,256]})
    add('duplicate-tint-index-after-valid-reads', policy={'default':[[[0,1],[0,2]],MASK,0,0,False,128]})
    add('invalid-light-after-valid-reads', policy={'default':[[],0x00112233,0,0,False,128]})
    add('missing-section-before-invalid-appearance', sections=[], policy={'default':[[],MASK,0,0,False,256]})
    add('sampler-token-accepted-wire-ascii-refused', identity='test:λ')
    add('sampler-token-accepted-wire-space-refused', identity='test registry')
    add('sampler-token-accepted-wire-length-refused', identity='x'*129)
    add('maximum4096-direct-codec-full-wire-value-budget', region=region(-16,-16,-16,16,16,16),
        sections=[pos(-16,-16,-16,air)], policy={'seed':0x12345678})
    dense = [[[i, 0xff123456] for i in range(256)],MASK,1,1,False,255]
    add('valid-tints-full-wire-text-budget', region=region(0,0,0,16,1,1), policy={'default':dense})
    add('valid-tints-full-wire-value-budget', region=region(0,0,0,16,2,1), policy={'default':dense})
    return cases


def region_values(value):
    return [value[key] for key in ('x','y','z','width','height','depth')]


def view_expected(case):
    body = [origin(37,9,-13), origin(1,2,3), origin(4,5,6), origin(7,8,9), f32(.6), f32(1.8), True, False, True, False]
    palette = {'none':None, 'aliases':[7,7,7,7], 'normal':[0,1,10,15]}[case['palette']]
    cache = None
    if case['cache'] == 'bad':
        cache = [999,[0,0,0,0,1,1],[7,7,7,7],[[123,456,789,99,MASK,99]]]
    elif case['cache'] == 'stale':
        cache = [11,region_values(case['region']),[0,1,10,15],[[MASK,0,MASK,0,1,0]]]
    return [body,case['yaw'],case['pitch'],palette,region_values(case['region']),cache]


def preflight(case):
    r = case['region']
    if any(not 1 <= r[d] <= 16 for d in ('width','height','depth')) or any(
            signed(r[a])+r[d]-1 > 2147483647 for a,d in zip(('x','y','z'),('width','height','depth'))):
        return 'generic-resource:invalid-region'
    coordinates = [struct.unpack('>d', struct.pack('>II', *case['origin'][i:i+2]))[0] for i in (0,2,4)]
    if any(not math.isfinite(x) or not -2147483648 <= math.floor(x) <= 2147483647 for x in coordinates):
        return 'generic-resource:invalid-origin'
    angles = [struct.unpack('>f', struct.pack('>I', case[key]))[0] for key in ('yaw','pitch')]
    if any(not math.isfinite(x) or abs(x) > 65536 for x in angles):
        return 'generic-resource:invalid-camera'
    if not case['identity']:
        return 'generic-resource:invalid-registry-identity'
    return None


def mixed(seed, index):
    return ((seed ^ (((index+1)&MASK)*2246822519&MASK))*3266489917)&MASK


def appearance_valid(value):
    colors,light,address,cull,nether,threshold = value
    indexes = [row[0] for row in colors]
    return light >> 24 == 255 and threshold <= 255 and len(colors) <= 256 and MASK not in indexes and len(set(indexes)) == len(indexes)


def section_key(point):
    return tuple(signed(x)//16 for x in point)


def expected_sample(case, sections, writes):
    error = preflight(case)
    if error:
        return {'error': error}
    r, p = case['region'], case['policy']
    surfaces = {row['state']:row['appearance'] for row in p.get('states', [])}
    overrides = {(row['x'],row['y'],row['z']):row['appearance'] for row in p.get('cells', [])}
    cells = []
    for iz in range(r['depth']):
        for iy in range(r['height']):
            for ix in range(r['width']):
                point = tuple(u32(r[a]+d) for a,d in zip(('x','y','z'),(ix,iy,iz)))
                key = section_key(point)
                if key not in sections:
                    return {'error':'missing-section:minecraft:overworld/'+'/'.join(str(u32(x)) for x in key)}
                state = writes.get(point, sections[key])
                edge = sum(i == 0 or i+1 == size for i,size in zip((ix,iy,iz),(r['width'],r['height'],r['depth'])))
                seed = p.get('seed', 0)
                for coordinate in point:
                    seed = mixed(seed, coordinate)
                surface = copy.deepcopy(overrides.get(point, surfaces.get(state, p.get('default', DEFAULT))))
                cells.append([*point,edge,state,seed,surface])
    if any(not appearance_valid(row[-1]) for row in cells):
        return {'error':'generic-resource:invalid-sample'}
    return {'sample':[case['identity'],7,11,case['origin'],[0,0,0,case['yaw'],case['pitch']],cells]}


def ast_nodes(value):
    return 1+sum(map(ast_nodes,value)) if isinstance(value,list) else 1


def expected_wire(sample):
    identity = sample[0]
    valid = 0 < len(identity) <= 128 and all(33 <= ord(x) <= 126 for x in identity)
    if not valid:
        return {'direct':'wire:catalog-sample', 'full':'wire:invalid-reply'}
    reply = [1,7,'sample-test',1,sample]
    if ast_nodes(reply) > 16384:
        return {'direct':None, 'full':'wire:encoded-value-budget'}
    text = json.dumps(reply, separators=(',',':'),ensure_ascii=True)
    return {'direct':None, 'full':'wire:encoded-transport-parser-budget' if len(text)>65536 else None}


def prepare():
    WORK.mkdir(parents=True,exist_ok=True)
    target = WORK/'preparation.json'
    assert not target.exists(), 'Preserve existing preparation; use a fresh --generation'
    reference = json.loads(Catalog.REFERENCE_EVIDENCE.read_text())
    assert Catalog.sha(Catalog.REGISTRY) == reference['sources']['tables']['generated/reference_blocks.tsv']['sha256']
    records = Catalog.registry_records(Catalog.REGISTRY)
    identity = test_registry.identity_hash(records)
    cases = corpus(records,identity)
    expected = []
    for case in cases:
        sections = {section_key((s['x'],s['y'],s['z'])):s['state'] for s in case['sections']}
        writes = {(s['x'],s['y'],s['z']):s['state'] for s in case['writes']}
        for step in case['observations']:
            writes.update({(s['x'],s['y'],s['z']):s['state'] for s in step.get('writes',[])})
            value = expected_sample(case,sections,writes)
            expected.append({'name':step['name'], 'view':view_expected(case), **value,
                             **({'wire':expected_wire(value['sample'])} if 'sample' in value else {})})
    prep = {'sources':Catalog.sources(),'entry':pin(ENTRY),'driver':pin(__file__),'registry':pin(Catalog.REGISTRY),
            'registry_identity':identity,'registry_state_count':sum(row['count'] for row in records),
            'cases':cases,'expected':expected,'scope':SCOPE}
    target.write_text(json.dumps(prep,sort_keys=True,indent=2)+'\n')
    evidence = {'status':'prepared_native_unexecuted','scope':SCOPE,'sources':prep['sources'],
                'preparation':{'path':str(target),'sha256':Catalog.sha(target),'cases':len(cases),'observations':len(expected)},
                'entry':prep['entry'],'driver':prep['driver'],'registry':prep['registry'],'registry_identity':identity,
                'checked_source':False,'native_executed':False}
    EVIDENCE.write_text(json.dumps(evidence,sort_keys=True,indent=2)+'\n')
    print(json.dumps({'status':evidence['status'],**evidence['preparation']}))


def preparation():
    prep = json.loads((WORK/'preparation.json').read_text())
    assert prep['sources'] == Catalog.sources(), 'Actual source graph changed; preserve and use a fresh generation'
    assert prep['driver'] == pin(__file__) and prep['registry'] == pin(Catalog.REGISTRY)
    return prep


def freeze():
    prep = preparation()
    manifest = Catalog.prepare_private(prep['sources'])
    emitter = Catalog.PRIVATE/'diagnose.mjs'
    old = str(Catalog.PRIVATE/'source/tests/resource_block_catalog.bend')
    new = str(Catalog.PRIVATE/'source/tests/generic_resource_world_sample_read.bend')
    if manifest['entry'] != new:
        text = emitter.read_text()
        assert old in text and not (Catalog.PRIVATE/'receipt.json').exists()
        emitter.write_text(text.replace(old,new))
        manifest['files'][str(emitter)] = Catalog.sha(emitter)
        manifest['entry'], manifest['scope'] = new,SCOPE+' Existing measured queue/zero-arity producer relocated only.'
        (Catalog.PRIVATE/'manifest.json').write_text(json.dumps(manifest,sort_keys=True,indent=2)+'\n')
    assert Catalog.prepare_private(prep['sources']) == manifest
    evidence = json.loads(EVIDENCE.read_text())
    evidence['private_preparation'] = {'manifest':pin(Catalog.PRIVATE/'manifest.json'),'basis':manifest['basis'],
                                       'entry':new,'limits':manifest['limits'],'exact_dependency_bytes':True}
    EVIDENCE.write_text(json.dumps(evidence,sort_keys=True,indent=2)+'\n')
    print(json.dumps({'status':'frozen_unexecuted','entry':new,'sources':len(prep['sources'])}))


def check():
    prep = preparation()
    result, receipt = Catalog.run([Catalog.BEND,ENTRY,'--check-only'],'source-check',180)
    assert 'ALL PROOFS CHECK' in result.stdout and Catalog.sources() == prep['sources']
    evidence = json.loads(EVIDENCE.read_text())
    evidence.update(checked_source=True,source_check=receipt,status='source_checked_native_unexecuted')
    EVIDENCE.write_text(json.dumps(evidence,sort_keys=True,indent=2)+'\n')


def build():
    freeze()
    prep = preparation()
    receipt = Catalog.build_private(prep['sources'])
    stamp = {'sources':prep['sources'],'binary_sha256':Catalog.sha(Catalog.BINARY),'receipt':receipt}
    (WORK/'native-build.json').write_text(json.dumps(stamp,sort_keys=True,indent=2)+'\n')
    evidence = json.loads(EVIDENCE.read_text())
    evidence.update(status='native_built_observations_pending',native_build=receipt,native_binary_sha256=stamp['binary_sha256'])
    EVIDENCE.write_text(json.dumps(evidence,sort_keys=True,indent=2)+'\n')


def verify(prep, reports):
    assert len(reports) == len(prep['expected'])
    successes = refusals = cells = direct_refusals = full_refusals = 0
    core = [7,12345,False,False,11,prep['registry_state_count'],
            [[[99,8,9],['time',777]]], [['applied',[6,4,3],10],['rejected',[5,2,1],'invalid-state:4294967295']]]
    for expected, observed in zip(prep['expected'],reports):
        name = expected['name']
        assert observed['name'] == name and observed['complete_core_equal'] is True, (name,'complete Core')
        assert observed['before'] == observed['after'] == {'registry':prep['registry_identity'],'view':expected['view'],'core':core}, (name,'owner observation')
        result = observed['result']
        if 'error' in expected:
            assert result == {'status':'error','error':expected['error']}, (name,result,expected['error'])
            refusals += 1
            continue
        assert result['status'] == 'ok' and result['sample'] == expected['sample'], (name,'independent cells')
        successes += 1
        cells += len(expected['sample'][-1])
        direct, full = result['direct_wire'], result['full_wire']
        if expected['wire']['direct']:
            assert direct == {'status':'error','error':expected['wire']['direct']}, (name,'direct wire',direct)
            direct_refusals += 1
        else:
            assert direct == {'status':'ok','sample':expected['sample']}, (name,'direct roundtrip')
        if expected['wire']['full']:
            assert full == {'status':'error','error':expected['wire']['full']}, (name,'full wire',full)
            full_refusals += 1
        else:
            assert full['status'] == 'ok' and json.loads(full['text']) == [1,7,'sample-test',1,expected['sample']]
            assert full['decoded'] == {'status':'ok','epoch':'sample-test','sequence':1,'sample':expected['sample']}
    return dict(observations=len(reports),sampler_successes=successes,sampler_refusals=refusals,observed_cells=cells,
                direct_wire_refusals=direct_refusals,full_wire_refusals=full_refusals,complete_core_equal_checks=len(reports))


def execute():
    prep = preparation()
    stamp = json.loads((WORK/'native-build.json').read_text())
    assert stamp['sources'] == prep['sources'] and stamp['binary_sha256'] == Catalog.sha(Catalog.BINARY)
    runs, copies = [],[]
    for iteration in (1,2):
        reports = []
        for offset in range(0,len(prep['cases']),4):
            group = prep['cases'][offset:offset+4]
            result,receipt = Catalog.run([Catalog.BINARY,'--threads','1','--gpu','off',
                    *(canonical(case).decode() for case in group)],f'native-{iteration}-{offset:03d}',180)
            lines = result.stdout.splitlines()
            assert len(lines) == sum(len(case['observations']) for case in group), (offset,'stdout report cardinality')
            reports.extend(json.loads(line) for line in lines)
            runs.append(receipt)
        counts = verify(prep,reports)
        copies.append(reports)
    assert copies[0] == copies[1] and Catalog.sources() == prep['sources']
    evidence = json.loads(EVIDENCE.read_text())
    evidence.update(status='passed',native_executed=True,native_runs=runs,validation={**counts,'two_runs_equal':True},
                    reports_sha256=hashlib.sha256(canonical(copies[0])).hexdigest())
    EVIDENCE.write_text(json.dumps(evidence,sort_keys=True,indent=2)+'\n')
    print(json.dumps({'status':'passed',**evidence['validation']}))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--generation',type=int,default=1)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--prepare-private',action='store_true')
    mode.add_argument('--check-source',action='store_true')
    mode.add_argument('--build-private',action='store_true')
    mode.add_argument('--reuse-native',action='store_true')
    args = parser.parse_args()
    configure(args.generation)
    if not (WORK/'preparation.json').exists():
        prepare()
    if args.prepare_private: freeze()
    elif args.check_source: check()
    elif args.build_private:
        build()
        execute()
    elif args.reuse_native: execute()
    else: print(json.dumps({'status':'prepared_only','path':str(WORK/'preparation.json')}))


if __name__ == '__main__':
    main()
