#!/usr/bin/env python3
"""Read pinned cooking outline/progress class bytes; no JVM or game launch."""
import hashlib
import json
from pathlib import Path
import struct
import time
import zipfile

from reference_inventory import ROOT, fingerprint, write_json
from reference_model_probe import CLIENT, META
from reference_player_inventory_probe import class_inventory

OUTPUT = ROOT / 'reference/player_cooking_protocol.json'
EVIDENCE = ROOT / 'evidence/player-cooking-protocol-reference.json'
PREFIX = 'net.minecraft.world.level.block.'
SELECTED = {
    PREFIX + 'FurnaceBlock': {'getShape'},
    PREFIX + 'BlastFurnaceBlock': {'getShape'},
    PREFIX + 'SmokerBlock': {'getShape'},
    PREFIX + 'AbstractFurnaceBlock': {'getShape'},
    PREFIX + 'BaseEntityBlock': {'getShape'},
    PREFIX + 'Block': {'getShape', 'column', 'box'},
    PREFIX + 'state.BlockBehaviour': {'getShape', 'getInteractionShape', 'getCollisionShape'},
    PREFIX + 'CampfireBlock': {'getShape', '<clinit>'},
    'net.minecraft.world.phys.shapes.Shapes': {'block', '<clinit>', 'lambda$static$0'},
    'net.minecraft.world.inventory.AbstractFurnaceMenu': {'isLit', 'getLitProgress', 'getBurnProgress'},
    'net.minecraft.client.gui.screens.inventory.AbstractFurnaceScreen': {'extractBackground'},
}


def pool(data):
    offset = 8

    def take(n):
        nonlocal offset
        value = data[offset:offset + n]
        if len(value) != n:
            raise ValueError('truncated constant pool')
        offset += n
        return value

    def u2():
        return int.from_bytes(take(2), 'big')

    entries, index = [None] * u2(), 1
    while index < len(entries):
        tag = take(1)[0]
        if tag == 1:
            value = take(u2()).decode('utf-8', errors='replace')
        elif tag in (3, 5):
            value = int.from_bytes(take(4 if tag == 3 else 8), 'big', signed=True)
        elif tag in (4, 6):
            value = struct.unpack('>f' if tag == 4 else '>d', take(4 if tag == 4 else 8))[0]
        elif tag in (7, 8, 16, 19, 20):
            value = u2()
        elif tag in (9, 10, 11, 12, 17, 18):
            value = (u2(), u2())
        elif tag == 15:
            value = (take(1)[0], u2())
        else:
            raise ValueError('unknown constant pool tag: ' + str(tag))
        entries[index] = (tag, value)
        index += 2 if tag in (5, 6) else 1

    def resolve(i):
        tag, value = entries[i]
        if tag in (7, 8, 16, 19, 20):
            return resolve(value)
        if tag in (9, 10, 11, 12):
            return tuple(resolve(v) for v in value)
        return value

    parent = resolve(int.from_bytes(data[offset + 4:offset + 6], 'big'))
    return parent, resolve


