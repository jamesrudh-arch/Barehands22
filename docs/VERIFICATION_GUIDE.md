# LEVERAGE — Verification Guide

How to run the game, what to check, and how to verify it honestly on
iPhone/XOGOT. Sandbox proofs are reproducible with the commands in §A;
device verification is §B–§E. **A desktop/headless pass is never iPhone
proof** — the status vocabulary lives in `docs/TRACEABILITY.md`.

---

## A. Reproduce the sandbox verification (any Linux/macOS/Windows box)

1. **Get an engine**: Godot 4.7.2-stable (editor or template). This repo
   was built and tested against a from-source editor build
   (`scons platform=linuxbsd target=editor dev_build=no x11=no wayland=no`).
2. **Import**: `godot --headless --path <repo> --import` → expect 333
   assets, no errors.
3. **Harness (logic suite, 21 checks)**:
   `godot --headless --path <repo> -s res://tests/harness.gd`
   Expect: `HARNESS: DONE — checks=21 fails=0`, exit code 0.
4. **Flow probe**: run the project normally (`godot --path <repo>`):
   boot splash (~3.4 s) → title → tap → content notice → menu → NEW GAME
   → city loads (~1–3 s) → prologue objective "Get to Mama Ruth's…".
5. **Play checks (desktop QA)**: WASD + mouse-drag look; J/K/L/I or
   gamepad X/Y/A/B for punch/heavy/kick/dodge; E or walk-to-marker + I/B
   to interact; enter any traffic car; open phone (Tab) → MAP/JOBS/RADIO.

## B. Device visual pass (iPhone via XOGOT — first import)

1. Transfer this project folder to the iPhone (Files app / iCloud Drive /
   Working Copy) into **On My iPhone → Xogot** (per official XOGOT docs).
2. Open in XOGOT; let it import (first import is longer).
3. Check in order, noting PASS/FAIL each:
   - Boot splash → title → notice → menu render (fonts legible, gold on
     black, no missing-texture magenta).
   - NEW GAME: city appears; **rain particles visible**; sky is night
     gradient; street lamps lit; building windows glow (facade emission).
   - Player character visible third-person: face/jacket/hair distinct,
   feet on ground (no sinking/floating), walk cycle reads.
   - Night→dawn transition (wait or advance via save): sun color/sky lerp.
   - Neon Mile at night: signage/neon materials, glass facades.
   - Interior (enter Ruth's): warm light, furniture, no z-fighting.
4. Any FAIL → capture screenshot + district/time/weather into
   `docs/TEST_REPORTS.md` as a device row.

## C. Touch ergonomics pass

1. One-handed reach: A/B/X/Y pad thumb-reachable; RUN/CRCH/BLK/LOCK/STY
   not colliding; PHONE/MAP/II top-right.
2. Virtual stick: appears at first left-side touch, knob clamps, releases
   clean (player stops immediately — no drift).
3. Camera drag: right-side drag rotates smoothly; sensitivity slider
   (phone → SETTINGS) changes it live; invert-Y works.
4. Multitouch: stick + camera + fire simultaneously (get in a gun fight
   while moving).
5. B-context: walk to a door → "[B] Enter …" prompt → tap B enters;
   in combat B dodges.
6. Deadzone check: tap (no drag) anywhere should not move camera/stick.
7. Adjust with SETTINGS → "Touch controls size" (0.7–1.5×).

## D. Systems spot-checks on device

| System | Check | Expect |
|---|---|---|
| Combat styles | STY cycles 5 styles | Stance/animation visibly changes; HUD style name updates |
| Wanted | Steal a car with a cop near | Stars rise; siren audio; cruiser pursues; ≥3 roadblock cars |
| Arrest | Let cops touch you on foot ~2 s | BUSTED toast, 10% fine, precinct spawn |
| Death | Lose a Yard 4 fight | Clinic spawn, fee toast |
| Missions | Phone → JOBS → accept side_courier | Objective + minimap marker; timed drive works |
| Shops | Pawn 24H: sell an item | Credits rise, inventory drops |
| Radio | In any car: RADIO button | Station cycles; music changes; "Radio off" works |
| Saves | Pause → SAVE GAME; kill app; relaunch → CONTINUE slot 1 | Position/money/mission restored |
| Weather | Play across ~15 real minutes | Weather rolls; rain starts/stops with audio + particles |

## E. Performance gate (device)

- Target 60 FPS; acceptable floor 30 FPS in worst case (Neon Mile night +
  rain + 12 traffic + pursuit).
- If below: phone → SETTINGS → Quality Low (shrinks shadow map + particle
  loads), and record the district/FPS in TEST_REPORTS.
- Thermals: 20-minute session should not throttle below the floor.
- Memory: no OOM kill with interior + rain + full crowd (XOGOT exposes no
  profiler; use iOS Settings → XOGOT memory indication or behavior).

## F. Reporting results back

Append a dated device block to `docs/TEST_REPORTS.md`:
`## T-1x Device pass (iPhone model, iOS version, XOGOT build) — date`
with per-item PASS/FAIL and screenshots archived outside git (they are
large; keep paths referenced). Update `docs/KNOWN_DEFECTS.md` D-items as
they close, and flip TRACEABILITY rows from DEVICE-ONLY to VERIFIED only
with that evidence attached.
