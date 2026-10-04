import Base
import ../src/player_inventory.bend as I
import ../src/player_inventory_codec.bend as C
import ../src/inventory.bend as Inv
import ../src/json.bend as J
import ../src/live.bend as L

# This executable owns no game transition. It drives the production inventory
# and codec and exposes their results to an independent host fixture comparator.
def slot_value(slot:Inv.Slot) -> J.Value:
  match slot:
    case Inv.InvEmpty{}: J.JNull{}
    case Inv.InvStack{Inv.ItemKey{id,components},count}:
      L.obj([J.JMember{"id",L.text(id)},J.JMember{"components",L.text(components)},J.JMember{"count",L.uint(count)}])

def slot_values(slots:List<&2,Inv.Slot>) -> List<&2,J.Value>:
  match slots:
    case Nil{}: []
    case slot <> rest: slot_value(slot) <> slot_values(rest)

def snapshot_value(snapshot:I.Snapshot) -> J.Value:
  I.Snapshot{selected,slots,I.Abilities{instabuild,maybuild}} = snapshot
  L.obj([J.JMember{"selected",L.uint(selected)},J.JMember{"slots",J.JArray{slot_values(slots)}},
    J.JMember{"abilities",L.obj([J.JMember{"instabuild",L.boolean(instabuild)},J.JMember{"maybuild",L.boolean(maybuild)}])}])

def report_inspected(label:String,status:String,result:I.State & I.Snapshot) -> IO(I.State):
  (inventory,snapshot) = result
  do IO<I.State>:
    IO.print(J.encode(L.obj([J.JMember{"label",L.text(label)},J.JMember{"status",L.text(status)},J.JMember{"inventory",snapshot_value(snapshot)}])))
    return inventory

def report(label:String,status:String,inventory:I.State) -> IO(I.State):
  report_inspected(label,status,I.inspect(inventory))

def unit_result(label:String,result:I.State & Result<&2,&2,String,Unit>) -> IO(I.State):
  (inventory,status) = result
  match status:
    case Fail{message}: report(label,"rejected:" ++ message,inventory)
    case Done{unit}: report(label,"ok",inventory)

def transfer_result(label:String,result:I.State & Inv.TransferStatus) -> IO(I.State):
  (inventory,status) = result
  report(label,Inv.status_show(status),inventory)

def selected_result(label:String,result:I.State & Inv.Slot) -> IO(I.State):
  (inventory,slot) = result
  report(label,"selected:" ++ J.encode(slot_value(slot)),inventory)

def number_value(result:Maybe<&2,U32>) -> U32:
  match result:
    case None{}: 4294967295
    case Some{value}: value

def number(text:String) -> U32:
  number_value(U32.read(text))

def mode(name:String) -> Inv.TransferMode:
  match name:
    case "split": Inv.TransferSplit{}
    case "merge": Inv.TransferMerge{}
    case _: Inv.TransferAny{}

def execute(inventory:I.State,fields:List<&2,String>) -> IO(I.State):
  match fields:
    case label <> "inspect" <> Nil{}: report(label,"ok",inventory)
    case label <> "selected" <> Nil{}: selected_result(label,I.selected(inventory))
    case label <> "select" <> index <> Nil{}: unit_result(label,I.select(inventory,number(index)))
    case label <> "acquire" <> index <> item <> count <> Nil{}:
      unit_result(label,I.acquire(inventory,number(index),Inv.ItemKey{item,""},number(count)))
    case label <> "modified" <> index <> item <> count <> Nil{}:
      unit_result(label,I.acquire(inventory,number(index),Inv.ItemKey{item,"{modified}"},number(count)))
    case label <> "transfer" <> source <> destination <> count <> kind <> Nil{}:
      transfer_result(label,I.transfer(inventory,number(source),number(destination),number(count),mode(kind)))
    case label <> "abilities" <> build <> may <> Nil{}:
      report(label,"ok",I.set_abilities(inventory,I.Abilities{U32.is_eq(number(build),1),U32.is_eq(number(may),1)}))
    case _: IO.die(I.State,2,"invalid player inventory test action")

