import Base
import ./entity_chunk_loading_model.bend as M

def choose(~D:Data,a:D,b:D,value:Bool) -> D:
  match value:
    case True{}: a
    case False{}: b
def word_equal(a:M.Word64,b:M.Word64) -> Bool:
  M.Word64{ah,al}=a
  M.Word64{bh,bl}=b
  U32.is_eq(ah,bh) && U32.is_eq(al,bl)
def word_zero(value:M.Word64) -> Bool:
  M.Word64{hi,lo}=value
  U32.is_eq(U32.or(hi,lo),0)
def word_negative(value:M.Word64) -> Bool:
  M.Word64{hi,lo}=value
  U32.is_ge(hi,2147483648)
def word_decrement(value:M.Word64) -> M.Word64:
  M.Word64{+hi,+lo}=value
  M.Word64{choose(U32,U32.sub(hi,1),hi,U32.is_eq(lo,0)),U32.sub(lo,1)}
def word_full(value:M.Word64) -> Bool:
  M.Word64{hi,lo}=value
  U32.is_eq(hi,4294967295) && U32.is_eq(lo,4294967295)
def word_increment(value:M.Word64) -> M.Word64:
  M.Word64{+hi,+lo}=value
  M.Word64{choose(U32,U32.add(hi,1),hi,U32.is_eq(lo,4294967295)),U32.add(lo,1)}
def key_equal(a:M.ChunkKey,b:M.ChunkKey) -> Bool:
  M.ChunkKey{ax,az}=a
  M.ChunkKey{bx,bz}=b
  U32.is_eq(ax,bx) && U32.is_eq(az,bz)
def scope_equal(a:M.Scope,b:M.Scope) -> Bool:
  M.Scope{aw,ad,ae}=a
  M.Scope{bw,bd,be}=b
  String.eq(aw,bw) && String.eq(ad,bd) && word_equal(ae,be)
def int_less(a:U32,b:U32) -> Bool:
  U32.is_lt(U32.xor(a,2147483648),U32.xor(b,2147483648))
def int_min(+a:U32,+b:U32) -> U32: choose(U32,a,b,int_less(a,b))
def flag(flags:U32,bit:U32) -> Bool: U32.is_ne(U32.and(flags,bit),0)
def type_equal(a:M.TicketType,b:M.TicketType) -> Bool:
  M.TicketType{an,at,af}=a
  M.TicketType{bn,bt,bf}=b
  String.eq(an,bn) && word_equal(at,bt) && U32.is_eq(af,bf)
def same_ticket(a:M.Ticket,b:M.Ticket) -> Bool:
  M.Ticket{M.TicketType{an,at,af},al,av}=a
  M.Ticket{M.TicketType{bn,bt,bf},bl,bv}=b
  String.eq(an,bn) && U32.is_eq(al,bl)
def has_timeout(value:M.TicketType) -> Bool:
  M.TicketType{name,time,flags}=value
  Bool.not(word_zero(time))
def type_flag(value:M.TicketType,bit:U32) -> Bool:
  M.TicketType{name,time,flags}=value
  flag(flags,bit)
def channel_flag(value:M.TicketType,channel:M.Channel) -> Bool:
  match channel:
    case M.Loading{}: type_flag(value,2)
    case M.Simulation{}: type_flag(value,4)
def full_status_levels(level:U32) -> M.FullStatus:
  match level:
    case 32: M.BlockTicking{}
    case 33: M.Full{}
    case _: M.Inaccessible{}
def full_status_small(level:U32,small:Bool) -> M.FullStatus:
  match small:
    case True{}: M.EntityTicking{}
    case False{}: full_status_levels(level)
def full_status(+level:U32) -> M.FullStatus:
  full_status_small(level,Bool.not(int_less(31,level)))
def status_rank(status:M.FullStatus) -> U32:
  match status:
    case M.Inaccessible{}: 0
    case M.Full{}: 1
    case M.BlockTicking{}: 2
    case M.EntityTicking{}: 3
def status_equal(a:M.FullStatus,b:M.FullStatus) -> Bool:
  U32.is_eq(status_rank(a),status_rank(b))
def visibility(status:M.FullStatus) -> M.Visibility:
  match status:
    case M.Inaccessible{}: M.Hidden{}
    case M.EntityTicking{}: M.Ticking{}
    case _: M.Tracked{}
def can_tick(status:M.FullStatus) -> Bool:
  match status:
    case M.EntityTicking{}: True{}
    case _: False{}
def entities_loaded(phase:M.EntityPhase) -> Bool:
  match phase:
    case M.Loaded{request,artifact}: True{}
    case _: False{}
# ChunkTracker's eight neighbors add/subtract Java int coordinates. The
# unsigned words retain that wrapping coordinate metric, capped by the caller.
def axis_distance(+a:U32,+b:U32) -> U32: U32.min(U32.sub(a,b),U32.sub(b,a))
def distance(a:M.ChunkKey,b:M.ChunkKey) -> U32:
  M.ChunkKey{ax,az}=a
  M.ChunkKey{bx,bz}=b
  U32.max(axis_distance(ax,bx),axis_distance(az,bz))
