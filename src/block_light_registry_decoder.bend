import Base
import ./block_light_registry.bend as R
import ./block_light.bend as B

type Error is Data:
  Schema{line:Nat,message:String}
  IdentityMismatch{identity:String}
  StateCountMismatch{count:U32}
type Header is Data:
  Header{identity:String,states:U32,shapes:U32,ranges:U32,words:U32}
type Range is Data:
  Range{first:U32,count:U32,entry:R.Entry}

def require(line:Nat,message:String,valid:Bool) -> Result<&2,&2,Error,Unit>:
  match valid:
    case False{}: Fail{Schema{line,message}}
    case True{}: Done{Unit{}}
def number_checked(line:Nat,text:String,value:U32,canonical:Bool) -> Result<&2,&2,Error,U32>:
  match canonical:
    case False{}: Fail{Schema{line,"noncanonical U32"}}
    case True{}: Done{value}
def number_found(line:Nat,+text:String,found:Maybe<&2,U32>) -> Result<&2,&2,Error,U32>:
  match found:
    case None{}: Fail{Schema{line,"invalid U32"}}
    case Some{+value}: number_checked(line,text,value,String.eq(text,U32.show(value)))
def number(line:Nat,+text:String) -> Result<&2,&2,Error,U32>:
  number_found(line,text,U32.read(text))
def words_extra(whole:U32,extra:Bool) -> U32:
  match extra:
    case False{}: whole
    case True{}: U32.inc(whole)
def words_for(+shapes:U32) -> U32:
  words_extra(U32.div(shapes,32),U32.is_ne(U32.mod(shapes,32),0))
def header_count(identity:String,states:U32,shapes:U32,ranges:U32,words:U32,valid:Bool) ->
    Result<&2,&2,Error,Header>:
  match valid:
    case False{}: Fail{StateCountMismatch{states}}
    case True{}: Done{Header{identity,states,shapes,ranges,words}}
def header_identity(+identity:String,expected:String,+states:U32,expected_states:U32,
    shapes:U32,ranges:U32,words:U32,valid:Bool) -> Result<&2,&2,Error,Header>:
  match valid:
    case False{}: Fail{IdentityMismatch{identity}}
    case True{}: header_count(identity,states,shapes,ranges,words,U32.is_eq(states,expected_states))
def header_fields(+expected:String,expected_states:U32,fields:List<&2,String>) -> Result<&2,&2,Error,Header>:
  match fields:
    case +magic <> +schema <> +version <> +identity <> states <> shapes <> ranges <> words <> Nil{}:
      do Result<&2,&2,Error,Header>:
        require(1n,"unsupported light catalog header",String.eq(magic,"BendBlockLightRegistry") &&
          String.eq(schema,"1") && String.eq(version,"26.3"))
        +count : U32 <- number(1n,states)
        +faces : U32 <- number(1n,shapes)
        +rows : U32 <- number(1n,ranges)
        +width : U32 <- number(1n,words)
        require(1n,"invalid light catalog dimensions",U32.is_gt(faces,0) &&
          U32.is_le(rows,count) && U32.is_eq(width,words_for(faces)))
        header_identity(identity,expected,count,expected_states,faces,rows,width,String.eq(identity,expected))
    case _: Fail{Schema{1n,"expected eight header fields"}}
def faces_valid(faces:R.Faces,+limit:U32) -> Bool:
  R.Faces{down,up,north,south,west,east} = faces
  U32.is_lt(down,limit) && U32.is_lt(up,limit) && U32.is_lt(north,limit) &&
    U32.is_lt(south,limit) && U32.is_lt(west,limit) && U32.is_lt(east,limit)
