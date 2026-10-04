import Base
import ./f64.bend as F
import ./worldgen_noise_settings.bend as NS
import ./json.bend as J

# JSON's original decimal token is converted as an exact integer ratio.
# The bit lists are little endian and normalized. The numerical resource policy
# admits 64 mantissa digits and an explicit exponent magnitude at most 384;
# unsupported larger tokens fail, rather than rounding through binary32.
type Big is Data:
  Big{bits:List<&2,Bool>}

type Decimal is Data:
  Decimal{negative:Bool,mantissa:Big,fraction_digits:U32,exponent_negative:Bool,exponent:U32}

def cleaned_head(bit:Bool,rest:List<&2,Bool>) -> List<&2,Bool>:
  match bit rest:
    case False{} Nil{}: []
    case _ _: bit <> rest

def cleaned(bits:List<&2,Bool>) -> List<&2,Bool>:
  match bits:
    case Nil{}: []
    case bit <> rest: cleaned_head(bit,cleaned(rest))

def big(bits:List<&2,Bool>) -> Big: Big{cleaned(bits)}

def small_bits(fuel:Nat,+value:U32) -> List<&2,Bool>:
  match fuel:
    case 0n: []
    case 1n+rest:
      U32.is_ne(U32.and(value,1),0) <> small_bits(rest,U32.shr(value))

def small(value:U32) -> Big: big(small_bits(32n,value))

def double(value:Big) -> Big:
  match value:
    case Big{Nil{}}: Big{[]}
    case Big{bit <> rest}: Big{False{} <> bit <> rest}

def add_bits(a:List<&2,Bool>,b:List<&2,Bool>,+carry:Bool) -> List<&2,Bool>:
  match a b carry:
    case Nil{} Nil{} False{}: []
    case Nil{} Nil{} True{}: [True{}]
    case +bit <> rest Nil{} _:
      Bool.xor(bit,carry) <> add_bits(rest,[],bit && carry)
    case Nil{} +bit <> rest _:
      Bool.xor(bit,carry) <> add_bits([],rest,bit && carry)
    case +a <> ar +b <> br +carry:
      Bool.xor(Bool.xor(a,b),carry) <> add_bits(ar,br,(a && b) || (a && carry) || (b && carry))

def add(a:Big,b:Big) -> Big:
  match a b:
    case Big{ab} Big{bb}: big(add_bits(ab,bb,False{}))

def times10(+value:Big) -> Big:
  add(double(value),double(double(double(value))))

def cmp_head(result:Cmp,a:Bool,b:Bool) -> Cmp:
  match result a b:
    case LT{} _ _: LT{}
    case GT{} _ _: GT{}
    case EQ{} False{} True{}: LT{}
    case EQ{} True{} False{}: GT{}
    case EQ{} _ _: EQ{}

def cmp_bits(a:List<&2,Bool>,b:List<&2,Bool>) -> Cmp:
  match a b:
    case Nil{} Nil{}: EQ{}
    case Nil{} _ <> _: LT{}
    case _ <> _ Nil{}: GT{}
    case a <> ar b <> br: cmp_head(cmp_bits(ar,br),a,b)

def cmp(a:Big,b:Big) -> Cmp:
  match a b:
    case Big{ab} Big{bb}: cmp_bits(ab,bb)

def sub_bits(a:List<&2,Bool>,b:List<&2,Bool>,+borrow:Bool) -> List<&2,Bool>:
  match a b:
    case Nil{} _: []
    case +a <> ar Nil{}:
      Bool.xor(a,borrow) <> sub_bits(ar,[],Bool.not(a) && borrow)
    case +a <> ar +b <> br:
      Bool.xor(Bool.xor(a,b),borrow) <> sub_bits(ar,br,
        (Bool.not(a) && (b || borrow)) || (b && borrow))

