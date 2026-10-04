import Base
import ./inventory.bend as Inv
import ./player_crafting_authority.bend as A
import ./player_crafting_authority_plan.bend as P
import ./player_crafting_authority_laws.bend as L
import ./player_inventory_return.bend as Return
import ./player_inventory_close_laws.bend as Close
import ./player_inventory_close_proof.bend as CloseProof

def OwnerShapeWitness(-depth:Nat,-slots:Array<Inv.Slot>) -> Type:
  Exists(Array<Inv.Slot> & Bool,result =>
    {A.shape(depth,slots) == result : Array<Inv.Slot> & Bool} &
    {L.shape_owner(result) == slots : Array<Inv.Slot>})

def shape_node_pair(-depth:Nat,-left:Array<Inv.Slot>,-right:Array<Inv.Slot>,
    first:Array<Inv.Slot> & Bool,second:Array<Inv.Slot> & Bool,
    first_evidence:{A.shape(depth,left) == first : Array<Inv.Slot> & Bool} & {L.shape_owner(first) == left : Array<Inv.Slot>},
    second_evidence:{A.shape(depth,right) == second : Array<Inv.Slot> & Bool} & {L.shape_owner(second) == right : Array<Inv.Slot>}) ->
    OwnerShapeWitness(1n+depth,ANode{left,right}):
  match first second first_evidence second_evidence:
    case Tuple{xs,+a} Tuple{ys,+b} Tuple{same_left,owned_left} Tuple{same_right,owned_right}:
      ((ANode{xs,ys},a && b),
        ((%Equal.sym(Array<Inv.Slot> & Bool,A.shape(depth,left),(xs,a),same_left) :
          {A.shape_pair(_,A.shape(depth,right)) == (ANode{xs,ys},a && b) : Array<Inv.Slot> & Bool}
        %Equal.sym(Array<Inv.Slot> & Bool,A.shape(depth,right),(ys,b),same_right) :
          {A.shape_pair((xs,a),_) == (ANode{xs,ys},a && b) : Array<Inv.Slot> & Bool}
        {==}),
        (%Equal.sym(Array<Inv.Slot>,xs,left,owned_left) :
          {ANode{_,ys} == ANode{left,right} : Array<Inv.Slot>}
        %Equal.sym(Array<Inv.Slot>,ys,right,owned_right) :
          {ANode{left,_} == ANode{left,right} : Array<Inv.Slot>}
        {==})))

def shape_node(-depth:Nat,-left:Array<Inv.Slot>,-right:Array<Inv.Slot>,
    first:OwnerShapeWitness(depth,left),second:OwnerShapeWitness(depth,right)) ->
    OwnerShapeWitness(1n+depth,ANode{left,right}):
  match first second:
    case Tuple{actual_left,evidence_left} Tuple{actual_right,evidence_right}:
      shape_node_pair(depth,left,right,actual_left,actual_right,evidence_left,evidence_right)

def shape_owned(+depth:Nat,slots:Array<Inv.Slot>) -> OwnerShapeWitness(depth,slots):
  match depth slots:
    case 0n ALeaf{value}: ((ALeaf{value},True{}),({==},{==}))
    case 0n ANode{left,right}: ((ANode{left,right},False{}),({==},{==}))
    case 1n+rest ALeaf{value}: ((ALeaf{value},False{}),({==},{==}))
    case 1n+rest ANode{left,right}: shape_node(rest,left,right,shape_owned(rest,left),shape_owned(rest,right))

def shape_project(-depth:Nat,-slots:Array<Inv.Slot>,result:OwnerShapeWitness(depth,slots)) ->
    {L.shape_owner(A.shape(depth,slots)) == slots : Array<Inv.Slot>}:
  match result:
    case Tuple{actual,Tuple{same,owned}}:
      %Equal.sym(Array<Inv.Slot> & Bool,A.shape(depth,slots),actual,same) :
        {L.shape_owner(_) == slots : Array<Inv.Slot>}
      owned

def L.geometry_shape_check_retains_complete_original_array(depth,slots):
  shape_project(depth,slots,shape_owned(depth,slots))

def OwnerSnapshotWitness(-slots:Array<Inv.Slot>) -> Type:
  Exists(Array<Inv.Slot> & List<&2,Inv.Slot>,result =>
    {A.array_snapshot(slots) == result : Array<Inv.Slot> & List<&2,Inv.Slot>} &
    {L.snapshot_owner(result) == slots : Array<Inv.Slot>})

