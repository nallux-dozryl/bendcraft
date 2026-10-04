import Base
import ./worldgen_biome.bend as B
import ./json.bend as J
import ./random.bend as R
import ./f64.bend as F
import ./world_generation_settings.bend as WG

# Climate.Parameter and the seven-dimensional parameterSpace, including offset.
# All words are exact Java long bit patterns; arithmetic wraps modulo 2^64.
type Interval is Data:
  Interval{min:F.Word64,max:F.Word64}

type Space is Data:
  Space{temperature:Interval,humidity:Interval,continentalness:Interval,
    erosion:Interval,depth:Interval,weirdness:Interval,offset:Interval}

type Entry is Data:
  Entry{index:U32,space:Space,biome:String}

type Tree is Data:
  Leaf{entry:Entry}
  Branch{space:Space,children:List<&2,Tree>,nodes:Nat}

type Loaded is Data:
  Loaded{identity:B.LoadedPreset,entries:List<&2,Entry>}

# One resolver represents one Java RTree thread-local search history. Its table
# and identity are immutable; only the previous selected leaf changes on lookup.
type Resolver is Type:
  Fixed{biome:String}
  MultiNoise{identity:B.LoadedPreset,inputs:B.Inputs,entries:List<&2,Entry>,
    tree:Tree,last:Maybe<&2,Entry>}

type Selection is Data:
  Selection{biome:String,index:U32,fitness:F.Word64}

def zero() -> F.Word64: F.Word64{0,0}
def maximum() -> F.Word64: F.Word64{2147483647,4294967295}

def gate(-A:Type,flag:Bool,yes:Unit -> A,no:Unit -> A) -> A:
  match flag:
    case True{}: yes(Unit{})
    case False{}: no(Unit{})

def ordered(-A:Type,order:Cmp,equal:Unit -> A,different:Cmp -> A) -> A:
  match order:
    case EQ{}: equal(Unit{})
    case _: different(order)

def paired(-A:Type,-B:Type,-C:Type,result:A & B,next:A -> B -> C) -> C:
  (a,b) = result
  next(a)(b)

def product_word(value:R.Bits64) -> F.Word64:
  match value:
    case R.Bits64{hi,lo}: F.Word64{hi,lo}

def add(a:F.Word64,b:F.Word64) -> F.Word64:
  match a b:
    case F.Word64{ah,+al} F.Word64{bh,+bl}:
      +lo = U32.add(al,bl)
      F.Word64{U32.add(U32.add(ah,bh),Bool.to_u32(U32.is_lt(lo,al))),lo}

def sub(a:F.Word64,b:F.Word64) -> F.Word64:
  match a b:
    case F.Word64{ah,+al} F.Word64{bh,+bl}:
      F.Word64{U32.sub(U32.sub(ah,bh),Bool.to_u32(U32.is_lt(al,bl))),U32.sub(al,bl)}

def multiply(a:F.Word64,b:F.Word64) -> F.Word64:
  match a b:
    case F.Word64{ah,al} F.Word64{bh,bl}:
      product_word(R.bits_mul(R.Bits64{ah,al},R.Bits64{bh,bl}))

def square(+value:F.Word64) -> F.Word64: multiply(value,value)

def low_order(al:U32,bl:U32,order:Cmp) -> Cmp:
  match order:
    case EQ{}: U32.cmp(al,bl)
    case _: order

def compare(a:F.Word64,b:F.Word64) -> Cmp:
  match a b:
    case F.Word64{ah,al} F.Word64{bh,bl}:
      low_order(al,bl,U32.cmp(U32.xor(ah,2147483648),U32.xor(bh,2147483648)))

def less(a:F.Word64,b:F.Word64) -> Bool: Cmp.is_lt(compare(a,b))
def word_equal(a:F.Word64,b:F.Word64) -> Bool: Cmp.is_eq(compare(a,b))

def choose_word(a:F.Word64,b:F.Word64,first:Bool) -> F.Word64:
  match first:
    case True{}: a
    case False{}: b

def minimum(+a:F.Word64,+b:F.Word64) -> F.Word64: choose_word(a,b,less(a,b))
def maximum_of(+a:F.Word64,+b:F.Word64) -> F.Word64: choose_word(b,a,less(a,b))

def absolute(+value:F.Word64) -> F.Word64:
  choose_word(sub(zero(),value),value,less(value,zero()))

# Java long division by 2 truncates toward zero, unlike an arithmetic shift.
def half(value:F.Word64) -> F.Word64:
  match value:
    case F.Word64{+hi,+lo}:
      +sign = U32.shrn(hi,31n)
      add(F.Word64{U32.or(U32.shr(hi),U32.shln(sign,31n)),
        U32.or(U32.shr(lo),U32.shln(hi,31n))},F.Word64{0,U32.and(sign,U32.and(lo,1))})

