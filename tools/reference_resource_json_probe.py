#!/usr/bin/env python3
"""Observe pinned Minecraft 26.3 reader JSON behavior through production Java APIs.

Only synthetic text is supplied. No launcher profiles, accounts, saves, native
window, client instance, or extracted Gson parser algorithm are involved.
"""
from __future__ import annotations

import argparse
import collections
import hashlib
import json
import pathlib
import subprocess
import zipfile

from reference_inventory import ROOT, JAVA, fingerprint
from reference_model_probe import CLIENT, verified_client_classpath

OUTPUT = ROOT / "reference/resource_json.json"
CACHE = ROOT / "reference/cache/resource-json-probe"


def encoded(value):
    # Lone UTF-16 surrogates are intentional fixtures; never encode them as UTF-8.
    return json.dumps(value, ensure_ascii=True, sort_keys=True, separators=(",", ":")).encode("ascii")


def sha(value):
    return hashlib.sha256(value).hexdigest()


def fixture_text(case):
    """Expand recorded stress inputs; also checks the Java generator's exact input."""
    if "input" in case:
        return case["input"]
    spec = case["input_spec"]
    kind, size = spec["kind"], spec["size"]
    if kind == "nested_array":
        return "[" * size + "0" + "]" * size
    if kind == "nested_object":
        return '{"a":' * size + "0" + "}" * size
    if kind == "number_repeat":
        return "1" * size
    if kind == "object_number_repeat":
        return '{"a":' + "1" * size + "}"
    if kind == "exponent_repeat":
        return "1e" + "1" * size
    if kind == "object_exponent_repeat":
        return '{"a":1e' + "1" * size + "}"
    if kind == "quoted_repeat":
        return '"' + "x" * size + '"'
    if kind == "unquoted_repeat":
        return "x" * size
    if kind == "array_repeat":
        return "[" + "0," * (size - 1) + "0]"
    raise ValueError("Unknown input spec: " + kind)


