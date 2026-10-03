#!/usr/bin/env python3
"""Owned support sampling/update versus fresh actual Player.aiStep/support calls."""
from __future__ import annotations
import argparse, copy, hashlib, json, os, pathlib, re, struct
from reference_inventory import ROOT, JAVA, canonical, fingerprint
from reference_block_probe import verified_classpath
from reference_movement_probe import SOURCE as MOVE_SOURCE, DIRECT_SOURCE
from reference_travel_probe import SOURCE as TRAVEL_SOURCE, bits, fbits, block
from reference_player_tick_probe import SOURCE as TICK_SOURCE
from reference_support_probe import SOURCE as SUPPORT_SOURCE
from test_player_tick_world import inputs as tick_inputs
from test_player_tick import parse as player_parse
from test_travel import parse as body_parse, values
from test_travel_world import lines_by_kind, world_blocks
from test_geometry import run, sha
from test_client_world import run as run_env
BEND=pathlib.Path.home()/'.bend/bin/bend';BINARY=ROOT/'build/support-world-tests';TABLE=ROOT/'generated/reference_mth_sin.f32'
DEPS=['src/support.bend','src/player_tick_world.bend','src/player_tick.bend','src/travel_world.bend','src/travel.bend','src/locomotion.bend','src/movement.bend','src/client_world.bend','src/f64.bend','src/geometry.bend','src/core.bend','src/game.bend','src/registry.bend','src/client_render.bend','src/schedule.bend']

def java_source():
    s=TICK_SOURCE.replace('public class ReferencePlayerTickProbe','public class ReferenceSupportWorldProbe').replace('static final Gson JSON=new Gson();','static final Gson JSON=new GsonBuilder().serializeNulls().create();')
    s=s.replace('extends ReferenceTravelProbe.FixtureLevel','extends ReferenceSupportProbe.FixtureLevel').replace('extends ReferenceTravelProbe.FixturePlayer','extends ReferenceSupportProbe.FixturePlayer')
    s=s.replace('FixturePlayer(Level l){super(l);}',r'''final List<Map<String,Object>> supportCalls=new ArrayList<>();
  FixturePlayer(Level l){super(l);}
  public void setOnGroundWithMovement(boolean grounded,boolean horizontal,Vec3 movement){
   if(supportCalls!=null){Map<String,Object> call=new TreeMap<>();call.put("grounded",grounded);call.put("horizontal",horizontal);call.put("movement",movement==null?null:ReferenceMovementProbe.vectorBits(movement));supportCalls.add(call);}
   super.setOnGroundWithMovement(grounded,horizontal,movement);
  }''')
    s=s.replace('  List<Map<String,Object>> ticks=new ArrayList<>();','  ReferenceSupportProbe.seed(p,in.getAsJsonObject("initial_cache"));\n  List<Map<String,Object>> ticks=new ArrayList<>();')
    s=s.replace('   Map<String,Object> initial=tickState(p);',r'''   Map<String,Object> beforeCache=ReferenceSupportProbe.cache(p);level.sampling=true;
   Map<String,Object> beforeSample=ReferenceSupportProbe.samples(p,new JsonArray());
   BlockPos beforeBelow=p.getBlockPosBelowThatAffectsMyMovement();
   String beforeFriction=ReferenceTravelProbe.fb(level.getBlockState(beforeBelow).getBlock().getFriction());level.sampling=false;
   Map<String,Object> initial=tickState(p);''')
    s=s.replace('level.clearTrace();p.aiStep();','level.clearTrace();level.supporting.clear();p.supportCalls.clear();p.recorded=null;p.aiStep();')
    s=s.replace('o.put("full_player_ai_step_executed",true);','o.put("full_player_ai_step_executed",true);o.put("before_cache",beforeCache);o.put("before_sample",beforeSample);o.put("before_friction_f32_bits",beforeFriction);o.put("movement_recorded",p.recorded!=null);o.put("support_cache",ReferenceSupportProbe.cache(p));o.put("support_queries",List.copyOf(level.supporting));o.put("support_calls",List.copyOf(p.supportCalls));')
    # Only add observations and fixture adapters; aiStep, movement, support and sampling delegate to super.
    marker=' public static void main(String[]args)'
    a=s.index(marker)
    s=s[:a]+r'''
 static Map<String,Object> metadata(){ReferenceDirectMovementProbe.initialize();Map<String,Object> out=new TreeMap<>();for(Block b:List.of(Blocks.AIR,Blocks.STONE,Blocks.DIRT,Blocks.OAK_PLANKS)){var state=b.defaultBlockState();out.put(BuiltInRegistries.BLOCK.getKey(b).toString(),Map.of("friction",ReferenceTravelProbe.fb(b.getFriction()),"jump_factor",ReferenceTravelProbe.fb(b.getJumpFactor()),"fence",state.is(net.minecraft.tags.BlockTags.FENCES),"wall",state.is(net.minecraft.tags.BlockTags.WALLS),"gate",b instanceof FenceGateBlock));}return Map.of("id","metadata","properties",out);}
 public static void main(String[]args)throws Exception{SharedConstants.tryDetectVersion();Bootstrap.bootStrap();try(BufferedReader r=Files.newBufferedReader(Path.of(args[0]));PrintWriter w=new PrintWriter(Files.newBufferedWriter(Path.of(args[1])))){for(String line;(line=r.readLine())!=null;){JsonObject c=JsonParser.parseString(line).getAsJsonObject();String op=c.get("operation").getAsString();w.println(JSON.toJson(op.equals("metadata")?metadata():op.equals("support_history")?ReferenceSupportProbe.history(c):observe(c)));}if(w.checkError())throw new IOException("Write failed");}}
}
'''
    return s

