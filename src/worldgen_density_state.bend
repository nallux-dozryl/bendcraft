import Base
import ./worldgen_density_ast.bend as A
import ./worldgen_density_compile.bend as Compile
import ./worldgen_density_codec.bend as Codec
import ./worldgen_density_noise.bend as DN
import ./worldgen_overworld.bend as O
import ./worldgen_seed.bend as WS
import ./worldgen_blended_noise.bend as BL
import ./worldgen_perlin_noise.bend as P
import ./f64.bend as F
import ./random.bend as R
import ./json.bend as J

type Key is Data:
  NormalKey{name:String}
  BaseKey{config:BL.Config}

type Producer is Type:
  Normal{noise:DN.Noise}
  Base{noise:BL.Blended}

type Slot is Type:
  Slot{key:Key,producer:Producer}

type Point is Data:
  Point{x:U32,y:U32,z:U32}

type Value is Data:
  Value{index:U32,value:F32}

type Cache is Data:
  Cache{point:Maybe<&2,Point>,values:List<&2,Value>}

type State is Type:
  State{program:A.Program,pool:List<&1,Slot>,cache:Cache}

type Factory is Type:
  Factory{keys:List<&2,Key>,pool:List<&1,Slot>}

def config_equal(a:BL.Config,b:BL.Config) -> Bool:
  match a b:
    case BL.Config{ax,ay,axf,ayf,asmear} BL.Config{bx,by,bxf,byf,bsmear}:
      F.is_eq(ax,bx) && F.is_eq(ay,by) && F.is_eq(axf,bxf) && F.is_eq(ayf,byf) && F.is_eq(asmear,bsmear)

def key_equal(a:Key,b:Key) -> Bool:
  match a b:
    case NormalKey{a} NormalKey{b}: String.eq(a,b)
    case BaseKey{a} BaseKey{b}: config_equal(a,b)
    case _ _: False{}

def has_key(keys:List<&2,Key>,+key:Key) -> Bool:
  match keys:
    case Nil{}: False{}
    case head <> rest: key_equal(head,key) || has_key(rest,key)

def producer_key(operation:A.Operation) -> Maybe<&2,Key>:
  match operation:
    case A.OpNoise{name,xz,y,sx,sy,sz,mode}: Some{NormalKey{name}}
    case A.OpShiftA{name}: Some{NormalKey{name}}
    case A.OpShiftB{name}: Some{NormalKey{name}}
    case A.OpBaseNoise{config}: Some{BaseKey{config}}
    case _: None{}

def root(plan:O.Plan) -> WS.Root:
  match plan:
    case O.Plan{generation,definition,random}: random

def base_created(result:R.Source & Result<&2,&1,String,BL.Blended>) -> Result<&2,&1,String,Producer>:
  match result:
    case Tuple{source,Fail{message}}: Fail{message}
    case Tuple{source,Done{noise}}: Done{Base{noise}}

def base_named(config:BL.Config,fuel:Nat,result:Result<&2,&2,String,R.Source>) -> Result<&2,&1,String,Producer>:
  match result:
    case Fail{message}: Fail{message}
    case Done{source}: base_created(BL.create(fuel,source,config))

def normal_created(result:Result<&2,&1,String,DN.Noise>) -> Result<&2,&1,String,Producer>:
  match result:
    case Fail{message}: Fail{message}
    case Done{noise}: Done{Normal{noise}}

def normal_configured(random:WS.Root,name:String,fuel:Nat,result:Result<&2,&2,String,DN.Config>) -> Result<&2,&1,String,Producer>:
  match result:
    case Fail{message}: Fail{message}
    case Done{config}: normal_created(DN.create(random,name,fuel,config))

def normal_defined(random:WS.Root,+name:String,fuel:Nat,result:Maybe<&2,J.Value>) -> Result<&2,&1,String,Producer>:
  match result:
    case None{}: Fail{"missing loaded normal-noise definition: " ++ name}
    case Some{definition}: normal_configured(random,name,fuel,Codec.noise_config(name,definition))

def create(key:Key,random:WS.Root,fuel:Nat,registry:A.Registry) -> Result<&2,&1,String,Producer>:
  match key registry:
    case BaseKey{config} _: base_named(config,fuel,WS.compiled_random(random,"minecraft:terrain"))
    case NormalKey{+name} A.Registry{densities,noises}: normal_defined(random,name,fuel,Compile.lookup(noises,name))

