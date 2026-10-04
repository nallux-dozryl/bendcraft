import Base
import ./generic_resource_world_sample_numeric_continuations_laws.bend as Laws
import ./block_model.bend as M
import ./blockstate_model.bend as S

def Laws.model_guard_matches_original_result_continuation(next,allowed,continuation):
  match allowed:
    case True{}: {==}
    case False{}: {==}

def Laws.blockstate_guard_matches_original_result_continuation(next,allowed,path,continuation):
  match allowed:
    case True{}: {==}
    case False{}: {==}

def Laws.model_wrapped_update_matches_original_expression(exponent,c,continuation):
  Laws.model_guard_matches_original_result_continuation(
    U32.add(U32.mul(exponent,10),U32.sub(c,48)),
    U32.is_le(U32.add(U32.mul(exponent,10),U32.sub(c,48)),100000),continuation)

def Laws.blockstate_wrapped_update_matches_original_expression(exponent,c,path,continuation):
  Laws.blockstate_guard_matches_original_result_continuation(
    U32.add(U32.mul(exponent,10),U32.sub(c,48)),
    U32.is_le(U32.add(U32.mul(exponent,10),U32.sub(c,48)),100000),path,continuation)

def Laws.model_guard_uses_actual_recursive_continuation(rest,stage,reversed,fraction,next,exponent_negative,negative,allowed):
  Laws.model_guard_matches_original_result_continuation(next,allowed,
    value => M.int_scan(rest,stage,reversed,fraction,value,exponent_negative,negative))

def Laws.blockstate_guard_uses_actual_recursive_continuation(rest,stage,digits,fraction,next,eneg,negative,path,allowed):
  Laws.blockstate_guard_matches_original_result_continuation(next,allowed,path,
    value => S.scan_number(rest,stage,digits,fraction,value,eneg,negative,path))
