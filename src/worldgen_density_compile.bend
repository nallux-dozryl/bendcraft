import Base
import ./worldgen_density_ast.bend as A
import ./worldgen_density_codec.bend as Codec
import ./worldgen_overworld.bend as O
import ./world_generation_settings.bend as WG
import ./json.bend as J

type Limits is Data:
  Limits{depth:Nat,nodes:U32,registry_entries:Nat}

type Memo is Data:
  Memo{key:String,index:U32}

type Build is Data:
  Build{nodes:List<&2,A.Node>,references:List<&2,Memo>,count:U32}

type Step is Data:
  Step{build:Build,index:U32}

def lookup(bindings:List<&2,A.Binding>,+key:String) -> Maybe<&2,J.Value>:
  match bindings:
    case Nil{}: None{}
    case A.Binding{name,value} <> rest:
      Bool.pick(Maybe<&2,J.Value>,String.eq(name,key),Some{value},lookup(rest,key))

def lookup_memo(memos:List<&2,Memo>,+key:String) -> Maybe<&2,U32>:
  match memos:
    case Nil{}: None{}
    case Memo{name,index} <> rest:
      Bool.pick(Maybe<&2,U32>,String.eq(name,key),Some{index},lookup_memo(rest,key))

def contains(path:List<&2,String>,+key:String) -> Bool:
  match path:
    case Nil{}: False{}
    case head <> rest: String.eq(head,key) || contains(rest,key)

def constant_type(value:Maybe<&2,J.Value>) -> Bool:
  match value:
    case Some{J.JString{"minecraft:constant"}}: True{}
    case _: False{}

def direct_constant(value:J.Value) -> Bool:
  match value:
    case J.JNumber{_}: True{}
    case J.JObject{fields}: constant_type(J.member(J.JObject{fields},"type"))
    case _: False{}

def zero_form(value:Result<&2,&2,String,A.Form>) -> Bool:
  match value:
    case Done{A.Constant{value}}: U32.is_eq(F32.bits(value),0)
    case _: False{}

def noise_mode_gate(x:Bool,y:Bool,z:Bool) -> A.NoiseMode:
  match x y z:
    case True{} True{} True{}: A.Plain{}
    case _ True{} _: A.ShiftedXZ{}
    case _ False{} _: A.ShiftedXYZ{}

def noise_mode(x:J.Value,y:J.Value,z:J.Value) -> A.NoiseMode:
  noise_mode_gate(zero_form(Codec.read(x)),zero_form(Codec.read(y)),zero_form(Codec.read(z)))

def binary_supported(operation:A.Binary) -> Bool:
  match operation:
    case A.Divide{}: False{}
    case A.Minimum{}: False{}
    case A.Maximum{}: False{}
    case _: True{}

def absent(value:Maybe<&2,J.Value>) -> Bool:
  match value:
    case None{}: True{}
    case Some{_}: False{}

def bindings_valid(room:Nat,bindings:List<&2,A.Binding>) -> Bool:
  match room bindings:
    case _ Nil{}: True{}
    case 0n _: False{}
    case 1n+left A.Binding{+name,value} <> +rest:
      WG.identifier(name) && absent(lookup(rest,name)) && bindings_valid(left,rest)

def registry_valid(registry:A.Registry,+room:Nat) -> Bool:
  match registry:
    case A.Registry{densities,noises}: bindings_valid(room,densities) && bindings_valid(room,noises)

def node_added(nodes:List<&2,A.Node>,references:List<&2,Memo>,+count:U32,
    original:J.Value,operation:A.Operation,valid:Bool) -> Result<&2,&2,String,Step>:
  match valid:
    case False{}: Fail{"density DAG exceeds caller node budget"}
    case True{}: Done{Step{Build{A.Node{count,original,operation} <> nodes,references,U32.inc(count)},count}}

def append(build:Build,original:J.Value,operation:A.Operation,+capacity:U32) -> Result<&2,&2,String,Step>:
  match build:
    case Build{nodes,references,+count}:
      node_added(nodes,references,count,original,operation,
        U32.is_lt(count,capacity) && U32.is_lt(count,2147483647))

