#!/usr/bin/env python3
"""Fresh pinned receiver observations of fall-history phases, not host physics."""
from __future__ import annotations
import argparse, base64, copy, hashlib, json, math, os, random, re, signal, struct, subprocess, time, zipfile
from pathlib import Path
from reference_inventory import ROOT, JAVA, canonical, fingerprint, write_json
from reference_model_probe import CLIENT, verified_client_classpath
import reference_local_input_probe as L

OUTPUT=ROOT/'reference/player_fall_history.json'
RAW=ROOT/'build/player-fall-history-reference'
FIXTURE='net.minecraft.fixture.LocalInputReceiverFixture'
CLASSES=['net.minecraft.world.entity.Entity','net.minecraft.world.entity.LivingEntity','net.minecraft.world.entity.player.Player','net.minecraft.client.player.LocalPlayer','net.minecraft.client.multiplayer.ClientLevel','net.minecraft.world.level.block.Block']
METHODS={'move','doCheckFallDamage','checkFallDamage','resetFallDistance','checkFallDistanceAccumulation','updateFluidInteraction','checkSupportingBlock','setOnGroundWithMovement','fallOn','causeFallDamage','calculateFallDamage','calculateFallPower','aiStep','baseTick','rideTick','makeStuckInBlock','handleOnClimbable','updateFallFlying','handleOnInsideBubbleColumn'}

def sha(b):return hashlib.sha256(b).hexdigest()
def bits(v):return v if isinstance(v,str) else struct.pack('>d',v).hex()
def vector(v):return [bits(x)for x in v]

def inputs():
    rows=[]
    def add(name,distance=0.,pos=(.5,4.,.5),steps=None,world='floor',ground=False):
        rows.append({'id':name,'distance_f64_bits':bits(distance),'position_f64_bits':vector(pos),'ground':ground,'world':world,'steps':steps or []})
    def move(v,**kw):return {'operation':'move','requested_f64_bits':vector(v),**kw}
    def check(y,g=False):return {'operation':'check','resolved_y_f64_bits':bits(y),'ground':g}
    add('air-descend',steps=[move((0,-.1,0))])
    add('air-ascend',distance=1.25,steps=[move((0,.42,0))])
    add('land-safe',distance=1.25,pos=(.5,1.125,.5),steps=[move((0,-.25,0))])
    add('land-large-feasibility',distance=20.,pos=(.5,1.125,.5),steps=[move((0,-.25,0))])
    add('blocked-no-position',distance=.5,pos=(.5,1.,.5),steps=[move((0,-1,0))],ground=True)
    add('skipped-position-still-history',distance=.5,pos=(1.-.6000000238418579/2,2.,.5),world='wall',steps=[move((1,-.0001,0))])
    add('position-rounding-vs-resolved',distance=.3,pos=(.5,1048576.,.5),steps=[move((0,-.1000000000001,0))])
    add('long-air-clip-miss',distance=.3,pos=(.5,10.,.5),steps=[move((0,-1.125,0))])
    add('zero-distance-no-clip',pos=(.5,10.,.5),steps=[move((0,-1.125,0))])
    add('no-physics-skips-history',distance=.5,steps=[move((0,-.25,0),no_physics=True)])
    add('chained-jump-air-land',pos=(.5,1.,.5),ground=True,steps=[{'operation':'jump'},move((0,.41999998688697815,0)),move((0,.15,0)),move((0,-.18,0)),move((0,-.22,0)),move((0,-.4,0)),move((0,-.1,0))])
    add('chained-fall-reset-recover',distance=.25,pos=(.5,10.,.5),steps=[move((0,-.2,0)),{'operation':'reset'},move((0,-.4,0)),{'operation':'clamp','velocity_y_f64_bits':bits(-.25)},move((0,-.2,0))])
    add('chained-two-descents',distance=.3,steps=[move((0,-.1,0)),move((0,-.1,0))])
    add('land-exact-safe-threshold',distance=2.875,pos=(.5,1.125,.5),steps=[move((0,-.25,0))])
    add('land-above-safe-threshold-feasibility',distance=2.8750000000000004,pos=(.5,1.125,.5),steps=[move((0,-.25,0))])
    for distance in [3.8749989999999994,3.874999,3.8749990000000003,3.875,3.999999,4.]:
        add('land-floor-threshold:'+str(distance),distance=distance,pos=(.5,1.125,.5),steps=[move((0,-.25,0))])
    for dy in [-1e100,-3.4028235677973366e38]:add('check-f32-overflow:'+str(dy),distance=.3,steps=[check(dy)])
    for old in [0.,'8000000000000000',.1,1.,1.0000000000000002,2.75,-.25,1e100,'7fefffffffffffff','ffefffffffffffff']:
        add('reset:'+str(old),distance=old,steps=[{'operation':'reset'}])
        for dy in [-.5000000000000001,-.5,-.49999999999999994,0.,'8000000000000000',.25]:
            add('clamp:'+str(old)+':'+str(dy),distance=old,steps=[{'operation':'clamp','velocity_y_f64_bits':bits(dy)}])
    # Direct actual checkFallDamage isolates arithmetic from the collision/body
    # service boundary, while move cases independently establish its call point.
    ys=[0.,'8000000000000000',-.1,-.1000000000001,-.0001,-1e-50,-1e-45,-16777217.,.125]
    olds=[0.,'8000000000000000',.3,1.0000000000000002,-.25,1e100,'7fefffffffffffff','ffefffffffffffff']
    for old in olds:
        for dy in ys:add('check:'+str(old)+':'+str(dy),distance=old,steps=[check(dy)])
    for old in [0.,'8000000000000000',-.25,.3,2.75]:
        for dy in [0.,'8000000000000000',-.125]:add('check-land:'+str(old)+':'+str(dy),distance=old,steps=[check(dy,True)])
    rng=random.Random(0x263fa11)
    for i in range(48):
        add('random-air:'+str(i),distance=rng.uniform(0,100),pos=(.5,100.,.5),steps=[move((rng.uniform(-.3,.3),rng.uniform(-.9,.9),rng.uniform(-.3,.3)))])
    return rows

