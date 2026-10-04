#!/usr/bin/env python3
"""Fresh normally constructed 26.3 scheduler snapshots; no host game oracle."""
from __future__ import annotations
import argparse, base64, copy, hashlib, json, os, random, re, signal, struct, subprocess, time, zipfile
from pathlib import Path
from reference_inventory import ROOT, JAVA, canonical, fingerprint, write_json
from reference_model_probe import CLIENT, verified_client_classpath
import reference_local_input_probe as L

OUTPUT = ROOT / 'reference/entity_common_tick.json'
RAW = ROOT / 'build/entity-common-tick-reference'
FIXTURE = 'net.minecraft.fixture.LocalInputReceiverFixture'
CLASSES = ['net.minecraft.world.entity.Entity', 'net.minecraft.world.entity.LivingEntity',
           'net.minecraft.world.entity.player.Player', 'net.minecraft.client.player.LocalPlayer',
           'net.minecraft.client.multiplayer.ClientLevel', 'net.minecraft.world.entity.InterpolationHandler',
           'net.minecraft.world.entity.AbstractInterpolationHandler', 'net.minecraft.world.entity.SteppedInterpolationHandler']
METHODS = {'commonTick', 'setOldPosAndRot', 'setOldPos', 'setOldRot', 'createInterpolationHandler',
           'getInterpolation', 'interpolate', 'hasActiveInterpolation', 'cancel', 'create'}

def sha(data): return hashlib.sha256(data).hexdigest()
def d(value): return value if isinstance(value, str) else struct.pack('>d', value).hex()
def f(value): return value if isinstance(value, str) else struct.pack('>f', value).hex()

def inputs():
    rows = []
    def add(name, position=(.5,1.,.5), rotation=(17.,-11.,12.,-9.), invulnerable=10,
            count=0, operations=('common_tick',), numeric=False,
            position_o=(7.,8.,9.), position_old=(-7.,-8.,-9.)):
        rows.append({'id':name, 'position_f64_bits':list(map(d,position)),
            'position_o_f64_bits':list(map(d,position_o)), 'position_old_f64_bits':list(map(d,position_old)),
            'rotation_f32_bits':list(map(f,rotation)), 'invulnerable_time_u32':invulnerable,
            'tick_count_u32':count, 'operations':list(operations), 'numeric_position_seed':numeric})
    for op in ['set_old_pos_and_rot','common_tick']:
        for invulnerable in [0,1,2,10,2147483647,2147483648,4294967295]:
            add(f'{op}/signed-invulnerability:{invulnerable}', invulnerable=invulnerable, operations=(op,))
        for count in [1,2147483646,2147483647,2147483648,4294967294,4294967295]:
            add(f'{op}/count:{count}',count=count,operations=(op,))
        add(op+'/signed-zero', position=('8000000000000000','0000000000000000','8000000000000000'),
            rotation=('80000000','00000000','00000000','80000000'), operations=(op,),
            position_o=('0000000000000000','8000000000000000','0000000000000000'))
        add(op+'/far-valid',position=(30000000.,-16000000.,-30000000.),operations=(op,))
        for i,values in enumerate([
            ('7fefffffffffffff','ffefffffffffffff','0000000000000001'),
            ('8000000000000001','0010000000000000','8010000000000000'),
            ('4340000000000000','c340000000000000','0000000000000000'),
        ]):
            add(f'{op}/raw-finite:{i}',position=values,numeric=True,operations=(op,),
                rotation=('7f7fffff','ff7fffff','00000001','80000001'),
                position_o=values[::-1],position_old=values)
    rng=random.Random(0x263ec7)
    def finite_word(bits, exponent_bits):
        while True:
            value=rng.getrandbits(bits)
            mask=((1<<exponent_bits)-1)<<(bits-exponent_bits-1)
            if value & mask != mask:return f'{value:0{bits//4}x}'
    for i in range(48):
        add(f'raw-finite-random:{i}', position=[finite_word(64,11) for _ in range(3)],
            position_o=[finite_word(64,11) for _ in range(3)],
            position_old=[finite_word(64,11) for _ in range(3)],
            rotation=[finite_word(32,8) for _ in range(4)],
            invulnerable=rng.getrandbits(32),count=rng.getrandbits(32),numeric=True,
            operations=('common_tick' if i%2 else 'set_old_pos_and_rot',))
    add('chain/common-5',invulnerable=3,count=4294967293,operations=('common_tick',)*5)
    add('chain/snapshot-common',invulnerable=2,count=2147483647,
        operations=('set_old_pos_and_rot','common_tick','set_old_pos_and_rot','common_tick'))
    add('chain/negative-int',invulnerable=2147483648,count=4294967295,operations=('common_tick',)*3)
    # Native extension failures contain nonfinite inputs and are not sent to
    # Java. Their explicitly repaired finite inputs are measured independently.
    base={'position':[.5,1.,.5],'position_o':[7.,8.,9.],
          'position_old':[-7.,-8.,-9.],'rotation':[17.,-11.,12.,-9.]}
    for field in range(13):
        value=copy.deepcopy(base)
        key=('position_o' if field<3 else 'position_old' if field<6 else
             'position' if field<9 else 'rotation')
        value[key][field if field<3 else field-3 if field<6 else field-6 if field<9 else field-9]=0.
        add('repair/field:'+str(field),**value)
    add('repair/owned-child',invulnerable=7,count=99,position_old=(0.,0.,0.))
    return rows

