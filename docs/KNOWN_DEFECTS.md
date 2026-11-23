# LEVERAGE — Known Defects & Open Items

Honest register. None of the below blocks the sandbox-verified core loop;
D-items are device verification, K-items are known code/content defects.

## Code / content defects (open)

| ID | Severity | Description | Impact | Plan |
|---|---|---|---|---|
| ~~K-01~~ | **CLOSED** | Traffic now queries `CityLife.traffic_green_at(pos + fwd·10m)` and treats red as a blocker (`vehicle.gd _check_ahead`) | — | Fixed; harness check 46 |
| ~~K-02~~ | **CLOSED** | Original claim was wrong — `nurse` archetype exists in peds.json; escort spawn key was `ped_nurse` (typo) so it fell back to archetype[0]. Now spawns `nurse` | — | Fixed |
| ~~K-03~~ | **CLOSED** | `save_state` now serializes `stage`, `rt_pos`, `rt_time`; `apply_save` fast-forwards to the saved stage (skipping cutscenes) | — | Fixed; harness check 46 |
| ~~K-04~~ | **CLOSED** | `player.rebuild_appearance()` rebuilds the humanoid in place on equip (vitals/style preserved); shop calls it immediately | — | Fixed |
| K-05 | Cosmetic | Exit-time leak warnings under harness quit (7 resources / 2 RIDs) — queue_free-at-quit artifacts | None at runtime | Ignore; re-check on device builds |
| ~~K-06~~ | **CLOSED** | forge facade() frame color + sill now cast/clip before arithmetic; facades re-baked, re-imported clean | — | Fixed |
| K-07 | Cosmetic | forge_audio_lib pink-noise `_filter` is a no-op stub (white noise used where pink intended) | Two ambience loops brighter than spec | Accepted |
| K-08 | Medium | **Visuals never rendered** in sandbox (headless): material assignments, emission night look, sky gradient, rain particles, HUD layout are logic-verified only | Unknown visual defects possible | Device pass per VERIFICATION_GUIDE §B |
| K-09 | Medium | Touch controls unproven on glass: multitouch tracking is index-based and desktop-mouse-mapped (index 999); feel/deadzones untested | Possible ergonomic fixes needed | Device pass §C |
| ~~K-10~~ | **CLOSED** | Tuning radio on foot now toasts "Signal's weak on foot — the radio plays while you drive." | — | Fixed |
| ~~K-11~~ | **CLOSED** | Touch **JMP** button (56px, left of pad cluster) fires `Input.action_press("jump")`; hidden while driving | — | Fixed; harness check 46 |
| ~~K-12~~ | **CLOSED** | Substitution centralized in `CityLife.format_news()`; both `push_news` and the city ticker route through it | — | Fixed |

## Device-only verification items (not defects — unproven)

| ID | Item |
|---|---|
| D-01 | XOGOT import of the project folder (Files/iCloud → On My iPhone → Xogot) and first launch |
| D-02 | Mobile renderer visual pass: facades/emission night, rain, fog, sky lerp, shadows, glow |
| D-03 | 60 FPS target + thermals in dense districts (Neon Mile night + rain worst case) |
| D-04 | Touch ergonomics: stick size/position, pad reachability one-handed, sensitivity defaults |
| D-05 | Audio mix on iPhone speakers/AirPods; bus balance; vox blip legibility |
| D-06 | Save persistence across app suspension/kill (user:// container) |
| D-07 | `sensor_landscape` orientation behavior + safe-area insets on notched devices |
| D-08 | Memory ceiling with 12 traffic + 26 peds + interior + rain particles |

## Explicitly out of scope (by design, recorded)

Full voice acting; photoreal assets; multiplayer; navmesh pathfinding;
network streaming; C#/native addons (XOGOT constraint).
