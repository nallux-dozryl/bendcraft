import Base
import ./texture_borrow_laws.bend as L
import ./client_render.bend as R

def uniform_lookup(+depth:Nat,+image:Image,+color:U32,+x:U32,+y:U32,+side:U32,right:Bool,bottom:Bool,uniform:L.Uniform(depth,image,color)) ->
    {R.pixel_lookup(depth,image,x,y,side,right,bottom) == color : U32}:
  match depth image right bottom:
    case _ Pix{value} _ _: uniform
    case 0n Qua{tl,tr,bl,br} _ _: match uniform:
    case 1n+p Qua{tl,tr,bl,br} False{} False{}:
      ((a,b),(c,d)) = uniform
      +half = U32.div(side,2)
      +nx = U32.mod(x,half)
      +ny = U32.mod(y,half)
      uniform_lookup(p,tl,color,nx,ny,half,U32.is_ge(nx,U32.div(half,2)),U32.is_ge(ny,U32.div(half,2)),a)
    case 1n+p Qua{tl,tr,bl,br} True{} False{}:
      ((a,b),(c,d)) = uniform
      +half = U32.div(side,2)
      +nx = U32.mod(x,half)
      +ny = U32.mod(y,half)
      uniform_lookup(p,tr,color,nx,ny,half,U32.is_ge(nx,U32.div(half,2)),U32.is_ge(ny,U32.div(half,2)),b)
    case 1n+p Qua{tl,tr,bl,br} False{} True{}:
      ((a,b),(c,d)) = uniform
      +half = U32.div(side,2)
      +nx = U32.mod(x,half)
      +ny = U32.mod(y,half)
      uniform_lookup(p,bl,color,nx,ny,half,U32.is_ge(nx,U32.div(half,2)),U32.is_ge(ny,U32.div(half,2)),c)
    case 1n+p Qua{tl,tr,bl,br} True{} True{}:
      ((a,b),(c,d)) = uniform
      +half = U32.div(side,2)
      +nx = U32.mod(x,half)
      +ny = U32.mod(y,half)
      uniform_lookup(p,br,color,nx,ny,half,U32.is_ge(nx,U32.div(half,2)),U32.is_ge(ny,U32.div(half,2)),d)

def L.uniform_representation_preserves_exact_color(depth,image,color,x,y,side,uniform):
  uniform_lookup(depth,image,color,x,y,side,U32.is_ge(x,U32.div(side,2)),U32.is_ge(y,U32.div(side,2)),uniform)

def L.compressed_leaf_reads_exact_word(depth,color,x,y,side):
  match depth:
    case 0n: {==}
    case 1n+p: {==}

def L.exhausted_branch_has_no_sample(tl,tr,bl,br,x,y,side): {==}
