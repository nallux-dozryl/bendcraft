import Base
import ./player_hud.bend as H
import ./player_presentation.bend as P
import ./client_controls.bend as C
import ./resource_client_wire.bend as W

law and_false_right:
  for value:Bool
  {(value && False{}) == False{} : Bool}

law inactive_event:
  for event:Event
  {H.command(event,False{}) == None{} : Maybe<&2,W.Command>}

law unfocused_batch:
  for actions:List<&2,C.Action>
  for +active:Bool
  {H.commands(actions,active,False{}) == [] : List<&2,W.Command>}

law focus_loss_suppresses_entire_packet:
  for actions:List<&2,C.Action>
  for captured:Bool
  for previous:Bool
  {H.packet_commands(C.Packet{actions,False{},captured},previous) == [] : List<&2,W.Command>}

law capture_loss_suppresses_entire_packet:
  for +actions:List<&2,C.Action>
  for +focused:Bool
  for +previous:Bool
  {H.packet_commands(C.Packet{actions,focused,False{}},previous) == [] : List<&2,W.Command>}

law capture_click_is_consumed:
  for x:U32
  for y:U32
  {H.packet_commands(C.Packet{[C.PlatformEvent{Mouse{x,y,0,True{}},True{}}],True{},True{}},False{}) == [] : List<&2,W.Command>}

# This is the real sparse compositor's recursive gate. Its caller uses exactly
# native_touched at each child; no world pixel is changed in an excluded branch.
law untouched_world_subtree:
  for +fuel:Nat
  for +image:Image
  for +view:H.View
  for +layout:H.Layout
  for +viewport:P.Viewport
  for +x:U32
  for +y:U32
  for +side:U32
  for outside:{H.native_touched(layout,viewport,x,y,side) == False{} : Bool}
  {H.native_overlay(fuel,image,view,layout,viewport,x,y,side,H.native_touched(layout,viewport,x,y,side)) == image : Image}

law matching_scene_projection_identity:
  for +image:Image
  for width:U32
  for height:U32
  for output_width:U32
  for output_height:U32
  {H.project_matching(image,width,height,output_width,output_height,True{}) == image : Image}

law invisible_projection_padding:
  for draw:Unit -> Image
  {H.projection_admit(False{},draw) == Pix{0} : Image}
