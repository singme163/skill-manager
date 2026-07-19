#!/bin/zsh
# Regenerates the documentation screenshots in docs/images/ by driving the
# app's built-in snapshot mode (SM_SNAPSHOT_DIR) and capturing each staged
# window with `screencapture -l` (requires Screen Recording permission for
# the terminal; falls back to the app's self-render when EXTERNAL=0).
set -euo pipefail
cd "$(dirname "$0")/.."

./Scripts/make-app.sh >/dev/null

DIR="$PWD/docs/images"
mkdir -p "$DIR"
rm -f "$DIR"/*.ready "$DIR"/*.done 2>/dev/null || true
pkill -x SkillManager 2>/dev/null || true
sleep 1

SM_SNAPSHOT_DIR="$DIR" SM_SNAPSHOT_EXTERNAL=1 ./dist/SkillManager.app/Contents/MacOS/SkillManager &

for name in main lint translate discovery sync; do
    n=0
    while [[ ! -f "$DIR/$name.ready" && $n -lt 100 ]]; do sleep 0.3; n=$((n+1)); done
    if [[ -f "$DIR/$name.ready" ]]; then
        screencapture -x -l "$(cat "$DIR/$name.ready")" "$DIR/$name.png"
        touch "$DIR/$name.done"
        echo "captured $name.png"
    else
        echo "TIMEOUT waiting for $name" >&2
    fi
done
wait
echo "Done: $DIR"
