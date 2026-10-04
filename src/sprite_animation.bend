import Base
import ./json.bend as J
import ./resource_json.bend as Q
import ./texture_metadata.bend as T
import ./texture_mipmap.bend as M

# CPU timeline/owned frame views. GPU upload and shader interpolation are open.
type FrameSpec is Data:
  FrameSpec{index:U32,time:Maybe<&2,U32>}
type Metadata is Data:
  Metadata{frames:Maybe<&2,List<&2,FrameSpec>>,width:Maybe<&2,U32>,height:Maybe<&2,U32>,default_time:U32,interpolate:Bool}
type FrameInfo is Data:
  FrameInfo{index:U32,time:U32}
type Limits is Data:
  Limits{max_dimension:U32,max_levels:U32,max_frames:U32,max_entries:U32,max_capacity:U32,max_work_pixels:U32}
type Error is Data:
  Error{code:String,field:String,index:U32}
type Plan is Data:
  Plan{width:U32,height:U32,row_size:U32,frame_count:U32,frames:List<&2,FrameInfo>,unique_frames:List<&2,U32>,interpolate:Bool,animated:Bool,dimensions:List<&2,M.Dimension>,capacity:U32,work:U32}
type Timeline is Data:
  NoTimeline{}
  Running{entry:U32,sub_frame:U32,dirty:Bool}
type Rect is Data:
  Rect{mip:U32,x:U32,y:U32,width:U32,height:U32}
type Selection is Data:
  NoAnimation{width:U32,height:U32}
  Animated{entry:U32,current:U32,next:U32,sub_frame:U32,duration:U32,dirty:Bool,needs_draw:Bool,current_rects:List<&2,Rect>,next_rects:List<&2,Rect>}
type Contents is Type:
  Contents{chain:M.Chain,metadata:Maybe<&2,Metadata>,limits:Limits,timeline:Timeline,tail:Maybe<&1,Contents>}
type Rejected is Type:
  Rejected{chain:M.Chain,error:Error}
type Usage is Data:
  Usage{capacity:U32,work:U32}
def defaults() -> Limits:
  Limits{8192,16,4096,65536,4194304,1048576}
def fail(-A:Data,code:String,field:String) -> Result<&2,&2,Error,A>:
  Fail{Error{code,field,0}}
def guard(value:Bool,code:String,field:String,index:U32) -> Result<&2,&2,Error,Unit>:
  match value:
    case True{}: Done{Unit{}}
    case False{}: Fail{Error{code,field,index}}
def positive(+value:U32) -> Bool:
  U32.is_gt(value,0) && U32.is_lt(value,2147483648)
def positive_number(+value:U32,field:String) -> Result<&2,&2,Error,U32>:
  J.choose(Result<&2,&2,Error,U32>,Done{value},fail(U32,"ExpectedPositive",field),positive(value))
def nonnegative_number(+value:U32,field:String) -> Result<&2,&2,Error,U32>:
  J.choose(Result<&2,&2,Error,U32>,Done{value},fail(U32,"ExpectedNonNegative",field),U32.is_lt(value,2147483648))

# Decimal truncate/mod32 follows actual Gson getAsInt observations. This narrow
# helper preserves the separately declared exponent budget without a Model import.
type IntToken is Data:
  IntToken{digits: List<&2, U32>, fraction: U32, exponent: U32, exponent_negative: Bool, negative: Bool}

def int_scan(text: String, +stage: U32, reversed: List<&2, U32>, +fraction: U32, +exponent: U32,
  +exponent_negative: Bool, +negative: Bool) -> Result<&2, &2, Error, IntToken>:
  match text:
    case SNil{}: Done{IntToken{List.reverse(&2, U32, reversed), fraction, exponent, exponent_negative, negative}}
    case SCon{Chr{+c}, rest}:
      match c:
        case 45:
          int_scan(rest, stage, reversed, fraction, exponent,
            J.choose(Bool, True{}, exponent_negative, U32.is_ge(stage, 2)),
            J.choose(Bool, negative, True{}, U32.is_ge(stage, 2)))
        case 43: int_scan(rest, stage, reversed, fraction, exponent, exponent_negative, negative)
        case 46: int_scan(rest, 1, reversed, fraction, exponent, exponent_negative, negative)
        case 101: int_scan(rest, 2, reversed, fraction, exponent, exponent_negative, negative)
        case 69: int_scan(rest, 2, reversed, fraction, exponent, exponent_negative, negative)
        case _:
          match stage:
            case 0: int_scan(rest, stage, U32.sub(c, 48) <> reversed, fraction, exponent, exponent_negative, negative)
            case 1: int_scan(rest, stage, U32.sub(c, 48) <> reversed, U32.add(fraction, 1), exponent, exponent_negative, negative)
            case _:
              do Result<&2, &2, Error, IntToken>:
                next : U32 <- J.choose(Result<&2, &2, Error, U32>,
                  Done{U32.add(U32.mul(exponent, 10), U32.sub(c, 48))},
                  fail(U32, "UnsupportedIntegerExponent", "integer"),
                  U32.is_le(U32.add(U32.mul(exponent, 10), U32.sub(c, 48)), 100000))
                int_scan(rest, stage, reversed, fraction, next, exponent_negative, negative)