def inputs():
    ticks=tick_inputs()
    for c in ticks:
        c['id']=c['id'].replace('tick-world-','support-world-');c['input']['initial_cache']={'main':None,'on_ground_no_blocks':False}
    # Native world is exactly the same declared 39-block W.fixture.
    histories=[]
    def add(label,pos,steps,main=None,flag=False):
        histories.append({'id':'support-world-history-'+label,'operation':'support_history','input':{'position':list(map(bits,pos)),'world_blocks':world_blocks(),'initial':{'main':main,'on_ground_no_blocks':flag},'steps':steps}})
    def step(pos=None,delta=None,ground=True,writes=()):
        out={'writes':list(writes),'grounded':ground,'horizontal':False,'movement':None if delta is None else list(map(bits,delta)),'offsets_f32_bits':[]}
        if pos is not None:out['position']=list(map(bits,pos))
        return out
    for x,z in [(1.,1.),(-1.,-1.),(-2.9,.5),(2.9,.5),(3.2,.5)]:add('seam-'+bits(x)+'-'+bits(z),(x,1.,z),[step(delta=(0.,0.,0.)),step(delta=None)])
    add('fallback-success',(3.5,1.,.5),[step(delta=(1.,0.,0.)),step(delta=(0.,0.,0.)),step(delta=None)],main=[2,0,0])
    add('fallback-null-zero',(3.5,1.,.5),[step(delta=None),step(delta=(1.,0.,0.)),step(delta=(0.,0.,0.)),step(ground=False),step(delta=(1.,0.,0.))],main=[2,0,0])
    add('no-blocks-history',(3.5,1.,.5),[step(delta=(1.,0.,0.)),step(pos=(2.5,1.,.5),delta=(0.,0.,0.))],main=[2,0,0],flag=True)
    add('queued-seam-removal',(1.,1.,1.),[step(delta=(0.,0.,0.)),step(delta=None,writes=[block([1,0,1],'minecraft:air')]),step(delta=(0.,0.,0.),writes=[block([0,0,1],'minecraft:air'),block([1,0,0],'minecraft:air'),block([0,0,0],'minecraft:air')]),step(delta=(0.,0.,0.),writes=[block([0,0,0],'minecraft:oak_planks')])])
    add('cached-air-sampling',(.5,1.,.5),[step(),step(writes=[block([0,0,0],'minecraft:air')]),step(delta=(0.,0.,0.)),step(writes=[block([0,0,0],'minecraft:dirt')])])
    add('negative-boundary',(-.5,1.,-.5),[step(),step(pos=(-.5,0.,-.5),delta=(-0.,-0.,-0.)),step(ground=False),step(pos=(-.5,1.,-.5),delta=(0.,0.,0.))])
    return ticks,histories

