import Base
import ../src/f64.bend as F
import ../src/nbt.bend as N
import ../src/player_look.bend as PL
import ../src/vanilla_entity_fields.bend as E

law signed_long_int_cast:
  for hi: U32
  for +lo: U32
  {E.as_int(N.Long{N.Word64{hi, lo}}) == Some{lo} : Maybe<&2, U32>}

def signed_long_int_cast(hi, lo):
  {==}

law unknown_member_order_and_value:
  for +name: N.Text
  for +value: N.Value
  {E.rewrite_members([N.Member{name, value}], Nil{}) == [N.Member{name, value}] : List<&2, N.Member>}

def unknown_member_order_and_value(name, value):
  {==}

# Runtime harness only: physical files enter the pure production adapter; all
# affine documents/trees are explicitly consumed after recording their data.
def words(bytes: List<&2, U32>) -> Result<&2, &2, String, List<&2, U32>>:
  match bytes:
    case Nil{}: Done{Nil{}}
    case a <> b <> c <> d <> rest:
      do Result<&2, &2, String, List<&2, U32>>:
        tail : List<&2, U32> <- words(rest)
        return U32.or(a, U32.or(U32.shln(b, 8n), U32.or(U32.shln(c, 16n), U32.shln(d, 24n)))) <> tail
    case _: Fail{"word fixture has a partial word"}

def fields(words: List<&2, U32>) -> Result<&2, &2, String, E.Fields>:
  match words:
    case a <> b <> c <> d <> e <> f <> g <> h <> i <> j <> k <> l <>
      m <> n <> o <> p <> q <> r <> s <> t <> u <> v <> w <> x <>
      yaw <> pitch <> py <> pp <> head <> body <> fh <> fl <>
      +ground <> air <> fire <> portal <> +invul <> +sync <> Nil{}:
      N.choose(Result<&2, &2, String, E.Fields>,
        Done{E.Fields{E.Vec3{F.F64{a,b},F.F64{c,d},F.F64{e,f}}, E.Vec3{F.F64{g,h},F.F64{i,j},F.F64{k,l}},
          E.Vec3{F.F64{m,n},F.F64{o,p},F.F64{q,r}}, E.Vec3{F.F64{s,t},F.F64{u,v},F.F64{w,x}},
          PL.State{PL.float_bits(yaw),PL.float_bits(pitch),PL.float_bits(py),PL.float_bits(pp)}, PL.float_bits(head),PL.float_bits(body),F.F64{fh,fl},
          U32.is_eq(ground,1),air,fire,portal,U32.is_eq(invul,1),U32.is_eq(sync,1)}},
        Fail{"noncanonical Boolean fixture"}, U32.is_le(ground,1) && U32.is_le(invul,1) && U32.is_le(sync,1))
    case _: Fail{"field fixture must contain 38 words"}

def double_words(value: F.F64) -> List<&2, U32>:
  match value:
    case F.F64{hi,lo}: [hi,lo]

def vector_words(value: E.Vec3) -> List<&2, U32>:
  match value:
    case E.Vec3{x,y,z}: List.append(&2,U32,double_words(x),List.append(&2,U32,double_words(y),double_words(z)))

def field_words(value: E.Fields) -> List<&2, U32>:
  match value:
    case E.Fields{pos,vel,o,old,PL.State{yaw,pitch,py,pp},head,body,fall,ground,air,fire,portal,invul,sync}:
      List.append(&2,U32,vector_words(pos),List.append(&2,U32,vector_words(vel),List.append(&2,U32,vector_words(o),List.append(&2,U32,vector_words(old),
        List.append(&2,U32,[PL.raw(yaw),PL.raw(pitch),PL.raw(py),PL.raw(pp),PL.raw(head),PL.raw(body)],List.append(&2,U32,double_words(fall),
          [Bool.to_u32(ground),air,fire,portal,Bool.to_u32(invul),Bool.to_u32(sync)]))))))

