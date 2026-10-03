#!/usr/bin/env python3
"""Execute pinned Java blockstate codecs and compare the pure native Bend API."""
from __future__ import annotations
import argparse
import copy
import hashlib
import json
import re
from pathlib import Path
import subprocess
import time
import reference_model_probe as probe

ROOT=Path(__file__).resolve().parents[1]
BEND=Path('/Users/chuah/.bend/bin/bend')
BIN=ROOT/'build/blockstate-model-tests'
DIR=ROOT/'build/blockstate-model-oracle'
REF=ROOT/'reference/model_semantics.json'
DIGIT_ZEROS=[48,1632,1776,1984,2406,2534,2662,2790,2918,3046,3174,3302,3430,3558,
             3664,3792,3872,4160,4240,6112,6160,6470,6608,6784,6800,6992,7088,7232,7248,
             42528,43216,43264,43472,43504,43600,44016,65296]

def sha(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def inputs():
    original=json.loads(REF.read_text())['inputs']
    data={k:copy.deepcopy(original[k]) for k in ['blockstates','selector_cases','condition_cases','dispatcher_cases']}
    data.update(models={},variants=[],parse_cases=[],graph_cases=[])
    data['schema_blocks']=list(data['blockstates'])+['wheat']
    def selector(block,key):data['selector_cases'].append({'id':f'edge_selector_{len(data["selector_cases"])}','block':block,'selector':key})
    def condition(block,value):data['condition_cases'].append({'id':f'edge_condition_{len(data["condition_cases"])}','block':block,'condition':value})
    def dispatcher(value,block='oak_fence',raw=None):
        data['dispatcher_cases'].append({'id':f'edge_dispatcher_{len(data["dispatcher_cases"])}','block':block,
            'json':json.dumps(value,separators=(',',':')) if raw is None else raw})
    one={'model':'minecraft:block/stone'}
    for key in [',',',,','=x','facing=north,,half=top','facing=north,half=top,',
                'facing=bad,facing=north','facing=north,facing=bad','facing=north,half',
                'facing=north,half=','facing=north,half=top=bad','facing=NORTH','facing=north ']:
        selector('oak_stairs',key)
    for key in ['age=0','age=+1','age=01','age=-0','age=١','age=１','age=2147483648','age=1.0','age= 1','age=8']:
        selector('wheat',key)
    for zero in DIGIT_ZEROS:
        for value in range(10):selector('wheat','age='+chr(zero+value))
    for value in ['true|','|true','true||false','!','!!true',' true','TRUE',1,1.9,4294967297,-0.9,True,False]:
        condition('oak_fence',{'north':value})
    for value in ['true|false|bad','!true|!false|bad','false|bad','bad|true|false']:
        condition('oak_fence',{'north':value})
    for value in ['+1','01','١','１',1,1.9,4294967297,'!1|2','!0|!1','0|1|2|3|4|5|6|7','8']:
        condition('wheat',{'age':value})
    for value in [{'AND':[],'OR':[]},{'OR':True},{'AND':'true'},{'OR':[{'AND':[]}]},
                  {'or':[{'north':'true'}]},{'north':'true','east':'false'},
                  {'north':'true','missing':'false'},{'OR':None},{'OR':{}},
                  {'north':None},{'OR':[{}, {'north':'true'}]}]:
        condition('oak_fence',value)
    for field,values in [('model',[True,1,None,[],{},'','Minecraft:block/stone']),
                         ('x',[90.9,-90,360,4294967386,2147483648,'90',True,None]),
                         ('uvlock',[True,False,1,0,'true',None])]:
        for value in values:dispatcher({'variants':{'':dict(one,**{field:value})}})
    for value in [None,{},[],0,True,'x']:
        dispatcher({'variants':value})
        dispatcher({'variants':{'':one},'multipart':value})
    for value in [0,-1,1,1.9,4294967297,2147483647,2147483648,'2',True,None]:
        dispatcher({'variants':{'':[dict(one,weight=value)]}})
    dispatcher({'variants':{'':dict(one,weight={'ignored':'value'})}})
    dispatcher({'multipart':[{'when':None,'apply':one}]})
    dispatcher({'variants':{'':one},'multipart':[{'when':{'missing':'true'},'apply':one}]})
    dispatcher({'variants':{'north=bad':one}})
    dispatcher({'variants':{'':one,'north=bad':{'model':'block/dirt'}}})
    dispatcher({'variants':{'':one,'north=true':{'model':'block/dirt'}}})
    dispatcher({'variants':{'north=true':one,'':{'model':'block/dirt'}}})
    dispatcher({'variants':{'':one,'north=true':{'model':'block/dirt'},'east=false':{'model':'block/glass'}}})
    dispatcher({'variants':{'north=true':one},'multipart':[{'apply':{'model':'block/dirt'}}]})
    dispatcher({'multipart':[{'when':{'north':'false'},'apply':one},
                             {'when':{'north':'true'},'apply':{'model':'block/dirt'}}]})
    dispatcher({},raw='{"variants":{"":{"model":"block/stone"},"north=true":{"model":"block/glass"},"":{"model":"block/dirt"}}}')
    dispatcher({},raw='{"variants":{"":{"model":"block/stone"}}} trailing')
    data['ticket_cases']=[
        {'id':'nonuniform_1_3','value':[dict(one,weight=1),dict(one,weight=3,y=90)],'tickets':list(range(4))},
        {'id':'nonuniform_2_1_4','value':[dict(one,weight=2),dict(one,weight=1,y=90),dict(one,weight=4,y=180)],'tickets':list(range(7))},
        {'id':'unit_weights','value':[one,dict(one,y=90)],'tickets':[0,1]},
        {'id':'equal_weights_3','value':[dict(one,weight=3),dict(one,weight=3,y=90)],'tickets':list(range(6))},
        {'id':'singleton_weight_3','value':[dict(one,weight=3)],'tickets':list(range(3))},
        {'id':'single_ignored_weight','value':dict(one,weight=-7),'tickets':[0]},
    ]
    return data

EXTRA_JAVA=r'''
 @SuppressWarnings({"rawtypes","unchecked"})
 static JsonObject schema(String name)throws Exception {
  var b=block(name);var d=b.getStateDefinition();var out=new JsonObject();var properties=new JsonObject();
  for(var pp:d.getProperties()){net.minecraft.world.level.block.state.properties.Property p=pp;var v=new JsonObject();
   v.addProperty("integer",p.getValueClass()==Integer.class);var values=new JsonArray();
   for(var value:p.getPossibleValues())values.add(p.getName((Comparable)value));v.add("values",values);properties.add(p.getName(),v);}
  out.addProperty("owner",b.toString());out.add("properties",properties);var states=new JsonArray();
  for(var state:d.getPossibleStates()){var s=new JsonObject();s.addProperty("id",Block.getId(state));var values=new JsonObject();
   for(var pp:d.getProperties()){net.minecraft.world.level.block.state.properties.Property p=pp;values.addProperty(p.getName(),p.getName(state.getValue(p)));}
   s.add("properties",values);states.add(s);}out.add("states",states);return out;
 }
 static JsonElement resourceTree(String text)throws Exception {
  return net.minecraft.util.GsonHelper.fromJson(G,new StringReader(text),JsonElement.class);
 }
 static JsonObject ticketCase(JsonObject input)throws Exception {
  var tree=new JsonObject();var variants=new JsonObject();variants.add("",input.get("value"));tree.add("variants",variants);
  var def=BlockStateModelDispatcher.CODEC.parse(JsonOps.INSTANCE,tree).getOrThrow();
  var model=def.simpleModels().get().models().get("");var out=new JsonObject();out.addProperty("id",input.get("id").getAsString());out.add("model",desc(model));var selected=new JsonArray();
  for(var t:input.getAsJsonArray("tickets")){int ticket=t.getAsInt();var calls=new JsonArray();
   var rng=(net.minecraft.util.RandomSource)java.lang.reflect.Proxy.newProxyInstance(net.minecraft.util.RandomSource.class.getClassLoader(),new Class<?>[]{net.minecraft.util.RandomSource.class},(proxy,method,args)->{
    if(method.getName().equals("nextInt")&&args.length==1){int bound=(Integer)args[0];if(ticket<0||ticket>=bound)throw new IllegalArgumentException("Ticket outside actual bound "+bound);calls.add(bound);return ticket;}
    throw new IllegalStateException("Unexpected RNG call "+method.getName());});
   var entry=new JsonObject();entry.addProperty("ticket",ticket);entry.add("calls",calls);
   entry.add("selected",desc(model instanceof WeightedVariants.Unbaked w?w.entries().getRandom(rng):model));selected.add(entry);
  }out.add("selected",selected);return out;
 }
'''

def oracle(data):
    DIR.mkdir(parents=True,exist_ok=True)
    source=probe.JAVA_SOURCE.replace('class ReferenceModelProbe {','class ReferenceModelProbe {'+EXTRA_JAVA)
    old='BlockStateModelDispatcher.CODEC.parse(JsonOps.INSTANCE,JsonParser.parseString(s))'
    assert source.count(old)==1
    source=source.replace(old,'BlockStateModelDispatcher.CODEC.parse(JsonOps.INSTANCE,resourceTree(s))')
    old='o.addProperty("mapped",root!=null);if(root!=null){'
    assert source.count(old)==1
    source=source.replace(old,old+'if(root instanceof BlockStateModel.SimpleCachedUnbakedRoot){var f=root.getClass().getDeclaredField("contents");f.setAccessible(true);o.add("root_model",desc(f.get(root)));}')
    old='j.add("selectors",selectors);var states=new JsonArray();'
    assert source.count(old)==1
    source=source.replace(old,'if(def.simpleModels().isPresent())j.add("variant_iteration_order",desc(def.simpleModels().get().models().keySet()));'+old)
    old='var out=new JsonObject();var parsed=new JsonObject();'
    source=source.replace(old,'var out=new JsonObject();var ticketCases=new JsonArray();for(var t:in.getAsJsonArray("ticket_cases"))ticketCases.add(ticketCase(t.getAsJsonObject()));out.add("ticket_cases",ticketCases);var zeros=new JsonArray();for(int c=0;c<65536;c++)if(Character.digit((char)c,10)==0)zeros.add(c);out.add("digit_zeros",zeros);var schemas=new JsonObject();for(var n:in.getAsJsonArray("schema_blocks"))schemas.add(n.getAsString(),schema(n.getAsString()));out.add("schemas",schemas);var parsed=new JsonObject();')
    java=DIR/'ReferenceModelProbe.java';inp=DIR/'inputs.json';output=DIR/'observations.json'
    java.write_text(source);inp.write_text(json.dumps(data,separators=(',',':'))+'\n')
    cp,provenance=probe.verified_client_classpath()
    command=[str(probe.JAVA),'--enable-native-access=ALL-UNNAMED','-cp',':'.join(map(str,cp)),str(java),str(inp),str(probe.CLIENT),str(output)]
    start=time.monotonic();p=subprocess.run(command,cwd=DIR,capture_output=True,text=True,timeout=180)
    (DIR/'stdout.log').write_text(p.stdout);(DIR/'stderr.log').write_text(p.stderr)
    assert p.returncode==0,(p.returncode,p.stdout,p.stderr)
    meta={'command':command,'harness_sha256':sha(java),'base_harness_sha256':hashlib.sha256(probe.JAVA_SOURCE.encode()).hexdigest(),
          'input_sha256':sha(inp),'observation_sha256':sha(output),'client':provenance['client'],
          'java':provenance['java'],'java_version':provenance['java_version'],
          'library_provenance_sha256':hashlib.sha256(json.dumps(provenance['libraries'],sort_keys=True).encode()).hexdigest(),
          'elapsed_seconds':round(time.monotonic()-start,3)}
    (DIR/'metadata.json').write_text(json.dumps(meta,indent=2)+'\n')
    return json.loads(output.read_text()),meta

def variant_projection(value):
    v=value['variant'] if 'variant' in value else value
    state=v['modelState']
    return {'model':v['modelLocation'],**{axis:int(state[axis][1:]) for axis in 'xyz'},'uvlock':state['uvLock']}

def choice_projection(value):
    if value['class'].endswith('SingleVariant$Unbaked'):
        return {'kind':'single','variant':variant_projection(value)}
    assert value['class'].endswith('WeightedVariants$Unbaked'),value
    entries=[{'variant':variant_projection(e['value']),'weight':e['weight']} for e in value['entries']]
    return {'kind':'weighted','total':sum(e['weight'] for e in entries),'entries':entries}

def condition_projection(value):
    if value is None:return None
    tokens=[]
    def visit(v):
        if v['class'].endswith('KeyValueCondition'):
            tokens.append({'kind':'keys','tests':{k:[{f:t[f] for f in ['value','negated']}
                for t in terms['entries']] for k,terms in v['tests'].items()}})
        else:
            assert v['class'].endswith('CombinedCondition'),v
            tokens.append({'kind':v['operation'].lower(),'count':len(v['terms'])})
            for t in v['terms']:visit(t)
    visit(value)
    return {'tokens':tokens}

def dispatcher_projection(value):
    variants={s['selector']:choice_projection(s['model']) for s in value['selectors'] if s['kind']=='simple'}
    parts=[{'condition':condition_projection(s['condition']),'choice':choice_projection(s['model'])}
        for s in value['selectors'] if s['kind']=='multipart']
    definition={'variants':variants or None,'selector_order':value.get('variant_iteration_order'),
                'multipart':parts or None}
    states=[]
    for s in value['states']:
        out={'id':s['state_id'],'mapped':s['mapped']}
        if s['mapped']:
            if 'root_model' in s:root={'kind':'variant','choice':choice_projection(s['root_model'])}
            else:root={'kind':'multipart','parts':[{'index':i,'choice':parts[i]['choice']}
                for i in s['selected_multipart_indices']]}
            out.update(root=root,dependencies=s['root_dependencies'])
        states.append(out)
    return {'status':'ok','definition':definition,'states':states}

def native_requests(data,observed):
    rows=[]
    schemas=observed['schemas']
    def state_input(block):
        s=schemas[block]
        return {'schema':{k:s[k] for k in ['owner','properties']},'states':s['states']}
    for kind in ['selector','condition','dispatcher']:
        key=kind+'_cases'
        assert len(data[key])==len(observed[key])
        for case,actual in zip(data[key],observed[key]):
            assert case['id']==actual['id']
            request={'mode':kind,**state_input(case['block'])}
            request['text' if kind=='dispatcher' else kind]=case['json' if kind=='dispatcher' else kind]
            if actual['status']=='error':expected={'status':'error'}
            elif kind=='selector':expected={'status':'ok','matches':actual['matches_state_ids']}
            elif kind=='condition':expected={'status':'ok','parsed':condition_projection(actual['parsed']),
                'matches':actual['matches_state_ids']}
            else:expected=dispatcher_projection(actual['result'])
            rows.append((case['id'],kind,request,expected,actual))
    for block,text in data['blockstates'].items():
        actual=observed['official_blockstates'][block]
        rows.append(('official_'+block,'official',{'mode':'dispatcher','text':text,**state_input(block)},
            dispatcher_projection(actual),actual))
    for case,actual in zip(data['ticket_cases'],observed['ticket_cases']):
        assert case['id']==actual['id']
        choice=choice_projection(actual['model']);tickets=list(case['tickets'])
        expected=[{'status':'ok','variant':variant_projection(t['selected'])} for t in actual['selected']]
        if choice['kind']=='weighted':
            # The exact Java proxy also records every actual bounded RNG call.
            assert all(t['calls']==[choice['total']] for t in actual['selected']),actual
            extra=[choice['total'],choice['total']+1,4294967295]
            tickets+=extra;expected += [{'status':'error','error':{'code':'TicketOutOfRange','path':'ticket','detail':str(t)}} for t in extra]
        else:
            assert all(t['calls']==[] for t in actual['selected']),actual
            tickets += [1,4294967295];expected += [{'status':'ok','variant':choice['variant']}]*2
        request={'mode':'choice','value':case['value'],'tickets':tickets}
        rows.append((case['id'],'choice',request,{'status':'ok','choice':choice,'tickets':expected},actual))
    # Independent explicit-boundary failures, outside constructible Java schemas.
    base={'mode':'dispatcher','text':'{"variants":{"":{"model":"block/stone"}}}',**state_input('wheat')}
    boundaries=[]
    for name,code,edit in [
        ('duplicate_state_id','DuplicateStateId',lambda r:r['states'].append(copy.deepcopy(r['states'][0]))),
        ('missing_state_property','IncompleteState',lambda r:r['states'][0]['properties'].clear()),
        ('state_noncanonical_integer','StateNonCanonicalValue',lambda r:r['states'][0]['properties'].update(age='01')),
        ('empty_property_domain','EmptyPropertyDomain',lambda r:r['schema']['properties']['age'].update(values=[])),
        ('duplicate_property_domain','DuplicatePropertyValue',lambda r:r['schema']['properties']['age'].update(values=['0','0'])),
        ('noncanonical_property_domain','NonCanonicalDomainValue',lambda r:r['schema']['properties']['age'].update(values=['01'])),
    ]:
        request=copy.deepcopy(base);edit(request);boundaries.append((name,'boundary',request,{'status':'error','code':code},None))
    return rows+boundaries

def run(command,timeout=180,allowed=False):
    command=list(map(str,command));start=time.monotonic()
    try:
        p=subprocess.run(command,cwd=ROOT,capture_output=True,text=True,timeout=timeout)
        record={'command':command,'exit_code':p.returncode,'stdout':p.stdout[-5000:],'stderr':p.stderr[-5000:],
                'elapsed_seconds':round(time.monotonic()-start,3)}
        if not allowed:assert p.returncode==0,record
        return p,record
    except subprocess.TimeoutExpired as e:
        decode=lambda x:x.decode(errors='replace') if isinstance(x,bytes) else x or ''
        record={'command':command,'status':'timeout','stdout':decode(e.stdout)[-5000:],'stderr':decode(e.stderr)[-5000:],
                'elapsed_seconds':round(time.monotonic()-start,3)}
        if not allowed:raise RuntimeError(record)
        return None,record

def kernel_projection():
    """Alpha-rename verbatim production definitions; omit only JSON runtime.

    A lexer protects strings/comments and preserves qualified Base identifiers.
    ResourceJson and Blockstate use J only for its exact AST/Limits declarations.
    """
    ast_source=(ROOT/'src/json.bend').read_text()
    ast=ast_source[ast_source.index('type Value is Data:'):ast_source.index('def default_limits()')]
    resource=(ROOT/'src/resource_json.bend').read_text()
    model=(ROOT/'src/blockstate_model.bend').read_text()
    laws=(ROOT/'tests/blockstate_model.bend').read_text().split('# Native harness.')[0]
    def symbols(source):
        out=set(re.findall(r'^(?:type|def|law) (\w+)\b',source,re.M))
        for block in re.findall(r'^type \w+ is Data:\n((?:  [^\n]*\n)+)',source,re.M):
            out.update(re.findall(r'^  (\w+)\{',block,re.M))
        return out
    tables={'J':{n:'BS_AST_'+n for n in symbols(ast)},'R':{n:'BS_Resource_'+n for n in symbols(resource)},
            'M':{n:'BS_Model_'+n for n in symbols(model)}}
    token=re.compile(r'"(?:\\.|[^"\\])*"|#[^\n]*|\b(?:J|R|M)\.\w+|\b\w+\b')
    def rewrite(source,table):
        source='\n'.join(line for line in source.splitlines() if not line.startswith('import '))
        def convert(m):
            t=m.group()
            if t.startswith(('"','#')):return t
            if '.' in t:
                alias,name=t.split('.');assert name in tables[alias],t
                return tables[alias][name]
            return table.get(t,t)
        return token.sub(convert,source)
    text='import Base\n\n'+rewrite(ast,tables['J'])+'\n'+rewrite(resource,tables['R'])+'\n'+rewrite(model,tables['M'])+'\n'+rewrite(laws,{n:'BS_Test_'+n for n in symbols(laws)})+'\n'
    path=ROOT/'build/blockstate-model-kernel.bend';path.write_text(text)
    return path,{'projection_sha256':sha(path),'ast_declarations_sha256':hashlib.sha256(ast.encode()).hexdigest(),
        'production_resource_sha256':sha(ROOT/'src/resource_json.bend'),'production_blockstate_sha256':sha(ROOT/'src/blockstate_model.bend'),
        'finite_law_prefix_sha256':hashlib.sha256(laws.encode()).hexdigest(),
        'transformation':'Retain all ResourceJson and Blockstate production types/functions and eight finite law helpers verbatim modulo import deletion and capture-avoiding lexical namespace alpha-renaming. Retain exact J.Value/Member/Limits declarations; exclude unreachable J parser/serializer and native IO harness. No implementation body, runtime limit, or condition is replaced or omitted.'}

def native_cases(rows):
    results=[];start=time.monotonic();offset=0
    while offset<len(rows):
        args=[];size=0
        while offset+len(args)<len(rows):
            value=json.dumps(rows[offset+len(args)][2],ensure_ascii=True,separators=(',',':'))
            if args and size+len(value)>65536:break
            args.append(value);size+=len(value)
        p,record=run([BIN,'--threads','1',*args],timeout=120)
        output=p.stdout.splitlines();assert len(output)==len(args),(offset,record)
        for row,line in zip(rows[offset:offset+len(args)],output):
            name,kind,request,expected,java=row;actual=json.loads(line)
            assert actual['status']==expected['status'],(name,expected,actual)
            if expected['status']=='ok':
                comparable={k:actual[k] for k in expected};assert comparable==expected,(name,expected,actual)
            elif kind=='selector':assert actual['error']['detail']==java['error']['message'],(name,java,actual)
            elif kind=='boundary':assert actual['error']['code']==expected['code'],(name,expected,actual)
            if kind=='condition':
                assert ('parsed' in actual)==('parsed' in java),(name,'decode/bind failure stage',java,actual)
                if java.get('parsed') is not None:
                    assert actual.get('parsed')==condition_projection(java['parsed']),(name,java,actual)
            if kind in ['condition','dispatcher'] and actual['status']=='error':
                message=java['error']['message']
                if message.startswith('Unknown property '):
                    assert actual['error']['code']=='ConditionUnknownProperty' and actual['error']['detail']==message,(name,java,actual)
                elif message.startswith('Unknown value '):
                    assert actual['error']['code']=='ConditionUnknownValue',(name,java,actual)
                elif message=='Empty term':
                    assert actual['error']['code']=='EmptyTerm' and actual['error']['detail']==message,(name,java,actual)
            results.append({'id':name,'kind':kind,'status':actual['status'],
                'native_sha256':hashlib.sha256(line.encode()).hexdigest(),
                'expected_sha256':hashlib.sha256(json.dumps(expected,sort_keys=True,separators=(',',':')).encode()).hexdigest(),
                **({'bend_error':actual['error'],'java_error':java.get('error') if java else None} if actual['status']=='error' else {}),
                **({'diagnostics':actual['diagnostics']} if 'diagnostics' in actual else {})})
        offset+=len(args)
    return results,round(time.monotonic()-start,3)

def write_java_evidence(data,observed,metadata):
    rows=[]
    for kind in ['selector_cases','condition_cases','dispatcher_cases']:
        for case,actual in zip(data[kind],observed[kind]):
            rows.append({'id':actual['id'],'kind':kind,'status':actual['status'],
                'input_sha256':hashlib.sha256(json.dumps(case,sort_keys=True,separators=(',',':')).encode()).hexdigest(),
                **({'error':actual['error'],'condition_decoded_before_failure':'parsed' in actual} if actual['status']=='error' else {})})
    report={'schema':1,'scope':'Direct pinned production Java blockstate codec/predicate/ordered-dispatch observations, without Bend native parity claim. Installed official resource texts remain outside this summary.',
        'oracle':metadata,'runner_sha256':sha(__file__),'reference_sha256':sha(REF),
        'counts':{k:len(observed[k]) for k in ['selector_cases','condition_cases','dispatcher_cases']},
        'official_blocks':len(observed['official_blockstates']),
        'official_states':sum(len(b['states']) for b in observed['official_blockstates'].values()),
        'BMP_digit_zero_characters':observed['digit_zeros'],'weighted_ticket_cases':observed['ticket_cases'],'results':rows}
    (ROOT/'evidence/blockstate-model-java.json').write_text(json.dumps(report,indent=2)+'\n')

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--oracle-only',action='store_true')
    ap.add_argument('--reuse-oracle',action='store_true');ap.add_argument('--skip-build',action='store_true')
    ap.add_argument('--skip-kernel',action='store_true');ap.add_argument('--prepare-only',action='store_true')
    ap.add_argument('--kernel-timeout',type=int,default=60);args=ap.parse_args()
    data=inputs()
    if args.reuse_oracle:
        metadata=json.loads((DIR/'metadata.json').read_text());observed=json.loads((DIR/'observations.json').read_text())
        assert metadata['observation_sha256']==sha(DIR/'observations.json')
        assert json.loads((DIR/'inputs.json').read_text())==data,'Regenerate stale Java oracle'
    else:observed,metadata=oracle(data)
    assert observed['digit_zeros']==DIGIT_ZEROS
    write_java_evidence(data,observed,metadata)
    summary={'selectors':len(data['selector_cases']),'conditions':len(data['condition_cases']),
        'dispatchers':len(data['dispatcher_cases']),'official_blocks':len(data['blockstates']),
        'official_states':sum(len(v['states']) for v in observed['official_blockstates'].values()),
        'weighted_java_tickets':sum(len(v['selected']) for v in observed['ticket_cases'])}
    if args.oracle_only:print(json.dumps(summary|{'oracle_sha256':metadata['observation_sha256']},indent=2));return
    rows=native_requests(data,observed);projection,projection_meta=kernel_projection()
    if args.prepare_only:print(json.dumps(summary|{'native_requests':len(rows),'projection':str(projection)},indent=2));return
    paths=['src/blockstate_model.bend','src/resource_json.bend','src/json.bend','tests/blockstate_model.bend']
    hashes={p:sha(ROOT/p) for p in paths};commands=[]
    for path in paths[:1]+paths[-1:]:
        p,record=run([BEND,path,'--check-only']);assert 'ALL PROOFS CHECK' in p.stdout;commands.append(record)
    receipt=ROOT/'build/blockstate-model-build.json'
    if not args.skip_build:
        p,record=run([BEND,'tests/blockstate_model.bend','-o',BIN],timeout=600,allowed=True);commands.append(record)
        attempts=ROOT/'evidence/blockstate-model-build-attempts.json'
        history=json.loads(attempts.read_text()) if attempts.exists() else {'schema':1,'attempts':[]}
        history['attempts'].append(record|{'source_hashes':hashes,'compiler_sha256':sha(BEND)})
        attempts.write_text(json.dumps(history,indent=2)+'\n')
        assert p is not None and p.returncode==0,record
        receipt.write_text(json.dumps({'source_hashes':hashes,'binary_sha256':sha(BIN),'compiler_sha256':sha(BEND),'command':record},indent=2)+'\n')
    else:
        cached=json.loads(receipt.read_text());assert cached['source_hashes']==hashes and cached['binary_sha256']==sha(BIN) and cached['compiler_sha256']==sha(BEND),'Stale build receipt'
    results,native_seconds=native_cases(rows)
    if not args.skip_kernel:
        for path in ['src/blockstate_model.bend','tests/blockstate_model.bend',projection]:
            p,record=run([BEND,path,'--verdict'],timeout=args.kernel_timeout,allowed=True);commands.append(record)
    assert hashes=={p:sha(ROOT/p) for p in paths},'Sources changed during verification'
    report={'schema':1,'scope':'Pure typed 26.3 blockstate resource decoding, property predicates, exact ordered variant dispatch, multipart groups/dependencies and explicit cumulative-weight ticket selection. No baking, registry acquisition, RNG ownership or client activation.',
        'counts':summary|{'native_requests':len(results),'native_successes':sum(r['status']=='ok' for r in results),
            'native_rejections':sum(r['status']=='error' for r in results)},'source_hashes':hashes,
        'binary_sha256':sha(BIN),'compiler_sha256':sha(BEND),'runner_sha256':sha(__file__),
        'native_build_skipped':args.skip_build,'native_build_receipt':json.loads(receipt.read_text()),'native_seconds':native_seconds,'oracle':metadata,
        'reference_corpus_sha256':sha(REF),'weighted_rng_calls':observed['ticket_cases'],
        'kernel_projection':projection_meta,'commands':commands,'results':results,
        'error_contract':'Bend returns stable code/path/detail. Selector details match all observed Java messages exactly. Condition/dispatcher aggregated DataResult exception formatting is retained in Java evidence but is not claimed byte-identical.',
        'limits':{'condition_work_steps':262144,'ordered_states':65535,'numeric_exponent_magnitude':100000,
            'weight_and_total_max':2147483647,'resource_json_default_codepoints':1048576,'resource_json_max_depth':255,'resource_json_number_ascii_units':1023}}
    target=ROOT/'evidence/blockstate-model-native.json';target.write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report['counts']|{'evidence':str(target),'native_seconds':native_seconds},indent=2))

if __name__=='__main__':main()
