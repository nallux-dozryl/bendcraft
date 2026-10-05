import Base
import ./player_cooking_menu.bend as Menu
import ./player_inventory.bend as I
import ./player_inventory_screen.bend as Screen
import ./player_inventory_return.bend as R
import ./player_cooking_menu_transfer.bend as Move
import ./inventory.bend as Inv
import ./player_hud.bend as H
import ./client_render.bend as Render
import ./png.bend as P
import ./nbt.bend as N
import ./cooking_recipe.bend as K
import ./f64.bend as F

# quit is0 for ordinary use,1 for OS close deferred behind a pending action,
# and2 while the authenticated MenuClose is pending. No close deletes a stack.
# Only UI metadata is retained. All39 visible cells and the carried item come
# from the correlated authoritative cooking/player snapshot on each frame.
type Point is Data:
  Point{x:U32,y:U32}
type State is Data:
  State{menu:U32,open:Bool,focused:Bool,captured:Bool,shift:U32,keys:U32,
    buttons:U32,pending:Bool,hover:Maybe<&2,U32>,viewport:Screen.Viewport,point:Maybe<&2,Point>,message:String,quit:U32}
type Intent is Data:
  ReleaseControls{}
  Capture{enabled:Bool}
  Quit{}
  Request{action:Menu.Action}
type Update is Data:
  Update{state:State,intents:List<&2,Intent>,consumed:Bool}
type Layout is Data:
  Layout{left:U32,top:U32,visible:Bool}
type View is Data:
  View{slots:List<&2,H.DrawSlot>,carried:H.DrawSlot,caption:String,
    lit:U32,burn:U32,labels:List<&2,String>,available:Bool}

def new() -> State: State{0,False{},True{},False{},0,0,0,False{},None{},Screen.Viewport{0,0,0,0},None{},"",0}
def opened_handle(handle:Menu.Handle,opened:Bool) -> Bool:
  match handle:
    case Menu.Closed{}: False{}
    case Menu.Furnace{menu,peer,position,block,kind,token}: opened
def opened(snapshot:Menu.Snapshot) -> Bool:
  Menu.Snapshot{handle,furnace,I.MenuSnapshot{saved,craft,carried,result,opened,revision}} = snapshot
  opened_handle(handle,opened)
def handle_menu(handle:Menu.Handle) -> U32:
  match handle:
    case Menu.Closed{}: 0
    case Menu.Furnace{id,peer,position,block,kind,token}: id
def menu(snapshot:Menu.Snapshot) -> U32:
  Menu.Snapshot{handle,furnace,inventory} = snapshot
  handle_menu(handle)

def layout(+viewport:Screen.Viewport) -> Layout:
  Screen.Viewport{+width,+height,nw,nh} = viewport
  Layout{U32.div(U32.sub(U32.max(width,176),176),2),U32.div(U32.sub(U32.max(height,166),166),2),
    Screen.viewport_valid(viewport) && U32.is_ge(width,176) && U32.is_ge(height,166)}
def same_viewport(a:Screen.Viewport,b:Screen.Viewport) -> Bool:
  Screen.Viewport{w,h,nw,nh} = a
  Screen.Viewport{u,v,nu,nv} = b
  U32.is_eq(w,u) && U32.is_eq(h,v) && U32.is_eq(nw,nu) && U32.is_eq(nh,nv)
def geometry(+state:State,+viewport:Screen.Viewport) -> State:
  State{menu,open,focused,captured,shift,keys,buttons,pending,hover,previous,point,message,quit} = state
  +same = same_viewport(previous,viewport)
  State{menu,open,focused,captured,shift,keys,buttons,pending,N.choose(Maybe<&2,U32>,hover,None{},same),viewport,N.choose(Maybe<&2,Point>,point,None{},same),message,quit}
