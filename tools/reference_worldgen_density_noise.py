#!/usr/bin/env python3
"""NormalNoise participant for the parent's single pinned density JVM batch.

This module starts no JVM or native process. Java's actual codec, constructor,
random implementations and getter produce every expected output. Python only
selects inputs, converts explicit input words and checks the native wire format.
"""
from __future__ import annotations

import hashlib
import json
import struct
import zipfile
from pathlib import Path

from reference_inventory import ROOT

JAR = ROOT / "reference/cache/versions/26.3/server-26.3.jar"
SHIPPED = ("temperature", "vegetation", "continentalness", "erosion", "ridge", "offset")
SEEDS = ("0", "1", "9223372036854775808", "18446744073709551615")
COORDINATES = (
    (0.0, 0.0, 0.0),
    (-0.0, -0.0, -0.0),
    (0.1, -0.1, 0.5),
    (-17.5, -64.25, 31.75),
    (16777216.25, -1.0, 0.125),
    (-16777216.25, 320.5, -16384.75),
    (30000000.5, -64.0, -30000000.25),
    (5e-324, -5e-324, 0.0),
)

JAVA_IMPORTS = r"""
import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import com.mojang.serialization.JsonOps;
import net.minecraft.util.RandomSource;
import net.minecraft.world.level.levelgen.LegacyRandomSource;
import net.minecraft.world.level.levelgen.XoroshiroRandomSource;
import net.minecraft.world.level.levelgen.synth.NormalNoise;
import net.minecraft.world.level.levelgen.synth.Noise;
"""

