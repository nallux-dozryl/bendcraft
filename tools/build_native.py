#!/usr/bin/env python3
"""Content-checked cache of the verified Bend CLI's ordinary CPU native output."""
from __future__ import annotations

import argparse
from contextlib import contextmanager
import fcntl
import hashlib
import json
import os
from pathlib import Path
import platform
import posixpath
import re
import shlex
import shutil
import stat
import subprocess
import sys
import tempfile
import time
from typing import Mapping

PINNED_VERSION = "bend 2.0.35"
PINNED_BEND_SHA256 = "99b3de8f6c5643d245bed839df2c28d1bb12efd41bb221154d25c15695b72e8e"
SCHEMA = 1
ROOT = Path(__file__).resolve().parents[1]
# All environment entries are keyed: wrappers/driver options must not silently
# alter a build. These injection mechanisms require additional dependency rules.
UNSUPPORTED_ENV = ("LD_PRELOAD", "DYLD_INSERT_LIBRARIES", "CCC_OVERRIDE_OPTIONS")


class CacheUnavailable(RuntimeError):
    """An input/compiler/build route cannot be completely resolved by this cache."""


class BuildFailed(RuntimeError):
    pass


class InputsChanged(RuntimeError):
    pass


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def encoded(value: object) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode()


def file_digest(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def stamp(path: Path) -> tuple:
    s = path.stat()
    return (s.st_dev, s.st_ino, s.st_size, s.st_mtime_ns, s.st_ctime_ns, s.st_mode)


class Snapshot:
    def __init__(self):
        self.files: dict[str, dict] = {}
        self.stamps: dict[str, tuple] = {}
        self._content: dict[str, tuple[str, bytes | None, tuple]] = {}

    def add(self, path: Path, kind: str, *, text: bool = False) -> str | None:
        lookup = str(path.expanduser().absolute())
        try:
            real = path.expanduser().resolve(strict=True)
            if not real.is_file():
                raise CacheUnavailable(f"dependency is not a regular file: {lookup}")
            before = stamp(real)
            prior = self._content.get(str(real))
            if prior is not None and prior[2] != before:
                raise InputsChanged(f"dependency changed between aliases: {lookup}")
            if prior is None or (text and prior[1] is None):
                data = real.read_bytes() if text else None
                sha = digest(data) if data is not None else file_digest(real)
                self._content[str(real)] = (sha, data, before)
            else:
                sha, data, _ = prior
            after = stamp(real)
        except (OSError, RuntimeError) as e:
            raise CacheUnavailable(f"unresolvable dependency {lookup}: {e}") from e
        if before != after:
            raise InputsChanged(f"dependency changed while hashing: {lookup}")
        if lookup in self.stamps and self.stamps[lookup] != after:
            raise InputsChanged(f"dependency changed during discovery: {lookup}")
        self.stamps[lookup] = after
        self.files[lookup] = {"lookup": lookup, "path": str(real), "kind": kind,
                              "sha256": sha, "bytes": after[2]}
        if text:
            try:
                return data.decode("utf-8")  # type: ignore[union-attr]
            except UnicodeDecodeError as e:
                raise CacheUnavailable(f"dependency is not UTF-8: {lookup}") from e
        return None

    def tree(self, path: Path, kind: str):
        if not path.is_dir():
            raise CacheUnavailable(f"missing toolchain directory: {path}")
        # Retain lookup paths as well as real paths; retargeted symlinks change keys.
        seen: set[str] = set()
        for directory, dirs, names in os.walk(path, followlinks=True):
            real = str(Path(directory).resolve())
            if real in seen:
                dirs[:] = []
                continue
            seen.add(real)
            for name in sorted(names):
                self.add(Path(directory) / name, kind)
            dirs.sort()

    def manifest(self) -> list[dict]:
        return [self.files[k] for k in sorted(self.files)]


def run(command: list[str], env: Mapping[str, str]) -> subprocess.CompletedProcess:
    try:
        result = subprocess.run(command, env=dict(env), text=True, capture_output=True)
    except OSError as e:
        raise CacheUnavailable(f"cannot run {command[0]}: {e}") from e
    if result.returncode:
        raise BuildFailed(f"command failed ({result.returncode}): {shlex.join(command)}\n"
                          + result.stdout[-8000:] + result.stderr[-8000:])
    return result


def resolve_executable(value: str, env: Mapping[str, str]) -> Path:
    found = shutil.which(value, path=env.get("PATH"))
    path = Path(found or value).expanduser().absolute()
    if not path.is_file() or not os.access(path, os.X_OK):
        raise CacheUnavailable(f"executable not found: {value}")
    return path


def foreign_paths(text: str):
    # The pinned parser accepts `import "literal.c"` inside a definition,
    # separated by arbitrary whitespace. Skip comments and ordinary literals.
    tokens = []
    i = 0
    while i < len(text):
        c = text[i]
        if c == "#":
            end = text.find("\n", i)
            i = len(text) if end < 0 else end + 1
        elif c in "\"'":
            quote, start = c, i + 1
            i += 1
            while i < len(text) and text[i] != quote:
                i += 2 if text[i] == "\\" else 1
            tokens.append(("string" if quote == '"' else "char", text[start:i]))
            i += 1
        elif c.isalpha() or c == "_":
            start = i
            i += 1
            while i < len(text) and (text[i].isalnum() or text[i] == "_"):
                i += 1
            tokens.append(("word", text[start:i]))
        else:
            if not c.isspace():
                tokens.append(("punct", c))
            i += 1
    for previous, current in zip(tokens, tokens[1:]):
        if previous == ("word", "import") and current[0] == "string":
            if not current[1].endswith((".c", ".js")):
                raise CacheUnavailable(f"unsupported foreign import: {current[1]}")
            yield current[1]


def source_graph(entry: Path, base: Path, env: Mapping[str, str], snapshot: Snapshot):
    library = Path(env.get("BEND_LIB", str(Path(env.get("HOME", str(Path.home()))) / ".bend/lib"))).absolute()
    visited, active, native = set(), set(), set()

    def load(path: Path):
        try:
            real = path.resolve(strict=True)
        except OSError as e:
            raise CacheUnavailable(f"unresolved Bend import {path}; no hub fetch is cached") from e
        if real in active:
            raise CacheUnavailable(f"Bend import cycle: {real}")
        if real in visited:
            return
        active.add(real)
        text = snapshot.add(path, "base" if real == base else "bend", text=True)
        assert text is not None
        aliases = set()
        for line in text.split("\n"):
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if not re.match(r"^import(?:\s|$)", line):
                break
            m = re.fullmatch(r"import\s+(\S+)(?:\s+as\s+([A-Za-z_]\w*))?\s*(?:#.*)?", line)
            if not m or (m[2] is None and m[1] != "Base"):
                raise CacheUnavailable(f"unsupported or malformed import in {real}: {line}")
            if m[2] is None:
                load(base)
                continue
            if m[2] in aliases or not m[1].endswith(".bend"):
                raise CacheUnavailable(f"invalid import in {real}: {line}")
            aliases.add(m[2])
            name = m[1]
            named = re.match(r"^([^/]*@[^/]*)/", name)
            if named:
                nv = named[1]
                if not re.fullmatch(r"[a-z][a-z0-9-]{0,63}@(?:0|[1-9][0-9]*)(?:\.(?:0|[1-9][0-9]*)){3}", nv):
                    raise CacheUnavailable(f"invalid package name: {nv}")
                mapping = snapshot.add(library / "names" / nv, "package-name", text=True)
                package = mapping.strip() if mapping is not None else ""
                if not re.fullmatch(r"0x[0-9a-f]{32}", package):
                    raise CacheUnavailable(f"unresolved package name: {nv}; run ordinary Bend first")
                name = package + name[len(nv):]
            normalized = posixpath.normpath(name)
            child = library / normalized if re.match(r"^0x[0-9a-f]+/", name) else real.parent / normalized
            load(child)
        for effect in foreign_paths(text):
            # JavaScript bodies are not read by Comp.effect_srcs for native C.
            if effect.endswith(".c"):
                native.add(Path(str(real.parent) + "/" + effect))
        active.remove(real)
        visited.add(real)

    load(entry)
    for path in sorted(native):
        text = snapshot.add(path, "native-effect", text=True)
        assert text is not None
        # Relative quoted includes would resolve against Bend's transient emitted
        # C directory, not this effect's directory. Never guess that directory.
        for include in re.finditer(r'^\s*#\s*(?:include|import|embed)\s+"([^"\n]+)"', text, re.M):
            if not Path(include[1]).is_absolute():
                raise CacheUnavailable(f"relative native include cannot be resolved safely: {path}: {include[1]}")
        if re.search(r"\b__(?:DATE|TIME|TIMESTAMP)__\b", text):
            raise CacheUnavailable(f"volatile compile-time macro in native effect: {path}")
        if path.resolve().parent != base.parent / "effs" and re.search(r"\b(?:__FILE__|__BASE_FILE__|__builtin_FILE)\b", text):
            raise CacheUnavailable(f"native effect depends on transient emitted filename: {path}")
    # book_read additionally observes this file's existence for a PROOF entry.
    if entry.name == "PROOF.bend":
        laws = entry.parent / "LAWS.bend"
        if laws.exists():
            snapshot.add(laws, "proof-import-requirement")
    return visited


def macho_dependencies(path: Path, executable: Path, env: Mapping[str, str], snapshot: Snapshot, seen: set[str]):
    real = path.resolve()
    if str(real) in seen:
        return
    seen.add(str(real))
    snapshot.add(path, "toolchain-dylib-or-tool")
    libraries = run(["/usr/bin/otool", "-arch", "arm64", "-L", str(path)], env).stdout
    loads = run(["/usr/bin/otool", "-arch", "arm64", "-l", str(path)], env).stdout
    def expand(value: str) -> Path:
        return Path(value.replace("@loader_path", str(path.parent)).replace("@executable_path", str(executable.parent)))
    rpaths = [expand(m[1]) for m in re.finditer(r"cmd LC_RPATH\n\s*cmdsize \d+\n\s*path (.*?) \(offset", loads)]
    # A dylib's own ID is printed by -L; it is not a further dependency.
    own_ids = set(m[1] for m in re.finditer(r"cmd LC_ID_DYLIB\n\s*cmdsize \d+\n\s*name (.*?) \(offset", loads))
    for name in re.findall(r"^\s+(.+?) \(compatibility version", libraries, re.M):
        if name in own_ids:
            continue
        if name.startswith("@rpath/"):
            candidates = [directory / name[len("@rpath/"):] for directory in rpaths]
            selected = next((p for p in candidates if p.is_file()), None)
            if selected is None:
                raise CacheUnavailable(f"unresolved toolchain dylib {name} loaded by {path}")
        else:
            selected = expand(name)
            if not selected.is_file():
                if name.startswith(("/System/Library/", "/usr/lib/")):
                    # Apple's protected dyld shared-cache libraries have no
                    # individual disk file. The OS build/ABI identity is keyed.
                    continue
                raise CacheUnavailable(f"unresolved toolchain dylib {name} loaded by {path}")
        macho_dependencies(selected, executable, env, snapshot, seen)


def compiler_identity(env: Mapping[str, str], snapshot: Snapshot) -> dict:
    candidates = ([env["CC"]] if env.get("CC") else []) + ["clang"]
    versions = set()
    for directory in env.get("PATH", "").split(os.pathsep):
        try:
            versions.update(n for n in os.listdir(directory or ".") if re.fullmatch(r"clang-\d+", n))
        except OSError:
            pass
    candidates += sorted(versions, key=lambda s: int(s.split("-")[1]), reverse=True)
    cc, version = None, ""
    for candidate in candidates:
        try:
            path = resolve_executable(candidate, env)
            result = run([str(path), "--version"], env)
            info = result.stdout + result.stderr
        except (CacheUnavailable, BuildFailed):
            continue
        match = re.search(r"^(Apple )?(?:\w+ )?clang version (\d+)", info, re.M)
        if match and int(match[2]) >= 14:
            cc, version = path, info
            break
    if cc is None:
        raise CacheUnavailable("the pinned Bend cc_find has no supported clang >= 14")
    with cc.open("rb") as selected:
        magic = selected.read(4)
    if magic not in (b"\xcf\xfa\xed\xfe", b"\xfe\xed\xfa\xcf", b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca", b"\xca\xfe\xba\xbf", b"\xbf\xba\xfe\xca"):
        raise CacheUnavailable("C compiler wrappers/scripts have unresolvable dependencies; select actual clang")
    snapshot.add(cc, "clang-driver")
    # Probe exactly the CPU flags selected by cli_build; -### also discloses the
    # selected cc1, linker, sysroot, target, deployment target and config flags.
    flags = ["-std=c11", "-O3", "/dev/null", "-lpthread", "-lm", "-o", "/dev/null"]
    probe = run([str(cc), "-x", "c", *flags, "-###"], env)
    driver = probe.stdout + probe.stderr
    commands = []
    for line in driver.splitlines():
        if line.lstrip().startswith('"'):
            try:
                commands.append(shlex.split(line))
            except ValueError as e:
                raise CacheUnavailable(f"unparseable clang driver command: {line}") from e
        if line.startswith("Configuration file: "):
            snapshot.add(Path(line[len("Configuration file: "):]), "clang-config")
    roots = set()
    macho_seen: set[str] = set()
    for command in commands:
        if command and Path(command[0]).is_file():
            snapshot.add(Path(command[0]), "clang-tool")
            macho_dependencies(Path(command[0]), Path(command[0]), env, snapshot, macho_seen)
        for word in command:
            if Path(word).is_absolute() and Path(word).is_file():
                snapshot.add(Path(word), "clang-driver-input")
                if word.endswith(".dylib"):
                    macho_dependencies(Path(word), Path(command[0]), env, snapshot, macho_seen)
        for index, word in enumerate(command[:-1]):
            if word in ("-isysroot", "-syslibroot"):
                roots.add(Path(command[index + 1]).resolve())
    resource = Path(run([str(cc), "-print-resource-dir"], env).stdout.strip())
    snapshot.tree(resource, "clang-resource")
    if platform.system() != "Darwin" or not roots:
        # Linux library and dynamic-loader closure needs a separate verified rule.
        raise CacheUnavailable("this verified cache currently supports ordinary macOS CPU builds only")
    for sdk in sorted(roots):
        for name in ("SDKSettings.json", "SDKSettings.plist"):
            path = sdk / name
            if path.exists():
                snapshot.add(path, "sdk-config")
        # Includes the -lm/-lpthread aliases, libSystem stubs and their reexports.
        snapshot.tree(sdk / "usr/lib", "sdk-link-library")
    # The linker trace resolves actual selected libraries, including a library
    # shadowing an SDK alias through an external search directory or config.
    with tempfile.TemporaryDirectory(prefix="bend-cache-link-") as temporary:
        probe_source = Path(temporary) / "probe.c"
        probe_source.write_text("int main(void) { return 0; }\n")
        linked = run([str(cc), "-std=c11", "-O3", str(probe_source), "-lpthread", "-lm",
                      "-Wl,-t", "-o", str(Path(temporary) / "probe")], env)
        for line in (linked.stdout + linked.stderr).splitlines():
            path = Path(line.strip().split("(", 1)[0])
            if path.is_absolute() and path.is_file() and not str(path).startswith(temporary + "/"):
                snapshot.add(path, "linker-selected-input")
    # Only clang-generated ephemeral .o paths are normalized, not user paths.
    ephemeral = {word for command in commands for word in command
                 if re.fullmatch(r".*/null-[0-9a-f]+\.o", word)}
    for name in sorted(ephemeral, key=len, reverse=True):
        driver = driver.replace(name, "<temporary.o>")
    return {"path": str(cc), "version": version, "driver_probe": driver,
            "resource_dir": str(resource.resolve()), "sysroots": sorted(map(str, roots)),
            "flags": ["-std=c11", "-O3", "<emitted.c>", "-lpthread", "-lm", "-o", "<native>"]}


@contextmanager
def lock(path: Path):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a+b") as handle:
        fcntl.flock(handle.fileno(), fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(handle.fileno(), fcntl.LOCK_UN)


def read_json(path: Path) -> dict | None:
    try:
        value = json.loads(path.read_text())
        return value if isinstance(value, dict) else None
    except (OSError, ValueError):
        return None


def guard_route(source: str):
    if not re.search(r"^#define BANGS\s+0$", source, re.M):
        raise CacheUnavailable("GPU/bang output is outside the plain CPU native cache")
    if re.search(r"^#import ", source, re.M):
        raise CacheUnavailable("Window/framework output requires the separate guarded platform_build.py route")
    if re.search(r"^\s*#\s*pragma\s+(?:comment\s*\(\s*(?:lib|linker)|clang\s+linker_option)", source, re.M):
        raise CacheUnavailable("source-directed library linkage is outside the verified CPU cache")
    if "#include <X11/" in source or "#include <alsa/" in source:
        raise CacheUnavailable("X11/ALSA library closure is outside the verified CPU cache")


def _collect(entry: Path, bend: Path, env: dict[str, str]) -> tuple:
    snapshot = Snapshot()
    snapshot.add(Path(__file__), "cache-policy")
    snapshot.add(bend, "bend-executable")
    compiler_sha = snapshot.files[str(bend.absolute())]["sha256"]
    if compiler_sha != PINNED_BEND_SHA256:
        raise CacheUnavailable("Bend executable differs from the verified dependency-loader digest")
    version = run([str(bend), "version"], env).stdout.strip()
    if version != PINNED_VERSION:
        raise CacheUnavailable(f"expected {PINNED_VERSION}, got {version}")
    base = (bend.resolve().parent.parent / "bend2/base.bend").resolve()
    source_graph(entry, base, env, snapshot)
    compiler = compiler_identity(env, snapshot)
    effective_env = dict(env)
    effective_env["CC"] = compiler["path"]
    # Values are hashed rather than recorded: an inherited environment may have
    # secrets. The full digest safely over-invalidates on irrelevant changes.
    context = {"schema": SCHEMA, "entry": str(entry), "bend_version": version,
               "platform": platform.platform(), "system": platform.system(),
               "machine": platform.machine(), "uname": list(platform.uname()),
               "os_build": run(["/usr/bin/sw_vers", "-buildVersion"], env).stdout.strip(),
               "cwd": str(Path.cwd().resolve()), "environment_sha256": digest(encoded(env)),
               "compiler": compiler, "files": snapshot.manifest()}
    return snapshot, context, effective_env


def _sources(entry: Path, bend: Path, env: dict[str, str], cache: Path) -> tuple:
    snapshot, context, effective_env = _collect(entry, bend, env)
    prekey = digest(encoded(context))
    target = cache / "sources" / prekey
    emitted = target / "generated.c"
    emitted_seconds = 0.0
    with lock(cache / "locks" / f"source-{prekey}.lock"):
        record = read_json(target / "manifest.json")
        valid = (record is not None and record.get("prekey") == prekey and emitted.is_file()
                 and record.get("sha256") == file_digest(emitted))
        if not valid:
            started = time.perf_counter()
            with tempfile.TemporaryDirectory(prefix=".source-", dir=cache / "sources") as temporary:
                temporary = Path(temporary)
                generated = temporary / "generated.c"
                run([str(bend), str(entry), "-o", str(generated)], effective_env)
                emitted_seconds = time.perf_counter() - started
                if not generated.is_file():
                    raise BuildFailed("Bend did not emit C; its native checker rejected the program")
                source = generated.read_text()
                guard_route(source)
                after, after_context, _ = _collect(entry, bend, env)
                if digest(encoded(after_context)) != prekey or after.stamps != snapshot.stamps:
                    raise InputsChanged("dependencies changed during C emission")
                record = {"prekey": prekey, "sha256": file_digest(generated)}
                (temporary / "manifest.json").write_bytes(encoded(record))
                if target.exists():
                    shutil.rmtree(target)
                os.replace(temporary, target)
        source = emitted.read_text()
        guard_route(source)
        # While locked, load bytes. Other builders never rewrite valid source.
        emitted_sha = digest(source.encode())
        if record is None or record.get("sha256") != emitted_sha:
            raise InputsChanged("emitted source changed while reading it")
    return snapshot, context, prekey, emitted, emitted_sha, effective_env, emitted_seconds


def _prepare(entry: Path, bend: Path, env: dict[str, str], cache: Path) -> dict:
    snapshot, context, prekey, emitted, emitted_sha, effective_env, seconds = _sources(entry, bend, env, cache)
    with tempfile.TemporaryDirectory(prefix=".deps-", dir=cache) as temporary:
        deps = Path(temporary) / "headers.d"
        run([context["compiler"]["path"], "-std=c11", "-O3", "-M", "-MF", str(deps),
             "-MT", "bend-cache-probe", str(emitted)], effective_env)
        text = deps.read_text().replace("\\\n", "")
        if ":" not in text:
            raise CacheUnavailable("Clang did not report a native header dependency graph")
        try:
            headers = shlex.split(text.split(":", 1)[1])
        except ValueError as e:
            raise CacheUnavailable("cannot parse Clang header dependency graph") from e
        for header in headers:
            path = Path(header)
            if path.resolve() != emitted.resolve():
                snapshot.add(path, "native-header")
    key_data = {"prekey": prekey, "emitted_c_sha256": emitted_sha,
                "dependencies": snapshot.manifest()}
    return {"cache_key": digest(encoded(key_data)), "key_data": key_data, "context": context,
            "snapshot": snapshot, "env": effective_env, "emitted_seconds": seconds,
            "emitted_c_sha256": emitted_sha}


def _verified(directory: Path, key: str) -> dict | None:
    record = read_json(directory / "manifest.json")
    binary = directory / "program"
    if not record or record.get("cache_key") != key or not binary.is_file():
        return None
    if not os.access(binary, os.X_OK) or record.get("binary_sha256") != file_digest(binary):
        return None
    if digest(encoded(record.get("key_data"))) != key:
        return None
    frozen = directory.parent.parent / "artifacts" / record["binary_sha256"] / "program"
    if not frozen.is_file() or not os.access(frozen, os.X_OK) or file_digest(frozen) != record["binary_sha256"]:
        return None
    return record


def _freeze(binary: Path, cache: Path, expected: str) -> Path:
    target = cache / "artifacts" / expected
    frozen = target / "program"
    with lock(cache / "locks" / ("artifact-" + expected + ".lock")):
        if frozen.is_file() and os.access(frozen, os.X_OK) and file_digest(frozen) == expected:
            return frozen
        with tempfile.TemporaryDirectory(prefix=".artifact-", dir=cache / "artifacts") as temporary:
            temporary = Path(temporary)
            shutil.copy2(binary, temporary / "program")
            if file_digest(temporary / "program") != expected:
                raise InputsChanged("executable changed while freezing its artifact")
            if target.exists():
                shutil.rmtree(target)
            os.replace(temporary, target)
    return frozen


def _publish(binary: Path, output: Path, expected: str, cache: Path):
    with lock(cache / "locks" / ("output-" + digest(str(output).encode()) + ".lock")):
        if output.is_symlink():
            raise CacheUnavailable(f"output became a symlink during build: {output}")
        if output.is_file() and os.access(output, os.X_OK) and file_digest(output) == expected:
            return False
        with tempfile.NamedTemporaryFile(prefix="." + output.name + ".", dir=output.parent, delete=False) as temporary:
            path = Path(temporary.name)
            try:
                with binary.open("rb") as source:
                    shutil.copyfileobj(source, temporary)
                temporary.flush()
                os.fsync(temporary.fileno())
                os.chmod(path, stat.S_IMODE(binary.stat().st_mode))
                if file_digest(path) != expected:
                    raise InputsChanged("cached executable changed during publication")
                os.replace(path, output)
            finally:
                path.unlink(missing_ok=True)
        return True


def ensure_native(entry: str | Path, output: str | Path, *, bend: str | Path | None = None,
                  cache_dir: str | Path | None = None, env: Mapping[str, str] | None = None,
                  force: bool = False) -> dict:
    """Build/reuse checked plain CPU native output, returning paths and evidence.

    `env` overrides inherited environment entries. `artifact` is the immutable
    key-specific executable; `path` is an atomically published convenience copy.
    Unsupported/unresolved dependencies raise CacheUnavailable, never a stale hit.
    """
    started = time.perf_counter()
    environment = dict(os.environ)
    if env is not None:
        environment.update({str(k): str(v) for k, v in env.items()})
    for name in set(UNSUPPORTED_ENV) | {k for k in environment if k.startswith("DYLD_")}:
        if environment.get(name):
            raise CacheUnavailable(f"unresolved compiler injection environment: {name}")
    entry = Path(entry).expanduser().resolve()
    output = Path(output).expanduser().absolute()
    # Match output aliases as well as paths, without replacing the aliased file.
    if output.is_symlink():
        raise CacheUnavailable(f"output must not be a symlink: {output}")
    if output.suffix in (".js", ".mjs", ".cjs", ".c", ".bendtt"):
        raise CacheUnavailable("output extension selects a non-native Bend CLI route")
    if output.is_dir():
        raise CacheUnavailable("native output is a directory")
    default_bend = environment.get("BEND") or shutil.which("bend", path=environment.get("PATH")) or str(Path.home() / ".bend/bin/bend")
    bend = resolve_executable(str(bend or default_bend), environment).resolve()
    cache = Path(cache_dir or ROOT / "build/native-cache").expanduser().resolve()
    for name in ("", "sources", "entries", "artifacts", "locks"):
        (cache / name).mkdir(parents=True, exist_ok=True, mode=0o700)
    output.parent.mkdir(parents=True, exist_ok=True)
    retries = 0
    for attempt in range(3):
        try:
            prepared = _prepare(entry, bend, environment, cache)
            inputs = prepared["snapshot"].files
            if str(output.resolve()) in {item["path"] for item in inputs.values()}:
                raise CacheUnavailable("native output would overwrite a compilation dependency")
            key = prepared["cache_key"]
            directory = cache / "entries" / key
            compile_seconds = 0.0
            with lock(cache / "locks" / ("native-" + key + ".lock")):
                record = None if force else _verified(directory, key)
                hit = record is not None
                if not hit:
                    compiling = time.perf_counter()
                    with tempfile.TemporaryDirectory(prefix=".native-", dir=cache / "entries") as temporary:
                        temporary = Path(temporary)
                        binary = temporary / "program"
                        result = run([str(bend), str(entry), "-o", str(binary)], prepared["env"])
                        if not binary.is_file() or not os.access(binary, os.X_OK):
                            raise BuildFailed("Bend did not produce an executable; native checker/build rejected it")
                        compile_seconds = time.perf_counter() - compiling
                        checked = _prepare(entry, bend, environment, cache)
                        if (checked["cache_key"] != key or checked["snapshot"].stamps != prepared["snapshot"].stamps):
                            raise InputsChanged("dependencies changed during native compilation")
                        record = {"schema": SCHEMA, "cache_key": key, "key_data": prepared["key_data"],
                                  "binary_sha256": file_digest(binary), "binary_bytes": binary.stat().st_size,
                                  "emitted_c_sha256": prepared["emitted_c_sha256"],
                                  "build_command": [str(bend), str(entry), "-o", "<unique temporary native path>"],
                                  "compiler": prepared["context"]["compiler"],
                                  "build_stdout": result.stdout[-4000:], "build_stderr": result.stderr[-4000:]}
                        _freeze(binary, cache, record["binary_sha256"])
                        (temporary / "manifest.json").write_bytes(encoded(record))
                        if directory.exists():
                            shutil.rmtree(directory)
                        os.replace(temporary, directory)
                else:
                    checked = _prepare(entry, bend, environment, cache)
                    if (checked["cache_key"] != key or checked["snapshot"].stamps != prepared["snapshot"].stamps):
                        raise InputsChanged("dependencies changed during cache verification")
                assert record is not None
                binary = cache / "artifacts" / record["binary_sha256"] / "program"
                if _verified(directory, key) is None:
                    raise InputsChanged("native artifact failed its digest check before publication")
                published = _publish(binary, output, record["binary_sha256"], cache)
                return {"path": str(output), "artifact": str(binary), "cache_key": key, "cache_hit": hit,
                        "output_replaced": published, "binary_sha256": record["binary_sha256"],
                        "binary_bytes": record["binary_bytes"], "emitted_c_sha256": record["emitted_c_sha256"],
                        "dependencies": prepared["snapshot"].manifest(), "compiler": prepared["context"]["compiler"],
                        "identity": {k: v for k, v in prepared["context"].items() if k not in ("files", "compiler")},
                        "retries": retries, "timings": {"total_seconds": time.perf_counter() - started,
                        "emission_seconds": prepared["emitted_seconds"], "native_seconds": compile_seconds}}
        except InputsChanged:
            retries += 1
            if attempt == 2:
                raise InputsChanged("inputs kept changing; no native output was published")
    raise AssertionError("unreachable")


def main(argv: list[str] | None = None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    if argv and argv[0] == "build":
        argv.pop(0)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("entry", type=Path)
    parser.add_argument("-o", "--output", type=Path, required=True)
    parser.add_argument("--bend")
    parser.add_argument("--cache-dir", type=Path)
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--report", type=Path)
    args = parser.parse_args(argv)
    try:
        report = ensure_native(args.entry, args.output, bend=args.bend, cache_dir=args.cache_dir, force=args.force)
    except (CacheUnavailable, BuildFailed, InputsChanged) as e:
        print(f"native cache: {e}", file=sys.stderr)
        return 1
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(prefix=".report-", dir=args.report.parent, delete=False) as temporary:
            temporary.write(json.dumps(report, indent=2).encode() + b"\n")
            name = temporary.name
        os.replace(name, args.report)
    print(json.dumps({k: report[k] for k in ("path", "artifact", "cache_key", "cache_hit", "binary_sha256", "timings")}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
