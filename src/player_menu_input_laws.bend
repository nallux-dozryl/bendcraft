import Base
import ./player_menu_input.bend as M
import ./player_inventory_screen.bend as S
import ./player_inventory.bend as I
import ./player_item_definitions.bend as D

# These equations bind the actual production adapter and complete received DTO.
# Every owned/equipment/crafting/carried slot, ability, menu result/open/revision
# field and the verified full catalog is retained during local input processing.
law observation_installs_received_full_authority:
  for controller:S.State
  for previous:Maybe<&2,I.MenuSnapshot>
  for +catalog:D.Catalog
  for +snapshot:I.MenuSnapshot
  {M.authority(M.observed(M.State{controller,previous,catalog},snapshot)) == (Some{snapshot},catalog) : Maybe<&2,I.MenuSnapshot> & D.Catalog}

law synchronization_retains_full_authority:
  for +state:M.State
  for focused:Bool
  for captured:Bool
  {M.updated_authority(M.synchronize(state,focused,captured)) == M.authority(state) : Maybe<&2,I.MenuSnapshot> & D.Catalog}

law event_retains_full_authority:
  for event:Event
  for events:List<&2,Event>
  for intents:List<&2,S.Intent>
  for +state:M.State
  for viewport:S.Viewport
  for focused:Bool
  for captured:Bool
  {M.batch_authority(M.event(event,events,intents,state,viewport,focused,captured)) == M.authority(state) : Maybe<&2,I.MenuSnapshot> & D.Catalog}

law packet_retains_full_authority:
  for +state:M.State
  for events:List<Event>
  for viewport:S.Viewport
  for +focused:Bool
  for +captured:Bool
  {M.batch_authority(M.packet(state,events,viewport,focused,captured)) == M.authority(state) : Maybe<&2,I.MenuSnapshot> & D.Catalog}

# Completion uses the actual received snapshot even for a refused operation.
# Epoch/sequence/framing admission is the presenter's separate transport gate.
law completion_installs_received_full_authority:
  for controller:S.State
  for previous:Maybe<&2,I.MenuSnapshot>
  for +catalog:D.Catalog
  for +snapshot:I.MenuSnapshot
  for accepted:Bool
  {M.updated_authority(M.completed(M.State{controller,previous,catalog},snapshot,accepted)) == (Some{snapshot},catalog) : Maybe<&2,I.MenuSnapshot> & D.Catalog}
