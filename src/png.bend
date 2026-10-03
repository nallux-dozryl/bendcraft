import Base
import ./compression.bend as C

# PNG pixels are straight-alpha 0xAARRGGBB, compatible with Base Pix.
# All formats observed in pinned 26.3 block textures are noninterlaced,
# depths 1/2/4/8. Unsupported formats fail before allocating image storage.
type Limits is Data:
  Limits{max_input: U32, max_width: U32, max_height: U32, max_pixels: U32}

type Error is Data:
  Error{code: String}

type Decoded is Data:
  Decoded{width: U32, height: U32, pixels: List<&2, U32>}

type Header is Data:
  Header{width: U32, height: U32, depth: U32, color: U32, row_bytes: U32, bpp: U32}

type State is Data:
  State{header: Maybe<&2, Header>, palette: List<&2, U32>, transparency: List<&2, U32>,
    idat_reversed: List<&2, U32>, palette_seen: Bool, transparency_seen: Bool,
    idat_seen: Bool, idat_ended: Bool, finished: Bool, chunks: U32}

type Cursor is Data:
  Cursor{bytes: List<&2, U32>, offset: U32}

type Read<-A: Data> is Data:
  Read{cursor: Cursor, value: A}

def paired(-A: Type, -B: Type, -R: Type, pair: A & B, body: A -> B -> R) -> R:
  match pair:
    case Tuple{a,b}: body(a)(b)

def read_with(-A: Data, -R: Type, read: Read<A>, body: Cursor -> A -> R) -> R:
  match read:
    case Read{cursor,value}: body(cursor)(value)

def choose(-A: Type, yes: A, no: A, condition: Bool) -> A:
  match condition:
    case True{}: yes
    case False{}: no

def require(valid: Bool, code: String) -> Result<&2, &1, Error, Unit>:
  match valid:
    case True{}: Done{Unit{}}
    case False{}: Fail{Error{code}}

def default_limits() -> Limits:
  Limits{16777216,1024,4096,1048576}

def count(bytes: List<&2,U32>, +limit: U32, +n: U32) -> Result<&2,&1,Error,U32>:
  match bytes:
    case Nil{}: Done{n}
    case +b <> tail:
      do Result<&2,&1,Error,U32>:
        require(U32.is_lt(b,256),"InvalidByte")
        require(U32.is_lt(n,limit),"InputLimit")
        count(tail,limit,U32.inc(n))

def take(n: Nat, cursor: Cursor, reversed: List<&2,U32>) -> Result<&2,&1,Error,Read<List<&2,U32>>>:
  match n cursor:
    case 0n _: Done{Read{cursor,List.reverse(&2,U32,reversed)}}
    case 1n+p Cursor{Nil{},offset}: Fail{Error{"Truncated"}}
    case 1n+p Cursor{b <> tail,offset}: take(p,Cursor{tail,U32.inc(offset)},b <> reversed)

def be32(bytes: List<&2,U32>) -> U32:
  match bytes:
    case a <> b <> c <> d <> rest: U32.or(U32.shln(a,24n),U32.or(U32.shln(b,16n),U32.or(U32.shln(c,8n),d)))
    case _: 0

def at(bytes: List<&2,U32>, n: Nat) -> U32:
  match bytes n:
    case Nil{} _: 0
    case b <> tail 0n: b
    case b <> tail 1n+p: at(tail,p)

def append_reverse(bytes: List<&2,U32>, reversed: List<&2,U32>) -> List<&2,U32>:
  match bytes:
    case Nil{}: reversed
    case b <> tail: append_reverse(tail,b <> reversed)

def channels(color: U32) -> U32:
  match color:
    case 0: 1
    case 2: 3
    case 3: 1
    case 4: 2
    case 6: 4
    case _: 0

def valid_format(+depth: U32,+color: U32) -> Bool:
  (U32.is_eq(depth,8) && (U32.is_eq(color,0) || U32.is_eq(color,2) || U32.is_eq(color,3) || U32.is_eq(color,4) || U32.is_eq(color,6))) ||
  ((U32.is_eq(depth,1) || U32.is_eq(depth,2) || U32.is_eq(depth,4)) && (U32.is_eq(color,0) || U32.is_eq(color,3)))

