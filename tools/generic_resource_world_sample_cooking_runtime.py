#!/usr/bin/env python3
"""Private callback-driven Generic cooking caller test; preparation is file-only.

The optional native modes use a copy of an explicitly completed Generic C file.
Only the event callback pump and hidden virtual focus/capture are injected. Bend
gameplay, menu, wire, resource, CPU drawing and Window.frame bodies stay exact.
This is synthetic native callback acceptance, never foreground OS input.
"""
from __future__ import annotations

import argparse
import copy
import json
import os
import shutil
import sys
import time
from pathlib import Path
from unittest import mock

PYTHON = Path.home()/'.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3'
if Path(sys.executable).resolve() != PYTHON.resolve():
    os.execv(str(PYTHON), [str(PYTHON), '-B', __file__, *sys.argv[1:]])
sys.dont_write_bytecode = True

import generic_resource_world_sample_client_runtime as G
import test_playable_client_cooking_publication as Pub
import test_play_minecraft_cooking_close as Close
import test_world_generation_settings as Generation

ROOT, R, S, Host, Pair = G.ROOT, G.R, G.S, G.Host, G.Pair
B, A, Menu = Pub.B, Pub.A, Pub.Menu
require, pin = G.require, G.pin
PREFIX = 'generic-resource-world-sample-cooking-runtime'
POINT = ('minecraft:overworld', 12, 8, 12)
# The unchanged interactive open uses960x540. Native.configure intentionally
# does not resize a hidden window; use that real geometry without another seam.
WIDTH, HEIGHT = 960, 540
INPUT_ENV = 'MC_PRIVATE_COOKING_CALLBACK_INBOX'
ACK_ENV = 'MC_PRIVATE_COOKING_CALLBACK_ACK'

# The declaration is inserted before the unchanged Objective-C Window.frame.
# Implementation appears after the actual project view's implementation.
DECLARATION = r'''
// PRIVATE TEST SEAM: no OS focus, cursor warp/hide or event posting.
static BOOL mc_cooking_callback_test(void) {
  const char* inbox = getenv("MC_PRIVATE_COOKING_CALLBACK_INBOX");
  const char* mode = getenv("BEND_MINECRAFT_LAUNCH_MODE");
  return inbox && *inbox && mode && strcmp(mode,"hidden") == 0;
}
static void mc_cooking_callback_frame(NSWindow* win);
'''

CALLBACK_SOURCE = r'''
// Native NSEvent's factory does not establish a right-button payload in the
// retained boundary fixture. This private local event supplies the declared
// content/window coordinates and button to the unchanged real callbacks.
@interface MCCookingCallbackMouse : NSEvent {
  NSPoint localPoint;
  NSInteger localButton;
  NSEventType localType;
}
- (instancetype)initAt:(NSPoint)point button:(NSInteger)button type:(NSEventType)type;
@end
@implementation MCCookingCallbackMouse
- (instancetype)initAt:(NSPoint)point button:(NSInteger)button type:(NSEventType)type {
  self = [super init];
  if (self) { localPoint=point; localButton=button; localType=type; }
  return self;
}
- (NSPoint)locationInWindow { return localPoint; }
- (NSInteger)buttonNumber { return localButton; }
- (NSEventType)type { return localType; }
@end

static void mc_cooking_callback_frame(NSWindow* win) {
  static unsigned long long lastToken = 0;
  static unsigned long long frame = 0;
  frame += 1;
  if (!mc_cooking_callback_test()) return;
  if (![win.contentView isKindOfClass:MCPlayerPresentationView.class])
    err_fail("private cooking callback: actual project view missing");
  NSString* inbox = [NSString stringWithUTF8String:getenv("MC_PRIVATE_COOKING_CALLBACK_INBOX")];
  NSData* bytes = [NSData dataWithContentsOfFile:inbox];
  if (!bytes) return;
  NSError* error = nil;
  id parsed = [NSJSONSerialization JSONObjectWithData:bytes options:0 error:&error];
  if (error || ![parsed isKindOfClass:NSDictionary.class])
    err_fail("private cooking callback: malformed inbox");
  NSDictionary* batch = parsed;
  unsigned long long token = [batch[@"token"] unsignedLongLongValue];
  if (token <= lastToken) return;
  if (token != lastToken + 1 || ![batch[@"events"] isKindOfClass:NSArray.class])
    err_fail("private cooking callback: nonsequential batch");
  MCPlayerPresentationView* view = (MCPlayerPresentationView*)win.contentView;
  NSUInteger before = view->evs.length;
  for (NSDictionary* event in batch[@"events"]) {
    NSString* kind = event[@"kind"];
    BOOL down = [event[@"down"] boolValue];
    if ([kind isEqualToString:@"mouse"]) {
      NSInteger button = [event[@"button"] integerValue];
      if (button != 0 && button != 1) err_fail("private cooking callback: button");
      NSPoint point = [view convertPoint:NSMakePoint([event[@"x"] doubleValue],
        [event[@"y"] doubleValue]) toView:nil];
      NSEventType type = button == 0 ? (down ? NSEventTypeLeftMouseDown : NSEventTypeLeftMouseUp)
        : (down ? NSEventTypeRightMouseDown : NSEventTypeRightMouseUp);
      NSEvent* value = [[MCCookingCallbackMouse alloc] initAt:point button:button type:type];
      if (button == 0) { if (down) [view mouseDown:value]; else [view mouseUp:value]; }
      else { if (down) [view rightMouseDown:value]; else [view rightMouseUp:value]; }
    } else if ([kind isEqualToString:@"key"]) {
      NSString* text = event[@"text"];
      NSEvent* value = [NSEvent keyEventWithType:down ? NSEventTypeKeyDown : NSEventTypeKeyUp
        location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:win.windowNumber
        context:nil characters:text charactersIgnoringModifiers:text isARepeat:NO
        keyCode:[event[@"physical"] unsignedShortValue]];
      if (down) [view keyDown:value]; else [view keyUp:value];
    } else if ([kind isEqualToString:@"close"]) {
      if ([view windowShouldClose:win]) err_fail("private cooking callback: close bypass");
    } else err_fail("private cooking callback: unknown kind");
  }
  const u32* words = view->evs.bytes;
  NSMutableArray* queued = [NSMutableArray new];
  for (NSUInteger offset = before / sizeof(u32); offset < view->evs.length / sizeof(u32); offset++)
    [queued addObject:@(words[offset])];
  NSDictionary* receipt = @{@"token":@(token),@"frame":@(frame),
    @"virtual_focus":@YES,@"virtual_capture":@(view->grab),
    @"point_width":@(view.bounds.size.width),@"point_height":@(view.bounds.size.height),
    @"queue_words":queued,@"events":batch[@"events"],@"scope":@"private local callbacks"};
  NSData* ack = [NSJSONSerialization dataWithJSONObject:receipt options:0 error:&error];
  const char* target = getenv("MC_PRIVATE_COOKING_CALLBACK_ACK");
  if (!target || !ack || ![ack writeToFile:[NSString stringWithUTF8String:target]
    options:NSDataWritingAtomic error:&error]) err_fail("private cooking callback: acknowledgement");
  lastToken = token;
}
'''


