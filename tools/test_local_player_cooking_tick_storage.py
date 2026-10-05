#!/usr/bin/env python3
"""Narrow native checks for the single-image format5 storage component.

Use the established entity-codec builder and bounded runner. Python constructs
ordered physical NBT; no cooking/tick/manager semantics run on the host.
"""
from __future__ import annotations
import argparse
import dataclasses
import hashlib
import json
from pathlib import Path
import sys
import test_local_player_effect_entities_codec as H
import test_local_player_effect_tick_recovery as Q
import test_entity_membership_codec as Manager
import test_nbt as N

ROOT=H.ROOT
ENTRY=ROOT/'tests/local_player_cooking_tick_storage.bend'
WORK=ROOT/'build/local-player-cooking-tick-storage'
H.ENTRY=ENTRY
GUARDS=(
    'constructor clock duplicates and order retained',
    'legacy projection retains unavailable runtime and sound',
    'legacy cannot restore guessed runtime',
    'clock field must be LongArray',
    'known recovery cannot be replaced by empty entity bytes',
    'noncanonical runtime tail refuses storage encode',
    'storage encode byte limit refuses',
    'storage encode depth limit refuses',
    'storage encode element limit refuses',
    'known empty manager remains distinct from unavailable',
    'known empty manager survives full restoration as data',
    'aggregate envelope bound refuses individually fitting nested images',
    'full recovery and remaining clock words roundtrip',
    'sole owner and clock inputs survive repeated inspect',
    'physical component trailing bytes refuse',
)
CLOCKS=((0xffffffff,0),(0x80000000,0xffffffff),(0,0),(0xffffffff,0))

def envelope(recovery=None,membership=None):
    return N.RootTag(N.text('bendex:local-player-cooking-tick-storage'),H.compound(
        format=H.integer(1),recovery=N.Value(7,N.encode_root(Q.root() if recovery is None else recovery)),
        membership=N.Value(9,(7,() if membership is None else (N.Value(7,membership),)))))

def root(payload=None,clocks=CLOCKS):
    return N.RootTag(N.text('fixture:local-player-cooking-tick-storage'),H.compound(
        entities=N.Value(7,N.encode_root(envelope()) if payload is None else payload),
        clock_inputs=N.Value(12,tuple((hi<<32)|lo for hi,lo in clocks))))

def empty_manager():
    return N.RootTag(N.text('bendex:entity-membership'),H.compound(format=H.integer(1),
        members=N.Value(9,(10,())),sections=N.Value(9,(10,())),chunks=N.Value(9,(10,())),
        tracked=N.Value(9,(10,())),ticked=N.Value(9,(10,()))))