# Insert these class members into the parent's one Java main class. Prefixes
# avoid collisions with its DAG participant's reflection and word helpers.
JAVA_HELPERS = r"""
  static Object dnField(Object object,String name) throws Exception {
    for(Class<?> type=object.getClass();type!=null;type=type.getSuperclass()) {
      try { var f=type.getDeclaredField(name);f.setAccessible(true);return f.get(object); }
      catch(NoSuchFieldException missing) { }
    }
    throw new NoSuchFieldException(object.getClass().getName()+"."+name);
  }
  static java.util.List<Long> dnWords(long value) {
    return java.util.List.of(value>>>32,value&0xffffffffL);
  }
  static java.util.List<Long> dnDoubleWords(double value) {
    return dnWords(Double.doubleToRawLongBits(value));
  }
  static long dnFloatWord(float value) {
    return Integer.toUnsignedLong(Float.floatToRawIntBits(value));
  }
  static double dnDouble(JsonArray words) {
    if(words.size()!=2)throw new IllegalArgumentException("double word count");
    return Double.longBitsToDouble((words.get(0).getAsLong()<<32)|words.get(1).getAsLong());
  }
  static java.util.Map<String,Object> dnSource(RandomSource source) throws Exception {
    if(source instanceof LegacyRandomSource) {
      var seed=(java.util.concurrent.atomic.AtomicLong)dnField(source,"seed");
      return java.util.Map.of("kind","legacy","words",dnWords(seed.get()));
    }
    var generator=dnField(source,"randomNumberGenerator");
    var words=new java.util.ArrayList<Long>();
    words.addAll(dnWords((long)dnField(generator,"seedLo")));
    words.addAll(dnWords((long)dnField(generator,"seedHi")));
    return java.util.Map.of("kind","xoroshiro","words",words);
  }
  static java.util.Map<String,Object> dnConfig(NormalNoise definition) throws Exception {
    var p=dnField(definition,"parameters");
    var modifiers=new java.util.ArrayList<Object>();
    for(var value:(java.util.List<?>)dnField(p,"amplitudeModifiers"))
      modifiers.add(dnDoubleWords(((Number)value).doubleValue()));
    return java.util.Map.of(
      "amplitude_bits",dnDoubleWords((double)dnField(p,"baseAmplitude")),
      "base_octave_word",Integer.toUnsignedLong((int)dnField(p,"baseOctave")),
      "octave_count",(int)dnField(p,"octaveCount"),
      "normalization",((Enum<?>)dnField(p,"normalize")).name().toLowerCase(java.util.Locale.ROOT),
      "modifier_bits",modifiers);
  }
  static java.util.List<Object> dnOctaves(NormalNoise definition) throws Exception {
    var output=new java.util.ArrayList<Object>();
    for(var octave:(java.util.List<?>)dnField(definition,"octaves")) {
      var seed=octave.getClass().getDeclaredMethod("seed");seed.setAccessible(true);
      output.add(java.util.Map.of(
        "index",Integer.toUnsignedLong((int)dnField(octave,"octaveIndex")),
        "frequency_bits",dnDoubleWords((double)dnField(octave,"frequency")),
        "amplitude_bits",dnDoubleWords((double)dnField(octave,"amplitude")),
        "seed",seed.invoke(octave)));
    }
    return output;
  }
  static java.util.List<Object> dnLayers(Noise noise) throws Exception {
    var output=new java.util.ArrayList<Object>();
    for(var layer:(Object[])dnField(noise,"layers")) {
      var producer=dnField(layer,"noise");
      var permutation=new java.util.ArrayList<Integer>();
      for(byte value:(byte[])dnField(producer,"perms"))permutation.add(Byte.toUnsignedInt(value));
      if(permutation.size()!=256)throw new IllegalStateException("actual PN permutation capacity changed");
      output.add(java.util.Map.of(
        "frequency_bits",dnDoubleWords((double)dnField(layer,"frequency")),
        "amplitude_bits",dnFloatWord((float)dnField(layer,"amplitude")),
        "offset_bits",java.util.List.of(
          dnDoubleWords((double)dnField(producer,"offsetX")),
          dnDoubleWords((double)dnField(producer,"offsetY")),
          dnDoubleWords((double)dnField(producer,"offsetZ"))),
        "permutation",permutation,
        "producer_class",producer.getClass().getName()));
    }
    return output;
  }
  static java.util.Map<String,Object> dnLoadedClass(Class<?> type) throws Exception {
    var member=type.getName().replace('.','/')+".class";
    try(var stream=type.getResourceAsStream("/"+member)) {
      if(stream==null)throw new IllegalStateException("missing actual class "+member);
      var data=stream.readAllBytes();
      var domain=type.getProtectionDomain();
      var source=domain==null?null:domain.getCodeSource();
      var loader=type.getClassLoader();
      return java.util.Map.of("member",member,"bytes",data.length,
        "sha256",java.util.HexFormat.of().formatHex(java.security.MessageDigest.getInstance("SHA-256").digest(data)),
        "code_source",source==null?"jrt:/"+type.getModule().getName():source.getLocation().toString(),
        "class_loader",loader==null?"bootstrap":loader.getClass().getName());
    }
  }
  static java.util.Map<String,Object> densityNoiseObserve(JsonArray cases) throws Exception {
    var output=new java.util.ArrayList<Object>();
    for(var element:cases) {
      var input=element.getAsJsonObject();
      var row=new java.util.TreeMap<String,Object>();
      var seed=Long.parseUnsignedLong(input.get("seed").getAsString());
      var name=input.get("name").getAsString();
      var legacy=input.get("legacy").getAsBoolean();
      RandomSource root=legacy?new LegacyRandomSource(seed):new XoroshiroRandomSource(seed);
      var factory=root.forkPositional();
      var source=factory.fromHashOf(name);
      row.put("id",input.get("id").getAsString());
      row.put("before_source",dnSource(source));
      NormalNoise definition;
      try {
        definition=NormalNoise.DIRECT_CODEC.parse(JsonOps.INSTANCE,
          JsonParser.parseString(input.get("parameter_json").getAsString())).getOrThrow();
      } catch(Exception refused) {
        row.put("status","codec_refused");
        row.put("exception",refused.getClass().getName());
        row.put("message",String.valueOf(refused.getMessage()));
        row.put("post_source",dnSource(source));
        output.add(row);continue;
      }
      row.put("decoded_config",dnConfig(definition));
      row.put("normalization_bits",dnDoubleWords((double)dnField(definition,"normalizationFactor")));
      var interval=definition.range();
      row.put("range_min_bits",dnFloatWord(((Number)dnField(interval,"min")).floatValue()));
      row.put("range_max_bits",dnFloatWord(((Number)dnField(interval,"max")).floatValue()));
      row.put("octaves",dnOctaves(definition));
      Noise noise;
      if(input.get("kind").getAsString().equals("unsupported_biome")) {
        // RandomState$1's actual key-specific path ignores the selected root
        // algorithm and uses LegacyRandom(seed+0/seed+1), respectively.
        source=new LegacyRandomSource(seed+(name.equals("minecraft:nether/vegetation")?1L:0L));
        row.put("legacy_initializer_before_source",dnSource(source));
        noise=definition.createForLegacyNetherBiome(source);
        row.put("status","legacy_initializer_observed");
      } else {
        noise=definition.create(source);
        row.put("status","created");
      }
      row.put("post_source",dnSource(source));
      var layers=dnLayers(noise);row.put("layers",layers);
      row.put("stack_class",noise.getClass().getName());
      var samples=new java.util.ArrayList<Long>();
      for(var coordinate:input.getAsJsonArray("coordinates")) {
        var point=coordinate.getAsJsonArray();
        if(point.size()!=3)throw new IllegalArgumentException("coordinate dimension");
        samples.add(dnFloatWord(noise.get(dnDouble(point.get(0).getAsJsonArray()),
          dnDouble(point.get(1).getAsJsonArray()),dnDouble(point.get(2).getAsJsonArray()))));
      }
      row.put("scalar_bits",samples);
      row.put("layers_unchanged_after_getters",layers.equals(dnLayers(noise)));
      output.add(row);
    }
    var pins=new java.util.ArrayList<Object>();
    for(var name:new String[]{
      "net.minecraft.world.level.levelgen.synth.NormalNoise",
      "net.minecraft.world.level.levelgen.synth.NormalNoise$Parameters",
      "net.minecraft.world.level.levelgen.synth.NormalNoise$OctaveInfo",
      "net.minecraft.world.level.levelgen.synth.NormalNoise$Normalization",
      "net.minecraft.world.level.levelgen.synth.NormalNoise$Builder",
      "net.minecraft.world.level.levelgen.synth.NoiseStack",
      "net.minecraft.world.level.levelgen.synth.NoiseStack$Builder",
      "net.minecraft.world.level.levelgen.synth.NoiseStack$Layer",
      "net.minecraft.world.level.levelgen.synth.NoiseStack$Perlin",
      "net.minecraft.world.level.levelgen.synth.PerlinNoise",
      "net.minecraft.world.level.levelgen.synth.GradientNoise",
      "net.minecraft.world.level.levelgen.synth.LegacyFbmInitializer",
      "net.minecraft.world.level.levelgen.LegacyRandomSource",
      "net.minecraft.world.level.levelgen.XoroshiroRandomSource",
      "net.minecraft.world.level.levelgen.Xoroshiro128PlusPlus",
      "net.minecraft.util.Interval",
      "java.util.stream.DoublePipeline",
      "java.util.stream.Collectors"})pins.add(dnLoadedClass(Class.forName(name)));
    return java.util.Map.of("cases",output,"loaded_classes",pins,
      "java_runtime",Runtime.version().toString(),
      "scope","Actual NormalNoise codec/normalization/range/octaves, seeded constructors, complete layers and scalar getters; native fuel/refusal policy is checked separately");
  }
"""


