import Base
import ../src/entity_chunk_loading_model.bend as M
import ../src/entity_chunk_loading_math.bend as A
import ../src/entity_chunk_loading_tickets.bend as T

# Flat decimal input is representation plumbing only. All arithmetic, ticket
# mutations, source levels, timer eligibility and graph values call production.
type Command is Data:
  Command{mode:String,id:U32,key:M.ChunkKey,identity:String,time:M.Word64,
    flags:U32,level:U32,holder:U32}
def number_result(value:Maybe<&2,U32>) -> Result<&2,&2,String,U32>:
  match value:
    case Some{word}: Done{word}
    case None{}: Fail{"fixture expected an unsigned decimal word"}
def number(value:String) -> Result<&2,&2,String,U32>: number_result(U32.read(value))
def parsed(values:List<&2,String>) -> Result<&2,&2,String,Command>:
  match values:
    case mode <> id <> x <> z <> identity <> hi <> lo <> flags <> level <> holder <> Nil{}:
      do Result<&2,&2,String,Command>:
        id : U32 <- number(id)
        x : U32 <- number(x)
        z : U32 <- number(z)
        hi : U32 <- number(hi)
        lo : U32 <- number(lo)
        flags : U32 <- number(flags)
        level : U32 <- number(level)
        holder : U32 <- number(holder)
        return Command{mode,id,M.ChunkKey{x,z},identity,M.Word64{hi,lo},flags,level,holder}
    case _: Fail{"fixture expected exactly ten input fields"}
def bit(value:Bool) -> String:
  match value:
    case True{}: "1"
    case False{}: "0"
def words(value:M.Word64) -> String:
  M.Word64{hi,lo}=value
  U32.show(hi) ++ ":" ++ U32.show(lo)
def channel(value:M.Channel) -> String:
  match value:
    case M.Loading{}: "loading"
    case M.Simulation{}: "simulation"
def visibility(value:M.Visibility) -> String:
  match value:
    case M.Hidden{}: "HIDDEN"
    case M.Tracked{}: "TRACKED"
    case M.Ticking{}: "TICKING"
def status(value:M.FullStatus) -> String:
  match value:
    case M.Inaccessible{}: "INACCESSIBLE"
    case M.Full{}: "FULL"
    case M.BlockTicking{}: "BLOCK_TICKING"
    case M.EntityTicking{}: "ENTITY_TICKING"
def event(value:M.LoaderEvent) -> String:
  match value:
    case M.SourceLevelChanged{key,kind,level,decrease}:
      channel(kind) ++ ":" ++ U32.show(level) ++ ":" ++ bit(decrease)
    case _: "unexpected-event"
def event_values(values:List<&2,M.LoaderEvent>) -> List<&2,String>:
  match values:
    case Nil{}: []
    case head <> rest: event(head) <> event_values(rest)
def events(values:List<&2,M.LoaderEvent>) -> String:
  match values:
    case Nil{}: "-"
    case head <> rest: String.join(event(head) <> event_values(rest),",")
def store_text(id:U32,changed:Bool,+tickets:List<&2,M.Ticket>,effects:List<&2,M.LoaderEvent>) -> String:
  "store " ++ U32.show(id) ++ " " ++ bit(changed) ++ " " ++
    U32.show(T.source_level(tickets,M.Loading{},45)) ++ " " ++
    U32.show(T.source_level(tickets,M.Simulation{},45)) ++ " " ++
    Nat.show(List.length(&2,M.Ticket,tickets)) ++ " " ++ events(effects)
def stored(id:U32,+key:M.ChunkKey,buckets:List<&2,M.Bucket>,+before:List<&2,M.Ticket>,
    +kind:M.TicketType,+added:Bool,result:M.TicketsChanged) -> IO(List<&2,M.Bucket>):
  M.TicketsChanged{+tickets,+changed,loading,simulation}=result
  effects=T.direct_events(key,before,tickets,45,added,changed,
    A.choose(Bool,A.type_flag(kind,2),loading,added),A.choose(Bool,A.type_flag(kind,4),simulation,added))
  do IO<List<&2,M.Bucket>>:
    IO.print(store_text(id,changed,tickets,effects))
    return T.bucket_replace(buckets,key,tickets)
