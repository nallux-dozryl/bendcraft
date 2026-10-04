import Base
import ./player_inventory_screen.bend as S
import ./player_inventory.bend as I
import ./player_inventory_screen_laws.bend as L
import ./inventory_proof.bend as TransferProof
import ./inventory_laws.bend as Transfer

def L.event_retains_full_authority(controller,snapshot,catalog,viewport,event,focused,captured): {==}
def L.reply_installs_full_authority(controller,previous,snapshot,catalog,accepted): {==}

def L.focus_loss_composes_without_changing_pending_or_authority(controller):
  match controller:
    case S.State{open,keys,buttons,captured,focused,source,offer,pending,tab,row,query,message,hover}: {==}

def L.unadmitted_observation_retains_entire_controller(controller,snapshot): {==}

def L.refused_close_retains_owned_inventory(state): {==}

def L.menu_open_close_changes_only_open_flag(state):
  match state:
    case I.State{inventory,selected,abilities,I.Profile{definitions,status,I.Menu{opened,revision,result}}}: {==}

def L.inventory_authority_refusal_retains_every_owned_slot(state,index,key,count):
  I.refused_acquisition_preserves_inventory(state,index,key,count)

def L.invalid_transfer_retains_every_owned_slot(state,source,destination,count,mode): {==}

def L.production_transfer_count_conservation(requested,source,destination,room):
  Transfer.count_conservation(requested,source,destination,room)