def continued(result:Result<&2,&2,String,Step>,operation:Build -> U32 -> Result<&2,&2,String,Step>) -> Result<&2,&2,String,Step>:
  match result:
    case Fail{message}: Fail{message}
    case Done{Step{build,index}}: operation(build,index)

def binary_admitted(operation:A.Binary,original:J.Value,capacity:U32,+left:J.Value,+right:J.Value,
    +path:List<&2,String>,build:Build,
    recurse:J.Value -> List<&2,String> -> Build -> Result<&2,&2,String,Step>,
    recurse_right:J.Value -> List<&2,String> -> Build -> Result<&2,&2,String,Step>,valid:Bool) -> Result<&2,&2,String,Step>:
  match valid:
    case False{}: Fail{"density divide/min/max require the actual compiled range and constant-specialization implementation"}
    case True{}:
      continued(recurse(left,path,build),next => left_index =>
        continued(recurse_right(right,path,next),next => right_index =>
          append(next,original,A.OpBinary{operation,left_index,right_index,direct_constant(left),direct_constant(right)},capacity)))

def named(key:String,result:Result<&2,&2,String,Step>) -> Result<&2,&2,String,Step>:
  match result:
    case Fail{message}: Fail{message}
    case Done{Step{Build{nodes,references,count},+index}}:
      Done{Step{Build{nodes,Memo{key,index} <> references,count},index}}

def reference_loaded(+key:String,path:List<&2,String>,build:Build,
    loaded:Maybe<&2,J.Value>,cycle:Bool,
    recurse:J.Value -> List<&2,String> -> Build -> Result<&2,&2,String,Step>) -> Result<&2,&2,String,Step>:
  match loaded cycle:
    case _ True{}: Fail{"density registry reference cycle at " ++ key}
    case None{} False{}: Fail{"missing loaded density definition: " ++ key}
    case Some{value} False{}: named(key,recurse(value,key <> path,build))

def reference_memo(+key:String,+path:List<&2,String>,+build:Build,+definitions:List<&2,A.Binding>,memo:Maybe<&2,U32>,
    recurse:J.Value -> List<&2,String> -> Build -> Result<&2,&2,String,Step>) -> Result<&2,&2,String,Step>:
  match memo:
    case Some{index}: Done{Step{build,index}}
    case None{}: reference_loaded(key,path,build,lookup(definitions,key),contains(path,key),recurse)

def reference(+key:String,+path:List<&2,String>,+build:Build,registry:A.Registry,
    recurse:J.Value -> List<&2,String> -> Build -> Result<&2,&2,String,Step>) -> Result<&2,&2,String,Step>:
  match build registry:
    case Build{nodes,+memos,count} A.Registry{definitions,noises}:
      reference_memo(key,path,Build{nodes,memos,count},definitions,lookup_memo(memos,key),recurse)