def digit_word(fuel: Nat, digits: List<&2, U32>, acc: U32) -> U32:
  match fuel digits:
    case 1n+p h <> t: digit_word(p, t, U32.add(U32.mul(acc, 10), h))
    case _ _: acc

def decimal_shift(fuel: Nat, value: U32) -> U32:
  match fuel:
    case 0n: value
    case 1n+p: decimal_shift(p, U32.mul(value, 10))

def integer_shift(digits: List<&2, U32>, length: Nat, shift: U32, small: Bool) -> U32:
  match small:
    case False{}: 0
    case True{}: decimal_shift(U32.to_nat(shift), digit_word(length, digits, 0))

def integer_magnitude(digits: List<&2, U32>, length: Nat, +fraction: U32, +exponent: U32, exp_negative: Bool, shift: Bool) -> U32:
  match shift:
    case True{}: integer_shift(digits, length, U32.sub(exponent, fraction), U32.is_lt(U32.sub(exponent, fraction), 32))
    case False{}:
      drop = J.choose(U32, U32.add(fraction, exponent), U32.sub(fraction, exponent), exp_negative)
      digit_word(Nat.sub(length, U32.to_nat(drop)), digits, 0)

def integer_token(token: IntToken) -> U32:
  match token:
    case IntToken{+digits, +fraction, +exponent, +exp_negative, +negative}:
      length = List.length(&2, U32, digits)
      +magnitude = integer_magnitude(digits, length, fraction, exponent, exp_negative,
        Bool.not(exp_negative) && U32.is_ge(exponent, fraction))
      J.choose(U32, U32.sub(0, magnitude), magnitude, negative)


def integer_parsed(value:Result<&2,&2,String,J.Value>,field:String) -> Result<&2,&2,Error,U32>:
  match value:
    case Done{J.JNumber{raw}}:
      do Result<&2,&2,Error,U32>:
        token : IntToken <- int_scan(raw,0,[],0,0,False{},False{})
        Done{integer_token(token)}
    case _: fail(U32,"ExpectedInteger",field)
def integer(value:J.Value,field:String) -> Result<&2,&2,Error,U32>:
  match value:
    case J.JNumber{raw}: integer_parsed(J.parse(raw),field)
    case _: fail(U32,"ExpectedInteger",field)
def required_positive(value:Maybe<&2,J.Value>,+field:String) -> Result<&2,&2,Error,U32>:
  match value:
    case None{}: fail(U32,"MissingField",field)
    case Some{v}:
      do Result<&2,&2,Error,U32>:
        n : U32 <- integer(v,field)
        positive_number(n,field)
def optional_positive(value:Maybe<&2,J.Value>,+field:String) -> Result<&2,&2,Error,Maybe<&2,U32>>:
  match value:
    case None{}: Done{None{}}
    case Some{J.JNull{}}: Done{None{}}
    case Some{v}:
      do Result<&2,&2,Error,Maybe<&2,U32>>:
        n : U32 <- integer(v,field)
        p : U32 <- positive_number(n,field)
        Done{Some{p}}
def required_index(value:Maybe<&2,J.Value>) -> Result<&2,&2,Error,U32>:
  match value:
    case None{}: fail(U32,"MissingField","index")
    case Some{v}:
      do Result<&2,&2,Error,U32>:
        n : U32 <- integer(v,"index")
        nonnegative_number(n,"index")
def frame_spec(+value:J.Value) -> Result<&2,&2,Error,FrameSpec>:
  match value:
    case J.JNumber{raw}:
      do Result<&2,&2,Error,FrameSpec>:
        n : U32 <- integer(value,"frames")
        i : U32 <- nonnegative_number(n,"frames")
        Done{FrameSpec{i,None{}}}
    case J.JObject{members}:
      do Result<&2,&2,Error,FrameSpec>:
        i : U32 <- required_index(J.member(value,"index"))
        t : Maybe<&2,U32> <- optional_positive(J.member(value,"time"),"time")
        Done{FrameSpec{i,t}}
    case _: fail(FrameSpec,"InvalidFrame","frames")
