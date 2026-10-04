import Base
import ./section_map.bend as M
import ./section.bend as S

# Read the actual affine trie without pop/set normalization or bucket reordering.
# Coordinates are section-local; the existing Section.get validates them.
def paired(-A: Type, -B: Type, -T: Type, value: A & B, finish: A -> B -> T) -> T:
  match value:
    case (a, b): finish(a, b)

def hit(+key: String, tail: List<&1, M.Entry>,
        result: S.Section & Result<&2, &2, S.Section.Error, U32>) -> List<&1, M.Entry> & Maybe<&2, Result<&2, &2, S.Section.Error, U32>>:
  (section, status) = result
  (M.Entry{key, section} <> tail, Some{status})

def skipped(head: M.Entry,
            result: List<&1, M.Entry> & Maybe<&2, Result<&2, &2, S.Section.Error, U32>>) -> List<&1, M.Entry> & Maybe<&2, Result<&2, &2, S.Section.Error, U32>>:
  (tail, status) = result
  (head <> tail, status)

def bucket_result(key: String, section: S.Section, +x: U32, +y: U32, +z: U32,
                  found: Bool, result: List<&1, M.Entry> & Maybe<&2, Result<&2, &2, S.Section.Error, U32>>) -> List<&1, M.Entry> & Maybe<&2, Result<&2, &2, S.Section.Error, U32>>:
  match found result:
    case True{} Tuple{tail, previous}: hit(key, tail, S.Section.get(section, x, y, z))
    case False{} result: skipped(M.Entry{key, section}, result)

def bucket(entries: List<&1, M.Entry>, +key: String, +x: U32, +y: U32, +z: U32) -> List<&1, M.Entry> & Maybe<&2, Result<&2, &2, S.Section.Error, U32>>:
  match entries:
    case Nil{}: ([], None{})
    case M.Entry{+candidate, section} <> tail:
      bucket_result(candidate, section, x, y, z, String.eq(candidate, key), bucket(tail, key, x, y, z))

def leaf(result: List<&1, M.Entry> & Maybe<&2, Result<&2, &2, S.Section.Error, U32>>) -> M.Sections & Maybe<&2, Result<&2, &2, S.Section.Error, U32>>:
  (entries, status) = result
  (M.Bucket{entries}, status)

def left(hi: M.Sections, result: M.Sections & Maybe<&2, Result<&2, &2, S.Section.Error, U32>>) -> M.Sections & Maybe<&2, Result<&2, &2, S.Section.Error, U32>>:
  (lo, status) = result
  (M.Branch{lo, hi}, status)

def right(lo: M.Sections, result: M.Sections & Maybe<&2, Result<&2, &2, S.Section.Error, U32>>) -> M.Sections & Maybe<&2, Result<&2, &2, S.Section.Error, U32>>:
  (hi, status) = result
  (M.Branch{lo, hi}, status)

def branch(lo: M.Sections, hi: M.Sections,
           in_lo: M.Sections -> M.Sections & Maybe<&2, Result<&2, &2, S.Section.Error, U32>>,
           in_hi: M.Sections -> M.Sections & Maybe<&2, Result<&2, &2, S.Section.Error, U32>>,
           bit: U32) -> M.Sections & Maybe<&2, Result<&2, &2, S.Section.Error, U32>>:
  match bit:
    case 0: left(hi, in_lo(lo))
    case _: right(lo, in_hi(hi))

def go(+depth: Nat, sections: M.Sections, +bits: U32, +key: String,
       +x: U32, +y: U32, +z: U32) -> M.Sections & Maybe<&2, Result<&2, &2, S.Section.Error, U32>>:
  match depth sections:
    case _ M.EmptySections{}: (M.EmptySections{}, None{})
    case 0n M.Bucket{entries}: leaf(bucket(entries, key, x, y, z))
    case 1n+p M.Branch{lo, hi}:
      branch(lo, hi, lo => go(p, lo, U32.shr(bits), key, x, y, z),
        hi => go(p, hi, U32.shr(bits), key, x, y, z), U32.and(bits, 1))
    case _ other: (other, None{})

def read(sections: M.Sections, +key: String, x: U32, y: U32, z: U32) -> M.Sections & Maybe<&2, Result<&2, &2, S.Section.Error, U32>>:
  go(32n, sections, M.hash(key), key, x, y, z)
