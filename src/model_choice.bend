import Base
import ./blockstate_model.bend as B
import ./random.bend as R

# Selection only: geometry, state predicates, exceptional block seed policy and
# nondeterministic source creation belong to the caller.
type Error is Data:
  InvalidChoice{error:B.Error}
  RandomFailure{error:R.RandomError}
type Selected is Data:
  Selected{part_index:Maybe<&2,U32>,variant:B.Variant}
type Selection is Data:
  Selection{parts:List<&2,Selected>,multipart_seed:Maybe<&2,R.Bits64>}
type ChoiceOutput is Data:
  ChoiceOutput{source:R.Source,variant:B.Variant}
type PartsOutput is Data:
  PartsOutput{source:R.Source,parts:List<&2,Selected>}
type Output is Data:
  Output{source:R.Source,selection:Selection}

def validated_choice(result:Result<&2,&2,B.Error,B.Variant>) -> Result<&2,&2,Error,Unit>:
  match result:
    case Done{v}: Done{Unit{}}
    case Fail{e}: Fail{InvalidChoice{e}}

def validate_choice(+choice:B.Choice) -> Result<&2,&2,Error,Unit>:
  validated_choice(B.choose(choice,0))

def validate_parts(+parts:List<&2,B.SelectedPart>) -> Result<&2,&2,Error,Unit>:
  match parts:
    case Nil{}: Done{Unit{}}
    case B.SelectedPart{index,choice} <> rest:
      do Result<&2,&2,Error,Unit>:
        valid:Unit <- validate_choice(choice)
        validate_parts(rest)

def validate_root(+root:B.Root) -> Result<&2,&2,Error,Unit>:
  match root:
    case B.VariantRoot{choice}: validate_choice(choice)
    case B.MultipartRoot{parts,names}: validate_parts(parts)

def selected_variant(source:R.Source,result:Result<&2,&2,B.Error,B.Variant>)
  -> Result<&2,&2,Error,ChoiceOutput>:
  match result:
    case Done{variant}: Done{ChoiceOutput{source,variant}}
    case Fail{error}: Fail{InvalidChoice{error}}

def selected_ticket(source:R.Source,+choice:B.Choice,ticket:Result<&2,&2,R.RandomError,U32>)
  -> Result<&2,&2,Error,ChoiceOutput>:
  match ticket:
    case Fail{error}: Fail{RandomFailure{error}}
    case Done{word}: selected_variant(source,B.choose(choice,word))

def weighted_result(+choice:B.Choice,result:R.Source & Result<&2,&2,R.RandomError,U32>)
  -> Result<&2,&2,Error,ChoiceOutput>:
  match result:
    case (source,ticket): selected_ticket(source,choice,ticket)

def select_choice(+choice:B.Choice,source:R.Source,+fuel:Nat)
  -> Result<&2,&2,Error,ChoiceOutput>:
  match choice:
    case B.Single{variant}: Done{ChoiceOutput{source,variant}}
    case B.WeightedChoice{+entries,+total}:
      weighted_result(B.WeightedChoice{entries,total},R.next_bounded(fuel,source,total))

def choice_source(value:ChoiceOutput) -> R.Source:
  match value:
    case ChoiceOutput{source,variant}: source
def choice_variant(value:ChoiceOutput) -> B.Variant:
  match value:
    case ChoiceOutput{source,variant}: variant
def parts_source(value:PartsOutput) -> R.Source:
  match value:
    case PartsOutput{source,parts}: source
def parts_values(value:PartsOutput) -> List<&2,Selected>:
  match value:
    case PartsOutput{source,parts}: parts

def select_parts(+parts:List<&2,B.SelectedPart>,source:R.Source,+seed:R.Bits64,+fuel:Nat)
  -> Result<&2,&2,Error,PartsOutput>:
  match parts:
    case Nil{}: Done{PartsOutput{source,Nil{}}}
    case B.SelectedPart{index,choice} <> rest:
      do Result<&2,&2,Error,PartsOutput>:
        +head:ChoiceOutput <- select_choice(choice,R.reseed(source,seed),fuel)
        +tail:PartsOutput <- select_parts(rest,choice_source(head),seed,fuel)
        Done{PartsOutput{parts_source(tail),Selected{Some{index},choice_variant(head)} <> parts_values(tail)}}

def multipart_result(+parts:List<&2,B.SelectedPart>,+fuel:Nat,pair:R.Source & R.Bits64)
  -> Result<&2,&2,Error,Output>:
  match pair:
    case (source,+seed):
      do Result<&2,&2,Error,Output>:
        +output:PartsOutput <- select_parts(parts,source,seed,fuel)
        Done{Output{parts_source(output),Selection{parts_values(output),Some{seed}}}}

def select_valid(+root:B.Root,source:R.Source,+fuel:Nat)
  -> Result<&2,&2,Error,Output>:
  match root:
    case B.VariantRoot{choice}:
      do Result<&2,&2,Error,Output>:
        +output:ChoiceOutput <- select_choice(choice,source,fuel)
        Done{Output{choice_source(output),Selection{Selected{None{},choice_variant(output)} <> Nil{},None{}}}}
    case B.MultipartRoot{parts,names}: multipart_result(parts,fuel,R.next_long(source))

def select_checked(+root:B.Root,source:R.Source,+fuel:Nat,checked:Result<&2,&2,Error,Unit>)
  -> Result<&2,&2,Error,Output>:
  match checked:
    case Fail{error}: Fail{error}
    case Done{valid}: select_valid(root,source,fuel)

def commit(original:R.Source,result:Result<&2,&2,Error,Output>)
  -> R.Source & Result<&2,&2,Error,Selection>:
  match result:
    case Fail{error}: (original,Fail{error})
    case Done{Output{source,value}}: (source,Done{value})

# Fuel is a per-choice rejection limit. Every failure atomically rolls back the
# original caller source; Java itself has no finite rejection/rollback policy.
def select(+root:B.Root,+source:R.Source,+fuel:Nat)
  -> R.Source & Result<&2,&2,Error,Selection>:
  commit(source,select_checked(root,source,fuel,validate_root(root)))

# The production renderer reseeds its source from an explicit caller long.
# On failure, including after the reseed, return the pre-call source.
def select_seeded(+root:B.Root,+source:R.Source,seed:R.Bits64,+fuel:Nat)
  -> R.Source & Result<&2,&2,Error,Selection>:
  commit(source,select_checked(root,R.reseed(source,seed),fuel,validate_root(root)))

# Exact Mth.getSeed(x,y,z) default. BlockState.getSeed delegates to its block and
# bed/door/double-plant overrides exist; this is not a universal state seed.
def default_position_seed(x:U32,y:U32,z:U32) -> R.Bits64:
  R.position_seed(x,y,z)

law commit_failure_preserves_source:
  for source:R.Source
  for error:Error
  {commit(source,Fail{error}) == (source,Fail{error}) : R.Source & Result<&2,&2,Error,Selection>}
def commit_failure_preserves_source(source,error):
  {==}
