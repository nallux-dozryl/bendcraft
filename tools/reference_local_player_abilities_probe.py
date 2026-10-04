#!/usr/bin/env python3
"""Narrow actual creative-flight receiver observations; no expected simulator."""
from __future__ import annotations
import argparse, base64, hashlib, json, zipfile
from pathlib import Path
import reference_local_input_probe as LI
import test_local_player_session as S
from reference_inventory import ROOT, JAVA, canonical, fingerprint
from reference_model_probe import CLIENT, verified_client_classpath
NAME='net.minecraft.fixture.LocalInputReceiverFixture'
CRITICAL=['net.minecraft.client.player.LocalPlayer','net.minecraft.client.player.AbstractClientPlayer',
 'net.minecraft.world.entity.player.Player','net.minecraft.world.entity.Avatar','net.minecraft.world.entity.LivingEntity',
 'net.minecraft.world.entity.Entity','net.minecraft.client.multiplayer.ClientLevel',
 'net.minecraft.client.multiplayer.MultiPlayerGameMode','net.minecraft.world.entity.player.Abilities',
 'net.minecraft.world.entity.ai.attributes.AttributeInstance','net.minecraft.world.entity.ai.attributes.RangedAttribute']

def inputs():
    cases=[]
    def add(name,masks,**changes):
        seed=LI.initial(mayfly=True,flying=True,grounded=False,**changes)
        seed.update(walking_speed_f32_bits=LI.fb(.1),flying_speed_f32_bits=LI.fb(.05),fall_distance=LI.db(8))
        cases.append({'id':name,'initial':seed,'steps':[{'held_mask':m} for m in masks]})
    add('up',[16,16])
    add('down',[32,32])
    add('both-preserve-negative-zero',[48],velocity=[LI.db(0),LI.db(-0.0),LI.db(0)])
    add('sprint-with-zero-food',[65,65],food=0)
    add('ground-flight-takeoff',[16],jump_trigger=3,flying_override=False,grounded_override=True)
    add('flight-ground-cancellation',[0],velocity=[LI.db(0),LI.db(-.25),LI.db(0)])
    add('double-tap-flight',[16,0,16,0],flying_override=False,grounded_override=True)
    for c in cases:
        seed=c['initial']
        for k in ('flying','grounded'):
            override=seed.pop(k+'_override',None)
            if override is not None:seed[k]=override
    return {'keyboard':[],'vectors':[],'receivers':[],'ai_step':cases}

