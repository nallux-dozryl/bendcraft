import Base
import ../src/mesh_tile_render.bend as T
import ../src/mesh_render.bend as M
import ../src/client_render.bend as R
import ../src/png.bend as P
import ../build/mesh-tile-render/fixture-001/fixtures.bend as F

def words(values:List<&2,U32>) -> String:
  match values:
    case Nil{}: ""
    case head <> Nil{}: U32.show(head)
    case head <> tail: U32.show(head) ++ "," ++ words(tail)

def mesh_image(status:Result<&2,&2,M.Error,Image>) -> Image:
  match status:
    case Done{image}: image
    case Fail{error}: Pix{0}

def mesh_result(value:R.Assets & Result<&2,&2,M.Error,Image>) -> R.Assets & Image:
  (assets,status) = value
  (assets,mesh_image(status))

def scene_quads(scene:M.Scene) -> Nat:
  M.Scene{camera,quads,settings} = scene
  List.length(&2,M.Quad,quads)

def selector(scene:M.Scene,id:U32,+width:U32,+height:U32) -> IO(Unit):
  match scene:
    case M.Scene{+camera,head <> tail,+settings}:
      IO.print("selector|" ++ U32.show(id) ++ "|" ++ U32.show(Bool.to_u32(
        T.admitted(False{},M.prepare_quad(head,0),M.basis(camera,settings),settings,0,0,width,height))))
    case _: IO.pure(Unit,Unit{})

def report(image:Image,+id:U32,+mode:String,width:U32,height:U32,before:Nat) -> IO(Unit):
  do IO<Unit>:
    IO.print("pixels|" ++ U32.show(id) ++ "|" ++ mode ++ "|" ++ words(R.pixels_of(image,width,height)))
    after : Nat <- IO.now()
    IO.print("time|" ++ U32.show(id) ++ "|" ++ mode ++ "|" ++ Nat.show(Nat.sub(after,before)))

def tile_report(value:T.Owner & R.Assets & Image,+id:U32,width:U32,height:U32,before:Nat) -> IO(R.Assets):
  (owner,assets,image) = value
  do IO<R.Assets>:
    report(image,id,"tile",width,height,before)
    IO.print("release|" ++ U32.show(id) ++ "|" ++ Nat.show(scene_quads(T.release(owner))))
    return assets

def mesh_report(value:R.Assets & Image,id:U32,mode:String,width:U32,height:U32,before:Nat) -> IO(R.Assets):
  (assets,image) = value
  do IO<R.Assets>:
    report(image,id,mode,width,height,before)
    return assets

def tested(+id:U32,+scene:M.Scene,assets:R.Assets,+width:U32,+height:U32) -> IO(R.Assets):
  do IO<R.Assets>:
    selector(scene,id,width,height)
    begin : Nat <- IO.now()
    assets : R.Assets <- tile_report(T.draw(T.prepare(scene,width,height),assets),id,width,height,begin)
    middle : Nat <- IO.now()
    assets : R.Assets <- mesh_report(mesh_result(M.render_flat(scene,assets,width,height)),id,"flat",width,height,middle)
    later : Nat <- IO.now()
    assets : R.Assets <- mesh_report(mesh_result(M.render(scene,assets,width,height)),id,"bvh",width,height,later)
    return assets

def cases(remaining:List<&2,F.Case>,assets:R.Assets) -> IO(Unit):
  match remaining:
    case Nil{}: IO.pure(Unit,Unit{})
    case F.Case{id,scene,width,height} <> tail:
      do IO<Unit>:
        assets : R.Assets <- tested(id,scene,assets,width,height)
        cases(tail,assets)

def arguments(args:List<String>) -> IO(Unit):
  cases(F.cases(),F.assets())
