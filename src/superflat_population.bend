import Base
import ./world_generation_settings.bend as WG
import ./core.bend as C
import ./section.bend as S
import ./section_map.bend as SM
import ./schedule.bend as Q

# Chunk and section coordinates are signed I32 bit patterns. This rectangle is
# a demand, not a world boundary. Each admitted position owns all 4096 cells.
type Region is Data:
  Region{x:U32,z:U32,width:U32,depth:U32,bottom:U32,sections:U32}

type Budget is Data:
  Budget{max_requested_sections:Nat,max_loaded_sections:Nat,max_generated_cells:Nat}

type Layer is Data:
  Layer{height:U32,state:U32}

type Flat is Data:
  Flat{dimension:String,min_y:U32,height:U32,air:U32,layers:List<&2,Layer>}

type Receipt is Data:
  Receipt{requested:Nat,created:Nat,loaded:Nat}

def default_budget() -> Budget:
  # Matches today's WorldCodec section admission. Region persistence/eviction
  # must be implemented before unbounded exploration can exceed this budget.
  Budget{512n,512n,2097152n}

def signed_span(+first:U32,+count:U32) -> Bool:
  U32.is_lt(0,count) && U32.is_le(count,268435456) &&
    S.Coord.section_valid(first) && S.Coord.section_valid(U32.sub(U32.add(first,count),1)) &&
    WG.signed_le(first,U32.sub(U32.add(first,count),1))

def region_count(region:Region) -> Nat:
  Region{x,z,width,depth,bottom,sections} = region
  Nat.mul(U32.to_nat(width),Nat.mul(U32.to_nat(depth),U32.to_nat(sections)))

def region_valid(region:Region) -> Bool:
  Region{x,z,width,depth,bottom,sections} = region
  signed_span(x,width) && signed_span(z,depth) && signed_span(bottom,sections)

def column_valid(region:Region,valid:Bool) -> Result<&2,&2,String,Region>:
  match valid:
    case True{}: Done{region}
    case False{}: Fail{"chunk demand or neighbor halo exceeds signed coordinate representation"}

def column(settings:WG.Settings,x:U32,z:U32) -> Result<&2,&2,String,Region>:
  match settings:
    case WG.Unspecified{}: Fail{"generator settings unavailable for legacy save"}
    case WG.Settings{dimension,min_y,height,seed,generator}:
      +region = {Region{x,z,1,1,U32.sub(S.Coord.section(min_y),1),U32.add(U32.div(height,16),2)} : Region}
      column_valid(region,region_valid(region))

def position(+flat:Flat,+region:Region,+index:U32) -> C.Position:
  Flat{dimension,min_y,height,air,layers} = flat
  Region{x,z,+width,+depth,bottom,sections} = region
  C.Position{dimension,
    S.Coord.compose_value(U32.add(x,U32.mod(index,width)),0),
    S.Coord.compose_value(U32.add(bottom,U32.div(index,U32.mul(width,depth))),0),
    S.Coord.compose_value(U32.add(z,U32.mod(U32.div(index,width),depth)),0)}

def layer_at_gate(offset:U32,height:U32,state:U32,within:Bool,next:U32 -> U32) -> U32:
  match within:
    case True{}: state
    case False{}: next(U32.sub(offset,height))

def layer_at(layers:List<&2,Layer>,+offset:U32,+air:U32) -> U32:
  match layers:
    case Nil{}: air
    case Layer{+height,state} <> rest:
      layer_at_gate(offset,height,state,U32.is_lt(offset,height),o => layer_at(rest,o,air))

def state_at_gate(layers:List<&2,Layer>,air:U32,offset:U32,inside:Bool) -> U32:
  match inside:
    case True{}: layer_at(layers,offset,air)
    case False{}: air

def state_at(flat:Flat,+y:U32) -> U32:
  Flat{dimension,+min_y,+height,air,layers} = flat
  state_at_gate(layers,air,U32.sub(y,min_y),
    WG.signed_le(min_y,y) && U32.is_lt(U32.sub(y,min_y),height))

def fill_result(result:S.Section & Result<&2,&2,S.Section.Error,Unit>) -> S.Section:
  (section,status) = result
  section

