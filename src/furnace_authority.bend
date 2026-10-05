import Base
import ./inventory.bend as Inv
import ./crafting_recipe.bend as R
import ./crafting_recipe_decoder.bend as D
import ./cooking_recipe.bend as K
import ./cooking_recipe_number.bend as N
import ./furnace_authority_fuel.bend as F

type Use is Data:
  Use{recipe_id:String,count:U32}
type Frame is Data:
  Frame{kind:K.CookingKind,lit_remaining:U32,lit_total:U32,cooking_spent:U32,cooking_total:U32,speed:F32,cached:Maybe<&2,String>,uses:List<&2,Use>}
type Snapshot is Data:
  Snapshot{frame:Frame,slots:K.FurnaceSlots}
type State is Type:
  State{inventory:Inv.Inventory,frame:Frame}
type Effects is Data:
  Effects{dirty:Bool,lit_change:Maybe<&2,Bool>,drops:List<&2,Inv.Slot>,completed:Maybe<&2,String>}
type Transition is Data:
  Transition{after:Snapshot,effects:Effects}
type Selection is Data:
  Selection{plan:Maybe<&2,K.Plan>,cached:Maybe<&2,String>}
type FuelSpent is Data:
  FuelSpent{fuel:Inv.Slot,drops:List<&2,Inv.Slot>}
type Persisted is Data:
  Persisted{slots:K.FurnaceSlots,cooking_time_spent:U32,cooking_total_time:U32,lit_time_remaining:U32,lit_total_time:U32,speed_multiplier:F32,recipes_used:List<&2,Use>}
type XpRequest is Data:
  XpRequest{recipe_id:String,uses:U32,experience:F32}
type Face is Data:
  Up{}
  Down{}
  Side{}

# Java int fields cross every public boundary as two's-complement bits.
def signed_lt(+a:U32,+b:U32) -> Bool:
  U32.is_lt(U32.xor(a,2147483648),U32.xor(b,2147483648))
def signed_gt(+a:U32,+b:U32) -> Bool:
  signed_lt(b,a)
def signed_min(+a:U32,+b:U32) -> U32:
  R.choose(U32,a,b,signed_lt(a,b))
def signed_max(+a:U32,+b:U32) -> U32:
  R.choose(U32,b,a,signed_lt(a,b))
def lit(+frame:Frame) -> Bool:
  Frame{kind,remaining,total,spent,cook_total,speed,cached,uses} = frame
  signed_gt(remaining,0)
def timing(+frame:Frame,+remaining:U32,+total:U32,+spent:U32,+cook_total:U32,+speed:F32) -> Frame:
  Frame{kind,r,t,s,c,old,cached,uses} = frame
  Frame{kind,remaining,total,spent,cook_total,speed,cached,uses}
def cache(+frame:Frame,+value:Maybe<&2,String>) -> Frame:
  Frame{kind,r,t,s,c,speed,old,uses} = frame
  Frame{kind,r,t,s,c,speed,value,uses}
def use_table(+frame:Frame,+value:List<&2,Use>) -> Frame:
  Frame{kind,r,t,s,c,speed,cached,old} = frame
  Frame{kind,r,t,s,c,speed,cached,value}
def reset_progress(+frame:Frame) -> Frame:
  Frame{kind,+r,t,+s,+c,+speed,cached,uses} = frame
  Frame{kind,r,t,0,c,speed,cached,uses}
def spend_lit_checked(+frame:Frame,+positive:Bool) -> Frame:
  Frame{kind,+r,t,+s,+c,+speed,cached,uses} = frame
  Frame{kind,R.choose(U32,U32.sub(r,1),r,positive),t,s,c,speed,cached,uses}
def spend_lit(+frame:Frame) -> Frame:
  spend_lit_checked(frame,lit(frame))
def cool_checked(+frame:Frame,+positive:Bool) -> Frame:
  Frame{kind,+r,t,+s,+c,+speed,cached,uses} = frame
  Frame{kind,r,t,R.choose(U32,signed_min(signed_max(U32.sub(s,2),0),c),s,positive),c,speed,cached,uses}
def cool(+frame:Frame) -> Frame:
  Frame{kind,+r,t,+s,+c,+speed,cached,uses} = frame
  cool_checked(frame,signed_gt(s,0))
def different(+a:Bool,+b:Bool) -> Bool:
  match a b:
    case True{} True{}: False{}
    case False{} False{}: False{}
    case _ _: True{}
