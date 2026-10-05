import Base
import ./block_model.bend as M
import ./json.bend as J

law minus_retains_the_stage_and_updates_only_its_actual_sign:
  for +rest:String
  for +stage:U32
  for +reversed:List<&2,U32>
  for +fraction:U32
  for +exponent:U32
  for +exponent_negative:Bool
  for +negative:Bool
  {M.int_scan_admitted(SCon{Chr{45},rest},True{},stage,reversed,fraction,exponent,exponent_negative,negative) ==
    M.int_scan_admitted(rest,True{},stage,reversed,fraction,exponent,J.choose(Bool,True{},exponent_negative,U32.is_ge(stage,2)),J.choose(Bool,negative,True{},U32.is_ge(stage,2))) : Result<&2,&2,M.Error,M.IntToken>}
def minus_retains_the_stage_and_updates_only_its_actual_sign(rest,stage,reversed,fraction,exponent,exponent_negative,negative):
  {==}

law plus_preserves_all_accumulated_token_fields:
  for +rest:String
  for +stage:U32
  for +reversed:List<&2,U32>
  for +fraction:U32
  for +exponent:U32
  for +exponent_negative:Bool
  for +negative:Bool
  {M.int_scan_admitted(SCon{Chr{43},rest},True{},stage,reversed,fraction,exponent,exponent_negative,negative) ==
    M.int_scan_admitted(rest,True{},stage,reversed,fraction,exponent,exponent_negative,negative) : Result<&2,&2,M.Error,M.IntToken>}
def plus_preserves_all_accumulated_token_fields(rest,stage,reversed,fraction,exponent,exponent_negative,negative):
  {==}

law point_selects_fractional_stage_and_preserves_the_token:
  for +rest:String
  for +stage:U32
  for +reversed:List<&2,U32>
  for +fraction:U32
  for +exponent:U32
  for +exponent_negative:Bool
  for +negative:Bool
  {M.int_scan_admitted(SCon{Chr{46},rest},True{},stage,reversed,fraction,exponent,exponent_negative,negative) ==
    M.int_scan_admitted(rest,True{},1,reversed,fraction,exponent,exponent_negative,negative) : Result<&2,&2,M.Error,M.IntToken>}
def point_selects_fractional_stage_and_preserves_the_token(rest,stage,reversed,fraction,exponent,exponent_negative,negative):
  {==}

law lower_exponent_selects_stage_two_and_preserves_the_token:
  for +rest:String
  for +stage:U32
  for +reversed:List<&2,U32>
  for +fraction:U32
  for +exponent:U32
  for +exponent_negative:Bool
  for +negative:Bool
  {M.int_scan_admitted(SCon{Chr{101},rest},True{},stage,reversed,fraction,exponent,exponent_negative,negative) ==
    M.int_scan_admitted(rest,True{},2,reversed,fraction,exponent,exponent_negative,negative) : Result<&2,&2,M.Error,M.IntToken>}
def lower_exponent_selects_stage_two_and_preserves_the_token(rest,stage,reversed,fraction,exponent,exponent_negative,negative):
  {==}

law upper_exponent_selects_stage_two_and_preserves_the_token:
  for +rest:String
  for +stage:U32
  for +reversed:List<&2,U32>
  for +fraction:U32
  for +exponent:U32
  for +exponent_negative:Bool
  for +negative:Bool
  {M.int_scan_admitted(SCon{Chr{69},rest},True{},stage,reversed,fraction,exponent,exponent_negative,negative) ==
    M.int_scan_admitted(rest,True{},2,reversed,fraction,exponent,exponent_negative,negative) : Result<&2,&2,M.Error,M.IntToken>}
def upper_exponent_selects_stage_two_and_preserves_the_token(rest,stage,reversed,fraction,exponent,exponent_negative,negative):
  {==}

law refused_admission_keeps_the_exact_error_for_any_remaining_text:
  for text:String
  for stage:U32
  for reversed:List<&2,U32>
  for fraction:U32
  for exponent:U32
  for exponent_negative:Bool
  for negative:Bool
  {M.int_scan_admitted(text,False{},stage,reversed,fraction,exponent,exponent_negative,negative) ==
    Fail{M.Error{"UnsupportedIntegerExponent","integer"}} : Result<&2,&2,M.Error,M.IntToken>}
def refused_admission_keeps_the_exact_error_for_any_remaining_text(text,stage,reversed,fraction,exponent,exponent_negative,negative):
  match text:
    case SNil{}: {==}
    case SCon{Chr{head},tail}: {==}

law admitted_end_reverses_only_the_digit_owner_and_keeps_every_metadata_field:
  for +stage:U32
  for +reversed:List<&2,U32>
  for +fraction:U32
  for +exponent:U32
  for +exponent_negative:Bool
  for +negative:Bool
  {M.int_scan_admitted(SNil{},True{},stage,reversed,fraction,exponent,exponent_negative,negative) ==
    Done{M.IntToken{List.reverse(&2,U32,reversed),fraction,exponent,exponent_negative,negative}} : Result<&2,&2,M.Error,M.IntToken>}
def admitted_end_reverses_only_the_digit_owner_and_keeps_every_metadata_field(stage,reversed,fraction,exponent,exponent_negative,negative):
  {==}

law whole_digit_preserves_fraction_exponent_and_signs:
  for +rest:String
  for +reversed:List<&2,U32>
  for +fraction:U32
  for +exponent:U32
  for +exponent_negative:Bool
  for +negative:Bool
  {M.int_scan_admitted(SCon{Chr{55},rest},True{},0,reversed,fraction,exponent,exponent_negative,negative) ==
    M.int_scan_admitted(rest,True{},0,7 <> reversed,fraction,exponent,exponent_negative,negative) : Result<&2,&2,M.Error,M.IntToken>}
def whole_digit_preserves_fraction_exponent_and_signs(rest,reversed,fraction,exponent,exponent_negative,negative):
  {==}

law fractional_digit_increments_only_fraction_and_extends_digits:
  for +rest:String
  for +reversed:List<&2,U32>
  for +fraction:U32
  for +exponent:U32
  for +exponent_negative:Bool
  for +negative:Bool
  {M.int_scan_admitted(SCon{Chr{55},rest},True{},1,reversed,fraction,exponent,exponent_negative,negative) ==
    M.int_scan_admitted(rest,True{},1,7 <> reversed,U32.add(fraction,1),exponent,exponent_negative,negative) : Result<&2,&2,M.Error,M.IntToken>}
def fractional_digit_increments_only_fraction_and_extends_digits(rest,reversed,fraction,exponent,exponent_negative,negative):
  {==}

law exponent_digit_preserves_digits_and_uses_the_original_wrapping_limit:
  for +rest:String
  for +reversed:List<&2,U32>
  for +fraction:U32
  for +exponent:U32
  for +exponent_negative:Bool
  for +negative:Bool
  {M.int_scan_admitted(SCon{Chr{55},rest},True{},2,reversed,fraction,exponent,exponent_negative,negative) ==
    M.int_scan_admitted(rest,U32.is_le(U32.add(U32.mul(exponent,10),7),100000),2,reversed,fraction,U32.add(U32.mul(exponent,10),7),exponent_negative,negative) : Result<&2,&2,M.Error,M.IntToken>}
def exponent_digit_preserves_digits_and_uses_the_original_wrapping_limit(rest,reversed,fraction,exponent,exponent_negative,negative):
  {==}