HELPERS=r'''
 static Map<String,Object> history(LocalPlayer p)throws Exception{
  Map<String,Object> m=new TreeMap<>();m.put("distance_f64_bits",bits(p.fallDistance));m.put("position_f64_bits",vector(p.position()));m.put("velocity_f64_bits",vector(p.getDeltaMovement()));m.put("ground",p.onGround());m.put("in_water",p.isInWater());m.put("local_authority",p.isLocalInstanceAuthoritative());m.put("no_physics",p.noPhysics);m.put("health_f32_bits",bits(p.getHealth()));m.put("safe_fall_distance_f64_bits",bits(p.getAttributeValue(Attributes.SAFE_FALL_DISTANCE)));m.put("fall_damage_multiplier_f64_bits",bits(p.getAttributeValue(Attributes.FALL_DAMAGE_MULTIPLIER)));m.put("calculated_default_fall_damage",invokeInherited(p,"calculateFallDamage",new Class<?>[]{double.class,float.class},p.fallDistance,1f));m.put("ignoring_impulse_fall_damage",p.isIgnoringFallDamageFromCurrentImpulse());m.put("collisions",List.of(p.horizontalCollision,p.verticalCollision,p.verticalCollisionBelow));m.put("support",String.valueOf(read(p,"mainSupportingBlockPos")));m.put("ground_no_blocks",read(p,"onGroundNoBlocks"));return m;
 }
 static Map<String,Object> event(String name,LocalPlayer p){try{return Map.of("phase",name,"history",history(p));}catch(Exception e){throw new RuntimeException(e);}}
 static void fallCorpus(HolderLookup.Provider lookup)throws Exception{
  JsonArray inputs=JsonParser.parseString(new String(Base64.getDecoder().decode(__FALL_INPUT__),java.nio.charset.StandardCharsets.UTF_8)).getAsJsonArray();
  for(JsonElement e:inputs)for(boolean observed:List.of(false,true)){
   JsonObject in=e.getAsJsonObject();Context c=new Context(lookup,observed);LocalPlayer p=c.player;c.keys(0);p.getAttribute(Attributes.STEP_HEIGHT).setBaseValue(0);p.getAbilities().flying=false;p.setPos(v3(in.getAsJsonArray("position_f64_bits")));p.setOnGround(in.get("ground").getAsBoolean());p.fallDistance=d(in.get("distance_f64_bits"));p.setDeltaMovement(Vec3.ZERO);
   if(in.get("world").getAsString().equals("wall")){c.level.blocks.put(new BlockPos(1,2,0),Blocks.STONE.defaultBlockState());c.level.blocks.put(new BlockPos(1,3,0),Blocks.STONE.defaultBlockState());}
   List<Map<String,Object>> steps=new ArrayList<>();
   for(JsonElement se:in.getAsJsonArray("steps")){
    JsonObject s=se.getAsJsonObject();String op=s.get("operation").getAsString();if(observed)((ObservedPlayer)p).fallPhases.clear();c.level.observations.clear();c.level.fallClips.clear();Map<String,Object> step=new TreeMap<>();step.put("before",history(p));step.put("input",s);
    try{
     switch(op){
      case "move":{
       p.noPhysics=s.has("no_physics")&&s.get("no_physics").getAsBoolean();Vec3 requested=v3(s.getAsJsonArray("requested_f64_bits"));
       if(!p.noPhysics){Vec3 resolved=(Vec3)invokeInherited(p,"collide",new Class<?>[]{Vec3.class},requested);step.put("direct_collision_f64_bits",vector(resolved));step.put("resolved_length_squared_f64_bits",bits(resolved.lengthSqr()));step.put("requested_length_squared_f64_bits",bits(requested.lengthSqr()));step.put("java_gate_diagnostic",resolved.lengthSqr()>1.0E-7 || requested.lengthSqr()-resolved.lengthSqr()<1.0E-7);}
       p.move(MoverType.SELF,requested);break;
      }
      case "check":invokeInherited(p,"checkFallDamage",new Class<?>[]{double.class,boolean.class,BlockState.class,BlockPos.class},d(s.get("resolved_y_f64_bits")),s.get("ground").getAsBoolean(),Blocks.STONE.defaultBlockState(),BlockPos.ZERO);break;
      case "reset":p.resetFallDistance();break;
      case "clamp":p.setDeltaMovement(new Vec3(0,d(s.get("velocity_y_f64_bits")),0));p.checkFallDistanceAccumulation();break;
      case "jump":p.jumpFromGround();break;
      default:throw new IllegalArgumentException("unknown operation");
     }
     step.put("ok",true);
    }catch(Throwable error){Throwable root=error;while(root.getCause()!=null)root=root.getCause();step.put("ok",false);step.put("error_class",root.getClass().getName());step.put("error_message",String.valueOf(root.getMessage()));}
    step.put("expected",history(p));step.put("phases",observed?List.copyOf(((ObservedPlayer)p).fallPhases):List.of());step.put("service_calls",new TreeMap<>(c.level.observations));step.put("clip_calls",List.copyOf(c.level.fallClips));steps.add(step);
   }
   output(Map.of("id",in.get("id").getAsString(),"observed",observed,"steps",steps));
  }
 }
'''
OBSERVER=r'''
  final List<Map<String,Object>> fallPhases=new ArrayList<>();
  protected void checkFallDamage(double y,boolean ground,BlockState state,BlockPos pos){if(fallPhases!=null)fallPhases.add(Map.of("phase","check_entry","resolved_y_f64_bits",bits(y),"ground",ground,"block",BuiltInRegistries.BLOCK.getKey(state.getBlock()).toString(),"history",safeHistory()));super.checkFallDamage(y,ground,state,pos);if(fallPhases!=null)fallPhases.add(event("check_exit",this));}
  public void recordMovement(MoverType mover,Vec3 resolved){if(fallPhases!=null)fallPhases.add(Map.of("phase","record_movement","resolved_f64_bits",vector(resolved),"history",safeHistory()));super.recordMovement(mover,resolved);}
  public void resetFallDistance(){if(fallPhases!=null)fallPhases.add(event("reset_entry",this));super.resetFallDistance();if(fallPhases!=null)fallPhases.add(event("reset_exit",this));}
  public void checkFallDistanceAccumulation(){if(fallPhases!=null)fallPhases.add(event("clamp_entry",this));super.checkFallDistanceAccumulation();if(fallPhases!=null)fallPhases.add(event("clamp_exit",this));}
  private Map<String,Object> safeHistory(){try{return history(this);}catch(Exception e){throw new RuntimeException(e);}}
'''

