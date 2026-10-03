#!/usr/bin/env python3
"""Observe pinned official Java RNG methods; Python generates inputs only."""
from __future__ import annotations
import argparse, collections, hashlib, json, pathlib, random, subprocess, zipfile
from reference_inventory import ROOT, JAVA, canonical, fingerprint, write_json
from reference_block_probe import verified_classpath

CLASSES = [
    'net.minecraft.world.level.levelgen.LegacyRandomSource',
    'net.minecraft.world.level.levelgen.BitRandomSource',
    'net.minecraft.world.level.levelgen.XoroshiroRandomSource',
    'net.minecraft.world.level.levelgen.Xoroshiro128PlusPlus',
    'net.minecraft.world.level.levelgen.RandomSupport',
    'net.minecraft.world.level.levelgen.RandomSupport$Seed128bit',
    'net.minecraft.world.level.levelgen.PositionalRandomFactory',
    'net.minecraft.world.level.levelgen.LegacyRandomSource$LegacyPositionalRandomFactory',
    'net.minecraft.world.level.levelgen.XoroshiroRandomSource$XoroshiroPositionalRandomFactory',
    'net.minecraft.util.RandomSource', 'net.minecraft.util.Mth',
]
SEED=263_640_48
SOURCE=r'''
import java.io.*;
import java.nio.file.*;
import java.lang.reflect.*;
import java.util.*;
import java.util.concurrent.atomic.AtomicLong;
import com.google.gson.*;
import net.minecraft.util.RandomSource;
import net.minecraft.world.level.levelgen.*;

public class ReferenceRandomProbe {
    static final Gson JSON=new Gson();
    static final Field LEGACY_SEED, XORO_RNG, LOW, HIGH;
    static {
        try {
            LEGACY_SEED=LegacyRandomSource.class.getDeclaredField("seed"); LEGACY_SEED.setAccessible(true);
            XORO_RNG=XoroshiroRandomSource.class.getDeclaredField("randomNumberGenerator"); XORO_RNG.setAccessible(true);
            LOW=Xoroshiro128PlusPlus.class.getDeclaredField("seedLo"); LOW.setAccessible(true);
            HIGH=Xoroshiro128PlusPlus.class.getDeclaredField("seedHi"); HIGH.setAccessible(true);
        } catch(Exception e) { throw new ExceptionInInitializerError(e); }
    }
    static long word(String s) { return Long.parseUnsignedLong(s); }
    static long bits(String hi,String lo) { return (word(hi)<<32)|word(lo); }
    static String pair(long value) { return Long.toUnsignedString(value>>>32)+","+Long.toUnsignedString(value&0xffffffffL); }
    static String state(RandomSource source) throws Exception {
        if(source instanceof LegacyRandomSource) return "l,"+pair(((AtomicLong)LEGACY_SEED.get(source)).get())+",0,0";
        Object r=XORO_RNG.get(source); return "x,"+pair(LOW.getLong(r))+","+pair(HIGH.getLong(r));
    }
    static RandomSource cloneState(RandomSource source) throws Exception {
        if(source instanceof LegacyRandomSource) {
            LegacyRandomSource copy=new LegacyRandomSource(0); ((AtomicLong)LEGACY_SEED.get(copy)).set(((AtomicLong)LEGACY_SEED.get(source)).get()); return copy;
        }
        Object r=XORO_RNG.get(source); return new XoroshiroRandomSource(LOW.getLong(r),HIGH.getLong(r));
    }
    static String factory(PositionalRandomFactory source) throws Exception {
        Class<?> type=source.getClass();
        if(type.getSimpleName().equals("LegacyPositionalRandomFactory")) { Field seed=type.getDeclaredField("seed"); seed.setAccessible(true); return "l,"+pair(seed.getLong(source))+",0,0"; }
        Field low=type.getDeclaredField("seedLo"),high=type.getDeclaredField("seedHi"); low.setAccessible(true); high.setAccessible(true); return "x,"+pair(low.getLong(source))+","+pair(high.getLong(source));
    }
    static int draws(RandomSource before,String target) throws Exception {
        RandomSource cursor=cloneState(before);
        for(int n=1;n<=10000;n++) {
            if(cursor instanceof LegacyRandomSource legacy) legacy.next(31); else cursor.nextLong();
            if(state(cursor).equals(target)) return n;
        }
        throw new IllegalStateException("No state advancement match within10000 primitive draws");
    }
    static Map<String,Object> observe(JsonObject input) throws Exception {
        String protocol=input.get("protocol").getAsString(); String[] p=protocol.split("\\|",-1);
        String label=p[0]; RandomSource source;
        switch(p[1]) {
            case "l": source=new LegacyRandomSource(bits(p[2],p[3])); break;
            case "x": source=new XoroshiroRandomSource(bits(p[2],p[3])); break;
            case "r": source=new XoroshiroRandomSource(bits(p[2],p[3]),bits(p[4],p[5])); break;
            default: throw new IllegalArgumentException("Unknown RNG kind");
        }
        List<String> output=new ArrayList<>(); List<Integer> boundedDraws=new ArrayList<>(); List<String> unsupportedHashObservations=new ArrayList<>(); List<Map<String,Object>> boundedJavaObservations=new ArrayList<>();
        output.add(label+"|0|init|"+state(source)); int index=0;
        for(String op:p[6].split(";",-1)) {
            String[] a=op.split(":",-1); String value;
            switch(a[0]) {
                case "i": value=Long.toUnsignedString(Integer.toUnsignedLong(source.nextInt())); break;
                case "l": value=pair(source.nextLong()); break;
                case "b": value=source.nextBoolean()?"1":"0"; break;
                case "f": value=Long.toUnsignedString(Integer.toUnsignedLong(Float.floatToRawIntBits(source.nextFloat()))); break;
                case "d": value=pair(Double.doubleToRawLongBits(source.nextDouble())); break;
                case "n": {
                    int bound=(int)word(a[1]), fuel=(int)word(a[2]); RandomSource before=cloneState(source); Map<String,Object> observed=new TreeMap<>(); observed.put("operation_index",index+1); observed.put("bound",bound); observed.put("fuel",fuel); observed.put("before_state",state(before));
                    try {
                        int actual=source.nextInt(bound); int n=draws(before,state(source)); boundedDraws.add(n);
                        observed.put("java_value",actual); observed.put("java_after_state",state(source)); observed.put("primitive_draws",n);
                        if(n>fuel) { source=before; value="fuel"; } else value="ok:"+actual;
                    } catch(IllegalArgumentException e) { if(!state(source).equals(state(before))) throw new IllegalStateException("Invalid Java bound advanced state"); value="invalid"; boundedDraws.add(0); observed.put("java_error_class",e.getClass().getName()); observed.put("java_after_state",state(source)); observed.put("primitive_draws",0); }
                    boundedJavaObservations.add(observed);
                    break;
                }
                case "c": source.consumeCount((int)word(a[1])); value="-"; break;
                case "s": source.setSeed(bits(a[1],a[2])); value="-"; break;
                case "k": { RandomSource child=source.fork(); value="parent:"+state(source); source=child; break; }
                case "p": { PositionalRandomFactory pos=source.forkPositional(); value="parent:"+state(source)+";factory:"+factory(pos); source=pos.at((int)word(a[1]),(int)word(a[2]),(int)word(a[3])); break; }
                case "t": { PositionalRandomFactory pos=source.forkPositional(); value="parent:"+state(source)+";factory:"+factory(pos); source=pos.fromSeed(bits(a[1],a[2])); break; }
                case "h": {
                    RandomSource before=cloneState(source); PositionalRandomFactory pos=source.forkPositional(); String text=op.substring(2);
                    RandomSource child=pos.fromHashOf(text);
                    if(source instanceof XoroshiroRandomSource) { unsupportedHashObservations.add(state(child)); source=before; value="unsupported"; }
                    else { value="parent:"+state(source)+";factory:"+factory(pos); source=child; }
                    break;
                }
                default: throw new IllegalArgumentException("Unknown RNG operation");
            }
            output.add(label+"|"+(++index)+"|"+value+"|"+state(source));
        }
        Map<String,Object> result=new TreeMap<>(); result.put("id",input.get("id").getAsString()); result.put("expected",output); result.put("bounded_primitive_draws",boundedDraws); result.put("bounded_java_observations",boundedJavaObservations); result.put("unsupported_xoroshiro_hash_child_states",unsupportedHashObservations); return result;
    }
    public static void main(String[] args) throws Exception {
        try(BufferedReader input=Files.newBufferedReader(Path.of(args[0])); PrintWriter output=new PrintWriter(Files.newBufferedWriter(Path.of(args[1])))) {
            String line; while((line=input.readLine())!=null) output.println(JSON.toJson(observe(JsonParser.parseString(line).getAsJsonObject())));
            if(output.checkError()) throw new IOException("RNG observation write failed");
        }
    }
}
'''

