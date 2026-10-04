import Base
import ./mesh_tile_render.bend as T
import ./mesh_render.bend as M
import ./client_render.bend as R
import ./player_presentation.bend as P

# Entire returned frame owner and every resource texture Image are retained.
law draw_retains_complete_owner_and_resources:
  for +owner:T.Owner
  for +textures:List<&2,R.Texture>
  {T.retained(T.draw(owner,R.Assets{textures})) == (owner,textures) : T.Owner & List<&2,R.Texture>}

law local_list_release_preserves_complete_image:
  for +image:Image
  for opaque:List<&2,M.Prepared>
  for alpha:List<&2,M.Prepared>
  {T.fin(image,opaque,alpha) == image : Image}

law straight_line_tile_has_256_backing_pixels:
  for opaque:List<&2,M.Prepared>
  for alpha:List<&2,M.Prepared>
  for camera:R.Basis
  for settings:M.Settings
  for textures:List<&2,R.Texture>
  for x:U32
  for y:U32
  for width:U32
  for height:U32
  {P.image_leaves(T.b16(opaque,alpha,camera,settings,textures,x,y,width,height)) == 256n : Nat}

# Canonical whole tile support observation calls the actual production ray_hit.
# Padding samples are None, and every admitted sample uses real M.quad_hit.
def samples(fuel:Nat,+quad:M.Prepared,+camera:R.Basis,+settings:M.Settings,+x:U32,+y:U32,+width:U32,+height:U32,+index:U32) -> List<&2,Maybe<&2,M.Hit>>:
  match fuel:
    case 0n: []
    case 1n+rest:
      +px = U32.add(x,U32.mod(index,16))
      +py = U32.add(y,U32.div(index,16))
      T.ray_hit(U32.is_lt(px,width) && U32.is_lt(py,height),quad,camera,settings,px,py,width,height) <>
        samples(rest,quad,camera,settings,x,y,width,height,U32.inc(index))

def no_hits(fuel:Nat) -> List<&2,Maybe<&2,M.Hit>>:
  match fuel:
    case 0n: []
    case 1n+rest: None{} <> no_hits(rest)

law rejected_scan_has_no_hit_in_any_sample:
  for +fuel:Nat
  for +quad:M.Prepared
  for +camera:R.Basis
  for +settings:M.Settings
  for +x:U32
  for +y:U32
  for +width:U32
  for +height:U32
  for +index:U32
  for rejected:{T.any_hit(fuel,False{},quad,camera,settings,x,y,width,height,index) == False{} : Bool}
  {samples(fuel,quad,camera,settings,x,y,width,height,index) == no_hits(fuel) : List<&2,Maybe<&2,M.Hit>>}

law actual_tile_rejection_has_complete_miss_contract:
  for +quad:M.Prepared
  for bounds:T.Screen
  for +camera:R.Basis
  for +settings:M.Settings
  for +x:U32
  for +y:U32
  for +width:U32
  for +height:U32
  for rejected:{T.admitted(T.may_overlap(bounds,x,y),quad,camera,settings,x,y,width,height) == False{} : Bool}
  {samples(256n,quad,camera,settings,x,y,width,height,0) == no_hits(256n) : List<&2,Maybe<&2,M.Hit>>}

# An omitted no-hit quad cannot change the whole production opaque traversal,
# including its incumbent Fragment, texture sampling, source index and order.
law omitted_miss_preserves_complete_opaque_trace:
  for +head:M.Prepared
  for +tail:List<&2,M.Prepared>
  for +origin:M.Vec3
  for +direction:M.Vec3
  for +settings:M.Settings
  for +textures:List<&2,R.Texture>
  for +best:M.Fragment
  for miss:{M.quad_hit(head,origin,direction,settings) == None{} : Maybe<&2,M.Hit>}
  {M.opaque_trace(head <> tail,origin,direction,settings,textures,best) ==
    M.opaque_trace(tail,origin,direction,settings,textures,best) : M.Fragment}
