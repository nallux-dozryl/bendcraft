import Base
import ./generic_resource_world_sample_demand.bend as D
import ./generic_resource_world_sample_resources.bend as Session
import ./resource_block_catalog.bend as C
import ./resource_block_catalog_profile.bend as Profile
import ./block_resources.bend as BR
import ./block_bake.bend as K

# Family admission is independent of a fixed startup fixture. Actual model and
# sprite IO still validates every demanded family and every material reference.
# Known special renderers remain named refusals, rather than empty model frames.
def modes(values:List<&2,String>,map:Map<&2,C.Mode>) -> Map<&2,C.Mode>:
  match values:
    case Nil{}: map
    case +name <> tail: modes(tail,Map.set(&2,C.Mode,map,name,Profile.vanilla_mode(name)))

def layers(values:List<&2,String>,map:Map<&2,K.Layer>) -> Map<&2,K.Layer>:
  match values:
    case Nil{}: map
    case name <> tail: layers(tail,Map.set(&2,K.Layer,map,"minecraft:block/" ++ name,K.Solid{}))

# The four original furnace sprites are static solid resources in the pinned
# 26.3 JAR. This does not infer an arbitrary sprite's layer from its alpha or
# invent tint, animation, fluid, block-entity or full-lighting behavior.
def extended_materials(value:BR.Policy) -> BR.Policy:
  BR.StaticNormalized{base} = value
  BR.StaticNormalized{layers(["furnace_top","furnace_side","furnace_front","furnace_front_on"],base)}

def materials() -> BR.Policy:
  extended_materials(Profile.static_policy())

def admission() -> D.Admission:
  D.Admission{Some{C.Model{}},modes(["minecraft:air","minecraft:cave_air","minecraft:void_air",
    "minecraft:water","minecraft:lava","minecraft:chest","minecraft:trapped_chest","minecraft:ender_chest"],MTip{}),materials()}

def config(jar:String) -> Session.Config:
  Session.Config{jar,admission(),D.Limits{4096,256,C.defaults()}}
