import Base
import ./player_inventory.bend as I
import ./player_inventory_return.bend as Return
import ./player_inventory_close_laws.bend as L
import ./inventory.bend as Inv

def L.false_is_not_true(contradiction):
  %Equal.sym(Bool,False{},True{},contradiction) : L.truth_type(_)
  Unit{}

def L.conjunction_left_is_true(a,b,admitted):
  match a:
    case False{}: Empty.absurd({False{} == True{} : Bool},L.false_is_not_true(admitted))
    case True{}: {==}

def L.conjunction_right_is_true(a,b,admitted):
  match a b:
    case False{} _: Empty.absurd({b == True{} : Bool},L.false_is_not_true(admitted))
    case True{} _: admitted

def L.admitted_nat_is_equal(a,b,admitted):
  match a b:
    case 0n 0n: {==}
    case 0n 1n+n: Empty.absurd({0n == 1n+n : Nat},L.false_is_not_true(admitted))
    case 1n+n 0n: Empty.absurd({1n+n == 0n : Nat},L.false_is_not_true(admitted))
    case 1n+a 1n+b:
      %Equal.sym(Nat,a,b,L.admitted_nat_is_equal(a,b,admitted)) : {1n+_ == 1n+b : Nat}
      {==}

def L.admitted_complete_ledgers_are_equal(before,after,admitted):
  match before after:
    case Nil{} Nil{}: {==}
    case Nil{} b <> right: Empty.absurd({[] == b <> right : List<&2,Nat>},L.false_is_not_true(admitted))
    case a <> left Nil{}: Empty.absurd({a <> left == [] : List<&2,Nat>},L.false_is_not_true(admitted))
    case a <> left b <> right:
      %Equal.sym(Nat,a,b,L.admitted_nat_is_equal(a,b,L.conjunction_left_is_true(Nat.is_eq(a,b),Return.counts_equal(left,right),admitted))) : {(_ <> left) == (b <> right) : List<&2,Nat>}
      %Equal.sym(List<&2,Nat>,left,right,L.admitted_complete_ledgers_are_equal(left,right,L.conjunction_right_is_true(Nat.is_eq(a,b),Return.counts_equal(left,right),admitted))) : {(b <> _) == (b <> right) : List<&2,Nat>}
      {==}

def L.production_plan_admission_conserves_every_item_count(plan,admitted):
  match plan:
    case Return.Plan{slots,before,after,returned,valid}:
      L.admitted_complete_ledgers_are_equal(before,after,L.conjunction_right_is_true(Bool.and(returned,valid),Return.counts_equal(before,after),admitted))

def L.actual_production_return_preserves_complete_item_count_ledger(slots,selected,catalog,admitted):
  L.production_plan_admission_conserves_every_item_count(Return.plan(slots,selected,catalog),admitted)

def L.refused_actual_plan_retains_complete_owned_inventory(state,plan,refused):
  %Equal.sym(Bool,Return.admitted(plan),False{},refused) : {I.close_return_guard(_,state,Return.slots(plan)) == (state,Fail{"menu retains carried or crafting items; return/drop authority is required before closing"}) : I.State & Result<&2,&2,String,Unit>}
  {==}

def L.refused_return_retains_complete_owned_inventory(state,slots): {==}
def L.committed_return_retains_entire_noninventory_owner(inventory,selected,abilities,definitions,status,opened,revision,result): {==}
def L.closing_empty_menu_clears_only_derived_result_and_retains_owned_inventory(inventory,selected,abilities,definitions,status,opened,revision,cached): {==}

def L.complete_production_array_commit_and_backing_retention(new0,new1,new2,new3,new4,new5,new6,new7,new8,new9,new10,new11,new12,new13,new14,new15,new16,new17,new18,new19,new20,new21,new22,new23,new24,new25,new26,new27,new28,new29,new30,new31,new32,new33,new34,new35,new36,new37,new38,new39,new40,new41,new42,new43,new44,new45,new46,new47,old0,old1,old2,old3,old4,old5,old6,old7,old8,old9,old10,old11,old12,old13,old14,old15,old16,old17,old18,old19,old20,old21,old22,old23,old24,old25,old26,old27,old28,old29,old30,old31,old32,old33,old34,old35,old36,old37,old38,old39,old40,old41,old42,old43,old44,old45,old46,old47,old48,old49,old50,old51,old52,old53,old54,old55,old56,old57,old58,old59,old60,old61,old62,old63): {==}
