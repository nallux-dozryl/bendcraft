import Base
import ./mesh_tile_render.bend as T
import ./mesh_tile_render_laws.bend as L
import ./mesh_render.bend as M
import ./client_render.bend as R

def L.draw_retains_complete_owner_and_resources(owner,textures):
  match owner:
    case T.Owner{scene,camera,settings,width,height,depth,cells}: {==}

def finish_alpha(+image:Image,alpha:List<&2,M.Prepared>) -> {T.fin(image,[],alpha) == image : Image}:
  match alpha:
    case Nil{}: {==}
    case head <> tail: finish_alpha(image,tail)

def L.local_list_release_preserves_complete_image(image,opaque,alpha):
  match opaque:
    case Nil{}: finish_alpha(image,alpha)
    case head <> tail: L.local_list_release_preserves_complete_image(image,tail,alpha)

def L.straight_line_tile_has_256_backing_pixels(opaque,alpha,camera,settings,textures,x,y,width,height): {==}

def false_type(value:Bool) -> Data:
  match value:
    case True{}: Unit
    case False{}: Empty

def true_is_not_false(contradiction:{True{} == False{} : Bool}) -> Empty:
  %contradiction : false_type(_)
  Unit{}

def found_scan_true(fuel:Nat,+quad:M.Prepared,+camera:R.Basis,+settings:M.Settings,+x:U32,+y:U32,+width:U32,+height:U32,+index:U32) ->
    {T.any_hit(fuel,True{},quad,camera,settings,x,y,width,height,index) == True{} : Bool}:
  match fuel:
    case 0n: {==}
    case 1n+rest: {==}

def sample_complete(hit:Maybe<&2,M.Hit>,+fuel:Nat,+quad:M.Prepared,+camera:R.Basis,+settings:M.Settings,+x:U32,+y:U32,+width:U32,+height:U32,+index:U32,
    rejected:{T.any_hit(fuel,T.has_hit(hit),quad,camera,settings,x,y,width,height,U32.inc(index)) == False{} : Bool},
    more:{T.any_hit(fuel,False{},quad,camera,settings,x,y,width,height,U32.inc(index)) == False{} : Bool} ->
      {L.samples(fuel,quad,camera,settings,x,y,width,height,U32.inc(index)) == L.no_hits(fuel) : List<&2,Maybe<&2,M.Hit>>}) ->
    {hit <> L.samples(fuel,quad,camera,settings,x,y,width,height,U32.inc(index)) == None{} <> L.no_hits(fuel) : List<&2,Maybe<&2,M.Hit>>}:
  match hit:
    case Some{value}:
      Empty.absurd({Some{value} <> L.samples(fuel,quad,camera,settings,x,y,width,height,U32.inc(index)) == None{} <> L.no_hits(fuel) : List<&2,Maybe<&2,M.Hit>>},true_is_not_false(Equal.trans(Bool,True{},T.any_hit(fuel,True{},quad,camera,settings,x,y,width,height,U32.inc(index)),False{},
        Equal.sym(Bool,T.any_hit(fuel,True{},quad,camera,settings,x,y,width,height,U32.inc(index)),True{},found_scan_true(fuel,quad,camera,settings,x,y,width,height,U32.inc(index))),rejected)))
    case None{}:
      Equal.cong(List<&2,Maybe<&2,M.Hit>>,List<&2,Maybe<&2,M.Hit>>,tail => None{} <> tail,
        L.samples(fuel,quad,camera,settings,x,y,width,height,U32.inc(index)),L.no_hits(fuel),
        more(rejected))

def L.rejected_scan_has_no_hit_in_any_sample(fuel,quad,camera,settings,x,y,width,height,index,rejected):
  match fuel:
    case 0n: {==}
    case 1n+rest:
      +px = U32.add(x,U32.mod(index,16))
      +py = U32.add(y,U32.div(index,16))
      sample_complete(T.ray_hit(U32.is_lt(px,width) && U32.is_lt(py,height),quad,camera,settings,px,py,width,height),rest,quad,camera,settings,x,y,width,height,index,rejected,
        refused => L.rejected_scan_has_no_hit_in_any_sample(rest,quad,camera,settings,x,y,width,height,U32.inc(index),refused))

def rejected_proposal(proposal:Bool,+quad:M.Prepared,+camera:R.Basis,+settings:M.Settings,+x:U32,+y:U32,+width:U32,+height:U32,
    rejected:{T.admitted(proposal,quad,camera,settings,x,y,width,height) == False{} : Bool}) ->
    {L.samples(256n,quad,camera,settings,x,y,width,height,0) == L.no_hits(256n) : List<&2,Maybe<&2,M.Hit>>}:
  match proposal:
    case True{}: Empty.absurd({L.samples(256n,quad,camera,settings,x,y,width,height,0) == L.no_hits(256n) : List<&2,Maybe<&2,M.Hit>>},true_is_not_false(rejected))
    case False{}: L.rejected_scan_has_no_hit_in_any_sample(256n,quad,camera,settings,x,y,width,height,0,rejected)

def L.actual_tile_rejection_has_complete_miss_contract(quad,bounds,camera,settings,x,y,width,height,rejected):
  rejected_proposal(T.may_overlap(bounds,x,y),quad,camera,settings,x,y,width,height,rejected)

def missed_candidate(prepared:M.Prepared,+textures:List<&2,R.Texture>,+best:M.Fragment) ->
  {M.solid_candidate(None{},prepared,textures,best) == best : M.Fragment}:
  match prepared textures:
    case M.Prepared{a,b,material,cull,order,index,bounds} Nil{}: {==}
    case M.Prepared{a,b,material,cull,order,index,bounds} head <> tail: {==}

def L.omitted_miss_preserves_complete_opaque_trace(head,tail,origin,direction,settings,textures,best,miss):
  Equal.trans(M.Fragment,
    M.opaque_trace(head <> tail,origin,direction,settings,textures,best),
    M.opaque_trace(tail,origin,direction,settings,textures,M.solid_candidate(None{},head,textures,best)),
    M.opaque_trace(tail,origin,direction,settings,textures,best),
    Equal.cong(Maybe<&2,M.Hit>,M.Fragment,
      hit => M.opaque_trace(tail,origin,direction,settings,textures,M.solid_candidate(hit,head,textures,best)),
      M.quad_hit(head,origin,direction,settings),None{},miss),
    Equal.cong(M.Fragment,M.Fragment,candidate => M.opaque_trace(tail,origin,direction,settings,textures,candidate),
      M.solid_candidate(None{},head,textures,best),best,missed_candidate(head,textures,best)))
