import Base
import ../src/player_inventory_screen.bend as S
import ../src/player_inventory.bend as I
import ../src/player_item_definitions.bend as D
import ../src/player_item_catalog.bend as Catalog
import ../src/inventory.bend as Inv
import ../src/json.bend as J
import ../src/live.bend as L
import ../src/resource_client_wire.bend as Wire

# Literal fixtures are independent of the controller. Every output includes
# the complete authority, so conservation is checked beyond a selected slot.
def empty(left:Nat) -> List<&2,Inv.Slot>:
  match left:
    case 0n: []
    case 1n+n: Inv.InvEmpty{} <> empty(n)

def stack(id:String,count:U32) -> Inv.Slot: Inv.InvStack{Inv.ItemKey{id,""},count}

def fixture(+opened:Bool) -> I.MenuSnapshot:
  I.MenuSnapshot{I.Persisted{I.Snapshot{4,stack("minecraft:stone",19) <> empty(35n),I.Abilities{True{},False{}}},
    [stack("minecraft:dirt",2),Inv.InvEmpty{},stack("minecraft:oak_planks",3),Inv.InvEmpty{},stack("minecraft:stone",4),stack("minecraft:dirt",5),stack("minecraft:oak_planks",6)],
    I.Status{True{},True{},False{},1036831949,1028443341}},[stack("minecraft:dirt",7),Inv.InvEmpty{},stack("minecraft:stone",8),Inv.InvEmpty{}],
    stack("minecraft:oak_planks",9),Some{stack("minecraft:stone",10)},opened,11n}

def main_state(open:Bool,pending:U32,tab:U32) -> S.State:
  S.State{open,0,0,False{},True{},None{},None{},pending,tab,0,"",S.Ready{},S.Outside{}}

def unfocused_state(pending:U32) -> S.State:
  S.State{False{},0,0,False{},False{},None{},None{},pending,0,0,"",S.Waiting{},S.Outside{}}

def movement_state() -> S.State:
  S.State{True{},0,0,False{},True{},Some{0},None{},0,2,0,"",S.ChooseTarget{},S.Outside{}}

def acquisition_state() -> S.State:
  S.State{True{},0,0,False{},True{},None{},Some{D.Definition{1,"minecraft:stone","block.minecraft.stone",64,1386,
    "5b59e002f4f7936d6af1fe77fc08cdfd019c0ab140dcc2b62f0ce3562be37a6b",True{}}},0,1,0,"",S.ChooseSlot{},S.Outside{}}

def hit_value(hit:S.Hit) -> J.Value:
  match hit:
    case S.AtViewport{width,height,nw,nh,target}: hit_value(target)
    case S.Outside{}: L.text("outside")
    case S.Slot{index}: L.obj([J.JMember{"slot",L.uint(index)}])
    case S.Palette{index}: L.obj([J.JMember{"palette",L.uint(index)}])
    case S.Tab{index}: L.obj([J.JMember{"tab",L.uint(index)}])
    case S.Previous{}: L.text("previous")
    case S.Next{}: L.text("next")
    case S.Search{}: L.text("search")

def key_value(key:Inv.ItemKey) -> J.Value:
  Inv.ItemKey{id,components} = key
  L.obj([J.JMember{"id",L.text(id)},J.JMember{"components",L.text(components)}])

def intent_value(intent:S.Intent) -> J.Value:
  match intent:
    case S.ReleaseControls{}: L.text("release")
    case S.Capture{enabled}: L.obj([J.JMember{"capture",L.boolean(enabled)}])
    case S.Select{slot}: L.obj([J.JMember{"select",L.uint(slot)}])
    case S.Transfer{source,destination,count,mode}: L.obj([J.JMember{"transfer",J.JArray{[L.uint(source),L.uint(destination),L.uint(count)]}}])
    case S.Acquire{slot,key,count}: L.obj([J.JMember{"acquire",J.JArray{[L.uint(slot),key_value(key),L.uint(count)]}}])
    case S.MenuOpen{}: L.text("open")
    case S.MenuClose{}: L.text("close")
    case S.MenuClick{slot,I.Pickup{button}}: L.obj([J.JMember{"pickup",J.JArray{[L.uint(slot),L.uint(button)]}}])
    case S.MenuClick{slot,I.Swap{button}}: L.obj([J.JMember{"swap",J.JArray{[L.uint(slot),L.uint(button)]}}])
    case S.MenuClick{slot,click}: L.obj([J.JMember{"menu-click",L.uint(slot)}])
    case S.Quit{}: L.text("quit")