def fixtures():
    out = []

    def add(identifier, category, text):
        out.append({"id": identifier, "category": category, "input": text})

    for token in ["-0", "-0.0", "0", "0.0", "1e0", "1E+0", "01", "-01", "+1", ".5", "5.",
                  "1e", "1e+", "1e-", "NaN", "Infinity", "-Infinity", "+Infinity", "nan", "inf",
                  "0x10", "0x1p0", "1_0", "1f", "1d", "9223372036854775807", "9223372036854775808",
                  "-9223372036854775808", "-9223372036854775809", "1e9999", "true", "TRUE", "TrUe",
                  "false", "FALSE", "null", "nUlL", "undefined", "word", "truex", "null0"]:
        add("token_" + str(len(out)), "tokens", token)
    for name, text in [
        ("double_quote", '"word"'), ("single_quote", "'word'"), ("unquoted", "a-b_./:+$@~?%&*"),
        ("double_apostrophe", '"a\'b"'), ("single_double_quote", "'a\"b'"),
        ("empty_double", '""'), ("empty_single", "''"),
        ("unquoted_space", "two words"), ("unquoted_equals", "a=b"), ("unquoted_backslash", "a\\b"),
        ("object_unquoted", "{a:1,b:word}"), ("object_single", "{'a':'word'}"),
        ("object_equals", "{a=1}"), ("object_arrow", "{a=>1}"), ("object_semicolon", "{a:1;b:2}"),
        ("object_duplicate", "{a:1,b:2,a:3}"),
        ("object_duplicate_strict", '{"a":1,"b":2,"a":3}'),
        ("object_nested_duplicate", '{"a":{"x":1,"x":2},"b":0,"a":[3]}'),
        ("object_escape_duplicate", '{"a":1,"\\u0061":2,"b":3}'),
        ("object_null_key", "{null:1,true:2,01:3}"),
        ("object_missing_colon", "{a 1}"), ("object_missing_value", "{a:}"),
        ("object_missing_name", "{:1}"), ("object_trailing_comma", "{a:1,}"),
        ("object_trailing_semicolon", "{a:1;}"), ("object_double_comma", "{a:1,,b:2}"),
        ("array_empty", "[]"), ("array_leading_comma", "[,1]"), ("array_trailing_comma", "[1,]"),
        ("array_only_comma", "[,]"), ("array_two_commas", "[,,]"),
        ("array_internal_missing", "[1,,2]"), ("array_semicolon", "[1;2]"),
        ("array_trailing_semicolon", "[1;]"), ("array_only_semicolon", "[;]"),
        ("array_mixed_separators", "[1;,2]"), ("array_missing_separator", "[1 2]"),
        ("empty", ""), ("whitespace", " \t\r\n"), ("bom_empty", "\ufeff"),
        ("bom_first", "\ufeff{}"), ("bom_after_space", " \ufeff{}"), ("bom_twice", "\ufeff\ufeff{}"),
        ("bom_after_root", "{}\ufeff"), ("bom_in_string", '"\ufeff"'),
        ("xssi", ")]}'\n{}"), ("xssi_leading_space", " \t)]}'\n{}"),
        ("xssi_crlf", ")]}'\r\n{}"), ("xssi_no_lf", ")]}'{}"),
        ("line_comment", "// comment\n{}"), ("line_comment_eof", "// comment"),
        ("block_comment", "/* comment */{}"), ("block_unterminated", "/* comment"),
        ("hash_comment", "# comment\n{}"), ("hash_comment_eof", "# comment"),
        ("comments_inside", '{/*a*/"a"/*b*/:/*c*/1/*d*/,//e\n"b":2#f\n}'),
        ("slash_in_unquoted", "a/b"), ("hash_in_unquoted", "a#b"),
        ("trailing_line_comment", "{}// comment"), ("trailing_hash_comment", "{}# comment"),
        ("trailing_block_comment", "{}/* comment */"),
        ("root_objects", "{} {}"), ("root_arrays", "[] []"), ("root_numbers", "1 2"),
        ("root_null_object", "null {}"), ("root_null_word", "null xyz"),
        ("root_null_bad", "null ["), ("root_object_bad", "{} ["),
        ("root_object_immediate", "{}{}"), ("root_object_trailing_word", "{}word"),
        ("root_object_trailing_close", "{}]"), ("root_object_trailing_comma", "{},"),
        ("prefix_number_x", "1x"), ("prefix_true_x", "truex"), ("prefix_null_x", "nullx"),
        ("prefix_number_slash_x", "1/x"), ("prefix_number_line_comment", "1//x"),
        ("prefix_number_space_comment", "1 /*x*/"), ("prefix_true_slash_x", "true/x"),
        ("prefix_string_x", '"x"x'), ("prefix_object_x", "{}x"), ("prefix_array_x", "[]x"),
        ("prefix_number_comma", "1,2"), ("prefix_number_semicolon", "1;2"),
        ("prefix_object_unterminated_comment", '{"a":1} /*unterminated'),
        ("eof_array", "[1"), ("eof_object", '{"a":1'), ("eof_quote", '"word'),
        ("eof_escape", '"a\\'), ("eof_unicode", '"\\u123"'),
        ("model_defaults", "{}"), ("model_comments", "{/*x*/}"),
        ("model_parent_single", "{'parent':'block/stone'}"),
        ("model_parent_unquoted", "{parent:block/stone}"),
        ("model_parent_duplicate", '{"parent":"block/stone","parent":"block/dirt"}'),
        ("model_trailing_bad", '{} {bad'), ("model_null", "null"),
        ("model_ambient_uppercase", '{"ambientocclusion":TRUE}'),
        ("model_ambient_string", '{"ambientocclusion":"false"}'),
        ("model_unknown_numeric", '{"unknown":-0,"unknown2":1e0}'),
    ]:
        add(name, "reader_forms", text)
    for name, text in [
        ("escapes_standard", '"\\\"\\\\\\/\\b\\f\\n\\r\\t"'),
        ("escape_apostrophe", '"\\\'"'), ("escape_unknown", '"\\q"'),
        ("escape_linefeed", '"a\\\nb"'), ("escape_cr", '"a\\\rb"'),
        ("escape_crlf", '"a\\\r\nb"'), ("escape_unicode_upper", '"\\uABCD"'),
        ("escape_unicode_bad", '"\\u12xz"'), ("escape_unicode_short", '"\\u123"'),
        ("escape_high_lone", '"\\ud800"'), ("escape_low_lone", '"\\udc00"'),
        ("escape_surrogate_pair", '"\\ud83d\\ude00"'),
        ("escape_surrogate_reversed", '"\\udc00\\ud800"'),
        ("escape_surrogate_separated", '"\\ud800x\\udc00"'),
        ("raw_surrogate_high", '"\ud800"'), ("raw_surrogate_low", '"\udc00"'),
        ("raw_surrogate_pair", '"\ud83d\ude00"'), ("raw_emoji", '"😀"'),
        ("key_surrogate", '{"\\ud800":1,"\\ud800":2,"x":3}'),
        ("key_supplementary_raw_escape", '{"😀":1,"\\ud83d\\ude00":2,"b":3}'),
        ("key_lone_raw_escape", '{"\ud800":1,"\\ud800":2,"b":3}'),
        ("unquoted_surrogate", "\ud800"), ("single_escape_apostrophe", "'a\\'b'"),
        ("single_escape_double", "'a\\\"b'"),
    ]:
        add(name, "escapes_utf16", text)
    for code in [0, 1, 8, 9, 10, 11, 12, 13, 31, 32, 127, 0x85, 0xa0, 0x2028, 0x2029]:
        add(f"raw_quoted_{code:04x}", "controls", '"a' + chr(code) + 'b"')
        add(f"whitespace_{code:04x}", "controls", chr(code) + '{}')
    for code in [*range(128), 0x85, 0xa0, 0x2028, 0xfeff]:
        for token in ["1", "true"]:
            add(f"delimiter_{token}_{code:04x}", "delimiter_sweep", token + chr(code) + "x")
    for depth in [0, 1, 31, 32, 63, 64, 127, 128, 253, 254, 255, 256, 257, 511, 512, 1024]:
        for kind in ["nested_array", "nested_object"]:
            out.append({"id": f"{kind}_{depth}", "category": "depth", "input_spec": {"kind": kind, "size": depth}})
    for size in [512, 1023, 1024, 1025, 2048, 10000, 16384]:
        for kind in ["number_repeat", "object_number_repeat"]:
            out.append({"id": f"{kind}_{size}", "category": "size", "input_spec": {"kind": kind, "size": size}})
    for size in [1021, 1022, 1023, 4096]:
        for kind in ["exponent_repeat", "object_exponent_repeat"]:
            out.append({"id": f"{kind}_{size}", "category": "size", "input_spec": {"kind": kind, "size": size}})
    for kind in ["quoted_repeat", "unquoted_repeat", "array_repeat"]:
        for size in ([1024, 16384, 65536, 262144, 1048576] if kind != "array_repeat" else [16384, 65536]):
            out.append({"id": f"{kind}_{size}", "category": "size", "input_spec": {"kind": kind, "size": size}})
    if len({x["id"] for x in out}) != len(out):
        raise ValueError("Duplicate fixture id")
    return out