# Literal positions are the actual pinned FurnaceMenu slot observations.
def slot_position(+index:U32) -> Point:
  N.choose(Point,Point{56,17},N.choose(Point,Point{56,53},N.choose(Point,Point{116,35},
    N.choose(Point,Point{U32.add(8,U32.mul(U32.mod(U32.sub(index,3),9),18)),U32.add(84,U32.mul(U32.div(U32.sub(index,3),9),18))},
      Point{U32.add(8,U32.mul(U32.sub(index,30),18)),142},U32.is_lt(index,30)),U32.is_eq(index,2)),U32.is_eq(index,1)),U32.is_zero(index))
def at_position(+x:U32,+y:U32,value:Point) -> Bool:
  Point{left,top} = value
  H.inside(x,y,left,top,16,16)
def logical_hit(left:Nat,+index:U32,+x:U32,+y:U32) -> Maybe<&2,U32>:
  match left:
    case 0n: None{}
    case 1n+n: N.choose(Maybe<&2,U32>,Some{index},logical_hit(n,U32.add(index,1),x,y),at_position(x,y,slot_position(index)))
def shown(value:Layout) -> Bool:
  Layout{left,top,visible} = value
  visible
def hit_layout(+viewport:Screen.Viewport,+x:U32,+y:U32,value:Layout) -> Maybe<&2,U32>:
  Screen.Viewport{w,h,nw,nh} = viewport
  Layout{left,top,visible} = value
  logical_hit(39n,0,U32.sub(U32.div(U32.mul(x,w),nw),left),U32.sub(U32.div(U32.mul(y,h),nh),top))
def hit_valid(allowed:Bool,+viewport:Screen.Viewport,+x:U32,+y:U32) -> Maybe<&2,U32>:
  match allowed:
    case False{}: None{}
    case True{}: hit_layout(viewport,x,y,layout(viewport))
def hit(+viewport:Screen.Viewport,+x:U32,+y:U32) -> Maybe<&2,U32>:
  Screen.Viewport{w,h,+nw,+nh} = viewport
  hit_valid(shown(layout(viewport)) && U32.is_lt(x,nw) && U32.is_lt(y,nh),viewport,x,y)
def is_open(state:State) -> Bool:
  State{menu,open,focused,captured,shift,keys,buttons,pending,hover,viewport,point,message,quit} = state
  open
def active(state:State) -> Bool:
  State{menu,open,focused,captured,shift,keys,buttons,pending,hover,viewport,point,message,quit} = state
  open || pending || U32.is_gt(quit,0)
def menu_id(state:State) -> U32:
  State{menu,open,focused,captured,shift,keys,buttons,pending,hover,viewport,point,message,quit} = state
  menu
def quitting(+state:State,+quit:U32) -> State:
  State{menu,open,focused,captured,shift,keys,buttons,pending,hover,viewport,point,message,previous} = state
  State{menu,open,focused,captured,shift,keys,buttons,pending,hover,viewport,point,message,quit}
def observed(+state:State,+snapshot:Menu.Snapshot) -> State:
  State{+old,was,focused,captured,shift,keys,buttons,pending,hover,viewport,point,message,quit} = state
  +same = opened(snapshot) && U32.is_eq(menu(snapshot),old)
  State{menu(snapshot),opened(snapshot),focused,captured,shift,keys,buttons,pending,
    N.choose(Maybe<&2,U32>,hover,None{},same),viewport,N.choose(Maybe<&2,Point>,point,None{},same),message,quit}
def completed_state(+state:State,+snapshot:Menu.Snapshot,error:String) -> State:
  State{+old,+was,+focused,+captured,+shift,+keys,+buttons,pending,+hover,+viewport,+point,message,quit} = state
  +open = opened(snapshot)
  +same = was && open && U32.is_eq(old,menu(snapshot))
  State{menu(snapshot),open,focused,N.choose(Bool,captured,False{},same),N.choose(U32,shift,0,same),N.choose(U32,keys,0,same),
    N.choose(U32,buttons,0,same),False{},N.choose(Maybe<&2,U32>,hover,None{},same),viewport,N.choose(Maybe<&2,Point>,point,None{},same),error,0}
