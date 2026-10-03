import Base

# Pure JSON. Offsets count Unicode scalar/code-point positions, starting at zero.
type Value is Data:
  JNull{}
  JBool{value: Bool}
  JNumber{raw: String}
  JString{value: String}
  JArray{values: List<&2, Value>}
  JObject{members: List<&2, Member>}

type Member is Data:
  JMember{key: String, value: Value}

type Limits is Data:
  Limits{max_codepoints: Nat, max_depth: U32}

def default_limits() -> Limits:
  Limits{16384n, 64}

type Frame is Data:
  ArrayFrame{values: List<&2, Value>}
  ObjectFrame{members: List<&2, Member>, key: String, seen: Map<&2, Unit>}

type Target is Data:
  StringTarget{}
  KeyTarget{members: List<&2, Member>, seen: Map<&2, Unit>}

type Escape is Data:
  Plain{}
  Slash{}
  Hex{left: U32, code: U32, high: U32}
  LowSlash{high: U32}
  LowU{high: U32}

type Mode is Data:
  NeedValue{}
  ArrayWant{values: List<&2, Value>, allow_end: Bool}
  ArrayAfter{values: List<&2, Value>}
  ObjectWant{members: List<&2, Member>, seen: Map<&2, Unit>, allow_end: Bool}
  ColonWant{members: List<&2, Member>, seen: Map<&2, Unit>, key: String}
  ObjectAfter{members: List<&2, Member>, seen: Map<&2, Unit>}
  StringRead{reversed: String, escape: Escape, target: Target}
  NumberRead{reversed: String, state: U32}
  WordRead{remaining: String, value: Value}
  Produced{value: Value}
  Complete{value: Value}

type State is Data:
  State{text: String, offset: U32, depth: U32, frames: List<&2, Frame>, mode: Mode}

type Step is Data:
  Continue{state: State}
  Finished{value: Value}
  Rejected{message: String}

def choose(-A: Data, yes: A, no: A, test: Bool) -> A:
  match test:
    case True{}: yes
    case False{}: no

def error(offset: U32, message: String) -> Step:
  Rejected{message ++ " at offset " ++ U32.show(offset)}

def stay(text: String, offset: U32, depth: U32, frames: List<&2, Frame>, mode: Mode) -> Step:
  Continue{State{text, offset, depth, frames, mode}}

def advance(text: String, offset: U32, depth: U32, frames: List<&2, Frame>, mode: Mode) -> Step:
  stay(text, U32.add(offset, 1), depth, frames, mode)

def whitespace(+c: U32) -> Bool:
  U32.is_eq(c, 32) || U32.is_eq(c, 9) || U32.is_eq(c, 10) || U32.is_eq(c, 13)

def digit(+c: U32) -> Bool:
  U32.is_ge(c, 48) && U32.is_le(c, 57)

def scalar(+c: U32) -> Bool:
  U32.is_le(c, 1114111) && Bool.not(U32.is_ge(c, 55296) && U32.is_le(c, 57343))

def accepting(+state: U32) -> Bool:
  U32.is_eq(state, 1) || U32.is_eq(state, 2) || U32.is_eq(state, 4) || U32.is_eq(state, 7)

# Limit counting examines at most limit+1 input characters.
def within(fuel: Nat, text: String) -> Bool:
  match fuel text:
    case _ SNil{}: True{}
    case 0n SCon{h, t}: False{}
    case 1n+f SCon{h, t}: within(f, t)

def open_container(+c: U32, text: String, +offset: U32, +depth: U32, +frames: List<&2, Frame>, max_depth: U32) -> Step:
  mode = choose(Mode, ArrayWant{Nil{}, True{}}, ObjectWant{Nil{}, MTip{}, True{}}, U32.is_eq(c, 91))
  choose(Step, advance(text, offset, U32.add(depth, 1), frames, mode),
    error(offset, "nesting limit exceeded"), U32.is_lt(depth, max_depth))

def initial_number(c: U32) -> U32:
  match c:
    case 45: 0
    case 48: 1
    case _: 2

