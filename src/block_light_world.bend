import Base
import ./block_light.bend as B
import ./core.bend as C
import ./section.bend as S
import ./section_map.bend as M
import ./schedule.bend as Q

# The authoritative Core.World and light field have one joined affine owner.
# Initial loading forbids edits/ticks/sampling, but may be resumed after a
# missing descriptor is supplied. No array is cloned or retained separately.
type Work is Data:
  Work{origin:C.Position,index:U32,cells:List<&2,U32>}
type Cursor is Data:
  Cursor{keys:List<&2,String>,active:Maybe<&2,Work>}
type State is Type:
  State{world:C.World,light:B.State,loading:Maybe<&2,Cursor>}
type Error is Data:
  CoreFailure{error:C.Error}
  LoadingInProgress{}
  MissingDescriptor{state:U32}
  InvalidDescriptor{state:U32}
  InvalidSectionKey{key:String}
  LightPending{pending:Nat}
  ResidencyMismatch{position:C.Position}
type Progress is Data:
  Loading{}
  Settled{}
  Propagating{pending:Nat}
type Observation is Data:
  Observation{position:C.Position,block:Maybe<&2,U32>,light:Maybe<&2,U32>}
type FrameSamples is Data:
  FrameSamples{clock:C.Clock,cells:List<&2,Observation>}
type Prepared is Data:
  Plain{mutation:C.Mutation}
  Block{position:C.Position,descriptor:B.Descriptor}
  Fill{position:C.Position,descriptor:B.Descriptor}
type Due is Data:
  Due{stamp:Q.Stamp,operation:Prepared}

def origin(position:C.Position) -> C.Position:
  C.Position{dimension,x,y,z} = position
  C.Position{dimension,S.Coord.compose_value(S.Coord.section(x),0),
    S.Coord.compose_value(S.Coord.section(y),0),S.Coord.compose_value(S.Coord.section(z),0)}

def indexed(position:C.Position,+index:U32) -> C.Position:
  C.Position{dimension,x,y,z} = position
  C.Position{dimension,U32.add(x,U32.and(index,15)),
    U32.add(y,U32.shrn(index,8n)),U32.add(z,U32.and(U32.shrn(index,4n),15))}

def key_checked(+key:String,+dimension:String,+x:U32,+y:U32,+z:U32,
    valid:Bool) -> Result<&2,&2,Error,C.Position>:
  match valid:
    case False{}: Fail{InvalidSectionKey{key}}
    case True{}:
      Done{C.Position{dimension,S.Coord.compose_value(x,0),
        S.Coord.compose_value(y,0),S.Coord.compose_value(z,0)}}

def key_numbers(+key:String,+dimension:String,px:Maybe<&2,U32>,
    py:Maybe<&2,U32>,pz:Maybe<&2,U32>) -> Result<&2,&2,Error,C.Position>:
  match px py pz:
    case Some{+x} Some{+y} Some{+z}:
      key_checked(key,dimension,x,y,z,C.dimension_known(dimension) &&
        S.Coord.section_valid(x) && S.Coord.section_valid(y) && S.Coord.section_valid(z) &&
        String.eq(key,dimension ++ "/" ++ U32.show(x) ++ "/" ++ U32.show(y) ++ "/" ++ U32.show(z)))
    case _ _ _: Fail{InvalidSectionKey{key}}

def key_parts(key:String,parts:List<&2,String>) -> Result<&2,&2,Error,C.Position>:
  match parts:
    case dimension <> x <> y <> z <> Nil{}:
      key_numbers(key,dimension,U32.read(x),U32.read(y),U32.read(z))
    case _: Fail{InvalidSectionKey{key}}

def key_origin(+key:String) -> Result<&2,&2,Error,C.Position>:
  key_parts(key,String.split(key,'/'))

# Enumeration and snapshots reconstruct the exact trie/bucket order; unlike
# pop/set, neither operation turns a query into a map mutation.
def keys_entry(+key:String,section:S.Section,
    rest:List<&1,M.Entry> & List<&2,String>) -> List<&1,M.Entry> & List<&2,String>:
  (entries,keys) = rest
  (M.Entry{key,section} <> entries,key <> keys)