def sources(values):
    result=L.receiver_sources({});source=result[FIXTURE]
    needle='  final List<Map<String,Object>> calls=new ArrayList<>();';assert source.count(needle)==1;source=source.replace(needle,needle+OBSERVER)
    needle='  final Map<String,Integer> observations=new TreeMap<>();';assert source.count(needle)==1
    source=source.replace(needle,needle+r'''
  final List<Map<String,Object>> fallClips=new ArrayList<>();
  public BlockHitResult clip(ClipContext context){BlockHitResult result=super.clip(context);if(fallClips!=null)fallClips.add(Map.of("type",result.getType().toString(),"from_f64_bits",vector(context.getFrom()),"to_f64_bits",vector(context.getTo()),"block_pos",result.getBlockPos().toString()));return result;}
''')
    needle=' public static void run(String mode)throws Exception{';assert source.count(needle)==1
    encoded=base64.b64encode(canonical(values)).decode()
    input_expression='String.join("",new String[]{'+','.join(json.dumps(encoded[i:i+6144])for i in range(0,len(encoded),6144))+'})'
    source=source.replace(needle,HELPERS.replace('__FALL_INPUT__',input_expression)+'\n'+needle)
    needle='  if(mode.equals("corpus"))';assert source.count(needle)==1;source=source.replace(needle,'  if(mode.equals("fall-history")){fallCorpus(lookup);return;}\n'+needle)
    result[FIXTURE]=source;return result