def value_char(+c: U32, +text: String, +offset: U32, +depth: U32, +frames: List<&2, Frame>, max_depth: U32) -> Step:
  match c:
    case 32: advance(text, offset, depth, frames, NeedValue{})
    case 9: advance(text, offset, depth, frames, NeedValue{})
    case 10: advance(text, offset, depth, frames, NeedValue{})
    case 13: advance(text, offset, depth, frames, NeedValue{})
    case 91: open_container(c, text, offset, depth, frames, max_depth)
    case 123: open_container(c, text, offset, depth, frames, max_depth)
    case 34: advance(text, offset, depth, frames, StringRead{SNil{}, Plain{}, StringTarget{}})
    case 110: advance(text, offset, depth, frames, WordRead{"ull", JNull{}})
    case 116: advance(text, offset, depth, frames, WordRead{"rue", JBool{True{}}})
    case 102: advance(text, offset, depth, frames, WordRead{"alse", JBool{False{}}})
    case _:
      choose(Step, advance(text, offset, depth, frames,
        NumberRead{Char.show(Chr{c}), initial_number(c)}),
        error(offset, "expected JSON value"), U32.is_eq(c, 45) || digit(c))

def array_want(+c: U32, +text: String, +offset: U32, +depth: U32, +frames: List<&2, Frame>, +values: List<&2, Value>, allow_end: Bool) -> Step:
  match c:
    case 93:
      choose(Step, advance(text, offset, U32.sub(depth, 1), frames,
        Produced{JArray{List.reverse(&2, Value, values)}}), error(offset, "trailing array comma"), allow_end)
    case _:
      choose(Step, advance(text, offset, depth, frames, ArrayWant{values, allow_end}),
        stay(SCon{Chr{c}, text}, offset, depth, ArrayFrame{values} <> frames, NeedValue{}), whitespace(c))

def array_after(+c: U32, +text: String, +offset: U32, +depth: U32, +frames: List<&2, Frame>, +values: List<&2, Value>) -> Step:
  match c:
    case 93: advance(text, offset, U32.sub(depth, 1), frames, Produced{JArray{List.reverse(&2, Value, values)}})
    case 44: advance(text, offset, depth, frames, ArrayWant{values, False{}})
    case _:
      choose(Step, advance(text, offset, depth, frames, ArrayAfter{values}),
        error(offset, "expected array comma or closing bracket"), whitespace(c))

def object_want(+c: U32, +text: String, +offset: U32, +depth: U32, +frames: List<&2, Frame>, +members: List<&2, Member>, +seen: Map<&2, Unit>, allow_end: Bool) -> Step:
  match c:
    case 125:
      choose(Step, advance(text, offset, U32.sub(depth, 1), frames,
        Produced{JObject{List.reverse(&2, Member, members)}}), error(offset, "trailing object comma"), allow_end)
    case 34: advance(text, offset, depth, frames, StringRead{SNil{}, Plain{}, KeyTarget{members, seen}})
    case _:
      choose(Step, advance(text, offset, depth, frames, ObjectWant{members, seen, allow_end}),
        error(offset, "expected object member name"), whitespace(c))

def colon_want(+c: U32, +text: String, +offset: U32, +depth: U32, +frames: List<&2, Frame>, +members: List<&2, Member>, +seen: Map<&2, Unit>, +key: String) -> Step:
  match c:
    case 58: advance(text, offset, depth, ObjectFrame{members, key, seen} <> frames, NeedValue{})
    case _:
      choose(Step, advance(text, offset, depth, frames, ColonWant{members, seen, key}),
        error(offset, "expected member colon"), whitespace(c))

def object_after(+c: U32, +text: String, +offset: U32, +depth: U32, +frames: List<&2, Frame>, +members: List<&2, Member>, +seen: Map<&2, Unit>) -> Step:
  match c:
    case 125: advance(text, offset, U32.sub(depth, 1), frames, Produced{JObject{List.reverse(&2, Member, members)}})
    case 44: advance(text, offset, depth, frames, ObjectWant{members, seen, False{}})
    case _:
      choose(Step, advance(text, offset, depth, frames, ObjectAfter{members, seen}),
        error(offset, "expected object comma or closing brace"), whitespace(c))

