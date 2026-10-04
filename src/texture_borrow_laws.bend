import Base
import ./client_render.bend as R

# A representation property, independent of coordinates or branch selection:
# every leaf has the same complete ARGB word and is reached within the depth.
# A Qua at exhausted depth is deliberately excluded: production returns zero.
def Uniform(+depth:Nat,+image:Image,+color:U32) -> Type:
  match depth image:
    case _ Pix{value}: {value == color : U32}
    case 0n Qua{tl,tr,bl,br}: Empty
    case 1n+p Qua{tl,tr,bl,br}:
      (Uniform(p,tl,color) & Uniform(p,tr,color)) & (Uniform(p,bl,color) & Uniform(p,br,color))

# Refining a uniform Pix into any certified uniform Image tree preserves its
# complete color, including alpha, at every coordinate and even a zero side.
law uniform_representation_preserves_exact_color:
  for +depth:Nat
  for +image:Image
  for +color:U32
  for +x:U32
  for +y:U32
  for +side:U32
  for uniform:Uniform(depth,image,color)
  {R.pixel_at(depth,image,x,y,side) == color : U32}

law compressed_leaf_reads_exact_word:
  for depth:Nat
  for color:U32
  for x:U32
  for y:U32
  for side:U32
  {R.pixel_at(depth,Pix{color},x,y,side) == color : U32}

law exhausted_branch_has_no_sample:
  for tl:Image
  for tr:Image
  for bl:Image
  for br:Image
  for x:U32
  for y:U32
  for side:U32
  {R.pixel_at(0n,Qua{tl,tr,bl,br},x,y,side) == 0 : U32}
