import Base
import ./player_presentation_input_laws.bend as L
import ./player_hud.bend as H
import ./player_presentation.bend as P
import ./client_controls.bend as C
import ./resource_client_wire.bend as W

def L.and_false_right(value):
  match value:
    case False{}: {==}
    case True{}: {==}

def L.inactive_event(event): {==}

def L.unfocused_batch(actions,active):
  match actions:
    case Nil{}: {==}
    case C.Release{} <> tail: L.unfocused_batch(tail,False{})
    case C.PlatformEvent{+event,+captured} <> +tail:
      Equal.trans(List<&2,W.Command>,
        H.prepend(H.command(event,active && captured && False{}),H.commands(tail,captured,False{})),
        H.commands(tail,captured,False{}),[],
        Equal.cong(Maybe<&2,W.Command>,List<&2,W.Command>,
          head => H.prepend(head,H.commands(tail,captured,False{})),
          H.command(event,active && captured && False{}),None{},
          Equal.trans(Maybe<&2,W.Command>,H.command(event,active && captured && False{}),H.command(event,False{}),None{},
            Equal.cong(Bool,Maybe<&2,W.Command>,flag => H.command(event,flag),
              active && captured && False{},False{},L.and_false_right(active && captured)),
            L.inactive_event(event))),L.unfocused_batch(tail,captured))

def L.focus_loss_suppresses_entire_packet(actions,captured,previous):
  L.unfocused_batch(actions,previous)

def L.capture_loss_suppresses_entire_packet(actions,focused,previous):
  Equal.trans(List<&2,W.Command>,H.commands(actions,previous,focused && False{}),H.commands(actions,previous,False{}),[],
    Equal.cong(Bool,List<&2,W.Command>,flag => H.commands(actions,previous,flag),
      focused && False{},False{},L.and_false_right(focused)),L.unfocused_batch(actions,previous))

def L.capture_click_is_consumed(x,y): {==}

def overlay_inactive(+fuel:Nat,+image:Image,+view:H.View,+layout:H.Layout,+viewport:P.Viewport,
    +x:U32,+y:U32,+side:U32) -> {H.native_overlay(fuel,image,view,layout,viewport,x,y,side,False{}) == image : Image}:
  match fuel image:
    case 0n Pix{color}: {==}
    case 0n Qua{tl,tr,bl,br}: {==}
    case 1n+rest Pix{color}: {==}
    case 1n+rest Qua{tl,tr,bl,br}: {==}

def L.untouched_world_subtree(fuel,image,view,layout,viewport,x,y,side,outside):
  Equal.trans(Image,
    H.native_overlay(fuel,image,view,layout,viewport,x,y,side,H.native_touched(layout,viewport,x,y,side)),
    H.native_overlay(fuel,image,view,layout,viewport,x,y,side,False{}),image,
    Equal.cong(Bool,Image,active => H.native_overlay(fuel,image,view,layout,viewport,x,y,side,active),
      H.native_touched(layout,viewport,x,y,side),False{},outside),
    overlay_inactive(fuel,image,view,layout,viewport,x,y,side))

def L.matching_scene_projection_identity(image,width,height,output_width,output_height): {==}
def L.invisible_projection_padding(draw): {==}
