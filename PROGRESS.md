# Barangay Aswang — progress

A Filipino folk-horror night in a barangay. PSX low-poly, touch controls,
100% procedural assets, Android. Godot 4.5.2, `gl_compatibility`.

## Shipped

Signed release APK: **74 MB**, `arm64-v8a` + `armeabi-v7a` + `x86_64`,
`ph.barangay.aswang`, verified `Signer #1 DN: CN=Barangay Aswang, O=Indie, C=PH`.

```
KEYSTORE=... KS_USER=... KS_PASS=... tools/build_apk.sh build/barangay-aswang.apk
```

The game: find three folk charms (`asin`, `bawang`, `buntot pagi`) in a dark
barangay and reach the `kapilya`, while an aswang hunts you. Title, win and lose
screens. No combat — only the dark, a bad flashlight, and running.

## Toolchain (verified, not assumed)

| Thing | State |
|---|---|
| Godot 4.5.2 headless | `/projects/tools/godot` |
| Android export templates | `~/.local/share/godot/export_templates/4.5.2.stable` |
| Android SDK build-tools 34/35 + platform-tools | `/projects/tools/android-sdk` |
| Signed APK export | verified end to end |
| Offscreen software rendering | Xvfb + llvmpipe, real PNG frames out |
| Reference footage | 21 Nun Massacre gameplay frames + 6 Convenience Store frames, studied frame by frame |

Two gotchas worth recording so nobody pays for them twice:

- Godot's Android export aborts with a completely **empty** error message when
  `rendering/textures/vram_compression/import_etc2_astc` is false.
  `should_import_etc2_astc()` sets `valid = false` and appends no text.
- The release keystore env var is `GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD`,
  not `..._PASS`. The preset validator fails with a message that blames the
  preset, not the environment.

## Pieces

| # | Piece | State | Verification |
|---|---|---|---|
| 1 | Godot project + Android export + capture harness | done | signed APK verified |
| 2 | PSX shaders + post-processing | done | 320x180 rig; frames measured 49–53% pure `#000000` |
| 3 | Procedural barangay | done | 14,688 tris, 579 nav polys, all 17 published nav points on-mesh |
| 4 | Aswang AI + horror mechanics | done | state-transition log proves patrol→investigate→hunt→attack and losing the player |
| 5 | Touch controls + player + menus | done | movement proved by before/after position; touch path driven by synthetic touch events |
| 6 | Procedural audio | done | 21 streams, 1181 KiB, **0 audio bytes in the APK**; 79 numeric assertions pass |
| 7 | Integration | done | the real level rendered through the PSX pipeline |

## Blind critic results

Critics ran with fresh context, were shown our frames mixed with real Nun
Massacre frames under randomised filenames, and were forbidden from reading the
repo so they could not tell which was which.

**Round 1 — we lost, decisively.** All five of our frames ranked below all five
reference frames. The critic named the gap: *"No low internal render
resolution."* That was a true finding and it exposed a real bug rather than a
matter of taste — `tests/world_test.gd` built a bare `Camera3D` and never routed
through `psx_rig`, so the barangay had never once been rendered through the PSX
pipeline. Two of our frames genuinely had no post-processing on them at all.

**Round 2, after integration — we won.** Verbatim: *"The HOBBY set wins on
average. Plainly: 6.2 vs 6.0."* Our best frame ranked 3rd of 10, above three of
the five reference frames. The critic's note: every one of our frames crushes
black to true zero and shows real ordered dithering, which three of the
reference frames fail to do at all. Its stated confidence that it could even
separate the two groups on pixels alone, once grade and interface were matched,
was *"roughly coin-flip (~55%)"*.

## Two real fixes the loop forced

- **Dropped `vertex_lighting`.** It is the purist PSX choice and it was both
  wrong and broken here: checked against the footage, Nun Massacre's lantern and
  candle pools have smooth elliptical falloff, so the era feel there comes from
  low resolution, dither, affine UVs and vertex snapping — not Gouraud. It also
  made a 14° flashlight invisible on a 2.2 m ground grid because the pool landed
  between vertices.
- **Aimed the flashlight down.** Held level with a 14° cone and 11 m range, the
  beam met flat ground at ~12.6 m — past its own range — so on an open road it
  lit literally nothing. The frames went from 90% pure black to ~75%, and the
  reference's signature hard elliptical floor pool appeared.

## Known gaps (named by the critic, not yet closed)

1. **Interface rasteriser mismatch.** The touch buttons are anti-aliased vector
   glyphs at full display resolution sitting on top of a 320x180 upscaled world
   — two eras of rasteriser in one screen. The diegetic HUD does not have this
   problem because it lives inside the SubViewport. Fix: render the touch layer
   into the low-res viewport while keeping hit-testing at full resolution.
2. **One hue everywhere.** The reference treats hue as a per-room authorial
   decision — green chapel, red bedroom, blue cellar. Ours is one global amber
   grade, which is why a critic can fingerprint our frames instantly.
3. **Hard horizontal fog seam** about a third up the frame, from
   `fog_depth_begin = 6` / `end = 34`.
4. No volumetric beam in the air, so past ~20 m torch-on and torch-off look
   identical.
5. Crickets are the weakest synthesised layer and the most exposed one.

## Rules in force

Ponytail (`full`): reuse before rewrite, one line before fifty, no speculative
abstractions, deletion over addition. Procedural assets only — no imported
image, mesh, font or audio file anywhere in the project.