def key_finish(text: String, +offset: U32, depth: U32, frames: List<&2, Frame>, members: List<&2, Member>, +key: String, lookup: Map<&2, Unit> & Bool) -> Step:
  (seen, duplicate) = lookup
  match duplicate:
    case True{}: error(offset, "duplicate object member")
    case False{}:
      advance(text, offset, depth, frames, ColonWant{members, Map.set(&2, Unit, seen, key, Unit{}), key})

def string_finish(target: Target, reversed: String, text: String, offset: U32, depth: U32, frames: List<&2, Frame>) -> Step:
  match target:
    case StringTarget{}:
      advance(text, offset, depth, frames, Produced{JString{String.reverse(reversed)}})
    case KeyTarget{members, seen}:
      +key = String.reverse(reversed)
      key_finish(text, offset, depth, frames, members, key, Map.has(&2, Unit, seen, key))

def hex_digit(+c: U32) -> Maybe<&2, U32>:
  choose(Maybe<&2, U32>, Some{U32.sub(c, 48)},
    choose(Maybe<&2, U32>, Some{U32.sub(c, 55)},
      choose(Maybe<&2, U32>, Some{U32.sub(c, 87)}, None{},
        U32.is_ge(c, 97) && U32.is_le(c, 102)),
      U32.is_ge(c, 65) && U32.is_le(c, 70)), digit(c))

def hex_finish(+code: U32, +high: U32, +text: String, +offset: U32, +depth: U32, +frames: List<&2, Frame>, +reversed: String, +target: Target) -> Step:
  match high:
    case 0:
      choose(Step, advance(text, offset, depth, frames, StringRead{reversed, LowSlash{code}, target}),
        choose(Step, advance(text, offset, depth, frames, StringRead{SCon{Chr{code}, reversed}, Plain{}, target}),
          error(offset, "unpaired low surrogate"), scalar(code)),
        U32.is_ge(code, 55296) && U32.is_le(code, 56319))
    case _:
      decoded = U32.add(65536, U32.add(U32.mul(U32.sub(high, 55296), 1024), U32.sub(code, 56320)))
      choose(Step, advance(text, offset, depth, frames, StringRead{SCon{Chr{decoded}, reversed}, Plain{}, target}),
        error(offset, "invalid low surrogate"), U32.is_ge(code, 56320) && U32.is_le(code, 57343))

def hex_read(found: Maybe<&2, U32>, +left: U32, +code: U32, +high: U32, +text: String, +offset: U32, +depth: U32, +frames: List<&2, Frame>, +reversed: String, +target: Target) -> Step:
  match found:
    case None{}: error(offset, "invalid Unicode escape digit")
    case Some{value}:
      +next = U32.add(U32.mul(code, 16), value)
      choose(Step, hex_finish(next, high, text, offset, depth, frames, reversed, target),
        advance(text, offset, depth, frames, StringRead{reversed, Hex{U32.sub(left, 1), next, high}, target}), U32.is_eq(left, 1))

def escaped(+c: U32, +text: String, +offset: U32, +depth: U32, +frames: List<&2, Frame>, +reversed: String, +target: Target) -> Step:
  match c:
    case 34: advance(text, offset, depth, frames, StringRead{SCon{Chr{34}, reversed}, Plain{}, target})
    case 92: advance(text, offset, depth, frames, StringRead{SCon{Chr{92}, reversed}, Plain{}, target})
    case 47: advance(text, offset, depth, frames, StringRead{SCon{Chr{47}, reversed}, Plain{}, target})
    case 98: advance(text, offset, depth, frames, StringRead{SCon{Chr{8}, reversed}, Plain{}, target})
    case 102: advance(text, offset, depth, frames, StringRead{SCon{Chr{12}, reversed}, Plain{}, target})
    case 110: advance(text, offset, depth, frames, StringRead{SCon{Chr{10}, reversed}, Plain{}, target})
    case 114: advance(text, offset, depth, frames, StringRead{SCon{Chr{13}, reversed}, Plain{}, target})
    case 116: advance(text, offset, depth, frames, StringRead{SCon{Chr{9}, reversed}, Plain{}, target})
    case 117: advance(text, offset, depth, frames, StringRead{reversed, Hex{4, 0, 0}, target})
    case _: error(offset, "invalid string escape")