def center(interval:Interval) -> F.Word64:
  match interval:
    case Interval{min,max}: half(add(min,max))

# Parameter.distance computes both subtractions first and compares signed longs.
# The defined Java overflow behavior is retained even for extreme target words.
def interval_distance(interval:Interval,+value:F.Word64) -> F.Word64:
  match interval:
    case Interval{min,max}:
      +above = sub(value,max)
      choose_word(above,maximum_of(sub(min,value),zero()),less(zero(),above))

def interval_span(a:Interval,b:Interval) -> Interval:
  match a b:
    case Interval{amin,amax} Interval{bmin,bmax}:
      Interval{minimum(amin,bmin),maximum_of(amax,bmax)}

def space_span(a:Space,b:Space) -> Space:
  match a b:
    case Space{at,ah,ac,ae,ad,aw,ao} Space{bt,bh,bc,be,bd,bw,bo}:
      Space{interval_span(at,bt),interval_span(ah,bh),interval_span(ac,bc),
        interval_span(ae,be),interval_span(ad,bd),interval_span(aw,bw),interval_span(ao,bo)}

def space_interval(space:Space,axis:U32) -> Interval:
  match space axis:
    case Space{t,h,c,e,d,w,o} 0: t
    case Space{t,h,c,e,d,w,o} 1: h
    case Space{t,h,c,e,d,w,o} 2: c
    case Space{t,h,c,e,d,w,o} 3: e
    case Space{t,h,c,e,d,w,o} 4: d
    case Space{t,h,c,e,d,w,o} 5: w
    case Space{t,h,c,e,d,w,o} _: o

def fitness(space:Space,target:B.Target) -> F.Word64:
  match space target:
    case Space{t,h,c,e,d,w,o} B.Target{tv,hv,cv,ev,dv,wv}:
      add(add(add(add(add(add(square(interval_distance(t,tv)),square(interval_distance(h,hv))),
        square(interval_distance(c,cv))),square(interval_distance(e,ev))),
        square(interval_distance(d,dv))),square(interval_distance(w,wv))),square(interval_distance(o,zero())))

def entry_space(entry:Entry) -> Space:
  match entry:
    case Entry{index,space,biome}: space

def tree_space(tree:Tree) -> Space:
  match tree:
    case Leaf{entry}: entry_space(entry)
    case Branch{space,children,nodes}: space

def tree_size(tree:Tree) -> Nat:
  match tree:
    case Leaf{entry}: 1n
    case Branch{space,children,nodes}: nodes

def nodes_size(nodes:List<&2,Tree>) -> Nat:
  match nodes:
    case Nil{}: 0n
    case node <> rest: Nat.add(tree_size(node),nodes_size(rest))

def span_rest(nodes:List<&2,Tree>,space:Space) -> Space:
  match nodes:
    case Nil{}: space
    case node <> rest: span_rest(rest,space_span(space,tree_space(node)))

def branch(nodes:List<&2,Tree>) -> Result<&2,&2,String,Tree>:
  match nodes:
    case Nil{}: Fail{"climate tree needs at least one child"}
    case +node <> +rest:
      Done{Branch{span_rest(rest,tree_space(node)),node <> rest,1n+Nat.add(tree_size(node),nodes_size(rest))}}

def width(interval:Interval) -> F.Word64:
  match interval:
    case Interval{min,max}: absolute(sub(max,min))

def cost(space:Space) -> F.Word64:
  match space:
    case Space{t,h,c,e,d,w,o}:
      add(add(add(add(add(add(width(t),width(h)),width(c)),width(e)),width(d)),width(w)),width(o))

def total_center(space:Space) -> F.Word64:
  match space:
    case Space{t,h,c,e,d,w,o}:
      add(add(add(add(add(add(absolute(center(t)),absolute(center(h))),absolute(center(c))),
        absolute(center(e))),absolute(center(d))),absolute(center(w))),absolute(center(o)))

type Order is Data:
  TotalCenter{}
  AxisCenter{axis:U32,absolute:Bool}

def axis_center(+space:Space,axis:U32,absolute_center:Bool) -> F.Word64:
  +value = center(space_interval(space,axis))
  choose_word(absolute(value),value,absolute_center)

def axis_order(fuel:Nat,+a:Space,+b:Space,+axis:U32,+absolute_center:Bool) -> Cmp:
  match fuel:
    case 0n: EQ{}
    case 1n+rest:
      ordered(Cmp,compare(axis_center(a,axis,absolute_center),axis_center(b,axis,absolute_center)),
        u => axis_order(rest,a,b,U32.mod(U32.add(axis,1),7),absolute_center),order => order)