def prepare(directory,selected_case=None):
    directory.mkdir(parents=True,exist_ok=True)
    selected=inputs()
    if selected_case is not None:
        selected["ai_step"]=[c for c in selected["ai_step"] if c["id"]==selected_case]
        assert len(selected["ai_step"])==1
    sources=LI.receiver_sources(selected);source=sources[NAME]
    # Keep normal real MultiPlayerGameMode construction. Its ordinary initial
    # mode is non-spectator, while saved abilities select the creative branch.
    old='mc.camera=player;mc.player=player;input=new KeyboardInput(mc.options);'
    assert source.count(old)==1
    source=source.replace(old,'mc.camera=player;mc.player=player;mc.gameMode=new MultiPlayerGameMode(mc,connection);input=new KeyboardInput(mc.options);')
    old='p.getAbilities().flying=in.get("flying").getAsBoolean();'
    assert source.count(old)==1
    source=source.replace(old,old+'p.getAbilities().setWalkingSpeed(f(in.get("walking_speed_f32_bits")));p.getAbilities().setFlyingSpeed(f(in.get("flying_speed_f32_bits")));p.getAttribute(Attributes.MOVEMENT_SPEED).setBaseValue((double)p.getAbilities().getWalkingSpeed());p.fallDistance=d(in.get("fall_distance"));')
    old='m.put("crouching",p.isCrouching());'
    assert source.count(old)==1
    source=source.replace(old,'m.put("mayfly",p.getAbilities().mayfly);m.put("flying",p.getAbilities().flying);m.put("walking_speed_f32_bits",bits(p.getAbilities().getWalkingSpeed()));m.put("flying_speed_f32_bits",bits(p.getAbilities().getFlyingSpeed()));m.put("fall_distance",bits(p.fallDistance));'+old)
    sources[NAME]=source
    cp,provenance=verified_client_classpath()
    payload={'sources':sources,'client_jar':str(CLIENT),'mode':'corpus'}
    encoded=base64.b64encode(canonical(payload)).decode()
    launcher=LI.RECEIVER_LAUNCHER.replace('Base64.getDecoder().decode(args[0])',
      'Base64.getDecoder().decode(String.join("",new String[]{'+','.join(json.dumps(encoded[i:i+6144]) for i in range(0,len(encoded),6144))+'}))',1)
    target=directory/'actual-receiver-launcher.java';target.write_text(launcher)
    (directory/'inputs.json').write_bytes(canonical(selected)+b'\n')
    for name,text in sources.items():(directory/(name+'.java')).write_text(text)
    with zipfile.ZipFile(CLIENT) as jar:
        pins={n:hashlib.sha256(jar.read(n.replace('.','/')+'.class')).hexdigest() for n in CRITICAL}
    value={'schema':1,'inputs':selected,'official_class_pins':pins,'classpath_provenance':provenance,
      'sources':{n:hashlib.sha256(s.encode()).hexdigest() for n,s in sources.items()},
      'launcher':S.pin(target),'reference_helper':S.pin(Path(LI.__file__)),
      'command':[str(JAVA),'--source','25','--class-path',':'.join(map(str,cp)),str(target)],
      'scope':'Actual normal LocalPlayer/ClientLevel/MultiPlayerGameMode; ordinary non-spectator creative saved abilities; four declared external services; finite dry flight only, no whole-client/window parity'}
    S.exclusive_json(directory/'preparation.json',value)
    return value

def run(directory):
    prep=json.loads((directory/'preparation.json').read_text())
    assert S.pin(Path(prep['launcher']['path']))==prep['launcher']
    process,out,err=S.bounded(prep['command'],30,directory,'actual-java')
    rows=[json.loads(l[len('LOCAL_RECEIVER_JSON:'):]) for l in out.decode().splitlines() if l.startswith('LOCAL_RECEIVER_JSON:')]
    classes=[json.loads(l[len('LOCAL_INPUT_CLASSES:'):]) for l in out.decode().splitlines() if l.startswith('LOCAL_INPUT_CLASSES:')]
    ok=process['exit_code']==0 and not process['timed_out'] and process['group_absent'] and len(classes)==1
    if ok:
        assert all(classes[0].get(n)==v for n,v in prep['official_class_pins'].items())
        for c in prep['inputs']['ai_step']:
            plain=next(r for r in rows if r['id']==c['id'] and not r['observed'])
            observed=next(r for r in rows if r['id']==c['id'] and r['observed'])
            assert len(plain['steps'])==len(c['steps'])
            for a,b in zip(plain['steps'],observed['steps']):
                for key in ('before','context','expected'):assert a[key]==b[key],(c['id'],key)
    result={'schema':1,'status':'PASS' if ok else 'FAIL','process':process,'preparation':prep,'official_loaded':classes,'rows':rows,
      'counts':{'sequences':len(prep['inputs']['ai_step']),'ticks_per_receiver':sum(len(c['steps']) for c in prep['inputs']['ai_step'])}}
    S.exclusive_json(directory/'result.json',result)
    print(json.dumps({'status':result['status'],'receipt':str(directory/'result.json'),'counts':result['counts']}))
    assert ok,err.decode()[-5000:]

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('mode',choices=['prepare','run']);parser.add_argument('directory',type=Path);parser.add_argument('--case')
    args=parser.parse_args()
    if args.mode=='prepare':print(json.dumps({'prepared':str(args.directory),'command':prepare(args.directory,args.case)['command']}))
    else:run(args.directory)
