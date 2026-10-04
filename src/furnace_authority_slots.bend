import Base
import ./inventory.bend as Inv
import ./crafting_recipe.bend as R
import ./cooking_recipe.bend as K
import ./cooking_recipe_number.bend as N
import ./furnace_authority.bend as A
import ./furnace_authority_fuel.bend as F

def slot_at(+slots:K.FurnaceSlots,+index:U32) -> Inv.Slot:
  K.FurnaceSlots{input,fuel,output} = slots
  match index:
    case 0: input
    case 1: fuel
    case 2: output
    case _: Inv.InvEmpty{}
def replaced(+slots:K.FurnaceSlots,+index:U32,+value:Inv.Slot) -> K.FurnaceSlots:
  K.FurnaceSlots{input,fuel,output} = slots
  match index:
    case 0: K.FurnaceSlots{value,fuel,output}
    case 1: K.FurnaceSlots{input,value,output}
    case 2: K.FurnaceSlots{input,fuel,value}
    case _: K.FurnaceSlots{input,fuel,output}
def one(+slot:Inv.Slot) -> Inv.Slot:
  match slot:
    case Inv.InvEmpty{}: Inv.InvEmpty{}
    case Inv.InvStack{key,count}: Inv.InvStack{key,1}
def definition_limit(+value:Maybe<&2,R.ItemDefinition>) -> U32:
  match value:
    case None{}: 0
    case Some{R.ItemDefinition{id,limit,remainder}}: limit
def key_limit(+catalog:K.Catalog,+metadata:List<&2,Inv.ItemMetadata>,+key:Inv.ItemKey) -> U32:
  K.Catalog{recipes,tags,items} = catalog
  Inv.ItemKey{+id,+components} = key
  R.choose(U32,definition_limit(R.item_definition(items,id)),K.output_limit(R.input_metadata(metadata,Inv.ItemKey{id,components})),String.eq(components,""))
def clamped(+catalog:K.Catalog,+metadata:List<&2,Inv.ItemMetadata>,+slot:Inv.Slot) -> Inv.Slot:
  match slot:
    case Inv.InvEmpty{}: Inv.InvEmpty{}
    case Inv.InvStack{+key,count}: Inv.InvStack{key,U32.min(count,U32.min(64,key_limit(catalog,metadata,key)))}
def same_item(+existing:Inv.Slot,+new:Inv.Slot) -> Bool:
  match existing new:
    case Inv.InvStack{a,n} Inv.InvStack{b,m}: Inv.key_equal(a,b)
    case _ _: False{}
def total(+plan:Maybe<&2,K.Plan>,+speed:F32) -> U32:
  match plan:
    case None{}: 200
    case Some{K.Plan{id,kind,output,before,time,xp}}: N.total_time(time,speed)
def retimed(+frame:A.Frame,+selection:A.Selection) -> A.Frame:
  A.Frame{kind,r,t,s,c,+speed,cached,uses} = frame
  A.Selection{plan,next} = selection
  A.Frame{kind,r,t,0,total(plan,speed),speed,next,uses}
def changed_input(+catalog:K.Catalog,+frame:A.Frame,+slots:K.FurnaceSlots,+metadata:List<&2,Inv.ItemMetadata>) -> Result<&2,&2,String,A.Transition>:
  K.FurnaceSlots{input,fuel,output} = slots
  do Result<&2,&2,String,A.Transition>:
    selection : A.Selection <- A.select(catalog,frame,input,metadata)
    return A.Transition{A.Snapshot{retimed(frame,selection),slots},A.Effects{True{},None{},[],None{}}}
def changed(+catalog:K.Catalog,+frame:A.Frame,+slots:K.FurnaceSlots,+metadata:List<&2,Inv.ItemMetadata>,+reset:Bool) -> Result<&2,&2,String,A.Transition>:
  match reset:
    case True{}: changed_input(catalog,frame,slots,metadata)
    case False{}: Done{A.Transition{A.Snapshot{frame,slots},A.Effects{False{},None{},[],None{}}}}