def node_order(order:Order,a:Tree,b:Tree) -> Cmp:
  match order:
    case TotalCenter{}: compare(total_center(tree_space(a)),total_center(tree_space(b)))
    case AxisCenter{axis,absolute_center}: axis_order(7n,tree_space(a),tree_space(b),axis,absolute_center)

# Stable bottom-up merge sort implements List.sort's stable comparator order.
def merge_nodes(fuel:Nat,+order:Order,left:List<&2,Tree>,right:List<&2,Tree>) -> List<&2,Tree>:
  match fuel left right:
    case _ Nil{} _: right
    case _ _ Nil{}: left
    case 0n _ _: List.append(&2,Tree,left,right)
    case 1n+ +rest +a <> +at +b <> +bt:
      gate(List<&2,Tree>,Cmp.is_gt(node_order(order,a,b)),
        u => b <> merge_nodes(rest,order,a <> at,bt),
        u => a <> merge_nodes(rest,order,at,b <> bt))

def singletons(nodes:List<&2,Tree>) -> List<&2,List<&2,Tree>>:
  match nodes:
    case Nil{}: Nil{}
    case node <> rest: [node] <> singletons(rest)

def sort_pass(+order:Order,runs:List<&2,List<&2,Tree>>) -> List<&2,List<&2,Tree>>:
  match runs:
    case Nil{}: Nil{}
    case one <> Nil{}: [one]
    case +one <> +two <> rest:
      merge_nodes(Nat.add(List.length(&2,Tree,one),List.length(&2,Tree,two)),order,one,two) <>
        sort_pass(order,rest)

def sort_runs(fuel:Nat,+order:Order,runs:List<&2,List<&2,Tree>>) -> List<&2,Tree>:
  match fuel runs:
    case _ Nil{}: Nil{}
    case _ one <> Nil{}: one
    case 0n _: List.concat(&2,Tree,runs)
    case 1n+rest _: sort_runs(rest,order,sort_pass(order,runs))

def sort_nodes(+order:Order,+nodes:List<&2,Tree>) -> List<&2,Tree>:
  sort_runs(List.length(&2,Tree,nodes),order,singletons(nodes))

# For finite list sizes admitted by the loader this is the same bucket size as
# 19^floor(log(size-.01)/log(19)): the largest power of19 strictly below size.
def bucket_size(fuel:Nat,+size:U32,+power:U32) -> U32:
  match fuel:
    case 0n: power
    case 1n+ +rest:
      +next = U32.mul(power,19)
      gate(U32,U32.is_lt(next,size) && U32.is_gt(next,power),
        u => bucket_size(rest,size,next),u => power)

def split_nodes(count:Nat,nodes:List<&2,Tree>,taken:List<&2,Tree>) -> List<&2,Tree> & List<&2,Tree>:
  match count nodes:
    case 0n _: (List.reverse(&2,Tree,taken),nodes)
    case _ Nil{}: (List.reverse(&2,Tree,taken),Nil{})
    case 1n+rest node <> tail: split_nodes(rest,tail,node <> taken)

def buckets(fuel:Nat,+size:Nat,nodes:List<&2,Tree>) -> Result<&2,&2,String,List<&2,Tree>>:
  match fuel nodes:
    case _ Nil{}: Done{Nil{}}
    case 0n _: Fail{"climate tree bucket budget exhausted"}
    case 1n+rest _:
      paired(List<&2,Tree>,List<&2,Tree>,Result<&2,&2,String,List<&2,Tree>>,
        split_nodes(size,nodes,Nil{}),head => tail => (
          do Result<&2,&2,String,List<&2,Tree>>:
            node : Tree <- branch(head)
            more : List<&2,Tree> <- buckets(rest,size,tail)
            return node <> more))

def bucket_nodes(+nodes:List<&2,Tree>) -> Result<&2,&2,String,List<&2,Tree>>:
  +count = List.length(&2,Tree,nodes)
  buckets(count,U32.to_nat(bucket_size(16n,U32.from_nat(count),1)),nodes)

def bucket_cost(nodes:List<&2,Tree>) -> F.Word64:
  match nodes:
    case Nil{}: zero()
    case node <> rest: add(cost(tree_space(node)),bucket_cost(rest))

type Partition is Data:
  Partition{axis:U32,cost:F.Word64,buckets:List<&2,Tree>}

