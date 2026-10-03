# Dynamic block-state metadata; no block behaviors are implemented here.
import Base
import ./json.bend as J
import ./unicode.bend as Unicode
import ./hash.bend as Hash

type Property is Data:
  Property{name: String, values: List<&2, String>, count: U32, stride: U32}

type Block is Data:
  Block{protocol_id: U32, name: String, first: U32, count: U32, default_id: U32, properties: List<&2, Property>}

type Assignment is Data:
  Assignment{name: String, value: String}

type Policy is Data:
  Exact{}
  Defaults{}

type Resolved is Data:
  Resolved{protocol_id: U32, name: String, state_id: U32, assignments: List<&2, Assignment>}

type Error is Data:
  SchemaError{row: U32, message: String}
  ReadError{code: U32, message: String}
  InvalidResource{name: String}
  UnknownBlock{name: String}
  InvalidState{state_id: U32}
  UnknownProperty{name: String}
  DuplicateProperty{name: String}
  MissingProperty{name: String}
  InvalidValue{property: String, value: String}

type Registry is Type:
  Registry{blocks: Array<Block>, names: Map<&2, U32>, block_count: U32, state_count: U32}

def empty_block() -> Block:
  Block{0, "", 0, 0, 0, Nil{}}

def error_text(error: Error) -> String:
  match error:
    case SchemaError{row, message}: "schema:" ++ U32.show(row) ++ ":" ++ message
    case ReadError{code, message}: "read:" ++ U32.show(code) ++ ":" ++ message
    case InvalidResource{name}: "invalid-resource:" ++ name
    case UnknownBlock{name}: "unknown-block:" ++ name
    case InvalidState{state_id}: "invalid-state:" ++ U32.show(state_id)
    case UnknownProperty{name}: "unknown-property:" ++ name
    case DuplicateProperty{name}: "duplicate-property:" ++ name
    case MissingProperty{name}: "missing-property:" ++ name
    case InvalidValue{property, value}: "invalid-value:" ++ property ++ "=" ++ value

def require(row: U32, message: String, ok: Bool) -> Result<&2, &2, Error, Unit>:
  match ok:
    case False{}: Fail{SchemaError{row, message}}
    case True{}: Done{Unit{}}

def token_char(+c: U32) -> Bool:
  (U32.is_ge(c, 97) && U32.is_le(c, 122)) || (U32.is_ge(c, 48) && U32.is_le(c, 57)) || U32.is_eq(c, 95)

def resource_char(+c: U32, path: Bool) -> Bool:
  token_char(c) || U32.is_eq(c, 45) || U32.is_eq(c, 46) || (path && U32.is_eq(c, 47))

def resource_part(text: String, +path: Bool) -> Bool:
  match text:
    case SNil{}: True{}
    case SCon{Chr{c}, t}: resource_char(c, path) && resource_part(t, path)

def resource_fields(fields: List<&2, String>) -> Bool:
  match fields:
    case +namespace <> +path <> Nil{}:
      Bool.not(String.is_empty(namespace)) && Bool.not(String.is_empty(path)) && resource_part(namespace, False{}) && resource_part(path, True{})
    case _: False{}

def resource_valid(+name: String) -> Bool:
  J.within(512n, name) && resource_fields(String.split(name, ':'))

def token_go(text: String) -> Bool:
  match text:
    case SNil{}: True{}
    case SCon{Chr{c}, t}: token_char(c) && token_go(t)

def token_valid(+text: String) -> Bool:
  Bool.not(String.is_empty(text)) && J.within(128n, text) && token_go(text)

def number_result(row: U32, field: String, number: Maybe<&2, U32>) -> Result<&2, &2, Error, U32>:
  match number:
    case None{}: Fail{SchemaError{row, "invalid U32 " ++ field}}
    case Some{value}: Done{value}

def number(row: U32, field: String, text: String) -> Result<&2, &2, Error, U32>:
  number_result(row, field, J.u32_lexeme(text))

def string_present(values: List<&2, String>, +value: String) -> Bool:
  match values:
    case Nil{}: False{}
    case h <> t: String.eq(h, value) || string_present(t, value)

def property_present(properties: List<&2, Property>, +name: String) -> Bool:
  match properties:
    case Nil{}: False{}
    case Property{key, values, count, stride} <> t: String.eq(key, name) || property_present(t, name)

def domain_values(values: List<&2, J.Value>, +row: U32, +count: U32, +acc: List<&2, String>) -> Result<&2, &2, Error, List<&2, String>>:
  match values:
    case Nil{}:
      do Result<&2, &2, Error, List<&2, String>>:
        checked : Unit <- require(row, "empty property domain", U32.is_gt(count, 0))
        return List.reverse(&2, String, acc)
    case J.JString{+value} <> rest:
      do Result<&2, &2, Error, List<&2, String>>:
        checked : Unit <- require(row, "invalid or duplicate property value", Bool.not(String.is_empty(value)) && J.within(256n, value) && Bool.not(string_present(acc, value)) && U32.is_lt(count, 256))
        domain_values(rest, row, (count + 1 : U32), value <> acc)
    case _: Fail{SchemaError{row, "property domain must contain strings"}}