def frame_specs(fuel:Nat,values:List<&2,J.Value>) -> Result<&2,&2,Error,List<&2,FrameSpec>>:
  match fuel values:
    case _ Nil{}: Done{[]}
    case 0n h<>rest: fail(List<&2,FrameSpec>,"EntryLimit","frames")
    case 1n+p h<>rest:
      do Result<&2,&2,Error,List<&2,FrameSpec>>:
        first : FrameSpec <- frame_spec(h)
        tail : List<&2,FrameSpec> <- frame_specs(p,rest)
        Done{first<>tail}
def frames(value:Maybe<&2,J.Value>) -> Result<&2,&2,Error,Maybe<&2,List<&2,FrameSpec>>>:
  match value:
    case None{}: Done{None{}}
    case Some{J.JNull{}}: Done{None{}}
    case Some{J.JArray{values}}:
      do Result<&2,&2,Error,Maybe<&2,List<&2,FrameSpec>>>:
        fs : List<&2,FrameSpec> <- frame_specs(65536n,values)
        Done{Some{fs}}
    case _: fail(Maybe<&2,List<&2,FrameSpec>>,"InvalidFrames","frames")
def boolean_result(value:Result<&2,&2,T.Error,Bool>) -> Result<&2,&2,Error,Bool>:
  match value:
    case Done{v}: Done{v}
    case Fail{T.Error{code,field,message}}: fail(Bool,code,field)
def decode_section(+value:J.Value) -> Result<&2,&2,Error,Metadata>:
  match value:
    case J.JObject{members}:
      do Result<&2,&2,Error,Metadata>:
        fs : Maybe<&2,List<&2,FrameSpec>> <- frames(J.member(value,"frames"))
        w : Maybe<&2,U32> <- optional_positive(J.member(value,"width"),"width")
        h : Maybe<&2,U32> <- optional_positive(J.member(value,"height"),"height")
        t : Maybe<&2,U32> <- optional_positive(J.member(value,"frametime"),"frametime")
        interpolate : Bool <- boolean_result(T.boolean(J.member(value,"interpolate"),"interpolate"))
        Done{Metadata{fs,w,h,Maybe.default(&2,U32,t,1),interpolate}}
    case _: fail(Metadata,"InvalidSection","animation")
def document_section(value:Maybe<&2,J.Value>) -> Result<&2,&2,Error,Maybe<&2,Metadata>>:
  match value:
    case None{}: Done{None{}}
    case Some{v}:
      do Result<&2,&2,Error,Maybe<&2,Metadata>>:
        m : Metadata <- decode_section(v)
        Done{Some{m}}
def decode_document(+value:J.Value) -> Result<&2,&2,Error,Maybe<&2,Metadata>>:
  match value:
    case J.JObject{members}: document_section(J.member(value,"animation"))
    case _: fail(Maybe<&2,Metadata>,"InvalidDocument","")
def parsed_document(value:Result<&2,&2,String,J.Value>) -> Result<&2,&2,Error,Maybe<&2,Metadata>>:
  match value:
    case Done{v}: decode_document(v)
    case Fail{message}: fail(Maybe<&2,Metadata>,"InvalidJson","")
def parse_document(text:String) -> Result<&2,&2,Error,Maybe<&2,Metadata>>:
  parsed_document(Q.parse(text))
def parse_document_with(text:String,limits:J.Limits) -> Result<&2,&2,Error,Maybe<&2,Metadata>>:
  parsed_document(Q.parse_with(text,limits))

# Admission is loader-style: positive divisible frame grid and coherent supplied
# mips. Direct SpriteContents truncating/invalid constructor observations remain
# distinct. No mip owner or padding cell is removed by this interpretation.
type Size is Data:
  Size{width:U32,height:U32}
def metadata_size(+w:U32,+h:U32,metadata:Maybe<&2,Metadata>) -> Size:
  match metadata:
    case None{}: Size{w,h}
    case Some{Metadata{fs,None{},None{},time,interp}}:
      +side = J.choose(U32,w,h,U32.is_le(w,h))
      Size{side,side}
    case Some{Metadata{fs,Some{fw},None{},time,interp}}: Size{fw,h}
    case Some{Metadata{fs,None{},Some{fh},time,interp}}: Size{w,fh}
    case Some{Metadata{fs,Some{fw},Some{fh},time,interp}}: Size{fw,fh}
