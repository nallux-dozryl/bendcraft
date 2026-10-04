#!/usr/bin/env python3
"""Exact production texture reads and emitted ownership; no game/window launch."""
from __future__ import annotations
import hashlib, io, json, os, re, shutil, subprocess, time, zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BEND = Path.home() / '.bend/bin/bend'
BUILD = ROOT / 'build/texture_borrow_001'
JAR = Path.home() / 'Library/Application Support/minecraft/versions/26.3/26.3.jar'

def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def command(args, timeout=60, env=None):
    start = time.monotonic()
    p = subprocess.run(list(map(str, args)), cwd=ROOT, capture_output=True,
                       text=True, timeout=timeout, env=env)
    assert p.returncode == 0, (args, p.returncode, p.stdout, p.stderr)
    return p.stdout, {'command': list(map(str, args)), 'exit': p.returncode,
                     'seconds': round(time.monotonic() - start, 4)}

def tree(depth, side, width, height, values, x=0, y=0):
    if not depth:
        return values[y * width + x] if x < width and y < height else 0
    half = side // 2
    return tuple(tree(depth-1, half, width, height, values, x+dx, y+dy)
                 for dx, dy in ((0,0), (half,0), (0,half), (half,half)))

def old_address(image, depth, x, y, side):
    """Historical address semantics; only malformed-tree compatibility uses this."""
    while isinstance(image, tuple) and depth:
        half = side // 2
        image = image[(2 if y >= half else 0) + (1 if x >= half else 0)]
        x, y = (x % half, y % half) if half else (x, y)
        side, depth = half, depth - 1
    return 0 if isinstance(image, tuple) else image

