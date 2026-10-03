import Base
import ./png.bend as P
import ./archive.bend as A

# Render-only F32 values are narrowed from the authoritative simulation.
# Block list is an immutable world snapshot; renderer never advances a tick.
type Block is Data:
  Block{x: F32,y: F32,z: F32,state: U32,material: U32}

type Camera is Data:
  Camera{x: F32,y: F32,z: F32,yaw: F32,pitch: F32}

type Snapshot is Data:
  Snapshot{tick: Nat,revision: Nat,blocks: List<&2,Block>,camera: Camera}

type Texture is Data:
  Texture{width: U32,height: U32,side: U32,image: Image}

type Assets is Type:
  Assets{textures: List<&2,Texture>}

type Basis is Data:
  Basis{x:F32,y:F32,z:F32,rx:F32,rz:F32,ux:F32,uy:F32,uz:F32,fx:F32,fy:F32,fz:F32,scale:F32}

type Direction is Data:
  Direction{x:F32,y:F32,z:F32}

type Interval is Data:
  Interval{near:F32,far:F32,face:U32}

type Hit is Data:
  Hit{distance:F32,material:U32,face:U32,u:F32,v:F32,found:Bool}

def asset_names() -> List<&2,String>:
  ["assets/minecraft/textures/block/stone.png","assets/minecraft/textures/block/dirt.png","assets/minecraft/textures/block/oak_planks.png"]

def side_for(+value: U32) -> U32:
  U32.shln(1,P.array_depth(13n,value,1))

def texture_tree(+n: Nat,+pixels: List<&2,U32>,+width: U32,+height: U32,+x: U32,+y: U32,+side: U32) -> Image:
  match n:
    case 0n: Pix{P.choose(U32,P.at(pixels,U32.to_nat(U32.add(U32.mul(y,width),x))),0,U32.is_lt(x,width) && U32.is_lt(y,height))}
    case 1n+p:
      +half = U32.div(side,2)
      Qua{texture_tree(p,pixels,width,height,x,y,half),texture_tree(p,pixels,width,height,U32.add(x,half),y,half),texture_tree(p,pixels,width,height,x,U32.add(y,half),half),texture_tree(p,pixels,width,height,U32.add(x,half),U32.add(y,half),half)}

def texture(decoded: P.Decoded) -> Texture:
  P.Decoded{+w,+h,+pixels} = decoded
  # Animated atlases retain their full RGBA decode. This supported material
  # set has square textures; selecting animation frames belongs to the model layer.
  +side = side_for(U32.max(w,h))
  Texture{w,h,side,texture_tree(P.array_depth(13n,side,1),pixels,w,h,0,0,side)}

def quadrant(tl: Image,tr: Image,bl: Image,br: Image,right: Bool,bottom: Bool) -> Image:
  match right bottom:
    case False{} False{}: tl
    case True{} False{}: tr
    case False{} True{}: bl
    case True{} True{}: br

def pixel_at(n: Nat,image: Image,+x: U32,+y: U32,+side: U32) -> U32:
  match n image:
    case _ Pix{color}: color
    case 0n Qua{tl,tr,bl,br}: 0
    case 1n+p Qua{tl,tr,bl,br}:
      +half = U32.div(side,2)
      pixel_at(p,quadrant(tl,tr,bl,br,U32.is_ge(x,half),U32.is_ge(y,half)),U32.mod(x,half),U32.mod(y,half),half)

def fractional(+x: F32) -> F32:
  F32.sub(x,F32.floor(x))

def texel(texture: Texture,+u: F32,+v: F32) -> U32:
  Texture{+w,+h,+side,image} = texture
  pixel_at(P.array_depth(13n,side,1),image,U32.min(U32.sub(w,1),F32.to_u32(F32.mul(F32.from_nat(U32.to_nat(w)),fractional(u)))),U32.min(U32.sub(h,1),F32.to_u32(F32.mul(F32.from_nat(U32.to_nat(h)),fractional(v)))),side)

def material(textures: List<&2,Texture>,index: Nat,u: F32,v: F32) -> U32:
  match textures index:
    case Nil{} _: 4294902015
    case head <> tail 0n: texel(head,u,v)
    case head <> tail 1n+p: material(tail,p,u,v)

def basis(camera: Camera) -> Basis:
  Camera{x,y,z,+yaw,+pitch} = camera
  +sy = F32.sin(yaw)
  +cy = F32.cos(yaw)
  +sp = F32.sin(pitch)
  +cp = F32.cos(pitch)
  Basis{x,y,z,cy,sy,F32.neg(F32.mul(sy,sp)),cp,F32.mul(cy,sp),F32.neg(F32.mul(sy,cp)),F32.neg(sp),F32.mul(cy,cp),0.7002075382}

