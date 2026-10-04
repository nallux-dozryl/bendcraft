import Base
import ../src/core.bend as C
import ../src/schedule.bend as Q
import ../src/block_light.bend as L
import ../src/block_light_world.bend as W
import ../src/cooking_world.bend as CW
import ../src/cooking_world_bindings.bend as B
import ../src/cooking_world_store.bend as S
import ../src/cooking_recipe.bend as K
import ../src/crafting_recipe.bend as R
import ../src/furnace_authority.bend as F
import ../src/furnace_authority_fuel.bend as Fuel
import ../src/campfire_authority_items.bend as AI
import ../src/inventory.bend as I

# These statements quantify over the actual affine owner/store and call the
# production branch, rather than proving a disconnected marker projection.
law teardown_precedes_original_ordered_intents:
  for candidate:C.Position
  for previous:B.Binding
  for entity:S.Entity
  for position:C.Position
  for rest:List<&1,S.Entry>
  for views:List<&2,S.View>
  {S.changed_entry(S.Entry{candidate,previous,entity},position,B.Other{},rest,views,False{}) ==
    (rest,S.OwnerReset{position} <> S.removal(views,position,previous)) : List<&1,S.Entry> & List<&2,S.Effect>}
def teardown_precedes_original_ordered_intents(candidate,previous,entity,position,rest,views): {==}

law same_block_branch_retains_owner_without_reset:
  for candidate:C.Position
  for previous:B.Binding
  for next:B.Binding
  for entity:S.Entity
  for position:C.Position
  for rest:List<&1,S.Entry>
  for views:List<&2,S.View>
  {S.changed_entry(S.Entry{candidate,previous,entity},position,B.Cooking{next},rest,views,True{}) ==
    (S.Entry{candidate,next,S.updated_entity(previous,next,entity)} <> rest,[]) : List<&1,S.Entry> & List<&2,S.Effect>}
def same_block_branch_retains_owner_without_reset(candidate,previous,next,entity,position,rest,views): {==}

def position(x:U32) -> C.Position: C.Position{"minecraft:overworld",x,0,0}
def furnace(state:U32,lit:Bool) -> B.Binding:
  B.Binding{state,"minecraft:furnace",B.Furnace{K.Smelting{}},lit,1,2}
def smoker() -> B.Binding:
  B.Binding{3,"minecraft:smoker",B.Furnace{K.Smoking{}},False{},3,3}
def bindings() -> B.Catalog:
  B.Catalog{"lifecycle-fixture",4,Map.set(&2,Maybe<&2,B.Binding>,
    Map.set(&2,Maybe<&2,B.Binding>,Map.set(&2,Maybe<&2,B.Binding>,
      Map.set(&2,Maybe<&2,B.Binding>,MTip{},"0",None{}),"1",Some{furnace(1,False{})}),
      "2",Some{furnace(2,True{})}),"3",Some{smoker()})}
def stack(id:String,count:U32) -> I.Slot: I.InvStack{I.ItemKey{id,""},count}
def snapshot() -> F.Snapshot:
  F.Snapshot{F.Frame{K.Smelting{},11,13,17,19,1.0,Some{"fixture:smelt"},[F.Use{"fixture:smelt",2}]},
    K.FurnaceSlots{stack("minecraft:iron_ore",2),stack("minecraft:coal",1),stack("minecraft:iron_ingot",3)}}
def recipes() -> K.Catalog:
  K.Catalog{[K.Cooking{"fixture:smelt",K.Smelting{},R.AnyOf{[R.Item{"minecraft:iron_ore"}]},
    stack("minecraft:iron_ingot",1),200,0.5}],[],[]}
def context() -> CW.Context:
  CW.Context{bindings(),AI.Context{recipes(),[],MTip{}},Fuel.Catalog{[],[],[],[],[],[]},64n}
def properties(unit:Unit,state:U32) -> Maybe<&2,L.Descriptor>:
  Some{L.Descriptor{state,0,0}}
def enabled(unit:Unit,position:C.Position) -> Bool: True{}
def guard(label:String,valid:Bool) -> IO(Unit):
  match valid:
    case False{}: IO.die(Unit,3,"lifecycle guard failed: " ++ label)
    case True{}: IO.print("ok " ++ label)
def expect(label:String,result:CW.State & Result<&2,&2,CW.Error,Unit>,next:CW.State -> IO(Unit)) -> IO(Unit):
  (owner,status) = result
  match status:
    case Fail{error}: IO.die(Unit,2,"lifecycle operation refused: " ++ label)
    case Done{unit}: next(owner)
