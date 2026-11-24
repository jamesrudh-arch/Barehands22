# LEVERAGE — Changelog

## 2026-11-24 — DEPTH WAVE 48: a living world, and a product that ships

Wave 47 made the game *feel* right. The audit that followed said the honest
thing: feel is not the whole product. Named gaps the user asked for by name —
trains, filling stations, rivers/water, wildlife, the studio logo, and a story
intro where the characters actually talk — were all either absent or vestigial.
This wave closes them, and fixes seven defects found on the way, four of which
were in shipping code paths nobody had ever exercised.

Harness: **314 → 445 checks, 0 fails across 5 consecutive runs**, 0 `SCRIPT
ERROR`, 4 engine `ERROR:` (all after the `DONE` line — shutdown RID leaks from
the moth swarms and creature meshes being torn down with the tree). 42
GDScript files, 17,490 lines. 1,545 of those lines are new this wave.

### 1. The living world — `scripts/world/wildlife.gd` (931 lines, new)

Before this the city had traffic and crowds and **not one creature**. `events.json`
even promised a dock cat that did not exist.

- **Birds** (cap 14): gulls over the harbour, crows and pigeons inland. States
  `perch | hop | circle | flee`, with two mirrored wing meshes driven per-state.
- **Rats** (cap 8), **stray cats and dogs** (cap 5), **fish** (cap 6) that break
  the surface on a timer, and **moth swarms** (6 sites) — pooled `GPUParticles3D`
  re-sited onto the nearest lamp positions, emitting only after dark.
- Budgeted with hysteresis: `LIVE_RADIUS` 58 m, `DESPAWN_RADIUS` 78 m, ticked at
  1.1 s. Nothing spawns forever; nothing pops at the edge of view.
- `Bus.crime_committed` startles birds and rats — gunfire empties a rooftop.
- Every creature mesh sets `set_normal`/`set_uv` on **every** vertex (the
  `ARRAY_TEX_UV` latch bug from wave 47 does not get to come back).
- **Harbour water rebuilt**: one static quad → three sheets (`HarbourWater`
  base, `HarbourChop` scrolling *against* it at 1.9× UV scale, `HarbourFoam`
  surging on a 0.55 rad/s sine) plus a `StaticBody3D`. `WorldGen._process` now
  scrolls them. Two sheets moving in opposite directions is what reads as chop.
- 14 new synthesized sounds: 3 bird chirps, gull, crow, wing flutter, rat
  squeak/scuttle, cat, dog, insect buzz (3.0 s loop), fish splash, water lap
  (4.0 s loop).

### 2. The Smoke Line — `scripts/world/smoke_line.gd` (363 lines, new)

Two missions (`m10_smoke_line`), a safehouse (`Smokeline Bolt-Hole`) and a POI
(`Smoke Line Overlook`) all named a railway that **did not exist**. Grepping
`data/*.json` for rail/train/locomotive/freight returned only "Yard" hits.

- **920 m of viaduct** along the existing east-west arterial at `z = -30`
  (`x = -560 … 360`), deck at 7.2 m, railhead 8.25 m: tapered piers with
  capitals and plinths every 24 m, segmented deck/ballast/girders with X
  cross-bracing, parapets, sleepers every 2 m, rails laid in 20 m lengths,
  gantry lamps every 60 m, and an **Overlook station** at `x = 300` — 52 m
  platform, canopy, and a stair down to the street, 90 m from the POI it was
  named after. Walkable: 46 m `StaticBody3D` segments on layer 1.
- **A moving freight consist**: diesel locomotive (body, cab, nose, roof-walk,
  radiator, horn stacks, exhaust, bogies, coupler, amber livery stripe, glass)
  pulling six mixed cars — boxcar, tank, flat, gondola, boxcar, flat — at
  17.5 m/s (63 km/h), wrapping on a ±220 m horizon margin so it is audible from
  four districts.
- Headlight (range 95 m, energy 3.2) burns **only after dark**; an always-lit
  marker and a red tail lamp do not.
- **Audio is a live 3D emitter** parented to the locomotive — `unit_size` 26,
  `max_distance` 230, `ATTENUATION_INVERSE_DISTANCE` — so *Godot* does the
  Doppler and the pass-by. The sample is written flat on purpose. Rumble swells
  with proximity, `rail_clack` fires every 20 m inside 120 m, and the horn rolls
  on a 16–34 s timer inside 170 m.
- **It is a hazard, not decoration**: standing on the deck (±2.2 m y, ±3.4 m z)
  takes 34 damage through `take_hit(..., "train", null)`, shakes the camera
  0.55, plays `slam`, and throws the player clear via `velocity`. Rate-limited so
  it cannot chain into an instant death. Standing on the street *under* the
  viaduct is perfectly safe — asserted both ways.
- 4 new synthesized sounds: `train_horn` (Bb3/D4 minor-third pair, two detuned
  doubles, bandpassed, 1.2 % pitch sag, 0.22 s breath burst, 0.75 s reverb so it
  comes off a viaduct), `train_rumble` (4.0 s loop: low-passed rolling noise at
  0.37 Hz + 260–900 Hz steel resonance + **8 evenly spaced joint clacks so the
  loop point is seamless**), `rail_clack`, `train_brake`.

### 3. Filling stations and a real fuel economy — `scripts/world/fuel_pump.gd` (251 lines, new)

The user named filling stations. There were none, and 11 vehicles had `hp`,
`_speed`, `_rpm` and `_gear` but **no tank**.

- **Six forecourts, one per district**, data-driven from `city.json`
  (`world.stations`). Each: 30 × 20 m pad, canopy with fascia band and three
  emissive soffit panels, four posts on plinths, pump islands with bodies,
  glass heads, hoses, nozzels and yellow bollards, painted bay lines, a kiosk
  with a glass front and door, and a **5.6 m price totem** lit from both sides —
  the thing you actually spot from down the road. 22 pumps total.
- Canopies **turn to face the arterial they front** (`_station_along_z`), so the
  same authored geometry reads correctly on an east-west and a north-south road.
- **Prices differ on purpose**: Slag Yard $1.75 and Dockside $1.85 (diesel,
  industrial) up to Crown Premium $3.05. Cheap fuel is in the rough districts.
  Where you fill is a small economic decision the city already understands.
- Price also moves with `street_rep`: respected (≥ +8) earns up to 15 % off;
  at or below −25 you pay a 25 % premium — which is exactly the incentive to
  steal instead.
- **Fuel model**: per-vehicle `tank_l` from `vehicles.json` (bike 14 L … bus
  260 L). Burn = idle + base × (0.35 + throttle × 1.35) × (1 + km/h ÷ 260), so
  load matters more than road speed — sitting in traffic at high revs is what
  empties a tank. Hard throttle costs >2× idling (asserted).
- Parked cars spawn at **0.42–1.0** of a tank. A stolen ride is sometimes a
  short ride; that is the entire point of a fuel economy.
- Below the 12 % reserve line the engine **starves audibly** — the note breaks
  up under load and coughs on a 2.4–5.5 s random timer — before it dies. Dry
  means zero torque: you are coasting, and the starter hunts for a rev it
  cannot hold.
- **You are billed by the litre as it flows**, not up front. Running out of cash
  mid-fill shuts the nozzle off (`broke`). You can fill from the driver's seat —
  nobody should have to climb out in the rain for a menu.
- **Driving off mid-fill is theft**: `note_deed("fuel_theft", district, false)`,
  +6 district heat, and the world's existing witness/snitch system notices.
- Fuel stations get their own colour on the minimap and the phone's big map, and
  they register in `WorldGen.pois`, so tap-to-route works.
- 4 new synthesized sounds: `fuel_pump` (3.0 s seamless loop — hose bed, 50 Hz
  pump hum, six evenly spaced gurgles so the seam falls *between* bubbles, and
  wobble periods that divide the loop into whole cycles so it never clicks),
  `fuel_cap` (thread ratchet + hollow clink), `nozzle_off` (auto-shutoff clunk),
  `engine_sputter` (starter whir, four uneven firing pulses that die).
- **HUD**: a real fuel gauge — bar with the reserve line ticked on it, litre
  count, amber under 30 %, pulsing red on the reserve, dead red when dry.

### 4. The opening now tells the story

`cs_intro` was **3 spoken lines over one push-in**: Eli narrated at the camera
twice, Ruth said one thing, nobody answered anybody. ~14 s.

