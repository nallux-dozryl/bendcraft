import Base

# Pinned 26.3 Stitcher rectangle semantics. No image/animation/GPU effects.
type Entry is Data:
  Entry{namespace:String,path:String,width:U32,height:U32,tag:U32}

type Config is Data:
  Config{max_width:U32,max_height:U32,mip_level:U32,padding_setting:U32}

type Limits is Data:
  Limits{max_entries:U32,max_id_codepoints:U32}

type Request is Type:
  Request{config:Config,entries:List<&2,Entry>}

type Holder is Data:
  Holder{entry:Entry,width:U32,height:U32}

type Placement is Data:
  Placement{holder:Holder,x:U32,y:U32}

type Packed is Data:
  Packed{width:U32,height:U32,padding:U32,sorted:List<&2,Holder>,placements:List<&2,Placement>}

type Error is Data:
  Error{code:String,tag:U32,partial:Maybe<&2,Packed>}

# Slots retain the Java tree's depth-first leaf order. Splitting replaces one
# free leaf with the occupied leaf and the exact ordered residual rectangles.
type Slot is Data:
  Slot{x:U32,y:U32,width:U32,height:U32,holder:Maybe<&2,Holder>}

type Storage is Data:
  Storage{width:U32,height:U32,slots:List<&2,Slot>}

def defaults() -> Limits:
  Limits{4096,4096}

def choose(-A:Type,yes:A,no:A,value:Bool) -> A:
  match value:
    case True{}: yes
    case False{}: no

def branch(-A:Type,yes:Unit -> A,no:Unit -> A,value:Bool) -> A:
  match value:
    case True{}: yes(Unit{})
    case False{}: no(Unit{})

# Java int arithmetic helpers are public for independent overflow probes.
# All shifts use Java's low-five-bit distance, including negative raw words.
def sar_with(+value:U32,+distance:Nat,negative:Bool) -> U32:
  match negative:
    case False{}: U32.shrn(value,distance)
    case True{}: U32.or(U32.shrn(value,distance),U32.not(U32.shrn(4294967295,distance)))

def sar(+value:U32,distance:U32) -> U32:
  sar_with(value,U32.to_nat(U32.and(distance,31)),U32.is_ge(value,2147483648))

def padding_exponent(+value:U32) -> U32:
  choose(U32,0,U32.min(value,4),U32.is_ge(value,2147483648))

def padding_raw(level:U32,setting:U32) -> U32:
  U32.shln(U32.shln(1,U32.to_nat(U32.and(level,31))),U32.to_nat(padding_exponent((setting - 1 : U32))))

def round_raw(+value:U32,+level:U32) -> U32:
  +distance = U32.to_nat(U32.and(level,31))
  extra = choose(U32,0,1,U32.is_zero(U32.and(value,(U32.shln(1,distance) - 1 : U32))))
  U32.shln((sar(value,level) + extra : U32),distance)

def power_raw(value:U32) -> U32:
  +a = (value - 1 : U32)
  +b = U32.or(a,sar(a,1))
  +c = U32.or(b,sar(b,2))
  +d = U32.or(c,sar(c,4))
  +e = U32.or(d,sar(d,8))
  (U32.or(e,sar(e,16)) + 1 : U32)

def namespace_char(+c:U32) -> Bool:
  (U32.is_ge(c,97) && U32.is_le(c,122)) || (U32.is_ge(c,48) && U32.is_le(c,57)) || U32.is_eq(c,95) || U32.is_eq(c,45) || U32.is_eq(c,46)

def identifier_chars(text:String,+path:Bool) -> Bool:
  match text:
    case SNil{}: True{}
    case SCon{Chr{+c},rest}: (namespace_char(c) || (path && U32.is_eq(c,47))) && identifier_chars(rest,path)

def identifier_ok(value:Entry) -> Bool:
  Entry{+namespace,path,width,height,tag} = value
  Bool.not(String.eq(namespace,"..")) && identifier_chars(namespace,False{}) && identifier_chars(path,True{})