def better_partition(axis:U32,+nodes:List<&2,Tree>,+previous:Partition) -> Partition:
  match previous:
    case Partition{old_axis,+old_cost,old_buckets}:
      +new_cost = bucket_cost(nodes)
      gate(Partition,less(new_cost,old_cost),
        u => Partition{axis,new_cost,nodes},u => Partition{old_axis,old_cost,old_buckets})

def choose_partition(fuel:Nat,+axis:U32,+nodes:List<&2,Tree>,previous:Partition) -> Result<&2,&2,String,Partition>:
  match fuel:
    case 0n: Done{previous}
    case 1n+rest:
      +sorted = sort_nodes(AxisCenter{axis,False{}},nodes)
      do Result<&2,&2,String,Partition>:
        grouped : List<&2,Tree> <- bucket_nodes(sorted)
        return_result : Partition <- choose_partition(rest,U32.add(axis,1),sorted,better_partition(axis,grouped,previous))
        return return_result

def sorted_partition(selected:Partition) -> List<&2,Tree>:
  match selected:
    case Partition{axis,unused,grouped}: sort_nodes(AxisCenter{axis,True{}},grouped)

def partition(nodes:List<&2,Tree>) -> Result<&2,&2,String,List<&2,Tree>>:
  do Result<&2,&2,String,List<&2,Tree>>:
    selected : Partition <- choose_partition(7n,0,nodes,Partition{0,maximum(),Nil{}})
    return sorted_partition(selected)

type BuildJob is Data:
  Group{nodes:List<&2,Tree>}
  Assemble{count:Nat}

def group_jobs(nodes:List<&2,Tree>) -> List<&2,BuildJob>:
  match nodes:
    case Nil{}: Nil{}
    case Branch{space,children,size} <> rest: Group{children} <> group_jobs(rest)
    case Leaf{entry} <> rest: Group{[Leaf{entry}]} <> group_jobs(rest)

def assemble_nodes(count:Nat,values:List<&2,Tree>) -> List<&2,Tree> & List<&2,Tree>:
  split_nodes(count,values,Nil{})

# Explicit work stack avoids mutual recursive helpers and bounds every build.
def build_loop(fuel:Nat,jobs:List<&2,BuildJob>,+values:List<&2,Tree>) -> Result<&2,&2,String,Tree>:
  match fuel jobs:
    case _ Nil{}:
      match values:
        case value <> Nil{}: Done{value}
        case _: Fail{"climate tree build stack malformed"}
    case 0n _: Fail{"climate tree build budget exhausted"}
    case 1n+remaining Assemble{count} <> rest:
      paired(List<&2,Tree>,List<&2,Tree>,Result<&2,&2,String,Tree>,
        assemble_nodes(count,values),children => tail => (
          do Result<&2,&2,String,Tree>:
            node : Tree <- branch(List.reverse(&2,Tree,children))
            next : Tree <- build_loop(remaining,rest,node <> tail)
            return next))
    case 1n+remaining Group{Nil{}} <> rest: Fail{"climate parameter list must be nonempty"}
    case 1n+remaining Group{node <> Nil{}} <> rest: build_loop(remaining,rest,node <> values)
    case 1n+ +remaining Group{+nodes} <> +rest:
      gate(Result<&2,&2,String,Tree>,Nat.is_le(List.length(&2,Tree,nodes),19n),u => (
          do Result<&2,&2,String,Tree>:
            node : Tree <- branch(sort_nodes(TotalCenter{},nodes))
            next : Tree <- build_loop(remaining,rest,node <> values)
            return next),u => (
          do Result<&2,&2,String,Tree>:
            +grouped : List<&2,Tree> <- partition(nodes)
            next : Tree <- build_loop(remaining,List.append(&2,BuildJob,group_jobs(grouped),
              Assemble{List.length(&2,Tree,grouped)} <> rest),values)
            return next))

def leaves(entries:List<&2,Entry>) -> List<&2,Tree>:
  match entries:
    case Nil{}: Nil{}
    case entry <> rest: Leaf{entry} <> leaves(rest)

def build(entries:List<&2,Entry>,budget:Nat) -> Result<&2,&2,String,Tree>:
  build_loop(budget,[Group{leaves(entries)}],Nil{})

def cached_fitness(last:Maybe<&2,Entry>,+target:B.Target) -> F.Word64:
  match last:
    case None{}: maximum()
    case Some{entry}: fitness(entry_space(entry),target)

def select_better(+entry:Entry,+target:B.Target,+previous:Maybe<&2,Entry>) -> Maybe<&2,Entry>:
  gate(Maybe<&2,Entry>,less(fitness(entry_space(entry),target),cached_fitness(previous,target)),
    u => Some{entry},u => previous)