def range_fields(+line:Nat,+shapes:U32,fields:List<&2,String>) -> Result<&2,&2,Error,Range>:
  match fields:
    case tag <> first <> count <> emission <> dampening <> down <> up <> north <> south <> west <> east <> Nil{}:
      do Result<&2,&2,Error,Range>:
        require(line,"expected state range row",String.eq(tag,"S"))
        start : U32 <- number(line,first)
        +size : U32 <- number(line,count)
        +e : U32 <- number(line,emission)
        +d : U32 <- number(line,dampening)
        dn : U32 <- number(line,down)
        u : U32 <- number(line,up)
        n : U32 <- number(line,north)
        s : U32 <- number(line,south)
        w : U32 <- number(line,west)
        x : U32 <- number(line,east)
        +faces : R.Faces = R.Faces{dn,u,n,s,w,x}
        require(line,"invalid state range properties or face",U32.is_gt(size,0) &&
          B.descriptor_valid(B.Descriptor{0,e,d}) && faces_valid(faces,shapes))
        return Range{start,size,R.Entry{e,d,faces}}
    case _: Fail{Schema{line,"expected eleven state range fields"}}
def fill(fuel:Nat,+state:U32,+entry:R.Entry,entries:Map<&2,Maybe<&2,R.Entry>>) -> Map<&2,Maybe<&2,R.Entry>>:
  match fuel:
    case 0n: entries
    case 1n+p: fill(p,U32.inc(state),entry,Map.set(&2,Maybe<&2,R.Entry>,entries,U32.show(state),Some{entry}))
def range_built(+line:Nat,+states:U32,+next:U32,entries:Map<&2,Maybe<&2,R.Entry>>,
    range:Range,valid:Bool) -> Result<&2,&1,Error,U32 & Map<&2,Maybe<&2,R.Entry>>>:
  match range valid:
    case _ False{}: Fail{Schema{line,"noncontiguous or overflowing state range"}}
    case Range{first,+count,entry} True{}:
      Done{(U32.add(next,count),fill(U32.to_nat(count),next,entry,entries))}
def build_range(+line:Nat,+states:U32,+next:U32,entries:Map<&2,Maybe<&2,R.Entry>>,
    parsed:Result<&2,&2,Error,Range>) -> Result<&2,&1,Error,U32 & Map<&2,Maybe<&2,R.Entry>>>:
  match parsed:
    case Fail{error}: Fail{error}
    case Done{+range}:
      Range{first,count,entry} = range
      range_built(line,states,next,entries,range,U32.is_eq(first,next) &&
        U32.is_le(first,states) && U32.is_le(count,U32.sub(states,first)))
def ranges_complete(line:Nat,next:U32,states:U32,entries:Map<&2,Maybe<&2,R.Entry>>,
    tail:List<&2,String>,valid:Bool) -> Result<&2,&1,Error,Map<&2,Maybe<&2,R.Entry>> & List<&2,String>>:
  match valid:
    case False{}: Fail{Schema{line,"incomplete state coverage"}}
    case True{}: Done{(entries,tail)}
def range_rows(fuel:Nat,lines:List<&2,String>,+line:Nat,+next:U32,+states:U32,+shapes:U32,
    entries:Map<&2,Maybe<&2,R.Entry>>) -> Result<&2,&1,Error,Map<&2,Maybe<&2,R.Entry>> & List<&2,String>>:
  match fuel lines:
    case 0n tail: ranges_complete(line,next,states,entries,tail,U32.is_eq(next,states))
    case 1n+p text <> rest:
      do Result<&2,&1,Error,Map<&2,Maybe<&2,R.Entry>> & List<&2,String>>:
        built : U32 & Map<&2,Maybe<&2,R.Entry>> <- build_range(line,states,next,entries,
          range_fields(line,shapes,String.split(text,'\t')))
        B.paired(U32,Map<&2,Maybe<&2,R.Entry>>,
          Result<&2,&1,Error,Map<&2,Maybe<&2,R.Entry>> & List<&2,String>>,built,
          next=> entries=> range_rows(p,rest,1n+line,next,states,shapes,entries))
    case _ _: Fail{Schema{line,"missing state ranges"}}
def words(fuel:Nat,fields:List<&2,String>,+line:Nat) -> Result<&2,&2,Error,List<&2,U32>>:
  match fuel fields:
    case 0n Nil{}: Done{[]}
    case 1n+p head <> tail:
      do Result<&2,&2,Error,List<&2,U32>>:
        value : U32 <- number(line,head)
        rest : List<&2,U32> <- words(p,tail,line)
        return value <> rest
    case _ _: Fail{Schema{line,"incorrect face row word count"}}
def last_word(words:List<&2,U32>) -> U32:
  match words:
    case Nil{}: 0
    case value <> Nil{}: value
    case value <> next <> tail: last_word(next <> tail)
