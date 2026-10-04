import Base
import ../src/block_light_registry.bend as R
import ../src/block_light_registry_decoder.bend as D
import ../src/block_light_registry_loader.bend as L
import ../src/block_light.bend as B

def identity() -> String: "4f75fa335a12e34cf74be71ff6a0ee530b13233212423f5463bb26a2fe4f3cfc"
def show_descriptor(result:Maybe<&2,B.Descriptor>) -> String:
  match result:
    case None{}: "? ? ?"
    case Some{B.Descriptor{state,emission,dampening}}: U32.show(state) ++ " " ++ U32.show(emission) ++ " " ++ U32.show(dampening)
def show_face(result:Result<&2,&2,R.Error,U32>) -> String:
  match result:
    case Fail{error}: "?"
    case Done{face}: U32.show(face)
def show_bit(result:Result<&2,&2,R.Error,Bool>) -> String:
  match result:
    case Fail{error}: "?"
    case Done{False{}}: "0"
    case Done{True{}}: "1"
def facing(+catalog:R.Catalog,+state:U32) -> String:
  show_face(R.state_face(catalog,state,B.Down{})) ++ " " ++
  show_face(R.state_face(catalog,state,B.Up{})) ++ " " ++
  show_face(R.state_face(catalog,state,B.North{})) ++ " " ++
  show_face(R.state_face(catalog,state,B.South{})) ++ " " ++
  show_face(R.state_face(catalog,state,B.West{})) ++ " " ++
  show_face(R.state_face(catalog,state,B.East{}))
def edges(+catalog:R.Catalog,+source:U32,+target:U32) -> String:
  show_bit(R.occlusion(catalog,source,target,B.Down{})) ++
  show_bit(R.occlusion(catalog,source,target,B.Up{})) ++
  show_bit(R.occlusion(catalog,source,target,B.North{})) ++
  show_bit(R.occlusion(catalog,source,target,B.South{})) ++
  show_bit(R.occlusion(catalog,source,target,B.West{})) ++
  show_bit(R.occlusion(catalog,source,target,B.East{}))
def emit_states(fuel:Nat,+catalog:R.Catalog,+index:U32,+count:U32) -> IO(Unit):
  match fuel:
    case 0n: IO.pure(Unit,Unit{})
    case 1n+p:
      do IO<Unit>:
        IO.print("S " ++ show_descriptor(R.properties(catalog,index)) ++ " " ++
          facing(catalog,index) ++ " " ++ edges(catalog,index,U32.mod(U32.add(U32.mul(index,7919),13),count)))
        emit_states(p,catalog,U32.inc(index),count)
def pair_bits(fuel:Nat,+catalog:R.Catalog,+source:U32,+target:U32) -> String:
  match fuel:
    case 0n: ""
    case 1n+p: show_bit(R.face_pair(catalog,source,target)) ++ pair_bits(p,catalog,source,U32.inc(target))
def emit_pairs(fuel:Nat,+catalog:R.Catalog,+index:U32,+shapes:U32) -> IO(Unit):
  match fuel:
    case 0n: IO.pure(Unit,Unit{})
    case 1n+p:
      do IO<Unit>:
        IO.print("F " ++ U32.show(index) ++ " " ++ pair_bits(U32.to_nat(shapes),catalog,index,0))
        emit_pairs(p,catalog,U32.inc(index),shapes)
def decode_status(result:Result<&2,&2,D.Error,R.Catalog>) -> String:
  match result:
    case Fail{D.Schema{line,message}}: "schema"
    case Fail{D.IdentityMismatch{identity}}: "identity"
    case Fail{D.StateCountMismatch{count}}: "count"
    case Done{catalog}: "ok"
def mini_header(states:String,shapes:String,ranges:String,words:String) -> String:
  "BendBlockLightRegistry\t1\t26.3\tI\t" ++ states ++ "\t" ++ shapes ++ "\t" ++ ranges ++ "\t" ++ words ++ "\n"
def mini_ranges() -> String:
  "S\t0\t1\t0\t0\t0\t0\t0\t0\t0\t0\nS\t1\t1\t15\t15\t1\t1\t1\t1\t1\t1\n"
def mini_faces() -> String: "F\t0\t2\nF\t1\t3\n"
def check(label:String,expected:String,result:Result<&2,&2,D.Error,R.Catalog>) -> IO(Unit):
  IO.print("guard " ++ label ++ " " ++ expected ++ "/" ++ decode_status(result))
