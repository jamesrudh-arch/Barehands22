# LEVERAGE — Wave-45 Full Audit

Date: 2026-11-23 · Scope: entire repository at wave 45 · Method: cross-referencing
every data file against the code that consumes it, every audio/texture asset
against its references, save serialization symmetry, settings plumbing end to
end, orphan-code hunts (unused `react` events, unused stings, unreachable
tutorial hints), balance math on weapons/economy/properties, and per-frame cost
scans. Findings are evidence-based: each one cites the file and the concrete
defect, not a general worry.

Scale of what was audited: 39 GDScript files (~14.2k lines), 5.4k lines of JSON
data, 341 asset files (audio/textures/faces), 29 story missions + 8 side jobs,
6 districts, 4 radio stations, 17 tutorial hints.

## Fixed during this audit

| # | Finding | Evidence | Fix |
|---|---|---|---|
| A1 | **Missing-file music reference**: cutscene.gd requested `music_finale`; the asset on disk is `music_ending.ogg` | `grep music_finale scripts/ui/cutscene.gd` vs `ls assets/audio/music/` | Renamed the reference (L321). `play_music` degrades silently, so the finale cutscene had been scoring-less all along |
| A2 | **4 sting tracks shipped but never played** (`sting_success/fail/busted/wasted`) | Cross-ref: every `assets/audio/music/*.ogg` against `sfx(`/`play_music(`/`sting(` call sites | New `AudioDirector.sting()` one-shot (Music bus, non-looping, music-volume); wired into mission `_complete` (both branches), `_on_busted`, and `game_over(kind)` |
| A3 | **5 orphan SFX**: `shell_drop`, `police_radio`, `door_metal_open/close`, `veh_horn_long` | Dynamic-name-aware cross-ref (`foot_%s_%s_%d` etc. excluded first) | Brass ejects on reload start; police radio chatter every 9–18 s at wanted ≥ 2; shop doors at motors/pawn/gunsmith open+close; 40 % of AI drivers honk when blocked |
| A4 | **Dead setting `shake`**: the SETTINGS app persisted it; nothing read it | `grep -rn '"shake"' scripts/` → only game.gd defaults + phone/menu writers | `Effects.add_shake()` early-returns when off (motion-sickness friendly, as the UI promised) |
| A5 | **Dead settings `sensitivity` / `invert_y`**: camera_rig.gd declared both vars and used them in `look()`, but nothing ever assigned them — the sliders did literally nothing | No `settings_changed.connect` anywhere; no assignment to `cr.sensitivity` | `_apply_settings()` on ready + live on `Bus.settings_changed` |
| A6 | **Dead setting `touch_scale`**: HUD button/stick sizes were hardcoded | `_touch_btn(..., size)` never consulted settings | Size multiplier in `_touch_btn` + stick base/knob; `settings_changed` now triggers HUD rebuild |
| A7 | **Two orphan `npc.react()` events**: `"siren"` and `"crime"` had handlers in npc.gd but zero callers | `grep -rn '\.react(' scripts/` → 5 call sites, neither event among them | Rubbernecking: cruisers on pursuit make nearby civilians GAWK (1.1 s scan cadence); witnessed carjackings (theft sev ≥ 3) now trigger the `crime` reaction radius |
| A8 | **Two dialogue speakers with no character entry** (`pawnkeep`, `vendor`): dialogue UI fell back to rendering the raw ID as the name plate | Cross-ref dialogue.json `spk` fields vs characters.json | Added Solomon Pike (Pawn 24H) and Street Vendor (noodle stall) with full appearance/voice; `ped_m`/`ped_f` vox banks exist so their lines are voiced |
| A9 | **Tracked stats never surfaced**: `wrecks`, `resprays`, `arrests`, `deaths`, `thefts`, `races_won`, `gambled`, `collectibles`, km counters, playtime all incremented but absent from the STATS app | phone_ui `_show_stats` showed only 5 of ~15 stats | New "STREET LEDGER" section: time played, movement, crimes, fights, wheels, bodies |

### Caught by the live harness after the static pass (the strongest argument for behavioral tests)