def keys_entries(entries:List<&1,M.Entry>) -> List<&1,M.Entry> & List<&2,String>:
  match entries:
    case Nil{}: ([],[])
    case M.Entry{key,section} <> rest: keys_entry(key,section,keys_entries(rest))
def keys_leaf(result:List<&1,M.Entry> & List<&2,String>) -> M.Sections & List<&2,String>:
  (entries,keys) = result
  (M.Bucket{entries},keys)
def keys_branch(left:M.Sections & List<&2,String>,right:M.Sections & List<&2,String>) ->
    M.Sections & List<&2,String>:
  (lo,a) = left
  (hi,b) = right
  (M.Branch{lo,hi},List.append(&2,String,a,b))
def section_keys(sections:M.Sections) -> M.Sections & List<&2,String>:
  match sections:
    case M.EmptySections{}: (M.EmptySections{},[])
    case M.Bucket{entries}: keys_leaf(keys_entries(entries))
    case M.Branch{lo,hi}: keys_branch(section_keys(lo),section_keys(hi))
def begin_keys(world:C.World,result:M.Sections & List<&2,String>) -> State:
  (sections,keys) = result
  State{C.replace_sections(world,sections),B.new(),Some{Cursor{keys,None{}}}}
def begin(world:C.World) -> State:
  C.World{tick,time,paused,daylight,revision,count,sections,pending,events} = world
  begin_keys(C.World{tick,time,paused,daylight,revision,count,M.EmptySections{},pending,events},
    section_keys(sections))

def snapshot_hit(key:String,tail:List<&1,M.Entry>,
    result:S.Section & List<&2,U32>) -> List<&1,M.Entry> & Maybe<&2,List<&2,U32>>:
  (section,cells) = result
  (M.Entry{key,section} <> tail,Some{cells})
def snapshot_skip(head:M.Entry,result:List<&1,M.Entry> & Maybe<&2,List<&2,U32>>) ->
    List<&1,M.Entry> & Maybe<&2,List<&2,U32>>:
  (tail,cells) = result
  (head <> tail,cells)
def snapshot_entry(hit:Bool,key:String,section:S.Section,
    result:List<&1,M.Entry> & Maybe<&2,List<&2,U32>>) ->
    List<&1,M.Entry> & Maybe<&2,List<&2,U32>>:
  match hit:
    case True{}:
      (tail,ignored) = result
      snapshot_hit(key,tail,S.Section.snapshot(section))
    case False{}: snapshot_skip(M.Entry{key,section},result)
def snapshot_entries(entries:List<&1,M.Entry>,+key:String) ->
    List<&1,M.Entry> & Maybe<&2,List<&2,U32>>:
  match entries:
    case Nil{}: ([],None{})
    case M.Entry{+candidate,section} <> tail:
      snapshot_entry(String.eq(candidate,key),candidate,section,snapshot_entries(tail,key))
def snapshot_leaf(result:List<&1,M.Entry> & Maybe<&2,List<&2,U32>>) ->
    M.Sections & Maybe<&2,List<&2,U32>>:
  (entries,cells) = result
  (M.Bucket{entries},cells)
def snapshot_left(hi:M.Sections,result:M.Sections & Maybe<&2,List<&2,U32>>) ->
    M.Sections & Maybe<&2,List<&2,U32>>:
  (lo,cells) = result
  (M.Branch{lo,hi},cells)
def snapshot_right(lo:M.Sections,result:M.Sections & Maybe<&2,List<&2,U32>>) ->
    M.Sections & Maybe<&2,List<&2,U32>>:
  (hi,cells) = result
  (M.Branch{lo,hi},cells)
def snapshot_branch(bit:U32,lo:M.Sections,hi:M.Sections,
    left:M.Sections -> M.Sections & Maybe<&2,List<&2,U32>>,
    right:M.Sections -> M.Sections & Maybe<&2,List<&2,U32>>) ->
    M.Sections & Maybe<&2,List<&2,U32>>:
  match bit:
    case 0: snapshot_left(hi,left(lo))
    case _: snapshot_right(lo,right(hi))