def validate_limits(+limits:Limits) -> Result<&2,&2,Error,Unit>:
  Limits{+dimension,+levels,+frames,+entries,+capacity,+work} = limits
  guard(U32.is_gt(dimension,0)&&U32.is_le(dimension,16384)&&U32.is_gt(levels,0)&&U32.is_le(levels,16)&&U32.is_gt(frames,0)&&U32.is_le(frames,65536)&&U32.is_le(entries,65536)&&U32.is_le(capacity,16777216)&&U32.is_le(work,16777216),"LimitsRange","limits",0)
def validate_entries(frames:Maybe<&2,List<&2,FrameSpec>>,entries:U32) -> Result<&2,&2,Error,Unit>:
  match frames:
    case None{}: Done{Unit{}}
    case Some{values}: guard(Nat.is_le(List.length(&2,FrameSpec,values),U32.to_nat(entries)),"EntryLimit","frames",0)
def validate_metadata(value:Maybe<&2,Metadata>,+limits:Limits) -> Result<&2,&2,Error,Unit>:
  match value limits:
    case None{} _: Done{Unit{}}
    case Some{Metadata{frames,w,h,t,i}} Limits{d,l,f,+entries,c,p}:
      do Result<&2,&2,Error,Unit>:
        guard(positive(t),"DefaultTimeRange","frametime",0)
        validate_entries(frames,entries)
def validate_dimensions(values:List<&2,M.Dimension>,+limits:Limits,+w:U32,+h:U32,+fw:U32,+fh:U32,+index:U32,+capacity:U32,+work:U32) -> Result<&2,&2,Error,Usage>:
  match values limits:
    case Nil{} _: Done{Usage{capacity,work}}
    case M.Dimension{+iw,+ih,+size} <> rest Limits{+maximum,levels,frames,entries,+budget,+work_limit}:
      do Result<&2,&2,Error,Usage>:
        guard(U32.is_gt(iw,0)&&U32.is_gt(ih,0)&&U32.is_le(iw,maximum)&&U32.is_le(ih,maximum),"DimensionRange","mip",index)
        guard(U32.is_gt(size,0),"BufferShape","mip",index)
        guard(U32.is_le(U32.mul(iw,ih),size),"BufferLength","mip",index)
        guard(U32.is_eq(iw,w)&&U32.is_eq(ih,h),"MipCoherence","mip",index)
        guard(U32.is_gt(fw,0)&&U32.is_gt(fh,0),"ZeroFrameMip","mip",index)
        guard(U32.is_le(size,U32.sub(budget,capacity)),"CapacityLimit","mip",index)
        guard(U32.is_le(U32.mul(iw,ih),U32.sub(work_limit,work)),"WorkLimit","mip",index)
        validate_dimensions(rest,limits,U32.shr(w),U32.shr(h),U32.shr(fw),U32.shr(fh),U32.add(index,1),U32.add(capacity,size),U32.add(work,U32.mul(iw,ih)))
def enumerate_frames(fuel:Nat,+index:U32,+time:U32) -> List<&2,FrameInfo>:
  match fuel:
    case 0n: []
    case 1n+p: FrameInfo{index,time} <> enumerate_frames(p,U32.add(index,1),time)
def filtered_frame(f:List<&2,FrameInfo> -> List<&2,FrameInfo>,+index:U32,+time:U32,count:U32) -> List<&2,FrameInfo>:
  f(J.choose(List<&2,FrameInfo>,[FrameInfo{index,time}],[],U32.is_lt(index,count)&&positive(time)))
def append_frames(values:List<&2,FrameInfo>,tail:List<&2,FrameInfo>) -> List<&2,FrameInfo>:
  match values:
    case Nil{}: tail
    case h <> rest: h <> append_frames(rest,tail)
def filter_frames(values:List<&2,FrameSpec>,+time:U32,+count:U32) -> List<&2,FrameInfo>:
  match values:
    case Nil{}: []
    case FrameSpec{index,override} <> rest:
      filtered_frame(first => append_frames(first,filter_frames(rest,time,count)),index,Maybe.default(&2,U32,override,time),count)
def selected_frames(metadata:Maybe<&2,Metadata>,count:U32) -> List<&2,FrameInfo>:
  match metadata:
    case None{}: []
    case Some{Metadata{None{},w,h,time,interp}}: enumerate_frames(U32.to_nat(count),0,time)
    case Some{Metadata{Some{frames},w,h,time,interp}}: filter_frames(frames,time,count)
def contains(values:List<&2,U32>,+index:U32) -> Bool:
  match values:
    case Nil{}: False{}
    case h <> rest: U32.is_eq(h,index)||contains(rest,index)