def header(+bytes: List<&2,U32>, limits: Limits) -> Result<&2,&1,Error,Header>:
  Limits{input,+max_width,+max_height,+max_pixels} = limits
  +w = be32(bytes)
  +h = be32(List.drop(&2,U32,bytes,4n))
  +d = at(bytes,8n)
  +c = at(bytes,9n)
  +row = U32.div(U32.add(U32.mul(U32.mul(w,channels(c)),d),7),8)
  do Result<&2,&1,Error,Header>:
    require(U32.is_eq(U32.from_nat(List.length(&2,U32,bytes)),13),"IHDRLength")
    require(U32.is_gt(w,0) && U32.is_gt(h,0) && U32.is_le(w,max_width) && U32.is_le(h,max_height),"Dimensions")
    require(U32.is_le(max_width,4096) && U32.is_le(max_height,4096) && U32.is_le(max_pixels,16777216) && U32.is_le(w,U32.div(max_pixels,h)),"PixelLimit")
    require(valid_format(d,c),"UnsupportedFormat")
    require(U32.is_zero(at(bytes,10n)) && U32.is_zero(at(bytes,11n)),"UnsupportedMethod")
    require(U32.is_zero(at(bytes,12n)),"UnsupportedInterlace")
    return Header{w,h,d,c,row,U32.max(1,U32.div(U32.mul(channels(c),d),8))}

def ihdr(bytes: List<&2,U32>, state: State, limits: Limits) -> Result<&2,&1,Error,State>:
  State{+old,+pal,+trns,+data,+ps,+ts,+seen,+ended,+finished,+chunks} = state
  do Result<&2,&1,Error,State>:
    require(U32.is_zero(chunks),"IHDRMustBeFirst")
    got : Header <- header(bytes,limits)
    return State{Some{got},pal,trns,data,ps,ts,seen,ended,finished,U32.inc(chunks)}

def plte(+bytes: List<&2,U32>, state: State) -> Result<&2,&1,Error,State>:
  State{+hdr,+old,+trns,+data,+ps,+ts,+seen,+ended,+finished,+chunks} = state
  +n = U32.from_nat(List.length(&2,U32,bytes))
  do Result<&2,&1,Error,State>:
    require(Bool.not(ps) && Bool.not(ts) && Bool.not(seen) && Maybe.is_some(&2,Header,hdr),"PLTEOrder")
    require(U32.is_gt(n,0) && U32.is_le(n,768) && U32.is_zero(U32.mod(n,3)),"PLTELength")
    return State{hdr,bytes,trns,data,True{},ts,seen,ended,finished,U32.inc(chunks)}

def trns_order(hdr: Maybe<&2,Header>,ps: Bool) -> Bool:
  match hdr:
    case None{}: False{}
    case Some{Header{w,h,d,c,row,bpp}}: U32.is_ne(c,3) || ps

def trns(+bytes: List<&2,U32>, state: State) -> Result<&2,&1,Error,State>:
  State{+hdr,+pal,+old,+data,+ps,+ts,+seen,+ended,+finished,+chunks} = state
  do Result<&2,&1,Error,State>:
    require(Bool.not(ts) && Bool.not(seen) && trns_order(hdr,ps),"TRNSOrder")
    return State{hdr,pal,bytes,data,ps,True{},seen,ended,finished,U32.inc(chunks)}

def idat(bytes: List<&2,U32>, state: State) -> Result<&2,&1,Error,State>:
  State{+hdr,+pal,+trns,+data,+ps,+ts,+seen,+ended,+finished,+chunks} = state
  do Result<&2,&1,Error,State>:
    require(Bool.not(ended),"IDATNotContiguous")
    return State{hdr,pal,trns,append_reverse(bytes,data),ps,ts,True{},False{},finished,U32.inc(chunks)}

def ancillary(state: State) -> State:
  State{+hdr,+pal,+trns,+data,+ps,+ts,+seen,+ended,+finished,+chunks} = state
  State{hdr,pal,trns,data,ps,ts,seen,seen || ended,finished,U32.inc(chunks)}

def chunk_name_valid(bytes: List<&2,U32>) -> Bool:
  match bytes:
    case Nil{}: True{}
    case +b <> tail:
      ((U32.is_ge(b,65) && U32.is_le(b,90)) || (U32.is_ge(b,97) && U32.is_le(b,122))) && chunk_name_valid(tail)

