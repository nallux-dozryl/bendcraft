import Base
import ./section_map_read.bend as R
import ./section_map.bend as M
import ./section.bend as S
import ./section_map_read_laws.bend as Laws

def Laws.checked_section_refusal_preserves_full_head_and_bucket_tail(array, key, tail): {==}
def Laws.selected_section_result_stays_at_its_original_bucket_position(key, section, tail, status): {==}
def Laws.collision_prefix_is_neither_deleted_nor_reordered(head, tail, status): {==}
def Laws.empty_leaf_preserves_its_exact_trie_constructor(bits, key, x, y, z): {==}
def Laws.malformed_depth_preserves_all_owned_bucket_entries(entries, bits, key, x, y, z): {==}
def Laws.terminal_branch_is_retained_on_shape_refusal(lo, hi, bits, key, x, y, z): {==}
def Laws.left_read_retains_untouched_right_and_returned_left_owners(lo, hi, status): {==}
def Laws.right_read_retains_untouched_left_and_returned_right_owners(lo, hi, status): {==}
def Laws.leaf_read_preserves_all_entries_and_their_order(entries, status): {==}

def Laws.actual_bucket_head_read_preserves_complete_collision_bucket(key, section, tail, x, y, z, status, tail_status, key_hit, section_retained, tail_retained):
  %Equal.sym(List<&1, M.Entry> & Maybe<&2, Result<&2, &2, S.Section.Error, U32>>, R.bucket(tail, key, x, y, z), (tail, tail_status), tail_retained) :
    {R.bucket_result(key, section, x, y, z, String.eq(key, key), _) == (M.Entry{key, section} <> tail, Some{status}) : List<&1, M.Entry> & Maybe<&2, Result<&2, &2, S.Section.Error, U32>>}
  %Equal.sym(Bool, String.eq(key, key), True{}, key_hit) :
    {R.bucket_result(key, section, x, y, z, _, (tail, tail_status)) == (M.Entry{key, section} <> tail, Some{status}) : List<&1, M.Entry> & Maybe<&2, Result<&2, &2, S.Section.Error, U32>>}
  %Equal.sym(S.Section & Result<&2, &2, S.Section.Error, U32>, S.Section.get(section, x, y, z), (section, status), section_retained) :
    {R.hit(key, tail, _) == (M.Entry{key, section} <> tail, Some{status}) : List<&1, M.Entry> & Maybe<&2, Result<&2, &2, S.Section.Error, U32>>}
  {==}

def Laws.actual_bucket_miss_retains_arbitrary_prefix_and_tail(candidate, section, tail, key, x, y, z, status, missing, tail_retained):
  %Equal.sym(List<&1, M.Entry> & Maybe<&2, Result<&2, &2, S.Section.Error, U32>>, R.bucket(tail, key, x, y, z), (tail, status), tail_retained) :
    {R.bucket_result(candidate, section, x, y, z, String.eq(candidate, key), _) == (M.Entry{candidate, section} <> tail, status) : List<&1, M.Entry> & Maybe<&2, Result<&2, &2, S.Section.Error, U32>>}
  %Equal.sym(Bool, String.eq(candidate, key), False{}, missing) :
    {R.bucket_result(candidate, section, x, y, z, _, (tail, status)) == (M.Entry{candidate, section} <> tail, status) : List<&1, M.Entry> & Maybe<&2, Result<&2, &2, S.Section.Error, U32>>}
  {==}
