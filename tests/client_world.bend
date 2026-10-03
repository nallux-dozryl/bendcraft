import Base
import ../src/client_world.bend as W
import ../src/client_render.bend as R
import ../src/core.bend as C
import ../src/game.bend as G
import ../src/registry.bend as B
import ../src/movement.bend as M
import ../src/geometry.bend as A
import ../src/f64.bend as F
import ../src/live.bend as L
import ../src/json.bend as J
import ../src/schedule.bend as Q

def number_result(result: Maybe<&2, U32>) -> U32:
  match result:
    case Some{value}: value
    case None{}: 0

def number(text: String) -> U32:
  number_result(U32.read(text))

def f32(value: U32) -> F32:
  match value:
    case U32{word}: F32{word}

def word(value: F32) -> U32:
  match value:
    case F32{word}: U32{word}

def scalar(value: F.F64) -> String:
  F.F64{hi, lo} = value
  U32.show(hi) ++ "," ++ U32.show(lo)

def vector(value: M.Vec3) -> String:
  M.Vec3{x, y, z} = value
  scalar(x) ++ "," ++ scalar(y) ++ "," ++ scalar(z)

def box(value: A.AABB) -> String:
  A.AABB{a, b, c, d, e, f} = value
  scalar(a) ++ "," ++ scalar(b) ++ "," ++ scalar(c) ++ "," ++ scalar(d) ++ "," ++ scalar(e) ++ "," ++ scalar(f)

def count_blocks(blocks: List<&2, R.Block>) -> Nat:
  match blocks:
    case Nil{}: 0n
    case block <> rest: 1n+count_blocks(rest)

def blocks_text(blocks: List<&2, R.Block>) -> String:
  match blocks:
    case Nil{}: ""
    case R.Block{x, y, z, state, material} <> rest:
      U32.show(word(x)) ++ "," ++ U32.show(word(y)) ++ "," ++ U32.show(word(z)) ++ "," ++ U32.show(state) ++ "," ++ U32.show(material) ++ ";" ++ blocks_text(rest)

def snapshot_text(value: R.Snapshot) -> String:
  R.Snapshot{tick, revision, +blocks, R.Camera{x, y, z, yaw, pitch}} = value
  Nat.show(tick) ++ "|" ++ Nat.show(revision) ++ "|" ++ Nat.show(count_blocks(blocks)) ++ "|" ++ U32.show(word(x)) ++ "," ++ U32.show(word(y)) ++ "," ++ U32.show(word(z)) ++ "," ++ U32.show(word(yaw)) ++ "," ++ U32.show(word(pitch)) ++ "|" ++ blocks_text(blocks)

def transition_text(value: M.Transition) -> String:
  M.Transition{M.Body{position, bounds, velocity, width, height, ground, horizontal, vertical, below}, delta, stepped, changed} = value
  vector(delta) ++ "|" ++ vector(position) ++ "|" ++ box(bounds) ++ "|" ++ vector(velocity) ++ "|" ++ U32.show(Bool.to_u32(ground)) ++ "," ++ U32.show(Bool.to_u32(horizontal)) ++ "," ++ U32.show(Bool.to_u32(vertical)) ++ "," ++ U32.show(Bool.to_u32(below)) ++ "," ++ U32.show(Bool.to_u32(stepped)) ++ "," ++ U32.show(Bool.to_u32(changed))

def colliders_text(values: List<&2, A.Collider>) -> String:
  match values:
    case Nil{}: ""
    case A.EmptyCollider{} <> rest: "empty;" ++ colliders_text(rest)
    case A.BoxCollider{A.AABB{a, b, c, d, e, f}} <> rest: scalar(a) ++ "," ++ scalar(b) ++ "," ++ scalar(c) ++ ";" ++ colliders_text(rest)

def snapshot_report(id: String, result: W.State & Result<&2, &2, String, R.Snapshot>) -> IO(W.State):
  (state, status) = result
  match status:
    case Fail{error}:
      do IO<W.State>:
        IO.print(id ++ "|error|" ++ error)
        return state
    case Done{value}:
      do IO<W.State>:
        IO.print(id ++ "|snapshot|" ++ snapshot_text(value))
        return state