def bytes(words: List<&2, U32>) -> List<&2, U32>:
  match words:
    case Nil{}: Nil{}
    case +word <> rest: U32.and(word,255) <> U32.and(U32.shrn(word,8n),255) <> U32.and(U32.shrn(word,16n),255) <> U32.shrn(word,24n) <> bytes(rest)

def error_text(error: E.Error) -> String:
  match error:
    case E.UnsupportedConfig{}: "UnsupportedConfig"
    case E.InvalidPrior{field}: "InvalidPrior:" ++ U32.show(field)
    case E.InvalidPosition{axis}: "InvalidPosition:" ++ U32.show(axis)
    case E.NbtError{message}: "NbtError"
    case E.RootType{}: "RootType"
    case E.DuplicateSelected{key}: "DuplicateSelected:" ++ key
    case E.UnsupportedNumericLong{key}: "UnsupportedNumericLong:" ++ key

def note_text(note: E.Note) -> String:
  match note:
    case E.NonNumericScalar{key,tag}: "NonNumericScalar:" ++ key ++ ":" ++ U32.show(tag)
    case E.InvalidVector{key}: "InvalidVector:" ++ key
    case E.VectorSize{key,expected,actual,partial}: "VectorSize:" ++ key ++ ":" ++ U32.show(expected) ++ ":" ++ U32.show(actual) ++ ":" ++ U32.show(Bool.to_u32(partial))

def notes_text(notes: List<&2, E.Note>) -> String:
  match notes:
    case Nil{}: ""
    case h <> Nil{}: "\"" ++ note_text(h) ++ "\""
    case h <> rest: "\"" ++ note_text(h) ++ "\"," ++ notes_text(rest)

def file_read_done(result: File & Result<&1,&1,U32 & String,List<&2,U32>>) -> IO(List<&2,U32>):
  (file,status) = result
  do IO<List<&2,U32>>:
    File.close(file)
    IO.pass(List<&2,U32>,status)

def read(path: String) -> IO(List<&2,U32>):
  do IO<List<&2,U32>>:
    file : File <- IO.try(File,File.open(path,"r"))
    result : File & Result<&1,&1,U32 & String,List<&2,U32>> <- File.read_bytes(file,1048577)
    file_read_done(result)

def write_done(result: File & Result<&1,&1,U32 & String,Unit>) -> IO(Unit):
  (file,status) = result
  do IO<Unit>:
    IO.pass(Unit,status)
    File.close(file)

def write(path: String, data: List<&2,U32>) -> IO(Unit):
  do IO<Unit>:
    file : File <- IO.try(File,File.open(path,"w"))
    result : File & Result<&1,&1,U32 & String,Unit> <- File.write_bytes(file,data)
    write_done(result)

def io_result(-A: Data, result: Result<&2,&2,String,A>) -> Result<&1,&1,U32 & String,A>:
  match result:
    case Fail{message}: Fail{(2,message)}
    case Done{value}: Done{value}

def write_root(path: String, root: N.Root) -> IO(Unit):
  do IO<Unit>:
    data : List<&2,U32> <- IO.pass(List<&2,U32>,io_result(List<&2,U32>,N.encode(root)))
    write(path,data)


def consume_document(document: E.Document, result: Unit) -> IO(Unit):
  do IO<Unit>:
    IO.pure(Unit,E.close_document(document))

def recovery(prefix: String, result: E.LoadOutcome) -> IO(Unit):
  match result:
    case E.Accepted{E.Document{tree,+value},notes}:
      do IO<Unit>:
        write(prefix ++ ".recovery",bytes(field_words(value)))
        IO.pure(Unit,E.close_tree(tree))
    case E.Rejected{prior,candidate,error}:
      do IO<Unit>:
        IO.pure(Unit,E.close_document(prior))
        IO.pure(Unit,E.close_tree(candidate))