def installed(+key:Key,factory:Factory,result:Result<&2,&1,String,Producer>) -> Result<&2,&1,String,Factory>:
  match factory result:
    case _ Fail{message}: Fail{message}
    case Factory{keys,pool} Done{producer}: Done{Factory{key <> keys,Slot{key,producer} <> pool}}

def needed(+key:Key,factory:Factory,random:WS.Root,fuel:Nat,registry:A.Registry,known:Bool) -> Result<&2,&1,String,Factory>:
  match known:
    case True{}: Done{factory}
    case False{}: installed(key,factory,create(key,random,fuel,registry))

def leaf(factory:Factory,random:WS.Root,fuel:Nat,registry:A.Registry,key:Maybe<&2,Key>) -> Result<&2,&1,String,Factory>:
  match factory key:
    case _ None{}: Done{factory}
    case Factory{+keys,pool} Some{+key}: needed(key,Factory{keys,pool},random,fuel,registry,has_key(keys,key))

def continued(result:Result<&2,&1,String,Factory>,operation:Factory -> Result<&2,&1,String,Factory>) -> Result<&2,&1,String,Factory>:
  match result:
    case Fail{message}: Fail{message}
    case Done{factory}: operation(factory)

def initialize_nodes(nodes:List<&2,A.Node>,+random:WS.Root,+fuel:Nat,+registry:A.Registry,factory:Factory) -> Result<&2,&1,String,Factory>:
  match nodes:
    case Nil{}: Done{factory}
    case A.Node{index,original,operation} <> rest:
      continued(leaf(factory,random,fuel,registry,producer_key(operation)),
        next => initialize_nodes(rest,random,fuel,registry,next))

def prepared(program:A.Program,result:Result<&2,&1,String,Factory>) -> Result<&2,&1,String,State>:
  match result:
    case Fail{message}: Fail{message}
    case Done{Factory{keys,pool}}: Done{State{program,List.reverse(&1,Slot,pool),Cache{None{},[]}}}

def initialize(+program:A.Program,fuel:Nat) -> Result<&2,&1,String,State>:
  match program:
    case A.Program{+plan,+registry,expression,+nodes,index}:
      prepared(A.Program{plan,registry,expression,nodes,index},initialize_nodes(nodes,root(plan),fuel,registry,Factory{[],[]}))

def producer_get(producer:Producer,+x:F.F64,+y:F.F64,+z:F.F64) -> Producer & F32:
  match producer:
    case Normal{noise}:
      P.paired(DN.Noise,F32,Producer & F32,DN.get(noise,x,y,z),next => value => (Normal{next},value))
    case Base{noise}:
      P.paired(BL.Blended,F32,Producer & F32,BL.get(noise,False{},x,y,z),next => value => (Base{next},value))

def slot_found(key:Key,rest:List<&1,Slot>,result:Producer & F32) -> List<&1,Slot> & Result<&2,&2,String,F32>:
  match result:
    case Tuple{producer,value}: (Slot{key,producer} <> rest,Done{value})

def slot_missed(key:Key,producer:Producer,result:List<&1,Slot> & Result<&2,&2,String,F32>) -> List<&1,Slot> & Result<&2,&2,String,F32>:
  match result:
    case Tuple{rest,status}: (Slot{key,producer} <> rest,status)

def slot_read(key:Key,producer:Producer,rest:List<&1,Slot>,x:F.F64,y:F.F64,z:F.F64,found:Bool,
    continuation:List<&1,Slot> -> List<&1,Slot> & Result<&2,&2,String,F32>) -> List<&1,Slot> & Result<&2,&2,String,F32>:
  match found:
    case True{}: slot_found(key,rest,producer_get(producer,x,y,z))
    case False{}: slot_missed(key,producer,continuation(rest))

# A successful or refused lookup reconstructs each slot at its exact original
# list position. No pop/reinsert or registry-owner replacement is performed.
def pool_get(fuel:Nat,pool:List<&1,Slot>,+target:Key,+x:F.F64,+y:F.F64,+z:F.F64) -> List<&1,Slot> & Result<&2,&2,String,F32>:
  match fuel pool:
    case 0n _: (pool,Fail{"density seeded-noise lookup exceeds caller budget"})
    case _ Nil{}: ([],Fail{"density node has no initialized seeded-noise owner"})
    case 1n+left Slot{+key,producer} <> rest:
      slot_read(key,producer,rest,x,y,z,key_equal(key,target),
        next => pool_get(left,next,target,x,y,z))