def movement_report(id: String, result: W.State & Result<&2, &2, String, M.Transition>) -> IO(W.State):
  (state, status) = result
  match status:
    case Fail{error}:
      do IO<W.State>:
        IO.print(id ++ "|error|" ++ error)
        return state
    case Done{value}:
      do IO<W.State>:
        IO.print(id ++ "|movement|" ++ transition_text(value))
        return state

def unit_report(id: String, result: W.State & Result<&2, &2, String, Unit>) -> IO(W.State):
  (state, status) = result
  match status:
    case Fail{error}:
      do IO<W.State>:
        IO.print(id ++ "|error|" ++ error)
        return state
    case Done{unit}:
      do IO<W.State>:
        IO.print(id ++ "|done")
        return state

def release(state: W.State) -> IO(Unit):
  IO.pure(Unit, Unit{})

def loaded_fixture(result: W.State & Result<&2, &2, String, Unit>) -> IO(W.State):
  (state, status) = result
  match status:
    case Fail{error}: IO.die(W.State, 1, "fixture failed:" ++ error)
    case Done{unit}: IO.pure(W.State, state)

def replace_body(state: W.State, body: M.Body) -> W.State:
  W.State{engine, old, yaw, pitch, palette, region, cache} = state
  W.State{engine, body, yaw, pitch, palette, region, cache}

def replace_angles(state: W.State, yaw: F32, pitch: F32) -> W.State:
  W.State{engine, body, old_yaw, old_pitch, palette, region, cache} = state
  W.State{engine, body, yaw, pitch, palette, region, cache}

def query_report(id: String, result: C.World & Result<&2, &2, String, List<&2, A.Collider>>) -> IO(Unit):
  (world, status) = result
  match status:
    case Fail{error}: IO.print(id ++ "|error|" ++ error)
    case Done{values}: IO.print(id ++ "|query|" ++ colliders_text(values))

def query_state(id: String, state: W.State, query: A.AABB) -> IO(Unit):
  W.State{G.Engine{world, registry}, body, yaw, pitch, palette, region, cache} = state
  match palette:
    case None{}: IO.die(Unit, 1, "missing fixture palette")
    case Some{actual}: query_report(id, W.collect(world, actual, query))

def repeated(+id: String, state: W.State) -> IO(Unit):
  do IO<Unit>:
    first : W.State <- snapshot_report(id ++ "-first", W.snapshot(state, 64, 48))
    second : W.State <- snapshot_report(id ++ "-second", W.snapshot(first, 800, 600))
    third : W.State <- snapshot_report(id ++ "-uncached", W.snapshot(W.invalidate_cache(second), 64, 48))
    release(third)

def body_move(id: String, state: W.State, fields: List<&2, String>) -> IO(Unit):
  match fields:
    case pxh <> pxl <> pyh <> pyl <> pzh <> pzl <> dxh <> dxl <> dyh <> dyl <> dzh <> dzl <> maximum <> grounded <> width <> height <> Nil{}:
      body = M.Body.new(M.Vec3{F.F64{number(pxh), number(pxl)}, F.F64{number(pyh), number(pyl)}, F.F64{number(pzh), number(pzl)}}, f32(number(width)), f32(number(height)), M.Vec3.zero(), U32.is_ne(number(grounded), 0))
      do IO<Unit>:
        next : W.State <- movement_report(id, W.move(replace_body(state, body), M.Vec3{F.F64{number(dxh), number(dxl)}, F.F64{number(dyh), number(dyl)}, F.F64{number(dzh), number(dzl)}}, f32(number(maximum))))
        release(next)
    case _: IO.die(Unit, 2, "invalid body-move protocol")

