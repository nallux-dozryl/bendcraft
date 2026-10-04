#!/usr/bin/env python3
"""Actual transport command candidate, full-owner rollback and wire admission."""
from __future__ import annotations
import argparse,copy,hashlib,json,subprocess,time
from pathlib import Path
import build_native,item_component_check as C,item_component_wire_check as Gate
from test_player_look import imports
from reference_inventory import ROOT,write_json,fingerprint,canonical

BUILD=ROOT/'build/item_component_wire_transport';EVIDENCE=ROOT/'evidence/item_component_wire_transport.json'
def pin(p):return {'path':str(Path(p).resolve()),**fingerprint(Path(p))}
def line(v):return json.dumps(v,separators=(',',':'),ensure_ascii=True)
def frozen_entry(work,entry=None):
    """Copy the actual imported declarations and native effects unchanged."""
    entry=entry or ROOT/'tests/item_component_wire_transport.bend'
    sources=imports([entry]);pins=dict(sources)
    for relative in sources:
        path=ROOT/relative
        for effect in build_native.foreign_paths(path.read_text()):
            native=(path.parent/effect).resolve()
            if native.is_file():pins[str(native.relative_to(ROOT))]=hashlib.sha256(native.read_bytes()).hexdigest()
    destination=work/'source';assert not destination.exists(),'fresh source snapshot required'
    for relative,expected in pins.items():
        data=(ROOT/relative).read_bytes();assert hashlib.sha256(data).hexdigest()==expected,relative
        path=destination/relative;path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(data)
    assert imports([entry])==sources,'Imported sources changed while freezing'
    assert all(hashlib.sha256((ROOT/relative).read_bytes()).hexdigest()==expected for relative,expected in pins.items()),'Native effects changed while freezing'
    snapshot={'original_source_sha256':pins,'declaration_bytes_unchanged':True,'entry':str(destination/entry.relative_to(ROOT))}
    write_json(work/'source-snapshot.json',snapshot)
    return Path(snapshot['entry']),snapshot
def tree(slots):
    if len(slots)==1:return [Gate.slot(slots[0])]
    mid=len(slots)//2;return [tree(slots[:mid]),tree(slots[mid:])]
def invoke(case,action,sequence=1,epoch='fixture:epoch'):
    case['wire']=line([1,1,epoch,sequence,action]);case['action']=action;case['sequence']=sequence;case['call_epoch']=epoch;return case
def owner(name,context='none',**changes):
    v=Gate.owner(name,context=context,shape='valid',result=None);v.update(changes);return v
def corpus(reference):
    out=[];base=reference['default_components']
    for row in reference['rows'][:17]:
        key=C.identity(row['components'],base)
        for context in ['none','empty']:
            x=owner(row['id']+'/'+context,context,components=key,expect='acquire')
            out.append(invoke(x,[7,2,[C.ITEM,key],1]))
    effective=copy.deepcopy(base);effective[C.EFFECTS]=[{'id':'minecraft:speed'}]*1200
    long=C.identity(effective,base);stack={'id':C.ITEM,'components':long,'count':1}
    assert len(long)<65536
    for context in ['none','empty']:
        x=owner('large-fitting/'+context,context,components=long,expect='acquire');out.append(invoke(x,[7,2,[C.ITEM,long],1]))
        x=owner('two-large-overflow/'+context,context,components=long,index=3,expect='rollback');x['backing'][2]=copy.deepcopy(stack)
        out.append(invoke(x,[7,3,[C.ITEM,long],1]));assert len(x['wire'])<65536
        proposed=copy.deepcopy(x);proposed['backing'][3]=copy.deepcopy(stack);proposed['epoch']='fixture:epoch';proposed['diagnostic']='';proposed['maximum_header']=False
        assert len(line(Gate.reply(proposed)))>65536
        x=owner('already-overbudget/'+context,context,components=long,opened=False,expect='fault');x['backing'][2]=copy.deepcopy(stack);x['backing'][3]=copy.deepcopy(stack)
        out.append(invoke(x,[9]))
        for kind in ['short','unbalanced']:
            expected='constructor-refused' if kind=='unbalanced' else 'fault'
            x=owner('malformed-tree/'+context+'/'+kind,context,shape=kind,components=long,expect=expected);out.append(invoke(x,[9]))
        for mode,length in [('short-logical',47),('long-logical',49)]:
            x=owner(mode+'/'+context,context,length=length,components=long,expect='rollback');out.append(invoke(x,[9]))
    # A real refresh can add a second long profile solely as derived result.
    x=owner('derived-output-overflow','output',components=long,expect='rollback');x['backing'][2]=copy.deepcopy(stack)
    x['backing'][43]={'id':'minecraft:stone','components':'','count':1};out.append(invoke(x,[8]))
    # Malformed existing keys/result must refuse without committing other fields.
    for target in ['main','carried','result']:
        x=owner('malformed-existing/'+target,'none' if target=='result' else 'empty',opened=False,expect='fault')
        bad={'id':C.ITEM,'components':'BendCraftComponents1\t1\t{}','count':1}
        if target=='main':x['backing'][1]=bad
        elif target=='carried':x['backing'][47]=bad
        else:x['result']=bad
        out.append(invoke(x,[9]))
    x=owner('stale-sequence','empty',components=long,expect='stale');x['backing'][2]=copy.deepcopy(stack);out.append(invoke(x,[7,3,[C.ITEM,long],1],2))
    x=owner('wrong-epoch','empty',components=long,expect='stale');out.append(invoke(x,[7,3,[C.ITEM,long],1],1,'other:epoch'))
    # Exercise each named prospective route with ordinary valid state.
    for name,action in [('inspect',[8]),('open',[9]),('close',[10]),('select',[12,2]),('pickup',[11,38,[0,0]]),('swap',[11,38,[2,1]]),('transfer',[6,0,2,3,0])]:
        x=owner('ordinary/'+name,'none',expect=name)
        if name in ['pickup','swap']:x['backing'][2]={'id':'minecraft:stone','components':'','count':5}
        out.append(invoke(x,action))
    return out