def state_chunks(state: State) -> U32:
  State{+hdr,+pal,+trns,+data,+ps,+ts,+seen,+ended,+finished,+chunks} = state
  chunks

def end_state(state: State, size: U32) -> Result<&2,&1,Error,State>:
  State{+hdr,+pal,+trns,+data,+ps,+ts,+seen,+ended,+finished,+chunks} = state
  do Result<&2,&1,Error,State>:
    require(U32.is_zero(size),"IENDLength")
    return State{hdr,pal,trns,data,ps,ts,seen,ended,True{},U32.inc(chunks)}

def process_type(kind: U32, name: List<&2,U32>, +bytes: List<&2,U32>, +state: State, limits: Limits) -> Result<&2,&1,Error,State>:
  match kind:
    case 1229472850: ihdr(bytes,state,limits)
    case 1347179589: plte(bytes,state)
    case 1951551059: trns(bytes,state)
    case 1229209940: idat(bytes,state)
    case 1229278788: end_state(state,U32.from_nat(List.length(&2,U32,bytes)))
    case _:
      do Result<&2,&1,Error,State>:
        require(U32.is_ne(U32.and(at(name,0n),32),0),"UnknownCriticalChunk")
        require(U32.is_gt(state_chunks(state),0),"IHDRMustBeFirst")
        return ancillary(state)

def process(+name: List<&2,U32>, bytes: List<&2,U32>, +state: State, limits: Limits) -> Result<&2,&1,Error,State>:
  do Result<&2,&1,Error,State>:
    require(chunk_name_valid(name) && U32.is_zero(U32.and(at(name,2n),32)),"ChunkName")
    process_type(be32(name),name,bytes,state,limits)

def state_finished(state: State) -> Bool:
  State{+hdr,+pal,+trns,+data,+ps,+ts,+seen,+ended,+finished,+chunks} = state
  finished

def chunks(fuel: Nat, cursor: Cursor, +state: State, +limits: Limits) -> Result<&2,&1,Error,State>:
  match fuel cursor:
    case _ Cursor{Nil{},offset}:
      do Result<&2,&1,Error,State>:
        require(state_finished(state),"MissingIEND")
        return state
    case 0n _: Fail{Error{"ChunkLimit"}}
    case 1n+p _:
      do Result<&2,&1,Error,State>:
        require(Bool.not(state_finished(state)),"TrailingData")
        prefix : Read<List<&2,U32>> <- take(8n,cursor,[])
        read_with(List<&2,U32>,Result<&2,&1,Error,State>,prefix,cursor => +prefix => (
          +size = be32(prefix)
          +name = List.drop(&2,U32,prefix,4n)
          do Result<&2,&1,Error,State>:
            require(U32.is_le(size,16777216),"ChunkLimit")
            payload : Read<List<&2,U32>> <- take(U32.to_nat(size),cursor,[])
            read_with(List<&2,U32>,Result<&2,&1,Error,State>,payload,cursor => +payload => (
              do Result<&2,&1,Error,State>:
                trailer : Read<List<&2,U32>> <- take(4n,cursor,[])
                read_with(List<&2,U32>,Result<&2,&1,Error,State>,trailer,cursor => checksum => (
                  do Result<&2,&1,Error,State>:
                    require(U32.is_eq(C.crc32(List.append(&2,U32,name,payload)),be32(checksum)),"CRC")
                    next : State <- process(name,payload,state,limits)
                    chunks(p,cursor,next,limits)
                ))
            ))
        ))

def distance(+a: U32,+b: U32) -> U32:
  U32.sub(U32.max(a,b),U32.min(a,b))

def paeth(+a: U32,+b: U32,+c: U32) -> U32:
  +pa = distance(b,c)
  +pb = distance(a,c)
  +pc = distance(U32.add(a,b),U32.mul(c,2))
  choose(U32,a,choose(U32,b,c,U32.is_le(pb,pc)),U32.is_le(pa,pb) && U32.is_le(pa,pc))

def predictor(filter: U32,a: U32,b: U32,c: U32) -> U32:
  match filter:
    case 0: 0
    case 1: a
    case 2: b
    case 3: U32.div(U32.add(a,b),2)
    case 4: paeth(a,b,c)
    case _: 0

