# DEVELOPMENT STATE — LEVERAGE
_Last updated: session 3 (systems integration + first engine-verified gameplay)_

## OVERHAUL STATE (2026-11-23)

Wave 1 (visual rebuild) DONE: humanoid v2, vehicle v2, city v2, cinematic
grade — details and next waves in docs/VISUAL_QUALITY_REPORT.md §3.
Device fixes same day: menu scene roots were 0x0 Controls (blank/broken UI on
XOGOT), stretch aspect now keep_height for portrait hosts. Harness gates the
new geometry budgets (check 50). NEXT ACTION: wave 2 = phone life (incoming
calls, threads), then W3 map/GPS routes, W4 enemy tactics, W5 mission
playability pass, W6 animation depth, W7 audio identity, W8 device passes.

## Stage
VERTICAL GAMEPLAY COMPLETE IN SANDBOX — the full city boots headless in the
real Godot 4.7.2 binary; player, combat, vehicles, traffic, crowds, police,
missions, dialogue, interiors, shops, phone, saves all execute with 0 script
errors (harness **585/585 checks**). Presentation flow (boot→title→notice→menu→city)
wired. Remaining: tutorial layer, radio-in-vehicle, news feed polish, device
docs/verification guide, final audit.

## Completed (all committed, branch arena/9f25f474-barehands22)
- ENGINE: Godot 4.7.2-stable editor built from source (45 min, /tmp/godot-4.7.2-stable/bin/godot.linuxbsd.editor.x86_64).
  Project imports clean (**369** assets). Headless smoke + gameplay harness both green.
- ASSETS: 96 world textures (incl. 8 facade albedos + 8 emission), 138 SFX,
  16 music OGG, 60 vox blips (20 banks × 3), 29 UI PNGs, 24 face albedos,
  6 DejaVu fonts. All 96 world textures VRAM-compressed + mipmapped (D-25);
  369 importable assets total.
- DATA: 16 JSONs valid — characters(16), combat_styles(5), weapons(9), armor(4),
  items(10), outfits(6), vehicles(8), peds(25), city (6 districts, 109 lane
  loops, 27 POIs incl. 3 added: poi_ruths_alley/poi_plaza/poi_refinery_gate),
  missions(20: m01–m12 + 8 side), dialogue(49 trees incl. 2 added choice trees),
  events(12), shops(6), radio(4), news+barks.
- CORE AUTOLOADS (15): Bus, Db, WorldState, SaveSystem, AudioDirector, Effects,
  WorldGen, InteriorManager, Cutscene, DialogueUI, MissionManager, ShopUI,
  PhoneUI, Game (+CityLife node in city scene).
- PLAYER LAYER: humanoid.gd (22-bone skinned mesh builder), anim_driver.gd
  (procedural gait/combat/pose animation), camera_rig.gd (orbit + lock-on +
  cinematic + group "cam_rig"), player.gd (move/sprint/crouch/dodge, X/Y/A/B
  combat mapping, lock-on, style cycling, vehicles, interact, footsteps,
  district tracking, save/apply_save, give_weapon/use_item, touch_move).
- COMBAT: combat_controller.gd (12 attack timelines, reach+arc validation,
  block/parry window, stagger/knockdown, death/revive), weapons_controller.gd
  (guns: pellets/spread/recoil/hitscan/reload timeline/reserves; melee via
  combat controller; crime emission on gunfire).
- WORLD: world_gen.gd (merged per-district ArrayMesh chunks + trimesh
  collision; roads/marks/crosswalks/traffic lights; buildings from district
  facade palettes; 12 landmark types; furniture; lamps; POI doors),
  poi_door.gd, exit_door.gd, interior_manager.gd (19 procedural room defs,
  furniture sets, per-room collision + lighting).
- NPC: npc.gd (peds w/ routines, named characters, enemies; flee/gawk/talk/
  combat states; distance LOD 60/20/5 Hz; barks via Bus.dialogue_line; witness
  crime reports; memory of death → homicide crime).
- VEHICLE: vehicle.gd (VehicleBody3D; procedural car/bike meshes; engine audio
  w/ pitch by speed; headlights/taillights by night+weather; police lightbar +
  siren; damage/smoke; crash detection via velocity delta; traffic lane AI w/
  obstacle raycast; player_drive API), city_life.gd (crowd spawner, traffic
  spawner on 109 lane loops, parked cars, police dispatch/pursuit/roadblocks/
  arrest, 12 world events w/ actor staging, pooled night lamp lighting (28
  OmniLights), traffic-light cycle, district ambience+music routing).
- MISSIONS: mission_manager.gd (stage machine for 22 stage types: goto/talk/
  choice/objective/cutscene/event/combat/collect/carry/drive/drive_timed/race/
  escort/search/stealth/phone; choice effects; rewards; 3-act story chain w/
  requires_flag + act gating; bust/death recovery w/ fines + respawn; save/
  apply_save; race tracks; pickup.gd glowing collectibles).
- UI: dialogue_ui.gd (portraits, typewriter, voiced lines, node choices +
  mission choices via callback), cutscene.gd (letterbox/cards/cam moves/spawn/
  teleport/weather/music/fade verbs; 5 scripted cutscenes cs_intro/kidnap/
  exchange/finale/ending), shop_ui.gd (buy/sell/vehicles/clinic heal, keeper dialogue),
  phone_ui.gd (9 apps: MAP w/ live city draw, JOBS, RADIO tune, CALLS w/
  contact chats, BAG equip/use, MSGS, SAVE 3 slots, SETTINGS, NEWS),
  hud.gd (vitals bars, money, wanted stars, clock/weather/district, minimap
  w/ roads+POIs+mission marker+enemies, objective, toasts, lock-on marker,
  crosshair, full iPhone touch controls: virtual stick + camera drag + X/Y/A/B
  pad + sprint/crouch/block/lock/style/car/brake/horn/aim/fire/reload +
  phone/map/pause system buttons + pause menu).