def unique_if(f:List<&2,U32> -> List<&2,U32>,seen:List<&2,U32>,+index:U32,duplicate:Bool) -> List<&2,U32>:
  match duplicate:
    case True{}: f(seen)
    case False{}: index <> f(index<>seen)
def unique(values:List<&2,FrameInfo>,+seen:List<&2,U32>) -> List<&2,U32>:
  match values:
    case Nil{}: []
    case FrameInfo{+index,time} <> rest:
      unique_if(next_seen => unique(rest,next_seen),seen,index,contains(seen,index))
def interpolation(value:Maybe<&2,Metadata>) -> Bool:
  match value:
    case None{}: False{}
    case Some{Metadata{fs,w,h,t,interp}}: interp
def make_plan(+dimensions:List<&2,M.Dimension>,+size:Size,+rows:U32,+count:U32,+metadata:Maybe<&2,Metadata>,usage:Usage) -> Plan:
  Size{w,h} = size
  Usage{capacity,work} = usage
  +frames = selected_frames(metadata,count)
  +animated = Nat.is_gt(List.length(&2,FrameInfo,frames),1n)
  Plan{w,h,rows,count,J.choose(List<&2,FrameInfo>,frames,[],animated),J.choose(List<&2,U32>,unique(frames,[]),[1],animated),interpolation(metadata),animated,dimensions,capacity,work}
def plan_grid(+dimensions:List<&2,M.Dimension>,+metadata:Maybe<&2,Metadata>,+limits:Limits,+w:U32,+h:U32,+size:Size) -> Result<&2,&2,Error,Plan>:
  Limits{maximum,levels,+frames,entries,capacity,work} = limits
  Size{+fw,+fh} = size
  +rows = U32.div(w,fw)
  +count = U32.mul(rows,U32.div(h,fh))
  do Result<&2,&2,Error,Plan>:
    guard(U32.is_le(count,frames),"FrameLimit","frame",count)
    usage : Usage <- validate_dimensions(dimensions,limits,w,h,fw,fh,0,0,0)
    Done{make_plan(dimensions,size,rows,count,metadata,usage)}
def plan_sized(+dimensions:List<&2,M.Dimension>,+metadata:Maybe<&2,Metadata>,+limits:Limits,+w:U32,+h:U32,+size:Size) -> Result<&2,&2,Error,Plan>:
  Limits{maximum,levels,+frames,entries,capacity,work} = limits
  Size{+fw,+fh} = size
  do Result<&2,&2,Error,Plan>:
    guard(positive(fw)&&positive(fh),"FrameDimension","frame",0)
    guard(U32.is_le(fw,w)&&U32.is_le(fh,h),"FrameDimension","frame",0)
    guard(U32.is_eq(U32.mod(w,fw),0)&&U32.is_eq(U32.mod(h,fh),0),"NonDivisible","frame",0)
    plan_grid(dimensions,metadata,limits,w,h,size)
def plan_first(+dimensions:List<&2,M.Dimension>,+metadata:Maybe<&2,Metadata>,+limits:Limits,first:M.Dimension) -> Result<&2,&2,Error,Plan>:
  Limits{+maximum,+levels,frames,entries,capacity,work} = limits
  M.Dimension{+w,+h,c} = first
  do Result<&2,&2,Error,Plan>:
    validate_limits(limits)
    guard(Nat.is_ge(List.length(&2,M.Dimension,dimensions),1n)&&Nat.is_le(List.length(&2,M.Dimension,dimensions),U32.to_nat(levels)),"LevelCount","mip",0)
    validate_metadata(metadata,limits)
    guard(U32.is_gt(w,0)&&U32.is_gt(h,0)&&U32.is_le(w,maximum)&&U32.is_le(h,maximum),"DimensionRange","mip",0)
    plan_sized(dimensions,metadata,limits,w,h,metadata_size(w,h,metadata))
def plan(+dimensions:List<&2,M.Dimension>,metadata:Maybe<&2,Metadata>,limits:Limits) -> Result<&2,&2,Error,Plan>:
  plan_first(dimensions,metadata,limits,M.first_dimension(dimensions))
def starting(value:Plan) -> Timeline:
  Plan{w,h,r,c,fs,us,i,animated,d,capacity,work} = value
  match animated:
    case False{}: NoTimeline{}
    case True{}: Running{0,0,True{}}
def admit_result(chain:M.Chain,+metadata:Maybe<&2,Metadata>,limits:Limits,result:Result<&2,&2,Error,Plan>) -> Result<&1,&1,Rejected,Contents>:
  match result:
    case Fail{error}: Fail{Rejected{chain,error}}
    case Done{p}: Done{Contents{chain,metadata,limits,starting(p),None{}}}
