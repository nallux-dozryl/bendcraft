import Base
import ../src/player_block_interaction.bend as BI
import ../src/core.bend as C
import ../src/movement.bend as M
import ../src/f64.bend as F
import ../src/locomotion.bend as T
import ../src/player_look.bend as Look

# This observer receives only test inputs. Expected answers stay in the host's
# independently observed Java reference, never in the product or this entry.
def face_text(face:BI.Face) -> String:
  match face:
    case BI.Down{}: "DOWN"
    case BI.Up{}: "UP"
    case BI.North{}: "NORTH"
    case BI.South{}: "SOUTH"
    case BI.West{}: "WEST"
    case BI.East{}: "EAST"

def f64_words(value:F.F64) -> String:
  F.F64{hi,lo} = value
  U32.show(hi) ++ "\t" ++ U32.show(lo)

def vector_words(value:M.Vec3) -> String:
  M.Vec3{x,y,z} = value
  f64_words(x) ++ "\t" ++ f64_words(y) ++ "\t" ++ f64_words(z)

def position_words(value:C.Position) -> String:
  C.Position{dimension,x,y,z} = value
  U32.show(x) ++ "\t" ++ U32.show(y) ++ "\t" ++ U32.show(z)

def hit_words(value:Maybe<&2,BI.Hit>) -> String:
  match value:
    case None{}: "clip\t0"
    case Some{BI.Hit{position,state,face,location,inside}}:
      "clip\t1\t" ++ face_text(face) ++ "\t" ++ U32.show(Bool.to_u32(inside)) ++
        "\t" ++ position_words(position) ++ "\t" ++ vector_words(location)

def nearest_words(+face:BI.Face) -> String:
  "nearest\t" ++ face_text(face) ++ "\t" ++ face_text(BI.opposite(face))

# AABB.clip has no shape-length gate or inside sampling. Its one full-cube box
# is translated by BlockPos before the production plane clipper is called.
def aabb_clip(+position:C.Position,+from:M.Vec3,to:M.Vec3) -> Maybe<&2,BI.Hit>:
  +delta = BI.subtract(to,from)
  BI.clip_external(position,0,from,delta,BI.clip_planes(from,delta,BI.cube(position)))

def written(tables:T.Tables,text:String) -> IO(T.Tables):
  do IO<T.Tables>:
    IO.print(text)
    return tables

def view_written(id:String,result:T.Tables & M.Vec3) -> IO(T.Tables):
  (tables,value) = result
  written(tables,id ++ "\tview\t" ++ vector_words(value))

def dispatch(id:String,operation:String,fields:List<&2,U32>,tables:T.Tables) -> IO(T.Tables):
  match operation fields:
    case "nearest" xh <> xl <> yh <> yl <> zh <> zl <> Nil{}:
      written(tables,id ++ "\t" ++ nearest_words(BI.nearest_x(F.F64{xh,xl},F.F64{yh,yl},F.F64{zh,zl})))
    case "view" yaw <> pitch <> Nil{}:
      view_written(id,BI.view_vector(tables,Look.float_bits(yaw),Look.float_bits(pitch)))
    case "shape_clip" x <> y <> z <> xh <> xl <> yh <> yl <> zh <> zl <> ah <> al <> bh <> bl <> ch <> cl <> Nil{}:
      written(tables,id ++ "\t" ++ hit_words(BI.clip_cube(C.Position{"minecraft:overworld",x,y,z},0,
        M.Vec3{F.F64{xh,xl},F.F64{yh,yl},F.F64{zh,zl}},M.Vec3{F.F64{ah,al},F.F64{bh,bl},F.F64{ch,cl}})))
    case "aabb_clip" x <> y <> z <> xh <> xl <> yh <> yl <> zh <> zl <> ah <> al <> bh <> bl <> ch <> cl <> Nil{}:
      written(tables,id ++ "\t" ++ hit_words(aabb_clip(C.Position{"minecraft:overworld",x,y,z},
        M.Vec3{F.F64{xh,xl},F.F64{yh,yl},F.F64{zh,zl}},M.Vec3{F.F64{ah,al},F.F64{bh,bl},F.F64{ch,cl}})))
    case "reach" Nil{}:
      written(tables,id ++ "\treach\t" ++ f64_words(BI.creative_reach()))
    case _ _: IO.die(T.Tables,2,"invalid player block reference operation or arity")

