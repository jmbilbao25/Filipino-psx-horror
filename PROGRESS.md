# Barangay Aswang — live progress

Updated as work lands. Newest state at the top of each table cell.

## Toolchain (done, verified)

| Thing | State |
|---|---|
| Godot 4.5.2 headless | installed `/projects/tools/godot` |
| Android export templates | installed `~/.local/share/godot/export_templates/4.5.2.stable` |
| Android SDK (build-tools 34/35, platform-tools) | installed `/projects/tools/android-sdk` |
| Release keystore | generated, kept out of the repo |
| **Signed APK export** | **verified end to end** — `Signer #1 DN: CN=Barangay Aswang` |
| Offscreen software rendering | verified — Xvfb + llvmpipe/lavapipe, PNG frames out |
| Reference footage | 21 Nun Massacre gameplay frames + 6 Convenience Store frames pulled and studied |

Gotcha worth recording: Godot's Android export aborts with an **empty** error
message when `rendering/textures/vram_compression/import_etc2_astc` is false.
`should_import_etc2_astc()` sets `valid = false` and appends no text. Cost an
hour; documented so nobody pays it twice.

## Pieces

| # | Piece | Builder | Critic verdict | State |
|---|---|---|---|---|
| 1 | Godot project + Android export | me | — | done |
| 2 | PSX shaders + post-processing | — | — | not started |
| 3 | Procedural 3D environment | — | — | not started |
| 4 | Enemy AI + horror mechanics | — | — | not started |
| 5 | Touch UI + controls | — | — | not started |
| 6 | Audio + atmosphere | — | — | not started |
| 7 | Integration | — | — | not started |

## Rules in force

- Ponytail (`full`): reuse before rewrite, one line before fifty, no
  speculative abstractions, deletion over addition.
- Every piece gets a builder and a **separate critic with fresh context**.
- The critic compares **rendered frames** against real reference frames, blind,
  and names the single biggest gap. Loop until ours is picked.
- Procedural assets only. No imported art of any kind.
