#!/usr/bin/env python3
"""Check cached-recipe result preservation in one frozen Actor023 pure graph.

No actor build or timing is performed here. The independent kernel checks all
five declared laws, including arbitrary-list equivalence to the retained prior
lookup. Native compares complete plans and fallback/refusal results to explicit
goldens; the existing 26.3 furnace observation remains a separate reference.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import shutil
import struct
import sys

import test_local_player_effect_entities_codec as H
import test_crafting_recipe_components as C

ROOT, BEND, Build = H.ROOT, H.BEND, H.Build
WORK = ROOT / 'build/furnace-authority-cache'
OWNED = ('src/furnace_authority.bend', 'src/furnace_authority_cache_laws.bend',
         'src/furnace_authority_cache_proof.bend', 'tests/furnace_authority_cache.bend')


def stack(item, count=1, components=''):
    return {'id': item, 'count': count, 'components': components}


def plan(*, output=None, time=200, xp=.35):
    return {'id': 'test:first', 'kind': 'minecraft:smelting',
            'output': stack('minecraft:cooked_beef') if output is None else output,
            'before': stack('minecraft:beef', 2), 'time': time,
            'experience_bits': struct.unpack('>I', struct.pack('>f', xp))[0]}


def expected():
    complete = plan()
    emptied = plan(time=73, xp=1.25); emptied['output'] = None
    alternate = plan(output=stack('minecraft:charcoal', 2), time=73, xp=1.25)
    modified = plan(output=stack('minecraft:charcoal', 7,
        'BendCraftComponents1\t16\t{"minecraft:max_stack_size":16}'), time=73, xp=1.25)
    cached = {
        'absent-cache': None, 'empty-catalog': None, 'missing-id': None,
        'matching-head': complete, 'skip-different-id': complete,
        'cached-id-beats-earlier-input-match': complete,
        'first-duplicate-wins': complete, 'unsupported-first-duplicate': None,
        'wrong-kind-first-duplicate': None, 'wrong-input-first-duplicate': None,
        'invalid-output-id-keeps-plan': emptied, 'zero-output-keeps-plan': emptied,
        'oversized-output-keeps-plan': emptied, 'empty-input': None,
        'zero-input-count': None, 'tag-input': alternate, 'missing-tag': None,
        'exact-component-output': modified,
    }
    selection = {
        'unsupported-first-falls-back': {'plan': complete, 'cached': 'test:first'},
        'invalid-output-does-not-fall-back': {'plan': emptied, 'cached': 'test:first'},
        'missing-cache-falls-back': {'plan': complete, 'cached': 'test:first'},
        'miss-retains-cache': {'plan': None, 'cached': 'test:missing'},
        'invalid-input-count-refuses': {'error': 'invalid cooking input: item definition, count or components'},
        'empty-input-retains-cache': {'plan': None, 'cached': 'test:missing'},
    }
    return {'cached': cached, 'selection': selection}


def freeze(directory):
    baseline = ROOT / 'build/compiler-producer-diagnostic-023/source'
    mapping = json.loads((baseline / 'source-map.json').read_bytes())
    for row in mapping['files']:
        H.require(H.pin(baseline / row['path'])['sha256'] == row['original_sha256'],
                  'Frozen023 source drift: ' + row['path'])
    source = directory / 'source'
    shutil.copytree(baseline, source)
    for relative in OWNED:
        target = source / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes((ROOT / relative).read_bytes())
    H.write(directory / 'sources.json', {
        'baseline_source_map': H.pin(baseline / 'source-map.json'),
        'product_delta': ['src/furnace_authority.bend'],
        'source_overlays': {relative: H.pin(source / relative) for relative in OWNED},
        'tools': [H.pin(Path(__file__)), H.pin(Path(H.__file__)), H.pin(Path(Build.__file__))],
    })
    return source


def exporter(source, directory):
    roots = ['furnace_authority_cache_laws:' + name for name in re.findall(
        r'^law (\w+):', (source / 'src/furnace_authority_cache_laws.bend').read_text(), re.M)]
    H.require(len(roots) == 5, 'All five declared cache laws must be checked')
    script = '''import * as B from "file:///Users/chuah/Documents/ChatGPT/bendex/bend/bend2/bend.ts";
import * as Safe from "file:///Users/chuah/Documents/ChatGPT/bendex/bend/bend2/safe.ts";
import * as fs from "node:fs";import * as crypto from "node:crypto";
const entry=ENTRY,dir=DIR,roots=ROOTS;
const sha=x=>crypto.createHash("sha256").update(x).digest("hex");
const book=B.book_nil(),seen=new Map();await B.book_load(book,entry,"",seen);
const pins=()=>Object.fromEntries([...seen.keys()].sort().map(p=>[p,sha(fs.readFileSync(p))]));
const before=pins();B.book_valid(book);if(book.hols!==0)throw Error("Open proof holes");
console.log("ALL ORDINARY SOURCE CHECKS PASS");
const order=[...book.order],tlds=book.tlds,ctrs=book.ctrs,tmps=book.tmps;
const originals=Object.entries(tlds).map(([k,t])=>[k,t,t.T,t.$==="Def"?t.v:null,t.$==="Def"?t.e:null]);
const termPins=roots.map(k=>{const t=tlds[k];if(t?.$!=="Def"||!t.e||!t.v||t.u||t.i)throw Error("Missing checked pure proof "+k);return {name:k,type_sha256:sha(B.term_key(B.term_lower(t.T))),checked_proof_sha256:sha(B.term_key(t.e)),source_body_sha256:sha(B.term_key(B.term_lower(t.v)))};});
book.order=order.filter((k,i)=>roots.includes(k)&&order.lastIndexOf(k)===i);
if(book.order.length!==roots.length||book.tlds!==tlds||book.ctrs!==ctrs||book.tmps!==tmps)throw Error("Declaration ownership changed");
for(const [k,t,T,v,e] of originals)if(book.tlds[k]!==t||t.T!==T||(t.$==="Def"&&(t.v!==v||t.e!==e)))throw Error("Checked term changed "+k);
const exclusions=Safe.safe_emit(book,dir+"/selected.bendtt");
if(JSON.stringify(before)!==JSON.stringify(pins()))throw Error("Proof source changed");
fs.writeFileSync(dir+"/selection.json",JSON.stringify({roots,termPins,exclusions,source_pins:before,holes:book.hols,checked_types_and_bodies_unchanged:true,all_original_declaration_maps_retained:true},null,2)+"\\n");
if(exclusions.length)throw Error("Export exclusions "+JSON.stringify(exclusions));
console.log("CHECKED ROOT EXPORT PASS");
'''.replace('ENTRY', json.dumps(str(source / 'src/furnace_authority_cache_proof.bend'))).replace(
        'DIR', json.dumps(str(directory))).replace('ROOTS', json.dumps(roots))
    path = directory / 'export.mjs'; path.write_text(script)
    return path


def build_child(directory):
    with H.forbid_retries():
        report = Build.ensure_native(directory / 'source/tests/furnace_authority_cache.bend',
            directory / 'native', bend=BEND, cache_dir=WORK / 'native-cache')
    H.require(report['retries'] == 0, 'Focused cache builder retried')
    H.write(directory / 'build.json', report)


def main(native):
    WORK.mkdir(parents=True, exist_ok=True)
    number = 1
    while (directory := WORK / f'attempt-{number:03}').exists(): number += 1
    directory.mkdir()
    source, processes = freeze(directory), []
    overlays = {relative: H.pin(source / relative) for relative in OWNED}
    try:
        def run(argv, label, cap):
            process = H.bounded(directory, argv, label, cap)
            processes.append(process); H.process_ok(process)
            H.require(not Path(process['stderr']['path']).read_bytes(), 'Unexpected stderr: ' + label)
            return process
        script = exporter(source, directory)
        ordinary = run([C.NODE, '--experimental-transform-types', '--disable-warning=ExperimentalWarning',
            '--max-old-space-size=4096', '--stack-size=4096', script], 'original-source-and-export', 90)
        H.require('CHECKED ROOT EXPORT PASS' in Path(ordinary['stdout']['path']).read_text(), 'Original cache proof check')
        kernel = run(['/usr/bin/env', 'LEAN_STACK_SIZE=4194304', C.KERNEL, directory / 'selected.bendtt'], 'kernel', 60)
        H.require(Path(kernel['stdout']['path']).read_text().strip() == 'ALL PROOFS CHECK', 'Independent cache kernel')
        result = {'status': 'PASS_KERNEL', 'laws': 5, 'sources': H.pin(directory / 'sources.json'),
            'selection': H.pin(directory / 'selection.json'), 'kernel': H.pin(C.KERNEL),
            'kernel_input': H.pin(directory / 'selected.bendtt'), 'processes': processes,
            'actor_timing': 'not executed by this runner', 'full_actor_source_verdict': 'separate'}
        if native:
            run([sys.executable, '-B', Path(__file__), '--build-child', directory], 'native-build', 240)
            output_pins = []
            for threads in (1, 4):
                tested = run(['/usr/bin/env', f'BEND_THREADS={threads}', 'BEND_GPU=0', directory / 'native'],
                             f'native-{threads}-threads', 30)
                actual = json.loads(Path(tested['stdout']['path']).read_bytes())
                golden = expected()
                H.require(set(actual) == set(golden), 'Complete cache protocol')
                for group in golden:
                    H.require([row['id'] for row in actual[group]] == list(golden[group]), 'Ordered cache cases: ' + group)
                    for row in actual[group]:
                        H.require(row['actual'] == golden[group][row['id']], 'Independent cache result: ' + row['id'])
                        if group == 'cached':
                            H.require(row['previous'] == row['actual'], 'Retained previous result differs: ' + row['id'])
                output_pins.append(tested['stdout'])
            H.require(output_pins[0]['sha256'] == output_pins[1]['sha256'], 'Native thread outputs differ')
            result.update(status='PASS_NARROW', native_cases=sum(map(len, expected().values())),
                previous_result_comparisons=len(expected()['cached']), native_threads=[1, 4],
                binary=H.pin(directory / 'native'), build=H.pin(directory / 'build.json'))
        H.require(overlays == {relative: H.pin(source / relative) for relative in OWNED}, 'Frozen cache overlay drift')
        H.write(directory / 'result.json', result)
        compact = dict(result, processes=[{key: process[key] for key in ('pid','exit_code','timed_out','cleanup','seconds','stdout','stderr')} for process in processes],
            complete_receipt=H.pin(directory / 'result.json'), scope=__doc__)
        H.write(ROOT / f'evidence/furnace-authority-cache-{number:03}.json', compact)
        print(json.dumps({'status': result['status'], 'directory': str(directory), 'laws': 5,
                          'native_cases': result.get('native_cases', 0)}), flush=True)
    except BaseException as error:
        failure = {'status':'FAIL','type':type(error).__name__,'message':str(error),'processes':processes}
        H.write(directory / 'failure.json', failure)
        H.write(ROOT / f'evidence/furnace-authority-cache-{number:03}-failure.json',
                dict(failure, complete_receipt=H.pin(directory / 'failure.json')))
        raise


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--native', action='store_true', help='one tested native emission after the five-law kernel')
    parser.add_argument('--build-child', type=Path, help=argparse.SUPPRESS)
    arguments = parser.parse_args()
    build_child(arguments.build_child) if arguments.build_child else main(arguments.native)
