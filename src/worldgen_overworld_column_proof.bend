import Base
import ./worldgen_overworld_column_laws.bend as ColumnLaws
import ./worldgen_overworld_laws.bend as Laws
import ./worldgen_overworld_proof.bend as OverworldProof
import ./worldgen_overworld.bend as O
import ./worldgen_noise_laws.bend as NoiseLaws
import ./worldgen_noise_proof.bend as NoiseProof
import ./worldgen_blended_noise.bend as BL
import ./worldgen_perlin_noise.bend as P
import ./f64.bend as F

# The induction carries the actual returned pair, its equation, and the complete
# original sampler owner. The column values need no independent sampler read.
def loop_finished(-plan:O.Plan,-original:BL.Blended,-next:BL.Blended,
    -x:U32,-z:U32,-bottom:U32,-step:U32,-rest:Nat,-y:U32,-values:List<&2,F32>,-value:F32,
    sampled:{BL.sample_block(original,False{},x,y,z) == (next,value) : BL.Blended & F32},
    retained:{next == original : BL.Blended},actual:O.Sampler & O.Column,
    evidence:{O.sample_loop(plan,x,z,bottom,step,rest,U32.add(y,step),value <> values,next) ==
      actual : O.Sampler & O.Column} &
      {NoiseLaws.state_owner(O.Sampler,O.Column,actual) == O.Sampler{plan,next} : O.Sampler}) ->
    NoiseProof.StateWitness(O.Sampler,O.Column,O.Sampler{plan,original},
      O.sample_loop(plan,x,z,bottom,step,1n+rest,y,values,original)):
  match actual evidence:
    case Tuple{sampler,column} Tuple{continued,owned}:
      ((sampler,column),
        ((%Equal.sym(BL.Blended & F32,BL.sample_block(original,False{},x,y,z),(next,value),sampled) :
          {P.paired(BL.Blended,F32,O.Sampler & O.Column,_,
            next => value => O.sample_loop(plan,x,z,bottom,step,rest,U32.add(y,step),value <> values,next)) ==
            (sampler,column) : O.Sampler & O.Column}
        continued),
        (%retained :
          {NoiseLaws.state_owner(O.Sampler,O.Column,(sampler,column)) == O.Sampler{plan,_} : O.Sampler}
        owned)))

def loop_continued(-plan:O.Plan,-original:BL.Blended,-next:BL.Blended,
    -x:U32,-z:U32,-bottom:U32,-step:U32,-rest:Nat,-y:U32,-values:List<&2,F32>,-value:F32,
    sampled:{BL.sample_block(original,False{},x,y,z) == (next,value) : BL.Blended & F32},
    retained:{next == original : BL.Blended},
    result:NoiseProof.StateWitness(O.Sampler,O.Column,O.Sampler{plan,next},
      O.sample_loop(plan,x,z,bottom,step,rest,U32.add(y,step),value <> values,next))) ->
    NoiseProof.StateWitness(O.Sampler,O.Column,O.Sampler{plan,original},
      O.sample_loop(plan,x,z,bottom,step,1n+rest,y,values,original)):
  match result:
    case Tuple{actual,evidence}:
      loop_finished(plan,original,next,x,z,bottom,step,rest,y,values,value,sampled,retained,actual,evidence)

# This continuation is the structurally smaller induction hypothesis, rather
# than a generic erased callback for the producer. Its result names the real
# sample_loop expression and its complete actual returned owner.
def loop_sample_pair(-plan:O.Plan,-original:BL.Blended,
    -x:U32,-z:U32,-bottom:U32,-step:U32,-rest:Nat,-y:U32,-values:List<&2,F32>,
    actual:BL.Blended & F32,
    evidence:{BL.sample_block(original,False{},x,y,z) == actual : BL.Blended & F32} &
      {NoiseLaws.state_owner(BL.Blended,F32,actual) == original : BL.Blended},
    induction:(@next:BL.Blended -> @+value:F32 ->
      NoiseProof.StateWitness(O.Sampler,O.Column,O.Sampler{plan,next},
        O.sample_loop(plan,x,z,bottom,step,rest,U32.add(y,step),value <> values,next)))) ->
    NoiseProof.StateWitness(O.Sampler,O.Column,O.Sampler{plan,original},
      O.sample_loop(plan,x,z,bottom,step,1n+rest,y,values,original)):
  match actual evidence:
    case Tuple{next,+value} Tuple{sampled,retained}:
      loop_continued(plan,original,next,x,z,bottom,step,rest,y,values,value,sampled,retained,
        induction(next,value))

def loop_sample_result(-plan:O.Plan,-original:BL.Blended,
    -x:U32,-z:U32,-bottom:U32,-step:U32,-rest:Nat,-y:U32,-values:List<&2,F32>,
    result:NoiseProof.StateWitness(BL.Blended,F32,original,BL.sample_block(original,False{},x,y,z)),
    induction:(@next:BL.Blended -> @+value:F32 ->
      NoiseProof.StateWitness(O.Sampler,O.Column,O.Sampler{plan,next},
        O.sample_loop(plan,x,z,bottom,step,rest,U32.add(y,step),value <> values,next)))) ->
    NoiseProof.StateWitness(O.Sampler,O.Column,O.Sampler{plan,original},
      O.sample_loop(plan,x,z,bottom,step,1n+rest,y,values,original)):
  match result:
    case Tuple{actual,evidence}:
      loop_sample_pair(plan,original,x,z,bottom,step,rest,y,values,actual,evidence,induction)

