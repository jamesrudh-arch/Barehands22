# LEVERAGE — Requirements Traceability

Status vocabulary (strict): **IMPLEMENTED** = code complete, parse-clean.
**TESTED** = executed in the real Godot 4.7.2 binary headless in the
sandbox with assertions (harness/flow probes). **VERIFIED** = tested plus
visual/interactive confirmation. **DEVICE-ONLY** = cannot be proven in the
sandbox; requires the iPhone/XOGOT. Headless testing proves logic, never
rendering, audio audibility, touch feel or device performance.

| # | Requirement | Where implemented | Status | Evidence |
|---|---|---|---|---|
| 1 | Distinctive art direction, not asset-flip | `docs/ART_DIRECTION.md`; `tools/forge/*` (all-original procedural set); ember/industrial-noir palette; facade emission night system | IMPLEMENTED; visuals DEVICE-ONLY | ASSET_REGISTER (0 third-party art); headless import 369 assets clean |
| 2 | Full humanoid characters w/ faces, rigs | `scripts/player/humanoid.gd` (22-bone rig, 6-surface skinned mesh, 24 faces, 17 hair, 8 skins, outfits) | TESTED | harness: "player skeleton built", NPC bodies spawn citywide |
| 3 | Complete animation pipeline (idle→sprint, combat, vehicles, facial) | `scripts/player/anim_driver.gd` (phase-locked gait, 12 attack sets, 15 modes incl. drive/ride/talk; face = talk blip + portrait system) | TESTED (logic); visuals DEVICE-ONLY | harness movement/attack/death; no anim errors in 100 s soak |
| 4 | Asset research w/ download & license records | `docs/ASSET_REGISTER.md` §9, `docs/LICENSES.md` | VERIFIED (docs) | research table + license texts committed |
| 5 | 6-area connected city, interiors, doors, traffic, landmarks, streaming | `scripts/world/world_gen.gd` (6 districts, arterials, 12 landmark types, 27 POI doors), `interior_manager.gd` (19 rooms), `city_life.gd` (traffic on 109 loops, spawn/cull = streaming) | TESTED | harness: interior enter/exit; flow probes: 75+ collision bodies, lanes=109, traffic=7–8 active |
| 6 | Responsive third-person controller + collision-safe camera | `scripts/player/player.gd` (walk/run/sprint/crouch/dodge, accel/friction), `camera_rig.gd` (orbit, collision pull-in, lock-on, FOV kick, cinematic) | TESTED (movement); feel DEVICE-ONLY | harness "player moved"; on_floor=true after winding fix |
| 7 | 5 distinct melee disciplines that play differently | `data/combat_styles.json` + `combat_controller.gd` (per-style speed/dmg/reach/stamina/stance; throw vs kick vs sway mechanics) | TESTED (switching); balance DEVICE-ONLY | style cycle via STY; stance feeds AnimDriver |
| 8 | Full weapons/armour with gameplay effects | `data/weapons.json` (9) + `weapons_controller.gd` (pellets/spread/recoil/reload/reserves/hitscan) + `data/armor.json` (protection/speed_mod) | TESTED | harness gunfire executed; gun purchased → owned_weapons |
| 9 | Exact mapping X=punch Y=heavy A=kick B=dodge; B=interact out of combat | `project.godot [input]`; `player.gd` `_handle_combat_input`/`_handle_interact`; HUD pad geometry | TESTED (actions fire via Input.action_press in harness) | CONTROLS.md §4 |
| 10 | One authoritative input map + iPhone touch controls matching it | HUD injects `Input.action_press/release` for the same actions; floating stick + camera drag; no parallel paths | IMPLEMENTED; ergonomics DEVICE-ONLY | hud.gd `_press/_release`; CONTROLS.md §2 |
| 11 | Vehicle system: cars, motorcycles, physics, traffic AI, enter/exit | `scripts/vehicle/vehicle.gd` (VehicleBody3D, 8 defs incl. bike, per-wheel steer/traction, engine audio, damage, police bar), `city_life.gd` traffic, `player.gd` enter/exit | TESTED | harness: vehicle spawned/entered/driven 34.7 km/h/exited |
| 12 | Living NPC system: 16 named + ~25 ped archetypes, routines, memory | `scripts/npc/npc.gd` (routines per archetype, named placement, react flee/gawk/call-police, LOD 60/20/5 Hz), WorldState.remember/relationships | TESTED | harness peds=11–12 active; routine states cycle |
| 13 | Enemy + police AI: wanted levels, pursuits, roadblocks | npc.setup_enemy (5 kinds incl. gunmen with hitscan), `city_life._police_tick` (dispatch by wanted, cruiser pursuit, foot cops, roadblocks ≥3, arrest timer) | TESTED (spawn/dispatch); chase feel DEVICE-ONLY | harness wanted=3; police units spawn on crime signal |
| 14 | Persistent world events, weather, day/night | `data/events.json` (12, actor-staged by CityLife), `world_state.gd` (24 h clock, weather roll, wetness), `city.gd` (sun/sky/fog/rain/thunder by hour+weather) | TESTED | harness weather set; city day/night runs in soak |
| 15 | Full story w/ meaningful choices/consequences | `data/missions.json` (3 acts, 12 story), 49 dialogue trees, choice effects → flags/faction/rel/wanted gating later missions (`requires_flag`, act gates) | TESTED | harness: prologue starts, goto→talk advances |
| 16 | Missions, side jobs, economy, shops, inventory, phone, map, saves | `mission_manager.gd` (29 missions, 125 stages, 22 stage types, 8 side jobs, rewards, bust/death recovery), `shop_ui.gd` (6 shops + sell + clinic + dealership), `phone_ui.gd` (9 apps incl. drawn map), `save_system.gd` (3 slots) | TESTED | harness: shop open/buy; save+load roundtrip with player+missions |
| 17 | D'Youngs presentation → title → notice → menus → cinematic → tutorial | `scenes/boot|title|notice|menu|city.tscn`; cs_kidnap cutscene; `tutorial.gd` 8-step contextual coach | TESTED (flow probes: boot→title clean 40 s; menu→new_game→city, mission m01 stage go_ruths) | flow3/flow10 logs |
| 18 | Complete audio identity | 138 SFX + 16 music + 60 vox blips (all forged), AudioDirector 5-bus mix, district music routing, vehicle radio, news stings | IMPLEMENTED; audibility DEVICE-ONLY | asset counts in register |
| 19 | Professional UI/UX, no fake dashboards | HUD/Phone/Shop/Dialogue/Cutscene all procedural but data-live: real vitals, real minimap geometry, real save metas, real news queue | TESTED (logic); look DEVICE-ONLY | harness UI paths execute error-free |
| 20 | Mobile optimisation: LOD, pooling, streaming | NPC/traffic distance LOD + cull, 28-light pool, particle/decoder pools, merged district meshes (~90 draw calls), interiors on-demand, POT textures 64–2048² all VRAM-compressed with mipmaps, Mobile renderer | IMPLEMENTED; FPS DEVICE-ONLY | architecture doc §5–6 |
| 21 | Godot 4.7 + Mobile renderer + XOGOT/iPhone target | `project.godot` (renderer `mobile`, `sensor_landscape`, `canvas_items` stretch, `scale_mode="fractional"`, **both** `import_etc2_astc` and `import_s3tc_bptc` true, `virtual_controller/enable=false`), `config/features=("4.7")`, GDScript only, no compiled addons/GDExtension/C#. API surface is the **full Godot 4.7** one — the earlier "restricted to 4.5-documented surface" claim was K-16 and had no basis: Xogot's App Store runtime has been 4.7 since release 1.7.2 (now 1.7.12); only the manual *bundled with* XogotDocs is a 4.5-era snapshot, and it is read for concepts, never as API authority | VERIFIED (config + harness step 98, 24 assertions); ASTC quality and orientation DEVICE-ONLY | DECISION_LOG D-01..D-03, D-02a, D-25..D-32; KNOWN_DEFECTS K-14..K-21 |
| 22 | Process: state file, honest statuses, docs suite | `docs/DEVELOPMENT_STATE.md` + 14 docs + this matrix | VERIFIED (docs) | committed + pushed |

## Coverage summary

- 22/22 mandatory requirement lines have implementations committed.
- TESTED in-engine (headless sandbox): rows 2,3,5,6,8,9,11,12,13,14,15,16,17,19 (logic).
- DEVICE-ONLY aspects (explicitly not claimed): rendering visuals, audio
  audibility, touch ergonomics, FPS/thermals, XOGOT import itself.
- No requirement was dropped; failed approaches are recorded in
  `docs/DECISION_LOG.md` and `docs/KNOWN_DEFECTS.md`.