def query_fields(id: String, state: W.State, fields: List<&2, String>) -> IO(Unit):
  match fields:
    case ah <> al <> bh <> bl <> ch <> cl <> dh <> dl <> eh <> el <> fh <> fl <> Nil{}:
      query_state(id, state, A.AABB{F.F64{number(ah), number(al)}, F.F64{number(bh), number(bl)}, F.F64{number(ch), number(cl)}, F.F64{number(dh), number(dl)}, F.F64{number(eh), number(el)}, F.F64{number(fh), number(fl)}})
    case _: IO.die(Unit, 2, "invalid query protocol")

def bounds_report(id: String, result: Result<&2, &2, String, W.Bounds>) -> IO(Unit):
  match result:
    case Fail{error}: IO.print(id ++ "|error|" ++ error)
    case Done{W.Bounds{x, y, z, w, h, d}}: IO.print(id ++ "|bounds|" ++ U32.show(x) ++ "," ++ U32.show(y) ++ "," ++ U32.show(z) ++ "," ++ U32.show(w) ++ "," ++ U32.show(h) ++ "," ++ U32.show(d))

def bounds_fields(id: String, fields: List<&2, String>) -> IO(Unit):
  match fields:
    case ah <> al <> bh <> bl <> ch <> cl <> dh <> dl <> eh <> el <> fh <> fl <> Nil{}:
      bounds_report(id, W.query_bounds(A.AABB{F.F64{number(ah), number(al)}, F.F64{number(bh), number(bl)}, F.F64{number(ch), number(cl)}, F.F64{number(dh), number(dl)}, F.F64{number(eh), number(el)}, F.F64{number(fh), number(fl)}}))
    case _: IO.die(Unit, 2, "invalid bounds protocol")

def response_state(result: W.State & L.Session & J.Value) -> W.State:
  (state, session, value) = result
  state

def change_block(state: W.State, value: U32) -> W.State:
  request = L.obj([J.JMember{"id", L.text("fixture-edit")}, J.JMember{"op", L.text("world.block.set")}, J.JMember{"args", L.obj([J.JMember{"dimension", L.text("minecraft:overworld")}, J.JMember{"x", L.uint(0)}, J.JMember{"y", L.uint(1)}, J.JMember{"z", L.uint(0)}, J.JMember{"state", L.uint(value)}])}])
  response_state(W.dispatch(state, L.Session{9, 0n, C.Developer{}}, "test", request))

def advance(state: W.State) -> W.State:
  response_state(W.dispatch(state, L.Session{9, 1n, C.Developer{}}, "test", L.obj([J.JMember{"id", L.text("fixture-step")}, J.JMember{"op", L.text("simulation.step")}, J.JMember{"args", L.obj([J.JMember{"ticks", L.uint(1)}])}])))

def unpause(state: W.State) -> W.State:
  response_state(W.dispatch(state, L.Session{9, 0n, C.Developer{}}, "test", L.obj([J.JMember{"id", L.text("unpause")}, J.JMember{"op", L.text("simulation.pause")}, J.JMember{"args", L.obj([J.JMember{"paused", L.boolean(False{})}])}])))

def fixture_again(state: W.State) -> W.State & Result<&2, &2, String, Unit>:
  W.State{engine, body, yaw, pitch, palette, region, cache} = state
  W.fixture(engine)

def consumed_snapshot(result: W.State & Result<&2, &2, String, R.Snapshot>) -> W.State & Nat:
  (state, status) = result
  match status:
    case Fail{error}: (state, 0n)
    case Done{R.Snapshot{tick, revision, blocks, camera}}: (state, count_blocks(blocks))

def benchmark(n: Nat, state: W.State, count: Nat) -> W.State & Nat:
  match n:
    case 0n: (state, count)
    case 1n+rest:
      W.paired(W.State, Nat, W.State & Nat, consumed_snapshot(W.snapshot(state, 64, 48)), next => added => benchmark(rest, next, Nat.add(count, added)))

def benchmark_report(id: String, result: W.State & Nat) -> IO(Unit):
  (state, count) = result
  IO.print(id ++ "|count|" ++ Nat.show(count))

