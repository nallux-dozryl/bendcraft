import Base
import ./player_block_inside_stuck.bend as Inside
import ./local_player_runtime.bend as R
import ./local_phase_runtime.bend as X
import ./local_move_history.bend as MH
import ./player_fall_history.bend as H
import ./player_runtime.bend as Plain
import ./player_controls.bend as CT
import ./mouse_input.bend as MI
import ./local_player_record.bend as PR
import ./local_player_storage.bend as PS
import ./client_controls.bend as CC
import ./player_input.bend as PI
import ./client_world.bend as W
import ./client_render.bend as CR
import ./extended_persistence.bend as E
import ./persistence.bend as P
import ./world_lock.bend as WL
import ./locomotion.bend as T
import ./game.bend as G
import ./core.bend as C
import ./registry.bend as B
import ./live.bend as L
import ./json.bend as J
import ./player_inventory.bend as I
import ./player_inventory_codec.bend as IC
import ./inventory.bend as Inv
import ./player_block_interaction.bend as BI
import ./world_generation_settings.bend as WG
import ./player_item_definitions.bend as D

# The LocalPlayer runtime owns the only Engine/body. The leased save shell
# transfers that Engine and the complete supported local record through the
# existing atomic extension transaction. Renderer/API reads never tick it.
type Shell is Type:
  Shell{identity:String,path:String,highwater:U32,limits:P.Limits,lease:WL.Lease,
    maximum:U32,catalog:List<&2,E.Operation>,inventory:I.State,fresh:Bool,generation:WG.Settings}
type State is Type:
  State{player:X.State,shell:Shell}

# Startup provenance is transient. An empty loaded Core is still a loaded
# world; only the codec's fresh initializer authorizes terrain initialization.
def fresh(state:State) -> State & Bool:
  State{player,Shell{identity,path,highwater,limits,lease,maximum,catalog,inventory,+initial,generation}} = state
  (State{player,Shell{identity,path,highwater,limits,lease,maximum,catalog,inventory,initial,generation}},initial)

def mark_initialized(state:State) -> State:
  State{player,Shell{identity,path,highwater,limits,lease,maximum,catalog,inventory,initial,generation}} = state
  State{player,Shell{identity,path,highwater,limits,lease,maximum,catalog,inventory,False{},generation}}

def generation(state:State) -> State & WG.Settings:
  State{player,Shell{identity,path,highwater,limits,lease,maximum,catalog,inventory,fresh,+settings}} = state
  (State{player,Shell{identity,path,highwater,limits,lease,maximum,catalog,inventory,fresh,settings}},settings)

def generation_assign(state:State,settings:WG.Settings) -> State:
  State{player,Shell{identity,path,highwater,limits,lease,maximum,catalog,inventory,fresh,old}} = state
  State{player,Shell{identity,path,highwater,limits,lease,maximum,catalog,inventory,fresh,settings}}

def generation_validated(state:State,result:Result<&2,&2,String,WG.Settings>) -> State & Result<&2,&2,String,Unit>:
  match result:
    case Fail{message}: (state,Fail{message})
    case Done{settings}: (generation_assign(state,settings),Done{Unit{}})

def set_generation(state:State,settings:WG.Settings) -> State & Result<&2,&2,String,Unit>:
  generation_validated(state,WG.validate(settings))

def to_bundle_split(shell:Shell,result:G.Engine & PR.Record & R.Transient) -> E.State<IC.Saved> & R.Transient:
  Shell{identity,path,highwater,limits,lease,maximum,catalog,inventory,fresh,generation} = shell
  (engine,record,transient) = result
  (E.State{P.State{engine,identity,path,highwater,limits,lease},IC.Saved{record,inventory,fresh,generation},maximum,catalog},transient)

def to_bundle(state:State) -> E.State<IC.Saved> & R.Transient:
  State{player,shell} = state
  to_bundle_split(shell,R.detach(player))

def from_bundle(stored:E.State<IC.Saved>,transient:R.Transient) -> State:
  E.State{P.State{engine,identity,path,highwater,limits,lease},IC.Saved{record,inventory,fresh,generation},maximum,catalog} = stored
  State{R.attach(engine,record,transient),Shell{identity,path,highwater,limits,lease,maximum,catalog,inventory,fresh,generation}}

def queried(-A:Type,shell:Shell,result:X.State & A) -> State & A:
  (player,value) = result
  (State{player,shell},value)

def query(-A:Type,state:State,operation:X.State -> X.State & A) -> State & A:
  State{player,shell} = state
  queried(A,shell,operation(player))

