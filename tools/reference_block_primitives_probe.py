#!/usr/bin/env python3
"""Actual pinned Block stored/getter primitives; no contextual shape extraction."""
from __future__ import annotations
import argparse
import csv
import hashlib
import json
from pathlib import Path
import re
import struct
import subprocess
import zipfile

from reference_block_probe import verified_classpath
from reference_inventory import JAVA, ROOT, canonical, fingerprint, write_json
from test_persistence import registry_identity, OFFICIAL

WORK = ROOT / 'build/block-physics/reference'
TABLE = ROOT / 'generated/reference_block_primitives.tsv'
REFERENCE = ROOT / 'reference/block_primitives.json'
FIELDS = ('friction', 'speed_factor', 'jump_factor')
METHODS = ('getFriction', 'getSpeedFactor', 'getJumpFactor')
OWNER = 'net.minecraft.world.level.block.Block'

SOURCE = r'''import java.io.*;
import java.nio.file.*;
import java.lang.reflect.*;
import java.util.*;
import com.google.gson.Gson;
import net.minecraft.SharedConstants;
import net.minecraft.server.Bootstrap;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.state.BlockState;

class ReferenceBlockPrimitivesProbe {
  static final String[] METHODS={"getFriction","getSpeedFactor","getJumpFactor"};
  static final String[] FIELDS={"friction","speedFactor","jumpFactor"};
  static String raw(float x) { return String.format(Locale.ROOT,"%08x",Float.floatToRawIntBits(x)); }
  static String wide(float x) { return String.format(Locale.ROOT,"%016x",Double.doubleToRawLongBits((double)x)); }
  static Field stored(Class<?> type,String name) throws Exception {
    while(type!=null){try{return type.getDeclaredField(name);}catch(NoSuchFieldException missing){type=type.getSuperclass();}}
    throw new NoSuchFieldException(name);
  }
  public static void main(String[] args) throws Exception {
    SharedConstants.tryDetectVersion(); Bootstrap.bootStrap();
    Field[] fields=new Field[3];
    for(int i=0;i<3;i++){ fields[i]=stored(Block.class,FIELDS[i]); fields[i].setAccessible(true); }
    var blocks=new TreeMap<String,Object>();
    try(var out=new PrintWriter(Files.newBufferedWriter(Path.of(args[0])))) {
      out.println("state_id\tblock_identifier\tfriction_f32_bits\tfriction_promoted_f64_bits\tspeed_factor_f32_bits\tspeed_factor_promoted_f64_bits\tjump_factor_f32_bits\tjump_factor_promoted_f64_bits");
      for(int id=0;id<Block.BLOCK_STATE_REGISTRY.size();id++){
        BlockState state=Block.stateById(id);Block b=state.getBlock();
        String name=BuiltInRegistries.BLOCK.getKey(b).toString();
        float[] values={b.getFriction(),b.getSpeedFactor(),b.getJumpFactor()};
        if(!blocks.containsKey(name)) {
          var record=new TreeMap<String,Object>();
          record.put("class",b.getClass().getName());record.put("protocol",BuiltInRegistries.BLOCK.getId(b));
          var owners=new TreeMap<String,String>();var modifiers=new TreeMap<String,String>();var fieldOwners=new TreeMap<String,String>();
          for(int i=0;i<3;i++){
            owners.put(METHODS[i],b.getClass().getMethod(METHODS[i]).getDeclaringClass().getName());
            modifiers.put(FIELDS[i],Modifier.toString(fields[i].getModifiers()));fieldOwners.put(FIELDS[i],fields[i].getDeclaringClass().getName());
          }
          record.put("owners",owners);record.put("field_modifiers",modifiers);record.put("field_owners",fieldOwners);blocks.put(name,record);
        }
        StringBuilder line=new StringBuilder(id+"\t"+name);
        for(int i=0;i<3;i++){
          if(Float.floatToRawIntBits(values[i])!=Float.floatToRawIntBits(fields[i].getFloat(b)))
            throw new AssertionError("Stored/getter mismatch:"+id+":"+FIELDS[i]);
          line.append('\t').append(raw(values[i])).append('\t').append(wide(values[i]));
        }
        out.println(line);
      }
      if(out.checkError())throw new IOException("Probe output failed");
    }
    var result=new TreeMap<String,Object>();result.put("version",SharedConstants.getCurrentVersion().id());
    result.put("states",Block.BLOCK_STATE_REGISTRY.size());result.put("blocks",blocks);
    Files.writeString(Path.of(args[1]),new Gson().toJson(result));
  }
}
'''

def sha(data):
    return hashlib.sha256(data).hexdigest()

def rows(path):
    with path.open() as stream:
        return list(csv.DictReader(stream, delimiter='\t'))