def replace_once(text, old, new, label):
    require(text.count(old) == 1, 'Private callback transform requires exactly one ' + label)
    return text.replace(old, new, 1)


def transformed(source):
    text = source.read_text()
    edits = []
    old = '  const char* got = io_nul(name, n) ? NULL : getenv(name);\n  free(name);'
    new = r'''  const char* got = io_nul(name, n) ? NULL : getenv(name);
  // PRIVATE TEST SEAM: only the unchanged Bend entry's interactive mode read.
  // Native code still reads the actual hidden process environment directly.
  const char* callback = getenv("MC_PRIVATE_COOKING_CALLBACK_INBOX");
  const char* native_mode = getenv("BEND_MINECRAFT_LAUNCH_MODE");
  if (callback && *callback && native_mode && strcmp(native_mode,"hidden") == 0
      && n == sizeof("BEND_MINECRAFT_LAUNCH_MODE") - 1
      && memcmp(name,"BEND_MINECRAFT_LAUNCH_MODE",n) == 0) {
    got = "human";
    const char* target = getenv("MC_PRIVATE_COOKING_MODE_RECEIPT");
    if (!target) err_fail("private cooking mode: missing receipt");
    FILE* receipt = fopen(target,"a");
    if (!receipt) err_fail("private cooking mode: receipt open");
    fputs("{\"effect\":\"CID_IO_GET_ENV\",\"query\":\"BEND_MINECRAFT_LAUNCH_MODE\",\"returned\":\"human\",\"native_environment\":\"hidden\"}\n",receipt);
    if (fclose(receipt) != 0) err_fail("private cooking mode: receipt close");
  }
  free(name);'''
    text = replace_once(text, old, new, 'exact IO.get_env queried mode boundary')
    edits.append('Only queried BEND_MINECRAFT_LAUNCH_MODE returns human under explicit hidden callback marker; all other effect/env reads exact')
    header = 'static Term window_frame(Env e, intptr_t at, Term image) {\n  NSView*'
    text = replace_once(text, header, DECLARATION + '\n' + header, 'Objective-C frame declaration')
    edits.append('Private declaration before the actual Objective-C Window.frame')
    old = '  window_show(e, (CAMetalLayer*)view.layer, image);\n  Term list = window_list(e, evs.bytes, evs.length / 20);'
    text = replace_once(text, old, '  window_show(e, (CAMetalLayer*)view.layer, image);\n  mc_cooking_callback_frame((__bridge NSWindow*)(void*)at);\n  Term list = window_list(e, evs.bytes, evs.length / 20);', 'actual frame callback boundary')
    edits.append('After original window_show, before unchanged window_list/queue clearing')
    old = '- (void)setGrab:(BOOL)on {\n  // An inactive application may still have a key window.'
    new = '- (void)setGrab:(BOOL)on {\n  if (mc_cooking_callback_test()) {\n    BOOL previous = grab;\n    grab = on;\n    if (previous && !grab) [self releaseKeys];\n    return;\n  }\n  // An inactive application may still have a key window.'
    text = replace_once(text, old, new, 'project capture method')
    edits.append('Test-only virtual grab branch; no Base cursor effects; real releaseKeys retained')
    old = '  captured = focused && [[win.contentView valueForKey:@"grab"] boolValue];\n#endif\n  Term focus'
    new = '  captured = focused && [[win.contentView valueForKey:@"grab"] boolValue];\n  if (mc_cooking_callback_test()) {\n    focused = true;\n    captured = [[win.contentView valueForKey:@"grab"] boolValue];\n  }\n#endif\n  Term focus'
    text = replace_once(text, old, new, 'actual Native.status observation')
    edits.append('Test-only focused=True/captured=virtual grab, within actual Native.status')
    marker = 'static Term mc_window_input_status_run(Env e, Term* f, IoWork* w) {'
    text = replace_once(text, marker, CALLBACK_SOURCE + '\n' + marker, 'callback implementation placement')
    edits.append('Local callback implementation after actual MCPlayerPresentationView declaration')
    return text, {'edits': edits, 'event_callback_source_sha256': G.digest(CALLBACK_SOURCE.encode()),
                  'declaration_sha256': G.digest(DECLARATION.encode()), 'production_Bend_edits': 0,
                  'production_Native_edits': 0, 'original_C_edits': 0,
                  'interactive_mode_read': {'effect': 'CID_IO_GET_ENV',
                       'query': 'BEND_MINECRAFT_LAUNCH_MODE', 'returned': 'human',
                       'actual_native_environment': 'hidden', 'other_queries_changed': False},
                  'original_window_show_list_and_drawing_retained': True,
                  'scope': 'Synthetic local NSEvent callbacks and virtual focus/capture only; no OS event posting, focus, capture, cursor or input-latency claim.'}