def admit(value:M.Chain,+metadata:Maybe<&2,Metadata>,+limits:Limits) -> Result<&1,&1,Rejected,Contents>:
  M.Chain{levels} = value
  M.paired(List<&1,M.Level>,List<&2,M.Dimension>,Result<&1,&1,Rejected,Contents>,M.inspect_levels(levels),levels => dimensions => admit_result(M.Chain{levels},metadata,limits,plan(dimensions,metadata,limits)))

def frame_at(values:List<&2,FrameInfo>,index:Nat) -> FrameInfo:
  match values index:
    case h <> rest 0n: h
    case h <> rest 1n+p: frame_at(rest,p)
    case _ _: FrameInfo{0,0}
def rects(dimensions:List<&2,M.Dimension>,+fw:U32,+fh:U32,+x:U32,+y:U32,+mip:U32) -> List<&2,Rect>:
  match dimensions:
    case Nil{}: []
    case h <> rest: Rect{mip,x,y,fw,fh} <> rects(rest,U32.shr(fw),U32.shr(fh),U32.shr(x),U32.shr(y),U32.add(mip,1))
def frame_rects(+p:Plan,+index:U32) -> List<&2,Rect>:
  Plan{+w,+h,+rows,c,fs,us,i,a,dimensions,capacity,work} = p
  rects(dimensions,w,h,U32.mul(U32.mod(index,rows),w),U32.mul(U32.div(index,rows),h),0)
def timeline_time(+sub:U32,value:FrameInfo) -> Result<&2,&2,Error,Unit>:
  FrameInfo{index,time} = value
  guard(U32.is_lt(sub,time),"TimelineSubFrame","timeline",sub)
def timeline_sub(frames:List<&2,FrameInfo>,entry:U32,sub:U32) -> Result<&2,&2,Error,Unit>:
  timeline_time(sub,frame_at(frames,U32.to_nat(entry)))
def timeline_valid(+p:Plan,+value:Timeline) -> Result<&2,&2,Error,Unit>:
  Plan{w,h,rows,count,+frames,us,i,animated,dimensions,capacity,work} = p
  match animated value:
    case False{} NoTimeline{}: Done{Unit{}}
    case True{} Running{+entry,+sub,dirty}:
      do Result<&2,&2,Error,Unit>:
        guard(Nat.is_lt(U32.to_nat(entry),List.length(&2,FrameInfo,frames)),"TimelineEntry","timeline",entry)
        timeline_sub(frames,entry,sub)
    case _ _: fail(Unit,"TimelineKind","timeline")
def selected(+p:Plan,+entry:U32,sub:U32,+dirty:Bool,interp:Bool,current:FrameInfo,next:FrameInfo) -> Selection:
  FrameInfo{+current_index,time} = current
  FrameInfo{+next_index,next_time} = next
  Animated{entry,current_index,next_index,sub,time,dirty,interp||dirty,frame_rects(p,current_index),frame_rects(p,next_index)}
def selection(+p:Plan,value:Timeline) -> Selection:
  Plan{w,h,rows,count,+frames,us,+interp,animated,ds,capacity,work} = p
  match value:
    case NoTimeline{}: NoAnimation{w,h}
    case Running{+entry,sub,dirty}:
      selected(p,entry,sub,dirty,interp,frame_at(frames,U32.to_nat(entry)),frame_at(frames,U32.to_nat(U32.mod(U32.add(entry,1),U32.from_nat(List.length(&2,FrameInfo,frames))))))
def advanced_next(entry:U32,current:U32,value:FrameInfo) -> Timeline:
  FrameInfo{next,next_time} = value
  Running{entry,0,Bool.not(U32.is_eq(current,next))}
def advanced_if(+frames:List<&2,FrameInfo>,+entry:U32,sub:U32,current:U32,elapsed:Bool) -> Timeline:
  match elapsed:
    case False{}: Running{entry,U32.add(sub,1),False{}}
    case True{}:
      +next_entry = U32.mod(U32.add(entry,1),U32.from_nat(List.length(&2,FrameInfo,frames)))
      advanced_next(next_entry,current,frame_at(frames,U32.to_nat(next_entry)))
def advanced_current(frames:List<&2,FrameInfo>,entry:U32,+sub:U32,value:FrameInfo) -> Timeline:
  FrameInfo{current,time} = value
  advanced_if(frames,entry,sub,current,U32.is_ge(U32.add(sub,1),time))
