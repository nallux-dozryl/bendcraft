import Base
import ./resource_client_wire.bend as Wire
import ./framing.bend as Framing
import ./resource_client_framing.bend as PrivateFraming
import ./client_presenter.bend as Common
import ./client_controls.bend as Controls
import ./window_input.bend as Input
import ./resource_frame.bend as RF
import ./world_resource_frame.bend as WRF
import ./world_visibility.bend as Visibility
import ./client_render.bend as Pixels
import ./client_world.bend as World
import ./movement.bend as Movement
import ./f64.bend as Double
import ./png.bend as PNG
import ./compression.bend as Checksum
import ./player_hud.bend as HUD
import ./player_inventory.bend as Inventory
import ./block_resources.bend as Resources
import ./player_presentation.bend as Presentation
import ./player_presentation_native.bend as NativePresentation
import ./player_inventory_screen.bend as Screen
import ./player_menu_input.bend as MenuInput
import ./player_item_definitions.bend as ItemDefinitions
import ./player_item_catalog.bend as ItemCatalog
import ./inventory_key_consumer.bend as Keys

# This process owns textures, one private connection and one Window. The only
# world authority is the peer's saved LocalPlayer actor; no driver/actor handle
# or persistence owner enters these presentation continuations.
type Link is Type:
  Dead{message:String}
  Open{socket:Socket,buffer:Framing.Buffer,pending:List<&2,String>,epoch:String,sequence:Nat}
type Receive is Type:
  Again{link:Link}
  Received{link:Link,value:Result<&2,&2,String,Wire.Reply>}
type Config is Data:
  Config{human:Bool,frames:Maybe<&2,Nat>,width:U32,height:U32,
    trace:Maybe<&2,String>,serial:Nat,plan:Presentation.Plan,started:U32,menu:MenuInput.State,keys:Keys.Profile,physical_keys:Bool}

type MenuResult is Type:
  MenuResult{window:Window,link:Link,state:MenuInput.State,keep:Bool,status:Result<&2,&2,String,Unit>}

def menu_state(config:Config) -> MenuInput.State:
  Config{human,frames,width,height,trace,serial,plan,started,menu,keys,physical_keys} = config
  menu

def with_menu(config:Config,menu:MenuInput.State) -> Config:
  Config{human,frames,width,height,trace,serial,plan,started,previous,keys,physical_keys} = config
  Config{human,frames,width,height,trace,serial,plan,started,menu,keys,physical_keys}
def presentation_width(human:Bool,logical:U32) -> U32:
  HUD.presentation_width(human,logical)

def presentation_height(human:Bool,logical:U32) -> U32:
  HUD.presentation_height(human,logical)

def close_link(link:Link) -> IO(Unit):
  match link:
    case Dead{message}: IO.pure(Unit,Unit{})
    case Open{socket,buffer,pending,epoch,sequence}: Socket.close(socket)

def failure(socket:Socket,+message:String) -> IO(Link & Result<&2,&2,String,Wire.Reply>):
  do IO<Link & Result<&2,&2,String,Wire.Reply>>:
    Socket.close(socket)
    return (Dead{message},Fail{message})

# TCP.poll's String decoder is safe for the deliberately ASCII wire domain:
# raw non-ASCII bytes produce non-ASCII scalars and are rejected. Unicode text
# in protocol fields is escaped by Wire, so a multi-byte boundary is never an
# admitted record. Existing Framing still counts/validates the actual ASCII.
def ascii_head(valid:Bool,value:U32,tail:Result<&2,&2,String,List<&2,U32>>) -> Result<&2,&2,String,List<&2,U32>>:
  match valid:
    case False{}: Fail{"Wire:RawNonASCII"}
    case True{}:
      do Result<&2,&2,String,List<&2,U32>>:
        rest : List<&2,U32> <- tail
        Done{value <> rest}

def ascii_bytes(text:String) -> Result<&2,&2,String,List<&2,U32>>:
  match text:
    case SNil{}: Done{[]}
    case SCon{Chr{+value},tail}: ascii_head(U32.is_lt(value,128),value,ascii_bytes(tail))

def decoded(socket:Socket,buffer:Framing.Buffer,pending:List<&2,String>,epoch:String,sequence:Nat,
    result:Result<&2,&2,String,Wire.Reply>) -> IO(Link & Result<&2,&2,String,Wire.Reply>):
  match result:
    case Fail{message}: failure(socket,"Wire:Decode:" ++ message)
    case Done{reply}: IO.pure(Link & Result<&2,&2,String,Wire.Reply>,(Open{socket,buffer,pending,epoch,sequence},Done{reply}))

def framed(socket:Socket,epoch:String,sequence:Nat,value:Result<&1,&1,String,Framing.Buffer & List<&2,String>>) -> IO(Receive):
  match value:
    case Fail{message}:
      do IO<Receive>:
        result : Link & Result<&2,&2,String,Wire.Reply> <- failure(socket,"Wire:Frame:" ++ message)
        PNG.paired(Link,Result<&2,&2,String,Wire.Reply>,IO(Receive),result,link => status => IO.pure(Receive,Received{link,status}))
    case Done{Tuple{buffer,pending}}: IO.pure(Receive,Again{Open{socket,buffer,pending,epoch,sequence}})

def polled_ascii(socket:Socket,buffer:Framing.Buffer,epoch:String,sequence:Nat,value:Result<&2,&2,String,List<&2,U32>>) -> IO(Receive):
  match value:
    case Fail{message}:
      do IO<Receive>:
        result : Link & Result<&2,&2,String,Wire.Reply> <- failure(socket,message)
        PNG.paired(Link,Result<&2,&2,String,Wire.Reply>,IO(Receive),result,link => status => IO.pure(Receive,Received{link,status}))
    case Done{bytes}: framed(socket,epoch,sequence,PrivateFraming.feed(buffer,bytes))

def polled(buffer:Framing.Buffer,epoch:String,sequence:Nat,result:Socket & Result<&1,&1,U32 & String,Maybe<&1,String>>) -> IO(Receive):
  (socket,status) = result
  match status:
    case Done{Some{SCon{head,tail}}}: polled_ascii(socket,buffer,epoch,sequence,ascii_bytes(SCon{head,tail}))
    case _:
      do IO<Receive>:
        result : Link & Result<&2,&2,String,Wire.Reply> <- failure(socket,"Wire:ReceiveClosedFailedOrTimedOut")
        PNG.paired(Link,Result<&2,&2,String,Wire.Reply>,IO(Receive),result,link => failed => IO.pure(Receive,Received{link,failed}))

def polled_room(room:Bool,buffer:Framing.Buffer,epoch:String,sequence:Nat,
    result:Socket & Result<&1,&1,U32 & String,Maybe<&1,String>>) -> IO(Receive):
  match room:
    case True{}: polled(buffer,epoch,sequence,result)
    case False{}:
      PNG.paired(Socket,Result<&1,&1,U32 & String,Maybe<&1,String>>,IO(Receive),result,
        socket => status =>
          do IO<Receive>:
            result : Link & Result<&2,&2,String,Wire.Reply> <- failure(socket,"Wire:ResponseDeadline")
            PNG.paired(Link,Result<&2,&2,String,Wire.Reply>,IO(Receive),result,
              link => failed => IO.pure(Receive,Received{link,failed})))

