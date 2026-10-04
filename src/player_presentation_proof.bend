import Base
import ./player_presentation.bend as P
import ./player_presentation_laws.bend as L
import ./mesh_render.bend as M
import ./client_render.bend as R

def four_equal(+a:Nat,+b:Nat,+c:Nat,+d:Nat,+value:Nat,
    ea:{a == value : Nat},eb:{b == value : Nat},ec:{c == value : Nat},ed:{d == value : Nat}) ->
    {Nat.add(a,Nat.add(b,Nat.add(c,d))) == Nat.add(value,Nat.add(value,Nat.add(value,value))) : Nat}:
  Equal.trans(Nat,Nat.add(a,Nat.add(b,Nat.add(c,d))),Nat.add(value,Nat.add(b,Nat.add(c,d))),
    Nat.add(value,Nat.add(value,Nat.add(value,value))),
    Equal.cong(Nat,Nat,x => Nat.add(x,Nat.add(b,Nat.add(c,d))),a,value,ea),
    Equal.trans(Nat,Nat.add(value,Nat.add(b,Nat.add(c,d))),Nat.add(value,Nat.add(value,Nat.add(c,d))),
      Nat.add(value,Nat.add(value,Nat.add(value,value))),
      Equal.cong(Nat,Nat,x => Nat.add(value,Nat.add(x,Nat.add(c,d))),b,value,eb),
      Equal.trans(Nat,Nat.add(value,Nat.add(value,Nat.add(c,d))),Nat.add(value,Nat.add(value,Nat.add(value,d))),
        Nat.add(value,Nat.add(value,Nat.add(value,value))),
        Equal.cong(Nat,Nat,x => Nat.add(value,Nat.add(value,Nat.add(x,d))),c,value,ec),
        Equal.cong(Nat,Nat,x => Nat.add(value,Nat.add(value,Nat.add(value,x))),d,value,ed))))

def L.tile_backing_allocation(n,tree,quads,textures,camera,settings,x,y,side,width,height):
  match n:
    case 0n: {==}
    case 1n+rest:
      +half = U32.div(side,2)
      four_equal(
        P.image_leaves(M.tile(rest,tree,quads,textures,camera,settings,x,y,half,width,height)),
        P.image_leaves(M.tile(rest,tree,quads,textures,camera,settings,U32.add(x,half),y,half,width,height)),
        P.image_leaves(M.tile(rest,tree,quads,textures,camera,settings,x,U32.add(y,half),half,width,height)),
        P.image_leaves(M.tile(rest,tree,quads,textures,camera,settings,U32.add(x,half),U32.add(y,half),half,width,height)),P.leaves(rest),
        L.tile_backing_allocation(rest,tree,quads,textures,camera,settings,x,y,half,width,height),
        L.tile_backing_allocation(rest,tree,quads,textures,camera,settings,U32.add(x,half),y,half,width,height),
        L.tile_backing_allocation(rest,tree,quads,textures,camera,settings,x,U32.add(y,half),half,width,height),
        L.tile_backing_allocation(rest,tree,quads,textures,camera,settings,U32.add(x,half),U32.add(y,half),half,width,height))

def L.frame_backing_allocation(n,tile_depth,tree,quads,textures,camera,settings,x,y,side,width,height):
  match n:
    case 0n: L.tile_backing_allocation(tile_depth,tree,quads,textures,camera,settings,x,y,side,width,height)
    case 1n+rest:
      +half = U32.div(side,2)
      four_equal(
        P.image_leaves(M.frame(rest,tile_depth,tree,quads,textures,camera,settings,x,y,half,width,height)),
        P.image_leaves(M.frame(rest,tile_depth,tree,quads,textures,camera,settings,U32.add(x,half),y,half,width,height)),
        P.image_leaves(M.frame(rest,tile_depth,tree,quads,textures,camera,settings,x,U32.add(y,half),half,width,height)),
        P.image_leaves(M.frame(rest,tile_depth,tree,quads,textures,camera,settings,U32.add(x,half),U32.add(y,half),half,width,height)),P.leaves(Nat.add(rest,tile_depth)),
        L.frame_backing_allocation(rest,tile_depth,tree,quads,textures,camera,settings,x,y,half,width,height),
        L.frame_backing_allocation(rest,tile_depth,tree,quads,textures,camera,settings,U32.add(x,half),y,half,width,height),
        L.frame_backing_allocation(rest,tile_depth,tree,quads,textures,camera,settings,x,U32.add(y,half),half,width,height),
        L.frame_backing_allocation(rest,tile_depth,tree,quads,textures,camera,settings,U32.add(x,half),U32.add(y,half),half,width,height))

def L.frame_dimension_interface(width,height,settings): {==}
def L.look_delta_preserved(dx,dy,plan): {==}
def L.key_code_preserved(code,down,plan): {==}
def L.event_order_preserved(head,tail,plan): {==}

def L.outside_pointer_rejected(pixel,source,target,outside):
  Equal.cong(Bool,U32,inside => P.pointer_coordinate_checked(pixel,source,target,inside),
    U32.is_lt(pixel,source),False{},outside)

def outside_lists_zero(+quads:List<&2,M.Prepared>,+textures:List<&2,R.Texture>) ->
    {M.outside_lists(quads,textures) == 0 : U32}:
  match quads textures:
    case Nil{} Nil{}: {==}
    case head <> tail Nil{}: {==}
    case Nil{} head <> tail: {==}
    case head <> tail other <> rest: {==}

def outside_tree_zero(tree:M.Spatial,quads:List<&2,M.Prepared>,textures:List<&2,R.Texture>) ->
    {M.outside_tree(tree,quads,textures) == 0 : U32}:
  match tree:
    case M.Empty{}: outside_lists_zero(quads,textures)
    case M.Flat{entries}: outside_lists_zero(quads,textures)
    case M.Leaf{bounds,entries}: outside_lists_zero(quads,textures)
    case M.Branch{bounds,left,right}: outside_lists_zero(quads,textures)

def L.invisible_pixel_zero(tree,quads,textures,camera,settings,x,y,width,height,outside):
  Equal.trans(U32,M.pixel(tree,quads,textures,camera,settings,x,y,width,height),
    M.outside_tree(tree,quads,textures),0,
    Equal.cong(Bool,U32,inside => M.pixel_inside(inside,tree,quads,textures,camera,settings,x,y,width,height),
      U32.is_lt(x,width) && U32.is_lt(y,height),False{},outside),
    outside_tree_zero(tree,quads,textures))
