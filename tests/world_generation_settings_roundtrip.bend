import Base
import ../src/world_generation_settings.bend as WG
import ../src/world_generation_settings_codec.bend as Codec
import ../src/nbt.bend as N

def flag(value:Bool) -> String:
  U32.show(Bool.to_u32(value))

def properties(values:List<&2,WG.Assignment>) -> String:
  match values:
    case Nil{}: ""
    case WG.Assignment{name,value} <> rest: name ++ "=" ++ value ++ ";" ++ properties(rest)

def layers(values:List<&2,WG.Layer>) -> String:
  match values:
    case Nil{}: ""
    case WG.Layer{height,block,assignments} <> rest:
      U32.show(height) ++ "," ++ block ++ "," ++ properties(assignments) ++ "/" ++ layers(rest)

def structures(value:Maybe<&2,List<&2,String>>) -> String:
  match value:
    case None{}: "unspecified"
    case Some{entries}: "specified:" ++ String.join(entries,",")

def biomes(value:WG.BiomeSource) -> String:
  match value:
    case WG.MultiNoisePreset{preset}: "multi_noise_preset," ++ preset
    case WG.EndBiomes{}: "the_end"
    case WG.FixedBiome{biome}: "fixed," ++ biome

def generator(value:WG.Generator) -> String:
  match value:
    case WG.Flat{profile,biome,values,features,lakes,sets}:
      "flat|" ++ profile ++ "|" ++ biome ++ "|" ++ layers(values) ++ "|" ++ flag(features) ++ "|" ++ flag(lakes) ++ "|" ++ structures(sets)
    case WG.Noise{settings,source}: "noise|" ++ settings ++ "|" ++ biomes(source)

def describe(value:WG.Settings) -> String:
  match value:
    case WG.Unspecified{}: "unspecified"
    case WG.Settings{dimension,min_y,height,N.Word64{hi,lo},gen}:
      dimension ++ "|" ++ U32.show(min_y) ++ "|" ++ U32.show(height) ++ "|" ++ U32.show(hi) ++ "," ++ U32.show(lo) ++ "|" ++ generator(gen)

def decoded_result(result:Result<&2,&2,String,WG.Settings>) -> String:
  match result:
    case Fail{message}: "fail|" ++ message
    case Done{settings}: "decoded|" ++ describe(settings)

def encoded_result(result:Result<&2,&2,String,List<&2,U32>>) -> String:
  match result:
    case Fail{message}: "fail|" ++ message
    case Done{bytes}: decoded_result(Codec.decode(bytes))

def roundtrip(name:String,settings:WG.Settings) -> String:
  name ++ "|" ++ encoded_result(Codec.encode(settings))

def long_profile() -> String:
  "bendex:abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz"

def custom_structures(sets:Maybe<&2,List<&2,String>>) -> WG.Settings:
  WG.Settings{"minecraft:overworld",4294967232,384,N.Word64{2147483648,4294967295},
    WG.Flat{long_profile(),"minecraft:plains",[WG.Layer{0,"minecraft:air",[]},WG.Layer{4,"minecraft:oak_log",[WG.Assignment{"axis","z"}]}],
      True{},True{},sets}}

def run(args:List<&2,String>) -> IO(Unit):
  do IO<Unit>:
    IO.print(roundtrip("legacy",WG.legacy()))
    IO.print(roundtrip("custom",WG.stone_dirt(N.Word64{4294967295,4294967295})))
    IO.print(roundtrip("classic",WG.classic(N.Word64{2147483648,0})))
    IO.print(roundtrip("normal",WG.normal(N.Word64{0,4294967295})))
    IO.print(roundtrip("long-unspecified",custom_structures(None{})))
    IO.print(roundtrip("long-empty",custom_structures(Some{[]})))
    IO.print(roundtrip("long-ordered",custom_structures(Some{["minecraft:villages","minecraft:strongholds"]})))
    IO.print(roundtrip("invalid",WG.Settings{"minecraft:overworld",4294967233,384,N.Word64{0,0},WG.Noise{"minecraft:overworld",WG.EndBiomes{}}}))
    return Unit{}

def main() -> IO(Unit):
  run([])
