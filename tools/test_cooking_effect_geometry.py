#!/usr/bin/env python3
"""Narrow actual-Java versus production Bend geometry boundaries."""
import copy,json,shutil
from pathlib import Path
import test_campfire_authority as T
ROOT=T.ROOT;WORK=ROOT/'build/cooking-effect-geometry-native';T.WORK=WORK

def bits(s):v=int(s,16);return [v>>32,v&0xffffffff]
def vector(a):return [bits(v) for v in a] if a is not None else None
def shape(v):
    v=copy.deepcopy(v)
    for a in v['axes']:a['coords']=vector(a['coords'])
    return v

def main():
    WORK.mkdir(parents=True,exist_ok=True);ref=json.loads((ROOT/'reference/cooking_effect_geometry.json').read_text());assert ref['pin']=='26.3'
    cases=[];expected=[];names=[]
    for source,observed in zip(ref['inputs'],ref['observations']['cases']):
        assert source['id']==observed['id']
        if not source.get('admitted',True):continue
        p=[__import__('struct').unpack('>d',bytes.fromhex(v))[0] for v in source['point']]
        coverage=vector([__import__('struct').pack('>d',v).hex() for v in [p[0]-3,p[1]-3,p[2]-3,p[0]+3,p[1]+3,p[2]+3]])
        blocks=[{'full':o['full'],'box':vector(o['box']),'shape':shape(o['shape'])} for o in observed['obstacles']]
        cases.append({'point':vector(source['point']),'coverage':coverage,'blocks':blocks,'entities':[vector(b) for b in source['entities']]})
        expected.append({'clear':observed['clear'],'free':vector(observed.get('free')),'position':vector(observed['position']),'body':vector(observed['body']),'outer':vector(observed['outer']),**{key:[vector(b) for b in observed[key]['boxes']] for key in ['search','union','available']}});names.append(source['id'])
    (WORK/'input.json').write_text(json.dumps(cases,separators=(',',':'))+'\n');(WORK/'expected.json').write_text(json.dumps(expected,indent=2)+'\n')
    pins={str(p.relative_to(ROOT)):T.digest(p) for pattern in ['src/cooking_effect_geometry*.bend','tests/cooking_effect_geometry*.bend','tools/*cooking_effect_geometry*'] for p in ROOT.glob(pattern)}
    pins['reference/cooking_effect_geometry.json']=T.digest(ROOT/'reference/cooking_effect_geometry.json')
    checks=[]
    checks.append(T.run('emit',[T.NODE,'--experimental-transform-types','--stack-size=4096','--max-old-space-size=1536','tools/cooking_effect_geometry_emit.mjs','tests/cooking_effect_geometry.bend',WORK/'receiver.c'],timeout=120,max_rss=2*1024**3))
    checks.append(T.run('clang',[shutil.which('clang'),'-std=c11','-O2',WORK/'receiver.c','-lpthread','-lm','-o',WORK/'receiver'],timeout=180,max_rss=2*1024**3))
    checks.append(T.run('native',['/usr/bin/time','-l',WORK/'receiver','--gpu','off','--threads','1',WORK/'input.json'],timeout=60,max_rss=1024**3))
    actual=json.loads((WORK/'native.stdout').read_text());(WORK/'actual.json').write_text(json.dumps(actual,indent=2)+'\n')
    for name,a,b in zip(names,actual,expected):assert a==b,{'id':name,'actual':a,'expected':b}
    assert len(actual)==len(expected)
    assert all(T.digest(ROOT/p)==h for p,h in pins.items()),'source changed during native checks'
    evidence={'status':'passed','command':'python3 tools/test_cooking_effect_geometry.py','checks':checks,'source_sha256':pins,'actual_java_cases':len(names),'names':names,'bitwise_observations':['body','outer','clear','free','position','ordered-search-boxes','ordered-union-boxes','ordered-available-boxes'],'scope':'Actual production pure placement provider; actual initialized block collision shapes and coordinate grids from pinned Java. Core capture wrapper/source+ownership laws checked separately. Border-outside reference case explains refused admission and is not claimed as supported native placement.'}
    (ROOT/'evidence/cooking-effect-geometry-native.json').write_text(json.dumps(evidence,indent=2)+'\n');print(json.dumps({'status':'passed','cases':len(names)}))
if __name__=='__main__':main()
