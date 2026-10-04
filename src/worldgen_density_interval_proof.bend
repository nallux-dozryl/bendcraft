import Base
import ./worldgen_density_interval_laws.bend as Laws
import ./worldgen_density_interval.bend as I

def Laws.nai_absorbs_addition(range):
  match range:
    case I.NaI{}: {==}
    case I.Range{minimum,maximum}: {==}

def Laws.nai_absorbs_subtraction(range):
  match range:
    case I.NaI{}: {==}
    case I.Range{minimum,maximum}: {==}

def Laws.nai_absorbs_multiplication(range):
  match range:
    case I.NaI{}: {==}
    case I.Range{minimum,maximum}: {==}

def Laws.nai_absorbs_minimum(range):
  match range:
    case I.NaI{}: {==}
    case I.Range{minimum,maximum}: {==}

def Laws.nai_absorbs_maximum(range):
  match range:
    case I.NaI{}: {==}
    case I.Range{minimum,maximum}: {==}

def Laws.nai_alpha_cancels_lerp_bounds(first,last): {==}
def Laws.empty_encapsulation_is_refused(): {==}
def Laws.missing_range_child_is_refused(index): {==}
def Laws.missing_noise_range_is_refused(key): {==}
def Laws.empty_range_analysis_retains_complete_existing_table(registry,entries): {==}
def Laws.minmax_disjoint_left_reads_only_left(Owner,operation,left,right,owner,first,second): {==}
def Laws.minmax_disjoint_right_reads_only_right(Owner,operation,left,right,owner,first,second): {==}
def Laws.successful_bound_short_circuit_retains_complete_owner(Owner,operation,owner,value,right,read): {==}
def Laws.failed_left_minmax_cancels_right_read(Owner,operation,right,bound,owner,message,read): {==}
def Laws.failed_constant_input_retains_complete_owner(Owner,operation,constant,owner,message): {==}