def snapshot(state:State,width:U32,height:U32) -> State & Result<&2,&2,String,CR.Snapshot>:
  query(Result<&2,&2,String,CR.Snapshot>,state,p => R.snapshot(p,width,height))

def input(state:State,bindings:PI.Bindings,packet:CC.Packet) -> State & Result<&2,&2,String,Unit>:
  query(Result<&2,&2,String,Unit>,state,p => R.input(p,bindings,packet))

def release(state:State) -> State:
  State{player,shell} = state
  State{R.release(player),shell}

def realtime_step(driver:R.Driver,state:State) -> State:
  State{player,shell} = state
  State{R.realtime_step(driver,player),shell}

def advance(~driver:R.Driver,state:State,ticks:U32) -> State:
  State{player,shell} = state
  State{R.advance(~driver,U32.to_nat(ticks),player),shell}

def inventory_queried(-A:Type,player:X.State,identity:String,path:String,highwater:U32,limits:P.Limits,lease:WL.Lease,maximum:U32,catalog:List<&2,E.Operation>,fresh:Bool,generation:WG.Settings,result:I.State & A) -> State & A:
  (inventory,value) = result
  (State{player,Shell{identity,path,highwater,limits,lease,maximum,catalog,inventory,fresh,generation}},value)

def inventory_query(-A:Type,state:State,operation:I.State -> I.State & A) -> State & A:
  State{player,Shell{identity,path,highwater,limits,lease,maximum,catalog,inventory,fresh,generation}} = state
  inventory_queried(A,player,identity,path,highwater,limits,lease,maximum,catalog,fresh,generation,operation(inventory))

def inventory_inspect(state:State) -> State & I.Snapshot:
  inventory_query(I.Snapshot,state,I.inspect)

def inventory_selected(state:State) -> State & Inv.Slot:
  inventory_query(Inv.Slot,state,I.selected)

def inventory_select(state:State,index:U32) -> State & Result<&2,&2,String,Unit>:
  inventory_query(Result<&2,&2,String,Unit>,state,i => I.select(i,index))

def inventory_transfer(state:State,source:U32,destination:U32,count:U32,mode:Inv.TransferMode) -> State & Inv.TransferStatus:
  inventory_query(Inv.TransferStatus,state,i => I.transfer(i,source,destination,count,mode))

def inventory_acquire(state:State,index:U32,key:Inv.ItemKey,count:U32) -> State & Result<&2,&2,String,Unit>:
  inventory_query(Result<&2,&2,String,Unit>,state,i => I.acquire(i,index,key,count))

def inventory_abilities(state:State) -> State & I.Abilities:
  inventory_query(I.Abilities,state,I.abilities)

def inventory_status(state:State) -> State & I.Status:
  inventory_query(I.Status,state,I.status)

def inventory_status_updated(result:State & Unit) -> State:
  (state,unit) = result
  state

def set_inventory_status(state:State,status:I.Status) -> State:
  inventory_status_updated(inventory_query(Unit,state,i => (I.set_status(i,status),Unit{})))

def status_runtime_updated(shell:Shell,result:X.State & I.Status) -> State:
  Shell{identity,path,highwater,limits,lease,maximum,catalog,inventory,fresh,generation} = shell
  (player,status) = result
  State{player,Shell{identity,path,highwater,limits,lease,maximum,catalog,I.set_status(inventory,status),fresh,generation}}

def status_inventory_read(operation:I.Status -> X.State -> X.State & I.Status,player:X.State,identity:String,path:String,highwater:U32,limits:P.Limits,lease:WL.Lease,maximum:U32,catalog:List<&2,E.Operation>,fresh:Bool,generation:WG.Settings,result:I.State & I.Status) -> State:
  (inventory,status) = result
  status_runtime_updated(Shell{identity,path,highwater,limits,lease,maximum,catalog,inventory,fresh,generation},operation(status,player))

def run_with_status(state:State,operation:I.Status -> X.State -> X.State & I.Status) -> State:
  State{player,Shell{identity,path,highwater,limits,lease,maximum,catalog,inventory,fresh,generation}} = state
  status_inventory_read(operation,player,identity,path,highwater,limits,lease,maximum,catalog,fresh,generation,I.status(inventory))

def inventory_definitions(state:State) -> State & D.Catalog:
  inventory_query(D.Catalog,state,I.definitions)

def menu_inspect(state:State) -> State & I.MenuSnapshot:
  inventory_query(I.MenuSnapshot,state,I.menu_inspect)

def menu_open(state:State) -> State & Result<&2,&2,String,Unit>:
  inventory_query(Result<&2,&2,String,Unit>,state,I.menu_open)