def property_fields(+row: U32, +acc: List<&2, Property>, fields: List<&2, J.Member>) -> Result<&2, &2, Error, Property>:
  match fields:
    case J.JMember{"name", J.JString{+name}} <> J.JMember{"values", J.JArray{values}} <> Nil{}:
      do Result<&2, &2, Error, Property>:
        checked : Unit <- require(row, "invalid or duplicate property name", token_valid(name) && Bool.not(property_present(acc, name)))
        +domain : List<&2, String> <- domain_values(values, row, 0, Nil{})
        return Property{name, domain, U32.from_nat(List.length(&2, String, domain)), 0}
    case J.JMember{"values", J.JArray{values}} <> J.JMember{"name", J.JString{+name}} <> Nil{}:
      do Result<&2, &2, Error, Property>:
        checked : Unit <- require(row, "invalid or duplicate property name", token_valid(name) && Bool.not(property_present(acc, name)))
        +domain : List<&2, String> <- domain_values(values, row, 0, Nil{})
        return Property{name, domain, U32.from_nat(List.length(&2, String, domain)), 0}
    case _: Fail{SchemaError{row, "property must have exactly name and values"}}

def property_domains(values: List<&2, J.Value>, +row: U32, +count: U32, +acc: List<&2, Property>) -> Result<&2, &2, Error, List<&2, Property>>:
  match values:
    case Nil{}: Done{acc}
    case J.JObject{fields} <> rest:
      do Result<&2, &2, Error, List<&2, Property>>:
        checked : Unit <- require(row, "too many properties", U32.is_lt(count, 64))
        property : Property <- property_fields(row, acc, fields)
        property_domains(rest, row, (count + 1 : U32), property <> acc)
    case _: Fail{SchemaError{row, "ordered properties must contain objects"}}

def property_strides(properties: List<&2, Property>, +row: U32, +product: U32, expected: U32, acc: List<&2, Property>) -> Result<&2, &2, Error, List<&2, Property>>:
  match properties:
    case Nil{}:
      do Result<&2, &2, Error, List<&2, Property>>:
        checked : Unit <- require(row, "state count disagrees with property product", U32.is_eq(product, expected))
        return acc
    case Property{name, values, +count, stride} <> rest:
      do Result<&2, &2, Error, List<&2, Property>>:
        checked : Unit <- require(row, "property product overflow", U32.is_le(count, (4294967295 / product : U32)))
        property_strides(rest, row, (product * count : U32), expected, Property{name, values, count, product} <> acc)

def properties_value(+row: U32, expected: U32, parsed: Result<&2, &2, String, J.Value>) -> Result<&2, &2, Error, List<&2, Property>>:
  match parsed:
    case Fail{message}: Fail{SchemaError{row, "property JSON: " ++ message}}
    case Done{J.JArray{values}}:
      do Result<&2, &2, Error, List<&2, Property>>:
        domains : List<&2, Property> <- property_domains(values, row, 0, Nil{})
        property_strides(domains, row, 1, expected, Nil{})
    case _: Fail{SchemaError{row, "ordered properties must be a JSON array"}}

def row_fields(+row: U32, fields: List<&2, String>) -> Result<&2, &2, Error, Block>:
  match fields:
    case protocol <> +name <> first <> count <> default_id <> props <> Nil{}:
      do Result<&2, &2, Error, Block>:
        protocol_id : U32 <- number(row, "protocol ID", protocol)
        +first_id : U32 <- number(row, "first state ID", first)
        +state_count : U32 <- number(row, "state count", count)
        +default_state : U32 <- number(row, "default state ID", default_id)
        checked_name : Unit <- require(row, "invalid resource identifier", resource_valid(name))
        checked_range : Unit <- require(row, "invalid state interval/default", U32.is_gt(state_count, 0) && U32.is_le(state_count, (4294967295 - first_id : U32)) && U32.is_ge(default_state, first_id) && U32.is_lt(default_state, (first_id + state_count : U32)))
        properties : List<&2, Property> <- properties_value(row, state_count, J.parse(props))
        return Block{protocol_id, name, first_id, state_count, default_state, properties}
    case _: Fail{SchemaError{row, "expected exactly six TSV fields"}}

def header() -> String:
  "block_protocol_id\tidentifier\tfirst_state_id\tstate_count\tdefault_state_id\tordered_properties_json"

def row_add.header(acc: List<&2, Block>, good: Bool) -> Result<&2, &2, Error, List<&2, Block>>:
  match good:
    case False{}: Fail{SchemaError{1, "invalid TSV header"}}
    case True{}: Done{acc}

def row_add(+row: U32, +line: String, accumulated: Result<&2, &2, Error, List<&2, Block>>) -> Result<&2, &2, Error, List<&2, Block>>:
  match row accumulated:
    case 1 Done{acc}: row_add.header(acc, String.eq(line, header()))
    case _ Fail{error}: Fail{error}
    case _ Done{acc}:
      do Result<&2, &2, Error, List<&2, Block>>:
        block : Block <- row_fields(row, String.split(line, '\t'))
        return block <> acc