def snapshot_go(+depth:Nat,sections:M.Sections,+bits:U32,+key:String) ->
    M.Sections & Maybe<&2,List<&2,U32>>:
  match depth sections:
    case _ M.EmptySections{}: (M.EmptySections{},None{})
    case 0n M.Bucket{entries}: snapshot_leaf(snapshot_entries(entries,key))
    case 1n+rest M.Branch{lo,hi}:
      snapshot_branch(U32.and(bits,1),lo,hi,
        lo => snapshot_go(rest,lo,U32.shr(bits),key),
        hi => snapshot_go(rest,hi,U32.shr(bits),key))
    case _ other: (other,None{})
def snapshot_world(world:C.World,result:M.Sections & Maybe<&2,List<&2,U32>>) ->
    C.World & Maybe<&2,List<&2,U32>>:
  (sections,cells) = result
  (C.replace_sections(world,sections),cells)
def snapshot(world:C.World,+key:String) -> C.World & Maybe<&2,List<&2,U32>>:
  C.World{tick,time,paused,daylight,revision,count,sections,pending,events} = world
  snapshot_world(C.World{tick,time,paused,daylight,revision,count,M.EmptySections{},pending,events},
    snapshot_go(32n,sections,M.hash(key),key))

def effective(enabled:Bool,state:U32,emission:U32,dampening:U32) -> B.Descriptor:
  match enabled:
    case True{}: B.Descriptor{state,emission,dampening}
    case False{}: B.Descriptor{state,0,dampening}
def descriptor_checked(state:U32,descriptor:B.Descriptor,enabled:Bool,valid:Bool) ->
    Result<&2,&2,Error,B.Descriptor>:
  B.Descriptor{id,emission,dampening} = descriptor
  match valid:
    case False{}: Fail{InvalidDescriptor{state}}
    case True{}: Done{effective(enabled,id,emission,dampening)}
def descriptor_result(+state:U32,enabled:Bool,found:Maybe<&2,B.Descriptor>) ->
    Result<&2,&2,Error,B.Descriptor>:
  match found:
    case None{}: Fail{MissingDescriptor{state}}
    case Some{+descriptor}:
      B.Descriptor{id,emission,dampening} = descriptor
      descriptor_checked(state,descriptor,enabled,U32.is_eq(id,state) &&
        B.descriptor_valid(descriptor))
def descriptor(~Context:Data,~properties:Context -> U32 -> Maybe<&2,B.Descriptor>,
    ~enabled:Context -> C.Position -> Bool,+context:Context,position:C.Position,+state:U32) ->
    Result<&2,&2,Error,B.Descriptor>:
  descriptor_result(state,enabled(context,origin(position)),properties(context,state))
def published(result:B.State & Result<&2,&2,B.Error,Unit>) -> B.State:
  (state,status) = result
  state

# Bootstrap starts at B.new and cannot advance/edit until its cursor ends.
# All resident levels therefore start0. Only effective emitters can initiate a
# positive change; their changes will schedule each subsequent consumer through
# B.advance. Nonemitters need no initial self/neighbor notifications.
def initial_notify(emits:Bool,position:C.Position,state:B.State) -> B.State:
  match emits:
    case False{}: state
    case True{}: B.notify(state,position)
def initial_light(light:B.State,+position:C.Position,+descriptor:B.Descriptor) -> B.State:
  B.State{cells,front,back,queued,pending} = light
  initial_notify(U32.is_gt(B.emission(descriptor),0),position,
    B.State{Map.set(&2,Maybe<&2,B.Cell>,cells,B.key(position),Some{B.Cell{descriptor,0}}),
      front,back,queued,pending})