def menu_close(state:State) -> State & Result<&2,&2,String,Unit>:
  inventory_query(Result<&2,&2,String,Unit>,state,I.menu_close)

def menu_click(state:State,index:U32,click:I.Click) -> State & Result<&2,&2,String,Unit>:
  inventory_query(Result<&2,&2,String,Unit>,state,i => I.menu_click(i,index,click))

def catalog(unit:Unit) -> List<&2,E.Operation>:
  [E.Operation{"player.inspect",L.Public{},[],"Observe the complete supported LocalPlayer record as exact typed NBT bytes; this query does not advance simulation."}]

def byte_values(bytes:List<&2,U32>) -> List<&2,J.Value>:
  match bytes:
    case Nil{}: []
    case byte <> rest: L.uint(byte) <> byte_values(rest)

def inspected(engine:G.Engine,record:PR.Record,result:Result<&2,&2,PR.Error,List<&2,U32>>) -> G.Engine & PR.Record & Result<&2,&2,L.Fault,J.Value>:
  match result:
    case Fail{error}: (engine,record,Fail{L.bad("InvalidPlayerState",PR.error_text(error))})
    case Done{bytes}: (engine,record,Done{L.obj([J.JMember{"format",L.text("bendex:local-player-record")},J.JMember{"nbt_bytes",J.JArray{byte_values(bytes)}}])})

def operation_dispatch(engine:G.Engine,+record:PR.Record,session:L.Session,envelope:L.Envelope) -> G.Engine & PR.Record & Result<&2,&2,L.Fault,J.Value>:
  L.Envelope{id,op,args,at} = envelope
  match op:
    case "player.inspect": inspected(engine,record,PR.encode(record))
    case _: (engine,record,Fail{L.bad("UnknownOperation","unknown player operation")})

def operation_dispatch_plain(engine:G.Engine,record:PR.Record,session:L.Session,envelope:L.Envelope) -> G.Engine & PR.Record & Result<&2,&2,L.Fault,J.Value>:
  operation_dispatch(engine,record,session,envelope)

def operations() -> E.Operations<PR.Record>:
  E.Operations{catalog,operation_dispatch_plain}

def inventory_catalog(unit:Unit) -> List<&2,E.Operation>:
  List.append(&2,E.Operation,catalog(unit),[
    E.Operation{"inventory.inspect",L.Public{},[],"Read the owned 36-slot main inventory, selected hotbar and player build abilities without advancing simulation."},
    E.Operation{"inventory.selected",L.Public{},[],"Read the selected hotbar item without advancing simulation."},
    E.Operation{"inventory.select",L.DeveloperOnly{},[L.Field{"slot",L.Unsigned{0,8},True{}}],"Select one of the nine hotbar slots."},
    E.Operation{"inventory.transfer",L.DeveloperOnly{},[L.Field{"source",L.Unsigned{0,35},True{}},L.Field{"destination",L.Unsigned{0,35},True{}},L.Field{"count",L.Unsigned{0,4294967295},True{}},L.Field{"mode",L.Text{["transfer","split","merge"]},True{}}],"Transfer a clamped count between two main-inventory slots; split requires an empty destination and merge requires a stack."},
    E.Operation{"inventory.acquire",L.DeveloperOnly{},[L.Field{"slot",L.Unsigned{0,35},True{}},L.Field{"item",L.Text{[]},True{}},L.Field{"count",L.Unsigned{0,99},True{}}],"Creative acquisition replaces one main slot with an enabled pinned default item; its observed stack limit and player instabuild ability are required."}])

def inventory_slot_value(slot:Inv.Slot) -> J.Value:
  match slot:
    case Inv.InvEmpty{}: J.JNull{}
    case Inv.InvStack{Inv.ItemKey{id,components},count}:
      L.obj([J.JMember{"id",L.text(id)},J.JMember{"components",L.text(components)},J.JMember{"count",L.uint(count)}])

def inventory_slot_values(slots:List<&2,Inv.Slot>) -> List<&2,J.Value>:
  match slots:
    case Nil{}: []
    case slot <> rest: inventory_slot_value(slot) <> inventory_slot_values(rest)

def inventory_abilities_value(profile:I.Abilities) -> J.Value:
  I.Abilities{instabuild,maybuild} = profile
  L.obj([J.JMember{"instabuild",L.boolean(instabuild)},J.JMember{"maybuild",L.boolean(maybuild)}])

