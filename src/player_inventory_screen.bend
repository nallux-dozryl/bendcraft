import Base
import ./player_inventory.bend as I
import ./inventory.bend as Inv
import ./player_item_definitions.bend as D
import ./player_hud.bend as H
import ./client_render.bend as R
import ./png.bend as P

# Authority is the complete server snapshot. The controller owns references,
# latches and request state only; the actual carried stack is in MenuSnapshot.
type Hit is Data:
  Outside{}
  Slot{index:U32}
  Palette{index:U32}
  Tab{index:U32}
  Previous{}
  Next{}
  Search{}

type Notice is Data:
  Ready{}
  Waiting{}
  Rejected{}
  Unavailable{}
  ChooseSlot{}
  ChooseTarget{}
  Invalid{}
  TooSmall{}

type State is Data:
  State{open:Bool,keys:U32,buttons:U32,captured:Bool,focused:Bool,
    source:Maybe<&2,U32>,offer:Maybe<&2,D.Definition>,pending:U32,
    tab:U32,row:U32,query:String,notice:Notice,hover:Hit}

type Intent is Data:
  ReleaseControls{}
  Capture{enabled:Bool}
  Select{slot:U32}
  Transfer{source:U32,destination:U32,count:U32,mode:Inv.TransferMode}
  Acquire{slot:U32,key:Inv.ItemKey,count:U32}
  MenuOpen{}
  MenuClose{}
  MenuClick{slot:U32,click:I.Click}
  Quit{}

type Update is Data:
  Update{state:State,intents:List<&2,Intent>,consumed:Bool}

type Frame is Data:
  Frame{controller:State,snapshot:I.MenuSnapshot,catalog:D.Catalog}

type Decision is Data:
  Decision{frame:Frame,intents:List<&2,Intent>,consumed:Bool}

type Viewport is Data:
  Viewport{width:U32,height:U32,native_width:U32,native_height:U32}

type Layout is Data:
  Layout{width:U32,height:U32,left:U32,top:U32,slot:U32,
    panel_width:U32,panel_height:U32,visible:Bool}

type ItemIcon is Data:
  ItemIcon{id:String,texture:R.Texture}

type View is Data:
  View{slots:List<&2,H.DrawSlot>,palette:List<&2,H.DrawSlot>,result:Maybe<&2,H.DrawSlot>,
    carried:H.DrawSlot,selected:U32,creative:Bool,valid:Bool,caption:String}

def new(captured:Bool) -> State:
  State{False{},0,0,captured,True{},None{},None{},0,0,0,"",Ready{},Outside{}}

def is_open(state:State) -> Bool:
  State{open,keys,buttons,captured,focused,source,offer,pending,tab,row,query,message,hover} = state
  open

def dimensions(+width:U32,+height:U32) -> Bool:
  U32.is_gt(width,0) && U32.is_gt(height,0) && U32.is_le(width,8192) && U32.is_le(height,8192)

def viewport_valid(viewport:Viewport) -> Bool:
  Viewport{width,height,nw,nh} = viewport
  dimensions(width,height) && dimensions(nw,nh)

def layout(+width:U32,+height:U32) -> Layout:
  +slot = U32.max(1,U32.min(20,U32.min(U32.div(U32.sub(U32.max(width,24),24),9),
    U32.div(U32.sub(U32.max(height,48),48),8))))
  +pw = U32.add(U32.mul(slot,9),16)
  +ph = U32.add(U32.mul(slot,8),48)
  Layout{width,height,U32.div(U32.sub(U32.max(width,pw),pw),2),
    U32.div(U32.sub(U32.max(height,ph),ph),2),slot,pw,ph,
    dimensions(width,height) && U32.is_ge(slot,16) && U32.is_ge(width,pw) && U32.is_ge(height,ph)}

def visible(value:Layout) -> Bool:
  Layout{width,height,left,top,size,pw,ph,visible} = value
  visible

def main_top(value:Layout) -> U32:
  Layout{width,height,left,top,size,pw,ph,visible} = value
  U32.add(top,U32.add(U32.mul(size,4),30))

def hotbar_top(value:Layout) -> U32:
  Layout{width,height,left,top,size,pw,ph,visible} = value
  U32.add(top,U32.add(U32.mul(size,7),36))

# InventoryMenu's verified46 slots: result0,craft1..4,armor5..8,
# main9..35,hotbar36..44,offhand45. BODY/SADDLE stay in saved equipment.
def inventory_hit(+value:Layout,+x:U32,+y:U32) -> Hit:
  Layout{width,height,+left,+top,+size,pw,ph,shown} = value
  +gx = U32.add(left,8)
  +gy = U32.add(top,24)
  +cx = U32.add(gx,U32.mul(size,5))
  +cy = U32.add(gy,size)
  P.choose(Hit,Slot{U32.add(5,U32.div(U32.sub(y,gy),size))},
    P.choose(Hit,Slot{U32.add(1,U32.add(U32.mul(U32.div(U32.sub(y,cy),size),2),U32.div(U32.sub(x,cx),size)))},
      P.choose(Hit,Slot{0},P.choose(Hit,Slot{45},Outside{},H.inside(x,y,U32.add(gx,U32.mul(size,4)),U32.add(gy,U32.mul(size,3)),size,size)),
        H.inside(x,y,U32.add(gx,U32.mul(size,8)),U32.add(gy,U32.mul(size,2)),size,size)),
      H.inside(x,y,cx,cy,U32.mul(size,2),U32.mul(size,2))),H.inside(x,y,gx,gy,size,U32.mul(size,4)))

def logical_hit_active(active:Bool,+value:Layout,+tab:U32,+x:U32,+y:U32) -> Hit:
  match active:
    case False{}: Outside{}
    case True{}:
      Layout{width,height,+left,+top,+size,pw,ph,shown} = value
      +gx = U32.add(left,8)
      +mt = main_top(value)
      +ht = hotbar_top(value)
      +nt = U32.add(top,U32.add(U32.mul(size,6),30))
      P.choose(Hit,Tab{U32.div(U32.sub(x,gx),U32.mul(size,3))},
        P.choose(Hit,Slot{U32.add(36,U32.div(U32.sub(x,gx),size))},
          P.choose(Hit,P.choose(Hit,Palette{U32.add(U32.mul(U32.div(U32.sub(y,U32.add(top,24)),size),9),U32.div(U32.sub(x,gx),size))},
            P.choose(Hit,Previous{},P.choose(Hit,Next{},P.choose(Hit,Search{},Outside{},H.inside(x,y,U32.add(gx,size),nt,U32.mul(size,7),size)),H.inside(x,y,U32.add(gx,U32.mul(size,8)),nt,size,size)),H.inside(x,y,gx,nt,size,size)),
            H.inside(x,y,gx,U32.add(top,24),U32.mul(size,9),U32.mul(size,5))),
            P.choose(Hit,Slot{U32.add(9,U32.add(U32.mul(U32.div(U32.sub(y,mt),size),9),U32.div(U32.sub(x,gx),size)))},inventory_hit(value,x,y),
              H.inside(x,y,gx,mt,U32.mul(size,9),U32.mul(size,3))),U32.is_eq(tab,1) || U32.is_eq(tab,3)),
          H.inside(x,y,gx,ht,U32.mul(size,9),size)),H.inside(x,y,gx,U32.add(top,6),U32.mul(size,9),12))

