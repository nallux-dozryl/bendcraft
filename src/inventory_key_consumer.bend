import Base
import ./player_inventory_screen.bend as S
import ./png.bend as P

# AppKit physical key identities are separate from printable characters. The
# native adapter only records the unsigned16 hardware word; binding semantics
# and menu/search/world routing remain in Bend. This namespace cannot overlap
# Base character or sided-modifier codes.
type Profile is Data:
  Profile{hotbar:List<&2,Maybe<&2,U32>>,offhand:Maybe<&2,U32>,inventory:Maybe<&2,U32>,close:Maybe<&2,U32>}

def defaults() -> Profile:
  Profile{[Some{18},Some{19},Some{20},Some{21},Some{23},Some{22},Some{26},Some{28},Some{25}],Some{3},Some{14},Some{53}}

def key_valid(key:Maybe<&2,U32>) -> Bool:
  match key:
    case None{}: True{}
    case Some{value}: U32.is_lt(value,65536)

def keys_valid(keys:List<&2,Maybe<&2,U32>>) -> Bool:
  match keys:
    case Nil{}: True{}
    case head <> tail: key_valid(head) && keys_valid(tail)

def valid(profile:Profile) -> Bool:
  Profile{+hotbar,offhand,inventory,close} = profile
  Nat.is_eq(List.length(&2,Maybe<&2,U32>,hotbar),9n) && keys_valid(hotbar) &&
    key_valid(offhand) && key_valid(inventory) && key_valid(close)

def validate(+profile:Profile) -> Result<&2,&2,String,Profile>:
  P.choose(Result<&2,&2,String,Profile>,Done{profile},Fail{"inventory bindings require nine hotbar entries and unsigned16 AppKit key codes"},valid(profile))

def matches(key:Maybe<&2,U32>,code:U32) -> Bool:
  match key:
    case None{}: False{}
    case Some{bound}: U32.is_eq(bound,code)

def hotbar(keys:List<&2,Maybe<&2,U32>>,+code:U32,+index:U32) -> Maybe<&2,U32>:
  match keys:
    case Nil{}: None{}
    case head <> tail:
      P.choose(Maybe<&2,U32>,Some{U32.add(49,index)},hotbar(tail,code,U32.add(index,1)),matches(head,code))

# Inventory/Escape precede the inherited GUI hotbar check. That check tests
# offhand first, then hotbar0..8; duplicate bindings keep this deterministic
# priority rather than inventing independent simultaneous owned mutations.
def bound(profile:Profile,+code:U32) -> Maybe<&2,U32>:
  Profile{slots,offhand,inventory,close} = profile
  P.choose(Maybe<&2,U32>,Some{69},
    P.choose(Maybe<&2,U32>,Some{27},
      P.choose(Maybe<&2,U32>,Some{70},hotbar(slots,code,0),matches(offhand,code)),matches(close,code)),matches(inventory,code))

def physical(+code:U32) -> Bool:
  U32.is_ge(code,2147483648) && U32.is_lt(code,2147614720)

def physical_code(code:U32) -> U32: U32.mod(code,65536)

def marker(code:U32) -> U32: U32.add(code,2147483648)
def paired_marker(code:U32) -> U32: U32.add(code,2147549184)

def logical_follows(+code:U32) -> Bool:
  U32.is_ge(code,2147549184) && U32.is_lt(code,2147614720)

def consumes_character(bound:Maybe<&2,U32>,searching:Bool) -> Bool:
  match bound:
    case None{}: False{}
    case Some{code}: Bool.not(searching) || U32.is_eq(code,27)

def same(left:Bool,right:Bool) -> Bool:
  match left:
    case False{}: Bool.not(right)
    case True{}: right

def drop_paired_character(down:Bool,+pending:List<&2,Event>) -> List<&2,Event>:
  match pending:
    case Key{code,+next_down} <> +rest:
      P.choose(List<&2,Event>,rest,Key{code,next_down} <> rest,same(down,next_down))
    case _: pending

# The upper physical subrange states that the next queued Key is this native
# key's paired character. It is set only when the adapter actually enqueues that
# character; duplicate logical holds and batch release use the unpaired range.
def following(profile:Profile,state:S.State,input:Event,+pending:List<&2,Event>) -> List<&2,Event>:
  match input:
    case Key{+code,down}:
      P.choose(List<&2,Event>,drop_paired_character(down,pending),pending,
        logical_follows(code) && consumes_character(bound(profile,physical_code(code)),S.searching(state)))
    case _: pending

def shortcut(+code:U32) -> Bool:
  S.swap_code(code) || U32.is_eq(code,69) || U32.is_eq(code,101) || U32.is_eq(code,27)

def mapped(bound:Maybe<&2,U32>,+down:Bool,searching:Bool) -> Maybe<&2,Event>:
  match bound:
    case None{}: None{}
    case Some{+code}:
      P.choose(Maybe<&2,Event>,None{},Some{Key{code,down}},searching && down && U32.is_ne(code,27))

def keyboard(isphysical:Bool,profile:Profile,state:S.State,+code:U32,+down:Bool) -> Maybe<&2,Event>:
  match isphysical:
    case True{}: mapped(bound(profile,physical_code(code)),down,S.searching(state))
    case False{}:
      P.choose(Maybe<&2,Event>,None{},Some{Key{code,down}},
        shortcut(code) && (Bool.not(S.searching(state)) || U32.is_eq(code,27)))

def event(profile:Profile,state:S.State,input:Event) -> Maybe<&2,Event>:
  match input:
    case Key{+code,down}: keyboard(physical(code),profile,state,code,down)
    case _: Some{input}