def installed(result:C.World & Result<&2,&2,C.Error,Unit>,next:CW.State -> IO(Unit)) -> IO(Unit):
  (world,status) = result
  match status:
    case Fail{error}: IO.die(Unit,2,"lifecycle fixture Core write refused")
    case Done{unit}:
      next(CW.State{W.State{world,L.new(),None{}},
        [S.Entry{position(0),furnace(1,False{}),S.Furnace{F.install(snapshot())}}],CW.Idle{},[]})
def created(result:C.World & Result<&2,&2,C.Error,Unit>,next:CW.State -> IO(Unit)) -> IO(Unit):
  (world,status) = result
  match status:
    case Fail{error}: IO.die(Unit,2,"lifecycle fixture Core create refused")
    case Done{unit}: installed(C.write_block(world,position(0),1),next)
def initial(next:CW.State -> IO(Unit)) -> IO(Unit):
  created(C.create_section(C.new(4),position(0),0),next)
def admit(owner:CW.State,sequence:Nat,point:C.Position,state:U32) -> CW.State & Result<&2,&2,CW.Error,Unit>:
  CW.admit(~Unit,~properties,~enabled,Unit{},owner,C.Developer{},Q.Stamp{1n,0,sequence},C.BlockSet{point,state})
def start(owner:CW.State,next:CW.State -> IO(Unit)) -> IO(Unit):
  expect("start one scheduled tick",CW.start_tick(~Unit,~properties,~enabled,Unit{},context(),owner),next)
def original_intents(values:List<&2,S.Effect>) -> Bool:
  match values:
    case S.OwnerReset{+p} <> S.Drop{a,0,ia} <> S.Drop{b,1,ib} <> S.Drop{c,2,ic} <> S.Experience{d,F.XpRequest{id,count,xp}} <> Nil{}:
      B.equal_position(p,position(0)) && B.equal_position(p,a) && B.equal_position(p,b) &&
      B.equal_position(p,c) && B.equal_position(p,d) &&
      K.slot_equal(ia,stack("minecraft:iron_ore",2)) && K.slot_equal(ib,stack("minecraft:coal",1)) &&
      K.slot_equal(ic,stack("minecraft:iron_ingot",3)) && String.eq(id,"fixture:smelt") &&
      U32.is_eq(count,2) && U32.is_eq(F32.bits(xp),1056964608)
    case _: False{}
def reset_empty(values:List<&2,S.Effect>) -> Bool:
  match values:
    case S.OwnerReset{+p} <> S.Drop{a,0,I.InvEmpty{}} <> S.Drop{b,1,I.InvEmpty{}} <> S.Drop{c,2,I.InvEmpty{}} <> Nil{}:
      B.equal_position(p,position(0)) && B.equal_position(p,a) && B.equal_position(p,b) && B.equal_position(p,c)
    case _: False{}
def twice(values:List<&2,S.Effect>) -> Bool:
  match values:
    case +a <> +b <> +c <> +d <> +e <> tail:
      original_intents([a,b,c,d,e]) && reset_empty(tail)
    case _: False{}
def clock_result(label:String,expected_revision:Nat,result:C.World & C.Clock,next:C.World -> IO(Unit)) -> IO(Unit):
  (owner,C.Clock{tick,time,paused,daylight,revision,pending}) = result
  do IO<Unit>:
    guard(label,Nat.is_eq(tick,1n) && Nat.is_eq(time,1n) && Nat.is_eq(revision,expected_revision) && Nat.is_eq(pending,0n))
    next(owner)
def checked_clock(label:String,expected_revision:Nat,world:C.World,next:C.World -> IO(Unit)) -> IO(Unit):
  clock_result(label,expected_revision,C.clock(world),next)
def final_block(result:C.World & Result<&2,&2,C.Error,U32>,expected:U32) -> IO(Unit):
  (world,status) = result
  match status:
    case Fail{error}: IO.die(Unit,2,"lifecycle final Core read refused")
    case Done{id}: guard("actual Core final block",U32.is_eq(id,expected))
def removed(owner:CW.State) -> IO(Unit):
  match owner:
    case CW.State{W.State{world,light,loading},entries,CW.Cooking{tick,effects},keys}:
      do IO<Unit>:
        guard("remove-recreate-remove two markers and exact ordered drops/XP",twice(effects))
        guard("final cooking owner removed",List.is_empty(&1,S.Entry,entries) && Nat.is_eq(tick,1n))
        checked_clock("exactly one tick three accepted edits",3n,world,
          world => final_block(C.read_block(world,position(0)),0))
    case _: IO.die(Unit,2,"lifecycle final phase invalid")
