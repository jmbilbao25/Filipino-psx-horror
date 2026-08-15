#!/usr/bin/env bash
# Build a signed release APK. Keystore comes from the environment so no secret
# ever lands in the repo.
#
#   KEYSTORE=/path/release.keystore KS_USER=alias KS_PASS=pw tools/build_apk.sh out.apk
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-$REPO/build/barangay-aswang.apk}"
GODOT="${GODOT:-/projects/tools/godot}"

export ANDROID_HOME="${ANDROID_HOME:-/projects/tools/android-sdk}"
export JAVA_HOME="${JAVA_HOME:-/root/.local/share/mise/installs/java/25}"
export GODOT_SILENCE_ROOT_WARNING=1

# Godot reads the release keystore from these three env vars.
export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="${KEYSTORE:?set KEYSTORE}"
export GODOT_ANDROID_KEYSTORE_RELEASE_USER="${KS_USER:?set KS_USER}"
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="${KS_PASS:?set KS_PASS}"

mkdir -p "$(dirname "$OUT")"

echo "== importing resources"
# First import always reports missing .godot artifacts; that is expected.
"$GODOT" --headless --path "$REPO" --import 2>&1 | grep -iE '^(ERROR|SCRIPT ERROR)' || true

echo "== exporting $OUT"
"$GODOT" --headless --path "$REPO" --export-release Android "$OUT" 2>&1 \
  | grep -viE 'No project icon|^$' | tail -25

test -f "$OUT" || { echo "FAILED: no APK produced"; exit 1; }

echo "== verifying signature"
APKSIGNER="$(ls -d "$ANDROID_HOME"/build-tools/*/apksigner | sort -V | tail -1)"
"$APKSIGNER" verify --print-certs "$OUT" 2>/dev/null | grep -E 'Signer #1 certificate (DN|SHA-256)'

echo "== OK  $(du -h "$OUT" | cut -f1)  $OUT"
