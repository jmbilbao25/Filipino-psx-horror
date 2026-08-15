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

# Godot keeps the Android SDK path in EDITOR settings, not in the project, and it
# rewrites that file wholesale on any editor/--import run -- which silently drops
# these keys and makes the export fail with a "Missing build-tools" error even
# though the SDK is right there. So assert them every build instead of trusting
# a file outside the repo.
ES="$HOME/.config/godot/editor_settings-4.5.tres"
mkdir -p "$(dirname "$ES")" "$HOME/.local/share/godot/keystores"
DBG="$HOME/.local/share/godot/keystores/debug.keystore"
[ -f "$DBG" ] || keytool -keystore "$DBG" -storepass android -alias androiddebugkey \
  -keypass android -genkeypair -keyalg RSA -validity 10000 \
  -dname "CN=Android Debug,O=Android,C=US" >/dev/null 2>&1
python3 - "$ES" "$ANDROID_HOME" "$JAVA_HOME" "$DBG" <<'PYEOF'
import sys, pathlib, re
es, sdk, jdk, dbg = sys.argv[1:5]
want = {
    "export/android/android_sdk_path": sdk,
    "export/android/java_sdk_path": jdk,
    "export/android/debug_keystore": dbg,
    "export/android/debug_keystore_user": "androiddebugkey",
    "export/android/debug_keystore_pass": "android",
}
p = pathlib.Path(es)
txt = p.read_text() if p.exists() else '[gd_resource type="EditorSettings" format=3]\n\n[resource]\n'
if "[resource]" not in txt:
    txt += "\n[resource]\n"
for k, v in want.items():
    line = '%s = "%s"' % (k, v)
    if re.search(r'(?m)^%s\s*=' % re.escape(k), txt):
        txt = re.sub(r'(?m)^%s\s*=.*$' % re.escape(k), line, txt)
    else:
        txt = txt.replace("[resource]", "[resource]\n" + line, 1)
p.write_text(txt)
print("editor settings: android sdk/jdk paths asserted")
PYEOF

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
