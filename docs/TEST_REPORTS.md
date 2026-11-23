# LEVERAGE — Test Reports

Environment: Linux sandbox (Debian 12, 2 CPU), **Godot 4.7.2-stable editor
binary built from source** (`/tmp/godot-4.7.2-stable/bin/godot.linuxbsd.
editor.x86_64`, headless: x11=no wayland=no). All runs `--headless`.
**Headless ≠ device:** no rasterization, no audio device, no touch glass.
Results below are *sandbox logic* proof only (see TRACEABILITY vocabulary).

---

## T-01 Asset import

Command: `godot --headless --path . --import`
Result: **PASS** — 333 assets imported; no errors. (Only historical error
was the then-missing boot.tscn, since created.)

## T-02 GDScript syntax gate (per-write)

Command: `/tmp/gvenv/bin/gdparse <file>` after every script write.
Result: **PASS** — all 33 scripts (+ tests) parse-clean. Note: gdparse
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
Result: **PASS — 21/21 checks, 0 fails, 0 script errors** (latest run):

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

Exit-time leak warnings (7 resources / 2 RIDs) are harness-quit artifacts
(queue_free at quit), not runtime leaks — see KNOWN_DEFECTS K-07.

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
Result: **PASS** — every referenced SFX name exists (14 mismatches found
in session 3 and remapped, e.g. cash_register→cash, ui_open→shop_bell).

---

## Not tested here (explicitly)

Rendering output, visual correctness of materials/lighting, audio
audibility/mix, touch ergonomics/multitouch on glass, frame rate/thermals
on iPhone, XOGOT import and iOS behaviors — all **DEVICE-ONLY**, see
`docs/VERIFICATION_GUIDE.md`.
