import Base
import ./core.bend as C
import ./nbt.bend as N
import ./cooking_world_bindings.bend as B
import ./cooking_recipe.bend as Recipe
import ./campfire_authority.bend as Camp
import ./cooking_effect_publication_journal.bend as J

# Internal durable owner image. Preserve the complete Patricia tree, including
# removed-owner counters; a pending notification is never an incarnation source.
type Recovery is Data:
  Recovery{incarnations:Map<&2,Nat>,journal:J.View}

def words(value:String) -> List<&2,U32>:
  match value:
    case SNil{}: []
    case SCon{Chr{word},rest}: word <> words(rest)
def string(value:List<&2,U32>) -> String:
  match value:
    case Nil{}: ""
    case word <> rest: SCon{Chr{word},string(rest)}
def equal_words(a:List<&2,U32>,b:List<&2,U32>) -> Bool:
  match a b:
    case Nil{} Nil{}: True{}
    case x <> xs y <> ys: U32.is_eq(x,y) && equal_words(xs,ys)
    case _ _: False{}
def text(value:String) -> N.Text: N.Text{words(value)}
def name(value:N.Text,expected:String) -> Bool:
  N.Text{units} = value
  equal_words(units,words(expected))
def member(key:String,value:N.Value) -> N.Member: N.Member{text(key),value}
def guard(valid:Bool,message:String) -> Result<&2,&2,String,Unit>:
  match valid:
    case True{}: Done{Unit{}}
    case False{}: Fail{"cooking-publication-recovery:" ++ message}
def nat_value(value:Nat) -> N.Value: N.IntArray{words(Nat.show(value))}
def natural_read(+raw:String,result:Maybe<&2,Nat>) -> Result<&2,&2,String,Nat>:
  match result:
    case None{}: Fail{"cooking-publication-recovery:natural number"}
    case Some{+value}:
      do Result<&2,&2,String,Nat>:
        guard(String.eq(raw,Nat.show(value)) && Nat.is_le(value,J.maximum_sequence()),"noncanonical natural number")
        return value
def nat_read(value:N.Value) -> Result<&2,&2,String,Nat>:
  match value:
    case N.IntArray{units}:
      +raw = string(units)
      do Result<&2,&2,String,Nat>:
        guard(Nat.is_le(String.length(raw),15n),"natural number length")
        natural_read(raw,Nat.read(raw))
    case _: Fail{"cooking-publication-recovery:natural number type"}
def position_value(value:C.Position) -> N.Value:
  C.Position{dimension,x,y,z} = value
  N.Compound{[member("dimension",N.IntArray{words(dimension)}),member("x",N.Int{x}),member("y",N.Int{y}),member("z",N.Int{z})]}
def position_read(value:N.Value) -> Result<&2,&2,String,C.Position>:
  match value:
    case N.Compound{N.Member{a,N.IntArray{dimension}} <> N.Member{b,N.Int{x}} <> N.Member{c,N.Int{y}} <> N.Member{d,N.Int{z}} <> Nil{}}:
      do Result<&2,&2,String,C.Position>:
        guard(name(a,"dimension") && name(b,"x") && name(c,"y") && name(d,"z"),"position schema")
        return C.Position{string(dimension),x,y,z}
    case _: Fail{"cooking-publication-recovery:position schema"}
def family_value(value:B.Family) -> N.Value:
  match value:
    case B.Furnace{Recipe.Smelting{}}: N.Int{0}
    case B.Furnace{Recipe.Blasting{}}: N.Int{1}
    case B.Furnace{Recipe.Smoking{}}: N.Int{2}
    case B.Furnace{Recipe.Campfire{}}: N.Int{3}
    case B.Campfire{Camp.Ordinary{}}: N.Int{4}
    case B.Campfire{Camp.Soul{}}: N.Int{5}
def family_read(value:N.Value) -> Result<&2,&2,String,B.Family>:
  match value:
    case N.Int{0}: Done{B.Furnace{Recipe.Smelting{}}}
    case N.Int{1}: Done{B.Furnace{Recipe.Blasting{}}}
    case N.Int{2}: Done{B.Furnace{Recipe.Smoking{}}}
    case N.Int{3}: Done{B.Furnace{Recipe.Campfire{}}}
    case N.Int{4}: Done{B.Campfire{Camp.Ordinary{}}}
    case N.Int{5}: Done{B.Campfire{Camp.Soul{}}}
    case _: Fail{"cooking-publication-recovery:binding family"}
def bool_read(value:U32) -> Result<&2,&2,String,Bool>:
  match value:
    case 0: Done{False{}}
    case 1: Done{True{}}
    case _: Fail{"cooking-publication-recovery:noncanonical boolean"}