def observe(ticks,histories):
    jars,release=verified_classpath();work=ROOT/'build/support-world-oracle';work.mkdir(parents=True,exist_ok=True);sources=[]
    derived=java_source()
    for name,source in [('ReferenceMovementProbe',MOVE_SOURCE),('ReferenceDirectMovementProbe',DIRECT_SOURCE),('ReferenceTravelProbe',TRAVEL_SOURCE),('ReferencePlayerTickProbe',TICK_SOURCE),('ReferenceSupportProbe',SUPPORT_SOURCE),('ReferenceSupportWorldProbe',derived)]:
        p=work/(name+'.java');p.write_text(source);sources.append(p)
    cp=os.pathsep.join(map(str,jars));build=run([JAVA.parent/'javac','-cp',cp,'-d',work,*sources])
    incoming=work/'input.jsonl';outgoing=work/'output.jsonl';incoming.write_text(''.join(canonical(c).decode()+'\n' for c in [{'id':'metadata','operation':'metadata'},*ticks,*histories]))
    execution=run([JAVA,'-cp',str(work)+os.pathsep+cp,'ReferenceSupportWorldProbe',incoming,outgoing]);observed=list(map(json.loads,outgoing.read_text().splitlines()))
    metadata=observed.pop(0)['properties'];assert len(metadata)==4
    for name,v in metadata.items():assert v=={'friction':fbits(.6),'jump_factor':fbits(1.),'fence':False,'wall':False,'gate':False},(name,v)
    t=[{**c,**o} for c,o in zip(ticks,observed[:len(ticks)],strict=True)];h=[{**c,**o} for c,o in zip(histories,observed[len(ticks):],strict=True)]
    for c in t:
        for tick in c['ticks']:
            o=tick['observation'];assert o['full_player_ai_step_executed'] and len(o['support_calls'])==1
            assert o['support_calls'][0]['movement'] is not None
    provenance={'build':build,'execution':execution,'input_sha256':sha(incoming),'output_sha256':sha(outgoing),'java_sources_sha256':hashlib.sha256((MOVE_SOURCE+DIRECT_SOURCE+TRAVEL_SOURCE+TICK_SOURCE+SUPPORT_SOURCE+derived).encode()).hexdigest(),'pinned_classpath':[fingerprint(p) for p in jars],'runtime':fingerprint(JAVA),'release':release}
    return t,h,metadata,provenance

def words(value):
    if isinstance(value,str):return [int(value[:8],16),int(value[8:],16)]
    return [x for v in value for x in words(v)]
def u(value):return int(value,16) if isinstance(value,str) else int(value)&0xffffffff

def request(c,i,op):
    v=c['input'];tick=c['ticks'][i];o=tick['observation'];initial=o['initial'];a=o['attributes'];update=v['ticks'][i];s=v['initial_cache']
    sprint=v['sprinting']
    for up in v['ticks'][:i+1]:sprint=up.get('sprinting',sprint)
    f=[*words(initial['position']),*words(initial['velocity']),initial['flags'][0],*map(u,initial['input_f32_bits']),initial['jumping'],initial['jump_delay'],initial['jump_trigger'],initial['needs_sync'],u(initial['stored_speed_f32_bits']),u(initial['head_yaw_f32_bits']),*words(a['movement_speed']),*words(a['gravity']),*words(a['friction_modifier']),*words(a['air_drag_modifier']),u(v['yaw_f32_bits']),u(a['maximum_f32_bits']),sprint,v['no_gravity'],v['discard_friction'],*words(a['jump_strength']),'input_f32_bits' in update,'jumping' in update,s['main'] is not None,*(s['main'] or [0,0,0]),s['on_ground_no_blocks'],False,*words([bits(0.)]*3)]
    return '|'.join(map(str,[c['id']+':'+str(i),op,*map(u,f)]))