def line_finish(reversed: String) -> String:
  match reversed:
    case SCon{Chr{13}, rest}: String.reverse(rest)
    case _: String.reverse(reversed)

def scan(text: String, +row: U32, line: String, accumulated: Result<&2, &2, Error, List<&2, Block>>) -> Result<&2, &2, Error, List<&2, Block>>:
  match text:
    case SNil{}:
      match line:
        case SNil{}: accumulated
        case _: row_add(row, line_finish(line), accumulated)
    case SCon{Chr{10}, rest}: scan(rest, (row + 1 : U32), "", row_add(row, line_finish(line), accumulated))
    case SCon{c, rest}: scan(rest, row, SCon{c, line}, accumulated)

# No Array value is stored in a generic Map. Metadata elements have one closed type.
def build_step.valid(blocks: Array<Block>, names: Map<&2, U32>, protocol: U32, +name: String, first: U32, +count: U32, default_id: U32, props: List<&2, Property>, +loaded: U32, +states: U32, row: U32, valid: Bool) -> Result<&2, &1, Error, Registry>:
  match valid:
    case False{}: Fail{SchemaError{row, "duplicate name, noncontiguous IDs, or block capacity exceeded"}}
    case True{}:
      Done{Registry{Array.set(Block, blocks, loaded, Block{protocol, name, first, count, default_id, props}), Map.set(&2, U32, names, name, loaded), (loaded + 1 : U32), (states + count : U32)}}

def build_step.lookup(blocks: Array<Block>, +protocol: U32, name: String, +first: U32, count: U32, default_id: U32, props: List<&2, Property>, +loaded: U32, +states: U32, row: U32, lookup: Map<&2, U32> & Bool) -> Result<&2, &1, Error, Registry>:
  (names, duplicate) = lookup
  build_step.valid(blocks, names, protocol, name, first, count, default_id, props, loaded, states, row, Bool.not(duplicate) && U32.is_eq(protocol, loaded) && U32.is_eq(first, states) && U32.is_lt(loaded, 4096))

def build_step(block: Block, +row: U32, registry: Registry) -> Result<&2, &1, Error, Registry>:
  match block registry:
    case Block{+protocol, +name, +first, +count, default_id, props} Registry{blocks, names, +loaded, +states}:
      build_step.lookup(blocks, protocol, name, first, count, default_id, props, loaded, states, row, Map.has(&2, U32, names, name))

def build_done(registry: Registry, valid: Bool) -> Result<&2, &1, Error, Registry>:
  match valid:
    case False{}: Fail{SchemaError{1, "empty block inventory"}}
    case True{}: Done{registry}

def build_go(blocks: List<&2, Block>, +row: U32, current: Result<&2, &1, Error, Registry>) -> Result<&2, &1, Error, Registry>:
  match blocks current:
    case _ Fail{error}: Fail{error}
    case Nil{} Done{Registry{array, names, +count, states}}:
      build_done(Registry{array, names, count, states}, U32.is_gt(count, 0))
    case block <> rest Done{registry}:
      build_go(rest, (row + 1 : U32), build_step(block, row, registry))


def parse_result(parsed: Result<&2, &2, Error, List<&2, Block>>) -> Result<&2, &1, Error, Registry>:
  match parsed:
    case Fail{error}: Fail{error}
    case Done{blocks}:
      build_go(List.reverse(&2, Block, blocks), 2, Done{Registry{[empty_block() : Block*4096n], MTip{}, 0, 0}})

def parse_valid(text: String, valid: Bool) -> Result<&2, &1, Error, Registry>:
  match valid:
    case False{}: Fail{SchemaError{0, "registry text exceeds 4194304 code points"}}
    case True{}: parse_result(scan(text, 1, "", Done{Nil{}}))

def Registry.parse(+text: String) -> Result<&2, &1, Error, Registry>:
  parse_valid(text, J.within(4194304n, text))

# File bytes are bounded before ordinary strict UTF-8 is decoded in Bend.
def read_text.decode(decoded: Result<&2, &2, String, String>) -> Result<&2, &2, Error, String>:
  match decoded:
    case Fail{message}: Fail{SchemaError{0, "UTF-8: " ++ message}}
    case Done{text}: Done{text}

def read_text.tail(bytes: List<&2, U32>, read: File & Result<&1, &1, U32 & String, List<&2, U32>>) -> IO(Result<&2, &2, Error, String>):
  (file, result) = read
  match result:
    case Fail{(code, message)}:
      do IO<Result<&2, &2, Error, String>>:
        File.close(file)
        return Fail{ReadError{code, message}}
    case Done{Nil{}}:
      do IO<Result<&2, &2, Error, String>>:
        File.close(file)
        return read_text.decode(Unicode.decode(4194304n, bytes))
    case Done{_}:
      do IO<Result<&2, &2, Error, String>>:
        File.close(file)
        return Fail{SchemaError{0, "file exceeds 4194304 bytes"}}

