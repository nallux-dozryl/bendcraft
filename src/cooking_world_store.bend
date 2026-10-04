import Base
import ./core.bend as C
import ./cooking_world_bindings.bend as B
import ./inventory.bend as I
import ./cooking_recipe.bend as K
import ./furnace_authority.bend as F
import ./furnace_authority_xp.bend as X
import ./campfire_authority.bend as A
import ./campfire_authority_items.bend as AI

type Entity is Type:
  Furnace{state:F.State}
  Campfire{state:A.State}
type Entry is Type:
  Entry{position:C.Position,binding:B.Binding,entity:Entity}
type Body is Data:
  FurnaceView{snapshot:F.Snapshot}
  CampfireView{kind:A.CampfireKind,lit:Bool,cells:A.Four,cache:Maybe<&2,String>}
type Effect is Data:
  OwnerReset{position:C.Position}
  Drop{position:C.Position,slot:U32,item:I.Slot}
  Experience{position:C.Position,request:F.XpRequest}
  Dirty{position:C.Position}
  BlockUpdate{position:C.Position,count:Nat}
  BlockChange{position:C.Position,count:Nat}
type View is Data:
  View{position:C.Position,binding:B.Binding,body:Body,removal:List<&2,Effect>}

def drops(+position:C.Position,values:List<&2,A.Drop>) -> List<&2,Effect>:
  match values:
    case Nil{}: []
    case A.Drop{slot,item} <> rest: Drop{position,slot,item} <> drops(position,rest)
def experiences(+position:C.Position,values:List<&2,F.XpRequest>) -> List<&2,Effect>:
  match values:
    case Nil{}: []
    case head <> rest: Experience{position,head} <> experiences(position,rest)
def furnace_removal(+recipes:K.Catalog,+position:C.Position,snapshot:F.Snapshot) -> Result<&2,&2,String,List<&2,Effect>>:
  F.Snapshot{+frame,K.FurnaceSlots{input,fuel,output}} = snapshot
  do Result<&2,&2,String,List<&2,Effect>>:
    requests : List<&2,F.XpRequest> <- X.pop(recipes,frame)
    return List.append(&2,Effect,[Drop{position,0,input},Drop{position,1,fuel},Drop{position,2,output}],experiences(position,requests))
def campfire_removal(+position:C.Position,cells:A.Four) -> List<&2,Effect>:
  A.Four{A.Cell{AI.Input{a,pa},ap,at},A.Cell{AI.Input{b,pb},bp,bt},A.Cell{AI.Input{c,pc},cp,ct},A.Cell{AI.Input{d,pd},dp,dt}} = cells
  [Drop{position,0,a},Drop{position,1,b},Drop{position,2,c},Drop{position,3,d}]
def furnace_inspected(+recipes:K.Catalog,+position:C.Position,+binding:B.Binding,
    result:F.State & Maybe<&2,F.Snapshot>) -> Entry & Result<&2,&2,String,View>:
  (owner,value) = result
  match value:
    case None{}: (Entry{position,binding,Furnace{owner}},Fail{"cooking-world:invalid-furnace-array-owner"})
    case Some{+snapshot}:
      (Entry{position,binding,Furnace{owner}},Result.map(&2,&2,String,List<&2,Effect>,View,
        removal => View{position,binding,FurnaceView{snapshot},removal},furnace_removal(recipes,position,snapshot)))
def inspect_entry(recipes:K.Catalog,entry:Entry) -> Entry & Result<&2,&2,String,View>:
  match entry:
    case Entry{position,binding,Furnace{owner}}: furnace_inspected(recipes,position,binding,F.inspect(owner))
    case Entry{+position,+binding,Campfire{A.State{+kind,+lit,+cells,+cache}}}:
      (Entry{position,binding,Campfire{A.State{kind,lit,cells,cache}}},
        Done{View{position,binding,CampfireView{kind,lit,cells,cache},campfire_removal(position,cells)}})
def inspected_cons(result:List<&1,Entry> & Result<&2,&2,String,List<&2,View>>,
    entry:Entry,head:Result<&2,&2,String,View>) ->
    List<&1,Entry> & Result<&2,&2,String,List<&2,View>>:
  (entries,tail) = result
  match tail head:
    case _ Fail{message}: (entry <> entries,Fail{message})
    case Fail{message} Done{value}: (entry <> entries,Fail{message})
    case Done{rest} Done{value}: (entry <> entries,Done{value <> rest})
