import Base
import ./core.bend as C
import ./game.bend as G
import ./cooking_recipe.bend as Recipe
import ./cooking_world_bindings.bend as B
import ./cooking_effect_publication_journal.bend as J
import ./cooking_effect_publication.bend as Publication

# These positions exercise the actual signed section-coordinate conversion:
# the first two positions share chunk (0,0), while the third is chunk (1,2).
def first_position() -> C.Position: C.Position{"minecraft:overworld",15,8,15}
def later_same_chunk_position() -> C.Position: C.Position{"minecraft:overworld",0,42,0}
def later_other_chunk_position() -> C.Position: C.Position{"minecraft:overworld",16,8,32}
def first_chunk() -> J.Chunk: J.Chunk{"minecraft:overworld",0,0}
def other_chunk() -> J.Chunk: J.Chunk{"minecraft:overworld",1,2}

# One immutable snapshot is obtained from the actual owner after its first
# mark. A second actual mark happens before the saved snapshot commits.
# In particular, this is not a replacement implementation of retained().
def after_latest(saved:J.Snapshot,result:J.State & J.Receipt) -> J.State:
  (owner,latest) = result
  J.save_completed(owner,Done{J.FullCookingSaveCommitted{saved}})
def after_snapshot(later:C.Position,later_source:J.Source,result:J.State & J.Snapshot) -> J.State:
  (owner,saved) = result
  after_latest(saved,J.marked(later,later_source,owner))
def after_first(later:C.Position,later_source:J.Source,result:J.State & J.Receipt) -> J.State:
  (owner,receipt) = result
  after_snapshot(later,later_source,J.snapshot(owner))
def commit_older_snapshot(first:J.Source,+later:C.Position,later_source:J.Source) -> J.State:
  after_first(later,later_source,J.marked(first_position(),first,J.new()))

# Both actual vanilla state bindings are registered independently. The
# catalogue is deliberately a small fixture; this contract does not claim
# authentication of an arbitrary Registry or run neighbour receivers.
def furnace(+lit:Bool) -> B.Binding:
  B.Binding{Bool.pick(U32,lit,6883,6884),"minecraft:furnace",
    B.Furnace{Recipe.Smelting{}},lit,6884,6883}
def bindings() -> B.Catalog:
  B.Catalog{"publication-law-fixture",6885,
    Map.set(&2,Maybe<&2,B.Binding>,
      Map.set(&2,Maybe<&2,B.Binding>,MTip{},"6884",Some{furnace(False{})}),
      "6883",Some{furnace(True{})})}
def source(lit:Bool,incarnation:Nat) -> J.Source:
  J.Source{first_position(),furnace(lit),incarnation}

# The error may originate in encoding, writing or atomic commit. No receipt,
# revision, unsaved entry, or nested Source in the complete owner is replaced.
law failed_full_save_retains_complete_journal:
  for owner:J.State
  for message:String
  {J.save_completed(owner,Fail{message}) == owner : J.State}

# A future snapshot is inadmissible even when its chunks would otherwise
# match every unsaved entry. The statement quantifies over the complete View
# and does not assume that install() has supplied a canonical journal.
law future_snapshot_cannot_clear_complete_journal:
  for sequence:Nat
  for unsaved:List<&2,J.DirtyChunk>
  for last:Maybe<&2,J.Receipt>
  for saved:Nat
  for chunks:List<&2,J.DirtyChunk>
  for future:{Nat.is_le(saved,sequence) == False{} : Bool}
  {J.save_completed(J.State{J.View{sequence,unsaved,last}},
      Done{J.FullCookingSaveCommitted{J.Snapshot{saved,chunks}}}) ==
    J.State{J.View{sequence,unsaved,last}} : J.State}

# A repeated mark must replace every obsolete entry for the actual chunk,
# retain the other chunk and publish the next monotonic receipt. The full
# arbitrary captured Source is retained in both returned receipt locations.
law repeated_mark_deduplicates_actual_chunk_and_advances_receipt:
  for captured:J.Source
  for last:Maybe<&2,J.Receipt>
  {J.marked(first_position(),captured,
      J.State{J.View{3n,
        [J.DirtyChunk{first_chunk(),1n},J.DirtyChunk{other_chunk(),2n},
         J.DirtyChunk{first_chunk(),3n}],last}}) ==
    (J.State{J.View{4n,
       [J.DirtyChunk{first_chunk(),4n},J.DirtyChunk{other_chunk(),2n}],
       Some{J.Receipt{first_position(),captured,first_chunk(),4n}}}},
     J.Receipt{first_position(),captured,first_chunk(),4n}) : J.State & J.Receipt}

# The save contains revision1 of this chunk. Its later revision2 and the
# latest complete receipt survive the successful commit of that old save.
law older_actual_save_preserves_later_same_chunk_and_latest_receipt:
  for first:J.Source
  for later:J.Source
  {commit_older_snapshot(first,later_same_chunk_position(),later) ==
    J.State{J.View{2n,[J.DirtyChunk{first_chunk(),2n}],
      Some{J.Receipt{later_same_chunk_position(),later,first_chunk(),2n}}}} : J.State}

# This is the complementary real chronology: the saved chunk is cleared,
# while the later different chunk and its complete latest receipt survive.
law older_actual_save_clears_only_saved_chunk_and_preserves_latest_receipt:
  for first:J.Source
  for later:J.Source
  {commit_older_snapshot(first,later_other_chunk_position(),later) ==
    J.State{J.View{2n,[J.DirtyChunk{other_chunk(),2n}],
      Some{J.Receipt{later_other_chunk_position(),later,other_chunk(),2n}}}} : J.State}

# The actual publisher cannot turn a producer-captured Source into a dirty
# receipt without attestation from the current owned block entity. This
# branch retains the complete Engine and arbitrary complete journal owner.
law missing_current_source_retains_complete_engine_and_journal:
  for engine:G.Engine
  for owner:J.State
  {Publication.dirty(engine,Publication.Context{bindings()},source(False{},7n),
      None{},first_position(),owner) ==
    (engine,owner,Fail{"cooking-publication:current-block-entity-owner-required"}) :
    G.Engine & J.State & Result<&2,&2,String,J.Receipt>}

# LIT does not change the block-entity owner: both individually registered
# bindings with the same family and incarnation attest successfully. A
# replacement incarnation refuses the actual publisher before Core reads or
# journal mutation, retaining every part of its two affine owners.
law lit_change_attests_same_owner_and_new_incarnation_retains_owners:
  for engine:G.Engine
  for owner:J.State
  {(Publication.sources(bindings(),source(False{},7n),Some{source(True{},7n)}),
    Publication.dirty(engine,Publication.Context{bindings()},source(False{},7n),
      Some{source(True{},8n)},first_position(),owner)) ==
    (Done{source(True{},7n)},
     (engine,owner,Fail{"cooking-publication:stale-block-entity-incarnation"})) :
    Result<&2,&2,String,J.Source> &
      (G.Engine & J.State & Result<&2,&2,String,J.Receipt>)}
