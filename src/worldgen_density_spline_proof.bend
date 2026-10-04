import Base
import ./worldgen_density_spline_laws.bend as Laws

def Laws.constant_evaluation_retains_complete_owner(Owner,value,owner,coordinate,one,left,right): {==}
def Laws.coordinate_failure_cancels_child_evaluation(Owner,points,owner,message,one,left,right): {==}
def Laws.refused_selection_retains_complete_owner(Owner,owner,x,points,message,one,left,right): {==}
def Laws.absent_endpoint_cancels_child_evaluation(Owner,owner,x,read): {==}
def Laws.failed_left_endpoint_cancels_right_evaluation(Owner,x,l0,l1,value,d0,d1,owner,message,read): {==}
def Laws.constant_compilation_retains_complete_owner(Owner,value,owner,coordinate,points): {==}
def Laws.empty_point_compilation_retains_complete_owner(Owner,owner,tree,rest): {==}
def Laws.coordinate_compile_failure_cancels_point_compilation(Owner,points,owner,message,read): {==}
def Laws.failed_point_value_cancels_tail_compilation(Owner,location,derivative,rest,owner,message,read): {==}
def Laws.successful_point_compilation_preserves_order(Owner,point,owner,rest): {==}
def Laws.nai_coordinate_range_cancels_child_range_reads(next): {==}