def load_cell(state:State,keys:List<&2,String>,
    +position:C.Position,+index:U32,+id:U32,tail:List<&2,U32>,result:Result<&2,&2,Error,B.Descriptor>,
    next:State -> State & Result<&2,&2,Error,Unit>) -> State & Result<&2,&2,Error,Unit>:
  State{world,light,old} = state
  match result:
    case Fail{error}:
      (State{world,light,Some{Cursor{keys,Some{Work{position,index,id <> tail}}}}},Fail{error})
    case Done{descriptor}:
      next(State{world,initial_light(light,indexed(position,index),descriptor),
        Some{Cursor{keys,Some{Work{position,U32.inc(index),tail}}}}})
def load_snapshot(state:State,+key:String,keys:List<&2,String>,position:C.Position,
    observed:C.World & Maybe<&2,List<&2,U32>>,
    next:State -> State & Result<&2,&2,Error,Unit>) -> State & Result<&2,&2,Error,Unit>:
  State{ignored,light,old} = state
  (world,cells) = observed
  match cells:
    case None{}:
      (State{world,light,Some{Cursor{key <> keys,None{}}}},Fail{CoreFailure{C.MissingSection{key}}})
    case Some{cells}: next(State{world,light,Some{Cursor{keys,Some{Work{position,0,cells}}}}})
def load_key(state:State,+key:String,keys:List<&2,String>,parsed:Result<&2,&2,Error,C.Position>,
    next:State -> State & Result<&2,&2,Error,Unit>) -> State & Result<&2,&2,Error,Unit>:
  State{world,light,old} = state
  match parsed:
    case Fail{error}: (State{world,light,Some{Cursor{key <> keys,None{}}}},Fail{error})
    case Done{position}:
      load_snapshot(State{C.new(0),light,None{}},key,keys,position,snapshot(world,key),next)

# Each scalar publication and each section acquisition consumes one unit.
# Acquisition snapshots exactly4096 scalar IDs and returns the original array.
def load_resume(~Context:Data,~properties:Context -> U32 -> Maybe<&2,B.Descriptor>,
    ~enabled:Context -> C.Position -> Bool,+context:Context,budget:Nat,state:State) ->
    State & Result<&2,&2,Error,Unit>:
  match budget state:
    case 0n state: (state,Done{Unit{}})
    case 1n+rest State{world,light,None{}}: (State{world,light,None{}},Done{Unit{}})
    case 1n+rest State{world,light,Some{Cursor{keys,Some{Work{+p,i,+id <> tail}}}}}:
      load_cell(State{world,light,None{}},keys,p,i,id,tail,
        descriptor(~Context,~properties,~enabled,context,p,id),
        state => load_resume(~Context,~properties,~enabled,context,rest,state))
    case 1n+rest State{world,light,Some{Cursor{keys,Some{Work{p,i,Nil{}}}}}}:
      load_resume(~Context,~properties,~enabled,context,rest,State{world,light,Some{Cursor{keys,None{}}}})
    case 1n+rest State{world,light,Some{Cursor{Nil{},None{}}}}:
      (State{world,light,None{}},Done{Unit{}})
    case 1n+rest State{world,light,Some{Cursor{+key <> keys,None{}}}}:
      load_key(State{world,light,None{}},key,keys,key_origin(key),
        state => load_resume(~Context,~properties,~enabled,context,rest,state))

def fill_light(fuel:Nat,+index:U32,+position:C.Position,+descriptor:B.Descriptor,
    light:B.State) -> B.State:
  match fuel:
    case 0n: light
    case 1n+rest:
      fill_light(rest,U32.inc(index),position,descriptor,
        published(B.publish(light,indexed(position,index),descriptor)))
def changed_light(operation:Prepared,light:B.State) -> B.State:
  match operation:
    case Plain{mutation}: light
    case Block{position,descriptor}: published(B.publish(light,position,descriptor))
    case Fill{position,descriptor}: fill_light(4096n,0,origin(position),descriptor,light)
def prepared_mutation(operation:Prepared) -> C.Mutation:
  match operation:
    case Plain{mutation}: mutation
    case Block{position,B.Descriptor{id,e,d}}: C.BlockSet{position,id}
    case Fill{position,B.Descriptor{id,e,d}}: C.SectionCreate{position,id}
