import Base
import ./local_player_session.bend as S
import ./local_player_runtime.bend as Runtime
import ./local_player_record.bend as Record
import ./player_record.bend as Saved
import ./player_codec.bend as Codec
import ./local_player_cooking.bend as Cooking
import ./cooking_world.bend as CW
import ./player_cooking_menu.bend as Menu
import ./player_cooking_menu_campfire.bend as Campfire
import ./player_cooking_target.bend as Target
import ./player_inventory.bend as I
import ./core.bend as C
import ./player_block_interaction.bend as BI
import ./player_core_edit.bend as Edit
import ./f64.bend as F
import ./png.bend as Pair

type Request is Data:
  Open{position:C.Position}
  Act{action:Menu.Action}
  Use{offhand:Bool,sequence:Nat}

# These defaults are the existing closed neutral LocalPlayer profile. The
# current record has no range-modifier owner; request fields cannot set range.
def range_of(creative:Bool) -> F.F64:
  match creative:
    case True{}: F.from_u32(5)
    case False{}: F.div(F.from_u32(9),F.from_u32(2))

def range(abilities:I.Abilities) -> F.F64:
  I.Abilities{creative,maybuild} = abilities
  range_of(creative)

def dimension(record:Record.Record) -> String:
  Record.Record{Saved.Record{Codec.Snapshot{state,support,yaw,pitch,dimension},look},local,sprinting,pose,minor,history,entity} = record
  dimension

def handle_position(handle:Menu.Handle) -> C.Position:
  match handle:
    case Menu.Closed{}: C.Position{"minecraft:overworld",0,0,0}
    case Menu.Furnace{menu,peer,position,block,kind,token}: position

def current_action(handle:Menu.Handle,action:Menu.Action) -> Menu.Action:
  match handle action:
    # Zero is a read-only current-menu discovery request for a new connection.
    case Menu.Furnace{id,peer,position,block,kind,token} Menu.MenuInspect{0}: Menu.MenuInspect{id}
    case _ _: action

def campfire_operation(admit:Menu.Reply -> Result<&2,&2,String,Unit>,context:CW.Context,owner:CW.State,inventory:I.State,position:C.Position,access:Menu.Access,offhand:Bool) -> CW.State & I.State & Result<&2,&2,String,Menu.Reply>:
  match offhand:
    case False{}: Campfire.use_hands(admit,context,owner,inventory,position,access)
    case True{}: Campfire.use(admit,context,owner,inventory,position,access,True{})

def operation(admit:Menu.Reply -> Result<&2,&2,String,Unit>,+handle:Menu.Handle,access:Menu.Access,next:U32,request:Request,
    context:CW.Context,owner:CW.State,inventory:I.State) ->
    CW.State & I.State & Result<&2,&2,String,Menu.Reply>:
  match request:
    case Open{position}: Menu.open(admit,context,owner,inventory,handle,access,position,next)
    case Act{action}: Menu.dispatch(admit,context,owner,inventory,handle,access,current_action(handle,action))
    case Use{offhand,sequence}: Campfire.use(admit,context,owner,inventory,handle_position(handle),access,offhand)

# Reply effects stay in the real actor's released-effect queue. They are never
# serialized as client authority and are not replayed by per-frame inspection.
def enqueued(+reply:Menu.Reply,result:S.State & Result<&2,&2,String,Unit>) -> S.State & Result<&2,&2,String,Menu.Reply>:
  (saved,status) = result
  match status:
    case Fail{message}: (saved,Fail{message})
    case Done{unit}: (saved,Done{reply})

def returned(result:S.State & Result<&2,&2,String,Menu.Reply>) -> S.State & Result<&2,&2,String,Menu.Reply>:
  (saved,status) = result
  match status:
    case Fail{message}: (saved,Fail{message})
    case Done{+reply}:
      Menu.Reply{accepted,message,snapshot,effects} = reply
      match effects:
        case Nil{}: (saved,Done{reply})
        case _: enqueued(reply,S.cooking_enqueue_effects(saved,effects))

def accessed(admit:Menu.Reply -> Result<&2,&2,String,Unit>,handle:Menu.Handle,next:U32,request:Request,result:S.State & Result<&2,&2,String,Menu.Access>) -> S.State & Result<&2,&2,String,Menu.Reply>:
  (saved,status) = result
  match status:
    case Fail{message}: (saved,Fail{message})
    case Done{+access}:
      returned(S.cooking_inventory_query(Menu.Reply,saved,
        world => sidecar => inventory => Cooking.with_inventory_owner(Menu.Reply,world,sidecar,inventory,
          context => owner => items => operation(admit,handle,access,next,request,context,owner,items))))

def token(+capability:C.Capability,+record:Record.Record,+range:F.F64,result:S.State & Nat) -> S.State & Result<&2,&2,String,Menu.Access>:
  (saved,incarnation) = result
  (saved,Done{Menu.Access{capability,Maybe.is_some(&2,U32,Edit.player_peer(capability)),dimension(record),BI.eye(record),range,incarnation}})

def recorded(capability:C.Capability,position:C.Position,range:F.F64,result:S.State & Result<&2,&2,String,Record.Record>) -> S.State & Result<&2,&2,String,Menu.Access>:
  (saved,status) = result
  match status:
    case Fail{message}: (saved,Fail{message})
    case Done{record}: token(capability,record,range,S.cooking_sidecar_query(Nat,saved,sidecar => Cooking.incarnation(sidecar,position)))

