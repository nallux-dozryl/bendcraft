import Base
import ./player_item_definitions.bend as D
import ./player_item_table.bend as Table

# The renderer loads the same observed definition table as the authority. It
# never replaces a missing/invalid full catalog with a fabricated item list.
def decoded(status:Result<&1,&1,U32 & String,List<&2,U32>>) -> Result<&2,&2,String,D.Catalog>:
  match status:
    case Fail{Tuple{code,message}}: Fail{"item catalog read: " ++ message}
    case Done{bytes}:
      do Result<&2,&2,String,D.Catalog>:
        text : String <- Table.text(bytes)
        D.parse(text)

def read(result:File & Result<&1,&1,U32 & String,List<&2,U32>>) -> IO(Result<&2,&2,String,D.Catalog>):
  (file,status) = result
  do IO<Result<&2,&2,String,D.Catalog>>:
    File.close(file)
    return decoded(status)

def opened(result:Result<&1,&1,U32 & String,File>) -> IO(Result<&2,&2,String,D.Catalog>):
  match result:
    case Fail{Tuple{code,message}}: IO.pure(Result<&2,&2,String,D.Catalog>,Fail{"item catalog open: " ++ message})
    case Done{file}:
      do IO<Result<&2,&2,String,D.Catalog>>:
        result : File & Result<&1,&1,U32 & String,List<&2,U32>> <- File.read_bytes(file,1048577)
        read(result)

def load(path:String) -> IO(Result<&2,&2,String,D.Catalog>):
  do IO<Result<&2,&2,String,D.Catalog>>:
    result : Result<&1,&1,U32 & String,File> <- File.open(path,"r")
    opened(result)