def advanced(+p:Plan,value:Timeline) -> Timeline:
  Plan{w,h,rows,count,+frames,us,i,a,d,c,work} = p
  match value:
    case NoTimeline{}: NoTimeline{}
    case Running{+entry,+sub,old_dirty}: advanced_current(frames,entry,sub,frame_at(frames,U32.to_nat(entry)))
type Observation is Data:
  Observation{plan:Plan,selection:Selection}
def observe_plan(+timeline:Timeline,+p:Plan) -> Result<&2,&2,Error,Observation>:
  do Result<&2,&2,Error,Observation>:
    timeline_valid(p,timeline)
    Done{Observation{p,selection(p,timeline)}}
def inspect_result(chain:M.Chain,metadata:Maybe<&2,Metadata>,limits:Limits,+timeline:Timeline,result:Result<&2,&2,Error,Plan>) -> Contents & Result<&2,&2,Error,Observation>:
  match result:
    case Fail{e}: (Contents{chain,metadata,limits,timeline,None{}},Fail{e})
    case Done{p}: (Contents{chain,metadata,limits,timeline,None{}},observe_plan(timeline,p))
def inspect(value:Contents) -> Contents & Result<&2,&2,Error,Observation>:
  match value:
    case Contents{M.Chain{levels},+metadata,+limits,timeline,None{}}:
      M.paired(List<&1,M.Level>,List<&2,M.Dimension>,Contents & Result<&2,&2,Error,Observation>,M.inspect_levels(levels),levels => dimensions => inspect_result(M.Chain{levels},metadata,limits,timeline,plan(dimensions,metadata,limits)))
    case Contents{chain,metadata,limits,timeline,Some{tail}}:
      (Contents{chain,metadata,limits,timeline,Some{tail}},Fail{Error{"NestedOwner","contents",0}})
def tick_result(result:Result<&2,&2,Error,Observation>,value:Contents) -> Contents & Result<&2,&2,Error,Selection>:
  match result:
    case Fail{e}: (value,Fail{e})
    case Done{Observation{+p,previous}}:
      Contents{chain,metadata,limits,timeline,tail} = value
      +next = advanced(p,timeline)
      (Contents{chain,metadata,limits,next,tail},Done{selection(p,next)})
def tick(value:Contents) -> Contents & Result<&2,&2,Error,Selection>:
  M.paired(Contents,Result<&2,&2,Error,Observation>,Contents & Result<&2,&2,Error,Selection>,inspect(value),value => result => tick_result(result,value))

def rect_at(values:List<&2,Rect>,index:Nat) -> Rect:
  match values index:
    case h <> rest 0n: h
    case h <> rest 1n+p: rect_at(rest,p)
    case _ _: Rect{0,0,0,0,0}
def dimension_at(values:List<&2,M.Dimension>,index:Nat) -> M.Dimension:
  match values index:
    case h <> rest 0n: h
    case h <> rest 1n+p: dimension_at(rest,p)
    case _ _: M.Dimension{0,0,0}
def crop_bounds(+rect:Rect,dimension:M.Dimension,+index:U32,+capacity:U32,+work:U32,limits:Limits) -> Result<&2,&2,Error,Rect>:
  Rect{m,+x,+y,+rw,+rh} = rect
  M.Dimension{+iw,+ih,size} = dimension
  Limits{d,l,f,e,+budget,+work_limit} = limits
  do Result<&2,&2,Error,Rect>:
    guard(U32.is_le(rw,iw)&&U32.is_le(rh,ih)&&U32.is_le(x,U32.sub(iw,rw))&&U32.is_le(y,U32.sub(ih,rh)),"RectBounds","frame",index)
    guard(U32.is_le(M.rounded_capacity(24n,U32.mul(rw,rh),1),U32.sub(budget,capacity)),"CropCapacity","frame",index)
    guard(U32.is_le(U32.mul(rw,rh),U32.sub(work_limit,work)),"CropWork","frame",index)
    Done{rect}
def crop_rect(+p:Plan,+index:U32,+mip:U32,limits:Limits) -> Result<&2,&2,Error,Rect>:
  Plan{w,h,r,count,frames,unique,i,animated,+dimensions,capacity,work} = p
  crop_bounds(rect_at(frame_rects(p,index),U32.to_nat(mip)),dimension_at(dimensions,U32.to_nat(mip)),index,capacity,work,limits)
