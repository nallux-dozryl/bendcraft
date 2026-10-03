#!/usr/bin/env python3
"""Inventory pinned client PNGs and selected model dependencies; no rendering."""
from __future__ import annotations

import argparse
import collections
import copy
import hashlib
import io
import json
import pathlib
import struct
import zlib
import zipfile

import PIL
from PIL import Image
from reference_inventory import ROOT, INSTALL, canonical, fingerprint, write_json

OUTPUT=ROOT/"reference/render_assets.json"
CLIENT=INSTALL/"versions/26.3/26.3.jar"
BLOCKS=["stone","dirt","oak_planks","grass_block","glass"]
MIN_TEXTURES=["stone","dirt","oak_planks","glass","grass_block_top","grass_block_side","grass_block_side_overlay","snow"]


class UnsupportedPng(ValueError):pass


def sha(data:bytes)->str:return hashlib.sha256(data).hexdigest()


def verify_client()->dict:
    release=json.loads((ROOT/"reference/release.json").read_text())
    if release["pin"]!="26.3" or fingerprint(CLIENT)["sha256"]!=release["client"]["sha256"]:raise ValueError("Pinned client artifact mismatch")
    return release


def parse_png(data:bytes)->dict:
    if data[:8]!=b'\x89PNG\r\n\x1a\n':raise ValueError("Invalid PNG signature")
    chunks=[];off=8
    while off<len(data):
        if off+12>len(data):raise ValueError("Truncated PNG chunk header")
        length=struct.unpack_from('>I',data,off)[0];end=off+12+length
        if end>len(data):raise ValueError("Truncated PNG chunk payload")
        tag=data[off+4:off+8];payload=data[off+8:off+8+length];crc=struct.unpack_from('>I',data,off+8+length)[0]
        if zlib.crc32(tag+payload)&0xffffffff!=crc:raise ValueError("PNG chunk CRC mismatch")
        chunks.append((tag.decode('ascii'),payload,off));off=end
        if tag==b'IEND':break
    if not chunks or chunks[0][0]!='IHDR' or len(chunks[0][1])!=13 or chunks[-1][0]!='IEND':raise ValueError("Invalid PNG header/end topology")
    if sum(t=='IHDR' for t,_,_ in chunks)!=1 or sum(t=='IEND'for t,_,_ in chunks)!=1:raise ValueError("Duplicate PNG structural chunk")
    w,h,depth,color,compression,filtering,interlace=struct.unpack('>IIBBBBB',chunks[0][1])
    if not w or not h:raise ValueError("Invalid PNG image dimensions")
    return {"width":w,"height":h,"bit_depth":depth,"color_type":color,"compression_method":compression,"filter_method":filtering,"interlace_method":interlace,"chunks":chunks,"trailing_bytes":len(data)-off}


