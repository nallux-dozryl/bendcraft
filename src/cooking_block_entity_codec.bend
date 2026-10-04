import Base
import ./nbt.bend as N
import ./inventory.bend as I
import ./crafting_recipe.bend as R
import ./crafting_recipe_decoder.bend as D
import ./cooking_recipe.bend as K
import ./furnace_authority.bend as FA
import ./campfire_authority.bend as CA
import ./campfire_authority_items.bend as CI
import ./cooking_block_entity_codec_nbt.bend as B
import ./cooking_block_entity_codec_items.bend as Items

type Details is Data:
  Details{root_name:N.Text,extras:List<&2,N.Member>,inputs:List<&2,CI.Input>,admission:Items.Admission,discarded:U32}
type FurnaceDocument is Data:
  FurnaceDocument{record:FA.Persisted,details:Details}
type CampfireDocument is Data:
  CampfireDocument{record:CA.Record,details:Details}

# Unknown and base-block-entity fields remain an explicit sidecar. The cooking
# body encoder does not pretend to interpret CustomName/Lock/components.
def cooking_field(+name:N.Text,campfire:Bool) -> Bool:
  match campfire:
    case True{}: B.text_equal(name,B.text("Items")) || B.text_equal(name,B.text("CookingTimes")) || B.text_equal(name,B.text("CookingTotalTimes"))
    case False{}: B.text_equal(name,B.text("Items")) || B.text_equal(name,B.text("cooking_time_spent")) || B.text_equal(name,B.text("cooking_total_time")) || B.text_equal(name,B.text("lit_time_remaining")) || B.text_equal(name,B.text("lit_total_time")) || B.text_equal(name,B.text("speed_multiplier")) || B.text_equal(name,B.text("RecipesUsed"))
def extras(values:List<&2,N.Member>,+campfire:Bool) -> List<&2,N.Member>:
  match values:
    case Nil{}: []
    case +head <> +rest:
      N.Member{+name,value} = head
      R.choose(List<&2,N.Member>,extras(rest,campfire),head <> extras(rest,campfire),cooking_field(name,campfire))
def root_members(root:N.Root) -> Result<&2,&2,String,List<&2,N.Member>>:
  match root:
    case N.Root{name,N.Compound{members}}: Done{members}
    case _: Fail{"cooking block entity requires Compound root"}
def parsed_use_id(value:Result<&2,&2,String,String>) -> Maybe<&2,String>:
  match value:
    case Fail{message}: None{}
    case Done{raw}:
      +id = D.qualified(raw)
      R.choose(Maybe<&2,String>,Some{id},None{},D.identifier(id))
def use_id(name:N.Text) -> Maybe<&2,String>:
  N.Text{units} = name
  parsed_use_id(B.ascii(units,""))
def use_more(count:Maybe<&2,U32>,name:Maybe<&2,String>,tail:List<&2,FA.Use>) -> List<&2,FA.Use>:
  match count name:
    case Some{bits} Some{id}: FA.Use{id,bits} <> tail
    case _ _: tail
def use_entry(name:N.Text,value:N.Value,tail:List<&2,FA.Use>,duplicate:Bool) -> List<&2,FA.Use>:
  match duplicate:
    case True{}: tail
    case False{}: use_more(B.int_tag(value,False{}),use_id(name),tail)
def uses(values:List<&2,N.Member>) -> List<&2,FA.Use>:
  match values:
    case Nil{}: []
    case N.Member{+name,value} <> +rest: use_entry(name,value,uses(rest),Maybe.is_some(&2,N.Value,B.find(rest,name)))
def used(value:Maybe<&2,N.Value>) -> List<&2,FA.Use>:
  match value:
    case Some{N.Compound{members}}: uses(members)
    case _: []
def furnace_slots(values:List<&2,CI.Input>) -> Result<&2,&2,String,K.FurnaceSlots>:
  match values:
    case CI.Input{a,pa} <> CI.Input{b,pb} <> CI.Input{c,pc} <> Nil{}: Done{K.FurnaceSlots{a,b,c}}
    case _: Fail{"physical furnace decoder requires three logical inputs"}
