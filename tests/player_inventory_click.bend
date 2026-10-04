import Base
import ../src/player_inventory.bend as I
import ../src/inventory.bend as Inv
import ../src/player_item_definitions.bend as D
import ../src/player_item_catalog.bend as Catalog
import ./player_inventory_close.bend as Fixture

# Initialize the actual sole owner, invoke production menu_click, then consume
# and report every64 backing cell and every retained player/profile field.
def execute(catalog:D.Catalog,fields:List<&2,String>) -> IO(Unit):
  match fields:
    case label <> selected <> instabuild <> maybuild <> invulnerable <> mayfly <> flying <> walking_speed <> flying_speed <> revision <> output <> opened <> target <> button <> slots:
      Fixture.completed(label,I.menu_click(I.State{
        I.write_returned(Fixture.fixture_slots(slots),0,Inv.Inventory{Array.new(Inv.Slot,6n,Inv.InvEmpty{}),48}),
        Fixture.number(selected),I.Abilities{Fixture.flag(instabuild),Fixture.flag(maybuild)},
        I.Profile{catalog,I.Status{Fixture.flag(invulnerable),Fixture.flag(mayfly),Fixture.flag(flying),Fixture.number(walking_speed),Fixture.number(flying_speed)},
          I.Menu{Fixture.flag(opened),U32.to_nat(Fixture.number(revision)),Fixture.fixture_result(output)}}},
          Fixture.number(target),I.Swap{Fixture.number(button)}))
    case _: IO.die(Unit,2,"swap fixture requires full profile and64 backing slots")

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
    case _: IO.die(Unit,2,"expected verified item table then swap fixtures")

def main() -> IO(Unit): IO.bind(List<String>,Unit,IO.args(),arguments)