JAVA_SOURCE = r'''
import com.google.gson.*;
import com.google.gson.stream.*;
import net.minecraft.util.GsonHelper;
import net.minecraft.client.resources.model.cuboid.CuboidModel;
import java.io.*;
import java.nio.file.*;
import java.nio.charset.*;
import java.security.*;
import java.util.*;

class ReferenceResourceJsonProbe {
 static final Gson G = new GsonBuilder().serializeNulls().disableHtmlEscaping().create();
 static String hex(String s) { var b=new StringBuilder(); for(int i=0;i<s.length();i++) b.append(String.format("%04x",(int)s.charAt(i))); return b.toString(); }
 static String ascii(String s) {var b=new StringBuilder();for(int i=0;i<s.length();i++){char c=s.charAt(i);if(c>127)b.append(String.format("\\u%04x",(int)c));else b.append(c);}return b.toString();}
 static boolean lone(String s) { for(int i=0;i<s.length();i++){ char c=s.charAt(i); if(Character.isHighSurrogate(c)){if(i+1<s.length()&&Character.isLowSurrogate(s.charAt(i+1)))i++;else return true;}else if(Character.isLowSurrogate(c))return true;} return false; }
 static JsonObject string(String s) {var o=new JsonObject();o.addProperty("utf16_hex",hex(s));o.addProperty("has_unpaired_surrogate",lone(s));return o;}
 static JsonObject project(JsonElement e) {
  var o=new JsonObject();
  if(e==null||e.isJsonNull()){o.addProperty("kind","null");return o;}
  if(e.isJsonPrimitive()){var p=e.getAsJsonPrimitive();if(p.isBoolean()){o.addProperty("kind","boolean");o.addProperty("value",p.getAsBoolean());}else if(p.isNumber()){o.addProperty("kind","number");o.addProperty("lexeme",p.getAsString());}else{o=string(p.getAsString());o.addProperty("kind","string");}return o;}
  if(e.isJsonArray()){o.addProperty("kind","array");var a=new JsonArray();for(var v:e.getAsJsonArray())a.add(project(v));o.add("elements",a);return o;}
  o.addProperty("kind","object");var a=new JsonArray();for(var entry:e.getAsJsonObject().entrySet()){var v=string(entry.getKey());v.add("value",project(entry.getValue()));a.add(v);}o.add("members",a);return o;
 }
 static String digestUtf16(String s)throws Exception{var d=MessageDigest.getInstance("SHA-256");for(int i=0;i<s.length();i++){char c=s.charAt(i);d.update((byte)(c>>8));d.update((byte)c);}return HexFormat.of().formatHex(d.digest());}
 record At(JsonElement value,int depth){}
 static JsonObject summary(JsonElement e)throws Exception{
  var o=new JsonObject();var counts=new TreeMap<String,Integer>();var stack=new ArrayDeque<At>();stack.push(new At(e,0));int max=0,total=0;String largest=null,largestKind=null;
  while(!stack.isEmpty()){var at=stack.pop();var v=at.value();max=Math.max(max,at.depth());total++;String k=v.isJsonNull()?"null":v.isJsonArray()?"array":v.isJsonObject()?"object":v.getAsJsonPrimitive().isBoolean()?"boolean":v.getAsJsonPrimitive().isNumber()?"number":"string";counts.merge(k,1,Integer::sum);if(k.equals("string")||k.equals("number")){String s=v.getAsString();if(largest==null||s.length()>largest.length()){largest=s;largestKind=k;}}if(v.isJsonArray())for(var x:v.getAsJsonArray())stack.push(new At(x,at.depth()+1));if(v.isJsonObject())for(var x:v.getAsJsonObject().entrySet())stack.push(new At(x.getValue(),at.depth()+1));}
  o.add("node_kinds",G.toJsonTree(counts));o.addProperty("node_count",total);o.addProperty("max_depth",max);if(largest!=null){var s=new JsonObject();s.addProperty("kind",largestKind);s.addProperty("utf16_length",largest.length());s.addProperty("utf16be_sha256",digestUtf16(largest));s.addProperty("has_unpaired_surrogate",lone(largest));s.addProperty("prefix",largest.substring(0,Math.min(32,largest.length())));s.addProperty("suffix",largest.substring(Math.max(0,largest.length()-32)));o.add("largest_scalar",s);}return o;
 }
 static void message(JsonObject o,String m){o.addProperty("message",m==null?null:m.substring(0,Math.min(512,m.length())));if(m!=null&&m.length()>512){try{o.addProperty("message_truncated",true);o.addProperty("message_utf16_length",m.length());o.addProperty("message_utf16be_sha256",digestUtf16(m));}catch(Exception ex){throw new AssertionError(ex);}}}
 static JsonObject err(Throwable e){var o=new JsonObject();o.addProperty("status","error");o.addProperty("error_class",e.getClass().getName());message(o,e.getMessage());var causes=new JsonArray();for(var c=e.getCause();c!=null;c=c.getCause()){var x=new JsonObject();x.addProperty("error_class",c.getClass().getName());message(x,c.getMessage());causes.add(x);}o.add("causes",causes);return o;}
 static JsonObject tree(String text,String mode,boolean compact)throws Exception{JsonElement value;try{switch(mode){case "parse_reader":value=JsonParser.parseReader(new StringReader(text));break;case "parse_json_reader":value=JsonParser.parseReader(new JsonReader(new StringReader(text)));break;case "gson_helper_tree":value=GsonHelper.fromJson(G,new StringReader(text),JsonElement.class);break;default:throw new IllegalArgumentException(mode);}}catch(Throwable e){return err(e);}var o=new JsonObject();o.addProperty("status","ok");o.add(compact?"tree_summary":"tree",compact?summary(value):project(value));return o;}
 static JsonObject model(String text){CuboidModel m;try{m=CuboidModel.fromStream(new StringReader(text));}catch(Throwable e){return err(e);}var o=new JsonObject();o.addProperty("status","ok");var s=new JsonObject();s.addProperty("parent",m.parent()==null?null:m.parent().toString());s.addProperty("gui_light",m.guiLight()==null?null:m.guiLight().toString());s.addProperty("ambient_occlusion",m.ambientOcclusion());s.addProperty("geometry_class",m.geometry()==null?null:m.geometry().getClass().getName());var keys=new JsonArray();for(var key:m.textureSlots().values().keySet())keys.add(string(key));s.add("texture_keys",keys);o.add("summary",s);return o;}
 static String input(JsonObject c){if(c.has("input"))return c.get("input").getAsString();var s=c.getAsJsonObject("input_spec");int n=s.get("size").getAsInt();return switch(s.get("kind").getAsString()){case "nested_array"->"[".repeat(n)+"0"+"]".repeat(n);case "nested_object"->"{\"a\":".repeat(n)+"0"+"}".repeat(n);case "number_repeat"->"1".repeat(n);case "object_number_repeat"->"{\"a\":"+"1".repeat(n)+"}";case "exponent_repeat"->"1e"+"1".repeat(n);case "object_exponent_repeat"->"{\"a\":1e"+"1".repeat(n)+"}";case "quoted_repeat"->"\""+"x".repeat(n)+"\"";case "unquoted_repeat"->"x".repeat(n);case "array_repeat"->"["+"0,".repeat(n-1)+"0]";default->throw new IllegalArgumentException("input spec");};}
 public static void main(String[] args)throws Exception{
  var in=JsonParser.parseString(Files.readString(Path.of(args[0]),StandardCharsets.US_ASCII)).getAsJsonArray();var out=new JsonObject();var defaults=new JsonObject();var jr=new JsonReader(new StringReader(""));defaults.addProperty("strictness",jr.getStrictness().toString());defaults.addProperty("nesting_limit",jr.getNestingLimit());defaults.addProperty("gson_version",Gson.class.getPackage().getImplementationVersion());out.add("json_reader_defaults",defaults);var cases=new JsonArray();
  for(var j:in){var c=j.getAsJsonObject();var text=input(c);var o=new JsonObject();o.addProperty("id",c.get("id").getAsString());o.addProperty("input_utf16_length",text.length());o.addProperty("input_utf16be_sha256",digestUtf16(text));var results=new JsonObject();for(var mode:List.of("parse_reader","parse_json_reader","gson_helper_tree"))results.add(mode,tree(text,mode,c.has("input_spec")));results.add("cuboid_from_stream",model(text));o.add("results",results);cases.add(o);}
  out.add("cases",cases);Files.writeString(Path.of(args[1]),ascii(G.toJson(out)),StandardCharsets.US_ASCII);
 }
}
'''


