#!/usr/bin/env python3
"""Actual 26.3 KeyboardInput.tick and native logical press/release checks."""
from __future__ import annotations
import argparse, hashlib, json, pathlib, random, re, subprocess, sys, time, zipfile
from reference_model_probe import verified_client_classpath
from reference_inventory import JAVA, fingerprint
from test_geometry import run

ROOT=pathlib.Path(__file__).resolve().parents[1]
BEND=pathlib.Path('/Users/chuah/.bend/bin/bend')
BINARY=ROOT/'build/player-input-tests'

JAVA_SOURCE=r'''
import java.lang.reflect.*;
import net.minecraft.client.Options;
import net.minecraft.client.KeyMapping;
import net.minecraft.client.player.KeyboardInput;
import net.minecraft.world.entity.player.Input;
import net.minecraft.world.phys.Vec2;
public class ReferencePlayerInputProbe {
  static final sun.misc.Unsafe U;
  static {try {Field f=sun.misc.Unsafe.class.getDeclaredField("theUnsafe");f.setAccessible(true);U=(sun.misc.Unsafe)f.get(null);}catch(Exception e){throw new RuntimeException(e);}}
  static int mask(Input i){return (i.forward()?1:0)|(i.backward()?2:0)|(i.left()?4:0)|(i.right()?8:0)|(i.jump()?16:0)|(i.shift()?32:0)|(i.sprint()?64:0);}
  static String sample(KeyboardInput k){Vec2 v=k.getMoveVector();return mask(k.keyPresses)+"|"+Integer.toUnsignedString(Float.floatToRawIntBits(v.x))+"|"+Integer.toUnsignedString(Float.floatToRawIntBits(v.y))+"|"+(k.hasForwardImpulse()?"1":"0");}
  public static void main(String[] args)throws Exception{
    // Allocate only the storage layer. No window, options constructor, GLFW
    // key read or Minecraft instance is used. All sampled methods are actual.
    Options o=(Options)U.allocateInstance(Options.class);
    String[] names={"keyUp","keyDown","keyLeft","keyRight","keyJump","keyShift","keySprint"};
    KeyMapping[] keys=new KeyMapping[7];
    for(int n=0;n<7;n++){keys[n]=(KeyMapping)U.allocateInstance(KeyMapping.class);Field f=Options.class.getDeclaredField(names[n]);f.setAccessible(true);f.set(o,keys[n]);}
    KeyboardInput k=new KeyboardInput(o);
    for(int m=0;m<128;m++){
      for(int n=0;n<7;n++)keys[n].setDown((m&(1<<n))!=0);
      k.tick();System.out.println("tick|"+m+"|"+sample(k));
      k.makeJump();System.out.println("jump|"+m+"|"+sample(k));
      for(KeyMapping key:keys)key.setDown(false);
      k.tick();System.out.println("clear|"+m+"|"+sample(k));
    }
  }
}
'''

def sha(path):return hashlib.sha256(pathlib.Path(path).read_bytes()).hexdigest()

def compact_record(record):
    result=dict(record)
    for stream in ['stdout','stderr']:
        value=result.pop(stream,'');result[stream+'_bytes']=len(value.encode());result[stream+'_sha256']=hashlib.sha256(value.encode()).hexdigest()
        if stream=='stderr' and value:result[stream+'_excerpt']=value[-2000:]
    return result

def oracle():
    paths,provenance=verified_client_classpath();directory=ROOT/'build/player-input-oracle';directory.mkdir(parents=True,exist_ok=True)
    source=directory/'ReferencePlayerInputProbe.java';source.write_text(JAVA_SOURCE);classpath=':'.join(map(str,paths))
    build=run([JAVA.with_name('javac'),'-cp',classpath,'-d',directory,source])
    command=[JAVA,'-cp',str(directory)+':'+classpath,'ReferencePlayerInputProbe']
    first=run(command);second=run(command);assert first['stdout']==second['stdout']
    records={}
    for line in first['stdout'].splitlines():
        kind,mask,*values=line.split('|');key=(kind,int(mask));assert key not in records and len(values)==4
        records[key]='|'.join(values)
    assert len(records)==384
    classes={}
    with zipfile.ZipFile(paths[0])as archive:
        for name in ['net/minecraft/client/player/KeyboardInput.class','net/minecraft/client/player/ClientInput.class','net/minecraft/client/KeyMapping.class','net/minecraft/world/entity/player/Input.class','net/minecraft/world/phys/Vec2.class','net/minecraft/util/Mth.class']:
            value=archive.read(name);classes[name]={'bytes':len(value),'sha256':hashlib.sha256(value).hexdigest()}
    return records,{'provenance':provenance,'actual_class_hashes':classes,'java_source_sha256':sha(source),'java_class_sha256':sha(directory/'ReferencePlayerInputProbe.class'),'build':compact_record(build),'runs':[compact_record(first),compact_record(second)],'independent_java_runs':2,'scope':'untouched KeyboardInput.tick, ClientInput.makeJump/getMoveVector/hasForwardImpulse, KeyMapping.setDown/isDown; Options/KeyMapping storage allocated without constructors; no OS input or LocalPlayer.aiStep'}