def intent_values(values:List<&2,S.Intent>) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case value <> rest: intent_value(value) <> intent_values(rest)

def source_value(value:Maybe<&2,U32>) -> J.Value:
  match value:
    case None{}: J.JNull{}
    case Some{index}: L.uint(index)

def offer_value(value:Maybe<&2,D.Definition>) -> J.Value:
  match value:
    case None{}: J.JNull{}
    case Some{D.Definition{number,id,description,limit,set,hash,enabled}}:
      J.JArray{[L.uint(number),L.text(id),L.text(description),L.uint(limit),L.uint(set),L.text(hash),L.boolean(enabled)]}

def notice_value(value:S.Notice) -> J.Value:
  match value:
    case S.Ready{}: L.text("ready")
    case S.Waiting{}: L.text("waiting")
    case S.Rejected{}: L.text("rejected")
    case S.Invalid{}: L.text("invalid")
    case S.TooSmall{}: L.text("too-small")
    case S.Unavailable{}: L.text("unavailable")
    case S.ChooseTarget{}: L.text("choose-target")
    case S.ChooseSlot{}: L.text("choose-slot")

def hover_viewport(hit:S.Hit) -> J.Value:
  match hit:
    case S.AtViewport{width,height,nw,nh,target}: J.JArray{[L.uint(width),L.uint(height),L.uint(nw),L.uint(nh)]}
    case _: J.JNull{}

def state_value(state:S.State) -> J.Value:
  S.State{open,keys,buttons,captured,focused,source,offer,pending,tab,row,query,message,+hover} = state
  L.obj([J.JMember{"open",L.boolean(open)},J.JMember{"keys",L.uint(keys)},J.JMember{"buttons",L.uint(buttons)},
    J.JMember{"captured",L.boolean(captured)},J.JMember{"focused",L.boolean(focused)},J.JMember{"pending",L.uint(pending)},
    J.JMember{"tab",L.uint(tab)},J.JMember{"row",L.uint(row)},J.JMember{"query",L.text(query)},J.JMember{"hover",hit_value(hover)},
    J.JMember{"source",source_value(source)},J.JMember{"offer",offer_value(offer)},J.JMember{"notice",notice_value(message)},
    J.JMember{"hover_viewport",hover_viewport(hover)}])

def report(label:String,decision:S.Decision) -> IO(Unit):
  S.Decision{S.Frame{state,snapshot,catalog},intents,consumed} = decision
  IO.print(J.encode(L.obj([J.JMember{"label",L.text(label)},J.JMember{"controller",state_value(state)},
    J.JMember{"authority",Wire.menu_snapshot_value(snapshot)},J.JMember{"intents",J.JArray{intent_values(intents)}},J.JMember{"consumed",L.boolean(consumed)}])))

def frame(state:S.State,opened:Bool) -> S.Frame: S.Frame{state,fixture(opened),D.legacy()}

def with_carried(snapshot:I.MenuSnapshot,carried:Inv.Slot) -> I.MenuSnapshot:
  I.MenuSnapshot{saved,craft,old,result,opened,revision} = snapshot
  I.MenuSnapshot{saved,craft,carried,result,opened,revision}

def key_frame(state:S.State,opened:Bool,carried:Inv.Slot) -> S.Frame:
  S.Frame{state,with_carried(fixture(opened),carried),D.legacy()}

# Actual Move establishes hover; keyboard cases never manufacture a Slot hit.
def moved(frame:S.Frame,+viewport:S.Viewport,x:U32,y:U32) -> S.Frame:
  S.decision_frame(S.step_frame(frame,viewport,Move{x,y},True{},False{}))

def keyed(frame:S.Frame,+viewport:S.Viewport,code:U32,down:Bool) -> S.Decision:
  S.step_frame(frame,viewport,Key{code,down},True{},False{})

