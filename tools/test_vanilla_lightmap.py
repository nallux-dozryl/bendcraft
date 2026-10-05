#!/usr/bin/env python3
"""Actual Bend source/native, pinned helper and real installed shader boundaries."""
import json,math,struct
import test_campfire_authority as T
ROOT=T.ROOT;WORK=ROOT/'build/vanilla-lightmap-native'
def f(w):return struct.unpack('<f',struct.pack('<I',w))[0]
def double_words(x):return list(struct.unpack('>II',struct.pack('>d',x)))
def flat(r):
 return r['environment']+[r['tick_count'],r['blend'],int(r['night_duration'] is not None),r['night_duration'] or 0,r['water'],int(r['conduit']),*double_words(r['gamma']),*double_words(r['darkness_scale']),int(r['hide_flash']),int(r['flash'] is not None),*(r['flash'] or[0,0]),int(r['boss_fog']),*r['boss'],r['partial'],r['flicker']]
def compare(got,ref):
 assert got['ticks']==ref['java']['ticks'],'exact four-draw Legacy RNG state/flicker must match actual extractor.tick'
 assert got['prepares']==ref['java']['prepares'],'actual Java helper uniform preparation must match bitwise'
 max_raw=0;exact_raw=0;finite=0;black=0;byte_delta=0;exact_bytes=0;sample_error=0
 assert len(got['shaders'])==len(ref['shader_cases'])
 for actual,case in zip(got['shaders'],ref['shader_cases']):
  expected=case['observed'];assert len(actual['raw'])==len(actual['argb'])==256
  for a,e in zip(actual['raw'],expected['raw']):
   if a is None:
    assert all(math.isnan(f(x))for x in e),(case['name'],e);black+=1
   else:
    assert all(math.isfinite(f(x))for x in a+e)
    for x,y in zip(a,e):
     error=abs(f(x)-f(y));max_raw=max(max_raw,error);exact_raw+=x==y;finite+=1
     assert error<=2e-6,(case['name'],a,e,error)
  for a,e in zip(actual['argb'],expected['argb']):
   assert isinstance(a,int) and a>>24==e>>24==255
   for shift in [0,8,16]:
    x=(a>>shift)&255;y=(e>>shift)&255;delta=abs(x-y);byte_delta=max(byte_delta,delta);exact_bytes+=x==y
    assert delta<=1,(case['name'],hex(a),hex(e))
  for a,e in zip(actual['samples'],expected['samples']):
   for x,y in zip(a,e):
    error=abs(f(x)-f(y));sample_error=max(sample_error,error)
    assert error<=1/255+2e-6,(case['name'],a,e,error)
 return {'actual_java_flicker_ticks_raw_exact':96,'actual_java_helper_preparations_raw_exact':28,'installed_fragment_shader_pixels':2048,'finite_shader_components':finite,'raw_bit_exact_shader_components':exact_raw,'max_abs_raw_error':max_raw,'undefined_black_pixels_correctly_refused_raw_and_stored_zero':black,'rgba8_color_components':6144,'exact_rgba8_color_components':exact_bytes,'max_rgba8_channel_difference':byte_delta,'actual_installed_LINEAR_sampler_probes':88,'max_abs_filtered_error':sample_error}