@unsafe
def receive_next(step:Receive,deadline:Nat) -> IO(Link & Result<&2,&2,String,Wire.Reply>):
  match step:
    case Received{link,status}: IO.pure(Link & Result<&2,&2,String,Wire.Reply>,(link,status))
    case Again{link}: receive(link,deadline)

def receive_room(link:Link,+deadline:Nat,+now:Nat,room:Bool) -> IO(Link & Result<&2,&2,String,Wire.Reply>):
  match link room:
    case Open{socket,buffer,pending,epoch,sequence} False{}: failure(socket,"Wire:ResponseDeadline")
    case Open{socket,buffer,pending,epoch,sequence} True{}:
      do IO<Link & Result<&2,&2,String,Wire.Reply>>:
        bytes : Socket & Result<&1,&1,U32 & String,Maybe<&1,String>> <- TCP.poll(socket,8192,U32.from_nat(Nat.sub(deadline,now)))
        after : Nat <- IO.now()
        step : Receive <- polled_room(Nat.is_lt(after,deadline),buffer,epoch,sequence,bytes)
        receive_next(step,deadline)
    case Dead{+message} _: IO.pure(Link & Result<&2,&2,String,Wire.Reply>,(Dead{message},Fail{message}))

@unsafe
def receive(link:Link,+deadline:Nat) -> IO(Link & Result<&2,&2,String,Wire.Reply>):
  match link:
    case Dead{+message}: IO.pure(Link & Result<&2,&2,String,Wire.Reply>,(Dead{message},Fail{message}))
    case Open{socket,buffer,line <> pending,epoch,sequence}: decoded(socket,buffer,pending,epoch,sequence,Wire.decode_reply(line))
    case Open{socket,buffer,Nil{},epoch,sequence}:
      do IO<Link & Result<&2,&2,String,Wire.Reply>>:
        +now : Nat <- IO.now()
        receive_room(Open{socket,buffer,[],epoch,sequence},deadline,now,Nat.is_lt(now,deadline))

def reply_boundary(buffer:Framing.Buffer,pending:List<&2,String>) -> Bool:
  Framing.Buffer{reversed,size} = buffer
  U32.is_eq(size,0) && List.is_empty(&2,U32,reversed) && List.is_empty(&2,String,pending)

def correlation_gate(valid:Bool,socket:Socket,buffer:Framing.Buffer,epoch:String,sequence:Nat,reply:Wire.Reply) -> IO(Link & Result<&2,&2,String,Wire.Reply>):
  match valid:
    case False{}: failure(socket,"Wire:Correlation")
    case True{}: IO.pure(Link & Result<&2,&2,String,Wire.Reply>,(Open{socket,buffer,[],epoch,sequence},Done{reply}))

def fault_correlated(valid:Bool,socket:Socket,message:String) -> IO(Link & Result<&2,&2,String,Wire.Reply>):
  match valid:
    case False{}: failure(socket,"Wire:Correlation")
    case True{}: failure(socket,"Wire:Peer:" ++ message)

def correlated_reply(+epoch:String,+sequence:Nat,socket:Socket,buffer:Framing.Buffer,current:String,next:Nat,+reply:Wire.Reply,clean:Bool) -> IO(Link & Result<&2,&2,String,Wire.Reply>):
  match reply clean:
    case Wire.HelloAck{assigned,zero} True{}:
      correlation_gate(String.eq(epoch,"") && Nat.is_eq(sequence,0n) && Nat.is_eq(zero,0n),socket,buffer,assigned,1n,reply)
    case Wire.FrameReply{actual,seq,sample} True{}:
      correlation_gate(String.eq(epoch,actual) && Nat.is_eq(sequence,seq),socket,buffer,current,next,reply)
    case Wire.Ack{actual,seq} True{}:
      correlation_gate(String.eq(epoch,actual) && Nat.is_eq(sequence,seq),socket,buffer,current,next,reply)
    case Wire.InventoryReply{actual,seq,inventory} True{}:
      correlation_gate(String.eq(epoch,actual) && Nat.is_eq(sequence,seq),socket,buffer,current,next,reply)
    case Wire.ActionReply{actual,seq,changed,message} True{}:
      correlation_gate(String.eq(epoch,actual) && Nat.is_eq(sequence,seq),socket,buffer,current,next,reply)
    case Wire.MenuReply{actual,seq,accepted,message,snapshot} True{}:
      correlation_gate(String.eq(epoch,actual) && Nat.is_eq(sequence,seq),socket,buffer,current,next,reply)
    case Wire.Fault{actual,seq,message} True{}:
      fault_correlated(String.eq(epoch,actual) && Nat.is_eq(sequence,seq),socket,message)
    case _ _: failure(socket,"Wire:Unsolicited")

def correlated(epoch:String,sequence:Nat,result:Link & Result<&2,&2,String,Wire.Reply>) -> IO(Link & Result<&2,&2,String,Wire.Reply>):
  (link,status) = result
  match link status:
    case Dead{+message} _: IO.pure(Link & Result<&2,&2,String,Wire.Reply>,(Dead{message},Fail{message}))
    case Open{socket,buffer,pending,current,next} Fail{message}: failure(socket,message)
    case Open{socket,+buffer,+pending,current,next} Done{reply}:
      correlated_reply(epoch,sequence,socket,buffer,current,next,reply,reply_boundary(buffer,pending))

def response_expired(link:Link,status:Result<&2,&2,String,Wire.Reply>) -> IO(Link & Result<&2,&2,String,Wire.Reply>):
  match link:
    case Dead{+message}: IO.pure(Link & Result<&2,&2,String,Wire.Reply>,(Dead{message},Fail{message}))
    case Open{socket,buffer,pending,current,next}: failure(socket,"Wire:ResponseDeadline")

def response_room(room:Bool,epoch:String,sequence:Nat,result:Link & Result<&2,&2,String,Wire.Reply>) -> IO(Link & Result<&2,&2,String,Wire.Reply>):
  match room:
    case True{}: correlated(epoch,sequence,result)
    case False{}:
      PNG.paired(Link,Result<&2,&2,String,Wire.Reply>,IO(Link & Result<&2,&2,String,Wire.Reply>),result,
        link => status => response_expired(link,status))

def sent(buffer:Framing.Buffer,epoch:String,sequence:Nat,+expected:String,+seq:Nat,+deadline:Nat,
    result:Socket & Result<&1,&1,U32 & String,Unit>) -> IO(Link & Result<&2,&2,String,Wire.Reply>):
  (socket,status) = result
  match status:
    case Fail{error}: failure(socket,"Wire:Send")
    case Done{unit}:
      do IO<Link & Result<&2,&2,String,Wire.Reply>>:
        reply : Link & Result<&2,&2,String,Wire.Reply> <- receive(Open{socket,buffer,[],epoch,sequence},deadline)
        after : Nat <- IO.now()
        response_room(Nat.is_lt(after,deadline),expected,seq,reply)