def silent(+key:M.ChunkKey,buckets:List<&2,M.Bucket>,result:M.TicketsChanged) -> List<&2,M.Bucket>:
  M.TicketsChanged{tickets,changed,loading,simulation}=result
  T.bucket_replace(buckets,key,tickets)
def holder(value:U32) -> Maybe<&2,M.HolderReadiness>:
  match value:
    case 0: None{}
    case 1: Some{M.AbsentHolder{}}
    case 2: Some{M.NotReadyForSaving{}}
    case _: Some{M.ReadyForSaving{}}
def purged(id:U32,+key:M.ChunkKey,buckets:List<&2,M.Bucket>,result:Result<&2,&2,String,M.TicketsChanged>) -> IO(List<&2,M.Bucket>):
  match result:
    case Fail{message}: IO.die(List<&2,M.Bucket>,3,message)
    case Done{M.TicketsChanged{+tickets,changed,loading,simulation}}:
      do IO<List<&2,M.Bucket>>:
        IO.print(store_text(id,changed,tickets,T.bulk_events(key,tickets,45,loading,simulation)))
        return T.bucket_replace(buckets,key,tickets)
def lifetime_purged(key:M.ChunkKey,buckets:List<&2,M.Bucket>,result:Result<&2,&2,String,M.TicketsChanged>) -> IO(List<&2,M.Bucket>):
  match result:
    case Fail{message}: IO.die(List<&2,M.Bucket>,3,message)
    case Done{M.TicketsChanged{tickets,changed,loading,simulation}}:
      IO.pure(List<&2,M.Bucket>,T.bucket_replace(buckets,key,tickets))
def life_head(id:U32,count:Nat,ticket:M.Ticket) -> String:
  M.Ticket{+kind,level,+left}=ticket
  "life " ++ U32.show(id) ++ " " ++ Nat.show(count) ++ " " ++ words(left) ++ " " ++
    bit(T.ticket_timed_out(M.Ticket{kind,level,left}))
def life(id:U32,+tickets:List<&2,M.Ticket>) -> String:
  match tickets:
    case Nil{}: "life " ++ U32.show(id) ++ " 0 - 0"
    case head <> rest: life_head(id,List.length(&2,M.Ticket,tickets),head)
def timer_text(id:U32,+before:M.Ticket,after:M.Ticket) -> String:
  M.Ticket{kind,level,left}=before
  M.Ticket{kind2,level2,+left2}=after
  "timer " ++ U32.show(id) ++ " " ++ words(left) ++ " " ++ bit(T.ticket_timed_out(before)) ++
    " " ++ words(left2) ++ " " ++ bit(T.ticket_timed_out(M.Ticket{kind2,level2,left2}))
def type_text(id:U32,+kind:M.TicketType) -> String:
  "type " ++ U32.show(id) ++ " " ++ bit(A.type_flag(kind,1)) ++ " " ++ bit(A.type_flag(kind,2)) ++
    " " ++ bit(A.type_flag(kind,4)) ++ " " ++ bit(A.type_flag(kind,8)) ++ " " ++
    bit(A.type_flag(kind,16)) ++ " " ++ bit(A.has_timeout(kind))
def level_text(id:U32,+level:U32) -> String:
  +actual=A.full_status(level)
  "level " ++ U32.show(id) ++ " " ++ status(actual) ++ " " ++ visibility(A.visibility(actual)) ++
    " " ++ bit(A.can_tick(actual))
def selected_channel(value:U32) -> M.Channel:
  match value:
    case 0: M.Loading{}
    case _: M.Simulation{}
