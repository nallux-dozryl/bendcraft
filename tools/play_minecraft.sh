#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
actor="$root/build/compiler-producer-diagnostic-012/actor"
renderer="$root/build/playable-renderer-current/007/renderer"
python='/Users/chuah/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3'
cd "$root"
if [ ! -x "$actor" ] || [ ! -x "$renderer" ] || [ ! -x "$python" ]; then
  echo "Current actor012, renderer007 and bundled Python are required." >&2; exit 1
fi
"$python" - "$actor" "$renderer" <<'CHECK'
import hashlib,sys
for path,expected in zip(sys.argv[1:],['3c773cc1a70bf614724b880bed403e4dba6b2b8800515ae8b1cb040573055c38','71d7763bc576509a8d8b43205eeb4bb07f4541c283a6bfd75f1ea15a6a7b0130']):
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
export MC_WORLD_PATH="${MC_WORLD_PATH:-$root/build/playable-world.nbt}"
export MC_WORLD_MISSING=create
export MC_LIVE_PORT="${MC_LIVE_PORT:-25565}"
export MC_BLOCK_REGISTRY="$root/generated/reference_blocks.tsv"
export MC_RENDER_PORT="${MC_RENDER_PORT:-25566}"
export MC_RENDER_TOKEN="${MC_RENDER_TOKEN:-$(/usr/bin/uuidgen)}"
export MC_RENDER_EPOCH="${MC_RENDER_EPOCH:-$(/usr/bin/uuidgen | /usr/bin/tr -d '-')}"
export MC_DEV_TOKEN="${MC_DEV_TOKEN:-$(/usr/bin/uuidgen)}"
export BEND_MINECRAFT_LAUNCH_MODE="${BEND_MINECRAFT_LAUNCH_MODE:-human}"
logs=$(/usr/bin/mktemp -d "$root/build/playable-renderer-current/007/current-launch.XXXXXX")
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
for ((i=0;i<200;i++)); do
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
  for name in MC_ACTOR_PID MC_LIVE_PORT MC_RENDER_PORT MC_RENDER_TOKEN MC_RENDER_EPOCH MC_DEV_TOKEN MC_WORLD_PATH BEND_MINECRAFT_LAUNCH_MODE; do printf 'export %s=%q\n' "$name" "${!name}"; done >"$connection"
  if kill -0 "$actor_pid" 2>/dev/null; then
    echo "Actor remains running (PID $actor_pid). No saved result is claimed. Reconnect: '$root/tools/play_minecraft.sh' --reconnect '$connection'. Make inventory space before closing again." >&2
  else
    echo "Actor is no longer running. No saved result is claimed. Connection details: $connection; logs: $logs" >&2
  fi
  exit 2
fi
if [ "$signal_status" -ne 0 ]; then renderer_status="$signal_status"; fi
exit "$renderer_status"
