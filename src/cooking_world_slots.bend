import Base
import ./core.bend as C
import ./block_light.bend as L
import ./block_light_world.bend as W
import ./cooking_world.bend as CW
import ./cooking_world_store.bend as S
import ./cooking_world_bindings.bend as B
import ./cooking_world_items.bend as I
import ./cooking_world_tick.bend as T
import ./inventory.bend as Inv
import ./json.bend as J
import ./cooking_recipe.bend as K
import ./furnace_authority.bend as F
import ./furnace_authority_slots.bend as FS
import ./campfire_authority.bend as A
import ./campfire_authority_items.bend as AI
import ./player_core_edit.bend as P

type Command is Data:
  FurnaceSet{index:U32,value:AI.Input}
  FurnaceTake{index:U32}
  FurnaceTakeCount{index:U32,count:U32}
  CampfirePlace{held:AI.Input,infinite:Bool}
type Receipt is Data:
  Receipt{previous:Inv.Slot,remaining:AI.Input,index:U32,effects:List<&2,S.Effect>}
type Proposal is Data:
  Proposal{transition:F.Transition,previous:Inv.Slot,remaining:AI.Input,index:U32}
def remainder(value:Inv.Slot,+placed:U32) -> Inv.Slot:
  match value:
    case Inv.InvEmpty{}: Inv.InvEmpty{}
    case Inv.InvStack{+key,+count}: Inv.canonical_stack(key,U32.sub(count,placed),U32.is_eq(count,placed))
def set_receipt(+transition:F.Transition,previous:Inv.Slot,+value:Inv.Slot,patch:J.Value,+index:U32) -> Proposal:
  F.Transition{F.Snapshot{frame,slots},effects} = transition
  Proposal{transition,previous,AI.Input{remainder(value,Inv.slot_count(FS.slot_at(slots,index))),patch},index}
def proposed_set(+catalog:K.Catalog,+snapshot:F.Snapshot,+index:U32,+value:Inv.Slot,patch:J.Value,metadata:List<&2,Inv.ItemMetadata>) -> Result<&2,&2,String,Proposal>:
  F.Snapshot{frame,+slots} = snapshot
  do Result<&2,&2,String,Proposal>:
    +transition : F.Transition <- FS.put_snapshot(catalog,snapshot,index,value,metadata)
    return set_receipt(transition,FS.slot_at(slots,index),value,patch,index)
def set_admitted(+context:CW.Context,+snapshot:F.Snapshot,+index:U32,+value:Inv.Slot,patch:J.Value,result:Result<&2,&2,String,I.Admission>) -> Result<&2,&2,String,Proposal>:
  CW.Context{catalog,AI.Context{recipes,defaults,features},fuel,depth} = context
  F.Snapshot{frame,+slots} = snapshot
  match result:
    case Fail{message}: Fail{message}
    case Done{I.Admission{metadata,profiles}}:
      do Result<&2,&2,String,Proposal>:
        accepted : Bool <- FS.can_place(fuel,profiles,slots,index,value)
        AI.guarded(accepted,"cooking-world:furnace-slot-placement-denied")
        proposed_set(recipes,snapshot,index,value,patch,metadata)
def take_admitted(context:CW.Context,+snapshot:F.Snapshot,+index:U32,admission:I.Admission) -> Result<&2,&2,String,Proposal>:
  CW.Context{catalog,AI.Context{recipes,defaults,features},fuel,depth} = context
  F.Snapshot{frame,+slots} = snapshot
  I.Admission{metadata,profiles} = admission
  do Result<&2,&2,String,Proposal>:
    transition : F.Transition <- FS.put_snapshot(recipes,snapshot,index,Inv.InvEmpty{},metadata)
    return Proposal{transition,FS.slot_at(slots,index),AI.plain(),index}
def extracted(+value:Inv.Slot,+requested:U32) -> Inv.Slot:
  match value:
    case Inv.InvEmpty{}: Inv.InvEmpty{}
    case Inv.InvStack{key,+count}:
      Inv.canonical_stack(key,U32.min(count,requested),U32.is_zero(requested))
def take_count_admitted(context:CW.Context,+snapshot:F.Snapshot,+index:U32,+count:U32,admission:I.Admission) -> Result<&2,&2,String,Proposal>:
  CW.Context{catalog,AI.Context{recipes,defaults,features},fuel,depth} = context
  F.Snapshot{frame,+slots} = snapshot
  I.Admission{metadata,profiles} = admission
  +previous = extracted(FS.slot_at(slots,index),count)
  do Result<&2,&2,String,Proposal>:
    transition : F.Transition <- FS.put_snapshot(recipes,snapshot,index,
      remainder(FS.slot_at(slots,index),Inv.slot_count(previous)),metadata)
    return Proposal{transition,previous,AI.plain(),index}
