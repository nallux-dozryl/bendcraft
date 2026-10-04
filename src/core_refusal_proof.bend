import Base
import ./core.bend as C
import ./schedule.bend as Q
import ./section_map.bend as M
import ./section_map_update.bend as U
import ./section_map_update_laws.bend as UpdateLaws
import ./section_map_update_proof.bend as UpdateProof
import ./section.bend as S
import ./core_refusal_laws.bend as L

def L.duplicate_apply_retains_complete_world(tick,time,paused,daylight,revision,count,sections,pending,events,position,fill,exists):
  %Equal.sym(M.Sections & Result<&2,&2,U.Error,Unit>,U.create(sections,C.section_key(position),fill),(sections,Fail{U.Existing{}}),UpdateLaws.duplicate_create_retains_complete_map(sections,C.section_key(position),fill,exists)) :
    {C.updated_sections(C.World{tick,time,paused,daylight,revision,count,M.EmptySections{},pending,events},position,_) ==
      (C.World{tick,time,paused,daylight,revision,count,sections,pending,events},Fail{C.SectionExists{C.section_key(position)}}) : C.World & Result<&2,&2,C.Error,Unit>}
  {==}

def L.missing_apply_retains_complete_world(tick,time,paused,daylight,revision,count,sections,pending,events,position,state,absent):
  match position:
    case C.Position{dimension,x,y,z}:
      %Equal.sym(M.Sections & Result<&2,&2,U.Error,Unit>,U.write(sections,C.section_key(C.Position{dimension,x,y,z}),S.Coord.local(x),S.Coord.local(y),S.Coord.local(z),state),(sections,Fail{U.Missing{}}),UpdateLaws.missing_write_retains_complete_map(sections,C.section_key(C.Position{dimension,x,y,z}),S.Coord.local(x),S.Coord.local(y),S.Coord.local(z),state,absent)) :
        {C.updated_sections(C.World{tick,time,paused,daylight,revision,count,M.EmptySections{},pending,events},C.Position{dimension,x,y,z},_) ==
          (C.World{tick,time,paused,daylight,revision,count,sections,pending,events},Fail{C.MissingSection{C.section_key(C.Position{dimension,x,y,z})}}) : C.World & Result<&2,&2,C.Error,Unit>}
      {==}

def L.section_refusal_composition_preserves_complete_world(tick,time,paused,daylight,revision,count,sections,pending,events,position,error): {==}

def L.malformed_create_apply_retains_complete_world(tick,time,paused,daylight,revision,count,sections,pending,events,position,fill,malformed):
  %Equal.sym(M.Sections & Result<&2,&2,U.Error,Unit>,U.create(sections,C.section_key(position),fill),(sections,Fail{U.Malformed{}}),UpdateLaws.malformed_create_retains_complete_map(sections,C.section_key(position),fill,malformed)) :
    {C.updated_sections(C.World{tick,time,paused,daylight,revision,count,M.EmptySections{},pending,events},position,_) ==
      (C.World{tick,time,paused,daylight,revision,count,sections,pending,events},Fail{C.InvalidCoordinate{}}) : C.World & Result<&2,&2,C.Error,Unit>}
  {==}
