# LEVERAGE — Changelog

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