- SCENES: boot.tscn (D'Youngs splash), title.tscn (logo + tap-to-continue),
  notice.tscn (content advisory), menu.tscn (new/continue/settings/credits),
  city.tscn (env + day/night sun + rain particles + thunder + WorldGen build +
  CityLife + player spawn + HUD + event routing + radio news ticker).
- TESTS: tests/harness.gd SceneTree harness — 26 checks, 0 fails:
  spawn/skeleton/combat/weapons/movement/melee/enemy damage+death/vehicle
  spawn+enter+drive (34.7 km/h)/prologue start/goto→talk stage advance/
  dialogue open/save+load roundtrip/wanted/peds+traffic+parked counts/
  interior enter+exit/shop open+gun purchase/gunfire hitscan.

## Status discipline
IMPLEMENTED+TESTED(headless sandbox): everything above.
NOT TESTED: touch controls on real glass, rendering visuals (headless = no
rasterization), audio audibility, performance/FPS on iPhone.
DEVICE-ONLY pending: XOGOT import on iPhone, touch ergonomics, Mobile renderer
visual check, 60 FPS validation.

## Known defects / accepted
- Exit-time leak warnings in harness (queue_free at quit) — cosmetic.
- numpy uint8 RuntimeWarning in forge facade() — cosmetic.
- pink-noise _filter stub is a no-op — accepted.
- Traffic vehicles ignore red lights visually (they raycast obstacles only).
- Escort VIP uses first ped archetype (ped ids don't include "ped_nurse").

## Fixed this session (engine-verified)
- CRITICAL: ground-plate top-face triangle winding was inverted → trimesh
  collision is single-sided → player/NPCs/vehicles fell through the world.
  Fixed Acc.box() top quad order; player now on_floor=true at spawn.
- current_scene was never set for manually-added scenes → all _scene()
  helpers returned null; Game.goto_scene + harness now set it.
- ParticleProcessMaterial has no emission_texture → particles now use textured
  billboard QuadMesh draw pass.
- VehicleBody3D has no brake_force → per-wheel brake via _set_brake().
- VehicleWheel3D props are use_as_steering/use_as_traction (not wheel_*).
- AudioStreamWAV loops via loop_mode (not .loop); engine loop fixed.
- Crash detection via velocity delta (no total_applied_impulse on body state).
- Skeleton3D node now named so Humanoid path lookups work.
- StyleBoxTexture margins are texture_margin_* (not margin_*).
- Dozens of typed-inference fixes (INFERENCE_ON_VARIANT is error-by-default).
- Tutorial layer added (scripts/ui/tutorial.gd, contextual 8-step coach).
- Vehicle radio (CityLife.radio_cycle + RADIO HUD button; station persists).
- News feed: CityLife pushes headlines on missions completed / wanted changes.
- boot→title flow verified headless (main scene runs clean 40 s).
- Flow verified: menu → new_game → city → prologue m01 stage go_ruths.

## CINEMATIC OVERHAUL — wave status (2026-11-23)

Waves 1–7 committed on arena/94fd4268-barehands22:
- W1 `b77a388` humanoid v2 / vehicle v2 (+_wheel_mesh) / city v2 / filmic grade / check 50
- W2 `ee01406` CallManager + call overlay + threads + forged phone audio / check 51
- W3 `e2cd7e8` A* GPS routing over lane graph + phone-map route layer / check 52
- W4 `e2cd7e8` enemy tactics: stagger, call-help, flank, retreat, style attack pools / check 53
- W5 `56ecc9e` mission playability audit of all 20 missions; clerk char fixed; mission calls ring via CallManager
- W6 `4f06df5` steering/bike-lean/vibration drive poses; visible bike rider / check 54
- W7 `4f06df5`+`c2560d7` gearbox RPM sim + shift/skid SFX + reverse lights; adaptive music director
- extras: fog of war `46846e9` (check 55), wet-road sheen + rain fog `349b070`,
  opening cinematic cs_intro `e6678cb`, safehouses + hidden stashes `d20908d`,
  shops now open `7dd7a0b`, casino + fight club playable `a323f76`,
  HUD phone badge `c25fb6fa`

## Exact next action
1. ~~Engine rebuild~~ DONE 2026-11-23: 4.7.2 built, headless import clean,
   **harness checks=45 fails=0** — checks 50–55 runtime-TESTED.
   Wave 8 (depth: escalation/progression/stealth/gunplay) raised the suite
   to **checks=64 fails=0, 0 script errors** — see docs/LEVERAGE_VISION.md
   and CHANGELOG 2026-11-23 DEPTH WAVE 8.
2. ~~Open PR~~ DONE: PR #3 (arena/94fd4268-barehands22 → main).
3. Device pass per docs/VERIFICATION_GUIDE.md §B–§E when an iPhone/XOGOT
   environment is available; flip DEVICE-ONLY rows with evidence (W8).

## Delivery
- Branch pushed to origin (github.com/jamesrudh-arch/Barehands22,
  arena/9f25f474-barehands22). Docs suite complete (15 docs incl.
  FINAL_REPORT). Harness 26/26, flow probes green, 0 script errors.
5. Write remaining docs: DESIGN, TECH_ARCHITECTURE, ART_DIRECTION,
   WORLD_CHARACTERS, CONTROL_MAP, ASSET_REGISTER (+licenses),
   REQUIREMENTS_TRACEABILITY, DECISION_LOG, CHANGELOG, TEST_REPORTS,
   KNOWN_DEFECTS, VERIFICATION_GUIDE; final honest per-requirement report.
6. Commit + push branch; deliver via GitHub.