def direction(basis: Basis,+sx: U32,+sy: U32,+width: U32,+height: U32) -> Direction:
  Basis{x,y,z,+rx,+rz,+ux,+uy,+uz,+fx,+fy,+fz,+scale} = basis
  +u = F32.mul(F32.sub(F32.div(F32.mul(F32.add(F32.from_nat(U32.to_nat(sx)),0.5),2.0),F32.from_nat(U32.to_nat(width))),1.0),F32.mul(scale,F32.div(F32.from_nat(U32.to_nat(width)),F32.from_nat(U32.to_nat(height)))))
  +v = F32.mul(F32.sub(1.0,F32.div(F32.mul(F32.add(F32.from_nat(U32.to_nat(sy)),0.5),2.0),F32.from_nat(U32.to_nat(height)))),scale)
  +dx = F32.add(fx,F32.add(F32.mul(rx,u),F32.mul(ux,v)))
  +dy = F32.add(fy,F32.mul(uy,v))
  +dz = F32.add(fz,F32.add(F32.mul(rz,u),F32.mul(uz,v)))
  +len = F32.sqrt(F32.add(F32.mul(dx,dx),F32.add(F32.mul(dy,dy),F32.mul(dz,dz))))
  Direction{F32.div(dx,len),F32.div(dy,len),F32.div(dz,len)}

def slab_choose(+origin: F32,+dir: F32,+low: F32,+negative: U32,positive: U32,parallel: Bool) -> Interval:
  match parallel:
    case True{}: P.choose(Interval,Interval{F32.neg(100000000000000000000.0),100000000000000000000.0,negative},Interval{100000000000000000000.0,F32.neg(100000000000000000000.0),negative},F32.is_ge(origin,low) && F32.is_le(origin,F32.add(low,1.0)))
    case False{}:
      +a = F32.div(F32.sub(low,origin),dir)
      +b = F32.div(F32.sub(F32.add(low,1.0),origin),dir)
      Interval{F32.min(a,b),F32.max(a,b),P.choose(U32,negative,positive,F32.is_gt(dir,0.0))}

def slab(+origin: F32,+dir: F32,low: F32,negative: U32,positive: U32) -> Interval:
  slab_choose(origin,dir,low,negative,positive,F32.is_lt(F32.abs(dir),0.00000001))

def combine(a: Interval,b: Interval) -> Interval:
  match a b:
    case Interval{+an,af,ai} Interval{+bn,bf,bi}: Interval{F32.max(an,bn),F32.min(af,bf),P.choose(U32,ai,bi,F32.is_ge(an,bn))}

def hit_uv(face: U32,+x: F32,+y: F32,+z: F32) -> F32 & F32:
  match face:
    case 0: (z,F32.sub(1.0,y))
    case 1: (F32.sub(1.0,z),F32.sub(1.0,y))
    case 2: (x,F32.sub(1.0,z))
    case 3: (x,z)
    case 4: (F32.sub(1.0,x),F32.sub(1.0,y))
    case _: (x,F32.sub(1.0,y))

def hit_selected(valid: Bool,distance: F32,material: U32,face: U32,uv: F32 & F32,old: Hit) -> Hit:
  match valid:
    case False{}: old
    case True{}:
      (u,v) = uv
      Hit{distance,material,face,u,v,True{}}

def block_interval(interval: Interval,material: U32,+ox:F32,+oy:F32,+oz:F32,+dx:F32,+dy:F32,+dz:F32,bx:F32,by:F32,bz:F32,old:F32,best:Hit) -> Hit:
  Interval{+near,+far,+face} = interval
  hit_selected(F32.is_ge(near,0.0001) && F32.is_le(near,far) && F32.is_lt(near,old),near,material,face,hit_uv(face,F32.sub(F32.add(ox,F32.mul(dx,near)),bx),F32.sub(F32.add(oy,F32.mul(dy,near)),by),F32.sub(F32.add(oz,F32.mul(dz,near)),bz)),best)

def block_hit(block: Block,camera: Basis,dir: Direction,+best: Hit) -> Hit:
  match block camera dir best:
    case Block{+bx,+by,+bz,state,material} Basis{+ox,+oy,+oz,rx,rz,ux,uy,uz,fx,fy,fz,scale} Direction{+dx,+dy,+dz} Hit{+old,om,of,ou,ov,found}:
      block_interval(combine(combine(slab(ox,dx,bx,0,1),slab(oy,dy,by,2,3)),slab(oz,dz,bz,4,5)),material,ox,oy,oz,dx,dy,dz,bx,by,bz,old,best)

