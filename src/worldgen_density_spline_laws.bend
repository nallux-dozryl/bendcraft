import Base
import ./worldgen_density_spline.bend as S
import ./worldgen_density_spline_compile.bend as C
import ./worldgen_density_spline_eval.bend as E
import ./worldgen_density_spline_range.bend as R
import ./worldgen_density_interval.bend as I
import ./json.bend as J

# These contracts cover actual one-layer compilation/evaluation over arbitrary
# complete affine owners and arbitrary callbacks. Numeric parity is a separate
# pinned-Java/native obligation; none of these laws manufacture an IEEE theorem.
law constant_evaluation_retains_complete_owner:
  for -Owner:Type
  for value:F32
  for owner:Owner
  for coordinate:Owner -> U32 -> Owner & Result<&2,&2,String,F32>
  for one:S.Tree<U32> -> Owner -> Owner & Result<&2,&2,String,F32>
  for left:S.Tree<U32> -> Owner -> Owner & Result<&2,&2,String,F32>
  for right:S.Tree<U32> -> Owner -> Owner & Result<&2,&2,String,F32>
  {E.step(Owner,S.Constant{value},owner,coordinate,one,left,right) ==
    (owner,Done{value}) : Owner & Result<&2,&2,String,F32>}

law coordinate_failure_cancels_child_evaluation:
  for -Owner:Type
  for points:List<&2,S.Point<U32>>
  for owner:Owner
  for message:String
  for one:S.Tree<U32> -> Owner -> Owner & Result<&2,&2,String,F32>
  for left:S.Tree<U32> -> Owner -> Owner & Result<&2,&2,String,F32>
  for right:S.Tree<U32> -> Owner -> Owner & Result<&2,&2,String,F32>
  {E.coordinate(Owner,points,(owner,Fail{message}),one,left,right) ==
    (owner,Fail{message}) : Owner & Result<&2,&2,String,F32>}

law refused_selection_retains_complete_owner:
  for -Owner:Type
  for owner:Owner
  for x:F32
  for points:List<&2,S.Point<U32>>
  for message:String
  for one:S.Tree<U32> -> Owner -> Owner & Result<&2,&2,String,F32>
  for left:S.Tree<U32> -> Owner -> Owner & Result<&2,&2,String,F32>
  for right:S.Tree<U32> -> Owner -> Owner & Result<&2,&2,String,F32>
  {E.selection(Owner,owner,x,points,Fail{message},one,left,right) ==
    (owner,Fail{message}) : Owner & Result<&2,&2,String,F32>}

law absent_endpoint_cancels_child_evaluation:
  for -Owner:Type
  for owner:Owner
  for x:F32
  for read:S.Tree<U32> -> Owner -> Owner & Result<&2,&2,String,F32>
  {E.endpoint(Owner,owner,x,None{},read) ==
    (owner,Fail{"density spline selected point is absent"}) : Owner & Result<&2,&2,String,F32>}

law failed_left_endpoint_cancels_right_evaluation:
  for -Owner:Type
  for x:F32
  for l0:F32
  for l1:F32
  for value:S.Tree<U32>
  for d0:F32
  for d1:F32
  for owner:Owner
  for message:String
  for read:S.Tree<U32> -> Owner -> Owner & Result<&2,&2,String,F32>
  {E.segment_left(Owner,x,l0,l1,value,d0,d1,(owner,Fail{message}),read) ==
    (owner,Fail{message}) : Owner & Result<&2,&2,String,F32>}

law constant_compilation_retains_complete_owner:
  for -Owner:Type
  for value:F32
  for owner:Owner
  for coordinate:Owner -> J.Value -> Owner & Result<&2,&2,String,U32>
  for points:Owner -> List<&2,S.Point<J.Value>> -> Owner & Result<&2,&2,String,List<&2,S.Point<U32>>>
  {C.tree(Owner,S.Constant{value},owner,coordinate,points) ==
    (owner,Done{S.Constant{value}}) : Owner & Result<&2,&2,String,S.Tree<U32>>}

law empty_point_compilation_retains_complete_owner:
  for -Owner:Type
  for owner:Owner
  for tree:Owner -> S.Tree<J.Value> -> Owner & Result<&2,&2,String,S.Tree<U32>>
  for rest:Owner -> List<&2,S.Point<J.Value>> -> Owner & Result<&2,&2,String,List<&2,S.Point<U32>>>
  {C.points(Owner,[],owner,tree,rest) ==
    (owner,Done{[]}) : Owner & Result<&2,&2,String,List<&2,S.Point<U32>>>}

law coordinate_compile_failure_cancels_point_compilation:
  for -Owner:Type
  for points:List<&2,S.Point<J.Value>>
  for owner:Owner
  for message:String
  for read:Owner -> List<&2,S.Point<J.Value>> -> Owner & Result<&2,&2,String,List<&2,S.Point<U32>>>
  {C.coordinate_result(Owner,points,(owner,Fail{message}),read) ==
    (owner,Fail{message}) : Owner & Result<&2,&2,String,S.Tree<U32>>}

law failed_point_value_cancels_tail_compilation:
  for -Owner:Type
  for location:F32
  for derivative:F32
  for rest:List<&2,S.Point<J.Value>>
  for owner:Owner
  for message:String
  for read:Owner -> List<&2,S.Point<J.Value>> -> Owner & Result<&2,&2,String,List<&2,S.Point<U32>>>
  {C.point_tree_result(Owner,location,derivative,rest,(owner,Fail{message}),read) ==
    (owner,Fail{message}) : Owner & Result<&2,&2,String,List<&2,S.Point<U32>>>}

law successful_point_compilation_preserves_order:
  for -Owner:Type
  for point:S.Point<U32>
  for owner:Owner
  for rest:List<&2,S.Point<U32>>
  {C.points_result(Owner,point,(owner,Done{rest})) ==
    (owner,Done{point <> rest}) : Owner & Result<&2,&2,String,List<&2,S.Point<U32>>>}

law nai_coordinate_range_cancels_child_range_reads:
  for next:I.Interval -> Result<&2,&2,String,R.Output>
  {R.coordinate_result(Done{I.NaI{}},next) ==
    Done{R.RangeOutput{I.NaI{}}} : Result<&2,&2,String,R.Output>}