def furnace_parsed(+context:Items.Context,name:N.Text,+members:List<&2,N.Member>,decoded:Items.Decoded) -> Result<&2,&2,String,FurnaceDocument>:
  Items.Decoded{+inputs,discarded} = decoded
  do Result<&2,&2,String,FurnaceDocument>:
    slots : K.FurnaceSlots <- furnace_slots(inputs)
    admission : Items.Admission <- Items.admit(inputs,context)
    +table : List<&2,FA.Use> = used(B.find(members,B.text("RecipesUsed")))
    B.guard(FA.uses_valid(table),"normalized RecipesUsed identifier collision outside physical codec domain")
    return FurnaceDocument{FA.Persisted{slots,B.int_optional(B.find(members,B.text("cooking_time_spent")),0,True{}),B.int_optional(B.find(members,B.text("cooking_total_time")),0,True{}),B.int_optional(B.find(members,B.text("lit_time_remaining")),0,True{}),B.int_optional(B.find(members,B.text("lit_total_time")),0,True{}),B.float_optional(B.find(members,B.text("speed_multiplier")),1.0),table},Details{name,extras(members,False{}),inputs,admission,discarded}}
def furnace_root(+context:Items.Context,+root:N.Root) -> Result<&2,&2,String,FurnaceDocument>:
  N.Root{+name,value} = root
  do Result<&2,&2,String,FurnaceDocument>:
    +members : List<&2,N.Member> <- root_members(root)
    decoded : Items.Decoded <- Items.decode(context,3n,B.find(members,B.text("Items")))
    furnace_parsed(context,name,members,decoded)
def decode_furnace(+context:Items.Context,limits:N.Limits,bytes:List<&2,U32>) -> Result<&2,&2,String,FurnaceDocument>:
  do Result<&2,&2,String,FurnaceDocument>:
    root : N.Root <- N.decode_with(limits,bytes)
    furnace_root(context,root)

# getIntArray absent/wrong type zeros the complete destination. Present arrays
# copy only min(source.length,4), retaining the old tail even when length is0.
def copy_prefix(prior:List<&2,U32>,source:List<&2,U32>) -> List<&2,U32>:
  match prior source:
    case Nil{} _: []
    case _ Nil{}: prior
    case head <> rest value <> tail: value <> copy_prefix(rest,tail)
def int_array(prior:List<&2,U32>,value:Maybe<&2,N.Value>) -> List<&2,U32>:
  match value:
    case Some{N.IntArray{values}}: copy_prefix(prior,values)
    case _: [0,0,0,0]
def cell_inputs(cells:CA.Four) -> List<&2,CI.Input>:
  CA.Four{CA.Cell{a,p,t},CA.Cell{b,q,u},CA.Cell{c,r,v},CA.Cell{d,s,w}} = cells
  [a,b,c,d]
def cell_progress(cells:CA.Four) -> List<&2,U32>:
  CA.Four{CA.Cell{a,p,t},CA.Cell{b,q,u},CA.Cell{c,r,v},CA.Cell{d,s,w}} = cells
  [p,q,r,s]
def cell_total(cells:CA.Four) -> List<&2,U32>:
  CA.Four{CA.Cell{a,p,t},CA.Cell{b,q,u},CA.Cell{c,r,v},CA.Cell{d,s,w}} = cells
  [t,u,v,w]
def campfire_cells(inputs:List<&2,CI.Input>,progress:List<&2,U32>,total:List<&2,U32>) -> Result<&2,&2,String,CA.Four>:
  match inputs progress total:
    case a <> b <> c <> d <> Nil{} p <> q <> r <> s <> Nil{} t <> u <> v <> w <> Nil{}: Done{CA.Four{CA.Cell{a,p,t},CA.Cell{b,q,u},CA.Cell{c,r,v},CA.Cell{d,s,w}}}
    case _ _ _: Fail{"physical campfire decoder requires four inputs and timer cells"}