def binding_value(value:B.Binding) -> N.Value:
  B.Binding{state,block,family,lit,dark,bright} = value
  N.Compound{[member("state",N.Int{state}),member("block",N.IntArray{words(block)}),member("family",family_value(family)),
    member("lit",N.Int{Bool.to_u32(lit)}),member("unlit_state",N.Int{dark}),member("lit_state",N.Int{bright})]}
def binding_read(value:N.Value) -> Result<&2,&2,String,B.Binding>:
  match value:
    case N.Compound{N.Member{a,N.Int{state}} <> N.Member{b,N.IntArray{block}} <> N.Member{c,family} <>
        N.Member{d,N.Int{lit}} <> N.Member{e,N.Int{dark}} <> N.Member{f,N.Int{bright}} <> Nil{}}:
      do Result<&2,&2,String,B.Binding>:
        guard(name(a,"state") && name(b,"block") && name(c,"family") && name(d,"lit") && name(e,"unlit_state") && name(f,"lit_state"),"binding schema")
        kind : B.Family <- family_read(family)
        light : Bool <- bool_read(lit)
        return B.Binding{state,string(block),kind,light,dark,bright}
    case _: Fail{"cooking-publication-recovery:binding schema"}
def source_value(value:J.Source) -> N.Value:
  J.Source{position,binding,incarnation} = value
  N.Compound{[member("position",position_value(position)),member("binding",binding_value(binding)),member("incarnation",nat_value(incarnation))]}
def source_checked(+source:J.Source) -> Result<&2,&2,String,J.Source>:
  do Result<&2,&2,String,J.Source>:
    guard(J.source_valid(source),"source structure")
    return source
def source_read(value:N.Value) -> Result<&2,&2,String,J.Source>:
  match value:
    case N.Compound{N.Member{a,position} <> N.Member{b,binding} <> N.Member{c,incarnation} <> Nil{}}:
      do Result<&2,&2,String,J.Source>:
        guard(name(a,"position") && name(b,"binding") && name(c,"incarnation"),"source schema")
        point : C.Position <- position_read(position)
        cached : B.Binding <- binding_read(binding)
        token : Nat <- nat_read(incarnation)
        source_checked(J.Source{point,cached,token})
    case _: Fail{"cooking-publication-recovery:source schema"}
def chunk_value(value:J.Chunk) -> N.Value:
  J.Chunk{dimension,x,z} = value
  N.Compound{[member("dimension",N.IntArray{words(dimension)}),member("x",N.Int{x}),member("z",N.Int{z})]}
def chunk_read(value:N.Value) -> Result<&2,&2,String,J.Chunk>:
  match value:
    case N.Compound{N.Member{a,N.IntArray{dimension}} <> N.Member{b,N.Int{x}} <> N.Member{c,N.Int{z}} <> Nil{}}:
      do Result<&2,&2,String,J.Chunk>:
        guard(name(a,"dimension") && name(b,"x") && name(c,"z"),"chunk schema")
        return J.Chunk{string(dimension),x,z}
    case _: Fail{"cooking-publication-recovery:chunk schema"}
def dirty_value(value:J.DirtyChunk) -> N.Value:
  J.DirtyChunk{chunk,sequence} = value
  N.Compound{[member("chunk",chunk_value(chunk)),member("sequence",nat_value(sequence))]}
def dirty_read(value:N.Value) -> Result<&2,&2,String,J.DirtyChunk>:
  match value:
    case N.Compound{N.Member{a,chunk} <> N.Member{b,sequence} <> Nil{}}:
      do Result<&2,&2,String,J.DirtyChunk>:
        guard(name(a,"chunk") && name(b,"sequence"),"dirty chunk schema")
        target : J.Chunk <- chunk_read(chunk)
        revision : Nat <- nat_read(sequence)
        return J.DirtyChunk{target,revision}
    case _: Fail{"cooking-publication-recovery:dirty chunk schema"}
def dirty_values(values:List<&2,J.DirtyChunk>) -> List<&2,N.Value>:
  match values:
    case Nil{}: []
    case head <> rest: dirty_value(head) <> dirty_values(rest)
def dirties_read(values:List<&2,N.Value>) -> Result<&2,&2,String,List<&2,J.DirtyChunk>>:
  match values:
    case Nil{}: Done{[]}
    case head <> rest:
      do Result<&2,&2,String,List<&2,J.DirtyChunk>>:
        first : J.DirtyChunk <- dirty_read(head)
        tail : List<&2,J.DirtyChunk> <- dirties_read(rest)
        return first <> tail
def dirty_list_read(value:N.Value) -> Result<&2,&2,String,List<&2,J.DirtyChunk>>:
  match value:
    case N.ListTag{10,values}: dirties_read(values)
    case _: Fail{"cooking-publication-recovery:dirty list schema"}
def receipt_value(value:J.Receipt) -> N.Value:
  J.Receipt{position,source,chunk,sequence} = value
  N.Compound{[member("position",position_value(position)),member("source",source_value(source)),
    member("chunk",chunk_value(chunk)),member("sequence",nat_value(sequence))]}
