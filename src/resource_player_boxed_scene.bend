import Base
import ./resource_player_scene.bend as Plain
import ./player_session.bend as S
import ./player_runtime.bend as R
import ./client_presenter.bend as CP
import ./client_world.bend as W
import ./world_visibility.bend as V
import ./world_resource_frame.bend as F
import ./resource_frame.bend as RF
import ./world_mesh.bend as WM

# Recursive wrappers keep the generic presenter continuations narrow. All
# contents remain present; this changes the representation, not the renderer.
type Frame is Data:
  Frame{sample: V.Sample, tail: List<&2, Frame>}

type Assets is Type:
  Assets{resources: RF.Assets, tail: List<&1, Assets>}

def assets(resources: RF.Assets) -> Assets:
  Assets{resources, []}

def sampled(value: W.State & Result<&2, &2, String, V.Sample>) -> W.State & Result<&2, &2, String, Frame>:
  (world, status) = value
  match status:
    case Fail{error}: (world, Fail{error})
    case Done{sample}: (world, Done{Frame{sample, []}})

def world_snapshot(world: W.State) -> W.State & Result<&2, &2, String, Frame>:
  sampled(Plain.world_snapshot(world))

def snapshot_valid(state: S.State, valid: Bool) -> S.State & Result<&2, &2, String, Frame>:
  match valid:
    case False{}: (state, Fail{"ResourceScene:Frame"})
    case True{}:
      S.query(Result<&2, &2, String, Frame>, state,
        p => R.query(Result<&2, &2, String, Frame>, p, world_snapshot))

def snapshot(state: S.State, width: U32, height: U32) -> S.State & Result<&2, &2, String, Frame>:
  snapshot_valid(state, WM.frame_valid(WM.frame(width, height)))

law invalid_frame_preserves_session:
  for state: S.State
  {snapshot_valid(state, False{}) == (state, Fail{"ResourceScene:Frame"}) : S.State & Result<&2, &2, String, Frame>}
def invalid_frame_preserves_session(state):
  {==}

def canonical(frame: Frame) -> Bool:
  match frame:
    case Frame{sample, Nil{}}: True{}
    case _: False{}

def presenter_driver() -> CP.Driver<S.State, Frame>:
  CP.Driver{snapshot, Plain.input, S.release, canonical}

def describe(frame: Frame) -> String:
  Frame{sample, tail} = frame
  Plain.describe(sample)

def drawn(value: RF.Assets & Result<&2, &2, String, Image>) -> Assets & Result<&2, &2, String, Image>:
  (resources, status) = value
  (Assets{resources, []}, status)

def draw_assets(sample: V.Sample, owned: Assets, width: U32, height: U32) -> Assets & Result<&2, &2, String, Image>:
  match owned:
    case Assets{resources, Nil{}}: drawn(F.draw(sample, resources, width, height))
    case Assets{resources, tail}: (Assets{resources, tail}, Fail{"ResourceScene:AssetsTail"})

def draw(frame: Frame, owned: Assets, width: U32, height: U32) -> Assets & Result<&2, &2, String, Image>:
  match frame:
    case Frame{sample, Nil{}}: draw_assets(sample, owned, width, height)
    case _: (owned, Fail{"ResourceScene:FrameTail"})

# Every affine nested owner is consumed. Both recursive calls descend through
# actual list fields; no reconstructed work stack or mutual recursion is used.
def close_all(values: List<&1, Assets>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit, Unit{})
    case Assets{resources, tail} <> rest:
      do IO<Unit>:
        RF.close_assets(resources)
        close_all(tail)
        close_all(rest)

def close_assets(owned: Assets) -> IO(Unit):
  close_all([owned])

def renderer() -> CP.Renderer<Frame, Assets>:
  CP.Renderer{draw, describe, close_assets}

def resource_palette(state: S.State) -> S.State & Result<&2, &2, String, RF.Palette>:
  Plain.resource_palette(state)