def main():
    BUILD.mkdir(parents=True, exist_ok=True)
    files = ('src/client_render.bend','src/texture_borrow_laws.bend','src/texture_borrow_proof.bend',
             'tests/texture_borrow_pixels.bend','tools/texture_borrow_test.py')
    sources = {name:digest(ROOT/name) for name in files}
    checks = []
    env = os.environ.copy()
    env['PATH'] = str(ROOT / '.runtime/toolchains/lean-4.34.0-darwin_aarch64/bin') + os.pathsep + env['PATH']
    for label, cmd in (
        ('ordinary', [BEND, 'tests/texture_borrow_pixels.bend', '--check-only']),
        ('kernel', [BEND, 'src/texture_borrow_proof.bend', '--verdict']),
        ('emit', [BEND, 'tests/texture_borrow_pixels.bend', '-o', BUILD/'pixels.c']),
        ('native', [shutil.which('clang') or 'clang', '-std=c11', '-O3', BUILD/'pixels.c', '-lpthread', '-lm', '-o', BUILD/'pixels'])):
        output, row = command(cmd, env=env)
        if label == 'kernel':
            assert output.strip() == 'ALL PROOFS CHECK', output
        checks.append({'kind': label, **row, 'stdout': output.strip()})
        (BUILD/(label+'.json')).write_text(json.dumps(checks[-1], indent=2)+'\n')

    c = (BUILD/'pixels.c').read_text()
    functions = list(re.finditer(r'^INLINE Term (spin_\d+)\([^\n]*\) \{\n', c, re.M))
    candidates = []
    for i, match in enumerate(functions):
        end = functions[i+1].start() if i+1 < len(functions) else c.find('\n//', match.end())
        body = c[match.start():end]
        if re.search(r'\b_right_\d+', body) and re.search(r'\b_bottom_\d+', body) and re.search(r'\b_image_\d+', body):
            candidates.append((match.group(1), body, c.count('\n',0,match.start())+1))
    assert len(candidates) == 1, [(n, line) for n, _, line in candidates]
    name, body, line = candidates[0]
    assert body.count('term_peek(') == 2, body
    forbidden = ('ctr_take(', 'term_sink(', 'term_keep(', 'heap_alloc(', 'spare_free(', 'heap_free(')
    assert not any(word in body for word in forbidden), body
    assert body.count('WL_AGAIN('+name+')') == 4, body
    (BUILD/'lookup.c.txt').write_text(body)
    ownership = {'function': name, 'line': line, 'borrowed_node_reads': 2,
                 'tail_branch_loops': 4, 'forbidden_calls': {word: body.count(word) for word in forbidden},
                 'body_sha256': hashlib.sha256(body.encode()).hexdigest()}

    reference_path = ROOT/'reference/texture_mipmap.json'
    reference = json.loads(reference_path.read_text())
    assert reference['pin'] == '26.3'
    fixtures = []
    seen = set()
    # Independently observed Java NativeImage words, not output supplied to Bend.
    for case in reference['observations']['cases']:
        for level, image in enumerate(case['result'].get('before', [])):
            w, h, values = image['width'], image['height'], image['pixels']
            if w*h > 1024:
                continue
            assert w > 0 and h > 0 and len(values) >= w*h
            key = (w,h,tuple(values[:w*h]))
            if key in seen:
                continue
            seen.add(key)
            fixtures.append((f'java:{case["id"]}:{level}',w,h,values[:w*h]))
    # Same three pinned textures used by the existing client-render oracle.
    from PIL import Image
    with zipfile.ZipFile(JAR) as jar:
        for texture in ('stone','dirt','oak_planks'):
            image = Image.open(io.BytesIO(jar.read('assets/minecraft/textures/block/'+texture+'.png'))).convert('RGBA')
            values = [(a<<24)|(r<<16)|(g<<8)|b
                      for r,g,b,a in (image.getpixel((x,y)) for y in range(image.height) for x in range(image.width))]
            fixtures.append(('jar:'+texture,*image.size,values))

    rows = []
    def run(mode, w, h, td, ts, sd, ss, ow, oh, values):
        output, _ = command([BUILD/'pixels', '--gpu', 'off', '--threads', '1', '--',
                             mode,w,h,td,ts,sd,ss,ow,oh,*values], timeout=15)
        lines = output.splitlines()
        assert len(lines) == 2, output
        return [list(map(int, text.split())) for text in lines]

    for label,w,h,values in fixtures:
        depth = (max(w,h)-1).bit_length()
        side = 1 << depth
        actual, texels = run('flat',w,h,depth,side,depth,side,side,side,values)
        # Flat row-major NativeImage/Pillow words are the independent oracle.
        expected = [values[y*w+x] if x<w and y<h else 0
                    for y in range(side) for x in range(side)]
        assert actual == expected, ('raw pixel mismatch',label)
        assert texels == values, ('texel/retained-owner mismatch',label)
        rows.append({'fixture':label,'size':[w,h],'pixel_reads':len(actual),
                     'texel_reads':len(texels),'actual_sha256':hashlib.sha256(json.dumps(actual).encode()).hexdigest()})

    values = sum(reference['inputs']['quads'][3:7], [])
    mixed = (values[0],tuple(values[1:5]),values[5],
             (values[6],values[7],tuple(values[8:12]),values[12]))
    for mode in ('leaf','mixed','flat'):
        image = values[0] if mode == 'leaf' else mixed if mode == 'mixed' else tree(3,8,4,4,values)
        for depth in (0,1,2,3,4,7):
            for side in (0,1,2,3,5,8,16):
                actual, texels = run(mode,4,4,3,8,depth,side,10,10,values)
                expected = [old_address(image,depth,x,y,side) for y in range(10) for x in range(10)]
                assert actual == expected, ('historical malformed address mismatch',mode,depth,side)
                expected_texels = [old_address(image,3,x,y,8) for y in range(4) for x in range(4)]
                assert texels == expected_texels, ('retained edge tree changed',mode,depth,side)
                rows.append({'fixture':'compatibility:'+mode,'depth':depth,'side':side,'pixel_reads':len(actual),'texel_reads':len(texels)})

    assert sources == {name:digest(ROOT/name) for name in files}, 'Owned sources changed during verification'
    evidence = {'schema':1,'status':'passed','confidence':'high for stated checks',
                'source_sha256':sources,
                'compiler':{'path':str(BEND),'sha256':digest(BEND),'version':'2.0.35'},
                'checks':checks,'ownership':ownership,'emitted_c_sha256':digest(BUILD/'pixels.c'),
                'independent_fixture_source':str(reference_path.relative_to(ROOT)),
                'independent_fixture_sha256':digest(reference_path),'pinned_jar_sha256':digest(JAR),
                'fixture_count':len(fixtures),'compatibility_cases':126,
                'pixel_reads':sum(row['pixel_reads'] for row in rows),
                'texel_reads':sum(row['texel_reads'] for row in rows),'cases':rows,
                'proof_scope':'Uniform complete-ARGB Image representation invariance with sufficient depth, exact compressed leaf, exhausted Qua returns zero; actual production functions, no axioms/unsafe/foreign proof evidence.',
                'limitations':'No full renderer build, frame-rate benchmark, GUI launch or universal preservation proof for nonuniform malformed Image trees. Native edge compatibility uses the historical address semantics; ordinary/Java/Pillow fixtures provide independent expected words.',
                'command':'python3 tools/texture_borrow_test.py'}
    path = ROOT/'evidence/texture_borrow_native.json'
    path.write_text(json.dumps(evidence,indent=2)+'\n')
    print(json.dumps({key:evidence[key] for key in ('status','fixture_count','compatibility_cases','pixel_reads','texel_reads','ownership')}))

if __name__ == '__main__':
    main()
