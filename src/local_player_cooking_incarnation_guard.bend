import Base
import ./core.bend as C
import ./block_light_world.bend as W
import ./cooking_world_bindings.bend as B
import ./cooking_world_store.bend as S

# Only immutable admission metadata is projected. No Core/Section/Entry owner
# is copied or speculatively changed, and no furnace arrays are constructed.
type Header is Data:
  Header{position:C.Position,binding:B.Binding}
type Operation is Data:
  Operation{prepared:W.Prepared,classification:Maybe<&2,B.Classification>}
type Change is Data:
  Change{headers:List<&2,Header>,reset:Maybe<&2,C.Position>}
type Scan is Data:
  Scan{headers:List<&2,Header>,incarnations:Map<&2,Nat>,skip:Nat}

def maximum() -> Nat: Nat.add(Nat.mul(65536n,4294967295n),65535n)

def headers(views:List<&2,S.View>) -> List<&2,Header>:
  match views:
    case Nil{}: []
    case S.View{position,binding,body,effects} <> rest: Header{position,binding} <> headers(rest)

def mutations(operations:List<&2,Operation>) -> List<&2,C.Mutation>:
  match operations:
    case Nil{}: []
    case Operation{prepared,classification} <> rest: W.prepared_mutation(prepared) <> mutations(rest)

def create(position:C.Position,value:B.Classification,rest:List<&2,Header>) -> List<&2,Header>:
  match value:
    case B.Other{}: rest
    case B.Cooking{binding}: Header{position,binding} <> rest

def changed(same:Bool,candidate:C.Position,+position:C.Position,
    value:B.Classification,rest:List<&2,Header>) -> Change:
  match same value:
    case True{} B.Cooking{binding}: Change{Header{candidate,binding} <> rest,None{}}
    case _ other: Change{create(position,other,rest),Some{position}}

def found(candidate:C.Position,previous:B.Binding,+position:C.Position,+value:B.Classification,rest:List<&2,Header>) -> Change:
  match value:
    case B.Other{}: changed(False{},candidate,position,B.Other{},rest)
    case B.Cooking{+next}: changed(B.same_block(previous,next),candidate,position,value,rest)

def kept(head:Header,result:Change) -> Change:
  Change{rest,reset} = result
  Change{head <> rest,reset}

def choose(hit:Bool,head:Header,position:C.Position,value:B.Classification,rest:List<&2,Header>,
    next:Unit -> Change) -> Change:
  match hit head:
    case True{} Header{candidate,binding}: found(candidate,binding,position,value,rest)
    case False{} head: kept(head,next(Unit{}))

# Store.change updates the first actual matching Entry, retaining duplicates
# and order. A map keyed only by position would change that contract.
def change(values:List<&2,Header>,+position:C.Position,+value:B.Classification) -> Change:
  match values:
    case Nil{}: Change{create(position,value,[]),None{}}
    case +head <> +rest:
      Header{+candidate,binding} = head
      choose(B.equal_position(candidate,position),head,position,value,rest,
        unit => change(rest,position,value))

def fill(left:Nat,+origin:C.Position,+binding:B.Binding,+index:U32,rest:List<&2,Header>) -> List<&2,Header>:
  match left:
    case 0n: rest
    case 1n+remaining: Header{W.indexed(origin,index),binding} <> fill(remaining,origin,binding,U32.inc(index),rest)

def filled(position:C.Position,value:B.Classification,rest:List<&2,Header>) -> List<&2,Header>:
  match value:
    case B.Other{}: rest
    case B.Cooking{binding}: fill(4096n,W.origin(position),binding,0,rest)

def lifecycle(operation:Operation,values:List<&2,Header>) -> Change:
  match operation:
    case Operation{W.Block{position,descriptor},Some{value}}: change(values,position,value)
    case Operation{W.Fill{position,descriptor},Some{value}}: Change{filled(position,value,values),None{}}
    case _: Change{values,None{}}

def counted(valid:Bool,key:String,values:List<&2,Header>,incarnations:Map<&2,Nat>,current:Nat) ->
    Result<&2,&2,String,Scan>:
  match valid:
    case False{}: Fail{"local-cooking:incarnation-exhausted"}
    case True{}: Done{Scan{values,Map.set(&2,Nat,incarnations,key,1n+current),0n}}

def observed(key:String,values:List<&2,Header>,result:Map<&2,Nat> & Nat) -> Result<&2,&2,String,Scan>:
  (incarnations,+current) = result
  counted(Nat.is_lt(current,maximum()),key,values,incarnations,current)

def reset(skip:Nat,+position:C.Position,values:List<&2,Header>,incarnations:Map<&2,Nat>) -> Result<&2,&2,String,Scan>:
  match skip:
    case 0n: observed(B.key(position),values,Map.get(Nat,0n,incarnations,B.key(position)))
    case 1n+remaining: Done{Scan{values,incarnations,remaining}}

def changed_scan(incarnations:Map<&2,Nat>,skip:Nat,result:Change) -> Result<&2,&2,String,Scan>:
  match result:
    case Change{values,None{}}: Done{Scan{values,incarnations,skip}}
    case Change{values,Some{position}}: reset(skip,position,values,incarnations)

def accepted(operation:Operation,scan:Scan,status:Result<&2,&2,C.Error,Unit>) -> Result<&2,&2,String,Scan>:
  match scan status:
    case scan Fail{error}: Done{scan}
    case Scan{values,incarnations,skip} Done{unit}: changed_scan(incarnations,skip,lifecycle(operation,values))

def walk(operations:List<&2,Operation>,statuses:List<&2,Result<&2,&2,C.Error,Unit>>,
    result:Result<&2,&2,String,Scan>) -> Result<&2,&2,String,Unit>:
  match operations statuses result:
    case _ _ Fail{message}: Fail{message}
    case Nil{} Nil{} Done{scan}: Done{Unit{}}
    case operation <> rest status <> tail Done{scan}: walk(rest,tail,accepted(operation,scan,status))
    case _ _ Done{scan}: Fail{"local-cooking:incarnation-due-status-mismatch"}

def checked(operations:List<&2,Operation>,values:List<&2,Header>,incarnations:Map<&2,Nat>,skip:Nat,
    result:C.World & List<&2,Result<&2,&2,C.Error,Unit>>) -> C.World & Result<&2,&2,String,Unit>:
  (world,statuses) = result
  (world,walk(operations,statuses,Done{Scan{values,incarnations,skip}}))

# Application acceptance is observed on the sole real Core owner. Only the
# temporary header/counter metadata changes during prospective admission.
def check(world:C.World,views:List<&2,S.View>,+operations:List<&2,Operation>,incarnations:Map<&2,Nat>,skip:Nat) ->
    C.World & Result<&2,&2,String,Unit>:
  checked(operations,headers(views),incarnations,skip,C.prospective_results(world,mutations(operations)))