It is now **61 steps, 19 spoken lines, 3 speakers, 22 camera moves, 97 s** —
Ruth (5+ lines), Eli, and Crowe's man Gunnar on the phone. Four beats: Ruth
comes to find him in the rain; the phone call delivers the number and the day;
Eli decides not to pay it; pull out to the title. Shot on **shot/reverse-shot**
grammar — Cam A sits on Ruth's far side looking past her at Eli, Cam B on Eli's
far side looking past him at Ruth, ~7 m apart so every cut genuinely reverses
the angle. Ruth is spawned as a body in the world, so the frame has two people
in it. The last line is the closest the camera ever gets to him.

The thesis now lands *in dialogue*: "Everyone in this city has leverage on
somebody, Mama. That is the whole economy." → "And when they find out you have
been reading their books?" → "Then I will have leverage too."

Asserted structurally, not by vibes: no speaker runs more than 2 lines
unbroken, the player character is ≤ 60 % of the lines, every speaker resolves to
a real voice bank on disk, every camera looks at something ≥ 0.5 m away
(`Camera3D.look_at` throws otherwise), and the skip still hands over to the
prologue mission.

### 5. Studio identity

`boot.gd` rewritten around a forged **3.90 s stereo `studio_sting`** (peak
0.880): 0–0.95 s breath (bandpassed air swell + 62→31 Hz sub-drop), a strike at
0.95 s (kick + F-minor pad + highpassed crack), then bells at 1.15/1.34/1.53 s
(F4/A4/C5) with an F5 shimmer resolving to F major-7th, through 1.15 s reverb.
The card is timed to it — `STRIKE` 0.95, `NAME_IN` 1.15, `TAG_IN` 1.78,
`FADE_OUT` 3.20, `HANDOFF` 4.25 — with a radial bloom, an inverted vignette, a
smoothstep rise that pushes 1.07 → 1.00 and overshoots, a flash scaled by f², a
hairline rule, and "D'YOUNGS GAMES / presents". Any input skips it. The dev
overlay is now F3-only instead of shipping on screen.

### 6. Seven defects found and fixed