def inventory_snapshot_value(snapshot:I.Snapshot) -> J.Value:
  I.Snapshot{selected,slots,abilities} = snapshot
  L.obj([J.JMember{"selected",L.uint(selected)},J.JMember{"slots",J.JArray{inventory_slot_values(slots)}},J.JMember{"abilities",inventory_abilities_value(abilities)}])

def inventory_answer(engine:G.Engine,record:PR.Record,fresh:Bool,generation:WG.Settings,result:I.State & Result<&2,&2,L.Fault,J.Value>) -> G.Engine & IC.Saved & Result<&2,&2,L.Fault,J.Value>:
  (inventory,answer) = result
  (engine,IC.Saved{record,inventory,fresh,generation},answer)

def inventory_inspected(result:I.State & I.Snapshot) -> I.State & Result<&2,&2,L.Fault,J.Value>:
  (inventory,snapshot) = result
  (inventory,Done{inventory_snapshot_value(snapshot)})

def inventory_selected_value(index:U32,result:I.State & Inv.Slot) -> I.State & Result<&2,&2,L.Fault,J.Value>:
  (inventory,slot) = result
  (inventory,Done{L.obj([J.JMember{"index",L.uint(index)},J.JMember{"slot",inventory_slot_value(slot)}])})

def inventory_selected_index(result:I.State & U32) -> I.State & Result<&2,&2,L.Fault,J.Value>:
  (inventory,index) = result
  inventory_selected_value(index,I.selected(inventory))

def inventory_selected_inspected(inventory:I.State) -> I.State & Result<&2,&2,L.Fault,J.Value>:
  inventory_selected_index(I.selection(inventory))

def inventory_selection_value(index:U32,result:I.State & Result<&2,&2,String,Unit>) -> I.State & Result<&2,&2,L.Fault,J.Value>:
  (inventory,status) = result
  match status:
    case Fail{message}: (inventory,Fail{L.bad("InvalidArguments",message)})
    case Done{unit}: (inventory,Done{L.obj([J.JMember{"selected",L.uint(index)}])})

def inventory_select_args(inventory:I.State,result:Result<&2,&2,L.Fault,U32>) -> I.State & Result<&2,&2,L.Fault,J.Value>:
  match result:
    case Fail{fault}: (inventory,Fail{fault})
    case Done{+index}: inventory_selection_value(index,I.select(inventory,index))

def inventory_transfer_value(result:I.State & Inv.TransferStatus) -> I.State & Result<&2,&2,L.Fault,J.Value>:
  (inventory,status) = result
  match status:
    case Inv.InvRejected{reason}: (inventory,Fail{L.bad("InventoryTransferRejected",Inv.error_name(reason))})
    case Inv.InvMoved{count}: (inventory,Done{L.obj([J.JMember{"moved",L.uint(count)}])})

type InventoryTransfer is Data:
  InventoryTransfer{source:U32,destination:U32,count:U32,mode:Inv.TransferMode}

def inventory_transfer_mode(mode:String) -> Result<&2,&2,L.Fault,Inv.TransferMode>:
  match mode:
    case "transfer": Done{Inv.TransferAny{}}
    case "split": Done{Inv.TransferSplit{}}
    case "merge": Done{Inv.TransferMerge{}}
    case _: Fail{L.invalid("mode")}

def inventory_transfer_arguments(+args:J.Value) -> Result<&2,&2,L.Fault,InventoryTransfer>:
  do Result<&2,&2,L.Fault,InventoryTransfer>:
    source : U32 <- L.get_number(args,"source",False{})
    destination : U32 <- L.get_number(args,"destination",False{})
    count : U32 <- L.get_number(args,"count",False{})
    mode : String <- L.get_string(args,"mode")
    parsed : Inv.TransferMode <- inventory_transfer_mode(mode)
    return InventoryTransfer{source,destination,count,parsed}

def inventory_transfer_args(inventory:I.State,result:Result<&2,&2,L.Fault,InventoryTransfer>) -> I.State & Result<&2,&2,L.Fault,J.Value>:
  match result:
    case Fail{fault}: (inventory,Fail{fault})
    case Done{InventoryTransfer{source,destination,count,mode}}:
      inventory_transfer_value(I.transfer(inventory,source,destination,count,mode))

type InventoryAcquire is Data:
  InventoryAcquire{slot:U32,item:String,count:U32}

def inventory_acquire_arguments(+args:J.Value) -> Result<&2,&2,L.Fault,InventoryAcquire>:
  do Result<&2,&2,L.Fault,InventoryAcquire>:
    slot : U32 <- L.get_number(args,"slot",False{})
    item : String <- L.get_string(args,"item")
    count : U32 <- L.get_number(args,"count",False{})
    return InventoryAcquire{slot,item,count}

