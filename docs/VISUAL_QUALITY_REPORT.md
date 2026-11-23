# LEVERAGE — Visual Quality Report & Overhaul Ledger

Status: **LIVING DOCUMENT** for the cinematic overhaul ordered 2026-11-23.
Method: code-level audit of every generator + asset class, measured geometry
budgets (harness checks 50), and the honest constraint that the delivery
sandbox is headless (no GPU) — engine pixels are verified on device per
`VERIFICATION_GUIDE.md` §B; offline, geometry/material budgets and the
software concept renderer (`tools/concept/render_concept.py`) are the evidence.

## 1. Audit findings (pre-overhaul)

| Area | Verdict | Evidence |
|---|---|---|
| Character bodies | **REJECTED — toy-like** | torso/limbs were 6 boxes + 2 cylinders; hands single boxes; skull a box with a flat face quad |
| Character materials | Partially good | face texture atlas (24), fabric normal maps, skin/hair palettes — kept |
| Vehicles | **REJECTED — 4 boxes** | body+cabin+2 bumpers; wheels bare cylinders |
| City blocks | Fair base, thin detail | facade texture slots, signs, posters, roof clutter existed; no cornices, entrances, balconies; trees = trunk + cone |
| Street furniture | Thin | bin/bench/hydrant only |
| Lighting/grade | **REJECTED — flat** | linear tonemap, no grading, glow off |
| HUD/phone UI | Good foundation | kept per order (controls + phone design) |
| Runtime systems | Good foundation | combat/wanted/traffic/save/missions logic retained |

## 2. Wave 1 (this change set) — executed

- **Humanoid v2** (`scripts/player/humanoid.gd`): new `loft()` primitive;
  anatomical pelvis/chest lofts, jacket shell + collar (real cloth layer),
  sculpted head (skull sphere, jaw loft, chin, cheeks, brow, nose loft, lips,
  ears), deltoid/elbow/knee joints, tapered arms with sleeves + cuffs,
  hands with palm/fingers/thumb, calves with bulge, shoes with sole/upper/toe,
  glutes. Same skeleton & material slots → all animation kept.
  Budget gate: 1 500–14 000 tris (harness 50).
- **Vehicle v2** (`scripts/vehicle/vehicle.gd`): 8-station lofted body with
  cabin shoulders, greenhouse glass surface (alpha), chrome trim, mirrors,
  bumpers, interior (dash, seats, wheel); wheels = tyre + rim barrel +
  5 spokes + hub, two materials. Paint metallic 0.62/rough 0.30.
  Budget gate: 200–9 000 tris (harness 50).
- **City v2** (`scripts/world/world_gen.gd`): trees with tapered trunk,
  2–4 branches, 3-blob crowns, per-tree lean/scale; parapet lip + cornice
  bands; recessed entrances with step + awning; balcony stacks on mid-rise;
  new props: bus_stop, dumpster, sign_pole, planter; hydrant cap.
- **Cinematic grade** (`scripts/scenes/city.gd`): Filmic tonemap, contrast
  1.07 / saturation 0.93 adjustment, controlled glow (0.32) for neon bleed.

## 3. Wave ledger (status after each wave)

- **W1 Visual overhaul** — COMMITTED `b77a388`. Humanoid v2, vehicle v2
  (incl. `_wheel_mesh`), city v2, filmic grade, triangle-budget gates (check 50).
- **W2 Phone life** — COMMITTED `ee01406`. CallManager state machine
  (IDLE/RINGING/IN_CALL, 22 s timeout, retry-when-calm queue), call overlay
  (portrait/answer/decline/subtitles/hang-up), call log + message threads
  with unread badges persisted in saves, mission offers arrive as real calls,
  ambient character calls, forged ring/ringback/msg/connect audio (check 51).
- **W3 Map/GPS** — COMMITTED `e2cd7e8`. A* over the lane graph
  (`WorldGen.route_world`), route polyline + player dot + destination ring on
  the phone map, tap-POI routing, ROUTE TO OBJECTIVE button, GPS state saved
  (check 52). Fog-of-war discovery remains an open item (see §5).
- **W4 Enemy tactics** — COMMITTED `e2cd7e8`. Stagger/give-ground when hurt,
  call-for-help with convergence, ally-down flinch, pincer flanking, gun
  spacing + retreat at low HP, per-style melee attack pools, feint backoff
  (check 53).
- **W5 Mission playability** — COMMITTED `56ecc9e`. Audited all 20 missions:
  every stage type has runtime logic, all cutscene/dialogue/POI refs resolve;
  fixed dangling `clerk` character; mission phone stages ring via CallManager;
  ending chain (m12 → cs_ending → game_complete → menu) verified by audit.
- **W6 Animation depth** — COMMITTED `4f06df5`. Steering-coupled driving
  poses, visible bike rider with lean, road vibration (check 54).
- **W7 Audio identity** — COMMITTED `4f06df5`. Gearbox RPM simulation with
  shift dips + forged shift clunks, tyre skid SFX, reverse lights, per-style
  engine pitch. Footstep surfaces already covered (5 surfaces × walk/run).
- **W8 Device verification** — PENDING. XOGOT passes §B–§E with this report
  as baseline.

**Runtime verification (2026-11-23):** engine 4.7.2 rebuilt in sandbox;
headless `--import` clean; harness run **checks=45 fails=0** — all of
checks 50–55 (triangle budgets, phone ring/decline/log, GPS A* route,
tactics surface, drive-animation wiring, fog persistence) now TESTED, not
just IMPLEMENTED. Fixes made during verification: typed-inference parse
errors (phone_ui/city/npc/city_life), bike `_head_l` null guard, HUD
armor/current_district property names, phone WAV path consolidation,
route-graph k-NN stitching (lane loops were disconnected islands).

## 5. Open items

- XOGOT/iPhone device verification of touch layout, audio mix, performance
  (W8).

## 4. Honesty ledger

- No engine pixels were produced in-sandbox (headless, no GPU): visual claims
  here are geometry/material/budget claims + device screenshots when the user
  provides them. Automated checks prove structure, not beauty.
- Faces remain texture-mapped plates on sculpted heads (mobile budget);
  full geometric faces + PBR skin are a stated non-goal for iPhone class.
- Animation remains procedural/procedural-blend; no mocap library is licensed.