def inspected_head(result:Entry & Result<&2,&2,String,View>,tail:List<&1,Entry> & Result<&2,&2,String,List<&2,View>>) ->
    List<&1,Entry> & Result<&2,&2,String,List<&2,View>>:
  (entry,head) = result
  inspected_cons(tail,entry,head)
def inspect(+recipes:K.Catalog,entries:List<&1,Entry>) ->
    List<&1,Entry> & Result<&2,&2,String,List<&2,View>>:
  match entries:
    case Nil{}: ([],Done{[]})
    case head <> tail: inspected_head(inspect_entry(recipes,head),inspect(recipes,tail))
def view_at(values:List<&2,View>,+position:C.Position) -> Maybe<&2,View>:
  match values:
    case Nil{}: None{}
    case +head <> rest:
      View{+candidate,binding,body,removal} = head
      Bool.pick(Maybe<&2,View>,B.equal_position(candidate,position),Some{head},view_at(rest,position))
def empty_removal(+position:C.Position,binding:B.Binding) -> List<&2,Effect>:
  B.Binding{state,block,family,lit,dark,bright} = binding
  match family:
    case B.Furnace{kind}: [Drop{position,0,I.InvEmpty{}},Drop{position,1,I.InvEmpty{}},Drop{position,2,I.InvEmpty{}}]
    case B.Campfire{kind}: [Drop{position,0,I.InvEmpty{}},Drop{position,1,I.InvEmpty{}},Drop{position,2,I.InvEmpty{}},Drop{position,3,I.InvEmpty{}}]
def removal_found(position:C.Position,binding:B.Binding,value:Maybe<&2,View>) -> List<&2,Effect>:
  match value:
    case None{}: empty_removal(position,binding)
    case Some{View{p,b,body,effects}}: effects
def removal(values:List<&2,View>,+position:C.Position,binding:B.Binding) -> List<&2,Effect>:
  removal_found(position,binding,view_at(values,position))
def updated_campfire(owner:A.State,value:Bool,same:Bool) -> A.State:
  match same:
    case True{}: owner
    case False{}: A.cache_reset(A.set_lit(owner,value))
def fresh(binding:B.Binding) -> Entity:
  B.Binding{state,block,family,+lit,dark,bright} = binding
  match family:
    case B.Furnace{kind}:
      Furnace{F.install(F.Snapshot{F.Frame{kind,0,0,0,0,1.0,None{},[]},K.FurnaceSlots{I.InvEmpty{},I.InvEmpty{},I.InvEmpty{}}})}
    case B.Campfire{kind}: Campfire{A.new(kind,lit)}
def updated_entity(old:B.Binding,next:B.Binding,entity:Entity) -> Entity:
  B.Binding{+state,name,kind,lit,dark,bright} = old
  B.Binding{+other,block,family,+value,unlit,light} = next
  match entity:
    case Furnace{owner}: Furnace{owner}
    case Campfire{owner}:
      Campfire{updated_campfire(owner,value,U32.is_eq(state,other))}
def create(position:C.Position,value:B.Classification,entries:List<&1,Entry>) -> List<&1,Entry>:
  match value:
    case B.Other{}: entries
    case B.Cooking{+binding}: Entry{position,binding,fresh(binding)} <> entries
def changed_entry(entry:Entry,+position:C.Position,+value:B.Classification,
    rest:List<&1,Entry>,views:List<&2,View>,same:Bool) -> List<&1,Entry> & List<&2,Effect>:
  Entry{candidate,+previous,entity} = entry
  match value same:
    case B.Cooking{+next} True{}:
      (Entry{candidate,next,updated_entity(previous,next,entity)} <> rest,[])
    case _ _:
      # This branch is reached by accepted Core lifecycle publication. The
      # marker distinguishes old-owner teardown from ordinary output drops,
      # including removal and recreation of the same block in one due batch.
      (create(position,value,rest),OwnerReset{position} <> removal(views,position,previous))