def words(value: float) -> list[int]:
    """Encode a chosen input; never calculate a noise output."""
    return list(struct.unpack(">II", struct.pack(">d", value)))


def config_words(parameter_json: str) -> dict:
    value = json.loads(parameter_json)
    normalization = value.get("normalize", True)
    if normalization is True:
        normalization = "enabled"
    elif normalization is False:
        normalization = "disabled"
    return {
        "amplitude_bits": words(float(value.get("base_amplitude", 1.0))),
        "base_octave_word": int(value["base_octave"]) & 0xFFFFFFFF,
        "octave_count": int(value.get("octave_count", 1)),
        "normalization": normalization,
        "modifier_bits": [words(float(v)) for v in value.get("amplitude_modifiers", [])],
    }


def input_cases() -> dict:
    """Return {'cases': [...], 'installed_entries': [...]} for the main batch."""
    cases, entries = [], []
    coordinates = [[words(axis) for axis in point] for point in COORDINATES]

    def add(label, name, parameter_json, seed="0", legacy=False, kind="normal", fuel=64):
        cases.append({"id": f"{label}/{seed}/{'legacy' if legacy else 'xoroshiro'}",
                      "name": name, "parameter_json": parameter_json, "seed": seed,
                      "legacy": legacy, "kind": kind, "fuel": fuel,
                      "coordinates": coordinates})

    with zipfile.ZipFile(JAR) as jar:
        shipped = {}
        for name in (*SHIPPED, "nether/temperature", "nether/vegetation"):
            member = "data/minecraft/worldgen/noise/" + name + ".json"
            raw = jar.read(member)
            shipped[name] = raw.decode()
            entries.append({"member": member, "bytes": len(raw),
                            "sha256": hashlib.sha256(raw).hexdigest()})
        for seed in SEEDS:
            for legacy in (False, True):
                for name in SHIPPED:
                    add(name, "minecraft:" + name, shipped[name], seed, legacy)
        for legacy in (False, True):
            for name in ("nether/temperature", "nether/vegetation"):
                add(name, "minecraft:" + name, shipped[name], "18446744073709551615",
                    legacy, "unsupported_biome")

    custom = (
        ("default-enabled", '{"base_octave":0}'),
        ("default-disabled", '{"base_octave":-2,"base_amplitude":1.25,"octave_count":3,"normalize":false}'),
        ("default-legacy", '{"base_octave":-10,"octave_count":6,"normalize":"legacy"}'),
        ("zero-modifiers", '{"base_octave":-9,"octave_count":3,"amplitude_modifiers":[0.0,0.0,0.0]}'),
        ("underflow-enabled", '{"base_octave":-1,"base_amplitude":9.999999747378752E-6,"amplitude_modifiers":[5e-324]}'),
        ("underflow-disabled", '{"base_octave":-1,"base_amplitude":9.999999747378752E-6,"normalize":false,"amplitude_modifiers":[5e-324]}'),
        ("sparse-legacy", '{"base_octave":-9,"base_amplitude":0.9494731054427978,"octave_count":5,"normalize":"legacy","amplitude_modifiers":[0,1,0,0,2]}'),
        ("count32-low", '{"base_octave":-32,"octave_count":32}'),
        ("count32-high", '{"base_octave":32,"base_amplitude":1000000,"octave_count":32,"normalize":false}'),
        ("compensated", '{"base_octave":-3,"octave_count":6,"amplitude_modifiers":[1000000,1e-12,1000000,1e-6,0.125,2]}'),
    )
    invalid = (
        ("amplitude-low", '{"base_octave":0,"base_amplitude":0}'),
        ("octave-low", '{"base_octave":-33}'),
        ("count-low", '{"base_octave":0,"octave_count":0}'),
        ("count-high", '{"base_octave":0,"octave_count":33}'),
        ("modifier-count", '{"base_octave":0,"octave_count":2,"amplitude_modifiers":[1]}'),
        ("modifier-negative", '{"base_octave":0,"amplitude_modifiers":[-1]}'),
        ("modifier-negative-zero", '{"base_octave":0,"amplitude_modifiers":[-0.0]}'),
    )
    for legacy in (False, True):
        for label, parameters in custom:
            add(label, "bendex:" + label, parameters, "1", legacy,
                fuel=0 if label == "zero-modifiers" else 64)
        for label, parameters in invalid:
            add(label, "bendex:" + label, parameters, "1", legacy, "invalid_config")
        add("zero-fuel", "bendex:zero-fuel", '{"base_octave":-1}', "1", legacy,
            "fuel_refusal", 0)
    if len({c["id"] for c in cases}) != len(cases):
        raise AssertionError("duplicate density-noise case identity")
    return {"cases": cases, "installed_entries": entries}