# Callers subtract only after the exact nonnegative comparison.
def sub(a:Big,b:Big) -> Big:
  match a b:
    case Big{ab} Big{bb}: big(sub_bits(ab,bb,False{}))

def pow10_loop(fuel:Nat,value:Big) -> Big:
  match fuel:
    case 0n: value
    case 1n+rest: pow10_loop(rest,times10(value))

def pow10(power:U32) -> Big: pow10_loop(U32.to_nat(power),small(1))

def exponent_checked(result:Result<&2,&2,String,Decimal>,valid:Bool) -> Result<&2,&2,String,Decimal>:
  match valid:
    case False{}: Fail{"density decimal exponent exceeds numerical resource budget"}
    case True{}: result

def exponent_digits(text:String,negative:Bool,mantissa:Big,fraction:U32,exponent_negative:Bool,+value:U32) -> Result<&2,&2,String,Decimal>:
  match text:
    case SNil{}: Done{Decimal{negative,mantissa,fraction,exponent_negative,value}}
    case SCon{Chr{+code},rest}:
      exponent_checked(exponent_digits(rest,negative,mantissa,fraction,exponent_negative,
        U32.add(U32.mul(value,10),U32.sub(code,48))),
        U32.is_le(value,38) && U32.is_le(U32.add(U32.mul(value,10),U32.sub(code,48)),384))

def exponent(text:String,negative:Bool,mantissa:Big,fraction:U32) -> Result<&2,&2,String,Decimal>:
  match text:
    case SCon{Chr{45},rest}: exponent_digits(rest,negative,mantissa,fraction,True{},0)
    case SCon{Chr{43},rest}: exponent_digits(rest,negative,mantissa,fraction,False{},0)
    case _: exponent_digits(text,negative,mantissa,fraction,False{},0)

def mantissa_checked(result:Result<&2,&2,String,Decimal>,valid:Bool) -> Result<&2,&2,String,Decimal>:
  match valid:
    case False{}: Fail{"density decimal mantissa exceeds numerical resource budget"}
    case True{}: result

def mantissa_digits(text:String,negative:Bool,value:Big,+after_dot:Bool,+fraction:U32,+digits:U32) -> Result<&2,&2,String,Decimal>:
  match text:
    case SNil{}: Done{Decimal{negative,value,fraction,False{},0}}
    case SCon{Chr{46},rest}: mantissa_digits(rest,negative,value,True{},fraction,digits)
    case SCon{Chr{101},rest}: exponent(rest,negative,value,fraction)
    case SCon{Chr{69},rest}: exponent(rest,negative,value,fraction)
    case SCon{Chr{code},rest}:
      mantissa_checked(mantissa_digits(rest,negative,add(times10(value),small(U32.sub(code,48))),after_dot,
        U32.add(fraction,Bool.to_u32(after_dot)),U32.inc(digits)),U32.is_lt(digits,64))

def decimal_body(text:String) -> Result<&2,&2,String,Decimal>:
  match text:
    case SCon{Chr{45},rest}: mantissa_digits(rest,True{},small(0),False{},0,0)
    case _: mantissa_digits(text,False{},small(0),False{},0,0)

def admitted_decimal(text:String,valid:Bool) -> Result<&2,&2,String,Decimal>:
  match valid:
    case False{}: Fail{"density number is not a bounded JSON decimal token"}
    case True{}: decimal_body(text)

def decimal(+text:String) -> Result<&2,&2,String,Decimal>:
  admitted_decimal(text,NS.number_valid(text) && J.within(128n,text))

def multiply_loop(bits:List<&2,Bool>,+factor:Big,accumulator:Big) -> Big:
  match bits:
    case Nil{}: accumulator
    case False{} <> rest: multiply_loop(rest,double(factor),accumulator)
    case True{} <> rest: multiply_loop(rest,double(factor),add(accumulator,factor))

def multiply(a:Big,b:Big) -> Big:
  match a:
    case Big{bits}: multiply_loop(bits,b,small(0))