def native_hit_active(active:Bool,viewport:Viewport,tab:U32,x:U32,y:U32) -> Hit:
  match active:
    case False{}: Outside{}
    case True{}:
      Viewport{+width,+height,+nw,+nh} = viewport
      logical_hit_active(visible(layout(width,height)),layout(width,height),tab,
        U32.div(U32.mul(x,width),nw),U32.div(U32.mul(y,height),nh))

def hit(+viewport:Viewport,tab:U32,+x:U32,+y:U32) -> Hit:
  Viewport{width,height,nw,nh} = viewport
  native_hit_active(viewport_valid(viewport) && U32.is_lt(x,nw) && U32.is_lt(y,nh),viewport,tab,x,y)

def prefix(text:String,wanted:String) -> Bool:
  match text wanted:
    case _ SNil{}: True{}
    case SCon{Chr{a},rest} SCon{Chr{b},tail}: U32.is_eq(a,b) && prefix(rest,tail)
    case _ _: False{}

def contains(text:String,+wanted:String) -> Bool:
  match text:
    case SNil{}: String.is_empty(wanted)
    case SCon{head,+rest}: prefix(SCon{head,rest},wanted) || contains(rest,wanted)

def matching_admitted(allowed:Bool,item:D.Definition,tail:List<&2,D.Definition>) -> List<&2,D.Definition>:
  match allowed:
    case False{}: tail
    case True{}: item <> tail

def matching_rows(rows:List<&2,D.Definition>,+query:String) -> List<&2,D.Definition>:
  match rows:
    case Nil{}: []
    case +item <> rest:
      D.Definition{number,+id,description,limit,set,hash,enabled} = item
      matching_admitted(enabled && Bool.not(String.eq(id,"minecraft:air")) && contains(id,query),item,matching_rows(rest,query))

def matching(+catalog:D.Catalog,+query:String) -> List<&2,D.Definition>:
  matching_rows(D.all(catalog),query)

def skip_items(left:Nat,values:List<&2,D.Definition>) -> List<&2,D.Definition>:
  match left values:
    case 0n _: values
    case 1n+n item <> rest: skip_items(n,rest)
    case _ _: []

def item_at(values:List<&2,D.Definition>,index:Nat) -> Maybe<&2,D.Definition>:
  match values index:
    case item <> rest 0n: Some{item}
    case item <> rest 1n+n: item_at(rest,n)
    case _ _: None{}

def palette(catalog:D.Catalog,state:State) -> List<&2,D.Definition>:
  State{open,keys,buttons,captured,focused,source,offer,pending,tab,row,query,message,hover} = state
  skip_items(U32.to_nat(U32.mul(row,9)),matching(catalog,query))

def main_snapshot(snapshot:I.MenuSnapshot) -> I.Snapshot:
  I.MenuSnapshot{I.Persisted{main,equipment,status},craft,carried,result,opened,revision} = snapshot
  main

def creative_main(snapshot:I.Snapshot) -> Bool:
  I.Snapshot{selected,slots,I.Abilities{instabuild,maybuild}} = snapshot
  instabuild

def creative(snapshot:I.MenuSnapshot) -> Bool:
  creative_main(main_snapshot(snapshot))

def notice(state:State,value:Notice) -> State:
  State{open,keys,buttons,captured,focused,source,offer,pending,tab,row,query,old,hover} = state
  State{open,keys,buttons,captured,focused,source,offer,pending,tab,row,query,value,hover}

def pending_intent(state:State,intent:Intent) -> Update:
  State{open,keys,buttons,captured,focused,source,offer,pending,tab,row,query,message,hover} = state
  Update{State{open,keys,buttons,captured,focused,None{},None{},3,tab,row,query,Waiting{},hover},[intent],True{}}

def focus_lost(state:State) -> Update:
  State{+open,+keys,+buttons,+captured,focused,source,offer,+pending,tab,row,query,message,hover} = state
  Update{State{False{},0,0,False{},False{},None{},None{},pending,tab,row,query,
    P.choose(Notice,Waiting{},Ready{},U32.is_ne(pending,0)),Outside{}},
    P.choose(List<&2,Intent>,[ReleaseControls{},Capture{False{}}],[],open || captured || U32.is_ne(buttons,0) || U32.is_ne(keys,0)),True{}}

def synchronize_focused(state:State,+captured:Bool) -> Update:
  State{+open,keys,buttons,+previous,oldfocus,source,offer,pending,tab,row,query,message,hover} = state
  Update{State{open,keys,buttons,captured,True{},source,offer,pending,tab,row,query,message,hover},
    P.choose(List<&2,Intent>,[ReleaseControls{},Capture{False{}}],
      P.choose(List<&2,Intent>,[ReleaseControls{}],[],Bool.not(open) && previous && Bool.not(captured)),open && captured),open}

def synchronize(state:State,focused:Bool,captured:Bool) -> Update:
  match focused:
    case False{}: focus_lost(state)
    case True{}: synchronize_focused(state,captured)

def observed_open(state:State,snapshot:I.MenuSnapshot) -> State:
  State{open,keys,buttons,captured,focused,source,offer,pending,tab,row,query,message,hover} = state
  I.MenuSnapshot{saved,craft,carried,result,opened,revision} = snapshot
  State{opened,keys,buttons,captured,focused,source,offer,pending,tab,row,query,message,hover}

def observed_checked(admitted:Bool,state:State,snapshot:I.MenuSnapshot) -> State:
  match admitted:
    case False{}: state
    case True{}: observed_open(state,snapshot)