def normal_completed_intents(+state:State,+snapshot:Menu.Snapshot) -> List<&2,Intent>:
  State{menu,+was,+focused,captured,shift,keys,buttons,pending,hover,viewport,point,message,quit} = state
  +open = opened(snapshot)
  N.choose(List<&2,Intent>,[ReleaseControls{},Capture{False{}}],N.choose(List<&2,Intent>,[Capture{True{}}],[],focused && was && Bool.not(open)),open && Bool.not(was))
def requested(+state:State,action:Menu.Action) -> Update:
  State{menu,open,focused,captured,shift,keys,buttons,waiting,hover,viewport,point,message,quit} = state
  Update{State{menu,open,focused,captured,shift,keys,buttons,True{},hover,viewport,point,"",quit},[Request{action}],True{}}
def quit_completed(quit:U32,+next:State,+open:Bool) -> Update:
  match quit:
    case 0: Update{next,[],True{}}
    case 1: N.choose(Update,requested(quitting(next,2),Menu.MenuClose{menu_id(next)}),Update{next,[Quit{}],True{}},open)
    case _: Update{next,N.choose(List<&2,Intent>,[],[Quit{}],open),True{}}
def completion(quit:U32,+previous:State,+snapshot:Menu.Snapshot,+next:State) -> Update:
  match quit:
    case 0: Update{next,normal_completed_intents(previous,snapshot),True{}}
    case _: quit_completed(quit,next,opened(snapshot))
def completed(+state:State,+reply:Menu.Reply) -> Update:
  State{old,was,focused,captured,shift,keys,buttons,pending,hover,viewport,point,message,quit} = state
  Menu.Reply{accepted,+error,+snapshot,effects} = reply
  completion(quit,state,snapshot,completed_state(state,snapshot,error))
# Completion is invoked only after authenticated epoch/sequence correlation.
# The presenter must freshly query native focus before executing CaptureTrue.
def focus(+state:State,+focused:Bool,+captured:Bool) -> Update:
  State{menu,+open,was,held,shift,keys,buttons,pending,hover,viewport,point,message,quit} = state
  N.choose(Update,Update{State{menu,open,False{},False{},0,0,0,pending,None{},viewport,None{},message,quit},
    N.choose(List<&2,Intent>,[ReleaseControls{},Capture{False{}}],[],was || held || captured),open},
    Update{State{menu,open,True{},captured,shift,keys,buttons,pending,hover,viewport,point,message,quit},[],False{}},Bool.not(focused))
def hovered(+state:State,hover:Maybe<&2,U32>) -> State:
  State{menu,open,focused,captured,shift,keys,buttons,pending,old,viewport,point,message,quit} = state
  State{menu,open,focused,captured,shift,keys,buttons,pending,hover,viewport,point,message,quit}
def bit(+bits:U32,+mask:U32,+down:Bool) -> U32:
  N.choose(U32,U32.or(bits,mask),U32.and(bits,U32.not(mask)),down)
def key_mask(+code:U32) -> U32:
  N.choose(U32,1,N.choose(U32,2,0,U32.is_eq(code,69) || U32.is_eq(code,101)),U32.is_eq(code,27))
def shift_mask(+code:U32) -> U32:
  N.choose(U32,1,N.choose(U32,2,0,U32.is_eq(code,65596)),U32.is_eq(code,65592))
def keyed(+state:State,+code:U32,+down:Bool) -> State:
  State{menu,open,focused,captured,shift,keys,buttons,pending,hover,viewport,point,message,quit} = state
  State{menu,open,focused,captured,bit(shift,shift_mask(code),down),bit(keys,key_mask(code),down),buttons,pending,hover,viewport,point,message,quit}
def key_allowed(allowed:Bool,+state:State,+code:U32,+down:Bool) -> Update:
  match allowed:
    case False{}: Update{keyed(state,code,down),[],is_open(state)}
    case True{}: requested(keyed(state,code,down),Menu.MenuClose{menu_id(state)})
