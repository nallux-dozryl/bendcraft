import Base
import ./item_component.bend as C
import ./json.bend as J

# Exactly the observed numeric lexemes in the initialized default profile.
type Observed is Data:
  RepairCost{}
  StackSize{}
  Nutrition{}
  Saturation{}
def observed(value:Observed) -> String:
  match value:
    case RepairCost{}: "0"
    case StackSize{}: "1"
    case Nutrition{}: "6"
    case Saturation{}: "7.2000003"

law every_observed_initial_numeric_lexeme_is_admitted:
  for value:Observed
  {C.initial_number_valid(observed(value)) == True{} : Bool}
def every_observed_initial_numeric_lexeme_is_admitted(value):
  match value:
    case RepairCost{}: {==}
    case StackSize{}: {==}
    case Nutrition{}: {==}
    case Saturation{}: {==}

law every_other_initial_numeric_lexeme_is_refused:
  for +raw:String
  for zero:{String.eq(raw,"0") == False{} : Bool}
  for one:{String.eq(raw,"1") == False{} : Bool}
  for six:{String.eq(raw,"6") == False{} : Bool}
  for saturation:{String.eq(raw,"7.2000003") == False{} : Bool}
  {C.initial_number_valid(raw) == False{} : Bool}
def every_other_initial_numeric_lexeme_is_refused(raw,zero,one,six,saturation):
  %Equal.sym(Bool,String.eq(raw,"0"),False{},zero) :
    {_ || (String.eq(raw,"1") || (String.eq(raw,"6") || String.eq(raw,"7.2000003"))) == False{} : Bool}
  %Equal.sym(Bool,String.eq(raw,"1"),False{},one) :
    {_ || (String.eq(raw,"6") || String.eq(raw,"7.2000003")) == False{} : Bool}
  %Equal.sym(Bool,String.eq(raw,"6"),False{},six) :
    {_ || String.eq(raw,"7.2000003") == False{} : Bool}
  %Equal.sym(Bool,String.eq(raw,"7.2000003"),False{},saturation) :
    {_ == False{} : Bool}
  {==}

law refused_numeric_text_stops_the_actual_ast_guard_before_any_suffix:
  for +raw:String
  for fuel:Nat
  for tail:List<&2,J.Value>
  for rejected:{C.initial_number_valid(raw) == False{} : Bool}
  {C.initial_values_valid(1n+fuel,J.JNumber{raw} <> tail) == False{} : Bool}
def refused_numeric_text_stops_the_actual_ast_guard_before_any_suffix(raw,fuel,tail,rejected):
  %Equal.sym(Bool,C.initial_number_valid(raw),False{},rejected) :
    {_ && C.initial_values_valid(fuel,tail) == False{} : Bool}
  {==}