def finish_changed(+after:Snapshot,+dirty:Bool,+drops:List<&2,Inv.Slot>,+completed:Maybe<&2,String>,+now:Bool,+changed:Bool) -> Transition:
  Transition{after,Effects{dirty || changed,R.choose(Maybe<&2,Bool>,Some{now},None{},changed),drops,completed}}
def finish(+was:Bool,+after:Snapshot,+dirty:Bool,+drops:List<&2,Inv.Slot>,+completed:Maybe<&2,String>) -> Transition:
  Snapshot{+frame,slots} = after
  +now = lit(frame)
  finish_changed(after,dirty,drops,completed,now,different(was,now))

def cached_recipe_matched(recipe:K.Recipe,items:List<&2,R.ItemDefinition>,input:Inv.Slot,matched:Bool) -> Maybe<&2,K.Plan>:
  match matched:
    case False{}: None{}
    case True{}: K.plan(recipe,items,input)
def cached_recipe_identified(+recipe:K.Recipe,kind:K.CookingKind,tags:List<&2,R.Tag>,+items:List<&2,R.ItemDefinition>,+input:Inv.Slot,identified:Bool,miss:Unit -> Maybe<&2,K.Plan>) -> Maybe<&2,K.Plan>:
  match identified:
    case False{}: miss(Unit{})
    case True{}: cached_recipe_matched(recipe,items,input,K.matches(recipe,kind,tags,input))
def cached_recipe(+recipes:List<&2,K.Recipe>,+id:String,+kind:K.CookingKind,+tags:List<&2,R.Tag>,+items:List<&2,R.ItemDefinition>,+input:Inv.Slot) -> Maybe<&2,K.Plan>:
  match recipes:
    case Nil{}: None{}
    case +recipe <> rest:
      cached_recipe_identified(recipe,kind,tags,items,input,String.eq(K.recipe_id(recipe),id),
        unit => cached_recipe(rest,id,kind,tags,items,input))
def cached_plan(+catalog:K.Catalog,+kind:K.CookingKind,+input:Inv.Slot,+id:Maybe<&2,String>) -> Maybe<&2,K.Plan>:
  K.Catalog{recipes,tags,items} = catalog
  match id:
    case None{}: None{}
    case Some{name}: cached_recipe(recipes,name,kind,tags,items,input)
def select_found(+previous:Maybe<&2,String>,+value:Maybe<&2,K.Plan>) -> Selection:
  match value:
    case None{}: Selection{None{},previous}
    case Some{+plan}:
      K.Plan{id,kind,output,before,time,xp} = plan
      Selection{Some{plan},Some{id}}
def select_cached(+catalog:K.Catalog,+kind:K.CookingKind,+input:Inv.Slot,+metadata:List<&2,Inv.ItemMetadata>,+previous:Maybe<&2,String>,+value:Maybe<&2,K.Plan>) -> Result<&2,&2,String,Selection>:
  match value:
    case Some{plan}: Done{select_found(previous,Some{plan})}
    case None{}:
      do Result<&2,&2,String,Selection>:
        selected : Maybe<&2,K.Plan> <- K.find_with_metadata(catalog,kind,input,metadata)
        return select_found(previous,selected)
def select(+catalog:K.Catalog,+frame:Frame,+input:Inv.Slot,+metadata:List<&2,Inv.ItemMetadata>) -> Result<&2,&2,String,Selection>:
  Frame{+kind,r,t,s,c,speed,+cached,uses} = frame
  select_cached(catalog,kind,input,metadata,cached,cached_plan(catalog,kind,input,cached))

def add_use(+values:List<&2,Use>,+id:String) -> List<&2,Use>:
  match values:
    case Nil{}: [Use{id,1}]
    case Use{+other,count} <> rest:
      R.choose(List<&2,Use>,Use{other,U32.add(count,1)} <> rest,Use{other,count} <> add_use(rest,id),String.eq(other,id))
def record_use(+frame:Frame,+id:String) -> Frame:
  Frame{kind,+r,t,+s,+c,+speed,cached,uses} = frame
  Frame{kind,r,t,s,c,speed,cached,add_use(uses,id)}
def nonempty_drop(+value:Inv.Slot) -> List<&2,Inv.Slot>:
  match value:
    case Inv.InvEmpty{}: []
    case Inv.InvStack{key,count}: [Inv.InvStack{key,count}]