def campfire_parsed(+context:Items.Context,prior:CA.Record,name:N.Text,+members:List<&2,N.Member>,decoded:Items.Decoded) -> Result<&2,&2,String,CampfireDocument>:
  CA.Record{+old} = prior
  Items.Decoded{+inputs,discarded} = decoded
  do Result<&2,&2,String,CampfireDocument>:
    cells : CA.Four <- campfire_cells(inputs,int_array(cell_progress(old),B.find(members,B.text("CookingTimes"))),int_array(cell_total(old),B.find(members,B.text("CookingTotalTimes"))))
    admission : Items.Admission <- Items.admit(inputs,context)
    return CampfireDocument{CA.Record{cells},Details{name,extras(members,True{}),inputs,admission,discarded}}
def campfire_root(+context:Items.Context,prior:CA.Record,+root:N.Root) -> Result<&2,&2,String,CampfireDocument>:
  N.Root{+name,value} = root
  do Result<&2,&2,String,CampfireDocument>:
    +members : List<&2,N.Member> <- root_members(root)
    decoded : Items.Decoded <- Items.decode(context,4n,B.find(members,B.text("Items")))
    campfire_parsed(context,prior,name,members,decoded)
def decode_campfire(+context:Items.Context,prior:CA.Record,limits:N.Limits,bytes:List<&2,U32>) -> Result<&2,&2,String,CampfireDocument>:
  do Result<&2,&2,String,CampfireDocument>:
    root : N.Root <- N.decode_with(limits,bytes)
    campfire_root(context,prior,root)

def slot_list(value:K.FurnaceSlots) -> List<&2,I.Slot>:
  K.FurnaceSlots{a,b,c} = value
  [a,b,c]
def input_slots(values:List<&2,CI.Input>) -> List<&2,I.Slot>:
  match values:
    case Nil{}: []
    case CI.Input{slot,patch} <> rest: slot <> input_slots(rest)
def item_list(+values:List<&2,N.Value>) -> N.Value:
  N.ListTag{R.choose(U32,0,10,List.is_empty(&2,N.Value,values)),values}
def use_members(values:List<&2,FA.Use>) -> List<&2,N.Member>:
  match values:
    case Nil{}: []
    case FA.Use{id,count} <> rest: B.member(id,N.Int{count}) <> use_members(rest)
def furnace_body(+context:Items.Context,record:FA.Persisted) -> Result<&2,&2,String,N.Value>:
  FA.Persisted{slots,s,c,r,t,speed,+table} = record
  do Result<&2,&2,String,N.Value>:
    B.guard(FA.uses_valid(table),"RecipesUsed requires unique qualified identifiers")
    rows : List<&2,N.Value> <- Items.encode_slots(slot_list(slots),context,0)
    return N.Compound{[B.member("cooking_time_spent",N.Int{s}),B.member("cooking_total_time",N.Int{c}),B.member("lit_time_remaining",N.Int{r}),B.member("lit_total_time",N.Int{t}),B.member("speed_multiplier",N.Float{B.canonical_float(speed)}),B.member("Items",item_list(rows)),B.member("RecipesUsed",N.Compound{use_members(table)})]}
def encode_furnace(context:Items.Context,limits:N.Limits,record:FA.Persisted) -> Result<&2,&2,String,List<&2,U32>>:
  do Result<&2,&2,String,List<&2,U32>>:
    body : N.Value <- furnace_body(context,record)
    N.encode_with(limits,N.Root{B.text(""),body})
def campfire_body(context:Items.Context,record:CA.Record) -> Result<&2,&2,String,N.Value>:
  CA.Record{+cells} = record
  do Result<&2,&2,String,N.Value>:
    rows : List<&2,N.Value> <- Items.encode_slots(input_slots(cell_inputs(cells)),context,0)
    return N.Compound{[B.member("Items",item_list(rows)),B.member("CookingTimes",N.IntArray{cell_progress(cells)}),B.member("CookingTotalTimes",N.IntArray{cell_total(cells)})]}
def encode_campfire(context:Items.Context,limits:N.Limits,record:CA.Record) -> Result<&2,&2,String,List<&2,U32>>:
  do Result<&2,&2,String,List<&2,U32>>:
    body : N.Value <- campfire_body(context,record)
    N.encode_with(limits,N.Root{B.text(""),body})