HELPERS = r'''
 static Map<String,Object> scheduler(LocalPlayer p)throws Exception{
  Map<String,Object> m=new TreeMap<>();m.put("position_f64_bits",vector(p.position()));
  m.put("position_o_f64_bits",List.of(bits(p.xo),bits(p.yo),bits(p.zo)));
  m.put("position_old_f64_bits",List.of(bits((double)read(p,"xOld")),bits((double)read(p,"yOld")),bits((double)read(p,"zOld"))));
  m.put("rotation_f32_bits",List.of(bits(p.getYRot()),bits(p.getXRot()),bits(p.yRotO),bits(p.xRotO)));
  m.put("invulnerable_time_u32",Integer.toUnsignedLong((int)read(p,"invulnerableTime")));
  m.put("tick_count_u32",Integer.toUnsignedLong(p.tickCount));
  m.put("client_side",p.level().isClientSide());m.put("interpolation_active",p.getInterpolation().hasActiveInterpolation());
  m.put("interpolation_handler",p.getInterpolation().getClass().getName());
  AABB b=p.getBoundingBox();m.put("body",Map.of("box",List.of(bits(b.minX),bits(b.minY),bits(b.minZ),bits(b.maxX),bits(b.maxY),bits(b.maxZ)),"velocity",vector(p.getDeltaMovement()),"width_f32_bits",bits(p.getBbWidth()),"height_f32_bits",bits(p.getBbHeight()),"flags",List.of(p.onGround(),p.horizontalCollision,p.verticalCollision,p.verticalCollisionBelow)));
  return m;
 }
 static void commonCorpus(HolderLookup.Provider lookup)throws Exception{
  JsonArray inputs=JsonParser.parseString(new String(Base64.getDecoder().decode(__COMMON_INPUT__),java.nio.charset.StandardCharsets.UTF_8)).getAsJsonArray();
  for(JsonElement e:inputs)for(boolean observed:List.of(false,true)){
   JsonObject in=e.getAsJsonObject();Context c=new Context(lookup,observed);LocalPlayer p=c.player;c.keys(0);
   Vec3 pos=v3(in.getAsJsonArray("position_f64_bits"));
   if(in.get("numeric_position_seed").getAsBoolean())seed(p,"position",pos);else p.setPos(pos);
   JsonArray o=in.getAsJsonArray("position_o_f64_bits"),old=in.getAsJsonArray("position_old_f64_bits"),a=in.getAsJsonArray("rotation_f32_bits");
   p.xo=d(o.get(0));p.yo=d(o.get(1));p.zo=d(o.get(2));seed(p,"xOld",d(old.get(0)));seed(p,"yOld",d(old.get(1)));seed(p,"zOld",d(old.get(2)));
   seed(p,"yRot",f(a.get(0)));seed(p,"xRot",f(a.get(1)));p.yRotO=f(a.get(2));p.xRotO=f(a.get(3));
   seed(p,"invulnerableTime",(int)in.get("invulnerable_time_u32").getAsLong());p.tickCount=(int)in.get("tick_count_u32").getAsLong();
   if(p.getInterpolation().hasActiveInterpolation())throw new IllegalStateException("Normal fixture handler unexpectedly active");
   List<Map<String,Object>> steps=new ArrayList<>();
   for(JsonElement operation:in.getAsJsonArray("operations")){
    if(observed)((ObservedPlayer)p).commonPhases.clear();Map<String,Object> row=new TreeMap<>();row.put("operation",operation.getAsString());row.put("before",scheduler(p));
    if(operation.getAsString().equals("common_tick"))p.commonTick();else if(operation.getAsString().equals("set_old_pos_and_rot"))p.setOldPosAndRot();else throw new IllegalArgumentException("unknown operation");
    row.put("expected",scheduler(p));row.put("phases",observed?List.copyOf(((ObservedPlayer)p).commonPhases):List.of());steps.add(row);
   }
   output(Map.of("id",in.get("id").getAsString(),"observed",observed,"steps",steps,"service_calls",c.level.observations,"outgoing_packet_classes",c.connection.sent));
  }
 }
'''
OBSERVER = r'''
  final List<Map<String,Object>> commonPhases=new ArrayList<>();
  void commonPhase(String label){if(commonPhases!=null)try{commonPhases.add(Map.of("phase",label,"snapshot",scheduler(this)));}catch(Exception e){throw new RuntimeException(e);}}
  protected void setOldPos(){commonPhase("old_position_entry");super.setOldPos();commonPhase("old_position_exit");}
  public void setOldRot(){commonPhase("old_rotation_entry");super.setOldRot();commonPhase("old_rotation_exit");}
'''