def keyboard(+state:State,+code:U32,+down:Bool) -> Update:
  State{menu,open,focused,captured,shift,keys,buttons,waiting,hover,viewport,point,message,quit} = state
  key_allowed(open && focused && Bool.not(waiting) && down && U32.is_gt(key_mask(code),0) && U32.is_zero(U32.and(keys,key_mask(code))),state,code,down)
def buttoned(+state:State,+button:U32,+down:Bool,+target:Maybe<&2,U32>) -> State:
  State{menu,open,focused,captured,shift,keys,buttons,pending,hover,viewport,point,message,quit} = state
  State{menu,open,focused,captured,shift,keys,bit(buttons,U32.shln(1,U32.to_nat(button)),down),pending,target,viewport,point,message,quit}
def mouse_target(target:Maybe<&2,U32>,+state:State,+button:U32) -> Update:
  match target:
    case None{}: Update{state,[],is_open(state)}
    case Some{+index}:
      State{+menu,open,focused,captured,shift,keys,buttons,pending,hover,viewport,point,message,quit} = state
      requested(state,N.choose(Menu.Action,Menu.MenuQuickMove{menu,index},Menu.MenuPickup{menu,index,button},U32.is_gt(shift,0)))
def mouse_allowed(allowed:Bool,+state:State,+button:U32,+down:Bool,+target:Maybe<&2,U32>) -> Update:
  match allowed:
    case False{}: Update{buttoned(state,button,down,target),[],True{}}
    case True{}: mouse_target(target,buttoned(state,button,down,target),button)
def mouse_known(+state:State,+viewport:Screen.Viewport,+x:U32,+y:U32,+button:U32,+down:Bool) -> Update:
  State{menu,open,focused,captured,shift,keys,+buttons,waiting,hover,previous,point,message,quit} = state
  mouse_allowed(open && focused && Bool.not(captured) && Bool.not(waiting) && down && U32.is_lt(button,2) &&
    U32.is_zero(U32.and(buttons,U32.shln(1,U32.to_nat(U32.min(button,1))))),state,U32.min(button,1),down,hit(viewport,x,y))
def mouse_valid(valid:Bool,+state:State,+viewport:Screen.Viewport,+x:U32,+y:U32,+button:U32,+down:Bool) -> Update:
  match valid:
    case False{}: Update{state,[],True{}}
    case True{}: mouse_known(state,viewport,x,y,button,down)
def mouse(+state:State,+viewport:Screen.Viewport,+x:U32,+y:U32,+button:U32,+down:Bool) -> Update:
  mouse_valid(U32.is_lt(button,2),state,viewport,x,y,button,down)
def pointer_allowed(allowed:Bool,+state:State,+x:U32,+y:U32) -> State:
  State{menu,open,focused,captured,shift,keys,buttons,pending,hover,viewport,point,message,quit} = state
  State{menu,open,focused,captured,shift,keys,buttons,pending,hover,viewport,N.choose(Maybe<&2,Point>,Some{Point{x,y}},None{},allowed),message,quit}
def pointed(+state:State,+viewport:Screen.Viewport,+x:U32,+y:U32) -> State:
  Screen.Viewport{w,h,nw,nh} = viewport
  pointer_allowed(Screen.viewport_valid(viewport) && U32.is_lt(x,nw) && U32.is_lt(y,nh),state,x,y)
def close_requested(+state:State) -> Update:
  State{menu,open,focused,captured,shift,keys,buttons,pending,hover,viewport,point,message,+quit} = state
  N.choose(Update,Update{quitting(state,N.choose(U32,2,1,U32.is_eq(quit,2))),[],True{}},
    requested(quitting(state,2),Menu.MenuClose{menu}),pending)