def raw_request(c,i,op):
    s=c['steps'][i]['observation'];inp=c['input'];step=inp['steps'][i];seed=inp['initial'];pos=s['position'];delta=step['movement'];dummy={'input':{'yaw_f32_bits':fbits(0.),'sprinting':False,'no_gravity':False,'discard_friction':False,'ticks':[{}],'initial_cache':seed},'id':c['id'],'ticks':[{'observation':{'initial':{'position':pos,'velocity':[bits(0.)]*3,'flags':[step['grounded']],'input_f32_bits':[fbits(0.)]*3,'jumping':False,'jump_delay':0,'jump_trigger':0,'needs_sync':False,'stored_speed_f32_bits':fbits(0.),'head_yaw_f32_bits':fbits(0.)},'attributes':{'movement_speed':bits(.1),'gravity':bits(.08),'friction_modifier':bits(1.),'air_drag_modifier':bits(1.),'maximum_f32_bits':fbits(.6),'jump_strength':bits(.42)}}}]}
    fields=request(dummy,0,op).split('|');fields[0]=c['id']+':'+str(i);fields[-7]=str(int(delta is not None));fields[-6:]=list(map(str,words(delta or [bits(0.)]*3)))
    return '|'.join(fields)

def support(line):
    _,_,p,flag=line.split('|');return {'main':None if p=='none' else [v-(1<<32) if v>=1<<31 else v for v in map(int,p.split(','))],'on_ground_no_blocks':bool(int(flag))}
def sample(line):
    _,_,p,friction,jump=line.split('|');return {'below':[v-(1<<32) if v>=1<<31 else v for v in map(int,p.split(','))],'friction':f'{int(friction):08x}','jump':f'{int(jump):08x}'}
def retained(lines,id):
    for kind in ['clock','view','body']:
        assert lines[id+'-before',kind].split('|')[2:]==lines[id+'-after',kind].split('|')[2:],(id,kind)
def query(lines,id,which):
    line=lines[id,which].split('|');return {'box':values(line[2:14]),'positions':[[v-(1<<32) if v>=1<<31 else v for v in map(int,p.split(','))] for p in line[14].split(';') if p]}
def validate_queries(lines,id,queries):
    for i,q in enumerate(queries):
        got=query(lines,id,'primary' if i==0 else 'fallback');assert got=={'box':q['box'],'positions':[v['position'] for v in q['candidates']]},(id,q,got)
    return len(queries)

def validate_ticks(cases):
    batches=[];queries=0
    for c in cases:
        args=[request(c,i,'start' if i==0 else 'chain') for i in range(len(c['ticks']))];r=run([BINARY,'--gpu','off',TABLE,*args]);lines=lines_by_kind(r['stdout'])
        for i,t in enumerate(c['ticks']):
            id=c['id']+':'+str(i);o=t['observation'];e=t['expected'];assert player_parse(lines[id,'state'])[1]==e,id
            assert player_parse(lines[id+'-before','state'])[1]==o['initial'],id
            assert support(lines[id,'support'])==o['support_cache'],(id,support(lines[id,'support']),o['support_cache'])
            got=sample(lines[id,'sample']);assert got=={'below':o['before_sample']['below'],'friction':o['before_friction_f32_bits'],'jump':o['before_sample']['jump_factor_f32_bits']},(id,got)
            assert body_parse(lines[id+'-after','body'])[1]=={k:e[k] for k in ['position','box','velocity','width_f32_bits','height_f32_bits','flags']},id
            for kind in ['clock','view']:assert lines[id+'-before',kind].split('|')[2:]==lines[id+'-after',kind].split('|')[2:],(id,kind)
            assert values(lines[id,'transition'].split('|')[2:8])==o['support_calls'][0]['movement'],id
            assert bool(int(lines[id,'transition'].split('|')[-1]))==o['movement_recorded'],id
            queries+=validate_queries(lines,id,o['support_queries'])
        batches.append({'id':c['id'],'ticks':len(c['ticks']),'seconds':r['seconds'],'application_gate_rejections':sum(not t['observation']['movement_recorded'] for t in c['ticks']),'native_step_outcomes':sum(bool(int(lines[c['id']+':'+str(i),'transition'].split('|')[-2])) for i in range(len(c['ticks'])))})
    return batches,queries

