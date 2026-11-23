# LEVERAGE — Known Defects & Open Items

Honest register. None of the below blocks the sandbox-verified core loop;
D-items are device verification, K-items are known code/content defects.

## Code / content defects (open)

| ID | Severity | Description | Impact | Plan |
|---|---|---|---|---|
| K-01 | Low | Traffic vehicles brake for obstacles but do **not read traffic-light state** (light cycle is visual only; `CityLife.traffic_green_at` exists but is unused) | Intersections feel lawless | Wire `_check_ahead` to also test `traffic_green_at` |
| K-02 | Low | Escort side job spawns VIPs with the first ped archetype (no dedicated `ped_nurse` in data) | Cosmetic mismatch | Add 1–2 VIP archetypes to peds.json |
| K-03 | Low | `MissionManager.apply_save` restarts an in-flight mission from stage 0 (stage-internal runtime state not persisted) | Mid-mission load loses stage progress, not the mission | Document or serialize `stage_i` + light rt fields |
| K-04 | Low | Outfit purchases apply on **respawn/reload** (humanoid rebuilt then), notified in-shop | Delayed cosmetic gratification | Rebuild humanoid on equip |
| K-05 | Cosmetic | Exit-time leak warnings under harness quit (7 resources / 2 RIDs) — queue_free-at-quit artifacts | None at runtime | Ignore; re-check on device builds |
| K-06 | Cosmetic | numpy uint8 overflow RuntimeWarning in forge facade() frame color (clamps) | Slight hue variance in one facade — reads as weathering | Accepted |
| K-07 | Cosmetic | forge_audio_lib pink-noise `_filter` is a no-op stub (white noise used where pink intended) | Two ambience loops brighter than spec | Accepted |
| K-08 | Medium | **Visuals never rendered** in sandbox (headless): material assignments, emission night look, sky gradient, rain particles, HUD layout are logic-verified only | Unknown visual defects possible | Device pass per VERIFICATION_GUIDE §B |
| K-09 | Medium | Touch controls unproven on glass: multitouch tracking is index-based and desktop-mouse-mapped (index 999); feel/deadzones untested | Possible ergonomic fixes needed | Device pass §C |
| K-10 | Low | Radio plays station tracks only while in a vehicle (`_radio_tick` gate); on-foot radio = district score | Design choice, but PHONE→RADIO on foot silently keeps district music | Show toast "tune in from a car" |
| K-11 | Low | `jump` action has no touch button (keyboard/gamepad only) | Jump unavailable on pure touch | Add JMP button or stick-flick |
| K-12 | Low | News templates with `{district}`/`{hour}` placeholders: only city.gd ticker substitutes; some pushes may show raw braces if a template sneaks through another path | Rare cosmetic | Centralize substitution in push_news |

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