def inventory():
    result={}
    with zipfile.ZipFile(CLIENT)as z:
        for owner in CLASSES:
            text=subprocess.run([str(JAVA.parent/'javap'),'-classpath',str(CLIENT),'-c','-p',owner],capture_output=True,text=True,check=True).stdout
            methods=[]
            for sig,body in re.findall(r'^  ((?:public|protected|private)[^\n]*?\([^\n]*\);)\n(.*?)(?=^  (?:public|protected|private|static)|\Z)',text,re.M|re.S):
                name=re.search(r'([\w$<>]+)\([^\n]*\);$',sig)
                if name and name[1]in METHODS:methods.append({'signature':sig,'bytecode_text_sha256':sha(body.encode()),'calls':sorted(set(re.findall(r'// (?:InterfaceMethod|Method) (.+)',body)))})
            entry=owner.replace('.','/')+'.class';result[owner]={'class_entry':entry,'class_sha256':sha(z.read(entry)),'bytecode_text_sha256':sha(text.encode()),'methods':methods}
    return result

def template_hashes():return {k:sha(v.encode())for k,v in L.RECEIVER_SOURCES.items()}
def source_hashes(values):return {k:sha(v.encode())for k,v in sources(values).items()}

def execute(values,label):
    paths,provenance=verified_client_classpath();ss=sources(values);payload={'sources':ss,'client_jar':str(CLIENT),'mode':'fall-history'}
    encoded=base64.b64encode(canonical(payload)).decode();launcher=L.RECEIVER_LAUNCHER.replace('Base64.getDecoder().decode(args[0])','Base64.getDecoder().decode(String.join("",new String[]{'+','.join(json.dumps(encoded[i:i+6144])for i in range(0,len(encoded),6144))+'}))',1)
    command=[str(JAVA),'--source','25','--class-path',':'.join(map(str,paths)),'/dev/stdin'];start=time.monotonic()
    process=subprocess.Popen(command,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,start_new_session=True)
    try:stdout,stderr=process.communicate(launcher,timeout=120)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid,signal.SIGKILL);stdout,stderr=process.communicate();raise RuntimeError('120s Java fall-history watchdog expired')
    rows=[json.loads(line[len('LOCAL_RECEIVER_JSON:'):])for line in stdout.splitlines()if line.startswith('LOCAL_RECEIVER_JSON:')]
    loaded=[json.loads(line[len('LOCAL_INPUT_CLASSES:'):])for line in stdout.splitlines()if line.startswith('LOCAL_INPUT_CLASSES:')]
    RAW.mkdir(parents=True,exist_ok=True);path=RAW/(label+'.full.json');write_json(path,{'observations':rows,'loaded_official_classes':loaded,'fixture_sources':ss,'launcher':launcher,'stdout':stdout,'stderr':stderr,'returncode':process.returncode,'command':command})
    assert process.returncode==0,('Java probe failed',process.returncode,str(path));assert len(loaded)==1 and len(rows)==2*len(values),'Missing actual observations'
    inv=inventory()
    for name in CLASSES:assert loaded[0][name]==inv[name]['class_sha256'],'Official receiver bytes mismatch: '+name
    fixtures=[]
    for value,a,b in zip(values,rows[::2],rows[1::2]):
        assert a['id']==b['id']==value['id'] and a['observed']is False and b['observed']is True
        assert len(a['steps'])==len(b['steps'])==len(value['steps'])
        f=dict(value);f['observations']=[]
        for plain,observed in zip(a['steps'],b['steps']):
            assert {k:v for k,v in plain.items()if k not in ['phases','service_calls']}=={k:v for k,v in observed.items()if k not in ['phases','service_calls']},'Super-calling observer changed actual history'
            f['observations'].append(observed)
        fixtures.append(f)
    summary={'schema':'player-fall-history-observation-summary-v1','status':'passed','scope':'Actual normal-constructor movement/history phase observations; no whole lifecycle or damage implementation claim.','raw_report':{'path':str(path.relative_to(ROOT)),**fingerprint(path)},'provenance':provenance,'source':inv,'fixture_template_sha256':template_hashes(),'fixture_source_sha256':source_hashes(values),'launcher_source_sha256':sha(L.RECEIVER_LAUNCHER.encode()),'producer':fingerprint(Path(__file__)),'boundary_producer':fingerprint(Path(L.__file__)),'observation_count':len(rows),'step_count':sum(len(r['steps'])for r in rows),'observations_sha256':sha(canonical(rows)),'fixtures_sha256':sha(canonical(fixtures)),'loaded_official_class_count':len(loaded[0]),'loaded_official_class_tree_sha256':sha(canonical(loaded[0])),'substituted_external_types':sorted(set(ss)-{FIXTURE}),'execution':{'command':command,'seconds':round(time.monotonic()-start,6),'returncode':process.returncode,'stdin_sha256':sha(launcher.encode()),'stdout_sha256':sha(stdout.encode()),'stderr_sha256':sha(stderr.encode()),'reproduce':f'PYTHONDONTWRITEBYTECODE=1 python3 tools/reference_player_fall_history_probe.py --{label}'}}
    write_json(ROOT/f'evidence/player-fall-history-reference-{label}.json',summary);return fixtures,summary

