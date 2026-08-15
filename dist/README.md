# Download

> **Build 4 is a diagnostic build.** A phone renders the game black while every
> offscreen desktop capture is correct, so the failure is in mobile GLES and
> cannot be reproduced on the build machine. This build reports its own state
> on screen, outside the two suspect layers, and lets you bypass the
> post-processing live. See "If the screen is black" at the bottom.

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


## If the screen is black

The top of the screen now draws a strip of **colour bars** and three lines of
text on a plain full-resolution layer. That layer sits **outside** the 320x180
SubViewport and **outside** `post.gdshader` — the two things suspected of
rendering black. So:

| What you see | What it means |
|---|---|
| Nothing at all, pure black | The engine or the whole 2D canvas is failing. Not a shader problem. |
| Colour bars + text, game still black | The SubViewport / post-processing chain is the culprit. |
| Bars, text, and a blue title screen | Rendering is fine. |

**Then tap the box in the top-right marked `PLAIN`.** That switches the
post-processing off and shows the raw 320x180 image. It survives into the game,
so you can play with it off.

- If **PLAIN: ON** makes the picture appear, the post shader is at fault.
- If it is still black with PLAIN on, the SubViewport is at fault.

Either answer is enough to fix it properly. Please also report the third line of
text, which names the GPU and the driver.

If you have `adb`, `adb logcat -s godot:V` prints the same information plus a
`rig:` line showing whether the render target and material are actually attached.
