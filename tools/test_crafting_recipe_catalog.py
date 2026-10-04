#!/usr/bin/env python3
"""Focused failures through the already-built production Bend catalog decoder."""
from __future__ import annotations
import copy,json,subprocess
from pathlib import Path
from reference_inventory import ROOT,write_json,fingerprint
import reference_crafting_recipe_probe as P
import test_crafting_recipe as T

def main():
    saved=json.loads((ROOT/'build/crafting-recipe-build.json').read_text())
    assert saved['sources']==T.source_identity() and saved['binary_sha256']==fingerprint(T.BINARY)['sha256']
    source={'type':'minecraft:crafting_shaped','key':{'X':'#minecraft:planks'},'pattern':['X'],'result':{'id':'minecraft:stick'}}
    catalog={'items':[{'id':'minecraft:oak_planks','limit':64,'remainder':None},{'id':'minecraft:stick','limit':64,'remainder':None}],
             'tags':[{'id':'minecraft:planks','items':['minecraft:oak_planks']}],
             'recipes':[{'id':'bendcraft:test','source':source}]}
    cases=[]
    def add(label,mutation,error):
        value=copy.deepcopy(catalog);mutation(value);cases.append((label,value,error))
    add('duplicate_item',lambda v:v['items'].append(copy.deepcopy(v['items'][0])),'duplicate crafting catalog item')
    add('zero_item_limit',lambda v:v['items'][0].update(limit=0),'invalid crafting catalog item definition')
    add('large_item_limit',lambda v:v['items'][0].update(limit=100),'invalid crafting catalog item definition')
    add('unknown_remainder',lambda v:v['items'][0].update(remainder={'id':'minecraft:missing','count':1}),'unknown or invalid remainder')
    add('overfull_remainder',lambda v:v['items'][0].update(remainder={'id':'minecraft:stick','count':65}),'unknown or invalid remainder')
    add('duplicate_tag',lambda v:v['tags'].append(copy.deepcopy(v['tags'][0])),'duplicate crafting catalog tag')
    add('unknown_tag_member',lambda v:v['tags'][0]['items'].append('minecraft:missing'),'tag contains an unknown item')
    add('duplicate_recipe',lambda v:v['recipes'].append(copy.deepcopy(v['recipes'][0])),'duplicate crafting catalog recipe')
    add('unknown_ingredient_tag',lambda v:v['recipes'][0]['source']['key'].update(X='#minecraft:missing'),'unknown item/tag')
    add('unknown_ingredient_item',lambda v:v['recipes'][0]['source']['key'].update(X='minecraft:missing'),'unknown item/tag')
    add('unknown_output_item',lambda v:v['recipes'][0]['source']['result'].update(id='minecraft:missing'),'unknown item/tag')
    records=[]
    for label,value,error in cases:
        request={'catalog':value,'queries':[],'decoder_queries':[]};path=P.CACHE/'catalog-failure-input.json';write_json(path,request)
        result=subprocess.run([str(T.BINARY),'--threads','1','--gpu','off',str(path)],capture_output=True,text=True,timeout=10)
        assert result.returncode==2 and error in result.stderr,(label,result.returncode,result.stdout,result.stderr)
        records.append({'id':label,'status':result.returncode,'error':result.stderr.strip()})
    evidence={'schema_version':1,'pin':'26.3','status':'passed','cases':records,'source_identity':T.source_identity(),'binary':fingerprint(T.BINARY),'tool':fingerprint(Path(__file__)),
              'boundary':'Actual Bend catalog decoder admission failures. These independently specified malformed interchange cases are not Java JSON error-text parity.'}
    write_json(ROOT/'evidence/crafting-recipe-catalog-admission.json',evidence)
    print(json.dumps({'status':'passed','catalog_admission_cases':len(records)}))

if __name__=='__main__':main()
