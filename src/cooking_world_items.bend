import Base
import ./json.bend as J
import ./inventory.bend as I
import ./crafting_recipe_components.bend as C
import ./campfire_authority_items.bend as A
import ./cooking_recipe.bend as K
import ./furnace_authority.bend as F
import ./furnace_authority_fuel.bend as FF
import ./furnace_authority_decoder.bend as FD
import ./cooking_block_entity_codec_components.bend as CC

type Admission is Data:
  Admission{metadata:List<&2,I.ItemMetadata>,profiles:List<&2,FF.FuelProfile>}
def initialized(found:Maybe<&2,J.Value>) -> Result<&2,&2,String,J.Value>:
  match found:
    case None{}: Fail{"cooking-world:item-lacks-initialized-defaults"}
    case Some{value}: Done{value}
def profile(+context:A.Context,+slot:I.Slot) -> Result<&2,&2,String,Maybe<&2,FF.FuelProfile>>:
  A.Context{recipes,defaults,features} = context
  match slot:
    case I.InvEmpty{}: Done{None{}}
    case I.InvStack{I.ItemKey{+id,+components},count}:
      do Result<&2,&2,String,Maybe<&2,FF.FuelProfile>>:
        +base : J.Value <- initialized(C.default_for(defaults,id))
        +patch : J.Value <- CC.patch(base,I.ItemKey{id,components})
        admitted : Maybe<&2,I.ItemMetadata> <- A.admit(context,A.Input{slot,patch})
        fuel : FF.FuelProfile <- FD.admit(base,I.ItemKey{id,components},patch)
        return Some{fuel}
def append(rest:Admission,value:Maybe<&2,FF.FuelProfile>) -> Admission:
  Admission{metadata,profiles} = rest
  match value:
    case None{}: rest
    case Some{+head}:
      FF.FuelProfile{key,fuel,item} = head
      Admission{item <> metadata,head <> profiles}
def slots(values:List<&2,I.Slot>,+context:A.Context) -> Result<&2,&2,String,Admission>:
  match values:
    case Nil{}: Done{Admission{[],[]}}
    case head <> tail:
      do Result<&2,&2,String,Admission>:
        value : Maybe<&2,FF.FuelProfile> <- profile(context,head)
        rest : Admission <- slots(tail,context)
        return append(rest,value)
def furnace(context:A.Context,snapshot:F.Snapshot) -> Result<&2,&2,String,Admission>:
  F.Snapshot{frame,K.FurnaceSlots{input,fuel,output}} = snapshot
  slots([input,fuel,output],context)
