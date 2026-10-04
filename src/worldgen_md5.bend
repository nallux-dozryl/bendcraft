import Base

# RFC 1321 compression and little-endian byte packing. This is the actual
# positional-name seed digest, not a cryptographic service or host adapter.
type Digest is Data:
  Digest{a:U32,b:U32,c:U32,d:U32}

type Round is Data:
  Round{kind:U32,index:U32,shift:Nat,constant:U32}

type State is Type:
  State{hash:Digest,words:Array<U32>,position:U32,partial:U32,length_hi:U32,length_lo:U32}

def initial() -> Digest:
  Digest{1732584193,4023233417,2562383102,271733878}

def rotate_left(+word:U32,+shift:Nat) -> U32:
  U32.or(U32.shln(word,shift),U32.shrn(word,Nat.sub(32n,shift)))

def boolean(kind:U32,+b:U32,+c:U32,+d:U32) -> U32:
  match kind:
    case 0: U32.or(U32.and(b,c),U32.and(U32.not(b),d))
    case 1: U32.or(U32.and(b,d),U32.and(c,U32.not(d)))
    case 2: U32.xor(U32.xor(b,c),d)
    case _: U32.xor(c,U32.or(b,U32.not(d)))

def step(current:Digest,round:Round,word:U32) -> Digest:
  match current round:
    case Digest{a,+b,+c,+d} Round{kind,index,shift,constant}:
      Digest{d,U32.add(b,rotate_left(U32.add(U32.add(a,boolean(kind,b,c,d)),U32.add(word,constant)),shift)),b,c}

def read_step(round:Round,current:Digest,read:Array<U32> & U32) -> Array<U32> & Digest:
  (words,word) = read
  (words,step(current,round,word))

def rounds(instructions:List<&2,Round>,current:Array<U32> & Digest) -> Array<U32> & Digest:
  match instructions:
    case Nil{}: current
    case Round{kind,+index,shift,constant} <> rest:
      (words,hash) = current
      rounds(rest,read_step(Round{kind,index,shift,constant},hash,Array.get(U32,words,index)))

def add_hash(left:Digest,right:Digest) -> Digest:
  match left right:
    case Digest{a,b,c,d} Digest{w,x,y,z}:
      Digest{U32.add(a,w),U32.add(b,x),U32.add(c,y),U32.add(d,z)}

def compressed(+hash:Digest,current:Array<U32> & Digest) -> Array<U32> & Digest:
  (words,value) = current
  (words,add_hash(hash,value))

def instructions() -> List<&2,Round>:
  [Round{0,0,7n,3614090360},Round{0,1,12n,3905402710},Round{0,2,17n,606105819},Round{0,3,22n,3250441966},
   Round{0,4,7n,4118548399},Round{0,5,12n,1200080426},Round{0,6,17n,2821735955},Round{0,7,22n,4249261313},
   Round{0,8,7n,1770035416},Round{0,9,12n,2336552879},Round{0,10,17n,4294925233},Round{0,11,22n,2304563134},
   Round{0,12,7n,1804603682},Round{0,13,12n,4254626195},Round{0,14,17n,2792965006},Round{0,15,22n,1236535329},
   Round{1,1,5n,4129170786},Round{1,6,9n,3225465664},Round{1,11,14n,643717713},Round{1,0,20n,3921069994},
   Round{1,5,5n,3593408605},Round{1,10,9n,38016083},Round{1,15,14n,3634488961},Round{1,4,20n,3889429448},
   Round{1,9,5n,568446438},Round{1,14,9n,3275163606},Round{1,3,14n,4107603335},Round{1,8,20n,1163531501},
   Round{1,13,5n,2850285829},Round{1,2,9n,4243563512},Round{1,7,14n,1735328473},Round{1,12,20n,2368359562},
   Round{2,5,4n,4294588738},Round{2,8,11n,2272392833},Round{2,11,16n,1839030562},Round{2,14,23n,4259657740},
   Round{2,1,4n,2763975236},Round{2,4,11n,1272893353},Round{2,7,16n,4139469664},Round{2,10,23n,3200236656},
   Round{2,13,4n,681279174},Round{2,0,11n,3936430074},Round{2,3,16n,3572445317},Round{2,6,23n,76029189},
   Round{2,9,4n,3654602809},Round{2,12,11n,3873151461},Round{2,15,16n,530742520},Round{2,2,23n,3299628645},
   Round{3,0,6n,4096336452},Round{3,7,10n,1126891415},Round{3,14,15n,2878612391},Round{3,5,21n,4237533241},
   Round{3,12,6n,1700485571},Round{3,3,10n,2399980690},Round{3,10,15n,4293915773},Round{3,1,21n,2240044497},
   Round{3,8,6n,1873313359},Round{3,15,10n,4264355552},Round{3,6,15n,2734768916},Round{3,13,21n,1309151649},
   Round{3,4,6n,4149444226},Round{3,11,10n,3174756917},Round{3,2,15n,718787259},Round{3,9,21n,3951481745}]

