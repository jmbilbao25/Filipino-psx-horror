#!/usr/bin/env bash
# Render the game offscreen on a software GPU and save PNG frames.
# This is how every critic sees the build: real pixels, not a description.
#
#   tools/capture.sh <shot_script> <out_dir> [WxH]
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${1:?usage: capture.sh <shot_script> <out_dir> [WxH]}"
OUT="${2:?usage: capture.sh <shot_script> <out_dir> [WxH]}"
RES="${3:-960x540}"
GODOT="${GODOT:-/projects/tools/godot}"

mkdir -p "$OUT"; rm -f "$OUT"/*.png 2>/dev/null

pkill -x Xvfb 2>/dev/null; sleep 1
(Xvfb :99 -screen 0 1920x1080x24 >/dev/null 2>&1 &)
sleep 2

export DISPLAY=:99 LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe
export GODOT_SILENCE_ROOT_WARNING=1
export SHOT_DIR="$OUT" SHOT_SCRIPT="$SCRIPT"

timeout 900 "$GODOT" --path "$REPO" --rendering-driver opengl3 \
  --resolution "$RES" --audio-driver Dummy 2>&1 \
  | grep -viE 'ALSA lib|audio_driver_alsa|All audio drivers|audio_server\.cpp|init_output_device|XDG_RUNTIME_DIR' \
  | tail -50

pkill -x Xvfb 2>/dev/null
echo "--- frames:"; ls "$OUT"/*.png 2>/dev/null