def guards() -> IO(Unit):
  +header : String = mini_header("2","2","2","1")
  +ranges : String = mini_ranges()
  +faces : String = mini_faces()
  +valid : String = header ++ ranges ++ faces
  do IO<Unit>:
    check("valid","ok",D.decode("I",2,valid))
    check("identity","identity",D.decode("wrong",2,valid))
    check("count","count",D.decode("I",3,valid))
    check("version","schema",D.decode("I",2,"BendBlockLightRegistry\t1\t26.4\tI\t2\t2\t2\t1\n" ++ ranges ++ faces))
    check("width","schema",D.decode("I",2,mini_header("2","2","2","2") ++ ranges ++ faces))
    check("zero_shape","schema",D.decode("I",2,mini_header("2","0","2","0") ++ ranges ++ faces))
    check("range_gap","schema",D.decode("I",2,header ++ "S\t1\t1\t0\t0\t0\t0\t0\t0\t0\t0\n" ++ ranges ++ faces))
    check("range_overflow","schema",D.decode("I",2,header ++ "S\t0\t3\t0\t0\t0\t0\t0\t0\t0\t0\n" ++ ranges ++ faces))
    check("zero_range","schema",D.decode("I",2,header ++ "S\t0\t0\t0\t0\t0\t0\t0\t0\t0\t0\n" ++ ranges ++ faces))
    check("emission","schema",D.decode("I",2,header ++ "S\t0\t1\t16\t0\t0\t0\t0\t0\t0\t0\n" ++ ranges ++ faces))
    check("dampening","schema",D.decode("I",2,header ++ "S\t0\t1\t0\t16\t0\t0\t0\t0\t0\t0\n" ++ ranges ++ faces))
    check("face","schema",D.decode("I",2,header ++ "S\t0\t1\t0\t0\t2\t0\t0\t0\t0\t0\n" ++ ranges ++ faces))
    check("coverage","schema",D.decode("I",2,mini_header("2","2","1","1") ++ "S\t0\t1\t0\t0\t0\t0\t0\t0\t0\t0\n" ++ faces))
    check("matrix_gap","schema",D.decode("I",2,header ++ ranges ++ "F\t1\t2\nF\t1\t3\n"))
    check("matrix_padding","schema",D.decode("I",2,header ++ ranges ++ "F\t0\t4\nF\t1\t3\n"))
    check("matrix_truncated","schema",D.decode("I",2,header ++ ranges ++ "F\t0\t2\n"))
    check("matrix_extra_word","schema",D.decode("I",2,header ++ ranges ++ "F\t0\t2\t0\nF\t1\t3\n"))
    check("trailing","schema",D.decode("I",2,valid ++ "extra\n"))
    check("noncanonical","schema",D.decode("I",2,mini_header("02","2","2","1") ++ ranges ++ faces))
    check("overflow_decimal","schema",D.decode("I",2,mini_header("4294967298","2","2","1") ++ ranges ++ faces))
def loader_status(result:Result<&2,&2,L.Error,R.Catalog>) -> String:
  match result:
    case Fail{L.Decode{error}}: "decode"
    case Fail{L.Text{message}}: "text"
    case Fail{L.IntegrityMismatch{}}: "integrity"
    case Fail{L.ByteLimit{limit}}: "limit"
    case Fail{L.Read{code,message}}: "read"
    case Fail{L.ReadLimitOutsideU32{limit}}: "read-limit"
    case Done{catalog}: "ok"
def loaded(result:Result<&2,&2,L.Error,R.Catalog>) -> IO(Unit):
  match result:
    case Fail{error}: IO.print("load " ++ loader_status(Fail{error}))
    case Done{+catalog}:
      R.Catalog{identity,+count,+shapes,entries,rows} = catalog
      do IO<Unit>:
        IO.print("meta " ++ U32.show(count) ++ " " ++ U32.show(shapes))
        emit_states(U32.to_nat(count),catalog,0,count)
        emit_pairs(U32.to_nat(shapes),catalog,0,shapes)
        IO.print("outside " ++ show_descriptor(R.properties(catalog,count)) ++ " " ++
          show_face(R.state_face(catalog,4294967295,B.Up{})) ++ " " ++ show_bit(R.face_pair(catalog,shapes,0)))
        IO.print("closed " ++ show_bit(Done{R.occludes(catalog,B.Descriptor{4294967295,0,0},B.Descriptor{0,0,0},B.East{})}))
def main() -> IO(Unit):
  do IO<Unit>:
    guards()
    IO.print("guard loader_corruption integrity/" ++ loader_status(L.parse(identity(),35723,8n,[0])))
    bytes : Result<&2,&2,L.Error,List<&2,U32>> <- L.read_file(1n,"reference/block_light_registry.tsv")
    IO.print("guard loader_limit limit/" ++ loader_status(L.loaded(identity(),35723,1n,bytes)))
    absent : Result<&2,&2,L.Error,List<&2,U32>> <- L.read_file(1024n,"build/block-light-registry/absent-file")
    IO.print("guard loader_absent read/" ++ loader_status(L.loaded(identity(),35723,1024n,absent)))
    result : Result<&2,&2,L.Error,R.Catalog> <- L.load(identity(),35723,1048576n,"reference/block_light_registry.tsv")
    loaded(result)