def hydrate(value):
    """Recover exact Java UTF-16 strings without the UTF-8 writer replacing them."""
    if isinstance(value, list):
        return [hydrate(x) for x in value]
    if isinstance(value, dict):
        out = {k: hydrate(v) for k, v in value.items()}
        if "utf16_hex" in out:
            out["text"] = bytes.fromhex(out["utf16_hex"]).decode("utf-16-be", errors="surrogatepass")
        return out
    return value


def source_records(cp, provenance):
    names = ["net/minecraft/util/GsonHelper.class", "net/minecraft/client/resources/model/cuboid/CuboidModel.class",
             "net/minecraft/client/resources/model/cuboid/CuboidModel$Deserializer.class"]
    gson = next(x for x in provenance["libraries"] if x["path"].startswith("com/google/code/gson/gson/"))
    gson_path = next(x for x in cp if x.name == pathlib.Path(gson["path"]).name)
    gson_names = ["com/google/gson/JsonParser.class", "com/google/gson/stream/JsonReader.class", "com/google/gson/JsonPrimitive.class",
                  "com/google/gson/internal/LazilyParsedNumber.class", "com/google/gson/JsonObject.class",
                  "com/google/gson/internal/LinkedTreeMap.class", "com/google/gson/internal/bind/JsonElementTypeAdapter.class"]
    records = []
    for jar, targets in [(CLIENT, names), (gson_path, gson_names)]:
        with zipfile.ZipFile(jar) as z:
            for name in targets:
                if name not in z.namelist():
                    continue
                b = z.read(name)
                records.append({"class": name[:-6].replace("/", "."), "jar": jar.name, "bytes": len(b), "sha256": sha(b)})
    run = subprocess.run([str(JAVA.with_name("javap")), "-p", "-c", "-classpath", ":".join(map(str, cp)),
                          "com.google.gson.JsonParser", "com.google.gson.stream.JsonReader", "net.minecraft.util.GsonHelper",
                          "net.minecraft.client.resources.model.cuboid.CuboidModel"], capture_output=True, text=True, check=True)
    p = CACHE / "official-javap.txt"
    p.write_text(run.stdout)
    return {"classes": records, "gson_artifact": gson, "java_harness_sha256": sha(JAVA_SOURCE.encode()),
            "javap": fingerprint(p), "authority": "Pinned production Java methods executed directly; bytecode only establishes API wiring"}


