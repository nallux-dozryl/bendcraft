#!/usr/bin/env python3
"""Bounded native CPU/Metal renderer integration with independent pixel oracle.

The generated scene is explicitly a verification fixture. It establishes no
Minecraft gameplay, world-generation, model-variant or lighting parity.
"""
from __future__ import annotations
import hashlib,json,math,os,struct,subprocess,time,zipfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
PYTHON=Path.home()/'.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3'
BEND=Path.home()/'.bend/bin/bend'
JAR=Path.home()/'Library/Application Support/minecraft/versions/26.3/26.3.jar'
BLOCKS=[(x,0,z,1,0) for x in range(5) for z in range(5)]+[(1,1,2,10,1),(2,1,2,15,2),(2,2,2,15,2)]
CAMERA=(2.65,3.17,-4.23,0.09,0.37)
SOURCE='''import Base
import ../src/client_render.bend as R
import ../src/png.bend as P
import ../src/archive.bend as A
import ../src/platform.bend as Native

def scene() -> R.Snapshot:
  R.Snapshot{0n,0n,BLOCKS,R.Camera{CAMERA}}

def end(shown: Window & Image & List<Event>) -> IO(Unit):
  (window,image,events) = shown
  do IO<Unit>:
    observed : Window & String <- Native.Platform.inspect(window)
    P.paired(Window,String,IO(Unit),observed,window => text => (
      do IO<Unit>:
        IO.print("observed=" ++ text)
        Window.close(window)
    ))

def display(pair: R.Assets & Image,before: Nat) -> IO(Unit):
  (assets,+image) = pair
  do IO<Unit>:
    after : Nat <- IO.now()
    IO.print("render_ms=" ++ Nat.show(Nat.sub(after,before)))
    R.write_ppm("FRAME",image,SIZE,SIZE)
    window : Window <- IO.try(Window,Window.open("Minecraft bounded render verification fixture",SIZE,SIZE))
    shown : Window & Image & List<Event> <- Window.frame(window,image)
    IO.print("frame_returned=true")
    end(shown)

def warm(+n: Nat,assets: R.Assets) -> IO(R.Assets):
  match n:
    case 0n: IO.pure(R.Assets,assets)
    case 1n+p:
      do IO<R.Assets>:
        before : Nat <- IO.now()
        pair : R.Assets & Image = R.render_gpu(scene(),assets,SIZE,SIZE)
        P.paired(R.Assets,Image,IO(R.Assets),pair,assets => image => (
          do IO<R.Assets>:
            after : Nat <- IO.now()
            IO.print("warm_render_ms=" ++ Nat.show(Nat.sub(after,before)))
            Unit <- IO.pure(Unit,Image.drop(image))
            warm(p,assets)
        ))

def ready(result: Result<&2,&1,A.Error,R.Assets>) -> IO(Unit):
  match result:
    case Fail{error}: IO.die(Unit,1,A.error_text(error))
    case Done{assets}:
      do IO<Unit>:
        assets : R.Assets <- warm(5n,assets)
        before : Nat <- IO.now()
        display(R.render_gpu(scene(),assets,SIZE,SIZE),before)

def main() -> IO(Unit):
  do IO<Unit>:
    loaded : Result<&2,&1,A.Error,R.Assets> <- R.load_assets("JAR")
    ready(loaded)
'''

def run(args,*,hidden=False,timeout=180):
    env=os.environ.copy()
    if hidden:env['BEND_MINECRAFT_LAUNCH_MODE']='hidden'
    started=time.monotonic()
    p=subprocess.run([str(a) for a in args],cwd=ROOT,text=True,capture_output=True,env=env,timeout=timeout)
    assert p.returncode==0,(args,p.stdout,p.stderr)
    return p.stdout,p.stderr,time.monotonic()-started

def f(x):return struct.unpack('f',struct.pack('f',x))[0]
def add(a,b):return f(f(a)+f(b))
def sub(a,b):return f(f(a)-f(b))
def mul(a,b):return f(f(a)*f(b))
def div(a,b):return f(f(a)/f(b))

