import Base
import ./player_inventory_screen.bend as Screen
import ./player_inventory.bend as I
import ./player_item_definitions.bend as D
import ./player_presentation.bend as P
import ./resource_client_wire.bend as W
import ./player_hud.bend as H

# No authority snapshot exists until the authenticated MenuReply arrives.
# This state owns only immutable observations and the screen controller.
type State is Data:
  State{controller:Screen.State,snapshot:Maybe<&2,I.MenuSnapshot>,catalog:D.Catalog}
type Batch is Data:
  Batch{state:State,intents:List<&2,Screen.Intent>,events:List<&2,Event>}

def new(catalog:D.Catalog) -> State:
  State{Screen.new(False{}),None{},catalog}

def viewport(value:P.Viewport) -> Screen.Viewport:
  P.Viewport{width,height,native_width,native_height} = value
  Screen.Viewport{width,height,native_width,native_height}

def observed(state:State,+snapshot:I.MenuSnapshot) -> State:
  State{controller,previous,catalog} = state
  State{Screen.observed(controller,snapshot),Some{snapshot},catalog}

def updated(snapshot:Maybe<&2,I.MenuSnapshot>,catalog:D.Catalog,result:Screen.Update) -> State & List<&2,Screen.Intent>:
  Screen.Update{controller,intents,consumed} = result
  (State{controller,snapshot,catalog},intents)

def completed(state:State,+snapshot:I.MenuSnapshot,accepted:Bool) -> State & List<&2,Screen.Intent>:
  State{controller,previous,catalog} = state
  updated(Some{snapshot},catalog,Screen.completed(controller,snapshot,accepted))

def synchronize(state:State,focused:Bool,captured:Bool) -> State & List<&2,Screen.Intent>:
  match state:
    case State{controller,None{},catalog}:
      updated(None{},catalog,Screen.synchronize(controller,focused,captured))
    case State{controller,Some{+snapshot},catalog}:
      updated(Some{snapshot},catalog,Screen.synchronize_authority(controller,snapshot,focused,captured))

def retain(event:Event,events:List<&2,Event>,consumed:Bool) -> List<&2,Event>:
  match consumed:
    case False{}: event <> events
    case True{}: events

def decided(+event:Event,events:List<&2,Event>,intents:List<&2,Screen.Intent>,result:Screen.Decision) -> Batch:
  Screen.Decision{Screen.Frame{controller,snapshot,catalog},requests,consumed} = result
  Batch{State{controller,Some{snapshot},catalog},List.append(&2,Screen.Intent,intents,requests),retain(event,events,consumed)}

def event(+event:Event,events:List<&2,Event>,intents:List<&2,Screen.Intent>,state:State,
    viewport:Screen.Viewport,focused:Bool,captured:Bool) -> Batch:
  match state:
    case State{controller,None{},catalog}: Batch{State{controller,None{},catalog},intents,event <> events}
    case State{controller,Some{snapshot},catalog}:
      decided(event,events,intents,Screen.step_frame(Screen.Frame{controller,snapshot,catalog},viewport,event,focused,captured))

def events(pending:List<Event>,+viewport:Screen.Viewport,+focused:Bool,+captured:Bool,batch:Batch) -> Batch:
  match pending batch:
    case Nil{} Batch{state,intents,reversed}: Batch{state,intents,List.reverse(&2,Event,reversed)}
    case head <> tail Batch{state,intents,reversed}:
      events(tail,viewport,focused,captured,event(head,reversed,intents,state,viewport,focused,captured))

def synchronized(pending:List<Event>,viewport:Screen.Viewport,focused:Bool,captured:Bool,
    result:State & List<&2,Screen.Intent>) -> Batch:
  (state,intents) = result
  events(pending,viewport,focused,captured,Batch{state,intents,[]})

def packet(state:State,pending:List<Event>,viewport:Screen.Viewport,+focused:Bool,+captured:Bool) -> Batch:
  synchronized(pending,viewport,focused,captured,synchronize(state,focused,captured))

def game_events(pending:List<&2,Event>) -> List<Event>:
  match pending:
    case Nil{}: []
    case head <> tail: head <> game_events(tail)

def capture_allowed(state:State) -> Bool:
  State{controller,snapshot,catalog} = state
  Bool.not(Screen.is_open(controller))

def authority(state:State) -> Maybe<&2,I.MenuSnapshot> & D.Catalog:
  State{controller,snapshot,catalog} = state
  (snapshot,catalog)

def batch_authority(batch:Batch) -> Maybe<&2,I.MenuSnapshot> & D.Catalog:
  Batch{state,intents,events} = batch
  authority(state)

def updated_authority(result:State & List<&2,Screen.Intent>) -> Maybe<&2,I.MenuSnapshot> & D.Catalog:
  (state,intents) = result
  authority(state)

def draw(image:Image,state:State,view:Maybe<&2,Screen.View>,extent:P.Viewport) -> Image:
  match state view:
    case State{controller,snapshot,catalog} Some{value}: Screen.draw_native(image,value,controller,viewport(extent))
    case _ None{}: image

def wire(intent:Screen.Intent) -> Maybe<&2,W.Command>:
  match intent:
    case Screen.Select{index}: Some{W.Select{index}}
    case Screen.Transfer{source,destination,count,mode}: Some{W.Transfer{source,destination,count,mode}}
    case Screen.Acquire{index,key,count}: Some{W.Acquire{index,key,count}}
    case Screen.MenuOpen{}: Some{W.MenuOpen{}}
    case Screen.MenuClose{}: Some{W.MenuClose{}}
    case Screen.MenuClick{index,click}: Some{W.MenuClick{index,click}}
    case _: None{}

def view(state:State,icons:List<&2,Screen.ItemIcon>,fallback:H.Icons) -> Maybe<&2,Screen.View>:
  match state:
    case State{controller,None{},catalog}: None{}
    case State{controller,Some{snapshot},catalog}: Some{Screen.prepare(Screen.Frame{controller,snapshot,catalog},icons,fallback)}
