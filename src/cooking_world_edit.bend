import Base
import ./core.bend as C
import ./block_light.bend as L
import ./block_light_world.bend as W
import ./cooking_world.bend as CW
import ./cooking_world_bindings.bend as B
import ./cooking_world_store.bend as S
import ./campfire_authority_items.bend as AI
import ./player_core_edit.bend as P

def committed(world:W.State,effects:List<&2,S.Effect>,result:List<&1,S.Entry> & List<&2,S.Effect>) -> CW.State & Result<&2,&2,CW.Error,List<&2,S.Effect>>:
  (entries,more) = result
  (CW.State{world,entries,CW.Idle{},[]},Done{List.append(&2,S.Effect,effects,more)})
def applied(+operation:W.Prepared,+position:C.Position,classification:B.Classification,
    light:L.State,loading:Maybe<&2,W.Cursor>,entries:List<&1,S.Entry>,views:List<&2,S.View>,
    result:C.World & Result<&2,&2,P.Error,Unit>) -> CW.State & Result<&2,&2,CW.Error,List<&2,S.Effect>>:
  (world,status) = result
  match status:
    case Fail{error}: (CW.State{W.State{world,light,loading},entries,CW.Idle{},[]},Fail{CW.Player{error}})
    case Done{unit}: committed(W.State{world,W.changed_light(operation,light),loading},[],S.change(position,classification,entries,views))
def world_apply(world:W.State,+operation:W.Prepared,+position:C.Position,state:U32,cap:C.Capability,expected:Nat,sequence:Nat,maybuild:Bool,
    classification:B.Classification,entries:List<&1,S.Entry>,views:List<&2,S.View>) -> CW.State & Result<&2,&2,CW.Error,List<&2,S.Effect>>:
  W.State{owner,light,loading} = world
  applied(operation,position,classification,light,loading,entries,views,P.edit(owner,cap,position,state,expected,sequence,maybuild))
def classified(+position:C.Position,state:U32,cap:C.Capability,expected:Nat,sequence:Nat,maybuild:Bool,
    entries:List<&1,S.Entry>,views:List<&2,S.View>,world:W.State,+operation:W.Prepared,
    result:Result<&2,&2,String,B.Classification>) -> CW.State & Result<&2,&2,CW.Error,List<&2,S.Effect>>:
  match result:
    case Fail{message}: (CW.State{world,entries,CW.Idle{},[]},Fail{CW.Authority{message}})
    case Done{value}: world_apply(world,operation,position,state,cap,expected,sequence,maybuild,value,entries,views)
def prepared(catalog:B.Catalog,position:C.Position,+state:U32,cap:C.Capability,expected:Nat,sequence:Nat,maybuild:Bool,
    entries:List<&1,S.Entry>,views:List<&2,S.View>,world:W.State,result:Result<&2,&2,W.Error,W.Prepared>) -> CW.State & Result<&2,&2,CW.Error,List<&2,S.Effect>>:
  match result:
    case Fail{error}: (CW.State{world,entries,CW.Idle{},[]},Fail{CW.World{error}})
    case Done{operation}: classified(position,state,cap,expected,sequence,maybuild,entries,views,world,operation,B.classify(catalog,state))
def validated(~Light:Data,~properties:Light -> U32 -> Maybe<&2,L.Descriptor>,~enabled:Light -> C.Position -> Bool,
    light_context:Light,catalog:B.Catalog,+position:C.Position,+state:U32,cap:C.Capability,expected:Nat,sequence:Nat,maybuild:Bool,
    entries:List<&1,S.Entry>,views:List<&2,S.View>,world:W.State) -> CW.State & Result<&2,&2,CW.Error,List<&2,S.Effect>>:
  W.State{C.World{tick,time,paused,daylight,revision,+count,sections,pending,events},light,loading} = world
  prepared(catalog,position,state,cap,expected,sequence,maybuild,entries,views,
    W.State{C.World{tick,time,paused,daylight,revision,count,sections,pending,events},light,loading},
    W.checked_prepare(~Light,~properties,~enabled,light_context,C.BlockSet{position,state},C.validate(C.BlockSet{position,state},count)))