def inventory_acquisition_value(result:I.State & Result<&2,&2,String,Unit>) -> I.State & Result<&2,&2,L.Fault,J.Value>:
  (inventory,status) = result
  match status:
    case Fail{message}: (inventory,Fail{L.bad("InventoryAcquisitionRejected",message)})
    case Done{unit}: (inventory,Done{L.obj([J.JMember{"acquired",L.boolean(True{})}])})

def inventory_acquire_args(inventory:I.State,result:Result<&2,&2,L.Fault,InventoryAcquire>) -> I.State & Result<&2,&2,L.Fault,J.Value>:
  match result:
    case Fail{fault}: (inventory,Fail{fault})
    case Done{InventoryAcquire{slot,item,count}}:
      inventory_acquisition_value(I.acquire(inventory,slot,Inv.ItemKey{item,""},count))

def inventory_record_inspected(inventory:I.State,fresh:Bool,generation:WG.Settings,result:G.Engine & PR.Record & Result<&2,&2,L.Fault,J.Value>) -> G.Engine & IC.Saved & Result<&2,&2,L.Fault,J.Value>:
  (engine,record,answer) = result
  (engine,IC.Saved{record,inventory,fresh,generation},answer)

def inventory_operation_dispatch(engine:G.Engine,saved:IC.Saved,session:L.Session,envelope:L.Envelope) -> G.Engine & IC.Saved & Result<&2,&2,L.Fault,J.Value>:
  IC.Saved{record,inventory,fresh,generation} = saved
  L.Envelope{id,+op,args,at} = envelope
  match op:
    case "player.inspect": inventory_record_inspected(inventory,fresh,generation,operation_dispatch(engine,record,session,L.Envelope{id,op,args,at}))
    case "inventory.inspect": inventory_answer(engine,record,fresh,generation,inventory_inspected(I.inspect(inventory)))
    case "inventory.selected": inventory_answer(engine,record,fresh,generation,inventory_selected_inspected(inventory))
    case "inventory.select": inventory_answer(engine,record,fresh,generation,inventory_select_args(inventory,L.get_number(args,"slot",False{})))
    case "inventory.transfer": inventory_answer(engine,record,fresh,generation,inventory_transfer_args(inventory,inventory_transfer_arguments(args)))
    case "inventory.acquire": inventory_answer(engine,record,fresh,generation,inventory_acquire_args(inventory,inventory_acquire_arguments(args)))
    case _: (engine,IC.Saved{record,inventory,fresh,generation},Fail{L.bad("UnknownOperation","unknown player inventory operation")})

def inventory_operations() -> E.Operations<IC.Saved>:
  E.Operations{inventory_catalog,inventory_operation_dispatch}

def dispatched(transient:R.Transient,result:E.State<IC.Saved> & L.Session & J.Value) -> State & L.Session & J.Value:
  (stored,session,value) = result
  (from_bundle(stored,transient),session,value)

def delegate_bundle(session:L.Session,token:String,request:J.Value,result:E.State<IC.Saved> & R.Transient) -> IO(State & L.Session & J.Value):
  (stored,transient) = result
  do IO<State & L.Session & J.Value>:
    result : E.State<IC.Saved> & L.Session & J.Value <- E.dispatch(~IC.Saved,~IC.codec(),~inventory_operations(),stored,session,token,request)
    return dispatched(transient,result)

def delegate(state:State,session:L.Session,token:String,request:J.Value) -> IO(State & L.Session & J.Value):
  delegate_bundle(session,token,request,to_bundle(state))

def response(state:State,session:L.Session,value:J.Value) -> State & L.Session & J.Value:
  (state,session,value)

def success(state:State,session:L.Session,id:String,value:J.Value) -> State & L.Session & J.Value:
  response(state,session,L.obj([J.JMember{"id",L.text(id)},J.JMember{"ok",L.boolean(True{})},J.JMember{"result",value}]))

def failure(state:State,session:L.Session,id:String,fault:L.Fault) -> State & L.Session & J.Value:
  response(state,session,L.obj([J.JMember{"id",L.text(id)},J.JMember{"ok",L.boolean(False{})},J.JMember{"error",L.fault_value(fault)}]))

def observed(state:State,+peer:U32) -> State:
  State{player,Shell{identity,path,+highwater,limits,lease,maximum,catalog,inventory,fresh,generation}} = state
  State{player,Shell{identity,path,U32.max(highwater,peer),limits,lease,maximum,catalog,inventory,fresh,generation}}

