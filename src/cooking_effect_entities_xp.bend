import Base
import ./core.bend as C
import ./random.bend as R
import ./f64.bend as F
import ./vanilla_entity_fields.bend as V
import ./furnace_authority.bend as FA
import ./furnace_authority_xp.bend as XP
import ./cooking_effect_entities_model.bend as E
import ./cooking_effect_entities_math.bend as M
import ./cooking_effect_entities_query.bend as Q
import ./cooking_effect_entities_spawn.bend as S

def denomination_go(values:List<&2,U32>,+total:U32) -> U32:
  match values:
    case Nil{}: 1
    case +head <> rest: Bool.pick(U32,U32.is_ge(total,head),head,denomination_go(rest,total))
def denomination(total:U32) -> U32:
  denomination_go([2477,1237,617,307,149,73,37,17,7,3,1],total)
def orb_finished(dimension:String,id:U32,most:R.Bits64,least:R.Bits64,order:Nat,point:V.Vec3,value:U32,
    result:R.Source & (V.Vec3 & F32)) -> E.Record:
  (source,pair) = result
  (velocity,yaw) = pair
  E.Orb{M.base(dimension,id,most,least,source,M.fields(point,velocity,yaw),order),value,0,5,1,None{}}
def orb_uuid(dimension:String,id:U32,order:Nat,point:V.Vec3,value:U32,result:R.Source & (R.Bits64 & R.Bits64)) -> E.Record:
  (source,pair) = result
  (most,least) = pair
  orb_finished(dimension,id,most,least,order,point,value,M.orb_rotation(source))
def orb_source(dimension:String,id:U32,order:Nat,point:V.Vec3,value:U32,result:R.Bits64 & R.Source) -> R.Bits64 & E.Record:
  (unique,source) = result
  (unique,orb_uuid(dimension,id,order,point,value,M.uuid(source)))
def orb_spawn(dimension:String,point:V.Vec3,value:U32,view:E.View,times:List<&2,R.Bits64>,+id:U32) -> Result<&2,&2,E.Error,E.Plan>:
  E.View{level,unique,cursor,+order,+records} = view
  match times:
    case Nil{}: Fail{E.EntropyNeeded{1n}}
    case time <> rest:
      Done{S.item_created(level,id,order,records,rest,orb_source(dimension,id,order,point,value,M.constructor_source(unique,time)))}
def orb_id(dimension:String,point:V.Vec3,value:U32,view:E.View,times:List<&2,R.Bits64>,result:Result<&2,&2,E.Error,U32>) -> Result<&2,&2,E.Error,E.Plan>:
  match result:
    case Fail{error}: Fail{error}
    case Done{id}: orb_spawn(dimension,point,value,view,times,id)
def placed(+context:E.Context,dimension:String,value:U32,+view:E.View,times:List<&2,R.Bits64>,result:Result<&2,&2,E.Error,V.Vec3>) -> Result<&2,&2,E.Error,E.Plan>:
  E.View{level,unique,cursor,order,records} = view
  match result:
    case Fail{error}: Fail{error}
    case Done{point}: orb_id(dimension,point,value,view,times,E.next_id(context,cursor,records))
def merged(view:E.View,id:U32,times:List<&2,R.Bits64>) -> Result<&2,&2,E.Error,E.Plan>:
  E.View{level,unique,cursor,order,records} = view
  Done{E.Plan{E.View{level,unique,cursor,order,Q.update(records,id)},times}}
# Place is the actual world's noCollision/findFreePosition constructor seam.
# It returns the final base position, including the y-height/2 adjustment.
def found(~Geometry:Data,~place:Geometry -> String -> V.Vec3 -> Result<&2,&2,E.Error,V.Vec3>,
    geometry:Geometry,context:E.Context,+dimension:String,point:V.Vec3,value:U32,view:E.View,times:List<&2,R.Bits64>,result:Result<&2,&2,E.Error,Maybe<&2,Q.Hit>>) -> Result<&2,&2,E.Error,E.Plan>:
  match result:
    case Fail{error}: Fail{error}
    case Done{Some{Q.Hit{id,key}}}:
      merged(view,id,times)
    case Done{None{}}: placed(context,dimension,value,view,times,place(geometry,dimension,point))
def merging(~Geometry:Data,~place:Geometry -> String -> V.Vec3 -> Result<&2,&2,E.Error,V.Vec3>,
    geometry:Geometry,context:E.Context,+dimension:String,+point:V.Vec3,+value:U32,unique:R.Bits64,cursor:U32,order:Nat,+records:List<&2,E.Record>,times:List<&2,R.Bits64>,draw:E.Bounded) -> Result<&2,&2,E.Error,E.Plan>:
  E.Bounded{+level,ticket} = draw
  found(~Geometry,~place,geometry,context,dimension,point,value,E.View{level,unique,cursor,order,records},times,Q.find(records,dimension,point,ticket,value,None{}))
