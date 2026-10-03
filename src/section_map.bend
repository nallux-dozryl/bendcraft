import Base
import ./section.bend as S

# A concrete owned map avoids Bend 2.0.35's rejected open generic Array layout.
# Fixed 32-bit trie paths plus full-key collision buckets preserve exact keys.
type Entry is Type:
  Entry{key: String, section: S.Section}

type Sections is Type:
  EmptySections{}
  Branch{lo: Sections, hi: Sections}
  Bucket{entries: List<&1, Entry>}

def hash_go(key: String, acc: U32) -> U32:
  match key:
    case SNil{}:
      acc
    case SCon{Chr{code}, t}:
      hash_go(t, (U32.xor(acc, code) * 16777619 : U32))

def hash(key: String) -> U32:
  hash_go(key, 2166136261)

def pop_prepend(head: Entry, r: List<&1, Entry> & Maybe<&1, S.Section>) -> List<&1, Entry> & Maybe<&1, S.Section>:
  (tail, found) = r
  (head <> tail, found)

def pop_choose(hit: Bool, key: String, section: S.Section, r: List<&1, Entry> & Maybe<&1, S.Section>) -> List<&1, Entry> & Maybe<&1, S.Section>:
  match hit r:
    case True{} Tuple{tail, found}:
      (tail, Some{section})
    case False{} Tuple{tail, found}:
      (Entry{key, section} <> tail, found)

def pop_bucket(entries: List<&1, Entry>, +key: String) -> List<&1, Entry> & Maybe<&1, S.Section>:
  match entries:
    case Nil{}:
      ([], None{})
    case Con{Entry{+candidate, section}, tail}:
      pop_choose(String.eq(candidate, key), candidate, section, pop_bucket(tail, key))

def bucket_result(r: List<&1, Entry> & Maybe<&1, S.Section>) -> Sections & Maybe<&1, S.Section>:
  (entries, found) = r
  match entries:
    case Nil{}:
      (EmptySections{}, found)
    case es:
      (Bucket{es}, found)

def keep_lo(hi: Sections, r: Sections & Maybe<&1, S.Section>) -> Sections & Maybe<&1, S.Section>:
  (lo, found) = r
  (Branch{lo, hi}, found)

def keep_hi(lo: Sections, r: Sections & Maybe<&1, S.Section>) -> Sections & Maybe<&1, S.Section>:
  (hi, found) = r
  (Branch{lo, hi}, found)

def pop_choose_branch(low: U32, lo: Sections, hi: Sections, left: Sections -> Sections & Maybe<&1, S.Section>, right: Sections -> Sections & Maybe<&1, S.Section>) -> Sections & Maybe<&1, S.Section>:
  match low:
    case 0:
      keep_lo(hi, left(lo))
    case other:
      keep_hi(lo, right(hi))

def pop_go(+depth: Nat, sections: Sections, +bits: U32, +key: String) -> Sections & Maybe<&1, S.Section>:
  match depth sections:
    case _ EmptySections{}:
      (EmptySections{}, None{})
    case 0n Bucket{entries}:
      bucket_result(pop_bucket(entries, key))
    case 1n+d Branch{lo, hi}:
      pop_choose_branch(U32.and(bits, 1), lo, hi, l => pop_go(d, l, U32.shr(bits), key), h => pop_go(d, h, U32.shr(bits), key))
    case _ other:
      (other, None{})

def pop(sections: Sections, +key: String) -> Sections & Maybe<&1, S.Section>:
  pop_go(32n, sections, hash(key), key)

def put_bucket(key: String, section: S.Section, r: List<&1, Entry> & Maybe<&1, S.Section>) -> Sections:
  (remaining, replaced) = r
  Bucket{Entry{key, section} <> remaining}

def put_choose_branch(low: U32, lo: Sections, hi: Sections, section: S.Section, left: Sections -> S.Section -> Sections, right: Sections -> S.Section -> Sections) -> Sections:
  match low:
    case 0:
      Branch{left(lo, section), hi}
    case other:
      Branch{lo, right(hi, section)}

def put_go(+depth: Nat, sections: Sections, +bits: U32, +key: String, section: S.Section) -> Sections:
  match depth sections:
    case 0n Bucket{entries}:
      put_bucket(key, section, pop_bucket(entries, key))
    case 0n other:
      Bucket{[Entry{key, section}]}
    case 1n+d Branch{lo, hi}:
      put_choose_branch(U32.and(bits, 1), lo, hi, section, l => v => put_go(d, l, U32.shr(bits), key, v), h => v => put_go(d, h, U32.shr(bits), key, v))
    case 1n+d other:
      put_choose_branch(U32.and(bits, 1), EmptySections{}, EmptySections{}, section, l => v => put_go(d, l, U32.shr(bits), key, v), h => v => put_go(d, h, U32.shr(bits), key, v))

def set(sections: Sections, +key: String, section: S.Section) -> Sections:
  put_go(32n, sections, hash(key), key, section)