def number_gate(value:Maybe<&2,U32>,remaining:Maybe<&2,List<&2,U32>>) -> Maybe<&2,List<&2,U32>>:
  match value remaining:
    case Some{value} Some{remaining}: Some{value <> remaining}
    case _ _: None{}

def numbers(fields:List<&2,String>) -> Maybe<&2,List<&2,U32>>:
  match fields:
    case Nil{}: Some{Nil{}}
    case field <> rest: number_gate(U32.read(field),numbers(rest))

def numeric(id:String,operation:String,fields:Maybe<&2,List<&2,U32>>,tables:T.Tables) -> IO(T.Tables):
  match fields:
    case None{}: IO.die(T.Tables,2,"invalid player block reference U32 word")
    case Some{fields}: dispatch(id,operation,fields,tables)

def header(fields:List<&2,String>,tables:T.Tables) -> IO(T.Tables):
  match fields:
    case id <> operation <> rest: numeric(id,operation,numbers(rest),tables)
    case _: IO.die(T.Tables,2,"invalid player block reference TSV header")

def requests(lines:List<&2,String>,tables:T.Tables) -> IO(Unit):
  match lines:
    case Nil{}: IO.pure(Unit,Unit{})
    case SNil{} <> Nil{}: IO.pure(Unit,Unit{})
    case line <> rest:
      do IO<Unit>:
        next:T.Tables <- header(String.split(line,'\t'),tables)
        requests(rest,next)

# Pipes can return short reads. Read bounded chunks until actual EOF instead
# of assuming one File.read returned the complete TSV corpus.
def input_chunk(text:String,result:File & Result<&1,&1,U32 & String,String>,next:File -> String -> IO(String)) -> IO(String):
  (file,status) = result
  match status:
    case Fail{(code,message)}:
      do IO<String>:
        File.close(file)
        IO.die(String,2,"player block reference stdin read failed: " ++ message)
    case Done{SNil{}}:
      do IO<String>:
        File.close(file)
        return text
    case Done{chunk}: next(file)(text ++ chunk)

def input_text(fuel:Nat,input:File,text:String) -> IO(String):
  match fuel:
    case 0n:
      do IO<String>:
        File.close(input)
        IO.die(String,2,"player block reference stdin exceeded chunk limit")
    case 1n+rest:
      do IO<String>:
        result:File & Result<&1,&1,U32 & String,String> <- File.read(input,4096)
        input_chunk(text,result,file => remaining => input_text(rest,file,remaining))

def loaded(path:String,result:Result<&2,&1,T.Error,T.Tables>) -> IO(Unit):
  match result:
    case Fail{cause}: IO.die(Unit,2,"player block reference pinned sine table load failed")
    case Done{tables}:
      do IO<Unit>:
        input:File <- IO.try(File,File.open(path,"r"))
        text:String <- input_text(1025n,input,"")
        requests(String.split(text,'\n'),tables)

def arguments(args:List<String>) -> IO(Unit):
  match args:
    case exe <> table <> Nil{}:
      IO.bind(Result<&2,&1,T.Error,T.Tables>,Unit,T.Tables.load(table),result => loaded("/dev/stdin",result))
    case exe <> table <> path <> Nil{}:
      IO.bind(Result<&2,&1,T.Error,T.Tables>,Unit,T.Tables.load(table),result => loaded(path,result))
    case _: IO.die(Unit,2,"expected program, pinned sine table and optional TSV input path")

def main() -> IO(Unit):
  IO.bind(List<String>,Unit,IO.args(),arguments)
