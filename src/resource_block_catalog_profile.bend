import Base
import ./resource_block_catalog.bend as C
import ./block_bake.bend as K
import ./block_resources.bend as BR
import ./blockstate_model.bend as S
import ./world_mesh.bend as WM

# A useful pinned static profile, not a coverage inventory. The general loader
# accepts arbitrary registry names, caller renderer modes and resource policy.
def static_names() -> List<&2,String>:
  ["minecraft:stone","minecraft:dirt","minecraft:oak_planks","minecraft:cobblestone",
    "minecraft:sand","minecraft:bricks","minecraft:grass_block","minecraft:oak_log",
    "minecraft:oak_slab","minecraft:oak_stairs","minecraft:oak_fence"]

def vanilla_mode(+name:String) -> C.Mode:
  S.choose_value(C.Mode,C.Invisible{},
    S.choose_value(C.Mode,C.Unsupported{"fluid"},
      S.choose_value(C.Mode,C.Unsupported{"block_entity"},C.Model{},
        S.contains(["minecraft:chest","minecraft:trapped_chest","minecraft:ender_chest"],name)),
      S.contains(["minecraft:water","minecraft:lava"],name)),
    S.contains(["minecraft:air","minecraft:cave_air","minecraft:void_air"],name))

def requests(values:List<&2,String>) -> List<&2,C.Request>:
  match values:
    case Nil{}: Nil{}
    case +name <> rest: C.Request{name,vanilla_mode(name)} <> requests(rest)

def static_requests() -> List<&2,C.Request>:
  requests("minecraft:air" <> static_names())

def layers(values:List<&2,String>,map:Map<&2,K.Layer>) -> Map<&2,K.Layer>:
  match values:
    case Nil{}: map
    case name <> rest: layers(rest,Map.set(&2,K.Layer,map,"minecraft:block/" ++ name,K.Solid{}))

def static_policy() -> BR.Policy:
  BR.StaticNormalized{Map.set(&2,K.Layer,
    layers(["stone","dirt","oak_planks","cobblestone","sand","bricks",
      "oak_log","oak_log_top","grass_block_top","grass_block_side","grass_block_snow"],MTip{}),
    "minecraft:block/grass_block_side_overlay",K.Cutout{})}

def parsed_state(found:Maybe<&2,U32>,name:String) -> Result<&2,&2,C.Error,U32>:
  match found:
    case None{}: Fail{C.Error{"InvalidStateKey","catalog",name}}
    case Some{state}: Done{state}

def preview_binding(+catalog:C.Catalog,state:U32,appearance:WM.Appearance) -> Result<&2,&2,C.Error,WM.Binding>:
  C.Catalog{registry,entries,loaded} = catalog
  do Result<&2,&2,C.Error,WM.Binding>:
    +entry:C.Entry <- C.lookup(catalog,state)
    C.binding_result(C.bind_entry(entry,C.first_selection(entry),loaded,appearance))

def preview_keys(values:List<&2,String>,+catalog:C.Catalog,+appearance:WM.Appearance) -> Result<&2,&2,C.Error,List<&2,WM.Binding>>:
  match values:
    case Nil{}: Done{Nil{}}
    case +name <> rest:
      do Result<&2,&2,C.Error,List<&2,WM.Binding>>:
        state:U32 <- parsed_state(U32.read(name),name)
        binding:WM.Binding <- preview_binding(catalog,state,appearance)
        tail:List<&2,WM.Binding> <- preview_keys(rest,catalog,appearance)
        Done{binding <> tail}

# This bridge exposes every retained state to existing state-indexed meshes.
# Its first weighted choices and caller appearance are explicit preview policy;
# Java position RNG and biome lighting/tint still belong to the scene sampler.
def preview_bindings(+catalog:C.Catalog,appearance:WM.Appearance) -> Result<&2,&2,C.Error,List<&2,WM.Binding>>:
  C.Catalog{registry,entries,loaded} = catalog
  preview_keys(BR.sorted(Map.keys(&2,C.Entry,entries)),catalog,appearance)