def resident(~Light:Data,~properties:Light -> U32 -> Maybe<&2,L.Descriptor>,~enabled:Light -> C.Position -> Bool,
    light_context:Light,catalog:B.Catalog,position:C.Position,state:U32,cap:C.Capability,expected:Nat,sequence:Nat,maybuild:Bool,
    entries:List<&1,S.Entry>,views:List<&2,S.View>,result:W.State & Result<&2,&2,CW.Error,Unit>) -> CW.State & Result<&2,&2,CW.Error,List<&2,S.Effect>>:
  (world,status) = result
  match status:
    case Fail{error}: (CW.State{world,entries,CW.Idle{},[]},Fail{error})
    case Done{unit}: validated(~Light,~properties,~enabled,light_context,catalog,position,state,cap,expected,sequence,maybuild,entries,views,world)
def inspected(~Light:Data,~properties:Light -> U32 -> Maybe<&2,L.Descriptor>,~enabled:Light -> C.Position -> Bool,
    light_context:Light,catalog:B.Catalog,position:C.Position,state:U32,cap:C.Capability,expected:Nat,sequence:Nat,maybuild:Bool,
    world:W.State,result:List<&1,S.Entry> & Result<&2,&2,String,List<&2,S.View>>) -> CW.State & Result<&2,&2,CW.Error,List<&2,S.Effect>>:
  (entries,status) = result
  match status:
    case Fail{message}: (CW.State{world,entries,CW.Idle{},[]},Fail{CW.Authority{message}})
    case Done{+views}: resident(~Light,~properties,~enabled,light_context,catalog,position,state,cap,expected,sequence,maybuild,entries,views,CW.resident(views,world))
def with_context(~Light:Data,~properties:Light -> U32 -> Maybe<&2,L.Descriptor>,~enabled:Light -> C.Position -> Bool,
    light_context:Light,context:CW.Context,position:C.Position,state:U32,cap:C.Capability,expected:Nat,sequence:Nat,maybuild:Bool,
    world:W.State,entries:List<&1,S.Entry>) -> CW.State & Result<&2,&2,CW.Error,List<&2,S.Effect>>:
  CW.Context{catalog,AI.Context{recipes,defaults,features},fuel,depth} = context
  inspected(~Light,~properties,~enabled,light_context,catalog,position,state,cap,expected,sequence,maybuild,world,S.inspect(recipes,entries))
def permission(~Light:Data,~properties:Light -> U32 -> Maybe<&2,L.Descriptor>,~enabled:Light -> C.Position -> Bool,
    light_context:Light,context:CW.Context,position:C.Position,state:U32,cap:C.Capability,expected:Nat,sequence:Nat,+maybuild:Bool,
    owner:CW.State,allowed:Bool) -> CW.State & Result<&2,&2,CW.Error,List<&2,S.Effect>>:
  match owner allowed:
    case owner False{}: (owner,Fail{CW.Player{P.PermissionDenied{}}})
    case CW.State{world,entries,CW.Cooking{tick,effects},keys} True{}:
      (CW.State{world,entries,CW.Cooking{tick,effects},keys},Fail{CW.Busy{}})
    case CW.State{world,entries,CW.Idle{},key <> rest} True{}:
      (CW.State{world,entries,CW.Idle{},key <> rest},Fail{CW.Loading{}})
    case CW.State{W.State{world,light,Some{cursor}},entries,CW.Idle{},Nil{}} True{}:
      (CW.State{W.State{world,light,Some{cursor}},entries,CW.Idle{},[]},Fail{CW.World{W.LoadingInProgress{}}})
    case CW.State{world,entries,CW.Idle{},Nil{}} True{}:
      with_context(~Light,~properties,~enabled,light_context,context,position,state,cap,expected,sequence,maybuild,world,entries)
# The server supplies its actual capability/observed ability. This delegates
# sequence/revision/world admission and the actual write to Player CoreEdit.
def player_edit(~Light:Data,~properties:Light -> U32 -> Maybe<&2,L.Descriptor>,~enabled:Light -> C.Position -> Bool,
    light_context:Light,context:CW.Context,owner:CW.State,+cap:C.Capability,position:C.Position,state:U32,expected:Nat,sequence:Nat,+maybuild:Bool) -> CW.State & Result<&2,&2,CW.Error,List<&2,S.Effect>>:
  permission(~Light,~properties,~enabled,light_context,context,position,state,cap,expected,sequence,maybuild,owner,
    maybuild && Maybe.is_some(&2,U32,P.player_peer(cap)))