def spent_remainder(+remaining:Inv.Slot,+remainder:Inv.Slot) -> FuelSpent:
  match remaining:
    case Inv.InvEmpty{}: FuelSpent{remainder,[]}
    case Inv.InvStack{key,count}: FuelSpent{remaining,nonempty_drop(remainder)}
def consume_fuel(+catalog:K.Catalog,+fuel:Inv.Slot) -> FuelSpent:
  K.Catalog{recipes,tags,items} = catalog
  match fuel:
    case Inv.InvEmpty{}: FuelSpent{Inv.InvEmpty{},[]}
    case Inv.InvStack{Inv.ItemKey{+id,+payload},+count}:
      spent_remainder(K.consume_input(Inv.InvStack{Inv.ItemKey{id,payload},count}),R.remainder_known(R.item_definition(items,id)))
def rescale(+frame:Frame,+plan:K.Plan,+time:U32,+speed:F32) -> Frame:
  Frame{kind,r,t,+spent,+old,previous,cached,uses} = frame
  K.Plan{id,k,output,before,base,xp} = plan
  +total = N.total_time(base,speed)
  +resize = signed_gt(old,0) && signed_lt(spent,old)
  +progress = N.java_int(F32.ceil(F32.mul(F32.div(N.signed_float(spent),N.signed_float(old)),N.signed_float(total))))
  Frame{kind,time,time,R.choose(U32,progress,spent,resize),R.choose(U32,total,old,resize),speed,cached,uses}
def advance(+frame:Frame) -> Frame:
  Frame{kind,+r,t,+s,+c,+speed,cached,uses} = frame
  Frame{kind,r,t,U32.add(s,1),c,speed,cached,uses}
def due(+frame:Frame) -> Bool:
  Frame{kind,+r,t,+s,+c,+speed,cached,uses} = frame
  Bool.not(signed_lt(s,c))
def next_completion(+frame:Frame,+plan:K.Plan) -> Frame:
  Frame{kind,r,t,s,c,+speed,cached,uses} = frame
  K.Plan{id,k,output,before,base,xp} = plan
  Frame{kind,r,t,0,N.total_time(base,speed),speed,cached,uses}
def completed(+was:Bool,+frame:Frame,+plan:K.Plan,+drops:List<&2,Inv.Slot>,+completion:K.Completion) -> Transition:
  K.Completion{+id,before,after,xp} = completion
  finish(was,Snapshot{record_use(next_completion(frame,plan),id),after},True{},drops,Some{id})
def completing(+was:Bool,+catalog:K.Catalog,+frame:Frame,+slots:K.FurnaceSlots,+plan:K.Plan,+metadata:List<&2,Inv.ItemMetadata>,+drops:List<&2,Inv.Slot>,+dirty:Bool,+complete_now:Bool) -> Result<&2,&2,String,Transition>:
  match complete_now:
    case False{}: Done{finish(was,Snapshot{frame,slots},dirty,drops,None{})}
    case True{}:
      do Result<&2,&2,String,Transition>:
        completion : K.Completion <- K.complete(catalog,plan,slots,metadata,64)
        return completed(was,frame,plan,drops,completion)
def burning(+was:Bool,+catalog:K.Catalog,+frame:Frame,+slots:K.FurnaceSlots,+plan:K.Plan,+metadata:List<&2,Inv.ItemMetadata>,+drops:List<&2,Inv.Slot>,+dirty:Bool,+is_lit:Bool) -> Result<&2,&2,String,Transition>:
  match is_lit:
    case False{}: Done{finish(was,Snapshot{reset_progress(frame),slots},dirty,drops,None{})}
    case True{}:
      +next = advance(frame)
      completing(was,catalog,next,slots,plan,metadata,drops,dirty,due(next))
def ignition_consumed(+was:Bool,+catalog:K.Catalog,+frame:Frame,+input:Inv.Slot,+output:Inv.Slot,+plan:K.Plan,+metadata:List<&2,Inv.ItemMetadata>,+value:FuelSpent) -> Result<&2,&2,String,Transition>:
  FuelSpent{remaining,drops} = value
  burning(was,catalog,frame,K.FurnaceSlots{input,remaining,output},plan,metadata,drops,True{},True{})
def ignited(+was:Bool,+catalog:K.Catalog,+frame:Frame,+slots:K.FurnaceSlots,+plan:K.Plan,+metadata:List<&2,Inv.ItemMetadata>,+positive:Bool) -> Result<&2,&2,String,Transition>:
  K.FurnaceSlots{input,fuel,output} = slots
  match positive:
    case False{}: burning(was,catalog,frame,slots,plan,metadata,[],False{},False{})
    case True{}: ignition_consumed(was,catalog,frame,input,output,plan,metadata,consume_fuel(catalog,fuel))
