# LEVERAGE — Technical Architecture

Engine: **Godot 4.7.2-stable**, renderer: **Mobile**
(`renderer/rendering_method="mobile"`), target device: **iPhone via XOGOT**
(GDScript only — no C#, no compiled addons/GDExtension).

The API surface is the **full Godot 4.7** one, not a subset. XOGOT's App Store
runtime has been Godot 4.7 since release **1.7.2**; this project develops
against **1.7.12** (D-27). The *manual bundled inside* XogotDocs is a 4.5-era
snapshot (`Manual/migrating/` stops at `upgrading_to_godot_4.5.md`, no
`classes/` reference), so it is read for concepts only and is **never** treated
as the authority on what exists (D-02a). An earlier revision of this line
inherited that snapshot's age as an engine restriction — a limit with no basis,
since the engine binary is 4.7.2-stable. Verified against
`xibbon/XogotDocs@4a5a22c` (K-16).

---

## 1. Runtime topology

```
SceneTree root
├── 19 autoloads (project.godot, load order matters)
│   Bus            global signal hub (53 signals) — all cross-system events
│   Db             loads 16 JSONs once; typed accessors; single source of truth
│   Type           typography: 3 families × regular/bold, role presets, theme
│   Difficulty     3 presets (street 0.72 / ledger 1.00 / crowe 1.34), threat(),
│   │              scale_count(), police_cap()
│   Progression    xp/level, per-style xp, unlock gating
│   Cinematics     hitstop, slowmo, fov_punch
│   WorldState     clock/day, weather, money, wanted, factions, relationships,
│   │              memory, flags, stats, inventory, weapons, saves serialize v5
│   SaveSystem     user://save_slot_%d.json, 3 slots + meta
│   AudioDirector  5 buses (master/music/sfx/vox/ambient), pooled 2D/3D SFX
│   │              players, crossfaded music A/B, vox blip queue, radio
│   Effects        pooled GPUParticles bursts, tracers, decals, muzzle lights,
│   │              camera shake (registered camera)
│   WorldGen       builds Cinder City: merged ArrayMesh chunks per district +
│   │              trimesh StaticBody collision, landmarks, furniture, lamps,
│   │              traffic lights, 109 lane loops, POI doors; spatial queries
│   InteriorManager 19 procedural room defs, one interior at a time, return pos
│   Cutscene       letterbox/cards/cam moves/actor staging; 5 scripted scenes
│   DialogueUI     typewriter boxes, portraits, voiced lines, choice menus
│   CallManager    inbound/outbound phone calls during play
│   MissionManager 29 missions as stage machines (125 stages, 22 types), chain,
│   │              rewards, bust/death recovery, save/apply
│   ShopUI         buy/sell/vehicles/clinic-heal full-screen shop
│   PhoneUI        9 apps incl. live-drawn city map
│   Game           app state machine (BOOT/MENU/LOADING/PLAYING/CINEMATIC/
│                  PAUSED/GAMEOVER), scene flow, settings JSON, autosave
└── current_scene
    boot.tscn → title.tscn → notice.tscn → menu.tscn → city.tscn
                                             city.tscn (Node3D)
                                             ├── WorldEnvironment (dynamic env)
                                             ├── DirectionalLight3D (day/night)
                                             ├── GPUParticles3D (rain, cam-follow)
                                             ├── CinderCity (WorldGen output)
                                             │   └── district_* ×6 (meshes+collision+POI doors)
                                             ├── CityLife (Node) — crowds/traffic/police/
                                             │   events/lamp pool/traffic lights/ambience/radio
                                             ├── Player (CharacterBody3D)
                                             │   ├── CollisionShape3D (capsule)
                                             │   └── Humanoid (Node3D)
                                             │       └── Skeleton3D (22 bones)
                                             │           └── MeshInstance3D (6 surfaces)
                                             ├── CameraRig (Node3D, group cam_rig)
                                             │   └── Camera3D (collision-aware orbit)
                                             ├── Tutorial (Node)
                                             └── HUD (CanvasLayer, procedural touch UI)
```

## 2. Data-driven design

All content lives in `data/*.json` (15 files), loaded once by `Db`:
characters(16) · combat_styles(5) · weapons(9) · armor(4) · items(10) ·
outfits(6) · vehicles(8) · peds(25) · city(6 districts + world + 27 POIs) ·
missions(20) · dialogue(49 trees) · events(12) · shops(6) · radio(4) ·
news+barks. Scripts contain systems; JSON contains the world. Mission stages
are declarative (`type`, `poi`, `char`, `dialogue`, `options[].effects`,
`check` expressions evaluated by a tiny safe evaluator: `money>=1500`,
`flag:x`, `item:y>=2`, `wanted>=1`, `hour>=22`, `stat:z>=3`).

## 3. Event flow (Bus)

UI and systems never reference each other directly for state changes:
gameplay emits (`crime_committed`, `mission_completed`, `district_changed`,
`vehicle_entered`, …), listeners react (CityLife dispatches police on
`crime_committed`; HUD redraws on vitals signals; PhoneUI news app reads
`radio_news`; MissionManager listens to `world_event`/`dialogue_ended`).
Exceptions (documented): player↔combat↔weapons are object-composed
(RefCounted controllers held by the player/NPC), and MissionManager spawns
actors into `current_scene` directly.

## 4. Characters

`Humanoid.build(params)` — static procedural builder: 22-bone Skeleton3D
(hips→feet, spine→head, 2×3-segment arms), rest poses from a bone table,
skinned 6-surface ArrayMesh (skin / face-textured head / hair / jacket /
pants / shoes) generated by an accumulator that emits weighted quads/boxes/
cylinders bound to bones. 17 hair styles, 8 skin tones, 24 face textures,
outfit colors from JSON. One builder serves player, 16 named NPCs, 25 ped
archetypes and all enemies — zero external 3D assets.

`AnimDriver` — pose-space procedural animation: phase-locked gait (walk/
run/sprint by speed01), per-style combat stances, 12 attack keyframe sets,
hit/down/getup/block/aim/drive/ride/sit/talk/listen/carry/dead/search/
combat_idle modes, lean/facing-delta/air/land blending. No animation files,
no state machine assets — fully code-driven, so every character animates
identically well at zero memory cost.

## 5. City generation & streaming

`WorldGen.build_city()` runs once at city load (~1–2 s desktop): per
district, roads/sidewalks/markings/crosswalks, buildings from the district
facade palette (8 procedural facade albedos + matching night-emission
textures), 12 landmark types (church, park, crane, containers, lighthouse,
tower, plaza, arch, refinery, slagheap, dome, manor), street furniture,
lamps, traffic lights, and POI doors — each district merged into a handful
of ArrayMesh chunks (one per material slot) with matching trimesh
StaticBody collision (markings excluded). Total draw calls for the whole
city: ~90 meshes. "Streaming" is by-exception: interiors are generated on
entry and freed on exit; NPCs/traffic spawn-despawn by distance (150 m /
170 m cull); night lights are a fixed 28-lamp pool reassigned each second
to the lamps nearest the player.

**Critical correctness note:** Godot trimesh (ConcavePolygonShape3D)
collision is single-sided — triangle winding must face the colliding side.
The ground plate's top face winding was inverted in the first build
(everything fell through the world); fixed and covered by the harness.

## 6. Simulation LOD

- NPC `_physics_process` self-throttles: 60 Hz (<25 m), 20 Hz (<60 m),
  5 Hz (<140 m), frozen beyond; routine pedestrians never pathfind — they
  walk straight toward random targets within their home district.
- Traffic vehicles tick every frame only while within 170 m; lane-follow
  is a pure pursuit controller + 9 m obstacle raycast.
- Police pursuit: cars steer at the player with distance-based throttle;
  foot units reuse the NPC combat state.
- Particles: pooled GPUParticles3D (fixed count) + billboard quad draw
  passes; decals are pooled quads with lifetime.

## 7. Physics & collision layers

Layer 1 = world, 2 = characters, 4 = vehicles. Combat hitscan rays query
mask 1|2|4 excluding the shooter; vehicle obstacle rays query 1|2|4
excluding self; ground checks query 1. CharacterBody3D for player/NPCs
(capsules), VehicleBody3D with VehicleWheel3D children (per-wheel
`use_as_steering`/`use_as_traction`, brake applied per wheel —
VehicleBody3D has no `brake_force` property in 4.x), StaticBody3D trimesh
for the world.

## 8. Audio architecture

AudioDirector creates 5 buses at boot and owns: a pool of 2D SFX players,
a pool of AudioStreamPlayer3D, two music players crossfaded by timer, named
ambient loops (rain/traffic/crowd/siren/interior) with volume targets, and
a vox queue that plays stylized bark blips (`vox/{voice}_{0..2}.wav`) under
subtitles. WAV loops use `AudioStreamWAV.loop_mode` (there is no `.loop`
property); OGG music uses `AudioStreamOggVorbis.loop`. Radio = station
track lists from JSON; in-vehicle only; district exploration music when
radio off.

## 9. UI architecture

All UI is built procedurally in code (CanvasLayers, no .tscn UI scenes):
HUD (layer 30), DialogueUI (40), ShopUI (45), PhoneUI (50), Cutscene (60).
Touch input: one full-screen PASS Control catches ScreenTouch/Drag; left
45% = floating virtual stick (writes `player.touch_move`), right = camera
drag (feeds `player.look_input` with sensitivity setting); buttons are real
`Button` nodes that consume their touches and drive the **same input
actions** as keyboard/gamepad via `Input.action_press/release` — one
authoritative input map, three devices. Pause menu is HUD-owned with
PROCESS_MODE_ALWAYS.

## 10. Save system

`SaveSystem.save_game(slot, extra)` writes JSON to `user://save_slot_N.json`
(WorldState.serialize v5 + Game's extra: player transform/vitals/weapons/
reserves, mission manager completed/failed/active, district). Autosave =
slot 0 on mission complete and pause-menu save. Load = `Game.continue_game`
→ city boots → `player.apply_save` + `MissionManager.apply_save` (active
mission restarts from its beginning — stage-internal state is not
persisted, documented limitation). Settings persist separately in
`user://settings.json`.

## 11. Performance budget (Mobile renderer)

- ~90 merged meshes + ≤28 dynamic omnis (pooled) + 1 shadowed directional.
- Textures POT and ≤2048² (mobile GPU limit 4096², non-POT repeat risk);
  all 96 world textures VRAM-compressed with mipmaps, UI/faces left Lossless.
  Census: 68×512², 18×256², 5×128², 2×1024², 2×2048², 1×64².
- Particles pooled; decals pooled; tracers 60 ms lifetime.
- No real-time GI, no SSAO, no SDFGI (Mobile renderer feature set);
  night atmosphere comes from emissive facades + lamp pool + glow.
- Quality setting (low/med/high) maps to shadow size/particle counts via
  settings_changed (desktop QA convenience; iPhone defaults medium).

## 12. Testing architecture

- `tools/forge/*` — Python generators (deterministic, seeded).
- `/tmp/gvenv/bin/gdparse` — fast syntax gate after every script write.
- `godot --headless --import` — asset import validation (**369** assets; also
  the step that applies the texture import params, and a prerequisite for the
  parse gate below because `class_name` globals are registered by the scan).
- `tests/harness.gd` — SceneTree harness booting the real city: **585 checks**
  across spawn/movement/combat/vehicles/missions/dialogue/interiors/shops/
  saves/police plus XOGOT-iPhone compliance (step 98), 0 fails. The count must
  match across a plain run and a `--verbose` run — a moving count means a guard
  silently skipped an assertion (K-21).
- Flow probes (`/tmp/flow*.gd`, ad hoc): boot→title→menu→new_game→city
  path, ground-support raycasts, collision winding regression.
- Status discipline: sandbox-headless results are **TESTED (sandbox)**,
  never presented as device proof; iPhone items are **DEVICE-ONLY**.
