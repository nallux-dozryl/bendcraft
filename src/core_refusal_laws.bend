import Base
import ./core.bend as C
import ./schedule.bend as Q
import ./section_map.bend as M
import ./section_map_update.bend as U
import ./section_map_update_laws.bend as UpdateLaws
import ./section.bend as S

law duplicate_apply_retains_complete_world:
  for +tick:Nat
  for +time:Nat
  for +paused:Bool
  for +daylight:Bool
  for +revision:Nat
  for +count:U32
  for sections:M.Sections
  for +pending:List<&2,Q.Pending<C.Mutation>>
  for +events:List<&2,C.CoreEvent>
  for +position:C.Position
  for fill:U32
  for exists:{U.present(U.path(32n,M.hash(C.section_key(position))),sections,C.section_key(position)) == True{} : Bool}
  {C.apply(C.World{tick,time,paused,daylight,revision,count,sections,pending,events},C.SectionCreate{position,fill}) ==
    (C.World{tick,time,paused,daylight,revision,count,sections,pending,events},Fail{C.SectionExists{C.section_key(position)}}) : C.World & Result<&2,&2,C.Error,Unit>}

law missing_apply_retains_complete_world:
  for +tick:Nat
  for +time:Nat
  for +paused:Bool
  for +daylight:Bool
  for +revision:Nat
  for +count:U32
  for sections:M.Sections
  for +pending:List<&2,Q.Pending<C.Mutation>>
  for +events:List<&2,C.CoreEvent>
  for +position:C.Position
  for state:U32
  for absent:{U.present(U.path(32n,M.hash(C.section_key(position))),sections,C.section_key(position)) == False{} : Bool}
  {C.apply(C.World{tick,time,paused,daylight,revision,count,sections,pending,events},C.BlockSet{position,state}) ==
    (C.World{tick,time,paused,daylight,revision,count,sections,pending,events},Fail{C.MissingSection{C.section_key(position)}}) : C.World & Result<&2,&2,C.Error,Unit>}

# This is the actual Core consumer of a Section rejection. World-coordinate
# callers supply Coord.local, so invalid raw locals occur at the map interface.
law section_refusal_composition_preserves_complete_world:
  for +tick:Nat
  for +time:Nat
  for +paused:Bool
  for +daylight:Bool
  for +revision:Nat
  for +count:U32
  for sections:M.Sections
  for +pending:List<&2,Q.Pending<C.Mutation>>
  for +events:List<&2,C.CoreEvent>
  for position:C.Position
  for error:S.Section.Error
  {C.updated_sections(C.World{tick,time,paused,daylight,revision,count,M.EmptySections{},pending,events},position,
    (sections,Fail{U.SectionRejected{error}})) ==
    (C.World{tick,time,paused,daylight,revision,count,sections,pending,events},Fail{C.InvalidCoordinate{}}) : C.World & Result<&2,&2,C.Error,Unit>}

law malformed_create_apply_retains_complete_world:
  for +tick:Nat
  for +time:Nat
  for +paused:Bool
  for +daylight:Bool
  for +revision:Nat
  for +count:U32
  for sections:M.Sections
  for +pending:List<&2,Q.Pending<C.Mutation>>
  for +events:List<&2,C.CoreEvent>
  for +position:C.Position
  for fill:U32
  for malformed:{UpdateLaws.valid_route(U.path(32n,M.hash(C.section_key(position))),sections) == False{} : Bool}
  {C.apply(C.World{tick,time,paused,daylight,revision,count,sections,pending,events},C.SectionCreate{position,fill}) ==
    (C.World{tick,time,paused,daylight,revision,count,sections,pending,events},Fail{C.InvalidCoordinate{}}) : C.World & Result<&2,&2,C.Error,Unit>}
