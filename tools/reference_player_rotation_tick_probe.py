#!/usr/bin/env python3
"""Pinned normal-constructor camera tick projection; no host gameplay oracle."""
from __future__ import annotations
import argparse, base64, copy, hashlib, json, os, random, re, signal, struct, subprocess, time, zipfile
from pathlib import Path
from reference_inventory import ROOT, JAVA, canonical, fingerprint, write_json
from reference_model_probe import CLIENT, verified_client_classpath
import reference_local_input_probe as L

OUTPUT=ROOT/'reference/player_rotation_tick.json'
RAW=ROOT/'build/player-rotation-tick-reference'
FIXTURE='net.minecraft.fixture.LocalInputReceiverFixture'
CLASSES=['net.minecraft.world.entity.Entity','net.minecraft.world.entity.LivingEntity','net.minecraft.world.entity.player.Player','net.minecraft.client.player.AbstractClientPlayer','net.minecraft.client.player.LocalPlayer','net.minecraft.client.multiplayer.ClientLevel']
METHODS={'commonTick','setOldRot','setOldPosAndRot','tick','aiStep','tickNonPassenger'}

def sha(b):return hashlib.sha256(b).hexdigest()
def bits(v):return struct.pack('>f',v).hex()
def word(v):return struct.unpack('>f',bytes.fromhex(v))[0]

def inputs():
    rows=[]
    def add(op,v,count=0):rows.append({'id':f'{op}:{len(rows)}','operation':op,'rotation_f32_bits':[x if isinstance(x,str) else bits(x) for x in v],'tick_count_u32':count})
    small=[[17,-11,12,-9],[0,0,720,-720],['80000000','00000000','00000000','80000000'],[524288,-524288,-1048576,1048576],[-524288,524288,1048576,-1048576],[179.99998474121094,-179.99998474121094,-360.125,360.125]]
    for op in ['set_old_rot','common_tick','ai_step']:
        for v in small:add(op,v)
    for count in [1,2147483646,2147483647,2147483648,4294967294,4294967295]:add('common_tick',[17,-11,12,-9],count)
    # ULP neighbours exercise strict < -180 and inclusive >= 180 separately.
    for current in [0.,17.,-11.,360.25,-360.25,524288.,-524288.]:
        for delta in [-720.125,-360.,-180.00001525878906,-180.,-179.99998474121094,179.99998474121094,180.,180.00001525878906,360.,720.125]:
            add('tick',[current,-current,current-delta,-current+delta])
    for v in small:add('tick',v)
    rng=random.Random(0x263ca)
    for _ in range(64):add('tick',[rng.uniform(-524288,524288),rng.uniform(-524288,524288),rng.uniform(-1048576,1048576),rng.uniform(-1048576,1048576)])
    for op in ['common_tick_then_tick','level_tick']:
        for v in small:add(op,v)
        for _ in range(10):add(op,[rng.uniform(-1000,1000),rng.uniform(-90,90),rng.uniform(-1048576,1048576),rng.uniform(-1048576,1048576)])
    # Keep the original 196 full-tick fixtures byte-for-byte and append only
    # safe snapshot paths, equal-angle full ticks, and standalone IEEE operators.
    huge = [
        ['7f7fffff','ff7fffff','00000001','80000001'],
        ['ff7fffff','7f7fffff','50000000','d0000000'],
        ['49000001','c9000001','49800001','c9800001'],
        ['5f000000','df000000','7f7fffff','ff7fffff'],
        ['00000001','80000001','7f7fffff','ff7fffff'],
    ]
    for op in ['set_old_rot','common_tick']:
        for v in huge:add(op,v,4294967295)
    for yaw,pitch in [('7f7fffff','ff7fffff'),('ff7fffff','7f7fffff'),
                      ('50000000','d0000000'),('d0000000','50000000'),
                      ('4f800000','cf800000'),('cf800000','4f800000'),
                      ('5f000000','df000000'),('00000001','80000001')]:
        add('huge_equal_tick',[yaw,pitch,yaw,pitch])
    for v in [
        ['7f7fffff','ff7fffff','ff7fffff','7f7fffff'],
        ['00000000','00000000','7f7fffff','ff7fffff'],
        ['00000000','00000000','50000000','d0000000'],
        ['00000000','00000000','50000001','d0000001'],
        ['00000000','00000000','4fffffff','cfffffff'],
        ['00000000','00000000','4f800000','cf800000'],
        ['50000000','d0000000','50000000','d0000000'],
        ['7f7fffff','ff7fffff','7f7fffff','ff7fffff'],
        ['4f800000','cf800000','4f800001','cf800001'],
        ['4f7fffff','cf7fffff','4f800000','cf800000'],
        ['4f800000','cf800000','4f7fffff','cf7fffff'],
        ['4ffffffe','cffffffe','4fffffff','cfffffff'],
        ['4fffffff','cfffffff','50000000','d0000000'],
        ['50000000','d0000000','50000001','d0000001'],
        ['00000001','80000001','00000001','80000001'],
    ]:add('float_step',v)
    return rows