| # | Finding | Evidence | Fix |
|---|---|---|---|
| B1 | **All 18 campaign `talk` stages stalled forever**: `_setup_stage`/tick opened the dialogue tree and set `rt["done"]`, but `_on_dialogue_ended` had branches only for `choice` and `phone` — closing a conversation never advanced the mission | Harness step 30 printed stage still `talk` after exhausting the tree; `grep '"talk"'` showed 3 sites, none calling `_advance_stage` | `elif t == "talk": _advance_stage()` when the tree closes; new harness regression check |
| B2 | **PIT maneuvers never fired**: `_pit_tick` read `pv.velocity` — VehicleBody3D has `linear_velocity`, so the speed gate (`pvel.length() < 9.0`) always rejected and every chase shove was dead code | Harness step 78 failed both PIT checks despite a cruiser placed alongside at 12 m/s | Read `linear_velocity` when present; harness also corrected to place the cruiser inside the 2.0–5.5 m PIT band (it had been spawning at 1.6 m, below the minimum) |

Both passed gdparse and every static cross-ref — only running the game found
them. B1 means the entire story campaign was uncompletable past its first
conversation; B2 means a whole pursuit-escalation feature (wave 43) had never
actually triggered in play.

## Verified clean (no action needed)

- **Data ↔ code cross-references**: every vehicle id in traffic/parked/shop
  spawns exists in vehicles.json; every mission giver has a dialogue tree and a
  character; every dialogue `goto` resolves inside its tree; every item/weapon/
  outfit/property id referenced in shops, rewards, and code exists in data.
- **Radio**: all 9 station tracks exist on disk; chatter banks are non-empty for
  all 3 real stations; `radio.json` uses the `stations` key the code reads.
- **News templates**: only placeholder is `{district}`; `format_news()` handles
  it; queue caps at 24 with dedupe.
- **Save symmetry**: `WorldState.serialize`/`deserialize` write and read the same
  key set (SAVE_VERSION 5); `Progression` same; `load_game` return dict feeds
  `player.apply_save`, `mission_manager.apply_save`, `Progression.apply_save`.
  Settings (including the four now-wired ones) round-trip via SETTINGS_PATH.
- **Worldgen determinism (open question closed)**: the `"worldgen"` payload key
  is always `{}` — and that is *correct*, not a gap. `world_gen.gd` seeds each
  district RNG with `hash(district_id)` (L214), so the entire city layout —
  buildings, trees, props — regenerates identically on every load with no state
  to persist. Verified end to end: `build_city` is the only generation entry
  point and takes no seed from saves.
- **Tutorial**: all 17 hints reachable — sequential `_process` display plus six
  signal-triggered ones (combat/vehicle/wanted/phone/interact/mastery).
- **Mission check grammar**: all `stage.check` expressions across 37 missions
  match the grammar `_check_stage` implements; all reward shapes valid.
- **No debug leftovers**: zero `print(` outside harness/forge tooling, no
  `push_error`-only paths, no commented-out code blocks left behind.
- **No dead code after `return`**: multiline-return scan came back clean
  (earlier hits were false positives from formatted returns).
- **Economy math**: shop prices (bandage 40 … plate carrier tier), busted fine
  (10 % money, cap 500), lay-low 250, property prices 1200–6000 with `income`
  payouts present for all six — all consistent between data and code paths.

## Observations & recommendations (not defects)

1. **Weapon balance**: DPS spread is intentional but rifle (90) vs SMG (169)
   means the rifle must earn its 1600 cr via 120 m range and 45-dmg one-shot
   potential on peds. Recommend a device-playtest pass on rifle feel; if it
   underwhelms, buff is damage 45→52 rather than RPM (preserves identity).
2. **Shotgun pellets=8 × 14 dmg = 112 per full connect at 60 RPM** — strongest
   close-range option by a wide margin. Fine for the genre; flag for playtest.