def reserved_local_peer(state:State,result:Result<&2,&2,String,U32>) -> State & Result<&2,&2,String,C.Capability>:
  match result:
    case Fail{message}: (state,Fail{message})
    case Done{4294967295}: (state,Fail{"peer ID range cannot reserve a local player and a public peer"})
    case Done{+peer}: (observed(state,peer),Done{C.Player{peer}})

# The renderer's Player identity belongs to the durable peer allocator. Reserve
# it before opening public listeners; no peer zero or fabricated identity is used.
def reserve_local_player(state:State) -> State & Result<&2,&2,String,C.Capability>:
  State{player,Shell{identity,path,+highwater,limits,lease,maximum,catalog,inventory,fresh,generation}} = state
  reserved_local_peer(State{player,Shell{identity,path,highwater,limits,lease,maximum,catalog,inventory,fresh,generation}},P.next_peer(highwater))

def block_action_executed(shell:Shell,record:PR.Record,palette:Maybe<&2,W.Palette>,region:W.Bounds,cache:Maybe<&2,W.SnapshotCache>,buttons:PI.Buttons,mouse:MI.State,options:MI.Options,receiver:Inside.Receiver,error:Maybe<&2,String>,state_tail:List<&1,X.State>,motion_tail:List<&1,MH.State>,metadata_tail:List<&2,X.Metadata>,result:G.Engine & T.Tables & BI.Outcome) -> State & BI.Outcome:
  (engine,tables,outcome) = result
  (State{R.attach(engine,record,R.Transient{tables,palette,region,cache,buttons,mouse,options, receiver, error,state_tail,motion_tail,metadata_tail}),shell},outcome)

def block_action_detached(shell:Shell,abilities:I.Abilities,held:Inv.Slot,cap:C.Capability,sequence:Nat,button:U32,result:G.Engine & PR.Record & R.Transient) -> State & BI.Outcome:
  (engine,+record,R.Transient{tables,palette,region,cache,buttons,mouse,options, receiver, error,state_tail,motion_tail,metadata_tail}) = result
  block_action_executed(shell,record,palette,region,cache,buttons,mouse,options,receiver,error,state_tail,motion_tail,metadata_tail,BI.execute(engine,record,tables,abilities,held,cap,sequence,button))

def block_action_record(abilities:I.Abilities,held:Inv.Slot,cap:C.Capability,sequence:Nat,button:U32,shell:Shell,result:X.State & Result<&2,&2,String,PR.Record>) -> State & BI.Outcome:
  (player,status) = result
  match status:
    case Fail{message}: (State{player,shell},BI.Outcome{False{},message})
    case Done{record}: block_action_detached(shell,abilities,held,cap,sequence,button,R.detach(player))

def block_action_abilities(player:X.State,held:Inv.Slot,cap:C.Capability,sequence:Nat,button:U32,identity:String,path:String,highwater:U32,limits:P.Limits,lease:WL.Lease,maximum:U32,catalog:List<&2,E.Operation>,fresh:Bool,generation:WG.Settings,result:I.State & I.Abilities) -> State & BI.Outcome:
  (inventory,abilities) = result
  block_action_record(abilities,held,cap,sequence,button,Shell{identity,path,highwater,limits,lease,maximum,catalog,inventory,fresh,generation},R.record_checked(player))

def block_action_selected(cap:C.Capability,sequence:Nat,button:U32,result:State & Inv.Slot) -> State & BI.Outcome:
  (State{player,Shell{identity,path,highwater,limits,lease,maximum,catalog,inventory,fresh,generation}},held) = result
  block_action_abilities(player,held,cap,sequence,button,identity,path,highwater,limits,lease,maximum,catalog,fresh,generation,I.abilities(inventory))

def block_action(state:State,cap:C.Capability,sequence:Nat,button:U32) -> State & BI.Outcome:
  block_action_selected(cap,sequence,button,inventory_selected(state))

def clock_core(registry:B.Registry,view:W.View,result:C.World & C.Clock) -> W.State & C.Clock:
  (world,clock) = result
  (W.attach(G.Engine{world,registry},view),clock)

def clock_world(result:G.Engine & W.View) -> W.State & C.Clock:
  (G.Engine{world,registry},view) = result
  clock_core(registry,view,C.clock(world))

def clock_read(world:W.State) -> W.State & C.Clock:
  clock_world(W.take(world))

def clock_response(session:L.Session,id:String,result:State & C.Clock) -> State & L.Session & J.Value:
  (state,clock) = result
  success(state,session,id,L.clock_value(clock))