def verify(case,row):
    before=row['before'];after=row['after'];expect=case['expect']
    assert row['world_unchanged'] and row['encoding']['accepted'],case['name']
    assert before['inventory']['length']==case['length'] and before['inventory']['catalog_count']==1658
    assert before['lease']==['fixture:epoch',1,41,True] and before['counter']==5
    assert before['nonce']=='fixture:nonce' and before['capability']=='fixture:token'
    if case['shape']=='valid':assert before['inventory']['tree']==tree(case['backing']),case['name']
    elif case['shape']=='short':assert before['inventory']['tree']==[[1,'fixture:raw','\ninvalid',0xffffffff]]
    else:assert before['inventory']['tree']==[[[0]],[[[1,'fixture:raw','\ninvalid',0xffffffff]],[[1,'minecraft:stone','',7]]]]
    assert before['inventory']['selected']==case['selected'] and before['inventory']['abilities']==[case['instabuild'],case['maybuild']]
    assert before['inventory']['status']==[case['invulnerable'],case['mayfly'],case['flying'],case['walking'],case['flying_speed']]
    assert before['inventory']['menu']==[case['opened'],case['revision'],[0] if case['result'] is None else [1,Gate.slot(case['result'])]]
    dto=json.loads(row['encoding']['text']);assert dto==row['reply'];assert row['encoding']['text']==line(dto)
    if expect in ['rollback','fault','stale']:
        assert before['inventory']==after['inventory'],(case['name'],'complete raw I owner')
        assert before['context']==after['context'],(case['name'],'complete recipe catalog/cache/mode')
    if expect=='stale':
        assert before==after and dto[1]==3 and not row['keep'],case['name']
    else:
        assert after['lease']==['fixture:epoch',2,100,True],case['name']
        for key in ['counter','nonce','capability']:assert after[key]==before[key],case['name']
    if expect in ['fault','stale']:
        assert dto[1]==3 and not row['keep'],case['name']
        assert dto[4]==('Wire:InventoryReplyEncoding' if expect=='fault' else 'RendererLeaseOrSequence'),case['name']
    elif expect=='rollback':
        assert dto[1]==6 and dto[4] is False and dto[5]=='inventory:prospective-reply-refused' and row['keep'],case['name']
    else:
        assert dto[1]==6 and dto[4] is True and row['keep'],(case['name'],dto[:6])
        expected=copy.deepcopy(before['inventory']);slots=copy.deepcopy(case['backing'])
        if expect=='acquire':slots[case['action'][1]]={'id':case['id'],'components':case['components'],'count':1}
        elif expect=='select':expected['selected']=2
        elif expect=='close':expected['menu'][0]=False
        elif expect=='pickup':slots[47]=slots[2];slots[2]=None;expected['menu'][1]+=1;expected['menu'][2]=[0]
        elif expect=='swap':slots[2],slots[1]=slots[1],slots[2];expected['menu'][1]+=1;expected['menu'][2]=[0]
        elif expect=='transfer':slots[0]['count']-=3;slots[2]={'id':'minecraft:stone','components':'','count':3}
        expected['tree']=tree(slots)
        assert after['inventory']==expected,(case['name'],'complete admitted I owner')
        if case['context']=='empty':
            ctx=copy.deepcopy(before['context']);ctx[3]=None;assert after['context']==ctx,case['name']
        else:assert after['context']==before['context'],case['name']
    return len(row['encoding']['text'])