HELPERS=r'''
 static Map<String,Object> camera(LocalPlayer p){return Map.of("rotation_f32_bits",List.of(bits(p.getYRot()),bits(p.getXRot()),bits(p.yRotO),bits(p.xRotO)),"tick_count_u32",Integer.toUnsignedLong(p.tickCount));}
 static Map<String,Object> numeric(float current,float previous){float difference=current-previous;float minus=previous-360f,plus=previous+360f;return Map.of("difference",bits(difference),"negative_needed",difference < -180f,"positive_needed",difference >= 180f,"minus360",bits(minus),"plus360",bits(plus),"minus_difference",bits(current-minus),"plus_difference",bits(current-plus),"minus_finished",current-minus>=-180f && current-minus<180f,"plus_finished",current-plus>=-180f && current-plus<180f);}
 static void rotationCorpus(HolderLookup.Provider lookup)throws Exception{
  JsonArray inputs=JsonParser.parseString(new String(Base64.getDecoder().decode(__ROTATION_INPUT__),java.nio.charset.StandardCharsets.UTF_8)).getAsJsonArray();
  for(JsonElement e:inputs)for(boolean observed:List.of(false,true)){
   JsonObject in=e.getAsJsonObject();Context c=new Context(lookup,observed);LocalPlayer p=c.player;c.keys(0);JsonArray a=in.getAsJsonArray("rotation_f32_bits");
   seed(p,"yRot",f(a.get(0)));seed(p,"xRot",f(a.get(1)));p.yRotO=f(a.get(2));p.xRotO=f(a.get(3));p.tickCount=(int)in.get("tick_count_u32").getAsLong();
   p.yHeadRot=p.getYRot();p.yHeadRotO=p.getYRot();p.yBodyRot=p.getYRot();p.yBodyRotO=p.getYRot();seed(p,"invulnerableTime",10);
   if(observed){((ObservedPlayer)p).calls.clear();((ObservedPlayer)p).rotationPhases.clear();}
   Map<String,Object> row=new TreeMap<>();row.put("id",in.get("id").getAsString());row.put("operation",in.get("operation").getAsString());row.put("observed",observed);row.put("before",camera(p));row.put("invulnerable_before",read(p,"invulnerableTime"));
   try{
    switch(in.get("operation").getAsString()){
     case "set_old_rot":p.setOldRot();break;
     case "common_tick":p.commonTick();break;
     case "ai_step":p.aiStep();break;
     case "tick":p.tick();break;
     case "huge_equal_tick":
      if(Float.floatToRawIntBits(p.getYRot())!=Float.floatToRawIntBits(p.yRotO)||Float.floatToRawIntBits(p.getXRot())!=Float.floatToRawIntBits(p.xRotO))throw new IllegalArgumentException("Huge unequal full ticks are forbidden in this probe");
      p.tick();break;
     case "float_step":row.put("numeric",Map.of("yaw",numeric(p.getYRot(),p.yRotO),"pitch",numeric(p.getXRot(),p.xRotO)));break;
     case "common_tick_then_tick":p.commonTick();row.put("after_common",camera(p));p.tick();break;
     case "level_tick":c.level.tickNonPassenger(p);break;
     default:throw new IllegalArgumentException("unknown probe operation");
    }
    row.put("ok",true);row.put("expected",camera(p));
   }catch(Throwable failure){Throwable root=failure;while(root.getCause()!=null)root=root.getCause();row.put("ok",false);row.put("error_class",root.getClass().getName());row.put("error_message",String.valueOf(root.getMessage()));}
   row.put("invulnerable_after",read(p,"invulnerableTime"));row.put("rotation_phases",observed?List.copyOf(((ObservedPlayer)p).rotationPhases):List.of());row.put("service_calls",c.level.observations);row.put("outgoing_packet_classes",c.connection.sent);output(row);
  }
 }
'''
OBSERVER=r'''
  final List<Map<String,Object>> rotationPhases=new ArrayList<>();
  public void aiStep(){if(rotationPhases!=null)rotationPhases.add(Map.of("phase","before_ai_step","camera",camera(this)));super.aiStep();if(rotationPhases!=null)rotationPhases.add(Map.of("phase","after_ai_step","camera",camera(this)));}
'''

