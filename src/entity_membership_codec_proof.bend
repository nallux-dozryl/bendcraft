import Base
import ./entity_membership_codec_laws.bend as L
import ./entity_section_membership_model.bend as M
import ./cooking_effect_entities_model.bend as E
import ./random.bend as R
import ./geometry.bend as A
import ./f64.bend as F

def L.box_words_preserve_every_endpoint(box):
  match box:
    case A.AABB{F.F64{ah,al},F.F64{bh,bl},F.F64{ch,cl},F.F64{dh,dl},F.F64{eh,el},F.F64{fh,fl}}: {==}
def L.uuid_words_preserve_complete_identity(uuid):
  match uuid:
    case E.Uuid{R.Bits64{a,b},R.Bits64{c,d}}: {==}
def L.packed_key_words_are_lossless(key):
  match key:
    case M.SectionKey{x,y,z}: {==}
def L.closed_visibility_projection_is_lossless(visibility):
  match visibility:
    case M.Hidden{}: {==}
    case M.Tracked{}: {==}
    case M.Ticking{}: {==}
def L.inspect_save_retains_complete_manager_and_actual_encoding(limits,view):
  match view:
    case M.View{members,sections,chunks,tracked,ticked}: {==}