def id_le(a:Entry,b:Entry) -> Bool:
  Entry{na,+pa,wa,ha,ta} = a
  Entry{nb,+pb,wb,hb,tb} = b
  choose(Bool,String.is_le(na,nb),String.is_lt(pa,pb),String.eq(pa,pb))

def holder_le(a:Holder,b:Holder) -> Bool:
  Holder{ea,+wa,+ha} = a
  Holder{eb,+wb,+hb} = b
  choose(Bool,choose(Bool,id_le(ea,eb),U32.is_gt(wa,wb),U32.is_eq(wa,wb)),U32.is_gt(ha,hb),U32.is_eq(ha,hb))

def guarded(-A:Data,value:A,code:String,tag:U32,ok:Bool) -> Result<&2,&2,Error,A>:
  match ok:
    case True{}: Done{value}
    case False{}: Fail{Error{code,tag,None{}}}

def config_ok(+value:Config) -> Result<&2,&2,Error,Config>:
  Config{+w,+h,level,setting} = value
  do Result<&2,&2,Error,Config>:
    bounded : Config <- guarded(Config,value,"AtlasRange",0,U32.is_gt(w,0) && U32.is_le(w,536870912) && U32.is_gt(h,0) && U32.is_le(h,536870912))
    guarded(Config,bounded,"MipRange",0,U32.is_le(level,24))

def make_holder(+entry:Entry,+config:Config,+limits:Limits) -> Result<&2,&2,Error,Holder>:
  Entry{+ns,+path,+w,+h,+tag} = entry
  Config{mw,mh,+level,setting} = config
  Limits{count,+id_limit} = limits
  +padding = padding_raw(level,setting)
  +rw = round_raw((w + (2 * padding : U32) : U32),level)
  +rh = round_raw((h + (2 * padding : U32) : U32),level)
  do Result<&2,&2,Error,Holder>:
    valid : Entry <- guarded(Entry,entry,"InvalidIdentifier",tag,identifier_ok(entry))
    named : Entry <- guarded(Entry,valid,"IdentifierLimit",tag,Nat.is_le(String.length(ns),U32.to_nat(id_limit)) && Nat.is_le(String.length(path),U32.to_nat(id_limit)))
    sized : Entry <- guarded(Entry,named,"EntryRange",tag,U32.is_gt(w,0) && U32.is_le(w,536870912) && U32.is_gt(h,0) && U32.is_le(h,536870912))
    guarded(Holder,Holder{sized,rw,rh},"HolderRange",tag,U32.is_gt(rw,0) && U32.is_le(rw,536870912) && U32.is_gt(rh,0) && U32.is_le(rh,536870912))

def holders(entries:List<&2,Entry>,+config:Config,+limits:Limits) -> Result<&2,&2,Error,List<&2,Holder>>:
  match entries:
    case Nil{}: Done{[]}
    case entry <> rest:
      do Result<&2,&2,Error,List<&2,Holder>>:
        h : Holder <- make_holder(entry,config,limits)
        t : List<&2,Holder> <- holders(rest,config,limits)
        Done{h <> t}

def split_both(+x:U32,+y:U32,w:U32,h:U32,+hw:U32,+hh:U32,dw:U32,dh:U32,vertical:Bool) -> List<&2,Slot>:
  match vertical:
    case True{}: [Slot{x,(y + hh : U32),hw,dh,None{}},Slot{(x + hw : U32),y,dw,h,None{}}]
    case False{}: [Slot{(x + hw : U32),y,dw,hh,None{}},Slot{x,(y + hh : U32),w,dh,None{}}]

def residual(both:Bool,slot:Slot,holder:Holder) -> List<&2,Slot>:
  match both:
    case True{}:
      Slot{+x,+y,+w,+h,old} = slot
      Holder{entry,+hw,+hh} = holder
      +dw = (w - hw : U32)
      +dh = (h - hh : U32)
      split_both(x,y,w,h,hw,hh,dw,dh,U32.is_ge(U32.max(h,dw),U32.max(w,dh)))
    case False{}:
      Slot{+x,+y,w,h,old} = slot
      Holder{entry,+hw,+hh} = holder
      +dw = (w - hw : U32)
      +dh = (h - hh : U32)
      choose(List<&2,Slot>,choose(List<&2,Slot>,[],[Slot{x,(y + hh : U32),hw,dh,None{}}],U32.is_zero(dh)),[Slot{(x + hw : U32),y,dw,hh,None{}}],U32.is_zero(dw))

