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

## 3. Still below the bar — next waves (ordered)

- **W2 Phone life**: incoming-call state machine (ringtone, answer/decline
  screen, missed-call log), message threads w/ read state, contact portraits.
- **W3 Map/GPS**: route search over the 109-lane graph, draw route polyline,
  POI iconography, fog-of-war discovery.
- **W4 Enemy tactics**: flank/cover/retreat/call-help states; per-archetype
  aggression & accuracy; suppressive behaviour for gunmen.
- **W5 Mission completion pass**: playable sequences for every mission entry
  (stage logic verified end-to-end, not text-only).
- **W6 Animation depth**: idle/walk blends, hit reactions, enter/exit vehicle
  poses (procedural bone drives on the existing skeleton).
- **W7 Audio identity**: engine gears, footstep surfaces, ringtone, mix bus.
- **W8 Device verification**: XOGOT passes §B–§E with this report as baseline.

## 4. Honesty ledger

- No engine pixels were produced in-sandbox (headless, no GPU): visual claims
  here are geometry/material/budget claims + device screenshots when the user
  provides them. Automated checks prove structure, not beauty.
- Faces remain texture-mapped plates on sculpted heads (mobile budget);
  full geometric faces + PBR skin are a stated non-goal for iPhone class.
- Animation remains procedural/procedural-blend; no mocap library is licensed.