def snapshot_node_pair(-left:Array<Inv.Slot>,-right:Array<Inv.Slot>,
    first:Array<Inv.Slot> & List<&2,Inv.Slot>,second:Array<Inv.Slot> & List<&2,Inv.Slot>,
    first_evidence:{A.array_snapshot(left) == first : Array<Inv.Slot> & List<&2,Inv.Slot>} & {L.snapshot_owner(first) == left : Array<Inv.Slot>},
    second_evidence:{A.array_snapshot(right) == second : Array<Inv.Slot> & List<&2,Inv.Slot>} & {L.snapshot_owner(second) == right : Array<Inv.Slot>}) ->
    OwnerSnapshotWitness(ANode{left,right}):
  match first second first_evidence second_evidence:
    case Tuple{xs,+a} Tuple{ys,+b} Tuple{same_left,owned_left} Tuple{same_right,owned_right}:
      ((ANode{xs,ys},List.append(&2,Inv.Slot,a,b)),
        ((%Equal.sym(Array<Inv.Slot> & List<&2,Inv.Slot>,A.array_snapshot(left),(xs,a),same_left) :
          {A.array_snapshot_pair(_,A.array_snapshot(right)) == (ANode{xs,ys},List.append(&2,Inv.Slot,a,b)) : Array<Inv.Slot> & List<&2,Inv.Slot>}
        %Equal.sym(Array<Inv.Slot> & List<&2,Inv.Slot>,A.array_snapshot(right),(ys,b),same_right) :
          {A.array_snapshot_pair((xs,a),_) == (ANode{xs,ys},List.append(&2,Inv.Slot,a,b)) : Array<Inv.Slot> & List<&2,Inv.Slot>}
        {==}),
        (%Equal.sym(Array<Inv.Slot>,xs,left,owned_left) :
          {ANode{_,ys} == ANode{left,right} : Array<Inv.Slot>}
        %Equal.sym(Array<Inv.Slot>,ys,right,owned_right) :
          {ANode{left,_} == ANode{left,right} : Array<Inv.Slot>}
        {==})))

def snapshot_node(-left:Array<Inv.Slot>,-right:Array<Inv.Slot>,first:OwnerSnapshotWitness(left),second:OwnerSnapshotWitness(right)) -> OwnerSnapshotWitness(ANode{left,right}):
  match first second:
    case Tuple{actual_left,evidence_left} Tuple{actual_right,evidence_right}:
      snapshot_node_pair(left,right,actual_left,actual_right,evidence_left,evidence_right)

def snapshot_owned(slots:Array<Inv.Slot>) -> OwnerSnapshotWitness(slots):
  match slots:
    case ALeaf{+value}: ((ALeaf{value},[value]),({==},{==}))
    case ANode{left,right}: snapshot_node(left,right,snapshot_owned(left),snapshot_owned(right))

def snapshot_project(-slots:Array<Inv.Slot>,result:OwnerSnapshotWitness(slots)) ->
    {L.snapshot_owner(A.array_snapshot(slots)) == slots : Array<Inv.Slot>}:
  match result:
    case Tuple{actual,Tuple{same,owned}}:
      %Equal.sym(Array<Inv.Slot> & List<&2,Inv.Slot>,A.array_snapshot(slots),actual,same) :
        {L.snapshot_owner(_) == slots : Array<Inv.Slot>}
      owned

def L.malformed_snapshot_walk_retains_complete_original_array(slots):
  snapshot_project(slots,snapshot_owned(slots))

def L.admitted_craft_preserves_complete_transformation_ledger(transaction,admitted):
  match transaction:
    case P.Transaction{slots,grid,taken,before,after,consumed,produced,valid,message}:
      Close.admitted_complete_ledgers_are_equal(P.vector_add(before,produced),P.vector_add(after,consumed),
        Close.conjunction_right_is_true(valid,Return.counts_equal(P.vector_add(before,produced),P.vector_add(after,consumed)),admitted))

def L.actual_crafting_plan_preserves_complete_transformation_ledger(slots,grid,recipe,selected,catalog,button,admitted):
  L.admitted_craft_preserves_complete_transformation_ledger(P.plan(slots,grid,recipe,selected,catalog,button),admitted)

def L.refused_craft_retains_entire_player_bench_catalog_and_cache(state,transaction,refused):
  %Equal.sym(Bool,P.admitted(transaction),False{},refused) : {A.take_guard(_,state,transaction) == (state,Fail{P.message(transaction)}) : A.State & Result<&2,&2,String,Inv.Slot>}
  {==}

def L.stale_plan_retains_entire_crafting_authority(state,snapshot,grid,plan,button): {==}
def L.absent_plan_retains_entire_crafting_authority(state,snapshot,grid,button): {==}
def L.closed_menu_or_invalid_button_retains_entire_crafting_authority(state,snapshot,grid,cache,button): {==}
def L.changed_recipe_retains_entire_crafting_authority(state,snapshot,grid,plan,button): {==}
def L.empty_result_refuses_before_owned_mutation(state,slots,grid,steps,selected,catalog,button): {==}
def L.missing_component_admission_refuses_before_owned_mutation(state,slots,grid,key,count,steps,selected,catalog,button): {==}
def L.refused_refresh_retains_entire_authority_and_previous_result(state,message): {==}
def L.craft_commit_preserves_all_noninventory_player_fields(inventory,selected,abilities,definitions,status,opened,revision,result,slots): {==}

def L.actual_typed_crafting_plan_preserves_complete_transformation_ledger(slots,grid,recipe,selected,catalog,button,mode,admitted):
  L.admitted_craft_preserves_complete_transformation_ledger(P.plan_with(slots,grid,recipe,selected,catalog,button,mode),admitted)
def L.default_only_refuses_all_nonempty_component_keys(catalog,key): {==}
def L.absent_initialized_component_definition_refuses(key): {==}
def L.complete_bench_commit_retains_seven_nonlogical_backing_cells(new0,new1,new2,new3,new4,new5,new6,new7,new8,old0,old1,old2,old3,old4,old5,old6,old7,old8,old9,old10,old11,old12,old13,old14,old15): {==}

def L.malformed_owner_take_retains_entire_authority(state,button): {==}
def L.malformed_owner_refresh_retains_entire_authority(state): {==}
