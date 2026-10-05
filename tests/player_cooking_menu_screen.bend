import Base
import ../src/player_cooking_menu_screen.bend as S
import ../src/player_cooking_menu.bend as Menu
import ../src/player_inventory_screen.bend as InventoryScreen
import ../src/player_inventory.bend as I
import ../src/inventory.bend as Inv
import ../src/cooking_recipe.bend as K
import ../src/core.bend as C
import ../src/json.bend as J
import ../src/live.bend as L

def empty(left:Nat) -> List<&2,Inv.Slot>:
  match left:
    case 0n: []
    case 1n+n: Inv.InvEmpty{} <> empty(n)
def carried(open:Bool) -> Inv.Slot:
  match open:
    case False{}: Inv.InvEmpty{}
    case True{}: Inv.InvStack{Inv.ItemKey{"minecraft:stone",""},3}
def inventory(+open:Bool) -> I.MenuSnapshot:
  I.MenuSnapshot{I.Persisted{I.Snapshot{7,empty(36n),I.Abilities{False{},False{}}},empty(7n),I.Status{True{},True{},False{},2147483648,2143289345}},empty(4n),carried(open),None{},open,19n}
def N_handle(open:Bool) -> Menu.Handle:
  match open:
    case False{}: Menu.Closed{}
    case True{}: Menu.Furnace{5,7,C.Position{"minecraft:overworld",0,0,0},"minecraft:furnace",K.Smelting{},2n}
def furnace_view(open:Bool) -> Maybe<&2,Menu.FurnaceView>:
  match open:
    case False{}: None{}
    case True{}: Some{Menu.FurnaceView{K.Smelting{},K.FurnaceSlots{Inv.InvEmpty{},Inv.InvEmpty{},Inv.InvEmpty{}},70,1600,80,200}}
def snapshot(+open:Bool) -> Menu.Snapshot:
  Menu.Snapshot{N_handle(open),furnace_view(open),inventory(open)}
def viewport() -> InventoryScreen.Viewport: InventoryScreen.Viewport{320,180,1280,720}
def state(shift:U32,buttons:U32,pending:Bool) -> S.State:
  S.State{5,True{},True{},False{},shift,0,buttons,pending,Some{0},viewport(),Some{S.Point{512,100}},"",0}
def string(action:Menu.Action) -> String:
  match action:
    case Menu.MenuInspect{menu}: "inspect"
    case Menu.MenuClose{menu}: "close"
    case Menu.MenuPickup{menu,index,button}: "pickup: " ++ U32.show(index) ++ ":" ++ U32.show(button)
    case Menu.MenuQuickMove{menu,index}: "quick: " ++ U32.show(index)
def intents(values:List<&2,S.Intent>) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case S.ReleaseControls{} <> rest: L.text("release") <> intents(rest)
    case S.Capture{enabled} <> rest: L.text("capture:" ++ U32.show(Bool.to_u32(enabled))) <> intents(rest)
    case S.Quit{} <> rest: L.text("quit") <> intents(rest)
    case S.Request{action} <> rest: L.text(string(action)) <> intents(rest)
def report(label:String,update:S.Update) -> IO(Unit):
  S.Update{S.State{menu,open,focused,captured,shift,keys,buttons,pending,hover,vp,point,message,quit},requests,consumed} = update
  IO.print(J.encode(L.obj([J.JMember{"id",L.text(label)},J.JMember{"menu",L.uint(menu)},J.JMember{"open",L.boolean(open)},
    J.JMember{"focused",L.boolean(focused)},J.JMember{"captured",L.boolean(captured)},J.JMember{"shift",L.uint(shift)},
    J.JMember{"buttons",L.uint(buttons)},J.JMember{"quit",L.uint(quit)},J.JMember{"pending",L.boolean(pending)},J.JMember{"consumed",L.boolean(consumed)},
    J.JMember{"intents",J.JArray{intents(requests)}}])))
def click_after_reply(result:S.Update) -> S.Update:
  S.Update{state,requests,consumed} = result
  S.step(state,viewport(),Mouse{512,100,0,True{}},True{},False{})