def edit_palette(state: W.State) -> W.State:
  W.State{engine, body, yaw, pitch, +palette, region, cache} = state
  match palette:
    case None{}: W.State{engine, body, yaw, pitch, palette, region, cache}
    case Some{W.Palette{air, stone, dirt, planks}}: advance(change_block(W.State{engine, body, yaw, pitch, palette, region, cache}, planks))

def block_default(result: B.Registry & Result<&2, &2, B.Error, B.Block>) -> B.Registry & U32:
  (registry, status) = result
  match status:
    case Fail{error}: (registry, 4294967295)
    case Done{B.Block{protocol, name, first, count, default_id, properties}}: (registry, default_id)

def unsupported(state: W.State) -> W.State:
  W.State{G.Engine{world, registry}, body, yaw, pitch, palette, region, cache} = state
  W.paired(B.Registry, U32, W.State, block_default(B.Registry.block(registry, "minecraft:glass")), registry => value => advance(change_block(W.State{G.Engine{world, registry}, body, yaw, pitch, palette, region, cache}, value)))

def raw_write_result(result: C.World & Result<&2, &2, C.Error, Unit>, registry: B.Registry, body: M.Body, yaw: F32, pitch: F32, palette: Maybe<&2, W.Palette>, region: W.Bounds, cache: Maybe<&2, W.SnapshotCache>) -> W.State:
  (world, status) = result
  W.invalidate_cache(W.State{G.Engine{world, registry}, body, yaw, pitch, palette, region, cache})

def raw_edit(state: W.State) -> W.State:
  W.State{G.Engine{world, registry}, body, yaw, pitch, +palette, region, cache} = state
  match palette:
    case None{}: W.State{G.Engine{world, registry}, body, yaw, pitch, palette, region, cache}
    case Some{W.Palette{air, stone, dirt, planks}}: raw_write_result(C.write_block(world, C.Position{"minecraft:overworld", 0, 1, 0}, planks), registry, body, yaw, pitch, palette, region, cache)

def swap_palette(state: W.State) -> W.State:
  W.State{engine, body, yaw, pitch, palette, region, cache} = state
  match palette:
    case None{}: W.State{engine, body, yaw, pitch, None{}, region, cache}
    case Some{W.Palette{air, stone, dirt, planks}}: W.State{engine, body, yaw, pitch, Some{W.Palette{air, dirt, stone, planks}}, region, cache}

def view_roundtrip(result: G.Engine & W.View) -> W.State:
  (engine, view) = result
  W.attach(engine, view)

def far_admitted(result: C.World & Result<&2, &2, C.Error, Unit>, registry: B.Registry, body: M.Body, palette: Maybe<&2, W.Palette>, region: W.Bounds) -> IO(W.State):
  (world, status) = result
  match status:
    case Fail{error}: IO.die(W.State, 1, "far fixture admission:" ++ W.error_text(error))
    case Done{unit}: IO.pure(W.State, W.State{G.Engine{C.step(world), registry}, body, 0.0, 0.2, palette, region, None{}})

def far_owned(state: W.State, +x: U32, +y: U32, +z: U32, position: M.Vec3) -> IO(W.State):
  W.State{G.Engine{world, registry}, old, yaw, pitch, +palette, region, cache} = state
  match palette:
    case None{}: IO.die(W.State, 1, "far fixture palette unavailable")
    case Some{W.Palette{air, stone, dirt, planks}}:
      far_admitted(C.admit(world, C.Developer{}, Q.Stamp{1n, 3, 0n}, C.SectionCreate{C.Position{"minecraft:overworld", x, y, z}, stone}), registry, M.Body.new(position, 0.6, 1.8, M.Vec3.zero(), True{}), palette, W.Bounds{x, y, z, 3, 2, 3})

