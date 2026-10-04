#!/usr/bin/env python3
"""Targeted native comparison of production patched crafting to actual Java."""
from __future__ import annotations
import argparse,copy,json,re,subprocess,time
from pathlib import Path
import reference_crafting_recipe_components_probe as P
from reference_inventory import ROOT,canonical,fingerprint,write_json

BEND=Path('/Users/chuah/.bend/bin/bend')
BINARY=ROOT/'build/crafting-recipe-component-tests'
EVIDENCE=ROOT/'evidence/crafting-recipe-components.json'
SOURCES=['src/crafting_recipe.bend','src/crafting_recipe_decoder.bend','src/crafting_recipe_components.bend','src/crafting_recipe_component_registry.bend','src/crafting_recipe_components_laws.bend','src/crafting_recipe_components_proof.bend','tests/crafting_recipe_components.bend','tests/crafting_recipe.bend','src/inventory.bend','src/json.bend']
NODE=Path('/opt/homebrew/Cellar/node/23.5.0/bin/node')
KERNEL=Path('/Users/chuah/.bend/bendtt/e15042434e73aab0/bendtt')

def identity():return {p:fingerprint(ROOT/p)['sha256'] for p in SOURCES}

def run(command,timeout=120):
    start=time.monotonic();result=subprocess.run(list(map(str,command)),capture_output=True,text=True,timeout=timeout,cwd=ROOT)
    receipt={'command':list(map(str,command)),'seconds':round(time.monotonic()-start,6),'status':result.returncode,'stdout':result.stdout[-6000:],'stderr':result.stderr[-6000:]}
    if result.returncode:raise AssertionError(receipt)
    return result,receipt

def check_proof():
    folder=P.CACHE/'proof';folder.mkdir(parents=True,exist_ok=True)
    laws=re.findall(r'^law (\w+):',(ROOT/'src/crafting_recipe_components_laws.bend').read_text(),re.M)
    roots=['crafting_recipe_components_laws:'+law for law in laws]
    ordinary_only=['crafting_recipe_components_laws:non_stew_identity_cannot_use_closed_stew_authority']
    selected=[root for root in roots if root not in ordinary_only]
    # Existing checked-root workflow: all source is checked before selecting
    # export roots; declaration maps, original checked types/bodies stay intact.
    script='''import * as B from "file:///Users/chuah/Documents/ChatGPT/bendex/bend/bend2/bend.ts";
import * as Safe from "file:///Users/chuah/Documents/ChatGPT/bendex/bend/bend2/safe.ts";
import * as fs from "node:fs";import * as crypto from "node:crypto";
const entry=ENTRY,dir=DIR,roots=ROOTS,ordinaryOnly=ORDINARY_ONLY;
const sha=x=>crypto.createHash("sha256").update(x).digest("hex");
const book=B.book_nil(),seen=new Map();await B.book_load(book,entry,"",seen);
const before=Object.fromEntries([...seen.keys()].sort().map(p=>[p,sha(fs.readFileSync(p))]));
B.book_valid(book);if(book.hols!==0)throw Error("Open proof holes");
console.log("ALL ORDINARY SOURCE CHECKS PASS");
const order=[...book.order],tlds=book.tlds,ctrs=book.ctrs,tmps=book.tmps;
const originals=Object.entries(tlds).map(([k,t])=>[k,t,t.T,t.$==="Def"?t.v:null,t.$==="Def"?t.e:null]);
const termPins=roots.map(k=>{const t=tlds[k];if(t?.$!=="Def"||!t.e||!t.v||t.u||t.i)throw Error("Missing checked pure proof "+k);return {name:k,type_sha256:sha(B.term_key(B.term_lower(t.T))),checked_proof_sha256:sha(B.term_key(t.e)),source_body_sha256:sha(B.term_key(B.term_lower(t.v)))};});
book.order=order.filter((k,i)=>roots.includes(k)&&order.lastIndexOf(k)===i);
if(book.order.length!==roots.length||book.tlds!==tlds||book.ctrs!==ctrs||book.tmps!==tmps)throw Error("Selection changed declaration ownership");
for(const [k,t,T,v,e] of originals)if(book.tlds[k]!==t||t.T!==T||(t.$==="Def"&&(t.v!==v||t.e!==e)))throw Error("Selection altered term "+k);
const exclusions=Safe.safe_emit(book,dir+"/selected.bendtt");
const after=Object.fromEntries([...seen.keys()].sort().map(p=>[p,sha(fs.readFileSync(p))]));
if(JSON.stringify(before)!==JSON.stringify(after))throw Error("Proof sources changed");
fs.writeFileSync(dir+"/selection.json",JSON.stringify({roots,termPins,exclusions,ordinary_only_roots:ordinaryOnly,ordinary_only_reason:"Full stew validator reaches the existing Nat.show.fin/go mutual-recursion exporter limitation; all source laws are ordinarily checked before export selection.",checked_types_and_bodies_unchanged:true,all_original_declaration_maps_retained:true,source_pins:after},null,2)+"\\n");
if(exclusions.length)throw Error("Export exclusions "+JSON.stringify(exclusions));
console.log("CHECKED ROOT EXPORT PASS");
'''.replace('ENTRY',json.dumps(str(ROOT/'src/crafting_recipe_components_proof.bend'))).replace('DIR',json.dumps(str(folder))).replace('ROOTS',json.dumps(selected)).replace('ORDINARY_ONLY',json.dumps(ordinary_only))
    path=folder/'export.mjs';path.write_text(script)
    _,exported=run([NODE,'--experimental-transform-types','--max-old-space-size=2048','--stack-size=4096',path],120)
    result,checked=run(['/usr/bin/env','LEAN_STACK_SIZE=4194304',KERNEL,folder/'selected.bendtt'],60)
    assert result.stdout.strip()=='ALL PROOFS CHECK',result.stdout
    return {'export':exported,'kernel':checked,'selection':json.loads((folder/'selection.json').read_text()),'artifact':fingerprint(folder/'selected.bendtt'),'compiler_api':[fingerprint(ROOT.parent/'bend/bend2'/p) for p in ['bend.ts','safe.ts']],'kernel_binary':fingerprint(KERNEL),'node':fingerprint(NODE)}

