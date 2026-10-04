import Base
import ./core.bend as C
import ./block_light.bend as L
import ./block_light_world.bend as W
import ./cooking_world.bend as CW
import ./cooking_world_store.bend as S
import ./cooking_world_bindings.bend as B
import ./campfire_authority_items.bend as CI
import ./cooking_block_entity_codec.bend as CB
import ./cooking_block_entity_codec_items.bend as Items
import ./nbt.bend as N
import ./furnace_authority.bend as FA
import ./campfire_authority.bend as CA

# Physical cooking bodies join the same real world owner. The actor retains
# Details' base/extras sidecar and owns durable world framing and writes.
def codec_context(context:CI.Context) -> Items.Context:
  CI.Context{recipes,defaults,features} = context
  Items.Context{recipes,defaults}
def codec(context:CW.Context) -> Items.Context:
  codec_context(CW.recipes(context))
def furnace_loaded(position:C.Position,binding:B.Binding,
    result:FA.State & Result<&2,&2,String,CB.Details>) -> S.Entry & Result<&2,&2,CW.Error,CB.Details>:
  (owner,status) = result
  match status:
    case Fail{message}: (S.Entry{position,binding,S.Furnace{owner}},Fail{CW.Authority{message}})
    case Done{details}: (S.Entry{position,binding,S.Furnace{owner}},Done{details})
def campfire_loaded(position:C.Position,binding:B.Binding,
    result:CA.State & Result<&2,&2,String,CB.Details>) -> S.Entry & Result<&2,&2,CW.Error,CB.Details>:
  (owner,status) = result
  match status:
    case Fail{message}: (S.Entry{position,binding,S.Campfire{owner}},Fail{CW.Authority{message}})
    case Done{details}: (S.Entry{position,binding,S.Campfire{owner}},Done{details})
def load_entry(context:CW.Context,limits:N.Limits,bytes:List<&2,U32>,entry:S.Entry) -> S.Entry & Result<&2,&2,CW.Error,CB.Details>:
  match entry:
    case S.Entry{position,binding,S.Furnace{owner}}: furnace_loaded(position,binding,CB.load_furnace(owner,codec(context),limits,bytes))
    case S.Entry{position,binding,S.Campfire{owner}}: campfire_loaded(position,binding,CB.load_campfire(owner,CW.recipes(context),limits,bytes))
def furnace_saved(position:C.Position,binding:B.Binding,
    result:FA.State & Result<&2,&2,String,List<&2,U32>>) -> S.Entry & Result<&2,&2,CW.Error,List<&2,U32>>:
  (owner,status) = result
  match status:
    case Fail{message}: (S.Entry{position,binding,S.Furnace{owner}},Fail{CW.Authority{message}})
    case Done{bytes}: (S.Entry{position,binding,S.Furnace{owner}},Done{bytes})
def campfire_saved(position:C.Position,binding:B.Binding,
    result:CA.State & Result<&2,&2,String,List<&2,U32>>) -> S.Entry & Result<&2,&2,CW.Error,List<&2,U32>>:
  (owner,status) = result
  match status:
    case Fail{message}: (S.Entry{position,binding,S.Campfire{owner}},Fail{CW.Authority{message}})
    case Done{bytes}: (S.Entry{position,binding,S.Campfire{owner}},Done{bytes})
def save_entry(context:CW.Context,limits:N.Limits,entry:S.Entry) -> S.Entry & Result<&2,&2,CW.Error,List<&2,U32>>:
  match entry:
    case S.Entry{position,binding,S.Furnace{owner}}: furnace_saved(position,binding,CB.save_furnace(owner,codec(context),limits))
    case S.Entry{position,binding,S.Campfire{owner}}: campfire_saved(position,binding,CB.save_campfire(owner,codec(context),limits))
def owned(~R:Data,result:S.Entry & Result<&2,&2,CW.Error,R>,rest:List<&1,S.Entry>) -> List<&1,S.Entry> & Result<&2,&2,CW.Error,R>:
  (head,status) = result
  (head <> rest,status)
def skipped(~R:Data,head:S.Entry,result:List<&1,S.Entry> & Result<&2,&2,CW.Error,R>) -> List<&1,S.Entry> & Result<&2,&2,CW.Error,R>:
  (rest,status) = result
  (head <> rest,status)
def verified(~R:Data,same:Bool,position:C.Position,head:S.Entry,rest:List<&1,S.Entry>,operation:S.Entry -> S.Entry & Result<&2,&2,CW.Error,R>) -> List<&1,S.Entry> & Result<&2,&2,CW.Error,R>:
  match same:
    case False{}: (head <> rest,Fail{CW.EntityMismatch{position}})
    case True{}: owned(~R,operation(head),rest)