def rejected(+prefix: String, prior: E.Document, candidate: E.TagTree, error: E.Error) -> IO(Unit):
  match prior candidate:
    case E.Document{E.TagTree{+root},+value} E.TagTree{candidate_root}:
      do IO<Unit>:
        write(prefix ++ ".state",bytes(field_words(value)))
        write_root(prefix ++ ".prior",root)
        write_root(prefix ++ ".candidate",candidate_root)
        recovery(prefix,E.load(E.Document{E.TagTree{root},value},E.TagTree{N.Root{E.text("recovery"),N.Compound{Nil{}}}},E.default_config()))
        IO.print("{\"ok\":false,\"error\":\"" ++ error_text(error) ++ "\"}")

def saved(+prefix: String, report: String, result: E.SaveOutcome) -> IO(Unit):
  match result:
    case E.Saved{E.Document{E.TagTree{+root},+value},E.TagTree{output}}:
      do IO<Unit>:
        write(prefix ++ ".state",bytes(field_words(value)))
        write_root(prefix ++ ".prior",root)
        write_root(prefix ++ ".saved",output)
        IO.print(report)
    case E.SaveRejected{E.Document{E.TagTree{root},value},error}:
      do IO<Unit>:
        write(prefix ++ ".state",bytes(field_words(value)))
        write_root(prefix ++ ".prior",root)
        IO.print("{\"ok\":false,\"error\":\"" ++ error_text(error) ++ "\"}")

def loaded(prefix: String, config: E.Config, result: E.LoadOutcome) -> IO(Unit):
  match result:
    case E.Rejected{prior,candidate,error}: rejected(prefix,prior,candidate,error)
    case E.Accepted{document,notes}:
      saved(prefix,"{\"ok\":true,\"notes\":[" ++ notes_text(notes) ++ "]}",E.save(document,config))

def execute(mode: String, prefix: String, +config: E.Config, prior_fields: E.Fields, prior_root: N.Root, candidate: N.Root) -> IO(Unit):
  match mode:
    case "load": loaded(prefix,config,E.load(E.Document{E.TagTree{prior_root},prior_fields},E.TagTree{candidate},config))
    case "save": saved(prefix,"{\"ok\":true}",E.save(E.Document{E.TagTree{prior_root},prior_fields},config))
    case _: IO.die(Unit,2,"expected load or save")

def run(mode: String, field_path: String, prior_path: String, candidate_path: String, prefix: String, config: E.Config) -> IO(Unit):
  do IO<Unit>:
    field_bytes : List<&2,U32> <- read(field_path)
    word_list : List<&2,U32> <- IO.pass(List<&2,U32>,io_result(List<&2,U32>,words(field_bytes)))
    value : E.Fields <- IO.pass(E.Fields,io_result(E.Fields,fields(word_list)))
    prior_bytes : List<&2,U32> <- read(prior_path)
    prior_root : N.Root <- IO.pass(N.Root,io_result(N.Root,N.decode_with(N.Limits{1048576,64,65536},prior_bytes)))
    candidate_bytes : List<&2,U32> <- read(candidate_path)
    candidate : N.Root <- IO.pass(N.Root,io_result(N.Root,N.decode_with(N.Limits{1048576,64,65536},candidate_bytes)))
    execute(mode,prefix,config,value,prior_root,candidate)

def parameters(mode: String, fields: String, prior: String, candidate: String, prefix: String,
    a: Maybe<&2,U32>, b: Maybe<&2,U32>, c: Maybe<&2,U32>, d: Maybe<&2,U32>) -> IO(Unit):
  match a b c d:
    case Some{bytes} Some{depth} Some{elements} Some{air}: run(mode,fields,prior,candidate,prefix,E.Config{N.Limits{bytes,depth,elements},air})
    case _ _ _ _: IO.die(Unit,2,"invalid unsigned config word")

def batch(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit,Unit{})
    case mode <> fields <> prior <> candidate <> prefix <> a <> b <> c <> d <> rest:
      do IO<Unit>:
        parameters(mode,fields,prior,candidate,prefix,U32.read(a),U32.read(b),U32.read(c),U32.read(d))
        batch(rest)
    case _: IO.die(Unit,2,"expected nine argument groups")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    batch(List.tail(&1,String,args))