def sources(values):
    result=L.receiver_sources({});source=result[FIXTURE]
    needle='  final List<Map<String,Object>> calls=new ArrayList<>();';assert source.count(needle)==1
    source=source.replace(needle,needle+OBSERVER)
    needle=' public static void run(String mode)throws Exception{';assert source.count(needle)==1
    helper=HELPERS.replace('__COMMON_INPUT__',json.dumps(base64.b64encode(canonical(values)).decode()))
    source=source.replace(needle,helper+'\n'+needle)
    needle='  if(mode.equals("corpus"))';assert source.count(needle)==1
    source=source.replace(needle,'  if(mode.equals("entity-common-tick")){commonCorpus(lookup);return;}\n'+needle)
    result[FIXTURE]=source;return result

def inventory():
    result={};RAW.mkdir(parents=True,exist_ok=True)
    with zipfile.ZipFile(CLIENT) as jar:
        for owner in CLASSES:
            text=subprocess.run([str(JAVA.parent/'javap'),'-classpath',str(CLIENT),'-p','-c',owner],capture_output=True,text=True,check=True,timeout=20).stdout
            path=RAW/(owner.rsplit('.',1)[-1]+'.javap.txt');path.write_text(text)
            methods=[]
            for signature,body in re.findall(r'^  ((?:public|protected|private)[^\n]*?\([^\n]*\);)\n(.*?)(?=^  (?:public|protected|private|static)|\Z)',text,re.M|re.S):
                m=re.search(r'([\w$<>]+)\([^\n]*\);$',signature)
                if m and m[1] in METHODS:
                    methods.append({'signature':signature,'body_sha256':sha(body.encode()),'calls':re.findall(r'// (?:InterfaceMethod|Method) (.+)',body),'field_writes':re.findall(r'putfield[^\n]*// Field (.+)',body)})
            entry=owner.replace('.','/')+'.class'
            result[owner]={'class_entry':entry,'class_sha256':sha(jar.read(entry)),'javap':{'path':str(path.relative_to(ROOT)),**fingerprint(path)},'methods':methods}
    return result

def template_hashes():return {k:sha(v.encode()) for k,v in L.RECEIVER_SOURCES.items()}
def source_hashes(values):return {k:sha(v.encode()) for k,v in sources(values).items()}

