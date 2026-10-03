#!/usr/bin/env python3
"""Bounded native CPU/Metal renderer integration with independent pixel oracle.

The generated scene is explicitly a verification fixture. It establishes no
Minecraft gameplay, world-generation, model-variant or lighting parity.
"""
from __future__ import annotations
import datetime,hashlib,json,math,os,select,socket,struct,subprocess,time,zipfile
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

def reference(size,textures,blocks=BLOCKS,camera=CAMERA):
    ox,oy,oz,yaw,pitch=map(f,camera)
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
            for bx,by,bz,state,material in blocks:
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
                    numerator=5 if face==3 else 1 if face==2 else 3 if face<2 else 4
                    denominator=2 if face==2 else 5
                    hit=bytes(c*numerator//denominator for c in rgb)
            g=y*60//size
            out.extend(hit or bytes((100+g,160+g//2,235)))
    return bytes(out)

def entry_integration(textures):
    from PIL import Image
    from test_server import Client,free_port
    binary=ROOT/'build/minecraft-client'
    report=ROOT/'build/client-render-entry-build.json'
    # Rebuild the actual entry through the same guarded launch path.
    output,errors,buildtime=run([PYTHON,'tools/platform_build.py','client.bend','-o',binary,'--report',report],hidden=True,timeout=300)
    dump=ROOT/'build/client-render-entry.ppm'
    if dump.exists():dump.unlink()
    port=free_port();token='client-render-integration-token'
    env=os.environ.copy();env.update(BEND_MINECRAFT_LAUNCH_MODE='hidden',MC_DEV_TOKEN=token,MC_LIVE_PORT=str(port))
    floor=[(x,0,z,0,1 if x==2 else 0) for z in range(-3,3) for x in range(-3,3)]
    raised=[(1,1,1,0,1),(2,1,2,0,2),(2,2,2,0,2)]
    blocks=sorted(floor+raised,key=lambda b:(b[2],b[1],b[0]))
    camera=(.5,2.62,-2.5,0.,.2)
    expected_before=reference(128,textures,blocks,camera)
    expected_after=reference(128,textures,sorted([(x,y,z,0,2) for x,y,z,_,_ in floor]+raised,key=lambda b:(b[2],b[1],b[0])),camera)
    process=subprocess.Popen([str(binary),'--gpu','off','--verification-fixture','--frames','100','--dump',str(dump)],cwd=ROOT,env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,bufsize=0)
    client=None
    def pixels(expected=None):
        deadline=time.monotonic()+15
        while time.monotonic()<deadline:
            try:
                image=Image.open(dump);data=image.tobytes()
                if image.size==(128,128) and (expected is None or data==expected):return data
            except (OSError,ValueError):pass
            if process.poll() is not None:break
            time.sleep(.01)
        raise AssertionError('actual entry did not produce expected complete image')
    try:
        assert select.select([process.stdout],[],[],60)[0],'actual client startup timed out'
        ready_line=process.stdout.readline();ready=json.loads(ready_line)
        assert ready['event']=='server.ready' and ready['port']==port,ready
        # These fixture positions and material assignments are independently
        # stated from the explicit scene contract, then checked against API
        # state and a pixel oracle. State IDs are resolved at the real endpoint.
        before=pixels(expected_before)
        (ROOT/'build/client-render-entry-before.ppm').write_bytes(b'P6\n128 128\n255\n'+before)
        client=Client(port)
        client.result('session.open',{'mode':'developer','token':token})
        initial=client.result('world.clock')
        assert initial['tick']==1 and initial['revision']==47 and initial['paused'] is True,initial
        air=client.result('registry.state.resolve',{'name':'minecraft:air','properties':{},'policy':'defaults'})['state']
        planks=client.result('registry.state.resolve',{'name':'minecraft:oak_planks','properties':{},'policy':'defaults'})['state']
        for x,_,z,_,_ in floor:
            position={'dimension':'minecraft:overworld','x':x,'y':0,'z':z}
            assert client.result('world.block.get',position)['state']!=air
            client.result('world.block.set',position|{'state':planks})
        stepped=client.result('simulation.step',{'ticks':1})
        assert stepped['tick']==2 and stepped['revision']==83 and stepped['pending']==0,stepped
        assert client.result('world.block.get',{'dimension':'minecraft:overworld','x':0,'y':0,'z':0})['state']==planks
        after=pixels(expected_after)
        assert before!=after,'same-world TCP edits were not visible in the renderer'
        (ROOT/'build/client-render-entry-after.ppm').write_bytes(b'P6\n128 128\n255\n'+after)
        client.close();client=None
        output,errors=process.communicate(timeout=60)
        output=output.decode();errors=errors.decode()
        assert process.returncode==0,(process.returncode,output,errors)
        snapshots=[json.loads(line) for line in output.splitlines() if line.startswith('{') and json.loads(line).get('event')=='client.snapshot']
        assert any(row['tick']==1 and row['revision']==47 and row['blocks']==39 for row in snapshots),snapshots[:5]
        assert any(row['tick']==2 and row['revision']==83 and row['blocks']==39 for row in snapshots),snapshots[-5:]
        assert len(snapshots)==100,len(snapshots)
        with socket.socket() as probe:
            probe.settimeout(.5)
            assert probe.connect_ex(('127.0.0.1',port))!=0,'client teardown left its listener open'
        return {'entry':'client.bend','frames':len(snapshots),'viewport':[128,128],'fixture_blocks':39,'initial_clock':initial,'after_tcp_edits_clock':stepped,'remote_block_updates':36,'before_pixel_sha256':hashlib.sha256(before).hexdigest(),'after_pixel_sha256':hashlib.sha256(after).hexdigest(),'independent_pixel_comparisons':32768,'shared_actor':'actual authenticated TCP edits became exact independently expected renderer pixels and snapshot revisions','teardown':'actor stop acknowledged; process exited0; real TCP port refused after exit','build_seconds':round(buildtime,3),'entry_source_sha256':hashlib.sha256((ROOT/'client.bend').read_bytes()).hexdigest()}
    finally:
        if client is not None:client.close()
        if process.poll() is None:process.kill();process.communicate()

def control_integration(textures):
    from PIL import Image
    from test_server import free_port
    entry=ROOT/'build/client-render-controls.bend'
    dump=ROOT/'build/client-render-controls.ppm'
    source=r'''import Base
import ../client.bend as Entry
import ../src/client_world.bend as W
import ../src/client_render.bend as R
import ../src/game.bend as G
import ../src/server.bend as S
import ../src/png.bend as P
import ../src/f64.bend as F
import ../src/movement.bend as M
import ../src/archive.bend as A

def bits(value:F.F64) -> String:
  F.F64{hi,lo} = value
  "[" ++ U32.show(hi) ++ "," ++ U32.show(lo) ++ "]"

def body_json(body:M.Body) -> String:
  M.Body{M.Vec3{x,y,z},box,velocity,width,height,ground,horizontal,vertical,below} = body
  "{\"event\":\"control.body\",\"position_bits\":[" ++ bits(x) ++ "," ++ bits(y) ++ "," ++ bits(z) ++ "]}"

def main() -> IO(Unit):
  do IO<Unit>:
    loaded : Result<&2,&1,A.Error,R.Assets> <- R.load_assets("JAR")
    assets : R.Assets <- Entry.ready_assets(loaded)
    engine : G.Engine <- G.load()
    world : W.State <- Entry.ready_world(W.fixture(engine))
    +handle : S.Handle<W.State> <- S.start_handle(~W.State,~S.Driver{W.step,W.dispatch},world)
    got : Result<&2,&2,String,R.Snapshot> <- S.local_call(W.State,Result<&2,&2,String,R.Snapshot>,handle,state => W.snapshot(state,128,128))
    snapshot : R.Snapshot <- Entry.snapshot_ready(got)
    keep : Bool <- Entry.events_camera([Key{119,True{}},Look{12.0,F32.neg(7.0)}],handle,Entry.camera_of(snapshot))
    IO.print(P.choose(String,"control_keep=true","control_keep=false",keep))
    body : M.Body <- S.local_call(W.State,M.Body,handle,W.body)
    IO.print(body_json(body))
    Entry.window_start(Entry.Options{True{},Some{1n},Some{"DUMP"},"JAR"},assets,handle,False{})
'''
    entry.write_text(source.replace('JAR',str(JAR)).replace('DUMP',str(dump)))
    binary=ROOT/'build/client-render-controls'
    output,errors,buildtime=run([PYTHON,'tools/platform_build.py',entry,'-o',binary,'--report',ROOT/'build/client-render-controls-build.json'],hidden=True,timeout=300)
    port=free_port();env=os.environ.copy();env.update(BEND_MINECRAFT_LAUNCH_MODE='hidden',MC_DEV_TOKEN='client-control-integration-token',MC_LIVE_PORT=str(port))
    p=subprocess.run([str(binary),'--gpu','off'],cwd=ROOT,env=env,text=True,capture_output=True,timeout=60)
    assert p.returncode==0,(p.stdout,p.stderr)
    assert 'control_keep=true' in p.stdout,p.stdout
    body=json.loads(next(line for line in p.stdout.splitlines() if line.startswith('{') and json.loads(line).get('event')=='control.body'))
    expected_bits=[list(struct.unpack('>II',struct.pack('>d',v))) for v in [.5,1.,-2.25]]
    assert body['position_bits']==expected_bits,(body,expected_bits)
    blocks=sorted([(x,0,z,0,1 if x==2 else 0) for z in range(-3,3) for x in range(-3,3)]+[(1,1,1,0,1),(2,1,2,0,2),(2,2,2,0,2)],key=lambda b:(b[2],b[1],b[0]))
    camera=(.5,2.62,-2.25,mul(12,.0025),add(f(.2),mul(-7,.0025)))
    actual=Image.open(dump).tobytes();expected=reference(128,textures,blocks,camera)
    assert actual==expected,('camera image mismatch',sum(a!=b for a,b in zip(actual,expected)))
    return {'events':'explicit synthetic Bend Key(W,down)+Look(12,-7), no focused hardware-input claim','body_position_f64_bits':expected_bits,'camera_f32':[f(v) for v in camera],'pixels_compared':16384,'pixel_sha256':hashlib.sha256(actual).hexdigest(),'build_seconds':round(buildtime,3),'shared_actor':True,'hidden_launch':True,'exit_code':p.returncode}

def main():
    from PIL import Image
    build=ROOT/'build';build.mkdir(exist_ok=True)
    from io import BytesIO
    with zipfile.ZipFile(JAR) as jar:
        textures=[Image.open(BytesIO(jar.read('assets/minecraft/textures/block/'+n+'.png'))).convert('RGBA') for n in ['stone','dirt','oak_planks']]
    cases=[]
    for backend,size in [('cpu',64),('gpu',64),('gpu',128)]:
        entry=build/f'client-render-{backend}-{size}.bend';frame=build/f'client-render-{backend}-{size}.ppm'
        source=SOURCE.replace('BLOCKS','['+','.join('R.Block{'+','.join(str(v)+'.0' if j<3 else str(v) for j,v in enumerate(b))+'}' for b in BLOCKS)+']').replace('CAMERA',','.join(str(v) if v>=0 else f'F32.neg({-v})' for v in CAMERA)).replace('FRAME',str(frame)).replace('JAR',str(JAR)).replace('SIZE',str(size))
        if backend=='cpu':source=source.replace('R.render_gpu(', 'R.render(')
        entry.write_text(source)
        binary=build/f'client-render-{backend}-{size}'
        output,errors,buildtime=run([PYTHON,'tools/platform_build.py',entry,'-o',binary,'--report',build/f'client-render-{backend}-{size}-build.json'],hidden=True,timeout=300)
        expected=reference(size,textures)
        mode_results={}
        for mode in (['off'] if backend=='cpu' else ['off','on']):
            output,errors,elapsed=run([binary,'--gpu',mode],hidden=True,timeout=180)
            image=Image.open(frame);actual=image.tobytes()
            assert image.size==(size,size)
            assert actual==expected,('oracle disagreement',size,mode,sum(a!=b for a,b in zip(actual,expected)))
            observed=json.loads(next(l.split('=',1)[1] for l in output.splitlines() if l.startswith('observed=')))
            assert not observed['visible'] and not observed['key'] and not observed['app_active'],observed
            mode_results[mode]={'pixel_sha256':hashlib.sha256(actual).hexdigest(),'render_ms':int(next(l.split('=',1)[1] for l in output.splitlines() if l.startswith('render_ms='))),'warm_samples_ms':[int(l.split('=',1)[1]) for l in output.splitlines() if l.startswith('warm_render_ms=')],'process_seconds':round(elapsed,4),'window':observed,'frame_returned':True}
            (build/f'client-render-{backend}-{size}-{mode}.ppm').write_bytes(frame.read_bytes())
        if backend=='gpu':assert mode_results['off']['pixel_sha256']==mode_results['on']['pixel_sha256']
        cases.append({'backend':backend,'size':[size,size],'block_count':len(BLOCKS),'oracle':'independent float32 Python ray/AABB/UV/pixel calculation with official Pillow-decoded texture bytes','pixels_compared':size*size,'build_seconds':round(buildtime,3),'modes':mode_results})
    entry=entry_integration(textures)
    controls=control_integration(textures)
    evidence={'controls_integration':controls,'entry_integration':entry,'date':datetime.datetime.now().astimezone().date().isoformat(),'scene':'explicit finite test fixture, not a default Minecraft world','asset_path':'actual pinned JAR via Bend archive+DEFLATE+PNG','jar_sha256':hashlib.sha256(JAR.read_bytes()).hexdigest(),'source_sha256':hashlib.sha256((ROOT/'src/client_render.bend').read_bytes()).hexdigest(),'native_launch_policy':'tools/platform_build.py; BEND_MINECRAFT_LAUNCH_MODE=hidden','image_boundary':'Bend-produced PPM tree readback proves renderer pixels; hidden Window.frame alone proves no presentation','cases':cases,'command':str(PYTHON)+' tools/test_client_render.py'}
    (ROOT/'evidence/client-render-native.json').write_text(json.dumps(evidence,indent=2)+'\n')
    print(json.dumps(evidence,indent=2))
if __name__=='__main__':main()