def padding_checked(last:U32,remainder:U32,aligned:Bool) -> Bool:
  match aligned:
    case True{}: True{}
    case False{}: U32.is_eq(U32.shrn(last,U32.to_nat(remainder)),0)
def padding(+values:List<&2,U32>,+shapes:U32) -> Bool:
  padding_checked(last_word(values),U32.mod(shapes,32),U32.is_eq(U32.mod(shapes,32),0))
def row_fields(+line:Nat,+index:U32,+shapes:U32,width:U32,fields:List<&2,String>) ->
    Result<&2,&2,Error,List<&2,U32>>:
  match fields:
    case tag <> id <> tail:
      do Result<&2,&2,Error,List<&2,U32>>:
        require(line,"expected face matrix row",String.eq(tag,"F"))
        parsed : U32 <- number(line,id)
        require(line,"noncontiguous face matrix row",U32.is_eq(index,parsed))
        +values : List<&2,U32> <- words(U32.to_nat(width),tail,line)
        require(line,"face matrix padding bits must be zero",padding(values,shapes))
        return values
    case _: Fail{Schema{line,"missing face matrix row"}}
def end_checked(header:Header,entries:Map<&2,Maybe<&2,R.Entry>>,
    rows:Map<&2,Maybe<&2,List<&2,U32>>>,line:Nat,tail:List<&2,String>) -> Result<&2,&2,Error,R.Catalog>:
  Header{identity,states,shapes,ranges,width} = header
  match tail:
    case Nil{}: Done{R.Catalog{identity,states,shapes,entries,rows}}
    case SNil{} <> Nil{}: Done{R.Catalog{identity,states,shapes,entries,rows}}
    case _: Fail{Schema{line,"unexpected trailing catalog rows"}}
def shape_rows(fuel:Nat,lines:List<&2,String>,+line:Nat,+index:U32,+header:Header,
    entries:Map<&2,Maybe<&2,R.Entry>>,rows:Map<&2,Maybe<&2,List<&2,U32>>>) -> Result<&2,&2,Error,R.Catalog>:
  match fuel lines:
    case 0n tail: end_checked(header,entries,rows,line,tail)
    case 1n+p text <> tail:
      Header{identity,states,+shapes,ranges,+width} = header
      do Result<&2,&2,Error,R.Catalog>:
        values : List<&2,U32> <- row_fields(line,index,shapes,width,String.split(text,'\t'))
        shape_rows(p,tail,1n+line,U32.inc(index),Header{identity,states,shapes,ranges,width},entries,
          Map.set(&2,Maybe<&2,List<&2,U32>>,rows,U32.show(index),Some{values}))
    case _ _: Fail{Schema{line,"missing face matrix rows"}}
def decoded_ranges(header:Header,result:Result<&2,&1,Error,Map<&2,Maybe<&2,R.Entry>> & List<&2,String>>) ->
    Result<&2,&2,Error,R.Catalog>:
  Header{identity,states,+shapes,+ranges,width} = header
  match result:
    case Fail{error}: Fail{error}
    case Done{Tuple{entries,tail}}:
      shape_rows(U32.to_nat(shapes),tail,2n+U32.to_nat(ranges),0,
        Header{identity,states,shapes,ranges,width},entries,MTip{})
def decoded_header(lines:List<&2,String>,parsed:Result<&2,&2,Error,Header>) -> Result<&2,&2,Error,R.Catalog>:
  match parsed:
    case Fail{error}: Fail{error}
    case Done{+header}:
      Header{identity,+states,+shapes,ranges,width} = header
      decoded_ranges(header,range_rows(U32.to_nat(ranges),lines,2n,0,states,shapes,MTip{}))
def decode_lines(expected:String,count:U32,lines:List<&2,String>) -> Result<&2,&2,Error,R.Catalog>:
  match lines:
    case header <> tail: decoded_header(tail,header_fields(expected,count,String.split(header,'\t')))
    case _: Fail{Schema{1n,"missing catalog header"}}
def decode(identity:String,count:U32,text:String) -> Result<&2,&2,Error,R.Catalog>:
  decode_lines(identity,count,String.split(text,'\n'))