def propose(+context:CW.Context,+snapshot:F.Snapshot,command:Command) -> Result<&2,&2,String,Proposal>:
  F.Snapshot{frame,K.FurnaceSlots{input,fuel,output}} = snapshot
  match command:
    case FurnaceSet{+index,AI.Input{+value,+patch}}:
      do Result<&2,&2,String,Proposal>:
        actual : Maybe<&2,Inv.ItemMetadata> <- AI.admit(CW.recipes(context),AI.Input{value,patch})
        set_admitted(context,snapshot,index,value,patch,I.slots([input,fuel,output,value],CW.recipes(context)))
    case FurnaceTake{+index}:
      do Result<&2,&2,String,Proposal>:
        admission : I.Admission <- I.furnace(CW.recipes(context),snapshot)
        take_admitted(context,snapshot,index,admission)
    case FurnaceTakeCount{+index,count}:
      do Result<&2,&2,String,Proposal>:
        admission : I.Admission <- I.furnace(CW.recipes(context),snapshot)
        take_count_admitted(context,snapshot,index,count,admission)
    case _: Fail{"cooking-world:command-requires-campfire"}
def furnace_committed(+position:C.Position,binding:B.Binding,+proposal:Proposal,result:F.State & Result<&2,&2,String,F.Effects>) -> S.Entry & Result<&2,&2,CW.Error,Receipt>:
  Proposal{transition,previous,remaining,index} = proposal
  (owner,status) = result
  match status:
    case Fail{message}: (S.Entry{position,binding,S.Furnace{owner}},Fail{CW.Authority{message}})
    case Done{effects}: (S.Entry{position,binding,S.Furnace{owner}},Done{Receipt{previous,remaining,index,T.furnace_effects(position,effects)}})
def furnace_proposed(position:C.Position,binding:B.Binding,owner:F.State,result:Result<&2,&2,String,Proposal>) -> S.Entry & Result<&2,&2,CW.Error,Receipt>:
  match result:
    case Fail{message}: (S.Entry{position,binding,S.Furnace{owner}},Fail{CW.Authority{message}})
    case Done{+proposal}:
      Proposal{transition,previous,remaining,index} = proposal
      furnace_committed(position,binding,proposal,F.commit(owner,Done{transition}))
def furnace_inspected(context:CW.Context,command:Command,position:C.Position,binding:B.Binding,result:F.State & Maybe<&2,F.Snapshot>) -> S.Entry & Result<&2,&2,CW.Error,Receipt>:
  (owner,value) = result
  match value:
    case None{}: (S.Entry{position,binding,S.Furnace{owner}},Fail{CW.Authority{"cooking-world:invalid-furnace-array-owner"}})
    case Some{snapshot}: furnace_proposed(position,binding,owner,propose(context,snapshot,command))
def campfire_placed(+position:C.Position,binding:B.Binding,result:A.State & A.Placement) -> S.Entry & Result<&2,&2,CW.Error,Receipt>:
  (owner,+placement) = result
  A.Placement{remaining,status} = placement
  match status:
    case Fail{message}: (S.Entry{position,binding,S.Campfire{owner}},Fail{CW.Authority{message}})
    case Done{index}:
      (S.Entry{position,binding,S.Campfire{owner}},Done{Receipt{Inv.InvEmpty{},remaining,index,T.campfire_effects(position,A.placement_effects(placement))}})
def campfire_command(context:CW.Context,position:C.Position,binding:B.Binding,owner:A.State,command:Command) -> S.Entry & Result<&2,&2,CW.Error,Receipt>:
  match command:
    case CampfirePlace{held,infinite}: campfire_placed(position,binding,A.place(CW.recipes(context),owner,held,infinite))
    case _: (S.Entry{position,binding,S.Campfire{owner}},Fail{CW.Authority{"cooking-world:command-requires-furnace"}})
def operate(context:CW.Context,entry:S.Entry,command:Command) -> S.Entry & Result<&2,&2,CW.Error,Receipt>:
  match entry:
    case S.Entry{position,binding,S.Furnace{owner}}: furnace_inspected(context,command,position,binding,F.inspect(owner))
    case S.Entry{position,binding,S.Campfire{owner}}: campfire_command(context,position,binding,owner,command)
def owned_cons(result:S.Entry & Result<&2,&2,CW.Error,Receipt>,rest:List<&1,S.Entry>) -> List<&1,S.Entry> & Result<&2,&2,CW.Error,Receipt>:
  (entry,status) = result
  (entry <> rest,status)
def skipped(head:S.Entry,result:List<&1,S.Entry> & Result<&2,&2,CW.Error,Receipt>) -> List<&1,S.Entry> & Result<&2,&2,CW.Error,Receipt>:
  (rest,status) = result
  (head <> rest,status)