def send_text(link:Link,expected:String,seq:Nat,encoded:Result<&2,&2,String,String>) -> IO(Link & Result<&2,&2,String,Wire.Reply>):
  match link encoded:
    case Dead{+message} _: IO.pure(Link & Result<&2,&2,String,Wire.Reply>,(Dead{message},Fail{message}))
    case Open{socket,buffer,Nil{},epoch,sequence} Done{text}:
      do IO<Link & Result<&2,&2,String,Wire.Reply>>:
        now : Nat <- IO.now()
        result : Socket & Result<&1,&1,U32 & String,Unit> <- TCP.send(socket,text ++ "\n")
        sent(buffer,epoch,sequence,expected,seq,5000n+now,result)
    case Open{socket,buffer,pending,epoch,sequence} Fail{message}: failure(socket,"Wire:Encode:" ++ message)
    case Open{socket,buffer,pending,epoch,sequence} Done{text}: failure(socket,"Wire:Unsolicited")

def call(link:Link,command:Wire.Command) -> IO(Link & Result<&2,&2,String,Wire.Reply>):
  match link:
    case Dead{+message}: IO.pure(Link & Result<&2,&2,String,Wire.Reply>,(Dead{message},Fail{message}))
    case Open{socket,buffer,pending,+epoch,+sequence}:
      send_text(Open{socket,buffer,pending,epoch,1n+sequence},epoch,sequence,Wire.encode_request(Wire.Call{epoch,sequence,command}))

def hello(capability:String,result:Result<&1,&1,U32 & String,Socket>) -> IO(Link & Result<&2,&2,String,Wire.Reply>):
  match result:
    case Fail{cause}: IO.pure(Link & Result<&2,&2,String,Wire.Reply>,(Dead{"Wire:Connect"},Fail{"Wire:Connect"}))
    case Done{socket}: send_text(Open{socket,Framing.new(),[],"",0n},"",0n,Wire.encode_request(Wire.Hello{capability}))

def connect(port:U32,capability:String) -> IO(Link & Result<&2,&2,String,Wire.Reply>):
  do IO<Link & Result<&2,&2,String,Wire.Reply>>:
    result : Result<&1,&1,U32 & String,Socket> <- TCP.connect("127.0.0.1",port)
    hello(capability,result)

def close_released(result:Link & Result<&2,&2,String,Wire.Reply>) -> IO(Unit):
  (link,status) = result
  close_link(link)

def release_close(link:Link) -> IO(Unit):
  do IO<Unit>:
    result : Link & Result<&2,&2,String,Wire.Reply> <- call(link,Wire.Release{})
    close_released(result)

def trace_mode(result:Result<&1,&1,U32 & String,String>) -> Maybe<&2,String>:
  match result:
    case Fail{cause}: None{}
    case Done{""}: None{}
    case Done{path}: Some{path}

def trace_status(status:Result<&1,&1,U32 & String,Unit>) -> Result<&2,&2,String,Unit>:
  match status:
    case Fail{(code,message)}: Fail{"frame readback: " ++ message}
    case Done{unit}: Done{unit}

def trace_closed(result:File & Result<&1,&1,U32 & String,Unit>) -> IO(Result<&2,&2,String,Unit>):
  (file,status) = result
  do IO<Result<&2,&2,String,Unit>>:
    File.close(file)
    return trace_status(status)

def trace_header(file:File,+bytes:List<&2,U32>,status:Result<&1,&1,U32 & String,Unit>) -> IO(Result<&2,&2,String,Unit>):
  match status:
    case Fail{cause}: trace_closed((file,Fail{cause}))
    case Done{unit}:
      do IO<Result<&2,&2,String,Unit>>:
        written : File & Result<&1,&1,U32 & String,Unit> <- File.write_bytes(file,bytes)
        trace_closed(written)

def trace_opened(+image:Image,+width:U32,+height:U32,result:Result<&1,&1,U32 & String,File>) -> IO(Result<&2,&2,String,Unit>):
  match result:
    case Fail{(code,message)}: IO.pure(Result<&2,&2,String,Unit>,Fail{"frame readback: " ++ message})
    case Done{file}:
      do IO<Result<&2,&2,String,Unit>>:
        header : File & Result<&1,&1,U32 & String,Unit> <- File.write(file,"P6\n" ++ U32.show(width) ++ " " ++ U32.show(height) ++ "\n255\n")
        PNG.paired(File,Result<&1,&1,U32 & String,Unit>,IO(Result<&2,&2,String,Unit>),header,
          file => status => trace_header(file,Pixels.ppm_bytes_go(Pixels.pixels_of(image,width,height),[]),status))

def trace_write(path:String,+image:Image,+width:U32,+height:U32) -> IO(Result<&2,&2,String,Unit>):
  do IO<Result<&2,&2,String,Unit>>:
    opened : Result<&1,&1,U32 & String,File> <- File.open(path,"w")
    trace_opened(image,width,height,opened)

def trace(image:Image,config:Config) -> IO(Result<&2,&2,String,Unit>):
  Config{human,frames,width,height,mode,serial,+plan,started,menu,keys,physical_keys} = config
  match mode:
    case None{}: IO.pure(Result<&2,&2,String,Unit>,Done{Unit{}})
    case Some{directory}: trace_write(directory ++ "/" ++ Nat.show(serial) ++ ".ppm",image,
      Presentation.output_width(plan),Presentation.output_height(plan))

def words(values:List<&2,U32>) -> String:
  match values:
    case Nil{}: ""
    case [value]: U32.show(value)
    case value <> tail: U32.show(value) ++ "," ++ words(tail)

def block_rows(values:List<&2,Pixels.Block>) -> String:
  match values:
    case Nil{}: ""
    case Pixels.Block{x,y,z,state,material} <> tail:
      words([F32.bits(x),F32.bits(y),F32.bits(z),state,material]) ++ ";" ++ block_rows(tail)

def raw_rows(values:List<&2,World.RawBlock>) -> String:
  match values:
    case Nil{}: ""
    case World.RawBlock{World.Cell{x,y,z,boundary},state,material} <> tail:
      words([x,y,z,boundary,state,material]) ++ ";" ++ raw_rows(tail)

def mask_rows(values:List<&2,Visibility.Visibility>) -> String:
  match values:
    case Nil{}: ""
    case Visibility.Visibility{World.Cell{x,y,z,boundary},state,visible} <> tail:
      words([x,y,z,boundary,state,visible]) ++ ";" ++ mask_rows(tail)

def sample_line(serial:Nat,sample:Visibility.Sample) -> String:
  Visibility.Sample{Pixels.Snapshot{tick,revision,blocks,Pixels.Camera{x,y,z,yaw,pitch}},raw,masks,
    Movement.Vec3{Double.F64{xh,xl},Double.F64{yh,yl},Double.F64{zh,zl}},
    World.Palette{air,stone,dirt,planks},reads} = sample
  "resource.sample|" ++ Nat.show(serial) ++ "|" ++ Nat.show(tick) ++ "|" ++ Nat.show(revision) ++ "|" ++
    words([F32.bits(x),F32.bits(y),F32.bits(z),F32.bits(yaw),F32.bits(pitch)]) ++ "|" ++
    words([xh,xl,yh,yl,zh,zl]) ++ "|" ++ words([air,stone,dirt,planks]) ++ "|" ++ U32.show(reads) ++ "|" ++
    block_rows(blocks) ++ "|" ++ raw_rows(raw) ++ "|" ++ mask_rows(masks)