def sticky(word:F.Wide,nonzero:Bool) -> F.Wide:
  match word:
    case F.Wide{hi,lo}: F.Wide{hi,U32.or(lo,Bool.to_u32(nonzero))}

def fraction_choice(+numerator:Big,+denominator:Big,word:F.Wide,relation:Cmp,
    continuation:Big -> F.Wide -> F.F64) -> F.F64:
  match relation:
    case LT{}: continuation(numerator,F.wide_shl(word))
    case _: continuation(sub(numerator,denominator),F.wide_increment(F.wide_shl(word)))

def fraction_loop(fuel:Nat,negative:Bool,+numerator:Big,+denominator:Big,exponent:U32,word:F.Wide) -> F.F64:
  match fuel:
    case 0n:
      F.product_normalized(negative,exponent,sticky(word,Bool.not(Cmp.is_eq(cmp(numerator,small(0))))))
    case 1n+rest:
      fraction_choice(double(numerator),denominator,word,cmp(double(numerator),denominator),
        next => word => fraction_loop(rest,negative,next,denominator,exponent,word))

def normalize_choice(negative:Bool,+numerator:Big,+denominator:Big,exponent:U32,
    lower:Cmp,upper:Cmp,continuation:Big -> Big -> U32 -> Result<&2,&2,String,F.F64>) -> Result<&2,&2,String,F.F64>:
  match lower upper:
    case LT{} _: continuation(double(numerator),denominator,U32.sub(exponent,1))
    case _ LT{}: Done{fraction_loop(55n,negative,sub(numerator,denominator),denominator,exponent,F.Wide{0,1})}
    case _ _: continuation(numerator,double(denominator),U32.inc(exponent))

def normalize(fuel:Nat,+negative:Bool,+numerator:Big,+denominator:Big,+exponent:U32) -> Result<&2,&2,String,F.F64>:
  match fuel:
    case 0n: Fail{"density decimal normalization exceeds numerical resource budget"}
    case 1n+rest:
      normalize_choice(negative,numerator,denominator,exponent,
        cmp(numerator,denominator),cmp(numerator,double(denominator)),
        next_n => next_d => next_e => normalize(rest,negative,next_n,next_d,next_e))

def rational_power(negative:Bool,mantissa:Big,power:U32,below:Bool) -> Result<&2,&2,String,F.F64>:
  match below:
    case True{}: normalize(4096n,negative,mantissa,pow10(U32.sub(0,power)),3071)
    case False{}: normalize(4096n,negative,multiply(mantissa,pow10(power)),small(1),3071)

def rational_signed(negative:Bool,mantissa:Big,+fraction:U32,exponent_negative:Bool,+exponent:U32) -> Result<&2,&2,String,F.F64>:
  match exponent_negative:
    case True{}: rational_power(negative,mantissa,U32.sub(0,U32.add(exponent,fraction)),True{})
    case False{}:
      rational_power(negative,mantissa,U32.sub(exponent,fraction),U32.is_lt(exponent,fraction))

def rational_nonzero(negative:Bool,mantissa:Big,fraction:U32,exponent_negative:Bool,exponent:U32,nonzero:Bool) -> Result<&2,&2,String,F.F64>:
  match nonzero:
    case False{}: Done{F.F64{F.sign_mask(negative),0}}
    case True{}: rational_signed(negative,mantissa,fraction,exponent_negative,exponent)

def converted(result:Result<&2,&2,String,Decimal>) -> Result<&2,&2,String,F.F64>:
  match result:
    case Fail{message}: Fail{message}
    case Done{Decimal{negative,+mantissa,fraction,exponent_negative,exponent}}:
      rational_nonzero(negative,mantissa,fraction,exponent_negative,exponent,Bool.not(Cmp.is_eq(cmp(mantissa,small(0)))))

def read(text:String) -> Result<&2,&2,String,F.F64>: converted(decimal(text))