def decode_reference_png(parsed:dict)->tuple[bytes,dict]:
    w,h,depth,color=parsed['width'],parsed['height'],parsed['bit_depth'],parsed['color_type'];chunks=parsed['chunks']
    channels={0:1,2:3,3:1,4:2,6:4}
    if parsed['compression_method']!=0 or parsed['filter_method']!=0 or parsed['interlace_method']!=0:raise UnsupportedPng("Only standard compression/filtering and noninterlaced PNG supported")
    if color not in channels or depth not in ({1,2,4,8}if color in [0,3]else{8}):raise UnsupportedPng("Unsupported PNG color-type/bit-depth combination")
    unknown=[t for t,_,_ in chunks if t[0].isupper()and t not in {'IHDR','PLTE','IDAT','IEND'}]
    if unknown:raise UnsupportedPng("Unknown critical PNG chunks: "+','.join(unknown))
    if any(t in {'acTL','fcTL','fdAT'}for t,_,_ in chunks):raise UnsupportedPng("Animated PNG frame decoding not covered")
    payload=b''.join(d for t,d,_ in chunks if t=='IDAT');decoder=zlib.decompressobj();filtered=decoder.decompress(payload)+decoder.flush()
    if not decoder.eof or decoder.unused_data or decoder.unconsumed_tail:raise ValueError("Invalid or extra PNG zlib stream data")
    rowbytes=(w*channels[color]*depth+7)//8;bpp=max(1,(channels[color]*depth+7)//8)
    if len(filtered)!=(rowbytes+1)*h:raise ValueError("PNG decompressed scanline length mismatch")
    palette=next((d for t,d,_ in chunks if t=='PLTE'),b'');transparency=next((d for t,d,_ in chunks if t=='tRNS'),b'')
    if color==3 and (not palette or len(palette)%3 or len(palette)>768):raise ValueError("Invalid PNG palette")
    if color==0 and transparency and len(transparency)!=2:raise ValueError("Invalid grayscale PNG transparency")
    if color==2 and transparency and len(transparency)!=6:raise ValueError("Invalid RGB PNG transparency")
    filters=collections.Counter();previous=bytearray(rowbytes);rgba=bytearray();scale=255//((1<<depth)-1)
    for y in range(h):
        start=y*(rowbytes+1);kind=filtered[start];filters[kind]+=1;row=bytearray(filtered[start+1:start+1+rowbytes])
        if kind not in range(5):raise ValueError("Unsupported PNG scanline filter")
        for i in range(rowbytes):
            left=row[i-bpp]if i>=bpp else 0;up=previous[i];corner=previous[i-bpp]if i>=bpp else 0
            if kind==1:row[i]=(row[i]+left)&255
            elif kind==2:row[i]=(row[i]+up)&255
            elif kind==3:row[i]=(row[i]+((left+up)//2))&255
            elif kind==4:
                p=left+up-corner;pa=abs(p-left);pb=abs(p-up);pc=abs(p-corner);predictor=left if pa<=pb and pa<=pc else up if pb<=pc else corner;row[i]=(row[i]+predictor)&255
        for x in range(w):
            if color in [0,3]:
                bit=x*depth;sample=(row[bit//8]>>(8-depth-bit%8))&((1<<depth)-1)
                if color==0:
                    grey=sample*scale;alpha=0 if transparency and sample==struct.unpack('>H',transparency)[0]else 255;rgba.extend((grey,grey,grey,alpha))
                else:
                    if sample*3+3>len(palette):raise ValueError("PNG palette sample outside palette")
                    rgba.extend(palette[sample*3:sample*3+3]);rgba.append(transparency[sample]if sample<len(transparency)else 255)
            elif color==2:
                rgb=row[x*3:x*3+3];alpha=0 if transparency and tuple(rgb)==struct.unpack('>HHH',transparency)else 255;rgba.extend(rgb);rgba.append(alpha)
            elif color==4:
                grey,alpha=row[x*2:x*2+2];rgba.extend((grey,grey,grey,alpha))
            else:rgba.extend(row[x*4:x*4+4])
        previous=row
    return bytes(rgba),{"scanline_filters":{str(k):v for k,v in sorted(filters.items())},"inflated_scanline_bytes":len(filtered)}


def png_record(path:str,data:bytes,archive:zipfile.ZipFile)->dict:
    p=parse_png(data);chunks=p.pop('chunks');record={"path":path,"resource_bytes":len(data),"resource_sha256":sha(data),**p,"chunk_order":[t for t,_,_ in chunks],"chunk_lengths":[len(d)for _,d,_ in chunks],"idat_count":sum(t=='IDAT'for t,_,_ in chunks),"idat_bytes":sum(len(d)for t,d,_ in chunks if t=='IDAT'),"all_chunk_crcs_valid":True}
    trns=next((d for t,d,_ in chunks if t=='tRNS'),None);plte=next((d for t,d,_ in chunks if t=='PLTE'),None)
    record['palette_entries']=len(plte)//3 if plte is not None else 0;record['transparency_chunk_bytes']=len(trns)if trns is not None else 0
    if trns is not None:record['transparency_chunk_sha256']=sha(trns)
    if trns is not None and p['color_type']==0:record['transparent_grayscale_sample']=struct.unpack('>H',trns)[0]
    if trns is not None and p['color_type']==2:record['transparent_rgb_samples']=list(struct.unpack('>HHH',trns))
    try:
        with Image.open(io.BytesIO(data))as im:
            record['pillow_mode']=im.mode;record['pillow_frame_count']=getattr(im,'n_frames',1);pixels=im.convert('RGBA').tobytes();record['pillow_rgba_sha256']=sha(pixels)
        decoded,filters=decode_reference_png({**p,'chunks':chunks});record.update(filters)
        if decoded!=pixels:raise ValueError("Independent PNG decoders disagree: "+path)
        record.update({"decode_status":"two_decoders_match","rgba_bytes":len(decoded),"rgba_sha256":sha(decoded),"alpha_min":min(decoded[3::4]),"alpha_max":max(decoded[3::4]),"alpha_zero_pixels":decoded[3::4].count(0),"alpha_partial_pixels":sum(0<a<255 for a in decoded[3::4])})
        if path in {f'assets/minecraft/textures/block/{n}.png'for n in MIN_TEXTURES}:record['rgba_row_sha256']=[sha(decoded[y*p['width']*4:(y+1)*p['width']*4])for y in range(p['height'])]
    except UnsupportedPng as e:record.update({"decode_status":"unsupported_reference_decoder","decode_reason":str(e)})
    except Exception as e:
        if isinstance(e,ValueError)and str(e).startswith('Independent PNG decoders disagree'):raise
        record.update({"decode_status":"decode_error","decode_error_class":type(e).__name__,"decode_reason":str(e)})
    metadata_path=path+'.mcmeta'
    try:metadata_bytes=archive.read(metadata_path)
    except KeyError:metadata_bytes=None
    if metadata_bytes is not None:
        metadata=json.loads(metadata_bytes);record['metadata']={"path":metadata_path,"resource_sha256":sha(metadata_bytes),"sections":sorted(metadata),"animation":metadata.get('animation'),"texture":metadata.get('texture')}
    return record


def identifier(name:str)->str:
    value=name if ':'in name else'minecraft:'+name
    namespace,path=value.split(':',1)
    if not namespace or not path or '..'in pathlib.PurePosixPath(path).parts:raise ValueError("Invalid selected model/texture identifier")
    return value


def resource_path(name:str,kind:str)->str:
    namespace,path=identifier(name).split(':',1);return f'assets/{namespace}/{kind}/{path}.json'


def selected_models(archive:zipfile.ZipFile)->dict:
    source={};resolved={};states={};visiting=set()
    def load(name):
        name=identifier(name)
        if name in resolved:return resolved[name]
        if name in visiting:raise ValueError("Selected model parent cycle")
        visiting.add(name);path=resource_path(name,'models');b=archive.read(path);data=json.loads(b);source[name]={"path":path,"resource_sha256":sha(b),"json":data}
        parent=load(data['parent'])if 'parent'in data else None
        textures=copy.deepcopy(parent['textures'])if parent else{};textures.update(data.get('textures',{}))
        elements=copy.deepcopy(data['elements'])if 'elements'in data else copy.deepcopy(parent['elements'])if parent else[]
        owner=name if 'elements'in data else parent['elements_source_model']if parent else None
        faces=[]
        for index,element in enumerate(elements):
            for direction,face in element.get('faces',{}).items():
                reference=face.get('texture');terminal=reference;aliases=[]
                while isinstance(terminal,str)and terminal.startswith('#'):
                    if terminal in aliases:raise ValueError("Selected model texture alias cycle")
                    aliases.append(terminal)
                    if terminal[1:]not in textures:break
                    terminal=textures[terminal[1:]]
                sprite=terminal.get('sprite')if isinstance(terminal,dict)else terminal
                if not isinstance(sprite,str):raise ValueError("Unsupported selected texture definition")
                resource=None
                if not sprite.startswith('#'):
                    ns,texture=identifier(sprite).split(':',1);resource=f'assets/{ns}/textures/{texture}.png'
                faces.append({"element_index":index,"direction":direction,"element_from":element.get('from'),"element_to":element.get('to'),"face_json":face,"texture_alias_chain":aliases,"terminal_texture_definition":terminal,"texture_resource":resource,"texture_resolution_status":"resolved"if resource is not None else'unbound_abstract_parent_variable',"uv_source":"explicit"if'uv'in face else'absent_in_source_java_default_not_executed',"tint_source":"explicit"if'tintindex'in face else'absent_in_source'})
        r={"parent_chain":([name]+parent['parent_chain'])if parent else[name],"textures":textures,"elements":elements,"elements_source_model":owner,"resolved_faces":faces,"interpretation_scope":"JSON parent inheritance for textures/elements and alias traversal only; no actual Java model bake, default UV generation, transformations, tint computation, random variant selection or rendering"};resolved[name]=r;visiting.remove(name);return r
    def models(value):
        if isinstance(value,dict):
            if 'model'in value:yield value['model']
            for v in value.values():yield from models(v)
        elif isinstance(value,list):
            for v in value:yield from models(v)
    for block in BLOCKS:
        path=f'assets/minecraft/blockstates/{block}.json';b=archive.read(path);data=json.loads(b);refs=sorted({identifier(m)for m in models(data)});states['minecraft:'+block]={"path":path,"resource_sha256":sha(b),"json":data,"referenced_models":refs}
        for m in refs:load(m)
    textures=sorted({f['texture_resource']for r in resolved.values()for f in r['resolved_faces']if f['texture_resource']is not None})
    return {"blockstates":states,"model_sources":dict(sorted(source.items())),"data_derived_models":dict(sorted(resolved.items())),"required_texture_resources":textures,"java_model_bake_executed":False}


def summarize(records):
    formats=collections.Counter(f"depth={r['bit_depth']},color={r['color_type']},interlace={r['interlace_method']}"for r in records)
    filters=collections.Counter();chunks=collections.Counter();groups=collections.Counter()
    for r in records:
        filters.update({k:v for k,v in r.get('scanline_filters',{}).items()});chunks.update(r['chunk_order']);parts=r['path'].split('/');groups[parts[3]if len(parts)>4 and parts[2]=='textures'else'other']+=1
    return {"png_count":len(records),"format_counts":dict(sorted(formats.items())),"decode_status_counts":dict(sorted(collections.Counter(r['decode_status']for r in records).items())),"chunk_occurrence_counts":dict(sorted(chunks.items())),"scanline_filter_counts":dict(sorted(filters.items())),"texture_group_counts":dict(sorted(groups.items())),"transparency_chunk_files":sum(r['transparency_chunk_bytes']>0 for r in records),"animated_metadata_files":sum('metadata'in r and r['metadata']['animation']is not None for r in records),"max_width":max(r['width']for r in records),"max_height":max(r['height']for r in records),"rgba_bytes":sum(r.get('rgba_bytes',0)for r in records)}


def observe():
    release=verify_client()
    with zipfile.ZipFile(CLIENT)as archive:
        names=sorted(n for n in archive.namelist()if n.endswith('.png'));records=[png_record(n,archive.read(n),archive)for n in names];models=selected_models(archive)
    return {"schema_version":1,"pin":"26.3","purpose":"Reference PNG resource/pixel inventory and selected JSON model inputs; no Java renderer fidelity claim","confidence":"high for two-decoder pixel equality and pinned raw JSON; model interpretation is explicitly bounded","client_sha256":release['client']['sha256'],"pillow_version":PIL.__version__,"reference_decoder_version":1,"pixel_encoding":"Row-major, top-to-bottom, left-to-right, straight non-premultiplied RGBA8; no gamma/ICC/tint/animation/atlas transform applied","records":records,"selected_models":models,"summary":summarize(records)}


def validate(metadata,fresh=None):
    if metadata['schema_version']!=1 or metadata['pin']!='26.3':raise ValueError("Render reference pin/schema mismatch")
    if metadata['observation_sha256']!=sha(canonical({k:v for k,v in metadata.items()if k!='observation_sha256'})):raise ValueError("Render reference checksum mismatch")
    if metadata['summary']!=summarize(metadata['records']):raise ValueError("Render reference count/summary mismatch")
    if len({r['path']for r in metadata['records']})!=len(metadata['records']):raise ValueError("Duplicate PNG resource path")
    paths={r['path']for r in metadata['records']}
    for r in metadata['records']:
        if len(r['chunk_order'])!=len(r['chunk_lengths'])or r['chunk_order'][0]!='IHDR'or r['chunk_order'][-1]!='IEND':raise ValueError("Render PNG chunk topology mismatch")
        if r['decode_status']=='two_decoders_match'and(r['rgba_sha256']!=r['pillow_rgba_sha256']or r['rgba_bytes']!=r['width']*r['height']*4):raise ValueError("Render PNG independent decoder/length mismatch")
    if any(p not in paths for p in metadata['selected_models']['required_texture_resources']):raise ValueError("Selected model missing texture resource")
    if fresh is not None:
        if {k:v for k,v in metadata.items()if k!='observation_sha256'}!=fresh:raise ValueError("Render reference differs from fresh pinned resources/pixel observations")
    return {"png_count":len(metadata['records']),"two_decoder_matches":sum(r['decode_status']=='two_decoders_match'for r in metadata['records']),"unsupported_or_errors":[{"path":r['path'],"status":r['decode_status'],"reason":r.get('decode_reason')}for r in metadata['records']if r['decode_status']!='two_decoders_match'],"selected_blockstates":len(metadata['selected_models']['blockstates']),"selected_model_sources":len(metadata['selected_models']['model_sources']),"selected_texture_dependencies":len(metadata['selected_models']['required_texture_resources']),"fresh_resource_comparison":fresh is not None}


def extract():
    data=observe();data['observation_sha256']=sha(canonical(data));checks=validate(data);write_json(OUTPUT,data)
    evidence={"status":"passed","scope":"Two independent PNG decoders and JSON dependencies, no game launch or model bake","reference":fingerprint(OUTPUT),"validation":checks,"summary":data['summary'],"commands":["python3 tools/reference_render_probe.py","python3 tools/reference_render_probe.py --verify-existing","python3 tools/reference_render_probe.py --selftest"]};write_json(ROOT/'evidence/reference-render-probe.json',evidence);return evidence


def verify_existing():
    metadata=json.loads(OUTPUT.read_text());checks=validate(metadata,observe());evidence={"status":"passed","reference":fingerprint(OUTPUT),"validation":checks,"pinned_client_hash_checked":True};write_json(ROOT/'evidence/reference-render-validation.json',evidence);return evidence


def selftest():
    metadata=json.loads(OUTPUT.read_text());a=observe();b=observe();validate(metadata,a);validate(metadata,b)
    if a!=b:raise ValueError("PNG/model reference observations not reproducible")
    failures=[]
    changed=copy.deepcopy(metadata);changed['records'][0]['rgba_sha256']='0'*64;changed['records'][0]['pillow_rgba_sha256']='0'*64
    for reseal in [False,True]:
        if reseal:changed['observation_sha256']=sha(canonical({k:v for k,v in changed.items()if k!='observation_sha256'}))
        try:validate(changed,a)
        except ValueError as e:failures.append({"case":"wrong_decoded_pixel_hash","resealed_observation_checksum":reseal,"rejected":True,"reason":str(e)})
        else:raise ValueError("Wrong PNG pixel hash accepted")
    changed=copy.deepcopy(metadata);changed['selected_models']['model_sources']['minecraft:block/glass']['json']['textures']['all']['sprite']='minecraft:block/stone';changed['observation_sha256']=sha(canonical({k:v for k,v in changed.items()if k!='observation_sha256'}))
    try:validate(changed,a)
    except ValueError as e:failures.append({"case":"wrong_glass_sprite_definition","resealed_observation_checksum":True,"rejected":True,"reason":str(e)})
    else:raise ValueError("Wrong selected model texture accepted")
    with zipfile.ZipFile(CLIENT)as archive:data=archive.read('assets/minecraft/textures/block/stone.png')
    parsed=parse_png(data);tag,payload,off=next(c for c in parsed['chunks']if c[0]=='IDAT');bad=bytearray(data);index=off+8+len(payload)-1;bad[index]^=1
    for reseal in [False,True]:
        if reseal:struct.pack_into('>I',bad,off+8+len(payload),zlib.crc32(bytes(bad[off+4:off+8+len(payload)]))&0xffffffff)
        try:decode_reference_png(parse_png(bytes(bad)))
        except(ValueError,zlib.error)as e:failures.append({"case":"corrupt_compressed_stone_data","resealed_chunk_crc":reseal,"rejected":True,"reason":str(e)})
        else:raise ValueError("Corrupted PNG compressed data accepted")
    evidence={"status":"passed","reference":fingerprint(OUTPUT),"independent_observation_runs":2,"pngs_per_run":len(a['records']),"byte_exact_reference_reproduced":True,"failure_injection":failures,"scope":"Reference resource/pixel integrity, no Bend or Java render comparison"};write_json(ROOT/'evidence/reference-render-selftest.json',evidence);return evidence


def main():
    p=argparse.ArgumentParser(description=__doc__);g=p.add_mutually_exclusive_group();g.add_argument('--verify-existing',action='store_true');g.add_argument('--selftest',action='store_true');a=p.parse_args();r=selftest()if a.selftest else verify_existing()if a.verify_existing else extract();print(json.dumps({"status":r['status'],"pngs":r.get('pngs_per_run',r.get('validation',{}).get('png_count'))},sort_keys=True))


if __name__=='__main__':main()
