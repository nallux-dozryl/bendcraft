import Base
import ./section_map_read.bend as R
import ./section_map.bend as M
import ./section.bend as S

law checked_section_refusal_preserves_full_head_and_bucket_tail:
  for array: Array<U32>
  for +key: String
  for tail: List<&1, M.Entry>
  {R.hit(key, tail, S.Section.get(S.Section{array}, 16, 0, 0)) ==
    (M.Entry{key, S.Section{array}} <> tail, Some{Fail{S.BadLocal{16, 0, 0}}}) : List<&1, M.Entry> & Maybe<&2, Result<&2, &2, S.Section.Error, U32>>}

law selected_section_result_stays_at_its_original_bucket_position:
  for +key: String
  for section: S.Section
  for tail: List<&1, M.Entry>
  for +status: Result<&2, &2, S.Section.Error, U32>
  {R.hit(key, tail, (section, status)) ==
    (M.Entry{key, section} <> tail, Some{status}) : List<&1, M.Entry> & Maybe<&2, Result<&2, &2, S.Section.Error, U32>>}

law collision_prefix_is_neither_deleted_nor_reordered:
  for head: M.Entry
  for tail: List<&1, M.Entry>
  for +status: Maybe<&2, Result<&2, &2, S.Section.Error, U32>>
  {R.skipped(head, (tail, status)) == (head <> tail, status) : List<&1, M.Entry> & Maybe<&2, Result<&2, &2, S.Section.Error, U32>>}

law empty_leaf_preserves_its_exact_trie_constructor:
  for bits: U32
  for key: String
  for x: U32
  for y: U32
  for z: U32
  {R.go(0n, M.Bucket{[]}, bits, key, x, y, z) == (M.Bucket{[]}, None{}) : M.Sections & Maybe<&2, Result<&2, &2, S.Section.Error, U32>>}

law malformed_depth_preserves_all_owned_bucket_entries:
  for entries: List<&1, M.Entry>
  for bits: U32
  for key: String
  for x: U32
  for y: U32
  for z: U32
  {R.go(1n, M.Bucket{entries}, bits, key, x, y, z) == (M.Bucket{entries}, None{}) : M.Sections & Maybe<&2, Result<&2, &2, S.Section.Error, U32>>}

law terminal_branch_is_retained_on_shape_refusal:
  for lo: M.Sections
  for hi: M.Sections
  for bits: U32
  for key: String
  for x: U32
  for y: U32
  for z: U32
  {R.go(0n, M.Branch{lo, hi}, bits, key, x, y, z) == (M.Branch{lo, hi}, None{}) : M.Sections & Maybe<&2, Result<&2, &2, S.Section.Error, U32>>}

law left_read_retains_untouched_right_and_returned_left_owners:
  for lo: M.Sections
  for hi: M.Sections
  for +status: Maybe<&2, Result<&2, &2, S.Section.Error, U32>>
  {R.left(hi, (lo, status)) == (M.Branch{lo, hi}, status) : M.Sections & Maybe<&2, Result<&2, &2, S.Section.Error, U32>>}

law right_read_retains_untouched_left_and_returned_right_owners:
  for lo: M.Sections
  for hi: M.Sections
  for +status: Maybe<&2, Result<&2, &2, S.Section.Error, U32>>
  {R.right(lo, (hi, status)) == (M.Branch{lo, hi}, status) : M.Sections & Maybe<&2, Result<&2, &2, S.Section.Error, U32>>}

law leaf_read_preserves_all_entries_and_their_order:
  for entries: List<&1, M.Entry>
  for +status: Maybe<&2, Result<&2, &2, S.Section.Error, U32>>
  {R.leaf((entries, status)) == (M.Bucket{entries}, status) : M.Sections & Maybe<&2, Result<&2, &2, S.Section.Error, U32>>}

# This couples arbitrary owned Section arrays to the actual checked getter and
# recursively returned bucket owner. It is not an invented read implementation.
law actual_bucket_head_read_preserves_complete_collision_bucket:
  for +key: String
  for section: S.Section
  for tail: List<&1, M.Entry>
  for +x: U32
  for +y: U32
  for +z: U32
  for +status: Result<&2, &2, S.Section.Error, U32>
  for +tail_status: Maybe<&2, Result<&2, &2, S.Section.Error, U32>>
  for key_hit: {String.eq(key, key) == True{} : Bool}
  for section_retained: {S.Section.get(section, x, y, z) == (section, status) : S.Section & Result<&2, &2, S.Section.Error, U32>}
  for tail_retained: {R.bucket(tail, key, x, y, z) == (tail, tail_status) : List<&1, M.Entry> & Maybe<&2, Result<&2, &2, S.Section.Error, U32>>}
  {R.bucket(M.Entry{key, section} <> tail, key, x, y, z) ==
    (M.Entry{key, section} <> tail, Some{status}) : List<&1, M.Entry> & Maybe<&2, Result<&2, &2, S.Section.Error, U32>>}

law actual_bucket_miss_retains_arbitrary_prefix_and_tail:
  for +candidate: String
  for section: S.Section
  for tail: List<&1, M.Entry>
  for +key: String
  for +x: U32
  for +y: U32
  for +z: U32
  for +status: Maybe<&2, Result<&2, &2, S.Section.Error, U32>>
  for missing: {String.eq(candidate, key) == False{} : Bool}
  for tail_retained: {R.bucket(tail, key, x, y, z) == (tail, status) : List<&1, M.Entry> & Maybe<&2, Result<&2, &2, S.Section.Error, U32>>}
  {R.bucket(M.Entry{candidate, section} <> tail, key, x, y, z) ==
    (M.Entry{candidate, section} <> tail, status) : List<&1, M.Entry> & Maybe<&2, Result<&2, &2, S.Section.Error, U32>>}