def execute(values,label):
    paths,provenance=verified_client_classpath();ss=sources(values)
    payload={'sources':ss,'client_jar':str(CLIENT),'mode':'entity-common-tick'}
    encoded=base64.b64encode(canonical(payload)).decode()
    launcher=L.RECEIVER_LAUNCHER.replace('Base64.getDecoder().decode(args[0])','Base64.getDecoder().decode(String.join("",new String[]{'+','.join(json.dumps(encoded[i:i+6144])for i in range(0,len(encoded),6144))+'}))',1)
    command=[str(JAVA),'--source','25','--class-path',os.pathsep.join(map(str,paths)),'/dev/stdin']
    start=time.monotonic();p=subprocess.Popen(command,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,start_new_session=True)
    try:stdout,stderr=p.communicate(launcher,timeout=120)
    except subprocess.TimeoutExpired:
        os.killpg(p.pid,signal.SIGKILL);stdout,stderr=p.communicate();raise RuntimeError('120-second commonTick JVM watchdog expired')
    rows=[json.loads(line[len('LOCAL_RECEIVER_JSON:'):])for line in stdout.splitlines()if line.startswith('LOCAL_RECEIVER_JSON:')]
    loaded=[json.loads(line[len('LOCAL_INPUT_CLASSES:'):])for line in stdout.splitlines()if line.startswith('LOCAL_INPUT_CLASSES:')]
    RAW.mkdir(parents=True,exist_ok=True);raw=RAW/(label+'.full.json')
    write_json(raw,{'observations':rows,'loaded_official_classes':loaded,'fixture_sources':ss,'launcher':launcher,'command':command,'stdout':stdout,'stderr':stderr,'returncode':p.returncode})
    assert p.returncode==0,(p.returncode,stderr[-3000:],stdout[-3000:])
    assert len(loaded)==1 and len(rows)==2*len(values),'Missing actual observations/class map'
    inv=inventory()
    for name in CLASSES:assert loaded[0][name]==inv[name]['class_sha256'],name
    fixtures=[]
    for value,plain,observed in zip(values,rows[::2],rows[1::2]):
        assert plain['id']==observed['id']==value['id'] and plain['observed'] is False and observed['observed'] is True
        assert len(plain['steps'])==len(observed['steps'])==len(value['operations'])
        for a,b in zip(plain['steps'],observed['steps']):
            assert {k:v for k,v in a.items()if k!='phases'}=={k:v for k,v in b.items()if k!='phases'},'Observer changed scheduler result'
            assert a['before']['body']==a['expected']['body'],'commonTick changed current Body fields'
            assert a['before']['position_f64_bits']==a['expected']['position_f64_bits'],'Inactive commonTick changed current position'
            assert a['before']['client_side'] and not a['before']['interpolation_active'] and not a['expected']['interpolation_active']
            assert a['before']['interpolation_handler']=='net.minecraft.world.entity.SteppedInterpolationHandler'
            assert [x['phase']for x in b['phases']]==['old_position_entry','old_position_exit','old_rotation_entry','old_rotation_exit']
        fixtures.append({**value,'steps':observed['steps']})
    summary={'schema_version':1,'pin':'26.3','status':'actual_normal_constructor_scheduler_observed',
        'scope':'Exact old-position pairs/camera snapshots/signed countdown/counter only; inactive real client handler. No handler internals, active interpolation or Entity.tick implementation.',
        'raw_report':{'path':str(raw.relative_to(ROOT)),**fingerprint(raw)},'provenance':provenance,
        'source':inv,'fixture_template_sha256':template_hashes(),'fixture_source_sha256':source_hashes(values),
        'launcher_source_sha256':sha(L.RECEIVER_LAUNCHER.encode()),'producer':fingerprint(Path(__file__)),
        'boundary_producer':fingerprint(Path(L.__file__)),'observation_count':len(rows),
        'actual_case_count':len(values),'actual_step_count':sum(len(v['operations'])for v in values),
        'observations_sha256':sha(canonical(rows)),'fixtures_sha256':sha(canonical(fixtures)),
        'plain_super_observer_parity':True,'current_body_and_position_retained':True,
        'loaded_official_class_count':len(loaded[0]),'loaded_official_class_tree_sha256':sha(canonical(loaded[0])),
        'substituted_external_types':sorted(set(ss)-{FIXTURE}),
        'numeric_field_seed_boundary':'Raw finite numeric-position cases seed position after normal construction without rebuilding Box; these test metadata copying only, not physically coherent Body reachability. Ordinary cases call actual setPos.',
        'execution':{'command_prefix':command[:4]+['<pinned classpath>','/dev/stdin'],'classpath_entry_count':len(paths),
            'classpath_sha256':sha(os.pathsep.join(map(str,paths)).encode()),'seconds':round(time.monotonic()-start,6),
            'returncode':p.returncode,'stdin_sha256':sha(launcher.encode()),'stdout_sha256':sha(stdout.encode()),'stderr_sha256':sha(stderr.encode()),
            'reproduce':f'PYTHONDONTWRITEBYTECODE=1 python3 tools/reference_entity_common_tick_probe.py --{label}'}}
    write_json(ROOT/f'evidence/entity-common-tick-reference-{label}.json',summary)
    return fixtures,summary