def far_sequence(+id: String, +position: M.Vec3, state: W.State) -> IO(Unit):
  do IO<Unit>:
    absolute : W.State <- snapshot_report(id ++ "-absolute", W.snapshot(state, 64, 48))
    relative : W.State <- snapshot_report(id ++ "-relative", W.relative_snapshot(absolute, 64, 48))
    roundtrip : W.State <- snapshot_report(id ++ "-roundtrip", W.relative_snapshot(view_roundtrip(W.take(relative)), 64, 48))
    changed : W.State <- snapshot_report(id ++ "-shifted", W.relative_snapshot(replace_body(roundtrip, M.Body.new(M.Vec3.add(position, M.Vec3{F.from_f32(0.25), F.from_f32(0.125), F.from_f32(F32.neg(0.25))}), 0.6, 1.8, M.Vec3.zero(), True{})), 64, 48))
    uncached : W.State <- snapshot_report(id ++ "-uncached", W.relative_snapshot(W.invalidate_cache(changed), 64, 48))
    bad : W.State <- snapshot_report(id ++ "-bad", W.relative_snapshot(replace_body(uncached, M.Body.new(M.Vec3{F.F64{2146959360, 0}, M.zero(), M.zero()}, 0.6, 1.8, M.Vec3.zero(), True{})), 64, 48))
    restored : W.State <- snapshot_report(id ++ "-restored", W.relative_snapshot(replace_body(bad, M.Body.new(position, 0.6, 1.8, M.Vec3.zero(), True{})), 64, 48))
    release(restored)

def far_fields(id: String, fields: List<&2, String>, state: W.State) -> IO(Unit):
  match fields:
    case x <> y <> z <> xh <> xl <> yh <> yl <> zh <> zl <> Nil{}:
      +position = {M.Vec3{F.F64{number(xh), number(xl)}, F.F64{number(yh), number(yl)}, F.F64{number(zh), number(zl)}} : M.Vec3}
      do IO<Unit>:
        initialized : W.State <- far_owned(state, number(x), number(y), number(z), position)
        far_sequence(id, position, initialized)
    case _: IO.die(Unit, 2, "invalid far protocol")