def access(saved:S.State,capability:C.Capability,position:C.Position,range:F.F64) -> S.State & Result<&2,&2,String,Menu.Access>:
  recorded(capability,position,range,S.query(Result<&2,&2,String,Record.Record>,saved,Runtime.record_checked))

def inspected(handle:Menu.Handle,accepted:Bool,message:String,result:S.State & I.MenuSnapshot) -> S.State & Result<&2,&2,String,Menu.Reply>:
  (saved,snapshot) = result
  (saved,Done{Menu.reply(accepted,message,handle,None{},snapshot,[])})

def open_allowed(admit:Menu.Reply -> Result<&2,&2,String,Unit>,saved:S.State,capability:C.Capability,handle:Menu.Handle,next:U32,+position:C.Position,range:F.F64,allowed:Bool) -> S.State & Result<&2,&2,String,Menu.Reply>:
  match allowed:
    case False{}: inspected(handle,False{},"cooking-menu:menu-id-exhausted",S.menu_inspect(saved))
    case True{}: accessed(admit,handle,next,Open{position},access(saved,capability,position,range))

def direct(admit:Menu.Reply -> Result<&2,&2,String,Unit>,saved:S.State,capability:C.Capability,+handle:Menu.Handle,+next:U32,+request:Request,range:F.F64) -> S.State & Result<&2,&2,String,Menu.Reply>:
  match handle request:
    case Menu.Closed{} Act{Menu.MenuInspect{0}}: inspected(handle,True{},"",S.menu_inspect(saved))
    case _ Open{position}: open_allowed(admit,saved,capability,handle,next,position,range,U32.is_gt(next,0) && U32.is_lt(next,4294967295))
    case _ _: accessed(admit,handle,next,request,access(saved,capability,handle_position(handle),range))

def campfire_accessed(admit:Menu.Reply -> Result<&2,&2,String,Unit>,position:C.Position,offhand:Bool,result:S.State & Result<&2,&2,String,Menu.Access>) -> S.State & Result<&2,&2,String,Menu.Reply>:
  (actual,status) = result
  match status:
    case Fail{message}: (actual,Fail{message})
    case Done{+access}:
      returned(S.cooking_inventory_query(Menu.Reply,actual,
        world => sidecar => inventory => Cooking.with_inventory_owner(Menu.Reply,world,sidecar,inventory,
          context => owner => items => campfire_operation(admit,context,owner,items,position,access,offhand))))

def use_picked(admit:Menu.Reply -> Result<&2,&2,String,Unit>,capability:C.Capability,+handle:Menu.Handle,next:U32,offhand:Bool,sequence:Nat,range:F.F64,
    result:S.State & Result<&2,&2,String,Maybe<&2,Target.Hit>>) -> S.State & Result<&2,&2,String,Menu.Reply>:
  (saved,status) = result
  match status:
    case Fail{message}: inspected(handle,False{},message,S.menu_inspect(saved))
    case Done{None{}}: inspected(handle,False{},"cooking-target:miss",S.menu_inspect(saved))
    case Done{Some{Target.Hit{position,Target.Furnace{}}}}: direct(admit,saved,capability,handle,next,Open{position},range)
    case Done{Some{Target.Hit{+position,Target.Campfire{}}}}:
      # A campfire has no Handle or GUI; its position is passed directly.
      campfire_accessed(admit,position,offhand,access(saved,capability,position,range))
    case Done{Some{Target.Hit{position,Target.Other{}}}}:
      inspected(handle,False{},"cooking-target:ordinary-block",S.menu_inspect(saved))

def ranged_request(admit:Menu.Reply -> Result<&2,&2,String,Unit>,saved:S.State,capability:C.Capability,handle:Menu.Handle,next:U32,request:Request,+reach:F.F64) -> S.State & Result<&2,&2,String,Menu.Reply>:
  match handle request:
    case Menu.Furnace{menu,peer,position,block,kind,token} Use{offhand,sequence}:
      inspected(handle,False{},"cooking-menu:already-open",S.menu_inspect(saved))
    case Menu.Closed{} Use{offhand,sequence}:
      use_picked(admit,capability,handle,next,offhand,sequence,reach,S.query(Result<&2,&2,String,Maybe<&2,Target.Hit>>,saved,player => Target.query(player,reach)))
    case _ _: direct(admit,saved,capability,handle,next,request,reach)

def ranged(admit:Menu.Reply -> Result<&2,&2,String,Unit>,capability:C.Capability,handle:Menu.Handle,next:U32,request:Request,result:S.State & I.Abilities) -> S.State & Result<&2,&2,String,Menu.Reply>:
  (saved,abilities) = result
  ranged_request(admit,saved,capability,handle,next,request,range(abilities))

def request(admit:Menu.Reply -> Result<&2,&2,String,Unit>,saved:S.State,capability:C.Capability,handle:Menu.Handle,next:U32,request:Request) -> S.State & Result<&2,&2,String,Menu.Reply>:
  ranged(admit,capability,handle,next,request,S.inventory_abilities(saved))
