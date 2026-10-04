import Base
import ../src/player_inventory.bend as I
import ../src/inventory.bend as Inv
import ../src/player_item_definitions.bend as D
import ../src/player_item_catalog.bend as Catalog
import ../src/json.bend as J
import ../src/live.bend as L

# Fixtures initialize the sole production owner, call actual menu_close once,
# then consume and report all64 backing cells plus every retained profile field.
# No return/insertion algorithm is implemented in this executable.
def number_value(result:Maybe<&2,U32>) -> U32:
  match result:
    case None{}: 4294967295
    case Some{value}: value

def number(text:String) -> U32: number_value(U32.read(text))
def flag(text:String) -> Bool: String.eq(text,"1")

def fixture_slot(fields:List<&2,String>) -> Inv.Slot:
  match fields:
    case "_" <> Nil{}: Inv.InvEmpty{}
    case id <> count <> Nil{}: Inv.InvStack{Inv.ItemKey{id,""},number(count)}
    case _: Inv.InvEmpty{}

def fixture_slots(fields:List<&2,String>) -> List<&2,Inv.Slot>:
  match fields:
    case Nil{}: []
    case field <> rest: fixture_slot(String.split(field,'~')) <> fixture_slots(rest)

def fixture_result(text:String) -> Maybe<&2,Inv.Slot>:
  match text:
    case "_": None{}
    case _: Some{fixture_slot(String.split(text,'~'))}

def slot_value(slot:Inv.Slot) -> J.Value:
  match slot:
    case Inv.InvEmpty{}: J.JNull{}
    case Inv.InvStack{Inv.ItemKey{id,components},count}:
      L.obj([J.JMember{"id",L.text(id)},J.JMember{"components",L.text(components)},J.JMember{"count",L.uint(count)}])

def slot_values(slots:List<&1,Inv.Slot>) -> List<&2,J.Value>:
  match slots:
    case Nil{}: []
    case slot <> rest: slot_value(slot) <> slot_values(rest)

def output_value(result:Maybe<&2,Inv.Slot>) -> J.Value:
  match result:
    case None{}: J.JNull{}
    case Some{slot}: slot_value(slot)

def abilities_value(abilities:I.Abilities,status:I.Status) -> J.Value:
  I.Abilities{instabuild,maybuild} = abilities
  I.Status{invulnerable,mayfly,flying,walking_speed,flying_speed} = status
  L.obj([J.JMember{"instabuild",L.boolean(instabuild)},J.JMember{"maybuild",L.boolean(maybuild)},
    J.JMember{"invulnerable",L.boolean(invulnerable)},J.JMember{"mayfly",L.boolean(mayfly)},
    J.JMember{"flying",L.boolean(flying)},J.JMember{"walking_speed",L.uint(walking_speed)},
    J.JMember{"flying_speed",L.uint(flying_speed)}])

def report(label:String,accepted:Bool,message:String,state:I.State) -> IO(Unit):
  I.State{Inv.Inventory{slots,length},selected,abilities,I.Profile{catalog,status,I.Menu{opened,revision,result}}} = state
  IO.print(J.encode(L.obj([J.JMember{"id",L.text(label)},J.JMember{"accepted",L.boolean(accepted)},
    J.JMember{"message",L.text(message)},J.JMember{"selected",L.uint(selected)},
    J.JMember{"abilities",abilities_value(abilities,status)},J.JMember{"opened",L.boolean(opened)},
    J.JMember{"revision",L.uint(U32.from_nat(revision))},J.JMember{"result",output_value(result)},
    J.JMember{"logical_length",L.uint(length)},J.JMember{"catalog_count",L.uint(D.count(catalog))},
    J.JMember{"all_backing_slots",J.JArray{slot_values(Array.to_list(~Inv.Slot,slots))}}])))

def completed(label:String,result:I.State & Result<&2,&2,String,Unit>) -> IO(Unit):
  (state,status) = result
  match status:
    case Fail{message}: report(label,False{},message,state)
    case Done{unit}: report(label,True{},"",state)

def execute(catalog:D.Catalog,fields:List<&2,String>) -> IO(Unit):
  match fields:
    case label <> selected <> instabuild <> maybuild <> invulnerable <> mayfly <> flying <> walking_speed <> flying_speed <> revision <> output <> slots:
      completed(label,I.menu_close(I.State{
        I.write_returned(fixture_slots(slots),0,Inv.Inventory{Array.new(Inv.Slot,6n,Inv.InvEmpty{}),48}),
        number(selected),I.Abilities{flag(instabuild),flag(maybuild)},
        I.Profile{catalog,I.Status{flag(invulnerable),flag(mayfly),flag(flying),number(walking_speed),number(flying_speed)},
          I.Menu{True{},U32.to_nat(number(revision)),fixture_result(output)}}}))
    case _: IO.die(Unit,2,"close fixture requires complete profile and64 backing slots")

def cases(+catalog:D.Catalog,args:List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit,Unit{})
    case argument <> rest:
      do IO<Unit>:
        execute(catalog,String.split(argument,'|'))
        cases(catalog,rest)

def loaded(args:List<String>,result:Result<&2,&2,String,D.Catalog>) -> IO(Unit):
  match result:
    case Fail{message}: IO.die(Unit,2,message)
    case Done{catalog}: cases(catalog,args)

def arguments(args:List<String>) -> IO(Unit):
  match args:
    case exe <> table <> inputs:
      do IO<Unit>:
        catalog : Result<&2,&2,String,D.Catalog> <- Catalog.load(table)
        loaded(inputs,catalog)
    case _: IO.die(Unit,2,"expected verified item table then close fixtures")

def main() -> IO(Unit): IO.bind(List<String>,Unit,IO.args(),arguments)