def ignition_values(+was:Bool,+catalog:K.Catalog,+frame:Frame,+slots:K.FurnaceSlots,+plan:K.Plan,+metadata:List<&2,Inv.ItemMetadata>,+values:F.Values) -> Result<&2,&2,String,Transition>:
  F.Values{+time,speed} = values
  ignited(was,catalog,rescale(frame,plan,time,speed),slots,plan,metadata,signed_gt(time,0))
def ignition(+was:Bool,+catalog:K.Catalog,+fuel_catalog:F.Catalog,+context:F.Context,+profiles:List<&2,F.FuelProfile>,+frame:Frame,+slots:K.FurnaceSlots,+plan:K.Plan,+metadata:List<&2,Inv.ItemMetadata>) -> Result<&2,&2,String,Transition>:
  K.FurnaceSlots{input,+fuel,output} = slots
  do Result<&2,&2,String,Transition>:
    component : Maybe<&2,F.CookingFuel> <- F.fuel_for(fuel_catalog,profiles,fuel)
    values : F.Values <- F.values(fuel_catalog,context,component)
    ignition_values(was,catalog,frame,slots,plan,metadata,values)
def can_burn(+catalog:K.Catalog,+slots:K.FurnaceSlots,+plan:K.Plan) -> Bool:
  K.FurnaceSlots{input,fuel,output} = slots
  K.Plan{id,kind,+result,before,time,xp} = plan
  K.positive(result) && K.capacity(output,result,64,K.output_limit(K.output_metadata(catalog,K.slot_key(result))))
def ready(+was:Bool,+catalog:K.Catalog,+fuel_catalog:F.Catalog,+context:F.Context,+profiles:List<&2,F.FuelProfile>,+frame:Frame,+slots:K.FurnaceSlots,+plan:K.Plan,+metadata:List<&2,Inv.ItemMetadata>,+capacity:Bool,+already_lit:Bool) -> Result<&2,&2,String,Transition>:
  match capacity already_lit:
    case False{} _: Done{finish(was,Snapshot{reset_progress(frame),slots},False{},[],None{})}
    case True{} True{}: burning(was,catalog,frame,slots,plan,metadata,[],False{},True{})
    case True{} False{}: ignition(was,catalog,fuel_catalog,context,profiles,frame,slots,plan,metadata)
def selected_plan(+was:Bool,+catalog:K.Catalog,+fuel_catalog:F.Catalog,+context:F.Context,+profiles:List<&2,F.FuelProfile>,+next:Frame,+slots:K.FurnaceSlots,+metadata:List<&2,Inv.ItemMetadata>,+value:Maybe<&2,K.Plan>) -> Result<&2,&2,String,Transition>:
  match value:
    # Actual no-recipe branch preserves progress while this active branch runs.
    case None{}: Done{finish(was,Snapshot{next,slots},False{},[],None{})}
    case Some{+plan}: ready(was,catalog,fuel_catalog,context,profiles,next,slots,plan,metadata,can_burn(catalog,slots,plan),lit(next))
def selected(+was:Bool,+catalog:K.Catalog,+fuel_catalog:F.Catalog,+context:F.Context,+profiles:List<&2,F.FuelProfile>,+frame:Frame,+slots:K.FurnaceSlots,+metadata:List<&2,Inv.ItemMetadata>,+selection:Selection) -> Result<&2,&2,String,Transition>:
  Selection{value,cached} = selection
  selected_plan(was,catalog,fuel_catalog,context,profiles,cache(frame,cached),slots,metadata,value)
def active(+was:Bool,+catalog:K.Catalog,+fuel_catalog:F.Catalog,+context:F.Context,+profiles:List<&2,F.FuelProfile>,+frame:Frame,+slots:K.FurnaceSlots,+metadata:List<&2,Inv.ItemMetadata>,+has_input:Bool) -> Result<&2,&2,String,Transition>:
  K.FurnaceSlots{input,fuel,output} = slots
  match has_input:
    case False{}: Done{finish(was,Snapshot{reset_progress(frame),slots},False{},[],None{})}
    case True{}:
      do Result<&2,&2,String,Transition>:
        selection : Selection <- select(catalog,frame,input,metadata)
        selected(was,catalog,fuel_catalog,context,profiles,frame,slots,metadata,selection)