def loop_owned(+plan:O.Plan,+x:U32,+z:U32,+bottom:U32,+step:U32,count:Nat,+y:U32,
    +values:List<&2,F32>,blended:BL.Blended) ->
    NoiseProof.StateWitness(O.Sampler,O.Column,O.Sampler{plan,blended},
      O.sample_loop(plan,x,z,bottom,step,count,y,values,blended)):
  match count:
    case 0n:
      ((O.Sampler{plan,blended},
        O.Column{"minecraft:overworld/base_3d_noise",x,z,bottom,step,List.reverse(&2,F32,values)}),({==},{==}))
    case 1n+rest:
      loop_sample_result(plan,blended,x,z,bottom,step,rest,y,values,
        NoiseProof.blended_owned(blended,False{},F.from_i32(x),F.from_i32(y),F.from_i32(z)),
        next => +value => loop_owned(plan,x,z,bottom,step,rest,U32.add(y,step),value <> values,next))

def ColumnWitness(-original:O.Sampler,-actual:O.Sampler & Result<&2,&2,String,O.Column>) -> Type:
  Exists(O.Sampler & Result<&2,&2,String,O.Column>,r =>
    {actual == r : O.Sampler & Result<&2,&2,String,O.Column>} &
    {Laws.column_owner(r) == original : O.Sampler})

def sampled_pair(-plan:O.Plan,-blended:BL.Blended,-x:U32,-z:U32,-bottom:U32,-step:U32,-count:U32,
    actual:O.Sampler & O.Column,
    evidence:{O.sample_loop(plan,x,z,bottom,step,U32.to_nat(count),bottom,[],blended) ==
      actual : O.Sampler & O.Column} &
      {NoiseLaws.state_owner(O.Sampler,O.Column,actual) == O.Sampler{plan,blended} : O.Sampler}) ->
    ColumnWitness(O.Sampler{plan,blended},O.column_admitted(O.Sampler{plan,blended},
      O.ColumnRequest{x,z,bottom,step,count},True{})):
  match actual evidence:
    case Tuple{sampler,column} Tuple{same,owned}:
      ((sampler,Done{column}),
        ((%Equal.sym(O.Sampler & O.Column,
          O.sample_loop(plan,x,z,bottom,step,U32.to_nat(count),bottom,[],blended),(sampler,column),same) :
          {O.sampled(_) == (sampler,Done{column}) : O.Sampler & Result<&2,&2,String,O.Column>}
        {==}),owned))

def sampled_result(-plan:O.Plan,-blended:BL.Blended,-x:U32,-z:U32,-bottom:U32,-step:U32,-count:U32,
    result:NoiseProof.StateWitness(O.Sampler,O.Column,O.Sampler{plan,blended},
      O.sample_loop(plan,x,z,bottom,step,U32.to_nat(count),bottom,[],blended))) ->
    ColumnWitness(O.Sampler{plan,blended},O.column_admitted(O.Sampler{plan,blended},
      O.ColumnRequest{x,z,bottom,step,count},True{})):
  match result:
    case Tuple{actual,evidence}: sampled_pair(plan,blended,x,z,bottom,step,count,actual,evidence)

def admitted_owned(sampler:O.Sampler,request:O.ColumnRequest,valid:Bool) ->
    ColumnWitness(sampler,O.column_admitted(sampler,request,valid)):
  match sampler request valid:
    case _ _ False{}:
      ((sampler,Fail{"column density request exceeds signed-coordinate or sample budget"}),({==},{==}))
    case O.Sampler{+plan,blended} O.ColumnRequest{+x,+z,+bottom,+step,+count} True{}:
      sampled_result(plan,blended,x,z,bottom,step,count,
        loop_owned(plan,x,z,bottom,step,U32.to_nat(count),bottom,[],blended))

def column_project_pair(-sampler:O.Sampler,-request:O.ColumnRequest,-budget:U32,
    actual:O.Sampler & Result<&2,&2,String,O.Column>,
    evidence:{O.sample_column(sampler,request,budget) == actual : O.Sampler & Result<&2,&2,String,O.Column>} &
      {Laws.column_owner(actual) == sampler : O.Sampler}) ->
    {Laws.column_owner(O.sample_column(sampler,request,budget)) == sampler : O.Sampler}:
  match evidence:
    case Tuple{same,owned}:
      %Equal.sym(O.Sampler & Result<&2,&2,String,O.Column>,O.sample_column(sampler,request,budget),actual,same) :
        {Laws.column_owner(_) == sampler : O.Sampler}
      owned

def column_project(-sampler:O.Sampler,-request:O.ColumnRequest,-budget:U32,
    result:ColumnWitness(sampler,O.sample_column(sampler,request,budget))) ->
    {Laws.column_owner(O.sample_column(sampler,request,budget)) == sampler : O.Sampler}:
  match result:
    case Tuple{actual,evidence}: column_project_pair(sampler,request,budget,actual,evidence)

def ColumnLaws.every_column_read_retains_complete_sampler(sampler,request,budget):
  column_project(sampler,request,budget,
    admitted_owned(sampler,request,O.request_valid(request,budget)))
