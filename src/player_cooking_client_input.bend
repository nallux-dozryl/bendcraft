import Base
import ./player_cooking_menu_screen.bend as CookingScreen
import ./player_cooking_menu.bend as Menu
import ./player_inventory_screen.bend as Screen
import ./inventory_key_consumer.bend as Keys
import ./resource_client_wire.bend as Wire
import ./player_hud.bend as H
import ./player_presentation.bend as P

# This owner retains only the correlated full DTO and local screen metadata.
# The actual cooking entities, inventory Array and effects stay in the actor.
type State is Data:
  State{controller:CookingScreen.State,snapshot:Maybe<&2,Menu.Snapshot>}
type Batch is Data:
  Batch{state:State,intents:List<&2,CookingScreen.Intent>,events:List<&2,Event>}

def new() -> State:
  State{CookingScreen.new(),None{}}

def observed(state:State,+snapshot:Menu.Snapshot) -> State:
  State{controller,previous} = state
  State{CookingScreen.observed(controller,snapshot),Some{snapshot}}

def updated(snapshot:Maybe<&2,Menu.Snapshot>,result:CookingScreen.Update) -> State & List<&2,CookingScreen.Intent>:
  CookingScreen.Update{controller,intents,consumed} = result
  (State{controller,snapshot},intents)

# Only the presenter may complete an authenticated, correlated operation.
def completed(state:State,+reply:Menu.Reply) -> State & List<&2,CookingScreen.Intent>:
  State{controller,previous} = state
  Menu.Reply{accepted,message,+snapshot,effects} = reply
  updated(Some{snapshot},CookingScreen.completed(controller,reply))

def focus(state:State,focused:Bool,captured:Bool) -> State & List<&2,CookingScreen.Intent>:
  State{controller,snapshot} = state
  updated(snapshot,CookingScreen.focus(controller,focused,captured))

def is_open(state:State) -> Bool:
  State{controller,snapshot} = state
  CookingScreen.is_open(controller)

def active(state:State) -> Bool:
  State{controller,snapshot} = state
  CookingScreen.active(controller)

def capture_allowed(state:State) -> Bool:
  Bool.not(active(state))

def menu_id(state:State) -> U32:
  State{controller,snapshot} = state
  CookingScreen.menu_id(controller)

def authority(state:State) -> Maybe<&2,Menu.Snapshot>:
  State{controller,snapshot} = state
  snapshot

def batch_authority(batch:Batch) -> Maybe<&2,Menu.Snapshot>:
  Batch{state,intents,events} = batch
  authority(state)

def updated_authority(result:State & List<&2,CookingScreen.Intent>) -> Maybe<&2,Menu.Snapshot>:
  (state,intents) = result
  authority(state)

def batch_events(batch:Batch) -> List<&2,Event>:
  Batch{state,intents,events} = batch
  events

def stepped(snapshot:Maybe<&2,Menu.Snapshot>,intents:List<&2,CookingScreen.Intent>,events:List<&2,Event>,result:CookingScreen.Update) -> Batch:
  CookingScreen.Update{controller,requests,consumed} = result
  Batch{State{controller,snapshot},List.append(&2,CookingScreen.Intent,intents,requests),events}

# Cooking owns the complete native batch while open or awaiting a reply. Its
# screen owns OS Close too: actual MenuClose must return carried items before
# a correlated closed reply may emit the deferred Quit intent.
def event(input:Event,intents:List<&2,CookingScreen.Intent>,events:List<&2,Event>,state:State,
    viewport:Screen.Viewport,focused:Bool,captured:Bool) -> Batch:
  State{controller,snapshot} = state
  stepped(snapshot,intents,events,CookingScreen.step(controller,viewport,input,focused,captured))

def mapped(input:Maybe<&2,Event>,intents:List<&2,CookingScreen.Intent>,events:List<&2,Event>,state:State,
    viewport:Screen.Viewport,focused:Bool,captured:Bool) -> Batch:
  match input:
    case None{}: Batch{state,intents,events}
    case Some{value}: event(value,intents,events,state,viewport,focused,captured)

# Cooking has no character search field. The neutral existing controller gives
# the actual key consumer its searching=False policy without another binding
# implementation. Unbound physical Shift keeps its paired logical sided code.
def key_event(profile:Keys.Profile,input:Event,intents:List<&2,CookingScreen.Intent>,events:List<&2,Event>,state:State,
    viewport:Screen.Viewport,focused:Bool,captured:Bool) -> Batch:
  mapped(Keys.event(profile,Screen.new(False{}),input),intents,events,state,viewport,focused,captured)

