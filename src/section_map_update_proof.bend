import Base
import ./section_map_update.bend as U
import ./section_map.bend as M
import ./section.bend as S
import ./section_proof.bend as SectionProof
import ./section_laws.bend as SectionLaws
import ./section_map_update_laws.bend as L

def L.false_is_not_true(contradiction):
  %Equal.sym(Bool,False{},True{},contradiction) : L.truth_type(_)
  Unit{}

def L.true_is_not_false(contradiction):
  L.false_is_not_true(Equal.sym(Bool,True{},False{},contradiction))

def L.bucket_membership_retains_complete_owner(entries,key):
  match entries:
    case Nil{}: {==}
    case M.Entry{candidate,section} <> tail:
      %Equal.sym(List<&1,M.Entry> & Bool,U.contains(tail,key),(tail,U.member(U.keys(tail),key)),L.bucket_membership_retains_complete_owner(tail,key)) :
        {U.presence_head(M.Entry{candidate,section},String.eq(candidate,key),_) ==
          (M.Entry{candidate,section} <> tail,U.member(U.keys(M.Entry{candidate,section} <> tail),key)) : List<&1,M.Entry> & Bool}
      {==}

def L.bucket_count_retains_complete_owner(entries):
  match entries:
    case Nil{}: {==}
    case M.Entry{candidate,section} <> tail:
      %Equal.sym(List<&1,M.Entry> & Nat,U.count(tail),(tail,List.length(&2,String,U.keys(tail))),L.bucket_count_retains_complete_owner(tail)) :
        {U.counted_head(M.Entry{candidate,section},_) == (M.Entry{candidate,section} <> tail,List.length(&2,String,U.keys(M.Entry{candidate,section} <> tail))) : List<&1,M.Entry> & Nat}
      {==}

def L.duplicate_bucket_refuses_without_reordering(entries,key,fill,exists):
  %Equal.sym(List<&1,M.Entry> & Bool,U.contains(entries,key),(entries,U.member(U.keys(entries),key)),L.bucket_membership_retains_complete_owner(entries,key)) :
    {U.create_bucket(key,fill,_) == (M.Bucket{entries},Fail{U.Existing{}}) : M.Sections & Result<&2,&2,U.Error,Unit>}
  %Equal.sym(Bool,U.member(U.keys(entries),key),True{},exists) :
    {U.created(entries,key,fill,_) == (M.Bucket{entries},Fail{U.Existing{}}) : M.Sections & Result<&2,&2,U.Error,Unit>}
  {==}

def L.missing_bucket_write_retains_all_entries(entries,key,x,y,z,state,absent):
  %Equal.sym(List<&1,M.Entry> & Bool,U.contains(entries,key),(entries,U.member(U.keys(entries),key)),L.bucket_membership_retains_complete_owner(entries,key)) :
    {U.write_leaf(key,x,y,z,state,_) == (M.Bucket{entries},Fail{U.Missing{}}) : M.Sections & Result<&2,&2,U.Error,Unit>}
  %Equal.sym(Bool,U.member(U.keys(entries),key),False{},absent) :
    {U.write_present(entries,key,x,y,z,state,_) == (M.Bucket{entries},Fail{U.Missing{}}) : M.Sections & Result<&2,&2,U.Error,Unit>}
  {==}

def L.invalid_local_bucket_write_retains_every_array_and_entry(entries,key,x,y,z,state,exists,invalid):
  %Equal.sym(List<&1,M.Entry> & Bool,U.contains(entries,key),(entries,U.member(U.keys(entries),key)),L.bucket_membership_retains_complete_owner(entries,key)) :
    {U.write_leaf(key,x,y,z,state,_) == (M.Bucket{entries},Fail{U.SectionRejected{S.BadLocal{x,y,z}}}) : M.Sections & Result<&2,&2,U.Error,Unit>}
  %Equal.sym(Bool,U.member(U.keys(entries),key),True{},exists) :
    {U.write_present(entries,key,x,y,z,state,_) == (M.Bucket{entries},Fail{U.SectionRejected{S.BadLocal{x,y,z}}}) : M.Sections & Result<&2,&2,U.Error,Unit>}
  %Equal.sym(Result<&2,&2,S.Section.Error,U32>,S.Section.local_index(x,y,z),Fail{S.BadLocal{x,y,z}},SectionLaws.local_index_rejects(x,y,z,invalid)) :
    {U.write_checked(entries,key,x,y,z,state,_) == (M.Bucket{entries},Fail{U.SectionRejected{S.BadLocal{x,y,z}}}) : M.Sections & Result<&2,&2,U.Error,Unit>}
  {==}

