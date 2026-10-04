import Base
import ./inventory.bend as Inv
import ./png.bend as P

# The full pinned table is an input to the game, not a Python item implementation.
# Empty components mean the item's observed defaults, not absent components.
type Definition is Data:
  Definition{number:U32,id:String,description:String,limit:U32,component_set:U32,
    components_sha256:String,enabled:Bool}

type Catalog is Data:
  Catalog{definitions:List<&2,Definition>,count:U32}

def guard(valid:Bool,message:String) -> Result<&2,&2,String,Unit>:
  match valid:
    case False{}: Fail{message}
    case True{}: Done{Unit{}}

def number(result:Maybe<&2,U32>,field:String) -> Result<&2,&2,String,U32>:
  match result:
    case None{}: Fail{"invalid item definition " ++ field}
    case Some{value}: Done{value}

def boolean(text:String) -> Result<&2,&2,String,Bool>:
  match text:
    case "True": Done{True{}}
    case "False": Done{False{}}
    case _: Fail{"invalid item definition enabled flag"}

def lower_hex(text:String) -> Bool:
  match text:
    case SNil{}: True{}
    case SCon{Chr{+code},rest}:
      ((U32.is_ge(code,48) && U32.is_le(code,57)) || (U32.is_ge(code,97) && U32.is_le(code,102))) && lower_hex(rest)

def identifier_tail(text:String,+path:Bool,+nonempty:Bool) -> Bool:
  match text path:
    case SNil{} _: path && nonempty
    case SCon{Chr{58},rest} False{}: nonempty && identifier_tail(rest,True{},False{})
    case SCon{Chr{+code},rest} _:
      (U32.is_eq(code,95) || U32.is_eq(code,45) || (path && U32.is_eq(code,47)) ||
        U32.is_eq(code,46) || (U32.is_ge(code,97) && U32.is_le(code,122)) ||
        (U32.is_ge(code,48) && U32.is_le(code,57))) && identifier_tail(rest,path,True{})

def identifier(text:String) -> Bool: identifier_tail(text,False{},False{})

def known(definitions:List<&2,Definition>,+wanted:String) -> Maybe<&2,Definition>:
  match definitions:
    case Nil{}: None{}
    case +head <> rest:
      Definition{number,id,description,limit,component_set,components_sha256,enabled} = head
      P.choose(Maybe<&2,Definition>,Some{head},known(rest,wanted),String.eq(id,wanted))

def definition(catalog:Catalog,id:String) -> Maybe<&2,Definition>:
  Catalog{definitions,count} = catalog
  known(definitions,id)

def metadata_known(item:Maybe<&2,Definition>,key:Inv.ItemKey) -> Maybe<&2,Inv.ItemMetadata>:
  match item:
    case None{}: None{}
    case Some{Definition{number,id,description,limit,component_set,components_sha256,enabled}}:
      P.choose(Maybe<&2,Inv.ItemMetadata>,Some{Inv.ItemMetadata{key,limit}},None{},enabled && Bool.not(String.eq(id,"minecraft:air")))

def metadata_plain(catalog:Catalog,+key:Inv.ItemKey) -> Maybe<&2,Inv.ItemMetadata>:
  Inv.ItemKey{id,components} = key
  metadata_known(definition(catalog,id),key)

def metadata_components(catalog:Catalog,key:Inv.ItemKey,plain:Bool) -> Maybe<&2,Inv.ItemMetadata>:
  match plain:
    case False{}: None{}
    case True{}: metadata_plain(catalog,key)

def metadata(catalog:Catalog,+key:Inv.ItemKey) -> Maybe<&2,Inv.ItemMetadata>:
  Inv.ItemKey{id,components} = key
  metadata_components(catalog,key,String.is_empty(components))

def fields(expected:U32,values:List<&2,String>,+previous:List<&2,Definition>) -> Result<&2,&2,String,Definition>:
  match values:
    case index <> +id <> item_class <> description <> item_limit <> maximum <> damage_limit <> damage <> count <> empty <> stackable <> damageable <> fits <> flags <> features <> rarity <> use <> foil <> enchantable <> remainder <> component_set <> +hash <> report_hash <> Nil{}:
      do Result<&2,&2,String,Definition>:
        +actual : U32 <- number(U32.read(index),"registry number")
        +limit : U32 <- number(U32.read(maximum),"maximum stack size")
        set : U32 <- number(U32.read(component_set),"component set")
        enabled : Bool <- boolean(flags)
        guard(U32.is_eq(actual,expected),"item definitions must have contiguous registry numbers")
        guard(Nat.is_gt(String.length(id),0n) && Nat.is_le(String.length(id),256n) && identifier(id),"invalid item definition identifier")
        guard(U32.is_ge(limit,1) && U32.is_le(limit,99),"invalid pinned maximum stack size")
        guard(Nat.is_eq(String.length(hash),64n) && lower_hex(hash),"invalid default component identity")
        guard(Bool.not(Maybe.is_some(&2,Definition,known(previous,id))),"duplicate item definition identifier")
        return Definition{actual,id,description,limit,set,hash,enabled}
    case _: Fail{"item definition requires exactly 23 table fields"}