def dispatch(+was:Bool,+catalog:K.Catalog,+fuel_catalog:F.Catalog,+context:F.Context,+profiles:List<&2,F.FuelProfile>,+frame:Frame,+slots:K.FurnaceSlots,+metadata:List<&2,Inv.ItemMetadata>,+run:Bool) -> Result<&2,&2,String,Transition>:
  K.FurnaceSlots{+input,fuel,output} = slots
  match run:
    case False{}: Done{finish(was,Snapshot{cool(frame),slots},False{},[],None{})}
    case True{}: active(was,catalog,fuel_catalog,context,profiles,frame,slots,metadata,K.positive(input))
def tick_checked(+catalog:K.Catalog,+fuel_catalog:F.Catalog,+context:F.Context,+profiles:List<&2,F.FuelProfile>,+snapshot:Snapshot,+metadata:List<&2,Inv.ItemMetadata>,+valid:Bool) -> Result<&2,&2,String,Transition>:
  Snapshot{+frame,+slots} = snapshot
  K.FurnaceSlots{+input,+fuel,output} = slots
  match valid:
    case False{}: Fail{"furnace snapshot rejected: kind, slot/component/count authority or recipesUsed"}
    case True{}:
      +next = spend_lit(frame)
      dispatch(lit(frame),catalog,fuel_catalog,context,profiles,next,slots,metadata,lit(next) || (K.positive(fuel) && K.positive(input)))
def use_ids(+values:List<&2,Use>) -> List<&2,String>:
  match values:
    case Nil{}: []
    case Use{id,count} <> rest: id <> use_ids(rest)
def uses_valid(+values:List<&2,Use>) -> Bool:
  match values:
    case Nil{}: True{}
    case Use{+id,count} <> +rest: D.identifier(id) && Bool.not(F.contains(use_ids(rest),id)) && uses_valid(rest)
def valid(+catalog:K.Catalog,+snapshot:Snapshot,+metadata:List<&2,Inv.ItemMetadata>) -> Bool:
  K.Catalog{recipes,tags,items} = catalog
  Snapshot{Frame{kind,r,t,s,c,speed,cached,uses},K.FurnaceSlots{input,fuel,output}} = snapshot
  Bool.not(K.kind_equal(kind,K.Campfire{})) && R.slots_valid_with_metadata([input,fuel,output],items,metadata) && uses_valid(uses)
def tick(+catalog:K.Catalog,+fuel_catalog:F.Catalog,+context:F.Context,+profiles:List<&2,F.FuelProfile>,+snapshot:Snapshot,+metadata:List<&2,Inv.ItemMetadata>) -> Result<&2,&2,String,Transition>:
  tick_checked(catalog,fuel_catalog,context,profiles,snapshot,metadata,valid(catalog,snapshot,metadata))

# The three logical slots have a single affine owner; the fourth backing cell
# is inaccessible. All gameplay decisions above run before writes are applied.
def read_third(+length:U32,+input:Inv.Slot,+fuel:Inv.Slot,result:Array<Inv.Slot> & Inv.Slot) -> Inv.Inventory & K.FurnaceSlots:
  (cells,output) = result
  (Inv.Inventory{cells,length},K.FurnaceSlots{input,fuel,output})
def read_second(+length:U32,+input:Inv.Slot,result:Array<Inv.Slot> & Inv.Slot) -> Inv.Inventory & K.FurnaceSlots:
  (cells,fuel) = result
  read_third(length,input,fuel,Array.get(Inv.Slot,cells,2))
def read_first(+length:U32,result:Array<Inv.Slot> & Inv.Slot) -> Inv.Inventory & K.FurnaceSlots:
  (cells,input) = result
  read_second(length,input,Array.get(Inv.Slot,cells,1))
def read_slots(inv:Inv.Inventory) -> Inv.Inventory & K.FurnaceSlots:
  Inv.Inventory{cells,length} = inv
  read_first(length,Array.get(Inv.Slot,cells,0))
def inspected(result:Inv.Inventory & K.FurnaceSlots,+frame:Frame) -> State & Maybe<&2,Snapshot>:
  (inventory,slots) = result
  (State{inventory,frame},Some{Snapshot{frame,slots}})
def inspect_checked(inventory:Inv.Inventory,+frame:Frame,+allowed:Bool) -> State & Maybe<&2,Snapshot>:
  match allowed:
    case False{}: (State{inventory,frame},None{})
    case True{}: inspected(read_slots(inventory),frame)