def operations(op: String, +id: String, fields: List<&2, String>, state: W.State) -> IO(Unit):
  match op:
    case "snapshot": repeated(id, state)
    case "query": query_fields(id, state, fields)
    case "move": body_move(id, state, fields)
    case "edit":
      do IO<Unit>:
        before : W.State <- snapshot_report(id ++ "-before", W.snapshot(state, 64, 48))
        after : W.State <- snapshot_report(id ++ "-after", W.snapshot(edit_palette(before), 64, 48))
        checked : W.State <- snapshot_report(id ++ "-uncached", W.snapshot(W.invalidate_cache(after), 64, 48))
        release(checked)
    case "unsupported":
      do IO<Unit>:
        next : W.State <- snapshot_report(id ++ "-bad", W.snapshot(unsupported(state), 64, 48))
        repaired : W.State <- snapshot_report(id ++ "-repaired", W.snapshot(edit_palette(next), 64, 48))
        checked : W.State <- snapshot_report(id ++ "-uncached", W.snapshot(W.invalidate_cache(repaired), 64, 48))
        release(checked)
    case "invalid-look":
      do IO<Unit>:
        next : W.State <- unit_report(id ++ "-look", W.look(state, f32(2139095040), 0.0))
        kept : W.State <- snapshot_report(id ++ "-kept", W.snapshot(next, 64, 48))
        release(kept)
    case "invalid-region":
      do IO<Unit>:
        next : W.State <- unit_report(id ++ "-region", W.set_region(state, W.Bounds{2147483647, 0, 0, 2, 1, 1}))
        kept : W.State <- snapshot_report(id ++ "-kept", W.snapshot(next, 64, 48))
        release(kept)
    case "invalid-move":
      do IO<Unit>:
        next : W.State <- movement_report(id ++ "-move", W.move(state, M.Vec3{F.F64{2146959360, 0}, M.zero(), M.zero()}, 0.6))
        kept : W.State <- snapshot_report(id ++ "-kept", W.snapshot(next, 64, 48))
        release(kept)
    case "move-camera":
      do IO<Unit>:
        before : W.State <- snapshot_report(id ++ "-before", W.snapshot(state, 64, 48))
        next : W.State <- movement_report(id ++ "-move", W.move(before, M.Vec3{F.from_f32(0.25), M.zero(), M.zero()}, 0.6))
        moved : W.State <- snapshot_report(id ++ "-camera", W.snapshot(next, 64, 48))
        checked : W.State <- snapshot_report(id ++ "-uncached", W.snapshot(W.invalidate_cache(moved), 64, 48))
        release(checked)
    case "pulse":
      do IO<Unit>:
        paused : W.State <- snapshot_report(id ++ "-paused", W.snapshot(W.step(state), 64, 48))
        running : W.State <- snapshot_report(id ++ "-running", W.snapshot(W.step(unpause(paused)), 64, 48))
        checked : W.State <- snapshot_report(id ++ "-uncached", W.snapshot(W.invalidate_cache(running), 64, 48))
        release(checked)
    case "fixture-again":
      do IO<Unit>:
        next : W.State <- unit_report(id ++ "-reject", fixture_again(state))
        kept : W.State <- snapshot_report(id ++ "-kept", W.snapshot(next, 64, 48))
        release(kept)
    case "benchmark": benchmark_report(id, benchmark(10000n, state, 0n))
    case "noop": release(state)
    case "look":
      do IO<Unit>:
        before : W.State <- snapshot_report(id ++ "-before", W.snapshot(state, 64, 48))
        looked : W.State <- unit_report(id ++ "-look", W.look(before, 1.0, F32.neg(0.3)))
        changed : W.State <- snapshot_report(id ++ "-after", W.snapshot(looked, 64, 48))
        checked : W.State <- snapshot_report(id ++ "-uncached", W.snapshot(W.invalidate_cache(changed), 64, 48))
        release(checked)
    case "region":
      do IO<Unit>:
        before : W.State <- snapshot_report(id ++ "-before", W.snapshot(state, 64, 48))
        selected : W.State <- unit_report(id ++ "-select", W.set_region(before, W.Bounds{4294967294, 0, 4294967294, 4, 2, 4}))
        changed : W.State <- snapshot_report(id ++ "-after", W.snapshot(selected, 64, 48))
        checked : W.State <- snapshot_report(id ++ "-uncached", W.snapshot(W.invalidate_cache(changed), 64, 48))
        restored : W.State <- unit_report(id ++ "-restore", W.set_region(checked, W.default_region()))
        all : W.State <- snapshot_report(id ++ "-restored", W.snapshot(restored, 64, 48))
        release(all)
    case "raw-edit":
      do IO<Unit>:
        before : W.State <- snapshot_report(id ++ "-before", W.snapshot(state, 64, 48))
        changed : W.State <- snapshot_report(id ++ "-after", W.snapshot(raw_edit(before), 64, 48))
        checked : W.State <- snapshot_report(id ++ "-uncached", W.snapshot(W.invalidate_cache(changed), 64, 48))
        release(checked)
    case "palette":
      do IO<Unit>:
        before : W.State <- snapshot_report(id ++ "-before", W.snapshot(state, 64, 48))
        changed : W.State <- snapshot_report(id ++ "-after", W.snapshot(swap_palette(before), 64, 48))
        checked : W.State <- snapshot_report(id ++ "-uncached", W.snapshot(W.invalidate_cache(changed), 64, 48))
        release(checked)
    case "view":
      do IO<Unit>:
        before : W.State <- snapshot_report(id ++ "-before", W.snapshot(state, 64, 48))
        attached : W.State <- snapshot_report(id ++ "-attached", W.snapshot(view_roundtrip(W.take(before)), 64, 48))
        relative : W.State <- snapshot_report(id ++ "-relative", W.relative_snapshot(attached, 64, 48))
        release(relative)
    case "relative-repair":
      do IO<Unit>:
        before : W.State <- snapshot_report(id ++ "-before", W.relative_snapshot(state, 64, 48))
        bad : W.State <- snapshot_report(id ++ "-bad", W.relative_snapshot(unsupported(before), 64, 48))
        repaired : W.State <- snapshot_report(id ++ "-repaired", W.relative_snapshot(edit_palette(bad), 64, 48))
        uncached : W.State <- snapshot_report(id ++ "-uncached", W.relative_snapshot(W.invalidate_cache(repaired), 64, 48))
        release(uncached)
    case "relative-raw":
      do IO<Unit>:
        before : W.State <- snapshot_report(id ++ "-before", W.relative_snapshot(state, 64, 48))
        edited : W.State <- snapshot_report(id ++ "-after", W.relative_snapshot(raw_edit(before), 64, 48))
        uncached : W.State <- snapshot_report(id ++ "-uncached", W.relative_snapshot(W.invalidate_cache(edited), 64, 48))
        release(uncached)
    case "relative-invalid":
      W.State{engine, +body, +yaw, +pitch, palette, region, cache} = state
      do IO<Unit>:
        before : W.State <- snapshot_report(id ++ "-before", W.relative_snapshot(W.State{engine, body, yaw, pitch, palette, region, cache}, 64, 48))
        infinity : W.State <- snapshot_report(id ++ "-infinity", W.relative_snapshot(replace_body(before, M.Body.new(M.Vec3{F.F64{2146435072, 0}, M.zero(), M.zero()}, 0.6, 1.8, M.Vec3.zero(), True{})), 64, 48))
        high : W.State <- snapshot_report(id ++ "-high", W.relative_snapshot(replace_body(infinity, M.Body.new(M.Vec3{F.from_u32(2147483648), M.zero(), M.zero()}, 0.6, 1.8, M.Vec3.zero(), True{})), 64, 48))
        low : W.State <- snapshot_report(id ++ "-low", W.relative_snapshot(replace_body(high, M.Body.new(M.Vec3{F.sub(F.from_i32(2147483648), F.from_u32(1)), M.zero(), M.zero()}, 0.6, 1.8, M.Vec3.zero(), True{})), 64, 48))
        angle : W.State <- snapshot_report(id ++ "-angle", W.relative_snapshot(replace_angles(replace_body(low, body), f32(2139095040), pitch), 64, 48))
        nan_pitch : W.State <- snapshot_report(id ++ "-pitch", W.relative_snapshot(replace_angles(angle, yaw, f32(2143289344)), 64, 48))
        restored : W.State <- snapshot_report(id ++ "-restored", W.relative_snapshot(replace_angles(nan_pitch, yaw, pitch), 64, 48))
        release(restored)
    case _: IO.die(Unit, 2, "invalid client-world operation")