def sample_description(sample:Visibility.Sample,serial:Nat,mode:Maybe<&2,String>) -> IO(Unit):
  match mode:
    case None{}: IO.pure(Unit,Unit{})
    case Some{directory}: IO.print(sample_line(serial,sample))

def frame_description(+sample:Visibility.Sample,config:Config) -> IO(Unit):
  Visibility.Sample{Pixels.Snapshot{tick,revision,+blocks,Pixels.Camera{x,y,z,yaw,pitch}},raw,masks,origin,palette,reads} = sample
  Config{human,frames,+width,+height,mode,serial,+plan,started,menu,keys,physical_keys} = config
  do IO<Unit>:
    IO.print("{\"event\":\"client.frame\",\"renderer\":\"remote-local-resource-instrument\",\"tick\":" ++ Nat.show(tick) ++
      ",\"revision\":" ++ Nat.show(revision) ++ ",\"blocks\":" ++ Nat.show(List.length(&2,Pixels.Block,blocks)) ++
      ",\"neighbor_reads\":" ++ U32.show(reads) ++ ",\"yaw_f32\":" ++ U32.show(F32.bits(yaw)) ++ ",\"pitch_f32\":" ++ U32.show(F32.bits(pitch)) ++
      ",\"logical_width\":" ++ U32.show(width) ++ ",\"logical_height\":" ++ U32.show(height) ++
      ",\"presentation_width\":" ++ U32.show(Presentation.output_width(plan)) ++
      ",\"presentation_height\":" ++ U32.show(Presentation.output_height(plan)) ++
      ",\"hud_width\":" ++ U32.show(Presentation.hud_width(plan)) ++ ",\"hud_height\":" ++ U32.show(Presentation.hud_height(plan)) ++
      ",\"scene_backing_pixels\":" ++ U32.show(Presentation.backing_pixels(width,height)) ++
      ",\"output_backing_pixels\":" ++ U32.show(Presentation.backing_pixels(Presentation.output_width(plan),Presentation.output_height(plan))) ++ "}")
    sample_description(sample,serial,mode)

def image_description(+image:Image,config:Config) -> IO(Unit):
  Config{human,frames,width,height,mode,serial,+plan,started,menu,keys,physical_keys} = config
  match mode:
    case None{}: IO.pure(Unit,Unit{})
    case Some{directory}:
      +present_width = Presentation.output_width(plan)
      +present_height = Presentation.output_height(plan)
      IO.print("resource.image|" ++ Nat.show(serial) ++ "|" ++ U32.show(present_width) ++ "|" ++ U32.show(present_height) ++ "|" ++ U32.show(Checksum.crc32(PNG.rgba_bytes(Pixels.pixels_of(image,present_width,present_height)))))

def closing(window:Window,assets:RF.Assets,link:Link,code:U32,message:String) -> IO(Unit):
  do IO<Unit>:
    Window.close(window)
    RF.close_assets(assets)
    release_close(link)
    IO.die(Unit,code,message)

def advance(config:Config) -> Config:
  Config{human,frames,width,height,trace,serial,+plan,started,menu,keys,physical_keys} = config
  Config{human,Common.remaining(frames),width,height,trace,1n+serial,plan,started,menu,keys,physical_keys}

def scheduled(window:Window,assets:RF.Assets,link:Link,config:Config,captured:Bool,keep:Bool,
    resume:Window -> RF.Assets -> Link -> Config -> Bool -> IO(Unit)) -> IO(Unit):
  match keep:
    case False{}: closing(window,assets,link,0,"client closed")
    case True{}:
      do IO<Unit>:
        IO.sleep(8)
        resume(window,assets,link,config,captured)

def packet_advance(window:Window,assets:RF.Assets,link:Link,+next:Config,captured:Bool,keep:Bool,
    resume:Window -> RF.Assets -> Link -> Config -> Bool -> IO(Unit)) -> IO(Unit):
  Config{human,frames,width,height,trace,serial,+plan,started,menu,keys,physical_keys} = next
  scheduled(window,assets,link,next,captured,keep && Common.continuing(frames),resume)

def describe_command(command:Wire.Command,status:Result<&2,&2,String,Wire.Reply>) -> IO(Unit):
  match command status:
    case Wire.Action{button} Done{Wire.ActionReply{epoch,sequence,changed,message}}:
      IO.print("client.action|" ++ Nat.show(sequence) ++ "|" ++ Bool.show(changed) ++ "|" ++ message)
    case _ _: IO.pure(Unit,Unit{})

def command_continue(rest:List<&2,Wire.Command>,link:Link,status:Result<&2,&2,String,Unit>,
    continue:List<&2,Wire.Command> -> Link -> IO(Link & Result<&2,&2,String,Unit>)) -> IO(Link & Result<&2,&2,String,Unit>):
  match status:
    case Fail{message}: IO.pure(Link & Result<&2,&2,String,Unit>,(link,Fail{message}))
    case Done{unit}: continue(rest,link)

def command_sent(+command:Wire.Command,rest:List<&2,Wire.Command>,+status:Result<&2,&2,String,Wire.Reply>,link:Link,
    continue:List<&2,Wire.Command> -> Link -> IO(Link & Result<&2,&2,String,Unit>)) -> IO(Link & Result<&2,&2,String,Unit>):
  do IO<Link & Result<&2,&2,String,Unit>>:
    describe_command(command,status)
    command_continue(rest,link,HUD.command_result(command,status),continue)

def command_pair(command:Wire.Command,rest:List<&2,Wire.Command>,result:Link & Result<&2,&2,String,Wire.Reply>,
    continue:List<&2,Wire.Command> -> Link -> IO(Link & Result<&2,&2,String,Unit>)) -> IO(Link & Result<&2,&2,String,Unit>):
  (link,status) = result
  command_sent(command,rest,status,link,continue)

@unsafe
def send_commands(commands:List<&2,Wire.Command>,link:Link) -> IO(Link & Result<&2,&2,String,Unit>):
  match commands:
    case Nil{}: IO.pure(Link & Result<&2,&2,String,Unit>,(link,Done{Unit{}}))
    case +command <> rest:
      do IO<Link & Result<&2,&2,String,Unit>>:
        result : Link & Result<&2,&2,String,Wire.Reply> <- call(link,command)
        command_pair(command,rest,result,tail => peer => send_commands(tail,peer))

def commands_sent(window:Window,assets:RF.Assets,config:Config,captured:Bool,keep:Bool,
    result:Link & Result<&2,&2,String,Unit>,resume:Window -> RF.Assets -> Link -> Config -> Bool -> IO(Unit)) -> IO(Unit):
  (link,status) = result
  match status:
    case Done{unit}: packet_advance(window,assets,link,advance(config),captured,keep,resume)
    case Fail{message}: closing(window,assets,link,1,"game command: " ++ message)