def verified_entry(~R:Data,position:C.Position,state:U32,head:S.Entry,rest:List<&1,S.Entry>,operation:S.Entry -> S.Entry & Result<&2,&2,CW.Error,R>) -> List<&1,S.Entry> & Result<&2,&2,CW.Error,R>:
  S.Entry{candidate,+binding,entity} = head
  B.Binding{id,block,family,lit,dark,bright} = binding
  verified(~R,U32.is_eq(state,id),position,S.Entry{candidate,binding,entity},rest,operation)
def chosen(~R:Data,hit:Bool,+position:C.Position,state:U32,head:S.Entry,rest:List<&1,S.Entry>,operation:S.Entry -> S.Entry & Result<&2,&2,CW.Error,R>,
    next:List<&1,S.Entry> -> (S.Entry -> S.Entry & Result<&2,&2,CW.Error,R>) -> List<&1,S.Entry> & Result<&2,&2,CW.Error,R>) -> List<&1,S.Entry> & Result<&2,&2,CW.Error,R>:
  match hit:
    case False{}: skipped(~R,head,next(rest)(operation))
    case True{}: verified_entry(~R,position,state,head,rest,operation)
def find(~R:Data,budget:Nat,+position:C.Position,+state:U32,operation:S.Entry -> S.Entry & Result<&2,&2,CW.Error,R>,entries:List<&1,S.Entry>) -> List<&1,S.Entry> & Result<&2,&2,CW.Error,R>:
  match budget entries:
    case 0n entries: (entries,Fail{CW.EntityMismatch{position}})
    case _ Nil{}: ([],Fail{CW.EntityMismatch{position}})
    case 1n+remaining S.Entry{+candidate,binding,entity} <> rest:
      chosen(~R,B.equal_position(position,candidate),position,state,S.Entry{candidate,binding,entity},rest,operation,
        rest => operation => find(~R,remaining,position,state,operation,rest))
def found(~R:Data,world:W.State,result:List<&1,S.Entry> & Result<&2,&2,CW.Error,R>) -> CW.State & Result<&2,&2,CW.Error,R>:
  (entries,status) = result
  (CW.State{world,entries,CW.Idle{},[]},status)
def sized(~R:Data,position:C.Position,state:U32,operation:S.Entry -> S.Entry & Result<&2,&2,CW.Error,R>,world:W.State,result:List<&1,S.Entry> & Nat) -> CW.State & Result<&2,&2,CW.Error,R>:
  (entries,count) = result
  found(~R,world,find(~R,1n+count,position,state,operation,entries))
def read(~R:Data,position:C.Position,operation:S.Entry -> S.Entry & Result<&2,&2,CW.Error,R>,light:L.State,loading:Maybe<&2,W.Cursor>,entries:List<&1,S.Entry>,result:C.World & Result<&2,&2,C.Error,U32>) -> CW.State & Result<&2,&2,CW.Error,R>:
  (world,status) = result
  match status:
    case Fail{error}: (CW.State{W.State{world,light,loading},entries,CW.Idle{},[]},Fail{CW.World{W.CoreFailure{error}}})
    case Done{state}: sized(~R,position,state,operation,W.State{world,light,loading},S.size(entries))
def access(~R:Data,allowed:Bool,owner:CW.State,+position:C.Position,operation:S.Entry -> S.Entry & Result<&2,&2,CW.Error,R>) -> CW.State & Result<&2,&2,CW.Error,R>:
  match allowed owner:
    case False{} owner: (owner,Fail{CW.Authority{"cooking-world:persistence-access-denied"}})
    case True{} CW.State{world,entries,CW.Cooking{tick,effects},keys}: (CW.State{world,entries,CW.Cooking{tick,effects},keys},Fail{CW.Busy{}})
    case True{} CW.State{world,entries,CW.Idle{},key <> rest}: (CW.State{world,entries,CW.Idle{},key <> rest},Fail{CW.Loading{}})
    case True{} CW.State{W.State{world,light,Some{cursor}},entries,CW.Idle{},Nil{}}: (CW.State{W.State{world,light,Some{cursor}},entries,CW.Idle{},[]},Fail{CW.World{W.LoadingInProgress{}}})
    case True{} CW.State{W.State{world,light,loading},entries,CW.Idle{},Nil{}}: read(~R,position,operation,light,loading,entries,C.read_block(world,position))
# Only the server's explicit Developer capability can materialize physical
# records. Ordinary slot interaction cannot import a body or overwrite timers.
def load(+context:CW.Context,owner:CW.State,position:C.Position,+limits:N.Limits,+bytes:List<&2,U32>,cap:C.Capability) -> CW.State & Result<&2,&2,CW.Error,CB.Details>:
  access(~CB.Details,C.developer(cap),owner,position,entry => load_entry(context,limits,bytes,entry))
def save(+context:CW.Context,owner:CW.State,position:C.Position,+limits:N.Limits,cap:C.Capability) -> CW.State & Result<&2,&2,CW.Error,List<&2,U32>>:
  access(~List<&2,U32>,C.developer(cap),owner,position,entry => save_entry(context,limits,entry))