- **Fuel pumps were silent.** `_build_flow()` created the `AudioStreamPlayer3D`
  and never called `add_child`, so it was outside the scene tree and Godot
  refused to play it ("Playback can only happen when a node is inside the scene
  tree" ×3). Every tank in the city would have filled in silence. Caught by
  step 93, not by reading the code.
- **The speedometer was never visible.** `_speed_lbl` used negative offsets
  (`offset_top = -200`) with `anchor_top` left at 0, so it sat 200 px *above*
  the top of the screen. Found while placing the fuel gauge. Both are now
  bottom-anchored, and step 93 asserts their rects are actually on screen.
- **There was no way to pause on a keyboard.** The `pause` input action existed
  in `project.godot` bound to physical keycode **4194304 = `KEY_SPECIAL`**,
  which no keyboard sends (`KEY_ESCAPE` is 4194305) — *and* nothing in 42
  scripts ever read the action. `Game._unhandled_input` now handles it, and the
  binding points at a real key. Pad START already worked, which is why nobody
  noticed.
- **The intro could not be skipped.** `Cutscene.skip()` existed from day one and
  was bound to **no input action at all**. Now `skip_cutscene` (Escape / Space /
  Enter / pad B), plus an on-screen "ESC — skip" hint while a cinematic runs —
  a 97 s opening the player cannot leave is a hostage situation.
- **Skipping would have crashed.** `skip()` set `_step_i = _steps.size()` while
  `_process` indexed `_steps[_step_i]` unguarded — out of bounds on the very
  first keypress. Bounds-guarded now, and asserted.
- **Shopkeepers thanked you in silence.** `shop_ui.gd` emitted
  `dialogue_line` with an **empty voice bank**, so `AudioDirector.speak` asked
  for `res://assets/audio/vox/_0.wav` — 8 missing-file warnings per run, now 0.
  Characters carry a `voice` field; it is used. Step 92 now asserts every
  character's bank exists on disk and that **no** call site anywhere emits
  dialogue with an empty voice.
- **The audio forge could not reproduce its own output.** `footstep()` seeded
  from `hash((surface, variant))` and `district_track()` from `hash(kind)` —
  Python salts `hash()` per process (`PYTHONHASHSEED`), so every run produced
  different footsteps and different music. Replaced with a stable `zlib.crc32`.
  Separately, 9 of this wave's new synths consumed the module-level
  `R = default_rng(4242)`, so *adding a sound silently re-rolled every sound
  after it* — 100 tracked audio files changed bytes. All 20 new synths now own
  a private seeded RNG. Verified: two consecutive runs are byte-identical for
  all 138 `.wav`. (The 16 `.ogg` still differ in 488 container bytes — the Ogg
  bitstream serial number at offset 14, a libsndfile property; **decoded PCM is
  identical**, so it is inaudible and not ours to fix.)

### 7. Harness honesty

- Steps 90–94 added: **314 → 445 checks**. Step 90 wildlife/water/studio, 91
  the Smoke Line, 92 ambient-bus and asset integrity, 93 the fuel economy, 94
  the opening cinematic and the input fixes.
- **Three real bugs step 90 caught** that a green-but-shallow harness had
  waved through: wildlife treated `world.water_z` as the harbour sheet's
  *centre* when `_build_water` puts the centre 130 m seaward (fish were
  spawning **on the docks**); `_update_moths()` trusted a `_night` flag only
  `_process` refreshes, so calling it directly silently did nothing; and birds
  spawned *only* on fire-escape rooftops, so any street without one had zero
  birds. Rules learned: a spawn system must not depend on one optional landmark
  type, and a tick method must not trust a flag another method owns.
- **Two flaky tests made deterministic.** The harness is a gauntlet — hostile
  peds from earlier steps keep swinging, so by step 87 the player was down to
  **3 HP** and `take_hit` no-ops on a dead player; damage assertions were a coin
  flip. Added `_revive_player()` for the steps that test *taking* damage. And
  step 83's intervention test did not control any of the four conditions
  `_intervene_tick` bails on (`in_vehicle`, `cutscene_active`, distance,
  cooldown), so adding world content — which shifts `randf()` everywhere —
  broke it intermittently. Both now pin their preconditions.
- Test-design rule reinforced: assertions that measure a randomized spawn must
  anchor to the spawned entity, or they pass and fail by luck.

## 2026-11-24 — DEPTH WAVE 47: felt, not seen (top-tier quality pass, part 2 — game feel)

The anti-flop wave. Research spine: Nijman's "Art of Screenshake"
proportionality ladder, Euphoria's "no two hits alike", the FPS-standard
directional damage read, and layered gunshot audio. Also fixes one of the
worst latent bugs in the repo.

- **BUG FOUND & FIXED — every enemy flinch was dead**: `anim.hit_t` was set
  on hit but only player.gd ever advanced it; npc.gd never ticked it, so
  `_hit_pose` always sampled at t=0 (k=sin(0)=0 — zero pose). Enemies ate
  punches with literally no body response. The reaction clock now lives in
  `AnimDriver.tick` (one source of truth for player + NPCs); player.gd's
  private advance removed (would double-speed).
- **Directional hit reactions**: `hit_t/hit_dir(±1)` replaced by
  `hit_vec` (shove in victim-local space) + `hit_power` (per attack kind,
  jab 0.22 → suplex 0.9) + `hit_seed` (per-hit jitter + asymmetric arm
  flail). Five reaction families: front/back stagger (from-behind hits
  windmill the arms and trip the legs), lateral whip with a stumble step
  (hooks/kicks), high snap (uppercut/kick_high — heels lift), low fold
  (ground pound — jackknife, knees buckle, root drops). Heavy hits
  (>0.65 power) always add a recovering stumble. Bullets flip their
  victim→shooter dir into the shove. No two hits look the same.
- **Juice ladder completed (Nijman proportionality)**: EVERY confirmed
  melee hit now gets a 25 ms micro-hitstop (lights felt paper-thin
  without one); heavies get the 70 ms stop + extra shake + a 1.8× blood
  burst; finishers keep their 120 ms + FOV punch. `Effects.burst` takes a
  juice-budget `scale` (amount, velocity, quad size).
- **Permanence**: kills now leave a blood decal where the body fell
  (0.55–0.9 m, random) — the street keeps the ledger visually too.
- **Guard break escalated**: the shatter now punches into a 0.22 s
  slow-mo (0.45 scale) + 0.35 shake + FOV kick — big events, big juice.
- **Directional damage read**: `Bus.player_damaged(dir, amount)` → HUD
  draws red arcs at the screen edge toward whoever hit you (up to 6
  stacked, arc grows outward as it fades, thickness scales with damage),
  and the camera FRAME gets shoved opposite the blow (damped spring
  punch). Gamepad rumble scales with damage taken.
- **Low-HP heartbeat**: under 30 % HP the screen edges throb red on a
  4.2 rad/s rhythm with a muted `land_thud` heartbeat — intensity scales
  as HP falls. Disabled in cutscenes.
- **Dynamic combat framing**: the orbit camera counts live hostiles
  within 14 m and pulls back (1 enemy +0.35 m, 2 +0.8, 3+ +1.5) so
  threats stay readable — the fight cam "breathes" like good action games.
- **Landing weight**: falls now track peak velocity; landings above 6 m/s
  shake the camera proportionally (up to 0.45), above 15 m/s add a 40 ms
  hitstop. Jumping off fire escapes feels like falling.
- **Neon-noir rain atmosphere**: new `RainSplash` particle crown (90
  splash jets in a 26 m box at the player's feet, rain only); puddles —
  fresh `decal_puddle` quads raycast onto ground near the player every
  1.4–3 s while raining (the texture shipped unused since wave 1);
  wet asphalt at night now throws the district's neon tint back as a
  faint emission (wet sheen); neon signs breathe on detuned sines and
  randomly drop out for 60–160 ms (buzzing-sign noir); rain ambience
  volume swells with wetness instead of a flat 0.35.
- **Layered gunshots**: every player shot and every NPC shot within 45 m
  gets an echo tail — the same sample replayed 180–340 ms later at ~20 %
  volume with tight pitch. The city throws the crack back.

### Engine hygiene: 16,141 errors per run → 3

The harness had been reporting **0 fails while the engine printed sixteen
thousand errors every single run**. Nothing asserted on the broken output,
so four real defects — two of them visual — lived undetected:

- **Decals never oriented to their surface.** `decal()` called `look_at()`
  *before* `add_child()`, and Godot refuses `look_at` on a node outside the
  tree — so the call silently did nothing and every blood/scorch/bullet
  decal kept its default floor pose. Worse, the code aligned the node's
  `+Z` to the surface normal while `PlaneMesh` faces `+Y`: a 90° error that
  would have made wall decals edge-on even if `look_at` had run. Now the
  decal is parented first and given a basis whose **Y axis is the surface
  normal** (with an explicit flip for ceilings), so blood on a wall lies on
  the wall.
- **Vehicle surfaces had no texture coordinates.** `_quad`/`_cap`/`_cap4`
  added bare vertices, latching the surface format *without* `TEX_UV`;
  every later `set_uv` was then rejected (16,128 errors), so car bodies,
  trim, glass and bumpers sampled UV (0,0) — flat albedo with zero texture
  detail. All three helpers now emit proper UVs through a single `_uv()`
  gate, and `_cap` planar-projects across the ring.
- **Dialogue choice buttons were unstyled.** `StyleBoxTexture` has
  `texture_margin_*`, not `margin_*`; the bad assignment threw mid-function
  and aborted `_build_choice_buttons`, so the hover/pressed styleboxes and
  the 17 px font override were never applied. Every branching conversation
  in the game rendered with default buttons.
- **A whole class of latent null-crashes.** Godot 4 has no `bool(null)`
  constructor, and `Node.get("missing")` returns `null` — so
  `bool(n.get("hostile"))` crashed whenever the property was absent. One
  instance was live: the "stood up for a civilian" witness loop died before
  recording the deed, so **protecting locals never raised street rep**.
  All ten unguarded casts across `npc`, `city_life`, `player`, `camera_rig`,
  `hud`, `shop_ui` and `cinematics` are hardened, and `str(n.get(...))` is
  guarded too — unguarded it yields the literal text `"<null>"`, which
  `npc.gd` would have read as a real faction tag and started friendly fire.
  A **project-wide RegEx scan** now walks every script under `res://scripts`
  and fails the harness if the pattern returns.
- Also removed a redundant `set_normal` in `_sb` (all callers end with
  `generate_normals()`) and dead no-op `root_off -= 0.0` lines.

Harness: **266 checks, 0 fails, 0 script errors, 3 engine errors** (all
benign shutdown RID notices) — **three consecutive headless runs** on the
rebuilt Godot 4.7.2 binary. 45 checks new since wave 46: reaction families
driven live through `take_hit` from five directions, decal permanence
counted in the scene tree, damage-arc signal + HUD + camera punch live,
neon flicker modulating emission at night and restoring by day, puddle tick
re-arming, plus the ten engine-hygiene regression guards above (wall and
ceiling decal basis, per-surface UV format on a spawned vehicle, stylebox
property names, and the project-wide cast scan).


## 2026-11-24 — DEPTH WAVE 46: the world that remembers (top-tier quality pass, part 1)

Grounded in real design research — RDR2's NPC memory/reputation, GTA V's
civilian agency, Sleeping Dogs' overheard conversations and street events,
Sifu's guard-break meter, Max Payne 3's bullet hitstop — this wave closes
six audited gaps where systems existed but were dead or missing.

- **Street ledger + street rep (RDR2 memory spine)**: `WorldState.remember()`
  finally has callers. A new `street_deeds` ledger (serialized, v5-compatible)
  records what the block SAW you do: standing up to predators (`stood_up`,
  +2), showing respect (+2), bullying locals (`bully`, -2), preying on
  civilians (`preyed_on`, -2), backing muggers, ignoring muggings, breaking
  up brawls. Derived `street_rep()` (-30..+30) drives everything below; a
  HUD chip shows the block's verdict. Deeds are throttled (20 s) so rep is
  earned, not farmed.
- **Witnesses remember**: the hardcoded 50% snitch chance is now
  `WorldState.snitch_chance()` — 22% when the block has your back (>=15),
  72% when you're known as a predator (<=-15). Killing a predator within
  14 m of civilians makes witnesses react with `respect` barks and logs a
  deed; saving a mugging victim gets a spoken thank-you. Killing civilians
  logs `preyed_on`.
- **Civilian agency (GTA V)**: talking to a local is now a DECISION panel,
  not a random bark — ask what's going on, show respect (a remembered deed,
  4-min per-NPC cooldown), antagonize them (remembered deed; they may flee),
  or walk away. Per-ped bark overrides from peds.json (`young`, `drunk`)
  are finally wired — students sound like students, drunks like drunks.
- **Overheard conversations (Sleeping Dogs)**: pairs of nearby locals now
  hold 12-20 s gossip conversations (6 new authored gossip lines — dock
  crates, Crowe's nephew, the Halcyon tower lights), facing each other,
  talking/listening. Linger within 3.5 m and the conversation turns to
  YOU: with bad street rep they call you out (`watch_it`), otherwise they
  acknowledge you (`interrupted`/`greet`).
- **Street-event intervention (GTA V/Sleeping Dogs)**: muggings and street
  fights now offer a choice when you walk into them — mugging: step in
  (mugger turns on you; killing them logs the deed and the victim thanks
  you), walk past (remembered as `ignored_mugging`), or BACK THE MUGGER
  (they stand down, you pay a cut, and the block remembers you as a
  predator). Brawls: break it up (+rep, actors calm and nod), watch, or
  jump in and swing (everyone within 14 m turns hostile, -rep).
- **Enemy posture / guard break (Sifu)**: blocked hits now chip a posture
  meter (heavies chip 2.2x) instead of dealing chip damage. Breach 100 and
  the guard SHATTERS — clang, sparks, 0.10 s hitstop, stagger 30, and a
  2.2 s window where the target can't block and eats +45% damage. Posture
  decays 12/s out of combat. Trained enemies (guard_strength >= 0.5) now
  raise guard in rhythm during melee — no more punching bags. The locked
  target's posture renders as an amber bar under the district name; it
  flashes red on break.
- **Bullet weight (Max Payne 3)**: player bullet hits now trigger hitstop
  (45 ms, 90 ms on kills) — guns no longer punch paper. Impact materials
  vary by district instead of hardcoded concrete: docks/slagworks ring
  metal, Neon Mile + Crown Heights shatter glass, the Furnace/Kiln Row
  splinter wood (dust burst instead of sparks), with per-hit pitch jitter.
- **Shopkeepers thank you**: buying from a keeper while your street rep is
  non-negative earns a spoken `thank` bark — the till is a relationship.

Harness: 221 checks, 0 fails (29 new — street ledger serialization and
signals, snitch scaling, guard-break wiring, civilian agency panel live
test, mugging intervention live test, impact materials, HUD surfaces).


## 2026-11-23 — DEPTH WAVE 45: the block fights back + full-repo audit

Four systems, then a line-by-line audit of everything (see docs/AUDIT.md).

- **Fire investigation**: a burning wreck in the street is a crime scene
  with a countdown. Every 25 s the CCPD rolls two non-hostile
  "Investigators" up to work the ashes — GAWK-state officers who loiter
  40–70 s and wander off. Arson now leaves badges standing in it.
- **Occupied traffic**: every traffic car carries a visible driver
  silhouette (shared low-poly capsule), and taxis fly a lit roof sign.
  The streets read as full of people, not rolling empty boxes. Blocked
  AI drivers honk (40 %).
- **side_epilogue**: after `game_complete`, Mama Ruth offers one last
  favor — a 110-second medicine run to the shelter, ending in a real
  choice (hang it up for the block, or take one more ride for the
  score). Gated by the new `requires_flag` mission field.
- **Full audit — 9 real defects found and fixed** (evidence in
  docs/AUDIT.md): the finale cutscene referenced a music file that
  doesn't exist; 4 sting tracks and 5 SFX shipped but never played (now
  wired: mission stings, reload brass, police radio chatter at 2+
  stars, shop doors); FOUR dead settings — `shake`, `sensitivity`,
  `invert_y`, `touch_scale` were persisted by the menus and consumed by
  nothing (all now live, including HUD rebuild on touch-scale change);
  two orphan `npc.react()` events (`siren` → civilians rubberneck
  passing cruisers, `crime` → witnessed carjackings); two dialogue
  speakers rendering as raw IDs (Solomon Pike + the noodle vendor now
  have character entries); ~10 tracked stats never shown (new STREET
  LEDGER dossier section); **and the big one: all 18 `talk` stages in
  the campaign stalled forever** — closing the dialogue never advanced
  the mission (fixed + regression-checked); PIT maneuvers never fired
  because `_pit_tick` read `velocity` off a VehicleBody3D (it's
  `linear_velocity`) — every chase shove in the game was dead code.
- Harness **191 checks, 0 fails, 0 script errors** (×3 consecutive
  runs): +9 live pursuit-stack/fire-investigation checks, +14 static
  audit-regression guards.

## 2026-11-23 — DEPTH WAVE 29: fire you can hear and watch die

- **Wrecks burn for 45 seconds**: flickering firelight (sine + noise),
  `burning` group membership, then the flames go out and the light is
  freed — explosions leave a scene, not a permanent lamp.
- **fire_barrel street events actually burn** now: a 2-minute barrel
  fire with its own light.
- **Proximity fire ambience**: the previously-registered "fire" ambient
  channel finally plays — `fire_crackle` loops, louder the closer you
  stand to anything burning (fades out past 22 m).
- Harness **117 checks, 0 fails, 0 script errors**.

## 2026-11-23 — DEPTH WAVE 44: everybody has a price

- **Paid lay-low**: hitting a safehouse with 3+ stars used to be a
  dead end — "too hot to sleep easy." Now, if you're carrying 250 cr,
  the block can be persuaded to forget a face and a car: two stars
  quietly disappear, cash changes hands, no questions. Broke and hot?
  The notification now tells you exactly what quiet costs.
- Another money sink for late-game wealth, and an escape valve that
  rewards planning (keep a roll on you) over save-scumming.
- Live behavioral test: hot + rich → wanted 4→2, money 500→250;
  hot + broke → stars stay. Game hour and wallet restored after.
- Harness **168 checks, 0 fails, 0 script errors**.

## 2026-11-23 — DEPTH WAVE 43: limp to the garage

- **Limp mode**: below 40 hp a car gives you only 55% of its engine
  and trails smoke puffs every half-second — the street can see
  you're hurt, and so can the cops. Dex's repair bay (wave 30) is the
  cure; the live test proves power drops and returns.
- **Real bug fixed**: `repair_full()` and `puncture_tires()` assigned
  `wheel_roll_friction` — a property that doesn't exist on Godot 4.7's
  `VehicleWheel3D`, throwing a script error on EVERY garage repair and
  EVERY spike strip since wave 30/14. Replaced with `brake` drag
  (0.02 rolling / 0.9 on shredded rubber) + reset per-wheel engine
  force. Caught the moment a behavioral test actually called the
  function.
- **Test flakiness killed**: run-over and lockpick live tests now drive
  physics deterministically (direct `_physics_process` /
  `_hotwire_tick` calls, thug respawn guard, re-arm on interrupt) —
  three consecutive runs at a stable check count.
- Harness **165 checks, 0 fails, 0 script errors**.

## 2026-11-23 — DEPTH WAVE 42: prove the burn, kill the dupe

- **Real bug found + fixed**: the `fire_barrel` world event carried TWO
  full burn implementations (a wave-29 heredoc applied twice) — every
  barrel spawned two burning nodes, one on a 90 s `create_timer` and
  one on the 120 s `_fires` tick. The orphaned twin is gone; one
  barrel, one fire, managed by `_fire_tick`. Regression guard in the
  harness counts `add_to_group("burning")` in the event block.
- **Live burn-expiry test**: wreck a sedan, fast-forward `_burn_t`,
  assert the hulk leaves the `burning` group and its fire light is
  freed when the fuel runs out.
- **Live fire-ambience test**: plant a burning node 4 m from the
  player, run `_fire_tick`, assert the "fire" ambient channel opens
  (vol > 0.2); move it 60 m away, assert the channel goes silent.
- Harness **163 checks, 0 fails, 0 script errors**.

## 2026-11-23 — DEPTH WAVE 41: work for the new verbs

- **Two new side jobs** that spend the systems recent waves built:
  - **Torch Job** (Gunnar, repeatable, 700 cr): the union dispute
    needs punctuation — wreck 2 vehicles while the block watches them
    burn.
  - **Clean Wheels** (Dex, repeatable, 1000 cr): lift a car, give it
    fresh paint at the PAINT bay (wave 33), run it to Yard 4 under
    two stars in 120 s. A dealership for previously loved cars.
- **Relative stat goals** (`statd:` prefix): repeatable objectives now
  count wrecks/thefts/resprays *since the stage started*, so last
  Tuesday's chaos can't pre-complete today's job. New stats: `wrecks`
  (every explosion), `resprays` (every paint job).
- Behavioral test: statd ignores pre-existing stats, counts new ones.
- Harness **157 checks, 0 fails, 0 script errors**.

## 2026-11-23 — DEPTH WAVE 40: you can see them panic

- **Commandeered cars show their driver**: when a fleeing civilian
  dives into a traffic car (wave 34), a seated silhouette appears
  behind the wheel — a capsule in hurried dark colors, riding the
  panic. When the driver calms down (panic timer ends) or the car
  goes up (explode cleanup), the silhouette leaves the frame. Bikes
  stay bike-shaped: no cabin, no passenger.
- **Live hijack-silhouette test**: harness converts a sedan to
  traffic, calls `civ_panic()`, asserts the driver mesh exists and the
  panic timer runs, expires the timer through `traffic_tick`, and
  asserts the driver is gone.
- Harness **150 checks, 0 fails, 0 script errors**.

## 2026-11-23 — DEPTH WAVE 39: prove the fire and the flinch

- **Live wreck-burn test**: harness totals a sedan with 9999 damage and
  asserts the wreck flag, the 45 s burn timer, the "burning" group
  membership, and the spawned fire light. Wave 29's pyrotechnics,
  verified end to end.
- **Live scatter test**: spawns a routine civilian 8 m off a car's
  nose, launches the car at 40 km/h, drives one scatter tick, and
  asserts the civilian flips ROUTINE → FLEE. Wave 32's street panic,
  verified end to end.
- Harness **147 checks, 0 fails, 0 script errors**.

## 2026-11-23 — DEPTH WAVE 38: prove the run-over

- **Live run-over behavioral test**: harness seats the player in a
  sedan, plants a thug 3 m off the nose, launches the car at 50 km/h,
  and asserts the thug is struck AND the player is charged (wanted
  ≥ 3) for it. Wave 32's physics, proven end to end.
- **Real bug caught and fixed**: when a civilian died, `_on_died`
  called `react()` on every nearby humanoid *without a method guard* —
  the player has no `react()`, so any player-caused pedestrian death
  (run-overs, wave 32) threw a script error. Guards added on both the
  ally-down and gunshots notification loops, plus validity checks.
- Harness **141 checks, 0 fails, 0 script errors**.

## 2026-11-23 — DEPTH WAVE 37: one pick per job

- **Lockpicks are consumables now**: a completed 2.2 s pick spends one
  Lockpick Set from the bag. Ran out? The window-smash is always
  there — loud, noticed, free. Shops sell picks for 60 cr, so quiet
  car theft becomes a resource decision, not a toggle.
- Warning notification when your last pick is used.
- **Live lockpick behavioral test**: harness parks a locked sedan next
  to the player, starts the pick, deterministically ticks it to
  completion, and asserts the car opens AND the pick count drops.
  Uncovered two real freeze conditions along the way — a dead player
  and an active mission cutscene both (correctly) halt interaction
  processing; the test now revives and skips cinematics.
- Harness **137 checks, 0 fails, 0 script errors**.

## 2026-11-23 — DEPTH WAVE 36: prove the drive-by

- **Live-fire behavioral test**: the harness now physically performs a
  drive-by — spawns a sedan, seats the player with an SMG, parks a
  thug 3 m off the fender, fires from the car's muzzle one physics
  frame later, and asserts the bullet lands (hp drops), ammo burns,
  and gunfire from the vehicle raises wanted level ≥ 2.
- Caught a real subtlety along the way: a CharacterBody3D added this
  frame is NOT solid to hitscan rays yet — the test now waits one
  physics step between spawn and shot, which mirrors how the game
  actually plays.
- Harness **134 checks, 0 fails, 0 script errors**.

## 2026-11-23 — DEPTH WAVE 35: a good witness describes the suspect

- **Witness call-ins now point at YOU**: when a civilian reports a
  crime they saw, the tip carries the suspect's position instead of
  the witness's own — police dispatch spawns near the player, not
  near the screaming.
- **Throttled snitching**: each witness can call it in at most once
  per 20 s (`_snitch_cd`), so one street crime doesn't cascade into
  a dozen sirens.
- Harness **129 checks, 0 fails, 0 script errors**.

## 2026-11-23 — DEPTH WAVE 34: the block has wheels

- **Fleeing civilians commandeer traffic**: a panicked pedestrian
  within 9 m of a slow traffic car dives in, the driver peels out —
  lane speed ×1.9, nervous horn blasts, red-light manners gone — for
  7–11 s, then settles back into traffic. Only civilians flee into
  cars; gunmen keep fighting.
- Vehicle `civ_panic()` + `_panic_t` timer; NPC `_try_hop_in_car()`
  throttled to 1 Hz, shrink-out exit so the car visibly carries them
  off.
- Harness **128 checks, 0 fails, 0 script errors**.

## 2026-11-23 — DEPTH WAVE 33: a fresh coat of consequences

- **Resprays at Dex's Garage**: a PAINT tab (motors only) sells 8
  colors — Cinder Red, Midnight, Brass, Teal Wave, Bone, Plum, Steel,
  Slag Orange — at 150 cr a pop. Works on the car you arrive in or the
  nearest non-wreck within 10 m; wrecks don't get paint jobs.
- `Vehicle.respray()` retints car body mesh surface 0 and bike
  material overrides live, so your ride leaves the bay a different
  car (at least to the neighbors).
- Harness **126 checks, 0 fails, 0 script errors**.

## 2026-11-23 — DEPTH WAVE 32: two tonnes of consequences

- **Run-overs are real**: any vehicle above ~14 km/h that touches a
  pedestrian deals speed-scaled damage (×3.4 per m/s — lethal above
  ~25 km/h), with blood, impact audio and knockback direction. Driven
  by the player, it's a crime: assault (sev 3) or homicide (sev 5) —
  witnesses, heat, ripples and all. Traffic vehicles cause tragedies
  the block reacts to.
- **Pedestrians scatter**: speeding metal within 13 m in its path
  makes civilians dive off the road (`scramble` reaction; a quarter
  of them scream doing it).
- Harness **124 checks, 0 fails, 0 script errors**.

## 2026-11-23 — DEPTH WAVE 31: the grudge grows teeth

- **Faction escalation**: past **−70 rep**, collections stop being
  collectors. A hit squad arrives — one extra body, armed (Syndicate
  Hitmen with pistols / Halcyon Cleaners with SMGs and armor), and the
  warning changes tone: *"They aren't collecting anymore. They're
  finishing."*
- The −35 collector tier is unchanged; the ladder now reads: cold
  shoulder (−25 shops) → grudge (−60 refused service) → collection
  (−35 ambushes) → **the hit (−70)**.
- Harness **122 checks, 0 fails, 0 script errors**.

## 2026-11-23 — DEPTH WAVE 29: fire you can hear, and watch die

- **Wrecks burn for 45 s**: flickering firelight (sine + noise jitter),
  `burning` group membership, then the flames go out and the light frees
  — an explosion leaves a scene, not a permanent lamp.
- **fire_barrel street events actually burn**: a 90-second barrel fire
  with its own flickering light.
- **Proximity fire ambience**: the registered-but-unused "fire" ambient
  channel finally plays — `fire_crackle` loops, louder the closer you
  stand to anything burning, silent past 22 m.
- **Dex's Garage REPAIR bay**: hull damage billed at 3 cr/point, new
  rubber for spike-shredded tires +200 cr; drives the car you arrive in
  (or the nearest beat-up one at the door). Wrecks stay wrecks.
- Harness extended (burn timers, ambient wiring, barrel fires, repair).

## 2026-11-23 — DEPTH WAVE 28: gunplay feeds mastery

- Landing shots grows the **WEAPON mastery** track (+1.2 XP per hit,
  +3.0 on the kill) — previously only melee hits trained styles, so
  the gun branch's rank-4 payoff (steadier hands, faster reloads) was
  unreachable by actually using guns.
- Harness **115 checks, 0 fails, 0 script errors**.

## 2026-11-23 — DEPTH WAVE 27: the papers watch YOUR career

- **Fame milestones**: six one-shot headlines fire as your career stats
  cross thresholds — 5 thefts, 25 KOs, 8 jobs done, 10k in pocket,
  3 ghost runs, 3 race wins. Each persists as a flag (never re-fires),
  pushed through the same NEWS pipeline as district heat.
- The city now narrates you, not just the neighborhoods you bleed in.
- Harness **114 checks, 0 fails, 0 script errors** (incl. live fame
  firing test).

## 2026-11-23 — DEPTH WAVE 26: the map learns to talk

- **District heat bleeds onto the phone map**: angry neighborhoods glow
  red (alpha scales with heat01) — plan routes around the heat you made.
- **Owned businesses appear as teal `$` markers** at their district's
  center — your portfolio, cartographed.
- Harness **112 checks, 0 fails, 0 script errors**.

## 2026-11-23 — DEPTH WAVE 25: the coach learns the new verbs

- Three new contextual tutorial steps: **lockpick** (fires the first
  time you touch a locked car — pick quiet vs smash loud), **driveby**
  (fires on your first shot fired from a car — bikes exempt, speed
  wobble explained), **garage** (fires on your first theft — KEEP THIS
  RIDE + SUMMON explained).
- All routed through the existing `Bus.tutorial_hint` relay; one-shot
  like every other coaching step.
- Harness **111 checks, 0 fails, 0 script errors**.

## 2026-11-23 — DEPTH WAVE 24: jobs for the new verbs

Three new side jobs that only exist because of waves 17–23:
- **"Repo Man"** (Dex, The Furnace): steal any car (`stat:thefts>=1`),
  then run it to Yard 4 in 110 s under scripted 2-star heat.
  800 cr / crew +3 / 240 XP.
- **"Silent Partner"** (Ruth, Kiln Row): buy into the Noodle Stall
  (phone → BIZ, new `prop:` objective expression) and Ruth backs you.
  1200 cr / family +5 / 260 XP.
- **"Heat Magnet"** (Nia, Neon Mile, repeatable): a 3-star, 100-second
  broadcast run from the Lounge to the Plaza for Nia's betting feed.
  950 cr / 280 XP.
- Harness **109 checks, 0 fails, 0 script errors**.

## 2026-11-23 — DEPTH WAVE 23: ownership has teeth

Every business now bends a system, not just the payday:
- **Noodle Stall**: consumables heal +25% — Aunt Adaeze feeds you.
- **Cab Medallion**: taxi fares half-rate (min 5 cr).
- **Laundromat**: wanted heat decays ×1.6 faster — it washes more than
  clothes.
- **Radio Ad Slot**: 30% of Static 88 chatter is now YOUR ad (flavor +
  billboard pride).
- **Berth 7 Sublease**: ammo costs −25% at every shop — crates move off
  the books.
- **Noir Lounge Back Room**: sevens pay ×2.4 and the high-roll
  threshold drops 9→8 — the house is your house.
- New `WorldState.owns_property(id)` helper; harness **105 checks,
  0 fails, 0 script errors**.

## 2026-11-23 — DEPTH WAVE 22: the portfolio

- **Six buyable businesses** (`data/properties.json`): Aunt Adaeze's
  Noodle Stall (1500 cr → 90/day) up to the Noir Lounge Back Room
  (6000 cr → 340/day) — laundromat, cab medallion, dock sublease,
  radio ad slot. Each pays its cut once per in-game day (both clock
  paths: real time and safehouse sleep/taxi skips).
- **BIZ phone app**: browse, read the blurbs, buy in; owned businesses
  show their daily payout. Autosaves on purchase.
- `owned_properties` serialized — **SAVE_VERSION 5**.
- Harness **101 checks, 0 fails, 0 script errors** (incl. live payout
  test: own the noodle stall, roll 24 h, cash lands).

## 2026-11-23 — DEPTH WAVE 21: taxis

- **TAXI phone app**: hail a cab to any discovered POI more than 60 m
  away. Fares run 12 cr + 9 cr per 100 m; the ride costs in-game time
  (~0.08–0.5 h by distance) so the city clock stays honest.
- No cab stops for a wanted rider — lose the stars first. Dropped at
  the curb beside the destination.

## 2026-11-23 — DEPTH WAVE 20: a drawn gun clears the street

- **Civilians panic at brandished weapons**: walk around on foot with a
  gun out in the open and people within 22 m (with line of sight)
  scream, scatter, and often call it in — no more strolling through the
  Mile with a rifle like it's a handbag. Crouching doesn't hide an
  out-and-out gun; holstered weapons and drive-bys from cars are
  unaffected (the car IS the disguise).
- Harness **96 checks, 0 fails, 0 script errors**.

## 2026-11-23 — DEPTH WAVE 19: drive-bys

- **Lean out and work the trigger**: guns fire from cars (not bikes —
  bikes need both hands) with muzzle flash from the window, camera
  kick, and the usual crime pipeline (suppressors still keep it quiet).
- Speed makes the gun honest: 2° wobble parked up to 11° at 90 km/h —
  drive-bys are for suppression and statements, not sniping.
- Reload (R) and weapon cycling (Page Up/Down) work behind the wheel.
- Harness **95 checks, 0 fails, 0 script errors**.

## 2026-11-23 — DEPTH WAVE 18: lockpicks earn their keep

- **Locked cars**: 60% of parked civilian cars (35% of bikes) now spawn
  locked. With a Lockpick Set in the BAG, F starts a 2.2 s quiet pick
  (walk away and it aborts); without one, you smash the window —
  instant, loud (`glass_break` at the car), and the theft crime jumps a
  severity level. The lockpick is finally a real tool, not inventory
  decoration.
- Harness **94 checks, 0 fails, 0 script errors**.

## 2026-11-23 — DEPTH WAVE 17: theft is a crime

- **Hot-wiring is now a felony**: entering any vehicle you don't own
  fires a `theft` crime — sev 2 for parked cars, sev 3 for carjacking
  live traffic (with a CARJACKED! sting). District heat, faction
  ripples, witnesses and dispatch all answer through the existing
  crime pipeline; `stats.thefts` counts your grand-total career.
- **Owned rides are clean**: mission vehicles, shop purchases and
  garage summons carry `is_player_owned` — the job's car isn't a
  felony, and neither is your own wheels.
- Harness **93 checks, 0 fails, 0 script errors**.

## 2026-11-23 — CRITICAL FIX: on-foot vehicle entry was dead code

- The `vehicle_enter` (F) handler had been stranded AFTER a `return`
  inside `_find_body()` since the wave-9 body-hiding reorder — on foot,
  pressing F next to any car did nothing. Entry now lives at the top of
  `_handle_interact`, before body/interact priority.
- Harness regression guard: source-position check that the on-foot
  `vehicle_enter` branch is reachable, PLUS a live spawn-and-enter drive
  test. Harness **92 checks, 0 fails, 0 script errors**.

## 2026-11-23 — DEPTH WAVE 16: hand cannons & loose rounds

- **Two new guns**: the Judge .357 (58 dmg, 6 shots, brutal recoil,
  1100 cr at Mags) and the Wasp Auto-9 (full-auto 1000 rpm machine
  pistol, 10 dmg, 780 cr — pawn shop too). New .357 Speedloader ammo.
- **Ammo items are finally usable**: loose boxes from the BAG feed the
  gun they were bought for (loot drops included); carrying rounds for a
  gun you don't own tells you so.
- NPC loot tables know the new guns (magnum drops .357, the Wasp drops
  9mm).
- Harness **91 checks, 0 fails, 0 script errors**.

## 2026-11-23 — DEPTH WAVE 15: sleep it off

- **Safehouse rest** now skips EIGHT HOURS (new `WorldState.advance_hours`,
  day rollover handled) — night jobs end at sunrise, schedules and crowd
  densities follow the clock honestly.
- Overnight cooldown: district heat drops to 35% across the city; wanted
  1–2 clears entirely; 3+ stars survive the night ("too hot to sleep
  easy").
- Harness **88 checks, 0 fails, 0 script errors**.

## 2026-11-23 — DEPTH WAVE 14: the garage

- **GARAGE phone app**: any ride you're sitting in can be filed as yours
  ("KEEP THIS RIDE") — the insurance trick every career thief needs.
- Owned rides (kept, or bought at a garage) can be **summoned to the
  nearest curb** anywhere in Cinder City for a 40 cr delivery fee —
  parked on a traffic lane point, ready to go.
- `owned_vehicles` was already serialized; saves (v4) carry the garage
  across sessions.
- Harness **86 checks, 0 fails, 0 script errors**.

## 2026-11-23 — DEPTH WAVE 13: the city hears everything

- **Sound propagation**: gunfire/explosions/homicides ripple outward —
  every civilian within earshot panics even with zero line of sight
  (explosions 45 m, shots 34 m). Combatants and hostiles don't spook at
  their own war.
- Weather muffles the ripple: rain cuts the radius ×0.7, fog ×0.85 —
  storm nights are the professional's friend (and the suppressor still
  prevents the crime signal entirely).
- Harness **85 checks, 0 fails, 0 script errors**.

## 2026-11-23 — DEPTH WAVE 12: weather plays the game

- **Fog** cuts NPC sightlines to 15 m (rain 21 m) and slows suspicion
  build past 8 m — stealth jobs get a weather window.
- **Police perception** caps at 32 m in fog / 44 m in rain (was always
  55 m) — losing a tail in the soup is now actually possible.
- **Wet asphalt**: road wetness eats up to 30% of tire grip and 18% of
  steering response — the wetness sim (already drifting toward weather
  targets) now reaches the driving feel. Rain chases slide.
- Harness still **84 checks, 0 fails, 0 script errors**.

## 2026-11-23 — DEPTH WAVE 11: scripted chases

- **Mission pursuits**: `drive_timed`/`race` stages accept a `pursuit`
  star level — the job scripts the heat (cruisers, drive-bys, roadblocks,
  PIT, spike strips all come from the existing pursuit stack). Borrowed
  stars are given back at stage cleanup unless the player earned worse.
- Quay Sprint now runs at 2 stars, Furnace Loop at 3, the High Road
  courier run at 2.
- **NEW SIDE JOB — "Bait Car"** (Dex, Ashfall Docks, repeatable): drive a
  bait car Berth 7 → Warehouse 12 under THREE stars in 120 s, then shake
  the heat to wanted ≤1. 1100 cr, crew +5, 300 XP.
- Harness extended to **84 checks** (cinematics wiring, drive-bys, turf
  wars, loot drops, siren-yielding traffic, scripted pursuits, side_bait).

## 2026-11-23 — DEPTH WAVE 10: fight-feel, living city, hotter pursuits

- **Cinematics autoload** (`scripts/core/cinematics.gd`): micro time-scale
  arbitration — hit-stop freeze frames, kill-cam slow-mo, FOV punches
  through the camera rig. Cooperates with FOCUS bullet-time (whoever wants
  the world slower wins; both restore cleanly; never fires during FOCUS).
- Heavy connects (haymaker, axe kick, suplex, ground pound, executioner,
  vertical swing, high kick) freeze-frame ~70 ms; ground finishers 120 ms
  + FOV punch; environmental slams 100 ms + punch.
- **Kill-cam**: dropping the last standing enemy within 30 m triggers a
  0.55 s slow-mo beat (0.3×). Vehicle explosions punch FOV and, within
  22 m of the player, dip into a 0.35 s slow-mo blast beat.
- **Living traffic**: rain slows cars to 72%, fog to 85%; patrol sirens
  within 34 m pull traffic toward the curb; a player car blocking the
  lane earns a horn (new `police_car` group when sirens run).
- **Turf wars**: NPCs pick targets — rival-faction enemies fight each
  other; new `turf_war` night event spawns Syndicate-vs-Halcyon clashes
  the player can watch, join, or loot.
- **Loot drops**: dead hostiles drop cash scaled by Difficulty.threat,
  ammo for their gun (65%), their melee weapon (30%), bandages (22%) —
  spawned as pickups so looting is a deliberate, risky beat.
- **Cruiser drive-bys**: at 2+ stars patrol cars fire through the glass —
  tracers, hit roll vs. vehicle panels (4–9 dmg) or the player on foot;
  accuracy scales with Difficulty and speed penalizes their aim.
- **Radio personality**: 15 new DJ chatter lines across the three
  stations; between-song banter fires every 75–150 s while driving with a
  static blip, leaking story texture (Berth 7, Halcyon, the docks body).
- Harness still **76 checks, 0 fails, 0 script errors**.


## 2026-11-23 — DEPTH WAVE 9: consequences, rooftops, wrecks

Second block of the deepening mandate (docs/LEVERAGE_VISION.md):

- **District heat**: crimes leave lingering per-district notoriety
  (0–100, cools ~0.35/s). Heat ×0.6 faster guard suspicion; milestones
  (35/70) file news stories on the phone feed (`PhoneUI.push_news`);
  bodies found spike heat +22. Persisted in saves.
- **Faction consequences**: violence on crew turf (docks/slagworks/neon)
  sours the Syndicate and quietly amuses Halcyon, and vice versa in the
  Furnace/Heights. Rep below −35 on a faction's turf sends **collector
  ambushes** (scale with Difficulty, survivor cools the grudge +4).
  Below −25 shopkeepers mark you up 25% and turn surly; below −60 they
  refuse service outright.
- **Stealth missions upgraded**: mission stealth stages now read the
  guards' real suspicion meters (cones/disguises/crouch apply) instead of
  a proximity cone; finishing unseen pays a **GHOST RUN** XP bonus
  (tracked in stats.ghost_runs).
- **Body hiding**: interact near a corpse to stash it (shrink-away anim,
  out of the corpse group — never discovered). New side jobs use it:
  **Ghost Work** (silent dock infiltration, hide the evidence) and
  **High Road** (Nia's courier run + level gate) — mission checker learns
  a `level` expression.
- **Fire escapes + climbing**: ~40% of taller buildings get zig-zag
  ladders/landings and register climb points; jump near one to climb
  hand-over-hand to the roof (or back down). Rooftops = escape routes
  above the police LOS math.
- **Vehicle wrecks explode**: hp 0 → blast (AOE damage + stagger to
  humanoids within 5.5 m, driver thrown out hurt), scorch shell, lingering
  fire light, `explosion` crime (severity 3). Wrecked flag prevents
  double-detonation.
- **Neon-noir identity**: each district tints the night air from a new
  `night_tint` palette (Mile = magenta haze, Docks = cold blue, Slag =
  ember) — fog light, sun rim and glow lean into it after dark; glow
  lifts at night. FOCUS gets a cold-blue screen vignette + HUD bar.
- **Coach**: 6 new contextual hints (parry-counter, mastery, focus,
  cover, stealth takedown, climb/vault) fired via `Bus.tutorial_hint`
  relay — tutorial stays a scene node, not an autoload.
- **Phone dossier**: new STATS app — level/XP, all five mastery ranks with
  unlocked moves, faction rep moods (allied → HUNTING YOU), district heat
  percentages, career numbers (KOs, ghost runs, bodies hidden).
- tools/build_engine.sh: canonical engine rebuild recipe checked in
  (pkgconf-lite needs SYSTEM_LIBDIR/SYSTEM_INCLUDEDIR/PKG_DEFAULT_PATH).
- Save version bumped to 4 (progression, district heat, attachments).
- Harness 64 → **76 checks, 0 fails, 0 script errors** (heat accrual +
  faction rep drop on docks crime, climb points reach roofs, wreck/
  explosion code, ghost runs, grudge ambushes, shop markup, dossier).


## 2026-11-23 — DEPTH WAVE 8: escalation + progression + stealth/gunplay depth

Per the user mandate (difficulty must escalate; nothing capped by earlier
numbers; see docs/LEVERAGE_VISION.md):

- **Difficulty director** (`scripts/core/difficulty.gd`, autoload): threat =
  story×0.75 + level×0.35 − death relief, clamped 0..1.6. Scales enemy
  HP/damage/accuracy/counts, police cap 4+12t, dispatch, peds/traffic,
  fight-club purse, and late-game thug loadout rolls (guns/bats/armor).
- **Progression spine** (`scripts/core/progression.gd`, autoload): XP/levels
  (raise HP/stamina/damage), per-style mastery ranks 1–5 grown by *using*
  the style; ranks unlock real moves — haymaker, high kick, axe kick,
  suplex, ground pound, sway strike, drunken flurry, vertical swing,
  executioner — plus passives (extended combos, throw dmg, counter window,
  iron jaw, fast reloads). Missions carry `rewards.xp`. Saved/loaded.
- **Combat cinematic layer**: parry now opens a 0.9 s counter window (×1.6
  dmg, "COUNTER!" sting); ground finishers on knocked targets (×2.2,
  "FINISHER!"); environmental takedowns (heavy attack slams a staggered
  enemy into geometry behind them, 55% max-HP + forced knockdown); stealth
  takedowns (crouch-dodge behind an unaware NPC = instant kill, +focus).
- **Gunplay weight**: FOCUS bullet-time (Q / RT-focus / touch FOCUS btn,
  meter drains 22/s, world at 0.35× time, spread ×0.55); per-weapon recoil
  climb + lateral patterns in weapons.json applied as camera kick; soft
  cover (crouch behind geometry: incoming damage ×0.45, no stagger,
  blindfire lane).
- **Stealth/awareness**: guard vision cones feed a suspicion meter
  (calm→45 suspicious bark→100 alarm), LOS checks, rain/distance/crouch
  modifiers, search-last-known-position sweeps; disguises via outfit
  `disguise` faction tags (×0.45 detection unless blatant); corpse group +
  body discovery (civilians find bodies → flee + crime report at body).
- **Living city**: NPC day parts (commute_am/work/commute_pm/nightlife/
  night) override base routines — commuters cross districts, workers hover,
  nightlife clusters chat, sensible folks shuffle home at 3am; crowd
  density breathes with hour/district/weather (rush ×1.5, neon/docks
  nightlife ×1.3, dead of night ×0.3, rain ×0.6).
- **Pursuit escalation**: 3★+ PIT maneuvers (spin-out impulse + damage +
  shake), 4★ spike strips across lanes ahead (tyres shred → limp mode via
  `vehicle.puncture_tires()`), strips clear when heat dies.
- **Vehicle variety**: bus, ambulance, pickup added; traffic is now
  district-flavored (docks=trucks, Heights=sports, Mile=taxis/bikes).
- **Weapon attachments** (Ghost Recon-lite): suppressor (quiet + no gunfire
  crime report), extended mag, foregrip (recoil ×0.65 incl. pattern),
  scope ×4, laser sight (hip-fire), hot load (+18% dmg, +30% recoil);
  fitted per weapon at the gunsmith MODS bench; persists in saves.
- **Movement**: vaulting (jump at knee–chest-high ledges: 3-ray probe,
  timed arc over, stamina cost) instead of face-planting into crates.
- New forged SFX: focus_on/off, takedown, shot_suppressed, tire_burst,
  crash_metal. New barks: suspicious/alert/body.
- Harness: 45 → **64 checks, 0 fails, 0 script errors** (progression,
  threat math, recoil patterns, focus/cover hooks, suspicion brain,
  attachments def() merge, schedules, PIT/spikes, vault/env-takedown).


## 2026-11-23 — CINEMATIC OVERHAUL WAVE 1 (visual rebuild)

Ordered overhaul: replace toy-like presentation with grounded, cinematic
crime-action quality. Wave 1 executed (see docs/VISUAL_QUALITY_REPORT.md):

- humanoid v2: lofted anatomy, cloth layers, sculpted head, real hands/shoes
- vehicle v2: lofted bodies, greenhouse glass, trim, interiors, rimmed wheels
- city v2: branched trees, cornices/parapets, entrances, balconies, new props
- cinematic grade: filmic tonemap + contrast/saturation + controlled glow
- harness +2 budget gates (checks 50) locking the new detail level
- device-blank-screen root cause fixed same day: 0x0 menu scene roots +
  stretch aspect keep_height for portrait hosts

Retained per order: control foundation, phone UI design, all runtime systems.

## 2026-11-23 — XOGOT device pass #1: portrait UI fix (K-13)

- First real-device boot succeeded (XOGOT on iPhone): engine, GDScript and scene flow run.
- Defect found: XOGOT's iOS shell runs **portrait**, ignoring `sensor_landscape`; fixed-offset UI collapsed (one-char-per-line labels, off-screen headings, gray clear color).
- Fix: `scripts/ui/ui_fit.gd` responsive helpers (clamp center/inset offsets to live viewport, refit on `size_changed`); applied across boot/title/notice/menu/dialogue/shop/phone/cutscene; HUD rebuilds touch cluster + refits centers on resize; `default_clear_color` = night black in project.godot.
- Harness +2 checks (UiFit clamp math).

## 2026-11-23 — Defect burn-down (K-01/02/03/04/06/10/11/12 closed)

- **K-01** traffic AI reads light state: `vehicle.gd _check_ahead` queries `CityLife.traffic_green_at` 10 m ahead; red = blocker.
- **K-02** escort VIP now spawns the existing `nurse` archetype (was a `ped_nurse` key typo → fallback to archetype[0]).
- **K-03** mid-mission save/load: `stage_i`, runtime target pos/time serialized; `apply_save` fast-forwards past completed stages and skips cutscene replay.
- **K-04** outfit equip rebuilds the player humanoid instantly (`player.rebuild_appearance()`, vitals/style preserved); shop no longer says "respawn to see it".
- **K-06** forge facade numpy uint8 overflow fixed (explicit int casts + clip); all 8 facades + grass re-baked, re-imported with 0 errors.
- **K-10** on-foot radio tuning now toasts an explanation instead of silently keeping district score.
- **K-11** touch **JMP** button added (56 px, left cluster, hidden while driving).
- **K-12** news placeholder substitution centralized in `CityLife.format_news()`; ticker + push_news both use it.
- Harness extended 21 → **24 checks** (traffic-light query, JMP button, mission stage serialization); all pass, engine import 0 errors.
- Open after this pass: K-05/K-07 (accepted cosmetic), K-08/K-09 (device-only verification passes).


Session-by-session record (branch `arena/9f25f474-barehands22`, base
`db5ead1` of `main`). Status vocabulary in `docs/TRACEABILITY.md`.

## Session 1 — Environment + foundation (`db5ead1`, `bf5de06`)
- Sandbox audit; Godot 4.7.2-stable identified as latest release
  (api.github.com); release CDN blocked → source tarball via codeload;
  pkgconf built static; background scons editor build started (headless
  flags, `-j2`, ~45 min wall).
- XOGOT docs cloned (xibbon/XogotDocs): GDScript-only on iPhone, touch-UI
  guidance, 4.5-era API surface → constraint adopted.
- Asset forge v1 (`tools/forge/`): 77 world textures, 29 UI textures,
  24 faces, 105 SFX, 15 music OGG, 60 vox blips. DejaVu fonts + license.
- `project.godot`: Mobile renderer, iPhone landscape/stretch settings,
  authoritative input map (X punch / Y heavy / A kick / B dodge+interact).

## Session 2 — Core code + all game data (data commits, `c96d512`)
- Core autoloads written + gdparse-clean: Bus (73 signals), Db (15-file
  JSON registry), WorldState (clock/weather/economy/wanted/factions/
  relationships/memory/flags/inventory, serialize v3), SaveSystem (3
  slots), AudioDirector (5 buses, pools, crossfade music, vox queue),
  Game (state machine, scene flow, settings, autosave).
- All 15 data JSONs authored: characters(16), combat_styles(5),
  weapons(9), armor(4), items(10), outfits(6), vehicles(8), peds(25),
  city (6 districts, landmarks, POIs, lanes inputs), missions(20),
  dialogue(47→49 trees), events(12), shops(6), radio(4), news+barks.
  news.json trailing-brace defect found by validator and fixed.
- Player layer: humanoid.gd (22-bone procedural skinned builder; leg-rest
  offset defect fixed), anim_driver.gd (phase-locked procedural animation,
  15 modes), camera_rig.gd (orbit/lock-on/FOV/cinematic), effects.gd
  (pooled particles/tracers/decals/shake).
- Combat layer: combat_controller.gd (12 timelines, reach+arc validation,
  block/parry, stagger/knockdown/death), weapons_controller.gd (gun state
  machine, hitscan, reload timeline, reserves).
- player.gd full controller (movement states, exact button mapping,
  lock-on, styles, vehicles, interact, footsteps, district tracking,
  save/apply_save).
- world_gen.gd (city builder: merged district chunks, roads/marks,
  buildings from facade palettes, 12 landmark types, furniture, lamps,
  traffic lights, lane loops, POI doors) + poi_door.gd; facade texture
  set extended (+8 albedos, +8 emission, grass ×3).

## Session 3 — Systems integration + first engine-verified gameplay (`9c8ccee`, `976a7ca`, `b9f87d2`)
- **Engine build finished**; `--headless --import` clean (333 assets).
- Data completion: +3 mission POIs (poi_ruths_alley, poi_plaza,
  poi_refinery_gate), +2 choice dialogue trees (dlg_m04/m05_choice).
- Interior system: interior_manager.gd (19 procedural rooms, furniture
  sets, collision, lighting, return-position exit) + exit_door.gd;
  poi_door routes via Bus world event.
- Vehicles: vehicle.gd (procedural car/bike bodies on VehicleBody3D,
  engine audio, lights, police bar/siren, damage, crash detect, lane
  traffic AI, player_drive API).
- NPCs: npc.gd (peds w/ routines, named characters w/ chats, enemies
  (melee + gunmen), flee/gawk/witness reactions, simulation LOD,
  save_state).
- City simulation: city_life.gd (crowds by district density, traffic on
  109 lane loops, parked cars, police dispatch/pursuit/roadblocks/arrest,
  12 staged world events, 28-lamp night pool, traffic-light cycle,
  district ambience + music routing, later: vehicle radio + news pushes).
- Missions: mission_manager.gd (16 stage types, choice effects, rewards,
  3-act chain w/ flag+act gating, bust/death recovery w/ fines/respawns,
  save/apply) + pickup.gd.
- UI: dialogue_ui.gd (portraits/typewriter/voiced lines/choices),
  cutscene.gd (letterbox/cards/cam verbs + 4 scripted cutscenes),
  shop_ui.gd (buy/sell/dealership/clinic), phone_ui.gd (9 apps incl.
  live-drawn city map), hud.gd (vitals/minimap/objective/toasts/lock
  marker + full iPhone touch control layer + pause menu), tutorial.gd.
- Scenes: boot/title/notice/menu/city (.tscn + scripts); day-night sun,
  weather rain/fog/thunder, event routing, news ticker, ground-verified
  player spawn.
- **Engine-verified fixes** (all found by real runtime, not gdparse):
  Bus signals called as functions → `.emit`; INFERENCE_ON_VARIANT sweep
  (40+ annotations); StyleBoxTexture `texture_margin_*`;
  DirectionalLight3D `SHADOW_PARALLEL_4_SPLITS`; Rect2 has no
  `distance_to*` → custom `_rect_dist`; Skeleton3D naming; VehicleWheel3D
  `use_as_steering/use_as_traction`; no body `brake_force` → per-wheel
  `_set_brake`; AudioStreamWAV `loop_mode`; no
  `total_applied_impulse` → velocity-delta crash detect;
  ParticleProcessMaterial has no `emission_texture` → billboard quad draw
  pass; `current_scene` must be set on manual scene adds;
  **CRITICAL: ground-plate triangle winding inverted → single-sided
  trimesh collision let everything fall through the world** — fixed and
  regression-covered.
- Tests: `tests/harness.gd` SceneTree harness — **21/21 checks, 0 script
  errors** (spawn, skeleton, combat controllers, movement, melee, enemy
  damage/death, vehicle spawn/enter/drive 34.7 km/h/exit, prologue start,
  goto→talk stage advance, dialogue open, save+load roundtrip, wanted,
  peds 11+/traffic 7+/parked 14/lane loops 109, interior enter/exit, shop
  open + gun purchase, gunfire hitscan). Flow probes: boot→title clean
  40 s; menu→new_game→city→m01 stage go_ruths; player on_floor=true at
  spawn.
- Docs suite written: MASTER_DESIGN, TECHNICAL_ARCHITECTURE,
  ART_DIRECTION, WORLD_DESIGN, CHARACTERS_AND_STORY, CONTROLS,
  ASSET_REGISTER, LICENSES, TRACEABILITY, DECISION_LOG, CHANGELOG,
  TEST_REPORTS, KNOWN_DEFECTS, VERIFICATION_GUIDE, FINAL_REPORT;
  DEVELOPMENT_STATE kept current.
- Branch pushed to origin (first push — earlier sessions were local-only).