def packet_sent(window:Window,assets:RF.Assets,config:Config,captured:Bool,keep:Bool,commands:List<&2,Wire.Command>,
    result:Link & Result<&2,&2,String,Wire.Reply>,resume:Window -> RF.Assets -> Link -> Config -> Bool -> IO(Unit)) -> IO(Unit):
  (link,status) = result
  match status:
    case Done{Wire.Ack{epoch,sequence}}:
      do IO<Unit>:
        sent : Link & Result<&2,&2,String,Unit> <- send_commands(commands,link)
        commands_sent(window,assets,config,captured,keep,sent,resume)
    case Done{other}: closing(window,assets,link,1,"input: Wire:ExpectedAck")
    case Fail{message}: closing(window,assets,link,1,"input: " ++ message)

def packet_flags(assets:RF.Assets,link:Link,config:Config,old:Bool,previous_capture:Bool,keep:Bool,actions:List<&2,Controls.Action>,
    window:Window,+focused:Bool,+captured:Bool,resume:Window -> RF.Assets -> Link -> Config -> Bool -> IO(Unit)) -> IO(Unit):
  +packet = {Controls.Packet{List.reverse(&2,Controls.Action,
    Common.lost_actions(actions,old && Bool.not(focused && captured))),focused,captured}:Controls.Packet}
  do IO<Unit>:
    sent : Link & Result<&2,&2,String,Wire.Reply> <- call(link,Wire.Input{packet})
    packet_sent(window,assets,config,focused && captured,keep,HUD.packet_commands(packet,previous_capture),sent,resume)

def packet_final(assets:RF.Assets,link:Link,config:Config,old:Bool,previous_capture:Bool,keep:Bool,actions:List<&2,Controls.Action>,
    result:Window & Bool & Bool,resume:Window -> RF.Assets -> Link -> Config -> Bool -> IO(Unit)) -> IO(Unit):
  (window,focused,captured) = result
  packet_flags(assets,link,config,old,previous_capture,keep,actions,window,focused,captured,resume)

def packet_events(assets:RF.Assets,link:Link,config:Config,previous_capture:Bool,result:Window & Bool & Bool & List<&2,Controls.Action>,
    resume:Window -> RF.Assets -> Link -> Config -> Bool -> IO(Unit)) -> IO(Unit):
  (window,captured,keep,actions) = result
  do IO<Unit>:
    status : Window & Bool & Bool <- Input.Native.status(window)
    packet_final(assets,link,config,captured,previous_capture,keep,actions,status,resume)

def packet_initial_flags(assets:RF.Assets,link:Link,config:Config,pending:List<Event>,allow:Bool,old:Bool,
    window:Window,+focused:Bool,+captured:Bool,resume:Window -> RF.Assets -> Link -> Config -> Bool -> IO(Unit)) -> IO(Unit):
  do IO<Unit>:
    events : Window & Bool & Bool & List<&2,Controls.Action> <- Common.events(pending,window,allow,focused && captured,True{},Common.lost_actions([],old && Bool.not(focused && captured)))
    packet_events(assets,link,config,focused && captured,events,resume)

def packet_initial(assets:RF.Assets,link:Link,config:Config,pending:List<Event>,allow:Bool,old:Bool,
    result:Window & Bool & Bool,resume:Window -> RF.Assets -> Link -> Config -> Bool -> IO(Unit)) -> IO(Unit):
  (window,focused,captured) = result
  packet_initial_flags(assets,link,config,pending,allow,old,window,focused,captured,resume)

def menu_completed(window:Window,link:Link,rest:List<&2,Screen.Intent>,human:Bool,keep:Bool,
    sequence:Nat,accepted:Bool,message:String,result:MenuInput.State & List<&2,Screen.Intent>,
    continue:List<&2,Screen.Intent> -> Window -> Link -> MenuInput.State -> Bool -> Bool -> IO(MenuResult)) -> IO(MenuResult):
  (next,following) = result
  do IO<MenuResult>:
    IO.print("client.menu|" ++ Nat.show(sequence) ++ "|" ++ Bool.show(accepted) ++ "|" ++ message)
    continue(List.append(&2,Screen.Intent,following,rest),window,link,next,human,keep)

def menu_reply(window:Window,+state:MenuInput.State,rest:List<&2,Screen.Intent>,human:Bool,keep:Bool,
    result:Link & Result<&2,&2,String,Wire.Reply>,
    continue:List<&2,Screen.Intent> -> Window -> Link -> MenuInput.State -> Bool -> Bool -> IO(MenuResult)) -> IO(MenuResult):
  (link,status) = result
  match status:
    case Fail{message}: IO.pure(MenuResult,MenuResult{window,link,state,keep,Fail{message}})
    case Done{Wire.MenuReply{epoch,sequence,+accepted,message,snapshot}}:
      menu_completed(window,link,rest,human,keep,sequence,accepted,message,
        MenuInput.completed(state,snapshot,accepted),continue)
    case Done{other}: IO.pure(MenuResult,MenuResult{window,link,state,keep,Fail{"Wire:ExpectedMenuReply"}})

def menu_command(command:Maybe<&2,Wire.Command>,window:Window,link:Link,state:MenuInput.State,
    rest:List<&2,Screen.Intent>,human:Bool,keep:Bool,
    continue:List<&2,Screen.Intent> -> Window -> Link -> MenuInput.State -> Bool -> Bool -> IO(MenuResult)) -> IO(MenuResult):
  match command:
    case None{}: IO.pure(MenuResult,MenuResult{window,link,state,keep,Fail{"unsupported menu intent"}})
    case Some{value}:
      do IO<MenuResult>:
        result : Link & Result<&2,&2,String,Wire.Reply> <- call(link,value)
        menu_reply(window,state,rest,human,keep,result,continue)

def menu_release(window:Window,state:MenuInput.State,rest:List<&2,Screen.Intent>,human:Bool,keep:Bool,
    result:Link & Result<&2,&2,String,Wire.Reply>,
    continue:List<&2,Screen.Intent> -> Window -> Link -> MenuInput.State -> Bool -> Bool -> IO(MenuResult)) -> IO(MenuResult):
  (link,status) = result
  match status:
    case Done{Wire.Ack{epoch,sequence}}: continue(rest,window,link,state,human,keep)
    case Fail{message}: IO.pure(MenuResult,MenuResult{window,link,state,keep,Fail{message}})
    case Done{other}: IO.pure(MenuResult,MenuResult{window,link,state,keep,Fail{"Wire:ExpectedReleaseInputAck"}})

def menu_captured(link:Link,state:MenuInput.State,rest:List<&2,Screen.Intent>,human:Bool,keep:Bool,
    result:Window & Bool,
    continue:List<&2,Screen.Intent> -> Window -> Link -> MenuInput.State -> Bool -> Bool -> IO(MenuResult)) -> IO(MenuResult):
  (window,captured) = result
  continue(rest,window,link,state,human,keep)

def menu_capture_status(link:Link,state:MenuInput.State,rest:List<&2,Screen.Intent>,+human:Bool,keep:Bool,enabled:Bool,
    result:Window & Bool & Bool,
    continue:List<&2,Screen.Intent> -> Window -> Link -> MenuInput.State -> Bool -> Bool -> IO(MenuResult)) -> IO(MenuResult):
  (window,focused,captured) = result
  do IO<MenuResult>:
    actual : Window & Bool <- Input.capture(window,human && enabled && focused)
    menu_captured(link,state,rest,human,keep,actual,continue)

