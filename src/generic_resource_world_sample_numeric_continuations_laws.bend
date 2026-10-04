import Base
import ./json.bend as J
import ./block_model.bend as M
import ./blockstate_model.bend as S

# These laws state the actual guard substitution for any affine continuation.
# They do not equate the complete original and candidate recursive parsers.
law model_guard_matches_original_result_continuation:
  for +next:U32
  for +allowed:Bool
  for continuation:U32 -> Result<&2,&2,M.Error,M.IntToken>
  {M.int_exponent_guard(next,allowed,continuation) ==
    Result.bind(&2,&2,M.Error,U32,M.IntToken,
      J.choose(Result<&2,&2,M.Error,U32>,Done{next},
        M.fail(U32,"UnsupportedIntegerExponent","integer"),allowed),
      continuation) : Result<&2,&2,M.Error,M.IntToken>}

law blockstate_guard_matches_original_result_continuation:
  for +next:U32
  for +allowed:Bool
  for +path:String
  for continuation:U32 -> Result<&2,&2,S.Error,S.NumberParts>
  {S.scan_number_exponent_guard(next,allowed,path,continuation) ==
    Result.bind(&2,&2,S.Error,U32,S.NumberParts,
      S.choose_value(Result<&2,&2,S.Error,U32>,Done{next},
        S.fail(U32,"IntegerExponentLimit",path,"Exponent magnitude exceeds 100000"),allowed),
      continuation) : Result<&2,&2,S.Error,S.NumberParts>}

law model_wrapped_update_matches_original_expression:
  for +exponent:U32
  for +c:U32
  for continuation:U32 -> Result<&2,&2,M.Error,M.IntToken>
  {M.int_exponent_guard(U32.add(U32.mul(exponent,10),U32.sub(c,48)),
      U32.is_le(U32.add(U32.mul(exponent,10),U32.sub(c,48)),100000),continuation) ==
    Result.bind(&2,&2,M.Error,U32,M.IntToken,
      J.choose(Result<&2,&2,M.Error,U32>,
        Done{U32.add(U32.mul(exponent,10),U32.sub(c,48))},
        M.fail(U32,"UnsupportedIntegerExponent","integer"),
        U32.is_le(U32.add(U32.mul(exponent,10),U32.sub(c,48)),100000)),
      continuation) : Result<&2,&2,M.Error,M.IntToken>}

law blockstate_wrapped_update_matches_original_expression:
  for +exponent:U32
  for +c:U32
  for +path:String
  for continuation:U32 -> Result<&2,&2,S.Error,S.NumberParts>
  {S.scan_number_exponent_guard(U32.add(U32.mul(exponent,10),U32.sub(c,48)),
      U32.is_le(U32.add(U32.mul(exponent,10),U32.sub(c,48)),100000),path,continuation) ==
    Result.bind(&2,&2,S.Error,U32,S.NumberParts,
      S.choose_value(Result<&2,&2,S.Error,U32>,
        Done{U32.add(U32.mul(exponent,10),U32.sub(c,48))},
        S.fail(U32,"IntegerExponentLimit",path,"Exponent magnitude exceeds 100000"),
        U32.is_le(U32.add(U32.mul(exponent,10),U32.sub(c,48)),100000)),
      continuation) : Result<&2,&2,S.Error,S.NumberParts>}

law model_guard_uses_actual_recursive_continuation:
  for +rest:String
  for +stage:U32
  for +reversed:List<&2,U32>
  for +fraction:U32
  for +next:U32
  for +exponent_negative:Bool
  for +negative:Bool
  for +allowed:Bool
  {M.int_exponent_guard(next,allowed,
      value => M.int_scan(rest,stage,reversed,fraction,value,exponent_negative,negative)) ==
    Result.bind(&2,&2,M.Error,U32,M.IntToken,
      J.choose(Result<&2,&2,M.Error,U32>,Done{next},
        M.fail(U32,"UnsupportedIntegerExponent","integer"),allowed),
      value => M.int_scan(rest,stage,reversed,fraction,value,exponent_negative,negative))
      : Result<&2,&2,M.Error,M.IntToken>}

law blockstate_guard_uses_actual_recursive_continuation:
  for +rest:String
  for +stage:U32
  for +digits:List<&2,U32>
  for +fraction:U32
  for +next:U32
  for +eneg:Bool
  for +negative:Bool
  for +path:String
  for +allowed:Bool
  {S.scan_number_exponent_guard(next,allowed,path,
      value => S.scan_number(rest,stage,digits,fraction,value,eneg,negative,path)) ==
    Result.bind(&2,&2,S.Error,U32,S.NumberParts,
      S.choose_value(Result<&2,&2,S.Error,U32>,Done{next},
        S.fail(U32,"IntegerExponentLimit",path,"Exponent magnitude exceeds 100000"),allowed),
      value => S.scan_number(rest,stage,digits,fraction,value,eneg,negative,path))
      : Result<&2,&2,S.Error,S.NumberParts>}
