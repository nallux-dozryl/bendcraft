#!/usr/bin/env python3
"""Focused native rollback/prefix/ID/clock checks; no Java corpus replay."""
import json,shutil
import test_campfire_authority as T
ROOT=T.ROOT;WORK=ROOT/'build/cooking-effect-entities-guards';T.WORK=WORK

def main():
    WORK.mkdir(parents=True,exist_ok=True)
    catalog=json.loads((ROOT/'reference/campfire_authority.json').read_text())['inputs']['catalog']
    (WORK/'catalog.json').write_text(json.dumps(catalog,separators=(',',':')))
    checks=[T.run('emit',[T.NODE,'--experimental-transform-types','--stack-size=4096','--max-old-space-size=1536','tools/cooking_effect_entities_emit.mjs','tests/cooking_effect_entities_guards.bend',WORK/'guards.c'],timeout=120)]
    checks.append(T.run('clang',[shutil.which('clang'),'-std=c11','-O2',WORK/'guards.c','-lpthread','-lm','-o',WORK/'guards'],timeout=180))
    checks.append(T.run('native',[WORK/'guards','--gpu','off','--threads','1',WORK/'catalog.json'],timeout=60,max_rss=1024**3))
    guards=json.loads((WORK/'native.stdout').read_text());assert len(guards)==10 and all(g['ok'] for g in guards),guards
    result={'status':'passed','checks':checks,'guards':guards,'source_manifest':json.loads((WORK/'guards.c.sources.json').read_text()),'native_clock_c_sha256':T.digest(ROOT/'src/cooking_effect_entities_clock.c'),'foreign_boundary':'Native io_tick() full 64-bit monotonic nanoseconds; pure Bend factory, RNG and fragmentation. Clock.now and Clock.apply execute actual native FFI. No proof claim for FFI.'}
    (ROOT/'evidence/cooking-effect-entities-guards.json').write_text(json.dumps(result,indent=2)+'\n');print('ten native rollback/prefix/ID/clock guards passed')
if __name__=='__main__':main()
