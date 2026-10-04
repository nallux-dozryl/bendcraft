#!/usr/bin/env python3
"""Inventory retained pinned density JSON against current decoder type cases.

Read-only resource inspection, without Java or native execution. Counts typed
JSON objects in each once-per-registry-definition closure, not compiled nodes.
This extractor does not evaluate density functions or implement game behavior.
"""
from __future__ import annotations
import argparse, collections, hashlib, json, re, zipfile
from pathlib import Path
from reference_inventory import ROOT, fingerprint, write_json

REFERENCE=ROOT/'reference/worldgen_density.json'
CODEC=ROOT/'src/worldgen_density_codec.bend'
OUTPUT=ROOT/'evidence/worldgen-density-router-boundaries.json'
SIGNATURES=[ROOT/'build/superflat-world/reference/density-noise-helper-signatures/stdout',
 ROOT/'build/superflat-world/reference/density-operator-signatures/stdout',
 ROOT/'build/superflat-world/reference/density-interval-blend-signatures-1791137663854721000/stdout']

def inspect():
    observed=json.loads(REFERENCE.read_text())
    if observed['pin']!='26.3' or observed['status']!='observed':
        raise ValueError('Actual pinned26.3 density reference required')
    densities=observed['registry']['densities']
    supported=set(re.findall(r'case "(minecraft:[^\"]+)":',CODEC.read_text()))
    jar=Path.home()/'Library/Application Support/minecraft/versions/26.3/26.3.jar'
    verified=[]
    with zipfile.ZipFile(jar) as archive:
        for key,value in densities.items():
            member='data/'+key.replace(':','/worldgen/density_function/')+'.json'
            raw=archive.read(member);pin=observed['installed_resource_pins'][member]
            if json.loads(raw)!=value or len(raw)!=pin['bytes'] or hashlib.sha256(raw).hexdigest()!=pin['sha256']:
                raise RuntimeError('Retained density definition differs from pinned installed bytes: '+key)
            verified.append({'key':key,'member':member,**pin})
    def inventory(expressions):
        references={};types=collections.Counter();unsupported=[];context=[]
        def visit(value,path):
            if isinstance(value,str) and value in densities:
                if value not in references:
                    references[value]=path
                    visit(densities[value],value)
            elif isinstance(value,list):
                for index,child in enumerate(value):visit(child,path+'/'+str(index))
            elif isinstance(value,dict):
                if 'type' in value:
                    kind=value['type'];types[kind]+=1
                    row={'kind':kind,'path':path}
                    if kind not in supported:unsupported.append(row)
                    if kind in ('minecraft:blend_alpha','minecraft:blend_offset','minecraft:blend_density'):context.append(row)
                for key,child in value.items():
                    if key not in ('type','noise'):visit(child,path+'/'+key)
        for name,expression in expressions.items():visit(expression,'noise_router/'+name)
        return {'loaded_definition_count':len(references),'loaded_definitions':references,
          'typed_json_object_count':sum(types.values()),'type_counts':dict(sorted(types.items())),
          'unsupported_type_counts':dict(sorted(collections.Counter(row['kind'] for row in unsupported).items())),
          'unsupported_typed_json_object_count':len(unsupported),'unsupported_objects':unsupported,
          'explicit_blending_context_objects':context}
    router=observed['settings']['noise_router']
    result={'schema':1,'pin':'26.3','status':'inspected','confidence':'high for retained resource identity and documented JSON object counts',
      'counting_method':'Walk density-valued JSON recursively, excluding type labels and noise-registry identifiers. Expand each reachable named density definition exactly once per closure. Count typed JSON objects, including objects under unsupported parents; these are not compiled DAG nodes, dynamic sample counts or proof obligations.',
      'per_router_root':{name:inventory({name:expression}) for name,expression in router.items()},
      'shared_eight_root_closure':inventory(router),'verified_installed_density_definition_count':len(verified),
      'installed_density_definitions':verified,'density_reference':fingerprint(REFERENCE),'decoder':fingerprint(CODEC),
      'retained_official_signature_receipts':[{'path':str(path.relative_to(ROOT)),**fingerprint(path)} for path in SIGNATURES],
      'helper':fingerprint(Path(__file__).resolve()),
      'scope':'File-only inventory of actual loaded shipped Overworld router resources and current decoder type cases. Explicit no-blending defaults cover blend alpha/offset/density only; beardifier remains unsupported. This inventory does not establish operator semantics, executable full-router admission, material/aquifer/surface joins or normal population.'}
    write_json(OUTPUT,result)
    return {'status':'inspected','final_density':result['per_router_root']['final_density']['unsupported_type_counts'],
      'final_density_unsupported_objects':result['per_router_root']['final_density']['unsupported_typed_json_object_count'],
      'surface':result['per_router_root']['chunk_surface_level']['unsupported_type_counts'],
      'shared_eight_unsupported':result['shared_eight_root_closure']['unsupported_type_counts']}

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--inspect',required=True,action='store_true');parser.parse_args()
    print(json.dumps(inspect(),sort_keys=True))
