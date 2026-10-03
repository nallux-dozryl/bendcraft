import Base
import ../src/mesh_render.bend as M
import ../src/client_render.bend as R
import ../src/png.bend as P
import ../src/archive.bend as A
import ../src/compression.bend as C
import ../build/mesh-render-fixtures.bend as F

type Reader is Data:
  Reader{bytes:List<&2,U32>,failed:Bool}
type RayCase is Data:
  RayCase{index:U32,quad:M.Quad,origin:M.Vec3,direction:M.Vec3}
type FrameCase is Data:
  FrameCase{index:U32,scene:M.Scene,width:U32,height:U32}
type Bundle is Data:
  Bundle{rays:List<&2,RayCase>,frames:List<&2,FrameCase>}

def raw(value:U32) -> F32:
  match value:
    case U32{word}: F32{word}

def word(~X:Type,reader:Reader,next:Reader -> U32 -> X) -> X:
  match reader:
    case Reader{a <> b <> c <> d <> tail,failed}: next(Reader{tail,failed},U32.or(a,U32.or(U32.shln(b,8n),U32.or(U32.shln(c,16n),U32.shln(d,24n)))))
    case _: next(Reader{[],True{}},0)

def number(~X:Type,reader:Reader,next:Reader -> F32 -> X) -> X:
  word(X,reader,r => n => next(r,raw(n)))

def vector(~X:Type,reader:Reader,next:Reader -> M.Vec3 -> X) -> X:
  number(X,reader,r => x => number(X,r,r => y => number(X,r,r => z => next(r,M.Vec3{x,y,z}))))

def vertex(~X:Type,reader:Reader,next:Reader -> M.Vertex -> X) -> X:
  vector(X,reader,r => p => number(X,r,r => u => number(X,r,r => v => next(r,M.Vertex{p,M.UV{u,v}}))))

def mode(value:U32,threshold:U32) -> M.Mode:
  match value:
    case 0: M.Opaque{}
    case 1: M.Cutout{threshold}
    case _: M.Translucent{}

def material(~X:Type,reader:Reader,next:Reader -> M.Material -> X) -> X:
  word(X,reader,r => texture => word(X,r,r => tint => word(X,r,r => light => number(X,r,r => shade => word(X,r,r => m => word(X,r,r => threshold => word(X,r,r => address => next(r,M.Material{texture,tint,light,shade,mode(m,threshold),P.choose(M.Address,M.Clamp{},M.Repeat{},U32.is_eq(address,0))}))))))))

def quad(~X:Type,reader:Reader,next:Reader -> M.Quad -> X) -> X:
  vertex(X,reader,r => a => vertex(X,r,r => b => vertex(X,r,r => c => vertex(X,r,r => d => material(X,r,r => m => word(X,r,r => cull => word(X,r,r => order => next(r,M.Quad{a,b,c,d,m,P.choose(M.Cull,M.Back{},M.NoCull{},U32.is_eq(cull,0)),order}))))))))

def camera(~X:Type,reader:Reader,next:Reader -> R.Camera -> X) -> X:
  number(X,reader,r => x => number(X,r,r => y => number(X,r,r => z => number(X,r,r => yaw => number(X,r,r => pitch => next(r,R.Camera{x,y,z,yaw,pitch}))))))

def settings(~X:Type,reader:Reader,next:Reader -> M.Settings -> X) -> X:
  number(X,reader,r => near => number(X,r,r => far => number(X,r,r => scale => word(X,r,r => color => next(r,M.Settings{near,far,scale,color})))))

def quads(n:Nat,reader:Reader) -> Reader & List<&2,M.Quad>:
  match n:
    case 0n: (reader,[])
    case 1n+p: quad(Reader & List<&2,M.Quad>,reader,r => q => P.paired(Reader,List<&2,M.Quad>,Reader & List<&2,M.Quad>,quads(p,r),r => tail => (r,q <> tail)))

def read_rays(n:Nat,+index:U32,reader:Reader) -> Reader & List<&2,RayCase>:
  match n:
    case 0n: (reader,[])
    case 1n+p: quad(Reader & List<&2,RayCase>,reader,r => q => vector(Reader & List<&2,RayCase>,r,r => origin => vector(Reader & List<&2,RayCase>,r,r => dir => P.paired(Reader,List<&2,RayCase>,Reader & List<&2,RayCase>,read_rays(p,U32.inc(index),r),r => tail => (r,RayCase{index,q,origin,dir} <> tail)))))

def read_frames(n:Nat,+index:U32,reader:Reader) -> Reader & List<&2,FrameCase>:
  match n:
    case 0n: (reader,[])
    case 1n+p: word(Reader & List<&2,FrameCase>,reader,r => width => word(Reader & List<&2,FrameCase>,r,r => height => camera(Reader & List<&2,FrameCase>,r,r => c => settings(Reader & List<&2,FrameCase>,r,r => s => word(Reader & List<&2,FrameCase>,r,r => count => P.paired(Reader,List<&2,M.Quad>,Reader & List<&2,FrameCase>,quads(U32.to_nat(U32.min(count,4097)),r),r => qs => P.paired(Reader,List<&2,FrameCase>,Reader & List<&2,FrameCase>,read_frames(p,U32.inc(index),r),r => tail => (r,FrameCase{index,M.Scene{c,qs,s},width,height} <> tail))))))))