def transitions(actions:List<String>,inventory:I.State) -> IO(Unit):
  match actions:
    case Nil{}: IO.pure(Unit,Unit{})
    case action <> rest:
      do IO<Unit>:
        next : I.State <- execute(inventory,String.split(action,'|'))
        transitions(rest,next)

def profile(name:String) -> I.State:
  I.set_abilities(I.new(),I.Abilities{String.eq(name,"creative"),True{}})

def written(result:File & Result<&1,&1,U32 & String,Unit>) -> IO(Unit):
  (file,status) = result
  do IO<Unit>:
    File.close(file)
    IO.pass(Unit,status)

def publish(path:String,bytes:List<&2,U32>) -> IO(Unit):
  do IO<Unit>:
    file : File <- IO.try(File,File.open(path,"w"))
    result : File & Result<&1,&1,U32 & String,Unit> <- File.write_bytes(file,bytes)
    written(result)

def loaded(result:File & Result<&1,&1,U32 & String,List<&2,U32>>) -> IO(List<&2,U32>):
  (file,status) = result
  do IO<List<&2,U32>>:
    File.close(file)
    IO.pass(List<&2,U32>,status)

def read(path:String) -> IO(List<&2,U32>):
  do IO<List<&2,U32>>:
    file : File <- IO.try(File,File.open(path,"r"))
    result : File & Result<&1,&1,U32 & String,List<&2,U32>> <- File.read_bytes(file,65537)
    loaded(result)

def codec_inspected(fresh:Bool,result:I.State & I.Snapshot) -> IO(Unit):
  (inventory,snapshot) = result
  IO.print(J.encode(L.obj([J.JMember{"status",L.text("ok")},J.JMember{"fresh",L.boolean(fresh)},J.JMember{"inventory",snapshot_value(snapshot)}])))

def codec_encoded(output:String,result:C.Saved & Result<&2,&2,String,List<&2,U32>>) -> IO(Unit):
  (C.Saved{record,inventory,fresh},status) = result
  match status:
    case Fail{message}: IO.print(J.encode(L.obj([J.JMember{"status",L.text("error")},J.JMember{"message",L.text(message)}])))
    case Done{bytes}:
      do IO<Unit>:
        publish(output,bytes)
        codec_inspected(fresh,I.inspect(inventory))

def codec_decoded(output:String,result:Result<&2,&1,String,C.Saved>) -> IO(Unit):
  match result:
    case Fail{message}: IO.print(J.encode(L.obj([J.JMember{"status",L.text("error")},J.JMember{"message",L.text(message)}])))
    case Done{saved}: codec_encoded(output,C.encode(saved))

def codec(schema:U32,input:String,output:String) -> IO(Unit):
  do IO<Unit>:
    bytes : List<&2,U32> <- read(input)
    codec_decoded(output,C.decode(schema,bytes))

def initial(output:String,creative:Bool) -> IO(Unit):
  match creative:
    case False{}: codec_decoded(output,C.initial(Unit{}))
    case True{}: codec_decoded(output,C.initial_creative(Unit{}))

def codec_batch(args:List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit,Unit{})
    case schema <> input <> output <> rest:
      do IO<Unit>:
        codec(number(schema),input,output)
        codec_batch(rest)
    case _: IO.die(Unit,2,"codec-batch requires SCHEMA INPUT OUTPUT triples")

def arguments(args:List<String>) -> IO(Unit):
  match args:
    case exe <> "transitions" <> name <> actions: transitions(actions,profile(name))
    case exe <> "codec" <> schema <> input <> output <> Nil{}: codec(number(schema),input,output)
    case exe <> "codec-batch" <> triples: codec_batch(triples)
    case exe <> "initial" <> name <> output <> Nil{}: initial(output,String.eq(name,"creative"))
    case _: IO.die(Unit,2,"expected transitions PROFILE ACTION..., codec SCHEMA INPUT OUTPUT, or initial PROFILE OUTPUT")

def main() -> IO(Unit):
  IO.bind(List<String>,Unit,IO.args(),arguments)
