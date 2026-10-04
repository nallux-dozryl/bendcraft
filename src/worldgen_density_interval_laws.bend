import Base
import ./worldgen_density_interval.bend as I
import ./worldgen_density_minmax.bend as M
import ./worldgen_density_ranges.bend as R
import ./worldgen_density_ast.bend as A
import ./json.bend as J

# Structural interval refusal/NaI and actual compiled-sampler control-flow
# contracts. Floating arithmetic parity is measured at the native IEEE boundary.
law nai_absorbs_addition:
  for range:I.Interval
  {I.add(I.NaI{},range) == Done{I.NaI{}} : Result<&2,&2,String,I.Interval>}

law nai_absorbs_subtraction:
  for range:I.Interval
  {I.sub(range,I.NaI{}) == Done{I.NaI{}} : Result<&2,&2,String,I.Interval>}

law nai_absorbs_multiplication:
  for range:I.Interval
  {I.mul(I.NaI{},range) == Done{I.NaI{}} : Result<&2,&2,String,I.Interval>}

law nai_absorbs_minimum:
  for range:I.Interval
  {I.min(range,I.NaI{}) == Done{I.NaI{}} : Result<&2,&2,String,I.Interval>}

law nai_absorbs_maximum:
  for range:I.Interval
  {I.max(I.NaI{},range) == Done{I.NaI{}} : Result<&2,&2,String,I.Interval>}

law nai_alpha_cancels_lerp_bounds:
  for first:F32
  for last:F32
  {I.lerp_pair(I.NaI{},first,last) == Done{I.NaI{}} : Result<&2,&2,String,I.Interval>}

law empty_encapsulation_is_refused:
  {I.encapsulate_ranges([]) == Fail{"density interval encapsulation requires a nonempty list"} : Result<&2,&2,String,I.Interval>}

law missing_range_child_is_refused:
  for index:U32
  {R.child([],index) == Fail{"density range child is absent or does not precede its parent"} : Result<&2,&2,String,I.Interval>}

law missing_noise_range_is_refused:
  for key:String
  {R.normal_loaded(key,None{}) == Fail{"density range requires the loaded normal-noise definition"} : Result<&2,&2,String,I.Interval>}

law empty_range_analysis_retains_complete_existing_table:
  for registry:A.Registry
  for entries:List<&2,R.Entry>
  {R.analyze([],registry,entries) == Done{entries} : Result<&2,&2,String,List<&2,R.Entry>>}

law minmax_disjoint_left_reads_only_left:
  for -Owner:Type
  for operation:A.Binary
  for left:U32
  for right:U32
  for owner:Owner
  for first:Owner -> U32 -> Owner & Result<&2,&2,String,F32>
  for second:Owner -> U32 -> Owner & Result<&2,&2,String,F32>
  {M.step(Owner,operation,left,right,A.ReadLeft{},owner,first,second) ==
    first(owner,left) : Owner & Result<&2,&2,String,F32>}

law minmax_disjoint_right_reads_only_right:
  for -Owner:Type
  for operation:A.Binary
  for left:U32
  for right:U32
  for owner:Owner
  for first:Owner -> U32 -> Owner & Result<&2,&2,String,F32>
  for second:Owner -> U32 -> Owner & Result<&2,&2,String,F32>
  {M.step(Owner,operation,left,right,A.ReadRight{},owner,first,second) ==
    second(owner,right) : Owner & Result<&2,&2,String,F32>}

law successful_bound_short_circuit_retains_complete_owner:
  for -Owner:Type
  for operation:A.Binary
  for owner:Owner
  for value:F32
  for right:U32
  for read:Owner -> U32 -> Owner & Result<&2,&2,String,F32>
  {M.second(Owner,operation,owner,value,right,True{},read) ==
    (owner,Done{value}) : Owner & Result<&2,&2,String,F32>}

law failed_left_minmax_cancels_right_read:
  for -Owner:Type
  for operation:A.Binary
  for right:U32
  for bound:F32
  for owner:Owner
  for message:String
  for read:Owner -> U32 -> Owner & Result<&2,&2,String,F32>
  {M.first(Owner,operation,right,bound,(owner,Fail{message}),read) ==
    (owner,Fail{message}) : Owner & Result<&2,&2,String,F32>}

law failed_constant_input_retains_complete_owner:
  for -Owner:Type
  for operation:A.Binary
  for constant:F32
  for owner:Owner
  for message:String
  {M.constant_combined(Owner,operation,constant,(owner,Fail{message})) ==
    (owner,Fail{message}) : Owner & Result<&2,&2,String,F32>}