def hovered_before_resize(result:S.Update) -> S.Update:
  S.Update{state,requests,consumed} = result
  S.step(state,InventoryScreen.Viewport{640,360,1280,720},Key{65592,True{}},True{},False{})
def close_after_reply(result:S.Update,+open:Bool,+accepted:Bool) -> S.Update:
  S.Update{state,intents,consumed} = result
  S.completed(state,Menu.Reply{accepted,"",snapshot(open),[]})
def closed_state() -> S.State:
  S.State{0,False{},True{},True{},0,0,0,False{},None{},viewport(),None{},"",0}
def progress(label:String,amount:U32,total:U32,extent:U32) -> IO(Unit):
  IO.print(J.encode(L.obj([J.JMember{"id",L.text(label)},J.JMember{"progress",L.uint(S.progress(amount,total,extent))},J.JMember{"intents",J.JArray{[]}}])))
def run() -> IO(Unit):
  do IO<Unit>:
    report("left-pickup",S.step(state(0,0,False{}),viewport(),Mouse{512,100,0,True{}},True{},False{}))
    report("right-pickup",S.step(state(0,0,False{}),viewport(),Mouse{512,100,1,True{}},True{},False{}))
    report("shift-quick",S.step(state(1,0,False{}),viewport(),Mouse{512,100,0,True{}},True{},False{}))
    report("pending-suppresses",S.step(state(1,0,True{}),viewport(),Mouse{512,100,0,True{}},True{},False{}))
    report("hold-suppresses",S.step(state(1,1,False{}),viewport(),Mouse{512,100,0,True{}},True{},False{}))
    report("same-open-shift-kept",S.completed(state(3,0,True{}),Menu.Reply{True{},"",snapshot(True{}),[]}))
    report("second-held-shift",click_after_reply(S.completed(state(3,0,True{}),Menu.Reply{True{},"",snapshot(True{}),[]})))
    report("focus-loss",S.step(state(3,3,True{}),viewport(),Key{27,True{}},False{},False{}))
    report("close",S.step(state(1,0,False{}),viewport(),Key{27,True{}},True{},False{}))
    report("close-refused",S.completed(state(1,0,True{}),Menu.Reply{False{},"cooking-menu:close-needs-real-drop-owner",snapshot(True{}),[]}))
    report("closed-capture",S.completed(state(1,0,True{}),Menu.Reply{True{},"",snapshot(False{}),[]}))
    report("resize-invalidates-hover",hovered_before_resize(S.step(state(0,0,False{}),viewport(),Move{512,100},True{},False{})))
    report("os-close",S.step(state(1,0,False{}),viewport(),Close{},True{},False{}))
    report("os-close-ack",close_after_reply(S.step(state(1,0,False{}),viewport(),Close{},True{},False{}),False{},True{}))
    report("os-close-refused",close_after_reply(S.step(state(1,0,False{}),viewport(),Close{},True{},False{}),True{},False{}))
    report("os-close-pending",S.step(state(1,0,True{}),viewport(),Close{},True{},False{}))
    report("os-close-followup",close_after_reply(S.step(state(1,0,True{}),viewport(),Close{},True{},False{}),True{},True{}))
    report("os-close-followup-ack",close_after_reply(close_after_reply(S.step(state(1,0,True{}),viewport(),Close{},True{},False{}),True{},True{}),False{},True{}))
    report("os-close-unfocused",S.step(state(1,0,False{}),viewport(),Close{},False{},False{}))
    report("closed-mouse-world",S.step(closed_state(),viewport(),Mouse{512,100,0,True{}},True{},True{}))
    report("too-small-suppresses",S.step(state(1,0,False{}),InventoryScreen.Viewport{160,120,640,480},Mouse{220,64,0,True{}},True{},False{}))
    report("closed-close-world",S.step(closed_state(),viewport(),Close{},True{},True{}))
    progress("progress-third",1,3,24)
    progress("progress-negative",4294967295,10,24)
    progress("progress-both-negative",4294967295,4294967294,24)
    progress("progress-minimum",2147483648,2147483648,24)
    progress("progress-zero-duration",1,0,24)
    progress("progress-lit-fallback",50,200,13)

def main() -> IO(Unit): run()
