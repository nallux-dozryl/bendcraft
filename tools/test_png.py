#!/usr/bin/env python3
"""Independent native Bend PNG comparisons; Pillow is an oracle, not runtime."""
from __future__ import annotations
import datetime,hashlib,json,os,struct,subprocess,tempfile,time,zipfile,zlib
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
BEND=Path.home()/'.bend/bin/bend'
PYTHON=Path.home()/'.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3'
JAR=Path.home()/'Library/Application Support/minecraft/versions/26.3/26.3.jar'

def chunk(name,data):
    return struct.pack('>I',len(data))+name+data+struct.pack('>I',zlib.crc32(name+data))
def png(w,h,d,c,scan,palette=None,trns=None):
    out=b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',w,h,d,c,0,0,0))
    if palette is not None:out+=chunk(b'PLTE',palette)
    if trns is not None:out+=chunk(b'tRNS',trns)
    compressed=zlib.compress(scan)
    return out+chunk(b'IDAT',compressed[:2])+chunk(b'IDAT',compressed[2:])+chunk(b'IEND',b'')
def run(args):
    p=subprocess.run(args,cwd=ROOT,text=True,capture_output=True,check=True)
    return p.stdout

def main():
    from PIL import Image
    started=time.monotonic()
    run([str(BEND),'src/png.bend','--verdict'])
    run([str(BEND),'tests/png.bend','-o','build/png-probe'])
    cases=[]
    with tempfile.TemporaryDirectory(prefix='minecraft-png-') as td:
        td=Path(td)
        with zipfile.ZipFile(JAR) as z:
            names=sorted(n for n in z.namelist() if n.startswith('assets/minecraft/textures/block/') and n.endswith('.png'))
            for i,name in enumerate(names):
                data=z.read(name);path=td/f'asset-{i}.png';path.write_bytes(data)
                cases.append((path,name,None))
        # Each predictor gets an independently encoded scanline with nonzero
        # left/top/corner bytes. Wider row makes packed-depth row padding visible.
        raw=[bytes((i*37+y*53)%256 for i in range(21)) for y in range(5)]
        scan=b''
        for y,row in enumerate(raw):
            filt=y;encoded=[]
            for x,v in enumerate(row):
                a=row[x-3] if x>=3 else 0;b=raw[y-1][x] if y else 0;c=raw[y-1][x-3] if y and x>=3 else 0
                pa,pb,pc=abs(b-c),abs(a-c),abs(a+b-2*c)
                pred=[0,a,b,(a+b)//2,a if pa<=pb and pa<=pc else b if pb<=pc else c][filt]
                encoded.append((v-pred)&255)
            scan+=bytes([filt])+bytes(encoded)
        generated={'filters':png(7,5,8,2,scan),'gray1':png(9,2,1,0,b'\0\xaa\x80\0\x55\0',trns=b'\0\1'),
                   'gray2':png(5,1,2,0,b'\0\x1b\x40'),'gray4':png(3,1,4,0,b'\0\x1f\x80'),
                   'indexed1':png(3,1,1,3,b'\0\xa0',palette=b'\x10\x20\x30\xff\x80\0',trns=b'\0\x7f'),
                   'rgb_trns':png(2,1,8,2,b'\0\x11\x22\x33\x11\x22\x34',trns=b'\0\x11\0\x22\0\x33')}
        for name,data in generated.items():
            path=td/f'{name}.png';path.write_bytes(data);cases.append((path,name,None))
        good=generated['filters']
        # Mutations isolate checksum, framing, compressed stream, ordering,
        # dimension, palette and semantic checks, with valid chunk CRC when needed.
        malformed={'signature':(b'x'+good[1:],'Signature'),'crc':(good[:-1]+bytes([good[-1]^1]),'CRC'),
            'trailing':(good+b'X','TrailingData'),'missing_iend':(good[:-12],'MissingIEND'),
            'interlace':(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',7,5,8,2,0,0,1))+good[33:],'UnsupportedInterlace'),
            'filter5':(png(1,1,8,0,b'\5\0'),'Filter'),'too_short':(png(1,1,8,0,b'\0'),'ScanlineLength'),
            'too_long':(png(1,1,8,0,b'\0\0\0'),'Zlib:OutputLimit'),
            'palette_oob':(png(1,1,8,3,b'\0\2',palette=b'\0\0\0'),'PaletteIndex'),
            'missing_plte':(png(1,1,8,3,b'\0\0'),'PaletteTransparency'),
            'critical':(good[:33]+chunk(b'ABCD',b'')+good[33:],'UnknownCriticalChunk'),
            'duplicate_ihdr':(good[:33]+good[8:33]+good[33:],'IHDRMustBeFirst'),
            'zero_width':(png(0,1,8,0,b'\0'),'Dimensions')}
        for name,(data,error) in malformed.items():
            path=td/f'invalid-{name}.png';path.write_bytes(data);cases.append((path,name,error))
        checked=0;verified=[]
        for start in range(0,len(cases),64):
            batch=cases[start:start+64]
            rows=[json.loads(x) for x in run([str(ROOT/'build/png-probe'),'--pixels',*[str(c[0]) for c in batch]]).splitlines()]
            assert len(rows)==len(batch)
            for (path,name,error),row in zip(batch,rows):
                if error:
                    assert row.get('error')==error,(name,row,error)
                else:
                    image=Image.open(path).convert('RGBA');rgba=image.tobytes()
                    actual=b''.join(bytes(((p>>16)&255,(p>>8)&255,p&255,p>>24)) for p in row['pixels'])
                    assert (row['width'],row['height'])==image.size,(name,row)
                    assert actual==rgba,name
                    assert row['rgba_crc32']==zlib.crc32(rgba),name
                    verified.append({'name':name,'width':image.width,'height':image.height,'rgba_sha256':hashlib.sha256(rgba).hexdigest()})
                checked+=1
        evidence={'date':datetime.datetime.now().astimezone().date().isoformat(),'compiler':run([str(BEND),'version']).strip(),'jar_sha256':hashlib.sha256(JAR.read_bytes()).hexdigest(),
          'runtime':'pure Bend PNG and DEFLATE; Base file effects only','oracle':'Pillow '+Image.__version__,
          'block_textures_compared_byte_for_byte':len(names),'synthetic_valid':len(generated),'malformed_rejected':len(malformed),
          'kernel':'ALL PROOFS CHECK','native_cases':checked,'elapsed_seconds':round(time.monotonic()-started,3),
          'selected':[v for v in verified if v['name'].rsplit('/',1)[-1] in ('stone.png','dirt.png','oak_planks.png','glass.png','grass_block_side_overlay.png','snow.png')],
          'source_sha256':hashlib.sha256((ROOT/'src/png.bend').read_bytes()).hexdigest(),'commands':['bend src/png.bend --verdict','bend tests/png.bend -o build/png-probe',str(PYTHON)+' tools/test_png.py']}
        (ROOT/'evidence/png-native.json').write_text(json.dumps(evidence,indent=2)+'\n')
        print(json.dumps(evidence,indent=2))
if __name__=='__main__':main()