def stepped(advance:State -> U32 -> State,state:State,session:L.Session,id:String,result:Result<&2,&2,L.Fault,L.Command>) -> State & L.Session & J.Value:
  match result:
    case Fail{fault}: failure(state,session,id,fault)
    case Done{L.StepCommand{ticks}}:
      clock_response(session,id,query(C.Clock,advance(state,ticks),p => R.query(C.Clock,p,clock_read)))
    case _: failure(state,session,id,L.bad("InvalidArguments","expected a simulation step command"))

def step_checked(advance:State -> U32 -> State,state:State,session:L.Session,id:String,args:J.Value,valid:Bool,allowed:Bool) -> State & L.Session & J.Value:
  match valid allowed:
    case False{} _: failure(state,session,id,L.bad("InvalidArguments","arguments or scheduled at field do not match the operation schema"))
    case True{} False{}: failure(state,session,id,L.bad("PermissionDenied","developer capability required"))
    case True{} True{}: stepped(advance,state,session,id,L.decode(L.StepTicks{},args))

# Intercept the real reserved core operation. Each individual tick applies due
# edits then player physics; delegating to Core.advance would skip interleaving.
def step_envelope(advance:State -> U32 -> State,state:State,session:L.Session,envelope:L.Envelope) -> State & L.Session & J.Value:
  L.Session{+peer,sequence,+capability} = session
  L.Envelope{id,op,+args,at} = envelope
  step_checked(advance,observed(state,peer),L.Session{peer,1n+sequence,capability},id,args,L.validate_args(args,[L.Field{"ticks",L.Unsigned{1,1000},True{}}]) && Maybe.is_none(&2,Nat,at),C.developer(capability))

# The durable codec cannot see transient ownership tails. Check the complete
# runtime only after the existing save/inspect schema and capability gates.
# Other requests keep the unconditional detach/attach owner-preserving path.
def record_refused(state:State,session:L.Session,id:String,code:String,message:String) -> State & L.Session & J.Value:
  L.Session{+peer,sequence,capability} = session
  failure(observed(state,peer),L.Session{peer,1n+sequence,capability},id,L.bad(code,message))

def record_runtime_checked(shell:Shell,session:L.Session,token:String,request:J.Value,id:String,code:String,result:X.State & Result<&2,&2,String,PR.Record>) -> IO(State & L.Session & J.Value):
  (player,status) = result
  match status:
    case Fail{message}: IO.pure(State & L.Session & J.Value,record_refused(State{player,shell},session,id,code,message))
    case Done{record}: delegate(State{player,shell},session,token,request)

def record_admitted(state:State,session:L.Session,token:String,request:J.Value,id:String,code:String) -> IO(State & L.Session & J.Value):
  State{player,shell} = state
  record_runtime_checked(shell,session,token,request,id,code,R.record_checked(player))

def record_valid(state:State,session:L.Session,token:String,request:J.Value,id:String,code:String,valid:Bool,permitted:Bool) -> IO(State & L.Session & J.Value):
  match valid permitted:
    case True{} True{}: record_admitted(state,session,token,request,id,code)
    case _ _: delegate(state,session,token,request)

def save_envelope(state:State,+session:L.Session,token:String,request:J.Value,envelope:L.Envelope) -> IO(State & L.Session & J.Value):
  L.Envelope{id,op,args,at} = envelope
  record_valid(state,session,token,request,id,"SaveEncodingFailed",L.validate_args(args,[]) && Maybe.is_none(&2,Nat,at),C.developer(L.capability(session)))

def inspect_envelope(state:State,session:L.Session,token:String,request:J.Value,envelope:L.Envelope) -> IO(State & L.Session & J.Value):
  L.Envelope{id,op,args,at} = envelope
  record_valid(state,session,token,request,id,"InvalidPlayerState",L.validate_args(args,[]) && Maybe.is_none(&2,Nat,at),True{})

def parsed(advance:State -> U32 -> State,state:State,session:L.Session,token:String,request:J.Value,result:Result<&2,&2,L.Fault,L.Envelope>) -> IO(State & L.Session & J.Value):
  match result:
    case Done{envelope}:
      L.Envelope{id,+op,args,at} = envelope
      match op:
        case "simulation.step": IO.pure(State & L.Session & J.Value,step_envelope(advance,state,session,L.Envelope{id,op,args,at}))
        case "world.save": save_envelope(state,session,token,request,L.Envelope{id,op,args,at})
        case "player.inspect": inspect_envelope(state,session,token,request,L.Envelope{id,op,args,at})
        case _: delegate(state,session,token,request)
    case _: delegate(state,session,token,request)