def fixture(case: dict, mode: str | None = None) -> str:
    """One literal native argument, after --gpu off --threads 1."""
    mode = mode or ("api" if case["kind"] == "unsupported_biome" else "normal")
    config = config_words(case["parameter_json"])
    seed = int(case["seed"])
    fields = (mode, seed >> 32, seed & 0xFFFFFFFF, int(case["legacy"]), case["name"],
              case["fuel"], *config["amplitude_bits"], config["base_octave_word"],
              config["octave_count"], config["normalization"],
              ";".join(",".join(map(str, row)) for row in config["modifier_bits"]),
              ";".join(",".join(str(word) for axis in point for word in axis)
                       for point in case["coordinates"]))
    return "|".join(map(str, fields))


def _unsigned(text: str, limit: int = 0xFFFFFFFF) -> int:
    if not text or not text.isascii() or not text.isdecimal():
        raise ValueError("invalid unsigned native word: " + repr(text))
    value = int(text)
    if value > limit:
        raise ValueError("native word outside admitted width")
    return value


def _words(text: str, count: int) -> list[int]:
    values = [_unsigned(part) for part in text.split(",")]
    if len(values) != count:
        raise ValueError(f"expected {count} native words, got {len(values)}")
    return values


def _rows(text: str) -> list[str]:
    if not text:
        return []
    if not text.endswith(";"):
        raise ValueError("native rows have no final separator")
    rows = text[:-1].split(";")
    if any(not row for row in rows):
        raise ValueError("empty interior native row")
    return rows