def string_char(escape: Escape, +c: U32, +text: String, +offset: U32, +depth: U32, +frames: List<&2, Frame>, +reversed: String, +target: Target) -> Step:
  match escape:
    case Plain{}:
      match c:
        case 34: string_finish(target, reversed, text, offset, depth, frames)
        case 92: advance(text, offset, depth, frames, StringRead{reversed, Slash{}, target})
        case _:
          choose(Step, advance(text, offset, depth, frames, StringRead{SCon{Chr{c}, reversed}, Plain{}, target}),
            error(offset, "invalid unescaped string character"), U32.is_ge(c, 32) && scalar(c))
    case Slash{}: escaped(c, text, offset, depth, frames, reversed, target)
    case Hex{left, code, high}: hex_read(hex_digit(c), left, code, high, text, offset, depth, frames, reversed, target)
    case LowSlash{high}:
      choose(Step, advance(text, offset, depth, frames, StringRead{reversed, LowU{high}, target}),
        error(offset, "high surrogate requires low surrogate escape"), U32.is_eq(c, 92))
    case LowU{high}:
      choose(Step, advance(text, offset, depth, frames, StringRead{reversed, Hex{4, 0, high}, target}),
        error(offset, "high surrogate requires low surrogate escape"), U32.is_eq(c, 117))

# Number states: 0 minus; 1 zero; 2 integer; 3 decimal point; 4 fraction;
# 5 exponent marker; 6 exponent sign; 7 exponent digits.
def number_finish(+state: U32, +reversed: String, +text: String, +offset: U32, +depth: U32, +frames: List<&2, Frame>) -> Step:
  choose(Step, stay(text, offset, depth, frames, Produced{JNumber{String.reverse(reversed)}}),
    error(offset, "incomplete number"), accepting(state))

def number_next(state: U32, +c: U32) -> Maybe<&2, U32>:
  match state:
    case 0: choose(Maybe<&2, U32>, Some{initial_number(c)}, None{}, digit(c))
    case 1:
      match c:
        case 46: Some{3}
        case 101: Some{5}
        case 69: Some{5}
        case _: None{}
    case 2:
      match c:
        case 46: Some{3}
        case 101: Some{5}
        case 69: Some{5}
        case _: choose(Maybe<&2, U32>, Some{2}, None{}, digit(c))
    case 3: choose(Maybe<&2, U32>, Some{4}, None{}, digit(c))
    case 4:
      match c:
        case 101: Some{5}
        case 69: Some{5}
        case _: choose(Maybe<&2, U32>, Some{4}, None{}, digit(c))
    case 5:
      match c:
        case 43: Some{6}
        case 45: Some{6}
        case _: choose(Maybe<&2, U32>, Some{7}, None{}, digit(c))
    case 6: choose(Maybe<&2, U32>, Some{7}, None{}, digit(c))
    case _: choose(Maybe<&2, U32>, Some{7}, None{}, digit(c))

def number_char(next: Maybe<&2, U32>, state: U32, +c: U32, +text: String, +offset: U32, +depth: U32, +frames: List<&2, Frame>, +reversed: String) -> Step:
  match next:
    case Some{n}: advance(text, offset, depth, frames, NumberRead{SCon{Chr{c}, reversed}, n})
    case None{}: number_finish(state, reversed, SCon{Chr{c}, text}, offset, depth, frames)

def produced(frames: List<&2, Frame>, text: String, offset: U32, depth: U32, value: Value) -> Step:
  match frames:
    case Nil{}: stay(text, offset, depth, Nil{}, Complete{value})
    case ArrayFrame{values} <> rest: stay(text, offset, depth, rest, ArrayAfter{value <> values})
    case ObjectFrame{members, key, seen} <> rest:
      stay(text, offset, depth, rest, ObjectAfter{JMember{key, value} <> members, seen})

