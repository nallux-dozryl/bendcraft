# Pure Bend PNG decoding

`src/png.bend` implements the PNG formats observed in the pinned Minecraft
Java 26.3 client. Parsing, CRC32, IDAT assembly, zlib/DEFLATE inflation,
unfiltering, palette lookup, transparency and RGBA conversion execute in Bend.
Python and Pillow occur only in independent verification.

## Public API and ownership

```text
P.decode(bytes: List<&2,U32>, limits: P.Limits)
  -> Result<&2,&1,P.Error,P.Decoded>
P.Decoded{width: U32,height: U32,pixels: List<&2,U32>}
P.Limits{max_input: U32,max_width: U32,max_height: U32,max_pixels: U32}
P.default_limits() -> P.Limits
P.rgba_bytes(pixels: List<&2,U32>) -> List<&2,U32>
```

Pixels are row-major straight alpha words `0xAARRGGBB`. `rgba_bytes` produces
ordinary byte-order RGBA for independent comparison. The default limits are
16 MiB compressed PNG input, width 1,024, height 4,096 and 1,048,576 pixels.
The supported configuration ceiling is 4,096 on either dimension and
16,777,216 pixels. Width and height must be positive. Each input list element
must be an actual byte. Storage allocations occur only after IHDR dimensions,
format and limits pass; each reconstruction array has one owner.

Supported color types are grayscale (0), RGB (2), indexed (3), grayscale plus
alpha (4) and RGBA (6). Grayscale and indexed accept depths 1, 2, 4 and 8;
RGB, grayscale plus alpha and RGBA accept depth 8. Packed samples reset at each
row, including row padding. Palette entries and `tRNS` alpha values are
preserved without premultiplication. RGB/grayscale transparent sample keys
are compared before grayscale depth scaling. All five PNG predictors use the
specified bytes-per-pixel, reconstructed left/top/corner bytes, and modular
byte arithmetic. Paeth implements its ordered tie breaking.

The decoder validates the PNG signature, IHDR order and length, chunk-name
reserved bit, every chunk's CRC including ignored ancillary chunks, supported
compression/filter methods, PLTE/tRNS ordering and sizes, palette indices,
contiguous IDAT chunks, IEND length and exact end of input. Multiple IDAT
chunks form one zlib stream. The compression decoder validates its zlib header,
DEFLATE structure and Adler32. The inflated scanline size must equal exactly
`height * (row_bytes + 1)` and malformed filter bytes fail.

Depth 16 and Adam7 interlace are explicit unsupported-format failures. They
are absent from the observed 1,300 vanilla block PNGs, and the independent
reference inventory also found them absent from all 3,965 client PNGs. This
module makes no claim to implement those unsupported PNG cases or resource
packs that require them.

## Verification

Run from the Minecraft project directory with the bundled workspace Python:

```sh
/Users/chuah/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 tools/test_png.py
```

The test compiles `tests/png.bend` as a native executable. That executable
reads bounded files using Base effects and calls the pure Bend decoder. Every
RGBA byte from **all 1,300 official block textures** is compared with Pillow
12.3.0, not merely a checksum. These actual textures cover all their observed
color types/depths and all five filters. Six additional independently encoded
fixtures cover predictor left/top/corner behavior, multiple IDAT chunks,
packed row padding and exact RGB/grayscale/indexed transparency. Thirteen
malformed fixtures are rejected with their expected semantic/checksum/framing
errors. Assets extracted for tests live in temporary or ignored directories;
no official pixels are committed.

`evidence/png-native.json` records the pinned JAR digest, native case counts,
selected independent RGBA hashes, source digest and reproduction command.
`bend src/png.bend --verdict` reports `ALL PROOFS CHECK` with no custom foreign
effects, unsafe definitions, axioms or placeholder proofs. That result checks
the definitions in the mathematical kernel. It is not a universal proof of
PNG conformance; the byte comparisons establish the stated finite behavior.
Confidence in the observed vanilla block decoding is high.