def prepare_descriptor(fill:Bool,position:C.Position,result:Result<&2,&2,Error,B.Descriptor>) ->
    Result<&2,&2,Error,Prepared>:
  match fill result:
    case _ Fail{error}: Fail{error}
    case False{} Done{descriptor}: Done{Block{position,descriptor}}
    case True{} Done{descriptor}: Done{Fill{position,descriptor}}
def prepare(~Context:Data,~properties:Context -> U32 -> Maybe<&2,B.Descriptor>,
    ~enabled:Context -> C.Position -> Bool,context:Context,mutation:C.Mutation) ->
    Result<&2,&2,Error,Prepared>:
  match mutation:
    case C.BlockSet{+p,id}:
      prepare_descriptor(False{},p,descriptor(~Context,~properties,~enabled,context,p,id))
    case C.SectionCreate{+p,id}:
      prepare_descriptor(True{},p,descriptor(~Context,~properties,~enabled,context,p,id))
    case other: Done{Plain{other}}
def core_valid(result:Result<&2,&2,C.Error,Unit>) -> Result<&2,&2,Error,Unit>:
  match result:
    case Done{u}: Done{Unit{}}
    case Fail{error}: Fail{CoreFailure{error}}
def checked_prepare(~Context:Data,~properties:Context -> U32 -> Maybe<&2,B.Descriptor>,
    ~enabled:Context -> C.Position -> Bool,context:Context,mutation:C.Mutation,
    valid:Result<&2,&2,C.Error,Unit>) -> Result<&2,&2,Error,Prepared>:
  match valid:
    case Fail{error}: Fail{CoreFailure{error}}
    case Done{u}: prepare(~Context,~properties,~enabled,context,mutation)
def applied(state:State,+operation:Prepared,result:C.World & Result<&2,&2,C.Error,Unit>) ->
    State & Result<&2,&2,Error,Unit>:
  State{ignored,light,loading} = state
  (world,status) = result
  match status:
    case Fail{error}: (State{world,light,loading},Fail{CoreFailure{error}})
    case Done{u}: (State{world,changed_light(operation,light),loading},Done{Unit{}})
def apply_prepared(state:State,+operation:Prepared) -> State & Result<&2,&2,Error,Unit>:
  State{world,light,loading} = state
  applied(State{C.new(0),light,loading},operation,C.apply(world,prepared_mutation(operation)))
def apply_existing(state:State,+operation:Prepared,+position:C.Position,fill:Bool,
    read:C.World & Result<&2,&2,C.Error,U32>) -> State & Result<&2,&2,Error,Unit>:
  State{ignored,light,loading} = state
  match fill read:
    case True{} Tuple{world,Done{id}}:
      (State{world,light,loading},Fail{CoreFailure{C.SectionExists{C.section_key(position)}}})
    case True{} Tuple{world,Fail{C.MissingSection{key}}}: apply_prepared(State{world,light,loading},operation)
    case False{} Tuple{world,Done{id}}: apply_prepared(State{world,light,loading},operation)
    case _ Tuple{world,Fail{error}}: (State{world,light,loading},Fail{CoreFailure{error}})
def apply_checked(state:State,prepared:Result<&2,&2,Error,Prepared>) ->
    State & Result<&2,&2,Error,Unit>:
  State{world,light,loading} = state
  match prepared:
    case Fail{error}: (State{world,light,loading},Fail{error})
    case Done{Plain{mutation}}: apply_prepared(State{world,light,loading},Plain{mutation})
    case Done{Block{+position,+descriptor}}:
      apply_existing(State{C.new(0),light,loading},Block{position,descriptor},position,False{},
        C.read_block(world,position))
    case Done{Fill{+position,+descriptor}}:
      apply_existing(State{C.new(0),light,loading},Fill{position,descriptor},position,True{},
        C.read_block(world,position))