@unsafe
def send_menu_intents(intents:List<&2,Screen.Intent>,window:Window,link:Link,state:MenuInput.State,+human:Bool,keep:Bool) -> IO(MenuResult):
  match intents:
    case Nil{}: IO.pure(MenuResult,MenuResult{window,link,state,keep,Done{Unit{}}})
    case Screen.ReleaseControls{} <> rest:
      do IO<MenuResult>:
        result : Link & Result<&2,&2,String,Wire.Reply> <- call(link,Wire.Release{})
        menu_release(window,state,rest,human,keep,result,tail => w => l => s => h => k => send_menu_intents(tail,w,l,s,h,k))
    case Screen.Capture{enabled} <> rest:
      do IO<MenuResult>:
        status : Window & Bool & Bool <- Input.Native.status(window)
        menu_capture_status(link,state,rest,human,keep,enabled,status,
          tail => w => l => s => h => k => send_menu_intents(tail,w,l,s,h,k))
    case Screen.Quit{} <> rest: IO.pure(MenuResult,MenuResult{window,link,state,False{},Done{Unit{}}})
    case intent <> rest:
      menu_command(MenuInput.wire(intent),window,link,state,rest,human,keep,
        tail => w => l => s => h => k => send_menu_intents(tail,w,l,s,h,k))

def menu_events_sent(assets:RF.Assets,+config:Config,pending:List<Event>,old:Bool,result:MenuResult,
    resume:Window -> RF.Assets -> Link -> Config -> Bool -> IO(Unit)) -> IO(Unit):
  Config{+human,frames,width,height,trace,serial,plan,started,previous,keys,physical_keys} = config
  match result:
    case MenuResult{window,link,state,False{},Done{unit}}: closing(window,assets,link,0,"client closed")
    case MenuResult{window,link,+state,True{},Done{unit}}:
      do IO<Unit>:
        status : Window & Bool & Bool <- Input.Native.status(window)
        packet_initial(assets,link,with_menu(config,state),pending,human && MenuInput.capture_allowed(state),old,status,resume)
    case MenuResult{window,link,state,keep,Fail{message}}: closing(window,assets,link,1,"menu command: " ++ message)

def menu_intercepted(assets:RF.Assets,link:Link,+config:Config,old:Bool,window:Window,
    batch:MenuInput.Batch,resume:Window -> RF.Assets -> Link -> Config -> Bool -> IO(Unit)) -> IO(Unit):
  Config{human,frames,width,height,trace,serial,plan,started,menu,keys,physical_keys} = config
  MenuInput.Batch{state,intents,events} = batch
  do IO<Unit>:
    sent : MenuResult <- send_menu_intents(intents,window,link,state,human,True{})
    menu_events_sent(assets,config,MenuInput.game_events(events),old,sent,resume)

def menu_intercept(assets:RF.Assets,link:Link,+config:Config,pending:List<Event>,old:Bool,
    result:Window & Bool & Bool,resume:Window -> RF.Assets -> Link -> Config -> Bool -> IO(Unit)) -> IO(Unit):
  Config{human,frames,width,height,trace,serial,+plan,started,menu,keys,physical_keys} = config
  (window,focused,captured) = result
  menu_intercepted(assets,link,config,old,window,MenuInput.packet_keys(physical_keys,keys,menu,pending,
    MenuInput.viewport(Presentation.hud_viewport(plan)),focused,captured),resume)

def input_presented(window:Window,assets:RF.Assets,link:Link,+config:Config,captured:Bool,+image:Image,pending:List<Event>,
    resume:Window -> RF.Assets -> Link -> Config -> Bool -> IO(Unit)) -> IO(Unit):
  Config{+human,frames,width,height,trace,serial,+plan,started,menu,keys,physical_keys} = config
  do IO<Unit>:
    image_description(image,config)
    window : Window <- Common.window_policy(window,human)
    status : Window & Bool & Bool <- Input.Native.status(window)
    menu_intercept(assets,link,config,Presentation.native_events(pending,plan),captured,status,resume)

def traced(window:Window,assets:RF.Assets,link:Link,config:Config,captured:Bool,image:Image,pending:List<Event>,
    status:Result<&2,&2,String,Unit>,resume:Window -> RF.Assets -> Link -> Config -> Bool -> IO(Unit)) -> IO(Unit):
  match status:
    case Fail{message}: closing(window,assets,link,1,message)
    case Done{unit}: input_presented(window,assets,link,config,captured,image,pending,resume)

def presented(assets:RF.Assets,link:Link,+config:Config,captured:Bool,result:Window & Image & List<Event>,
    resume:Window -> RF.Assets -> Link -> Config -> Bool -> IO(Unit)) -> IO(Unit):
  Config{human,frames,width,height,mode,serial,plan,started,menu,keys,physical_keys} = config
  (window,+image,pending) = result
  do IO<Unit>:
    now : U32 <- NativePresentation.Native.milliseconds()
    IO.print("client.timing|" ++ Nat.show(serial) ++ "|" ++ U32.show(U32.sub(now,started)))
    status : Result<&2,&2,String,Unit> <- trace(image,config)
    traced(window,assets,link,config,captured,image,pending,status,resume)

def drawn(window:Window,link:Link,+config:Config,captured:Bool,view:HUD.View,screen:Maybe<&2,Screen.View>,result:RF.Assets & Result<&2,&2,String,Image>,
    resume:Window -> RF.Assets -> Link -> Config -> Bool -> IO(Unit)) -> IO(Unit):
  Config{human,frames,width,height,trace,serial,+plan,started,menu,keys,physical_keys} = config
  (assets,status) = result
  match status:
    case Fail{message}: closing(window,assets,link,1,"render: " ++ message)
    case Done{image}:
      do IO<Unit>:
        shown : Window & Image & List<Event> <- Window.frame(window,
          MenuInput.draw(HUD.compose(image,view,plan),menu,screen,Presentation.hud_viewport(plan)))
        presented(assets,link,config,captured,shown,resume)

# Textures and catalog values are immutable Data. Retain their lists while
# restoring the sole affine RF.Assets owner before world rendering begins.
def hud_view(assets:RF.Assets,snapshot:Inventory.Snapshot) -> RF.Assets & HUD.View:
  match assets snapshot:
    case RF.Assets{Pixels.Assets{+textures},bindings,count,palette,
        Resources.Catalog{roots,source,models,+sprites,context,usage}} Inventory.Snapshot{selected,slots,abilities}:
      (RF.Assets{Pixels.Assets{textures},bindings,count,palette,Resources.Catalog{roots,source,models,sprites,context,usage}},
        HUD.prepare(selected,slots,HUD.icons(textures,sprites)))