def fill(fuel:Nat,+index:U32,+origin:U32,+flat:Flat,section:S.Section) -> S.Section:
  match fuel:
    case 0n: section
    case 1n+rest:
      fill(rest,U32.inc(index),origin,flat,
        fill_result(S.Section.set_index(section,index,state_at(flat,U32.add(origin,U32.div(index,256))))))

def complete_section(+flat:Flat,origin:U32) -> S.Section:
  Flat{dimension,min_y,height,air,layers} = flat
  fill(4096n,0,origin,flat,S.Section.new(air))

# Presence transfers the exact owner back. Unlike pop/set, it never removes or
# reorders a collision-bucket entry while testing whether a section is loaded.
def entries_keep(head:SM.Entry,hit:Bool,result:List<&1,SM.Entry> & Bool) -> List<&1,SM.Entry> & Bool:
  (tail,found) = result
  (head <> tail,hit || found)

def present_entries(entries:List<&1,SM.Entry>,+key:String) -> List<&1,SM.Entry> & Bool:
  match entries:
    case Nil{}: ([],False{})
    case SM.Entry{+candidate,section} <> rest:
      entries_keep(SM.Entry{candidate,section},String.eq(candidate,key),present_entries(rest,key))

def present_bucket(result:List<&1,SM.Entry> & Bool) -> SM.Sections & Bool:
  (entries,found) = result
  (SM.Bucket{entries},found)

def present_lo(hi:SM.Sections,result:SM.Sections & Bool) -> SM.Sections & Bool:
  (lo,found) = result
  (SM.Branch{lo,hi},found)

def present_hi(lo:SM.Sections,result:SM.Sections & Bool) -> SM.Sections & Bool:
  (hi,found) = result
  (SM.Branch{lo,hi},found)

def present_branch(low:Bool,lo:SM.Sections,hi:SM.Sections,left:SM.Sections -> SM.Sections & Bool,right:SM.Sections -> SM.Sections & Bool) -> SM.Sections & Bool:
  match low:
    case True{}: present_lo(hi,left(lo))
    case False{}: present_hi(lo,right(hi))

def present_go(+depth:Nat,sections:SM.Sections,+bits:U32,+key:String) -> SM.Sections & Bool:
  match depth sections:
    case _ SM.EmptySections{}: (SM.EmptySections{},False{})
    case 0n SM.Bucket{entries}: present_bucket(present_entries(entries,key))
    case 1n+rest SM.Branch{lo,hi}:
      present_branch(U32.is_eq(U32.and(bits,1),0),lo,hi,
        l => present_go(rest,l,U32.shr(bits),key),h => present_go(rest,h,U32.shr(bits),key))
    case _ other: (other,False{})

def present(sections:SM.Sections,+key:String) -> SM.Sections & Bool:
  present_go(32n,sections,SM.hash(key),key)

def counted_branch(left:SM.Sections & Nat,right:SM.Sections & Nat) -> SM.Sections & Nat:
  (lo,a) = left
  (hi,b) = right
  (SM.Branch{lo,hi},Nat.add(a,b))

def counted_entry(head:SM.Entry,result:List<&1,SM.Entry> & Nat) -> List<&1,SM.Entry> & Nat:
  (tail,n) = result
  (head <> tail,1n+n)

def count_entries(entries:List<&1,SM.Entry>) -> List<&1,SM.Entry> & Nat:
  match entries:
    case Nil{}: ([],0n)
    case head <> rest: counted_entry(head,count_entries(rest))

def count_bucket_result(result:List<&1,SM.Entry> & Nat) -> SM.Sections & Nat:
  (entries,n) = result
  (SM.Bucket{entries},n)

def count_bucket(entries:List<&1,SM.Entry>) -> SM.Sections & Nat:
  count_bucket_result(count_entries(entries))

def count(sections:SM.Sections) -> SM.Sections & Nat:
  match sections:
    case SM.EmptySections{}: (SM.EmptySections{},0n)
    case SM.Branch{lo,hi}: counted_branch(count(lo),count(hi))
    case SM.Bucket{entries}: count_bucket(entries)