def step_mode(mode: Mode, +text: String, +offset: U32, +depth: U32, +frames: List<&2, Frame>, max_depth: U32) -> Step:
  match mode:
    case Produced{value}: produced(frames, text, offset, depth, value)
    case WordRead{remaining, value}:
      match remaining text:
        case SNil{} _: stay(text, offset, depth, frames, Produced{value})
        case SCon{wanted, suffix} SCon{h, t}:
          choose(Step, advance(t, offset, depth, frames, WordRead{suffix, value}),
            error(offset, "invalid literal"), Char.is_eq(wanted, h))
        case _ SNil{}: error(offset, "incomplete literal")
    case Complete{+value}:
      match text:
        case SNil{}: Finished{value}
        case SCon{h, t}:
          choose(Step, advance(t, offset, depth, frames, Complete{value}),
            error(offset, "trailing input"), whitespace(Char.to_u32(h)))
    case NeedValue{}:
      match text:
        case SNil{}: error(offset, "expected JSON value")
        case SCon{h, t}: value_char(Char.to_u32(h), t, offset, depth, frames, max_depth)
    case ArrayWant{values, allow_end}:
      match text:
        case SNil{}: error(offset, "unclosed array")
        case SCon{h, t}: array_want(Char.to_u32(h), t, offset, depth, frames, values, allow_end)
    case ArrayAfter{values}:
      match text:
        case SNil{}: error(offset, "unclosed array")
        case SCon{h, t}: array_after(Char.to_u32(h), t, offset, depth, frames, values)
    case ObjectWant{members, seen, allow_end}:
      match text:
        case SNil{}: error(offset, "unclosed object")
        case SCon{h, t}: object_want(Char.to_u32(h), t, offset, depth, frames, members, seen, allow_end)
    case ColonWant{members, seen, key}:
      match text:
        case SNil{}: error(offset, "expected member colon")
        case SCon{h, t}: colon_want(Char.to_u32(h), t, offset, depth, frames, members, seen, key)
    case ObjectAfter{members, seen}:
      match text:
        case SNil{}: error(offset, "unclosed object")
        case SCon{h, t}: object_after(Char.to_u32(h), t, offset, depth, frames, members, seen)
    case StringRead{reversed, escape, target}:
      match text:
        case SNil{}: error(offset, "unterminated string or escape")
        case SCon{h, t}: string_char(escape, Char.to_u32(h), t, offset, depth, frames, reversed, target)
    case NumberRead{reversed, +state}:
      match text:
        case SNil{}: number_finish(state, reversed, SNil{}, offset, depth, frames)
        case SCon{+h, t}: number_char(number_next(state, Char.to_u32(h)), state, Char.to_u32(h), t, offset, depth, frames, reversed)

def step_with(state: State, max_depth: U32) -> Step:
  match state:
    case State{text, offset, depth, frames, mode}: step_mode(mode, text, offset, depth, frames, max_depth)

def step(state: State) -> Step:
  step_with(state, 64)

def run_with(fuel: Nat, result: Step, +max_depth: U32) -> Result<&2, &2, String, Value>:
  match fuel result:
    case _ Finished{value}: Done{value}
    case _ Rejected{message}: Fail{message}
    case 0n Continue{state}: Fail{"JSON work limit exceeded"}
    case 1n+f Continue{state}: run_with(f, step_with(state, max_depth), max_depth)

def run(fuel: Nat, result: Step) -> Result<&2, &2, String, Value>:
  run_with(fuel, result, 64)

def parse_size_checked(+text: String, max_codepoints: Nat, max_depth: U32, valid: Bool) -> Result<&2, &2, String, Value>:
  match valid:
    case False{}: Fail{"JSON input exceeds " ++ Nat.show(max_codepoints) ++ " code points"}
    case True{}:
      fuel = Nat.add(16n, Nat.mul(4n, String.length(text)))
      run_with(fuel, Continue{State{text, 0, 0, Nil{}, NeedValue{}}}, max_depth)

def parse_bounded(+text: String, +max_codepoints: Nat, max_depth: U32) -> Result<&2, &2, String, Value>:
  parse_size_checked(text, max_codepoints, max_depth, within(max_codepoints, text))

# Offset is U32. This tighter bound also keeps 4*length+16 below native Nat48.
# Match before counting/fuel construction: choose evaluates both arguments.
def parse_limits_checked(text: String, max_codepoints: Nat, max_depth: U32, supported: Bool) -> Result<&2, &2, String, Value>:
  match supported:
    case False{}: Fail{"JSON max_codepoints exceeds supported limit 4294967295"}
    case True{}: parse_bounded(text, max_codepoints, max_depth)

