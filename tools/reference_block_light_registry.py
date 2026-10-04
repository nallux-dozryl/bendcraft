#!/usr/bin/env python3
"""Observe every pinned26.3 cached block-light state and effective face pair."""
from __future__ import annotations
import hashlib,json,os,subprocess,time,zipfile
from pathlib import Path
from reference_model_probe import verified_client_classpath,JAVA,CLIENT
from reference_inventory import ROOT,canonical

WORK=ROOT/'build/block-light-registry'
IDENTITY='4f75fa335a12e34cf74be71ff6a0ee530b13233212423f5463bb26a2fe4f3cfc'
SOURCE=r'''import java.util.*;import java.nio.file.*;
import com.google.gson.*;import net.minecraft.SharedConstants;import net.minecraft.server.Bootstrap;
import net.minecraft.core.Direction;import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.state.BlockState;import net.minecraft.world.level.lighting.LightEngine;
import net.minecraft.world.phys.AABB;import net.minecraft.world.phys.shapes.*;
class BlockLightRegistryReference {
 static Gson JSON=new Gson();
 static String key(VoxelShape s){var boxes=new ArrayList<String>();for(AABB b:s.toAabbs())boxes.add(
  Double.toHexString(b.minX)+","+Double.toHexString(b.minY)+","+Double.toHexString(b.minZ)+","+
  Double.toHexString(b.maxX)+","+Double.toHexString(b.maxY)+","+Double.toHexString(b.maxZ));
  Collections.sort(boxes);return String.join(";",boxes);}
 public static void main(String[] args)throws Exception{
  SharedConstants.tryDetectVersion();Bootstrap.bootStrap();
  var shapes=new ArrayList<VoxelShape>();var keys=new ArrayList<String>();
  var byKey=new HashMap<String,Integer>();var byObject=new IdentityHashMap<VoxelShape,Integer>();
  var states=new ArrayList<List<Integer>>();int dynamic=0;int active=0;
  for(BlockState s:Block.BLOCK_STATE_REGISTRY){
   var row=new ArrayList<Integer>();row.add(Block.getId(s));row.add(s.getLightEmission());row.add(s.getLightDampening());
   if(s.getBlock().hasDynamicShape())dynamic++;
   if(s.canOcclude()&&s.useShapeForLightOcclusion())active++;
   for(Direction d:Direction.values()){
    VoxelShape shape=LightEngine.getOcclusionShape(s,d);Integer id=byObject.get(shape);
    if(id==null){String k=key(shape);id=byKey.get(k);if(id==null){id=shapes.size();shapes.add(shape);keys.add(k);byKey.put(k,id);}byObject.put(shape,id);}
    row.add(id);
   }states.add(row);
  }
  int words=(shapes.size()+31)/32;var rows=new ArrayList<List<Long>>();
  for(VoxelShape a:shapes){var row=new ArrayList<Long>();for(int w=0;w<words;w++){
   long bits=0;for(int k=0;k<32;k++){int b=32*w+k;if(b<shapes.size()&&Shapes.faceShapeOccludes(a,shapes.get(b)))bits|=1L<<k;}row.add(bits);
  }rows.add(row);}
  // Each interned representative is also checked against ALL actual effective
  // objects, so geometric deduplication cannot hide a different coverage result.
  long checks=0;for(BlockState s:Block.BLOCK_STATE_REGISTRY)for(Direction d:Direction.values()){
   VoxelShape actual=LightEngine.getOcclusionShape(s,d);int id=byObject.get(actual);
   for(int j=0;j<shapes.size();j++){
    boolean cached=((rows.get(id).get(j/32) >>> (j%32))&1L)!=0;
    if(cached!=Shapes.faceShapeOccludes(actual,shapes.get(j)))throw new AssertionError("Dedup coverage mismatch:"+Block.getId(s)+":"+d+":"+j);
    checks++;
   }
  }
  var result=new TreeMap<String,Object>();result.put("version",SharedConstants.getCurrentVersion().id());
  result.put("state_count",Block.BLOCK_STATE_REGISTRY.size());result.put("states",states);
  result.put("shape_keys",keys);result.put("matrix_rows",rows);result.put("shape_count",shapes.size());
  result.put("dynamic_shape_states",dynamic);result.put("effective_shape_states",active);
  result.put("actual_face_representative_checks",checks);
  Files.writeString(Path.of(args[0]),JSON.toJson(result));
 }
}'''
def digest(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def main():
    WORK.mkdir(parents=True,exist_ok=True)
    paths,provenance=verified_client_classpath()
    (WORK/'BlockLightRegistryReference.java').write_text(SOURCE)
    cmd=[JAVA,'-Xmx512m','--source','25','--class-path',os.pathsep.join(map(str,paths)),
         WORK/'BlockLightRegistryReference.java',WORK/'registry-output.json']
    started=time.monotonic()
    p=subprocess.run(list(map(str,cmd)),cwd=ROOT,capture_output=True,text=True,timeout=120)
    (WORK/'java.stdout').write_text(p.stdout);(WORK/'java.stderr').write_text(p.stderr)
    assert p.returncode==0,(p.returncode,p.stderr)
    observed=json.loads((WORK/'registry-output.json').read_text())
    assert observed['version']=='26.3' and observed['state_count']==35723
    states=observed['states'];assert [s[0] for s in states]==list(range(len(states)))
    n=observed['shape_count'];words=(n+31)//32
    assert len(observed['matrix_rows'])==n and all(len(r)==words for r in observed['matrix_rows'])
    ranges=[]
    for state in states:
        assert 0<=state[1]<=15 and 0<=state[2]<=15 and all(0<=f<n for f in state[3:])
        if ranges and ranges[-1][2:]==state[1:]:ranges[-1][1]+=1
        else:ranges.append([state[0],1,*state[1:]])
    rows=['BendBlockLightRegistry\t1\t26.3\t'+IDENTITY+f'\t{len(states)}\t{n}\t{len(ranges)}\t{words}']
    rows += ['\t'.join(map(str,['S',*r])) for r in ranges]
    rows += ['\t'.join(map(str,['F',i,*r])) for i,r in enumerate(observed['matrix_rows'])]
    data='\n'.join(rows)+'\n';table=ROOT/'reference/block_light_registry.tsv';table.write_text(data)
    class_hashes={}
    with zipfile.ZipFile(CLIENT) as jar:
        for name in ('net.minecraft.world.level.lighting.LightEngine',
                     'net.minecraft.world.level.block.state.BlockBehaviour$BlockStateBase',
                     'net.minecraft.world.phys.shapes.Shapes'):
            class_hashes[name]=hashlib.sha256(jar.read(name.replace('.','/')+'.class')).hexdigest()
    result={'pin':'26.3','registry_identity':IDENTITY,'state_count':len(states),
      'shape_count':n,'range_count':len(ranges),'row_words':words,'ranges':ranges,
      'shape_keys':observed['shape_keys'],'matrix_rows':observed['matrix_rows'],
      'dynamic_shape_states':observed['dynamic_shape_states'],
      'effective_shape_states':observed['effective_shape_states'],
      'actual_face_representative_checks':observed['actual_face_representative_checks'],
      'all_unique_face_pairs_observed':n*n,'table_sha256':digest(table),
      'observations_sha256':digest(WORK/'registry-output.json'),
      'harness_sha256':hashlib.sha256(SOURCE.encode()).hexdigest(),
      'classpath_provenance':provenance,'official_class_sha256':class_hashes,
      'command':list(map(str,cmd)),'seconds':round(time.monotonic()-started,4),
      'boundary':'All pinned registry cached block-light properties and exact effective cached-face union coverage. No collision/outline-shape context independence claim; Java26.3 light getters and face cache are state-only. Python only compresses observed rows; runtime lookup and decoding are Bend. No light propagation or unchanged phase replay.'}
    (ROOT/'reference/block_light_registry.json').write_text(json.dumps(result,indent=2)+'\n')
    evidence={k:result[k] for k in ('pin','state_count','shape_count','range_count',
      'all_unique_face_pairs_observed','actual_face_representative_checks','dynamic_shape_states',
      'effective_shape_states','table_sha256','observations_sha256','seconds','boundary')}
    evidence['status']='passed';evidence['command']='python3 tools/reference_block_light_registry.py'
    (ROOT/'evidence/block-light-registry-reference.json').write_text(json.dumps(evidence,indent=2)+'\n')
    print(json.dumps(evidence))
if __name__=='__main__':main()