def event_open(+state:State,+viewport:Screen.Viewport,input:Event) -> Update:
  State{menu,open,focused,captured,shift,keys,buttons,pending,hover,previous,point,message,quit} = state
  match input:
    case Close{}: close_requested(state)
    case Key{code,down}: keyboard(state,code,down)
    case Move{+x,+y}: Update{pointed(hovered(state,hit(viewport,x,y)),viewport,x,y),[],open}
    case Mouse{+x,+y,button,down}: mouse(pointed(state,viewport,x,y),viewport,x,y,button,down)
    case _: Update{state,[],open}
def event_allowed(allowed:Bool,+state:State,+viewport:Screen.Viewport,input:Event) -> Update:
  match allowed:
    case False{}: Update{state,[],False{}}
    case True{}: event_open(state,viewport,input)
def event(+state:State,+viewport:Screen.Viewport,input:Event) -> Update:
  event_allowed(is_open(state),state,viewport,input)
def appended_focus(intents:List<&2,Intent>,result:Update) -> Update:
  Update{state,following,consumed} = result
  Update{state,List.append(&2,Intent,intents,following),consumed}
def close_focus(+viewport:Screen.Viewport,result:Update) -> Update:
  Update{state,intents,consumed} = result
  appended_focus(intents,event(geometry(state,viewport),viewport,Close{}))
def focused_event(input:Event,+viewport:Screen.Viewport,+focused:Bool,result:Update) -> Update:
  match input:
    case Close{}: close_focus(viewport,result)
    case other:
      Update{+next,intents,consumed} = result
      N.choose(Update,event(geometry(next,viewport),viewport,other),Update{next,intents,consumed},focused)
def step(+state:State,viewport:Screen.Viewport,input:Event,+focused:Bool,+captured:Bool) -> Update:
  focused_event(input,viewport,focused,focus(state,focused,captured))

# Presenter supplies actual resolved resource textures. Missing bindings remain
# the existing explicit missing-icon mark, not invented furnace/fuel imagery.
def prepare_slots(left:Nat,+index:U32,+slots:List<&2,Inv.Slot>,+rows:List<&2,Screen.ItemIcon>,+icons:H.Icons) -> List<&2,H.DrawSlot>:
  match left:
    case 0n: []
    case 1n+n: Screen.draw_slot(R.at(slots,U32.to_nat(Move.backing(index))),rows,icons) <> prepare_slots(n,U32.add(index,1),slots,rows,icons)
def combined(slots:K.FurnaceSlots,player:List<&2,Inv.Slot>) -> List<&2,Inv.Slot>:
  K.FurnaceSlots{input,fuel,output} = slots
  input <> fuel <> output <> player
def slot_label(slot:Inv.Slot) -> String:
  match slot:
    case Inv.InvEmpty{}: ""
    case Inv.InvStack{Inv.ItemKey{id,components},count}: id ++ " " ++ U32.show(count)
def prepare_labels(left:Nat,+index:U32,+slots:List<&2,Inv.Slot>) -> List<&2,String>:
  match left:
    case 0n: []
    case 1n+n: slot_label(R.at(slots,U32.to_nat(Move.backing(index)))) <> prepare_labels(n,U32.add(index,1),slots)
def label_at(labels:List<&2,String>,index:Nat) -> String:
  match labels index:
    case Nil{} _: ""
    case head <> rest 0n: head
    case head <> rest 1n+n: label_at(rest,n)
def hover_label(hover:Maybe<&2,U32>,labels:List<&2,String>) -> String:
  match hover:
    case None{}: ""
    case Some{index}: label_at(labels,U32.to_nat(index))
def caption(kind:K.CookingKind) -> String:
  match kind:
    case K.Blasting{}: "BLAST FURNACE"
    case K.Smoking{}: "SMOKER"
    case _: "FURNACE"
def progress_ratio(+ratio:F32,extent:U32) -> U32:
  F32.to_u32(F32.mul(N.choose(F32,0.0,N.choose(F32,1.0,ratio,F.is_gt(F.from_f32(ratio),F.from_u32(1))),F.is_lt(F.from_f32(ratio),F.from_u32(0))),U32.to_f32(extent)))
