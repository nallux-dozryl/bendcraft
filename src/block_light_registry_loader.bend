import Base
import ./block_light_registry.bend as R
import ./block_light_registry_decoder.bend as D
import ./hash.bend as H
import ./unicode.bend as U

type Error is Data:
  Decode{error:D.Error}
  Text{message:String}
  IntegrityMismatch{}
  ByteLimit{limit:Nat}
  Read{code:U32,message:String}
  ReadLimitOutsideU32{limit:Nat}

def pinned_sha256() -> String:
  "0f147d2b6f9fa9cd3442ecd57175ae5f886d14b297f9ee45c1055ec2c0ad2f88"
def decoded(result:Result<&2,&2,D.Error,R.Catalog>) -> Result<&2,&2,Error,R.Catalog>:
  match result:
    case Fail{error}: Fail{Decode{error}}
    case Done{catalog}: Done{catalog}
def text(identity:String,count:U32,result:Result<&2,&2,String,String>) -> Result<&2,&2,Error,R.Catalog>:
  match result:
    case Fail{message}: Fail{Text{message}}
    case Done{content}: decoded(D.decode(identity,count,content))
def integrity(identity:String,count:U32,limit:Nat,bytes:List<&2,U32>,valid:Bool) -> Result<&2,&2,Error,R.Catalog>:
  match valid:
    case False{}: Fail{IntegrityMismatch{}}
    case True{}: text(identity,count,U.decode(limit,bytes))
def hashed(identity:String,count:U32,limit:Nat,bytes:List<&2,U32>,result:Result<&2,&2,String,H.Digest>) -> Result<&2,&2,Error,R.Catalog>:
  match result:
    case Fail{message}: Fail{Text{message}}
    case Done{digest}: integrity(identity,count,limit,bytes,String.eq(H.Digest.hex(digest),pinned_sha256()))
# This binds authenticated pinned data to the caller's actual registry identity
# and state count. The byte budget is caller policy, not a product state bound.
def parse(identity:String,count:U32,+limit:Nat,+bytes:List<&2,U32>) -> Result<&2,&2,Error,R.Catalog>:
  hashed(identity,count,limit,bytes,H.digest(limit,bytes))

def read_tail(+limit:Nat,bytes:List<&2,U32>,result:File & Result<&1,&1,U32 & String,List<&2,U32>>) -> IO(Result<&2,&2,Error,List<&2,U32>>):
  (file,status) = result
  match status:
    case Fail{Tuple{code,message}}:
      do IO<Result<&2,&2,Error,List<&2,U32>>>:
        File.close(file)
        return Fail{Read{code,message}}
    case Done{Nil{}}:
      do IO<Result<&2,&2,Error,List<&2,U32>>>:
        File.close(file)
        return Done{bytes}
    case Done{_}:
      do IO<Result<&2,&2,Error,List<&2,U32>>>:
        File.close(file)
        return Fail{ByteLimit{limit}}
def read_bytes(limit:Nat,result:File & Result<&1,&1,U32 & String,List<&2,U32>>) -> IO(Result<&2,&2,Error,List<&2,U32>>):
  (file,status) = result
  match status:
    case Fail{Tuple{code,message}}:
      do IO<Result<&2,&2,Error,List<&2,U32>>>:
        File.close(file)
        return Fail{Read{code,message}}
    case Done{bytes}:
      do IO<Result<&2,&2,Error,List<&2,U32>>>:
        tail : File & Result<&1,&1,U32 & String,List<&2,U32>> <- File.read_bytes(file,1)
        read_tail(limit,bytes,tail)
def read_open(+limit:Nat,result:Result<&1,&1,U32 & String,File>) -> IO(Result<&2,&2,Error,List<&2,U32>>):
  match result:
    case Fail{Tuple{code,message}}: IO.pure(Result<&2,&2,Error,List<&2,U32>>,Fail{Read{code,message}})
    case Done{file}:
      do IO<Result<&2,&2,Error,List<&2,U32>>>:
        bytes : File & Result<&1,&1,U32 & String,List<&2,U32>> <- File.read_bytes(file,U32.from_nat(limit))
        read_bytes(limit,bytes)
def read_file_valid(+limit:Nat,path:String,valid:Bool) -> IO(Result<&2,&2,Error,List<&2,U32>>):
  match valid:
    case False{}: IO.pure(Result<&2,&2,Error,List<&2,U32>>,Fail{ReadLimitOutsideU32{limit}})
    case True{}:
      do IO<Result<&2,&2,Error,List<&2,U32>>>:
        opened : Result<&1,&1,U32 & String,File> <- File.open(path,"r")
        read_open(limit,opened)
def read_file(+limit:Nat,path:String) -> IO(Result<&2,&2,Error,List<&2,U32>>):
  read_file_valid(limit,path,Nat.is_le(limit,4294967295n))
def loaded(identity:String,count:U32,limit:Nat,result:Result<&2,&2,Error,List<&2,U32>>) -> Result<&2,&2,Error,R.Catalog>:
  match result:
    case Fail{error}: Fail{error}
    case Done{bytes}: parse(identity,count,limit,bytes)
def load(identity:String,count:U32,+max_bytes:Nat,path:String) -> IO(Result<&2,&2,Error,R.Catalog>):
  do IO<Result<&2,&2,Error,R.Catalog>>:
    bytes : Result<&2,&2,Error,List<&2,U32>> <- read_file(max_bytes,path)
    return loaded(identity,count,max_bytes,bytes)
