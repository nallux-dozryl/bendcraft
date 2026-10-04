import Base
import ./hash.bend as Hash
import ./unicode.bend as Unicode

def require(valid:Bool,message:String) -> Result<&2,&2,String,Unit>:
  match valid:
    case False{}: Fail{message}
    case True{}: Done{Unit{}}

# One verification policy shared by the saved-player authority and presentation.
# The digest identifies the observed complete item-definition table.
def text(+bytes:List<&2,U32>) -> Result<&2,&2,String,String>:
  do Result<&2,&2,String,String>:
    digest:Hash.Digest <- Hash.digest(U32.to_nat(1048576),bytes)
    require(String.eq(Hash.Digest.hex(digest),"1cf2669ac760fed886b33d19b12e4782d5011c68c629d22328147d8a9a9bfa22"),"pinned item definition table digest mismatch")
    Unicode.decode(U32.to_nat(1048576),bytes)
