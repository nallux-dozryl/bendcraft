import Base
import ./movement.bend as M
import ./player_block_inside_stuck.bend as P

# These are observations of the actual callback receiver. The known movement
# service can delegate to a controlling Player; it is not the swept displacement.
type ReceiverInput is Data:
  ReceiverInput{client_authoritative: Bool, known_movement: M.Vec3,
                old_position: M.Vec3, current_position: M.Vec3}

def server_level(input: ReceiverInput) -> P.Level:
  ReceiverInput{authority, known, old, current} = input
  P.ServerLevel{authority, known, old, current}

def damage_movement(input: ReceiverInput) -> M.Vec3:
  P.server_movement(server_level(input))

def damage_required(input: ReceiverInput) -> Bool:
  P.berry_damage_horizontal(damage_movement(input))