def corpus():
    full=root()
    rows=[('full-owner-and-clocks',N.encode_root(full),True),
          ('empty-clock-source',N.encode_root(root(clocks=())),True),
          ('reversed-clock-source',N.encode_root(root(clocks=tuple(reversed(CLOCKS)))),True),
          ('legacy-unavailable',N.encode_root(root(N.encode_root(envelope(Q.root(runtimes=False,sound=False))))),True),
          ('known-empty-manager',N.encode_root(root(N.encode_root(envelope(membership=N.encode_root(empty_manager()))))),True),
          ('full-manager-and-tick',N.encode_root(root(N.encode_root(envelope(membership=N.encode_root(Manager.root()))))),True)]
    def add(name,document):rows.append((name,N.encode_root(document),False))
    add('wrong-component-root',dataclasses.replace(full,name=N.text('wrong')))
    add('component-wrong-type',dataclasses.replace(full,value=H.integer(1)))
    for i,(name,value) in enumerate(full.value.payload):
        key=''.join(map(chr,name))
        add(key+'-missing',dataclasses.replace(full,value=N.Value(10,full.value.payload[:i]+full.value.payload[i+1:])))
        add(key+'-duplicate',dataclasses.replace(full,value=N.Value(10,full.value.payload[:i+1]+((name,value),)+full.value.payload[i+1:])))
        add(key+'-wrong-type',H.changed(full,(key,),H.integer(0)))
    add('component-reordered',dataclasses.replace(full,value=N.Value(10,tuple(reversed(full.value.payload)))))
    add('component-extra',dataclasses.replace(full,value=N.Value(10,full.value.payload+((N.text('unexpected'),H.integer(0)),))))
    add('clocks-int-array',H.changed(full,('clock_inputs',),H.array(1,2)))
    add('clocks-long-list',H.changed(full,('clock_inputs',),N.Value(9,(4,(N.Value(4,1),)))))
    add('empty-entity-payload',root(b''))
    wrapped=envelope()
    for i,(name,value) in enumerate(wrapped.value.payload):
        key=''.join(map(chr,name))
        for label,new in [('missing',N.Value(10,wrapped.value.payload[:i]+wrapped.value.payload[i+1:])),
                          ('duplicate',N.Value(10,wrapped.value.payload[:i+1]+((name,value),)+wrapped.value.payload[i+1:]))]:
            add('envelope-'+key+'-'+label,root(N.encode_root(dataclasses.replace(wrapped,value=new))))
        add('envelope-'+key+'-type',root(N.encode_root(H.changed(wrapped,(key,),H.integer(0)))))
    for version in (0,2,0xffffffff):
        add('envelope-format-'+str(version),root(N.encode_root(H.changed(wrapped,('format',),H.integer(version)))))
    add('envelope-root-name',root(N.encode_root(dataclasses.replace(wrapped,name=N.text('wrong')))))
    add('envelope-reordered',root(N.encode_root(dataclasses.replace(wrapped,value=N.Value(10,tuple(reversed(wrapped.value.payload)))))))
    add('envelope-extra',root(N.encode_root(dataclasses.replace(wrapped,value=N.Value(10,wrapped.value.payload+((N.text('unexpected'),H.integer(0)),))))))
    add('membership-two-values',root(N.encode_root(H.changed(wrapped,('membership',),N.Value(9,(7,(N.Value(7,b''),N.Value(7,b''))))))))
    add('membership-empty-present',root(N.encode_root(envelope(membership=b''))))
    unknown_manager=N.encode_root(N.RootTag(N.text('wrong'),H.compound()))
    add('membership-unknown-present',root(N.encode_root(envelope(membership=unknown_manager))))
    for kind in (0,3,10):
        add('membership-empty-element-'+str(kind),root(N.encode_root(H.changed(wrapped,('membership',),N.Value(9,(kind,()))))))
    add('nested-q-empty',root(N.encode_root(H.changed(wrapped,('recovery',),N.Value(7,b'')))))
    add('nested-q-trailing',root(N.encode_root(H.changed(wrapped,('recovery',),N.Value(7,N.encode_root(Q.root())+b'\0')))))
    add('nested-q-unknown-field',root(N.encode_root(envelope(H.changed(Q.root(),('sound',),H.integer(0))))))
    raw=N.encode_root(wrapped)
    add('envelope-truncated',root(raw[:-1]));add('envelope-trailing',root(raw+b'\0'))
    raw=N.encode_root(full)
    rows += [('component-truncated',raw[:-1],False),('component-trailing',raw+b'\0',False)]
    H.require(len({r[0] for r in rows})==len(rows),'Duplicate fixture labels')
    return rows

def source_pins():
    rows=H.source_pins(); own=H.pin(Path(__file__))
    return rows+[dict(own,lookup=own['path'],kind='verification-tool'),
                 dict(H.pin(Path(Q.__file__)),kind='fixture-constructor'),
                 dict(H.pin(Path(Manager.__file__)),kind='fixture-constructor')]

def fresh():
    (WORK/'checks').mkdir(parents=True,exist_ok=True);number=1
    while (path:=WORK/'checks'/f'{number:03}').exists():number+=1
    path.mkdir();return number,path

def build_child(path):
    with H.forbid_retries():report=H.Build.ensure_native(ENTRY,path/'native',bend=H.BEND,cache_dir=WORK/'native-cache')
    H.require(report['retries']==0,'Builder retried');H.write(path/'build.json',report)