def validate(observed, receivers, old_rows, identity):
    old=json.loads((ROOT/'reference/block_physics.json').read_text())
    if sha((ROOT/'generated/reference_block_physics.tsv').read_bytes())!=old['table']['sha256']:
        raise ValueError('Existing full reference hash mismatch')
    if receivers['version']!='26.3' or receivers['states']!=35723 or len(receivers['blocks'])!=1286:
        raise ValueError('Actual pinned registry count/version mismatch')
    if len(observed)!=35723 or len(old_rows)!=35723:
        raise ValueError('State observation count mismatch')
    for block in receivers['blocks'].values():
        if set(block['owners'].values())!={OWNER} or any('final' not in v for v in block['field_modifiers'].values()):
            raise ValueError('Registered getter override or mutable primitive field')
    expected=[]
    for block in rows(OFFICIAL):
        first,count=int(block['first_state_id']),int(block['state_count'])
        if first!=len(expected) or receivers['blocks'][block['identifier']]['protocol']!=int(block['block_protocol_id']):
            raise ValueError('Official generator block/protocol disagreement')
        expected.extend([block['identifier']]*count)
    for index,(record,prior) in enumerate(zip(observed,old_rows)):
        if int(record['state_id'])!=index or record['state_id']!=prior['state_id'] or record['block_identifier']!=prior['block_identifier'] or record['block_identifier']!=expected[index]:
            raise ValueError('State identity disagreement')
        for field in FIELDS:
            raw=record[field+'_f32_bits'];wide=record[field+'_promoted_f64_bits']
            if not re.fullmatch('[0-9a-f]{8}',raw) or not re.fullmatch('[0-9a-f]{16}',wide):
                raise ValueError('Invalid raw encoding')
            numeric=struct.unpack('>f',bytes.fromhex(raw))[0]
            if struct.pack('>d',numeric).hex()!=wide or record[field+'_f32_bits']!=prior[field+'_f32_bits'] or wide!=prior[field+'_promoted_f64_bits']:
                raise ValueError('Actual raw value or widening disagreement')
    intervals=[]
    for record in observed:
        factors=[int(record[field+'_f32_bits'],16) for field in FIELDS]
        if intervals and intervals[-1]['factors']==factors:
            intervals[-1]['count']+=1
        else:
            intervals.append({'first':int(record['state_id']),'count':1,'factors':factors})
    header='BendBlockPrimitives\t1\t26.3\t'+identity+'\t35723\n'
    header+='first_state_id\tstate_count\tfriction_f32_bits\tspeed_factor_f32_bits\tjump_factor_f32_bits\n'
    table=(header+''.join('\t'.join(map(str,(r['first'],r['count'],*r['factors'])))+'\n' for r in intervals)).encode()
    return intervals,table

