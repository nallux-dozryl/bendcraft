#!/usr/bin/env python3
"""Observe original pinned moving block traversal and Entity effect dispatch.

The Java fixture calls original BlockGetter traversal and Entity dispatcher
methods. Python supplies test worlds and trajectories, never expected traversal.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import math
import struct
import subprocess
import time
import zipfile

import reference_player_block_inside_stuck_probe as PRIOR
from reference_inventory import ROOT, JAVA, canonical, fingerprint, write_json
from reference_block_probe import verified_classpath

RAW = ROOT / 'build/player-block-inside-sweep/reference'
OUTPUT = ROOT / 'reference/player_block_inside_sweep.json'


def replace_once(source, old, new):
    assert source.count(old) == 1, ('source substitution drift', old[:100])
    return source.replace(old, new, 1)


SOURCE = PRIOR.SOURCE.replace('ReferencePlayerBlockInsideStuckProbe', 'ReferencePlayerBlockInsideSweepProbe')
SOURCE = replace_once(SOURCE, ' static Vec3 vec(JsonArray a)', r'''
 static final Field VISITED,COLLECTOR,LAST_STEP,QUEUED,FINAL_MOVEMENTS;
 static final Method MAKE_BOX,APPLY_LIST,APPLY_STORED;
 static final Constructor<?> MOVEMENT_TWO,MOVEMENT_THREE;
 static {try{
  VISITED=Entity.class.getDeclaredField("visitedBlocks");VISITED.setAccessible(true);
  COLLECTOR=Entity.class.getDeclaredField("insideEffectCollector");COLLECTOR.setAccessible(true);
  LAST_STEP=InsideBlockEffectApplier.StepBasedCollector.class.getDeclaredField("lastStep");LAST_STEP.setAccessible(true);
  QUEUED=Entity.class.getDeclaredField("movementThisTick");QUEUED.setAccessible(true);
  FINAL_MOVEMENTS=Entity.class.getDeclaredField("finalMovementsThisTick");FINAL_MOVEMENTS.setAccessible(true);
  MAKE_BOX=Entity.class.getDeclaredMethod("makeBoundingBox",Vec3.class);MAKE_BOX.setAccessible(true);
  APPLY_LIST=Entity.class.getDeclaredMethod("applyEffectsFromBlocks",List.class);APPLY_LIST.setAccessible(true);
  APPLY_STORED=Entity.class.getDeclaredMethod("applyEffectsFromBlocks");APPLY_STORED.setAccessible(true);
  Class<?> movement=Class.forName("net.minecraft.world.entity.Entity$Movement");
  MOVEMENT_TWO=movement.getDeclaredConstructor(Vec3.class,Vec3.class);MOVEMENT_TWO.setAccessible(true);
  MOVEMENT_THREE=movement.getDeclaredConstructor(Vec3.class,Vec3.class,Vec3.class);MOVEMENT_THREE.setAccessible(true);
 }catch(Exception e){throw new ExceptionInInitializerError(e);}}
 static AABB makeBox(Entity e,Vec3 p){try{return (AABB)MAKE_BOX.invoke(e,p);}catch(Exception x){throw new RuntimeException(x);}}
 static int collectorStep(Entity e){try{return LAST_STEP.getInt(COLLECTOR.get(e));}catch(Exception x){throw new RuntimeException(x);}}
 static it.unimi.dsi.fastutil.longs.LongSet visited(Entity e){try{return (it.unimi.dsi.fastutil.longs.LongSet)VISITED.get(e);}catch(Exception x){throw new RuntimeException(x);}}
 static Map<String,Object> movement(JsonObject request){Vec3 from=vec(request.getAsJsonArray("from")),to=vec(request.getAsJsonArray("to"));
  return Map.of("from",ReferenceMovementProbe.vectorBits(from),"to",ReferenceMovementProbe.vectorBits(to),"delta",ReferenceMovementProbe.vectorBits(to.subtract(from)),"delta_length_squared",bits(to.subtract(from).lengthSqr()),"axis_original",request.getAsJsonArray("axis_original"));}
 static Object actualMovement(JsonObject request)throws Exception{Vec3 from=vec(request.getAsJsonArray("from")),to=vec(request.getAsJsonArray("to"));JsonArray axis=request.getAsJsonArray("axis_original");return axis.isEmpty()?MOVEMENT_TWO.newInstance(from,to):MOVEMENT_THREE.newInstance(from,to,vec(axis));}
 static List<Map<String,Object>> movementRecords(Object sequence)throws Exception{List<Map<String,Object>> out=new ArrayList<>();
  for(Object value:(Iterable<?>)sequence){Class<?> type=value.getClass();Method f=type.getDeclaredMethod("from"),t=type.getDeclaredMethod("to"),a=type.getDeclaredMethod("axisDependentOriginalMovement");f.setAccessible(true);t.setAccessible(true);a.setAccessible(true);Optional<?> axis=(Optional<?>)a.invoke(value);Vec3 from=(Vec3)f.invoke(value),to=(Vec3)t.invoke(value);out.add(Map.of("from",ReferenceMovementProbe.vectorBits(from),"to",ReferenceMovementProbe.vectorBits(to),"delta",ReferenceMovementProbe.vectorBits(to.subtract(from)),"axis_original",axis.isPresent()?ReferenceMovementProbe.vectorBits((Vec3)axis.get()):List.of()));}return out;}
 static List<Integer> callbackPosition(Entity e){FixtureLevel l=(FixtureLevel)e.level();return l.insideReads.isEmpty()?List.of():((List<Integer>)l.insideReads.getLast().get("position"));}
 static Map<String,Object> callbackRecord(Entity e,BlockState s){return Map.of("state",state(s),"position",callbackPosition(e),"collector_step",collectorStep(e));}
 static Vec3 vec(JsonArray a)''')
SOURCE = replace_once(SOURCE, '  Map<String,Object> m=new TreeMap<>();m.put("body",ReferenceTravelProbe.body(e));',
                     '  Map<String,Object> m=new TreeMap<>();m.put("body",ReferenceTravelProbe.body(e));m.put("old_position",ReferenceMovementProbe.vectorBits(e.oldPosition()));m.put("known_movement",ReferenceMovementProbe.vectorBits(e.getKnownMovement()));m.put("old_minus_position",ReferenceMovementProbe.vectorBits(e.oldPosition().subtract(e.position())));m.put("client_authoritative",e.isClientAuthoritative());m.put("alive",e.isAlive());')
SOURCE = replace_once(SOURCE, '  final List<Map<String,Object>> insideReads=new ArrayList<>();',
                     '  final List<Map<String,Object>> insideReads=new ArrayList<>();Entity receiver;')
SOURCE = replace_once(SOURCE, '   if(inside)insideReads.add(Map.of("position",List.of(p.getX(),p.getY(),p.getZ()),"state",state(s)));return s;}',
                     '   if(inside)insideReads.add(Map.of("position",List.of(p.getX(),p.getY(),p.getZ()),"packed_position",Long.toUnsignedString(p.asLong()),"state",state(s),"collector_step_before",collectorStep(receiver),"entity_seen_before",visited(receiver).contains(p.asLong())));return s;}')
SOURCE = replace_once(SOURCE, '  FixturePlayer(Level l){super(l);}',
                     '  boolean clientAuthoritative;\n  FixturePlayer(Level l){super(l);}\n  public boolean isClientAuthoritative(){return clientAuthoritative;}')
assert SOURCE.count('callbacks.add(state(s));super.onInsideBlock(s);') == 2
SOURCE = SOURCE.replace('callbacks.add(state(s));super.onInsideBlock(s);', 'callbacks.add(callbackRecord(this,s));super.onInsideBlock(s);')
assert SOURCE.count('m.put("state",state(s));m.put("argument"') == 2
SOURCE = SOURCE.replace('m.put("state",state(s));m.put("argument"', 'm.put("state",state(s));m.put("position",callbackPosition(this));m.put("collector_step",collectorStep(this));m.put("argument"')
SOURCE = replace_once(SOURCE, 'value!=Blocks.COBWEB&&value!=Blocks.SWEET_BERRY_BUSH&&value!=Blocks.AIR&&value!=Blocks.STONE',
                     'value!=Blocks.COBWEB&&value!=Blocks.SWEET_BERRY_BUSH&&value!=Blocks.AIR&&value!=Blocks.CAVE_AIR&&value!=Blocks.VOID_AIR&&value!=Blocks.STONE&&value!=Blocks.DIRT')
SOURCE = replace_once(SOURCE, '  e.setPos(vec(in.getAsJsonArray("position")));e.setOnGround(false);',
                     '  level.receiver=e;e.setPos(vec(in.getAsJsonArray("position")));e.setOldPosAndRot(vec(in.getAsJsonArray("old_position")),0f,0f);e.setOnGround(false);if(!in.getAsJsonArray("current_box").isEmpty())e.setBoundingBox(ReferenceMovementProbe.box(in.getAsJsonArray("current_box")));')
SOURCE = replace_once(SOURCE, '  if(e instanceof Player p)p.getAbilities().flying=in.get("flying").getAsBoolean();',
                     '  if(e instanceof FixturePlayer p){p.getAbilities().flying=in.get("flying").getAsBoolean();p.clientAuthoritative=in.get("client_authoritative").getAsBoolean();if(!in.get("alive").getAsBoolean())p.setHealth(0f);}')
SOURCE = replace_once(SOURCE, '  Map<String,Object> initial=snapshot(e);List<Map<String,Object>> observations=new ArrayList<>();',
                     '  Map<String,Object> initial=snapshot(e);List<Map<String,Object>> observations=new ArrayList<>();int dispatchCalls=0,walkCalls=0,geometryCalls=0;')
start = SOURCE.index('   if(step.get("operation").getAsString().equals("callback"))')
end = SOURCE.index('   m.put("after",snapshot(e));', start)
SOURCE = SOURCE[:start] + r'''
   String operation=step.get("operation").getAsString();
   if(operation.equals("walk")){walkCalls++;
    JsonObject request=step.getAsJsonObject("movement");Vec3 from=vec(request.getAsJsonArray("from")),to=vec(request.getAsJsonArray("to"));
    AABB box=makeBox(e,to).deflate((double)1e-5f);List<Map<String,Object>> visits=new ArrayList<>();int stopStep=step.get("stop_step").getAsInt();
    boolean completed=BlockGetter.forEachBlockIntersectedBetween(from,to,box,(position,index)->{
     boolean accepted=stopStep<0||index<stopStep;visits.add(Map.of("position",List.of(position.getX(),position.getY(),position.getZ()),"packed_position",Long.toUnsignedString(position.asLong()),"step",index,"accepted",accepted));return accepted;});
    m.put("movement",movement(request));m.put("endpoint_box",ReferenceMovementProbe.boxBits(makeBox(e,to)));m.put("deflated_endpoint_box",ReferenceMovementProbe.boxBits(box));
    m.put("visits",visits);m.put("completed",completed);m.put("stop_step",stopStep);
   }else if(operation.equals("sweep")){dispatchCalls++;
    level.blocks.clear();for(JsonElement bValue:step.getAsJsonArray("world_blocks")){JsonObject b=bValue.getAsJsonObject();JsonArray p=b.getAsJsonArray("position");level.blocks.put(new BlockPos(p.get(0).getAsInt(),p.get(1).getAsInt(),p.get(2).getAsInt()),block(b));}
    List<Object> movements=new ArrayList<>();for(JsonElement request:step.getAsJsonArray("movements"))movements.add(actualMovement(request.getAsJsonObject()));
    m.put("movements",movementRecords(movements));m.put("entity_visited_before",visited(e).size());m.put("collector_step_before",collectorStep(e));
    String route=step.get("route").getAsString();
    if(route.equals("public")){if(movements.size()!=1||!step.getAsJsonArray("movements").get(0).getAsJsonObject().getAsJsonArray("axis_original").isEmpty())throw new AssertionError("Invalid public route");JsonObject request=step.getAsJsonArray("movements").get(0).getAsJsonObject();e.applyEffectsFromBlocks(vec(request.getAsJsonArray("from")),vec(request.getAsJsonArray("to")));}
    else if(route.equals("list"))APPLY_LIST.invoke(e,movements);
    else if(route.equals("stored")){ArrayDeque<Object> queue=(ArrayDeque<Object>)QUEUED.get(e);queue.addAll(movements);m.put("queued_before",movementRecords(queue));APPLY_STORED.invoke(e);m.put("queued_after",movementRecords(queue));m.put("final_movements",movementRecords(FINAL_MOVEMENTS.get(e)));}
    else throw new IllegalArgumentException("Unknown original dispatch route");
    m.put("entity_visited_after",visited(e).size());m.put("collector_step_after",collectorStep(e));
    m.put("entity_inside_shapes",level.insideReads.stream().filter(r->{List<?> p=(List<?>)r.get("position");BlockState value=level.blocks.get(new BlockPos((int)p.get(0),(int)p.get(1),(int)p.get(2)));return value!=null&&!value.isAir();}).map(r->{List<?> p=(List<?>)r.get("position");BlockPos pos=new BlockPos((int)p.get(0),(int)p.get(1),(int)p.get(2));return Map.of("position",r.get("position"),"shape",insideShape(level.blocks.get(pos),level,pos,e));}).toList());
   }else if(operation.equals("geometry")){geometryCalls++;
    JsonObject request=step.getAsJsonObject("movement");Vec3 from=vec(request.getAsJsonArray("from")),to=vec(request.getAsJsonArray("to"));List<AABB> targets=new ArrayList<>();for(JsonElement target:step.getAsJsonArray("targets"))targets.add(ReferenceMovementProbe.box(target.getAsJsonArray()));
    m.put("movement",movement(request));m.put("start_box",ReferenceMovementProbe.boxBits(makeBox(e,from)));m.put("collided",e.collidedWithShapeMovingFrom(from,to,targets));
    List<Object> clips=new ArrayList<>();for(AABB target:targets){Optional<Vec3> clipped=target.clip(from,to);clips.add(clipped.isPresent()?ReferenceMovementProbe.vectorBits(clipped.get()):List.of());}m.put("target_clips",clips);
   }else throw new IllegalArgumentException("Unknown operation");
''' + SOURCE[end:]
SOURCE = replace_once(SOURCE, '"original_callbacks_executed",true,', '"original_callbacks_unchanged",true,')
SOURCE = replace_once(SOURCE, '"level_is_serverlevel",false)', '"level_is_serverlevel",false,"original_entity_dispatch_calls",dispatchCalls,"original_blockgetter_capture_calls",walkCalls,"original_aabb_geometry_calls",geometryCalls)')

SOURCES = {
    'ReferenceMovementProbe': PRIOR.MOVEMENT_SOURCE,
    'ReferenceDirectMovementProbe': PRIOR.DIRECT_SOURCE,
    'ReferenceTravelProbe': PRIOR.TRAVEL_SOURCE,
    'ReferencePlayerBlockInsideSweepProbe': SOURCE,
}


def sha(value):
    return hashlib.sha256(canonical(value)).hexdigest()


def bits(value):
    return struct.pack('>d', value).hex()


def vec(values):
    return list(map(bits, values))


def movement(start, end, original=None):
    return {'from': vec(start), 'to': vec(end), 'axis_original': [] if original is None else vec(original)}


def block(name, position, age=3):
    out = {'identifier': 'minecraft:' + name, 'position': list(position)}
    if name == 'sweet_berry_bush':
        out['age'] = age
    return out


def sweep(movements, world, route='list'):
    return {'operation': 'sweep', 'movements': movements, 'world_blocks': world, 'route': route}


def walk(start, end, stop=-1):
    return {'operation': 'walk', 'movement': movement(start, end), 'stop_step': stop}


def grid(low, high):
    """Explicit finite test world; this does not calculate expected contacts."""
    out = []
    names = ['cobweb', 'sweet_berry_bush', 'stone', 'air']
    for z in range(low[2], high[2] + 1):
        for y in range(low[1], high[1] + 1):
            for x in range(low[0], high[0] + 1):
                out.append(block(names[(x + 2*y + 3*z) % 4], (x, y, z), (x-y+z) % 4))
    return out


def generate_inputs():
    cases = []

    def add(label, steps, tags, **changes):
        value = {'receiver': 'player', 'position': vec([.5, 1., .5]), 'old_position': vec([.25, .9, .75]),
                 'current_box': [], 'velocity': vec([.2, -.1, .3]), 'initial_multiplier': vec([.125, .25, .5]),
                 'fall_distance': bits(3.5), 'weaving': False, 'flying': False, 'boots': 'none',
                 'no_physics': False, 'removed': False, 'alive': True, 'client_authoritative': False,
                 'impulse': 'ready', 'steps': steps}
        value.update(changes)
        cases.append({'id': 'block-inside-sweep:' + label, 'input': value, 'tags': tags})

    start = [.5, 1., .5]
    directions = [(2.25, 0., 0.), (-2.25, 0., 0.), (0., 2.25, 0.), (0., -2.25, 0.),
                  (0., 0., 2.25), (0., 0., -2.25), (2.25, 0., 2.25), (-2.25, 0., -2.25),
                  (2.25, 2.25, 2.25), (-2.25, -2.25, -2.25), (2., .5, 3.), (3., -.5, 2.),
                  (-3., .5, 2.), (2., -.5, -3.), (.5, 3., 2.), (2., 3., .5)]
    for index, delta in enumerate(directions):
        for origin in [start, [-1., -1., -1.]]:
            end = [a+b for a, b in zip(origin, delta, strict=True)]
            add('walk-direction-' + str(index) + '-' + str(origin[0]), [walk(origin, end)], ['actual_blockgetter', 'axis_ties', 'negative_coordinates'])
        end = [a+b for a, b in zip(start, delta, strict=True)]
        world = grid([math.floor(min(a,b))-1 for a,b in zip(start,end,strict=True)],
                     [math.floor(max(a,b))+1 for a,b in zip(start,end,strict=True)])
        for route in ['public', 'list']:
            add('dispatch-direction-' + str(index) + '-' + route,
                [sweep([movement(start,end)], world, route)], ['actual_entity_dispatch', 'moving', 'query_order'], position=vec(end))

    eps = struct.unpack('>f', struct.pack('>f', 1e-5))[0]
    square_f32 = struct.unpack('>f', struct.pack('>f', eps*eps))[0]
    threshold = math.sqrt(square_f32)
    for index, value in enumerate([math.nextafter(threshold, -math.inf), threshold, math.nextafter(threshold, math.inf), eps, 0., -0.]):
        for origin in [[0., 0., 0.], [-1., 0., -1.]]:
            end = [origin[0]+value, origin[1], origin[2]]
            add('tiny-' + str(index) + '-' + str(origin[0]), [walk(origin,end), sweep([movement(origin,end)], [block('cobweb',(0,0,0)),block('sweet_berry_bush',(-1,0,-1))])], ['float_square_threshold', 'signed_zero', 'actual_blockgetter', 'actual_entity_dispatch'], position=vec(end))
    for index,(origin,end) in enumerate([([0.,0.,0.],[-0.,-0.,-0.]),([-0.,-0.,-0.],[0.,0.,0.]),([-0.,0.,-0.],[2.,-0.,0.])]):
        add('raw-signed-zero-'+str(index),[walk(origin,end),sweep([movement(origin,end)],grid((-1,0,-1),(2,1,0)))],['raw_signed_zero_delta','actual_blockgetter','actual_entity_dispatch'],position=vec(end))
    width = struct.unpack('>f', struct.pack('>f', .6))[0]
    plane = 1.-width/2.+eps
    for index, value in enumerate([math.nextafter(plane,-math.inf), plane, math.nextafter(plane,math.inf), -plane]):
        origin = [value, 1., .5]
        end = [value, 1., 2.5]
        add('plane-' + str(index), [walk(origin,end), sweep([movement(origin,end)],grid((-1,1,-1),(2,2,3)))], ['initial_final_plane_tangency'], position=vec(end))

    end = [3.5, 3., 2.5]
    world = grid((-1,0,-1),(4,4,3))
    for index, original in enumerate([(3.,2.,2.),(2.,2.,3.),(-2.,2.,-3.),(3.,0.,3.),(0.,0.,0.),(-0.,-0.,-0.)]):
        add('axis-dependent-' + str(index), [sweep([movement(start,end,original)], world)], ['axis_dependent', 'original_order_vs_actual_delta'], position=vec(end))
    for index, sequence in enumerate([[movement(start,end),movement(end,start)],
                                     [movement(start,end),movement(start,end)],
                                     [movement(start,end),movement(end,start),movement(start,end)],
                                     [movement(start,end,(1.,0.,2.)),movement(end,start,(2.,0.,1.))]]):
        add('movement-chain-' + str(index), [sweep(sequence,world),sweep(sequence,world)], ['list_dedup', 'read_repetition', 'dedup_cleared_between_dispatches'], position=vec(start))
    for distance in [15.,16.,17.,30.,-24.]:
        end = [.5+distance,1.,.5]
        world = [block('cobweb' if x%2==0 else 'sweet_berry_bush',(x,y,0)) for x in range(math.floor(min(.5,end[0]))-1,math.floor(max(.5,end[0]))+2) for y in [1,2]]
        add('step-limit-' + str(distance), [walk(start,end,16),sweep([movement(start,end)],world)], ['step_16', 'final_fallback'], position=vec(end))
    for original in [(1.,0.,2.),(2.,0.,1.)]:
        end = [20.5,3.,20.5]
        add('axis-budget-' + str(original), [sweep([movement(start,end,original)],grid((-1,0,-1),(21,4,21)))], ['axis_shared_step_allowance', 'final_fallback'], position=vec(end))
    for removed in [False,True]:
        for no_physics in [False,True]:
            add('gate-' + str(removed) + '-' + str(no_physics), [sweep([movement(start,[2.5,1.,.5])],grid((0,1,0),(2,2,0)))], ['affected_by_blocks_gate'],removed=removed,no_physics=no_physics)
    add('dead-player',[sweep([movement(start,[2.5,1.,.5])],grid((0,1,0),(2,2,0)))],['alive_visitor_gate'],alive=False)
    for flying,weaving,impulse in [(False,True,'ready'),(True,False,'ready'),(True,True,'grace'),(False,False,'grace')]:
        add('facts-' + str((flying,weaving,impulse)),[sweep([movement(start,[2.5,1.,.5])],grid((0,1,0),(2,2,0)))],['receiver_facts','impulse'],flying=flying,weaving=weaving,impulse=impulse)
    add('nonliving',[sweep([movement(start,[2.5,1.,.5])],grid((0,1,0),(2,2,0)))],['nonliving_berry_exclusion'],receiver='nonliving')
    add('authority-known-movement',[sweep([movement(start,[2.5,1.,.5])],grid((0,1,0),(2,2,0)))],['actual_known_movement_getter','bytecode_berry_source_boundary'],client_authoritative=True)
    add('custom-current-box',[walk(start,[2.5,1.,.5]),sweep([movement(start,[2.5,1.,.5])],grid((0,1,0),(2,2,0)))],['dimensions_not_current_box'],current_box=vec([10.,10.,10.,11.,11.,11.]))
    for offset,label in [(4096,'packed-y'),(1<<26,'packed-x')]:
        a=[.5,1.,.5];b=[.5,1.,.5];b[1 if label=='packed-y' else 0]+=offset
        pa=[0,1,0];pb=pa.copy();pb[1 if label=='packed-y' else 0]+=offset
        world=[block('cobweb',pa),block('sweet_berry_bush',pb)]
        for reverse in [False,True]:
            sequence=[movement(a,a),movement(b,b)];sequence.reverse() if reverse else None
            add(label+'-'+str(reverse),[sweep(sequence,world)],['packed_long_alias','entity_list_dedup'],position=vec(b))
    for label,sequence,pos in [('empty',[],start),('queued',[movement(start,[2.5,1.,.5],(2.,0.,0.))],[2.5,1.,.5]),('append',[movement(start,[2.5,1.,.5])],[3.5,1.,.5])]:
        add('stored-'+label,[sweep(sequence,grid((-1,0,-1),(4,3,1)),'stored')],['actual_movement_queue','oldposition_fallback','final_position_append'],position=vec(pos))

    origins=[[192145824,578455600,1247992560],[343086944,1893213456,2117633648]]
    collision_movements=[];collision_world=[]
    for index,origin in enumerate(origins):
        a=[origin[0]+.5,float(origin[1]),origin[2]+.5];b=[origin[0]+1.5,float(origin[1]),origin[2]+.5]
        collision_movements.append(movement(a,b));collision_world.extend(block('stone' if index==0 else 'dirt',(origin[0]+x,origin[1]+y,origin[2]+z)) for x in [0,1] for y in [0,1] for z in [0])
        add('collision-origin-'+str(index),[walk(a,b),sweep([movement(a,b)],collision_world.copy())],['actual_queried_collision_bucket','large_signed_i32'],position=vec(b))
    for reverse in [False,True]:
        add('collision-list-'+str(reverse),[sweep(list(reversed(collision_movements)) if reverse else collision_movements,collision_world)],['actual_queried_collision_buckets','entity_list'],position=collision_movements[-1]['to'])
    for index,(a,b,target) in enumerate([([0.,0.,0.],[2.,0.,0.],[1.,-1.,-1.,2.,1.,1.]),
                                      ([0.,0.,0.],[0.,0.,0.],[-1.,-1.,-1.,1.,1.,1.]),
                                      ([0.,0.,0.],[2.,2.,2.],[1.,1.,1.,2.,2.,2.]),
                                      ([0.,0.,0.],[-2.,-2.,-2.],[-2.,-2.,-2.,-1.,-1.,-1.]),
                                      ([0.,0.,0.],[2.,0.,0.],[1.,1.8,0.,2.,2.,1.]),
                                      ([0.,0.,0.],[2.,0.,0.],[1.,1.8000001,0.,2.,2.,1.])]):
        add('geometry-'+str(index),[{'operation':'geometry','movement':movement(a,b),'targets':[vec(target)]}],['actual_aabb_collided_along_vector','original_clip'])
    # Appended admission cases preserve every previously committed case ID.
    for air_name,other_air in [('cave_air','void_air'),('void_air','cave_air')]:
        a=[.5,1.,.5];b=[2.75,1.,.5]
        world=[block(air_name,(0,y,0)) for y in [1,2]]+[block(other_air,(1,y,0)) for y in [1,2]]+[block('cobweb',(2,1,0)),block('sweet_berry_bush',(2,2,0),3)]
        chain=[movement(a,b),movement(b,a),movement(a,b)]
        add('mixed-air-'+air_name,[sweep(chain,world),sweep(chain,world),sweep([movement(b,a)],world,'public')],['actual_is_air','mixed_air_states','repeated_dispatch','dispatch_wide_air_not_deduped'],position=vec(b))
        low=[.5,1.,.5];high=[.5,4097.,.5]
        aliases=[block(air_name,(0,1,0)),block('cobweb',(0,4097,0))]
        for reverse in [False,True]:
            pair=[movement(low,low),movement(high,high)];pair.reverse() if reverse else None
            add('air-alias-'+air_name+'-'+str(reverse),[sweep(pair,aliases),sweep(pair,aliases)],['actual_is_air','packed_long_alias','air_bypasses_entity_dedup','repeated_dispatch'],position=vec(high))
    return cases


OWNERS = ['net.minecraft.world.entity.Entity','net.minecraft.world.entity.Entity$Movement',
          'net.minecraft.world.level.BlockGetter','net.minecraft.core.BlockPos','net.minecraft.core.BlockPos$7',
          'net.minecraft.core.Direction','net.minecraft.world.phys.AABB','net.minecraft.world.phys.Vec3',
          'net.minecraft.world.entity.InsideBlockEffectApplier$StepBasedCollector',
          'net.minecraft.world.level.block.WebBlock','net.minecraft.world.level.block.SweetBerryBushBlock',
          'net.minecraft.world.entity.player.Player','net.minecraft.world.entity.LivingEntity']


def source_inventory(jars):
    out = {}; folder = RAW/'bytecode'; folder.mkdir(parents=True,exist_ok=True)
    with zipfile.ZipFile(jars[0]) as archive:
        for owner in OWNERS:
            result = subprocess.run([str(JAVA.parent/'javap'),'-classpath',str(jars[0]),'-c','-p',owner],capture_output=True,text=True,check=True)
            path=folder/(owner+'.txt');path.write_text(result.stdout)
            out[owner]={'class_sha256':hashlib.sha256(archive.read(owner.replace('.','/')+'.class')).hexdigest(),'complete_bytecode_text_sha256':hashlib.sha256(result.stdout.encode()).hexdigest(),'bytecode':fingerprint(path)}
    return out


def compile_java(jars):
    RAW.mkdir(parents=True,exist_ok=True);classes=RAW/'classes';classes.mkdir(exist_ok=True)
    paths=[]
    for name,source in SOURCES.items():
        path=RAW/(name+'.java');path.write_text(source);paths.append(path)
    command=[str(JAVA.parent/'javac'),'-cp',':'.join(map(str,jars)),'-d',str(classes),*map(str,paths)]
    started=time.monotonic();result=subprocess.run(command,capture_output=True,text=True);log=RAW/'javac.log';log.write_text(result.stdout+result.stderr)
    if result.returncode:raise RuntimeError('javac failed; diagnostics: '+str(log))
    return {'command':command,'seconds':round(time.monotonic()-started,6),'log':fingerprint(log)}


def run_java(inputs,jars,label):
    incoming=RAW/(label+'-input.jsonl');outgoing=RAW/(label+'-observed.jsonl');incoming.write_text(''.join(canonical(c).decode()+'\n' for c in inputs))
    command=[str(JAVA),'-Xmx1g','-cp',str(RAW/'classes')+':'+':'.join(map(str,jars)),'ReferencePlayerBlockInsideSweepProbe',str(incoming),str(outgoing)]
    started=time.monotonic();result=subprocess.run(command,capture_output=True,text=True);log=RAW/(label+'.log');log.write_text(result.stdout+result.stderr)
    if result.returncode:raise RuntimeError('Actual Java oracle failed; diagnostics: '+str(log))
    observations=[json.loads(line) for line in outgoing.read_text().splitlines()];assert [c['id'] for c in observations]==[c['id'] for c in inputs]
    return observations,{'command':command,'seconds':round(time.monotonic()-started,6),'log':fingerprint(log),'input':fingerprint(incoming),'observations':fingerprint(outgoing)}


def validate(data,observed=None):
    assert data['pin']=='26.3' and data['schema_version']==1 and data['cases_sha256']==sha(data['cases'])
    assert [{k:c[k] for k in ['id','input','tags']} for c in data['cases']]==generate_inputs()
    if observed is not None:assert [{k:c[k] for k in ['id','expected','observation']} for c in data['cases']]==observed
    counts={'walk':0,'sweep':0,'geometry':0};visits=reads=callbacks=0;stopped=0
    for case in data['cases']:
        assert case['observation']['normal_constructor'] and case['observation']['original_callbacks_unchanged']
        for operation,field in [('walk','original_blockgetter_capture_calls'),('sweep','original_entity_dispatch_calls'),('geometry','original_aabb_geometry_calls')]:
            assert case['observation'][field]==sum(s['operation']==operation for s in case['input']['steps'])
        for request,step in zip(case['input']['steps'],case['expected']['steps'],strict=True):
            counts[request['operation']]+=1;reads+=len(step['inside_reads']);callbacks+=len(step.get('callbacks',[]))
            if request['operation']=='walk':
                visits+=len(step['visits']);stopped+=not step['completed'];assert step['inside_reads']==[]
            if request['operation']=='sweep':
                assert all(shape['shape']['identity_block'] for shape in step['entity_inside_shapes'])
                if case['input']['removed'] or case['input']['no_physics'] or not case['input']['alive']:assert step['inside_reads']==[]
                assert step['entity_visited_after']==0 and step['collector_step_after']==-1
    assert all(counts.values()) and stopped and reads and callbacks
    return {'case_count':len(data['cases']),'step_count':sum(counts.values()),'operations':counts,'actual_walk_visits':visits,'actual_dispatch_reads':reads,'actual_callbacks':callbacks,'stopped_walks':stopped,'oracle_compared':observed is not None}


def corruption_controls(data,observed):
    rejected=[]
    for name in ['checksum','expected-unsealed','expected-resealed','input-resealed','visit-step-resealed','callback-position-resealed']:
        bad=copy.deepcopy(data)
        if name=='checksum':bad['cases_sha256']='0'*64
        elif name=='input-resealed':bad['cases'][0]['input']['weaving']=not bad['cases'][0]['input']['weaving']
        elif name=='visit-step-resealed':
            step=next(s for c in bad['cases'] for s in c['expected']['steps'] if s.get('visits'));step['visits'][0]['step']+=1
        elif name=='callback-position-resealed':
            step=next(s for c in bad['cases'] for s in c['expected']['steps'] if s.get('callbacks'));step['callbacks'][0]['position'][0]+=1
        else:bad['cases'][0]['expected']['final']['stuck_multiplier'][0]=bits(123.)
        if name.endswith('resealed'):bad['cases_sha256']=sha(bad['cases'])
        try:validate(bad,observed)
        except AssertionError:rejected.append(name)
        else:raise AssertionError('Corrupt oracle accepted: '+name)
    return rejected


def extract():
    jars,release=verified_classpath();inputs=generate_inputs();compiled=compile_java(jars)
    first,one=run_java(inputs,jars,'independent-1');second,two=run_java(inputs,jars,'independent-2');assert first==second
    data={'schema_version':1,'pin':'26.3','cases':[{**i,**o} for i,o in zip(inputs,first,strict=True)],
          'server_bundle_sha256':release['server_bundle']['sha256'],'server_class_jar_sha256':release['server_bundle']['nested_server_sha256'],
          'runtime_executable':fingerprint(JAVA),'classpath_libraries':[fingerprint(p) for p in jars[1:]],
          'probe_java_sources_sha256':{name:hashlib.sha256(source.encode()).hexdigest() for name,source in SOURCES.items()},'source':source_inventory(jars),
          'scope':'Original BlockGetter swept traversal and original Entity moving effect dispatcher with normally constructed receivers.',
          'confidence':'high for the recorded traversal, list/axis/fallback/dedup and web/berry receiver branches',
          'fixture_boundary':{'normal_receivers':'Original Player/Entity constructors through unchanged historical fixture helpers; no Unsafe or replacement traversal/callback implementation.',
            'entry_points':['Original BlockGetter.forEachBlockIntersectedBetween with a recording visitor','Original Entity.applyEffectsFromBlocks(from,to)','Original private Entity.applyEffectsFromBlocks(List) via reflection','Original protected Entity.applyEffectsFromBlocks() with original constructed movement queue entries'],
            'observers_call_super':['makeStuckInBlock','onInsideBlock','tryResetCurrentImpulseContext','resetCurrentImpulseContext','FixtureLevel.getBlockState'],
            'step_visibility':'Static original BlockGetter recording visitor observes exact candidate step. Actual Entity read observer records collector step before read; actual callback observes collector.lastStep after original advanceStep. No guessed local lambda step is assigned to receiver reads.',
            'world':'Sparse real Level with original registry states and empty fluids; all selected non-air inside shapes are identity Shapes.block.',
            'authority':'FixturePlayer.isClientAuthoritative returns explicit input as the historical abstract fixture admission. getKnownMovement and oldPosition/Vec3 subtraction execute original methods and are recorded.',
            'berry_source':'Pinned bytecode establishes client authoritative knownMovement versus oldPosition-position only after ServerLevel/age guard. Plain Level never executes that guarded damage source branch.',
            'expected':'All expected traversal positions, step indices, raw movement/body/multiplier/fall/impulse and callbacks come from fresh original Java observations; Python only assembles trajectories/worlds.',
            'unmeasured':['Actual ServerLevel berry damage','fluid callbacks','arbitrary non-full entity-inside shapes','whole player tick integration']}}
    data['cases_sha256']=sha(data['cases']);validation=validate(data,first);validate(data,second);controls=corruption_controls(data,first)
    write_json(OUTPUT,data)
    evidence={'schema_version':1,'status':'passed','pin':'26.3','reference':fingerprint(OUTPUT),'validation':validation,'independent_java_runs':2,'compile':compiled,'runs':[one,two],'reference_corruptions_rejected':controls,'generator':fingerprint(ROOT/'tools/reference_player_block_inside_sweep_probe.py'),'reproduce':'PYTHONDONTWRITEBYTECODE=1 python3 tools/reference_player_block_inside_sweep_probe.py'}
    write_json(ROOT/'evidence/player-block-inside-sweep-reference.json',evidence)
    return {k:evidence[k] for k in ['status','validation','independent_java_runs','reference_corruptions_rejected']}


def verify():
    jars,release=verified_classpath();data=json.loads(OUTPUT.read_text())
    assert data['server_bundle_sha256']==release['server_bundle']['sha256'] and data['server_class_jar_sha256']==release['server_bundle']['nested_server_sha256']
    assert data['runtime_executable']==fingerprint(JAVA) and data['classpath_libraries']==[fingerprint(p) for p in jars[1:]]
    assert data['source']==source_inventory(jars) and data['probe_java_sources_sha256']=={name:hashlib.sha256(source.encode()).hexdigest() for name,source in SOURCES.items()}
    extraction=json.loads((ROOT/'evidence/player-block-inside-sweep-reference.json').read_text());assert fingerprint(OUTPUT)==extraction['reference']
    observations=[]
    for run in extraction['runs']:
        path=RAW/run['observations']['file'];assert fingerprint(path)==run['observations'];observations.append([json.loads(line) for line in path.read_text().splitlines()]);validate(data,observations[-1])
    assert len(observations)==2 and observations[0]==observations[1]
    evidence={'schema_version':1,'status':'passed','pin':'26.3','reference':fingerprint(OUTPUT),'validation':validate(data,observations[0]),'official_source_runtime_libraries_checked':True,'independent_observations_checked':2,'reference_corruptions_rejected':corruption_controls(data,observations[0]),'generator':fingerprint(ROOT/'tools/reference_player_block_inside_sweep_probe.py'),'reproduce':'PYTHONDONTWRITEBYTECODE=1 python3 tools/reference_player_block_inside_sweep_probe.py --verify-existing'}
    write_json(ROOT/'evidence/player-block-inside-sweep-reference-validation.json',evidence);return evidence


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--verify-existing',action='store_true');args=parser.parse_args()
    try:print(json.dumps(verify() if args.verify_existing else extract(),indent=2))
    except BaseException as error:
        failure={'schema_version':1,'status':'failed','error':repr(error),'generator':fingerprint(ROOT/'tools/reference_player_block_inside_sweep_probe.py'),'raw_folder':str(RAW),'scope':'Original Java reference extraction only; no Bend/native compilation.'}
        number=1
        while (ROOT/f'evidence/player-block-inside-sweep-reference-failure-{number:03d}.json').exists():number+=1
        write_json(ROOT/f'evidence/player-block-inside-sweep-reference-failure-{number:03d}.json',failure);raise


if __name__=='__main__':main()