def reference():
    data=json.loads(P.OUTPUT.read_text());rows=P.inputs()
    assert data['pin']=='26.3'
    assert data['source_sha256']==P.P.sha(P.SOURCE.encode())
    assert data['inputs_sha256']==P.P.sha(canonical(rows))
    # The registry dispatch is pinned data, never a finite recipe table.
    registry=(ROOT/'src/crafting_recipe_component_registry.bend').read_text()
    component,effects=registry.split('def effect(')
    assert re.findall(r'"(minecraft:[^"]+)"',component)==data['component_types']
    assert re.findall(r'"(minecraft:[^"]+)"',effects.split('def persistent(')[0])==data['effects']
    return data,rows

def request(data,rows):
    outcomes={r['id']:r for r in data['cases']}
    unsupported={'bendcraft:duration_fractional'}
    selected=[r for r in rows if outcomes[r['id']]['accepted'] and r['id'] not in unsupported]
    selected_ids={r['id'] for r in selected}
    source=json.loads((P.CACHE/'catalog.json').read_text())
    wanted=set();tag_names=set()
    for r in selected:
        wanted.add(r['source']['result']['id'])
        for ingredient in r['source']['ingredients']:
            if isinstance(ingredient,list):wanted.update(ingredient)
            elif ingredient.startswith('#'):tag_names.add(ingredient[1:])
            else:wanted.add(ingredient)
    tags=[t for t in source['tags'] if t['id'] in tag_names]
    for t in tags:wanted.update(t['items'])
    item_map={i['id']:i for i in source['items']}
    while True:
        extra={item_map[i]['remainder']['id'] for i in wanted if item_map[i]['remainder'] is not None}-wanted
        if not extra:break
        wanted.update(extra)
    catalog={'items':[i for i in source['items'] if i['id'] in wanted],'tags':tags,'recipes':selected}
    pairs=[r for r in data['comparisons'] if r['a'] in selected_ids and r['b'] in selected_ids]
    defaults=next(d['components'] for d in data['defaults'] if d['id']=='minecraft:suspicious_stew')
    envelope=lambda value:'BendCraftComponents1\t1\t'+canonical(value).decode()
    forged=copy.deepcopy(defaults);forged['minecraft:suspicious_stew_effects']=[{'id':'minecraft:speed','duration':20}];forged['minecraft:rarity']='epic'
    missing=copy.deepcopy(defaults);missing.pop('minecraft:suspicious_stew_effects')
    profiles=[]
    def profile(label,components,item='minecraft:suspicious_stew'):
        profiles.append({'id':label,'key':{'id':item,'count':1,'components':components}})
    profile('noncanonical_explicit_defaults',envelope(defaults))
    profile('changed_other_default',envelope(forged));profile('removed_effects',envelope(missing))
    profile('malformed_json','BendCraftComponents1\t1\t{')
    profile('raw_patch','BendCraftPatch1\t{}');profile('strict_invalid','BendCraftInvalidComponents1\t{}')
    profile('wrong_effective_limit','BendCraftComponents1\t2\t'+canonical(defaults).decode())
    profile('non_stew_key','',item='minecraft:stone')
    return {'catalog':catalog,'cases':selected,'comparisons':pairs,'decoder_cases':rows,'stew_defaults':defaults,'profile_cases':profiles},unsupported