def remove_recreate() -> IO(Unit):
  initial(owner => expect("remove",admit(owner,1n,position(0),0),owner =>
    expect("recreate same furnace",admit(owner,2n,position(0),1),owner =>
      expect("remove recreated furnace",admit(owner,3n,position(0),0),owner => start(owner,removed)))))
def retained_view(value:Maybe<&2,S.View>) -> Bool:
  match value:
    case Some{S.View{p,B.Binding{state,block,family,lit,dark,bright},S.FurnaceView{F.Snapshot{
        F.Frame{kind,r,total,spent,cook,speed,cache,uses},K.FurnaceSlots{input,fuel,output}}},effects}}:
      U32.is_eq(state,1) && U32.is_eq(r,11) && U32.is_eq(total,13) && U32.is_eq(spent,17) && U32.is_eq(cook,19) &&
      K.slot_equal(input,stack("minecraft:iron_ore",2)) && K.slot_equal(fuel,stack("minecraft:coal",1)) &&
      K.slot_equal(output,stack("minecraft:iron_ingot",3))
    case _: False{}
def retained(result:List<&1,S.Entry> & Result<&2,&2,String,List<&2,S.View>>,world:C.World,revision:Nat) -> IO(Unit):
  (entries,status) = result
  match status:
    case Fail{message}: IO.die(Unit,2,"lifecycle retained inspection refused")
    case Done{views}:
      do IO<Unit>:
        guard("same block LIT retains original furnace contents/timers",retained_view(S.view_at(views,position(0))))
        checked_clock("retained owner exact Core revision",revision,world,world => final_block(C.read_block(world,position(0)),1))
def same_block_done(owner:CW.State) -> IO(Unit):
  match owner:
    case CW.State{W.State{world,light,loading},entries,CW.Cooking{tick,effects},keys}:
      do IO<Unit>:
        guard("same block LIT has no teardown markers or output intents",List.is_empty(&2,S.Effect,effects))
        retained(S.inspect(recipes(),entries),world,2n)
    case _: IO.die(Unit,2,"lifecycle same block phase invalid")
def same_block() -> IO(Unit):
  initial(owner => expect("lit on",admit(owner,1n,position(0),2),owner =>
    expect("lit off",admit(owner,2n,position(0),1),owner => start(owner,same_block_done))))
def fresh_smoker(value:Maybe<&2,S.View>) -> Bool:
  match value:
    case Some{S.View{p,B.Binding{state,block,family,lit,dark,bright},S.FurnaceView{F.Snapshot{
        F.Frame{K.Smoking{},r,total,spent,cook,speed,None{},Nil{}},K.FurnaceSlots{I.InvEmpty{},I.InvEmpty{},I.InvEmpty{}}}},effects}}:
      U32.is_eq(state,3) && U32.is_eq(r,0) && U32.is_eq(total,0) && U32.is_eq(spent,0) && U32.is_eq(cook,0)
    case _: False{}
def replaced_views(result:List<&1,S.Entry> & Result<&2,&2,String,List<&2,S.View>>,world:C.World) -> IO(Unit):
  (entries,status) = result
  match status:
    case Fail{message}: IO.die(Unit,2,"lifecycle replacement inspection refused")
    case Done{views}:
      do IO<Unit>:
        guard("different cooking block installs fresh actual owner",fresh_smoker(S.view_at(views,position(0))))
        checked_clock("replacement exactly one accepted tick/edit",1n,world,world => final_block(C.read_block(world,position(0)),3))
def replaced(owner:CW.State) -> IO(Unit):
  match owner:
    case CW.State{W.State{world,light,loading},entries,CW.Cooking{tick,effects},keys}:
      do IO<Unit>:
        guard("replacement reset precedes preserved drops/XP",original_intents(effects))
        replaced_views(S.inspect(recipes(),entries),world)
    case _: IO.die(Unit,2,"lifecycle replacement phase invalid")
def replacement() -> IO(Unit):
  initial(owner => expect("replace furnace with smoker",admit(owner,1n,position(0),3),owner => start(owner,replaced)))
def refused(owner:CW.State) -> IO(Unit):
  match owner:
    case CW.State{W.State{world,light,loading},entries,CW.Cooking{tick,effects},keys}:
      do IO<Unit>:
        guard("rejected missing section write emits no reset",List.is_empty(&2,S.Effect,effects))
        retained(S.inspect(recipes(),entries),world,0n)
    case _: IO.die(Unit,2,"lifecycle refusal phase invalid")
def refusal() -> IO(Unit):
  initial(owner => expect("schedule missing section write",admit(owner,1n,position(32),0),owner => start(owner,refused)))
def main() -> IO(Unit):
  do IO<Unit>:
    remove_recreate()
    same_block()
    replacement()
    refusal()
