import Base
import ./json.bend as J

# Resource JSON. Error offsets count Bend input characters, starting at zero.
# The public tree is J.Value. This parser targets the measured 26.3 production
# GsonHelper STRICT reader, which consumes one root without an EOF check.
def default_limits() -> J.Limits:
  J.Limits{1048576n, 255}

type Frame is Data:
  ArrayFrame{values: List<&2, J.Value>}
  ObjectFrame{members: List<&2, J.Member>, key: String, seen: Map<&2, Unit>, duplicate: Bool}

type Target is Data:
  StringTarget{}
  KeyTarget{members: List<&2, J.Member>, seen: Map<&2, Unit>}

type Escape is Data:
  Plain{}
  Slash{}
  Hex{left: U32, code: U32}

type Mode is Data:
  NeedValue{}
  ArrayWant{values: List<&2, J.Value>, allow_end: Bool}
  ArrayAfter{values: List<&2, J.Value>}
  ObjectWant{members: List<&2, J.Member>, seen: Map<&2, Unit>, allow_end: Bool}
  ColonWant{members: List<&2, J.Member>, seen: Map<&2, Unit>, key: String, duplicate: Bool}
  ObjectAfter{members: List<&2, J.Member>, seen: Map<&2, Unit>}
  StringRead{reversed: String, escape: Escape, target: Target}
  NumberRead{reversed: String, state: U32, size: U32}
  WordRead{remaining: String, value: J.Value}
  Produced{value: J.Value}
  Complete{value: J.Value}

type State is Data:
  State{text: String, offset: U32, depth: U32, frames: List<&2, Frame>, mode: Mode}

type Step is Data:
  Continue{state: State}
  Finished{value: J.Value}
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
    case 110: advance(text, offset, depth, frames, WordRead{"ull", J.JNull{}})
    case 116: advance(text, offset, depth, frames, WordRead{"rue", J.JBool{True{}}})
    case 102: advance(text, offset, depth, frames, WordRead{"alse", J.JBool{False{}}})
    case _:
      choose(Step, advance(text, offset, depth, frames,
        NumberRead{Char.show(Chr{c}), initial_number(c), 1}),
        error(offset, "expected JSON value"), U32.is_eq(c, 45) || digit(c))

def array_want(+c: U32, +text: String, +offset: U32, +depth: U32, +frames: List<&2, Frame>, +values: List<&2, J.Value>, allow_end: Bool) -> Step:
  match c:
    case 93:
      choose(Step, advance(text, offset, U32.sub(depth, 1), frames,
        Produced{J.JArray{List.reverse(&2, J.Value, values)}}), error(offset, "trailing array comma"), allow_end)
    case _:
      choose(Step, advance(text, offset, depth, frames, ArrayWant{values, allow_end}),
        stay(SCon{Chr{c}, text}, offset, depth, ArrayFrame{values} <> frames, NeedValue{}), whitespace(c))

def array_after(+c: U32, +text: String, +offset: U32, +depth: U32, +frames: List<&2, Frame>, +values: List<&2, J.Value>) -> Step:
  match c:
    case 93: advance(text, offset, U32.sub(depth, 1), frames, Produced{J.JArray{List.reverse(&2, J.Value, values)}})
    case 44: advance(text, offset, depth, frames, ArrayWant{values, False{}})
    case _:
      choose(Step, advance(text, offset, depth, frames, ArrayAfter{values}),
        error(offset, "expected array comma or closing bracket"), whitespace(c))

def object_want(+c: U32, +text: String, +offset: U32, +depth: U32, +frames: List<&2, Frame>, +members: List<&2, J.Member>, +seen: Map<&2, Unit>, allow_end: Bool) -> Step:
  match c:
    case 125:
      choose(Step, advance(text, offset, U32.sub(depth, 1), frames,
        Produced{J.JObject{List.reverse(&2, J.Member, members)}}), error(offset, "trailing object comma"), allow_end)
    case 34: advance(text, offset, depth, frames, StringRead{SNil{}, Plain{}, KeyTarget{members, seen}})
    case _:
      choose(Step, advance(text, offset, depth, frames, ObjectWant{members, seen, allow_end}),
        error(offset, "expected object member name"), whitespace(c))

def colon_want(+c: U32, +text: String, +offset: U32, +depth: U32, +frames: List<&2, Frame>, +members: List<&2, J.Member>, +seen: Map<&2, Unit>, +key: String, +duplicate: Bool) -> Step:
  match c:
    case 58: advance(text, offset, depth, ObjectFrame{members, key, seen, duplicate} <> frames, NeedValue{})
    case _:
      choose(Step, advance(text, offset, depth, frames, ColonWant{members, seen, key, duplicate}),
        error(offset, "expected member colon"), whitespace(c))

