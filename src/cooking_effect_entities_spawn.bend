import Base
import ./core.bend as C
import ./json.bend as J
import ./random.bend as R
import ./f64.bend as F
import ./inventory.bend as I
import ./vanilla_entity_fields.bend as V
import ./campfire_authority_items.bend as CI
import ./crafting_recipe_components.bend as CC
import ./cooking_block_entity_codec_components.bend as Patch
import ./cooking_world_items.bend as Items
import ./furnace_authority.bend as FA
import ./furnace_authority_xp.bend as XP
import ./cooking_effect_entities_model.bend as E
import ./cooking_effect_entities_math.bend as M
import ./cooking_effect_entities_query.bend as Q

def normalized(+item:I.Slot) -> I.Slot:
  match item:
    case I.InvEmpty{}: item
    case I.InvStack{+key,+count}:
      Bool.pick(I.Slot,CI.non_air(key) && U32.is_gt(count,0) && U32.is_lt(count,2147483648),item,I.InvEmpty{})
def authenticate(context:CI.Context,key:I.ItemKey) -> Result<&2,&2,String,Unit>:
  CI.Context{recipes,+defaults,features} = context
  I.ItemKey{+id,+components} = key
  do Result<&2,&2,String,Unit>:
    +base : J.Value <- Items.initialized(CC.default_for(defaults,id))
    +patch : J.Value <- Patch.patch(base,I.ItemKey{id,components})
    admitted : Maybe<&2,I.ItemMetadata> <- CI.admit(CI.Context{recipes,defaults,features},CI.Input{I.InvStack{I.ItemKey{id,components},1},patch})
    return Unit{}
# Map only errors; the original full item identity is never reduced to an ID.
def admitted(result:Result<&2,&2,String,Unit>) -> Result<&2,&2,E.Error,Unit>:
  match result:
    case Fail{message}: Fail{E.Refused{message}}
    case Done{unit}: Done{Unit{}}
def item_finished(dimension:String,id:U32,most:R.Bits64,least:R.Bits64,order:Nat,point:V.Vec3,velocity:V.Vec3,item:I.Slot,
    result:R.Source & (F32 & F32)) -> E.Record:
  (source,pair) = result
  (bob,yaw) = pair
  E.Item{M.base(dimension,id,most,least,source,M.fields(point,velocity,yaw),order),item,0,0,5,None{},None{},bob}
def item_uuid(dimension:String,id:U32,order:Nat,point:V.Vec3,velocity:V.Vec3,item:I.Slot,
    result:R.Source & (R.Bits64 & R.Bits64)) -> E.Record:
  (source,pair) = result
  (most,least) = pair
  item_finished(dimension,id,most,least,order,point,velocity,item,M.item_rotation(source))
def item_source(dimension:String,id:U32,order:Nat,point:V.Vec3,velocity:V.Vec3,item:I.Slot,
    result:R.Bits64 & R.Source) -> R.Bits64 & E.Record:
  (unique,source) = result
  (unique,item_uuid(dimension,id,order,point,velocity,item,M.uuid(source)))
def item_created(+level:R.Source,+cursor:U32,+order:Nat,+records:List<&2,E.Record>,times:List<&2,R.Bits64>,
    result:R.Bits64 & E.Record) -> E.Plan:
  (unique,record) = result
  E.Plan{E.View{level,unique,cursor,1n+order,List.append(&2,E.Record,records,[record])},times}
def item_spawn(dimension:String,point:V.Vec3,velocity:V.Vec3,item:I.Slot,view:E.View,times:List<&2,R.Bits64>,+id:U32) -> Result<&2,&2,E.Error,E.Plan>:
  E.View{level,+unique,cursor,+order,+records} = view
  match times:
    case Nil{}: Fail{E.EntropyNeeded{1n}}
    case time <> rest:
      Done{item_created(level,id,order,records,rest,item_source(dimension,id,order,point,velocity,item,M.constructor_source(unique,time)))}
def item_id(+context:E.Context,+dimension:String,+point:V.Vec3,+velocity:V.Vec3,+item:I.Slot,+view:E.View,+times:List<&2,R.Bits64>,
    result:Result<&2,&2,E.Error,U32>) -> Result<&2,&2,E.Error,E.Plan>:
  match result:
    case Fail{error}: Fail{error}
    case Done{id}: item_spawn(dimension,point,velocity,item,view,times,id)
def item(+context:E.Context,dimension:String,point:V.Vec3,velocity:V.Vec3,value:I.Slot,+view:E.View,times:List<&2,R.Bits64>) -> Result<&2,&2,E.Error,E.Plan>:
  E.View{level,unique,cursor,order,records} = view
  item_id(context,dimension,point,velocity,value,view,times,E.next_id(context,cursor,records))
def chunk_velocity(context:E.Context,dimension:String,point:V.Vec3,key:I.ItemKey,count:U32,unique:R.Bits64,cursor:U32,order:Nat,records:List<&2,E.Record>,times:List<&2,R.Bits64>,
    result:R.Source & V.Vec3) -> Result<&2,&2,E.Error,E.Plan>:
  (level,velocity) = result
  item(context,dimension,point,velocity,I.InvStack{key,count},E.View{level,unique,cursor,order,records},times)
