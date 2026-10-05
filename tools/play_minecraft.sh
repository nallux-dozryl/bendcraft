#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
actor="$root/build/compiler-producer-diagnostic-024/actor"
renderer="$root/build/generic-resource-world-sample-client-native/012/renderer"
python='/Users/chuah/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3'
cd "$root"
if [ ! -x "$actor" ] || [ ! -x "$renderer" ] || [ ! -x "$python" ]; then
  echo "Current actor024, cooking catalog renderer012 and bundled Python are required." >&2; exit 1
fi
"$python" - "$actor" "$renderer" <<'CHECK'
import hashlib,sys
for path,expected in zip(sys.argv[1:],['c8dd57c0f5cd6d3607bc932bf6bb74ce27009f8b90efa7db4309beea5d1e2cc4','3bd945855c7526f713ed1df03ab89e136429fbc36132f6152ef16fc7a491a232']):
    if hashlib.sha256(open(path,'rb').read()).hexdigest()!=expected:
        sys.exit('Current playable binary changed: '+path)
CHECK
reconnect=''
if [ "${1:-}" = '--reconnect' ]; then
  if [ "$#" -lt 2 ]; then echo "--reconnect requires the private connection.env path." >&2; exit 1; fi
  reconnect="$2"; shift 2
  "$python" - "$reconnect" <<'PRIVATE'
import os,stat,sys
value=os.stat(sys.argv[1])
if not stat.S_ISREG(value.st_mode) or value.st_uid!=os.getuid() or stat.S_IMODE(value.st_mode)!=0o600:
    sys.exit('Reconnect file must be owned by you with permissions0600.')
PRIVATE
  source "$reconnect"
fi
export MC_WORLD_PATH="${MC_WORLD_PATH:-$root/build/playable-world-022.nbt}"
export MC_WORLD_MISSING=create
read -r MC_LIVE_PORT MC_RENDER_PORT < <("$python" - "${MC_LIVE_PORT:-}" "${MC_RENDER_PORT:-}" <<'PORTS'
import socket,sys
values=[]
for value in sys.argv[1:]:
    if value and (not value.isdecimal() or not 1<=int(value)<=65535):
        sys.exit('Explicit Minecraft ports must be integers from 1 through 65535.')
    values.append(int(value) if value else None)
if values[0] is not None and values[0]==values[1]:
    sys.exit('The public and private Minecraft ports must differ.')
used={p for p in values if p is not None};held=[]
try:
    for index,preferred in enumerate((25565,25566)):
        if values[index] is not None:
            continue
        listener=socket.socket(socket.AF_INET,socket.SOCK_STREAM)
        held.append(listener)
        try:
            if preferred in used:
                raise OSError('Port is reserved by the other explicit endpoint')
            listener.bind(('127.0.0.1',preferred))
        except OSError:
            listener.bind(('127.0.0.1',0))
        while listener.getsockname()[1] in used:
            listener=socket.socket(socket.AF_INET,socket.SOCK_STREAM)
            held.append(listener)
            listener.bind(('127.0.0.1',0))
        values[index]=listener.getsockname()[1]
        used.add(values[index])
    print(*values)
finally:
    for listener in held:
        listener.close()
PORTS
)
export MC_LIVE_PORT MC_RENDER_PORT
export MC_COOKING_PROTOCOL=1
export MC_BLOCK_REGISTRY="$root/generated/reference_blocks.tsv"
export BEND_MINECRAFT_REGISTRY="$root/generated/reference_blocks.tsv"
export MC_RENDER_TOKEN="${MC_RENDER_TOKEN:-$(/usr/bin/uuidgen)}"
export MC_RENDER_EPOCH="${MC_RENDER_EPOCH:-$(/usr/bin/uuidgen | /usr/bin/tr -d '-')}"
export MC_DEV_TOKEN="${MC_DEV_TOKEN:-$(/usr/bin/uuidgen)}"
export BEND_MINECRAFT_LAUNCH_MODE="${BEND_MINECRAFT_LAUNCH_MODE:-human}"
logs=$(/usr/bin/mktemp -d "$root/build/generic-resource-world-sample-client-native/012/current-launch.XXXXXX")
if [ -z "$reconnect" ]; then
  "$actor" --gpu off --threads 2 -- --game-mode creative --sine "$root/generated/reference_mth_sin.f32" >"$logs/actor.stdout" 2>"$logs/actor.stderr" &
  actor_pid=$!
