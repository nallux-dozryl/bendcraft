#!/usr/bin/env python3
"""Actual source/C/native shared-scene receiver with independent resource checks."""
import io,json,math,shutil,struct,zipfile
from PIL import Image
import reference_model_probe as R
import test_campfire_authority as T
ROOT=T.ROOT;WORK=ROOT/'build/entity-scene-render-native'
def f(w):return struct.unpack('>f',struct.pack('>I',w))[0]
def compare(got,reference):
 rows={r['name']:r for r in got['cases']}
 assert set(rows)=={'shared-quad-budget','missing-light','front','behind','world-only'},rows
 assert rows['shared-quad-budget']['error']=='scene:QuadLimit',rows['shared-quad-budget']
 assert rows['missing-light']['error']=='scene:light authority unavailable:not published'
 assert got['world_count']==1 and got['entity_count']==2
 for name in ['world-only','behind','front']:
  qs=rows[name]['scene'];assert [q['order']for q in qs]==list(range(len(qs)))
  assert all(q['texture']==0 for q in qs[:6]),name
  assert all(1<=q['texture']<3 for q in qs[6:]),name
  assert all(q['light']==4289777792 for q in qs[:6]),name
  assert all(q['light']==4292902992 for q in qs[6:]),name
 assert len(rows['world-only']['scene'])==6
 assert len(rows['behind']['scene'])==len(rows['front']['scene'])>7
 assert rows['behind']['pixels']==rows['world-only']['pixels'],'world geometry must occlude both real item and orb'
 differences=sum(a!=b for a,b in zip(rows['front']['pixels'],rows['world-only']['pixels']));assert differences>0,'front dropped entities must be visible'
 # Independent pinned PNG checks. BR appends its sorted cooked-beef sprite
 # before the explicitly appended XP sprite; world occupies the prefix.
 names=['block/stone','item/cooked_beef','entity/experience/experience_orb']
 with zipfile.ZipFile(R.CLIENT) as jar:
  for row,name in zip(got['textures'],names):
   im=Image.open(io.BytesIO(jar.read('assets/minecraft/textures/'+name+'.png'))).convert('RGBA');w,h=im.size;r,g,b,a=im.getpixel((w//2,h//2))
   assert row==[w,h,1<<((max(w,h)-1).bit_length()),(a<<24)|(r<<16)|(g<<8)|b],(name,row)
 maximum=0;exact=0
 assert len(got['cameras'])==len(reference['observations'])==50
 for native,expected in zip(got['cameras'],reference['observations']):
  for a,b in zip(native,expected['quaternion']):
   maximum=max(maximum,abs(f(a)-f(b)));exact+=a==b
   assert abs(f(a)-f(b))<=1.2e-7,(native,expected)
 return {'actual_java_camera_cases':50,'camera_components':200,'camera_raw_bit_exact_components':exact,'camera_max_abs_error':maximum,'real_png_shared_domain_samples':3,'opaque_world_blocks_occlude_real_item_and_orb':True,'foreground_changed_pixels':differences,'global_orders_and_shared_texture_indices_checked':True,'combined_world_quad_count':6,'combined_entity_quad_count':len(rows['front']['scene'])-6,'missing_authority_and_combined_budget_refusals':2}
def payload():
 reference=json.loads((ROOT/'reference/entity_scene_render.json').read_text())
 rows=json.loads((ROOT/'reference/campfire_authority.json').read_text())['inputs']['catalog']['items']
 return reference,{'catalog':{'items':[v for v in rows if v['id']=='minecraft:cooked_beef']},'item_table':(ROOT/'generated/reference_item_metadata.tsv').read_text(),'jar':str(R.CLIENT),'sine':str(ROOT/'generated/reference_mth_sin.f32'),'cases':reference['observations']}
def receipt(checks):
 reference,_=payload();got=json.loads((WORK/'native-1.stdout').read_text());comparison=compare(got,reference)
 four=json.loads((WORK/'native-4.stdout').read_text());assert got==four
 source=json.loads((WORK/'receiver.c.sources.json').read_text());assert all(T.digest(p)==h for p,h in source['source_sha256'].items())
 evidence={'status':'passed','pin':'26.3','command':'python3 tools/test_entity_scene_render.py','checks':checks,'source':source,'reference_sha256':T.digest(ROOT/'reference/entity_scene_render.json'),'input_sha256':T.digest(WORK/'input.json'),'initialized_default_source_sha256':T.digest(ROOT/'reference/campfire_authority.json'),'item_table_sha256':T.digest(ROOT/'generated/reference_item_metadata.tsv'),'mth_table_sha256':T.digest(ROOT/'generated/reference_mth_sin.f32'),'installed_client_sha256':T.digest(R.CLIENT),'native_emitted_c_sha256':T.digest(WORK/'receiver.c'),'native_binary_sha256':T.digest(WORK/'receiver'),'threads':[1,4],'comparisons':comparison,'boundary':'Original checked source book and original Comp.compile_book. Actual pinned installed stone and authenticated initialized cooked-beef models/PNG, actual XP sprite and existing item producer; ONE shared production Scene.draw_prepared/M.render. Hidden 32x32 CPU overlap/occlusion with explicit SYNTHETIC supplied light RGB only; no actual game lightmap or live settled actor publication claim. Camera compares actual Camera.setRotation receiver with measured native sinf numeric boundary. Existing item spawn/tick/bake corpus is not replayed. Independent connected kernel laws cover physical owner recovery/failure, separate from FFI/native IO and pixels. No GPU/front-end/OS presentation acceptance.'}
 (ROOT/'evidence/entity-scene-render-native.json').write_text(json.dumps(evidence,indent=2)+'\n');print(json.dumps(comparison))
def main():
 WORK.mkdir(parents=True,exist_ok=True);T.WORK=WORK
 _,data=payload();(WORK/'input.json').write_text(json.dumps(data,separators=(',',':'))+'\n')
 checks=[T.run('emit',[T.NODE,'--expose-gc','--experimental-transform-types','--stack-size=4096','--max-old-space-size=3072','tools/entity_scene_render_emit.mjs','tests/entity_scene_render.bend',WORK/'receiver.c'],timeout=60,max_rss=3758096384)]
 checks.append(T.run('clang',[shutil.which('clang'),'-std=c11','-O0','-fomit-frame-pointer','-ffp-contract=off',WORK/'receiver.c','-lpthread','-lm','-o',WORK/'receiver'],timeout=120))
 for threads in [1,4]:checks.append(T.run('native-'+str(threads),['/usr/bin/time','-l',WORK/'receiver','--gpu','off','--threads',str(threads),WORK/'input.json'],timeout=60,max_rss=1024**3))
 receipt(checks)
if __name__=='__main__':main()