def put_checked(+catalog:K.Catalog,+snapshot:A.Snapshot,+index:U32,+value:Inv.Slot,+metadata:List<&2,Inv.ItemMetadata>,+allowed:Bool) -> Result<&2,&2,String,A.Transition>:
  A.Snapshot{frame,+slots} = snapshot
  match allowed:
    case False{}: Fail{"furnace slot replacement refused: index, owner or exact item authority"}
    case True{}:
      +new = clamped(catalog,metadata,value)
      changed(catalog,frame,replaced(slots,index,new),metadata,U32.is_zero(index) && Bool.not(same_item(slot_at(slots,index),new)))
def put_snapshot(+catalog:K.Catalog,+snapshot:A.Snapshot,+index:U32,+value:Inv.Slot,+metadata:List<&2,Inv.ItemMetadata>) -> Result<&2,&2,String,A.Transition>:
  K.Catalog{recipes,tags,items} = catalog
  +nonempty_or_clear = K.positive(value) || K.slot_equal(value,Inv.InvEmpty{})
  put_checked(catalog,snapshot,index,value,metadata,U32.is_lt(index,3) && A.valid(catalog,snapshot,metadata) && nonempty_or_clear && R.slots_valid_with_metadata([one(value)],items,metadata))
def put_inspected(result:A.State & Maybe<&2,A.Snapshot>,+catalog:K.Catalog,+index:U32,+value:Inv.Slot,+metadata:List<&2,Inv.ItemMetadata>) -> A.State & Result<&2,&2,String,A.Effects>:
  match result:
    case (state,None{}): (state,Fail{"furnace owner requires three logical slots and sufficient backing capacity"})
    case (state,Some{snapshot}): A.commit(state,put_snapshot(catalog,snapshot,index,value,metadata))
# Low-level Container.setItem semantics. Slot permissions and transfer ownership
# are separate: this clips the supplied count just as the Java receiver does.
def put(state:A.State,+catalog:K.Catalog,+index:U32,+value:Inv.Slot,+metadata:List<&2,Inv.ItemMetadata>) -> A.State & Result<&2,&2,String,A.Effects>:
  put_inspected(A.inspect(state),catalog,index,value,metadata)
def is_bucket(+slot:Inv.Slot) -> Bool:
  match slot:
    case Inv.InvEmpty{}: False{}
    case Inv.InvStack{Inv.ItemKey{id,components},count}: String.eq(id,"minecraft:bucket")
def place_fuel(+existing:Inv.Slot,+value:Inv.Slot,+component:Maybe<&2,F.CookingFuel>) -> Bool:
  Maybe.is_some(&2,F.CookingFuel,component) || (is_bucket(value) && Bool.not(is_bucket(existing)))
def can_place(+fuel_catalog:F.Catalog,+profiles:List<&2,F.FuelProfile>,+slots:K.FurnaceSlots,+index:U32,+value:Inv.Slot) -> Result<&2,&2,String,Bool>:
  K.FurnaceSlots{input,fuel,output} = slots
  match index:
    case 0: Done{True{}}
    case 1:
      do Result<&2,&2,String,Bool>:
        component : Maybe<&2,F.CookingFuel> <- F.fuel_for(fuel_catalog,profiles,value)
        return place_fuel(fuel,value,component)
    case _: Done{False{}}
def slots_for_face(+face:A.Face) -> List<&2,U32>:
  match face:
    case A.Up{}: [0]
    case A.Down{}: [2,1]
    case A.Side{}: [1]
def bottom_take(+catalog:K.Catalog,+slot:Inv.Slot) -> Bool:
  K.Catalog{recipes,tags,items} = catalog
  match slot:
    case Inv.InvEmpty{}: False{}
    case Inv.InvStack{Inv.ItemKey{id,components},count}: R.tag_contains(R.tag_members(tags,"minecraft:furnace_fuel_bottom_takeable"),id)
def can_take(+catalog:K.Catalog,+index:U32,+slot:Inv.Slot,+face:A.Face) -> Bool:
  match index face:
    case 1 A.Down{}: bottom_take(catalog,slot)
    case _ _: True{}