def sources(values):
    result=L.receiver_sources({})
    source=result[FIXTURE]
    needle='  final List<Map<String,Object>> calls=new ArrayList<>();'
    assert source.count(needle)==1
    source=source.replace(needle,needle+OBSERVER)
    needle=' public static void run(String mode)throws Exception{'
    assert source.count(needle)==1
    helper=HELPERS.replace('__ROTATION_INPUT__',json.dumps(base64.b64encode(canonical(values)).decode()))
    source=source.replace(needle,helper+'\n'+needle)
    needle='  if(mode.equals("corpus"))'
    assert source.count(needle)==1
    source=source.replace(needle,'  if(mode.equals("rotation-tick")){rotationCorpus(lookup);return;}\n'+needle)
    result[FIXTURE]=source
    return result

def inventory():
    result={}
    with zipfile.ZipFile(CLIENT)as z:
        for owner in CLASSES:
            text=subprocess.run([str(JAVA.parent/'javap'),'-classpath',str(CLIENT),'-c','-p',owner],capture_output=True,text=True,check=True).stdout
            methods=[]
            for sig,body in re.findall(r'^  ((?:public|protected|private)[^\n]*?\([^\n]*\);)\n(.*?)(?=^  (?:public|protected|private|static)|\Z)',text,re.M|re.S):
                name=re.search(r'([\w$<>]+)\([^\n]*\);$',sig)
                if name and name[1]in METHODS:methods.append({'signature':sig,'bytecode_text_sha256':sha(body.encode()),'calls':sorted(set(re.findall(r'// (?:InterfaceMethod|Method) (.+)',body)))})
            entry=owner.replace('.','/')+'.class'
            result[owner]={'class_entry':entry,'class_sha256':sha(z.read(entry)),'bytecode_text_sha256':sha(text.encode()),'methods':methods}
    return result

def template_hashes():return {k:sha(v.encode())for k,v in L.RECEIVER_SOURCES.items()}
def source_hashes(values):return {k:sha(v.encode())for k,v in sources(values).items()}