else
  actor_pid="${MC_ACTOR_PID:?Reconnect file is missing MC_ACTOR_PID}"
  "$python" - "$actor_pid" "$actor" <<'OWNER'
import subprocess,sys
value=sys.argv[1]
if not value.isdecimal() or int(value)<=1:
    sys.exit('Reconnect actor PID is invalid.')
actual=subprocess.check_output(['/bin/ps','-p',value,'-o','args='],text=True).strip()
if actual!=sys.argv[2] and not actual.startswith(sys.argv[2]+' '):
    sys.exit('Reconnect PID belongs to a different process.')
OWNER
  if ! kill -0 "$actor_pid" 2>/dev/null; then echo "Retained actor is no longer running." >&2; exit 1; fi
fi
export MC_ACTOR_PID="$actor_pid"
finish() { kill -TERM "$actor_pid" 2>/dev/null || true; wait "$actor_pid" 2>/dev/null || true; }
renderer_pid=''
signal_status=0
on_signal() {
  signal_status="$1"
  if [ -n "$renderer_pid" ]; then kill -TERM "$renderer_pid" 2>/dev/null || true; fi
}
trap finish EXIT
trap 'on_signal 130' INT
trap 'on_signal 143' TERM
ready=false
if [ -n "$reconnect" ]; then ready=true; fi
for ((i=0;i<1500;i++)); do
  if [ "$ready" = true ]; then break; fi
  if /usr/bin/grep -q 'renderer.ready' "$logs/actor.stdout"; then ready=true; break; fi
  if ! kill -0 "$actor_pid" 2>/dev/null; then cat "$logs/actor.stderr"; exit 1; fi
  sleep 0.1
done
renderer_status="$signal_status"
if [ "$ready" = true ] && [ "$signal_status" -eq 0 ]; then
  "$renderer" --gpu off --threads 2 -- --jar '/Users/chuah/Library/Application Support/minecraft/versions/26.3/26.3.jar' --item-table "$root/generated/reference_item_metadata.tsv" "$@" &
  renderer_pid=$!
  if wait "$renderer_pid"; then :; else renderer_status=$?; fi
  if [ "$signal_status" -ne 0 ]; then
    wait "$renderer_pid" 2>/dev/null || true
    renderer_status="$signal_status"
  fi
  renderer_pid=''
elif [ "$ready" != true ]; then
  cat "$logs/actor.stderr"; echo "Actor startup timed out; attempting close/save. Logs: $logs" >&2
  renderer_status=1
fi
if [ "$renderer_status" -ne 0 ]; then
  echo "Renderer exited with status $renderer_status; attempting close and durable save. Logs: $logs" >&2
fi
if ! "$python" "$root/tools/play_minecraft_close.py"; then
  trap - EXIT INT TERM
  connection="$logs/connection.env"
  umask 077
  for name in MC_ACTOR_PID MC_LIVE_PORT MC_RENDER_PORT MC_RENDER_TOKEN MC_RENDER_EPOCH MC_DEV_TOKEN MC_COOKING_PROTOCOL MC_WORLD_PATH BEND_MINECRAFT_LAUNCH_MODE; do printf 'export %s=%q\n' "$name" "${!name}"; done >"$connection"
  if kill -0 "$actor_pid" 2>/dev/null; then
    echo "Actor remains running (PID $actor_pid). No saved result is claimed. Reconnect: '$root/tools/play_minecraft.sh' --reconnect '$connection'. Make inventory space before closing again." >&2
  else
    echo "Actor is no longer running. No saved result is claimed. Connection details: $connection; logs: $logs" >&2
  fi
  exit 2
fi
if [ "$signal_status" -ne 0 ]; then renderer_status="$signal_status"; fi
exit "$renderer_status"