def advance(node:Tree,+target:B.Target,last:Maybe<&2,Entry>,rest:List<&2,Tree>) ->
    List<&2,Tree> & Maybe<&2,Entry>:
  match node:
    case Leaf{entry}: (rest,select_better(entry,target,last))
    case Branch{space,children,size}: (List.append(&2,Tree,children,rest),last)

# This explicit DFS stack preserves Java's ordered child traversal and strict
# pruning. The previous leaf remains selected at equal fitness, including when
# the target changes. No unordered flattening or first-table-entry tie rule.
def search_loop(fuel:Nat,nodes:List<&2,Tree>,+target:B.Target,+last:Maybe<&2,Entry>) -> Maybe<&2,Entry>:
  match fuel nodes:
    case _ Nil{}: last
    case 0n _: None{}
    case 1n+ +remaining +node <> +rest:
      gate(Maybe<&2,Entry>,less(fitness(tree_space(node),target),cached_fitness(last,target)),u =>
          paired(List<&2,Tree>,Maybe<&2,Entry>,Maybe<&2,Entry>,advance(node,target,last,rest),
            next => previous => search_loop(remaining,next,target,previous)),
        u => search_loop(remaining,rest,target,last))

def search(+tree:Tree,+target:B.Target,last:Maybe<&2,Entry>) -> Maybe<&2,Entry>:
  match tree:
    case Leaf{entry}: Some{entry}
    case Branch{space,children,nodes}: search_loop(nodes,children,target,last)

def selected(entry:Entry,target:B.Target) -> Selection:
  match entry:
    case Entry{index,+space,biome}: Selection{biome,index,fitness(space,target)}

def resolved(identity:B.LoadedPreset,inputs:B.Inputs,entries:List<&2,Entry>,tree:Tree,
    last:Maybe<&2,Entry>,+target:B.Target,found:Maybe<&2,Entry>) -> Resolver & Result<&2,&2,String,Selection>:
  match found:
    case None{}: (MultiNoise{identity,inputs,entries,tree,last},Fail{"climate tree search produced no leaf"})
    case Some{+entry}: (MultiNoise{identity,inputs,entries,tree,Some{entry}},Done{selected(entry,target)})

def resolve_target(resolver:Resolver,+target:B.Target) -> Resolver & Result<&2,&2,String,Selection>:
  match resolver:
    case Fixed{+biome}: (Fixed{biome},Done{Selection{biome,0,zero()}})
    case MultiNoise{identity,inputs,entries,+tree,+last}:
      resolved(identity,inputs,entries,tree,last,target,search(tree,target,last))

def resolve_values(resolver:Resolver,values:B.Values) -> Resolver & Result<&2,&2,String,Selection>:
  resolve_target(resolver,B.target(values))

def preset_names_equal(a:Maybe<&2,J.Value>,b:Maybe<&2,J.Value>) -> Bool:
  match a b:
    case Some{J.JString{first}} Some{J.JString{second}}: String.eq(first,second)
    case _ _: False{}

# The native preset codec has one semantic member, "preset". Preserve the
# complete loaded definition, while comparing the same decoded preset identity.
def definitions_equal(a:B.LoadedPreset,b:B.LoadedPreset) -> Bool:
  match a b:
    case B.LoadedPreset{ak,av} B.LoadedPreset{bk,bv}:
      String.eq(ak,bk) && preset_names_equal(J.member(av,"preset"),J.member(bv,"preset"))

def prepared_tree(identity:B.LoadedPreset,inputs:B.Inputs,entries:List<&2,Entry>,
    built:Result<&2,&2,String,Tree>) -> Result<&2,&1,String,Resolver>:
  match built:
    case Fail{message}: Fail{message}
    case Done{tree}: Done{MultiNoise{identity,inputs,entries,tree,None{}}}

def prepare_checked(identity:B.LoadedPreset,inputs:B.Inputs,+entries:List<&2,Entry>,budget:Nat,
    valid:Bool) -> Result<&2,&1,String,Resolver>:
  match valid:
    case False{}: Fail{"climate preset identity or loaded definition mismatch"}
    case True{}: prepared_tree(identity,inputs,entries,build(entries,budget))

def prepare(plan:B.Plan,loaded:Loaded,budget:Nat) -> Result<&2,&1,String,Resolver>:
  match plan loaded:
    case B.Fixed{biome} _: Done{Fixed{biome}}
    case B.MultiNoise{+preset,+definition,inputs} Loaded{+identity,entries}:
      prepare_checked(identity,inputs,entries,budget,
        B.preset_matches(preset,identity) && definitions_equal(definition,identity))