def check_native(data,req,unsupported,threads):
    path=P.CACHE/'native-input.json';write_json(path,req)
    result,receipt=run([BINARY,'--threads',threads,'--gpu','off',path],90)
    actual=json.loads(result.stdout);observed={r['id']:r for r in data['cases']};defaults={r['id']:r['components'] for r in data['defaults']}
    outputs={r['id']:r for r in actual['outputs']}
    assert set(outputs)=={r['id'] for r in req['cases']}
    nondefault=0;strict_empty=0
    for id,row in outputs.items():
        java=observed[id];assert java['matches'],id
        expected=java['output'];slot=row['output']
        if expected['empty']:
            assert slot is None and row['limit'] is None and row['stew_profile_limit'] is None,(id,row,expected);strict_empty+=1;continue
        assert slot['id']==expected['id'] and slot['count']==expected['count'] and row['limit']==expected['limit'],(id,row,expected)
        components=slot['components']
        profile_expected=None
        if slot['id']=='minecraft:suspicious_stew' and 'minecraft:suspicious_stew_effects' in expected['components']:
            other={k:v for k,v in expected['components'].items() if k!='minecraft:suspicious_stew_effects'}
            base={k:v for k,v in defaults[slot['id']].items() if k!='minecraft:suspicious_stew_effects'}
            if other==base:profile_expected=1
        assert row['stew_profile_limit']==profile_expected,(id,row,profile_expected)
        if not components:
            assert defaults[slot['id']]==expected['components'],(id,'default identity lost modification')
        else:
            marker,limit,payload=components.split('\t')
            assert marker=='BendCraftComponents1' and int(limit)==expected['limit']
            assert json.loads(payload)==expected['components'],(id,json.loads(payload),expected['components'])
            assert defaults[slot['id']]!=expected['components'],(id,'nondefault identity for defaults')
            nondefault+=1
    assert actual['comparisons']==req['comparisons']
    assert actual['profile_cases']==[{'id':r['id'],'limit':None} for r in req['profile_cases']]
    decoder={r['id']:r['result'] for r in actual['decoder']}
    assert set(decoder)==set(observed)
    for id,java in observed.items():
        status=decoder[id]['status'];wanted='unsupported' if id in unsupported else ('supported' if java['accepted'] else 'rejected')
        assert status==wanted,(id,status,wanted,decoder[id])
    receipt.pop('stdout');receipt.update(outputs=len(outputs),comparisons=len(req['comparisons']),decoder_cases=len(decoder),nondefault_outputs=nondefault,strict_empty_outputs=strict_empty,forged_profile_refusals=len(req['profile_cases']),output_sha256=P.P.sha(result.stdout.encode()))
    write_json(P.CACHE/f'native-output-{threads}.json',actual)
    return receipt

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--reuse-built',action='store_true');parser.add_argument('--skip-checks',action='store_true');args=parser.parse_args()
    data,rows=reference();req,unsupported=request(data,rows);pins=identity();checks=[];cache=P.CACHE/'native-build.json'
    if not args.skip_checks:
        checks.append(check_proof())
        _,receipt=run([BEND,'tests/crafting_recipe_components.bend','--check-only']);checks.append(receipt)
    build=None
    if args.reuse_built:
        saved=json.loads(cache.read_text());assert saved['sources']==pins and saved['binary_sha256']==fingerprint(BINARY)['sha256']
    else:
        _,build=run([BEND,'tests/crafting_recipe_components.bend','-o',BINARY],180)
        assert identity()==pins,'sources changed during native build'
        write_json(cache,{'sources':pins,'binary_sha256':fingerprint(BINARY)['sha256'],'build':build})
    native=[check_native(data,req,unsupported,1),check_native(data,req,unsupported,4)]
    assert identity()==pins,'sources changed during verification'
    assert native[0]['output_sha256']==native[1]['output_sha256']
    evidence={'schema_version':1,'pin':'26.3','status':'passed','confidence':'high for the stated component codec domain','jar_patched_ordinary_outputs':17,'java_cases':len(data['cases']),'java_registered_removal_cases':122,'implemented_persistent_removal_types':119,'numeric_coercion_cases_explicitly_unsupported':sorted(unsupported),'native':native,'checks':checks,'build':build,'sources':{p:fingerprint(ROOT/p) for p in SOURCES},'reference':fingerprint(P.OUTPUT),'reference_tool':fingerprint(Path(P.__file__)),'test_tool':fingerprint(Path(__file__)),'binary':fingerprint(BINARY),'ordinary_laws':re.findall(r'^law (\w+):',(ROOT/'src/crafting_recipe_components_laws.bend').read_text(),re.M),'kernel_laws':[law for law in re.findall(r'^law (\w+):',(ROOT/'src/crafting_recipe_components_laws.bend').read_text(),re.M) if law!='non_stew_identity_cannot_use_closed_stew_authority'],'ordinary_only_laws':['non_stew_identity_cannot_use_closed_stew_authority'],'limitations':['Initialized default maps are trusted canonical DataComponentMap codec output; arbitrary unvalidated defaults are outside this boundary.','Value codecs are suspicious_stew_effects, max_stack_size, max_damage, damage, repair_cost, unbreakable, enchantment_glint_override; other set component types remain Unsupported.','Numeric coercions outside signed integer JSON lexemes and duplicate normalized patch keys are outside the supported domain.','The resolved component envelope is internal trusted identity data, not a public admission or save format.','Player metadata/admission/save adoption is owned and verified separately; this receipt does not claim that integration.','All 840 nonordinary recipe subclasses remain Unsupported.','No general mutation, game behavior or equality theorem for every registered component type.']}
    write_json(EVIDENCE,evidence);print(json.dumps({'status':'passed','native':native,'laws':len(evidence['kernel_laws'])},sort_keys=True))

if __name__=='__main__':main()
