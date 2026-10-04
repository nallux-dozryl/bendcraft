import Base
import ../src/client_render.bend as R
import ../src/png.bend as P

def number_read(value:Maybe<&2,U32>) -> U32:
  match value:
    case Some{n}: n
    case None{}: 0

def number(value:String) -> U32:
  number_read(U32.read(value))

def numbers(values:List<String>) -> List<&2,U32>:
  match values:
    case Nil{}: []
    case head <> tail: number(head) <> numbers(tail)

def mixed(+pixels:List<&2,U32>) -> Image:
  Qua{Pix{P.at(pixels,0n)},
    Qua{Pix{P.at(pixels,1n)},Pix{P.at(pixels,2n)},Pix{P.at(pixels,3n)},Pix{P.at(pixels,4n)}},
    Pix{P.at(pixels,5n)},
    Qua{Pix{P.at(pixels,6n)},Pix{P.at(pixels,7n)},
      Qua{Pix{P.at(pixels,8n)},Pix{P.at(pixels,9n)},Pix{P.at(pixels,10n)},Pix{P.at(pixels,11n)}},Pix{P.at(pixels,12n)}}}

def image(mode:String,+pixels:List<&2,U32>,width:U32,height:U32,depth:Nat,side:U32) -> Image:
  match mode:
    case "leaf": Pix{P.at(pixels,0n)}
    case "mixed": mixed(pixels)
    case _: R.texture_tree(depth,pixels,width,height,0,0,side)

def pixels(+n:Nat,+image:Image,+depth:Nat,+side:U32,+width:U32,+index:U32) -> List<&2,U32>:
  match n:
    case 0n: []
    case 1n+p:
      R.pixel_at(depth,image,U32.mod(index,width),U32.div(index,width),side) <> pixels(p,image,depth,side,width,U32.add(index,1))

def texels(+n:Nat,+texture:R.Texture,+width:U32,+height:U32,+index:U32) -> List<&2,U32>:
  match n:
    case 0n: []
    case 1n+p:
      +u = F32.div(F32.add(F32.from_nat(U32.to_nat(U32.mod(index,width))),0.5),F32.from_nat(U32.to_nat(width)))
      +v = F32.div(F32.add(F32.from_nat(U32.to_nat(U32.div(index,width))),0.5),F32.from_nat(U32.to_nat(height)))
      R.texel(texture,u,v) <> texels(p,texture,width,height,U32.add(index,1))

# Returning the complete image/texture owner after the reader is the real
# renderer's retained-assets interface; the reader must borrow that owner.
def retained_pixels(+image:Image,depth:Nat,side:U32,+width:U32,height:U32) -> List<&2,U32> & Image:
  (pixels(U32.to_nat(U32.mul(width,height)),image,depth,side,width,0),image)

def retained_texels(+texture:R.Texture,+width:U32,+height:U32) -> List<&2,U32> & R.Texture:
  (texels(U32.to_nat(U32.mul(width,height)),texture,width,height,0),texture)

def show(values:List<&2,U32>) -> String:
  match values:
    case Nil{}: ""
    case head <> tail: U32.show(head) ++ " " ++ show(tail)

def finish(pair:List<&2,U32> & R.Texture,sampled:List<&2,U32>) -> IO(Unit):
  (sampled_texels,texture) = pair
  R.Texture{width,height,side,image} = texture
  do IO<Unit>:
    IO.print(show(sampled))
    IO.print(show(sampled_texels))
    IO.pure(Unit,Image.drop(image))

def sampled(pair:List<&2,U32> & Image,+width:U32,+height:U32,side:U32) -> IO(Unit):
  (values,owner) = pair
  finish(retained_texels(R.Texture{width,height,side,owner},width,height),values)

def run(args:List<String>) -> IO(Unit):
  match args:
    case mode <> sw <> sh <> td <> ts <> sd <> ss <> ow <> oh <> raw:
      +w = number(sw)
      +h = number(sh)
      +depth = U32.to_nat(number(td))
      +side = number(ts)
      +values = numbers(raw)
      +tree = image(mode,values,w,h,depth,side)
      sampled(retained_pixels(tree,U32.to_nat(number(sd)),number(ss),number(ow),number(oh)),w,h,side)
    case _: IO.die(Unit,1,"texture_borrow_pixels: expected mode w h tree_depth tree_side sample_depth sample_side output_w output_h pixels")

def run_args(args:List<String>) -> IO(Unit):
  match args:
    case program <> rest: run(rest)
    case Nil{}: IO.die(Unit,1,"texture_borrow_pixels: missing arguments")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    run_args(args)