def probe():
    WORK.mkdir(parents=True,exist_ok=True)
    jars,release=verified_classpath();source=WORK/'ReferenceBlockPrimitivesProbe.java';source.write_text(SOURCE)
    subprocess.run([str(JAVA.parent/'javac'),'-cp',':'.join(map(str,jars)),'-d',str(WORK),str(source)],check=True,capture_output=True,timeout=60)
    runs=[]
    for i in range(2):
        table=WORK/f'actual-{i}.tsv';meta=WORK/f'receivers-{i}.json'
        result=subprocess.run([str(JAVA),'-cp',str(WORK)+':'+':'.join(map(str,jars)),'ReferenceBlockPrimitivesProbe',str(table),str(meta)],check=True,capture_output=True,timeout=60)
        (WORK/f'run-{i}.log').write_bytes(result.stdout+result.stderr)
        runs.append({'table':fingerprint(table),'receivers':fingerprint(meta)})
    if (WORK/'actual-0.tsv').read_bytes()!=(WORK/'actual-1.tsv').read_bytes() or (WORK/'receivers-0.json').read_bytes()!=(WORK/'receivers-1.json').read_bytes():
        raise ValueError('Independent Java reruns differ')
    observed=rows(WORK/'actual-0.tsv');receivers=json.loads((WORK/'receivers-0.json').read_text())
    identity,count,registry=registry_identity(OFFICIAL)
    if count!=35723:raise ValueError('Official metadata state count mismatch')
    intervals,data=validate(observed,receivers,rows(ROOT/'generated/reference_block_physics.tsv'),identity)
    bytecode=subprocess.run([str(JAVA.parent/'javap'),'-cp',str(jars[0]),'-c','-p',OWNER],check=True,capture_output=True,text=True,timeout=60).stdout
    (WORK/'Block.javap').write_text(bytecode)
    bodies={}
    for method,field in zip(METHODS,('friction','speedFactor','jumpFactor')):
        match=re.search(r'  public float '+method+r'\(\);\n(.*?)(?=\n  (?:public|protected|private|static)|\Z)',bytecode,re.S)
        if not match:raise ValueError('Missing production getter bytecode')
        body=match[1]
        operations=re.findall(r'^\s+\d+: (\w+)',body,re.M)
        if operations!=['aload_0','getfield','freturn'] or not re.search('// Field '+field+':F',body):
            raise ValueError('Getter is not the expected sole stored-field load')
        bodies[method]={'field':field,'operations':operations,'bytecode_text_sha256':sha(body.encode()),'declaring_owner':OWNER}
    declared=receivers['blocks']['minecraft:air']
    if any(b['field_owners']!=declared['field_owners'] or b['field_modifiers']!=declared['field_modifiers'] for b in receivers['blocks'].values()):
        raise ValueError('Unexpected primitive field declaration differences')
    with zipfile.ZipFile(jars[0]) as archive:
        class_hashes={name:sha(archive.read(name.replace('.','/')+'.class')) for name in {OWNER,*declared['field_owners'].values()}}
    TABLE.write_bytes(data)
    targeted={r['block_identifier']:{k:r[k] for k in ('state_id',*[x for f in FIELDS for x in (f+'_f32_bits',f+'_promoted_f64_bits')])} for r in observed if r['block_identifier'] in ('minecraft:air','minecraft:stone','minecraft:ice','minecraft:packed_ice','minecraft:blue_ice','minecraft:frosted_ice','minecraft:slime_block','minecraft:soul_sand','minecraft:honey_block')}
    output={'pin':'26.3','reference_only':True,'states':35723,'blocks':1286,'ranges':intervals,'unique_factor_triples':len(set(tuple(r['factors']) for r in intervals)),'registry':registry,'registry_identity':identity,'derived_table':fingerprint(TABLE),'source_sha256':sha(SOURCE.encode()),'tool_sha256':sha(Path(__file__).read_bytes()),'java_runtime':fingerprint(JAVA),'server_sha256':fingerprint(jars[0])['sha256'],'classpath_count':len(jars),'classpath_manifest_sha256':sha(canonical([fingerprint(p) for p in jars])),'class_sha256':class_hashes,'stored_field_declarations':{'owners':declared['field_owners'],'modifiers':declared['field_modifiers']},'getters':bodies,'registered_receiver_manifest_sha256':sha(canonical(receivers['blocks'])),'getter_equals_stored_field_all_states':True,'all_registered_getter_owners':OWNER,'two_byte_identical_java_runs':runs,'all_states_equal_existing_independent_reference':True,'targeted':targeted,'scope':['Only the stored Block friction, speedFactor and jumpFactor fields/getters.','All registered receivers inherit the inspected sole-field-return getters; final fields, no world/entity/position input or call.','No collision, shape, outline, light, contextual speed application or movement transition is generalized.']}
    write_json(REFERENCE,output)
    write_json(ROOT/'evidence/block-physics-reference.json',{k:v for k,v in output.items() if k!='ranges'})
    return output

def verify_existing():
    info=json.loads(REFERENCE.read_text());jars,_=verified_classpath()
    if info['source_sha256']!=sha(SOURCE.encode()) or info['tool_sha256']!=sha(Path(__file__).read_bytes()) or info['java_runtime']!=fingerprint(JAVA):
        raise ValueError('Reference source/tool/runtime changed')
    if info['classpath_manifest_sha256']!=sha(canonical([fingerprint(p) for p in jars])):
        raise ValueError('Official classpath changed')
    receivers=json.loads((WORK/'receivers-0.json').read_text());identity,count,_=registry_identity(OFFICIAL)
    intervals,data=validate(rows(WORK/'actual-0.tsv'),receivers,rows(ROOT/'generated/reference_block_physics.tsv'),identity)
    if info['registry_identity']!=identity or info['ranges']!=intervals or TABLE.read_bytes()!=data or info['derived_table']!=fingerprint(TABLE):
        raise ValueError('Derived pinned catalog corrupted')
    for i,r in enumerate(info['two_byte_identical_java_runs']):
        if r!={'table':fingerprint(WORK/f'actual-{i}.tsv'),'receivers':fingerprint(WORK/f'receivers-{i}.json')}:
            raise ValueError('Actual Java observation corrupted')
    return info

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--verify-existing',action='store_true');args=parser.parse_args()
    info=verify_existing() if args.verify_existing else probe()
    print(json.dumps({'status':'passed','states':info['states'],'blocks':info['blocks'],'ranges':len(info['ranges']),'bytes':info['derived_table']['bytes'],'sha256':info['derived_table']['sha256']}))

if __name__=='__main__':main()