def observed(+state:State,+snapshot:I.MenuSnapshot) -> State:
  State{open,keys,buttons,captured,focused,source,offer,pending,tab,row,query,message,hover} = state
  observed_checked(focused && U32.is_zero(pending) && I.menu_snapshot_valid(snapshot),state,snapshot)

def observation_focused(state:State) -> State:
  State{open,keys,buttons,captured,focused,source,offer,pending,tab,row,query,message,hover} = state
  State{open,keys,buttons,captured,True{},source,offer,pending,tab,row,query,message,hover}

def authority_synchronized(focused:Bool,state:State,snapshot:I.MenuSnapshot,captured:Bool) -> Update:
  match focused:
    case False{}: focus_lost(state)
    case True{}: synchronize(observed(observation_focused(state),snapshot),True{},captured)

def synchronize_authority(state:State,snapshot:I.MenuSnapshot,focused:Bool,captured:Bool) -> Update:
  authority_synchronized(focused,state,snapshot,captured)

def latch(+mask:U32,+bit:U32,down:Bool) -> U32:
  P.choose(U32,U32.or(mask,bit),U32.and(mask,U32.xor(4294967295,bit)),down)

def key_bit(code:U32) -> U32:
  match code:
    case 49: 1
    case 50: 2
    case 51: 4
    case 52: 8
    case 53: 16
    case 54: 32
    case 55: 64
    case 56: 128
    case 57: 256
    case 69: 512
    case 101: 512
    case 27: 1024
    case _: 0

def toggle_state(state:State) -> Update:
  State{+open,+keys,buttons,+captured,+focused,source,offer,pending,+tab,+row,+query,message,hover} = state
  P.choose(Update,Update{State{True{},keys,0,captured,focused,None{},None{},2,tab,row,query,Waiting{},Outside{}},
      [ReleaseControls{},Capture{False{}},MenuClose{}],True{}},
    Update{State{True{},keys,0,captured,focused,None{},None{},1,tab,row,query,Waiting{},Outside{}},
      [ReleaseControls{},Capture{False{}},MenuOpen{}],True{}},open)

def toggle_ready(state:State,allowed:Bool) -> Update:
  match allowed:
    case False{}: Update{notice(state,TooSmall{}),[],True{}}
    case True{}: toggle_state(state)

def toggle_viewport(state:State,+viewport:Viewport) -> Update:
  Viewport{width,height,nw,nh} = viewport
  toggle_ready(state,viewport_valid(viewport) && visible(layout(width,height)))

def toggle_admitted(state:State,viewport:Viewport,idle:Bool) -> Update:
  match idle:
    case False{}: Update{state,[],True{}}
    case True{}: toggle_viewport(state,viewport)

def key_command_values(+code:U32,+state:State,viewport:Viewport,+open:Bool,+pending:U32,captured:Bool) -> Update:
  match code:
    case 69: toggle_admitted(state,viewport,U32.is_zero(pending))
    case 101: toggle_admitted(state,viewport,U32.is_zero(pending))
    case 27: P.choose(Update,toggle_admitted(state,viewport,U32.is_zero(pending)),Update{state,[],False{}},open)
    case _: P.choose(Update,pending_intent(state,Select{U32.sub(code,49)}),Update{state,[],open},
      open && U32.is_zero(pending) && Bool.not(captured) && U32.is_ge(code,49) && U32.is_le(code,57))

def key_command(state:State,viewport:Viewport,code:U32) -> Update:
  State{+open,keys,buttons,+captured,focused,source,offer,+pending,tab,row,query,message,hover} = state
  key_command_values(code,State{open,keys,buttons,captured,focused,source,offer,pending,tab,row,query,message,hover},viewport,open,pending,captured)

def search(state:State,text:String) -> State:
  State{open,keys,buttons,captured,focused,source,offer,pending,tab,row,query,message,hover} = state
  State{open,keys,buttons,captured,focused,None{},None{},pending,tab,0,text,message,hover}

def drop_last(text:String) -> String:
  match text:
    case SCon{head,SNil{}}: ""
    case SCon{head,rest}: SCon{head,drop_last(rest)}
    case SNil{}: ""

def search_append(state:State,+code:U32) -> Update:
  State{open,keys,buttons,captured,focused,source,offer,pending,tab,row,query,message,hover} = state
  Update{State{open,keys,buttons,captured,focused,None{},None{},pending,tab,0,
    query ++ SCon{Chr{P.choose(U32,U32.add(code,32),code,U32.is_ge(code,65) && U32.is_le(code,90))},SNil{}},message,hover},[],True{}}

def search_character(state:State,code:U32,allowed:Bool) -> Update:
  match allowed:
    case False{}: Update{state,[],True{}}
    case True{}: search_append(state,code)

def search_key(+state:State,+code:U32) -> Update:
  State{open,keys,buttons,captured,focused,source,offer,pending,tab,row,+query,message,hover} = state
  match code:
    case 27: Update{State{open,keys,buttons,captured,focused,source,offer,pending,1,row,query,message,hover},[],True{}}
    case 13: Update{State{open,keys,buttons,captured,focused,source,offer,pending,1,row,query,message,hover},[],True{}}
    case 8: Update{search(state,drop_last(query)),[],True{}}
    case _: search_character(state,code,Nat.is_lt(String.length(query),64n) &&
      ((U32.is_ge(code,65) && U32.is_le(code,90)) || (U32.is_ge(code,97) && U32.is_le(code,122)) ||
        (U32.is_ge(code,48) && U32.is_le(code,57)) || U32.is_eq(code,95) || U32.is_eq(code,45) || U32.is_eq(code,46) || U32.is_eq(code,58) || U32.is_eq(code,47)))

def key_normal(state:State,viewport:Viewport,+code:U32,searching:Bool) -> Update:
  match searching:
    case True{}: search_key(state,code)
    case False{}: key_command(state,viewport,code)

def key_press(state:State,viewport:Viewport,+code:U32) -> Update:
  State{+open,keys,buttons,captured,focused,source,offer,+pending,+tab,row,query,message,hover} = state
  +next = {State{open,keys,buttons,captured,focused,source,offer,pending,tab,row,query,message,hover} : State}
  key_normal(next,viewport,code,U32.is_eq(tab,3))

def key_edge(edge:Bool,+state:State,viewport:Viewport,+code:U32) -> Update:
  match edge:
    case False{}: Update{state,[],is_open(state) || U32.is_eq(code,69) || U32.is_eq(code,101) || U32.is_eq(code,27)}
    case True{}: key_press(state,viewport,code)