# Low-level authorized application: mirrors Core.apply, with validation and
# catalog preflight. The public scheduled actor seam below owns permissions.
def apply(~Context:Data,~properties:Context -> U32 -> Maybe<&2,B.Descriptor>,
    ~enabled:Context -> C.Position -> Bool,context:Context,state:State,+mutation:C.Mutation) ->
    State & Result<&2,&2,Error,Unit>:
  match state:
    case State{world,light,Some{cursor}}:
      (State{world,light,Some{cursor}},Fail{LoadingInProgress{}})
    case State{C.World{tick,time,paused,daylight,revision,+count,sections,pending,events},light,None{}}:
      apply_checked(State{C.World{tick,time,paused,daylight,revision,count,sections,pending,events},light,None{}},
        checked_prepare(~Context,~properties,~enabled,context,mutation,C.validate(mutation,count)))

def apply_finished(stamp:Q.Stamp,result:State & Result<&2,&2,Error,Unit>) ->
    State & Result<&2,&2,Error,Unit>:
  (State{world,light,loading},+status) = result
  match status:
    case Done{u}: (State{C.finish(world,stamp,Done{Unit{}}),light,loading},Done{Unit{}})
    case Fail{error}: (State{world,light,loading},Fail{error})

def admission_valid(permission:Bool,future:Bool,room:Bool,
    valid:Result<&2,&2,C.Error,Unit>) -> Result<&2,&2,C.Error,Unit>:
  match permission future room valid:
    case False{} _ _ _: Fail{C.PermissionDenied{}}
    case True{} False{} _ _: Fail{C.PastTick{}}
    case True{} True{} False{} _: Fail{C.TooManyPending{}}
    case True{} True{} True{} result: result
def admitted(state:State,result:C.World & Result<&2,&2,C.Error,Unit>) ->
    State & Result<&2,&2,Error,Unit>:
  State{ignored,light,loading} = state
  (world,status) = result
  (State{world,light,loading},core_valid(status))
def admit_prepared(state:State,cap:C.Capability,stamp:Q.Stamp,mutation:C.Mutation,
    prepared:Result<&2,&2,Error,Prepared>) -> State & Result<&2,&2,Error,Unit>:
  State{world,light,loading} = state
  match prepared:
    case Fail{error}: (State{world,light,loading},Fail{error})
    case Done{operation}:
      admitted(State{C.new(0),light,loading},C.admit(world,cap,stamp,mutation))

# Catalog preflight cannot bypass Core admission: capability, tick, queue limit
# and registry validation are checked in Core order, then actual C.admit runs.
# Admission may queue while bootstrap is active; step refuses until it ends.
def admit(~Context:Data,~properties:Context -> U32 -> Maybe<&2,B.Descriptor>,
    ~enabled:Context -> C.Position -> Bool,context:Context,state:State,+cap:C.Capability,
    +stamp:Q.Stamp,+mutation:C.Mutation) -> State & Result<&2,&2,Error,Unit>:
  State{C.World{+tick,time,paused,daylight,revision,+count,sections,+pending,events},light,loading} = state
  admit_prepared(State{C.World{tick,time,paused,daylight,revision,count,sections,pending,events},light,loading},
    cap,stamp,mutation,checked_prepare(~Context,~properties,~enabled,context,mutation,
      admission_valid(C.developer(cap),Nat.is_gt(Q.stamp_tick(stamp),tick),
        Nat.is_lt(Q.length(C.Mutation,pending),4096n),C.validate(mutation,count))))

def due_cons(stamp:Q.Stamp,head:Result<&2,&2,Error,Prepared>,
    tail:Result<&2,&2,Error,List<&2,Due>>) -> Result<&2,&2,Error,List<&2,Due>>:
  match head tail:
    case Fail{error} _: Fail{error}
    case Done{operation} Fail{error}: Fail{error}
    case Done{operation} Done{rest}: Done{Due{stamp,operation} <> rest}