def compress(+hash:Digest,words:Array<U32>) -> Array<U32> & Digest:
  compressed(hash,rounds(instructions(),(words,hash)))

def new_state() -> State:
  State{initial(),Array.new(U32,4n,0),0,0,0,0}

def write_word(hash:Digest,words:Array<U32>,+position:U32,partial:U32,hi:U32,lo:U32,complete:Bool) -> State:
  match complete:
    case False{}: State{hash,words,position,partial,hi,lo}
    case True{}:
      State{hash,Array.set(U32,words,U32.sub(U32.shrn(position,2n),1),partial),position,0,hi,lo}

def compressed_state(hi:U32,lo:U32,result:Array<U32> & Digest) -> State:
  (words,hash) = result
  State{hash,words,0,0,hi,lo}

def complete_block(state:State,full:Bool) -> State:
  match state full:
    case _ False{}: state
    case State{hash,words,position,partial,hi,lo} True{}:
      compressed_state(hi,lo,compress(hash,words))

def append_byte(state:State,byte:U32) -> State:
  match state:
    case State{hash,words,+position,partial,hi,+lo}:
      +next = U32.inc(position)
      +next_lo = U32.inc(lo)
      complete_block(write_word(hash,words,next,
        U32.or(partial,U32.shln(byte,U32.to_nat(U32.mul(U32.and(position,3),8)))),
        U32.add(hi,Bool.to_u32(U32.is_zero(next_lo))),next_lo,U32.is_zero(U32.and(next,3))),U32.is_eq(next,64))

def append_list(bytes:List<&2,U32>,state:State) -> State:
  match bytes:
    case Nil{}: state
    case byte <> rest: append_list(rest,append_byte(state,byte))

def append_checked(state:State,byte:U32,valid:Bool) -> Result<&2,&1,String,State>:
  match valid:
    case False{}: Fail{"MD5 input byte exceeds 255"}
    case True{}: Done{append_byte(state,byte)}

def process(bytes:List<&2,U32>,room:Nat,state:Result<&2,&1,String,State>) -> Result<&2,&1,String,State>:
  match bytes room state:
    case _ _ Fail{message}: Fail{message}
    case Nil{} _ Done{state}: Done{state}
    case _ <> _ 0n Done{state}: Fail{"MD5 input byte budget exceeded"}
    case +byte <> rest 1n+left Done{state}:
      process(rest,left,append_checked(state,byte,U32.is_le(byte,255)))

def word_bytes(+word:U32) -> List<&2,U32>:
  [U32.and(word,255),U32.and(U32.shrn(word,8n),255),U32.and(U32.shrn(word,16n),255),U32.shrn(word,24n)]

def bit_length(+hi:U32,+lo:U32) -> List<&2,U32>:
  List.append(&2,U32,word_bytes(U32.shln(lo,3n)),word_bytes(U32.or(U32.shln(hi,3n),U32.shrn(lo,29n))))

def append_zeros(count:Nat,state:State) -> State:
  match count:
    case 0n: state
    case 1n+rest: append_zeros(rest,append_byte(state,0))

def padding(+position:U32,first:Bool) -> Nat:
  match first:
    case True{}: U32.to_nat(U32.sub(55,position))
    case False{}: U32.to_nat(U32.sub(119,position))

def state_digest(state:State) -> Digest:
  match state:
    case State{hash,words,position,partial,hi,lo}: hash

def finalize(state:State) -> Digest:
  match state:
    case State{hash,words,+position,partial,+hi,+lo}:
      state_digest(append_list(bit_length(hi,lo),append_zeros(padding(position,U32.is_le(position,55)),
        append_byte(State{hash,words,position,partial,hi,lo},128))))

def finish(result:Result<&2,&1,String,State>) -> Result<&2,&2,String,Digest>:
  match result:
    case Fail{message}: Fail{message}
    case Done{state}: Done{finalize(state)}

# A named-seed budget is an explicit caller resource limit. Refusing an
# oversized limit prevents native Nat wrapping before processing any bytes.
def digest_gate(limit:Nat,bytes:List<&2,U32>,valid:Bool) -> Result<&2,&2,String,Digest>:
  match valid:
    case False{}: Fail{"MD5 byte budget exceeds U32 representation"}
    case True{}: finish(process(bytes,limit,Done{new_state()}))

def digest(+limit:Nat,bytes:List<&2,U32>) -> Result<&2,&2,String,Digest>:
  digest_gate(limit,bytes,Nat.is_eq(Nat.div(Nat.div(limit,65536n),65536n),0n))

def byte_swap(+word:U32) -> U32:
  U32.or(U32.or(U32.shln(U32.and(word,255),24n),U32.shln(U32.and(U32.shrn(word,8n),255),16n)),
    U32.or(U32.shln(U32.and(U32.shrn(word,16n),255),8n),U32.shrn(word,24n)))

def bytes(hash:Digest) -> List<&2,U32>:
  match hash:
    case Digest{a,b,c,d}:
      List.append(&2,U32,word_bytes(a),List.append(&2,U32,word_bytes(b),List.append(&2,U32,word_bytes(c),word_bytes(d))))