def key_event(state:State,viewport:Viewport,+code:U32,+down:Bool) -> Update:
  State{open,+keys,buttons,captured,focused,source,offer,pending,tab,row,query,message,hover} = state
  +bit = key_bit(code)
  key_edge(down && U32.is_zero(U32.and(keys,bit)),
    State{open,latch(keys,bit,down),buttons,captured,focused,source,offer,pending,tab,row,query,message,hover},viewport,code)

def hover(state:State,target:Hit) -> State:
  State{open,keys,buttons,captured,focused,source,offer,pending,tab,row,query,message,old} = state
  State{open,keys,buttons,captured,focused,source,offer,pending,tab,row,query,message,target}

def tab_change(state:State,index:U32) -> Update:
  State{open,keys,buttons,captured,focused,source,offer,pending,tab,row,query,message,hover} = state
  Update{State{open,keys,buttons,captured,focused,None{},None{},pending,index,0,"",Ready{},hover},[],True{}}

def offered(state:State,item:D.Definition) -> Update:
  State{open,keys,buttons,captured,focused,source,offer,pending,tab,row,query,message,hover} = state
  Update{State{open,keys,buttons,captured,focused,None{},Some{item},pending,tab,row,query,ChooseSlot{},hover},[],True{}}

def offer_selected(state:State,found:Maybe<&2,D.Definition>,allowed:Bool) -> Update:
  match found allowed:
    case Some{item} True{}: offered(state,item)
    case _ _: Update{notice(state,Unavailable{}),[],True{}}

def main_index(index:Maybe<&2,U32>) -> Maybe<&2,U32>:
  match index:
    case None{}: None{}
    case Some{+slot}: P.choose(Maybe<&2,U32>,Some{slot},None{},U32.is_lt(slot,36))

def direct_slots(state:State,source:U32,destination:U32,button:U32,from:Inv.Slot) -> Update:
  match from:
    case Inv.InvEmpty{}: Update{notice(state,Rejected{}),[],True{}}
    case Inv.InvStack{key,count}: pending_intent(state,Transfer{source,destination,P.choose(U32,1,count,U32.is_eq(button,1)),Inv.TransferAny{}})

def source_chosen(state:State,index:U32) -> Update:
  State{open,keys,buttons,captured,focused,old,offer,pending,tab,row,query,message,hover} = state
  Update{State{open,keys,buttons,captured,focused,Some{index},None{},pending,tab,row,query,ChooseTarget{},hover},[],True{}}

def direct_source(state:State,+snapshot:I.MenuSnapshot,index:U32,source:Maybe<&2,U32>,slot:Inv.Slot,button:U32) -> Update:
  match source slot:
    case None{} Inv.InvEmpty{}: Update{state,[],True{}}
    case None{} Inv.InvStack{key,count}: source_chosen(state,index)
    case Some{+from} _: direct_slots(state,from,index,button,I.menu_snapshot_slot(snapshot,from))

def max_row(catalog:D.Catalog,query:String) -> U32:
  +rows = U32.div(U32.add(U32.from_nat(List.length(&2,D.Definition,matching(catalog,query))),8),9)
  U32.sub(U32.max(rows,5),5)

def scroll_to(state:State,row:U32) -> Update:
  State{open,keys,buttons,captured,focused,source,offer,pending,tab,previous,query,message,old} = state
  Update{State{open,keys,buttons,captured,focused,None{},None{},pending,tab,row,query,message,old},[],True{}}

def search_focus(state:State) -> Update:
  State{open,keys,buttons,captured,focused,source,offer,pending,tab,row,query,message,old} = state
  Update{State{open,keys,buttons,captured,focused,None{},None{},pending,3,row,query,message,old},[],True{}}

def offered_slot(state:State,+snapshot:I.MenuSnapshot,index:U32,+button:U32,found:Maybe<&2,U32>,offer:Maybe<&2,D.Definition>,source:Maybe<&2,U32>,direct:Bool) -> Update:
  match found offer direct:
    case Some{main} Some{D.Definition{number,id,description,limit,set,hash,enabled}} _:
      pending_intent(state,Acquire{main,Inv.ItemKey{id,""},P.choose(U32,1,limit,U32.is_eq(button,1))})
    case Some{+main} None{} True{}: direct_source(state,snapshot,main,source,I.menu_snapshot_slot(snapshot,main),button)
    case _ Some{item} _: Update{notice(state,Unavailable{}),[],True{}}
    case _ None{} _: pending_intent(state,MenuClick{index,I.Pickup{button}})

def click_target(target:Hit,+state:State,+snapshot:I.MenuSnapshot,+catalog:D.Catalog,+button:U32,source:Maybe<&2,U32>,offer:Maybe<&2,D.Definition>,tab:U32,+row:U32,query:String) -> Update:
  match target:
    case Outside{}: Update{state,[],True{}}
    case Tab{index}: tab_change(state,index)
    case Palette{index}: offer_selected(state,item_at(palette(catalog,state),U32.to_nat(index)),creative(snapshot))
    case Slot{+index}: offered_slot(state,snapshot,index,button,main_index(I.menu_index(index)),offer,source,U32.is_eq(tab,2))
    case Previous{}: scroll_to(state,U32.sub(U32.max(row,5),5))
    case Next{}: scroll_to(state,U32.min(U32.add(row,5),max_row(catalog,query)))
    case Search{}: search_focus(state)

def click(state:State,snapshot:I.MenuSnapshot,catalog:D.Catalog,target:Hit,button:U32) -> Update:
  State{open,keys,buttons,captured,focused,+source,+offer,pending,+tab,+row,+query,message,old} = state
  click_target(target,State{open,keys,buttons,captured,focused,source,offer,pending,tab,row,query,message,old},snapshot,catalog,button,source,offer,tab,row,query)

def mouse_admitted(allowed:Bool,+state:State,snapshot:I.MenuSnapshot,catalog:D.Catalog,viewport:Viewport,+x:U32,+y:U32,button:U32) -> Update:
  match allowed:
    case False{}: Update{state,[],is_open(state)}
    case True{}:
      State{open,keys,buttons,captured,focused,source,offer,pending,+tab,row,query,message,old} = state
      +target = hit(viewport,tab,x,y)
      click(State{open,keys,buttons,captured,focused,source,offer,pending,tab,row,query,message,target},snapshot,catalog,target,button)

