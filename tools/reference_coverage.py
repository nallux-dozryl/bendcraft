#!/usr/bin/env python3
"""Generate inventory coverage rows and a non-data behavior obligation map.

Existing implementation/verification evidence is preserved when rerun. Named
classes and method signatures locate work; they do not prove method semantics.
"""
from __future__ import annotations

import hashlib
import json
import pathlib
import subprocess
import zipfile

from reference_inventory import ROOT, JAVA, INSTALL, PIN, write_json, fingerprint

# Curated obligation groups, not a claim of an exhaustive executable spec.
# Each class name below is checked against the exact installed client artifact.
BEHAVIORS = [
    ("ticks", "Tick cadence, freeze/step/sprint, ordering and integrated pause", ["server.MinecraftServer", "world.TickRateManager", "server.ServerTickRateManager"], ["tick", "setTick", "setFrozen", "runServer"]),
    ("chunk_lifecycle", "Chunk loading, tickets, activity levels, asynchronous work and unloading", ["server.level.ServerChunkCache", "server.level.ChunkMap"], ["tick", "getChunk", "save", "close"]),
    ("randomness", "Exact random algorithms, seeds, stream consumption and deterministic replay", ["util.RandomSource", "world.level.levelgen.LegacyRandomSource", "world.level.levelgen.XoroshiroRandomSource"], ["next", "setSeed", "fork"]),
    ("terrain", "Noise, density, climate sampling, aquifers, terrain blending and surface generation", ["world.level.levelgen.NoiseBasedChunkGenerator"], ["fillFromNoise", "buildSurface", "applyCarvers", "getBase"]),
    ("biomes", "Biome selection, environmental attributes, spawn rules, features and colors", ["world.level.biome.Biome", "world.level.biome.MultiNoiseBiomeSource"], ["get", "collect", "create"]),
    ("structures", "Structure placement, locating, template palettes, jigsaw expansion and processors", ["world.level.levelgen.structure.Structure", "world.level.levelgen.structure.templatesystem.StructureTemplate"], ["generate", "place", "find", "load"]),
    ("dimensions_portals", "Dimension transitions, portal construction/search, scaling and respawn", ["world.level.block.Portal", "world.level.portal.TeleportTransition", "world.level.portal.PortalForcer"], ["get", "find", "create"]),
    ("block_interaction", "Placement, support, breaking, tools, shapes, interaction and drops", ["world.level.block.state.BlockBehaviour", "world.level.block.Block"], ["use", "getDestroy", "getCollision", "getShape", "destroy", "updateShape"]),
    ("block_updates", "Neighbor updates, scheduled/random ticks and update-order quirks", ["world.level.redstone.NeighborUpdater", "world.ticks.LevelTicks"], ["tick", "schedule", "neighbor", "update"]),
    ("redstone", "Power propagation, quasi-connectivity, component timing and experimental rules", ["world.level.redstone.RedstoneWireEvaluator", "world.level.redstone.ExperimentalRedstoneWireEvaluator", "world.level.block.piston.PistonBaseBlock"], ["updatePower", "get", "neighbor", "check", "triggerEvent"]),
    ("fluids", "Fluid levels, flow, source formation, interactions, waterlogging and scheduled ticks", ["world.level.material.FlowingFluid", "world.level.material.FluidState"], ["get", "tick", "spread"]),
    ("block_entities", "Block-entity persistence, ticking, containers, machinery and specialized behavior", ["world.level.block.entity.BlockEntity", "world.level.block.entity.BaseContainerBlockEntity"], ["load", "save", "get", "set", "trigger"]),
    ("item_use", "Components, item use, consumption, cooldowns, durability and damage", ["world.item.Item", "world.item.ItemStack"], ["use", "hurt", "consume", "finish", "get"]),
    ("inventories_menus", "Stack merging, click modes, drag rules, transactions, synchronization and every menu", ["world.inventory.AbstractContainerMenu", "world.entity.player.Inventory"], ["clicked", "quick", "move", "broadcast", "add", "remove"]),
    ("recipes", "Recipe codecs, matching, ingredients, results, special recipes and recipe-book rules", ["world.item.crafting.RecipeManager", "world.item.crafting.Recipe"], ["get", "matches", "assemble", "prepare", "apply"]),
    ("loot", "Loot contexts, randomness, conditions, functions, references and drop semantics", ["world.level.storage.loot.LootTable", "world.level.storage.loot.LootContext"], ["getRandom", "create", "validate", "fill"]),
    ("enchantments", "Enchantment compatibility, levels, effects, providers and equipment interactions", ["world.item.enchantment.EnchantmentHelper", "world.item.enchantment.Enchantment"], ["get", "run", "modify", "can"]),
    ("movement_collision", "Movement, collision/stepping, poses, fluid forces, riding and interpolation", ["world.entity.Entity", "world.entity.LivingEntity"], ["move", "collide", "travel", "ride", "jump", "updateSwimming"]),
    ("mobs_ai", "Every entity type, goals/brains, memory, sensors, navigation and species behavior", ["world.entity.Mob", "world.entity.ai.Brain", "world.level.pathfinder.PathFinder"], ["tick", "findPath", "get", "set", "start"]),
    ("spawning", "Natural/structure/spawner spawning, caps, despawn, breeding and difficulty", ["world.level.NaturalSpawner", "world.level.block.entity.SpawnerBlockEntity"], ["spawn", "get", "create", "serverTick"]),
    ("combat_health", "Damage sources, armor, attributes, effects, invulnerability, knockback and death", ["world.damagesource.DamageSources", "world.entity.LivingEntity"], ["hurt", "die", "knockback", "getArmor", "addEffect", "removeEffect"]),
    ("players_modes", "Survival/creative/adventure/spectator, abilities, actions, permissions and respawn", ["world.entity.player.Player", "world.entity.player.Abilities", "server.level.ServerPlayer"], ["attack", "tick", "isCreative", "isSpectator", "has", "restore"]),
    ("hunger_experience", "Food, saturation, exhaustion, regeneration, starvation and XP thresholds", ["world.food.FoodData", "world.entity.player.Player"], ["tick", "eat", "giveExperience", "getXp", "causeFood"]),
    ("advancements_stats", "Triggers, criteria, requirements, progress, rewards, statistics and achievements UI", ["server.PlayerAdvancements", "advancements.Advancement", "stats.ServerStatsCounter"], ["award", "revoke", "load", "save", "setValue", "flush"]),
    ("commands", "All command nodes, parsers, selectors, permissions, side effects and errors", ["commands.Commands", "commands.arguments.selector.EntitySelector", "server.commands.ExecuteCommand"], ["perform", "parse", "find", "register"]),
    ("scoreboards_teams", "Objectives, scores, teams, visibility, collision rules, boss bars and waypoints", ["world.scores.Scoreboard", "server.ServerScoreboard", "server.bossevents.CustomBossEvents"], ["add", "get", "remove", "set", "save", "load"]),
    ("time_weather", "World clocks, timelines, daylight, weather, sleep and environmental transitions", ["world.clock.WorldClock", "world.timeline.Timeline", "server.level.ServerLevel"], ["tick", "getTime", "setTime", "advanceWeather", "updateSky"]),
    ("explosions_fire", "Explosion ray sampling, block/entity effects, fire spread and destruction rules", ["world.level.ServerExplosion", "world.level.block.FireBlock"], ["explode", "tick", "get", "calculate"]),
    ("light", "Sky/block lighting, propagation, chunk boundaries and updates", ["world.level.lighting.LevelLightEngine", "world.level.lighting.LightEngine"], ["checkBlock", "runLight", "get", "update", "propagate"]),
    ("persistence", "NBT codecs, region/chunk/entity/player/world saves, migration and recovery", ["nbt.NbtIo", "world.level.chunk.storage.RegionFile", "world.level.storage.LevelStorageSource"], ["read", "write", "save", "createAccess", "validate"]),
    ("protocol", "Packet field codecs, ordering, connection states, compression, encryption and disconnects", ["network.Connection", "server.network.ServerGamePacketListenerImpl"], ["send", "tick", "handle", "disconnect", "setup"]),
    ("multiplayer", "Integrated/dedicated behavior, login, permissions, synchronization and multi-client sessions", ["server.dedicated.DedicatedServer", "client.server.IntegratedServer", "server.players.PlayerList"], ["tick", "initServer", "placeNewPlayer", "remove", "broadcast"]),
    ("client_loop_input", "Client scheduling, keyboard/mouse configuration, focus, window and controls", ["client.Minecraft", "client.KeyboardHandler", "client.MouseHandler"], ["tick", "run", "key", "mouse", "turnPlayer", "handle"]),
    ("rendering", "Camera, geometry, culling, lighting, transparency, effects, entities and GUI composition", ["client.renderer.GameRenderer", "client.renderer.LevelRenderer"], ["render", "tick", "resize", "allChanged", "extract"]),
    ("models_assets", "Models, blockstates, item definitions, equipment, texture atlases and pack overrides", ["client.resources.model.ModelManager", "client.renderer.texture.TextureManager"], ["get", "reload", "apply", "prepare", "register"]),
    ("particles_audio", "Particle types/simulation, sounds, attenuation, music, subtitles and event timing", ["client.particle.ParticleEngine", "client.sounds.SoundManager", "client.sounds.MusicManager"], ["tick", "play", "create", "render", "stop"]),
    ("ui_settings", "All screens, menus, HUD, chat, settings, accessibility and localization", ["client.gui.Gui", "client.Options", "client.gui.screens.TitleScreen", "client.resources.language.LanguageManager"], ["render", "tick", "load", "save", "get", "init"]),
    ("pack_loading", "Pack metadata/ranges, overlays, priority, tags, registry composition, reload and validation", ["server.packs.PackResources", "server.packs.resources.ReloadableResourceManager", "server.packs.repository.PackRepository"], ["get", "reload", "open", "load", "setSelected"]),
    ("game_tests", "Game-test definitions, environments, commands, assertions, ordering and reports", ["gametest.framework.GameTestServer", "gametest.framework.GameTestHelper"], ["tick", "assert", "start", "succeed", "fail"]),
]