def reference(size,textures):
    ox,oy,oz,yaw,pitch=map(f,CAMERA)
    sy,cy,sp,cp=map(f,(math.sin(yaw),math.cos(yaw),math.sin(pitch),math.cos(pitch)))
    rx,rz=cy,sy;ux,uy,uz=-mul(sy,sp),cp,mul(cy,sp);fx,fy,fz=-mul(sy,cp),-sp,mul(cy,cp)
    out=bytearray()
    for y in range(size):
        for x in range(size):
            u=mul(sub(div(mul(add(x,.5),2),size),1),f(.7002075382))
            v=mul(sub(1,div(mul(add(y,.5),2),size)),f(.7002075382))
            dx=add(fx,add(mul(rx,u),mul(ux,v)));dy=add(fy,mul(uy,v));dz=add(fz,add(mul(rz,u),mul(uz,v)))
            length=f(math.sqrt(add(mul(dx,dx),add(mul(dy,dy),mul(dz,dz)))))
            dx,dy,dz=div(dx,length),div(dy,length),div(dz,length)
            best=64.;hit=None
            for bx,by,bz,state,material in BLOCKS:
                spans=[]
                for origin,direction,low,face in ((ox,dx,bx,0),(oy,dy,by,2),(oz,dz,bz,4)):
                    if abs(direction)<1e-8:
                        spans.append((-1e20,1e20,face) if low<=origin<=low+1 else (1e20,-1e20,face))
                    else:
                        a=div(sub(low,origin),direction);b=div(sub(add(low,1),origin),direction)
                        spans.append((min(a,b),max(a,b),face if direction>0 else face+1))
                near,_,face=max(spans,key=lambda s:s[0]);far=min(s[1] for s in spans)
                if near>=f(.0001) and near<=far and near<best:
                    best=near
                    xx=sub(add(ox,mul(dx,near)),bx);yy=sub(add(oy,mul(dy,near)),by);zz=sub(add(oz,mul(dz,near)),bz)
                    uv=((zz,sub(1,yy)),(sub(1,zz),sub(1,yy)),(xx,sub(1,zz)),(xx,zz),(sub(1,xx),sub(1,yy)),(xx,sub(1,yy)))[face]
                    tx,ty=[min(15,int(mul(16,sub(t,math.floor(t))))) for t in uv]
                    rgb=textures[material].getpixel((tx,ty))[:3]
                    level=255 if face==3 else 153 if face<2 else 204 if face==2 else 127
                    hit=bytes(c*level//255 for c in rgb)
            g=y*60//size
            out.extend(hit or bytes((100+g,160+g//2,235)))
    return bytes(out)

def main():
    from PIL import Image
    build=ROOT/'build';build.mkdir(exist_ok=True)
    from io import BytesIO
    with zipfile.ZipFile(JAR) as jar:
        textures=[Image.open(BytesIO(jar.read('assets/minecraft/textures/block/'+n+'.png'))).convert('RGBA') for n in ['stone','dirt','oak_planks']]
    cases=[]
    for size in [64,128]:
        entry=build/f'client-render-{size}.bend';frame=build/f'client-render-{size}.ppm'
        source=SOURCE.replace('BLOCKS','['+','.join('R.Block{'+','.join(str(v)+'.0' if j<3 else str(v) for j,v in enumerate(b))+'}' for b in BLOCKS)+']').replace('CAMERA',','.join(str(v) if v>=0 else f'F32.neg({-v})' for v in CAMERA)).replace('FRAME',str(frame)).replace('JAR',str(JAR)).replace('SIZE',str(size))
        entry.write_text(source)
        binary=build/f'client-render-{size}'
        output,errors,buildtime=run([PYTHON,'tools/platform_build.py',entry,'-o',binary,'--report',build/f'client-render-{size}-build.json'],hidden=True,timeout=300)
        expected=reference(size,textures)
        mode_results={}
        for mode in ['off','on']:
            output,errors,elapsed=run([binary,'--gpu',mode],hidden=True,timeout=180)
            image=Image.open(frame);actual=image.tobytes()
            assert image.size==(size,size)
            assert actual==expected,('oracle disagreement',size,mode,sum(a!=b for a,b in zip(actual,expected)))
            observed=json.loads(next(l.split('=',1)[1] for l in output.splitlines() if l.startswith('observed=')))
            assert not observed['visible'] and not observed['key'] and not observed['app_active'],observed
            mode_results[mode]={'pixel_sha256':hashlib.sha256(actual).hexdigest(),'render_ms':int(next(l.split('=',1)[1] for l in output.splitlines() if l.startswith('render_ms='))),'warm_samples_ms':[int(l.split('=',1)[1]) for l in output.splitlines() if l.startswith('warm_render_ms=')],'process_seconds':round(elapsed,4),'window':observed,'frame_returned':True}
            (build/f'client-render-{size}-{mode}.ppm').write_bytes(frame.read_bytes())
        assert mode_results['off']['pixel_sha256']==mode_results['on']['pixel_sha256']
        cases.append({'size':[size,size],'block_count':len(BLOCKS),'oracle':'independent float32 Python ray/AABB/UV/pixel calculation with official Pillow-decoded texture bytes','pixels_compared':size*size,'build_seconds':round(buildtime,3),'modes':mode_results})
    evidence={'date':'2026-10-03','scene':'explicit finite test fixture, not a default Minecraft world','asset_path':'actual pinned JAR via Bend archive+DEFLATE+PNG','jar_sha256':hashlib.sha256(JAR.read_bytes()).hexdigest(),'source_sha256':hashlib.sha256((ROOT/'src/client_render.bend').read_bytes()).hexdigest(),'native_launch_policy':'tools/platform_build.py; BEND_MINECRAFT_LAUNCH_MODE=hidden','image_boundary':'Bend-produced PPM tree readback proves renderer pixels; hidden Window.frame alone proves no presentation','cases':cases,'command':str(PYTHON)+' tools/test_client_render.py'}
    (ROOT/'evidence/client-render-native.json').write_text(json.dumps(evidence,indent=2)+'\n')
    print(json.dumps(evidence,indent=2))
if __name__=='__main__':main()