def prepare_due(~Context:Data,~properties:Context -> U32 -> Maybe<&2,B.Descriptor>,
    ~enabled:Context -> C.Position -> Bool,ps:List<&2,Q.Pending<C.Mutation>>,
    +context:Context,+count:U32) -> Result<&2,&2,Error,List<&2,Due>>:
  match ps:
    case Nil{}: Done{[]}
    case Q.Pending{stamp,+mutation} <> rest:
      due_cons(stamp,checked_prepare(~Context,~properties,~enabled,context,mutation,C.validate(mutation,count)),
        prepare_due(~Context,~properties,~enabled,rest,context,count))
def due_applied(+stamp:Q.Stamp,+operation:Prepared,light:B.State,
    result:C.World & Result<&2,&2,C.Error,Unit>) -> State:
  (world,+status) = result
  match status:
    case Fail{error}: State{C.finish(world,stamp,status),light,None{}}
    case Done{u}: State{C.finish(world,stamp,status),changed_light(operation,light),None{}}
def apply_due(ps:List<&2,Due>,state:State) -> State:
  match ps:
    case Nil{}: state
    case Due{stamp,+operation} <> rest:
      State{world,light,loading} = state
      apply_due(rest,due_applied(stamp,operation,light,C.apply(world,prepared_mutation(operation))))
def step_prepared(state:State,future:List<&2,Q.Pending<C.Mutation>>,
    prepared:Result<&2,&2,Error,List<&2,Due>>) -> State & Result<&2,&2,Error,Unit>:
  State{C.World{+tick,time,paused,+daylight,revision,count,sections,pending,events},light,loading} = state
  match prepared:
    case Fail{error}:
      (State{C.World{tick,time,paused,daylight,revision,count,sections,pending,events},light,loading},Fail{error})
    case Done{due}:
      (apply_due(due,State{C.World{1n+tick,C.daylight_tick(time,daylight),paused,daylight,
        revision,count,sections,future,events},light,None{}}),Done{Unit{}})
def step_partition(~Context:Data,~properties:Context -> U32 -> Maybe<&2,B.Descriptor>,
    ~enabled:Context -> C.Position -> Bool,context:Context,state:State,count:U32,
    partition:List<&2,Q.Pending<C.Mutation>> & List<&2,Q.Pending<C.Mutation>>) ->
    State & Result<&2,&2,Error,Unit>:
  (due,future) = partition
  step_prepared(state,future,prepare_due(~Context,~properties,~enabled,due,context,count))

# Whole due-batch descriptor preflight happens before advancing Core's clock.
# Missing catalog data keeps tick, pending actions and both owners unchanged.
# Actual C.apply/C.finish retain Core ordering, events and revision semantics.
def step(~Context:Data,~properties:Context -> U32 -> Maybe<&2,B.Descriptor>,
    ~enabled:Context -> C.Position -> Bool,context:Context,state:State) ->
    State & Result<&2,&2,Error,Unit>:
  match state:
    case State{world,light,Some{cursor}}:
      (State{world,light,Some{cursor}},Fail{LoadingInProgress{}})
    case State{C.World{+tick,time,paused,daylight,revision,+count,sections,+pending,events},light,None{}}:
      step_partition(~Context,~properties,~enabled,context,
        State{C.World{tick,time,paused,daylight,revision,count,sections,pending,events},light,None{}},count,
        Q.take_due(C.Mutation,pending,1n+tick))
def realtime_choose(~Context:Data,~properties:Context -> U32 -> Maybe<&2,B.Descriptor>,
    ~enabled:Context -> C.Position -> Bool,context:Context,paused:Bool,state:State) ->
    State & Result<&2,&2,Error,Unit>:
  match paused:
    case True{}: (state,Done{Unit{}})
    case False{}: step(~Context,~properties,~enabled,context,state)
def realtime_step(~Context:Data,~properties:Context -> U32 -> Maybe<&2,B.Descriptor>,
    ~enabled:Context -> C.Position -> Bool,context:Context,state:State) ->
    State & Result<&2,&2,Error,Unit>:
  State{C.World{tick,time,+paused,daylight,revision,count,sections,pending,events},light,loading} = state
  realtime_choose(~Context,~properties,~enabled,context,paused,
    State{C.World{tick,time,paused,daylight,revision,count,sections,pending,events},light,loading})