def object_after(+c: U32, +text: String, +offset: U32, +depth: U32, +frames: List<&2, Frame>, +members: List<&2, J.Member>, +seen: Map<&2, Unit>) -> Step:
  match c:
    case 125: advance(text, offset, U32.sub(depth, 1), frames, Produced{J.JObject{List.reverse(&2, J.Member, members)}})
    case 44: advance(text, offset, depth, frames, ObjectWant{members, seen, False{}})
    case _:
      choose(Step, advance(text, offset, depth, frames, ObjectAfter{members, seen}),
        error(offset, "expected object comma or closing brace"), whitespace(c))

def key_finish(text: String, offset: U32, depth: U32, frames: List<&2, Frame>, members: List<&2, J.Member>, +key: String, lookup: Map<&2, Unit> & Bool) -> Step:
  (seen, duplicate) = lookup
  advance(text, offset, depth, frames, ColonWant{members, Map.set(&2, Unit, seen, key, Unit{}), key, duplicate})

# Java strings are UTF-16 sequences. Valid adjacent surrogate pairs project to
# one Bend scalar; lone surrogate units remain Chr{unit}, without replacement.
def high_surrogate(+c: U32) -> Bool:
  U32.is_ge(c, 55296) && U32.is_le(c, 56319)

def low_surrogate(+c: U32) -> Bool:
  U32.is_ge(c, 56320) && U32.is_le(c, 57343)

type Normalized is Data:
  Normalized{pending: Maybe<&2, U32>, reversed: String}

def normalize_pair(+c: U32, +high: U32, +reversed: String, paired: Bool) -> Normalized:
  match paired:
    case True{}:
      combined = U32.add(65536, U32.add(U32.mul(U32.sub(high, 55296), 1024), U32.sub(c, 56320)))
      Normalized{None{}, SCon{Chr{combined}, reversed}}
    case False{}:
      Normalized{choose(Maybe<&2, U32>, Some{c}, None{}, high_surrogate(c)),
        choose(String, SCon{Chr{high}, reversed}, SCon{Chr{c}, SCon{Chr{high}, reversed}}, high_surrogate(c))}

def normalize_char(pending: Maybe<&2, U32>, +c: U32, +reversed: String) -> Normalized:
  match pending:
    case None{}:
      Normalized{choose(Maybe<&2, U32>, Some{c}, None{}, high_surrogate(c)),
        choose(String, reversed, SCon{Chr{c}, reversed}, high_surrogate(c))}
    case Some{high}: normalize_pair(c, high, reversed, low_surrogate(c))

def normalize_end(pending: Maybe<&2, U32>, reversed: String) -> String:
  match pending:
    case None{}: String.reverse(reversed)
    case Some{high}: String.reverse(SCon{Chr{high}, reversed})

def normalize_pending(value: Normalized) -> Maybe<&2, U32>:
  match value:
    case Normalized{pending, reversed}: pending

def normalize_reversed(value: Normalized) -> String:
  match value:
    case Normalized{pending, reversed}: reversed

def normalize_go(text: String, pending: Maybe<&2, U32>, reversed: String) -> String:
  match text:
    case SNil{}: normalize_end(pending, reversed)
    case SCon{Chr{c}, rest}:
      +next = normalize_char(pending, c, reversed)
      normalize_go(rest, normalize_pending(next), normalize_reversed(next))

def normalize_utf16(text: String) -> String:
  normalize_go(text, None{}, SNil{})

def string_finish(target: Target, reversed: String, text: String, offset: U32, depth: U32, frames: List<&2, Frame>) -> Step:
  match target:
    case StringTarget{}:
      advance(text, offset, depth, frames, Produced{J.JString{normalize_utf16(String.reverse(reversed))}})
    case KeyTarget{members, seen}:
      +key = normalize_utf16(String.reverse(reversed))
      key_finish(text, offset, depth, frames, members, key, Map.has(&2, Unit, seen, key))

def hex_digit(+c: U32) -> Maybe<&2, U32>:
  choose(Maybe<&2, U32>, Some{U32.sub(c, 48)},
    choose(Maybe<&2, U32>, Some{U32.sub(c, 55)},
      choose(Maybe<&2, U32>, Some{U32.sub(c, 87)}, None{},
        U32.is_ge(c, 97) && U32.is_le(c, 102)),
      U32.is_ge(c, 65) && U32.is_le(c, 70)), digit(c))