def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--build',action='store_true');args=parser.parse_args();BUILD.mkdir(exist_ok=True)
    paths=[ROOT/'src'/x for x in ['player_inventory.bend','resource_client_wire.bend','item_component_wire_candidate.bend','remote_resource_transport.bend','remote_resource_backend.bend','player_crafting_authority.bend','player_crafting_authority_components.bend','player_crafting_session_adapter.bend','player_item_definitions.bend','item_component.bend','crafting_recipe_components.bend','json.bend']]+[ROOT/'tests/item_component_wire_transport.bend',ROOT/'tests/item_component_wire.bend',ROOT/'tests/player_crafting_backend.bend',Path(__file__),C.REFERENCE,Gate.TABLE]
    before=[pin(p) for p in paths];receipt={'status':'running','source_pins':before};write_json(EVIDENCE,receipt)
    try:
        binary=BUILD/'observer'
        if args.build:
            attempt=1
            while (BUILD/f'native-{attempt:03d}').exists():attempt+=1
            work=BUILD/f'native-{attempt:03d}';work.mkdir()
            entry,snapshot=frozen_entry(work);receipt['snapshot']=snapshot;write_json(EVIDENCE,receipt)
            built=build_native.ensure_native(entry,binary,bend=C.BEND);write_json(work/'native-build.json',built)
            receipt['build']={k:built[k] for k in ['path','binary_sha256','cache_key','cache_hit','timings']}
        assert binary.is_file(),'Run --build with one actual compiler slot'
        cases=corpus(json.loads(C.REFERENCE.read_text()));counts={};sizes={};constructor_refusals={}
        for index,case in enumerate(cases):
            path=BUILD/'fixture.json';write_json(path,[{k:v for k,v in case.items() if k not in ['name','expect','action','sequence','call_epoch']}])
            start=time.monotonic();p=subprocess.run([str(binary),'--gpu','off','--threads','1','--',str(Gate.TABLE),str(path)],cwd=ROOT,capture_output=True,text=True,timeout=180)
            if case['expect']=='constructor-refused':
                assert p.returncode==1 and p.stderr=='bend: runtime fail-stop\n' and not p.stdout,(case['name'],p.returncode,p.stdout,p.stderr)
                constructor_refusals[case['name']]={'returncode':p.returncode,'stderr':p.stderr,'scope':'Unequal physical Array child classes are refused by native blk_node before a Transport owner/reply can be observed.'}
                counts[case['expect']]=counts.get(case['expect'],0)+1
                receipt.update(checked=index+1,counts=counts,constructor_refusals=constructor_refusals);write_json(EVIDENCE,receipt)
                continue
            assert p.returncode==0,(case['name'],p.returncode,p.stderr)
            rows=[json.loads(s) for s in p.stdout.splitlines()];assert len(rows)==1,case['name']
            sizes[case['name']]=verify(case,rows[0]);counts[case['expect']]=counts.get(case['expect'],0)+1
            receipt.update(checked=index+1,counts=counts);write_json(EVIDENCE,receipt)
        # Same current native graph exercises all existing default wire/frame laws.
        gate=subprocess.run(['python3',str(ROOT/'tools/item_component_wire_check.py'),'--binary',str(binary)],cwd=ROOT,capture_output=True,text=True,timeout=600)
        assert gate.returncode==0,{'stdout':gate.stdout,'stderr':gate.stderr};receipt['wire_gate']=json.loads(gate.stdout.strip().splitlines()[-1])
        assert before==[pin(p) for p in paths],'Source changed during actual prospective transport replay'
        receipt.update(status='passed',cases=len(cases),transport_cases=len(cases)-len(constructor_refusals),constructor_refusals=constructor_refusals,counts=counts,reply_bytes=sizes,native_binary=pin(binary),
            semantics='Actual T.command_prepared -> actual command once -> complete Base.Array.clone I candidate -> actual encoder before actor publish. Overflow restores all I cells/tree/fields and recipe context, consumes one valid lease, checks exact refusal; representable malformed original snapshots yield compact Fault. Complete raw Core unchanged each completed command case. Two unequal-child Array constructors fail before Transport; they are not fallback observations.',
            limits={'transport_bytes':65536,'parser_scalars':65536,'parser_depth':8,'AST_values':16384,'per_key_wire_cap':None},
            unverified=['socket write failure/disconnect native boundary','physical OS client acceptance','world durable publication/recovery','full semantic effect-consumption gameplay'],
            reproduce='python3 tools/item_component_wire_transport_check.py --build')
        write_json(EVIDENCE,receipt);print(line({'status':'passed','cases':len(cases),'counts':counts,'gate_cases':receipt['wire_gate']['cases']}))
    except BaseException as error:
        receipt.update(status='failed',error=repr(error));write_json(EVIDENCE,receipt);write_json(EVIDENCE.with_name('item_component_wire_transport_failure_'+str(time.time_ns())+'.json'),receipt);raise
if __name__=='__main__':main()