def complete_parse(data):
    # The existing publication helper's default parse assumes its two-section
    # fixture. This caller retains104 sections and uses its existing explicit
    # complete-envelope bound; no gameplay/codec implementation is replaced.
    return S.N.Reader(data, max_bytes=33624064, max_depth=16,
                      max_elements=33624064).root()


def publication_bundle(*args):
    with Host.bindings(S.N, {'parse': complete_parse}):
        return Pub.bundle(*args)


def publication_projection(data, facts):
    with Host.bindings(S.N, {'parse': complete_parse}):
        return Pub.projection(data, facts)


def fixture():
    facts = Pub.C19.independent_expectations()
    palette = facts['palette']
    world = S.WC.empty_world(facts['count'], facts['identity'])
    air = (palette['minecraft:air'],) * 4096
    ground = tuple(palette['minecraft:' + name] for name in ('stone', 'dirt', 'dirt', 'stone')
                   for _ in range(256)) + air[:3072]
    world['sections'] = [{'key': S.BASE.section_key(x, y, z), 'cells': ground if y == -64 else air}
                         for x in (0, 16) for y in range(-80, 336, 16) for z in (-16, 0)]
    world['sections'].sort(key=lambda row: row['key'])
    world['revision'] = 1
    world['daylight'] = False
    world['max_peer'] = None
    for x in range(0, 32):
        for z in range(-16, 16):
            S.BASE.set_block(world, x, 7, z, palette['minecraft:stone'])
    S.BASE.set_block(world, *POINT[1:], facts['unlit'])
    record = A.playable_look(A.playable_spawn((12.5, 8., 10.5)), 30.)
    _, full = B.Inventory.parse_inventory_full(B.FULL_FIXTURE.read_bytes())
    full = copy.deepcopy(full)
    full['main'].update(selected=2, slots=[None] * 36,
                        abilities={'instabuild': True, 'maybuild': True})
    full['main']['slots'][:2] = [B.stack('minecraft:beef', 2), B.stack('minecraft:coal', 2)]
    full['equipment'] = [None] * 7
    full['status'] = dict(zip(B.Inventory.STATUS_FIELDS,
                            (True, True, False, 1036831949, 1028443341), strict=True))
    full['generation'] = Generation.stone_dirt_bytes(seed=0)
    body = Pub.physical(facts, [None] * 3, total=0, lit_total=0)
    counters = Pub.map_tree([(Pub.J.words('/'.join((POINT[0], *map(str, POINT[1:])))), 3),
                             (Pub.J.words(Pub.REMOVED), 9)])
    publication = Pub.J.encode_publication(counters, 0, (), None, Pub.catalog())
    payload = publication_bundle(world, 40, record, full, ((POINT, body),), (), None, (), publication)
    actual = publication_projection(payload, facts)
    require(actual['world'] == world and actual['player'] == S.local_bytes(record)
            and actual['full'] == full and actual['bodies'] == ((POINT, body),)
            and actual['publication']['incarnations'] == counters and len(world['sections']) == 104,
            'Independent authentic full104/format4 fixture reconstruction')
    sample = G.expected_sample(world, record)
    require(len(sample[5]) == 512 and facts['unlit'] in {cell[4] for cell in sample[5]},
            'Actual aimed furnace appears in complete Generic aperture')
    return {'facts': facts, 'world': world, 'record': record, 'full': full,
            'payload': payload, 'body': body, 'sample': sample, 'counters': counters}