def execute(values,label):
    for value in values:
        if value['operation'] in ['tick','common_tick_then_tick','level_tick']:
            assert all(abs(word(x))<=1048576 for x in value['rotation_f32_bits']), 'Huge unequal full tick rejected before launch'
        elif value['operation']=='huge_equal_tick':
            assert value['rotation_f32_bits'][:2]==value['rotation_f32_bits'][2:], 'Huge unequal full tick rejected before launch'
    paths,provenance=verified_client_classpath();ss=sources(values)
    payload={'sources':ss,'client_jar':str(CLIENT),'mode':'rotation-tick'}
    encoded=base64.b64encode(canonical(payload)).decode()
    launcher=L.RECEIVER_LAUNCHER.replace('Base64.getDecoder().decode(args[0])','Base64.getDecoder().decode(String.join("",new String[]{'+','.join(json.dumps(encoded[i:i+6144])for i in range(0,len(encoded),6144))+'}))',1)
    command=[str(JAVA),'--source','25','--class-path',':'.join(map(str,paths)),'/dev/stdin']
    start=time.monotonic();process=subprocess.Popen(command,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,start_new_session=True)
    try:stdout,stderr=process.communicate(launcher,timeout=120)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid,signal.SIGKILL);stdout,stderr=process.communicate();raise RuntimeError('120s Java camera probe watchdog expired')
    rows=[json.loads(line[len('LOCAL_RECEIVER_JSON:'):])for line in stdout.splitlines()if line.startswith('LOCAL_RECEIVER_JSON:')]
    loaded=[json.loads(line[len('LOCAL_INPUT_CLASSES:'):])for line in stdout.splitlines()if line.startswith('LOCAL_INPUT_CLASSES:')]
    RAW.mkdir(parents=True,exist_ok=True);path=RAW/(label+'.full.json')
    raw={'observations':rows,'loaded_official_classes':loaded,'fixture_sources':ss,'launcher':launcher,'stdout':stdout,'stderr':stderr,'returncode':process.returncode,'command':command}
    write_json(path,raw)
    assert process.returncode==0,(process.returncode,stderr[-3000:],stdout[-3000:])
    assert len(loaded)==1 and len(rows)==2*len(values),'Missing Java observations/class receipt'
    inv=inventory()
    for name in CLASSES:assert loaded[0][name]==inv[name]['class_sha256'],'Loaded official receiver bytes mismatch: '+name
    fixtures=[]
    for value,a,b in zip(values,rows[::2],rows[1::2]):
        assert a['id']==b['id']==value['id'] and a['observed']is False and b['observed']is True
        assert {k:v for k,v in a.items()if k not in ['observed','rotation_phases','service_calls','outgoing_packet_classes']}=={k:v for k,v in b.items()if k not in ['observed','rotation_phases','service_calls','outgoing_packet_classes']},'Observer changed camera tick result'
        assert a['ok'],'Actual receiver operation failed: '+str(a)
        assert a['before']=={'rotation_f32_bits':value['rotation_f32_bits'],'tick_count_u32':value['tick_count_u32']}
        f=dict(value);f['expected']=a['expected']
        if 'after_common'in a:f['after_common']=a['after_common']
        if 'numeric'in a:f['numeric']=a['numeric']
        if b['rotation_phases']:
            assert [p['phase']for p in b['rotation_phases']]==['before_ai_step','after_ai_step']
            f['before_ai_step']=b['rotation_phases'][0]['camera'];f['after_ai_step']=b['rotation_phases'][1]['camera']
        fixtures.append(f)
    summary={'schema':'player-rotation-tick-observation-summary-v1','status':'passed','scope':'Camera/count projection only; actual normal-constructor receivers with four declared external services. Whole lifecycle parity is not established.','raw_report':{'path':str(path.relative_to(ROOT)),**fingerprint(path)},'provenance':provenance,'source':inv,'fixture_template_sha256':template_hashes(),'fixture_source_sha256':source_hashes(values),'launcher_source_sha256':sha(L.RECEIVER_LAUNCHER.encode()),'producer':fingerprint(Path(__file__)),'boundary_producer':fingerprint(Path(L.__file__)),'observation_count':len(rows),'observations_sha256':sha(canonical(rows)),'fixtures_sha256':sha(canonical(fixtures)),'oracle_restriction':'Original bounded full-tick corpus unchanged; new huge full ticks require identical current/previous words. Huge unequal values invoke only snapshots or standalone Java F32 arithmetic, never full tick.','loaded_official_class_count':len(loaded[0]),'loaded_official_class_tree_sha256':sha(canonical(loaded[0])),'substituted_external_types':sorted(set(ss)-{FIXTURE}),'execution':{'command':command,'seconds':round(time.monotonic()-start,6),'returncode':process.returncode,'stdin_sha256':sha(launcher.encode()),'stdout_sha256':sha(stdout.encode()),'stderr_sha256':sha(stderr.encode()),'reproduce':f'PYTHONDONTWRITEBYTECODE=1 python3 tools/reference_player_rotation_tick_probe.py --{label}'}}
    write_json(ROOT/f'evidence/player-rotation-tick-reference-{label}.json',summary)
    return fixtures,summary

