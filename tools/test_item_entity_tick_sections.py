#!/usr/bin/env python3
"""Close changed section-key dispatch and complete Scene refusal, narrowly."""
import copy,json,shutil
import test_campfire_authority as T
from test_item_entity_tick import native_record,expanded_observations
ROOT=T.ROOT;WORK=ROOT/'build/item-entity-tick-sections-native';T.WORK=WORK
def main():
    WORK.mkdir(parents=True,exist_ok=True);ref=json.loads((ROOT/'reference/item_entity_tick_sections.json').read_text());assert ref['pin']=='26.3'
    base=json.loads((ROOT/'reference/item_entity_tick.json').read_text());obs=expanded_observations(base)['cases'][0]
    catalog=copy.deepcopy(json.loads((ROOT/'reference/campfire_authority.json').read_text())['inputs']['catalog']);catalog['recipes']=[];catalog['tags']=[]
    catalog['items']=[r for r in catalog['items'] if r['id']=='minecraft:stone'];catalog['campfire_features']=[dict(id='minecraft:stone',enabled=True)];defaults={r['id']:r['components'] for r in catalog['items']}
    before=native_record(obs['before']);before['item']['components']=obs['input_patch']
    (WORK/'input.json').write_text(json.dumps(dict(catalog=catalog,before=before,boundaries=ref['cases']),separators=(',',':'))+'\n')
    checks=[T.run('emit',[T.NODE,'--experimental-transform-types','--stack-size=4096','--max-old-space-size=1536','tools/item_entity_tick_emit.mjs','tests/item_entity_tick_sections.bend',WORK/'receiver.c'],timeout=70)]
    checks.append(T.run('clang',[shutil.which('clang'),'-std=c11','-O0','-fomit-frame-pointer',WORK/'receiver.c','-lpthread','-lm','-o',WORK/'receiver'],timeout=120))
    checks.append(T.run('native',[WORK/'receiver','--gpu','off','--threads','1',WORK/'input.json'],timeout=30,max_rss=1024**3))
    got=json.loads((WORK/'native.stdout').read_text());assert got['boundaries']==[dict(id=r['id'],same=r['same'],less=r['less']) for r in ref['cases']]
    r=got['refusal'];assert r['error']=='item entity-section migration/visibility callback authority unavailable' and r['id']=='migration-refusal'
    assert r['level']==dict(kind='legacy',seed=[11,22]) and r['unique']==[33,44] and r['cursor']==91 and r['order']==9 and r['sound']==dict(kind='legacy',seed=[55,66])
    record=r['records'][0];record['item']=T.decoded_slot(record['item'],defaults);assert record==native_record(obs['before'])
    assert r['runtimes']==[dict(id=71,runtime=obs['runtime_before'])]
    evidence=dict(status='passed',pin='26.3',actual_java_section_cases=len(ref['cases']),native_full_scene_refusal=1,checks=checks,reference_sha256=T.digest(ROOT/'reference/item_entity_tick_sections.json'),source=json.loads((WORK/'receiver.c.sources.json').read_text()),boundary='Actual production same_section and Merge.section_key/Q.less match actual packed SectionPos equality and signed long order at positive/negative/zero boundaries, integer saturation/NaN and packed-key wrapping. Actual False section_ready -> Scene.committed preserves complete entity, runtime, sound/RNG/factory/cursors. This closes changed packed-key projection and refusal; it does not claim actual section callback integration or replay unchanged tick/merge cases.')
    (ROOT/'evidence/item-entity-tick-sections.json').write_text(json.dumps(evidence,indent=2)+'\n');print(json.dumps(dict(status='passed',section_cases=len(ref['cases']),full_scene_refusal=1)))
if __name__=='__main__':main()
