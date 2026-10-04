import Base

# Every U32 has at most ten decimal digits. This word-based renderer avoids
# Nat.show's mutually recursive continuation representation in the independent
# exporter, while preserving the canonical component identity spelling.
def digits(fuel:Nat,+word:U32,suffix:String,more:Bool) -> String:
  match fuel more:
    case 0n _: suffix
    case _ False{}: suffix
    case 1n+n True{}:
      +next = U32.div(word,10)
      digits(n,next,SCon{Chr{U32.add(48,U32.mod(word,10))},suffix},U32.is_gt(next,0))

def show(word:U32) -> String:
  digits(10n,word,"",True{})