def plan_gate(found:Bool,sections:SM.Sections,missing:List<&2,C.Position>,p:C.Position,
    next:List<&2,C.Position> -> SM.Sections -> SM.Sections & List<&2,C.Position>) -> SM.Sections & List<&2,C.Position>:
  match found:
    case True{}: next(missing,sections)
    case False{}: next(p <> missing,sections)

def plan_next(p:C.Position,missing:List<&2,C.Position>,result:SM.Sections & Bool,
    next:List<&2,C.Position> -> SM.Sections -> SM.Sections & List<&2,C.Position>) -> SM.Sections & List<&2,C.Position>:
  (sections,found) = result
  plan_gate(found,sections,missing,p,next)

def plan(fuel:Nat,+index:U32,+flat:Flat,+region:Region,missing:List<&2,C.Position>,sections:SM.Sections) -> SM.Sections & List<&2,C.Position>:
  match fuel:
    case 0n: (sections,missing)
    case 1n+rest:
      +p = position(flat,region,index)
      plan_next(p,missing,present(sections,C.section_key(p)),xs => owner => plan(rest,U32.inc(index),flat,region,xs,owner))

def insert(missing:List<&2,C.Position>,+flat:Flat,sections:SM.Sections) -> SM.Sections:
  match missing:
    case Nil{}: sections
    case +p <> rest:
      C.Position{dimension,x,y,z} = p
      insert(rest,flat,SM.set(sections,C.section_key(p),complete_section(flat,y)))

def event_stamp(event:C.CoreEvent) -> Q.Stamp:
  match event:
    case C.Applied{stamp,revision}: stamp
    case C.Rejected{stamp,error}: stamp

def ordered_stamp(order:Cmp) -> Bool:
  match order:
    case LT{}: False{}
    case _: True{}

def stamp_after(events:List<&2,C.CoreEvent>,stamp:Q.Stamp) -> Bool:
  match events:
    case Nil{}: True{}
    case event <> rest: ordered_stamp(Q.compare(stamp,event_stamp(event)))

# Residency invalidates snapshots but is not a scheduled user mutation. In
# particular, it must not insert an Applied stamp ahead of still-pending work.
def resident_commit(world:C.World,sections:SM.Sections) -> C.World:
  C.World{tick,time,paused,daylight,revision,count,old,pending,events} = world
  C.World{tick,time,paused,daylight,1n+revision,count,sections,pending,events}

def populate_write_gate(+flat:Flat,+stamp:Q.Stamp,requested:Nat,+loaded:Nat,+missing:List<&2,C.Position>,
    world:C.World,sections:SM.Sections,valid:Bool) -> C.World & Result<&2,&2,String,Receipt>:
  match valid:
    case False{}: (C.replace_sections(world,sections),Fail{"generation stamp violates current clock or event order"})
    case True{}:
      (resident_commit(world,insert(missing,flat,sections)),
        Done{Receipt{requested,List.length(&2,C.Position,missing),Nat.add(loaded,List.length(&2,C.Position,missing))}})

def populate_write(flat:Flat,+stamp:Q.Stamp,requested:Nat,loaded:Nat,missing:List<&2,C.Position>,
    world:C.World,sections:SM.Sections) -> C.World & Result<&2,&2,String,Receipt>:
  C.World{+tick,time,paused,daylight,revision,state_count,old,pending,+events} = world
  populate_write_gate(flat,stamp,requested,loaded,missing,
    C.World{tick,time,paused,daylight,revision,state_count,old,pending,events},sections,
    Nat.is_le(Q.stamp_tick(stamp),tick) && stamp_after(events,stamp))

def populate_commit(flat:Flat,stamp:Q.Stamp,requested:Nat,+loaded:Nat,+missing:List<&2,C.Position>,
    world:C.World,sections:SM.Sections) -> C.World & Result<&2,&2,String,Receipt>:
  match missing:
    case Nil{}: (C.replace_sections(world,sections),Done{Receipt{requested,0n,loaded}})
    case missing: populate_write(flat,stamp,requested,loaded,missing,world,sections)