def step(~Geometry:Data,~place:Geometry -> String -> V.Vec3 -> Result<&2,&2,E.Error,V.Vec3>,
    geometry:Geometry,+context:E.Context,dimension:String,point:V.Vec3,value:U32,view:E.View,times:List<&2,R.Bits64>) -> Result<&2,&2,E.Error,E.Plan>:
  E.Context{items,E.Limits{steps,rejections,ids},reserved} = context
  E.View{level,unique,cursor,order,records} = view
  do Result<&2,&2,E.Error,E.Plan>:
    draw : E.Bounded <- E.random_result(R.next_bounded(rejections,level,40))
    merging(~Geometry,~place,geometry,context,dimension,point,value,unique,cursor,order,records,times,draw)
def award_step(~Geometry:Data,~place:Geometry -> String -> V.Vec3 -> Result<&2,&2,E.Error,V.Vec3>,
    geometry:Geometry,context:E.Context,dimension:String,point:V.Vec3,+value:U32,+total:U32,view:E.View,times:List<&2,R.Bits64>,
    next:U32 -> E.View -> List<&2,R.Bits64> -> Result<&2,&2,E.Error,E.Plan>) -> Result<&2,&2,E.Error,E.Plan>:
  Result.bind(&2,&2,E.Error,E.Plan,E.Plan,step(~Geometry,~place,geometry,context,dimension,point,value,view,times),
    plan => S.drop_next(plan,next(U32.sub(total,value))))
def award_loop(~Geometry:Data,~place:Geometry -> String -> V.Vec3 -> Result<&2,&2,E.Error,V.Vec3>,
    left:Nat,+geometry:Geometry,+context:E.Context,+dimension:String,+point:V.Vec3,+total:U32,view:E.View,times:List<&2,R.Bits64>) -> Result<&2,&2,E.Error,E.Plan>:
  match left total:
    case _ 0: Done{E.Plan{view,times}}
    case 0n _: Fail{E.SpawnBudget{}}
    case 1n+rest _:
      award_step(~Geometry,~place,geometry,context,dimension,point,denomination(total),total,view,times,
        remaining => view => times => award_loop(~Geometry,~place,rest,geometry,context,dimension,point,remaining,view,times))
def positive(~Geometry:Data,~place:Geometry -> String -> V.Vec3 -> Result<&2,&2,E.Error,V.Vec3>,
    allowed:Bool,geometry:Geometry,+context:E.Context,dimension:String,point:V.Vec3,total:U32,view:E.View,times:List<&2,R.Bits64>) -> Result<&2,&2,E.Error,E.Plan>:
  match allowed:
    case False{}: Done{E.Plan{view,times}}
    case True{}:
      E.Context{items,E.Limits{steps,rejections,ids},reserved} = context
      award_loop(~Geometry,~place,steps,geometry,context,dimension,point,total,view,times)
def awarded(~Geometry:Data,~place:Geometry -> String -> V.Vec3 -> Result<&2,&2,E.Error,V.Vec3>,
    geometry:Geometry,context:E.Context,+position:C.Position,+request:FA.XpRequest,unique:R.Bits64,cursor:U32,order:Nat,records:List<&2,E.Record>,times:List<&2,R.Bits64>,result:R.Source & F32) -> Result<&2,&2,E.Error,E.Plan>:
  (level,ticket) = result
  +total = XP.award(request,ticket)
  positive(~Geometry,~place,U32.is_gt(total,0) && U32.is_lt(total,2147483648),geometry,context,M.dimension(position),M.center(position),total,E.View{level,unique,cursor,order,records},times)
def rounding(source:R.Source,needed:Bool) -> R.Source & F32:
  match needed:
    case False{}: (source,0.0)
    case True{}: R.next_float(source)
def experience(~Geometry:Data,~place:Geometry -> String -> V.Vec3 -> Result<&2,&2,E.Error,V.Vec3>,
    geometry:Geometry,context:E.Context,+position:C.Position,+request:FA.XpRequest,view:E.View,times:List<&2,R.Bits64>) -> Result<&2,&2,E.Error,E.Plan>:
  E.View{level,unique,cursor,order,records} = view
  awarded(~Geometry,~place,geometry,context,position,request,unique,cursor,order,records,times,rounding(level,XP.advances_rng(request)))