def gui_key(label:String,x:U32,y:U32,code:U32,carried:Inv.Slot) -> IO(Unit):
  +viewport = {S.Viewport{320,180,960,540} : S.Viewport}
  report(label,keyed(moved(key_frame(main_state(True{},0,0),True{},carried),viewport,x,y),viewport,code,True{}))

def swap_hovered() -> S.Frame:
  moved(key_frame(main_state(True{},0,0),True{},Inv.InvEmpty{}),S.Viewport{320,180,960,540},315,291)

def swap_sent() -> S.Frame:
  S.decision_frame(keyed(swap_hovered(),S.Viewport{320,180,960,540},70,True{}))

def swap_acked() -> S.Frame:
  S.decision_frame(S.acknowledge(swap_sent(),with_carried(fixture(True{}),Inv.InvEmpty{}),True{}))

def swap_released() -> S.Frame:
  S.decision_frame(keyed(swap_acked(),S.Viewport{320,180,960,540},70,False{}))

def swap_captured() -> S.Frame:
  S.decision_frame(S.step_frame(swap_hovered(),S.Viewport{320,180,960,540},Look{0.0,0.0},True{},True{}))

def swap_cases() -> IO(Unit):
  +viewport = {S.Viewport{320,180,960,540} : S.Viewport}
  +resized = {S.Viewport{320,180,1920,1080} : S.Viewport}
  +scaled = {S.Viewport{640,360,960,540} : S.Viewport}
  do IO<Unit>:
    gui_key("digit-0",315,291,49,Inv.InvEmpty{})
    gui_key("digit-1",315,291,50,Inv.InvEmpty{})
    gui_key("digit-2",315,291,51,Inv.InvEmpty{})
    gui_key("digit-3",315,291,52,Inv.InvEmpty{})
    gui_key("digit-4",315,291,53,Inv.InvEmpty{})
    gui_key("digit-5",315,291,54,Inv.InvEmpty{})
    gui_key("digit-6",315,291,55,Inv.InvEmpty{})
    gui_key("digit-7",315,291,56,Inv.InvEmpty{})
    gui_key("digit-8",315,291,57,Inv.InvEmpty{})
    gui_key("offhand",315,291,70,Inv.InvEmpty{})
    gui_key("digit-no-hover",960,540,49,Inv.InvEmpty{})
    gui_key("offhand-no-hover",960,540,70,Inv.InvEmpty{})
    gui_key("digit-carried",315,291,49,stack("minecraft:dirt",3))
    gui_key("offhand-carried",315,291,70,stack("minecraft:dirt",3))
    gui_key("digit-shift",315,291,49,Inv.InvEmpty{})
    gui_key("offhand-control",315,291,70,Inv.InvEmpty{})
    gui_key("digit-result",651,177,49,Inv.InvEmpty{})
    gui_key("offhand-self",459,225,70,Inv.InvEmpty{})
    gui_key("offhand-lowercase",315,291,102,Inv.InvEmpty{})
    report("pending-blocks-key",keyed(swap_sent(),viewport,57,True{}))
    report("held-after-reply",keyed(swap_acked(),viewport,70,True{}))
    report("release-rearm",keyed(swap_released(),viewport,70,True{}))
    report("resize-clears-hover",keyed(swap_hovered(),resized,70,True{}))
    report("scale-clears-hover",keyed(swap_hovered(),scaled,49,True{}))
    report("capture-clears-hover",keyed(swap_captured(),viewport,70,True{}))
    report("resized-new-move",keyed(moved(swap_hovered(),resized,630,582),resized,70,True{}))
    report("world-digit",keyed(key_frame(main_state(False{},0,0),False{},Inv.InvEmpty{}),viewport,57,True{}))
    report("world-offhand",keyed(key_frame(main_state(False{},0,0),False{},Inv.InvEmpty{}),viewport,70,True{}))
    report("world-retained-search",keyed(key_frame(main_state(False{},0,3),False{},Inv.InvEmpty{}),viewport,57,True{}))
    report("search-digit",keyed(key_frame(main_state(True{},0,3),True{},Inv.InvEmpty{}),viewport,57,True{}))
    report("search-offhand-carried",keyed(key_frame(main_state(True{},0,3),True{},stack("minecraft:dirt",3)),viewport,70,True{}))
    report("tab-clears-hover",keyed(S.decision_frame(S.step_frame(swap_hovered(),viewport,Mouse{450,30,0,True{}},True{},False{})),viewport,70,True{}))
    report("focus-clears-hover",S.step_frame(swap_hovered(),viewport,Key{70,True{}},False{},False{}))
    report("late-refused-focus",S.acknowledge(S.decision_frame(S.step_frame(swap_sent(),viewport,Look{0.0,0.0},False{},False{})),with_carried(fixture(True{}),Inv.InvEmpty{}),False{}))