def terrain_free(+id: String, result: W.State & Result<&2, &2, String, Unit>) -> IO(Unit):
  do IO<Unit>:
    first : W.State <- unit_report(id ++ "-new", result)
    second : W.State <- snapshot_report(id ++ "-missing", W.snapshot(first, 64, 48))
    relative : W.State <- snapshot_report(id ++ "-relative-missing", W.relative_snapshot(second, 64, 48))
    third : W.State <- movement_report(id ++ "-stationary", W.move(relative, M.Vec3.zero(), 0.6))
    fourth : W.State <- movement_report(id ++ "-nonzero", W.move(third, M.Vec3{F.from_f32(0.25), M.zero(), M.zero()}, 0.6))
    release(fourth)

def command(fields: List<&2, String>, engine: G.Engine) -> IO(Unit):
  match fields:
    case "bounds" <> id <> rest: bounds_fields(id, rest)
    case "new" <> id <> Nil{}: terrain_free(id, W.new(engine))
    case "far" <> id <> rest:
      do IO<Unit>:
        state : W.State <- loaded_fixture(W.new(engine))
        far_fields(id, rest, state)
    case op <> id <> rest:
      do IO<Unit>:
        state : W.State <- loaded_fixture(W.fixture(engine))
        operations(op, id, rest, state)
    case _: IO.die(Unit, 2, "invalid client-world protocol")

def run(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case value <> rest:
      do IO<Unit>:
        engine : G.Engine <- G.load()
        command(String.split(value, '|'), engine)
        run(rest)

def drop_program(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case program <> rest: run(rest)

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), drop_program)
