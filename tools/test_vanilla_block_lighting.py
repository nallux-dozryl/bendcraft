#!/usr/bin/env python3
"""Compare production Bend lighting to actual installed Java QuadInstance."""
import copy,json,shutil,struct
import test_campfire_authority as T
ROOT=T.ROOT;WORK=ROOT/'build/vanilla-block-lighting-native';T.WORK=WORK

def bits(v):return struct.unpack('>I',struct.pack('>f',v))[0]
def input_case(raw,obs):
    r=copy.deepcopy(raw);r['source']=obs['source'];r['vertices']=[[bits(v) for v in p] for p in r['vertices']];r['cells']=copy.deepcopy(obs['cells']);r['cardinal']=obs['cardinal'];r['flat']=None if r['flat']==-1 else r['flat'];r['revision']=19
    for cell in r['cells']:cell['position']=[v&0xffffffff for v in cell['position']]
    return r

def main():
    WORK.mkdir(parents=True,exist_ok=True);ref=json.loads((ROOT/'reference/vanilla_block_lighting.json').read_text());assert ref['pin']=='26.3'
    cases=[input_case(r,o) for r,o in zip(ref['inputs'],ref['observations']['cases'])];base=next(c for c in cases if c['id']=='smooth-full-up');guards=[]
    for name in ['stale','missing-state','missing-light','duplicate','missing-cardinal','invalid-brightness','nonfinite','source-mismatch']:
        c=copy.deepcopy(base);c['id']='guard-'+name
        if name=='stale':c['revision']=20
        elif name=='missing-state':c['cells'][0]['info']=None
        elif name=='missing-light':c['cells'][0]['sky']=None
        elif name=='duplicate':c['cells'].append(copy.deepcopy(c['cells'][0]))
        elif name=='missing-cardinal':c['cardinal']=None
        elif name=='invalid-brightness':c['cells'][0]['block']=16
        elif name=='nonfinite':c['vertices'][0][0]=2139095040
        elif name=='source-mismatch':c['source']['emission']=1
        guards.append(c)
    (WORK/'input.json').write_text(json.dumps(cases+guards,separators=(',',':'))+'\n')
    checks=[T.run('emit',[T.NODE,'--experimental-transform-types','--stack-size=4096','--max-old-space-size=1536','tools/item_entity_tick_emit.mjs','tests/vanilla_block_lighting.bend',WORK/'receiver.c'],timeout=60)]
    checks.append(T.run('clang',[shutil.which('clang'),'-std=c11','-O2','-ffp-contract=off',WORK/'receiver.c','-lpthread','-lm','-o',WORK/'receiver'],timeout=80))
    checks.append(T.run('native',[WORK/'receiver','--gpu','off','--threads','1',WORK/'input.json'],timeout=30,max_rss=1024**3))
    got=json.loads((WORK/'native.stdout').read_text());assert len(got)==len(cases)+len(guards)
    for actual,expected,raw in zip(got,ref['observations']['cases'],ref['inputs']):
        assert actual['id']==expected['id'] and actual['vertices']==expected['vertices'],dict(id=expected['id'],actual=actual,expected=expected['vertices'])
        if raw['flat']==-1:assert actual['cubic']==expected['cubic'] and actual['partial']==expected['partial'],(actual,expected)
        stencil=set(map(tuple,actual['stencil']));assert len(stencil)==len(actual['stencil'])<=14
        observed={tuple(v&0xffffffff for v in c['position']) for c in expected['calls']}
        assert observed<=stencil,dict(id=expected['id'],missing=observed-stencil)
    for actual in got[len(cases):]:assert isinstance(actual['vertices'],dict) and 'error' in actual['vertices'],actual
    evidence=dict(status='passed',pin='26.3',actual_java_cases=len(cases),actual_vertex_records=4*len(cases),native_refusals=len(guards),checks=checks,reference_sha256=T.digest(ROOT/'reference/vanilla_block_lighting.json'),source=json.loads((WORK/'receiver.c.sources.json').read_text()),boundary='Actual BlockModelLighter flat/smooth, face shape flags, LightCoordsUtil blends, actual registered state flags and QuadInstance pervertex emission/ARGB compare. Six directions, partial/inset/nonplanar/outside-unit geometry, opaque diagonal fallback, mixed permeability, source/model emission, custom side shade/override and threshold boundaries. Conservative deduplicated stencil contains every actual world query. Missing/stale facts refuse. No liveCore field capture, shared mesh, GPU/world renderer or unchanged corpus replay claimed.')
    (ROOT/'evidence/vanilla-block-lighting-native.json').write_text(json.dumps(evidence,indent=2)+'\n');print(json.dumps(dict(status='passed',cases=len(cases),vertex_records=4*len(cases),refusals=len(guards))))
if __name__=='__main__':main()