def mouse_event(state:State,snapshot:I.MenuSnapshot,catalog:D.Catalog,viewport:Viewport,x:U32,y:U32,+button:U32,+down:Bool) -> Update:
  State{+open,keys,+buttons,+captured,focused,source,offer,+pending,tab,row,query,message,hover} = state
  +bit = P.choose(U32,1,P.choose(U32,2,0,U32.is_eq(button,1)),U32.is_eq(button,0))
  mouse_admitted(open && down && U32.is_lt(button,2) && U32.is_zero(pending) && Bool.not(captured) && U32.is_zero(U32.and(buttons,bit)),
    State{open,keys,latch(buttons,bit,down),captured,focused,source,offer,pending,tab,row,query,message,hover},snapshot,catalog,viewport,x,y,button)

def valid_event(event:Event,+state:State,snapshot:I.MenuSnapshot,catalog:D.Catalog,viewport:Viewport,+open:Bool,captured:Bool,tab:U32) -> Update:
  match event:
    case Key{code,down}: key_event(state,viewport,code,down)
    case Mouse{x,y,button,down}: mouse_event(state,snapshot,catalog,viewport,x,y,button,down)
    case Move{x,y}: Update{P.choose(State,hover(state,hit(viewport,tab,x,y)),state,open && Bool.not(captured)),[],open}
    case Close{}: Update{state,[ReleaseControls{},Capture{False{}},Quit{}],True{}}
    case _: Update{state,[],open}

def event_valid(state:State,snapshot:I.MenuSnapshot,catalog:D.Catalog,viewport:Viewport,event:Event) -> Update:
  State{+open,keys,buttons,+captured,focused,source,offer,pending,+tab,row,query,message,old} = state
  valid_event(event,State{open,keys,buttons,captured,focused,source,offer,pending,tab,row,query,message,old},snapshot,catalog,viewport,open,captured,tab)

def event_checked(valid:Bool,+state:State,snapshot:I.MenuSnapshot,catalog:D.Catalog,viewport:Viewport,event:Event) -> Update:
  match valid:
    case False{}: Update{notice(state,Invalid{}),[],is_open(state)}
    case True{}: event_valid(state,snapshot,catalog,viewport,event)

def event_combined(intents:List<&2,Intent>,result:Update) -> Update:
  Update{next,requests,used} = result
  Update{next,List.append(&2,Intent,intents,requests),used}

def event_observed(+snapshot:I.MenuSnapshot,+catalog:D.Catalog,viewport:Viewport,event:Event,result:Update) -> Update:
  Update{state,intents,consumed} = result
  event_combined(intents,event_checked(I.menu_snapshot_valid(snapshot),state,snapshot,catalog,viewport,event))

def step(state:State,+snapshot:I.MenuSnapshot,catalog:D.Catalog,viewport:Viewport,event:Event,focused:Bool,captured:Bool) -> Update:
  match focused:
    case False{}: focus_lost(state)
    case True{}: event_observed(snapshot,catalog,viewport,event,synchronize_authority(state,snapshot,True{},captured))

def controller(result:Update) -> State:
  Update{state,intents,consumed} = result
  state

def intents(result:Update) -> List<&2,Intent>:
  Update{state,intents,consumed} = result
  intents

def consumed(result:Update) -> Bool:
  Update{state,intents,consumed} = result
  consumed

def decided(snapshot:I.MenuSnapshot,catalog:D.Catalog,+result:Update) -> Decision:
  Decision{Frame{controller(result),snapshot,catalog},intents(result),consumed(result)}

def step_frame(frame:Frame,viewport:Viewport,event:Event,focused:Bool,captured:Bool) -> Decision:
  Frame{controller,+snapshot,+catalog} = frame
  decided(snapshot,catalog,step(controller,snapshot,catalog,viewport,event,focused,captured))

# Only a correlated authenticated reply replaces the full authority snapshot.
# Refused closes stay open. Focus loss cannot cause reply-driven recapture.
def completed(state:State,+snapshot:I.MenuSnapshot,accepted:Bool) -> Update:
  State{open,keys,buttons,captured,+focused,source,offer,+pending,tab,row,query,message,hover} = state
  I.MenuSnapshot{saved,craft,carried,result,+opened,revision} = snapshot
  +closed = U32.is_ne(pending,0) && Bool.not(opened)
  Update{State{opened && focused,
    keys,0,captured,focused,None{},None{},0,tab,row,query,P.choose(Notice,Ready{},Rejected{},accepted),hover},
    P.choose(List<&2,Intent>,[ReleaseControls{},Capture{True{}}],[],closed && focused),True{}}

def letter_ascii(code:U32) -> U32:
  match code:
    case 65: 31725
    case 66: 27566
    case 67: 31207
    case 68: 27502
    case 69: 31143
    case 70: 31140
    case 71: 31215
    case 72: 23533
    case 73: 29847
    case 74: 9366
    case 75: 23469
    case 76: 18727
    case 77: 24429
    case 78: 24429
    case 79: 31599
    case 80: 31716
    case 81: 31611
    case 82: 31725
    case 83: 31183
    case 84: 29842
    case 85: 23407
    case 86: 23402
    case 87: 23549
    case 88: 23213
    case 89: 23186
    case 90: 29351
    case 45: 448
    case 48: 31599
    case 46: 1
    case 58: 1040
    case 95: 7
    case 47: 4681
    case 49: 9362
    case 50: 29671
    case 51: 29647
    case 52: 23497
    case 53: 31183
    case 54: 31215
    case 55: 29257
    case 56: 31727
    case 57: 31695
    case _: 0

def letter(+code:U32) -> U32:
  letter_ascii(P.choose(U32,U32.sub(U32.max(code,32),32),code,U32.is_ge(code,97) && U32.is_le(code,122)))

def text_pixel(text:String,+x:U32,+y:U32) -> Bool:
  match text:
    case SNil{}: False{}
    case SCon{Chr{code},rest}:
      P.choose(Bool,U32.is_lt(x,3) && U32.is_lt(y,5) &&
        U32.is_ne(U32.and(U32.shrn(letter(code),U32.to_nat(U32.add(U32.mul(U32.sub(4,U32.min(y,4)),3),U32.sub(2,U32.min(x,2))))),1),0),
        text_pixel(rest,U32.sub(x,4),y),U32.is_lt(x,4))

def label_pixel(text:String,+x:U32,+y:U32,+left:U32,+top:U32) -> Bool:
  U32.is_ge(x,left) && U32.is_ge(y,top) && U32.is_lt(y,U32.add(top,5)) &&
    text_pixel(text,U32.sub(x,left),U32.sub(y,top))