def main() -> None:
    inventory = json.loads((ROOT / "reference/inventory.json").read_text())
    client = INSTALL / "versions/26.3/26.3.jar"
    release = json.loads((ROOT / "reference/release.json").read_text())
    if fingerprint(client)["sha256"] != release["client"]["sha256"]:
        raise ValueError("Pinned reference client SHA-256 mismatch")
    coverage_path = ROOT / "reference/coverage.json"
    previous = json.loads(coverage_path.read_text()) if coverage_path.exists() else {}
    previous_rows = {row["id"]: row for row in previous.get("rows", [])}
    source_records, rows = {}, []
    classes = sorted(set("net.minecraft." + short for _, _, names, _ in BEHAVIORS for short in names))
    with zipfile.ZipFile(client) as jar:
        for name in classes:
            path = name.replace(".", "/") + ".class"
            data = jar.read(path)  # Fail, rather than fabricate, if a class moved.
            source_records[name] = {"jar_path": path, "class_bytes": len(data), "class_sha256": hashlib.sha256(data).hexdigest()}
    javap = JAVA.parent / "javap"
    result = subprocess.run([str(javap), "-classpath", str(client), "-p", *classes], capture_output=True, text=True, check=True)
    (ROOT / "reference/cache/behavior-signatures.txt").write_text(result.stdout)
    chunks = result.stdout.split('Compiled from "')[1:]
    for chunk, name in zip(chunks, classes):
        if name not in chunk.splitlines()[1]:
            raise ValueError(f"Unexpected javap declaration for {name}")
        signatures = [line.strip() for line in chunk.splitlines() if line.startswith("  ") and "(" in line and line.rstrip().endswith(";")]
        source_records[name]["declared_method_signature_count"] = len(signatures)
        source_records[name]["method_signatures_sha256"] = hashlib.sha256("\n".join(signatures).encode()).hexdigest()
        source_records[name]["all_signatures"] = signatures
    if len(chunks) != len(classes):
        raise ValueError("Unexpected javap class report structure")
    def add(row: dict) -> None:
        old = previous_rows.get(row["id"], {})
        row.update({key: old.get(key, default) for key, default in {
            "implementation_status": "not_assessed", "implementation_evidence": [],
            "behavioral_reference_status": "not_collected", "behavioral_reference_evidence": [],
            "verification_status": "not_assessed", "verification_evidence": []}.items()})
        rows.append(row)
    for registry, count in inventory["registry_counts"].items():
        add({"id": "registry:" + registry, "kind": "static_registry", "reference_inventory_status": "extracted", "reference_count": count,
             "reference_evidence": ["generated/reference_registries.tsv", "reference/inventory.json"], "numeric_ids": "pinned_base_protocol_ids"})
    for key, group in inventory["data_categories"].items():
        add({"id": "data:" + key, "kind": "data_pack_content", "scope": group["scope"], "category": group["category"],
             "reference_inventory_status": "extracted", "reference_count": group["file_count"],
             "reference_evidence": ["generated/reference_data.tsv", "reference/inventory.json"], "codec_schema_status": "observed_shapes_only"})
    for key, group in inventory["resource_categories"].items():
        add({"id": "resource:" + key, "kind": "resource_pack_content", "category": group["category"], "reference_inventory_status": "extracted",
             "reference_count": group["file_count"], "reference_evidence": ["generated/reference_resources.tsv", "reference/inventory.json"]})
    add({"id": "resource:asset_index", "kind": "external_resource_metadata", "reference_inventory_status": "metadata_only", "reference_count": inventory["asset_index_objects"],
         "reference_evidence": ["generated/reference_resources.tsv", "reference/release.json"], "content_inspection_status": "not_downloaded_by_extractor"})
    behaviors = []
    for identifier, requirement, short_names, selectors in BEHAVIORS:
        names = ["net.minecraft." + short for short in short_names]
        selected = {name: [signature for signature in source_records[name]["all_signatures"] if any(selector in signature for selector in selectors)][:12] for name in names}
        behaviors.append({"id": identifier, "required_behavior": requirement, "source_classes": names,
                          "selected_method_signatures": selected, "source_signatures_verified": True,
                          "semantics_status": "requires_bytecode_or_reference_analysis_and_independent_fixtures"})
        add({"id": "behavior:" + identifier, "kind": "non_data_behavior", "required_behavior": requirement,
             "reference_inventory_status": "source_locations_identified", "reference_evidence": ["reference/behavior_inventory.json"], "source_classes": names})
        if identifier == "ticks" and (ROOT / "evidence/reference_tick_probe.json").exists():
            rows[-1]["behavioral_reference_status"] = "partial_narrow_fixture"
            rows[-1]["behavioral_reference_evidence"] = list(dict.fromkeys(rows[-1]["behavioral_reference_evidence"] + ["evidence/reference_tick_probe.json"]))
    for identifier, requirement in [
        ("bend_mod_semantics", "Typed Bend mods across every subsystem, dependency/conflict rules, reload, migration and client/server agreement"),
        ("live_api_mcp", "Deep live APIs and real MCP transport for gameplay, editing, mods, diagnostics and repeatable assertions"),
        ("laws_proofs", "Bend laws/proofs of the actual implementation, plus independent behavioral fixtures"),
        ("packaging", "Reproducible native macOS client/server packaging and installation"),
        ("performance", "Equivalent-workload benchmark against pinned Java release on this machine"),
    ]:
        add({"id": "product:" + identifier, "kind": "additional_product_requirement", "required_behavior": requirement,
             "reference_inventory_status": "outside_vanilla_data", "reference_evidence": ["AGENTS.md", "docs/STATUS.md"]})
    generated_ids = {row["id"] for row in rows}
    rows.extend(previous_rows[identifier] for identifier in sorted(previous_rows) if identifier not in generated_ids)
    write_json(coverage_path, {"pin": PIN, "inventory_is_implementation": False,
                             "behavioral_parity_established_by_inventory": False,
                             "assessment_rule": "Inventory, implementation and independent verification are separate. Preserve and update evidence per row; count identifiers, not coverage rows, for implementation claims.",
                             "rows": rows})
    for record in source_records.values():
        del record["all_signatures"]
    write_json(ROOT / "reference/behavior_inventory.json", {"pin": PIN, "curated_map_is_exhaustive_specification": False,
                                                            "source_kind": "Pinned client named compiled classes and javap declarations",
                                                            "source_classes": source_records, "obligation_groups": behaviors})
    write_json(ROOT / "evidence/reference_behavior_inventory.json", {"pin": PIN, "named_classes_verified": len(classes),
                                                                   "non_data_obligation_groups": len(BEHAVIORS), "coverage_rows": len(rows),
                                                                   "command": "python3 tools/reference_coverage.py", "behavioral_parity_established": False})
    print(json.dumps({"named_classes_verified": len(classes), "non_data_obligation_groups": len(BEHAVIORS), "coverage_rows": len(rows)}, sort_keys=True))


if __name__ == "__main__":
    main()
