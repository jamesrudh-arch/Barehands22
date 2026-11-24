# LEVERAGE — Test Reports

Environment: Linux sandbox (Debian 12, 2 CPU), **Godot 4.7.2-stable editor
binary built from source** (`/tmp/godot-4.7.2-stable/bin/godot.linuxbsd.
editor.x86_64`, headless: x11=no wayland=no). All runs `--headless`.
**Headless ≠ device:** no rasterization, no audio device, no touch glass.
Results below are *sandbox logic* proof only (see TRACEABILITY vocabulary).

---

## T-01 Asset import

Command: `godot --headless --path . --import`
Result: **PASS** — **369** assets imported; **0 errors** (re-run at wave 49.5
after `rm -rf .godot/imported`, ~10 s). The `[remap]` metadata on all 96 world
textures reads `"imported_formats": ["s3tc_bptc", "etc2_astc"]` with
`"vram_texture": true` — 96 × 2 `.ctex` artefacts, every one mipmapped and
`DATA_FORMAT_IMAGE`. (Earlier runs reported 333 assets; the set has grown.)

## T-02 GDScript syntax gate (per-write)

Command: `/tmp/gvenv/bin/gdparse <file>` after every script write.
Result: **PASS** — all **44** scripts (+ tests) parse-clean. Note: gdparse
misses engine-level typing rules; T-04/T-05 are the authority.

## T-03 City soak (main scene = city, 100–110 s)

Command: temporarily set `run/main_scene` to city.tscn; run headless.
Result: **PASS** — full city build (6 districts, landmarks, POIs, lanes),
CityLife crowds/traffic/police loop, HUD/dialogue/phone/shop autoloads
alive: **zero script errors** over the soak.

## T-04 Boot flow soak (main scene = boot.tscn, 40 s)

Result: **PASS** — D'Youngs splash runs, scene change to title executes,
no errors.

## T-05 Gameplay harness (`tests/harness.gd`, SceneTree script)

Command: `godot --headless --path . -s res://tests/harness.gd`
Result: **PASS — 585/585 checks, 0 fails, 0 script errors, exit 0** (latest run,
wave 49.5). The 26-check table below is the *original* wave-1 skeleton, kept for
history; the suite has since grown to 585 across 98 steps, the last of which
(step 98) is XOGOT/iPhone compliance — 24 assertions covering texture import
params, POT/size, both VRAM format flags, the `.ctex` header, Virtual
Controller, `config/features`, touch-button→Input-Map binding, the GDScript-only
ban, stretch/scale_mode, the audio name cross-reference and the iOS lifecycle
save.

**Determinism is now part of the result**: 585 was reproduced on plain ×2 and
`--verbose` ×1. It had been 584 plain / 583 verbose, because step 46 guarded an
assertion with an `if` and no `else` (K-21). A count that moves means the suite
tested different things on each run, so the two modes must agree.

| Check | Result |
|---|---|
| player spawned / skeleton built / combat+weapons controllers | OK |
| player moved under virtual-stick input (touch_move) | OK (|pos| 246.8) |
| melee attack accepted (X action press) | OK |
| enemy spawned, damaged 40 (hp 100→60), killed by 9999 hit → DEAD state | OK |
| vehicle spawned (dealership path), player entered | OK |
| vehicle driven: throttle → **34.7 km/h** | OK |
| prologue: `begin_prologue()` → m01_last_call active, objective text | OK |
| stage machine: goto → (teleport to poi_ruths) → talk_marcus stage | OK |
| dialogue: tree opened by talk stage (`dialogue open: true`) | OK |
| save/load roundtrip: autosave slot 0 → load → has player+missions | OK |
| wanted set to 3 (police dispatch path armed) | OK |
| city life: peds 11–12, traffic 7–8, parked 14, **109 lane loops** | OK |
| interior: enter int_ruths → active; exit → inactive, player restored | OK |
| shop: gunsmith opens; buy gun_pistol @ 900 with 5000 cr → owned_weapons | OK |
| gunfire: pistol equipped, reserve 60, try_fire hitscan executes | OK |

Exit-time leak warnings are harness-quit artifacts (queue_free at quit), not
runtime leaks — see KNOWN_DEFECTS K-05/K-07. Judge that list by **type**, never
by count: identical code has measured 15–18 resources and 16–26
`RendererSceneCull::Instance` RIDs across runs, so the number moves with teardown
ordering. A *new type* is the signal (that is how C1 was caught).

## T-06 Menu → New Game flow probe

Result: **PASS** — menu.tscn boots; `Game.new_game()` → city scene is
`current_scene`; `Game.state == PLAYING(3)`; player exists; MissionManager
auto-starts m01 via story intro; stage `go_ruths` active.

## T-07 Ground-support regression (collision winding)

Probes: raycasts at spawn and district interior points, mask 1, player
excluded; StaticBody census; shape face dumps.
Before fix: rays **missed** ground everywhere (inverted top-face winding,
single-sided concave collision); player fell to y=−16.
After fix (`Acc.box()` top quad order): `hit=true → col_kiln_row_1` at
spawn; **player pos y≈−0.02, on_floor=true**; harness movement checks
pass. Recorded as D-08; permanent regression coverage = T-05 movement +
T-06 on_floor.

## T-08 JSON data validators

Command: python `json.load` over `data/*.json` after every data edit.
Result: **PASS** — 15/15 valid; cross-reference audits: every mission
stage poi/char/dialogue/item resolves against city/characters/dialogue/
items registries (2 missing dialogues + 3 missing POIs found and added).

## T-09 Audio reference audit

Command: grep all `sfx*("name")` calls vs `assets/audio/sfx/` inventory.
Result: **PASS at the time, but the method was unsound and it missed K-19.**
14 mismatches were found in session 3 and remapped (e.g. cash_register→cash,
ui_open→shop_bell). A later grep-style sweep then reported this clean while
`fuel_pump.gd` still called `sfx_at("engine_start", …)` — a file that has never
existed, so the moment the player had just paid for was silent. Two reasons it
slipped through: a hand-run grep is not repeated, and a naive pattern matches
the prefix of genuinely dynamic names (`"imp_" + mat`), which trains you to
ignore hits.

Now done **in-engine every run** as part of step 98: a `RegEx` over every `.gd`
under `res://scripts` and `res://tests` requires the closing quote to be
followed by `,` or `)`, so dynamic concatenations are excluded rather than
false-flagged, and every literal is checked against disk — **152 `sfx()`/`sfx_at()`
calls (67 distinct), 16 `play_music()`/`sting()` calls (8 distinct), 19 voiced
characters × complete `_0/_1/_2` banks**, all resolving, 0 dead. The four
`"imp_" + mat` targets (`concrete`/`glass`/`metal`/`wood`) were verified by hand
since no pattern can see them.

---

## Not tested here (explicitly)

Rendering output, visual correctness of materials/lighting, audio
audibility/mix, touch ergonomics/multitouch on glass, frame rate/thermals
on iPhone, XOGOT import and iOS behaviors — all **DEVICE-ONLY**, see
`docs/VERIFICATION_GUIDE.md`.