def cases() -> IO(Unit):
  +viewport = {S.Viewport{320,180,960,540} : S.Viewport}
  do IO<Unit>:
    report("open",S.step_frame(frame(main_state(False{},0,0),False{}),viewport,Key{69,True{}},True{},True{}))
    report("pending-close",S.step_frame(frame(main_state(True{},3,0),True{}),viewport,Key{27,True{}},True{},False{}))
    report("close",S.step_frame(frame(main_state(True{},0,0),True{}),viewport,Key{27,True{}},True{},False{}))
    report("focus",S.step_frame(frame(main_state(True{},3,0),True{}),viewport,Look{1.0,F32.sub(0.0,2.0)},False{},False{}))
    report("select",S.step_frame(frame(main_state(True{},0,0),True{}),viewport,Key{57,True{}},True{},False{}))
    report("pickup",S.step_frame(frame(main_state(True{},0,0),True{}),viewport,Mouse{267,459,0,True{}},True{},False{}))
    report("right",S.step_frame(frame(main_state(True{},0,0),True{}),viewport,Mouse{267,459,1,True{}},True{},False{}))
    report("outside",S.step_frame(frame(main_state(True{},0,0),True{}),viewport,Mouse{960,540,0,True{}},True{},False{}))
    report("captured",S.step_frame(frame(main_state(True{},0,0),True{}),viewport,Mouse{267,459,0,True{}},True{},True{}))
    report("refused-close",S.acknowledge(frame(main_state(True{},2,0),True{}),fixture(True{}),False{}))
    report("accepted-close",S.acknowledge(frame(main_state(True{},2,0),True{}),fixture(False{}),True{}))
    report("open-reply",S.acknowledge(frame(main_state(True{},1,0),False{}),fixture(True{}),True{}))
    report("look-consumed",S.step_frame(frame(main_state(True{},0,0),True{}),viewport,Look{5.0,7.0},True{},False{}))
    report("move-tab",S.step_frame(frame(main_state(True{},0,0),True{}),viewport,Mouse{600,30,0,True{}},True{},False{}))
    report("items-tab",S.step_frame(frame(main_state(True{},0,0),True{}),viewport,Mouse{450,30,0,True{}},True{},False{}))
    report("palette",S.step_frame(frame(main_state(True{},0,1),True{}),viewport,Mouse{267,81,0,True{}},True{},False{}))
    report("late-close-unfocused",S.acknowledge(frame(unfocused_state(2),True{}),fixture(False{}),True{}))
    report("late-open-unfocused",S.acknowledge(frame(unfocused_state(1),False{}),fixture(True{}),True{}))
    report("refused-open",S.acknowledge(frame(main_state(True{},1,0),False{}),fixture(False{}),False{}))
    report("refused-already-closed",S.acknowledge(frame(main_state(True{},2,0),True{}),fixture(False{}),False{}))
    report("move-all",S.step_frame(frame(movement_state(),True{}),viewport,Mouse{267,291,0,True{}},True{},False{}))
    report("move-one",S.step_frame(frame(movement_state(),True{}),viewport,Mouse{267,291,1,True{}},True{},False{}))
    report("acquire-max",S.step_frame(frame(acquisition_state(),True{}),viewport,Mouse{267,459,0,True{}},True{},False{}))
    report("acquire-one",S.step_frame(frame(acquisition_state(),True{}),viewport,Mouse{267,459,1,True{}},True{},False{}))
    report("refocus-open",S.step_frame(frame(unfocused_state(0),True{}),viewport,Key{87,True{}},True{},True{}))
    report("observe-pending",S.Decision{frame(S.observed(main_state(True{},1,0),fixture(False{})),False{}),[],True{}})
    report("observe-unfocused",S.Decision{frame(S.observed(unfocused_state(0),fixture(True{})),True{}),[],True{}})