def read_text.read(read: File & Result<&1, &1, U32 & String, List<&2, U32>>) -> IO(Result<&2, &2, Error, String>):
  (file, result) = read
  match result:
    case Fail{(code, message)}:
      do IO<Result<&2, &2, Error, String>>:
        File.close(file)
        return Fail{ReadError{code, message}}
    case Done{bytes}:
      do IO<Result<&2, &2, Error, String>>:
        next : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_bytes(file, 1)
        read_text.tail(bytes, next)

def read_text.open(opened: Result<&1, &1, U32 & String, File>) -> IO(Result<&2, &2, Error, String>):
  match opened:
    case Fail{(code, message)}: IO.pure(Result<&2, &2, Error, String>, Fail{ReadError{code, message}})
    case Done{file}:
      do IO<Result<&2, &2, Error, String>>:
        read : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_bytes(file, 4194304)
        read_text.read(read)

def read_text(path: String) -> IO(Result<&2, &2, Error, String>):
  do IO<Result<&2, &2, Error, String>>:
    opened : Result<&1, &1, U32 & String, File> <- File.open(path, "r")
    read_text.open(opened)

def Registry.load.result(read: Result<&2, &2, Error, String>) -> Result<&2, &1, Error, Registry>:
  match read:
    case Fail{error}: Fail{error}
    case Done{text}: Registry.parse(text)

def Registry.load(path: String) -> IO(Result<&2, &1, Error, Registry>):
  do IO<Result<&2, &1, Error, Registry>>:
    read : Result<&2, &2, Error, String> <- read_text(path)
    return Registry.load.result(read)

# Name lookup preserves the unique registry owner.
def Registry.block.read(names: Map<&2, U32>, count: U32, states: U32, read: Array<Block> & Block) -> Registry & Result<&2, &2, Error, Block>:
  (blocks, block) = read
  (Registry{blocks, names, count, states}, Done{block})

def Registry.block.index_valid(blocks: Array<Block>, names: Map<&2, U32>, name: String, count: U32, states: U32, index: U32, valid: Bool) -> Registry & Result<&2, &2, Error, Block>:
  match valid:
    case False{}: (Registry{blocks, names, count, states}, Fail{UnknownBlock{name}})
    case True{}: Registry.block.read(names, count, states, Array.get(Block, blocks, index))

def Registry.block.index(blocks: Array<Block>, +name: String, +count: U32, states: U32, lookup: Map<&2, U32> & U32) -> Registry & Result<&2, &2, Error, Block>:
  (names, +index) = lookup
  Registry.block.index_valid(blocks, names, name, count, states, index, U32.is_lt(index, count))

def Registry.block.valid(registry: Registry, +name: String, valid: Bool) -> Registry & Result<&2, &2, Error, Block>:
  match registry valid:
    case Registry{blocks, names, count, states} False{}:
      (Registry{blocks, names, count, states}, Fail{InvalidResource{name}})
    case Registry{blocks, names, count, states} True{}:
      Registry.block.index(blocks, name, count, states, Map.get(U32, 4294967295, names, name))

def Registry.block(registry: Registry, +name: String) -> Registry & Result<&2, &2, Error, Block>:
  Registry.block.valid(registry, name, resource_valid(name))

# Validate all assignments before resolving missing values by the selected policy.
def property_find(properties: List<&2, Property>, +name: String) -> Maybe<&2, Property>:
  match properties:
    case Nil{}: None{}
    case +property <> rest:
      Property{+key, values, count, stride} = property
      J.choose(Maybe<&2, Property>, Some{property}, property_find(rest, name), String.eq(key, name))

def value_index(values: List<&2, String>, +value: String, +index: U32) -> Maybe<&2, U32>:
  match values:
    case Nil{}: None{}
    case text <> rest:
      J.choose(Maybe<&2, U32>, Some{index}, value_index(rest, value, (index + 1 : U32)), String.eq(text, value))

def assignment_value(indices: Map<&2, U32>, +name: String, value: String, index: Maybe<&2, U32>) -> Result<&2, &2, Error, Map<&2, U32>>:
  match index:
    case None{}: Fail{InvalidValue{name, value}}
    case Some{i}: Done{Map.set(&2, U32, indices, name, i)}

def assignment_property(indices: Map<&2, U32>, +name: String, +value: String, property: Maybe<&2, Property>) -> Result<&2, &2, Error, Map<&2, U32>>:
  match property:
    case None{}: Fail{UnknownProperty{name}}
    case Some{Property{key, values, count, stride}}:
      assignment_value(indices, name, value, value_index(values, value, 0))

def assignment_unique(properties: List<&2, Property>, +name: String, value: String, checked: Map<&2, U32> & Bool) -> Result<&2, &2, Error, Map<&2, U32>>:
  (indices, duplicate) = checked
  match duplicate:
    case True{}: Fail{DuplicateProperty{name}}
    case False{}: assignment_property(indices, name, value, property_find(properties, name))