def hex_read(found: Maybe<&2, U32>, +left: U32, +code: U32, +text: String, +offset: U32, +depth: U32, +frames: List<&2, Frame>, +reversed: String, +target: Target) -> Step:
  match found:
    case None{}: error(offset, "invalid Unicode escape digit")
    case Some{value}:
      +next = U32.add(U32.mul(code, 16), value)
      choose(Step, advance(text, offset, depth, frames, StringRead{SCon{Chr{next}, reversed}, Plain{}, target}),
        advance(text, offset, depth, frames, StringRead{reversed, Hex{U32.sub(left, 1), next}, target}), U32.is_eq(left, 1))

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
    case 117: advance(text, offset, depth, frames, StringRead{reversed, Hex{4, 0}, target})
    case _: error(offset, "invalid string escape")

def string_char(escape: Escape, +c: U32, +text: String, +offset: U32, +depth: U32, +frames: List<&2, Frame>, +reversed: String, +target: Target) -> Step:
  match escape:
    case Plain{}:
      match c:
        case 34: string_finish(target, reversed, text, offset, depth, frames)
        case 92: advance(text, offset, depth, frames, StringRead{reversed, Slash{}, target})
        case _:
          choose(Step, advance(text, offset, depth, frames, StringRead{SCon{Chr{c}, reversed}, Plain{}, target}),
            error(offset, "invalid unescaped string character"), U32.is_ge(c, 32) && U32.is_le(c, 1114111))
    case Slash{}: escaped(c, text, offset, depth, frames, reversed, target)
    case Hex{left, code}: hex_read(hex_digit(c), left, code, text, offset, depth, frames, reversed, target)

# Token terminators were measured directly for all ASCII characters. Form-feed
# terminates a number/keyword, but is not accepted as leading/interior whitespace.
def token_end(+c: U32) -> Bool:
  whitespace(c) || U32.is_eq(c, 12) || U32.is_eq(c, 44) || U32.is_eq(c, 58) ||
  U32.is_eq(c, 91) || U32.is_eq(c, 93) || U32.is_eq(c, 123) || U32.is_eq(c, 125)

