# Reference dossier

Derived by stepping through **real footage**, not from descriptions:

- Nun Massacre (Puppet Combo) — 7 gameplay GIFs from the itch.io page, frames
  extracted at start/middle/end. Local copies: `/projects/work/ref/nm_*.png`
- The Convenience Store (Chilla's Art) — 6 official Steam screenshots.
  Local copies: `/projects/work/ref/cs_*.jpg`

Reference frames are **not committed** (third-party art). They live in
`/projects/work/ref/` for side-by-side judging only.

---

## What the Nun Massacre frames actually show

Measured off the frames, not remembered:

1. **Blacks are crushed to true black.** Large regions are `#000000`. There is
   no ambient floor lifting the shadows. If you can see the whole room, it is
   wrong.
2. **Strong single-hue colour cast.** The chapel frame is olive/amber
   (R>G>>B). The corridor frame is yellow-green. Never neutral grey.
3. **Visible dither noise inside the dark areas.** Not smooth gradients —
   an ordered/blue-noise speckle that survives in the near-blacks. This is the
   single most recognisable trait.
4. **Posterised colour.** Few distinct values per channel; banding is
   deliberate and visible on walls.
5. **Light pools clip to white.** The candle and the lantern blow out to
   near-`#FFFFFF` with a hard edge, no soft filmic rolloff.
6. **CRT framing.** Rounded-corner dark border insetting the image, plus a
   heavy vignette. Corners are fully black.
7. **Scanlines + horizontal tape noise bands** over everything.
8. **Chromatic fringing** at high-contrast edges, strongest near frame edges.
9. **Internal resolution ~320x240**, upscaled with no filtering: chunky,
   aliased, stair-stepped edges. No anti-aliasing anywhere.
10. **Textures warp** as the camera moves (affine / non-perspective-correct
    texture mapping) and **vertices jitter** (integer vertex snapping).
11. Menus/item screens: flat saturated background, chunky monospace pixel
    font, hard white text.

## What the Convenience Store frames add

1. **Bloom on every light source** — fluorescent strips and specular hits
   glow well past their geometry.
2. **Floating dust motes** in the air catching the light.
3. **VHS grain + tape noise** over the whole frame.
4. Interiors are **over-exposed** — bright to the point of clipping — which
   makes the dark exterior feel darker by contrast.

## Horror feel, not just looks

- Long stretches of **nothing happening**. Dread is built by walking in the
  dark, not by a monster on screen.
- The threat is **mostly offscreen**. In the footage the nun appears in a
  doorway or over a wall — partially occluded, briefly, then gone.
- **Audio leads the visual.** You hear it before you see it.
- The player is **slow, and the light is weak**. No combat. Only hiding and
  running.

---

## Our target: a barangay at night

Filipino folk horror, `aswang` (shapeshifting night creature). Folklore that
must be mechanically real, not decoration:

- **`tik-tik`** — the bird call of the aswang's familiar. Folklore inverts the
  distance cue: **the call gets QUIETER as the aswang gets CLOSER.** This is
  the game's core tension instrument.
- **Repellents**: salt (`asin`), garlic (`bawang`), stingray tail
  (`buntot pagi`). These are the three charms the player collects.
- Setting props: nipa huts (`bahay kubo`), corrugated-iron fences, banana and
  coconut trees, a `sari-sari` store, a chapel (`kapilya`), a barangay
  basketball court, one buzzing sodium streetlight.

### Non-negotiable aesthetic targets

| Target | Value |
|---|---|
| Internal render resolution | 320x180 (16:9 sibling of 320x240), nearest-neighbour upscale |
| Ambient light | ~0, blacks must reach `#000000` |
| Colour cast | warm amber/olive at rest, shifting toward red under tension |
| Colour depth | posterised, ~5 bits per channel or fewer |
| Dither | ordered 4x4 Bayer, applied before quantisation, visible in darks |
| Vertex snapping | on, in view space |
| Texture mapping | affine (perspective-incorrect), visibly warping |
| Anti-aliasing | none, anywhere |
| Shadows | flashlight and streetlight only; everything else unlit black |
| Post chain | dither -> posterise -> scanlines -> chromatic aberration -> grain -> vignette -> CRT border |
| Assets | 100% procedural. No imported image, mesh, or audio file. |

### Anti-goals

- Neutral grey lighting, "readable" darkness, soft filmic tonemapping.
- Smooth gradients, anti-aliased edges, high internal resolution.
- Constant monster presence, or a monster that is always fully visible.
- Anything that looks like a modern mobile game: rounded UI cards, drop
  shadows, gradients, emoji, bright flat colours.
