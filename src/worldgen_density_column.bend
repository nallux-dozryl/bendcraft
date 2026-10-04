import Base
import ./worldgen_density.bend as D
import ./worldgen_density_state.bend as S
import ./worldgen_density_ast.bend as A
import ./worldgen_overworld.bend as O
import ./json.bend as J

# This is a production density-column consumer of the loaded finite graph.
# It publishes no block sections and cannot replace the missing final-density,
# aquifer, material, surface or structure stages with a scalar threshold.
type Column is Data:
  Column{expression:J.Value,x:U32,z:U32,min_y:U32,step:U32,values:List<&2,F32>}

def continued(result:S.State & Result<&2,&2,String,F32>,
    next:S.State -> F32 -> S.State & Result<&2,&2,String,Column>) -> S.State & Result<&2,&2,String,Column>:
  match result:
    case Tuple{state,Fail{message}}: (state,Fail{message})
    case Tuple{state,Done{value}}: next(state)(value)

def sample_loop(count:Nat,state:S.State,+depth:Nat,+index:U32,+expression:J.Value,
    +x:U32,+z:U32,+bottom:U32,+step:U32,+y:U32,values:List<&2,F32>) -> S.State & Result<&2,&2,String,Column>:
  match count:
    case 0n: (state,Done{Column{expression,x,z,bottom,step,List.reverse(&2,F32,values)}})
    case 1n+rest:
      continued(D.evaluate(depth,state,index,S.Point{x,y,z}),
        state => value => sample_loop(rest,state,depth,index,expression,x,z,bottom,step,U32.add(y,step),value <> values))

def transaction(original:S.Cache,result:S.State & Result<&2,&2,String,Column>) -> S.State & Result<&2,&2,String,Column>:
  match result:
    case Tuple{S.State{program,pool,cache},Fail{message}}: (S.State{program,pool,original},Fail{message})
    case Tuple{state,Done{column}}: (state,Done{column})

def admitted(state:S.State,request:O.ColumnRequest,depth:Nat,valid:Bool) -> S.State & Result<&2,&2,String,Column>:
  match state request valid:
    case _ _ False{}: (state,Fail{"column density request exceeds signed-coordinate or sample budget"})
    case S.State{A.Program{plan,registry,+expression,nodes,+index},pool,+cache}
        O.ColumnRequest{x,z,+bottom,step,count} True{}:
      transaction(cache,sample_loop(U32.to_nat(count),S.State{A.Program{plan,registry,expression,nodes,index},pool,cache},
        depth,index,expression,x,z,bottom,step,bottom,[]))

def sample(state:S.State,+request:O.ColumnRequest,budget:U32,depth:Nat) -> S.State & Result<&2,&2,String,Column>:
  admitted(state,request,depth,O.request_valid(request,budget))