def edits(c,i):
    names={'minecraft:air':0,'minecraft:stone':1,'minecraft:dirt':2,'minecraft:oak_planks':3}
    return ['|'.join(map(str,[c['id']+'-edit-'+str(i)+'-'+str(k),'edit',*[u(v) for v in b['position']],names[b['identifier']]])) for k,b in enumerate(c['input']['steps'][i]['writes'])]
def validate_histories(cases):
    batches=[];queries=0
    for c in cases:
        args=[]
        for i in range(len(c['steps'])):args+=edits(c,i)+[raw_request(c,i,'raw-start' if i==0 else 'raw')]
        r=run([BINARY,'--gpu','off',TABLE,*args]);lines=lines_by_kind(r['stdout'])
        for i,t in enumerate(c['steps']):
            id=c['id']+':'+str(i);o=t['observation'];e=t['expected'];retained(lines,id)
            assert support(lines[id,'support'])==e['cache'],(id,support(lines[id,'support']),e['cache'])
            got=sample(lines[id,'sample']);assert got['below']==e['samples']['below'] and got['jump']==e['samples']['jump_factor_f32_bits'] and got['friction']==fbits(.6),(id,got,e)
            queries+=validate_queries(lines,id,o['queries'])
        batches.append({'id':c['id'],'updates':len(c['steps']),'seconds':r['seconds']})
    return batches,queries