def progress_status(status:B.Status) -> Progress:
  match status:
    case B.Stable{}: Settled{}
    case B.MoreWork{pending}: Propagating{pending}
def progress(state:State) -> State & Progress:
  match state:
    case State{world,light,Some{cursor}}: (State{world,light,Some{cursor}},Loading{})
    case State{world,light,None{}}:
      B.paired(B.State,B.Status,State & Progress,B.status(light),
        light => status => (State{world,light,None{}},progress_status(status)))
def advance(~Context:Data,~occludes:Context -> B.Descriptor -> B.Descriptor -> B.Direction -> Bool,
    context:Context,budget:Nat,state:State) -> State & Progress:
  match state:
    case State{world,light,Some{cursor}}: (State{world,light,Some{cursor}},Loading{})
    case State{world,light,None{}}:
      B.paired(B.State,B.Status,State & Progress,B.advance(~Context,~occludes,context,budget,light),
        light => status => (State{world,light,None{}},progress_status(status)))

def observed(position:C.Position,result:Result<&2,&2,C.Error,U32>,level:Maybe<&2,U32>) ->
    Result<&2,&2,Error,Observation>:
  match result level:
    case Done{id} Some{light}: Done{Observation{position,Some{id},Some{light}}}
    case Fail{C.MissingSection{key}} None{}: Done{Observation{position,None{},None{}}}
    case _ _: Fail{ResidencyMismatch{position}}
def samples_cons(result:Result<&2,&2,Error,Observation>,state:State,
    tail:State -> State & Result<&2,&2,Error,List<&2,Observation>>) ->
    State & Result<&2,&2,Error,List<&2,Observation>>:
  match result:
    case Fail{error}: (state,Fail{error})
    case Done{cell}:
      B.paired(State,Result<&2,&2,Error,List<&2,Observation>>,State & Result<&2,&2,Error,List<&2,Observation>>,
        tail(state),state => result => (state,Result.map(&2,&2,Error,List<&2,Observation>,List<&2,Observation>,
          cells => cell <> cells,result)))
def samples(positions:List<&2,C.Position>,state:State) ->
    State & Result<&2,&2,Error,List<&2,Observation>>:
  match positions:
    case Nil{}: (state,Done{[]})
    case +position <> rest:
      State{world,light,loading} = state
      B.paired(C.World,Result<&2,&2,C.Error,U32>,State & Result<&2,&2,Error,List<&2,Observation>>,
        C.read_block(world,position),world => read =>
        B.paired(B.State,Maybe<&2,U32>,State & Result<&2,&2,Error,List<&2,Observation>>,
          B.sample(light,position),light => level =>
            samples_cons(observed(position,read,level),State{world,light,loading},
              state => samples(rest,state))))
def frame_result(result:State & Result<&2,&2,Error,List<&2,Observation>>) ->
    State & Result<&2,&2,Error,FrameSamples>:
  (State{world,light,loading},cells) = result
  B.paired(C.World,C.Clock,State & Result<&2,&2,Error,FrameSamples>,C.clock(world),world => clock =>
    (State{world,light,loading},Result.map(&2,&2,Error,List<&2,Observation>,FrameSamples,
      cells => FrameSamples{clock,cells},cells)))
def sample_ready(positions:List<&2,C.Position>,world:C.World,result:B.State & B.Status) ->
    State & Result<&2,&2,Error,FrameSamples>:
  (light,status) = result
  match status:
    case B.MoreWork{pending}: (State{world,light,None{}},Fail{LightPending{pending}})
    case B.Stable{}: frame_result(samples(positions,State{world,light,None{}}))
def sample_batch(positions:List<&2,C.Position>,state:State) ->
    State & Result<&2,&2,Error,FrameSamples>:
  match state:
    case State{world,light,Some{cursor}}:
      (State{world,light,Some{cursor}},Fail{LoadingInProgress{}})
    case State{world,light,None{}}: sample_ready(positions,world,B.status(light))