def native(args,expected):
    records=[]
    for offset in range(0,len(args),500):
        batch=run([BINARY,'--gpu','off',*args[offset:offset+500]])
        actual=batch['stdout'].splitlines();assert actual==expected[offset:offset+500],(offset,next(((a,b)for a,b in zip(actual,expected[offset:offset+500])if a!=b),None))
        records.append({'offset':offset,'cases':len(actual),'seconds':batch['seconds'],'output_sha256':hashlib.sha256(batch['stdout'].encode()).hexdigest()})
    return records

def expected_mask(record):
    return record.split('|')[0]

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--skip-build',action='store_true');opts=parser.parse_args()
    records,reference=oracle();sources=['src/player_input.bend','tests/player_input.bend','tools/test_player_input.py','docs/PLAYER_INPUT.md']
    generations={p:sha(ROOT/p)for p in sources};checks=[]
    for source in sources[:2]:
        checks.append(run([BEND,source,'--check-only']));checks.append(run([BEND,source,'--verdict']))
    builds=[]
    if opts.skip_build:
        previous=json.loads((ROOT/'evidence/player-input-verification.json').read_text());assert previous['sources_sha256']==generations and previous['binary_sha256']==sha(BINARY)
    else:builds.append(compact_record(run([BEND,'tests/player_input.bend','-o',BINARY])))
    arguments=[];answers=[]
    for mask in range(128):
        for kind,suffix in [('tick',''),('jump','|4294967294'),('clear','|4294967295')]:
            arguments.append(str(mask)+suffix);answers.append(records[kind,mask])
    runs=native(arguments,answers)
    # Distinct/shared bindings, high unsigned event codes, repeat-down,
    # key-up and unmatched codes. Expected logical state is an independent
    # mask update; numeric movement expectations remain actual Java outputs.
    rng=random.Random(0x2631);events=[];expected=[];policies=[[119,115,97,100,32,65592,65595],[9,9,9,9,9,9,9],[0,1,2147483647,2147483648,4294967295,65536,117]]
    for bindings in policies:
        for mask in range(128):
            for code in bindings+[2,65537,123456789]:
                for down in [0,1]:
                    next_mask=mask
                    for bit,binding in enumerate(bindings):
                        if binding==code:next_mask=(next_mask|(1<<bit))if down else(next_mask&~(1<<bit))
                    events.append('|'.join(map(str,[mask,*bindings,code,down])));expected.append(records['tick',next_mask])
    # Actual held-state progression across multiple pressed keys, cancellation,
    # repeats, release, remapping and a new unrelated event.
    chains=[]
    for chain in range(64):
        bindings=rng.choice(policies);mask=0
        for step in range(32):
            code=rng.choice(bindings+[47163]);down=rng.randrange(2);next_mask=mask
            for bit,binding in enumerate(bindings):
                if binding==code:next_mask=(next_mask|(1<<bit))if down else(next_mask&~(1<<bit))
            events.append('|'.join(map(str,[mask,*bindings,code,down])));expected.append(records['tick',next_mask]);mask=next_mask
        chains.append(mask)
    event_runs=native(events,expected)
    malformed=[]
    for request in ['broken','1|2','1|0|1','1|two','1|0|1|2|3|4|5|6|7|8|9']:
        result=run([BINARY,'--gpu','off',request],required=False);assert result['exit_code']==2 and 'invalid player input protocol'in result['stderr'];malformed.append(compact_record(result))
    assert generations=={p:sha(ROOT/p)for p in sources}
    source=(ROOT/sources[0]).read_text();assert not re.search(r'@unsafe|\w!\(|F32\.(sin|cos|sqrt)',source)
    evidence={'status':'passed','pin':'26.3','actual_keyboard_tick_comparisons':128,'actual_make_jump_comparisons':128,'actual_clear_tick_comparisons':128,'logical_event_cases':len(events),'held_sequences':64,'held_sequence_events':2048,'checks':checks,'kernel_pass':True,'laws':re.findall(r'^law (\w+):',source,re.M),'builds':builds,'native_reference_batches':runs,'native_event_batches':event_runs,'malformed_protocol':malformed,'direct_java':reference,'sources_sha256':generations,'binary_sha256':sha(BINARY),'confidence':'high for every seven-button logical KeyboardInput combination and recorded key-event transitions','unsupported':['real OS keyboard/mouse capture and mapping','LocalPlayer input-to-entity assignment, slowdown/pose/abilities/sprint state machine','input packet transport','continuous authoritative game integration']}
    (ROOT/'evidence/player-input-verification.json').write_text(json.dumps(evidence,indent=2,sort_keys=True)+'\n');print(json.dumps({k:evidence[k]for k in ['status','actual_keyboard_tick_comparisons','logical_event_cases','kernel_pass','confidence']},indent=2))

if __name__=='__main__':main()