def parse_with(text: String, limits: Limits) -> Result<&2, &2, String, Value>:
  match limits:
    case Limits{+max_codepoints, max_depth}:
      parse_limits_checked(text, max_codepoints, max_depth, Nat.is_le(max_codepoints, 4294967295n))

def parse_checked(text: String, valid: Bool) -> Result<&2, &2, String, Value>:
  parse_size_checked(text, 16384n, 64, valid)

def parse(text: String) -> Result<&2, &2, String, Value>:
  parse_with(text, default_limits())

# Serialization is structural and unbounded; valid AST construction is a caller contract.
def hex_char(+n: U32) -> Char:
  choose(Char, Chr{U32.add(n, 48)}, Chr{U32.add(n, 87)}, U32.is_lt(n, 10))

def escape_char(+c: U32) -> String:
  match c:
    case 34: "\\\""
    case 92: "\\\\"
    case 8: "\\b"
    case 12: "\\f"
    case 10: "\\n"
    case 13: "\\r"
    case 9: "\\t"
    case _:
      choose(String, "\\u00" ++ Char.show(hex_char(U32.div(c, 16))) ++ Char.show(hex_char(U32.mod(c, 16))),
        Char.show(Chr{c}), U32.is_lt(c, 32))

def quote_body(text: String) -> String:
  match text:
    case SNil{}: "\""
    case SCon{h, t}: escape_char(Char.to_u32(h)) ++ quote_body(t)

def quote(text: String) -> String:
  "\"" ++ quote_body(text)

def encode_go(value: Value, continuation: Bool) -> String:
  match value:
    case JNull{}: "null"
    case JBool{True{}}: "true"
    case JBool{False{}}: "false"
    case JNumber{raw}: raw
    case JString{text}: quote(text)
    case JArray{Nil{}}: choose(String, "]", "[]", continuation)
    case JArray{h <> t}:
      choose(String, ",", "[", continuation) ++ encode_go(h, False{}) ++ encode_go(JArray{t}, True{})
    case JObject{Nil{}}: choose(String, "}", "{}", continuation)
    case JObject{JMember{k, v} <> t}:
      choose(String, ",", "{", continuation) ++ quote(k) ++ ":" ++ encode_go(v, False{}) ++ encode_go(JObject{t}, True{})

def encode(value: Value) -> String:
  encode_go(value, False{})

def member_go(members: List<&2, Member>, +key: String) -> Maybe<&2, Value>:
  match members:
    case Nil{}: None{}
    case JMember{k, v} <> t:
      choose(Maybe<&2, Value>, Some{v}, member_go(t, key), String.eq(k, key))

def member(value: Value, key: String) -> Maybe<&2, Value>:
  match value:
    case JObject{members}: member_go(members, key)
    case _: None{}

def as_string(value: Value) -> Maybe<&2, String>:
  match value:
    case JString{text}: Some{text}
    case _: None{}

# Decimal range guards prevent accepting a wrapped U32 accumulator.
def u32_digits(text: String, +acc: U32) -> Maybe<&2, U32>:
  match text:
    case SNil{}: Some{acc}
    case SCon{Chr{+c}, t}:
      +d = U32.sub(c, 48)
      choose(Maybe<&2, U32>, u32_digits(t, U32.add(U32.mul(acc, 10), d)), None{},
        digit(c) && (U32.is_lt(acc, 429496729) || (U32.is_eq(acc, 429496729) && U32.is_le(d, 5))))

def u32_lexeme(text: String) -> Maybe<&2, U32>:
  match text:
    case SNil{}: None{}
    case SCon{Chr{48}, SNil{}}: Some{0}
    case SCon{Chr{+c}, t}:
      choose(Maybe<&2, U32>, u32_digits(t, U32.sub(c, 48)), None{}, U32.is_ge(c, 49) && U32.is_le(c, 57))

def as_u32(value: Value) -> Maybe<&2, U32>:
  match value:
    case JNumber{raw}: u32_lexeme(raw)
    case _: None{}
