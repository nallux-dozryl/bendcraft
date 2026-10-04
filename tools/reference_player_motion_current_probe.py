#!/usr/bin/env python3
"""Observe pinned Player.travel's actual one-shot Entity.move stuck phase.

Historical probe sources are imported unchanged; only this fresh fixture and its
ignored build directory are written. Expected bodies always come from Java.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import math
import re
import struct
import subprocess
import time
import zipfile

from reference_inventory import ROOT, JAVA, canonical, fingerprint, write_json
from reference_block_probe import verified_classpath
from reference_movement_probe import SOURCE as MOVEMENT_SOURCE, DIRECT_SOURCE
from reference_travel_probe import SOURCE as TRAVEL_SOURCE

RAW = ROOT / 'build/player-motion-current/reference'
OUTPUT = ROOT / 'reference/player_motion_current.json'
EVIDENCE = ROOT / 'evidence/player-motion-current-reference.json'
THRESHOLD = '3e7ad7f29abcaf48'


def sha(value):
    return hashlib.sha256(canonical(value)).hexdigest()


def replace_once(source, old, new):
    assert source.count(old) == 1, old
    return source.replace(old, new)


def java_source():
    source = TRAVEL_SOURCE.replace('ReferenceTravelProbe', 'ReferencePlayerMotionCurrentProbe')
    source = replace_once(source,
        'Vec3 requested,postMoveVelocity,recorded;Map<String,Object> postMoveBody;',
        'Vec3 requested,postMoveVelocity,recorded;Map<String,Object> postMoveBody,preMoveBody;'
        'Map<String,Object> stuckPhase;')
    source = replace_once(source,
        '  public void move(MoverType t,Vec3 v){hit("move_observer");requested=v;super.move(t,v);postMoveVelocity=getDeltaMovement();postMoveBody=body(this);}',
        '''  Vec3 stuck(){return stuckSpeedMultiplier;}
  protected Vec3 maybeBackOffFromEdge(Vec3 v,MoverType t){
   hit("stuck_phase_observer");
   Map<String,Object> m=new TreeMap<>();
   m.put("mover",t.name());m.put("entry_request",ReferenceMovementProbe.vectorBits(v));
   m.put("entry_body",body(this));m.put("entry_multiplier",ReferenceMovementProbe.vectorBits(stuck()));
   Vec3 result=super.maybeBackOffFromEdge(v,t);
   m.put("returned_request",ReferenceMovementProbe.vectorBits(result));stuckPhase=m;return result;
  }
  public void move(MoverType t,Vec3 v){hit("move_observer");requested=v;preMoveBody=body(this);super.move(t,v);postMoveVelocity=getDeltaMovement();postMoveBody=body(this);}''')
    source = replace_once(source,
        '  p.setDeltaMovement(ReferenceMovementProbe.vector(in.getAsJsonArray("velocity")));',
        '''  p.setDeltaMovement(ReferenceMovementProbe.vector(in.getAsJsonArray("velocity")));
  p.makeStuckInBlock(Blocks.AIR.defaultBlockState(),ReferenceMovementProbe.vector(in.getAsJsonArray("stuck_multiplier")));
  if(p.noPhysics)throw new AssertionError("SELF collision fixture unexpectedly has noPhysics");''')
    source = replace_once(source,
        '  p.observations.clear();level.clearTrace();p.travel(ReferenceMovementProbe.vector(in.getAsJsonArray("input")));',
        '''  actual.put("stuck_multiplier",ReferenceMovementProbe.vectorBits(p.stuck()));
  actual.put("stuck_length_squared",ReferenceMovementProbe.bits(p.stuck().lengthSqr()));
  p.observations.clear();level.clearTrace();p.travel(ReferenceMovementProbe.vector(in.getAsJsonArray("input")));''')
    source = replace_once(source,
        '  if(p.requested==null||p.postMoveVelocity==null||p.sampledBelow==null)throw new AssertionError("Actual dry-air travel path not executed");',
        '  if(p.requested==null||p.postMoveVelocity==null||p.sampledBelow==null||p.stuckPhase==null)throw new AssertionError("Actual dry-air stuck travel path not executed");')
    source = replace_once(source,
        '  return Map.of("id",c.get("id").getAsString(),"expected",body(p),"observation",observed);',
        '''  observed.put("pre_move_body",p.preMoveBody);observed.put("stuck_phase",p.stuckPhase);
  observed.put("recorded_displacement",p.recorded==null?null:ReferenceMovementProbe.vectorBits(p.recorded));
  observed.put("final_stuck_multiplier",ReferenceMovementProbe.vectorBits(p.stuck()));
  observed.put("full_entity_move_executed",true);
  return Map.of("id",c.get("id").getAsString(),"expected",body(p),"observation",observed);''')
    return source


SOURCE = java_source()


def bits(value):
    return struct.pack('>d', value).hex()


def fbits(value):
    return struct.pack('>f', value).hex()


def block(x, y, z):
    return {'position': [x, y, z], 'identifier': 'minecraft:stone'}


def generate_inputs():
    cases = []
    floor = [block(x, 0, z) for x in range(-2, 3) for z in range(-2, 3)]
    worlds = {
        'free': [], 'floor': floor,
        'wall': floor + [block(1, y, z) for y in [1, 2] for z in range(-2, 3)],
        'ceiling': floor + [block(x, 3, z) for x in range(-2, 3) for z in range(-2, 3)],
        'step': floor + [block(1, 1, 0)],
        'step_ceiling': floor + [block(1, 1, 0), block(1, 3, 0)],
    }

    def add(label, tags, **changes):
        value = {
            'position': list(map(bits, [.5, 1., .5])),
            'velocity': list(map(bits, [.75, -.2, .5])),
            'input': list(map(bits, [1., .25, 1.])),
            'stuck_multiplier': list(map(bits, [0., 0., 0.])),
            'grounded': True, 'sprinting': False, 'no_gravity': False,
            'discard_friction': False, 'yaw_f32_bits': fbits(0.),
            'movement_speed': bits(.1), 'gravity': bits(.08),
            'friction_modifier': bits(1.), 'air_drag_modifier': bits(1.),
            'step_height': bits(.6), 'world_blocks': floor,
        }
        value.update(changes)
        cases.append({'id': 'motion-current:' + label, 'operation': 'player_travel',
                      'input': value, 'tags': ['actual_player_travel', 'actual_entity_move', 'stuck_phase', *tags]})

    root = math.sqrt(1e-7)
    # The Java-observed squared length is stored; no Python threshold result is
    # used as an expected movement body.
    for axis in range(3):
        for index, component in enumerate([math.nextafter(root, 0.), root,
                                           math.nextafter(root, math.inf),
                                           -math.nextafter(root, 0.), -root,
                                           -math.nextafter(root, math.inf)]):
            vector = [0., 0., 0.]
            vector[axis] = component
            for ground in [False, True]:
                add(f'threshold-{axis}-{index}-{ground}', ['threshold', 'axis', 'strict_comparison'],
                    stuck_multiplier=list(map(bits, vector)), grounded=ground,
                    world_blocks=[] if not ground else floor)
    paired = math.sqrt(1e-7 / 2.)
    for index, component in enumerate([math.nextafter(paired, 0.), paired,
                                       math.nextafter(paired, math.inf)]):
        add(f'threshold-pair-{index}', ['threshold', 'sum_order'],
            stuck_multiplier=list(map(bits, [component, -component, -0.])))
    # sqrt(threshold)^2 rounds above threshold on this binary64 input. A
    # residual second component makes the Java left-associated sum exactly the
    # threshold, exercising the equality branch rather than only its neighbors.
    equal_x = math.nextafter(root, 0.)
    equal_y = math.sqrt(1e-7 - equal_x * equal_x)
    assert equal_x * equal_x + equal_y * equal_y == 1e-7
    for axis in range(3):
        vector = [0., 0., 0.]
        vector[axis], vector[(axis + 1) % 3] = equal_x, equal_y
        for ground in [False, True]:
            add(f'threshold-equal-{axis}-{ground}', ['threshold', 'exact_equality'],
                stuck_multiplier=list(map(bits, vector)), grounded=ground,
                world_blocks=[] if not ground else floor)
    for index, vector in enumerate([[0., 0., 0.], [-0., -0., -0.], [0., -0., 0.], [-0., 0., -0.]]):
        for moving in [False, True]:
            add(f'zero-{index}-{moving}', ['inactive', 'signed_zero'],
                stuck_multiplier=list(map(bits, vector)),
                velocity=list(map(bits, [.5, -.1, -.5] if moving else [-0., -0., -0.])),
                input=list(map(bits, [0., 0., 0.])), world_blocks=[])
    multipliers = [[.25, .05, .25], [1., 1., 1.], [-.5, 0., .5],
                   [0., -0., 1.], [2., .5, -1.], [1e-200, 1., 1e-200]]
    for name, world in worlds.items():
        for index, vector in enumerate(multipliers):
            add(f'{name}-{index}', [name, 'active', 'scale_then_clear'],
                stuck_multiplier=list(map(bits, vector)), world_blocks=world,
                step_height=bits(1. if name.startswith('step') else .6),
                velocity=list(map(bits, [.75, .6 if name == 'ceiling' else -.2, .5])),
                yaw_f32_bits=fbits(45.), sprinting=bool(index % 2))
    for no_gravity in [False, True]:
        for discard in [False, True]:
            for drag in [0., 1., 2.5]:
                add(f'finish-{no_gravity}-{discard}-{drag}', ['gravity_drag_after_zero'],
                    stuck_multiplier=list(map(bits, [.25, .05, .25])),
                    grounded=False, world_blocks=[], no_gravity=no_gravity,
                    discard_friction=discard, air_drag_modifier=bits(drag))
    for index, vector in enumerate([[1., 1., 1.], [0., 0., 0.], [1e200, 0., 0.], [-0., 1., 0.]]):
        add(f'zero-request-{index}', ['zero_request', 'reset_even_without_displacement'],
            stuck_multiplier=list(map(bits, vector)), velocity=list(map(bits, [0., 0., 0.])),
            input=list(map(bits, [0., 0., 0.])), grounded=False, world_blocks=[])
    return cases


def source_inventory(jars):
    owners = {
        'net.minecraft.world.entity.Entity': {'move', 'makeStuckInBlock', 'canSimulateMovement'},
        'net.minecraft.world.entity.player.Player': {'travel', 'getFlyingSpeed', 'maybeBackOffFromEdge'},
        'net.minecraft.world.entity.LivingEntity': {'travel', 'travelInAir', 'handleRelativeFrictionAndCalculateMovement'},
        'net.minecraft.world.phys.Vec3': {'lengthSqr', 'multiply'},
        'net.minecraft.world.entity.MoverType': {'isServerAndClientSimulated'},
    }
    classes = {}
    with zipfile.ZipFile(jars[0]) as archive:
        for owner, relevant in owners.items():
            result = subprocess.run([str(JAVA.parent / 'javap'), '-classpath', str(jars[0]), '-c', '-p', owner],
                                    capture_output=True, text=True, check=True)
            methods = []
            for part in re.split(r'(?=^  (?:public|private|protected|static).*(?:;|\{)$)', result.stdout, flags=re.M):
                lines = part.splitlines()
                if lines and any(re.search(r'\b' + re.escape(name) + r'\(', lines[0]) for name in relevant):
                    methods.append({'signature': lines[0].strip(),
                                    'bytecode_text_sha256': hashlib.sha256(part.encode()).hexdigest()})
            entry = owner.replace('.', '/') + '.class'
            classes[owner] = {'class_entry': entry, 'class_sha256': hashlib.sha256(archive.read(entry)).hexdigest(),
                              'complete_bytecode_text_sha256': hashlib.sha256(result.stdout.encode()).hexdigest(), 'methods': methods}
    return {'classes': classes}


def compile_java(jars):
    RAW.mkdir(parents=True, exist_ok=True)
    classes = RAW / 'classes'
    classes.mkdir(exist_ok=True)
    sources = []
    for name, source in [('ReferenceMovementProbe', MOVEMENT_SOURCE),
                         ('ReferenceDirectMovementProbe', DIRECT_SOURCE),
                         ('ReferencePlayerMotionCurrentProbe', SOURCE)]:
        path = RAW / (name + '.java')
        path.write_text(source)
        sources.append(path)
    command = [str(JAVA.parent / 'javac'), '-cp', ':'.join(map(str, jars)), '-d', str(classes), *map(str, sources)]
    start = time.monotonic()
    result = subprocess.run(command, capture_output=True, text=True)
    log = RAW / 'javac.log'
    log.write_text(result.stdout + result.stderr)
    result.check_returncode()
    return {'command': command, 'seconds': round(time.monotonic() - start, 6), 'log': fingerprint(log)}


def run_java(inputs, jars, label):
    incoming, outgoing = RAW / (label + '-input.jsonl'), RAW / (label + '-observed.jsonl')
    incoming.write_text(''.join(canonical(case).decode() + '\n' for case in inputs))
    command = [str(JAVA), '-cp', str(RAW / 'classes') + ':' + ':'.join(map(str, jars)),
               'ReferencePlayerMotionCurrentProbe', str(incoming), str(outgoing)]
    start = time.monotonic()
    result = subprocess.run(command, capture_output=True, text=True)
    log = RAW / (label + '.log')
    log.write_text(result.stdout + result.stderr)
    result.check_returncode()
    observed = [json.loads(line) for line in outgoing.read_text().splitlines()]
    assert [c['id'] for c in observed] == [c['id'] for c in inputs]
    return observed, {'command': command, 'seconds': round(time.monotonic() - start, 6),
                      'log': fingerprint(log), 'input': fingerprint(incoming), 'observations': fingerprint(outgoing)}


def validate(data, observed=None):
    assert data['pin'] == '26.3' and data['schema_version'] == 1
    assert data['cases_sha256'] == sha(data['cases'])
    assert [{k: c[k] for k in ['id', 'operation', 'input', 'tags']} for c in data['cases']] == generate_inputs()
    if observed is not None:
        assert [{k: c[k] for k in ['id', 'expected', 'observation']} for c in data['cases']] == observed
    active = 0
    inactive = 0
    exact_threshold = 0
    for case in data['cases']:
        o = case['observation']
        assert o['full_player_travel_executed'] and o['full_entity_move_executed']
        assert o['observer_calls']['stuck_phase_observer'] == 1
        assert o['stuck_phase']['mover'] == 'SELF'
        length = struct.unpack('>d', bytes.fromhex(o['actual_input']['stuck_length_squared']))[0]
        consumed = length > 1e-7
        active += consumed
        inactive += not consumed
        exact_threshold += o['actual_input']['stuck_length_squared'] == THRESHOLD
        if consumed:
            assert o['stuck_phase']['entry_body']['velocity'] == [bits(0.)] * 3
            assert o['stuck_phase']['entry_multiplier'] == o['final_stuck_multiplier'] == [bits(0.)] * 3
        else:
            assert o['stuck_phase']['entry_body']['velocity'] == o['pre_move_body']['velocity']
            assert o['stuck_phase']['entry_multiplier'] == o['final_stuck_multiplier'] == case['input']['stuck_multiplier']
        assert o['stuck_phase']['entry_request'] == o['stuck_phase']['returned_request'], 'neutral edge fixture drift'
    assert active and inactive and exact_threshold
    return {'case_count': len(data['cases']), 'active_cases': active, 'inactive_cases': inactive,
            'exact_threshold_cases': exact_threshold, 'actual_player_travel_cases': len(data['cases']),
            'oracle_compared': observed is not None}


def extract():
    jars, release = verified_classpath()
    inputs = generate_inputs()
    compile_receipt = compile_java(jars)
    first, run1 = run_java(inputs, jars, 'independent-1')
    second, run2 = run_java(inputs, jars, 'independent-2')
    assert first == second, 'Independent JVM observations differ'
    data = {
        'schema_version': 1, 'pin': '26.3', 'cases': [{**i, **o} for i, o in zip(inputs, first, strict=True)],
        'server_bundle_sha256': release['server_bundle']['sha256'],
        'server_class_jar_sha256': release['server_bundle']['nested_server_sha256'],
        'runtime_executable': fingerprint(JAVA),
        'runtime_version': subprocess.run([str(JAVA), '-version'], capture_output=True, text=True, check=True).stderr.strip().splitlines(),
        'classpath_libraries': [fingerprint(p) for p in jars[1:]],
        'probe_java_sources_sha256': {name: hashlib.sha256(source.encode()).hexdigest() for name, source in
                                    [('ReferenceMovementProbe', MOVEMENT_SOURCE), ('ReferenceDirectMovementProbe', DIRECT_SOURCE),
                                     ('ReferencePlayerMotionCurrentProbe', SOURCE)]},
        'source': source_inventory(jars),
        'scope': 'Actual untouched Player.travel/LivingEntity.travelInAir/Entity.move with an observed one-shot stuck multiplier in dry neutral SELF movement.',
        'confidence': 'high for recorded dry SELF stuck phase; no noPhysics, piston, liquid, hazard, flight or general server/client tick parity',
        'fixture_boundary': {
            'receiver': 'Normal FixturePlayer constructor delegates to actual Player/Avatar/LivingEntity; no travel, collide or movement algorithm replacement.',
            'setup': 'Original makeStuckInBlock(AIR, multiplier) sets the field before the initial snapshot and resets already-zero fall distance.',
            'observers_call_super': ['move', 'maybeBackOffFromEdge', 'moveRelative', 'getSpeed', 'getFlyingSpeed', 'getBlockPosBelowThatAffectsMyMovement', 'recordMovement'],
            'phase': 'maybeBackOffFromEdge entry records the real Entity.move request, body velocity and remaining multiplier after stuck consumption; return records unchanged actual Player edge hook result.',
            'world': 'Real sparse Level and BlockCollisions from existing direct fixture; all-air loaded LevelChunk sections are used only by dry fluid checks; stone full cubes and no actors.',
            'constant_return_overrides': {'gameMode': 'SURVIVAL', 'isClientAuthoritative': False, 'getMovementEmission': 'NONE', 'isSuppressingBounce': True},
            'admission': ['SELF', 'canSimulateMovement', 'local authoritative', 'noPhysics false', 'no passenger/swimming/flying/gliding/climbing/powder snow/effects/liquids', 'neutral edge input', 'unit block speed', 'suppressed restitution'],
            'expected': 'Final Body comes from the receiver after complete actual Player.travel; post_move_body is before inherited gravity/drag; no Bend value contributes to expected outcomes.',
        },
        'stuck_contract': {'threshold_f64_bits': THRESHOLD, 'test': 'lengthSqr strictly greater than threshold',
                           'length_order': '(x*x + y*y) + z*z', 'active_self_order': ['componentwise request multiply', 'stuck field positive ZERO', 'delta movement positive ZERO', 'actual edge backoff', 'actual collision', 'inherited gravity/drag']},
    }
    data['cases_sha256'] = sha(data['cases'])
    validation = validate(data, first)
    validate(data, second)
    failures = []
    for reseal in [False, True]:
        bad = copy.deepcopy(data)
        bad['cases'][0]['expected']['velocity'][0] = bits(123.)
        if reseal:
            bad['cases_sha256'] = sha(bad['cases'])
        try:
            validate(bad, first)
        except AssertionError:
            failures.append({'resealed': reseal, 'rejected': True})
        else:
            raise AssertionError('Corruption accepted')
    write_json(OUTPUT, data)
    evidence = {'schema_version': 1, 'status': 'passed', 'pin': '26.3', 'reference': fingerprint(OUTPUT),
                'validation': validation, 'independent_java_runs': 2, 'compile': compile_receipt,
                'runs': [run1, run2], 'failure_injections': failures,
                'generator': fingerprint(ROOT / 'tools/reference_player_motion_current_probe.py'),
                'reproduce': 'PYTHONDONTWRITEBYTECODE=1 python3 tools/reference_player_motion_current_probe.py'}
    write_json(EVIDENCE, evidence)
    return {k: evidence[k] for k in ['status', 'validation', 'independent_java_runs', 'failure_injections']}


def verify():
    jars, release = verified_classpath()
    data = json.loads(OUTPUT.read_text())
    assert data['server_bundle_sha256'] == release['server_bundle']['sha256']
    assert data['server_class_jar_sha256'] == release['server_bundle']['nested_server_sha256']
    assert data['runtime_executable'] == fingerprint(JAVA)
    assert data['classpath_libraries'] == [fingerprint(p) for p in jars[1:]]
    assert data['source'] == source_inventory(jars)
    assert data['probe_java_sources_sha256'] == {name: hashlib.sha256(source.encode()).hexdigest() for name, source in
                                               [('ReferenceMovementProbe', MOVEMENT_SOURCE), ('ReferenceDirectMovementProbe', DIRECT_SOURCE),
                                                ('ReferencePlayerMotionCurrentProbe', SOURCE)]}
    observations = [[json.loads(line) for line in (RAW / (label + '-observed.jsonl')).read_text().splitlines()]
                    for label in ['independent-1', 'independent-2']]
    assert observations[0] == observations[1]
    validation = validate(data, observations[0])
    evidence = {'schema_version': 1, 'status': 'passed', 'pin': '26.3', 'reference': fingerprint(OUTPUT),
                'validation': validation, 'official_source_runtime_libraries_checked': True,
                'independent_observations_checked': 2,
                'generator': fingerprint(ROOT / 'tools/reference_player_motion_current_probe.py'),
                'reproduce': 'PYTHONDONTWRITEBYTECODE=1 python3 tools/reference_player_motion_current_probe.py --verify-existing'}
    write_json(ROOT / 'evidence/player-motion-current-reference-validation.json', evidence)
    return evidence


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--verify-existing', action='store_true')
    args = parser.parse_args()
    print(json.dumps(verify() if args.verify_existing else extract(), indent=2))


if __name__ == '__main__':
    main()
