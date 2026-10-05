#!/usr/bin/env python3
"""Observe actual installed section-key equality and its migration callback."""
import hashlib,json,math,os,struct,subprocess,time
from pathlib import Path
from reference_model_probe import verified_client_classpath,JAVA
ROOT=Path(__file__).resolve().parents[1];WORK=ROOT/'build/item-entity-tick-sections-reference'
SOURCE=r'''
import com.google.gson.*;
import java.nio.file.*;
import java.util.*;
import net.minecraft.core.BlockPos;
import net.minecraft.core.SectionPos;
import net.minecraft.world.phys.Vec3;
class ItemEntityTickSectionsReference {
 static double word(JsonElement raw){var a=raw.getAsJsonArray();return Double.longBitsToDouble((a.get(0).getAsLong()<<32)|a.get(1).getAsLong());}
 static Vec3 vec(JsonArray a){return new Vec3(word(a.get(0)),word(a.get(1)),word(a.get(2)));}
 static Object bits(long value){return List.of(value>>>32,value&0xffffffffL);}
 public static void main(String[]args)throws Exception{
  List<Object> out=new ArrayList<>();
  for(var raw:JsonParser.parseString(Files.readString(Path.of(args[0]))).getAsJsonArray()){
   var r=raw.getAsJsonObject();BlockPos a=BlockPos.containing(vec(r.getAsJsonArray("first"))),b=BlockPos.containing(vec(r.getAsJsonArray("second")));
   long x=SectionPos.asLong(a),y=SectionPos.asLong(b);
   out.add(Map.of("id",r.get("id").getAsString(),"first",r.get("first"),"second",r.get("second"),"first_key",bits(x),"second_key",bits(y),"same",x==y,"less",x<y));
  }
  Files.writeString(Path.of(args[1]),new Gson().toJson(out));
 }
}
'''
def bits(x):
    n=struct.unpack('>Q',struct.pack('>d',x))[0];return [n>>32,n&0xffffffff]
def inputs():
    out=[]
    pairs=[('positive-inside',15.5,15.999999999999998),('positive-cross',15.999999999999998,16),('negative-inside',-16,-.0000000000000001),('negative-cross',-16,-16.000000000000004),('zero-cross',0,-.0000000000000001),('negative-zero',-0.,0.),('integer-extremes',-2147483648.,2147483647.),('positive-saturation',2147483647.,math.inf),('negative-saturation',-2147483648.,-math.inf),('nan-zero',math.nan,0.)]
    for axis in range(3):
        for label,a,b in pairs:
            first=[.5,.5,.5];second=first[:];first[axis]=a;second[axis]=b
            out.append(dict(id=f'{label}-{axis}',first=list(map(bits,first)),second=list(map(bits,second))))
        first=[.5,.5,.5];second=first[:];second[axis]=(1<<24 if axis==1 else 1<<26)+.5
        out.append(dict(id=f'packed-key-wrap-{axis}',first=list(map(bits,first)),second=list(map(bits,second))))
    return out
def main():
    WORK.mkdir(parents=True,exist_ok=True);paths,pin=verified_client_classpath();rows=inputs();(WORK/'input.json').write_text(json.dumps(rows));(WORK/'ItemEntityTickSectionsReference.java').write_text(SOURCE);start=time.monotonic()
    p=subprocess.run([str(JAVA),'-Xmx256m','--source','25','--class-path',os.pathsep.join(map(str,paths)),str(WORK/'ItemEntityTickSectionsReference.java'),str(WORK/'input.json'),str(WORK/'output.json')],capture_output=True,text=True,timeout=40)
    (WORK/'java.stdout').write_text(p.stdout);(WORK/'java.stderr').write_text(p.stderr);assert p.returncode==0,p.stderr
    j=subprocess.run([str(JAVA.parent/'javap'),'-c','-p','-classpath',os.pathsep.join(map(str,paths)),'net.minecraft.core.SectionPos','net.minecraft.world.level.entity.PersistentEntitySectionManager$Callback'],capture_output=True,text=True,check=True,timeout=20)
    (WORK/'receivers.javap').write_text(j.stdout)
    assert 'Field currentSectionKey:J' in j.stdout and 'Method updateStatus:' in j.stdout and 'long 4194303l' in j.stdout and 'long 1048575l' in j.stdout
    result=dict(pin='26.3',cases=json.loads((WORK/'output.json').read_text()),provenance=pin,source_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),java_source_sha256=hashlib.sha256(SOURCE.encode()).hexdigest(),callback_bytecode_sha256=hashlib.sha256(j.stdout.encode()).hexdigest(),seconds=round(time.monotonic()-start,4),boundary='Actual SectionPos.asLong(BlockPos.containing(Vec3)) equality; callback bytecode removes old membership, inserts into destination, replaces current key and calls updateStatus when packed keys differ. No host visibility/membership implementation and no claim that the callback has been joined.')
    (ROOT/'reference/item_entity_tick_sections.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(dict(status='passed',cases=len(rows))))
if __name__=='__main__':main()