def dispatch(command:Command,+buckets:List<&2,M.Bucket>) -> IO(List<&2,M.Bucket>):
  Command{mode,+id,+key,+identity,+time,+flags,+level,readiness}=command
  match mode:
    case "clear": IO.pure(List<&2,M.Bucket>,[])
    case "level":
      do IO<List<&2,M.Bucket>>:
        IO.print(level_text(id,level))
        return buckets
    case "type":
      do IO<List<&2,M.Bucket>>:
        IO.print(type_text(id,M.TicketType{identity,time,flags}))
        return buckets
    case "timer":
      +ticket=T.ticket_new(M.TicketType{identity,time,flags},level)
      do IO<List<&2,M.Bucket>>:
        IO.print(timer_text(id,ticket,T.decreased(ticket)))
        return buckets
    case "add":
      +kind : M.TicketType = M.TicketType{identity,time,flags}
      +before=T.bucket_tickets(buckets,key)
      stored(id,key,buckets,before,kind,True{},T.add_entries(before,T.ticket_new(kind,level)))
    case "remove":
      +kind : M.TicketType = M.TicketType{identity,time,flags}
      +before=T.bucket_tickets(buckets,key)
      stored(id,key,buckets,before,kind,False{},T.remove_entries(before,T.ticket_new(kind,level)))
    case "graph-add":
      IO.pure(List<&2,M.Bucket>,silent(key,buckets,T.add_entries(T.bucket_tickets(buckets,key),T.ticket_new(M.TicketType{identity,time,flags},level))))
    case "graph-remove":
      IO.pure(List<&2,M.Bucket>,silent(key,buckets,T.remove_entries(T.bucket_tickets(buckets,key),T.ticket_new(M.TicketType{identity,time,flags},level))))
    case "graph":
      do IO<List<&2,M.Bucket>>:
        IO.print("graph " ++ U32.show(id) ++ " " ++ U32.show(T.settled_level(buckets,key,selected_channel(flags),level)))
        return buckets
    case "purge": purged(id,key,buckets,T.purge_entries(T.bucket_tickets(buckets,key),holder(readiness)))
    case "lifetime-purge": lifetime_purged(key,buckets,T.purge_entries(T.bucket_tickets(buckets,key),holder(readiness)))
    case "life":
      do IO<List<&2,M.Bucket>>:
        IO.print(life(id,T.bucket_tickets(buckets,key)))
        return buckets
    case _: IO.die(List<&2,M.Bucket>,2,"fixture input mode is unknown")
def checked(result:Result<&2,&2,String,Command>,buckets:List<&2,M.Bucket>) -> IO(List<&2,M.Bucket>):
  match result:
    case Fail{message}: IO.die(List<&2,M.Bucket>,2,message)
    case Done{command}: dispatch(command,buckets)
def batch(lines:List<&2,String>,buckets:List<&2,M.Bucket>) -> IO(Unit):
  match lines:
    case Nil{}: IO.pure(Unit,Unit{})
    case "" <> rest: batch(rest,buckets)
    case line <> rest:
      do IO<Unit>:
        buckets : List<&2,M.Bucket> <- checked(parsed(String.split(line,Chr{32})),buckets)
        batch(rest,buckets)
def loaded(result:File & Result<&1,&1,U32 & String,String>) -> IO(String):
  (file,status)=result
  do IO<String>:
    File.close(file)
    IO.pass(String,status)
def read_file(path:String) -> IO(String):
  do IO<String>:
    file : File <- IO.try(File,File.open(path,"r"))
    result : File & Result<&1,&1,U32 & String,String> <- File.read(file,1048577)
    loaded(result)
def arguments(args:List<String>) -> IO(Unit):
  match args:
    case exe <> path <> Nil{}:
      do IO<Unit>:
        source : String <- read_file(path)
        batch(String.lines(source),[])
    case _: IO.die(Unit,2,"Expected one reference input file")
def main() -> IO(Unit): IO.bind(List<String>,Unit,IO.args(),arguments)