# Icon bindings are supplied by the actual resource/model presenter. Missing
# bindings remain visible as missing; no colored square impersonates an item.
def icon(rows:List<&2,ItemIcon>,+id:String) -> Maybe<&2,R.Texture>:
  match rows:
    case Nil{}: None{}
    case ItemIcon{wanted,+texture} <> rest:
      P.choose(Maybe<&2,R.Texture>,Some{texture},icon(rest,id),String.eq(wanted,id))

def fallback(found:Maybe<&2,R.Texture>,id:String,icons:H.Icons) -> Maybe<&2,R.Texture>:
  match found:
    case Some{texture}: Some{texture}
    case None{}: H.item_icon(id,icons)

def draw_slot(slot:Inv.Slot,+rows:List<&2,ItemIcon>,icons:H.Icons) -> H.DrawSlot:
  match slot:
    case Inv.InvEmpty{}: H.Empty{}
    case Inv.InvStack{Inv.ItemKey{+id,components},count}: H.Stack{count,fallback(icon(rows,id),id,icons)}

def draw_slots(left:Nat,slots:List<&2,Inv.Slot>,+rows:List<&2,ItemIcon>,+icons:H.Icons) -> List<&2,H.DrawSlot>:
  match left slots:
    case 1n+n slot <> rest: draw_slot(slot,rows,icons) <> draw_slots(n,rest,rows,icons)
    case _ _: []

def draw_palette(left:Nat,items:List<&2,D.Definition>,+rows:List<&2,ItemIcon>,+icons:H.Icons) -> List<&2,H.DrawSlot>:
  match left items:
    case 1n+n D.Definition{number,id,description,limit,set,hash,enabled} <> rest:
      draw_slot(Inv.InvStack{Inv.ItemKey{id,""},1},rows,icons) <> draw_palette(n,rest,rows,icons)
    case _ _: []

def draw_result(result:Maybe<&2,Inv.Slot>,rows:List<&2,ItemIcon>,icons:H.Icons) -> Maybe<&2,H.DrawSlot>:
  match result:
    case None{}: None{}
    case Some{slot}: Some{draw_slot(slot,rows,icons)}

def palette_caption(item:Maybe<&2,D.Definition>) -> String:
  match item:
    case None{}: ""
    case Some{D.Definition{number,id,description,limit,set,hash,enabled}}: id

def slot_caption(slot:Inv.Slot) -> String:
  match slot:
    case Inv.InvEmpty{}: ""
    case Inv.InvStack{Inv.ItemKey{id,components},count}: id

def menu_caption(index:Maybe<&2,U32>,snapshot:I.MenuSnapshot) -> String:
  match index:
    case None{}: "RECIPE UNAVAILABLE"
    case Some{slot}: slot_caption(I.menu_snapshot_slot(snapshot,slot))

def caption(+state:State,snapshot:I.MenuSnapshot,catalog:D.Catalog) -> String:
  State{open,keys,buttons,captured,focused,source,offer,pending,tab,row,query,message,target} = state
  match target:
    case Palette{index}: palette_caption(item_at(palette(catalog,state),U32.to_nat(index)))
    case Slot{index}: menu_caption(I.menu_index(index),snapshot)
    case Search{}: query
    case _: ""

def prepared(+state:State,+snapshot:I.MenuSnapshot,+catalog:D.Catalog,+rows:List<&2,ItemIcon>,+icons:H.Icons) -> View:
  I.MenuSnapshot{I.Persisted{I.Snapshot{selected,main,I.Abilities{instabuild,maybuild}},equipment,status},craft,+carried,result,opened,revision} = snapshot
  View{draw_slots(48n,List.append(&2,Inv.Slot,main,List.append(&2,Inv.Slot,equipment,List.append(&2,Inv.Slot,craft,[carried]))),rows,icons),
    draw_palette(45n,palette(catalog,state),rows,icons),draw_result(result,rows,icons),draw_slot(carried,rows,icons),selected,instabuild,True{},caption(state,snapshot,catalog)}

def prepare_checked(valid:Bool,state:State,snapshot:I.MenuSnapshot,catalog:D.Catalog,rows:List<&2,ItemIcon>,icons:H.Icons) -> View:
  match valid:
    case False{}: View{[],[],None{},H.Empty{},0,False{},False{},""}
    case True{}: prepared(state,snapshot,catalog,rows,icons)

def prepare(frame:Frame,rows:List<&2,ItemIcon>,icons:H.Icons) -> View:
  Frame{state,+snapshot,catalog} = frame
  prepare_checked(I.menu_snapshot_valid(snapshot),state,snapshot,catalog,rows,icons)

def edge(+x:U32,+y:U32,+size:U32) -> Bool:
  U32.is_zero(x) || U32.is_zero(y) || U32.is_eq(x,U32.sub(size,1)) || U32.is_eq(y,U32.sub(size,1))

def ref_matches(reference:Maybe<&2,U32>,index:Maybe<&2,U32>) -> Bool:
  match reference index:
    case Some{a} Some{b}: U32.is_eq(a,b)
    case _ _: False{}

def hit_same(a:Hit,b:Hit) -> Bool:
  match a b:
    case Slot{x} Slot{y}: U32.is_eq(x,y)
    case Palette{x} Palette{y}: U32.is_eq(x,y)
    case Tab{x} Tab{y}: U32.is_eq(x,y)
    case Previous{} Previous{}: True{}
    case Next{} Next{}: True{}
    case _ _: False{}

def missing(slot:H.DrawSlot) -> Bool:
  match slot:
    case H.Stack{count,None{}}: True{}
    case _: False{}

def stack_pixel(+slot:H.DrawSlot,+x:U32,+y:U32,+size:U32,+background:U32) -> U32:
  P.choose(U32,4294953472,H.stack_pixel(slot,x,y,size,background),
    missing(slot) && U32.is_eq(x,U32.div(size,2)) && U32.is_ge(y,4) && U32.is_le(y,U32.sub(size,4)))

def indexed_slot_values(index:Maybe<&2,U32>,slots:List<&2,H.DrawSlot>,result:Maybe<&2,H.DrawSlot>) -> H.DrawSlot:
  match index result:
    case None{} None{}: H.Empty{}
    case None{} Some{slot}: slot
    case Some{backing} _: H.at_slot(slots,U32.to_nat(backing))

def indexed_slot(view:View,index:Maybe<&2,U32>) -> H.DrawSlot:
  View{slots,palette,result,carried,selected,creative,valid,caption} = view
  indexed_slot_values(index,slots,result)