def split_slot(+slot:Slot,+holder:Holder) -> List<&2,Slot>:
  Slot{+x,+y,w,h,old} = slot
  Holder{entry,+hw,+hh} = holder
  Slot{x,y,hw,hh,Some{holder}} <> residual(U32.is_gt(w,hw) && U32.is_gt(h,hh),slot,holder)

def fits(slot:Slot,holder:Holder) -> Bool:
  match slot:
    case Slot{x,y,w,h,Some{old}}: False{}
    case Slot{x,y,w,h,None{}}:
      Holder{entry,hw,hh} = holder
      U32.is_le(hw,w) && U32.is_le(hh,h)

def found_slot(result:List<&2,Slot> & Bool,slot:Slot) -> List<&2,Slot> & Bool:
  (rest,found) = result
  (slot <> rest,found)

def use_slot(slot:Slot,rest:List<&2,Slot>,holder:Holder) -> List<&2,Slot> & Bool:
  (List.append(&2,Slot,split_slot(slot,holder),rest),True{})

def add_slots(slots:List<&2,Slot>,+holder:Holder) -> List<&2,Slot> & Bool:
  match slots:
    case Nil{}: ([],False{})
    case +slot <> +rest:
      branch(List<&2,Slot> & Bool,u => use_slot(slot,rest,holder),u => found_slot(add_slots(rest,holder),slot),fits(slot,holder))

def append_region(regions:List<&2,Slot>,old:List<&2,Slot>,width:U32,height:U32) -> Storage & Bool:
  (Storage{width,height,List.append(&2,Slot,old,regions)},True{})

def append_region_result(result:List<&2,Slot> & Bool,old:List<&2,Slot>,width:U32,height:U32) -> Storage & Bool:
  (regions,ignored) = result
  append_region(regions,old,width,height)

def expand_axis(x_axis:Bool,old:Storage,holder:Holder,+px:U32,+py:U32) -> Storage & Bool:
  match x_axis:
    case True{}:
      Storage{+x,+y,slots} = old
      +height = choose(U32,py,y,U32.is_zero(y))
      append_region_result(add_slots([Slot{x,0,(px - x : U32),height,None{}}],holder),slots,px,height)
    case False{}:
      Storage{+x,+y,slots} = old
      append_region_result(add_slots([Slot{0,y,x,(py - y : U32),None{}}],holder),slots,x,py)

def expand_choice(old:Storage,holder:Holder,+px:U32,+py:U32,+cx:Bool,cy:Bool,+sx:U32,+sy:U32,allowed:Bool) -> Storage & Bool:
  match allowed:
    case False{}: (old,False{})
    case True{}:
      +change_x = cx && U32.is_ne(sx,px)
      +change_y = cy && U32.is_ne(sy,py)
      expand_axis(choose(Bool,change_x,cx && U32.is_le(sx,sy),Bool.xor(change_x,change_y)),old,holder,px,py)

def expand(+old:Storage,+holder:Holder,config:Config) -> Storage & Bool:
  Storage{+x,+y,slots} = old
  Holder{entry,hw,hh} = holder
  Config{mw,mh,level,setting} = config
  +px = power_raw((x + hw : U32))
  +py = power_raw((y + hh : U32))
  +cx = U32.is_le(px,mw)
  +cy = U32.is_le(py,mh)
  expand_choice(old,holder,px,py,cx,cy,power_raw(x),power_raw(y),cx || cy)

def added_found(found:Bool,slots:List<&2,Slot>,width:U32,height:U32,holder:Holder,config:Config) -> Storage & Bool:
  match found:
    case True{}: (Storage{width,height,slots},True{})
    case False{}: expand(Storage{width,height,slots},holder,config)

def added(result:List<&2,Slot> & Bool,width:U32,height:U32,holder:Holder,config:Config) -> Storage & Bool:
  (slots,found) = result
  added_found(found,slots,width,height,holder,config)