def verify_data(data,provenance,inv):
    assert data['schema']==1 and data['pin']=='26.3'
    assert data['provenance']==provenance,'Pinned runtime/library provenance mismatch'
    assert data['source']==inv,'Pinned class/method provenance mismatch'
    assert data['inputs']==inputs(),'Probe input corpus mismatch'
    assert data['fixture_template_sha256']==template_hashes(),'Normal constructor boundary template mismatch'
    assert data['fixture_source_sha256']==source_hashes(data['inputs']),'Expanded probe source mismatch'
    assert data['launcher_source_sha256']==sha(L.RECEIVER_LAUNCHER.encode()),'Receiver launcher changed'
    assert data['observations_sha256']==sha(canonical(data['fixtures'])),'Actual fixture digest mismatch'
    assert len(data['fixtures'])==len(data['inputs'])
    raw=json.loads((ROOT/data['raw_report']['path']).read_text())
    assert {'path':data['raw_report']['path'],**fingerprint(ROOT/data['raw_report']['path'])}==data['raw_report'],'Raw report integrity mismatch'
    assert data['raw_observations_sha256']==sha(canonical(raw['observations'])),'Raw observation digest mismatch'
    assert data['loaded_official_class_tree_sha256']==sha(canonical(raw['loaded_official_classes'][0])),'Class tree mismatch'
    for f,v,a,b in zip(data['fixtures'],data['inputs'],raw['observations'][::2],raw['observations'][1::2]):
        assert f['id']==v['id']==a['id']==b['id'] and f['expected']==a['expected']==b['expected'],'Checked fixture not actual receiver output'
        if 'numeric' in f:assert f['numeric']==a['numeric']==b['numeric'],'Standalone Java numeric observations differ'
        phases=b['rotation_phases']
        if phases:assert f['after_ai_step']==phases[1]['camera'] and f['before_ai_step']==phases[0]['camera'],'Observed aiStep phase mismatch'
    return data

def verify_existing(selftest=False):
    _,provenance=verified_client_classpath();inv=inventory();data=verify_data(json.loads(OUTPUT.read_text()),provenance,inv)
    result={'status':'passed','scope':'Stored reference/provenance integrity; no new Java execution','reference':fingerprint(OUTPUT),'fixture_count':len(data['fixtures'])}
    if selftest:
        result['failure_injections']=[]
        for name,path in [('client',['provenance','client','sha256']),('runtime',['provenance','java','sha256']),('library',['provenance','libraries',0,'sha256']),('class',['source',CLASSES[0],'class_sha256']),('source',['launcher_source_sha256']),('observation',['fixtures',0,'expected','tick_count_u32'])]:
            c=copy.deepcopy(data);target=c
            for k in path[:-1]:target=target[k]
            target[path[-1]]='injected-mismatch'
            try:verify_data(c,provenance,inv)
            except AssertionError as e:result['failure_injections'].append({'injection':name,'rejected':True,'reason':str(e)})
            else:raise AssertionError('Accepted corrupt reference: '+name)
    write_json(ROOT/'evidence/player-rotation-tick-reference-integrity.json',result);return result

def main():
    p=argparse.ArgumentParser();g=p.add_mutually_exclusive_group(required=True)
    for op in ['feasibility','extract','rerun','selftest','verify']:g.add_argument('--'+op,action='store_true')
    a=p.parse_args()
    if a.feasibility:
        v=inputs();chosen=[next(x for x in v if x['operation']==op)for op in ['set_old_rot','common_tick','ai_step','tick','common_tick_then_tick','level_tick','huge_equal_tick','float_step']];_,r=execute(chosen,'feasibility')
    elif a.extract:
        v=inputs();f,r=execute(v,'extract');data={'schema':1,'pin':'26.3','inputs':v,'fixtures':f,'observations_sha256':sha(canonical(f)),'raw_observations_sha256':r['observations_sha256'],'raw_report':r['raw_report'],**{k:r[k]for k in ['provenance','source','fixture_template_sha256','fixture_source_sha256','launcher_source_sha256','loaded_official_class_count','loaded_official_class_tree_sha256']}}
        write_json(OUTPUT,data);r['reference']=fingerprint(OUTPUT);write_json(ROOT/'evidence/player-rotation-tick-reference-extract.json',r)
    elif a.rerun:
        verify_existing();old=json.loads(OUTPUT.read_text());f,r=execute(inputs(),'rerun');assert f==old['fixtures'],'Independent Java fixture outputs differ';assert r['loaded_official_class_tree_sha256']==old['loaded_official_class_tree_sha256'],'Independent loaded class tree differs';r['independent_parity']=True;write_json(ROOT/'evidence/player-rotation-tick-reference-rerun.json',r)
    else:r=verify_existing(a.selftest)
    print(json.dumps({'status':r['status'],'fixture_count':r.get('fixture_count',r.get('observation_count',0)//2),'raw_report':r.get('raw_report'),'independent_parity':r.get('independent_parity'),'failure_injections':r.get('failure_injections')},sort_keys=True))
if __name__=='__main__':main()