def result_paint(result:Maybe<&2,H.DrawSlot>,+x:U32,+y:U32,+size:U32,+background:U32) -> U32:
  match result:
    case Some{slot}: stack_pixel(slot,x,y,size,background)
    case None{}: P.choose(U32,4283979864,background,
      U32.is_eq(x,y) || U32.is_eq(U32.add(x,y),U32.sub(size,1)))

def slot_paint(+view:View,state:State,+index:U32,+x:U32,+y:U32,+size:U32) -> U32:
  View{slots,palette,+result,carried,+selected,creative,valid,caption} = view
  State{open,keys,buttons,captured,focused,source,offer,pending,tab,row,query,message,hover} = state
  +border = P.choose(U32,4281223331,P.choose(U32,4294967295,4281808695,
    U32.is_ge(index,36) && U32.is_lt(index,45) && U32.is_eq(U32.sub(index,36),selected)),ref_matches(source,I.menu_index(index)))
  +bg = P.choose(U32,4289506476,4287335307,hit_same(hover,Slot{index}) && U32.is_zero(pending))
  P.choose(U32,border,P.choose(U32,result_paint(result,x,y,size,bg),
    stack_pixel(indexed_slot(view,I.menu_index(index)),x,y,size,bg),U32.is_zero(index)),edge(x,y,size))

def message_text(message:Notice) -> String:
  match message:
    case Ready{}: "LEFT PICKUP RIGHT SPLIT"
    case Waiting{}: "WAIT FOR SERVER"
    case Rejected{}: "SERVER REFUSED RETRY"
    case Unavailable{}: "ACTION UNAVAILABLE"
    case ChooseSlot{}: "CHOOSE MAIN SLOT"
    case ChooseTarget{}: "LEFT ALL RIGHT ONE"
    case Invalid{}: "INVALID AUTHORITY"
    case TooSmall{}: "LARGER WINDOW NEEDED"

# Geometry used for painting is the same geometry used for hit testing.
def slot_position(+value:Layout,+index:U32) -> U32 & U32:
  Layout{width,height,+left,+top,+size,pw,ph,shown} = value
  +gx = U32.add(left,8)
  +gy = U32.add(top,24)
  P.choose(U32 & U32,(gx,U32.add(gy,U32.mul(U32.sub(index,5),size))),
    P.choose(U32 & U32,(U32.add(gx,U32.mul(U32.add(5,U32.mod(U32.sub(index,1),2)),size)),U32.add(gy,U32.mul(U32.add(1,U32.div(U32.sub(index,1),2)),size))),
      P.choose(U32 & U32,(U32.add(gx,U32.mul(size,8)),U32.add(gy,U32.mul(size,2))),
        P.choose(U32 & U32,(U32.add(gx,U32.mul(size,4)),U32.add(gy,U32.mul(size,3))),
          P.choose(U32 & U32,(U32.add(gx,U32.mul(U32.mod(U32.sub(index,9),9),size)),U32.add(main_top(value),U32.mul(U32.div(U32.sub(index,9),9),size))),
            (U32.add(gx,U32.mul(U32.sub(index,36),size)),hotbar_top(value)),U32.is_lt(index,36)),U32.is_eq(index,45)),U32.is_zero(index)),
      U32.is_ge(index,1) && U32.is_lt(index,5)),U32.is_ge(index,5) && U32.is_lt(index,9))

def slot_paint_position(view:View,state:State,index:U32,x:U32,y:U32,size:U32,position:U32 & U32) -> U32:
  (sx,sy) = position
  slot_paint(view,state,index,U32.sub(x,sx),U32.sub(y,sy),size)

def palette_paint(view:View,state:State,value:Layout,+x:U32,+y:U32,+index:U32) -> U32:
  View{slots,palette,result,carried,selected,+creative,valid,caption} = view
  State{open,keys,buttons,captured,focused,source,offer,pending,tab,row,query,message,hover} = state
  Layout{width,height,left,top,+size,pw,ph,visible} = value
  +paint = stack_pixel(H.at_slot(palette,U32.to_nat(index)),U32.mod(U32.sub(x,U32.add(left,8)),size),U32.mod(U32.sub(y,U32.add(top,24)),size),size,
    P.choose(U32,4289506476,4287335307,hit_same(hover,Palette{index})))
  P.choose(U32,paint,H.darken(paint),creative)

def panel_outside(view:View,state:State,value:Layout,+x:U32,+y:U32) -> U32:
  View{slots,palette,result,carried,selected,creative,valid,caption} = view
  State{open,keys,buttons,captured,focused,source,offer,pending,+tab,row,query,message,hover} = state
  Layout{width,height,+left,+top,+size,pw,ph,visible} = value
  +items = U32.is_eq(tab,1) || U32.is_eq(tab,3)
  +held_x = U32.add(left,U32.add(8,U32.mul(size,P.choose(U32,8,4,items))))
  +held_y = U32.add(top,P.choose(U32,U32.add(U32.mul(size,5),30),24,items))
  P.choose(U32,stack_pixel(carried,U32.sub(x,held_x),U32.sub(y,held_y),size,4287335307),
    P.choose(U32,4282400832,4291217094,
      label_pixel("HELD",x,y,held_x,U32.sub(held_y,6)) ||
      label_pixel(caption,x,y,U32.add(left,8),U32.add(top,U32.add(U32.mul(size,8),37))) ||
      label_pixel(message_text(message),x,y,U32.add(left,8),U32.add(top,U32.add(U32.mul(size,8),43))) ||
      (U32.is_ne(tab,1) && label_pixel("PLAYER",x,y,U32.add(left,U32.add(size,12)),U32.add(top,32))) ||
      (U32.is_ne(tab,1) && label_pixel("MODEL UNAVAILABLE",x,y,U32.add(left,U32.add(size,12)),U32.add(top,44)))),
    H.inside(x,y,held_x,held_y,size,size))