def progress_valid(allowed:Bool,+amount:U32,+total:U32,extent:U32) -> U32:
  match allowed:
    case False{}: 0
    case True{}: progress_ratio(F32.div(F.to_f32(F.from_i32(amount)),F.to_f32(F.from_i32(total))),extent)
def progress(+amount:U32,+total:U32,+extent:U32) -> U32:
  progress_valid(U32.is_ne(amount,0) && U32.is_ne(total,0),amount,total,extent)
def prepared_view(furnace:Maybe<&2,Menu.FurnaceView>,+inventory:I.MenuSnapshot,+rows:List<&2,Screen.ItemIcon>,+icons:H.Icons) -> View:
  match furnace:
    case None{}:
      I.MenuSnapshot{saved,craft,carried,result,opened,revision} = inventory
      View{prepare_slots(39n,0,combined(K.FurnaceSlots{Inv.InvEmpty{},Inv.InvEmpty{},Inv.InvEmpty{}},I.menu_slots(inventory)),rows,icons),
        Screen.draw_slot(carried,rows,icons),"FURNACE UNAVAILABLE",0,0,
        List.append(&2,String,["UNAVAILABLE","UNAVAILABLE","UNAVAILABLE"],List.drop(&2,String,prepare_labels(39n,0,combined(K.FurnaceSlots{Inv.InvEmpty{},Inv.InvEmpty{},Inv.InvEmpty{}},I.menu_slots(inventory))),3n)),False{}}
    case Some{Menu.FurnaceView{kind,+slots,r,+t,s,c}}:
      I.MenuSnapshot{saved,craft,carried,result,opened,revision} = inventory
      View{prepare_slots(39n,0,combined(slots,I.menu_slots(inventory)),rows,icons),
        Screen.draw_slot(carried,rows,icons),caption(kind),progress(r,N.choose(U32,200,t,U32.is_zero(t)),13),progress(s,c,24),prepare_labels(39n,0,combined(slots,I.menu_slots(inventory))),True{}}
def prepared_furnace(snapshot:Menu.Snapshot,+rows:List<&2,Screen.ItemIcon>,+icons:H.Icons) -> View:
  Menu.Snapshot{handle,furnace,inventory} = snapshot
  prepared_view(furnace,inventory,rows,icons)

def prepare(snapshot:Menu.Snapshot,rows:List<&2,Screen.ItemIcon>,icons:H.Icons) -> View:
  prepared_furnace(snapshot,rows,icons)
def stack_position(+view:View,+index:U32,+x:U32,+y:U32,position:Point) -> U32:
  View{slots,carried,caption,lit,burn,labels,available} = view
  Point{+left,+top} = position
  N.choose(U32,Screen.result_paint(None{},U32.sub(x,left),U32.sub(y,top),16,4287335307),
    Screen.stack_pixel(H.at_slot(slots,U32.to_nat(index)),U32.sub(x,left),U32.sub(y,top),16,4287335307),Bool.not(available) && U32.is_lt(index,3))
def stack_hit(+view:View,+x:U32,+y:U32,target:Maybe<&2,U32>) -> U32:
  match target:
    case None{}: 4290822336
    case Some{+index}: stack_position(view,index,x,y,slot_position(index))
def content(+view:View,+x:U32,+y:U32) -> U32:
  View{slots,carried,caption,+lit,+burn,labels,available} = view
  N.choose(U32,4282400832,N.choose(U32,4294967040,N.choose(U32,4293454056,
    stack_hit(view,x,y,logical_hit(39n,0,x,y)),
    H.inside(x,y,79,34,burn,16)),
    H.inside(x,y,56,U32.sub(49,lit),14,lit)),
    Screen.label_pixel(caption,x,y,8,6) || Screen.label_pixel("INVENTORY",x,y,8,73))
