import Base
import ./random.bend as random
import ./inventory.bend as I
import ./player_inventory.bend as P
import ./campfire_authority_items.bend as A
import ./cooking_effect_entities_model.bend as E

type OwnerResolution is Data:
  UnknownOwner{}
  KnownAbsent{}
  ResolvedOwner{uuid:E.Uuid,server_player:Bool}
type Admission is Data:
  Admission{admitted:Bool,server_side:Bool,dimension:String,player_id:U32,
    uuid:E.Uuid,server_player:Bool,thrower_resolution:OwnerResolution}
type Context is Data:
  Context{items:A.Context,operation_budget:Nat}
type Properties is Data:
  Properties{metadata:I.ItemMetadata,damaged:Bool}
type Pop is Data:
  Pop{slot:U32,duration:U32}
type Insertion is Data:
  Insertion{slots:List<&2,I.Slot>,remaining:U32,inserted:U32,returned:Bool,pops:List<&2,Pop>}
type Publication is Data:
  PopTime{slot:U32,duration:U32}
  TakePacket{entity_id:U32,player_id:U32,count:U32}
  MenuBroadcast{player_id:U32}
  EntityDiscard{entity_id:U32}
  PickupStat{player:E.Uuid,item_id:String,count:U32}
  ThrownPickedUpByEntity{thrower:E.Uuid,receiver:E.Uuid,item:I.Slot}
  ThrownPickedUpByPlayer{receiver:E.Uuid,owner:E.Uuid,item:I.Slot}
type Effects is Data:
  Effects{inventory_add_returned:Bool,inserted:U32,residue:U32,discarded:Bool,
    publications:List<&2,Publication>}
type Plan is Data:
  Plan{record:E.Record,slots:List<&2,I.Slot>,effects:Effects}
type Error is Data:
  Refused{message:String}
  BudgetExhausted{}

def same_uuid(a:E.Uuid,b:E.Uuid) -> Bool:
  E.Uuid{random.Bits64{ah,al},random.Bits64{bh,bl}} = a
  E.Uuid{random.Bits64{ch,cl},random.Bits64{dh,dl}} = b
  U32.is_eq(ah,ch) && U32.is_eq(al,cl) && U32.is_eq(bh,dh) && U32.is_eq(bl,dl)
def target(allowed:Maybe<&2,E.Uuid>,uuid:E.Uuid) -> Bool:
  match allowed:
    case None{}: True{}
    case Some{owner}: same_uuid(owner,uuid)
def no_effects(residue:U32) -> Effects: Effects{False{},0,residue,False{},[]}
def string_error(~A:Data,result:Result<&2,&2,String,A>) -> Result<&2,&2,Error,A>:
  match result:
    case Fail{message}: Fail{Refused{message}}
    case Done{value}: Done{value}
def guarded(valid:Bool,message:String) -> Result<&2,&2,Error,Unit>:
  match valid:
    case False{}: Fail{Refused{message}}
    case True{}: Done{Unit{}}
def installed(record:E.Record,slots:List<&2,I.Slot>,effects:Effects,player:P.State) -> E.Entity & P.State & Result<&2,&2,Error,Effects>:
  P.State{inventory,selected,abilities,profile} = player
  (E.Entity{record},P.State{P.write_returned(slots,0,inventory),selected,abilities,profile},Done{effects})
# Failure never installs a candidate array or replaces either affine owner.
def committed(entity:E.Entity,player:P.State,result:Result<&2,&2,Error,Plan>) -> E.Entity & P.State & Result<&2,&2,Error,Effects>:
  match result:
    case Fail{error}: (entity,player,Fail{error})
    case Done{Plan{record,slots,effects}}: installed(record,slots,effects,player)