def verified(context:CW.Context,position:C.Position,command:Command,head:S.Entry,rest:List<&1,S.Entry>,same:Bool) -> List<&1,S.Entry> & Result<&2,&2,CW.Error,Receipt>:
  match same:
    case False{}: (head <> rest,Fail{CW.EntityMismatch{position}})
    case True{}: owned_cons(operate(context,head,command),rest)
def verified_entry(context:CW.Context,position:C.Position,state:U32,command:Command,head:S.Entry,rest:List<&1,S.Entry>) -> List<&1,S.Entry> & Result<&2,&2,CW.Error,Receipt>:
  S.Entry{candidate,+binding,entity} = head
  B.Binding{id,block,family,lit,dark,bright} = binding
  verified(context,position,command,S.Entry{candidate,binding,entity},rest,U32.is_eq(state,id))
def chosen(+context:CW.Context,+position:C.Position,state:U32,command:Command,head:S.Entry,rest:List<&1,S.Entry>,hit:Bool,
    next:List<&1,S.Entry> -> List<&1,S.Entry> & Result<&2,&2,CW.Error,Receipt>) -> List<&1,S.Entry> & Result<&2,&2,CW.Error,Receipt>:
  match hit:
    case False{}: skipped(head,next(rest))
    case True{}: verified_entry(context,position,state,command,head,rest)
def find(budget:Nat,+context:CW.Context,+position:C.Position,+state:U32,+command:Command,entries:List<&1,S.Entry>) -> List<&1,S.Entry> & Result<&2,&2,CW.Error,Receipt>:
  match budget entries:
    case 0n entries: (entries,Fail{CW.EntityMismatch{position}})
    case _ Nil{}: ([],Fail{CW.EntityMismatch{position}})
    case 1n+remaining S.Entry{+candidate,binding,entity} <> rest:
      chosen(context,position,state,command,S.Entry{candidate,binding,entity},rest,B.equal_position(position,candidate),
        rest => find(remaining,context,position,state,command,rest))
def found(world:W.State,result:List<&1,S.Entry> & Result<&2,&2,CW.Error,Receipt>) -> CW.State & Result<&2,&2,CW.Error,Receipt>:
  (entries,status) = result
  (CW.State{world,entries,CW.Idle{},[]},status)
def sized(context:CW.Context,position:C.Position,state:U32,command:Command,world:W.State,result:List<&1,S.Entry> & Nat) -> CW.State & Result<&2,&2,CW.Error,Receipt>:
  (entries,count) = result
  found(world,find(1n+count,context,position,state,command,entries))
def read(context:CW.Context,position:C.Position,command:Command,light:L.State,loading:Maybe<&2,W.Cursor>,entries:List<&1,S.Entry>,result:C.World & Result<&2,&2,C.Error,U32>) -> CW.State & Result<&2,&2,CW.Error,Receipt>:
  (world,status) = result
  match status:
    case Fail{error}: (CW.State{W.State{world,light,loading},entries,CW.Idle{},[]},Fail{CW.World{W.CoreFailure{error}}})
    case Done{state}: sized(context,position,state,command,W.State{world,light,loading},S.size(entries))
def admitted(context:CW.Context,owner:CW.State,+position:C.Position,command:Command,allowed:Bool) -> CW.State & Result<&2,&2,CW.Error,Receipt>:
  match owner allowed:
    case owner False{}: (owner,Fail{CW.Authority{"cooking-world:slot-access-denied"}})
    case CW.State{world,entries,CW.Cooking{tick,effects},keys} True{}: (CW.State{world,entries,CW.Cooking{tick,effects},keys},Fail{CW.Busy{}})
    case CW.State{world,entries,CW.Idle{},key <> rest} True{}: (CW.State{world,entries,CW.Idle{},key <> rest},Fail{CW.Loading{}})
    case CW.State{W.State{world,light,Some{cursor}},entries,CW.Idle{},Nil{}} True{}: (CW.State{W.State{world,light,Some{cursor}},entries,CW.Idle{},[]},Fail{CW.World{W.LoadingInProgress{}}})
    case CW.State{W.State{world,light,loading},entries,CW.Idle{},Nil{}} True{}: read(context,position,command,light,loading,entries,C.read_block(world,position))
# This server-side seam joins actual block residency/state with the actual
# slot authorities. Menu identity, distance, hopper-face admission and the
# caller's player inventory/cursor owner remain the actor's transfer boundary.
def dispatch(context:CW.Context,owner:CW.State,position:C.Position,command:Command,+cap:C.Capability,may_interact:Bool) -> CW.State & Result<&2,&2,CW.Error,Receipt>:
  admitted(context,owner,position,command,may_interact && (C.developer(cap) || Maybe.is_some(&2,U32,P.player_peer(cap))))