def panel_content(+view:View,+state:State,+value:Layout,+x:U32,+y:U32,target:Hit) -> U32:
  State{open,keys,buttons,captured,focused,source,offer,pending,+tab,row,query,message,hover} = state
  Layout{width,height,+left,+top,+size,pw,ph,visible} = value
  match target:
    case Slot{+index}: slot_paint_position(view,state,index,x,y,size,slot_position(value,index))
    case Palette{index}: palette_paint(view,state,value,x,y,index)
    case Tab{+index}:
      +gx = U32.add(left,U32.add(8,U32.mul(index,U32.mul(size,3))))
      P.choose(U32,4282400832,P.choose(U32,4289506476,4287335307,U32.is_eq(tab,index)),
        label_pixel(P.choose(String,"PLAYER",P.choose(String,"ITEMS","MOVE",U32.is_eq(index,1)),U32.is_zero(index)),x,y,U32.add(gx,3),U32.add(top,9)))
    case Previous{}: P.choose(U32,4282400832,4287335307,label_pixel("PREV",x,y,U32.add(left,8),U32.add(top,U32.add(U32.mul(size,6),34))))
    case Next{}: P.choose(U32,4282400832,4287335307,label_pixel("NEXT",x,y,U32.add(left,U32.add(8,U32.mul(size,7))),U32.add(top,U32.add(U32.mul(size,6),34))))
    case Search{}: P.choose(U32,4282400832,4287335307,label_pixel(P.choose(String,"SEARCH",query,String.is_empty(query)),x,y,U32.add(left,U32.add(size,12)),U32.add(top,U32.add(U32.mul(size,6),34))))
    case Outside{}: panel_outside(view,state,value,x,y)

def pixel(+view:View,+state:State,+value:Layout,+x:U32,+y:U32,+world:U32) -> U32:
  State{open,keys,buttons,captured,focused,source,offer,pending,+tab,row,query,message,hover} = state
  Layout{width,height,+left,+top,+size,+pw,+ph,+visible} = value
  +inside = visible && H.inside(x,y,left,top,pw,ph)
  +border = U32.is_eq(x,left) || U32.is_eq(y,top) || U32.is_eq(x,U32.add(left,U32.sub(pw,1))) || U32.is_eq(y,U32.add(top,U32.sub(ph,1)))
  P.choose(U32,P.choose(U32,P.choose(U32,4294967295,4281808695,U32.is_eq(x,left) || U32.is_eq(y,top)),
    panel_content(view,state,value,x,y,logical_hit_active(visible,value,tab,x,y)),border),H.darken(world),inside)

def dim(image:Image) -> Image:
  match image:
    case Pix{color}: Pix{H.darken(color)}
    case Qua{tl,tr,bl,br}: Qua{dim(tl),dim(tr),dim(bl),dim(br)}

# Logical panel bounds project with floor at the near edge and ceil at the far
# edge. Native pixel sampling uses the exact inverse floor mapping of hit().
def touched_layout(+viewport:Viewport,+x:U32,+y:U32,side:U32,value:Layout) -> Bool:
  Viewport{+width,+height,+nw,+nh} = viewport
  Layout{w,h,+left,+top,size,+pw,+ph,shown} = value
  H.overlaps(x,y,side,U32.div(U32.mul(left,nw),width),U32.div(U32.mul(top,nh),height),
    U32.sub(U32.div(U32.add(U32.mul(U32.add(left,pw),nw),U32.sub(width,1)),width),U32.div(U32.mul(left,nw),width)),
    U32.sub(U32.div(U32.add(U32.mul(U32.add(top,ph),nh),U32.sub(height,1)),height),U32.div(U32.mul(top,nh),height)))

def touched(+viewport:Viewport,x:U32,y:U32,side:U32) -> Bool:
  Viewport{width,height,nw,nh} = viewport
  touched_layout(viewport,x,y,side,layout(width,height))

def native_pixel(+view:View,+state:State,viewport:Viewport,+x:U32,+y:U32,world:U32) -> U32:
  Viewport{+width,+height,nw,nh} = viewport
  pixel(view,state,layout(width,height),U32.div(U32.mul(x,width),nw),U32.div(U32.mul(y,height),nh),world)

def overlay(fuel:Nat,image:Image,+view:View,+state:State,+viewport:Viewport,+x:U32,+y:U32,+side:U32,active:Bool) -> Image:
  match fuel image active:
    case _ _ False{}: dim(image)
    case 0n Pix{color} True{}: Pix{native_pixel(view,state,viewport,x,y,color)}
    case 0n Qua{tl,tr,bl,br} True{}: Pix{native_pixel(view,state,viewport,x,y,R.pixel_at(0n,Qua{tl,tr,bl,br},0,0,1))}
    case 1n+ +rest Pix{+color} True{}:
      +half = U32.div(side,2)
      Qua{overlay(rest,Pix{color},view,state,viewport,x,y,half,touched(viewport,x,y,half)),
        overlay(rest,Pix{color},view,state,viewport,U32.add(x,half),y,half,touched(viewport,U32.add(x,half),y,half)),
        overlay(rest,Pix{color},view,state,viewport,x,U32.add(y,half),half,touched(viewport,x,U32.add(y,half),half)),
        overlay(rest,Pix{color},view,state,viewport,U32.add(x,half),U32.add(y,half),half,touched(viewport,U32.add(x,half),U32.add(y,half),half))}
    case 1n+ +rest Qua{tl,tr,bl,br} True{}:
      +half = U32.div(side,2)
      Qua{overlay(rest,tl,view,state,viewport,x,y,half,touched(viewport,x,y,half)),
        overlay(rest,tr,view,state,viewport,U32.add(x,half),y,half,touched(viewport,U32.add(x,half),y,half)),
        overlay(rest,bl,view,state,viewport,x,U32.add(y,half),half,touched(viewport,x,U32.add(y,half),half)),
        overlay(rest,br,view,state,viewport,U32.add(x,half),U32.add(y,half),half,touched(viewport,U32.add(x,half),U32.add(y,half),half))}

def draw_active(active:Bool,image:Image,view:View,state:State,+viewport:Viewport) -> Image:
  match active:
    case False{}: image
    case True{}:
      Viewport{width,height,nw,nh} = viewport
      +depth = P.array_depth(13n,U32.max(nw,nh),1)
      overlay(depth,image,view,state,viewport,0,0,U32.shln(1,depth),True{})

def draw_native(image:Image,view:View,+state:State,+viewport:Viewport) -> Image:
  Viewport{width,height,nw,nh} = viewport
  draw_active(is_open(state) && viewport_valid(viewport) && visible(layout(width,height)),image,view,state,viewport)

def authority(frame:Frame) -> I.MenuSnapshot & D.Catalog:
  Frame{controller,snapshot,catalog} = frame
  (snapshot,catalog)

def decision_frame(decision:Decision) -> Frame:
  Decision{frame,intents,consumed} = decision
  frame

def acknowledge(frame:Frame,+snapshot:I.MenuSnapshot,accepted:Bool) -> Decision:
  Frame{controller,previous,+catalog} = frame
  decided(snapshot,catalog,completed(controller,snapshot,accepted))
