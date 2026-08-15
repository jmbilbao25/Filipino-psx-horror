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

## Round 3 — the AI and audio critics, and what they broke

Two more fresh-context critics were run, one on the aswang, one on the audio.
Both were told to verify rather than trust, and both said **loses**. They were
right, and they found ten real defects that every earlier check had missed —
including checks written by the builders themselves.

The AI critic instrumented its own copy and logged `|last_known - true player
position|`, a number the shipped log never printed. That one measurement
collapsed the whole design:

| Defect | Evidence | Fixed |
|---|---|---|
| tik-tik gated behind `HUNT`, so the game's core tension instrument fired for **0 s of a 240 s night**, and silence meant both "nowhere near" and "right behind you" | `set_aswang_distance(d if hunting else INF)` | yes — pass the real distance always |
| `fuzz = 3.0 * (1.0 - n)` is **exactly 0** at sprint, so it held a perfect fix through walls for 70 s straight, `los=false` | `lk_err= 0.00` every frame | yes — floor of 2 m, never a fix |
| `hear_noise()` had **no range check**, so lifting a charm broadcast your exact position 50 m across the map | `lurk -> investigate d= 50.0m` | yes — same hearing model as sight |
| `_home` set once at spawn, so `patrol_radius` fenced it into one corner; **two of three charms were risk-free** | closest approach 14.7 m in 240 s | yes — radius covers the map |
| stood **frozen for the first 8 s** of every level: the dwell was spent even when the navmesh was not ready and no target got set | position identical t=0 → t=8 | yes — spend the dwell only once a target exists |
| player `RUN` 4.3 beat `HUNT` 3.5, so any chase ended by holding sprint in a straight line | hunt ended in 3.6 s | yes — HUNT 4.6 |

The audio critic re-measured everything independently and found the builder's
own tests were partly **vacuous**: the footstep-distinctness assertion compared
raw waveform correlation, which is always ~0 for different noise seeds and
therefore cannot fail; the cricket test passed for any 4 kHz sine. Its central
finding was worse than a bug:

- **91% of the tension mix sat below 200 Hz.** A phone speaker reproduces almost
  nothing under ~450 Hz, and the crickets ducked 24 dB to make room for it — so
  **raising tension made the game measurably quieter on the target device**,
  −2.7 to −4.2 dB. The mix reacted backwards to threat.
- Master clipped on the jumpscare: `bed(t=1) + scare` peaked 1.22 through the
  reverb bus. Per-stream normalisation cannot see a sum.
- Three of five loops pumped audibly (wind −10.9 dB every 3 s) because their LFO
  and partial periods did not divide the loop length.
- `tik_interval(1.0) = 0.85 s` was shorter than the 0.62 s sample: 86% duty at
  40 m, a machine gun rather than a sparse call.

Fixed, and the fix was **solved numerically rather than guessed** — a search over
candidate mixes for one that is louder through a phone highpass while keeping the
insect duck as a readable cue:

| Through | before | after |
|---|---|---|
| 300 Hz highpass | −2.7 dB | **+3.1 dB** |
| 450 Hz highpass | −3.6 dB | **+2.7 dB** |
| 600 Hz highpass | −4.2 dB | **+2.1 dB** |

Insects still duck 14 dB, so the cue survives. Drone partials moved to 700/1103 Hz
(whole cycles over the loop), wind LFO to 1/3 Hz, a limiter added to Master, and
the tik interval widened past the sample length. Verified: the call now fires
during LURK at 17.7 m and PATROL at 15.4 m — previously it never fired at all.

## Device bugs found by actually running it on a phone

Neither of these could be caught by the offscreen harness, which is the honest
limit of the whole verification setup: desktop GL is not mobile GLES.

**1. Portrait instead of landscape.** `window/handheld/orientation=1` — I read 1
as landscape. In Godot 4 the enum is `0 = Landscape`, `1 = Portrait`. Now 0, and
verified in the built APK rather than in the source:
`aapt2 dump xmltree` reports `android:screenOrientation=0`.

**2. Black screen with scanlines rolling down it.** `post.gdshader` used
`SCREEN_PIXEL_SIZE`, which in Godot is only valid in a `canvas_item` shader that
**also declares a `hint_screen_texture` sampler**. This shader does not, so on
mobile GLES it arrived as `0`:

```
px  = 1.0 / 0        = inf
asp = inf / inf      = NaN
mod(floor(UV * inf), 4.0)  -> NaN -> BAYER[undefined index]
step(NaN, 0.0)             -> undefined -> col *= 0
```

Everything multiplied to black, with a handful of pixels surviving — exactly what
the phone showed. Desktop GL happened to populate the builtin, which is why it
rendered perfectly in every capture. Fixed by removing the dependence entirely:
dither and grain now lock to a `const vec2 LOWRES = vec2(320.0, 180.0)`, which is
what the effect wanted in the first place, and the border uses a `16.0 / 9.0`
constant because the rig always presents a 16:9 image.

Also added `stretch_mode = 5` (keep-aspect-centered) to the rig, so an odd screen
letterboxes instead of stretching the 320x180 image over the whole panel.

## Known gaps (named by the critics, not yet closed)

0. **The aswang is nearly invisible.** Measured: with the torch off, past ~10 m
   it is numerically indistinguishable from not being there, and its emissive
   eyes are sub-pixel at 320x180. This also silently disables the LURK
   "gone when you look back" trick, which fired **zero times** in 240 s.
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
5. Crickets are a ring-modulated sine trill, not stridulation: 0% of energy
   below 3 kHz, spectral flatness 0.0000, and one fixed 6 s pattern forever.
6. No escalation: `aswang.gd` never reads `Game.charms`, so minute 10 plays
   identically to minute 1.
7. `scripts/game.gd` never sets `debug_log`, so the shipped game emits no AI
   log — the only observable aswang is the one in the test scene.

## Rules in force

Ponytail (`full`): reuse before rewrite, one line before fifty, no speculative
abstractions, deletion over addition. Procedural assets only — no imported
image, mesh, font or audio file anywhere in the project.
