#!/usr/bin/env python3
"""Pinned registry receivers for the Bend cooking/Core bridge; no gameplay in Python."""
from __future__ import annotations
import hashlib,json,subprocess,time
from pathlib import Path
from reference_model_probe import verified_client_classpath,JAVA
from reference_inventory import ROOT
WORK=ROOT/'build/cooking-world-reference'
SOURCE=r'''import java.util.*;import java.nio.file.*;import java.lang.reflect.*;
import com.google.gson.*;import net.minecraft.SharedConstants;import net.minecraft.server.Bootstrap;
import net.minecraft.core.*;import net.minecraft.core.registries.*;import net.minecraft.world.level.block.*;
import net.minecraft.world.level.block.state.*;import net.minecraft.world.level.block.state.properties.*;
class CookingWorldReference {
 static String family(Block b){if(b instanceof FurnaceBlock)return "smelting";if(b instanceof BlastFurnaceBlock)return "blasting";if(b instanceof SmokerBlock)return "smoking";if(b instanceof CampfireBlock)return "campfire";return "none";}
 static Map<String,String> properties(BlockState s){var out=new TreeMap<String,String>();for(Property p:s.getProperties())out.put(p.getName(),p.getName(s.getValue(p)));return out;}
 public static void main(String[]args){try{
  SharedConstants.tryDetectVersion();Bootstrap.bootStrap();Field damage=CampfireBlock.class.getDeclaredField("fireDamage");damage.setAccessible(true);
  var rows=new ArrayList<Object>();int count=0,ordinary=0;for(BlockState s:Block.BLOCK_STATE_REGISTRY){count++;Block b=s.getBlock();String f=family(b);if(f.equals("none")){ordinary++;continue;}
   var row=new TreeMap<String,Object>();row.put("state",Block.getId(s));row.put("block",BuiltInRegistries.BLOCK.getKey(b).toString());row.put("family",f);row.put("lit",s.getValue(BlockStateProperties.LIT));row.put("unlit_state",Block.getId(s.setValue(BlockStateProperties.LIT,false)));row.put("lit_state",Block.getId(s.setValue(BlockStateProperties.LIT,true)));row.put("properties",properties(s));row.put("fire_damage",b instanceof CampfireBlock?damage.getInt(b):0);rows.add(row);
  }
  Files.writeString(Path.of(args[0]),new GsonBuilder().serializeNulls().create().toJson(Map.of("pin",SharedConstants.getCurrentVersion().id(),"state_count",count,"non_cooking_states",ordinary,"bindings",rows)));
 }catch(Throwable e){e.printStackTrace(new java.io.PrintStream(new java.io.FileOutputStream(java.io.FileDescriptor.err)));System.exit(1);}}
}'''
def sha(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def main():
 WORK.mkdir(parents=True,exist_ok=True);paths,provenance=verified_client_classpath();cp=':'.join(map(str,paths));src=WORK/'CookingWorldReference.java';src.write_text(SOURCE)
 started=time.monotonic();subprocess.run([str(JAVA.parent/'javac'),'-cp',cp,str(src)],check=True,cwd=WORK,capture_output=True,text=True,timeout=60)
 subprocess.run([str(JAVA),'-Xmx512m','-cp',str(WORK)+':'+cp,'CookingWorldReference',str(WORK/'bindings.json')],check=True,cwd=WORK,capture_output=True,text=True,timeout=60)
 observed=json.loads((WORK/'bindings.json').read_text());assert observed['pin']=='26.3'
 registry=ROOT/'generated/reference_blocks.tsv';observed['registry_sha256']=sha(registry);observed['registry_identity']=json.loads((ROOT/'reference/block_light_registry.json').read_text())['registry_identity'];rows=observed['bindings'];byid={r['state']:r for r in rows}
 for r in rows:
  for flag,key in [(False,'unlit_state'),(True,'lit_state')]:
   target=byid[r[key]];assert target['block']==r['block'] and target['family']==r['family'] and target['lit']==flag
   assert {k:v for k,v in target['properties'].items() if k!='lit'}=={k:v for k,v in r['properties'].items() if k!='lit'}
 observed['provenance']=provenance;(ROOT/'reference/cooking_world.json').write_text(json.dumps(observed,indent=2)+'\n')
 # Small production manifest: authentication binds exhaustive classification,
 # not a hand-picked product state list. Registry identity remains explicit.
 text='pin\t26.3\t'+observed['registry_identity']+'\t'+str(observed['state_count'])+'\n'
 for r in rows:text+='\t'.join(map(str,[r['state'],r['block'],r['family'],str(r['lit']).lower(),r['unlit_state'],r['lit_state'],r['fire_damage']]))+'\n'
 (ROOT/'reference/cooking_world_bindings.tsv').write_text(text)
 evidence={'status':'passed','command':'python3 tools/reference_cooking_world.py','seconds':round(time.monotonic()-started,4),'all_registry_states_observed':observed['state_count'],'cooking_state_bindings':len(rows),'non_cooking_states':observed['non_cooking_states'],'binding_sha256':sha(ROOT/'reference/cooking_world_bindings.tsv'),'registry_sha256':sha(registry),'reference_sha256':sha(ROOT/'reference/cooking_world.json'),'boundary':'Actual installed Block.BLOCK_STATE_REGISTRY receivers, runtime block subclass classification, state.setValue(LIT) and complete non-LIT property equality; no world/entity lifecycle parity claim from enumeration.'}
 (ROOT/'evidence/cooking-world-reference.json').write_text(json.dumps(evidence,indent=2)+'\n');print(json.dumps(evidence))
if __name__=='__main__':main()
