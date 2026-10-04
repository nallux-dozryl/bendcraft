#!/usr/bin/env python3
"""Pinned26.3 actual normal-player SWAP receiver; no host click semantics."""
from __future__ import annotations
import argparse
import base64
import json
import os
from pathlib import Path
import zipfile

import reference_player_inventory_probe as P
import reference_local_input_probe as LI
from reference_inventory import ROOT, canonical, write_json

FIXTURE = 'net.minecraft.fixture.PlayerInventoryClickReceiverFixture'
OUTPUT = ROOT / 'reference/player_inventory_click.json'
METHODS = {
    **P.CLOSE_METHODS,
    'net.minecraft.world.inventory.AbstractContainerMenu':
        {'clicked', 'doClick', 'getSlot', 'getCarried', 'setCarried'},
    'net.minecraft.world.inventory.ContainerInput': {'<clinit>'},
    'net.minecraft.world.inventory.InventoryMenu$1': {'<init>', 'mayPlace', 'mayPickup', 'getMaxStackSize'},
}


def item(name, count=1):
    return {'item': 'minecraft:' + name, 'count': count}


def inputs():
    cases = []
    for mode in ('SURVIVAL', 'CREATIVE'):
        full = {str(i): item('dirt', 64) for i in range(36)}
        def case(name, target, button, slots=None):
            cases.append({'id': name + ':' + mode.lower(), 'operation': 'swap',
                          'mode': mode, 'target': target, 'button': button, 'selected': 7,
                          'slots': {'35': item('oak_planks', 6), '41': item('wolf_armor'),
                                    '42': item('saddle'), **(slots or {})},
                          'craft': [None, item('stone', 2), None, None],
                          'carried': item('dirt', 3)})
        case('empty-both', 10, 0)
        case('different-items', 10, 0, {'10': item('stone', 17), '0': item('dirt', 4)})
        case('same-item-counts', 10, 0, {'10': item('stone', 17), '0': item('stone', 4)})
        case('take-into-empty', 9, 8, {'9': item('ender_pearl', 16)})
        case('put-into-empty', 10, 7, {'7': item('shield')})
        case('same-backing-cell', 37, 1, {'1': item('stone', 17)})
        case('offhand-target', 45, 8, {'40': item('dirt', 5), '8': item('stone', 17)})
        case('offhand-button', 9, 40, {'9': item('dirt', 5), '40': item('stone', 17)})
        case('offhand-self', 45, 40, {'40': item('stone', 17)})
        case('craft-input', 1, 0, {'0': item('oak_planks', 5)})
        case('head-one', 5, 0, {'0': item('diamond_helmet')})
        case('head-refuses-stone', 5, 0, {'0': item('stone', 64)})
        case('take-head', 5, 0, {'39': item('diamond_helmet')})
        case('head-clips-stack', 5, 0, {'0': item('carved_pumpkin', 64)})
        case('head-return-displaced', 5, 0,
             {'39': item('diamond_helmet'), '0': item('carved_pumpkin', 64)})
        case('head-return-same-key', 5, 0,
             {'39': item('carved_pumpkin'), '0': item('carved_pumpkin', 64)})
        case('head-full-disposition', 5, 0,
             {**full, '39': item('diamond_helmet'), '0': item('carved_pumpkin', 64)})
        case('head-full-compatible', 5, 0,
             {**full, '39': item('carved_pumpkin'), '0': item('carved_pumpkin', 64)})
        for button in (9, 39, 41, -1):
            case('ignored-button-' + str(button), 10, button,
                 {'10': item('stone', 17), '0': item('dirt', 4)})
        case('result-empty', 0, 0, {'0': item('stone', 17)})
    for button in (0, 8, 40):
        cases.append({'id': 'adventure-movement-' + str(button), 'operation': 'swap',
                      'mode': 'ADVENTURE', 'target': 10, 'button': button, 'selected': 7,
                      'slots': {'10': item('stone', 17), str(button): item('dirt', 4)},
                      'craft': [None] * 4, 'carried': item('oak_planks', 2)})
    return cases