def carried_position(+carried:H.DrawSlot,+viewport:Screen.Viewport,+x:U32,+y:U32,+world:U32,point:Point) -> U32:
  Screen.Viewport{+w,+h,+nw,+nh} = viewport
  Point{px,py} = point
  +left = U32.sub(U32.max(8,U32.div(U32.mul(px,w),nw)),8)
  +top = U32.sub(U32.max(8,U32.div(U32.mul(py,h),nh)),8)
  N.choose(U32,Screen.stack_pixel(carried,U32.sub(x,left),U32.sub(y,top),16,world),world,H.inside(x,y,left,top,16,16))
def carried_pixel(point:Maybe<&2,Point>,+carried:H.DrawSlot,+viewport:Screen.Viewport,+x:U32,+y:U32,+world:U32) -> U32:
  match point carried:
    case None{} _: world
    case _ H.Empty{}: world
    case Some{value} _: carried_position(carried,viewport,x,y,world,value)
def notice(+state:State,labels:List<&2,String>) -> String:
  State{menu,open,focused,captured,shift,keys,buttons,pending,hover,viewport,point,+message,quit} = state
  N.choose(String,"WAITING",N.choose(String,"MAKE INVENTORY SPACE TO CLOSE",N.choose(String,"ACTION REFUSED",hover_label(hover,labels),Bool.not(String.is_empty(message))),
    String.eq(message,"cooking-menu:close-needs-real-drop-owner")),pending)
def panel_pixel(+view:View,+state:State,+viewport:Screen.Viewport,+x:U32,+y:U32,+world:U32,value:Layout) -> U32:
  View{slots,carried,caption,lit,burn,labels,available} = view
  State{menu,open,focused,captured,shift,keys,buttons,pending,hover,previous,point,message,quit} = state
  Layout{+left,+top,shown} = value
  carried_pixel(point,carried,viewport,x,y,N.choose(U32,4291559424,N.choose(U32,content(view,U32.sub(x,left),U32.sub(y,top)),H.darken(world),shown && H.inside(x,y,left,top,176,166)),H.inside(x,y,U32.add(left,8),U32.add(top,159),160,5) && Screen.label_pixel(notice(state,labels),x,y,U32.add(left,8),U32.add(top,159))))
def pixel_visible(visible:Bool,+view:View,+state:State,+viewport:Screen.Viewport,+x:U32,+y:U32,+world:U32) -> U32:
  match visible:
    case False{}: N.choose(U32,4294967295,H.darken(world),Screen.label_pixel("RESIZE WINDOW",x,y,4,4))
    case True{}: panel_pixel(view,state,viewport,x,y,world,layout(viewport))
def pixel(+view:View,+state:State,+viewport:Screen.Viewport,+x:U32,+y:U32,+world:U32) -> U32:
  pixel_visible(shown(layout(viewport)),view,state,viewport,x,y,world)
def native_pixel(+view:View,+state:State,+viewport:Screen.Viewport,+x:U32,+y:U32,world:U32) -> U32:
  Screen.Viewport{w,h,nw,nh} = viewport
  pixel(view,state,viewport,U32.div(U32.mul(x,w),nw),U32.div(U32.mul(y,h),nh),world)
def panel_touched(+viewport:Screen.Viewport,+x:U32,+y:U32,+side:U32,value:Layout) -> Bool:
  Screen.Viewport{+w,+h,+nw,+nh} = viewport
  Layout{left,top,visible} = value
  H.overlaps(x,y,side,U32.div(U32.mul(left,nw),w),U32.div(U32.mul(top,nh),h),
    U32.add(U32.div(U32.mul(176,nw),w),2),U32.add(U32.div(U32.mul(166,nh),h),2))
