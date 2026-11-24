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