SOURCE = P.JAVA_SOURCE[:P.JAVA_SOURCE.index(' public static void run(String ignored)')].replace(
    'public class PlayerInventoryReceiverFixture', 'public class PlayerInventoryClickReceiverFixture') + r'''
 static ItemStack inputStack(JsonElement element){return element==null||element.isJsonNull()?ItemStack.EMPTY:stack(element.getAsJsonObject().get("item").getAsString(),element.getAsJsonObject().get("count").getAsInt());}
 static Object menuState(LocalPlayer p)throws Exception{
  Map<String,Object> m=new TreeMap<>();m.put("inventory",state(p));
  List<Object> equipment=new ArrayList<>();for(int n=36;n<43;n++)equipment.add(stackState(p.getInventory().getItem(n)));
  List<Object> craft=new ArrayList<>();for(int n=1;n<=4;n++)craft.add(stackState(p.inventoryMenu.getSlot(n).getItem()));
  m.put("equipment",equipment);m.put("craft",craft);m.put("carried",stackState(p.inventoryMenu.getCarried()));
  m.put("result",stackState(p.inventoryMenu.getSlot(0).getItem()));return m;
 }
 public static void run(String ignored)throws Exception{
  SharedConstants.tryDetectVersion();Bootstrap.bootStrap();HolderLookup.Provider lookup=VanillaRegistries.createWorldLookup();
  for(var pending:BuiltInRegistries.DATA_COMPONENT_INITIALIZERS.build(lookup))pending.forEach((holder,components)->holder.bindComponents(components));
  for(String name:List.of("net.minecraft.world.entity.player.Abilities$Packed","net.minecraft.world.ContainerHelper","net.minecraft.world.inventory.Slot"))Class.forName(name,true,PlayerInventoryClickReceiverFixture.class.getClassLoader());
  JsonArray cases=JsonParser.parseString(new String(Base64.getDecoder().decode(__INPUT__),java.nio.charset.StandardCharsets.UTF_8)).getAsJsonArray();
  for(JsonElement entry:cases){JsonObject in=entry.getAsJsonObject();var context=new LocalInputReceiverFixture.Context(lookup,false);LocalPlayer p=context.player;var inventory=p.getInventory();
   for(var value:in.getAsJsonObject("slots").entrySet())inventory.setItem(Integer.parseInt(value.getKey()),inputStack(value.getValue()));
   inventory.setSelectedSlot(in.get("selected").getAsInt());GameType.valueOf(in.get("mode").getAsString()).updatePlayerAbilities(p.getAbilities());
   p.inventoryMenu.setCarried(inputStack(in.get("carried")));net.minecraft.world.Container crafting=(net.minecraft.world.Container)LocalInputReceiverFixture.read(p.inventoryMenu,"craftSlots");
   for(int n=0;n<4;n++)crafting.setItem(n,inputStack(in.getAsJsonArray("craft").get(n)));
   Map<String,Object> row=new TreeMap<>();row.put("id",in.get("id").getAsString());row.put("operation","swap");row.put("input",in);row.put("before",menuState(p));boolean ok=false;
   try{p.inventoryMenu.clicked(in.get("target").getAsInt(),in.get("button").getAsInt(),net.minecraft.world.inventory.ContainerInput.SWAP,p);ok=true;}
   catch(Throwable error){row.put("error",failure(error));}
   row.put("ok",ok);row.put("after",menuState(p));output(row);
  }
 }
}
'''


def prepared():
    if P.sha(Path(LI.__file__).read_bytes()) != P.FROZEN_LI:
        raise ValueError('Normal LocalPlayer fixture identity differs')
    paths, provenance = P.verified_classpath()
    cases = inputs()
    sources = LI.receiver_sources({})
    sources[FIXTURE] = SOURCE.replace('__INPUT__', LI.java_string(base64.b64encode(canonical(cases)).decode()))
    if 'Unsafe' in '\n'.join(sources.values()):
        raise ValueError('Unexpected unsafe fixture allocation')
    payload = {'sources': sources, 'client_jar': str(P.CLIENT), 'mode': 'player-inventory-click'}
    launcher = LI.RECEIVER_LAUNCHER.replace('net.minecraft.fixture.LocalInputReceiverFixture', FIXTURE, 1)
    launcher = launcher.replace('Base64.getDecoder().decode(args[0])',
        'Base64.getDecoder().decode(' + LI.java_string(base64.b64encode(canonical(payload)).decode()) + ')', 1)
    command = [str(P.JAVA), '-Xmx512m', '--source', '25', '--class-path', os.pathsep.join(map(str, paths)), '/dev/stdin']
    return {'cases': cases, 'sources': sources, 'launcher': launcher, 'command': command,
            'provenance': provenance, 'source_inventory': P.source_inventory(METHODS),
            'profile': 'menu-click-swap', 'timeout_seconds': 60}