def assignments_validate(assignments: List<&2, Assignment>, +properties: List<&2, Property>, current: Result<&2, &2, Error, Map<&2, U32>>) -> Result<&2, &2, Error, Map<&2, U32>>:
  match assignments current:
    case _ Fail{error}: Fail{error}
    case Nil{} Done{indices}: Done{indices}
    case Assignment{+name, value} <> rest Done{indices}:
      assignments_validate(rest, properties, assignment_unique(properties, name, value, Map.has(&2, U32, indices, name)))

type Resolution is Data:
  Resolution{indices: Map<&2, U32>, offset: U32}

def property_step.exact(+name: String, stride: U32, +offset: U32, lookup: Map<&2, U32> & U32) -> Result<&2, &2, Error, Resolution>:
  (indices, +index) = lookup
  J.choose(Result<&2, &2, Error, Resolution>, Fail{MissingProperty{name}}, Done{Resolution{indices, (offset + index * stride : U32)}}, U32.is_eq(index, 4294967295))

def property_step.defaults(+count: U32, +stride: U32, default_offset: U32, offset: U32, lookup: Map<&2, U32> & U32) -> Result<&2, &2, Error, Resolution>:
  (indices, +index) = lookup
  digit = J.choose(U32, ((default_offset / stride) % count : U32), index, U32.is_eq(index, 4294967295))
  Done{Resolution{indices, (offset + digit * stride : U32)}}

def property_step(property: Property, policy: Policy, default_offset: U32, resolution: Resolution) -> Result<&2, &2, Error, Resolution>:
  match property policy resolution:
    case Property{+name, values, count, stride} Exact{} Resolution{indices, offset}:
      property_step.exact(name, stride, offset, Map.get(U32, 4294967295, indices, name))
    case Property{+name, values, count, stride} Defaults{} Resolution{indices, offset}:
      property_step.defaults(count, stride, default_offset, offset, Map.get(U32, 4294967295, indices, name))

def resolve_properties(properties: List<&2, Property>, +first: U32, +default_offset: U32, +policy: Policy, current: Result<&2, &2, Error, Resolution>) -> Result<&2, &2, Error, U32>:
  match properties current:
    case _ Fail{error}: Fail{error}
    case Nil{} Done{Resolution{indices, offset}}: Done{(first + offset : U32)}
    case property <> rest Done{resolution}:
      resolve_properties(rest, first, default_offset, policy, property_step(property, policy, default_offset, resolution))

def resolve_validated(+properties: List<&2, Property>, first: U32, default_offset: U32, policy: Policy, validated: Result<&2, &2, Error, Map<&2, U32>>) -> Result<&2, &2, Error, U32>:
  match validated:
    case Fail{error}: Fail{error}
    case Done{indices}: resolve_properties(properties, first, default_offset, policy, Done{Resolution{indices, 0}})

def Registry.resolve.block(assignments: List<&2, Assignment>, policy: Policy, lookup: Registry & Result<&2, &2, Error, Block>) -> Registry & Result<&2, &2, Error, U32>:
  (registry, result) = lookup
  match result:
    case Fail{error}: (registry, Fail{error})
    case Done{Block{protocol, name, +first, count, default_id, +properties}}:
      (registry, resolve_validated(properties, first, (default_id - first : U32), policy, assignments_validate(assignments, properties, Done{MTip{}})))

def Registry.resolve(registry: Registry, name: String, assignments: List<&2, Assignment>, policy: Policy) -> Registry & Result<&2, &2, Error, U32>:
  Registry.resolve.block(assignments, policy, Registry.block(registry, name))

# State intervals are contiguous and ordered by protocol ID after validation.
type SearchStep is Data:
  SearchNext{lo: U32, hi: U32}
  SearchHit{block: Block}
  SearchMiss{}

def search_compare(+target: U32, +lo: U32, +hi: U32, +mid: U32, read: Array<Block> & Block) -> Array<Block> & SearchStep:
  (blocks, +block) = read
  Block{protocol, name, +first, count, default_id, props} = block
  (blocks, J.choose(SearchStep, SearchNext{lo, mid}, J.choose(SearchStep, SearchNext{(mid + 1 : U32), hi}, SearchHit{block}, U32.is_ge(target, (first + count : U32))), U32.is_lt(target, first)))

def search_request.valid(blocks: Array<Block>, +target: U32, +lo: U32, +hi: U32, valid: Bool) -> Array<Block> & SearchStep:
  match valid:
    case False{}: (blocks, SearchMiss{})
    case True{}:
      +mid = ((lo + hi) / 2 : U32)
      search_compare(target, lo, hi, mid, Array.get(Block, blocks, mid))

def search_request(blocks: Array<Block>, target: U32, +lo: U32, +hi: U32) -> Array<Block> & SearchStep:
  search_request.valid(blocks, target, lo, hi, U32.is_lt(lo, hi))