def verify_data(data,provenance,inv):
    assert data['schema']==1 and data['pin']=='26.3';assert data['provenance']==provenance,'Pinned runtime/library mismatch';assert data['source']==inv,'Pinned class/method mismatch';assert data['inputs']==inputs(),'Input corpus mismatch';assert data['fixture_template_sha256']==template_hashes(),'Normal-constructor template mismatch';assert data['fixture_source_sha256']==source_hashes(data['inputs']),'Expanded source mismatch';assert data['launcher_source_sha256']==sha(L.RECEIVER_LAUNCHER.encode()),'Launcher mismatch';assert data['fixtures_sha256']==sha(canonical(data['fixtures'])),'Fixture digest mismatch';assert len(data['fixtures'])==len(data['inputs'])
    path=ROOT/data['raw_report']['path'];assert {'path':data['raw_report']['path'],**fingerprint(path)}==data['raw_report'],'Raw integrity mismatch';raw=json.loads(path.read_text());assert data['raw_observations_sha256']==sha(canonical(raw['observations'])),'Observation digest mismatch';assert data['loaded_official_class_tree_sha256']==sha(canonical(raw['loaded_official_classes'][0])),'Loaded class tree mismatch'
    for f,v,a,b in zip(data['fixtures'],data['inputs'],raw['observations'][::2],raw['observations'][1::2]):
        assert f['id']==v['id']==a['id']==b['id'] and f['observations']==b['steps'],'Fixture is not actual observation'
        for plain,observed in zip(a['steps'],b['steps']):assert {k:v for k,v in plain.items()if k not in ['phases','service_calls']}=={k:v for k,v in observed.items()if k not in ['phases','service_calls']},'Observer parity mismatch'
    return data