def found_entry(entry:Entry,+position:C.Position,+value:B.Classification,
    rest:List<&1,Entry>,views:List<&2,View>) -> List<&1,Entry> & List<&2,Effect>:
  Entry{candidate,+previous,entity} = entry
  match value:
    case B.Other{}: changed_entry(Entry{candidate,previous,entity},position,B.Other{},rest,views,False{})
    case B.Cooking{+next}: changed_entry(Entry{candidate,previous,entity},position,value,rest,views,B.same_block(previous,next))
def kept_entry(head:Entry,result:List<&1,Entry> & List<&2,Effect>) -> List<&1,Entry> & List<&2,Effect>:
  (rest,effects) = result
  (head <> rest,effects)
def change_branch(hit:Bool,+position:C.Position,+value:B.Classification,head:Entry,tail:List<&1,Entry>,views:List<&2,View>,
    recurse:List<&1,Entry> -> List<&1,Entry> & List<&2,Effect>) -> List<&1,Entry> & List<&2,Effect>:
  match hit:
    case True{}: found_entry(head,position,value,tail,views)
    case False{}: kept_entry(head,recurse(tail))
# The representation is a general affine keyed store. Refused operations never
# pop/reinsert buckets; each retained constructor and array stays in order.
def change_go(budget:Nat,+position:C.Position,+value:B.Classification,entries:List<&1,Entry>,+views:List<&2,View>) ->
    List<&1,Entry> & List<&2,Effect>:
  match budget entries:
    case 0n entries: (entries,[])
    case _ Nil{}: (create(position,value,[]),[])
    case 1n+remaining Entry{+candidate,binding,entity} <> rest:
      change_branch(B.equal_position(position,candidate),position,value,Entry{candidate,binding,entity},rest,views,
        rest => change_go(remaining,position,value,rest,views))

def size_cons(head:Entry,result:List<&1,Entry> & Nat) -> List<&1,Entry> & Nat:
  (rest,count) = result
  (head <> rest,1n+count)
def size(entries:List<&1,Entry>) -> List<&1,Entry> & Nat:
  match entries:
    case Nil{}: ([],0n)
    case head <> tail: size_cons(head,size(tail))
def change_sized(position:C.Position,value:B.Classification,views:List<&2,View>,result:List<&1,Entry> & Nat) -> List<&1,Entry> & List<&2,Effect>:
  (entries,count) = result
  change_go(1n+count,position,value,entries,views)
def change(position:C.Position,value:B.Classification,entries:List<&1,Entry>,views:List<&2,View>) -> List<&1,Entry> & List<&2,Effect>:
  change_sized(position,value,views,size(entries))

def fresh_body(binding:B.Binding) -> Body:
  B.Binding{state,block,family,lit,dark,bright} = binding
  match family:
    case B.Furnace{kind}: FurnaceView{F.Snapshot{F.Frame{kind,0,0,0,0,1.0,None{},[]},K.FurnaceSlots{I.InvEmpty{},I.InvEmpty{},I.InvEmpty{}}}}
    case B.Campfire{kind}: CampfireView{kind,lit,A.Four{A.empty_cell(),A.empty_cell(),A.empty_cell(),A.empty_cell()},None{}}
def fresh_view(+position:C.Position,+binding:B.Binding) -> View:
  View{position,binding,fresh_body(binding),empty_removal(position,binding)}
def remove_view_cons(+head:View,position:C.Position,+tail:List<&2,View>) -> List<&2,View>:
  View{candidate,binding,body,effects} = head
  Bool.pick(List<&2,View>,B.equal_position(candidate,position),tail,head <> tail)
def remove_view(values:List<&2,View>,+position:C.Position) -> List<&2,View>:
  match values:
    case Nil{}: []
    case head <> tail: remove_view_cons(head,position,remove_view(tail,position))
def retained_view(+position:C.Position,+next:B.Binding,value:Maybe<&2,View>) -> View:
  match value:
    case None{}: fresh_view(position,next)
    case Some{+old}:
      View{p,+previous,body,effects} = old
      Bool.pick(View,B.same_block(previous,next),View{position,next,body,effects},fresh_view(position,next))
def changed_views(+position:C.Position,value:B.Classification,+views:List<&2,View>) -> List<&2,View>:
  match value:
    case B.Other{}: remove_view(views,position)
    case B.Cooking{binding}: retained_view(position,binding,view_at(views,position)) <> remove_view(views,position)