def events():
    left, top = (WIDTH - 176)//2, (HEIGHT - 166)//2
    def click(x, y, button=0):
        return [{'kind': 'mouse', 'x': x, 'y': y, 'button': button, 'down': down}
                for down in (True, False)]
    return [('use-ray', click(WIDTH//2, HEIGHT//2, 1)),
            ('pick-beef', click(left+16, top+150)),
            ('put-input', click(left+64, top+25)),
            ('pick-coal', click(left+34, top+150)),
            ('put-fuel', click(left+64, top+61)),
            ('pick-output', click(left+124, top+43)),
            ('put-main2', click(left+52, top+150)),
            ('close-cooking', [{'kind': 'key', 'physical': 14, 'text': 'e', 'down': down}
                               for down in (True, False)]),
            ('close-window', [{'kind': 'close'}])]


def prepare(directory, client_generation, donor_generation):
    directory.mkdir(parents=True, exist_ok=False)
    client = ROOT/f'build/generic-resource-world-sample-client-native/{client_generation:03d}'
    donor = ROOT/f'build/generic-resource-world-sample-client-native/{donor_generation:03d}'
    source = donor/'renderer.c'
    text, transform = transformed(source)
    target = directory/'renderer-callback.c'
    target.write_text(text)
    data = fixture()
    (directory/'seed.nbt').write_bytes(data['payload'])
    G.exclusive(directory/'events.json', events())
    G.exclusive(directory/'expected-sample.json', data['sample'])
    original_observer = Pair.observer()['observer']
    observer_source = Path(original_observer['source']).read_text()
    observer_source = replace_once(observer_source,
        'while process.isRunning && Date().timeIntervalSince(start) < 60 {',
        'while process.isRunning && Date().timeIntervalSince(start) < 120 {', 'only observer runtime cap')
    (directory/'observer.swift').write_text(observer_source)
    ready = {'status': 'prepared_native_unexecuted', 'client_generation': client_generation,
             'donor_generation': donor_generation, 'donor_C': pin(source),
             'donor_build': pin(donor/'build.json'), 'candidate_C': pin(target),
             'client_frozen_sources': pin(client/'private/source-map.json'),
             'native_same_generation_required': client_generation == donor_generation,
             'transform': transform, 'seed': pin(directory/'seed.nbt'),
             'events': pin(directory/'events.json'), 'helper': pin(Path(__file__)),
             'observer': {'original': original_observer, 'source': pin(directory/'observer.swift'),
                          'runtime_cap_seconds': 120, 'only_source_delta': 'Runtime cap60→120; no other observer behavior changes'},
             'runtime_inputs': Pub.runtime_pins(), 'registry': pin(G.REGISTRY),
             'fixture': {'position': list(POINT), 'feet': [12.5, 8, 10.5],
                         'look_degrees': [0, 30], 'full43': True, 'sections': 104,
                         'body_speed_bits': 1065353216, 'main0': 'minecraft:beef*2',
                         'main1': 'minecraft:coal*2', 'selected': 2,
                         'incarnation': 3, 'initial_registry_state': data['facts']['unlit'],
                         'render_extent': [WIDTH, HEIGHT], 'HUD_scale': 1},
             'expected_checkpoints': {'placed': [0, 0, 0, 200],
                                     '1': [1600, 1600, 1, 200],
                                     '100': [1501, 1600, 100, 200],
                                     '200': [1401, 1600, 0, 200],
                                     '300': [1301, 1600, 100, 200],
                                     '400': [1201, 1600, 0, 200]},
             'scope': 'Preparation only. Backend/menu state is never injected; first open must be CookingUse ray. Production011 ordinary compatibility is separate. Callback test uses real CPU images/Window.frame, no drawable/GPU/full vanilla frame/OS input proof.'}
    G.exclusive(directory/'prepared.json', ready)
    return ready


def admitted(directory):
    ready = json.loads((directory/'prepared.json').read_bytes())
    for key in ('donor_C', 'donor_build', 'candidate_C', 'client_frozen_sources', 'seed', 'events', 'helper'):
        require(ready[key] == pin(ready[key]['path']), 'Private callback prepared drift: ' + key)
    require(ready['client_generation'] == ready['donor_generation'],
            'Native caller must use its own completed C, not the10 declaration preparation donor')
    original = Path(ready['donor_C']['path']).parent/'renderer'
    G.client_artifact(original)
    return ready


def build_hook(directory):
    ready = admitted(directory)
    build = json.loads(Path(ready['donor_build']['path']).read_bytes())
    command = list(build['native']['command'])
    require('-O3' in command and '-fno-stack-check' in command,
            'Exact admitted production12 native flags must retain O3/fno-stack-check')
    old = ready['donor_C']['path']
    require(command.count(old) == 1 and command.count('-o') == 1, 'Actual immutable clang command shape')
    command[command.index(old)] = str(directory/'renderer-callback.c')
    command[command.index('-o') + 1] = str(directory/'renderer-callback')
    with Host.bindings(R, {'WORK': directory}):
        result = R.bounded(command, 300, 'callback-native-build')
    receipt = {'status': 'built_native_unexecuted' if result['exit_code'] == 0 and not result['timed_out'] else 'FAIL',
               'prepared': pin(directory/'prepared.json'), 'process': result,
               'candidate_C': pin(directory/'renderer-callback.c'), 'command': command,
               'original_C_unchanged': pin(old) == ready['donor_C'],
               'binary': pin(directory/'renderer-callback') if (directory/'renderer-callback').exists() else None}
    G.exclusive(directory/'callback-build.json', receipt)
    R.process_ok(result)
    return receipt


def reuse_hook(directory, previous):
    ready = admitted(directory)
    prior = json.loads((previous/'callback-build.json').read_bytes())
    require(prior['status'] == 'built_native_unexecuted'
            and prior['binary'] == pin(prior['binary']['path'])
            and prior['candidate_C'] == pin(prior['candidate_C']['path']), 'Retained real callback artifact')
    require(prior['candidate_C']['sha256'] == ready['candidate_C']['sha256']
            and json.loads((previous/'prepared.json').read_bytes())['donor_C'] == ready['donor_C'],
            'Host-only rerun must preserve exact completed C/transform/production generation')
    target = directory/'renderer-callback'
    require(not target.exists(), 'No replacement of an existing private artifact')
    shutil.copy2(prior['binary']['path'], target)
    receipt = {**prior, 'binary': pin(target), 'candidate_C': ready['candidate_C'],
               'prepared': pin(directory/'prepared.json'),
               'unchanged_native_artifact_reuse': {'build': pin(previous/'callback-build.json'),
                   'original_binary': prior['binary'], 'same_binary_sha256': pin(target)['sha256'],
                   'new_compiler_or_emitter_processes': 0,
                   'reason': 'Host-only observer/driver repair; byte-identical C and binary retained.'}}
    G.exclusive(directory/'callback-build.json', receipt)
    observer_receipt = previous/'observer-build.json'
    if observer_receipt.exists():
        observer = json.loads(observer_receipt.read_bytes())
        require(observer['status'] == 'PASS' and observer['runtime_cap_seconds'] == 120
                and observer['source'] == pin(observer['source']['path'])
                and observer['binary'] == pin(observer['binary']['path'])
                and observer['source']['sha256'] == pin(directory/'observer.swift')['sha256'],
                'Reuse only the exact completed private120s observer')
        shutil.copy2(observer['binary']['path'], directory/'observer')
        G.exclusive(directory/'observer-build.json', {**observer,
            'source': pin(directory/'observer.swift'), 'binary': pin(directory/'observer'),
            'unchanged_native_artifact_reuse': {'build': pin(observer_receipt),
                'original_binary': observer['binary'], 'new_compiler_processes': 0}})
    return receipt


def build_observer(directory):
    ready = admitted(directory)
    original = ready['observer']['original']
    require(pin(original['source'])['sha256'] == original['source_sha256'], 'Original observer source unchanged')
    command = json.loads(Path(original['build_receipt']['path']).read_bytes())['command']
    command = [str(directory/'observer.swift') if word == original['source'] else
               str(directory/'observer') if word == original['artifact'] else word for word in command]
    require(command == ['/usr/bin/swiftc', '-O', str(directory/'observer.swift'), '-o', str(directory/'observer')],
            'Exact retained observer compiler/flags; only private paths')
    with Host.bindings(R, {'WORK': directory}):
        result = R.bounded(command, 120, 'observer-build')
    receipt = {'status': 'PASS' if result['exit_code'] == 0 and not result['timed_out'] else 'FAIL',
               'source': pin(directory/'observer.swift'), 'process': result,
               'runtime_cap_seconds': 120, 'binary': pin(directory/'observer') if (directory/'observer').exists() else None}
    G.exclusive(directory/'observer-build.json', receipt)
    R.process_ok(result)
    return receipt


class CallbackRenderer(R.Renderer):
    def __init__(self, binary, relay, helpers, directory):
        original = R.subprocess.Popen
        def launch(argv, *args, **kwargs):
            require(argv[:2] == [helpers['observer']['artifact'], str(binary)], 'Existing real observer route')
            kwargs['env'] = dict(kwargs['env'], BEND_MINECRAFT_REGISTRY=str(G.REGISTRY),
                                 **{INPUT_ENV: str(directory/'callback-inbox.json'),
                                    ACK_ENV: str(directory/'callback-ack.json'),
                                    'MC_PRIVATE_COOKING_MODE_RECEIPT': str(directory/'mode-read.jsonl')})
            return original([*argv, '--width', str(WIDTH), '--height', str(HEIGHT),
                             '--render-scale', '100', '--hud-scale', '1', '--item-table',
                             str(ROOT/'generated/reference_item_metadata.tsv')], *args, **kwargs)
        with mock.patch.object(R.subprocess, 'Popen', launch):
            super().__init__(binary, relay, 'callback-client', helpers, frames=100000, jar=G.JAR)

    def finish(self, **kwargs):
        # Reuse the actual existing owner once the capped private observer has
        # exited. Its inherited60s communicate budget is then irrelevant; no
        # healthy process is killed or given a post-launch extension.
        deadline = self.started + 120
        while self.proc.poll() is None and time.monotonic() < deadline:
            time.sleep(.02)
        require(self.proc.poll() is not None, 'Predeclared120s observer completion')
        return super().finish(**kwargs)


class Driver:
    def __init__(self, directory, renderer, relay):
        self.directory, self.renderer, self.relay = directory, renderer, relay
        self.token = 0
        self.actions = []
        self.deadline = renderer.started + 120

    def wait(self, predicate, label):
        while time.monotonic() < self.deadline:
            value = predicate()
            if value is not None:
                return value
            require(self.renderer.proc.poll() is None, 'Actual client exited before ' + label)
            if self.relay.failure:
                raise AssertionError('Actual relay failed: ' + str(self.relay.failure))
            time.sleep(.01)
        raise AssertionError('Fixed native120s driver deadline: ' + label)

    def inject(self, label, events):
        self.token += 1
        batch = {'token': self.token, 'events': events}
        pending = self.directory/'callback-inbox.pending.json'
        pending.write_text(json.dumps(batch, separators=(',', ':')))
        os.replace(pending, self.directory/'callback-inbox.json')
        def ack():
            path = self.directory/'callback-ack.json'
            if not path.exists():
                return None
            value = json.loads(path.read_bytes())
            return value if value['token'] == self.token else None
        value = self.wait(ack, 'callback acknowledgement ' + label)
        require(value['events'] == events and len(value['queue_words']) % 5 == 0,
                'Actual callback queue receipt shape/events')
        require((value['point_width'], value['point_height']) == (WIDTH, HEIGHT),
                'Actual content/HUD coordinate assumption')
        self.actions.append({'label': label, 'batch': batch, 'actual_callback': value})
        G.exclusive(self.directory/f'callback-{self.token:02d}-{label}.json', self.actions[-1])

    def reply(self, cursor, tag, predicate, label, snapshot_match=None):
        def current():
            for index, row in enumerate(self.relay.records[cursor:], cursor):
                command = row['request']
                if command[:2] != [1, 1] or command[4][0] != tag or not predicate(command[4]):
                    continue
                response = row['reply']
                require(response[:2] == [1, 8] and response[2:4] == command[2:4]
                        and response[4:6] == [True, ''], 'Correlated real CookingReply: ' + label)
                if snapshot_match is not None and not snapshot_match(response[6]):
                    continue
                G.exclusive(self.directory/f'reply-{index:06d}-{label}.json', row)
                return index, response[6]
            return None
        return self.wait(current, label)

    def presented(self, index, label):
        # Inspect response is delivered before the same iteration paints the
        # CookingInput view. Require a later completed Window.frame timing and
        # retain the real CPU image, not just the authoritative endpoint DTO.
        before = len([line for line in self.renderer.out.read_text().splitlines()
                      if line.startswith('client.timing|')])
        def completed():
            lines = [line for line in self.renderer.out.read_text().splitlines()
                     if line.startswith('client.timing|')]
            if len(lines) <= before:
                return None
            finished = {}
            for line in self.renderer.out.read_text().splitlines():
                if line.startswith('resource.image|'):
                    fields = line.split('|')
                    if len(fields) == 5:
                        finished[int(fields[1])] = line
            for timing in reversed(lines[before:]):
                serial = int(timing.split('|')[1])
                path = self.renderer.images/f'{serial}.ppm'
                if serial not in finished or not path.exists():
                    continue
                raw = path.read_bytes()
                header = f'P6\n{WIDTH} {HEIGHT}\n255\n'.encode()
                if raw.startswith(header) and len(raw) == len(header) + WIDTH*HEIGHT*3:
                    return serial, path, finished[serial]
            return None
        serial, image, marker = self.wait(completed, 'actual painted frame ' + label)
        row = {'label': label, 'exchange_index': index, 'serial': serial, 'CPU_image': pin(image),
               'completed_resource_image_marker': marker, 'complete_P6_payload': True,
               'actual_pixel_extent': [WIDTH, HEIGHT], 'HUD_scale': 1,
               'elapsed_since_observer_start': time.monotonic()-self.renderer.started,
               'scope': 'Same returned CPU image composed by unchanged CookingInput/Window.frame; no drawable readback.'}
        G.exclusive(self.directory/('presented-' + label + '.json'), row)
        return row


def check_snapshot(snapshot, full, carried, revision, slots, timers, *, opened=True):
    expected_menu = B.empty_menu()
    expected_menu.update(carried=carried, revision=revision, opened=opened)
    require(snapshot[2] == B.authority(full, expected_menu), 'All43 cells/abilities/raw status/temp/menu revision')
    if opened:
        require(snapshot[0][:6] == [1, 1, 41, list(POINT), 'minecraft:furnace', 0]
                and snapshot[0][6] == 3, 'Actual ray-selected resident incarnation3')
        require(snapshot[1] == Menu.E.view(slots, timers), 'Exact furnace slots/timers')
    else:
        require(snapshot[:2] == [[0], [0]], 'Actual authenticated cooking close')


def expected_body(facts, ticks):
    original = S.N.parse(Pub.physical(facts, [None, B.stack('minecraft:coal', 1), None],
                         progress=0, remaining=1601-ticks, total=200, lit_total=1600))
    used = S.WC.compound([('minecraft:cooked_beef', S.WC.integer(2))])
    members = tuple((name, used if name == S.N.text('RecipesUsed') else value)
                    for name, value in original.value.payload)
    return S.N.encode_root(S.N.RootTag(original.name, S.N.Value(10, members)))


def expected_world(data, ticks):
    world = copy.deepcopy(data['world'])
    for _ in range(ticks):
        S.BASE.apply_tick(world)
    S.BASE.set_block(world, *POINT[1:], data['facts']['lit'])
    world['revision'] += 1
    world['events'].insert(0, {'stamp': (1, 0, world['revision']),
                              'kind': 0, 'revision': world['revision']})
    world['max_peer'] = 0
    return world


def native(directory, actor_generation, *, clock):
    ready = admitted(directory)
    callback_build = json.loads((directory/'callback-build.json').read_bytes())
    binary = directory/'renderer-callback'
    require(callback_build['status'] == 'built_native_unexecuted'
            and callback_build['binary'] == pin(binary), 'Actual private callback binary required')
    data = fixture()
    require(data['payload'] == (directory/'seed.nbt').read_bytes(), 'Fixture exact bytes')
    actor_work = ROOT/f'build/compiler-producer-diagnostic-{actor_generation:03d}'
    with Host.bindings(A, {'WORK': actor_work, 'SOURCE': actor_work/'source', 'ACTOR': actor_work/'actor'}):
        actor_build = B.artifact()
        observer = json.loads((directory/'observer-build.json').read_bytes())
        require(observer['status'] == 'PASS' and observer['binary'] == pin(directory/'observer')
                and observer['source'] == pin(directory/'observer.swift'), 'Exact private120s observer artifact')
        helpers = {'observer': {'source': str(directory/'observer.swift'), 'artifact': str(directory/'observer')}}
        attempt = directory/'native'
        attempt.mkdir(exist_ok=False)
        path = attempt/'world.nbt'
        path.write_bytes(data['payload'])
        actor = renderer = relay = None
        actions = []
        try:
            with Host.bindings(Pair, {'WORK': attempt}), Host.bindings(R, {'WORK': attempt}):
                began_ns = Pub.Storage.monotonic_ns()
                actor = G.backend(A.ACTOR, 'actor-callback', path)
                raw, ping = actor.tcp(True)
                require(ping['peer'] == 42, 'Durable40/local41/public42 peer ownership')
                relay = Pair.Relay(actor, 'callback-relay')
                renderer = CallbackRenderer(binary, relay, helpers, attempt)
                driver = Driver(attempt, renderer, relay)
                full = copy.deepcopy(data['full'])
                slots = [None] * 3
                batches = dict(events())
                # Empty CookingInspect is the real initial caller's discovery.
                driver.reply(0, 15, lambda command: command == [15, 0], 'initial closed inspect')
                cursor = len(relay.records)
                driver.inject('use-ray', batches['use-ray'])
                index, snapshot = driver.reply(cursor, 19, lambda command: command == [19, False], 'real CookingUse ray')
                check_snapshot(snapshot, full, None, 0, slots, [0, 0, 0, 0])
                actions.append(driver.presented(index, 'opened'))
                for label, logical, carried, changed, timers in (
                    ('pick-beef', 30, B.stack('minecraft:beef', 2), ('main', 0, None), [0, 0, 0, 0]),
                    ('put-input', 0, None, ('furnace', 0, B.stack('minecraft:beef', 2)), [0, 0, 0, 200]),
                    ('pick-coal', 31, B.stack('minecraft:coal', 2), ('main', 1, None), [0, 0, 0, 200]),
                    ('put-fuel', 1, None, ('furnace', 1, B.stack('minecraft:coal', 2)), [0, 0, 0, 200])):
                    cursor = len(relay.records)
                    driver.inject(label, batches[label])
                    index, snapshot = driver.reply(cursor, 16,
                        lambda command, logical=logical: command == [16, 1, logical, 0], label)
                    family, offset, item = changed
                    (full['main']['slots'] if family == 'main' else slots)[offset] = item
                    check_snapshot(snapshot, full, carried, len(actions), slots, timers)
                    actions.append(driver.presented(index, label))
                # Controller proofs alone do not execute these 400 actual ticks.
                # Controlled mode verifies exact checkpoints; ambient mode is
                # genuine server cadence, with observed exact timer relations.
                checkpoints = []
                started = time.monotonic()
                if clock == 'controlled':
                    for tick in range(1, 401):
                        target = started + tick * .05
                        if target > time.monotonic():
                            time.sleep(target - time.monotonic())
                        raw.call('simulation.step', {'ticks': 1})
                        if tick in (1, 100, 200, 300, 400):
                            cursor = len(relay.records)
                            wanted_timers = [1601-tick, 1600, tick % 200, 200]
                            index, snapshot = driver.reply(cursor, 15, lambda command: command == [15, 1], f'progress-{tick}',
                                lambda snapshot, wanted_timers=wanted_timers: snapshot[1][5:] == wanted_timers)
                            cooked = tick//200
                            slots = [B.stack('minecraft:beef', 2-cooked) if cooked < 2 else None,
                                     B.stack('minecraft:coal', 1), B.stack('minecraft:cooked_beef', cooked) if cooked else None]
                            check_snapshot(snapshot, full, None, 4, slots,
                                           [1601-tick, 1600, tick % 200, 200])
                            checkpoints.append(driver.presented(index, f'progress-{tick}'))
                else:
                    raw.call('simulation.pause', {'paused': False})
                    cursor = len(relay.records)
                    saw_partial = False
                    while True:
                        index, snapshot = driver.reply(cursor, 15, lambda command: command == [15, 1], 'ambient cooking inspect')
                        cursor = index + 1
                        furnace = snapshot[1]
                        require(furnace[:2] == [1, 0] and furnace[8] == 200, 'Real ambient furnace kind/total')
                        if 0 < furnace[7] < 200 and not saw_partial:
                            saw_partial = True
                            checkpoints.append(driver.presented(index, 'ambient-partial'))
                        if furnace[4] != [0] and furnace[4][-1] == 2:
                            break
                    require(saw_partial, 'Actual partial progress must be observed and painted')
                    slots = [None, B.stack('minecraft:coal', 1), B.stack('minecraft:cooked_beef', 2)]
                    # Keep the real actor unpaused until the renderer closes.
                    # The preserved008 run showed that pausing while its
                    # timer mailbox was behind could expire the renderer's
                    #100-pulse lease during catch-up. This host does not change
                    # the product timer or lease; each actual reply supplies
                    # its own exact burn/clock relation after both inputs end.
                    ticks = 1601-snapshot[1][5]
                    require(400 <= ticks < 1601, 'Bounded ambient burn has not extinguished')
                    check_snapshot(snapshot, full, None, 4, slots, [1601-ticks, 1600, 0, 200])
                    checkpoints.append(driver.presented(index, 'ambient-completed'))
                progress_seconds = time.monotonic()-started
                click_clocks = []
                for label, logical in (('pick-output', 2), ('put-main2', 32)):
                    cursor = len(relay.records)
                    driver.inject(label, batches[label])
                    index, snapshot = driver.reply(cursor, 16,
                        lambda command, logical=logical: command == [16, 1, logical, 0], label)
                    if logical == 2:
                        slots[2] = None
                        carried = B.stack('minecraft:cooked_beef', 2)
                    else:
                        full['main']['slots'][2] = B.stack('minecraft:cooked_beef', 2)
                        carried = None
                    revision = 5 if logical == 2 else 6
                    ticks = 1601-snapshot[1][5]
                    require(400 <= ticks < 1601, 'Actual transfer remains within first fuel burn')
                    check_snapshot(snapshot, full, carried, revision, slots,
                                   [1601-ticks, 1600, 0, 200])
                    click_clocks.append({'label': label, 'inferred_exact_Core_tick': ticks,
                                         'burn_remaining': snapshot[1][5]})
                    actions.append(driver.presented(index, label))
                cursor = len(relay.records)
                driver.inject('close-cooking', batches['close-cooking'])
                index, snapshot = driver.reply(cursor, 18, lambda command: command == [18, 1], 'E real cooking close')
                check_snapshot(snapshot, full, None, 6, slots, [], opened=False)
                actions.append(driver.presented(index, 'closed'))
                driver.inject('close-window', batches['close-window'])
                observed = renderer.finish(status=0)
                require(renderer.err.read_text().strip() == 'client closed', 'Actual normal closing diagnostic')
                modes = [json.loads(line) for line in (attempt/'mode-read.jsonl').read_bytes().splitlines()]
                require(modes == [{'effect': 'CID_IO_GET_ENV', 'query': 'BEND_MINECRAFT_LAUNCH_MODE',
                                   'returned': 'human', 'native_environment': 'hidden'}],
                        'Exactly one synthetic interactive mode query; actual hidden environment')
                traffic, traffic_pin = relay.finish()
                if clock == 'ambient':
                    raw.call('simulation.pause', {'paused': True})
                # A renderer has completed close before pausing. Reconcile
                # any already admitted cooking continuation before comparing
                # the complete durable owner; no active renderer lease is
                # needed for these public clock queries or the cold reload.
                previous = None
                while True:
                    clock_result = raw.call('world.clock')
                    if clock_result == previous and clock_result['paused']:
                        break
                    previous = clock_result
                    time.sleep(.06)
                require(400 <= clock_result['tick'] < 1601, 'Final paused clock remains within first fuel burn')
                # This is the unchanged public cooking-aware close/save helper.
                saves = Close.shutdown(actor, path, attempt, 'public-save', success=True)
                require(saves[-1]['event'] == 'client.save' and saves[-1]['result']['durable'],
                        'Real public durable shutdown save')
                physical = publication_projection(path.read_bytes(), data['facts'])
                require(physical['highwater'] == 43, 'Actual local41/public42/shutdown43 highwater')
                constructor = Pub.Entity.fresh_expected(physical['entities'], began_ns, Pub.Storage.monotonic_ns())
                ticks = clock_result['tick']
                require(physical['world'] == expected_world(data, ticks)
                        and physical['full'] == full and physical['clock_inputs'] == (),
                        'Independent completeCore/104 sections/lit event/full43/status/WG/clock oracle')
                require(physical['publication']['incarnations'] == data['counters'], 'Actual complete incarnation map retention')
                require(physical['bodies'] == ((POINT, expected_body(data['facts'], ticks)),),
                        'Independent exact physical Details/root/slot/timer/RecipesUsed body oracle')
                point = Pub.J.position(*POINT)
                producer = Pub.J.source(point, Pub.J.binding_for(Pub.catalog(), data['facts']['lit']), 3)
                journal = {'sequence': 7, 'unsaved': (),
                           'last': Pub.J.receipt(point, producer, Pub.J.chunk_for(point), 7)}
                require(physical['effects'] == () and physical['publication']['journal'] == journal,
                        'Exact seven delivered receipts/latest lit binding/incarnation/chunk/clean coverage')
                G.exclusive(attempt/'save-projection.json', {
                    'saved': pin(path), 'complete_reconstruction': True,
                    'full43': True, 'clock': clock_result, 'highwater': physical['highwater'],
                    'entity_owner': G.digest(Pub.Entity.encode(physical['entities'])),
                    'independent_fresh_constructor': constructor,
                    'physical_body': G.digest(physical['bodies'][0][1]),
                    'incarnation_map_retained': True, 'publication': physical['publication']['journal']})
                saved = path.read_bytes()
                # Stop/reap the original actor; a new real actor reads the same
                # complete durable envelope. No second renderer fixture is used.
                R.finish_backend(actor)
                actor = None
                cold = G.backend(A.ACTOR, 'actor-cold', path)
                actor = cold
                cold_raw, cold_ping = cold.tcp(True)
                require(cold_ping['peer'] == 45, 'Cold local44/public45 peer allocation')
                require(S.local_bytes(Menu.inspect_record(cold_raw)) == physical['player'],
                        'Actual cold full LocalPlayer record retention')
                control = Menu.connect(cold)
                cold_reply = control.call([15, 0], 8)
                require(cold_reply[4:6] == [True, ''] and cold_reply[6] ==
                        [[0], [0], B.authority(full, B.empty_menu())],
                        'Actual cold full43 authority and empty transient cooking state')
                control.call([2]); control.close(); cold.private = None
                cold_raw.call('world.save', {})
                cold_saved = publication_projection(path.read_bytes(), data['facts'])
                require(cold_saved['highwater'] == 45 and cold_saved['world'] == physical['world'] and cold_saved['full'] == full
                        and cold_saved['player'] == physical['player'] and cold_saved['bodies'] == physical['bodies']
                        and cold_saved['effects'] == physical['effects'] and cold_saved['entities'] == physical['entities']
                        and cold_saved['clock_inputs'] == physical['clock_inputs']
                        and cold_saved['publication'] == physical['publication'],
                        'Actual cold completeCore/player43/Details/effect/entity/RNG/clock/publication owner equality')
                result = {'status': 'PASS', 'original_build': pin(Path(ready['donor_build']['path'])),
                          'injected_binary': pin(binary), 'actor': actor_build['binary'],
                          'transform': ready['transform'], 'observer': observed,
                          'wire': traffic_pin, 'callback_batches': driver.actions,
                          'presented': actions, 'progress_presented': checkpoints,
                          'clock_mode': clock, 'progress_seconds': progress_seconds,
                          'transfer_clock_observations': click_clocks,
                          'pause_after_renderer_close': clock == 'ambient',
                          'predeclared_driver_observer_cap_seconds': 120,
                          'private_observer': observer,
                          'ticks': clock_result['tick'], 'normal_speed_bits': 1065353216,
                          'saved_before_cold': G.digest(saved), 'saved_after_cold': pin(path),
                          'complete_cold_owner_equality': True,
                          'limits': 'Private synthetic callbacks and focus/capture only. No foreground/hardware OS input, full vanilla frame, invented item icons, XP extraction or implicit ambient cadence claim.'}
                G.exclusive(attempt/'summary.json', result)
                return result
        except BaseException as error:
            G.exclusive(attempt/'first-failure.json', {'type': type(error).__name__, 'message': str(error)})
            raise
        finally:
            # Teardown entries are kept separate from the presentation rows.
            cleanup = []
            if renderer is not None:
                cleanup.append(('renderer', renderer.cleanup))
            if relay is not None:
                def finish_relay():
                    with Host.bindings(Pair, {'WORK': attempt}):
                        return relay.finish(failed=True)
                cleanup.append(('relay', finish_relay))
            if actor is not None:
                cleanup.append(('actor', lambda: R.finish_backend(actor)))
            G.finish_owned(cleanup, attempt/'final-cleanup.json')
            G.sweep_owned(attempt)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--generation', type=int, default=1)
    parser.add_argument('--client-generation', type=int, default=12)
    parser.add_argument('--donor-generation', type=int, help='Preparation-only declaration donor; native requires same as client')
    parser.add_argument('--actor-generation', type=int, default=22)
    parser.add_argument('--clock', choices=('ambient', 'controlled'), default='ambient')
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument('--prepare', action='store_true')
    modes.add_argument('--build-hook', action='store_true')
    modes.add_argument('--build-observer', action='store_true')
    modes.add_argument('--reuse-hook-generation', type=int, help='Reuse exact already compiled C/binary after a host-only repair')
    modes.add_argument('--native', action='store_true')
    args = parser.parse_args()
    require(all(1 <= value <= 999 for value in (args.generation, args.client_generation, args.actor_generation)),
            'Explicit bounded generation numbers')
    directory = ROOT/'build'/PREFIX/f'{args.generation:03d}'
    try:
        if args.build_hook:
            result = build_hook(directory)
        elif args.build_observer:
            result = build_observer(directory)
        elif args.reuse_hook_generation:
            result = reuse_hook(directory, ROOT/'build'/PREFIX/f'{args.reuse_hook_generation:03d}')
        elif args.native:
            result = native(directory, args.actor_generation, clock=args.clock)
        else:
            result = prepare(directory, args.client_generation, args.donor_generation or args.client_generation)
    except BaseException as error:
        failure = directory/'first-failure.json'
        if directory.exists() and not failure.exists():
            G.exclusive(failure, {'type': type(error).__name__, 'message': str(error),
                                  'mode': 'native' if args.native else 'build-hook' if args.build_hook else 'prepare'})
        raise
    print(json.dumps({'status': result['status'], 'directory': str(directory),
                      'native_executed': bool(args.native)}), flush=True)


if __name__ == '__main__':
    main()
