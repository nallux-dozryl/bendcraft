#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python='/Users/chuah/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3'
seed="$root/build/generic-resource-world-sample-cooking-runtime/011/demo-seed.nbt"
"$python" - "$root" "$seed" <<'CHECK'
import hashlib,sys
from pathlib import Path
root,seed=map(Path,sys.argv[1:])
launcher=(root/'tools/play_minecraft.sh').read_text()
for declaration in ('actor="$root/build/compiler-producer-diagnostic-024/actor"',
                    'renderer="$root/build/generic-resource-world-sample-client-native/012/renderer"'):
    if declaration not in launcher:
        sys.exit('The verified actor024/cooking-client012 public pair must be selected first.')
if not seed.is_file() or hashlib.sha256(seed.read_bytes()).hexdigest()!='e88e15ab0267beb9fea4ad55c9b9b7cd3cca27eea0cf5a3cc6d7b59a2ad1b859':
    sys.exit('The validated empty-furnace demo seed is unavailable or changed.')
CHECK
directory=$(/usr/bin/mktemp -d "$root/build/cooking-demo.XXXXXX")
/bin/cp "$seed" "$directory/world.nbt"
/bin/chmod 600 "$directory/world.nbt"
export MC_WORLD_PATH="$directory/world.nbt"
echo "Cooking demo world copy: $MC_WORLD_PATH"
printf 'After a successful close/save, reopen it with: MC_WORLD_PATH=%q %q\n' "$MC_WORLD_PATH" "$root/tools/play_minecraft.sh"
echo 'If closing is refused, use the private reconnect command printed by the launcher first.'
echo 'Use the furnace ahead. Beef2 is in the first hotbar slot; coal2 is in the second.'
echo 'Move beef to the input and coal to the fuel slot. After cooking, take the output and close with E or Esc.'
exec "$root/tools/play_minecraft.sh" --hud-scale 3 "$@"
