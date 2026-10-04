import Base
import ./nbt.bend as N
import ./random.bend as R
import ./worldgen_md5.bend as M

# The root is derived once from the actual durable seed and settings' random
# algorithm. Named streams derive from this immutable positional factory;
# their initialization/read order cannot advance a different named stream.
type Root is Data:
  Root{seed:N.Word64,legacy:Bool,factory:R.Positional}

def source(seed:N.Word64,legacy:Bool) -> R.Source:
  match seed legacy:
    case N.Word64{hi,lo} True{}: R.seeded_legacy(R.Bits64{hi,lo})
    case N.Word64{hi,lo} False{}: R.seeded_xoroshiro(R.Bits64{hi,lo})

def root_result(seed:N.Word64,legacy:Bool,result:R.Source & R.Positional) -> Root:
  (advanced,factory) = result
  Root{seed,legacy,factory}

def new(+seed:N.Word64,+legacy:Bool) -> Root:
  root_result(seed,legacy,R.fork_positional(source(seed,legacy)))

def ascii_byte(code:U32,valid:Bool,result:Result<&2,&2,String,List<&2,U32>>) -> Result<&2,&2,String,List<&2,U32>>:
  match valid result:
    case False{} _: Fail{"worldgen seed name must be ASCII"}
    case True{} Fail{message}: Fail{message}
    case True{} Done{bytes}: Done{code <> bytes}

# Resource identifiers and octave stream names in the pinned registry are
# ASCII. Other strings are refused explicitly, rather than mis-encoded as
# Java UTF-8. The byte budget is supplied by the producer's resource policy.
def ascii_bytes_with(room:Nat,text:String) -> Result<&2,&2,String,List<&2,U32>>:
  match room text:
    case _ SNil{}: Done{[]}
    case 0n _: Fail{"worldgen seed name exceeds byte budget"}
    case 1n+left SCon{Chr{+code},rest}:
      ascii_byte(code,U32.is_lt(code,128),ascii_bytes_with(left,rest))

def named_digest(low:R.Bits64,high:R.Bits64,result:Result<&2,&2,String,M.Digest>) -> Result<&2,&2,String,R.Source>:
  match result:
    case Fail{message}: Fail{message}
    case Done{M.Digest{a,b,c,d}}:
      Done{R.raw_xoroshiro(R.bits_xor(low,R.Bits64{M.byte_swap(a),M.byte_swap(b)}),
        R.bits_xor(high,R.Bits64{M.byte_swap(c),M.byte_swap(d)}))}

def named_bytes(limit:Nat,low:R.Bits64,high:R.Bits64,result:Result<&2,&2,String,List<&2,U32>>) -> Result<&2,&2,String,R.Source>:
  match result:
    case Fail{message}: Fail{message}
    case Done{bytes}: named_digest(low,high,M.digest(limit,bytes))

def legacy_name(seed:R.Bits64,text:String,result:Result<&2,&2,String,List<&2,U32>>) -> Result<&2,&2,String,R.Source>:
  match result:
    case Fail{message}: Fail{message}
    case Done{bytes}: Done{R.seeded_legacy(R.bits_xor(R.sign_extend(R.java_string_hash(text)),seed))}

def named_with(+limit:Nat,factory:R.Positional,+text:String) -> Result<&2,&2,String,R.Source>:
  match factory:
    case R.LegacyPositional{seed}:
      legacy_name(seed,text,ascii_bytes_with(limit,text))
    case R.XoroshiroPositional{low,high}: named_bytes(limit,low,high,ascii_bytes_with(limit,text))

def named(factory:R.Positional,text:String) -> Result<&2,&2,String,R.Source>:
  named_with(16384n,factory,text)

# RandomState's legacy exception applies only to the terrain stream; all
# other named streams still derive from the root positional factory.
def compiled_random_choice(seed:N.Word64,factory:R.Positional,name:String,legacy_terrain:Bool) -> Result<&2,&2,String,R.Source>:
  match legacy_terrain:
    case True{}: Done{source(seed,True{})}
    case False{}: named(factory,name)

def compiled_random(root:Root,+name:String) -> Result<&2,&2,String,R.Source>:
  match root:
    case Root{seed,+legacy,factory}:
      compiled_random_choice(seed,factory,name,legacy && String.eq(name,"minecraft:terrain"))

def seed(root:Root) -> N.Word64:
  match root:
    case Root{seed,legacy,factory}: seed
