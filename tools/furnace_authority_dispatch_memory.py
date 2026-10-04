#!/usr/bin/env python3
"""One controlled, source-only comparison of the two repaired declarations."""
from __future__ import annotations
import json,subprocess
from pathlib import Path
import test_crafting_recipe_components as C
from reference_inventory import ROOT,fingerprint,write_json

BASELINE='bd1e3dfa00a2722499767ff76876054e51c604a2'
FILES=['crafting_recipe_decoder.bend','crafting_recipe.bend','crafting_recipe_components.bend','crafting_recipe_component_registry.bend','inventory.bend','json.bend','u32_decimal.bend']
def main():
    folder=ROOT/'build/furnace-authority-dispatch/memory';folder.mkdir(parents=True,exist_ok=True)
    pins={name:fingerprint(ROOT/'src'/name) for name in FILES};runs={}
    for label in ['before','after']:
        source=folder/label/'src';source.mkdir(parents=True,exist_ok=True)
        for name in FILES:
            body=(ROOT/'src'/name).read_bytes()
            if label=='before' and name=='crafting_recipe_decoder.bend':
                body=subprocess.check_output(['git','show',BASELINE+':src/'+name],cwd=ROOT)
            (source/name).write_bytes(body)
        script=folder/(label+'.mjs')
        script.write_text('''import * as B from "file:///Users/chuah/Documents/ChatGPT/bendex/bend/bend2/bend.ts";
const b=B.book_nil(),seen=new Map(),start=Date.now(),points=[];
await B.book_load(b,ENTRY,"",seen);
let pass=0;b.order=new Proxy(b.order,{get(a,k){if(k==='0')pass++;if(pass===2&&/^\\d+$/.test(String(k)))points.push({name:a[k],rss:process.memoryUsage().rss,ms:Date.now()-start});return Reflect.get(a,k);}});
B.book_valid(b);if(b.hols!==0)throw Error("open holes");
console.log(JSON.stringify({points,max_rss_kib:process.resourceUsage().maxRSS,ms:Date.now()-start}));
'''.replace('ENTRY',json.dumps(str(source/'crafting_recipe_decoder.bend'))))
        result,receipt=C.run([C.NODE,'--experimental-transform-types','--stack-size=4096','--max-old-space-size=1536',script],30)
        measured=json.loads(result.stdout);write_json(folder/(label+'.json'),measured)
        selected={}
        for name in ['ordinary_output','decode_kind']:
            index=next(i for i,p in enumerate(measured['points']) if p['name']==name or p['name'].endswith(':'+name))
            a,b=measured['points'][index:index+2]
            selected[name]={'before_rss_bytes':a['rss'],'after_rss_bytes':b['rss'],'rss_delta_bytes':b['rss']-a['rss'],'check_ms':b['ms']-a['ms']}
        receipt.pop('stdout');runs[label]={'receipt':receipt,'declarations':selected,'max_rss_kib':measured['max_rss_kib'],'total_ms':measured['ms'],'decoder':fingerprint(source/'crafting_recipe_decoder.bend')}
    assert pins=={name:fingerprint(ROOT/'src'/name) for name in FILES}
    path=ROOT/'evidence/furnace-authority-dispatch.json';evidence=json.loads(path.read_text())
    evidence['source_memory']={'baseline_decoder_commit':BASELINE,'runs':runs,'unchanged_dependency_sources':pins,'tool':fingerprint(Path(__file__)),'scope':'Both runs load the same seven-file source-only graph; only the decoder dispatch differs. RSS deltas are observed allocation/residency, not proof of an asymptotic rate or a named internal hot function.'}
    write_json(path,evidence);print(json.dumps({k:v['declarations'] for k,v in runs.items()}))
if __name__=='__main__':main()