def collect(mode):
    preparation = prepared()
    run = P.observe(preparation, 'menu-click-swap-' + mode)
    rows, loaded = run['observations'], run['loaded_official_classes']
    for case, row in zip(preparation['cases'], rows, strict=True):
        if row['input'] != case or row['id'] != case['id']:
            raise ValueError('Actual SWAP input/order differs')
    for name in ('net.minecraft.world.inventory.AbstractContainerMenu',
                 'net.minecraft.world.inventory.InventoryMenu', 'net.minecraft.world.inventory.ContainerInput'):
        if name not in loaded:
            raise ValueError('Actual SWAP receiver class not loaded: ' + name)
    if any(not row['ok'] for row in rows):
        raise ValueError('Unexpected actual SWAP receiver exception; raw retained')
    stable = {'pin': '26.3', 'evidence_format': 'normal-player-swap-v1',
              'producer': P.pin(Path(__file__)), 'inputs': preparation['cases'],
              'observations': rows, 'observations_sha256': P.sha(canonical(rows)),
              'source_inventory': preparation['source_inventory'], 'provenance': preparation['provenance'],
              'fixture_sources_sha256': {name: P.sha(source.encode()) for name, source in preparation['sources'].items()},
              'launcher_source_sha256': P.sha(preparation['launcher'].encode()),
              'loaded_official_classes': {'count': len(loaded), 'all_verified_against_client_jar': True,
                  'complete_map_sha256': P.sha(canonical(loaded)),
                  'selected': {name: loaded[name] for name in METHODS if name in loaded}},
              'boundary': {'receiver': 'Actual InventoryMenu.clicked with ContainerInput.SWAP on normal LocalPlayer',
                  'profile': 'Actual fresh GameType ability update; no server game-mode lifecycle claimed',
                  'world': 'Frozen normal ClientLevel fixture; no owned world-drop consumer or foreground UI',
                  'reused_tools': 'Existing pinned inventory/class/source launcher and bounded raw-first observer'}}
    if mode == 'extract':
        write_json(OUTPUT, {**stable, 'raw_artifacts': [run['raw_artifact']], 'execution': run['execution']})
    else:
        existing = json.loads(OUTPUT.read_text())
        for key, value in stable.items():
            if existing[key] != value:
                raise ValueError('Fresh SWAP reproduction differs: ' + key)
    try:
        os.killpg(run['execution']['pid'], 0)
        absent = False
    except ProcessLookupError:
        absent = True
    receipt = {'status': 'observed' if mode == 'extract' else 'exact fresh-process reproduction',
               'mode': mode, 'reference': P.pin(OUTPUT), 'raw_artifact': run['raw_artifact'],
               'case_count': len(rows), 'observations_sha256': stable['observations_sha256'],
               'loaded_official_classes': len(loaded), 'all_official_class_hashes_verified': True,
               'execution': run['execution'], 'process_group_absent': absent,
               'bounds': {'heap_mib': 512, 'process_group_seconds': 60}, 'java_processes': 1}
    write_json(ROOT / ('evidence/player-inventory-click-reference-' + mode + '.json'), receipt)
    print(json.dumps(receipt, indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--prepare', action='store_true')
    parser.add_argument('--mode', choices=('extract', 'reproduce'), default='extract')
    args = parser.parse_args()
    if args.prepare:
        value = prepared()
        summary = {'status': 'prepared-not-executed', 'producer': P.pin(Path(__file__)),
                   'cases': len(value['cases']), 'inputs_sha256': P.sha(canonical(value['cases'])),
                   'source_inventory': value['source_inventory'], 'provenance': value['provenance'],
                   'bounds': {'heap_mib': 512, 'seconds': 60, 'cleanup_seconds': 10}, 'java_processes': 0}
        write_json(ROOT / 'evidence/player-inventory-click-reference-preparation.json', summary)
        print(json.dumps({key: summary[key] for key in ('status', 'cases', 'inputs_sha256', 'bounds', 'java_processes')}))
    else:
        collect(args.mode)


if __name__ == '__main__':
    main()