def crop_admission(+p:Plan,+index:U32,+mip:U32,limits:Limits) -> Result<&2,&2,Error,Rect>:
  Plan{w,h,r,count,frames,+unique,i,+animated,+dimensions,capacity,work} = p
  do Result<&2,&2,Error,Rect>:
    guard(animated,"StaticSelection","frame",index)
    guard(contains(unique,index),"UnreferencedFrame","frame",index)
    guard(Nat.is_lt(U32.to_nat(mip),List.length(&2,M.Dimension,dimensions)),"MipRange","mip",mip)
    crop_rect(p,index,mip,limits)
def copy_pixels(fuel:Nat,input:Array<U32>,output:Array<U32>,+source_w:U32,+x:U32,+y:U32,+w:U32,+at:U32) -> Array<U32> & Array<U32>:
  match fuel:
    case 0n: (input,output)
    case 1n+p:
      source = U32.add(U32.add(x,U32.mod(at,w)),U32.mul(U32.add(y,U32.div(at,w)),source_w))
      M.paired(Array<U32>,U32,Array<U32> & Array<U32>,Array.get(U32,input,source),input => pixel => copy_pixels(p,input,Array.set(U32,output,at,pixel),source_w,x,y,w,U32.add(at,1)))
def crop_level(value:M.Level,rect:Rect) -> M.Level & M.Level:
  M.Level{+iw,ih,pixels} = value
  Rect{mip,+x,+y,+w,+h} = rect
  M.paired(Array<U32>,Array<U32>,M.Level & M.Level,copy_pixels(U32.to_nat(U32.mul(w,h)),pixels,M.new_pixels(w,h,0),iw,x,y,w,0),pixels => cropped => (M.Level{iw,ih,pixels},M.Level{w,h,cropped}))
def crop_levels(values:List<&1,M.Level>,index:Nat,+rect:Rect) -> List<&1,M.Level> & Result<&2,&1,Error,M.Level>:
  match values index:
    case Nil{} _: ([],Fail{Error{"MipRange","mip",0}})
    case h <> rest 0n:
      M.paired(M.Level,M.Level,List<&1,M.Level> & Result<&2,&1,Error,M.Level>,crop_level(h,rect),h => cropped => (h<>rest,Done{cropped}))
    case h <> rest 1n+p:
      M.paired(List<&1,M.Level>,Result<&2,&1,Error,M.Level>,List<&1,M.Level> & Result<&2,&1,Error,M.Level>,crop_levels(rest,p,rect),rest => result => (h<>rest,result))
def read_admitted(result:Result<&2,&2,Error,Rect>,value:Contents) -> Contents & Result<&2,&1,Error,M.Level>:
  match result:
    case Fail{e}: (value,Fail{e})
    case Done{+rect}:
      Rect{mip,x,y,w,h} = rect
      Contents{M.Chain{levels},metadata,limits,timeline,tail} = value
      M.paired(List<&1,M.Level>,Result<&2,&1,Error,M.Level>,Contents & Result<&2,&1,Error,M.Level>,crop_levels(levels,U32.to_nat(mip),rect),levels => cropped => (Contents{M.Chain{levels},metadata,limits,timeline,tail},cropped))
def read_result(result:Result<&2,&2,Error,Observation>,value:Contents,+index:U32,+mip:U32) -> Contents & Result<&2,&1,Error,M.Level>:
  match result:
    case Fail{e}: (value,Fail{e})
    case Done{Observation{p,selection}}:
      Contents{chain,metadata,+limits,timeline,tail} = value
      read_admitted(crop_admission(p,index,mip,limits),Contents{chain,metadata,limits,timeline,tail})
def read_frame(value:Contents,index:U32,mip:U32) -> Contents & Result<&2,&1,Error,M.Level>:
  M.paired(Contents,Result<&2,&2,Error,Observation>,Contents & Result<&2,&1,Error,M.Level>,inspect(value),value => observation => read_result(observation,value,index,mip))
def close_pair(first:Unit,last:Unit) -> Unit:
  last
def close_contents(value:Contents) -> Unit:
  match value:
    case Contents{chain,metadata,limits,timeline,None{}}: M.close_chain(chain)
    case Contents{chain,metadata,limits,timeline,Some{rest}}: close_pair(M.close_chain(chain),close_contents(rest))
def close_rejected(value:Rejected) -> Unit:
  Rejected{chain,error} = value
  M.close_chain(chain)

law default_grid_size:
  {metadata_size(4,8,Some{Metadata{None{},None{},None{},1,False{}}}) == Size{4,4} : Size}
def default_grid_size():
  {==}
law static_kind:
  {starting(Plan{4,8,1,1,[],[1],False{},False{},[],0,0}) == NoTimeline{} : Timeline}
def static_kind():
  {==}
