# LEVERAGE — World Design: Cinder City

Six connected districts on one landmass, harbour to the west-south, refinery
east, heights north-east. All geometry is generated at load by `WorldGen`
from `data/city.json`; coordinates below are world XZ (metres).

---

## 1. Districts

| District | Center | Size | Character | Palette / facades | Music |
|---|---|---|---|---|---|
| **Kiln Row** | (-220, 60) | 280×240 | Old brick residential + market streets; where Eli grew up; Ruth's, the church, the clinic | brick_red/dark, stucco; sodium lamps | music_explore_kiln |
| **Ashfall Docks** | (-60, 190)* | ~300×260 | Container yards, Berth 7, haulage offices, cranes, lighthouse; Crew territory | corrugated metal, concrete; cold lamps | music_explore_docks |
| **The Furnace** | (60, -150) | 260×220 | Industrial heart: refinery gate, pawn row, Crowe Credit office, the precinct; furnace orange night glow | brick_grey, metal; orange lamps | (furnace ambience) |
| **Neon Mile** | (40, 110) | 240×200 | Nightlife strip: Noir Lounge, Bravado club, casino, noodle row; signage atlas + neon slots | glass, stucco; teal/magenta | music_explore_neon |
| **Slagworks** | (340, -220) | 260×220 | Abandoned heavy industry: Yard 4 fight pit, gunsmith, garage, slagheap landmark | corrugated, rusted metal | music_explore_slag |
| **Crown Heights** | (360, 110) | 240×200 | Money: Halcyon Tower, country club, observatory, manor, plaza; glass facades, white lamps | glass, concrete | music_explore_heights |

\* docks center per city.json; arterials (defined in city.json `world`)
connect all districts as wide through-roads; a water plane + collision
wall sits at `water_z = -380` (harbour edge).

Each district generates: road grid (per-district `road_w`, `block` size),
sidewalk plates, lane markings + crosswalks (visual-only collision),
buildings from the district facade palette with height ranges from
`heights`, street furniture (bins, benches, hydrants, signs, posters),
lamp posts (registered for the night light pool), traffic lights (cycling
emissive omnis), trees in park cells, and its landmark set.

## 2. Landmarks (12 generator types)

church (Kiln Row, spire + nave), park (plaza green + paths), crane (docks,
tower crane), containers (stacked yards), lighthouse (docks, striped tower
+ lamp), tower (Heights, glass shaft), plaza (Furnace, open stone + arch),
arch (Heights gateway), refinery (Furnace, stacks + pipes), slagheap
(Slagworks, coned ash mountain), dome (observatory), manor (Heights
estate). Landmarks reserve their cells so buildings never overlap them.

## 3. Points of interest (27, all with interact doors)

**Kiln Row:** poi_home (Vane Apartment, int_apartment) · poi_ruths (Mama
Ruth's Soul Food, shop `ruths`) · poi_church (St. Ember's Parish) ·
poi_clinic (Okonkwo Walk-In, shop `clinic`, death respawn) · poi_market
(shop `market`) · poi_ruths_alley (kidnap cutscene trigger).
**Docks:** poi_berth7 (Crew office) · poi_haulage · poi_warehouse12 ·
poi_quay. **Furnace:** poi_halcyon_tower* · poi_precinct (bust respawn) ·
poi_crowe_office (Crowe Credit) · poi_pawn (shop `pawn`). **Neon Mile:**
poi_noir_lounge · poi_bravado · poi_casino · poi_noodle_row.
**Slagworks:** poi_shelter (Bishop's mission) · poi_gunsmith (shop
`gunsmith`) · poi_garage (shop `motors`, race start) · poi_yard4 (fight
club). **Heights:** poi_overlook (finale approach) · poi_country_club ·
poi_observatory · poi_plaza (final confrontation).
\* Halcyon Tower is both landmark and POI door.

POI doors are Area3D markers (teal emissive quad, group `interact`, label
"Enter …"). Entering routes through `Bus.world_event("poi_enter")`: with
`interior` key → InteriorManager builds the room and moves the player
inside (exit door returns them exactly); without → notification +
discovery. Mission `goto`/`stealth` stages also complete on door entry.

## 4. Interiors (19 procedural room defs)

int_apartment, int_ruths, int_church, int_clinic, int_market, int_berth7,
int_haulage, int_warehouse, int_lobby (Halcyon), int_precinct, int_crowe,
int_pawn, int_lounge, int_club, int_casino, int_shelter, int_gunsmith,
int_garage, int_fightclub. Each: inward-facing shell (floor/ceiling/4
walls, material per def), box collisions, one warm omni, furniture sets
(counters, bars, pews, beds, shelves, crates, stage, ring, car lift…), and
a "Leave" door. One interior alive at a time — memory-safe on mobile.

## 5. Traffic & crowd geography

- **109 lane loops** (one per city block, square circuits at road level)
  registered per district; traffic spawns on loops 20–120 m from the
  player, culls at 170 m, targets ~12 active vehicles + ~18 parked.
- **Pedestrian routines** per archetype (commute, work, jog, courier,
  stumble, tourist, wander, guard, vendor, busker) anchored to spawn
  homes; district `ped_density` scales crowd targets; archetypes are
  district-tagged in `data/peds.json` (dockers at the docks, suits in
  Heights, club kids on the Mile…).
- **Police geography:** dispatch spawns 45–70 m out, cruisers pursue,
  roadblocks (2 cruisers, perpendicular) at wanted ≥3, arrest on foot
  contact → precinct respawn + 10% fine; bust respawn = poi_precinct,
  death respawn = poi_clinic.

## 6. Persistence & streaming model

The city is fully generated once (no chunk streaming needed at this scale
on mobile: ~90 merged meshes). What *is* dynamic: NPCs/traffic (spawn-cull
by distance), interiors (on-demand), night lamp pool (reassigned every second to
nearest lamps), weather particles (camera-parented), mission actors
(staged then freed), event actors (auto-freed). WorldState persists flags/
stats/discoveries; saves store player + missions + district.

## 7. Weather & sky

clear / overcast / rain / fog roll every 7–20 min (story opens 21:30,
day 1, raining). Rain: 1400 billboard streak particles camera-parented +
loop ambience + periodic thunder; wetness value drifts (future: surface
darkening); fog thickens distance falloff; sky gradient, ambient energy
and sun color all lerp by hour × weather. Night (19:00–06:00) flips
facade emission on and activates the lamp pool + traffic light visibility.