def rows(left:Nat,lines:List<&2,String>,+index:U32,+definitions:List<&2,Definition>) -> Result<&2,&2,String,Catalog>:
  match left lines:
    case _ Nil{}: Done{Catalog{List.reverse(&2,Definition,definitions),index}}
    case _ "" <> Nil{}: Done{Catalog{List.reverse(&2,Definition,definitions),index}}
    case 0n _: Fail{"item definition count exceeds 4096"}
    case 1n+n line <> rest:
      do Result<&2,&2,String,Catalog>:
        item : Definition <- fields(index,String.split(line,'\t'),definitions)
        rows(n,rest,U32.add(index,1),item <> definitions)

def header_equal(actual:List<&2,String>,expected:List<&2,String>) -> Bool:
  match actual expected:
    case Nil{} Nil{}: True{}
    case head <> rest field <> tail: String.eq(head,field) && header_equal(rest,tail)
    case _ _: False{}

def header_fields() -> List<&2,String>:
  ["item_id","identifier","item_class","description_id","item_default_max_stack_size",
    "default_stack_max_stack_size","default_max_damage","default_damage","default_count",
    "default_empty","default_stackable","default_damageable","fits_inside_container_items",
    "enabled_default_flags","required_features_json","rarity","use_animation","has_foil",
    "enchantable","crafting_remainder_json","default_component_set_id","default_components_sha256",
    "report_components_sha256"]

def header_checked(valid:Bool,rest:List<&2,String>) -> Result<&2,&2,String,Catalog>:
  match valid:
    case True{}: rows(U32.to_nat(4096),rest,0,[])
    case False{}: Fail{"unexpected item definition table header"}

def parse_header(header:List<&2,String>,rest:List<&2,String>) -> Result<&2,&2,String,Catalog>:
  header_checked(header_equal(header,header_fields()),rest)

def parse_lines(lines:List<&2,String>) -> Result<&2,&2,String,Catalog>:
  match lines:
    case head <> rest: parse_header(String.split(head,'\t'),rest)
    case _: Fail{"missing item definition table header"}

def parse_checked(valid:Bool,text:String) -> Result<&2,&2,String,Catalog>:
  match valid:
    case False{}: Fail{"item definition table exceeds 1048576 characters"}
    case True{}: parse_lines(String.split(text,'\n'))

def parse(+text:String) -> Result<&2,&2,String,Catalog>:
  parse_checked(Nat.is_le(String.length(text),U32.to_nat(1048576)),text)

# Compatibility constructors retain the historical three-item test profile.
# The named client/server consumer loads the complete pinned table instead.
def legacy() -> Catalog:
  Catalog{[Definition{1,"minecraft:stone","block.minecraft.stone",64,1386,"5b59e002f4f7936d6af1fe77fc08cdfd019c0ab140dcc2b62f0ce3562be37a6b",True{}},
    Definition{55,"minecraft:dirt","block.minecraft.dirt",64,454,"8cc25b8a8b7ea7bf7b95173f23fde8e1716e70150455faca1feafccb1111def6",True{}},
    Definition{63,"minecraft:oak_planks","block.minecraft.oak_planks",64,805,"b7cfa5f9c09e2124e8f7b46a18eeee35cd08942c68b0a873624b41f3efb8c8b9",True{}}],3}

def count(catalog:Catalog) -> U32:
  Catalog{definitions,count} = catalog
  count

def all(catalog:Catalog) -> List<&2,Definition>:
  Catalog{definitions,count} = catalog
  definitions


law component_patch_cannot_use_default_metadata:
  for catalog:Catalog
  for key:Inv.ItemKey
  {metadata_components(catalog,key,False{}) == None{} : Maybe<&2,Inv.ItemMetadata>}

def component_patch_cannot_use_default_metadata(catalog,key):
  {==}

