import Base
import ../src/u32_decimal.bend as D

def observed(value:Maybe<&2,U32>) -> IO(Unit):
  match value:
    case None{}: IO.print("invalid")
    case Some{word}: IO.print(D.show(word))

def words(values:List<&2,String>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit,Unit{})
    case "" <> Nil{}: IO.pure(Unit,Unit{})
    case value <> rest:
      do IO<Unit>:
        observed(U32.read(value))
        words(rest)

def read_done(result:File & Result<&1,&1,U32 & String,String>) -> IO(Unit):
  (file,status) = result
  do IO<Unit>:
    File.close(file)
    input : String <- IO.try(String,IO.pure(Result<&1,&1,U32 & String,String>,status))
    words(String.split(input,'\n'))

def arguments(values:List<String>) -> IO(Unit):
  match values:
    case program <> path <> Nil{}:
      do IO<Unit>:
        file : File <- IO.try(File,File.open(path,"r"))
        result : File & Result<&1,&1,U32 & String,String> <- File.read(file,1048576)
        read_done(result)
    case _: IO.die(Unit,2,"expected unsigned word fixture path")

def main() -> IO(Unit): IO.bind(List<String>,Unit,IO.args(),arguments)