# Literal native coordinates for the observed46-slot topology at logical320x180,
# drawable960x540. This fixture does not call production layout/slot_position.
type Point is Data:
  Point{x:U32,y:U32}

def hit_points() -> List<&2,Point>:
  [Point{651,177},Point{507,129},Point{555,129},Point{507,177},Point{555,177},Point{267,81},Point{267,129},Point{267,177},Point{267,225},Point{267,291},Point{315,291},Point{363,291},Point{411,291},Point{459,291},Point{507,291},Point{555,291},Point{603,291},Point{651,291},Point{267,339},Point{315,339},Point{363,339},Point{411,339},Point{459,339},Point{507,339},Point{555,339},Point{603,339},Point{651,339},Point{267,387},Point{315,387},Point{363,387},Point{411,387},Point{459,387},Point{507,387},Point{555,387},Point{603,387},Point{651,387},Point{267,453},Point{315,453},Point{363,453},Point{411,453},Point{459,453},Point{507,453},Point{555,453},Point{603,453},Point{651,453},Point{459,225}]

def hit_report(+index:U32,point:Point) -> IO(Unit):
  Point{x,y} = point
  IO.print(J.encode(L.obj([J.JMember{"slot",L.uint(index)},J.JMember{"hit",hit_value(S.hit(S.Viewport{320,180,960,540},0,x,y))}])))

def hits(points:List<&2,Point>,+index:U32) -> IO(Unit):
  match points:
    case Nil{}: IO.pure(Unit,Unit{})
    case point <> rest:
      do IO<Unit>:
        hit_report(index,point)
        hits(rest,U32.add(index,1))

def metadata_value(value:Maybe<&2,Inv.ItemMetadata>) -> J.Value:
  match value:
    case None{}: J.JNull{}
    case Some{Inv.ItemMetadata{key,limit}}: L.uint(limit)

def definitions_rows(+catalog:D.Catalog,items:List<&2,D.Definition>) -> IO(Unit):
  match items:
    case Nil{}: IO.pure(Unit,Unit{})
    case D.Definition{number,+id,description,limit,set,hash,enabled} <> rest:
      do IO<Unit>:
        IO.print(J.encode(L.obj([J.JMember{"number",L.uint(number)},J.JMember{"id",L.text(id)},
          J.JMember{"limit",L.uint(limit)},J.JMember{"component_set",L.uint(set)},J.JMember{"components_sha256",L.text(hash)},
          J.JMember{"enabled",L.boolean(enabled)},J.JMember{"metadata",metadata_value(D.metadata(catalog,Inv.ItemKey{id,""}))}])))
        definitions_rows(catalog,rest)

def definitions_loaded(result:Result<&2,&2,String,D.Catalog>) -> IO(Unit):
  match result:
    case Fail{message}: IO.die(Unit,1,message)
    case Done{+catalog}:
      do IO<Unit>:
        IO.print(J.encode(L.obj([J.JMember{"count",L.uint(D.count(catalog))}])))
        definitions_rows(catalog,D.all(catalog))

def definitions(path:String) -> IO(Unit):
  IO.bind(Result<&2,&2,String,D.Catalog>,Unit,Catalog.load(path),definitions_loaded)

def arguments(args:List<String>) -> IO(Unit):
  match args:
    case ["cases"]: cases()
    case ["hits"]: hits(hit_points(),0)
    case ["swap-keys"]: swap_cases()
    case ["definitions",path]: definitions(path)
    case _: IO.die(Unit,2,"inventory-screen requires cases, hits or definitions PATH")

def main_arguments(argv:List<String>) -> IO(Unit):
  match argv:
    case exe <> rest: arguments(rest)
    case _: IO.die(Unit,2,"missing inventory-screen arguments")

def main() -> IO(Unit):
  IO.bind(List<String>,Unit,IO.args(),main_arguments)
