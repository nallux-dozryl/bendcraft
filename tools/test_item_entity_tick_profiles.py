#!/usr/bin/env python3
"""Exercise actual initialized physical profile admission, not a world tick."""
import json,shutil
import test_campfire_authority as T
ROOT=T.ROOT;WORK=ROOT/'build/item-entity-tick-profiles';T.WORK=WORK

def main():
    WORK.mkdir(parents=True,exist_ok=True)
    checks=[T.run('emit',[T.NODE,'--experimental-transform-types','--stack-size=4096','--max-old-space-size=1536','tools/item_entity_tick_emit.mjs','tests/item_entity_tick_profiles.bend',WORK/'receiver.c'],timeout=70)]
    checks.append(T.run('clang',[shutil.which('clang'),'-std=c11','-O0','-fomit-frame-pointer',WORK/'receiver.c','-lpthread','-lm','-o',WORK/'receiver'],timeout=90))
    checks.append(T.run('native',[WORK/'receiver','--gpu','off','--threads','1',ROOT/'reference/item_entity_tick_profiles.json'],timeout=40))
    assert (WORK/'native.stdout').read_text().strip()=='307:1'
    evidence=dict(status='passed',profiles=307,actual_physical_file_admitted=True,one_byte_append_refused=True,reference_sha256=T.digest(ROOT/'reference/item_entity_tick_profiles.json'),checks=checks,source=json.loads((WORK/'receiver.c.sources.json').read_text()),boundary='Actual P.load checks entire UTF-8 physical metadata file before parsing. Actual initialized Java physical profile rows are admitted; appending one newline is refused. This does not establish additional block callback or arbitrary wet-state admission.')
    (ROOT/'evidence/item-entity-tick-profiles.json').write_text(json.dumps(evidence,indent=2)+'\n')
    print(json.dumps(dict(status='passed',profiles=307)))
if __name__=='__main__':main()