def chunk(context:E.Context,dimension:String,point:V.Vec3,key:I.ItemKey,count:U32,view:E.View,times:List<&2,R.Bits64>) -> Result<&2,&2,E.Error,E.Plan>:
  E.View{level,unique,cursor,order,records} = view
  chunk_velocity(context,dimension,point,key,count,unique,cursor,order,records,times,M.drop_velocity(level))
def split_count(+left:U32,draw:E.Bounded) -> E.Bounded:
  E.Bounded{level,value} = draw
  +wanted = U32.add(value,10)
  E.Bounded{level,Bool.pick(U32,U32.is_lt(left,wanted),left,wanted)}
def drop_next(plan:E.Plan,next:E.View -> List<&2,R.Bits64> -> Result<&2,&2,E.Error,E.Plan>) -> Result<&2,&2,E.Error,E.Plan>:
  E.Plan{view,times} = plan
  next(view)(times)
def drop_drawn(context:E.Context,dimension:String,point:V.Vec3,key:I.ItemKey,+count:U32,unique:R.Bits64,cursor:U32,order:Nat,records:List<&2,E.Record>,times:List<&2,R.Bits64>,draw:E.Bounded,
    next:U32 -> E.Plan -> Result<&2,&2,E.Error,E.Plan>) -> Result<&2,&2,E.Error,E.Plan>:
  E.Bounded{level,+amount} = draw
  Result.bind(&2,&2,E.Error,E.Plan,E.Plan,
    chunk(context,dimension,point,key,amount,E.View{level,unique,cursor,order,records},times),next(U32.sub(count,amount)))
def drop_step(+context:E.Context,dimension:String,point:V.Vec3,key:I.ItemKey,+count:U32,view:E.View,times:List<&2,R.Bits64>,
    next:U32 -> E.Plan -> Result<&2,&2,E.Error,E.Plan>) -> Result<&2,&2,E.Error,E.Plan>:
  E.Context{items,E.Limits{steps,rejections,ids},reserved} = context
  E.View{level,unique,cursor,order,records} = view
  do Result<&2,&2,E.Error,E.Plan>:
    draw : E.Bounded <- E.random_result(R.next_bounded(rejections,level,21))
    drop_drawn(context,dimension,point,key,count,unique,cursor,order,records,times,split_count(count,draw),next)
def drop_loop(left:Nat,+context:E.Context,+dimension:String,+point:V.Vec3,+key:I.ItemKey,count:U32,view:E.View,times:List<&2,R.Bits64>) -> Result<&2,&2,E.Error,E.Plan>:
  match left count:
    case _ 0: Done{E.Plan{view,times}}
    case 0n _: Fail{E.SpawnBudget{}}
    case 1n+rest _:
      drop_step(context,dimension,point,key,count,view,times,
        remaining => plan => drop_next(plan,view => times => drop_loop(rest,context,dimension,point,key,remaining,view,times)))
def drop_nonempty(+context:E.Context,position:C.Position,key:I.ItemKey,count:U32,level:R.Source,point:V.Vec3,unique:R.Bits64,cursor:U32,order:Nat,records:List<&2,E.Record>,times:List<&2,R.Bits64>) -> Result<&2,&2,E.Error,E.Plan>:
  E.Context{items,E.Limits{steps,rejections,ids},reserved} = context
  drop_loop(steps,context,M.dimension(position),point,key,count,E.View{level,unique,cursor,order,records},times)
def drop_point(item:I.Slot,context:E.Context,position:C.Position,level:R.Source,point:V.Vec3,unique:R.Bits64,cursor:U32,order:Nat,records:List<&2,E.Record>,times:List<&2,R.Bits64>) -> Result<&2,&2,E.Error,E.Plan>:
  match item:
    case I.InvEmpty{}: Done{E.Plan{E.View{level,unique,cursor,order,records},times}}
    case I.InvStack{key,count}: drop_nonempty(context,position,key,count,level,point,unique,cursor,order,records,times)
def drop_at(context:E.Context,position:C.Position,item:I.Slot,unique:R.Bits64,cursor:U32,order:Nat,records:List<&2,E.Record>,times:List<&2,R.Bits64>,result:R.Source & V.Vec3) -> Result<&2,&2,E.Error,E.Plan>:
  (level,point) = result
  drop_point(item,context,position,level,point,unique,cursor,order,records,times)
def drop_ready(context:E.Context,+position:C.Position,item:I.Slot,view:E.View,times:List<&2,R.Bits64>,status:Result<&2,&2,E.Error,Unit>) -> Result<&2,&2,E.Error,E.Plan>:
  E.View{level,unique,cursor,order,records} = view
  match status:
    case Fail{error}: Fail{error}
    case Done{unit}: drop_at(context,position,item,unique,cursor,order,records,times,M.drop_position(level,position))
def drop_normalized(+context:E.Context,+position:C.Position,+item:I.Slot,view:E.View,times:List<&2,R.Bits64>) -> Result<&2,&2,E.Error,E.Plan>:
  E.Context{items,limits,reserved} = context
  match item:
    case I.InvEmpty{}: drop_ready(context,position,item,view,times,Done{Unit{}})
    case I.InvStack{key,count}: drop_ready(context,position,item,view,times,admitted(authenticate(items,key)))
def drop(context:E.Context,position:C.Position,item:I.Slot,view:E.View,times:List<&2,R.Bits64>) -> Result<&2,&2,E.Error,E.Plan>:
  drop_normalized(context,position,normalized(item),view,times)