def receipt_read(value:N.Value) -> Result<&2,&2,String,J.Receipt>:
  match value:
    case N.Compound{N.Member{a,position} <> N.Member{b,source} <> N.Member{c,chunk} <> N.Member{d,sequence} <> Nil{}}:
      do Result<&2,&2,String,J.Receipt>:
        guard(name(a,"position") && name(b,"source") && name(c,"chunk") && name(d,"sequence"),"receipt schema")
        point : C.Position <- position_read(position)
        producer : J.Source <- source_read(source)
        target : J.Chunk <- chunk_read(chunk)
        revision : Nat <- nat_read(sequence)
        return J.Receipt{point,producer,target,revision}
    case _: Fail{"cooking-publication-recovery:receipt schema"}
def optional_receipt_value(value:Maybe<&2,J.Receipt>) -> N.Value:
  match value:
    case None{}: N.ListTag{10,[]}
    case Some{receipt}: N.ListTag{10,[receipt_value(receipt)]}
def optional_receipt_read(value:N.Value) -> Result<&2,&2,String,Maybe<&2,J.Receipt>>:
  match value:
    case N.ListTag{10,Nil{}}: Done{None{}}
    case N.ListTag{10,first <> Nil{}}:
      Result.map(&2,&2,String,J.Receipt,Maybe<&2,J.Receipt>,receipt => Some{receipt},receipt_read(first))
    case _: Fail{"cooking-publication-recovery:optional receipt schema"}
def journal_value(value:J.View) -> N.Value:
  J.View{sequence,unsaved,last} = value
  N.Compound{[member("sequence",nat_value(sequence)),member("unsaved",N.ListTag{10,dirty_values(unsaved)}),member("last",optional_receipt_value(last))]}
def journal_checked(+view:J.View) -> Result<&2,&2,String,J.View>:
  do Result<&2,&2,String,J.View>:
    guard(J.view_valid(view),"journal structure")
    return view
def journal_read(value:N.Value) -> Result<&2,&2,String,J.View>:
  match value:
    case N.Compound{N.Member{a,sequence} <> N.Member{b,unsaved} <> N.Member{c,last} <> Nil{}}:
      do Result<&2,&2,String,J.View>:
        guard(name(a,"sequence") && name(b,"unsaved") && name(c,"last"),"journal schema")
        revision : Nat <- nat_read(sequence)
        dirty : List<&2,J.DirtyChunk> <- dirty_list_read(unsaved)
        recent : Maybe<&2,J.Receipt> <- optional_receipt_read(last)
        journal_checked(J.View{revision,dirty,recent})
    case _: Fail{"cooking-publication-recovery:journal schema"}

def map_value(value:Map<&2,Nat>) -> N.Value:
  match value:
    case MTip{}: N.Compound{[member("kind",N.Int{0})]}
    case MLeaf{key,value}:
      N.Compound{[member("kind",N.Int{1}),member("key",N.IntArray{words(key)}),member("value",nat_value(value))]}
    case MNode{position,lo,hi}:
      N.Compound{[member("kind",N.Int{2}),member("position",nat_value(position)),member("lo",map_value(lo)),member("hi",map_value(hi))]}
def map_read(value:N.Value) -> Result<&2,&2,String,Map<&2,Nat>>:
  match value:
    case N.Compound{N.Member{a,N.Int{0}} <> Nil{}}:
      do Result<&2,&2,String,Map<&2,Nat>>:
        guard(name(a,"kind"),"map tip schema")
        return MTip{}
    case N.Compound{N.Member{a,N.Int{1}} <> N.Member{b,N.IntArray{key}} <> N.Member{c,value} <> Nil{}}:
      do Result<&2,&2,String,Map<&2,Nat>>:
        guard(name(a,"kind") && name(b,"key") && name(c,"value"),"map leaf schema")
        token : Nat <- nat_read(value)
        return MLeaf{string(key),token}
    case N.Compound{N.Member{a,N.Int{2}} <> N.Member{b,position} <> N.Member{c,lo} <> N.Member{d,hi} <> Nil{}}:
      do Result<&2,&2,String,Map<&2,Nat>>:
        guard(name(a,"kind") && name(b,"position") && name(c,"lo") && name(d,"hi"),"map node schema")
        bit : Nat <- nat_read(position)
        left : Map<&2,Nat> <- map_read(lo)
        right : Map<&2,Nat> <- map_read(hi)
        return MNode{bit,left,right}
    case _: Fail{"cooking-publication-recovery:map schema"}
def map_nonempty(value:Map<&2,Nat>) -> Bool:
  match value:
    case MTip{}: False{}
    case _: True{}