def _source(text: str) -> dict:
    fields = text.split(",")
    expected = {"legacy": 2, "xoroshiro": 4}.get(fields[0])
    if expected is None or len(fields) != expected + 1:
        raise ValueError("native Source constructor/word count")
    return {"kind": fields[0], "words": [_unsigned(word) for word in fields[1:]]}


def parse_native(stdout: str) -> dict:
    """Strict complete parser: surplus lines/fields/permutation words fail."""
    lines = stdout.splitlines()
    if len(lines) != 1:
        raise ValueError("expected exactly one native result line")
    fields = lines[0].split("|")
    if fields[0] == "fail":
        if len(fields) not in (2, 3):
            raise ValueError("native refusal field count")
        result = {"status": "refused", "message": fields[1]}
        if len(fields) == 3:
            result["source"] = _source(fields[2])
        return result
    if fields[0] == "api":
        if len(fields) != 2:
            raise ValueError("native public-get field count")
        return {"status": "api", "scalar_bits": [_unsigned(row) for row in _rows(fields[1])]}
    if fields[0] != "normal" or len(fields) != 7:
        raise ValueError("native NormalNoise constructor field count")
    octaves = []
    for row in _rows(fields[4]):
        value = _words(row, 5)
        octaves.append({"index": value[0], "frequency_bits": value[1:3],
                        "amplitude_bits": value[3:5]})
    layers = []
    for row in _rows(fields[5]):
        if not row.endswith(","):
            raise ValueError("native permutation has no final separator")
        value = _words(row[:-1], 265)
        permutation = value[9:]
        if sorted(permutation) != list(range(256)):
            raise ValueError("native permutation is not the complete byte permutation")
        layers.append({"frequency_bits": value[:2], "amplitude_bits": value[2],
                       "offset_bits": [value[3:5], value[5:7], value[7:9]],
                       "permutation": permutation})
    return {"status": "created", "post_source": _source(fields[1]),
            "normalization_bits": _words(fields[2], 2),
            "range_max_bits": _unsigned(fields[3]), "octaves": octaves,
            "layers": layers, "scalar_bits": [_unsigned(row) for row in _rows(fields[6])]}


def check_native(case: dict, observed: dict, stdout: str, mode: str | None = None) -> dict:
    """Compare to one retained real Java row; never synthesize Java results."""
    if observed.get("id") != case["id"]:
        raise AssertionError("Java/native case identity mismatch")
    actual = parse_native(stdout)
    kind = case["kind"]
    if kind == "invalid_config":
        if observed.get("status") != "codec_refused":
            raise AssertionError("the actual Java codec admitted a proposed refusal")
        wanted = {"status": "refused",
                  "message": "normal-noise configuration is outside the pinned finite codec ranges",
                  "source": observed["before_source"]}
        if observed["post_source"] != observed["before_source"]:
            raise AssertionError("Java codec refusal advanced the source")
        if actual != wanted:
            raise AssertionError((case["id"], "configuration/source refusal", actual, wanted))
        return {"id": case["id"], "scope": "actual codec refusal and complete native source retention"}
    if kind == "unsupported_biome":
        if observed.get("status") != "legacy_initializer_observed":
            raise AssertionError("actual Java legacy biome constructor was not observed")
        wanted = {"status": "refused", "message": "normal-noise legacy Nether biome initializer is unavailable"}
        if actual != wanted:
            raise AssertionError((case["id"], "unsupported initializer refusal", actual, wanted))
        return {"id": case["id"], "scope": "explicit native refusal of the observed real legacy initializer"}
    if observed.get("status") != "created":
        raise AssertionError((case["id"], "actual Java constructor failed", observed))
    if config_words(case["parameter_json"]) != observed["decoded_config"]:
        raise AssertionError((case["id"], "Python fixture inputs differ from actual Java decoded Config"))
    if not observed["layers_unchanged_after_getters"]:
        raise AssertionError("actual Java getter changed constructor layer data")
    if kind == "fuel_refusal":
        wanted = {"status": "refused", "message": "noise permutation random rejection fuel exhausted",
                  "source": observed["before_source"]}
        if actual != wanted:
            raise AssertionError((case["id"], "fuel exhaustion complete rollback", actual, wanted))
        return {"id": case["id"], "scope": "explicit native fuel policy and complete constructor rollback"}
    if mode == "api":
        wanted = {"status": "api", "scalar_bits": observed["scalar_bits"]}
        if actual != wanted:
            raise AssertionError((case["id"], "actual public constructor/getter scalar words differ"))
        return {"id": case["id"], "scope": "actual public constructor and getter scalar raw-word parity",
                "scalar_words": len(actual["scalar_bits"])}
    expected = {"status": "created", "post_source": observed["post_source"],
                "normalization_bits": observed["normalization_bits"],
                "range_max_bits": observed["range_max_bits"],
                "octaves": [{k: row[k] for k in ("index", "frequency_bits", "amplitude_bits")}
                            for row in observed["octaves"]],
                "layers": [{k: row[k] for k in ("frequency_bits", "amplitude_bits", "offset_bits", "permutation")}
                           for row in observed["layers"]], "scalar_bits": observed["scalar_bits"]}
    if actual != expected:
        differences = [key for key in expected if actual.get(key) != expected[key]]
        raise AssertionError((case["id"], "exact Java/native words differ", differences))
    if len(actual["scalar_bits"]) != len(case["coordinates"]):
        raise AssertionError("native scalar count does not match the selected inputs")
    return {"id": case["id"], "scope": "actual complete constructor and scalar raw-word parity",
            "octaves": len(actual["octaves"]), "layers": len(actual["layers"]),
            "permutation_words": sum(len(row["permutation"]) for row in actual["layers"]),
            "scalar_words": len(actual["scalar_bits"])}