def verify_data(data,provenance,inv):
    assert data['schema_version']==1 and data['pin']=='26.3'
    assert data['provenance']==provenance,'Pinned client/runtime/library provenance mismatch'
    assert data['source']==inv,'Pinned class/disassembly provenance mismatch'
    assert data['inputs']==inputs(),'Probe inputs changed'
    assert data['fixture_template_sha256']==template_hashes(),'Normal receiver template changed'
    assert data['fixture_source_sha256']==source_hashes(data['inputs']),'Expanded producer source changed'
    assert data['launcher_source_sha256']==sha(L.RECEIVER_LAUNCHER.encode()),'Launcher source changed'
    assert data['fixtures_sha256']==sha(canonical(data['fixtures'])),'Actual fixture digest mismatch'
    raw_path=ROOT/data['raw_report']['path'];assert {'path':data['raw_report']['path'],**fingerprint(raw_path)}==data['raw_report'],'Raw report mismatch'
    raw=json.loads(raw_path.read_text());assert data['raw_observations_sha256']==sha(canonical(raw['observations'])),'Raw observations mismatch'
    assert data['loaded_official_class_tree_sha256']==sha(canonical(raw['loaded_official_classes'][0])),'Loaded class tree mismatch'
    assert len(data['fixtures'])==len(data['inputs']) and len(raw['observations'])==2*len(data['inputs']),'Missing stored actual rows'
    for fixture,value,a,b in zip(data['fixtures'],data['inputs'],raw['observations'][::2],raw['observations'][1::2]):
        assert fixture['id']==value['id']==a['id']==b['id'] and fixture['steps']==b['steps'],'Fixture not actual observed output'
        assert [s['expected']for s in fixture['steps']]==[s['expected']for s in a['steps']],'Plain receiver differs'
    return data

def verify_existing(selftest=False):
    _,provenance=verified_client_classpath();data=verify_data(json.loads(OUTPUT.read_text()),provenance,inventory())
    result={'status':'passed','scope':'Stored reference integrity; no new target receiver execution',
        'reference':fingerprint(OUTPUT),'actual_case_count':len(data['fixtures']),'failure_injections':[]}
    if selftest:
        for name,path in [('client',['provenance','client','sha256']),('runtime',['provenance','java','sha256']),
            ('library',['provenance','libraries',0,'sha256']),('class',['source',CLASSES[0],'class_sha256']),
            ('source',['launcher_source_sha256']),('observation',['fixtures',0,'steps',0,'expected','tick_count_u32'])]:
            bad=copy.deepcopy(data);target=bad
            for key in path[:-1]:target=target[key]
            target[path[-1]]='injected-mismatch'
            try:verify_data(bad,provenance,data['source'])
            except AssertionError as error:result['failure_injections'].append({'injection':name,'rejected':True,'reason':str(error)})
            else:raise AssertionError('Accepted corrupt reference: '+name)
    write_json(ROOT/'evidence/entity-common-tick-reference-integrity.json',result);return result

def main():
    parser=argparse.ArgumentParser();group=parser.add_mutually_exclusive_group(required=True)
    for name in ['feasibility','extract','rerun','selftest','verify']:group.add_argument('--'+name,action='store_true')
    args=parser.parse_args()
    if args.feasibility:
        _,report=execute([inputs()[0],next(v for v in inputs()if v['id']=='common_tick/signed-invulnerability:10')], 'feasibility')
    elif args.extract:
        values=inputs();fixtures,report=execute(values,'extract')
        data={'schema_version':1,'pin':'26.3','inputs':values,'fixtures':fixtures,'fixtures_sha256':sha(canonical(fixtures)),
            'raw_observations_sha256':report['observations_sha256'],
            **{k:report[k]for k in ['raw_report','provenance','source','fixture_template_sha256','fixture_source_sha256','launcher_source_sha256','loaded_official_class_count','loaded_official_class_tree_sha256']}}
        write_json(OUTPUT,data);report['reference']=fingerprint(OUTPUT);write_json(ROOT/'evidence/entity-common-tick-reference-extract.json',report)
    elif args.rerun:
        verify_existing();old=json.loads(OUTPUT.read_text());fixtures,report=execute(inputs(),'rerun')
        assert fixtures==old['fixtures'],'Independent receiver outputs differ'
        assert report['loaded_official_class_tree_sha256']==old['loaded_official_class_tree_sha256'],'Independent loaded class tree differs'
        report['independent_parity']=True;write_json(ROOT/'evidence/entity-common-tick-reference-rerun.json',report)
    else:report=verify_existing(args.selftest)
    print(json.dumps({'status':report['status'],'actual_case_count':report.get('actual_case_count'),
        'actual_step_count':report.get('actual_step_count'),'independent_parity':report.get('independent_parity'),
        'failures_rejected':len(report.get('failure_injections',[])),'raw_report':report.get('raw_report')},sort_keys=True))

if __name__=='__main__':main()