def execute(inputs, cp, tag):
    CACHE.mkdir(parents=True, exist_ok=True)
    src = CACHE / "ReferenceResourceJsonProbe.java"
    src.write_text(JAVA_SOURCE)
    ip, op = CACHE / (tag + "-inputs.json"), CACHE / (tag + "-observations.json")
    ip.write_bytes(encoded(inputs))
    cmd = [str(JAVA), "-cp", ":".join(map(str, cp)), str(src), str(ip), str(op)]
    run = subprocess.run(cmd, cwd=CACHE, capture_output=True, text=True, timeout=180)
    (CACHE / (tag + "-stdout.log")).write_text(run.stdout)
    (CACHE / (tag + "-stderr.log")).write_text(run.stderr)
    if run.returncode:
        raise RuntimeError("Java resource JSON probe failed: " + run.stderr[-6000:] + run.stdout[-6000:])
    return hydrate(json.loads(op.read_text())), {"exit_code": run.returncode, "raw_output_sha256": sha(op.read_bytes())}


def counts(obs):
    return {"cases": len(obs["cases"]), "apis": {api: dict(collections.Counter(c["results"][api]["status"] for c in obs["cases"]))
                                                 for api in ["parse_reader", "parse_json_reader", "gson_helper_tree", "cuboid_from_stream"]}}