def L.duplicate_path_create_retains_complete_trie(route,sections,key,fill,exists):
  match route sections:
    case Nil{} M.Bucket{entries}: L.duplicate_bucket_refuses_without_reordering(entries,key,fill,exists)
    case False{} <> rest M.Branch{lo,hi}:
      %Equal.sym(M.Sections & Result<&2,&2,U.Error,Unit>,U.create_at(rest,lo,key,fill),(lo,Fail{U.Existing{}}),L.duplicate_path_create_retains_complete_trie(rest,lo,key,fill,exists)) :
        {U.left(hi,_) == (M.Branch{lo,hi},Fail{U.Existing{}}) : M.Sections & Result<&2,&2,U.Error,Unit>}
      {==}
    case True{} <> rest M.Branch{lo,hi}:
      %Equal.sym(M.Sections & Result<&2,&2,U.Error,Unit>,U.create_at(rest,hi,key,fill),(hi,Fail{U.Existing{}}),L.duplicate_path_create_retains_complete_trie(rest,hi,key,fill,exists)) :
        {U.right(lo,_) == (M.Branch{lo,hi},Fail{U.Existing{}}) : M.Sections & Result<&2,&2,U.Error,Unit>}
      {==}
    case Nil{} M.EmptySections{}: Empty.absurd({U.create_at([],M.EmptySections{},key,fill) == (M.EmptySections{},Fail{U.Existing{}}) : M.Sections & Result<&2,&2,U.Error,Unit>},L.false_is_not_true(exists))
    case Nil{} M.Branch{lo,hi}: Empty.absurd({U.create_at([],M.Branch{lo,hi},key,fill) == (M.Branch{lo,hi},Fail{U.Existing{}}) : M.Sections & Result<&2,&2,U.Error,Unit>},L.false_is_not_true(exists))
    case head <> rest M.EmptySections{}: Empty.absurd({U.create_at(head <> rest,M.EmptySections{},key,fill) == (M.EmptySections{},Fail{U.Existing{}}) : M.Sections & Result<&2,&2,U.Error,Unit>},L.false_is_not_true(exists))
    case head <> rest M.Bucket{entries}: Empty.absurd({U.create_at(head <> rest,M.Bucket{entries},key,fill) == (M.Bucket{entries},Fail{U.Existing{}}) : M.Sections & Result<&2,&2,U.Error,Unit>},L.false_is_not_true(exists))

def L.missing_path_write_retains_complete_trie(route,sections,key,x,y,z,state,absent):
  match route sections:
    case Nil{} M.Bucket{entries}: L.missing_bucket_write_retains_all_entries(entries,key,x,y,z,state,absent)
    case False{} <> rest M.Branch{lo,hi}:
      %Equal.sym(M.Sections & Result<&2,&2,U.Error,Unit>,U.write_at(rest,lo,key,x,y,z,state),(lo,Fail{U.Missing{}}),L.missing_path_write_retains_complete_trie(rest,lo,key,x,y,z,state,absent)) :
        {U.left(hi,_) == (M.Branch{lo,hi},Fail{U.Missing{}}) : M.Sections & Result<&2,&2,U.Error,Unit>}
      {==}
    case True{} <> rest M.Branch{lo,hi}:
      %Equal.sym(M.Sections & Result<&2,&2,U.Error,Unit>,U.write_at(rest,hi,key,x,y,z,state),(hi,Fail{U.Missing{}}),L.missing_path_write_retains_complete_trie(rest,hi,key,x,y,z,state,absent)) :
        {U.right(lo,_) == (M.Branch{lo,hi},Fail{U.Missing{}}) : M.Sections & Result<&2,&2,U.Error,Unit>}
      {==}
    case Nil{} M.EmptySections{}: {==}
    case Nil{} M.Branch{lo,hi}: {==}
    case head <> rest M.EmptySections{}: {==}
    case head <> rest M.Bucket{entries}: {==}