# Number states: 0 minus; 1 zero; 2 integer; 3 decimal point; 4 fraction;
# 5 exponent marker; 6 exponent sign; 7 exponent digits.
def number_finish(+state: U32, +reversed: String, +text: String, +offset: U32, +depth: U32, +frames: List<&2, Frame>) -> Step:
  choose(Step, stay(text, offset, depth, frames, Produced{J.JNumber{String.reverse(reversed)}}),
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

def number_char(next: Maybe<&2, U32>, state: U32, +c: U32, +text: String, +offset: U32, +depth: U32, +frames: List<&2, Frame>, +reversed: String, +size: U32) -> Step:
  match next:
    case Some{n}:
      choose(Step, advance(text, offset, depth, frames, NumberRead{SCon{Chr{c}, reversed}, n, U32.inc(size)}),
        error(offset, "numeric token exceeds measured 1023-unit limit"), U32.is_lt(size, 1023))
    case None{}:
      choose(Step, number_finish(state, reversed, SCon{Chr{c}, text}, offset, depth, frames),
        error(offset, "invalid number token"), token_end(c))

# Update an existing key in place. Newly encountered keys use the map above,
# avoiding a linear scan except for an actual duplicate replacement.
def replace_member(members: List<&2, J.Member>, +key: String, +value: J.Value) -> List<&2, J.Member>:
  match members:
    case Nil{}: Nil{}
    case J.JMember{+existing, +old} <> +rest:
      choose(List<&2, J.Member>, J.JMember{existing, value} <> rest,
        J.JMember{existing, old} <> replace_member(rest, key, value), String.eq(existing, key))

def object_value(members: List<&2, J.Member>, +key: String, +value: J.Value, duplicate: Bool) -> List<&2, J.Member>:
  match duplicate:
    case True{}: replace_member(members, key, value)
    case False{}: J.JMember{key, value} <> members

def produced(frames: List<&2, Frame>, text: String, offset: U32, depth: U32, value: J.Value) -> Step:
  match frames:
    case Nil{}: stay(text, offset, depth, Nil{}, Complete{value})
    case ArrayFrame{values} <> rest: stay(text, offset, depth, rest, ArrayAfter{value <> values})
    case ObjectFrame{members, key, seen, duplicate} <> rest:
      stay(text, offset, depth, rest, ObjectAfter{object_value(members, key, value, duplicate), seen})

def step_mode(mode: Mode, +text: String, +offset: U32, +depth: U32, +frames: List<&2, Frame>, max_depth: U32) -> Step:
  match mode:
    case Produced{value}: produced(frames, text, offset, depth, value)
    case WordRead{remaining, value}:
      match remaining text:
        case SNil{} SNil{}: stay(text, offset, depth, frames, Produced{value})
        case SNil{} SCon{h, t}:
          choose(Step, stay(SCon{h, t}, offset, depth, frames, Produced{value}),
            error(offset, "invalid literal token"), token_end(Char.to_u32(h)))
        case SCon{wanted, suffix} SCon{h, t}:
          choose(Step, advance(t, offset, depth, frames, WordRead{suffix, value}),
            error(offset, "invalid literal"), Char.is_eq(wanted, h))
        case _ SNil{}: error(offset, "incomplete literal")
    case Complete{value}: Finished{value}
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
    case ColonWant{members, seen, key, duplicate}:
      match text:
        case SNil{}: error(offset, "expected member colon")
        case SCon{h, t}: colon_want(Char.to_u32(h), t, offset, depth, frames, members, seen, key, duplicate)
    case ObjectAfter{members, seen}:
      match text:
        case SNil{}: error(offset, "unclosed object")
        case SCon{h, t}: object_after(Char.to_u32(h), t, offset, depth, frames, members, seen)
    case StringRead{reversed, escape, target}:
      match text:
        case SNil{}: error(offset, "unterminated string or escape")
        case SCon{h, t}: string_char(escape, Char.to_u32(h), t, offset, depth, frames, reversed, target)
    case NumberRead{reversed, +state, size}:
      match text:
        case SNil{}: number_finish(state, reversed, SNil{}, offset, depth, frames)
        case SCon{+h, t}: number_char(number_next(state, Char.to_u32(h)), state, Char.to_u32(h), t, offset, depth, frames, reversed, size)

def step_with(state: State, max_depth: U32) -> Step:
  match state:
    case State{text, offset, depth, frames, mode}: step_mode(mode, text, offset, depth, frames, max_depth)

def run_with(fuel: Nat, result: Step, +max_depth: U32) -> Result<&2, &2, String, J.Value>:
  match fuel result:
    case _ Finished{value}: Done{value}
    case _ Rejected{message}: Fail{message}
    case 0n Continue{state}: Fail{"Resource JSON work limit exceeded"}
    case 1n+f Continue{state}: run_with(f, step_with(state, max_depth), max_depth)

def initial_state(text: String) -> State:
  match text:
    case SNil{}: State{SNil{}, 0, 0, Nil{}, NeedValue{}}
    case SCon{Chr{65279}, rest}: State{rest, 1, 0, Nil{}, NeedValue{}}
    case SCon{h, rest}: State{SCon{h, rest}, 0, 0, Nil{}, NeedValue{}}

def parse_size_checked(+text: String, max_codepoints: Nat, max_depth: U32, valid: Bool) -> Result<&2, &2, String, J.Value>:
  match valid:
    case False{}: Fail{"Resource JSON input exceeds " ++ Nat.show(max_codepoints) ++ " code points"}
    case True{}:
      fuel = Nat.add(16n, Nat.mul(4n, String.length(text)))
      run_with(fuel, Continue{initial_state(text)}, max_depth)

def parse_bounded(+text: String, +max_codepoints: Nat, max_depth: U32) -> Result<&2, &2, String, J.Value>:
  parse_size_checked(text, max_codepoints, max_depth, within(max_codepoints, text))

# Offset is U32. This tighter bound also keeps 4*length+16 below native Nat48.
# Match before counting/fuel construction: choose evaluates both arguments.
def parse_limits_checked(text: String, max_codepoints: Nat, max_depth: U32, supported: Bool) -> Result<&2, &2, String, J.Value>:
  match supported:
    case False{}: Fail{"Resource JSON max_codepoints exceeds supported limit 4294967295"}
    case True{}: parse_bounded(text, max_codepoints, max_depth)

def parse_with(text: String, limits: J.Limits) -> Result<&2, &2, String, J.Value>:
  match limits:
    case J.Limits{+max_codepoints, +max_depth}:
      parse_limits_checked(text, max_codepoints, U32.min(max_depth, 255), Nat.is_le(max_codepoints, 4294967295n))

def parse(text: String) -> Result<&2, &2, String, J.Value>:
  parse_with(text, default_limits())

