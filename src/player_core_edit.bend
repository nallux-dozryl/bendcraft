import Base
import ./core.bend as C
import ./schedule.bend as Q

# Additive player edit admission leaves the frozen core API untouched. The
# server assigns the capability; private wire clients cannot supply a peer.
type Error is Data:
  PermissionDenied{}
  InvalidSequence{}
  StaleRevision{expected:Nat,actual:Nat}
  CoreError{cause:C.Error}

def error_text(error:Error) -> String:
  match error:
    case PermissionDenied{}: "interaction:permission-denied"
    case InvalidSequence{}: "interaction:invalid-sequence"
    case StaleRevision{expected,actual}: "interaction:stale-revision"
    case CoreError{cause}: "interaction:invalid-core-edit"

def player_peer(cap:C.Capability) -> Maybe<&2,U32>:
  match cap:
    case C.Player{+peer}: Bool.pick(Maybe<&2,U32>,U32.is_gt(peer,0),Some{peer},None{})
    case _: None{}

def finished(stamp:Q.Stamp,result:C.World & Result<&2,&2,C.Error,Unit>) -> C.World & Result<&2,&2,Error,Unit>:
  (world,status) = result
  match status:
    case Fail{cause}: (world,Fail{CoreError{cause}})
    case Done{unit}: (C.accepted(world,stamp),Done{Unit{}})

def present(stamp:Q.Stamp,position:C.Position,state:U32,result:C.World & Result<&2,&2,C.Error,U32>) -> C.World & Result<&2,&2,Error,Unit>:
  (world,status) = result
  match status:
    case Fail{cause}: (world,Fail{CoreError{cause}})
    case Done{old}: finished(stamp,C.write_block(world,position,state))

def validated(world:C.World,stamp:Q.Stamp,+position:C.Position,state:U32,status:Result<&2,&2,C.Error,Unit>) -> C.World & Result<&2,&2,Error,Unit>:
  match status:
    case Fail{cause}: (world,Fail{CoreError{cause}})
    case Done{unit}: present(stamp,position,state,C.read_block(world,position))

def current(world:C.World,stamp:Q.Stamp,+position:C.Position,+state:U32,count:U32,expected:Nat,revision:Nat,positive:Bool,matching:Bool) -> C.World & Result<&2,&2,Error,Unit>:
  match positive matching:
    case False{} _: (world,Fail{InvalidSequence{}})
    case True{} False{}: (world,Fail{StaleRevision{expected,revision}})
    case True{} True{}: validated(world,stamp,position,state,C.validate(C.BlockSet{position,state},count))

def player_current(world:C.World,position:C.Position,state:U32,+expected:Nat,+sequence:Nat,peer:U32) -> C.World & Result<&2,&2,Error,Unit>:
  C.World{+tick,time,paused,daylight,+revision,+count,sections,pending,events} = world
  stamp : Q.Stamp = Q.Stamp{tick,peer,sequence}
  owner : C.World = C.World{tick,time,paused,daylight,revision,count,sections,pending,events}
  current(owner,stamp,position,state,count,expected,revision,Nat.is_gt(sequence,0n),Nat.is_eq(expected,revision))

def checked(world:C.World,position:C.Position,state:U32,expected:Nat,sequence:Nat,maybuild:Bool,peer:Maybe<&2,U32>) -> C.World & Result<&2,&2,Error,Unit>:
  match maybuild peer:
    case False{} _: (world,Fail{PermissionDenied{}})
    case True{} None{}: (world,Fail{PermissionDenied{}})
    case True{} Some{peer}: player_current(world,position,state,expected,sequence,peer)

def edit(world:C.World,cap:C.Capability,position:C.Position,state:U32,expected:Nat,sequence:Nat,maybuild:Bool) -> C.World & Result<&2,&2,Error,Unit>:
  checked(world,position,state,expected,sequence,maybuild,player_peer(cap))

law denied_permission_preserves_world:
  for world:C.World
  for position:C.Position
  for state:U32
  for expected:Nat
  for sequence:Nat
  for peer:Maybe<&2,U32>
  {checked(world,position,state,expected,sequence,False{},peer) == (world,Fail{PermissionDenied{}}) : C.World & Result<&2,&2,Error,Unit>}
def denied_permission_preserves_world(world,position,state,expected,sequence,peer):
  {==}