def validate_observations(batch: dict, observed: dict) -> dict[str, dict]:
    """Validate the real batch's shape and official Minecraft class identities.

    JDK class pins are retained separately: java.base is loaded from jrt rather
    than the Minecraft jar. Their actual words are already observed through the
    real NormalNoise constructor's DoubleStream.sum call.
    """
    rows = observed["cases"]
    by_id = {row["id"]: row for row in rows}
    ids = {case["id"] for case in batch["cases"]}
    if len(by_id) != len(rows) or len(ids) != len(batch["cases"]) or set(by_id) != ids:
        raise AssertionError("density-noise batch has missing, extra or duplicate case identities")
    for case in batch["cases"]:
        row = by_id[case["id"]]
        wanted = {"invalid_config": "codec_refused", "unsupported_biome": "legacy_initializer_observed"}.get(case["kind"], "created")
        if row["status"] != wanted:
            raise AssertionError((case["id"], "actual Java case outcome differs", row["status"], wanted))
        if wanted == "codec_refused":
            if row["post_source"] != row["before_source"]:
                raise AssertionError("refused Java codec advanced its supplied source")
            continue
        if row["decoded_config"] != config_words(case["parameter_json"]):
            raise AssertionError((case["id"], "fixture and actual Java decoded words differ"))
        if len(row["scalar_bits"]) != len(case["coordinates"]) or not row["layers_unchanged_after_getters"]:
            raise AssertionError("actual Java getter result/state observation differs")
        for layer in row["layers"]:
            if sorted(layer["permutation"]) != list(range(256)):
                raise AssertionError("actual Java constructor did not expose its complete byte permutation")
        if case["id"].startswith("zero-modifiers/"):
            if row["layers"] or row["octaves"] or row["post_source"] == row["before_source"]:
                raise AssertionError("all-zero modifier constructor/fork observation differs")
        if case["id"].startswith("underflow-"):
            if len(row["octaves"]) != 1 or len(row["layers"]) != 2 or row["octaves"][0]["amplitude_bits"] != [0, 0]:
                raise AssertionError("nonzero underflow modifier's actual construction differs")
    pins = observed["loaded_classes"]
    if len({pin["member"] for pin in pins}) != len(pins):
        raise AssertionError("duplicate actual loaded-class pin")
    with zipfile.ZipFile(JAR) as jar:
        for pin in pins:
            if pin["member"].startswith("net/minecraft/"):
                data = jar.read(pin["member"])
                if len(data) != pin["bytes"] or hashlib.sha256(data).hexdigest() != pin["sha256"]:
                    raise AssertionError("actual loaded Minecraft class differs from the pinned jar: " + pin["member"])
    for member in ("java/util/stream/DoublePipeline.class", "java/util/stream/Collectors.class"):
        matching = [pin for pin in pins if pin["member"] == member]
        if len(matching) != 1 or matching[0]["code_source"] != "jrt:/java.base" or matching[0]["class_loader"] != "bootstrap":
            raise AssertionError("actual compensated-sum runtime class provenance missing")
    return by_id
