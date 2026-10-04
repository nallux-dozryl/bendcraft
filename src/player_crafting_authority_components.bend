import Base
import ./inventory.bend as Inv
import ./player_item_definitions.bend as D
import ./item_component.bend as C

# DefaultOnly is the live default until the inventory/profile/save join admits
# typed components. TypedStew is an explicit outer-consumer capability, never
# inferred from a component prefix or automatically enabled after a decode.
type Mode is Data:
  DefaultOnly{}
  TypedStew{defaults:C.Defaults}

def component_definition(definition:Maybe<&2,D.Definition>,key:Inv.ItemKey) -> Maybe<&2,Inv.ItemMetadata>:
  match definition:
    case None{}: None{}
    case Some{D.Definition{number,+id,description,limit,component_set,identity,enabled}}:
      C.metadata(C.default_from_identity(id,enabled,identity),key)

def known(mode:Mode,catalog:D.Catalog,+key:Inv.ItemKey) -> Maybe<&2,Inv.ItemMetadata>:
  match mode:
    case DefaultOnly{}: None{}
    case TypedStew{defaults}:
      Inv.ItemKey{id,components} = key
      C.metadata(D.component_defaults(catalog,id),key)

def plain(plain:Bool,mode:Mode,catalog:D.Catalog,key:Inv.ItemKey) -> Maybe<&2,Inv.ItemMetadata>:
  match plain:
    case True{}: D.metadata(catalog,key)
    case False{}: known(mode,catalog,key)

def metadata(mode:Mode,catalog:D.Catalog,+key:Inv.ItemKey) -> Maybe<&2,Inv.ItemMetadata>:
  Inv.ItemKey{id,components} = key
  plain(String.is_empty(components),mode,catalog,key)

def admitted(metadata:Maybe<&2,Inv.ItemMetadata>,slot:Inv.Slot) -> Bool:
  match metadata:
    case None{}: False{}
    case Some{definition}: Inv.slot_valid(slot,definition)

def valid_slot(+mode:Mode,+catalog:D.Catalog,+slot:Inv.Slot) -> Bool:
  match slot:
    case Inv.InvEmpty{}: True{}
    case Inv.InvStack{key,count}: admitted(metadata(mode,catalog,key),slot)

def valid_slots(left:Nat,values:List<&2,Inv.Slot>,+mode:Mode,+catalog:D.Catalog) -> Bool:
  match left values:
    case 0n Nil{}: True{}
    case 1n+n slot <> rest: valid_slot(mode,catalog,slot) && valid_slots(n,rest,mode,catalog)
    case _ _: False{}

def appended(value:Maybe<&2,Inv.ItemMetadata>,tail:List<&2,Inv.ItemMetadata>) -> List<&2,Inv.ItemMetadata>:
  match value:
    case None{}: tail
    case Some{metadata}: metadata <> tail

def modified(plain:Bool,mode:Mode,catalog:D.Catalog,key:Inv.ItemKey,tail:List<&2,Inv.ItemMetadata>) -> List<&2,Inv.ItemMetadata>:
  match plain:
    case True{}: tail
    case False{}: appended(known(mode,catalog,key),tail)

def input_metadata(values:List<&2,Inv.Slot>,+mode:Mode,+catalog:D.Catalog) -> List<&2,Inv.ItemMetadata>:
  match values:
    case Nil{}: []
    case Inv.InvEmpty{} <> rest: input_metadata(rest,mode,catalog)
    case Inv.InvStack{+key,count} <> rest:
      Inv.ItemKey{id,components} = key
      modified(String.is_empty(components),mode,catalog,key,input_metadata(rest,mode,catalog))