def menu_views(assets:RF.Assets,+menu:MenuInput.State) -> RF.Assets & Result<&2,&1,String,HUD.View & Maybe<&2,Screen.View>>:
  match assets menu:
    case RF.Assets{Pixels.Assets{+textures},bindings,count,palette,
        Resources.Catalog{roots,source,models,+sprites,context,usage}}
        MenuInput.State{controller,Some{Inventory.MenuSnapshot{Inventory.Persisted{Inventory.Snapshot{selected,slots,abilities},equipment,status},craft,carried,result,opened,revision}},catalog}:
      +icons = HUD.icons(textures,sprites)
      (RF.Assets{Pixels.Assets{textures},bindings,count,palette,Resources.Catalog{roots,source,models,sprites,context,usage}},
        Done{(HUD.prepare(selected,slots,icons),MenuInput.view(menu,[],icons))})
    case other _:
      (other,Fail{"no authoritative menu snapshot"})

def inventory_timed(window:Window,assets:RF.Assets,link:Link,+config:Config,captured:Bool,+sample:Visibility.Sample,
    view:HUD.View,screen:Maybe<&2,Screen.View>,begin:U32,
    resume:Window -> RF.Assets -> Link -> Config -> Bool -> IO(Unit)) -> IO(Unit):
  Config{human,frames,width,height,trace,serial,plan,started,menu,keys,physical_keys} = config
  +timed : Config = Config{human,frames,width,height,trace,serial,plan,begin,menu,keys,physical_keys}
  do IO<Unit>:
    frame_description(sample,timed)
    drawn(window,link,timed,captured,view,screen,WRF.draw(sample,assets,width,height),resume)

def inventory_draw(window:Window,link:Link,+config:Config,captured:Bool,+sample:Visibility.Sample,
    prepared:RF.Assets & Result<&2,&1,String,HUD.View & Maybe<&2,Screen.View>>,resume:Window -> RF.Assets -> Link -> Config -> Bool -> IO(Unit)) -> IO(Unit):
  Config{human,frames,width,height,trace,serial,+plan,started,menu,keys,physical_keys} = config
  (assets,status) = prepared
  match status:
    case Fail{message}: closing(window,assets,link,1,message)
    case Done{Tuple{view,screen}}:
      do IO<Unit>:
        begin : U32 <- NativePresentation.Native.milliseconds()
        inventory_timed(window,assets,link,config,captured,sample,view,screen,begin,resume)

def inventoried(window:Window,assets:RF.Assets,+config:Config,captured:Bool,sample:Visibility.Sample,
    result:Link & Result<&2,&2,String,Wire.Reply>,resume:Window -> RF.Assets -> Link -> Config -> Bool -> IO(Unit)) -> IO(Unit):
  (link,status) = result
  match status:
    case Done{Wire.MenuReply{epoch,sequence,accepted,message,snapshot}}:
      +menu = MenuInput.observed(menu_state(config),snapshot)
      inventory_draw(window,link,with_menu(config,menu),captured,sample,menu_views(assets,menu),resume)
    case Done{other}: closing(window,assets,link,1,"inventory query: Wire:ExpectedMenu")
    case Fail{message}: closing(window,assets,link,1,"inventory query: " ++ message)

def snapshot_ready(window:Window,assets:RF.Assets,link:Link,config:Config,captured:Bool,sample:Visibility.Sample,
    resume:Window -> RF.Assets -> Link -> Config -> Bool -> IO(Unit)) -> IO(Unit):
  do IO<Unit>:
    reply : Link & Result<&2,&2,String,Wire.Reply> <- call(link,Wire.MenuInspect{})
    inventoried(window,assets,config,captured,sample,reply,resume)

def sampled(window:Window,assets:RF.Assets,config:Config,captured:Bool,result:Link & Result<&2,&2,String,Wire.Reply>,
    resume:Window -> RF.Assets -> Link -> Config -> Bool -> IO(Unit)) -> IO(Unit):
  (link,status) = result
  match status:
    case Fail{message}: closing(window,assets,link,1,"frame query: " ++ message)
    case Done{Wire.FrameReply{epoch,sequence,sample}}: snapshot_ready(window,assets,link,config,captured,sample,resume)
    case Done{other}: closing(window,assets,link,1,"frame query: Wire:ExpectedFrame")

def query_planned(window:Window,assets:RF.Assets,link:Link,+config:Config,captured:Bool,valid:Bool,
    resume:Window -> RF.Assets -> Link -> Config -> Bool -> IO(Unit)) -> IO(Unit):
  match config valid:
    case _ False{}: closing(window,assets,link,1,"drawable dimensions exceed the configured presentation allocation policy")
    case Config{human,frames,width,height,trace,serial,plan,started,menu,keys,physical_keys} True{}:
      do IO<Unit>:
        reply : Link & Result<&2,&2,String,Wire.Reply> <- call(link,Wire.Frame{width,height})
        sampled(window,assets,config,captured,reply,resume)

def planned(assets:RF.Assets,link:Link,+config:Config,captured:Bool,
    result:Window & Presentation.Geometry,resume:Window -> RF.Assets -> Link -> Config -> Bool -> IO(Unit)) -> IO(Unit):
  Config{+human,frames,width,height,trace,serial,Presentation.Plan{+settings,viewport,sw,sh,pw,ph},started,menu,keys,physical_keys} = config
  (actual,+geometry) = result
  +next_plan = Presentation.plan(settings,geometry,human)
  +next_width = Presentation.scene_width(next_plan)
  +next_height = Presentation.scene_height(next_plan)
  +next : Config = Config{human,frames,next_width,next_height,trace,serial,next_plan,started,menu,keys,physical_keys}
  query_planned(actual,assets,link,next,captured,
    Presentation.geometry_valid(geometry) &&
      Presentation.dimensions(Presentation.output_width(next_plan),Presentation.output_height(next_plan)),resume)

@unsafe
def loop(window:Window,assets:RF.Assets,link:Link,+config:Config,captured:Bool) -> IO(Unit):
  do IO<Unit>:
    actual : Window & Presentation.Geometry <- NativePresentation.measure(window)
    planned(assets,link,config,captured,actual,w => a => l => c => capture => loop(w,a,l,c,capture))

def starting(window:Window,assets:RF.Assets,link:Link,+config:Config,captured:Bool,sample:Visibility.Sample) -> IO(Unit):
  Config{human,frames,width,height,trace,serial,+plan,started,menu,keys,physical_keys} = config
  match frames:
    case Some{0n}: closing(window,assets,link,0,"client closed")
    case _: snapshot_ready(window,assets,link,config,captured,sample,w => a => l => c => capture => loop(w,a,l,c,capture))

def captured(assets:RF.Assets,link:Link,config:Config,sample:Visibility.Sample,result:Window & Bool) -> IO(Unit):
  (window,capture) = result
  starting(window,assets,link,config,capture,sample)

def capture_configured(window:Window,assets:RF.Assets,link:Link,+config:Config,sample:Visibility.Sample,valid:Bool) -> IO(Unit):
  match config valid:
    case _ False{}: closing(window,assets,link,1,"drawable/content dimensions exceed the configured presentation allocation policy")
    case Config{+human,frames,width,height,trace,serial,plan,started,menu,keys,physical_keys} True{}:
      do IO<Unit>:
        actual : Window & Bool <- Input.capture(window,human)
        captured(assets,link,config,sample,actual)