def main():
 WORK.mkdir(parents=True,exist_ok=True);T.WORK=WORK;ref=json.loads((ROOT/'reference/vanilla_lightmap.json').read_text());checks=[]
 payload={'sine':str(ROOT/'generated/reference_mth_sin.f32'),'shaders':[c['uniforms']for c in ref['shader_cases']],'prepares':[flat(r)for r in ref['inputs']['prepares']],'ticks':[r['seed']+[r['count']]for r in ref['inputs']['ticks']]};(WORK/'input.json').write_text(json.dumps(payload))
 checks.append(T.run('export',[T.NODE,'--experimental-transform-types','--stack-size=4096','--max-old-space-size=2048','tools/vanilla_lightmap_proof.mjs',WORK],timeout=60,max_rss=2684354560))
 selection=json.loads((WORK/'selection.json').read_text());scope=json.loads((WORK/'scope.json').read_text());assert len(selection['roots'])==13 and scope['exclusions']==[]
 checks.append(T.run('kernel',['/usr/bin/env','LEAN_STACK_SIZE=4194304',T.KERNEL,WORK/'selected.bendtt'],timeout=60));assert (WORK/'kernel.stdout').read_text().strip()=='ALL PROOFS CHECK'
 checks.append(T.run('emit',[T.NODE,'--expose-gc','--experimental-transform-types','--stack-size=4096','--max-old-space-size=2048','tools/vanilla_lightmap_emit.mjs','tests/vanilla_lightmap.bend',WORK/'receiver.c'],timeout=90,max_rss=2684354560))
 checks.append(T.run('clang',['clang','-std=c11','-O2','-ffp-contract=off',WORK/'receiver.c','-lm','-lpthread','-o',WORK/'receiver'],timeout=60,max_rss=1610612736))
 checks.append(T.run('native-one',[WORK/'receiver','--gpu','off','--threads','1',WORK/'input.json'],timeout=60,max_rss=1024**3));got=json.loads((WORK/'native-one.stdout').read_text());summary=compare(got,ref)
 checks.append(T.run('native-four',[WORK/'receiver','--gpu','off','--threads','4',WORK/'input.json'],timeout=60,max_rss=1024**3));assert json.loads((WORK/'native-four.stdout').read_text())==got
 pins=json.loads((WORK/'receiver.c.sources.json').read_text());assert all(T.digest(p)==h for p,h in pins['source_sha256'].items()),'native source changed'
 proof={'status':'passed','ordinary_laws':13,'independent_kernel_laws':13,'roots':selection['roots'],'term_pins':selection['term_pins'],'source_sha256':json.loads((WORK/'source-pins.json').read_text()),'scope_exclusions':[],'checked_types_and_bodies_unchanged':selection['checked_types_and_bodies_unchanged'],'all_original_declaration_maps_retained':selection['all_original_tlds_ctrs_tmps_retained'],'selected_sha256':T.digest(WORK/'selected.bendtt'),'kernel_sha256':T.digest(T.KERNEL),'checks':checks[:2],'boundary':'Actual affine renderer/table rollback and successful/clean/absent extraction commit laws, initial texture, NV/flash gates and shader conversion failures. These do not prove transcendental tables, RNG arithmetic, floating shader parity, live EnvironmentAttribute authority or actor/frame integration; independent native/Java/shader observations cover their stated numerical boundaries.'}
 (ROOT/'evidence/vanilla-lightmap-proof.json').write_text(json.dumps(proof,indent=2)+'\n')
 evidence={'status':'passed','command':'python3 tools/test_vanilla_lightmap.py','reference_sha256':T.digest(ROOT/'reference/vanilla_lightmap.json'),'source_sha256':pins['source_sha256'],'emitted_c_sha256':T.digest(WORK/'receiver.c'),'compiler_sha256':pins['compiler_sha256'],'checks':checks,'summary':summary,'threads':[1,4],'shader_backend':ref['shader_backend'],'boundary':'Actual production Bend helpers and separate renderer RNG compared to retained actual pinned Java receivers; actual installed shader and LINEAR sampler executed offscreen CGL. CPU F32 results and nearest RGBA8 storage are compared at recorded numerical tolerances, never asserted globally bit-identical to GPU or to Minecraft Vulkan. No full client, gameplay environment authority, authoritative light-stamp publication or foreground/OS acceptance claimed.'}
 (ROOT/'evidence/vanilla-lightmap-native.json').write_text(json.dumps(evidence,indent=2)+'\n');print(json.dumps({'status':'passed',**summary,'kernel_laws':13}))
if __name__=='__main__':main()
