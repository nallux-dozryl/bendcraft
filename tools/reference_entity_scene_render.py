#!/usr/bin/env python3
"""Observe pinned Camera.setRotation directly without creating a client/window."""
import json, os
import reference_model_probe as R
import test_campfire_authority as T
ROOT=T.ROOT;WORK=ROOT/'build/entity-scene-render-reference'
JAVA=r'''
import java.nio.file.*;import java.lang.reflect.*;import com.google.gson.*;import org.joml.*;import sun.misc.Unsafe;import net.minecraft.client.Camera;
class ReferenceEntitySceneRender {
 static long b(float x){return Integer.toUnsignedLong(Float.floatToRawIntBits(x));}
 static JsonArray a(float...xs){var out=new JsonArray();for(float x:xs)out.add(b(x));return out;}
 public static void main(String[]args)throws Exception{
  var f=Unsafe.class.getDeclaredField("theUnsafe");f.setAccessible(true);var u=(Unsafe)f.get(null);
  var cam=(Camera)u.allocateInstance(Camera.class);for(String s:new String[]{"forwards","up","left"}){var v=Camera.class.getDeclaredField(s);v.setAccessible(true);v.set(cam,new Vector3f());}
  var qf=Camera.class.getDeclaredField("rotation");qf.setAccessible(true);qf.set(cam,new Quaternionf());var method=Camera.class.getDeclaredMethod("setRotation",float.class,float.class);method.setAccessible(true);
  var rows=new JsonArray();for(float yaw:new float[]{-720f,-180f,-90f,-.5f,0f,45f,90f,180f,359.5f,720f})for(float pitch:new float[]{-90f,-37.25f,0f,37.25f,90f}){
   method.invoke(cam,yaw,pitch);var q=(Quaternionf)qf.get(cam);var row=new JsonObject();row.add("degrees",a(yaw,pitch));row.add("radians",a(yaw*.017453292f,pitch*.017453292f));row.add("quaternion",a(q.x,q.y,q.z,q.w));rows.add(row);
  }
  Files.writeString(Path.of(args[0]),new Gson().toJson(rows));
 }
}
'''
def main():
 WORK.mkdir(parents=True,exist_ok=True);T.WORK=WORK
 paths,provenance=R.verified_client_classpath();p=WORK/'ReferenceEntitySceneRender.java';p.write_text(JAVA)
 check=T.run('java',[R.JAVA,'-Xmx512m','-cp',os.pathsep.join(map(str,paths)),p,WORK/'observations.json'],timeout=60,max_rss=1024**3)
 rows=json.loads((WORK/'observations.json').read_text());assert len(rows)==50
 result={'pin':'26.3','scope':'Actual Camera.setRotation receiver with actual JOML rotationYXZ; Unsafe only allocates the reference receiver without a client/window. Full official classpath verified. Native sinf is a measured boundary. No game lightmap, world lighting or OS rendering observation claimed.','provenance':provenance,'receiver_sha256':T.digest(p),'check':check,'observations':rows}
 (ROOT/'reference/entity_scene_render.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps({'status':'passed','camera_observations':len(rows)}))
if __name__=='__main__':main()