def trace(blocks: List<&2,Block>,+camera: Basis,+dir: Direction,best: Hit) -> Hit:
  match blocks:
    case Nil{}: best
    case block <> tail: trace(tail,camera,dir,block_hit(block,camera,dir,best))

def shade(+color: U32,+face: U32) -> U32:
  +level = P.choose(U32,255,P.choose(U32,153,P.choose(U32,204,127,U32.is_eq(face,2)),U32.is_lt(face,2)),U32.is_eq(face,3))
  P.argb(255,U32.div(U32.mul(U32.and(U32.shrn(color,16n),255),level),255),U32.div(U32.mul(U32.and(U32.shrn(color,8n),255),level),255),U32.div(U32.mul(U32.and(color,255),level),255))

def hit_color(hit: Hit,textures: List<&2,Texture>,sky: U32) -> U32:
  match hit:
    case Hit{distance,m,face,u,v,True{}}: shade(material(textures,U32.to_nat(m),u,v),face)
    case Hit{distance,m,face,u,v,False{}}: sky

def sky(+y: U32,height: U32) -> U32:
  +g = U32.div(U32.mul(y,60),height)
  P.argb(255,U32.add(100,g),U32.add(160,U32.div(g,2)),235)

def pixel(+blocks: List<&2,Block>,textures: List<&2,Texture>,+camera: Basis,+x: U32,+y: U32,+width: U32,+height: U32) -> U32:
  hit_color(trace(blocks,camera,direction(camera,x,y,width,height),Hit{64.0,0,0,0.0,0.0,False{}}),textures,sky(y,height))

# Flat 4x4 tiles under one balanced fork tree. Snapshot lists are borrowed.
def tile(+n: Nat,+blocks: List<&2,Block>,+textures: List<&2,Texture>,+camera: Basis,+x: U32,+y: U32,+side: U32,+width: U32,+height: U32) -> Image:
  match n:
    case 0n: Pix{pixel(blocks,textures,camera,x,y,width,height)}
    case 1n+p:
      +half = U32.div(side,2)
      Qua{tile(p,blocks,textures,camera,x,y,half,width,height),tile(p,blocks,textures,camera,U32.add(x,half),y,half,width,height),tile(p,blocks,textures,camera,x,U32.add(y,half),half,width,height),tile(p,blocks,textures,camera,U32.add(x,half),U32.add(y,half),half,width,height)}

def frame(+n: Nat,+blocks: List<&2,Block>,+textures: List<&2,Texture>,+camera: Basis,+x: U32,+y: U32,+side: U32,+width: U32,+height: U32) -> Image:
  match n:
    case 0n: tile(2n,blocks,textures,camera,x,y,side,width,height)
    case 1n+p:
      +half = U32.div(side,2)
      a b c d = frame(p,blocks,textures,camera,x,y,half,width,height) frame(p,blocks,textures,camera,U32.add(x,half),y,half,width,height)
        frame(p,blocks,textures,camera,x,U32.add(y,half),half,width,height) frame(p,blocks,textures,camera,U32.add(x,half),U32.add(y,half),half,width,height)
      Qua{a,b,c,d}

def render(+snapshot: Snapshot,assets: Assets,+width: U32,+height: U32) -> Assets & Image:
  match snapshot assets:
    case Snapshot{tick,revision,+blocks,camera} Assets{+textures}:
      +depth = P.array_depth(13n,U32.max(width,height),1)
      +side = U32.shln(1,depth)
      (Assets{textures},frame(Nat.sub(depth,2n),blocks,textures,basis(camera),0,0,side,width,height))

def render_gpu(+snapshot: Snapshot,assets: Assets,+width: U32,+height: U32) -> Assets & Image:
  match snapshot assets:
    case Snapshot{tick,revision,+blocks,camera} Assets{+textures}:
      +depth = P.array_depth(13n,U32.max(width,height),1)
      +side = U32.shln(1,depth)
      (Assets{textures},frame!(Nat.sub(depth,2n),blocks,textures,basis(camera),0,0,side,width,height))

def asset_decoded(result: Result<&2,&1,P.Error,P.Decoded>,name: String) -> Result<&2,&2,A.Error,Texture>:
  match result:
    case Fail{P.Error{code}}: Fail{A.Error{"PNG",0,name ++ ": " ++ code}}
    case Done{decoded}: Done{texture(decoded)}

def asset_read(result: Result<&2,&2,A.Error,List<&2,U32>>,name: String) -> Result<&2,&2,A.Error,Texture>:
  match result:
    case Fail{error}: Fail{error}
    case Done{bytes}: asset_decoded(P.decode(bytes,P.default_limits()),name)