def finished(batch:Batch) -> Batch:
  Batch{state,intents,reversed} = batch
  Batch{state,intents,List.reverse(&2,Event,reversed)}

def events(pending:List<Event>,+viewport:Screen.Viewport,+focused:Bool,+captured:Bool,batch:Batch) -> Batch:
  match pending batch:
    case Nil{} batch: finished(batch)
    case head <> tail Batch{state,intents,reversed}:
      events(tail,viewport,focused,captured,event(head,intents,reversed,state,viewport,focused,captured))

def shared_events(pending:List<Event>) -> List<&2,Event>:
  match pending:
    case Nil{}: []
    case head <> tail: head <> shared_events(tail)

def key_events_go(left:Nat,pending:List<&2,Event>,+profile:Keys.Profile,+viewport:Screen.Viewport,+focused:Bool,+captured:Bool,batch:Batch) -> Batch:
  match left pending batch:
    case 0n _ batch: finished(batch)
    case _ Nil{} batch: finished(batch)
    case 1n+n +head <> tail Batch{state,intents,reversed}:
      key_events_go(n,Keys.following(profile,Screen.new(False{}),head,tail),profile,viewport,focused,captured,
        key_event(profile,head,intents,reversed,state,viewport,focused,captured))

def key_events_shared(+pending:List<&2,Event>,profile:Keys.Profile,viewport:Screen.Viewport,focused:Bool,captured:Bool,batch:Batch) -> Batch:
  key_events_go(List.length(&2,Event,pending),pending,profile,viewport,focused,captured,batch)

def key_events(pending:List<Event>,profile:Keys.Profile,viewport:Screen.Viewport,focused:Bool,captured:Bool,batch:Batch) -> Batch:
  key_events_shared(shared_events(pending),profile,viewport,focused,captured,batch)

def active_packet(physical:Bool,profile:Keys.Profile,pending:List<Event>,viewport:Screen.Viewport,focused:Bool,captured:Bool,batch:Batch) -> Batch:
  match physical:
    case False{}: events(pending,viewport,focused,captured,batch)
    case True{}: key_events(pending,profile,viewport,focused,captured,batch)

def focused_packet(routed:Bool,physical:Bool,profile:Keys.Profile,pending:List<Event>,viewport:Screen.Viewport,focused:Bool,captured:Bool,
    result:State & List<&2,CookingScreen.Intent>) -> Batch:
  match routed:
    case False{}:
      (state,intents) = result
      # The ordinary MenuInput owner receives the unchanged original batch and
      # the same native flags; it owns world/inventory focus-release intents.
      Batch{state,[],shared_events(pending)}
    case True{}:
      (state,intents) = result
      active_packet(physical,profile,pending,viewport,focused,captured,Batch{state,intents,[]})

# Synchronize even an empty batch. Gate before key normalization: when cooking
# is inactive, all canonical physical markers and paired characters survive for
# the ordinary MenuInput owner to normalize exactly once.
def packet_keys(physical:Bool,profile:Keys.Profile,+state:State,pending:List<Event>,viewport:Screen.Viewport,+focused:Bool,+captured:Bool) -> Batch:
  focused_packet(active(state),physical,profile,pending,viewport,focused,captured,focus(state,focused,captured))

def wire(action:Menu.Action) -> Wire.Command:
  match action:
    case Menu.MenuInspect{menu}: Wire.CookingInspect{menu}
    case Menu.MenuPickup{menu,index,button}: Wire.CookingClick{menu,index,button}
    case Menu.MenuQuickMove{menu,index}: Wire.CookingQuickMove{menu,index}
    case Menu.MenuClose{menu}: Wire.CookingClose{menu}

def view(state:State,rows:List<&2,Screen.ItemIcon>,icons:H.Icons) -> Maybe<&2,CookingScreen.View>:
  match state:
    case State{controller,None{}}: None{}
    case State{controller,Some{snapshot}}: Some{CookingScreen.prepare(snapshot,rows,icons)}

def viewport(value:P.Viewport) -> Screen.Viewport:
  P.Viewport{width,height,native_width,native_height} = value
  Screen.Viewport{width,height,native_width,native_height}

def draw(image:Image,state:State,view:Maybe<&2,CookingScreen.View>,extent:P.Viewport) -> Image:
  match state view:
    case State{controller,snapshot} Some{value}: CookingScreen.draw_native(image,value,controller,viewport(extent))
    case _ None{}: image
