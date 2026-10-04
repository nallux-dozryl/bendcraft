import Base
import ./u32_decimal.bend as D
import ./u32_decimal_laws.bend as Laws

def Laws.zero_has_one_digit():
  {==}

def Laws.maximum_has_ten_digits():
  {==}

def Laws.stopped_digits_preserve_complete_accumulated_suffix(fuel,word,suffix):
  match fuel:
    case 0n: {==}
    case 1n+rest: {==}

def Laws.exhausted_budget_preserves_complete_accumulated_suffix(word,suffix,more):
  match more:
    case False{}: {==}
    case True{}: {==}