def search(fuel: Nat, +target: U32, pending: Array<Block> & SearchStep) -> Array<Block> & Result<&2, &2, Error, Block>:
  match fuel:
    case 0n:
      (blocks, step) = pending
      (blocks, Fail{InvalidState{target}})
    case 1n+p:
      (blocks, step) = pending
      match step:
        case SearchMiss{}: (blocks, Fail{InvalidState{target}})
        case SearchHit{block}: (blocks, Done{block})
        case SearchNext{lo, hi}:
          search(p, target, search_request(blocks, target, lo, hi))

def Registry.state_block.found(names: Map<&2, U32>, count: U32, states: U32, found: Array<Block> & Result<&2, &2, Error, Block>) -> Registry & Result<&2, &2, Error, Block>:
  (blocks, result) = found
  (Registry{blocks, names, count, states}, result)

def Registry.state_block.valid(registry: Registry, state_id: U32, valid: Bool) -> Registry & Result<&2, &2, Error, Block>:
  match registry valid:
    case Registry{blocks, names, count, states} False{}:
      (Registry{blocks, names, count, states}, Fail{InvalidState{state_id}})
    case Registry{blocks, names, +count, states} True{}:
      Registry.state_block.found(names, count, states, search(14n, state_id, (blocks, SearchNext{0, count})))

def Registry.state_block(registry: Registry, +state_id: U32) -> Registry & Result<&2, &2, Error, Block>:
  match registry:
    case Registry{blocks, names, count, +states}:
      Registry.state_block.valid(Registry{blocks, names, count, states}, state_id, U32.is_lt(state_id, states))

def decode_value(name: String, acc: List<&2, Assignment>, found: Maybe<&2, String>) -> Result<&2, &2, Error, List<&2, Assignment>>:
  match found:
    case None{}: Fail{SchemaError{0, "corrupt property stride/domain"}}
    case Some{value}: Done{Assignment{name, value} <> acc}

def decode_property(property: Property, relative: U32, acc: List<&2, Assignment>) -> Result<&2, &2, Error, List<&2, Assignment>>:
  match property:
    case Property{name, values, count, stride}:
      decode_value(name, acc, List.get(&2, String, values, U32.to_nat(((relative / stride) % count : U32))))

def decode_properties(properties: List<&2, Property>, +relative: U32, current: Result<&2, &2, Error, List<&2, Assignment>>) -> Result<&2, &2, Error, List<&2, Assignment>>:
  match properties current:
    case _ Fail{error}: Fail{error}
    case Nil{} Done{acc}: Done{List.reverse(&2, Assignment, acc)}
    case property <> rest Done{acc}:
      decode_properties(rest, relative, decode_property(property, relative, acc))

def Registry.decode.result(registry: Registry, protocol: U32, name: String, state_id: U32, decoded: Result<&2, &2, Error, List<&2, Assignment>>) -> Registry & Result<&2, &2, Error, Resolved>:
  match decoded:
    case Fail{error}: (registry, Fail{error})
    case Done{assignments}: (registry, Done{Resolved{protocol, name, state_id, assignments}})

def Registry.decode.block(+state_id: U32, lookup: Registry & Result<&2, &2, Error, Block>) -> Registry & Result<&2, &2, Error, Resolved>:
  (registry, result) = lookup
  match result:
    case Fail{error}: (registry, Fail{error})
    case Done{Block{protocol, name, first, count, default_id, properties}}:
      Registry.decode.result(registry, protocol, name, state_id, decode_properties(properties, (state_id - first : U32), Done{Nil{}}))

def Registry.decode(registry: Registry, +state_id: U32) -> Registry & Result<&2, &2, Error, Resolved>:
  Registry.decode.block(state_id, Registry.state_block(registry, state_id))

# Canonical identity v1 hashes parsed metadata, never the source TSV layout.
# A reverse byte accumulator gives linear assembly with an explicit 64 MiB cap.
type Canonical is Data:
  Canonical{room: Nat, reversed: List<&2, U32>}

def canonical_limit() -> Nat:
  67108864n

def canonical_add(bytes: List<&2, U32>, buffer: Canonical) -> Result<&2, &2, String, Canonical>:
  match bytes buffer:
    case Nil{} _: Done{buffer}
    case _ Canonical{0n, reversed}: Fail{"canonical identity exceeds 67108864 bytes"}
    case byte <> rest Canonical{1n+remaining, reversed}:
      canonical_add(rest, Canonical{remaining, byte <> reversed})

def canonical_number(value: U32, current: Result<&2, &2, String, Canonical>) -> Result<&2, &2, String, Canonical>:
  match current:
    case Fail{error}: Fail{error}
    case Done{buffer}: canonical_add(Hash.word_bytes(value), buffer)

def canonical_string.bytes(encoded: Result<&2, &2, String, List<&2, U32>>, buffer: Canonical) -> Result<&2, &2, String, Canonical>:
  match encoded:
    case Fail{error}: Fail{"canonical UTF-8: " ++ error}
    case Done{+bytes}:
      do Result<&2, &2, String, Canonical>:
        prefixed : Canonical <- canonical_add(Hash.word_bytes(U32.from_nat(List.length(&2, U32, bytes))), buffer)
        canonical_add(bytes, prefixed)

