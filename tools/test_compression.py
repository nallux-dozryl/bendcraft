#!/usr/bin/env python3
"""Independent native Bend DEFLATE/wrapper verification and equivalent benchmark.

Python creates fixtures and uses its zlib/gzip implementations as byte oracles.
It does not provide an inflater to Bend. Extracted installed assets stay in an
ignored temporary build directory; evidence stores hashes and summaries only.
"""
from __future__ import annotations

import argparse
from dataclasses import dataclass
from datetime import datetime, timezone
import gzip
import hashlib
import json
from pathlib import Path
import random
import statistics
import struct
import subprocess
import tempfile
import time
import zipfile
import zlib

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_JAR = Path.home() / "Library/Application Support/minecraft/versions/26.3/26.3.jar"


def require(value: bool, message: str) -> None:
    if not value:
        raise AssertionError(message)


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


class Bits:
    def __init__(self):
        self.bits: list[int] = []

    def uint(self, value: int, count: int) -> None:
        self.bits.extend((value >> bit) & 1 for bit in range(count))

    def huffman(self, symbol: int, lengths: list[int]) -> None:
        counts = [lengths.count(i) if i else 0 for i in range(16)]
        codes = [0] * 16
        for i in range(1, 16):
            codes[i] = (codes[i - 1] + counts[i - 1]) * 2
        for index, length in enumerate(lengths):
            if length:
                code = codes[length]
                codes[length] += 1
                if index == symbol:
                    self.bits.extend((code >> bit) & 1 for bit in reversed(range(length)))
                    return
        raise AssertionError("fixture symbol has no code")

    def align(self) -> None:
        while len(self.bits) % 8:
            self.bits.append(0)

    def bytes(self) -> bytes:
        self.align()
        return bytes(sum(self.bits[i + j] << j for j in range(8)) for i in range(0, len(self.bits), 8))

    def stored(self, data: bytes, final: bool) -> None:
        require(len(data) <= 65535, "oversized fixture stored block")
        self.uint(int(final), 1)
        self.uint(0, 2)
        self.align()
        self.uint(len(data), 16)
        self.uint(len(data) ^ 65535, 16)
        for byte in data:
            self.uint(byte, 8)

    def fixed(self, tokens: list[int | tuple[int, int, int, int]], final=True) -> None:
        self.uint(int(final), 1)
        self.uint(1, 2)
        literals = [8] * 144 + [9] * 112 + [7] * 24 + [8] * 8
        extras = [0] * 8 + [1] * 4 + [2] * 4 + [3] * 4 + [4] * 4 + [5] * 4 + [0]
        for token in tokens:
            if isinstance(token, int):
                self.huffman(token, literals)
            else:
                length_code, length_extra, distance_code, distance_extra = token
                self.huffman(length_code, literals)
                self.uint(length_extra, extras[length_code - 257])
                self.huffman(distance_code, [5] * 32)
                self.uint(distance_extra, max(0, distance_code // 2 - 1))
        self.huffman(256, literals)


def dynamic(lengths: list[int], distance_lengths: list[int], code_lengths: dict[int, int] | None = None,
            encoded: list[int | tuple[int, int]] | None = None, payload: list[int] = ()) -> bytes:
    writer = Bits()
    writer.uint(1, 1)
    writer.uint(2, 2)
    writer.uint(len(lengths) - 257, 5)
    writer.uint(len(distance_lengths) - 1, 5)
    mapping = code_lengths or {0: 1, 1: 1}
    codes = [mapping.get(i, 0) for i in range(19)]
    order = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]
    count = max(4, max(i + 1 for i, symbol in enumerate(order) if codes[symbol]))
    writer.uint(count - 4, 4)
    for symbol in order[:count]:
        writer.uint(codes[symbol], 3)
    for item in encoded if encoded is not None else lengths + distance_lengths:
        if isinstance(item, tuple):
            symbol, extra = item
            writer.huffman(symbol, codes)
            writer.uint(extra, {16: 2, 17: 3, 18: 7}[symbol])
        else:
            writer.huffman(item, codes)
    for symbol in payload:
        writer.huffman(symbol, lengths)
    return writer.bytes()


def compressed(data: bytes, mode: str, level=6, strategy=zlib.Z_DEFAULT_STRATEGY) -> bytes:
    obj = zlib.compressobj(level, zlib.DEFLATED, {"raw": -15, "zlib": 15, "gzip": 31}[mode], strategy=strategy)
    return obj.compress(data) + obj.flush()


def stored_expected(data: bytes, mode: str) -> bytes:
    chunks = [data[n:n + 65535] for n in range(0, len(data), 65535)] or [b""]
    raw = b"".join(bytes([int(n == len(chunks) - 1)]) + struct.pack("<HH", len(chunk), len(chunk) ^ 65535) + chunk
                   for n, chunk in enumerate(chunks))
    if mode == "zlib":
        raw = b"\x78\x01" + raw + struct.pack(">I", zlib.adler32(data))
    elif mode == "gzip":
        raw = b"\x1f\x8b\x08\x00" + b"\0" * 5 + b"\xff" + raw + struct.pack("<II", zlib.crc32(data), len(data))
    require(oracle(mode, raw) == data, "independent stored-writer packet is not interoperable")
    return raw


def oracle(mode: str, data: bytes) -> bytes:
    if mode == "gzip":
        return gzip.decompress(data)
    obj = zlib.decompressobj({"raw": -15, "zlib": 15}[mode])
    output = obj.decompress(data) + obj.flush()
    if not obj.eof or obj.unused_data or obj.unconsumed_tail:
        raise ValueError("incomplete stream or extra full bytes")
    return output


@dataclass
class Case:
    label: str
    mode: str
    data: bytes
    expected: bytes | None
    error: str | None = None
    input_limit: int | None = None
    output_limit: int | None = None


def valid(label: str, mode: str, data: bytes, expected: bytes) -> Case:
    require(oracle(mode, data) == expected, "independent fixture oracle mismatch: " + label)
    return Case(label, mode, data, expected)


def fixtures(jar: Path) -> tuple[list[Case], list[dict], list[str]]:
    rng = random.Random(195119501952)
    cases: list[Case] = []
    assets: list[dict] = []
    divergences: list[str] = []
    samples = [b"", b"123456789", bytes(range(256)), b"A" * 100000,
               ("Unicode 分割 🙂\n" * 97).encode(), bytes(rng.randrange(256) for _ in range(40000)),
               bytes(rng.choices(range(10), k=30000))]
    for index, data in enumerate(samples):
        for mode in ["raw", "zlib", "gzip"]:
            for level, strategy in [(0, 0), (6, 0), (6, zlib.Z_FIXED), (6, zlib.Z_HUFFMAN_ONLY), (6, zlib.Z_RLE)]:
                label = f"roundtrip-{index}-{mode}-{level}-{strategy}"
                cases.append(valid(label, mode, compressed(data, mode, level, strategy), data))
    for index in range(72):
        size = rng.randrange(0, 7000)
        alphabet = [1, 2, 17, 256][index % 4]
        data = bytes(rng.randrange(alphabet) for _ in range(size))
        mode = ["raw", "zlib", "gzip"][index % 3]
        cases.append(valid(f"seeded-random-{index}", mode, compressed(data, mode, index % 10), data))
    for mode in ["raw", "zlib", "gzip"]:
        data = b"cross-block-0123456789" * 251
        obj = zlib.compressobj(wbits={"raw": -15, "zlib": 15, "gzip": 31}[mode])
        raw = obj.compress(data[:173]) + obj.flush(zlib.Z_SYNC_FLUSH) + obj.compress(data[173:]) + obj.flush()
        cases.append(valid("synchronization-block-" + mode, mode, raw, data))

    for label, tokens, expected in [
        ("fixed-overlap-distance-1", [65, (285, 0, 0, 0)], b"A" * 259),
        ("fixed-overlap-distance-2", [65, 66, (257, 0, 1, 0)], b"ABABA"),
        ("fixed-empty", [], b""),
    ]:
        writer = Bits(); writer.fixed(tokens)
        cases.append(valid(label, "raw", writer.bytes(), expected))
    for label, tokens, error in [
        ("distance-before-history", [(257, 0, 0, 0)], "Distance"),
        ("reserved-literal", [286], "ReservedLiteral"),
        ("reserved-distance", [65, (257, 0, 30, 0)], "ReservedDistance"),
    ]:
        writer = Bits(); writer.fixed(tokens)
        cases.append(Case(label, "raw", writer.bytes(), None, error))
    seed = bytes(rng.randrange(256) for _ in range(32768))
    writer = Bits(); writer.stored(seed, False)
    distance_tokens = [(257, 0, code, (1 << max(0, code // 2 - 1)) - 1) for code in range(30)]
    writer.fixed(distance_tokens)
    cases.append(valid("all-distance-codes-and-32768-window", "raw", writer.bytes(), oracle("raw", writer.bytes())))
    writer = Bits(); writer.stored(seed, False)
    length_extras = [0] * 8 + [1] * 4 + [2] * 4 + [3] * 4 + [4] * 4 + [5] * 4 + [0]
    writer.fixed([(code, (1 << extra) - 1, 0, 0) for code, extra in zip(range(257, 286), length_extras)])
    cases.append(valid("all-length-codes-and-extra-bits", "raw", writer.bytes(), oracle("raw", writer.bytes())))
    writer = Bits(); ring_seed = seed * 2 + b"ring-rewrite" * 513
    writer.stored(ring_seed[:65535], False); writer.stored(ring_seed[65535:], False); writer.fixed([(285, 0, 29, 8191)])
    cases.append(valid("wrapped-history-and-cross-block-copy", "raw", writer.bytes(), oracle("raw", writer.bytes())))

    empty_lit = [0] * 256 + [1]
    cases.append(valid("dynamic-single-end-and-empty-distance", "raw", dynamic(empty_lit, [0], payload=[256]), b""))
    missing = [0] * 257; missing[65] = 1
    cases.append(Case("dynamic-missing-end", "raw", dynamic(missing, [0]), None, "MissingEndCode"))
    over = empty_lit.copy(); over[65] = over[66] = 1
    cases.append(Case("dynamic-literal-oversubscribed", "raw", dynamic(over, [0]), None, "HuffmanOversubscribed"))
    incomplete = [0] * 257; incomplete[65] = incomplete[256] = 2
    cases.append(Case("dynamic-literal-incomplete", "raw", dynamic(incomplete, [0], {0: 1, 2: 1}), None, "HuffmanIncomplete"))
    cases.append(Case("dynamic-distance-incomplete", "raw", dynamic(empty_lit, [2], {0: 1, 1: 2, 2: 2}), None, "HuffmanIncomplete"))
    cases.append(Case("repeat-without-previous", "raw", dynamic(empty_lit, [0], {0: 1, 16: 1}, [(16, 0)]), None, "CodeLengthRepeat"))
    cases.append(Case("repeat-overshoot", "raw", dynamic(empty_lit, [0], {0: 1, 18: 1}, [(18, 127)] * 2), None, "CodeLengthRepeat"))
    cases.append(Case("code-alphabet-oversubscribed", "raw", dynamic(empty_lit, [0], {0: 1, 1: 1, 18: 1}, []), None, "HuffmanOversubscribed"))
    cases.append(Case("code-alphabet-incomplete", "raw", dynamic(empty_lit, [0], {0: 2}, []), None, "HuffmanIncomplete"))
    crossing = [0] * 260; crossing[65] = crossing[256] = 1
    cases.append(valid("code-repeat-crosses-alphabet-boundary", "raw", dynamic(crossing, [0] * 3,
                       {0: 1, 1: 2, 16: 2}, crossing[:259] + [(16, 0), 0], [65, 256]), b"A"))
    # RFC1951 permits HDIST=32, while the zlib oracle rejects declarations >30.
    extended = dynamic(empty_lit, [0] * 32, payload=[256])
    cases.append(Case("rfc-distance-alphabet-32-unused", "raw", extended, b""))
    try:
        oracle("raw", extended)
        raise AssertionError("recorded zlib distance alphabet restriction changed")
    except zlib.error:
        divergences.append("RFC1951 HDIST=32 with unused reserved distance symbols is accepted; Python zlib rejects counts above30.")

    cases.extend([Case("reserved-block", "raw", b"\x07", None, "ReservedBlock"),
                  Case("stored-complement", "raw", b"\x01\x01\x00\x00\x00A", None, "StoredLength"),
                  Case("missing-final-block", "raw", b"\x00\x00\x00\xff\xff", None, "Truncated")])
    for mode in ["raw", "zlib", "gzip"]:
        full = compressed(b"truncate-every-byte-" * 4, mode)
        cases.extend(Case(f"truncated-{mode}-{n}", mode, full[:n], None) for n in range(len(full)))
        cases.append(Case("trailing-data-" + mode, mode, full + b"garbage", None))
        cases.append(Case("input-limit-" + mode, mode, full, None, "InputLimit", len(full) - 1))
        cases.append(Case("output-limit-" + mode, mode, full, None, "OutputLimit", output_limit=75))
        cases.append(Case("bomb-" + mode, mode, compressed(b"z" * 1048576, mode), None, "OutputLimit", output_limit=4096))
    z = compressed(b"checksum", "zlib")
    cases.extend([Case("zlib-adler", "zlib", z[:-1] + bytes([z[-1] ^ 1]), None, "AdlerMismatch"),
                  Case("zlib-fcheck", "zlib", bytes([z[0], z[1] ^ 1]) + z[2:], None, "ZlibHeader"),
                  Case("zlib-method", "zlib", b"\x79\x18" + z[2:], None, "ZlibHeader")])
    dictionary = zlib.compressobj(zdict=b"configured-preset-dictionary")
    cases.append(Case("zlib-preset-dictionary", "zlib", dictionary.compress(b"configured-preset-dictionary") + dictionary.flush(), None, "UnsupportedDictionary"))
    small_cmf = 8; flg = (-small_cmf * 256) % 31
    writer = Bits(); writer.stored(seed, False); writer.fixed([(257, 0, 29, 8191)])
    narrow_output = oracle("raw", writer.bytes())
    narrow = bytes([small_cmf, flg]) + writer.bytes() + struct.pack(">I", zlib.adler32(narrow_output))
    cases.append(Case("zlib-declared-window-bound", "zlib", narrow, None, "Distance"))
    divergences.append("Declared zlib window bound is enforced, including CINFO=0; default Python zlib may accept farther distances.")

    content = b"header-options-" * 100
    header = b"\x1f\x8b\x08\x1f\x00\x00\x00\x00\x00\xff"
    extra = b"XY\x03\x00abc"
    header += struct.pack("<H", len(extra)) + extra + b"fixture.dat\0comment\0"
    optional = header + struct.pack("<H", zlib.crc32(header) & 65535) + compressed(content, "raw") + struct.pack("<II", zlib.crc32(content), len(content))
    cases.append(valid("gzip-all-optional-fields", "gzip", optional, content))
    hcrc_offset = len(header)
    bad = bytearray(optional); bad[hcrc_offset] ^= 1
    cases.append(Case("gzip-header-crc", "gzip", bytes(bad), None, "HeaderCrcMismatch"))
    bad = bytearray(optional); bad[3] |= 32
    cases.append(Case("gzip-reserved-flag", "gzip", bytes(bad), None, "GzipHeader"))
    bad = bytearray(optional); bad[-8] ^= 1
    cases.append(Case("gzip-data-crc", "gzip", bytes(bad), None, "CrcMismatch"))
    bad = bytearray(optional); bad[-4] ^= 1
    cases.append(Case("gzip-size", "gzip", bytes(bad), None, "SizeMismatch"))
    cases.append(Case("gzip-name-unterminated", "gzip", b"\x1f\x8b\x08\x08" + b"\0" * 6 + b"name", None, "Truncated"))
    cases.append(Case("gzip-extra-truncated", "gzip", b"\x1f\x8b\x08\x04" + b"\0" * 6 + b"\xff\xffabc", None, "Truncated"))
    members = [b"", b"first" * 40, b"", bytes(range(256)), b"last" * 100]
    joined = b"".join(gzip.compress(member, mtime=0) for member in members)
    cases.append(valid("gzip-concatenated-members", "gzip", joined, b"".join(members)))
    writer = Bits(); writer.fixed([(257, 0, 0, 0)])
    illegal_second = b"\x1f\x8b\x08\x00" + b"\0" * 6 + writer.bytes() + b"\0" * 8
    cases.append(Case("gzip-members-cannot-share-history", "gzip", gzip.compress(b"A", mtime=0) + illegal_second, None, "Distance"))

    for index in range(450):
        mode = ["raw", "zlib", "gzip"][index % 3]
        original = compressed(samples[index % len(samples)], mode)
        mutated = bytearray(original)
        offset = rng.randrange(len(mutated)); mutated[offset] ^= 1 << rng.randrange(8)
        try:
            expected = oracle(mode, bytes(mutated))
        except (zlib.error, OSError, EOFError, ValueError):
            expected = None
        cases.append(Case(f"seeded-mutation-{index}", mode, bytes(mutated), expected))

    require(jar.is_file(), "installed pinned 26.3 reference jar missing")
    with zipfile.ZipFile(jar) as archive, jar.open("rb") as source:
        infos = [info for info in archive.infolist() if info.compress_type == 8 and
                 (info.filename.endswith(".nbt") or info.filename in {
                     "assets/minecraft/textures/block/stone.png", "assets/minecraft/textures/block/oak_log.png",
                     "assets/minecraft/lang/en_us.json"})]
        nbt = 0
        for info in infos:
            if info.filename.endswith(".nbt") and nbt >= 2:
                continue
            raw = archive.read(info)
            source.seek(info.header_offset)
            header = source.read(30)
            name_size, extra_size = struct.unpack_from("<HH", header, 26)
            source.seek(info.header_offset + 30 + name_size + extra_size)
            deflated = source.read(info.compress_size)
            cases.append(valid("reference-zip-" + info.filename, "raw", deflated, raw))
            assets.append({"entry": info.filename, "compressed_size": len(deflated), "output_size": len(raw),
                           "compressed_sha256": sha(deflated), "output_sha256": sha(raw)})
            if info.filename.endswith(".nbt"):
                nbt += 1
                require(raw.startswith(b"\x1f\x8b"), "reference structure NBT is not gzip")
                cases.append(valid("reference-gzip-nbt-" + info.filename, "gzip", raw, gzip.decompress(raw)))
            if info.filename.endswith(".png"):
                offset, idat = 8, b""
                while offset < len(raw):
                    length = struct.unpack_from(">I", raw, offset)[0]
                    if raw[offset + 4:offset + 8] == b"IDAT":
                        idat += raw[offset + 8:offset + 8 + length]
                    offset += length + 12
                cases.append(valid("reference-png-idat-" + info.filename, "zlib", idat, zlib.decompress(idat)))
    require(nbt == 2 and len(assets) >= 5, "insufficient actual installed asset/NBT fixtures")
    for index, content in enumerate([b"", b"123456789", bytes(range(256)), b"a" * 65535,
                                     b"b" * 65536, bytes(range(256)) * 512]):
        for mode in ["raw", "zlib", "gzip"]:
            raw = stored_expected(content, mode)
            cases.append(Case(f"stored-writer-{index}-{mode}", "encode-" + mode, content, raw))
            cases.append(valid(f"stored-writer-decoder-roundtrip-{index}-{mode}", mode, raw, content))
            cases.append(Case(f"stored-writer-output-limit-{index}-{mode}", "encode-" + mode,
                              content, None, "OutputLimit", output_limit=len(raw) - 1))
            if content:
                cases.append(Case(f"stored-writer-input-limit-{index}-{mode}", "encode-" + mode,
                                  content, None, "InputLimit", input_limit=len(content) - 1))
    return cases, assets, divergences


def native_cases(binary: Path, cases: list[Case], directory: Path) -> tuple[int, int]:
    successes = failures = 0
    for start in range(0, len(cases), 80):
        args = [str(binary), "--threads", "1", "--gpu", "off"]
        paths = []
        for index, case in enumerate(cases[start:start + 80], start):
            source, output = directory / f"{index}.bin", directory / f"{index}.out"
            source.write_bytes(case.data)
            paths.append(output)
            limit = case.output_limit if case.output_limit is not None else max(1, len(case.expected or b""))
            if case.expected is None and case.output_limit is None:
                limit = 2097152
            args += [case.mode, str(case.input_limit if case.input_limit is not None else len(case.data)),
                     str(limit), str(source), str(output), "1"]
        result = subprocess.run(args, cwd=ROOT, text=True, capture_output=True, timeout=120)
        require(result.returncode == 0 and not result.stderr, "native fixture process failed: " + result.stderr[:1500])
        lines = result.stdout.splitlines()
        require(len(lines) == len(paths), "native fixture response count differs")
        for case, path, line in zip(cases[start:start + 80], paths, lines):
            value = json.loads(line)
            require(value["ok"] == (case.expected is not None), "oracle status mismatch: " + case.label + " " + line)
            if case.expected is not None:
                successes += 1
                require(path.read_bytes() == case.expected, "exact decoded byte mismatch: " + case.label)
                checksum_bytes = case.data if case.mode.startswith("encode-") else case.expected
                require(value == {"ok": True, "size": len(case.expected), "consumed": len(case.data),
                                  "adler": zlib.adler32(checksum_bytes), "crc": zlib.crc32(checksum_bytes)},
                        "metadata/checksum mismatch: " + case.label)
            else:
                failures += 1
                require(not path.exists(), "failure published partial bytes: " + case.label)
                if case.error:
                    require(value["error"] == case.error, "wrong bounded decoder failure: " + case.label + " " + line)
    return successes, failures


C_BENCHMARK = r'''
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <zlib.h>
static double now(void) {
    struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t);
    return (double)t.tv_sec + (double)t.tv_nsec / 1e9;
}
int main(int argc, char **argv) {
    if (argc != 5) return 2;
    unsigned iterations = (unsigned)strtoul(argv[2], NULL, 10);
    unsigned max_input = (unsigned)strtoul(argv[3], NULL, 10);
    unsigned max_output = (unsigned)strtoul(argv[4], NULL, 10);
    double read_started = now();
    FILE *f = fopen(argv[1], "rb"); if (!f) return 3;
    if (fseek(f, 0, SEEK_END)) return 3;
    long length = ftell(f); rewind(f);
    if (length < 0 || (unsigned long)length > max_input) return 4;
    unsigned char *input = malloc((size_t)length ? (size_t)length : 1);
    if (!input || fread(input, 1, (size_t)length, f) != (size_t)length) return 3;
    fclose(f); double read_ms = (now() - read_started) * 1000;
    double started = now(); uint32_t digest = 0;
    for (unsigned i = 0; i < iterations; ++i) {
        unsigned char *output = malloc(max_output ? max_output : 1);
        z_stream s; memset(&s, 0, sizeof(s));
        s.next_in = input; s.avail_in = (unsigned)length;
        s.next_out = output; s.avail_out = max_output;
        if (!output || inflateInit(&s) != Z_OK) return 5;
        int code = inflate(&s, Z_FINISH);
        if (code != Z_STREAM_END || s.total_in != (unsigned long)length || s.total_out != max_output) return 6;
        uint32_t crc = (uint32_t)crc32(0, output, (unsigned)s.total_out);
        uint32_t fnv = 2166136261u;
        for (unsigned j = 0; j < s.total_out; ++j) fnv = (fnv ^ output[j]) * 16777619u;
        digest += (crc + (uint32_t)s.total_out) ^ (uint32_t)s.adler ^ fnv;
        inflateEnd(&s); free(output);
    }
    double steady_ms = (now() - started) * 1000;
    free(input);
    printf("{\"ok\":true,\"digest\":%u,\"read_ms\":%.6f,\"steady_ms\":%.6f,\"zlib\":\"%s\"}\n", digest, read_ms, steady_ms, zlibVersion());
    return 0;
}
'''


def measure(binary: Path, directory: Path) -> dict:
    source_code, c_binary = directory / "zlib_benchmark.c", directory / "zlib-benchmark"
    source_code.write_text(C_BENCHMARK)
    compile_result = subprocess.run(["clang", "-O2", str(source_code), "-lz", "-o", str(c_binary)],
                                    cwd=ROOT, capture_output=True, text=True, timeout=30)
    require(compile_result.returncode == 0, "equivalent C zlib driver compile failed: " + compile_result.stderr)
    rng = random.Random(1951)
    samples = {
        "repetitive": (b"equal bounded decompression workload; materialized output and checksums\n" * 997) + bytes(range(256)) * 128,
        "entropy": bytes(rng.randrange(256) for _ in range(32768)),
    }
    workloads = []
    for name, data in samples.items():
        encoded = compressed(data, "zlib")
        source = directory / ("benchmark-" + name + ".bin"); source.write_bytes(encoded)
        iterations, trials = 101, 5
        fnv = 2166136261
        for byte in data:
            fnv = ((fnv ^ byte) * 16777619) & 0xffffffff
        expected_digest = ((((zlib.crc32(data) + len(data)) & 0xffffffff) ^ zlib.adler32(data) ^ fnv) * iterations) & 0xffffffff
        native, reference = [], []
        for _ in range(trials):
            for executable, collection, arguments in [
                (binary, native, ["--threads", "1", "--gpu", "off", "bench-zlib", str(len(encoded)), str(len(data)), str(source), "-", str(iterations)]),
                (c_binary, reference, [str(source), str(iterations), str(len(encoded)), str(len(data))]),
            ]:
                begin = time.perf_counter()
                result = subprocess.run([str(executable)] + arguments, cwd=ROOT, capture_output=True, text=True, timeout=120)
                wall = time.perf_counter() - begin
                require(result.returncode == 0 and not result.stderr, "equivalent benchmark driver failed")
                value = json.loads(result.stdout)
                require(value["digest"] == expected_digest, "equivalent benchmark materialized byte/checksum digest differs")
                value["end_to_end_ms"] = wall * 1000
                collection.append(value)
        native_steady = statistics.median(item["steady_ms"] for item in native)
        reference_steady = statistics.median(item["steady_ms"] for item in reference)
        require(native_steady > 0 and reference_steady > 0, "steady benchmark resolution is insufficient")
        workloads.append({"name": name, "mode": "zlib", "compressed_bytes": len(encoded), "output_bytes": len(data),
                          "iterations": iterations, "trials": trials, "input_sha256": sha(encoded), "output_sha256": sha(data),
                          "native": native, "c_zlib": reference,
                          "native_steady_output_MB_per_second": len(data) * iterations / native_steady / 1000,
                          "c_zlib_steady_output_MB_per_second": len(data) * iterations / reference_steady / 1000,
                          "native_to_c_steady_elapsed_ratio": native_steady / reference_steady})
    return {"workloads": workloads, "c_driver_sha256": sha(C_BENCHMARK.encode()),
            "c_driver_compile": ["clang", "-O2", "zlib_benchmark.c", "-lz", "-o", "zlib-benchmark"],
            "scope": "Same file read once; repeated fresh zlib stream/output lifetimes; bounded complete wrapper decoding; Adler32+CRC32 metadata and full-output FNV scan prevent discarded output. C uses z_stream.adler from its wrapper check. Bend CPU1/GPUoff. Read, steady work and subprocess wall times are separate. Bend IO.now resolution1ms; C monotonic nanosecond clock. C temporary driver is solely an independent benchmark, never a Bend decoder dependency. No game-speed inference."}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bend", type=Path, default=Path.home() / ".bend/bin/bend")
    parser.add_argument("--jar", type=Path, default=DEFAULT_JAR)
    parser.add_argument("--skip-build", action="store_true")
    args = parser.parse_args()
    begin = time.monotonic(); binary = ROOT / "build/compression-tests"
    verdict = subprocess.run([str(args.bend), "tests/compression.bend", "--verdict"], cwd=ROOT,
                             text=True, capture_output=True, timeout=120)
    require(verdict.returncode == 0 and "ALL PROOFS CHECK" in verdict.stdout, "pure compression kernel verdict failed: " + verdict.stderr)
    if not args.skip_build:
        build = subprocess.run([str(args.bend), "tests/compression.bend", "-o", str(binary)], cwd=ROOT,
                               text=True, capture_output=True, timeout=120)
        require(build.returncode == 0, "native compression build failed: " + build.stderr)
    cases, assets, divergences = fixtures(args.jar)
    with tempfile.TemporaryDirectory(prefix="compression-oracle-", dir=ROOT / "build") as temp:
        directory = Path(temp)
        successes, failures = native_cases(binary, cases, directory)
        performance = measure(binary, directory)
    evidence = {"status": "passed", "recorded_at_utc": datetime.now(timezone.utc).isoformat(),
                "command": "python3 tools/test_compression.py" + (" --skip-build" if args.skip_build else ""),
                "cases": len(cases), "successes": successes, "rejections_without_output": failures,
                "fixture_manifest_sha256": sha(json.dumps([{"label": c.label, "mode": c.mode, "input": sha(c.data),
                    "expected": sha(c.expected) if c.expected is not None else None, "error": c.error,
                    "input_limit": c.input_limit, "output_limit": c.output_limit} for c in cases], sort_keys=True).encode()),
                "categories": ["stored/fixed/dynamic Huffman; all length/distance codes and extra bits", "overlapping and wrapped32768 history; references across blocks",
                               "single-symbol/empty-distance trees; code-length repeats across alphabets", "seeded random streams and450 mutation oracle cases",
                               "every-byte truncation; malformed trees/codes; complements/end/length checks", "zlib Adler/headers/dictionary/window validation",
                               "gzip optional fields/headerCRC/dataCRC/ISIZE/concatenation/member isolation", "input/output limits and1MiB expansion bombs; failures publish no output",
                               "actual installed26.3 ZIP entries, PNG IDAT zlib data and gzip structure NBT",
                               "pure stored-block raw/zlib/gzip writers;65535 boundaries; Python and Bend roundtrips; encoded limits"],
                "oracle_versions": {"python_zlib": zlib.ZLIB_VERSION, "runtime_zlib": zlib.ZLIB_RUNTIME_VERSION},
                "reference_jar_sha256": sha(args.jar.read_bytes()), "reference_assets": assets,
                "source_sha256": {name: sha((ROOT / name).read_bytes()) for name in ["src/compression.bend", "tests/compression.bend", "tools/test_compression.py"]},
                "compiler_sha256": sha(args.bend.read_bytes()), "binary_sha256": sha(binary.read_bytes()),
                "kernel_verdict": {"returncode": verdict.returncode, "stdout": verdict.stdout, "stderr": verdict.stderr},
                "intentional_strictness_or_rfc_oracle_differences": divergences,
                "benchmark": performance, "limits": ["Preset dictionaries unsupported and rejected; no streaming decode API.",
                    "Finite fixture equalities and termination/type checking do not prove universal RFC correctness.",
                    "No pack/NBT/gameplay parity follows from byte decompression; wrapper metadata is validated but not exposed."],
                "official_sources": ["https://www.rfc-editor.org/rfc/rfc1951", "https://www.rfc-editor.org/rfc/rfc1950", "https://www.rfc-editor.org/rfc/rfc1952"],
                "elapsed_seconds": round(time.monotonic() - begin, 3)}
    (ROOT / "evidence/compression-native.json").write_text(json.dumps(evidence, indent=2) + "\n")
    print(json.dumps({"status": "passed", "cases": len(cases), "successes": successes, "rejections": failures,
                      "benchmark": [{"workload": item["name"], "native_steady_MB_per_second": round(item["native_steady_output_MB_per_second"], 3),
                                     "native_to_c_steady_ratio": round(item["native_to_c_steady_elapsed_ratio"], 2)} for item in performance["workloads"]]}))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (AssertionError, OSError, ValueError, subprocess.SubprocessError) as error:
        print("Compression verification failed: " + str(error))
        raise SystemExit(1)