def populate_ready(flat:Flat,stamp:Q.Stamp,requested:Nat,loaded:Nat,missing:List<&2,C.Position>,
    world:C.World,sections:SM.Sections,admitted:Bool) -> C.World & Result<&2,&2,String,Receipt>:
  match admitted:
    case False{}: (C.replace_sections(world,sections),Fail{"chunk demand exceeds resident section or generation cell budget"})
    case True{}: populate_commit(flat,stamp,requested,loaded,missing,world,sections)

def populate_planned(flat:Flat,stamp:Q.Stamp,requested:Nat,+loaded:Nat,budget:Budget,world:C.World,result:SM.Sections & List<&2,C.Position>) -> C.World & Result<&2,&2,String,Receipt>:
  Budget{requests,resident,cells} = budget
  (sections,+missing) = result
  +new_count = List.length(&2,C.Position,missing)
  populate_ready(flat,stamp,requested,loaded,missing,world,sections,
    Nat.is_le(Nat.add(loaded,new_count),resident) && Nat.is_le(Nat.mul(new_count,4096n),cells))

def populate_counted(+flat:Flat,+region:Region,stamp:Q.Stamp,+requested:Nat,budget:Budget,world:C.World,result:SM.Sections & Nat) -> C.World & Result<&2,&2,String,Receipt>:
  (sections,loaded) = result
  populate_planned(flat,stamp,requested,loaded,budget,world,plan(requested,0,flat,region,[],sections))

def layer_states_valid(layers:List<&2,Layer>,+count:U32) -> Bool:
  match layers:
    case Nil{}: True{}
    case Layer{height,state} <> rest: U32.is_lt(state,count) && layer_states_valid(rest,count)

def resolved_height(layers:List<&2,Layer>) -> Nat:
  match layers:
    case Nil{}: 0n
    case Layer{height,state} <> rest: Nat.add(U32.to_nat(height),resolved_height(rest))

def flat_valid(flat:Flat,+count:U32) -> Bool:
  Flat{dimension,+min_y,+height,air,+layers} = flat
  C.dimension_known(dimension) && U32.is_eq(U32.and(min_y,15),0) &&
    U32.is_eq(U32.and(height,15),0) && U32.is_lt(0,height) && U32.is_le(height,2147483647) &&
    WG.signed_le(min_y,U32.sub(U32.add(min_y,height),1)) && U32.is_lt(air,count) &&
    layer_states_valid(layers,count) && Nat.is_le(resolved_height(layers),U32.to_nat(height))

def populate_world_gate(+flat:Flat,region:Region,stamp:Q.Stamp,requested:Nat,budget:Budget,
    +tick:Nat,time:Nat,paused:Bool,daylight:Bool,revision:Nat,+state_count:U32,sections:SM.Sections,pending:List<&2,Q.Pending<C.Mutation>>,events:List<&2,C.CoreEvent>,valid:Bool) -> C.World & Result<&2,&2,String,Receipt>:
  match valid:
    case False{}: (C.World{tick,time,paused,daylight,revision,state_count,sections,pending,events},Fail{"invalid or oversized chunk demand"})
    case True{}:
      populate_counted(flat,region,stamp,requested,budget,
        C.World{tick,time,paused,daylight,revision,state_count,SM.EmptySections{},pending,events},count(sections))

def populate_gate(+flat:Flat,region:Region,stamp:Q.Stamp,requested:Nat,budget:Budget,world:C.World,valid:Bool) -> C.World & Result<&2,&2,String,Receipt>:
  C.World{tick,time,paused,daylight,revision,+state_count,sections,pending,events} = world
  populate_world_gate(flat,region,stamp,requested,budget,tick,time,paused,daylight,revision,state_count,sections,pending,events,
    valid && flat_valid(flat,state_count))

# No writes occur before coordinate and complete admission checks. A demand
# containing only existing sections is idempotent, including revision/events.
def populate(flat:Flat,+region:Region,stamp:Q.Stamp,+budget:Budget,world:C.World) -> C.World & Result<&2,&2,String,Receipt>:
  Budget{requests,resident,cells} = budget
  populate_gate(flat,region,stamp,region_count(region),budget,world,
    region_valid(region) && Nat.is_le(region_count(region),requests) &&
      Nat.is_le(region_count(region),4294967295n))