def form(original:J.Value,form:A.Form,+registry:A.Registry,+path:List<&2,String>,build:Build,+capacity:U32,
    recurse:J.Value -> List<&2,String> -> Build -> Result<&2,&2,String,Step>,
    recurse_two:J.Value -> List<&2,String> -> Build -> Result<&2,&2,String,Step>,
    recurse_three:J.Value -> List<&2,String> -> Build -> Result<&2,&2,String,Step>) -> Result<&2,&2,String,Step>:
  match form:
    case A.Constant{value}: append(build,original,A.OpConstant{value},capacity)
    case A.Reference{key}: reference(key,path,build,registry,recurse)
    case A.Unary{operation,input}:
      continued(recurse(input,path,build),next => index => append(next,original,A.OpUnary{operation,index},capacity))
    case A.Binary{+operation,left,right}:
      binary_admitted(operation,original,capacity,left,right,path,build,recurse,recurse_two,binary_supported(operation))
    case A.Gradient{axis,bottom,top,from,to}: append(build,original,A.OpGradient{axis,bottom,top,from,to},capacity)
    case A.Clamp{input,low,high}:
      continued(recurse(input,path,build),next => index => append(next,original,A.OpClamp{index,low,high},capacity))
    case A.Lerp{alpha,first,second}:
      continued(recurse(alpha,path,build),next => alpha =>
        continued(recurse_two(first,path,next),next => first =>
          continued(recurse_three(second,path,next),next => second => append(next,original,A.OpLerp{alpha,first,second},capacity))))
    case A.RangeChoice{input,low,high,inside,outside}:
      continued(recurse(input,path,build),next => input =>
        continued(recurse_two(inside,path,next),next => inside =>
          continued(recurse_three(outside,path,next),next => outside => append(next,original,A.OpRangeChoice{input,low,high,inside,outside},capacity))))
    case A.Cache{input}:
      continued(recurse(input,path,build),next => index => append(next,original,A.OpCache{index},capacity))
    case A.BaseNoise{config}: append(build,original,A.OpBaseNoise{config},capacity)
    case A.Noise{key,xz,y,+sx,+sy,+sz}:
      continued(recurse(sx,path,build),next => x_index =>
        continued(recurse_two(sy,path,next),next => y_index =>
          continued(recurse_three(sz,path,next),next => z_index => append(next,original,A.OpNoise{key,xz,y,x_index,y_index,z_index,noise_mode(sx,sy,sz)},capacity))))
    case A.ShiftA{key}: append(build,original,A.OpShiftA{key},capacity)
    case A.ShiftB{key}: append(build,original,A.OpShiftB{key},capacity)
    case A.Unsupported{kind,definition}: Fail{"unsupported density function: " ++ kind}

def decoded(original:J.Value,registry:A.Registry,path:List<&2,String>,build:Build,capacity:U32,
    recurse:J.Value -> List<&2,String> -> Build -> Result<&2,&2,String,Step>,
    recurse_two:J.Value -> List<&2,String> -> Build -> Result<&2,&2,String,Step>,
    recurse_three:J.Value -> List<&2,String> -> Build -> Result<&2,&2,String,Step>,
    result:Result<&2,&2,String,A.Form>) -> Result<&2,&2,String,Step>:
  match result:
    case Fail{message}: Fail{message}
    case Done{value}: form(original,value,registry,path,build,capacity,recurse,recurse_two,recurse_three)

def lower(+fuel:Nat,+original:J.Value,+registry:A.Registry,path:List<&2,String>,build:Build,+capacity:U32) -> Result<&2,&2,String,Step>:
  match fuel:
    case 0n: Fail{"density expression exceeds caller reference/depth budget"}
    case 1n+rest:
      decoded(original,registry,path,build,capacity,
        value => path => state => lower(rest,value,registry,path,state,capacity),
        value => path => state => lower(rest,value,registry,path,state,capacity),
        value => path => state => lower(rest,value,registry,path,state,capacity),Codec.read(original))

def prepared(plan:O.Plan,registry:A.Registry,expression:J.Value,result:Result<&2,&2,String,Step>) -> Result<&2,&2,String,A.Program>:
  match result:
    case Fail{message}: Fail{message}
    case Done{Step{Build{nodes,references,count},root}}:
      Done{A.Program{plan,registry,expression,List.reverse(&2,A.Node,nodes),root}}

def admitted(+plan:O.Plan,+registry:A.Registry,+expression:J.Value,depth:Nat,capacity:U32,valid:Bool) -> Result<&2,&2,String,A.Program>:
  match valid:
    case False{}: Fail{"loaded density/noise registry has invalid identities, duplicates or exceeds caller budget"}
    case True{}: prepared(plan,registry,expression,lower(depth,expression,registry,[],Build{[],[],0},capacity))

def compile(plan:O.Plan,+registry:A.Registry,expression:J.Value,limits:Limits) -> Result<&2,&2,String,A.Program>:
  match limits:
    case Limits{depth,nodes,entries}: admitted(plan,registry,expression,depth,nodes,registry_valid(registry,entries))