def inspect_sized(+frame:Frame,+length:U32,result:Array<Inv.Slot> & U32) -> State & Maybe<&2,Snapshot>:
  (cells,capacity) = result
  inspect_checked(Inv.Inventory{cells,length},frame,U32.is_eq(length,3) && U32.is_ge(capacity,3))
def inspect(state:State) -> State & Maybe<&2,Snapshot>:
  State{Inv.Inventory{cells,length},frame} = state
  inspect_sized(frame,length,Array.size(Inv.Slot,cells))
def write_slots(inv:Inv.Inventory,+slots:K.FurnaceSlots) -> Inv.Inventory:
  Inv.Inventory{cells,length} = inv
  K.FurnaceSlots{input,fuel,output} = slots
  cells = Array.set(Inv.Slot,cells,0,input)
  cells = Array.set(Inv.Slot,cells,1,fuel)
  cells = Array.set(Inv.Slot,cells,2,output)
  Inv.Inventory{cells,length}
def install(+snapshot:Snapshot) -> State:
  Snapshot{frame,slots} = snapshot
  State{write_slots(Inv.Inventory{Array.new(Inv.Slot,2n,Inv.InvEmpty{}),3},slots),frame}
def commit(state:State,+result:Result<&2,&2,String,Transition>) -> State & Result<&2,&2,String,Effects>:
  match state result:
    case State{inventory,previous} Fail{message}: (State{inventory,previous},Fail{message})
    case State{inventory,previous} Done{Transition{Snapshot{frame,slots},effects}}:
      (State{write_slots(inventory,slots),frame},Done{effects})
def stepped(result:State & Maybe<&2,Snapshot>,+catalog:K.Catalog,+fuel_catalog:F.Catalog,+context:F.Context,+profiles:List<&2,F.FuelProfile>,+metadata:List<&2,Inv.ItemMetadata>) -> State & Result<&2,&2,String,Effects>:
  match result:
    case (state,None{}): (state,Fail{"furnace owner requires three logical slots and sufficient backing capacity"})
    case (state,Some{snapshot}): commit(state,tick(catalog,fuel_catalog,context,profiles,snapshot,metadata))
def step(state:State,+catalog:K.Catalog,+fuel_catalog:F.Catalog,+context:F.Context,+profiles:List<&2,F.FuelProfile>,+metadata:List<&2,Inv.ItemMetadata>) -> State & Result<&2,&2,String,Effects>:
  stepped(inspect(state),catalog,fuel_catalog,context,profiles,metadata)

def persisted(+snapshot:Snapshot) -> Persisted:
  Snapshot{Frame{kind,r,t,s,c,speed,cached,uses},slots} = snapshot
  Persisted{slots,s,c,r,t,speed,uses}
def saved(result:State & Maybe<&2,Snapshot>) -> State & Result<&2,&2,String,Persisted>:
  match result:
    case (state,None{}): (state,Fail{"furnace owner requires three logical slots and sufficient backing capacity"})
    case (state,Some{snapshot}): (state,Done{persisted(snapshot)})
def save(state:State) -> State & Result<&2,&2,String,Persisted>:
  saved(inspect(state))
def load_snapshot(+kind:K.CookingKind,+value:Persisted) -> Snapshot:
  Persisted{slots,s,c,r,t,speed,uses} = value
  Snapshot{Frame{kind,r,t,s,c,speed,None{},uses},slots}
def restore_checked(+snapshot:Snapshot,+valid:Bool) -> Result<&2,&1,String,State>:
  match valid:
    case False{}: Fail{"furnace restore rejected: slot/component/count authority, kind or recipesUsed"}
    case True{}: Done{install(snapshot)}
def load(+catalog:K.Catalog,+kind:K.CookingKind,+value:Persisted,+metadata:List<&2,Inv.ItemMetadata>) -> Result<&2,&1,String,State>:
  +snapshot = load_snapshot(kind,value)
  restore_checked(snapshot,valid(catalog,snapshot,metadata))
def new_checked(+kind:K.CookingKind,+allowed:Bool) -> Maybe<State>:
  match allowed:
    case False{}: None{}
    case True{}: Some{install(Snapshot{Frame{kind,0,0,0,0,1.0,None{},[]},K.FurnaceSlots{Inv.InvEmpty{},Inv.InvEmpty{},Inv.InvEmpty{}}})}
def new(+kind:K.CookingKind) -> Maybe<State>:
  new_checked(kind,Bool.not(K.kind_equal(kind,K.Campfire{})))