def canonical_string(text: String, current: Result<&2, &2, String, Canonical>) -> Result<&2, &2, String, Canonical>:
  match current:
    case Fail{error}: Fail{error}
    # Parsed names/domains have at most 512/256 scalars. 4096 bytes also
    # accommodates forged invalid-scalar rejection before any length narrowing.
    case Done{buffer}: canonical_string.bytes(Unicode.encode(4096n, text), buffer)

def canonical_property_count(values: List<&2, Property>, fuel: Nat, +count: U32) -> Result<&2, &2, String, U32>:
  match values fuel:
    case Nil{} _: Done{count}
    case _ 0n: Fail{"canonical identity exceeds 64 properties"}
    case property <> rest 1n+remaining: canonical_property_count(rest, remaining, U32.inc(count))

def canonical_values(values: List<&2, String>, remaining: Nat, current: Result<&2, &2, String, Canonical>) -> Result<&2, &2, String, Canonical>:
  match values remaining current:
    case _ _ Fail{error}: Fail{error}
    case Nil{} 0n _: current
    case Nil{} _ _: Fail{"canonical property count disagrees with domain"}
    case _ 0n _: Fail{"canonical property count disagrees with domain"}
    case text <> rest 1n+room _: canonical_values(rest, room, canonical_string(text, current))

def canonical_property.valid(property: Property, buffer: Canonical, valid: Bool) -> Result<&2, &2, String, Canonical>:
  match property valid:
    case _ False{}: Fail{"canonical property count must be between 1 and 256"}
    case Property{name, values, +count, stride} True{}:
      canonical_values(values, U32.to_nat(count), canonical_number(stride, canonical_number(count, canonical_string(name, Done{buffer}))))

def canonical_property(+property: Property, current: Result<&2, &2, String, Canonical>) -> Result<&2, &2, String, Canonical>:
  match property current:
    case _ Fail{error}: Fail{error}
    case Property{name, values, +count, stride} Done{buffer}:
      canonical_property.valid(property, buffer, U32.is_ge(count, 1) && U32.is_le(count, 256))

def canonical_properties(properties: List<&2, Property>, current: Result<&2, &2, String, Canonical>) -> Result<&2, &2, String, Canonical>:
  match properties:
    case Nil{}: current
    case property <> rest: canonical_properties(rest, canonical_property(property, current))

def canonical_block.count(block: Block, counted: Result<&2, &2, String, U32>, current: Result<&2, &2, String, Canonical>) -> Result<&2, &2, String, Canonical>:
  match block counted:
    case _ Fail{error}: Fail{error}
    case Block{protocol, name, first, count, default_id, properties} Done{property_count}:
      canonical_properties(properties,
        canonical_number(property_count, canonical_number(default_id, canonical_number(count, canonical_number(first,
          canonical_string(name, canonical_number(protocol, current)))))))

def canonical_block(block: Block, current: Result<&2, &2, String, Canonical>) -> Result<&2, &2, String, Canonical>:
  match block current:
    case _ Fail{error}: Fail{error}
    case Block{protocol, name, first, count, default_id, +properties} Done{buffer}:
      canonical_block.count(Block{protocol, name, first, count, default_id, properties}, canonical_property_count(properties, 64n, 0), Done{buffer})

def canonical_start(count: U32, states: U32) -> Result<&2, &2, String, Canonical>:
  do Result<&2, &2, String, Canonical>:
    magic : Canonical <- canonical_add([66, 101, 110, 100, 82, 101, 103, 105, 115, 116, 114, 121, 73, 100, 101, 110, 116, 105, 116, 121, 0], Canonical{canonical_limit(), Nil{}})
    canonical_number(states, canonical_number(count, canonical_number(1, Done{magic})))

type IdentityTraversal is Type:
  IdentityTraversal{registry: Registry, current: Result<&2, &2, String, Canonical>}

def identity_step.read(names: Map<&2, U32>, count: U32, states: U32, current: Result<&2, &2, String, Canonical>, read: Array<Block> & Block) -> IdentityTraversal:
  (blocks, block) = read
  IdentityTraversal{Registry{blocks, names, count, states}, canonical_block(block, current)}

def identity_step(index: U32, registry: Registry, current: Result<&2, &2, String, Canonical>) -> IdentityTraversal:
  match registry:
    case Registry{blocks, names, count, states}:
      identity_step.read(names, count, states, current, Array.get(Block, blocks, index))

def identity_blocks(fuel: Nat, +index: U32, pending: IdentityTraversal) -> IdentityTraversal:
  match fuel pending:
    case _ IdentityTraversal{registry, Fail{error}}: IdentityTraversal{registry, Fail{error}}
    case 0n _: pending
    case 1n+remaining IdentityTraversal{registry, current}:
      identity_blocks(remaining, U32.inc(index), identity_step(index, registry, current))

def identity_finish.hash(registry: Registry, result: Result<&2, &2, String, Hash.Digest>) -> Registry & Result<&2, &2, String, String>:
  match result:
    case Fail{error}: (registry, Fail{error})
    case Done{digest}: (registry, Done{Hash.Digest.hex(digest)})