def prepare():
    cases=corpus();expected=N.encode_root(root())
    H.require(N.parse(expected)==root(),'Independent fixture tree differs after physical roundtrip')
    report={'status':'PREPARED','cases':len(cases),'accepted':sum(r[2] for r in cases),'golden_bytes':len(expected),
            'golden_sha256':hashlib.sha256(expected).hexdigest(),'scope':'File-only physical fixtures; no Bend/native or CS integration claim.'}
    WORK.mkdir(parents=True,exist_ok=True);(WORK/'prepared.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report))

def main(ordinary_only=False):
    number,path=fresh();before=source_pins();H.write(path/'sources.json',before);processes=[]
    try:
        def run(argv,label,cap):
            result=H.bounded(path,argv,label,cap);processes.append(result);H.process_ok(result);return result
        checked=run([H.BEND,ENTRY,'--check-only'],'ordinary',60)
        H.require('ALL PROOFS CHECK' in Path(checked['stdout']['path']).read_text() and not Path(checked['stderr']['path']).read_bytes(),'Source check failed')
        report={'status':'SOURCE_PASS','processes':processes,'source_manifest':H.pin(path/'sources.json')}
        if not ordinary_only:
            run([sys.executable,Path(__file__),'--build-child',path],'native-build',600);binary=H.pin(path/'native')
            actual=run([path/'native','--gpu','off','--threads','1','cases'],'actual-native',60)
            lines=Path(actual['stdout']['path']).read_text().splitlines()
            H.require(lines[:-1]==['ok '+g for g in GUARDS] and lines[-1].startswith('bytes ') and not Path(actual['stderr']['path']).read_bytes(),'Actual guards differ')
            wire=H.parse_bytes(lines[-1][6:]);expected=N.encode_root(root())
            (path/'actual.nbt').write_bytes(wire);(path/'expected.nbt').write_bytes(expected)
            H.require(wire==expected and N.parse(wire)==root(),'Full component bytes differ')
            cases=[]
            for name,wire,accepted in corpus():
                fixture=path/(name+'.nbt');fixture.write_bytes(wire);cases.append({'name':name,'input':H.pin(fixture),'accepted':accepted})
            result=run([path/'native','--gpu','off','--threads','1','decode',*[c['input']['path'] for c in cases]],'physical-corpus-native',60)
            lines=Path(result['stdout']['path']).read_text().splitlines()
            H.require(len(lines)==len(cases) and not Path(result['stderr']['path']).read_bytes(),'Corpus output count differs')
            for case,line in zip(cases,lines):
                prefix='accepted '+case['input']['path']+' '
                H.require(line.startswith(prefix) and H.parse_bytes(line[len(prefix):])==Path(case['input']['path']).read_bytes() if case['accepted'] else line=='refused '+case['input']['path'],'Wrong fixture disposition: '+case['name'])
            H.require(binary==H.pin(path/'native'),'Binary drift')
            report.update(status='PASS',guards=list(GUARDS),cases=cases,accepted=sum(c['accepted'] for c in cases),binary=binary,
                          actual_wire=H.pin(path/'actual.nbt'),expected_wire=H.pin(path/'expected.nbt'),build=H.pin(path/'build.json'),
                          scope='Actual single Q recovery image, separate remaining constructor clocks and manager availability envelope. No M.State restore, cached visibility authority, format5 CS/save/coldrestart consumer claim.')
        H.require(before==source_pins(),'Source drift');H.write(path/'result.json',report)
        H.write(ROOT/f'evidence/local-player-cooking-tick-storage-{number:03}.json',report)
        print(json.dumps({'status':report['status'],'cases':len(report.get('cases',[])),'directory':str(path)}))
    except BaseException as error:
        report={'status':'FAIL','error':repr(error),'processes':processes,'source_manifest':H.pin(path/'sources.json')}
        H.write(path/'failure.json',report);H.write(ROOT/f'evidence/local-player-cooking-tick-storage-{number:03}-failure.json',report);raise

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);g=parser.add_mutually_exclusive_group()
    g.add_argument('--prepare',action='store_true');g.add_argument('--ordinary',action='store_true');g.add_argument('--native',action='store_true')
    parser.add_argument('--build-child',type=Path,help=argparse.SUPPRESS);args=parser.parse_args()
    if args.build_child:build_child(args.build_child)
    elif args.prepare:prepare()
    else:main(args.ordinary)