def main():
    started = time.monotonic()
    release = json.loads((ROOT / 'reference/release.json').read_text())
    version = json.loads(META.read_text())
    client = fingerprint(CLIENT)
    assert release['pin'] == version['id'] == '26.3'
    assert client['sha256'] == release['client']['sha256']
    assert client['sha1'] == version['downloads']['client']['sha1']
    assert client['bytes'] == version['downloads']['client']['size']
    classes, resolvers = {}, {}
    with zipfile.ZipFile(CLIENT) as jar:
        for name, selected in SELECTED.items():
            data = jar.read(name.replace('.', '/') + '.class')
            parent, resolve = pool(data)
            classes[name] = class_inventory(data, selected) | {'superclass': parent}
            resolvers[name] = resolve

    def code(name, method, descriptor=None):
        return bytes.fromhex(next(v['bytecode_hex'] for v in classes[name]['methods']
            if v['name'] == method and (descriptor is None or v['descriptor'] == descriptor)))

    chain = [PREFIX + v for v in ('AbstractFurnaceBlock', 'BaseEntityBlock', 'Block')] + [PREFIX + 'state.BlockBehaviour']
    for kind in ('FurnaceBlock', 'BlastFurnaceBlock', 'SmokerBlock'):
        names = [PREFIX + kind] + chain
        assert all(classes[a]['superclass'] == b.replace('.', '/') for a, b in zip(names, names[1:]))
        assert all(not classes[name]['methods'] for name in names[:-2])
    assert not any(v['name'] == 'getShape' for v in classes[PREFIX + 'Block']['methods'])
    behaviour = PREFIX + 'state.BlockBehaviour'
    outline = code(behaviour, 'getShape')
    assert outline == bytes.fromhex('b80198b0')
    assert resolvers[behaviour](0x198)[1][0] == 'block'
    assert resolvers[behaviour](0x189)[1][0] == 'empty'
    shapes = 'net.minecraft.world.phys.shapes.Shapes'
    assert code(shapes, 'block') == bytes.fromhex('b2000db0')
    assert code(shapes, 'lambda$static$0') == bytes.fromhex('bb004059040404b701e14b2a030303b601e4bb0045592ab70047b0')
    camp = PREFIX + 'CampfireBlock'
    assert code(camp, 'getShape') == bytes.fromhex('b20110b0')
    assert resolvers[camp](0x21c) == 16.0 and resolvers[camp](0x21e) == 7.0
    assert resolvers[camp](0x220)[1][0] == 'column'
    assert bytes.fromhex('14021c0e14021eb80220b30110') in code(camp, '<clinit>')
    block = PREFIX + 'Block'
    assert resolvers[block](0x76) == 16.0 and resolvers[block](0x96) == 2.0 and resolvers[block](0x98) == 8.0
    menu = 'net.minecraft.world.inventory.AbstractFurnaceMenu'
    assert code(menu, 'isLit') == bytes.fromhex('2ab4002803b900be02009e000704a7000403ac')
    screen = 'net.minecraft.client.gui.screens.inventory.AbstractFurnaceScreen'
    assert resolvers[screen](0x5a)[1][0] == 'isLit'
    assert resolvers[screen](0x5e)[1][0] == 'getLitProgress' and resolvers[screen](0x62) == 13.0
    assert resolvers[screen](0x63) == ('net/minecraft/util/Mth', ('ceil', '(F)I'))
    assert resolvers[screen](0x6d)[1][0] == 'getBurnProgress' and resolvers[screen](0x70) == 24.0
    background = code(screen, 'extractBackground')
    assert bytes.fromhex('b6005e12626ab800630460') in background
    assert bytes.fromhex('b6006d12706ab80063') in background

    references = {
        name: {hex(i): resolvers[name](i) for i in indices}
        for name, indices in {
            behaviour: [0x189, 0x198, 0x17b], camp: [0x110, 0x21c, 0x21e, 0x220],
            block: [0x76, 0x78, 0x96, 0x98, 0x9a, 0x9e],
            shapes: [0xd, 0x40, 0x45, 0x1e1, 0x1e4],
            screen: [0x5a, 0x5e, 0x62, 0x63, 0x6d, 0x70],
        }.items()}
    result = {'pin': '26.3', 'client': client, 'metadata': fingerprint(META), 'classes': classes,
        'resolved_constant_pool': references,
        'outline': {'furnace_all_states': [0, 0, 0, 1, 1, 1], 'campfire_all_states': [0, 0, 0, 1, 7/16, 1],
            'argument': 'Inherited state-independent getShape -> Shapes.block, whose initializer fills the only cell of a 1x1x1 discrete shape and wraps CubeVoxelShape. Campfire getShape -> SHAPE -> Block.column(16,0,7), with Block.box dividing coordinates by16.',
            'interaction_shape': 'Separate inherited getInteractionShape returns Shapes.empty. No collision-property assertion.'},
        'screen': {'flame': 'signed lit_remaining >0 gates ceil(clamped_signed_F32_ratio*13F)+1;14-pixel sprite, bottom y50',
            'arrow': 'ceil(clamped_signed_F32_ratio*24F)',
            'lit_duration_zero_fallback': 200},
        'scope': 'Pinned class-byte evidence of outline inheritance and screen/menu progress instructions. No JVM execution, complete ray/collision proof, native presentation or Java GUI observation.'}
    write_json(OUTPUT, result)
    write_json(EVIDENCE, {'status': 'passed-static-class-byte-checks', 'seconds': round(time.monotonic()-started, 6),
        'command': ['python3', 'tools/reference_player_cooking_protocol.py'], 'reference': fingerprint(OUTPUT),
        'extractor': fingerprint(Path(__file__)), 'class_parser': fingerprint(ROOT/'tools/reference_player_inventory_probe.py'),
        'scope': result['scope']})
    print(json.dumps({'status': 'passed-static-class-byte-checks', 'classes': len(classes), 'reference': str(OUTPUT)}))


if __name__ == '__main__':
    main()
