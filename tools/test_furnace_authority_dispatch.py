#!/usr/bin/env python3
"""Focused equivalence checks for the shared ordinary crafting dispatch repair."""
from __future__ import annotations
import json
from pathlib import Path
import test_crafting_recipe_components as C
from reference_inventory import ROOT,fingerprint,write_json

ENTRY=ROOT/'tests/furnace_authority_dispatch.bend'
CACHE=ROOT/'build/furnace-authority-dispatch'
def main():
    CACHE.mkdir(parents=True,exist_ok=True)
    decoder=ROOT/'src/crafting_recipe_decoder.bend'
    before={str(p.relative_to(ROOT)):fingerprint(p) for p in [decoder,ENTRY,Path(__file__)]}
    _,checked=C.run([C.BEND,ENTRY,'--check-only'],60)
    binary=CACHE/'dispatch'
    _,built=C.run([C.BEND,ENTRY,'-o',binary],120)
    runs=[]
    for threads in [1,4]:
        result,receipt=C.run(['/usr/bin/env',f'BEND_THREADS={threads}','BEND_GPU=0',binary],60)
        verdicts=json.loads(result.stdout)
        assert len(verdicts)==80 and all(value is True for value in verdicts),verdicts
        runs.append({'threads':threads,'comparisons':len(verdicts),**receipt})
    after={p:fingerprint(ROOT/p) for p in before}
    assert before==after,'dispatch sources changed during verification'
    write_json(ROOT/'evidence/furnace-authority-dispatch.json',{
        'status':'passed','scope':'Full result/recipe structural equivalence to original branch destinations for 5 payloads and 8 independently labelled kinds, both public entry points. Includes exact failure strings, shaped trim, alternatives/tags, count/component output identity and unsupported subclasses; no unchanged crafting corpus replay.',
        'check':checked,'build':built,'native':runs,'sources':after,'binary':fingerprint(binary)})
    print(json.dumps({'status':'passed','comparisons_per_thread':80}))
if __name__=='__main__':main()