def L.invalid_local_path_write_retains_complete_trie(route,sections,key,x,y,z,state,exists,invalid):
  match route sections:
    case Nil{} M.Bucket{entries}: L.invalid_local_bucket_write_retains_every_array_and_entry(entries,key,x,y,z,state,exists,invalid)
    case False{} <> rest M.Branch{lo,hi}:
      %Equal.sym(M.Sections & Result<&2,&2,U.Error,Unit>,U.write_at(rest,lo,key,x,y,z,state),(lo,Fail{U.SectionRejected{S.BadLocal{x,y,z}}}),L.invalid_local_path_write_retains_complete_trie(rest,lo,key,x,y,z,state,exists,invalid)) :
        {U.left(hi,_) == (M.Branch{lo,hi},Fail{U.SectionRejected{S.BadLocal{x,y,z}}}) : M.Sections & Result<&2,&2,U.Error,Unit>}
      {==}
    case True{} <> rest M.Branch{lo,hi}:
      %Equal.sym(M.Sections & Result<&2,&2,U.Error,Unit>,U.write_at(rest,hi,key,x,y,z,state),(hi,Fail{U.SectionRejected{S.BadLocal{x,y,z}}}),L.invalid_local_path_write_retains_complete_trie(rest,hi,key,x,y,z,state,exists,invalid)) :
        {U.right(lo,_) == (M.Branch{lo,hi},Fail{U.SectionRejected{S.BadLocal{x,y,z}}}) : M.Sections & Result<&2,&2,U.Error,Unit>}
      {==}
    case Nil{} M.EmptySections{}: Empty.absurd({U.write_at([],M.EmptySections{},key,x,y,z,state) == (M.EmptySections{},Fail{U.SectionRejected{S.BadLocal{x,y,z}}}) : M.Sections & Result<&2,&2,U.Error,Unit>},L.false_is_not_true(exists))
    case Nil{} M.Branch{lo,hi}: Empty.absurd({U.write_at([],M.Branch{lo,hi},key,x,y,z,state) == (M.Branch{lo,hi},Fail{U.SectionRejected{S.BadLocal{x,y,z}}}) : M.Sections & Result<&2,&2,U.Error,Unit>},L.false_is_not_true(exists))
    case head <> rest M.EmptySections{}: Empty.absurd({U.write_at(head <> rest,M.EmptySections{},key,x,y,z,state) == (M.EmptySections{},Fail{U.SectionRejected{S.BadLocal{x,y,z}}}) : M.Sections & Result<&2,&2,U.Error,Unit>},L.false_is_not_true(exists))
    case head <> rest M.Bucket{entries}: Empty.absurd({U.write_at(head <> rest,M.Bucket{entries},key,x,y,z,state) == (M.Bucket{entries},Fail{U.SectionRejected{S.BadLocal{x,y,z}}}) : M.Sections & Result<&2,&2,U.Error,Unit>},L.false_is_not_true(exists))

def L.duplicate_create_retains_complete_map(sections,key,fill,exists):
  L.duplicate_path_create_retains_complete_trie(U.path(32n,M.hash(key)),sections,key,fill,exists)

def L.missing_write_retains_complete_map(sections,key,x,y,z,state,absent):
  L.missing_path_write_retains_complete_trie(U.path(32n,M.hash(key)),sections,key,x,y,z,state,absent)

def L.invalid_local_write_retains_complete_map(sections,key,x,y,z,state,exists,invalid):
  L.invalid_local_path_write_retains_complete_trie(U.path(32n,M.hash(key)),sections,key,x,y,z,state,exists,invalid)

def L.actual_selected_section_refusal_retains_bucket_position(key,section,tail,x,y,z,state,invalid):
  %Equal.sym(S.Section & Result<&2,&2,S.Section.Error,Unit>,S.Section.set(section,x,y,z,state),(section,Fail{S.BadLocal{x,y,z}}),SectionLaws.set_local_rejects(section,x,y,z,state,invalid)) :
    {U.changed_head(key,tail,_) == (M.Entry{key,section} <> tail,Fail{U.SectionRejected{S.BadLocal{x,y,z}}}) : List<&1,M.Entry> & Result<&2,&2,U.Error,Unit>}
  {==}

def L.malformed_path_create_retains_complete_trie(route,sections,key,fill,malformed):
  match route sections:
    case Nil{} M.Branch{lo,hi}: {==}
    case False{} <> rest M.Bucket{entries}: {==}
    case True{} <> rest M.Bucket{entries}: {==}
    case False{} <> rest M.Branch{lo,hi}:
      %Equal.sym(M.Sections & Result<&2,&2,U.Error,Unit>,U.create_at(rest,lo,key,fill),(lo,Fail{U.Malformed{}}),L.malformed_path_create_retains_complete_trie(rest,lo,key,fill,malformed)) :
        {U.left(hi,_) == (M.Branch{lo,hi},Fail{U.Malformed{}}) : M.Sections & Result<&2,&2,U.Error,Unit>}
      {==}
    case True{} <> rest M.Branch{lo,hi}:
      %Equal.sym(M.Sections & Result<&2,&2,U.Error,Unit>,U.create_at(rest,hi,key,fill),(hi,Fail{U.Malformed{}}),L.malformed_path_create_retains_complete_trie(rest,hi,key,fill,malformed)) :
        {U.right(lo,_) == (M.Branch{lo,hi},Fail{U.Malformed{}}) : M.Sections & Result<&2,&2,U.Error,Unit>}
      {==}
    case Nil{} M.Bucket{entries}: Empty.absurd({U.create_at([],M.Bucket{entries},key,fill) == (M.Bucket{entries},Fail{U.Malformed{}}) : M.Sections & Result<&2,&2,U.Error,Unit>},L.true_is_not_false(malformed))
    case _ M.EmptySections{}: Empty.absurd({U.create_at(route,M.EmptySections{},key,fill) == (M.EmptySections{},Fail{U.Malformed{}}) : M.Sections & Result<&2,&2,U.Error,Unit>},L.true_is_not_false(malformed))

def L.malformed_create_retains_complete_map(sections,key,fill,malformed):
  L.malformed_path_create_retains_complete_trie(U.path(32n,M.hash(key)),sections,key,fill,malformed)
