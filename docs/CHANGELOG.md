# LEVERAGE — Changelog

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