def verify_existing(selftest=False):
    _,provenance=verified_client_classpath();inv=inventory();data=verify_data(json.loads(OUTPUT.read_text()),provenance,inv);result={'status':'passed','scope':'Stored reference integrity; no fresh Java run','reference':fingerprint(OUTPUT),'fixture_count':len(data['fixtures'])}
    if selftest:
        result['failure_injections']=[]
        for name,path in [('client',['provenance','client','sha256']),('runtime',['provenance','java','sha256']),('library',['provenance','libraries',0,'sha256']),('class',['source',CLASSES[0],'class_sha256']),('source',['launcher_source_sha256']),('observation',['fixtures',0,'observations',0,'expected','distance_f64_bits'])]:
            c=copy.deepcopy(data);target=c
            for k in path[:-1]:target=target[k]
            target[path[-1]]='injected-mismatch'
            try:verify_data(c,provenance,inv)
            except AssertionError as e:result['failure_injections'].append({'injection':name,'rejected':True,'reason':str(e)})
            else:raise AssertionError('Accepted corrupt reference: '+name)
    write_json(ROOT/'evidence/player-fall-history-reference-integrity.json',result);return result

def main():
    p=argparse.ArgumentParser();g=p.add_mutually_exclusive_group(required=True)
    for op in ['feasibility','extract','rerun','selftest','verify']:g.add_argument('--'+op,action='store_true')
    a=p.parse_args()
    if a.feasibility:_,r=execute(inputs()[:11],'feasibility')
    elif a.extract:
        v=inputs();f,r=execute(v,'extract');data={'schema':1,'pin':'26.3','inputs':v,'fixtures':f,'fixtures_sha256':sha(canonical(f)),'raw_observations_sha256':r['observations_sha256'],'raw_report':r['raw_report'],**{k:r[k]for k in ['provenance','source','fixture_template_sha256','fixture_source_sha256','launcher_source_sha256','loaded_official_class_count','loaded_official_class_tree_sha256']}};write_json(OUTPUT,data);r['reference']=fingerprint(OUTPUT);write_json(ROOT/'evidence/player-fall-history-reference-extract.json',r)
    elif a.rerun:
        verify_existing();old=json.loads(OUTPUT.read_text());f,r=execute(inputs(),'rerun');assert f==old['fixtures'],'Fresh independent fixture outputs differ';assert r['loaded_official_class_tree_sha256']==old['loaded_official_class_tree_sha256'],'Fresh class tree differs';r['independent_parity']=True;write_json(ROOT/'evidence/player-fall-history-reference-rerun.json',r)
    else:r=verify_existing(a.selftest)
    print(json.dumps({'status':r['status'],'fixture_count':r.get('fixture_count',r.get('observation_count',0)//2),'step_count':r.get('step_count'),'raw_report':r.get('raw_report'),'independent_parity':r.get('independent_parity'),'failure_injections':r.get('failure_injections')},sort_keys=True))
if __name__=='__main__':main()