def texture_accumulate(result: Result<&2,&2,A.Error,Texture>,reversed: List<&2,Texture>) -> Result<&2,&2,A.Error,List<&2,Texture>>:
  match result:
    case Fail{error}: Fail{error}
    case Done{texture}: Done{texture <> reversed}

def close_assets(archive: A.Archive,result: Result<&2,&2,A.Error,List<&2,Texture>>) -> IO(Result<&2,&1,A.Error,Assets>):
  match result:
    case Fail{error}:
      do IO<Result<&2,&1,A.Error,Assets>>:
        A.Archive.close(archive)
        return Fail{error}
    case Done{textures}:
      do IO<Result<&2,&1,A.Error,Assets>>:
        A.Archive.close(archive)
        return Done{Assets{List.reverse(&2,Texture,textures)}}

def assets_loop(names: List<&2,String>,archive: A.Archive,result: Result<&2,&2,A.Error,List<&2,Texture>>) -> IO(Result<&2,&1,A.Error,Assets>):
  match names result:
    case _ Fail{error}: close_assets(archive,Fail{error})
    case Nil{} _: close_assets(archive,result)
    case +name <> tail Done{reversed}:
      do IO<Result<&2,&1,A.Error,Assets>>:
        read : A.Archive & Result<&2,&2,A.Error,List<&2,U32>> <- A.Archive.read(archive,name)
        P.paired(A.Archive,Result<&2,&2,A.Error,List<&2,U32>>,IO(Result<&2,&1,A.Error,Assets>),read,archive => bytes => assets_loop(tail,archive,texture_accumulate(asset_read(bytes,name),reversed)))

def assets_opened(result: Result<&2,&1,A.Error,A.Archive>) -> IO(Result<&2,&1,A.Error,Assets>):
  match result:
    case Fail{error}: IO.pure(Result<&2,&1,A.Error,Assets>,Fail{error})
    case Done{archive}: assets_loop(asset_names(),archive,Done{[]})

def load_assets(path: String) -> IO(Result<&2,&1,A.Error,Assets>):
  do IO<Result<&2,&1,A.Error,Assets>>:
    opened : Result<&2,&1,A.Error,A.Archive> <- A.load(path,A.UTF8Fallback{},A.default_limits())
    assets_opened(opened)

def image_pixels(n: Nat,+index: U32,+image: Image,+width: U32,+depth: Nat,+side: U32,reversed: List<&2,U32>) -> List<&2,U32>:
  match n:
    case 0n: List.reverse(&2,U32,reversed)
    case 1n+p: image_pixels(p,U32.inc(index),image,width,depth,side,pixel_at(depth,image,U32.mod(index,width),U32.div(index,width),side) <> reversed)

def pixels_of(+image: Image,+width: U32,+height: U32) -> List<&2,U32>:
  +depth = P.array_depth(13n,U32.max(width,height),1)
  image_pixels(U32.to_nat(U32.mul(width,height)),0,image,width,depth,U32.shln(1,depth),[])

def ppm_bytes_go(pixels: List<&2,U32>,reversed: List<&2,U32>) -> List<&2,U32>:
  match pixels:
    case Nil{}: List.reverse(&2,U32,reversed)
    case +pixel <> tail: ppm_bytes_go(tail,U32.and(pixel,255) <> U32.and(U32.shrn(pixel,8n),255) <> U32.and(U32.shrn(pixel,16n),255) <> reversed)

def ppm_written(result: File & Result<&1,&1,U32 & String,Unit>) -> IO(Unit):
  (file,written) = result
  do IO<Unit>:
    Unit <- IO.try(Unit,IO.pure(Result<&1,&1,U32 & String,Unit>,written))
    File.close(file)

def write_ppm(path: String,+image: Image,+width: U32,+height: U32) -> IO(Unit):
  do IO<Unit>:
    file : File <- IO.try(File,File.open(path,"w"))
    header : File & Result<&1,&1,U32 & String,Unit> <- File.write(file,"P6\n" ++ U32.show(width) ++ " " ++ U32.show(height) ++ "\n255\n")
    P.paired(File,Result<&1,&1,U32 & String,Unit>,IO(Unit),header,file => result => (
      do IO<Unit>:
        Unit <- IO.try(Unit,IO.pure(Result<&1,&1,U32 & String,Unit>,result))
        written : File & Result<&1,&1,U32 & String,Unit> <- File.write_bytes(file,ppm_bytes_go(pixels_of(image,width,height),[]))
        ppm_written(written)
    ))
