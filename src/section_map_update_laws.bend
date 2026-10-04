import Base
import ./section_map_update.bend as U
import ./section_map.bend as M
import ./section.bend as S

def truth_type(value:Bool) -> Type:
  match value:
    case False{}: Empty
    case True{}: Unit

law false_is_not_true:
  for contradiction:{False{} == True{} : Bool}
  Empty

law true_is_not_false:
  for contradiction:{True{} == False{} : Bool}
  Empty

def valid_route(route:List<&2,Bool>,sections:M.Sections) -> Bool:
  match route sections:
    case _ M.EmptySections{}: True{}
    case Nil{} M.Bucket{entries}: True{}
    case False{} <> rest M.Branch{lo,hi}: valid_route(rest,lo)
    case True{} <> rest M.Branch{lo,hi}: valid_route(rest,hi)
    case _ _: False{}

# The specification reads the full keys of the actual owned entries. The
# equality retains every Section array and every collision position.
law bucket_membership_retains_complete_owner:
  for entries:List<&1,M.Entry>
  for +key:String
  {U.contains(entries,key) == (entries,U.member(U.keys(entries),key)) : List<&1,M.Entry> & Bool}

law bucket_count_retains_complete_owner:
  for entries:List<&1,M.Entry>
  {U.count(entries) == (entries,List.length(&2,String,U.keys(entries))) : List<&1,M.Entry> & Nat}

law duplicate_bucket_refuses_without_reordering:
  for entries:List<&1,M.Entry>
  for +key:String
  for fill:U32
  for exists:{U.member(U.keys(entries),key) == True{} : Bool}
  {U.create_bucket(key,fill,U.contains(entries,key)) == (M.Bucket{entries},Fail{U.Existing{}}) : M.Sections & Result<&2,&2,U.Error,Unit>}

law missing_bucket_write_retains_all_entries:
  for entries:List<&1,M.Entry>
  for +key:String
  for x:U32
  for y:U32
  for z:U32
  for state:U32
  for absent:{U.member(U.keys(entries),key) == False{} : Bool}
  {U.write_leaf(key,x,y,z,state,U.contains(entries,key)) == (M.Bucket{entries},Fail{U.Missing{}}) : M.Sections & Result<&2,&2,U.Error,Unit>}

law invalid_local_bucket_write_retains_every_array_and_entry:
  for entries:List<&1,M.Entry>
  for +key:String
  for +x:U32
  for +y:U32
  for +z:U32
  for state:U32
  for exists:{U.member(U.keys(entries),key) == True{} : Bool}
  for invalid:{S.Section.local_valid(x,y,z) == False{} : Bool}
  {U.write_leaf(key,x,y,z,state,U.contains(entries,key)) == (M.Bucket{entries},Fail{U.SectionRejected{S.BadLocal{x,y,z}}}) : M.Sections & Result<&2,&2,U.Error,Unit>}

# These three inductive contracts quantify over arbitrary actual tries and
# arbitrary paths, including empty buckets and malformed constructors.
law duplicate_path_create_retains_complete_trie:
  for +route:List<&2,Bool>
  for sections:M.Sections
  for +key:String
  for +fill:U32
  for exists:{U.present(route,sections,key) == True{} : Bool}
  {U.create_at(route,sections,key,fill) == (sections,Fail{U.Existing{}}) : M.Sections & Result<&2,&2,U.Error,Unit>}

law missing_path_write_retains_complete_trie:
  for +route:List<&2,Bool>
  for sections:M.Sections
  for +key:String
  for +x:U32
  for +y:U32
  for +z:U32
  for +state:U32
  for absent:{U.present(route,sections,key) == False{} : Bool}
  {U.write_at(route,sections,key,x,y,z,state) == (sections,Fail{U.Missing{}}) : M.Sections & Result<&2,&2,U.Error,Unit>}

law invalid_local_path_write_retains_complete_trie:
  for +route:List<&2,Bool>
  for sections:M.Sections
  for +key:String
  for +x:U32
  for +y:U32
  for +z:U32
  for +state:U32
  for exists:{U.present(route,sections,key) == True{} : Bool}
  for invalid:{S.Section.local_valid(x,y,z) == False{} : Bool}
  {U.write_at(route,sections,key,x,y,z,state) == (sections,Fail{U.SectionRejected{S.BadLocal{x,y,z}}}) : M.Sections & Result<&2,&2,U.Error,Unit>}

# The public interfaces use the existing actual SectionMap hash/path.
law duplicate_create_retains_complete_map:
  for sections:M.Sections
  for +key:String
  for fill:U32
  for exists:{U.present(U.path(32n,M.hash(key)),sections,key) == True{} : Bool}
  {U.create(sections,key,fill) == (sections,Fail{U.Existing{}}) : M.Sections & Result<&2,&2,U.Error,Unit>}

law missing_write_retains_complete_map:
  for sections:M.Sections
  for +key:String
  for x:U32
  for y:U32
  for z:U32
  for state:U32
  for absent:{U.present(U.path(32n,M.hash(key)),sections,key) == False{} : Bool}
  {U.write(sections,key,x,y,z,state) == (sections,Fail{U.Missing{}}) : M.Sections & Result<&2,&2,U.Error,Unit>}

law invalid_local_write_retains_complete_map:
  for sections:M.Sections
  for +key:String
  for +x:U32
  for +y:U32
  for +z:U32
  for state:U32
  for exists:{U.present(U.path(32n,M.hash(key)),sections,key) == True{} : Bool}
  for invalid:{S.Section.local_valid(x,y,z) == False{} : Bool}
  {U.write(sections,key,x,y,z,state) == (sections,Fail{U.SectionRejected{S.BadLocal{x,y,z}}}) : M.Sections & Result<&2,&2,U.Error,Unit>}

law actual_selected_section_refusal_retains_bucket_position:
  for +key:String
  for section:S.Section
  for tail:List<&1,M.Entry>
  for +x:U32
  for +y:U32
  for +z:U32
  for state:U32
  for invalid:{S.Section.local_valid(x,y,z) == False{} : Bool}
  {U.changed_head(key,tail,S.Section.set(section,x,y,z,state)) ==
    (M.Entry{key,section} <> tail,Fail{U.SectionRejected{S.BadLocal{x,y,z}}}) : List<&1,M.Entry> & Result<&2,&2,U.Error,Unit>}

law malformed_path_create_retains_complete_trie:
  for +route:List<&2,Bool>
  for sections:M.Sections
  for +key:String
  for +fill:U32
  for malformed:{valid_route(route,sections) == False{} : Bool}
  {U.create_at(route,sections,key,fill) == (sections,Fail{U.Malformed{}}) : M.Sections & Result<&2,&2,U.Error,Unit>}

law malformed_create_retains_complete_map:
  for sections:M.Sections
  for +key:String
  for fill:U32
  for malformed:{valid_route(U.path(32n,M.hash(key)),sections) == False{} : Bool}
  {U.create(sections,key,fill) == (sections,Fail{U.Malformed{}}) : M.Sections & Result<&2,&2,U.Error,Unit>}