def reconstructed(buffer: Array<U32>, +index: U32, +x: U32, +row: U32, +bpp: U32, filter: U32, byte: U32) -> Array<U32>:
  paired(Array<U32>,U32,Array<U32>,buffer[U32.sub(index,bpp)],buffer => left =>
    paired(Array<U32>,U32,Array<U32>,buffer[U32.sub(index,row)],buffer => top =>
      paired(Array<U32>,U32,Array<U32>,buffer[U32.sub(U32.sub(index,row),bpp)],buffer => corner => (
        +a = choose(U32,left,0,U32.is_ge(x,bpp))
        +b = choose(U32,top,0,U32.is_ge(index,row))
        c = choose(U32,corner,0,U32.is_ge(x,bpp) && U32.is_ge(index,row))
        buffer[index] <- U32.and(U32.add(byte,predictor(filter,a,b,c)),255)
      ))))

def row_bytes(n: Nat, bytes: List<&2,U32>, buffer: Array<U32>, +index: U32, +x: U32, +row: U32, +bpp: U32, +filter: U32) -> Result<&2,&1,Error,List<&2,U32> & Array<U32>>:
  match n bytes:
    case 0n _: Done{(bytes,buffer)}
    case 1n+p Nil{}: Fail{Error{"ScanlineLength"}}
    case 1n+p byte <> tail:
      row_bytes(p,tail,reconstructed(buffer,index,x,row,bpp,filter,byte),U32.inc(index),U32.inc(x),row,bpp,filter)

def rows(n: Nat, bytes: List<&2,U32>, buffer: Array<U32>, +index: U32, +row: U32, +bpp: U32) -> Result<&2,&1,Error,Array<U32>>:
  match n bytes:
    case 0n Nil{}: Done{buffer}
    case 0n _: Fail{Error{"ScanlineLength"}}
    case 1n+p Nil{}: Fail{Error{"ScanlineLength"}}
    case 1n+p +filter <> tail:
      do Result<&2,&1,Error,Array<U32>>:
        require(U32.is_le(filter,4),"Filter")
        got : List<&2,U32> & Array<U32> <- row_bytes(U32.to_nat(row),tail,buffer,index,0,row,bpp,filter)
        paired(List<&2,U32>,Array<U32>,Result<&2,&1,Error,Array<U32>>,got,tail => buffer => rows(p,tail,buffer,U32.add(index,row),row,bpp))

def array_depth(fuel: Nat,+needed: U32,+capacity: U32) -> Nat:
  match fuel:
    case 0n: 0n
    case 1n+p: choose(Nat,0n,1n+array_depth(p,needed,U32.mul(capacity,2)),U32.is_ge(capacity,needed))

def sample(buffer: Array<U32>, +base: U32, +n: U32,+depth: U32) -> Array<U32> & U32:
  +bit = U32.mul(n,depth)
  paired(Array<U32>,U32,Array<U32> & U32,buffer[U32.add(base,U32.div(bit,8))],buffer => byte =>
    (buffer,U32.and(U32.shrn(byte,U32.to_nat(U32.sub(U32.sub(8,depth),U32.mod(bit,8)))),U32.sub(U32.shln(1,U32.to_nat(depth)),1))))

def argb(a: U32,r: U32,g: U32,b: U32) -> U32:
  U32.or(U32.shln(a,24n),U32.or(U32.shln(r,16n),U32.or(U32.shln(g,8n),b)))

def transparent16(+bytes: List<&2,U32>, +n: Nat) -> U32:
  U32.or(U32.shln(at(bytes,n),8n),at(bytes,1n+n))

def gray_pixel(buffer: Array<U32>, base: U32, n: U32,+depth: U32,+trns: List<&2,U32>, has_trns: Bool) -> Array<U32> & U32:
  paired(Array<U32>,U32,Array<U32> & U32,sample(buffer,base,n,depth),buffer => +s => (
    +gray = U32.div(U32.mul(s,255),U32.sub(U32.shln(1,U32.to_nat(depth)),1))
    (buffer,argb(choose(U32,0,255,has_trns && U32.is_eq(s,transparent16(trns,0n))),gray,gray,gray))
  ))