def cursor_touched(+viewport:Screen.Viewport,+x:U32,+y:U32,+side:U32,point:Maybe<&2,Point>) -> Bool:
  Screen.Viewport{w,h,nw,nh} = viewport
  match point:
    case None{}: False{}
    case Some{Point{px,py}}:
      +sx = U32.add(U32.div(U32.mul(18,nw),w),2)
      +sy = U32.add(U32.div(U32.mul(18,nh),h),2)
      H.overlaps(x,y,side,U32.sub(U32.max(px,sx),sx),U32.sub(U32.max(py,sy),sy),U32.mul(sx,2),U32.mul(sy,2))
def touched_visible(visible:Bool,+state:State,+viewport:Screen.Viewport,+x:U32,+y:U32,+side:U32) -> Bool:
  match visible:
    case False{}:
      Screen.Viewport{w,h,nw,nh} = viewport
      H.overlaps(x,y,side,0,0,U32.add(U32.div(U32.mul(60,nw),w),2),U32.add(U32.div(U32.mul(12,nh),h),2))
    case True{}:
      State{menu,open,focused,captured,shift,keys,buttons,pending,hover,previous,point,message,quit} = state
      panel_touched(viewport,x,y,side,layout(viewport)) || cursor_touched(viewport,x,y,side,point)
def touched(+state:State,+viewport:Screen.Viewport,+x:U32,+y:U32,+side:U32) -> Bool:
  touched_visible(shown(layout(viewport)),state,viewport,x,y,side)
def overlay(left:Nat,image:Image,+view:View,+state:State,+viewport:Screen.Viewport,+x:U32,+y:U32,+side:U32,active:Bool) -> Image:
  match left image active:
    case _ _ False{}: Screen.dim(image)
    case 0n Pix{color} True{}: Pix{native_pixel(view,state,viewport,x,y,color)}
    case 0n Qua{tl,tr,bl,br} True{}: Pix{native_pixel(view,state,viewport,x,y,Render.pixel_at(0n,Qua{tl,tr,bl,br},0,0,1))}
    case 1n+ +n Pix{+color} True{}:
      +half = U32.div(side,2)
      Qua{overlay(n,Pix{color},view,state,viewport,x,y,half,touched(state,viewport,x,y,half)),overlay(n,Pix{color},view,state,viewport,U32.add(x,half),y,half,touched(state,viewport,U32.add(x,half),y,half)),
        overlay(n,Pix{color},view,state,viewport,x,U32.add(y,half),half,touched(state,viewport,x,U32.add(y,half),half)),overlay(n,Pix{color},view,state,viewport,U32.add(x,half),U32.add(y,half),half,touched(state,viewport,U32.add(x,half),U32.add(y,half),half))}
    case 1n+ +n Qua{tl,tr,bl,br} True{}:
      +half = U32.div(side,2)
      Qua{overlay(n,tl,view,state,viewport,x,y,half,touched(state,viewport,x,y,half)),overlay(n,tr,view,state,viewport,U32.add(x,half),y,half,touched(state,viewport,U32.add(x,half),y,half)),
        overlay(n,bl,view,state,viewport,x,U32.add(y,half),half,touched(state,viewport,x,U32.add(y,half),half)),overlay(n,br,view,state,viewport,U32.add(x,half),U32.add(y,half),half,touched(state,viewport,U32.add(x,half),U32.add(y,half),half))}
def draw_frame(image:Image,view:View,state:State,+viewport:Screen.Viewport) -> Image:
  Screen.Viewport{w,h,nw,nh} = viewport
  +depth = P.array_depth(13n,U32.max(nw,nh),1)
  overlay(depth,image,view,state,viewport,0,0,U32.shln(1,depth),True{})
def draw_active(allowed:Bool,image:Image,view:View,state:State,viewport:Screen.Viewport) -> Image:
  match allowed:
    case False{}: image
    case True{}: draw_frame(image,view,state,viewport)
def draw_native(image:Image,view:View,+state:State,+viewport:Screen.Viewport) -> Image:
  State{menu,open,focused,captured,shift,keys,buttons,pending,hover,previous,point,message,quit} = state
  draw_active(open && Screen.viewport_valid(viewport),image,view,state,viewport)