def words(value):
    value &= (1<<64)-1
    return [value>>32,value&0xffffffff]

def generate_inputs(random_cases=1000):
    rng=random.Random(SEED); cases=[]
    def add(kind,seed,operations,second=0,tags=()):
        label=f'rng{len(cases):05d}'
        protocol='|'.join(map(str,[label,kind,*words(seed),*words(second),';'.join(operations)]))
        cases.append({'id':label,'protocol':protocol,'tags':list(tags)})
    seeds=[0,1,2,-1,-2,-(1<<63),(1<<63)-1,1<<32,(1<<32)-1,(1<<48)-1,1<<48,0x5deece66d,0x6a09e667f3bcc909,0x9e3779b97f4a7c15,0xffff000000000000]
    bounds=[0,1,2,3,7,10,16,100,257,65536,(1<<30)-1,1<<30,(1<<30)+1,(1<<31)-1,1<<31,0xffffffff]
    base=['i','l','b','f','d']
    for kind in ['l','x']:
        for seed in seeds:
            ops=base*3+[f'n:{b}:64' for b in bounds]+['c:0','i','c:1','i','c:19','i','c:2147483648','i','c:4294967295','i','s:4294967295:4294967295']+base+['k']+base+['p:2147483648:4294967295:2147483647']+base+['t:2147483648:0']+base+['h:minecraft:terrain']+base
            add(kind,seed,ops,tags=['targeted','mixed_sequence','forks','signed_extremes'])
        for fuel in [0,1,2,3]:
            for bound in bounds:
                for _ in range(4): add(kind,rng.getrandbits(64),[f'n:{bound}:{fuel}','i','l','d'],tags=['fuel','bounds','rollback'])
        for text in ['', 'minecraft:overworld', 'Aa', 'BB', 'terrain/erosion', '雪', '😀', 'a😀𐐷z', '\uffff']:
            add(kind,rng.getrandbits(64),['h:'+text]+base*3,tags=['hash','utf16'])
        for coords in [(0,0,0),(1,-1,1),(-30000000,-64,30000000),(-2147483648,2147483647,-2147483648),(2147483647,-2147483648,2147483647)]:
            add(kind,rng.getrandbits(64),['p:'+':'.join(str(x&0xffffffff) for x in coords)]+base*3,tags=['position','signed_coordinates'])
    for low,high in [(0,0),(1,0),(0,1),(-1,-1),(-(1<<63),(1<<63)-1),(0x0123456789abcdef,0xfedcba9876543210)]:
        add('r',low,base*10+['k']+base+['p:1:2:3']+base,high,tags=['raw_xoroshiro','zero_guard'])
    for low,high in [(1,-1),(0,-1),(1,0),(-1,0)]:
        for op in base:
            add('r',low,[op]+base,high,tags=['first_draw','fraction_zero_maximum','raw_xoroshiro'])
    for i in range(random_cases):
        kind=['l','x','r'][i%3]; seed=rng.getrandbits(64); second=rng.getrandbits(64); ops=[]
        for _ in range(32):
            op=rng.choice(['i','l','b','f','d','n','n','n','c','k','p','t','s'])
            if op=='n': ops.append(f'n:{rng.choice(bounds+[rng.randrange(1,1<<31)])}:{rng.choice([0,1,2,64,64,64])}')
            elif op=='c': ops.append(f'c:{rng.choice([0,1,2,16,99,0xffffffff])}')
            elif op=='p': ops.append('p:'+':'.join(str(rng.getrandbits(32)) for _ in range(3)))
            elif op in ['s','t']: ops.append(op+':'+':'.join(map(str,words(rng.getrandbits(64)))))
            else: ops.append(op)
        add(kind,seed,ops,second,tags=['deterministic_random_inputs','mixed_sequence'])
    return cases