def rgb_pixel(buffer: Array<U32>, +base: U32, +n: U32,+trns: List<&2,U32>, has_trns: Bool) -> Array<U32> & U32:
  paired(Array<U32>,U32,Array<U32> & U32,sample(buffer,base,U32.mul(n,3),8),buffer => +r =>
    paired(Array<U32>,U32,Array<U32> & U32,sample(buffer,base,U32.add(U32.mul(n,3),1),8),buffer => +g =>
      paired(Array<U32>,U32,Array<U32> & U32,sample(buffer,base,U32.add(U32.mul(n,3),2),8),buffer => +b => (
        alpha = choose(U32,0,255,has_trns && U32.is_eq(r,transparent16(trns,0n)) && U32.is_eq(g,transparent16(trns,2n)) && U32.is_eq(b,transparent16(trns,4n)))
        (buffer,argb(alpha,r,g,b))
      ))))

def indexed_pixel(buffer: Array<U32>, base: U32, n: U32, depth: U32,+pal: List<&2,U32>,+trns: List<&2,U32>) -> Result<&2,&1,Error,Array<U32> & U32>:
  paired(Array<U32>,U32,Result<&2,&1,Error,Array<U32> & U32>,sample(buffer,base,n,depth),buffer => +s => (
    do Result<&2,&1,Error,Array<U32> & U32>:
      require(U32.is_lt(U32.mul(s,3),U32.from_nat(List.length(&2,U32,pal))),"PaletteIndex")
      return (buffer,argb(choose(U32,at(trns,U32.to_nat(s)),255,U32.is_lt(s,U32.from_nat(List.length(&2,U32,trns)))),at(pal,U32.to_nat(U32.mul(s,3))),at(pal,U32.to_nat(U32.add(U32.mul(s,3),1))),at(pal,U32.to_nat(U32.add(U32.mul(s,3),2)))))
  ))

def ga_pixel(buffer: Array<U32>,+base: U32,+n: U32) -> Array<U32> & U32:
  paired(Array<U32>,U32,Array<U32> & U32,sample(buffer,base,U32.mul(n,2),8),buffer => +g =>
    paired(Array<U32>,U32,Array<U32> & U32,sample(buffer,base,U32.add(U32.mul(n,2),1),8),buffer => a =>
      (buffer,argb(a,g,g,g))))

def rgba_pixel(buffer: Array<U32>,+base: U32,+n: U32) -> Array<U32> & U32:
  paired(Array<U32>,U32,Array<U32> & U32,sample(buffer,base,U32.mul(n,4),8),buffer => r =>
    paired(Array<U32>,U32,Array<U32> & U32,sample(buffer,base,U32.add(U32.mul(n,4),1),8),buffer => g =>
      paired(Array<U32>,U32,Array<U32> & U32,sample(buffer,base,U32.add(U32.mul(n,4),2),8),buffer => b =>
        paired(Array<U32>,U32,Array<U32> & U32,sample(buffer,base,U32.add(U32.mul(n,4),3),8),buffer => a =>
          (buffer,argb(a,r,g,b))))))

def pixel(color: U32,buffer: Array<U32>,base: U32,n: U32,depth: U32,pal: List<&2,U32>,trns: List<&2,U32>,has_trns: Bool) -> Result<&2,&1,Error,Array<U32> & U32>:
  match color:
    case 0: Done{gray_pixel(buffer,base,n,depth,trns,has_trns)}
    case 2: Done{rgb_pixel(buffer,base,n,trns,has_trns)}
    case 3: indexed_pixel(buffer,base,n,depth,pal,trns)
    case 4: Done{ga_pixel(buffer,base,n)}
    case 6: Done{rgba_pixel(buffer,base,n)}
    case _: Fail{Error{"UnsupportedFormat"}}

def pixels(n: Nat, buffer: Array<U32>,+index: U32,+header: Header,+pal: List<&2,U32>,+trns: List<&2,U32>,+has_trns: Bool,reversed: List<&2,U32>) -> Result<&2,&1,Error,List<&2,U32>>:
  match n:
    case 0n: Done{List.reverse(&2,U32,reversed)}
    case 1n+p:
      Header{+w,h,depth,color,row,bpp} = header
      do Result<&2,&1,Error,List<&2,U32>>:
        got : Array<U32> & U32 <- pixel(color,buffer,U32.mul(U32.div(index,w),row),U32.mod(index,w),depth,pal,trns,has_trns)
        paired(Array<U32>,U32,Result<&2,&1,Error,List<&2,U32>>,got,buffer => value => pixels(p,buffer,U32.inc(index),header,pal,trns,has_trns,value <> reversed))