def configured_window(assets:RF.Assets,link:Link,+config:Config,sample:Visibility.Sample,
    actual:Window & Presentation.Geometry) -> IO(Unit):
  Config{+human,frames,width,height,trace,serial,Presentation.Plan{+settings,viewport,sw,sh,pw,ph},started,menu,keys,physical_keys} = config
  (window,+geometry) = actual
  +plan = Presentation.plan(settings,geometry,human)
  +next : Config = Config{human,frames,Presentation.scene_width(plan),Presentation.scene_height(plan),trace,serial,plan,started,menu,keys,physical_keys}
  capture_configured(window,assets,link,next,sample,Presentation.geometry_valid(geometry) &&
    Presentation.dimensions(Presentation.output_width(plan),Presentation.output_height(plan)))

def keys_enabled(assets:RF.Assets,link:Link,config:Config,sample:Visibility.Sample,result:Window & Bool) -> IO(Unit):
  Config{human,frames,width,height,trace,serial,plan,started,menu,keys,previous} = config
  (window,enabled) = result
  do IO<Unit>:
    actual : Window & Presentation.Geometry <- NativePresentation.measure(window)
    configured_window(assets,link,Config{human,frames,width,height,trace,serial,plan,started,menu,keys,enabled},sample,actual)

def opened(assets:RF.Assets,link:Link,+config:Config,sample:Visibility.Sample,result:Result<&1,&1,U32 & String,Window>) -> IO(Unit):
  Config{+human,frames,width,height,trace,serial,Presentation.Plan{Presentation.Settings{+ow,+oh,percent,scale,+native,+fullscreen},viewport,sw,sh,pw,ph},started,menu,keys,physical_keys} = config
  match result:
    case Fail{(code,message)}:
      do IO<Unit>:
        RF.close_assets(assets)
        release_close(link)
        IO.die(Unit,code,"window open: " ++ message)
    case Done{window}:
      do IO<Unit>:
        configured : Window <- NativePresentation.Native.configure(window,ow,oh,native,fullscreen,human)
        keyed : Window & Bool <- NativePresentation.Native.inventory_keys(configured)
        keys_enabled(assets,link,config,sample,keyed)

def open_catalogued_valid(assets:RF.Assets,link:Link,sample:Visibility.Sample,+human:Bool,frames:Maybe<&2,Nat>,+settings:Presentation.Settings,catalog:ItemDefinitions.Catalog,keys:Keys.Profile) -> IO(Unit):
  Presentation.Settings{+ow,+oh,percent,scale,native,fullscreen} = settings
  +plan = Presentation.plan(settings,Presentation.Geometry{ow,oh,ow,oh},human)
  do IO<Unit>:
    mode : Result<&1,&1,U32 & String,String> <- IO.get_env("BEND_MINECRAFT_FRAME_DIR")
    window : Result<&1,&1,U32 & String,Window> <- Window.open("Minecraft 26.3 — remote LocalPlayer resource client",
      PNG.choose(U32,960,PNG.choose(U32,512,ow,U32.is_eq(ow,128) && U32.is_eq(oh,128)),human),
      PNG.choose(U32,540,PNG.choose(U32,512,oh,U32.is_eq(ow,128) && U32.is_eq(oh,128)),human))
    opened(assets,link,Config{human,frames,Presentation.scene_width(plan),Presentation.scene_height(plan),trace_mode(mode),0n,plan,0,MenuInput.new(catalog),keys,False{}},sample,window)

def open_catalogued_checked(assets:RF.Assets,link:Link,sample:Visibility.Sample,human:Bool,frames:Maybe<&2,Nat>,settings:Presentation.Settings,catalog:ItemDefinitions.Catalog,
    result:Result<&2,&2,String,Keys.Profile>) -> IO(Unit):
  match result:
    case Fail{message}:
      do IO<Unit>:
        RF.close_assets(assets)
        release_close(link)
        IO.die(Unit,1,message)
    case Done{keys}: open_catalogued_valid(assets,link,sample,human,frames,settings,catalog,keys)

# Profiles are fixed for the lifetime of this window. Rebinding a held input
# requires a release/reset transition before opening a new profile.
def open_catalogued_bindings(assets:RF.Assets,link:Link,sample:Visibility.Sample,human:Bool,frames:Maybe<&2,Nat>,settings:Presentation.Settings,catalog:ItemDefinitions.Catalog,keys:Keys.Profile) -> IO(Unit):
  open_catalogued_checked(assets,link,sample,human,frames,settings,catalog,Keys.validate(keys))

def open_catalogued(assets:RF.Assets,link:Link,sample:Visibility.Sample,human:Bool,frames:Maybe<&2,Nat>,settings:Presentation.Settings,catalog:ItemDefinitions.Catalog) -> IO(Unit):
  open_catalogued_bindings(assets,link,sample,human,frames,settings,catalog,Keys.defaults())

def catalog_loaded(assets:RF.Assets,link:Link,sample:Visibility.Sample,human:Bool,frames:Maybe<&2,Nat>,settings:Presentation.Settings,
    result:Result<&2,&2,String,ItemDefinitions.Catalog>) -> IO(Unit):
  match result:
    case Fail{message}:
      do IO<Unit>:
        RF.close_assets(assets)
        release_close(link)
        IO.die(Unit,1,message)
    case Done{catalog}: open_catalogued(assets,link,sample,human,frames,settings,catalog)

def catalog_loaded_bindings(assets:RF.Assets,link:Link,sample:Visibility.Sample,human:Bool,frames:Maybe<&2,Nat>,settings:Presentation.Settings,keys:Keys.Profile,
    result:Result<&2,&2,String,ItemDefinitions.Catalog>) -> IO(Unit):
  match result:
    case Fail{message}:
      do IO<Unit>:
        RF.close_assets(assets)
        release_close(link)
        IO.die(Unit,1,message)
    case Done{catalog}: open_catalogued_bindings(assets,link,sample,human,frames,settings,catalog,keys)

def open_item_table_bindings(assets:RF.Assets,link:Link,sample:Visibility.Sample,human:Bool,frames:Maybe<&2,Nat>,settings:Presentation.Settings,path:String,keys:Keys.Profile) -> IO(Unit):
  do IO<Unit>:
    catalog : Result<&2,&2,String,ItemDefinitions.Catalog> <- ItemCatalog.load(path)
    catalog_loaded_bindings(assets,link,sample,human,frames,settings,keys,catalog)

def open_item_table(assets:RF.Assets,link:Link,sample:Visibility.Sample,human:Bool,frames:Maybe<&2,Nat>,settings:Presentation.Settings,path:String) -> IO(Unit):
  open_item_table_bindings(assets,link,sample,human,frames,settings,path,Keys.defaults())

def open_settings(assets:RF.Assets,link:Link,sample:Visibility.Sample,human:Bool,frames:Maybe<&2,Nat>,settings:Presentation.Settings) -> IO(Unit):
  open_item_table(assets,link,sample,human,frames,settings,"generated/reference_item_metadata.tsv")

def open(assets:RF.Assets,link:Link,sample:Visibility.Sample,+human:Bool,frames:Maybe<&2,Nat>,width:U32,height:U32) -> IO(Unit):
  open_settings(assets,link,sample,human,frames,Presentation.Settings{width,height,100,1,False{},False{}})