def dispatch_using(advance:State -> U32 -> State,state:State,session:L.Session,token:String,+request:J.Value) -> IO(State & L.Session & J.Value):
  parsed(advance,state,session,token,request,L.envelope(request))

def dispatch(~driver:R.Driver,state:State,session:L.Session,token:String,+request:J.Value) -> IO(State & L.Session & J.Value):
  dispatch_using(state => ticks => advance(~driver,state,ticks),state,session,token,request)

type Ready is Type:
  Ready{state:State,first_peer:U32}

def startup_closed(message:String,result:Result<&1,&1,U32 & String,Unit>) -> IO(Ready):
  match result:
    case Fail{(code,cause)}: IO.die(Ready,1,"player session startup refused: " ++ message ++ "; lease release: " ++ cause)
    case Done{unit}: IO.die(Ready,1,"player session startup refused: " ++ message)

def startup_failed(shell:Shell,message:String) -> IO(Ready):
  Shell{identity,path,highwater,limits,lease,maximum,catalog,inventory,fresh,generation} = shell
  do IO<Ready>:
    result : Result<&1,&1,U32 & String,Unit> <- WL.release(lease)
    startup_closed(message,result)

def startup_restored(shell:Shell,first_peer:U32,result:X.State & Result<&2,&2,String,Unit>) -> IO(Ready):
  (player,status) = result
  match status:
    case Fail{message}: startup_failed(shell,message)
    case Done{unit}: IO.pure(Ready,Ready{State{player,shell},first_peer})

def startup_world(shell:Shell,first_peer:U32,tables:T.Tables,record:PR.Record,result:W.State & Result<&2,&2,String,Unit>) -> IO(Ready):
  (world,status) = result
  match status:
    case Fail{message}: startup_failed(shell,message)
    case Done{unit}: startup_restored(shell,first_peer,R.restore(R.fresh(world,tables),record))

def startup_base(base:P.State,record:PR.Record,maximum:U32,catalog:List<&2,E.Operation>,first_peer:U32,tables:T.Tables) -> IO(Ready):
  P.State{engine,identity,path,highwater,limits,lease} = base
  startup_world(Shell{identity,path,highwater,limits,lease,maximum,catalog,I.new(),False{},WG.legacy()},first_peer,tables,record,W.new(engine))

# Caller loads the closed PS codec/operations before adoption. The supplied
# Tables are the pinned owned sine lookup. Palette failure closes the save lease.
def new(ready:E.Ready<PR.Record>,tables:T.Tables) -> IO(Ready):
  E.Ready{E.State{base,record,maximum,catalog},first_peer} = ready
  startup_base(base,record,maximum,catalog,first_peer,tables)

def startup_inventory_validated(shell:Shell,first_peer:U32,tables:T.Tables,engine:G.Engine,result:Result<&2,&2,PR.Error,PR.Record>) -> IO(Ready):
  match result:
    case Fail{error}: startup_failed(shell,PR.error_text(error))
    case Done{record}: startup_world(shell,first_peer,tables,record,W.new(engine))

def startup_inventory_base(base:P.State,saved:IC.Saved,maximum:U32,catalog:List<&2,E.Operation>,first_peer:U32,tables:T.Tables) -> IO(Ready):
  P.State{engine,identity,path,highwater,limits,lease} = base
  IC.Saved{record,inventory,fresh,generation} = saved
  startup_inventory_validated(Shell{identity,path,highwater,limits,lease,maximum,catalog,inventory,fresh,generation},first_peer,tables,engine,PR.validate(record))

def new_inventory(ready:E.Ready<IC.Saved>,tables:T.Tables) -> IO(Ready):
  E.Ready{E.State{base,saved,maximum,catalog},first_peer} = ready
  startup_inventory_base(base,saved,maximum,catalog,first_peer,tables)

def returned_bundle(result:E.State<IC.Saved> & R.Transient) -> State:
  (stored,transient) = result
  from_bundle(stored,transient)


law bundle_transfer_preserves_all_local_runtime_and_save_fields:
  for state:State
  {returned_bundle(to_bundle(state)) == state : State}

def bundle_transfer_preserves_all_local_runtime_and_save_fields(state):
  match state:
    case State{X.State{MH.State{W.State{engine,body,yaw,pitch,palette,region,cache},support,minor,H.State{history},motion_tail},tables,
      X.Metadata{local,Plain.Metadata{input,jumping,delay,trigger,sync,speed,head},sprinting,pose,
        CT.Controller{buttons,look,mouse,options},entity, receiver, error,metadata_tail},state_tail},
      Shell{identity,path,highwater,limits,lease,maximum,catalog,inventory,fresh,generation}}: {==}