def source_inventory(jars):
    directory=ROOT/'build/random-reference'; directory.mkdir(parents=True,exist_ok=True)
    records={}; total=[]
    with zipfile.ZipFile(jars[0]) as archive:
        for cls in CLASSES:
            command=[str(JAVA.parent/'javap'),'-classpath',str(jars[0]),'-c','-p',cls]
            report=subprocess.run(command,text=True,capture_output=True,check=True).stdout
            (directory/(cls+'.javap')).write_text(report); total.append(report)
            entry=cls.replace('.','/')+'.class'
            records[cls]={'class_entry':entry,'class_sha256':hashlib.sha256(archive.read(entry)).hexdigest(),'javap_sha256':hashlib.sha256(report.encode()).hexdigest()}
    return {'classes':records,'complete_javap_sha256':hashlib.sha256(''.join(total).encode()).hexdigest()}


def run_java(inputs,jars):
    directory=ROOT/'build/random-reference'; directory.mkdir(parents=True,exist_ok=True)
    source=directory/'ReferenceRandomProbe.java'; source.write_text(SOURCE)
    classes=directory/'classes'; classes.mkdir(exist_ok=True)
    cp=':'.join(map(str,jars))
    compile_command=[str(JAVA.parent/'javac'),'-cp',cp,'-d',str(classes),str(source)]
    subprocess.run(compile_command,text=True,capture_output=True,check=True)
    incoming=directory/'input.jsonl';outgoing=directory/'observed.jsonl'
    incoming.write_bytes(b''.join(canonical(x)+b'\n' for x in inputs))
    command=[str(JAVA),'-cp',str(classes)+':'+cp,'ReferenceRandomProbe',str(incoming),str(outgoing)]
    result=subprocess.run(command,text=True,capture_output=True,check=True)
    (directory/'java.log').write_text(result.stdout+result.stderr)
    observed=[json.loads(x) for x in outgoing.read_text().splitlines()]
    assert [x['id'] for x in inputs]==[x['id'] for x in observed]
    return observed,{'java_source_sha256':hashlib.sha256(SOURCE.encode()).hexdigest(),'compile_command':compile_command,'run_command':command,'input_sha256':fingerprint(incoming)['sha256'],'observation_sha256':fingerprint(outgoing)['sha256']}


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--random',type=int,default=1000);args=parser.parse_args()
    jars,release=verified_classpath();inputs=generate_inputs(args.random); observations,probe=run_java(inputs,jars)
    cases=[dict(i,**{k:v for k,v in o.items() if k!='id'}) for i,o in zip(inputs,observations)]
    draws=collections.Counter(n for o in observations for n in o['bounded_primitive_draws'])
    metadata={'schema':1,'pin':'26.3','seed':SEED,'random_input_cases':args.random,'authority':'Actual named official Java26.3 methods with reflected raw state after every operation; Python selects inputs only','expectation_policy':'Java outputs/state are unchanged for supported successful operations. Invalid Java bounds map to checked InvalidBound. Fuel insufficiency and unsupported Xoroshiro string hashing use explicit Bend rollback/error extensions; original Java bounded outputs/states and unsupported hash child states are retained separately.','nested_server_sha256':release['server_bundle']['nested_server_sha256'],'runtime_executable':fingerprint(JAVA),'runtime_version':subprocess.run([str(JAVA),'-version'],text=True,capture_output=True,check=True).stderr.strip().splitlines(),'source_inventory':source_inventory(jars),'probe':probe,'cases_sha256':hashlib.sha256(canonical(cases)).hexdigest(),'cases':cases,'summary':{'cases':len(cases),'observations':sum(len(o['expected']) for o in observations),'bounded_draw_histogram':dict(sorted(draws.items())),'unsupported_xoroshiro_hash_observations':sum(len(o['unsupported_xoroshiro_hash_child_states']) for o in observations)}}
    write_json(ROOT/'reference/random.json',metadata)
    write_json(ROOT/'evidence/random-reference.json',{k:v for k,v in metadata.items() if k!='cases'})
    print(json.dumps(metadata['summary'],sort_keys=True))

if __name__=='__main__': main()