def validate(data, inputs=None, observations=None, provenance=None, source=None):
    if data.get("schema") != 1 or data.get("pin") != "26.3":
        raise ValueError("Resource JSON reference schema/pin mismatch")
    for name in ["inputs", "observations"]:
        if sha(encoded(data[name])) != data[name + "_sha256"]:
            raise ValueError(name + " checksum mismatch")
    for name, actual in [("inputs", inputs), ("observations", observations), ("provenance", provenance), ("source", source)]:
        # JSON combines valid escaped surrogate pairs into a scalar on reload;
        # ASCII JSON compares UTF-16 content rather than Python's representation.
        if actual is not None and encoded(data[name]) != encoded(actual):
            raise ValueError(name + " differs from fresh production observation")
    if counts(data["observations"]) != data["counts"]:
        raise ValueError("Reference counts mismatch")
    cases = data["observations"]["cases"]
    if [x["id"] for x in data["inputs"]] != [x["id"] for x in cases]:
        raise ValueError("Observation fixture identities/order mismatch")
    for fixture, observed in zip(data["inputs"], cases):
        raw = fixture_text(fixture).encode("utf-16-be", errors="surrogatepass")
        if len(raw) // 2 != observed["input_utf16_length"] or sha(raw) != observed["input_utf16be_sha256"]:
            raise ValueError("Java/Python input expansion mismatch: " + fixture["id"])
        if set(observed["results"]) != {"parse_reader", "parse_json_reader", "gson_helper_tree", "cuboid_from_stream"}:
            raise ValueError("Missing API observation: " + fixture["id"])
    return {"status": "pass", "counts": data["counts"], "observations_sha256": data["observations_sha256"]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["extract", "selftest", "validate"], nargs="?", default="extract")
    args = parser.parse_args()
    if args.action == "validate":
        print(json.dumps(validate(json.loads(OUTPUT.read_text()))))
        return
    cp, provenance = verified_client_classpath()
    inputs = fixtures()
    obs, run = execute(inputs, cp, args.action + "-a")
    source = source_records(cp, provenance)
    if args.action == "selftest":
        data = json.loads(OUTPUT.read_text())
        check = validate(data, inputs, obs, provenance, source)
        other, other_run = execute(inputs, cp, "selftest-b")
        validate(data, inputs, other, provenance, source)
        check["fresh_executions"] = [run, other_run]
        print(json.dumps(check))
        return
    data = {"schema": 1, "pin": "26.3", "oracle_version": "java26.3-reader-json-v1",
            "scope": "Synthetic text through actual pinned Gson JsonParser reader overloads, production GsonHelper strict tree adapter, and CuboidModel.fromStream; no game client activation",
            "tree_encoding": "kind distinguishes number/string; numeric lexeme is JsonPrimitive.getAsString, not original spelling when Gson normalizes an integer; object members retain Java insertion order after duplicate replacement; text/utf16_hex preserve Java UTF-16 including unpaired surrogates; generated depth/size inputs use compact tree summaries",
            "entrypoints": {
                "parse_reader": "JsonParser.parseReader(new StringReader(text)); actual Reader overload, including its trailing-document check",
                "parse_json_reader": "JsonParser.parseReader(new JsonReader(new StringReader(text))); actual JsonReader overload with recorded defaults",
                "gson_helper_tree": "GsonHelper.fromJson(new GsonBuilder().serializeNulls().disableHtmlEscaping().create(), new StringReader(text), JsonElement.class); production helper constructs STRICT reader and reads one tree",
                "cuboid_from_stream": "CuboidModel.fromStream(new StringReader(text)); actual production GSON adapter; successful summaries encode nullable inheritance fields without resolving model semantics"},
            "error_encoding": "Exceptions come from the invoked API; messages over512 UTF16 units retain prefix plus original UTF16 length/SHA256, including causes; harness summary errors are not converted into parser rejections",
            "input_spec": {"nested_array": "[ repeated size, 0, ] repeated size", "nested_object": "{\"a\": repeated size, 0, } repeated size",
                           "number_repeat": "1 repeated size", "object_number_repeat": "{\"a\": followed by 1 repeated size followed by }",
                           "exponent_repeat": "1e followed by 1 repeated size", "object_exponent_repeat": "{\"a\":1e followed by 1 repeated size followed by }",
                           "quoted_repeat": "double-quoted x repeated size", "unquoted_repeat": "x repeated size",
                           "array_repeat": "array with size copies of 0"},
            "provenance": provenance, "source": source, "inputs": inputs, "inputs_sha256": sha(encoded(inputs)),
            "observations": obs, "observations_sha256": sha(encoded(obs)), "counts": counts(obs), "extract_run": run,
            "reproduce": "python3 tools/reference_resource_json_probe.py selftest"}
    validate(data, inputs, obs, provenance, source)
    OUTPUT.write_text(json.dumps(data, ensure_ascii=True, sort_keys=True, indent=2) + "\n")
    print(json.dumps(validate(data)))


if __name__ == "__main__":
    main()
