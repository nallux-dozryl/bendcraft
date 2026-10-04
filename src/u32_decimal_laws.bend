import Base
import ./u32_decimal.bend as D

law zero_has_one_digit:
  {D.show(0) == "0" : String}

law maximum_has_ten_digits:
  {D.show(4294967295) == "4294967295" : String}

law stopped_digits_preserve_complete_accumulated_suffix:
  for fuel:Nat
  for word:U32
  for suffix:String
  {D.digits(fuel,word,suffix,False{}) == suffix : String}

law exhausted_budget_preserves_complete_accumulated_suffix:
  for word:U32
  for suffix:String
  for more:Bool
  {D.digits(0n,word,suffix,more) == suffix : String}