def map_first(value:Map<&2,Nat>) -> String:
  match value:
    case MTip{}: ""
    case MLeaf{key,value}: key
    case MNode{position,lo,hi}: map_first(lo)
def bit_matches(result:String & Bool,expected:Bool) -> Bool:
  (key,bit) = result
  Bool.not(Bool.xor(bit,expected))
def coordinate_key_valid(+raw:String,result:Maybe<&2,U32>) -> Bool:
  match result:
    case None{}: False{}
    case Some{value}: String.eq(raw,U32.show(value))
def coordinate_key(+raw:String) -> Bool:
  Nat.is_le(String.length(raw),10n) && coordinate_key_valid(raw,U32.read(raw))
def incarnation_key_parts(values:List<&2,String>) -> Bool:
  match values:
    case dimension <> x <> y <> z <> Nil{}:
      C.dimension_known(dimension) && coordinate_key(x) && coordinate_key(y) && coordinate_key(z)
    case _: False{}
def incarnation_key_valid(value:String) -> Bool:
  incarnation_key_parts(String.split(value,Chr{47}))
def map_partition(value:Map<&2,Nat>,+position:Nat,+representative:String,+high:Bool) -> Bool:
  match value:
    case MTip{}: False{}
    case MLeaf{+key,value}:
      Nat.is_ge(Map.diff(key,representative),position) && bit_matches(Map.bit(key,position),high)
    case MNode{at,lo,hi}:
      map_partition(lo,position,representative,high) && map_partition(hi,position,representative,high)
def map_after(value:Map<&2,Nat>,position:Nat) -> Bool:
  match value:
    case MNode{at,lo,hi}: Nat.is_gt(at,position)
    case _: True{}
def map_valid(value:Map<&2,Nat>) -> Bool:
  match value:
    case MTip{}: True{}
    case MLeaf{key,token}: incarnation_key_valid(key) && Nat.is_le(token,J.maximum_sequence())
    case MNode{+position,+lo,+hi}:
      Nat.is_le(position,J.maximum_sequence()) && map_nonempty(lo) && map_nonempty(hi) &&
        Nat.is_eq(Map.diff(map_first(lo),map_first(hi)),position) &&
        map_partition(lo,position,map_first(lo),False{}) && map_partition(hi,position,map_first(lo),True{}) &&
        map_after(lo,position) && map_after(hi,position) && map_valid(lo) && map_valid(hi)
def counter_checked(incarnation:Nat,result:Map<&2,Nat> & Nat) -> Bool:
  (values,current) = result
  Nat.is_le(incarnation,current)
def receipt_counter_valid(values:Map<&2,Nat>,last:Maybe<&2,J.Receipt>) -> Bool:
  match last:
    case None{}: True{}
    case Some{J.Receipt{position,J.Source{source,binding,incarnation},chunk,sequence}}:
      counter_checked(incarnation,Map.get(Nat,0n,values,B.key(position)))
def recovery_valid_counters(values:Map<&2,Nat>,journal:J.View) -> Bool:
  J.View{sequence,unsaved,last} = journal
  receipt_counter_valid(values,last)
def root(value:Recovery) -> N.Root:
  Recovery{incarnations,journal} = value
  N.Root{text("bendex:cooking-publication"),N.Compound{[member("format",N.Int{1}),member("incarnations",map_value(incarnations)),member("journal",journal_value(journal))]}}
def root_read(value:N.Root) -> Result<&2,&2,String,Recovery>:
  match value:
    case N.Root{n,N.Compound{N.Member{a,N.Int{1}} <> N.Member{b,incarnations} <> N.Member{c,journal} <> Nil{}}}:
      do Result<&2,&2,String,Recovery>:
        guard(name(n,"bendex:cooking-publication") && name(a,"format") && name(b,"incarnations") && name(c,"journal"),"root schema")
        +counters : Map<&2,Nat> <- map_read(incarnations)
        guard(map_valid(counters),"incarnation map structure")
        +history : J.View <- journal_read(journal)
        guard(recovery_valid_counters(counters,history),"receipt incarnation exceeds retained counter")
        return Recovery{counters,history}
    case _: Fail{"cooking-publication-recovery:root schema"}
def encode(limits:N.Limits,+value:Recovery) -> Result<&2,&2,String,List<&2,U32>>:
  Recovery{+incarnations,+journal} = value
  do Result<&2,&2,String,List<&2,U32>>:
    guard(map_valid(incarnations),"incarnation map structure")
    guard(J.view_valid(journal),"journal structure")
    guard(recovery_valid_counters(incarnations,journal),"receipt incarnation exceeds retained counter")
    N.encode_with(limits,root(value))
def decode(limits:N.Limits,bytes:List<&2,U32>) -> Result<&2,&2,String,Recovery>:
  Result.bind(&2,&2,String,N.Root,Recovery,N.decode_with(limits,bytes),root_read)
