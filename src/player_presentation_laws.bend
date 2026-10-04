import Base
import ./player_presentation.bend as P
import ./mesh_render.bend as M
import ./client_render.bend as R
import ./world_mesh.bend as W

# Allocation equations bind the actual Mesh.tile/frame output. Color, padding,
# BVH, texture and scene choices do not remove their full backing allocation.
law tile_backing_allocation:
  for +n:Nat
  for +tree:M.Spatial
  for +quads:List<&2,M.Prepared>
  for +textures:List<&2,R.Texture>
  for +camera:R.Basis
  for +settings:M.Settings
  for +x:U32
  for +y:U32
  for +side:U32
  for +width:U32
  for +height:U32
  {P.image_leaves(M.tile(n,tree,quads,textures,camera,settings,x,y,side,width,height)) == P.leaves(n) : Nat}

law frame_backing_allocation:
  for +n:Nat
  for +tree:M.Spatial
  for +quads:List<&2,M.Prepared>
  for +textures:List<&2,R.Texture>
  for +camera:R.Basis
  for +settings:M.Settings
  for +x:U32
  for +y:U32
  for +side:U32
  for +width:U32
  for +height:U32
  {P.image_leaves(M.frame(n,tree,quads,textures,camera,settings,x,y,side,width,height)) == P.leaves(Nat.add(n,2n)) : Nat}

law frame_dimension_interface:
  for +width:U32
  for +height:U32
  for +settings:M.Settings
  {W.frame_valid(W.Frame{width,height,settings}) == (P.dimensions(width,height) && M.settings_valid(settings)) : Bool}

law look_delta_preserved:
  for +dx:F32
  for +dy:F32
  for plan:P.Plan
  {P.native_event(Look{dx,dy},plan) == Look{dx,dy} : Event}

law key_code_preserved:
  for +code:U32
  for +down:Bool
  for plan:P.Plan
  {P.native_event(Key{code,down},plan) == Key{code,down} : Event}

law event_order_preserved:
  for head:Event
  for tail:List<Event>
  for +plan:P.Plan
  {P.native_events(head <> tail,plan) == P.native_event(head,plan) <> P.native_events(tail,plan) : List<Event>}

law outside_pointer_rejected:
  for +pixel:U32
  for +source:U32
  for +target:U32
  for outside:{U32.is_lt(pixel,source) == False{} : Bool}
  {P.pointer_coordinate(pixel,source,target) == target : U32}