def validate_rejections(base):
    reports=[]
    def run_case(label,commands,error,recover_kind='sample',recover_id='recovered'):
        r=run([BINARY,'--gpu','off',TABLE,*commands]);lines=lines_by_kind(r['stdout']);retained(lines,label)
        if (label,'support') in lines:assert support(lines[label,'support'])==base['steps'][0]['expected']['cache'],label
        err=lines[label,'error'] if (label,'error') in lines else lines[label,'sample-error'];assert err.split('|',2)[2].startswith(error),(label,err)
        assert sample(lines[recover_id,recover_kind])['friction']==fbits(.6)
        reports.append({'case':label,'error':err.split('|',2)[2],'continued_same_world':True})
    for label,change,error in [
        ('invalid-movement',lambda c:c['input']['steps'][0].__setitem__('movement',['7ff8000000000123',bits(0.),bits(0.)]),'invalid-support-movement:'),
        ('invalid-position',lambda c:c['steps'][0]['observation'].__setitem__('position',['7ff8000000000123',bits(1.),bits(1.)]),'invalid-support-position:'),
        ('missing-query',lambda c:c['steps'][0]['observation'].__setitem__('position',list(map(bits,[32.5,1.,.5]))),'missing-section:')]:
        c=copy.deepcopy(base);c['id']=label;change(c);id=label+':0';recovery=copy.deepcopy(base);recovery['id']='recovered'
        run_case(id,[raw_request(base,0,'raw-start'),raw_request(c,0,'raw'),raw_request(recovery,0,'raw')],error,recover_id='recovered:0')
    for label,where,seed,error in [
        ('unsupported-cached',[0,0,0],[0,0,0],'unsupported-block-state:'),
        ('unsupported-current',[0,1,0],None,'unsupported-block-state:'),
        ('unsupported-below',[0,0,0],None,'unsupported-block-state:'),
        ('missing-cached',[32,0,0],[32,0,0],'missing-section:')]:
        c=copy.deepcopy(base);c['id']=label;c['input']['initial']={'main':seed,'on_ground_no_blocks':False};c['steps'][0]['observation']['position']=list(map(bits,[.5,1.,.5]));id=label+':0'
        cmd=[raw_request(base,0,'raw-start')]
        if not label.startswith('missing'):cmd+=['|'.join(map(str,['write','edit',*where,4]))]
        cmd += [raw_request(c,0,'sample-position')]
        if not label.startswith('missing'):cmd+=['|'.join(map(str,['repair','edit',*where,0 if where[1]==1 else 1]))]
        recovery=copy.deepcopy(c);recovery['id']='recovered';recovery['input']['initial']['main']=None
        cmd += [raw_request(recovery,0,'sample-position')];run_case(id,cmd,error,recover_id='recovered:0')
    c=copy.deepcopy(base);c['id']='unsupported-query';recovery=copy.deepcopy(base);recovery['id']='recovered'
    run_case('unsupported-query:0',[raw_request(base,0,'raw-start'),'write|edit|1|0|1|4',raw_request(c,0,'raw'),'repair|edit|1|0|1|1',raw_request(recovery,0,'raw')],'unsupported-block-state:',recover_id='recovered:0')
    run_case('mismatch',[raw_request(base,0,'raw-start'),'mismatch|mismatch','recovered|sample'],'support-body-mismatch')
    r=run([BINARY,'--gpu','off',TABLE,raw_request(base,0,'raw-start'),'no-palette|no-palette']);lines=lines_by_kind(r['stdout']);retained(lines,'no-palette');assert lines['no-palette','sample-error'].endswith('|support-palette-unavailable');reports.append({'case':'no-palette','error':'support-palette-unavailable','continued_world_report':True})
    # Trusted low-level edit does not update revision or render cache; support reads
    # current Core cells directly. The render caller must still invalidate cache.
    c=copy.deepcopy(base);c['id']='raw-observe';c['steps'][0]['observation']['position']=list(map(bits,[.5,1.,.5]));c['input']['initial']={'main':[0,0,0],'on_ground_no_blocks':False}
    seed=copy.deepcopy(c);seed['id']='raw-seed'
    r=run([BINARY,'--gpu','off',TABLE,raw_request(seed,0,'sample-position'),'raw-remove|raw-edit|0|0|0|0','raw-read|sample',raw_request(c,0,'raw'),'raw-restore|raw-edit|0|0|0|1','raw-recovered|sample']);lines=lines_by_kind(r['stdout']);retained(lines,'raw-read');retained(lines,'raw-observe:0');assert support(lines['raw-observe:0','support'])=={'main':None,'on_ground_no_blocks':True};assert lines['raw-remove','clock'].split('|')[2:]==lines['raw-restore','clock'].split('|')[2:];assert lines['raw-remove','view'].split('|')[2:]==lines['raw-restore','view'].split('|')[2:];assert sample(lines['raw-recovered','sample'])['friction']==fbits(.6)
    # Same reading operator while the world is running retains clocks/paused flag.
    r=run([BINARY,'--gpu','off',TABLE,'unpause|running',raw_request(base,0,'raw-start')]);lines=lines_by_kind(r['stdout']);retained(lines,base['id']+':0');assert lines[base['id']+':0-before','clock'].split('|')[4]=='0'
    return reports