# Refusals never publish a replacement owner. inspect also validates backing
# capacity before any three-slot write; hidden backing cells are preserved.
def furnace_proposal(+recipes:K.Catalog,+record:FA.Persisted,kind:K.CookingKind,metadata:List<&2,I.ItemMetadata>) -> Result<&2,&2,String,FA.Transition>:
  +after = FA.load_snapshot(kind,record)
  do Result<&2,&2,String,FA.Transition>:
    B.guard(FA.valid(recipes,after,metadata),"physical furnace load exceeds live slot/component/count authority")
    return FA.Transition{after,FA.Effects{False{},None{},[],None{}}}
def furnace_committed(details:Details,result:FA.State & Result<&2,&2,String,FA.Effects>) -> FA.State & Result<&2,&2,String,Details>:
  match result:
    case (state,Fail{message}): (state,Fail{message})
    case (state,Done{effects}): (state,Done{details})
def furnace_inspected(context:Items.Context,document:FurnaceDocument,result:FA.State & Maybe<&2,FA.Snapshot>) -> FA.State & Result<&2,&2,String,Details>:
  Items.Context{recipes,defaults} = context
  FurnaceDocument{record,+details} = document
  Details{name,extras,inputs,Items.Admission{metadata,profiles},discarded} = details
  match result:
    case (state,None{}): (state,Fail{"physical furnace load requires valid three-slot backing owner"})
    case (state,Some{FA.Snapshot{FA.Frame{kind,r,t,s,c,speed,cache,uses},slots}}): furnace_committed(details,FA.commit(state,furnace_proposal(recipes,record,kind,metadata)))
def furnace_loaded(state:FA.State,context:Items.Context,result:Result<&2,&2,String,FurnaceDocument>) -> FA.State & Result<&2,&2,String,Details>:
  match result:
    case Fail{message}: (state,Fail{message})
    case Done{document}: furnace_inspected(context,document,FA.inspect(state))
def load_furnace(state:FA.State,+context:Items.Context,limits:N.Limits,bytes:List<&2,U32>) -> FA.State & Result<&2,&2,String,Details>:
  furnace_loaded(state,context,decode_furnace(context,limits,bytes))
def campfire_committed(details:Details,result:CA.State & Result<&2,&2,String,Unit>) -> CA.State & Result<&2,&2,String,Details>:
  match result:
    case (state,Fail{message}): (state,Fail{message})
    case (state,Done{unit}): (state,Done{details})
def campfire_loaded(state:CA.State,context:CI.Context,result:Result<&2,&2,String,CampfireDocument>) -> CA.State & Result<&2,&2,String,Details>:
  match result:
    case Fail{message}: (state,Fail{message})
    case Done{CampfireDocument{record,details}}: campfire_committed(details,CA.load_record(context,state,record))
def campfire_snapshotted(+context:CI.Context,limits:N.Limits,bytes:List<&2,U32>,result:CA.State & CA.Record) -> CA.State & Result<&2,&2,String,Details>:
  CI.Context{+recipes,+defaults,features} = context
  (state,prior) = result
  campfire_loaded(state,context,decode_campfire(Items.Context{recipes,defaults},prior,limits,bytes))
def load_campfire(state:CA.State,context:CI.Context,limits:N.Limits,bytes:List<&2,U32>) -> CA.State & Result<&2,&2,String,Details>:
  campfire_snapshotted(context,limits,bytes,CA.snapshot(state))
def furnace_saved(context:Items.Context,limits:N.Limits,result:FA.State & Result<&2,&2,String,FA.Persisted>) -> FA.State & Result<&2,&2,String,List<&2,U32>>:
  match result:
    case (state,Fail{message}): (state,Fail{message})
    case (state,Done{record}): (state,encode_furnace(context,limits,record))
def save_furnace(state:FA.State,context:Items.Context,limits:N.Limits) -> FA.State & Result<&2,&2,String,List<&2,U32>>:
  furnace_saved(context,limits,FA.save(state))
def campfire_saved(context:Items.Context,limits:N.Limits,result:CA.State & CA.Record) -> CA.State & Result<&2,&2,String,List<&2,U32>>:
  (state,record) = result
  (state,encode_campfire(context,limits,record))
def save_campfire(state:CA.State,context:Items.Context,limits:N.Limits) -> CA.State & Result<&2,&2,String,List<&2,U32>>:
  campfire_saved(context,limits,CA.snapshot(state))