# Generated from each observed default minecraft:equippable component; player
# armor admission never guesses a slot from the item name. BODY/SADDLE remain
# owned equipment and do not create extra InventoryMenu cells.
def equipment(id:String) -> Maybe<&2,U32>:
  match id:
    case "minecraft:carved_pumpkin": Some{39}
    case "minecraft:white_carpet": Some{41}
    case "minecraft:orange_carpet": Some{41}
    case "minecraft:magenta_carpet": Some{41}
    case "minecraft:light_blue_carpet": Some{41}
    case "minecraft:yellow_carpet": Some{41}
    case "minecraft:lime_carpet": Some{41}
    case "minecraft:pink_carpet": Some{41}
    case "minecraft:gray_carpet": Some{41}
    case "minecraft:light_gray_carpet": Some{41}
    case "minecraft:cyan_carpet": Some{41}
    case "minecraft:purple_carpet": Some{41}
    case "minecraft:blue_carpet": Some{41}
    case "minecraft:brown_carpet": Some{41}
    case "minecraft:green_carpet": Some{41}
    case "minecraft:red_carpet": Some{41}
    case "minecraft:black_carpet": Some{41}
    case "minecraft:saddle": Some{42}
    case "minecraft:white_harness": Some{41}
    case "minecraft:orange_harness": Some{41}
    case "minecraft:magenta_harness": Some{41}
    case "minecraft:light_blue_harness": Some{41}
    case "minecraft:yellow_harness": Some{41}
    case "minecraft:lime_harness": Some{41}
    case "minecraft:pink_harness": Some{41}
    case "minecraft:gray_harness": Some{41}
    case "minecraft:light_gray_harness": Some{41}
    case "minecraft:cyan_harness": Some{41}
    case "minecraft:purple_harness": Some{41}
    case "minecraft:blue_harness": Some{41}
    case "minecraft:brown_harness": Some{41}
    case "minecraft:green_harness": Some{41}
    case "minecraft:red_harness": Some{41}
    case "minecraft:black_harness": Some{41}
    case "minecraft:elytra": Some{38}
    case "minecraft:turtle_helmet": Some{39}
    case "minecraft:wolf_armor": Some{41}
    case "minecraft:leather_helmet": Some{39}
    case "minecraft:leather_chestplate": Some{38}
    case "minecraft:leather_leggings": Some{37}
    case "minecraft:leather_boots": Some{36}
    case "minecraft:copper_helmet": Some{39}
    case "minecraft:copper_chestplate": Some{38}
    case "minecraft:copper_leggings": Some{37}
    case "minecraft:copper_boots": Some{36}
    case "minecraft:chainmail_helmet": Some{39}
    case "minecraft:chainmail_chestplate": Some{38}
    case "minecraft:chainmail_leggings": Some{37}
    case "minecraft:chainmail_boots": Some{36}
    case "minecraft:iron_helmet": Some{39}
    case "minecraft:iron_chestplate": Some{38}
    case "minecraft:iron_leggings": Some{37}
    case "minecraft:iron_boots": Some{36}
    case "minecraft:diamond_helmet": Some{39}
    case "minecraft:diamond_chestplate": Some{38}
    case "minecraft:diamond_leggings": Some{37}
    case "minecraft:diamond_boots": Some{36}
    case "minecraft:golden_helmet": Some{39}
    case "minecraft:golden_chestplate": Some{38}
    case "minecraft:golden_leggings": Some{37}
    case "minecraft:golden_boots": Some{36}
    case "minecraft:netherite_helmet": Some{39}
    case "minecraft:netherite_chestplate": Some{38}
    case "minecraft:netherite_leggings": Some{37}
    case "minecraft:netherite_boots": Some{36}
    case "minecraft:skeleton_skull": Some{39}
    case "minecraft:wither_skeleton_skull": Some{39}
    case "minecraft:player_head": Some{39}
    case "minecraft:zombie_head": Some{39}
    case "minecraft:creeper_head": Some{39}
    case "minecraft:dragon_head": Some{39}
    case "minecraft:piglin_head": Some{39}
    case "minecraft:copper_horse_armor": Some{41}
    case "minecraft:iron_horse_armor": Some{41}
    case "minecraft:golden_horse_armor": Some{41}
    case "minecraft:diamond_horse_armor": Some{41}
    case "minecraft:netherite_horse_armor": Some{41}
    case "minecraft:leather_horse_armor": Some{41}
    case "minecraft:shield": Some{40}
    case "minecraft:iron_nautilus_armor": Some{41}
    case "minecraft:golden_nautilus_armor": Some{41}
    case "minecraft:diamond_nautilus_armor": Some{41}
    case "minecraft:netherite_nautilus_armor": Some{41}
    case "minecraft:copper_nautilus_armor": Some{41}
    case _: None{}