def main():
    p=argparse.ArgumentParser();p.add_argument('--skip-build',action='store_true');p.add_argument('--oracle-only',action='store_true');args=p.parse_args()
    ticks,histories,metadata,provenance=observe(*inputs())
    (ROOT/'evidence/support-world-reference.json').write_text(json.dumps({'schema_version':1,'status':'observed','properties':metadata,'ticks':ticks,'histories':histories,'provenance':provenance},sort_keys=True,indent=2)+'\n')
    if args.oracle_only:return
    generations={p:sha(ROOT/p) for p in ['src/support_world.bend','tests/support_world.bend',*DEPS]};checks=[run([BEND,p,'--check-only']) for p in ['src/support_world.bend','tests/support_world.bend']]
    if args.skip_build:
        prior=json.loads((ROOT/'build/support-world-build.json').read_text());assert prior['binary_sha256']==sha(BINARY) and prior['sources_sha256']==generations;builds=prior['builds']
    else:
        builds=[run([BEND,'tests/support_world.bend','-o',BINARY],timeout=600)];(ROOT/'build/support-world-build.json').write_text(json.dumps({'binary_sha256':sha(BINARY),'sources_sha256':generations,'builds':builds},indent=2)+'\n')
    batches,q=validate_ticks(ticks);raw,rq=validate_histories(histories)
    rejections=validate_rejections(histories[0])
    remap=ROOT/'build/support-world-oracle/palette.tsv';names=['minecraft:oak_planks','minecraft:stone','minecraft:air','minecraft:dirt'];remap.write_text('block_protocol_id\tidentifier\tfirst_state_id\tstate_count\tdefault_state_id\tordered_properties_json\n'+''.join(f'{i}\t{name}\t{i}\t1\t{i}\t[]\n' for i,name in enumerate(names)));env=os.environ.copy();env['MC_BLOCK_REGISTRY']=str(remap);c=ticks[0];r=run_env([BINARY,'--gpu','off',TABLE,request(c,0,'start')],env=env);lines=lines_by_kind(r['stdout']);assert support(lines[c['id']+':0','support'])==c['ticks'][0]['observation']['support_cache'];assert lines[c['id']+':0-before','view'].split('|')[4]=='2,1,3,0'
    for p,h in generations.items():assert sha(ROOT/p)==h,('dependency generation changed',p)
    source=(ROOT/'src/support_world.bend').read_text();assert not re.search(r'@unsafe|\bimport\s+[\"\']|\w!\(',source)
    e={'schema_version':1,'status':'passed','actual_player_ai_step_calls':sum(len(c['ticks']) for c in ticks),'actual_support_history_updates':sum(len(c['steps']) for c in histories),'ordered_support_queries_compared':q+rq,'fixture_blocks':39,'checked_fixture_mutations':47,'native_tick_sequences':batches,'native_support_histories':raw,'rejections':rejections,'same_owner_recoveries':sum(r.get('continued_same_world',False) for r in rejections),'running_clock_unchanged':True,'low_level_revision_bypass_observed':True,'dynamic_registry_remap':True,'clock_and_view_unchanged':True,'actual_block_properties':metadata,'builds':builds,'checks':checks,'provenance':provenance,'sources_sha256':{**generations,'tools/test_support_world.py':sha(ROOT/'tools/test_support_world.py'),'docs/SUPPORT_WORLD.md':sha(ROOT/'docs/SUPPORT_WORLD.md'),'tools/reference_support_probe.py':sha(ROOT/'tools/reference_support_probe.py'),'tools/reference_player_tick_probe.py':sha(ROOT/'tools/reference_player_tick_probe.py'),'tools/reference_travel_probe.py':sha(ROOT/'tools/reference_travel_probe.py'),'tools/reference_movement_probe.py':sha(ROOT/'tools/reference_movement_probe.py')},'binary_sha256':sha(BINARY),'table':fingerprint(TABLE),'ordinary_ownership_laws':re.findall(r'^law (\w+):',source,re.M),'successful_moves_without_position_application':sum(b['application_gate_rejections'] for b in batches),'native_step_outcomes':sum(b['native_step_outcomes'] for b in batches),'compiler':fingerprint(BEND),'compiler_version':run([BEND,'version']),'native_build_timeout_seconds':600,'whole_module_kernel_verified':False,'scope':['four dynamically mapped air/stone/dirt/oak_planks states','actual full-cube support candidates and ordered primary/fallback reads','local-authoritative neutral movement; support updated even without position application','support history retained natively through chained actual aiStep projections','friction/jump sample resolved before PW preparation, support after its successful returned movement','operator advances no clocks and changes no Core sections; queued edits are explicit fixture setup'],'confidence':'high within the declared finite neutral four-state world; complete Entity/Player/server tick is outside scope'}
    (ROOT/'evidence/support-world-verification.json').write_text(json.dumps(e,sort_keys=True,indent=2)+'\n');print(json.dumps({k:e[k] for k in ['status','actual_player_ai_step_calls','actual_support_history_updates','ordered_support_queries_compared','confidence']},indent=2))
if __name__=='__main__':main()
