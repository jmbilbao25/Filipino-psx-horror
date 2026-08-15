# Download

**[barangay-aswang.apk](barangay-aswang.apk)** — 73 MB, signed, ready to install.

Open it on an Android phone. You must allow "install from unknown source",
because this is signed with a self-made key, not by Google Play.

- `arm64-v8a`, `armeabi-v7a`, `x86_64`
- package `ph.barangay.aswang`, landscape
- signature verified: `CN=Barangay Aswang, O=Indie, C=PH`
- SHA-256 of the signing certificate:
  `6033a9c178e3b97cb6a8d74a0cfdd790538ad71cffd29ba28a74c02f9e1bf81d`

## How to play

Find three charms — **asin** (salt), **bawang** (garlic), **buntot pagi**
(stingray tail) — then reach the **kapilya** at the end of the road.

- **left thumb** — walk. The stick appears wherever your thumb lands.
- **right thumb** — drag to look.
- **ILAW** — flashlight. It has a battery, and it gets you seen.
- **TAKBO** — run. Sprinting is loud and carries about 26 m.
- **GAMIT** — interact.

You cannot fight the aswang. Stay dark, stay quiet, run.

## The one rule worth knowing

Folklore, and it is mechanically real here: the **tik-tik** call gets **quieter
as the aswang gets closer**, and stops completely within 5 m.

**The silence is the warning.**

## Rebuilding it yourself

The APK is committed so it can be downloaded without a build. To rebuild:

```
KEYSTORE=/path/release.keystore KS_USER=alias KS_PASS=pw \
  tools/build_apk.sh dist/barangay-aswang.apk
```

No keystore is committed. Generate one with `keytool -genkeypair`.
