import Base

# Internal nonnegative integer, little-endian base 65536. Canonical zero is [];
# nonzero integers have a nonzero last limb. float_parse keeps every integer
# below 4096 bits. mul_add requires 1 <= factor <= 33554431 and carry <= factor.
type BigUInt is Data:
  BigUInt{limbs: List<&2, U32>}

def choose(-A: Data, yes: A, no: A, test: Bool) -> A:
  match test:
    case True{}: yes
    case False{}: no

def carry_limbs(+carry: U32, high: Bool) -> List<&2, U32>:
  match high:
    case True{}: [U32.and(carry, 65535), U32.shrn(carry, 16n)]
    case False{}: choose(List<&2, U32>, [], [carry], U32.is_eq(carry, 0))

def multiply_limbs(limbs: List<&2, U32>, +factor: U32, +carry: U32) -> List<&2, U32>:
  match limbs:
    case Nil{}: carry_limbs(carry, U32.is_ge(carry, 65536))
    case +limb <> rest:
      +low = U32.add(U32.mul(limb, U32.and(factor, 65535)), U32.and(carry, 65535))
      U32.and(low, 65535) <> multiply_limbs(rest, factor, U32.add(U32.add(U32.shrn(low, 16n), U32.mul(limb, U32.shrn(factor, 16n))), U32.shrn(carry, 16n)))

def mul_add(value: BigUInt, factor: U32, carry: U32) -> BigUInt:
  match value:
    case BigUInt{limbs}: BigUInt{multiply_limbs(limbs, factor, carry)}

def zero() -> BigUInt:
  BigUInt{[]}

def one() -> BigUInt:
  BigUInt{[1]}

def times_ten(fuel: Nat, value: BigUInt) -> BigUInt:
  match fuel:
    case 0n: value
    case 1n+rest: times_ten(rest, mul_add(value, 10, 0))

def prepend_zero(fuel: Nat, limbs: List<&2, U32>) -> List<&2, U32>:
  match fuel:
    case 0n: limbs
    case 1n+rest: 0 <> prepend_zero(rest, limbs)

def shift_nonzero(value: BigUInt, +amount: U32) -> BigUInt:
  match value:
    case BigUInt{limbs}:
      BigUInt{prepend_zero(U32.to_nat(U32.shrn(amount, 4n)), multiply_limbs(limbs, U32.shln(1, U32.to_nat(U32.and(amount, 15))), 0))}

def shl(value: BigUInt, amount: U32) -> BigUInt:
  match value:
    case BigUInt{Nil{}}: zero()
    case BigUInt{limb <> rest}: shift_nonzero(BigUInt{limb <> rest}, amount)

def order_digit(previous: Cmp, current: Cmp) -> Cmp:
  match current:
    case EQ{}: previous
    case _: current

def compare_limbs(left: List<&2, U32>, right: List<&2, U32>, previous: Cmp) -> Cmp:
  match left right:
    case Nil{} Nil{}: previous
    case Nil{} b <> bs: LT{}
    case a <> xs Nil{}: GT{}
    case a <> xs b <> ys: compare_limbs(xs, ys, order_digit(previous, U32.cmp(a, b)))

def compare_lengths(left: List<&2, U32>, right: List<&2, U32>, order: Cmp) -> Cmp:
  match order:
    case EQ{}: compare_limbs(left, right, EQ{})
    case _: order

def compare(left: BigUInt, right: BigUInt) -> Cmp:
  match left right:
    case BigUInt{+xs} BigUInt{+ys}:
      compare_lengths(xs, ys, Nat.cmp(List.length(&2, U32, xs), List.length(&2, U32, ys)))
