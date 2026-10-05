import Base
import ../src/item_entity_tick_profiles.bend as P
import ../src/u32_decimal.bend as D

def rejected(result:Result<&2,&2,String,List<&2,P.Profile>>) -> Bool:
  match result:
    case Fail{message}: True{}
    case _: False{}
def report(+text:String,result:Result<&2,&2,String,List<&2,P.Profile>>) -> IO(Unit):
  match result:
    case Fail{message}: IO.die(Unit,2,message)
    case Done{+profiles}:
      IO.print(D.show(U32.from_nat(List.length(&2,P.Profile,profiles))) ++ ":" ++ U32.show(Bool.to_u32(rejected(P.load(text ++ "\n")))))
def read_done(value:File & Result<&1,&1,U32 & String,String>) -> IO(Unit):
  (file,status)=value
  do IO<Unit>:
    File.close(file)
    +text : String <- IO.try(String,IO.pure(Result<&1,&1,U32 & String,String>,status))
    report(text,P.load(text))
def arguments(args:List<String>) -> IO(Unit):
  match args:
    case +program <> +path <> Nil{}:
      do IO<Unit>:
        file : File <- IO.try(File,File.open(path,"r"))
        result : File & Result<&1,&1,U32 & String,String> <- File.read(file,262144)
        read_done(result)
    case _: IO.die(Unit,2,"expected exact physical profile path")
def main() -> IO(Unit): IO.bind(List<String>,Unit,IO.args(),arguments)
