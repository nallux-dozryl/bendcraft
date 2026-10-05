import Base
import ./game.bend as G
import ./core.bend as C
import ./local_player_cooking_publication_owner.bend as P
import ./local_player_cooking_publication.bend as Publication
import ./local_player_cooking_entity_owner.bend as Owner
import ./local_player_cooking_geometry_owner.bend as Geometry
import ./local_player_cooking.bend as K
import ./local_player_session.bend as S
import ./cooking_effect_publication.bend as Publisher
import ./cooking_effect_publication_journal.bend as J
import ./cooking_effect_entities_model.bend as E
import ./cooking_world.bend as CW
import ./cooking_world_store.bend as Store
import ./block_light.bend as Light
import ./block_light_world.bend as BW
import ./random.bend as Random
import ./extended_persistence.bend as Persistence

# A failed writer cannot clear the publication journal, including an arbitrary
# recursive carrier tail. This is the actual carrier consumer of SaveCommit.
law failed_save_retains_complete_publication_owner:
  for context:Publisher.Context
  for journal:J.State
  for tail:List<&1,P.Carrier>
  for message:String
  {P.save_completed(P.Bound{context,journal,tail},Fail{message}) ==
    P.Bound{context,journal,tail} : P.Carrier}

# A refused journal operation cannot change the entity/RNG/geometry domain.
# The returned publisher is the actual operation's owner; no copy is made.
law publisher_return_retains_complete_entity_owner:
  for context:E.Context
  for state:E.State
  for times:List<&2,Random.Bits64>
  for geometry:Maybe<&1,Geometry.Owner>
  for returned:P.Carrier
  for status:Result<&2,&2,String,Unit>
  {Owner.publisher_returned(Result<&2,&2,String,Unit>,
      publisher => Owner.Bound{context,state,times,geometry,publisher},(returned,status)) ==
    (Owner.Bound{context,state,times,geometry,returned},status) :
    Owner.Carrier & Result<&2,&2,String,Unit>}

# The complete live sidecar survives a refused full save, with physical bodies,
# lifecycle metadata, entity/RNG/clocks/geometry and both recursive tails.
law failed_save_retains_complete_cooking_sidecar:
  for context:K.Context
  for light:Light.State
  for loading:Maybe<&2,BW.Cursor>
  for entries:List<&1,Store.Entry>
  for phase:CW.Phase
  for keys:List<&2,String>
  for effects:List<&2,Store.Effect>
  for details:List<&2,K.BodyDetails>
  for incarnations:Map<&2,Nat>
  for acknowledged:Nat
  for entity_context:E.Context
  for state:E.State
  for times:List<&2,Random.Bits64>
  for geometry:Maybe<&1,Geometry.Owner>
  for publisher_context:Publisher.Context
  for journal:J.State
  for publisher_tail:List<&1,P.Carrier>
  for tail:List<&1,K.Sidecar>
  for message:String
  {Publication.save_completed(K.Initialized{context,light,loading,entries,phase,keys,effects,details,
      incarnations,acknowledged,Owner.Bound{entity_context,state,times,geometry,
        P.Bound{publisher_context,journal,publisher_tail}},tail},Fail{message}) ==
    K.Initialized{context,light,loading,entries,phase,keys,effects,details,
      incarnations,acknowledged,Owner.Bound{entity_context,state,times,geometry,
        P.Bound{publisher_context,journal,publisher_tail}},tail} : K.Sidecar}

# NotCommitted includes PublishedUnsynced. The actual typed writer receipt,
# rather than the successful JSON reply, controls this live acknowledgement.
law nondurable_receipt_retains_complete_session:
  for state:S.State
  for snapshot:Maybe<&2,J.Snapshot>
  {S.cooking_save_completed(state,snapshot,Persistence.NotCommitted{}) == state : S.State}

law absent_save_snapshot_retains_complete_session:
  for state:S.State
  for receipt:Persistence.SaveCompletion
  {S.cooking_save_completed(state,None{},receipt) == state : S.State}

# Actual journal admission refuses a noncanonical affine tail before Core or
# journal publication. All caller-owned Engine fields are retained by value.
law noncanonical_publication_tail_retains_complete_owner:
  for engine:G.Engine
  for context:Publisher.Context
  for journal:J.State
  for child:P.Carrier
  for tail:List<&1,P.Carrier>
  for producer:J.Source
  for current:Maybe<&2,J.Source>
  for position:C.Position
  {P.dirty_at(engine,P.Bound{context,journal,child <> tail},producer,current,position) ==
    (engine,P.Bound{context,journal,child <> tail},Fail{"local-cooking:noncanonical-publication-tail"}) :
    G.Engine & P.Carrier & Result<&2,&2,String,Unit>}