def bundle(reader:Reader) -> Reader & Bundle:
  word(Reader & Bundle,reader,r => count => P.paired(Reader,List<&2,RayCase>,Reader & Bundle,read_rays(U32.to_nat(U32.min(count,8192)),0,r),r => rays => word(Reader & Bundle,r,r => count => P.paired(Reader,List<&2,FrameCase>,Reader & Bundle,read_frames(U32.to_nat(U32.min(count,512)),0,r),r => frames => (r,Bundle{rays,frames})))))

def prepared(q:M.Quad) -> M.Prepared:
  M.prepare_quad(q,0)

def hit_text(result:Maybe<&2,M.Hit>) -> String:
  match result:
    case None{}: "none"
    case Some{M.Hit{distance,u,v}}: U32.show(F32.bits(distance)) ++ "," ++ U32.show(F32.bits(u)) ++ "," ++ U32.show(F32.bits(v))

def rays(cases:List<&2,RayCase>) -> IO(Unit):
  match cases:
    case Nil{}: IO.pure(Unit,Unit{})
    case RayCase{index,quad,origin,direction} <> tail:
      do IO<Unit>:
        IO.print("ray|" ++ U32.show(index) ++ "|" ++ hit_text(M.quad_hit(prepared(quad),origin,direction,M.defaults())))
        rays(tail)

def dumped(result:Result<&2,&2,M.Error,Image>,+name:String,+width:U32,+height:U32,before:Nat) -> IO(Unit):
  match result:
    case Fail{M.Error{code}}: IO.print("frame|" ++ name ++ "|error|" ++ code)
    case Done{+image}:
      do IO<Unit>:
        # The checksum forces every output pixel before reading the end time.
        IO.print("frame|" ++ name ++ "|crc|" ++ U32.show(C.crc32(P.rgba_bytes(R.pixels_of(image,width,height)))))
        after : Nat <- IO.now()
        IO.print("frame|" ++ name ++ "|ms|" ++ Nat.show(Nat.sub(after,before)))
        R.write_ppm("build/mesh-render-" ++ name ++ ".ppm",image,width,height)

def frame_ready(pair:R.Assets & Result<&2,&2,M.Error,Image>,name:String,width:U32,height:U32,before:Nat) -> IO(R.Assets):
  (assets,result) = pair
  do IO<R.Assets>:
    dumped(result,name,width,height,before)
    return assets

def frames(cases:List<&2,FrameCase>,assets:R.Assets) -> IO(R.Assets):
  match cases:
    case Nil{}: IO.pure(R.Assets,assets)
    case FrameCase{index,scene,+width,+height} <> tail:
      do IO<R.Assets>:
        before : Nat <- IO.now()
        assets : R.Assets <- frame_ready(F.draw(scene,assets,width,height),F.frame_name(index),width,height,before)
        frames(tail,assets)

def run_bundle(value:Bundle,assets:R.Assets) -> IO(Unit):
  Bundle{ray_cases,frame_cases} = value
  do IO<Unit>:
    rays(ray_cases)
    assets : R.Assets <- frames(frame_cases,F.augment(assets))
    return Unit{}

def parsed(pair:Reader & Bundle,assets:R.Assets) -> IO(Unit):
  (reader,value) = pair
  match reader:
    case Reader{Nil{},False{}}: run_bundle(value,assets)
    case _: IO.die(Unit,1,"invalid test fixture framing")

def fixture_read(pair:File & Result<&1,&1,U32 & String,List<&2,U32>>,assets:R.Assets) -> IO(Unit):
  (file,result) = pair
  do IO<Unit>:
    File.close(file)
    bytes : List<&2,U32> <- IO.try(List<&2,U32>,IO.pure(Result<&1,&1,U32 & String,List<&2,U32>>,result))
    parsed(bundle(Reader{bytes,False{}}),assets)

def loaded(result:Result<&2,&1,A.Error,R.Assets>) -> IO(Unit):
  match result:
    case Fail{error}: IO.die(Unit,1,A.error_text(error))
    case Done{assets}:
      do IO<Unit>:
        file : File <- IO.try(File,File.open("build/mesh-render-fixtures.bin","r"))
        read : File & Result<&1,&1,U32 & String,List<&2,U32>> <- File.read_bytes(file,8388608)
        fixture_read(read,assets)

def opened(result:Result<&2,&1,A.Error,A.Archive>) -> IO(Unit):
  match result:
    case Fail{error}: IO.die(Unit,1,A.error_text(error))
    case Done{archive}:
      do IO<Unit>:
        assets : Result<&2,&1,A.Error,R.Assets> <- R.assets_loop(F.names(),archive,Done{[]})
        loaded(assets)

def main() -> IO(Unit):
  do IO<Unit>:
    archive : Result<&2,&1,A.Error,A.Archive> <- A.load(F.jar(),A.UTF8Fallback{},A.default_limits())
    opened(archive)