def add(+old:Storage,+holder:Holder,config:Config) -> Storage & Bool:
  Storage{width,height,slots} = old
  added(add_slots(slots,holder),width,height,holder,config)

def placements(slots:List<&2,Slot>) -> List<&2,Placement>:
  match slots:
    case Nil{}: []
    case Slot{x,y,w,h,None{}} <> rest: placements(rest)
    case Slot{x,y,w,h,Some{holder}} <> rest: Placement{holder,x,y} <> placements(rest)

def packed(storage:Storage,sorted:List<&2,Holder>,padding:U32) -> Packed:
  Storage{w,h,slots} = storage
  Packed{w,h,padding,sorted,placements(slots)}

def finish_step(result:Storage & Bool,success:Storage -> Result<&2,&2,Error,Packed>,failure:Storage -> Result<&2,&2,Error,Packed>) -> Result<&2,&2,Error,Packed>:
  (+next,ok) = result
  branch(Result<&2,&2,Error,Packed>,u => success(next),u => failure(next),ok)

def proceed(todo:List<&2,Holder>,+sorted:List<&2,Holder>,+config:Config,state:Storage) -> Result<&2,&2,Error,Packed>:
  match todo:
    case Nil{}:
      Config{w,h,level,setting} = config
      Done{packed(state,sorted,padding_raw(level,setting))}
    case +holder <> +rest:
      Holder{Entry{ns,path,w,h,tag},hw,hh} = holder
      Config{mw,mh,level,setting} = config
      finish_step(add(state,holder,config),next => proceed(rest,sorted,config,next),next => Fail{Error{"NoSpace",tag,Some{packed(next,sorted,padding_raw(level,setting))}}})

def sorted_pack(values:List<&2,Holder>,+config:Config) -> Result<&2,&2,Error,Packed>:
  +sorted = List.sort(~Holder,~holder_le,values)
  proceed(sorted,sorted,config,Storage{0,0,[]})

def packing(+entries:List<&2,Entry>,+config:Config,+limits:Limits) -> Result<&2,&2,Error,Packed>:
  Limits{count,id_limit} = limits
  do Result<&2,&2,Error,Packed>:
    valid : Config <- config_ok(config)
    bounded : List<&2,Entry> <- guarded(List<&2,Entry>,entries,"EntryLimit",0,Nat.is_le(List.length(&2,Entry,entries),U32.to_nat(count)))
    values : List<&2,Holder> <- holders(bounded,valid,limits)
    sorted_pack(values,config)

# Request remains the sole affine token on every success/policy/NoSpace path.
def pack(request:Request,limits:Limits) -> Request & Result<&2,&2,Error,Packed>:
  Request{+config,+entries} = request
  (Request{config,entries},packing(entries,config,limits))

def placement_inside(value:Placement,+width:U32,+height:U32) -> Bool:
  Placement{Holder{entry,w,h},x,y} = value
  U32.is_le((x + w : U32),width) && U32.is_le((y + h : U32),height)

def all_inside(values:List<&2,Placement>,+w:U32,+h:U32) -> Bool:
  match values:
    case Nil{}: True{}
    case p <> rest: placement_inside(p,w,h) && all_inside(rest,w,h)

# Separate caller admission: Java can report success after dropping an oversized
# first holder, or initialize height beyond maxHeight. Do not mask that behavior.
def complete_within(+result:Packed,config:Config) -> Bool:
  Packed{+w,+h,padding,sorted,+placed} = result
  Config{mw,mh,level,setting} = config
  U32.is_le(w,mw) && U32.is_le(h,mh) && Nat.is_eq(List.length(&2,Holder,sorted),List.length(&2,Placement,placed)) && all_inside(placed,w,h)

def close_request(request:Request) -> Unit:
  Unit{}

law padding_zero:
  {padding_raw(0,0) == 1 : U32}
def padding_zero():
  {==}

law round_sixteen:
  {round_raw(18,2) == 20 : U32}
def round_sixteen():
  {==}

law empty_power:
  {power_raw(0) == 0 : U32}
def empty_power():
  {==}