def identity_finish(registry: Registry, current: Result<&2, &2, String, Canonical>) -> Registry & Result<&2, &2, String, String>:
  match current:
    case Fail{error}: (registry, Fail{error})
    case Done{Canonical{room, reversed}}:
      identity_finish.hash(registry, Hash.digest(canonical_limit(), List.reverse(&2, U32, reversed)))

def identity_finish.pending(pending: IdentityTraversal) -> Registry & Result<&2, &2, String, String>:
  match pending:
    case IdentityTraversal{registry, result}: identity_finish(registry, result)

def identity_sized.valid(registry: Registry, +count: U32, states: U32, valid: Bool) -> Registry & Result<&2, &2, String, String>:
  match valid:
    case False{}: (registry, Fail{"canonical registry count is invalid or exceeds its array"})
    case True{}: identity_finish.pending(identity_blocks(U32.to_nat(count), 0, IdentityTraversal{registry, canonical_start(count, states)}))

def identity_sized(names: Map<&2, U32>, +count: U32, +states: U32, sized: Array<Block> & U32) -> Registry & Result<&2, &2, String, String>:
  (blocks, capacity) = sized
  identity_sized.valid(Registry{blocks, names, count, states}, count, states, U32.is_gt(count, 0) && U32.is_le(count, 4096) && U32.is_le(count, capacity))

# Requires metadata validated by parse/load. Array bounds, UTF-8, list counts,
# and serialization capacity remain checked, including on failure paths.
def Registry.identity(registry: Registry) -> Registry & Result<&2, &2, String, String>:
  match registry:
    case Registry{blocks, names, count, states}: identity_sized(names, count, states, Array.size(Block, blocks))

law identity_failure_preserves_owner:
  for registry: Registry
  for +message: String
  {identity_finish(registry, Fail{message}) == (registry, Fail{message}) : Registry & Result<&2, &2, String, String>}

def identity_failure_preserves_owner(registry, message):
  {==}

law canonical_zero_budget_rejected:
  for byte: U32
  for rest: List<&2, U32>
  for reversed: List<&2, U32>
  {canonical_add(byte <> rest, Canonical{0n, reversed}) == Fail{"canonical identity exceeds 67108864 bytes"} : Result<&2, &2, String, Canonical>}

def canonical_zero_budget_rejected(byte, rest, reversed):
  {==}

law strict_file_utf8_rejected:
  {read_text.decode(Unicode.decode(4194304n, [192, 128])) == Fail{SchemaError{0, "UTF-8: invalid UTF-8 leading byte"}} : Result<&2, &2, Error, String>}

def strict_file_utf8_rejected():
  {==}

# Small implementation laws; execution parity is checked separately against reports.
law exact_missing_rejected:
  for +name: String
  {property_step.exact(name, 3, 0, (MTip{}, 4294967295)) == Fail{MissingProperty{name}} : Result<&2, &2, Error, Resolution>}

def exact_missing_rejected(name):
  {==}

law duplicate_assignment_rejected:
  for +name: String
  for value: String
  {assignment_unique(Nil{}, name, value, (MTip{}, True{})) == Fail{DuplicateProperty{name}} : Result<&2, &2, Error, Map<&2, U32>>}

def duplicate_assignment_rejected(name, value):
  {==}

law defaults_offset_fixture:
  {resolve_properties([Property{"powered", ["true", "false"], 2, 3}, Property{"axis", ["x", "y", "z"], 3, 1}], 1, 3, Defaults{}, Done{Resolution{MTip{}, 0}}) == Done{4} : Result<&2, &2, Error, U32>}

def defaults_offset_fixture():
  {==}

law decode_order_fixture:
  {decode_properties([Property{"powered", ["true", "false"], 2, 3}, Property{"axis", ["x", "y", "z"], 3, 1}], 5, Done{Nil{}}) == Done{[Assignment{"powered", "false"}, Assignment{"axis", "z"}]} : Result<&2, &2, Error, List<&2, Assignment>>}

def decode_order_fixture():
  {==}

law invalid_state_preserves_owner:
  for blocks: Array<Block>
  for names: Map<&2, U32>
  for count: U32
  for +states: U32
  for +state_id: U32
  for invalid: {U32.is_lt(state_id, states) == False{} : Bool}
  {Registry.decode(Registry{blocks, names, count, states}, state_id) == (Registry{blocks, names, count, states}, Fail{InvalidState{state_id}}) : Registry & Result<&2, &2, Error, Resolved>}

def invalid_state_preserves_owner(blocks, names, count, states, state_id, invalid):
  %Equal.sym(Bool, U32.is_lt(state_id, states), False{}, invalid) : {Registry.decode.block(state_id, Registry.state_block.valid(Registry{blocks, names, count, states}, state_id, _)) == (Registry{blocks, names, count, states}, Fail{InvalidState{state_id}}) : Registry & Result<&2, &2, Error, Resolved>}
  {==}