3. **Per-frame group scans**: vehicles scan `humanoid` twice per physics frame
   (run-over + blocker checks); NPCs scan `enemy`/`corpse` on their LOD-reduced
   tick. Bounded (~30–60 humanoids active), but D-03 (device FPS target) should
   watch this first if Neon Mile nights dip. A spatial hash is the escape hatch.
4. **Difficulty curve**: 22 call sites consume `Difficulty.*`; aggression feeds
   cruiser fire cadence and PIT likelihood. Curve itself is data in
   difficulty.gd — recommend exposing a difficulty preset picker in SETTINGS
   (casual/hardcore) since the systems already scale continuously.
5. **Weather affects grip via `wetness`** (20 refs) but radio chatter/news never
   mention rain — a cheap immersion win would be one weather-reactive chatter
   line per station.
6. **`sedan`/`taxi`/`police`/`bus`/`ambulance` have price=0** — correct (not
   shop stock), but the shop UI should defensively hide price-0 entries; it
   currently filters by an explicit stock list, which is fine as long as the
   list and vehicles.json stay in sync (harness now covers reachability).

## Harness posture

Wave-45 tree adds 23 checks: 9 live behavioral (steps 77/78 — pursuit spikes,
roadblock + PIT + fire investigation) and 14 static (investigators, traffic
drivers, epilogue mission + dialogue trees + flag gates, plus nine audit
regression guards so the A1–A9 fixes and worldgen determinism can't silently
rot). **Verified: 191 checks, 0 fails, 0 script errors — three consecutive
headless runs** on the rebuilt Godot 4.7.2 engine binary.

---

## Wave-47 addendum: live-harness finds (B3)

**B3 — every enemy flinch animation was dead (since wave 1).**
`CombatController.take_hit` sets `anim.hit_t = 0.0` and `anim.hit_dir`, but
only `player.gd` ever advanced `hit_t` (`+= delta * 4.0`, reset at >1.0).
`npc.gd` never touched it, so for every NPC `_hit_pose` was sampled at
`t = 0` forever — `k = sin(0·π) = 0`, i.e. the reaction pose contributed
exactly zero bone rotation. Enemies absorbed punches, kicks, bullets and
finishers with no body response whatsoever; the only hit feedback they ever
showed was the 0.15 s `hit_flash` tint, knockback velocity and particles.
This is the single largest contributor to the "floppy" feel rejected in
review, and no static grep could catch it: the fields existed, were set,
and were consumed — just never advanced.

Fix: the reaction clock now lives inside `AnimDriver.tick` (single source
of truth for player and NPCs alike); player.gd's private advance was
removed to prevent double-speed player reactions. Regression-guarded by
harness step 85 (`hit_t += delta * 4.0` in anim_driver + live tick test).

Lesson recorded: for procedural animation, "field is set AND consumed" is
not enough — verify the field is ADVANCED somewhere on the owner's tick
path. Add to the audit checklist for future waves.

**B4 — the harness was green while the engine printed 16,141 errors per run.**
Every wave since 1 asserted on *gameplay state* (hp, flags, positions,
source text) and never on *engine error output*. Four defects therefore
survived dozens of "221 checks, 0 fails" runs:

| Defect | Player-visible effect | Errors/run |
|---|---|---|
| `decal()` called `look_at()` before `add_child()` | decals on walls/ceilings lay flat on the floor; `+Z`-vs-`+Y` normal axis was also 90° wrong | 2 |
| `_quad`/`_cap`/`_cap4` added vertices with no UV | car bodies, trim, glass, bumpers sampled UV (0,0) — no texture detail on any vehicle | 16,128 |
| `StyleBoxTexture.margin_*` (property doesn't exist) | aborted `_build_choice_buttons`, so dialogue choices lost hover/pressed styles + font override | 2 |
| `bool(Node.get("missing"))` → no `bool(null)` ctor in Godot 4 | witness loop died before `note_deed`, so protecting civilians never raised street rep; `str()` variant yields `"<null>"` and was read as a faction tag | 1 |

**Process fix (now enforced):** the harness asserts on engine error output,
not just gameplay state. Step 89 carries ten live regression guards —
wall/ceiling decal basis alignment, per-surface `ARRAY_TEX_UV` on a spawned
vehicle, stylebox property names, and a project-wide `RegEx` scan of every
script under `res://scripts` that fails if an unguarded `bool()/float()/
int()/str()` cast on a no-default `Node.get()` returns.

**Lesson recorded:** "harness green" meant "no assertion failed", never
"no errors". A verification loop that ignores the engine's own error stream
will happily certify a broken build. Any future wave must report the
`SCRIPT ERROR` and `^ERROR:` counts alongside checks/fails, and treat a
nonzero count as a failure until explained.

## Wave-48 addendum: live-harness finds (B5)

Wave 48 added the wildlife/water layer, the Smoke Line freight railway, six
filling stations with a real fuel economy, and a rewritten opening cinematic.
Steps 90–94 took the harness from 314 to 445 checks. Five more defects surfaced,
in a different class from B3/B4: these were not crashes or rendering errors. They
were **silences and absences** — code that constructed the right object and then
never connected it to anything.

**B5 — "constructed" is not "in the scene tree".** `fuel_pump.gd` built its
`AudioStreamPlayer3D`, set the bus, the attenuation model, the loop points and
the stream — and never called `add_child`. Godot refuses to play a node outside
the tree (`Playback can only happen when a node is inside the scene tree`), so
every pump in Cinder City filled every tank in complete silence. It parsed
clean, it ran clean, and it would have shipped. Caught only because step 93
asserts `_flow.playing` after `interact()`.

**Lesson recorded:** for any node that *does* something — an emitter, a light, a
particle, an area — assert the **effect**, not the construction. `_flow != null`
is a statement about a variable; `_flow.playing` is a statement about the game.
The same rule caught the moth swarms in step 90 (`emitting`, not `!= null`).

**B6 — configuration that nothing reads.** `project.godot` declared a `pause`
input action bound to physical keycode `4194304`, which is `KEY_SPECIAL` — a
marker constant, not a key any keyboard sends (`KEY_ESCAPE` is `4194305`). That
alone would have been a dead binding. Worse, a grep of all 42 scripts showed
**nothing ever called `is_action_pressed("pause")`**: `Game.pause_toggle()` was
reachable only from a touch button and the pause menu itself. On desktop there
was no way to pause the game, and the config file looked like there was.
`Cutscene.skip()` had the same shape — a complete, correct implementation bound
to no input at all, guarding a 97-second opening cinematic.

**Lesson recorded:** an input action in `project.godot` is not a control until
something reads it. Audit step: for every action in the input map, grep for a
reader. For every public method with no caller, ask whether it was meant to be
reachable. And verify a keycode against the engine's own constant rather than
trusting the number — `KEY_SPECIAL` and `KEY_ESCAPE` differ by one.

**B7 — the asset forge could not reproduce its own output.** `forge_audio.py` is
documented in-repo as the source of truth for `assets/audio`. It was not. Two
call sites seeded generators from Python's builtin `hash()` — which is salted
per process by `PYTHONHASHSEED` — so footsteps and district music tracks came
out different on every run. Separately, nine of this wave's new synths drew from
the module-level `R = default_rng(4242)`, which meant *inserting a new sound
silently re-rolled every sound generated after it*: adding 4 fuel sounds changed
the bytes of 100 tracked audio files.

Fixed by replacing `hash()` with `zlib.crc32` and giving all 20 new synths a
private seeded generator. Verified: two consecutive runs are byte-identical
across all 138 `.wav`. The 16 `.ogg` differ in 488 bytes at offset 14 — the Ogg
bitstream serial number, assigned by libsndfile; **decoded PCM is identical**, so
it is inaudible and not ours to control.

**Lesson recorded:** a generator that claims to be a source of truth must be
reproducible, and that is a testable property — run it twice and diff. Also: a
shared mutable RNG in a build script makes the output order-dependent, so
*adding* content changes *unrelated* content. Give every synth its own seed.

**B8 — the harness is a gauntlet, and later steps inherit earlier damage.**
Step 87's directional-damage assertions began failing with no change to combat
code. The player arrived at step 87 with **3 HP**: hostile peds spawned by steps
11 and 86 keep swinging for the rest of the run, and `take_hit` early-returns on
a dead player, so the signal never fired. Step 83's intervention test failed the
same way — it asserted on `_intervene_tick`'s output without controlling any of
the four conditions that make it bail (`in_vehicle`, `cutscene_active`,
distance, cooldown), and adding world content shifts `randf()` consumption
everywhere, which changed which of those happened to be true.

Both now pin their preconditions: `_revive_player()` for steps that test *taking*
damage, and explicit state resets for steps that test a gated code path.

**Lesson recorded:** in a single long-running harness, every step's preconditions
are set by all the steps before it. A test that passes because of an accident of
ordering is not a test. When a step asserts on a gated path, enumerate the gates
and set every one of them — do not assume the world arrived in a convenient
state. And when a failure appears in code you never touched, check whether the
*state* reaching that code changed, not only the code.

## Wave-49 addendum: live-harness finds (B9)

Wave 49 put a river through the city, gave six inert mission verbs real
behaviour, rewrote the campaign from 89 to 125 stages, added difficulty
presets, and ended the typography situation. Steps 96–97 took the harness from
445 to **556 checks**. Six more defects surfaced. This wave's class is distinct
again from B3–B8: these were things that were **authored, wired, validated by a
test, and still wrong** — and two of them were wrong in the test as well as in
the code.

**B9 — a disconnected route graph returns an empty path, and nothing anywhere
says so.** `route_world()` returns `PackedVector3Array()` when the destination is
unreachable. That is a reasonable API. It is also completely silent: the GPS
overlay simply draws nothing, the player assumes the phone is being decorative,
and there is no log line, no warning and no fallback. Replicating the real graph
build in Python found **two components — 388 lane nodes and 48 belonging to
Crown Heights alone**. The lane rings are per-block islands stitched by a 70 m
k-NN, and the gap between Neon Mile's easternmost ring (`x = 137.8`) and Crown
Heights' westernmost (`x = 242`) is **104 m**, past the stitch cap. So the
Overlook, the Country Club, the Observatory, Crown Premium Fuels and the Crown
Heights stash had no GPS at all — and `m12_everyone`, the finale, opens with
`goto(poi_overlook)`. The last mission in the game sent the player to a waypoint
the phone could not route to.

This predated the river entirely; the river merely made me count the components.

**Lesson recorded:** any pathfinder that can fail must have its failure asserted,
not inferred. `route_world(a, b).size() >= 2` is a check about one pair of
points and tells you nothing about the graph. The assertion that matters is
**connectedness**: flood-fill from node 0 and require `seen.size() == nodes.size()`.
That is one loop, it is O(V+E), and it catches every unreachable-district bug at
once instead of one destination at a time. A silent-empty-return API is a defect
generator.

**B10 — the test had the same inverted convention as the code it was testing.**
`city.json`'s `axis` names the *constant* coordinate: `axis "x"` is a line of
constant `x` running north–south. `_station_along_z()` read it the other way, so
every filling station canopy was turned 90° from the arterial it fronts. The
harness assertion at step 93 — written in the same pass, from the same reading
of the JSON — inverted it identically, and so passed. It then asserted the
*weakest possible* consequence: "some canopies run north-south and some don't"
(`alongz93 > 0 and alongz93 < size`). A mixed result is what a correct builder
produces *and* what a builder with the convention backwards produces.

Fixed both, and changed the assertion to recompute the expected orientation per
station from `city.json` and the nearest arterial, then diff against the
builder's own answer: `wrong93.is_empty()`. Now 3 of 6 run north-south and the
test would name the station that disagreed.

**Lesson recorded:** a test written from the same misunderstanding as the code
confirms the misunderstanding twice and reports success. When the data file
defines a convention, derive the expectation **from the data file inside the
test**, not from your reading of it at authoring time. And distrust any assertion
of the form "some X and some not X" — it is satisfied by the bug and by the fix
alike. State the per-item expectation and assert the violation list is empty.

**B11 — `gdparse` cannot see identifier scope or a missing engine API, and one
such error deletes an autoload.** After the river landed, the harness reported
**130 checks / 6 fails** — a 380-check collapse. `gdparse` said the file was
fine. The engine said otherwise, three times: an undeclared `neon` local used in
two bridge builders (declared in `_build_river`, used in `_riv_road_bridge`), and
`Rect2.intersects_segment()`, which is Godot 3 and does not exist in 4.7
(`ClassDB.class_get_method_list("Rect2")` returns empty; `Geometry2D` has no
segment-vs-rect primitive at all either). A single parse error in `world_gen.gd`
takes the whole `WorldGen` autoload down with it, and `build_city`, `_poi_pos`,
the route graph and every harness step that depends on them fail in cascade.
The reported failures were nowhere near the actual defect.

`/tmp/w49/check.sh` now runs `--check-only --script` per file and greps **only**
`Parse Error` — bare `--check-only` also resolves identifiers, so it
false-positives `Compile Error: Identifier not found: Db` on every script that
touches an autoload. The gate runs before every harness run.

**Lesson recorded:** a static syntax checker and an engine load are different
tests, and only the second one sees scope and API existence. When the harness
fails in areas you never touched, grep for the **first** `Parse Error` before
reading a single assertion — a dead autoload produces hundreds of unrelated red
lines. And `Rect2`/`Geometry2D` method names must be verified against the running
engine's `ClassDB`, not against memory of a previous major version.

**B12 — an unparented `CollisionShape3D` is a two-symptom bug and one symptom is
at exit.** `_build_water` constructed its shape, sized it, positioned it, and
never called `add_child`. The harbour therefore had **zero collision**, and
`city.gd::_spawn_check` — awaiting two physics frames, finding no `_ground_below`,
and repositioning via `_find_ground` — teleported any player who spawned over the
water. The second symptom was a leaked `GodotShape3D` RID reported after the
harness `DONE` line. That leak had been counted as an unexplained 4th `^ERROR:`
in the wave-48 log and written off as shutdown noise.

It is the same rule as B5 ("assert the effect, not the construction") arriving
from a different direction: B5 was a node built and never tree-attached, and
this is a node built and never *parented*. The leak line in the log was the
diagnosis the whole time.

**Lesson recorded:** an `ERROR: N RID allocations of type 'GodotShape3D' were
leaked at exit` is not shutdown noise — it names a collision shape that was
allocated and never owned by anything. Treat a change in the leaked-RID count as
a signal, and when a count has been stable-but-unexplained across waves, go and
explain it. This one was a gameplay bug wearing the costume of a teardown
diagnostic.

**B13 — shipped assets that nothing loads.** `assets/fonts/` carried four DejaVu
faces with generated `.import` files, and `menu.gd` credited "Fonts: DejaVu
(Bitstream Vera / Arev license)" on the about card. There was no theme resource
anywhere in the project, **not one `add_theme_font_override()` call in 42
scripts**, and `gui/theme/custom_font_size` was the entire typography
configuration. Every label in the game rendered in Godot's built-in fallback
face. The credit was accurate about what was in the repository and wrong about
what was on screen — and nothing fails, warns or logs when an imported asset
goes unreferenced.

Fixed by `scripts/ui/type.gd`: a `Type` autoload with three roles (display /
body / mono), `Type.install()` setting a `Theme` whose **default** font is the
body role on the root `Window` so Controls nobody thought about still inherit,
and `Type.apply()` branching on node type because **`RichTextLabel` has no
`font` theme item at all** — it takes one override per weight, and setting only
`normal_font` leaves every bold span on the fallback. The step-97 assertion
lists `res://assets/fonts/*.ttf` and requires every one to be mapped to a role:
the regression guard is written from the data on disk, not from `Type`'s own
answer.

**Lesson recorded:** add "every imported asset is referenced" to the audit
checklist alongside "every reference resolves" — the existing cross-ref pass
only ever ran in one direction. An about/credits card is a claim about runtime
behaviour and should be verified as one. And `RichTextLabel` weight overrides
are a trap worth a comment at the call site, because it fails silently and only
on the bold spans.

**B14 — a mission verb that ticks a timer is a costume, not a mechanic.**
`survive`, `chase`, `plant`, `defend`, `rail_cross` and `observe` each had a
`_setup` branch, a `_tick` branch and authored data — and each did the same
thing: count down and advance. Six names for one verb. `observe` iterated an
`actors` list that nothing ever populated, so it iterated nothing. `rail_cross`
was literally unwinnable on foot: the Smoke Line runs at 17.5 m/s and the player
sprints at 6.4. `_tick_plant` re-armed the fuse every tick, so a planted charge
could never go off. `_on_choice_picked` silently dropped the `rel2` and
`faction_rep` keys the data authored.

Now each has a real win *and* a real loss condition, and each writes a stat the
Street Ledger surfaces: `holds_kept`, `runners_caught` / `runners_lost`,
`sabotages` + `clean_blasts`, `wards_kept`, `rail_crossings`, `stakeouts`.
`rail_cross` spawns the mission van; `observe` spawns two subjects and fails if
either reaches `suspicion >= 100`; `defend` gives the ward 4.5 dps inside 7 m
and fails the mission when it dies.

**Lesson recorded:** a stage type is not implemented because a `match` arm
exists. For each verb, name the **failure condition** — if the only way to not
complete it is to run out of clock, it is a timer. The `17.5 vs 6.4 m/s` case is
the sharper form of the same error: two authored numbers in different files that
individually look fine and together make an objective impossible. Cross-file
numeric comparisons against the physics that has to satisfy them.

### Verified clean this wave

- **River placement**: 0 district plates, 0 road strips, 0 building blocks, 0
  POIs, 0 filling stations and 0 rail viaduct piers intersect any of the three
  channels. The harness recomputes all of it from `city.json` each run.
- **Route graph**: 442 nodes (436 lane + 6 crossing), 1 component, 442/442
  reachable, **0 wading edges** — lane-to-lane and crossing ties alike.
- **Bridges**: every arterial that meets water has one and only those do (2
  road + 2 foot); every deck has collision you can stand on; no waypoint on a
  live GPS route is in the water.
- **Escapability**: the four landing treads descend monotonically and the
  bottom one is below the waterline, so the Cut is not a one-way trip.
- **Dialogue**: 57 trees, 161 nodes, **0 dangling `next`/`option` refs**, every
  `start` resolves. All three terminals using ad-hoc sentinels (`"end"`, `""`)
  normalized to `null`.
- **Choice contract**: every `choice` stage's `options[].id` matches a terminal
  node id in its referenced tree (`m10.choice_plan`, `m11.choice_final`,
  `m12.choice_ledger` → `ledger_burned` / `ledger_kept` / `ledger_law`).
- **Mission data**: 29 missions / 125 stages / 22 stage types; every `enemy`
  value is one of the six valid ids; every cutscene id is one of the five that
  exist; all six `race` tracks are in `RACE_TRACKS`.
- **JSON round-trip**: `data/city.json` and `data/missions.json` are stable under
  `json.dumps(indent=1)` + trailing newline; `data/dialogue.json` likewise.
- **Fonts**: all 6 roles load a real `Font`; display / body / mono are three
  genuinely different faces; the root `Window` carries the theme.
- **Harness hygiene**: 0 `SCRIPT ERROR`, 3 `^ERROR:` — all after the `DONE`
  line, all shutdown RID leaks, and one fewer than wave 48 because C1 is fixed.

### Scorecard after wave 49

| Axis | Wave 47 | Wave 48 | Wave 49 | Note |
|---|---|---|---|---|
| Systems depth | 9/10 | 9/10 | **9.5/10** | six verbs are mechanics now; difficulty is a real knob; the graph is connected |
| Game feel | 8.5/10 | 8.5/10 | **8.5/10** | unchanged — nothing this wave touched combat or movement response |
| Look & presentation | 7/10 | 7.5/10 | **8.5/10** | a river with real banks, bridges and a promenade; the whole UI is typeset rather than defaulted |