def transparency_valid(+h: Header,+palette: List<&2,U32>,+trns: List<&2,U32>,+ps: Bool,ts: Bool) -> Bool:
  Header{w,hh,+depth,+color,row,bpp} = h
  +plen = U32.from_nat(List.length(&2,U32,palette))
  +tlen = U32.from_nat(List.length(&2,U32,trns))
  (U32.is_ne(color,3) || (ps && U32.is_le(U32.div(plen,3),U32.shln(1,U32.to_nat(depth))))) &&
  (Bool.not(ps) || (U32.is_ne(color,0) && U32.is_ne(color,4))) &&
  (Bool.not(ts) || (U32.is_eq(color,0) && U32.is_eq(tlen,2)) || (U32.is_eq(color,2) && U32.is_eq(tlen,6)) || (U32.is_eq(color,3) && ps && U32.is_le(tlen,U32.div(plen,3))))

def inflate_result(result: Result<&2,&1,C.Error,C.Decoded>) -> Result<&2,&1,Error,C.Decoded>:
  match result:
    case Fail{C.Error{code}}: Fail{Error{"Zlib:" ++ code}}
    case Done{data}: Done{data}

def decode_image(+header: Header,palette: List<&2,U32>,trns: List<&2,U32>,has_trns: Bool,result: C.Decoded) -> Result<&2,&1,Error,Decoded>:
  match header result:
    case Header{+width,+height,depth,color,+row,bpp} C.Decoded{bytes,size,consumed,adler,crc}:
      do Result<&2,&1,Error,Decoded>:
        require(U32.is_eq(size,U32.mul(height,U32.inc(row))),"ScanlineLength")
        buffer : Array<U32> <- rows(U32.to_nat(height),bytes,Array.new(U32,array_depth(27n,U32.mul(height,row),1),0),0,row,bpp)
        got : List<&2,U32> <- pixels(U32.to_nat(U32.mul(width,height)),buffer,0,header,palette,trns,has_trns,[])
        return Decoded{width,height,got}

def finalize(state: State) -> Result<&2,&1,Error,Decoded>:
  match state:
    case State{None{},pal,trns,data,ps,ts,seen,ended,finished,chunks}: Fail{Error{"MissingIHDR"}}
    case State{Some{+h},+pal,+trns,data,ps,+ts,seen,ended,finished,chunks}:
      Header{w,+height,depth,color,+row,bpp} = h
      do Result<&2,&1,Error,Decoded>:
        require(seen,"MissingIDAT")
        require(transparency_valid(h,pal,trns,ps,ts),"PaletteTransparency")
        inflated : C.Decoded <- inflate_result(C.inflate_zlib(List.reverse(&2,U32,data),C.Limits{16777216,U32.mul(height,U32.inc(row))}))
        decode_image(h,pal,trns,ts,inflated)

def signature(bytes: List<&2,U32>,limits: Limits) -> Result<&2,&1,Error,Decoded>:
  match bytes:
    case 137 <> 80 <> 78 <> 71 <> 13 <> 10 <> 26 <> 10 <> tail:
      do Result<&2,&1,Error,Decoded>:
        state : State <- chunks(65536n,Cursor{tail,8},State{None{},[],[],[],False{},False{},False{},False{},False{},0},limits)
        finalize(state)
    case _: Fail{Error{"Signature"}}

def decode(+bytes: List<&2,U32>,+limits: Limits) -> Result<&2,&1,Error,Decoded>:
  Limits{input,w,h,pixels} = limits
  do Result<&2,&1,Error,Decoded>:
    size : U32 <- count(bytes,input,0)
    signature(bytes,limits)

def rgba_bytes_go(pixels: List<&2,U32>,reversed: List<&2,U32>) -> List<&2,U32>:
  match pixels:
    case Nil{}: List.reverse(&2,U32,reversed)
    case +p <> tail:
      rgba_bytes_go(tail,U32.shrn(p,24n) <> U32.and(p,255) <> U32.and(U32.shrn(p,8n),255) <> U32.and(U32.shrn(p,16n),255) <> reversed)

def rgba_bytes(pixels: List<&2,U32>) -> List<&2,U32>:
  rgba_bytes_go(pixels,[])
