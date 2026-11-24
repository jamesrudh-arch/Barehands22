# LEVERAGE — Verification Guide

How to run the game, what to check, and how to verify it honestly on
iPhone/XOGOT. Sandbox proofs are reproducible with the commands in §A;
device verification is §B–§E. **A desktop/headless pass is never iPhone
proof** — the status vocabulary lives in `docs/TRACEABILITY.md`.

---

## A. Reproduce the sandbox verification (any Linux/macOS/Windows box)

1. **Get an engine**: Godot 4.7.2-stable (editor or template). This repo is
   built and tested against a from-source editor build; the canonical recipe is
   `bash tools/build_engine.sh`, which runs `scons -j2 platform=linuxbsd
   target=editor` (~45 min on 2 CPUs) after installing a venv with
   `gdtoolkit`, `scons` and `numpy`.
2. **Import**: `godot --headless --path <repo> --import` → expect **369**
   importable source assets (149 PNG, 198 WAV, 16 OGG, 6 TTF), no errors.
3. **Parse gate** (before trusting any harness result):
   `godot --headless --path <repo> --check-only --script <file.gd>` per changed
   file, grepping **only** `Parse Error`. Do not use bare `--check-only` as a
   gate: it also resolves identifiers and false-positives
   `Compile Error: Identifier not found: Db` on every script touching an
   autoload. `gdparse` alone is NOT sufficient — it cannot see identifier scope
   or a missing engine API, and one such error kills a whole autoload and
   cascades into hundreds of unrelated red checks (see AUDIT B11).
   **Run the import before the gate.** On a fresh engine build or after
   `rm -rf .godot/imported`, `--check-only` fails on `tests/harness.gd` with
   `Parse Error: Identifier "UiFit" not declared` — `class_name` globals are
   registered by the project scan, which has not happened yet.
   `godot --headless --path <repo> --import` first (≈10 s, 0 errors, and it is
   the step that actually applies the texture import params), then gate. The
   same file passes immediately afterwards, which is how you tell a stale
   `class_name` cache from a genuine error.
4. **Harness (logic suite, 585 checks)**:
   `godot --headless --path <repo> -s res://tests/harness.gd`
   Expect: `HARNESS: DONE — checks=585 fails=0`, exit code 0, and **0**
   `SCRIPT ERROR` lines. Three `^ERROR:` lines after the `DONE` line are
   expected — shutdown RID leaks (K-05), not failures.
   **The count must be identical across runs.** Re-run plain and once with
   `--verbose`: both must report 585. A count that moves means a guard skipped
   an assertion rather than the suite growing (K-21 was exactly this — 584
   plain, 583 verbose, from an `if` with no `else`).
   Judge the three leak lines by **type**, never by count: identical code has
   been observed at 15–18 resources and 16–26 `RendererSceneCull::Instance`
   RIDs depending on teardown ordering. A *new type* in that list is the signal
   (that is how C1 was caught); a shifted number is not.
5. **Flow probe**: run the project normally (`godot --path <repo>`):
   boot splash (~3.4 s) → title → tap → content notice → menu → NEW GAME
   → city loads (~1–3 s) → prologue objective "Get to Mama Ruth's…".
6. **Play checks (desktop QA)**: WASD + mouse-drag look; J/K/L/I or
   gamepad X/Y/A/B for punch/heavy/kick/dodge; E or walk-to-marker + I/B
   to interact; enter any traffic car; open phone (Tab) → MAP/JOBS/RADIO.

## B. Device visual pass (iPhone via XOGOT — first import)

**Requires XOGOT 1.7.2 or later** (first App Store release on the Godot 4.7
engine line; 1.7.12 at time of writing, which also raised the iOS memory limit
for larger projects — see D-27). An older XOGOT runs Godot 4.6 or 4.5 and will
warn that the project's `config/features` is newer than its engine.

NOTE (2026-11-23): XOGOT's iOS shell runs the project in PORTRAIT regardless of
`handheld/orientation`. The **current** XogotDocs say nothing at all about
orientation — there is no guidance to cite either way — so this remains an
empirical device observation and D-07 stays open. All code-built UI is
width-responsive since the K-13 fix (`scripts/ui/ui_fit.gd`), so portrait and
landscape both lay out correctly.
After any repo update, re-import the fresh copy in XOGOT (old imports cache).

1. Get the project onto the iPhone. Per `Getting Started.md` §2, either:
   - download the repository **as a zip directly from GitHub**, then in the
     Files app **tap the zip to decompress it** before opening it in XOGOT
     (XOGOT will not read the archive itself); or
   - use [Working Copy](https://workingcopyapp.com) against the Git remote.
2. In the **Files app**, navigate to the project folder, tap and hold it and
   choose **Copy**; then tap **On My iPhone** in the sidebar, open the **Xogot**
   folder, tap and hold in the empty area and choose **Paste**.
3. If XOGOT was already open, **restart it** — the docs note a newly imported
   project may not appear in the Project Manager until you do.
4. Open the project in XOGOT and let it import. **Expect the first import to be
   slow, and expect it to look like a hang**: 369 assets, and the 96 world
   textures are now VRAM-compressed with full mip chains (D-25), which is real
   encoding work on a phone. XOGOT's `faq.md` warns about precisely this —
   *"It can take a while to re-import assets for your project to the iPad, and
   one of Xogot's most visible limitation currently is that the progress
   indicators in the UI are not shown, which can be a little jarring when
   importing a large new project and Xogot not responding."* **Do not force-quit
   it.** It is a one-time cost per import, and it is the point of the change:
   seconds of import for ~130 MB of runtime VRAM.
   If scenes then fail to open with `Texture (binding: 0, index 0) is not a
   valid texture` / `Failed to create uniform set for batch`, that is the
   `faq.md` VRAM-format failure (D-28/K-17). This repo now sets both
   `rendering/textures/vram_compression/import_etc2_astc` and `import_s3tc_bptc`
   to `true`, so it should not happen — but the flags are restart-required
   (`GLOBAL_DEF_RST`), so if you ever change them you must **close and reopen
   the project** for the imports to re-run.
5. Confirm **Settings → Input Devices → Virtual Controller → Enable Controller**
   is **off**. `project.godot` now sets `input_devices/virtual_controller/enable=false`
   (D-26), so it should already be off; check anyway, because if it is on you
   will see XOGOT's gamepad overlay drawn on top of this game's own touch layer
   and both will be firing the same actions.
   While you are in Settings, also confirm **Display → Window → Scale Mode**
   reads **Fractional**, not XOGOT's "Auto" default, which its `faq.md` says can
   make a game "appear zoomed in or stretched" (D-29). `project.godot` sets it,
   so this is a confirmation, not a configuration step.
   Two further `faq.md` behaviours worth knowing before you blame the game:
   swiping up to close a running game **terminates XOGOT entirely** when iPad
   Multitasking is off (use the in-editor Stop button instead), and XOGOT works
   fully offline — only the Learning Center, the Asset Library and web sharing
   need a network.
6. Check in order, noting PASS/FAIL each:
   - Boot splash → title → notice → menu render (fonts legible, gold on
     black, no missing-texture magenta).
   - NEW GAME: city appears; **rain particles visible**; sky is night
     gradient; street lamps lit; building windows glow (facade emission).
   - Player character visible third-person: face/jacket/hair distinct,
   feet on ground (no sinking/floating), walk cycle reads.
   - Night→dawn transition (wait or advance via save): sun color/sky lerp.
   - Neon Mile at night: signage/neon materials, glass facades.
   - Interior (enter Ruth's): warm light, furniture, no z-fighting.
7. Any FAIL → capture screenshot + district/time/weather into
   `docs/TEST_REPORTS.md` as a device row.
8. **Texture check specific to D-25**: look at a long straight stretch of
   asphalt or a distant concrete facade. Before this wave those surfaces had no
   mipmaps at all, so they shimmer and crawl with aliasing as the camera moves.
   After, they should stay still and go smoothly blurry with distance. Also
   check a lit surface at a raking angle — normal maps imported without
   `compress/normal_map=1` light incorrectly.

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
  profiler; use iOS Settings → XOGOT memory indication or behavior). XOGOT
  1.7.12 raised the iOS memory limit (#3457), so test on the current build and
  record the XOGOT version with the result — a pass on 1.7.12 is not evidence
  about 1.7.2.
- VRAM: the texture set is now ~12 MB compressed rather than ~144 MB
  uncompressed (D-25). If this gate was ever failed on memory before, re-test
  before treating it as still failing.

## F. Reporting results back

Append a dated device block to `docs/TEST_REPORTS.md`:
`## T-1x Device pass (iPhone model, iOS version, XOGOT build) — date`
with per-item PASS/FAIL and screenshots archived outside git (they are
large; keep paths referenced). Update `docs/KNOWN_DEFECTS.md` D-items as
they close, and flip TRACEABILITY rows from DEVICE-ONLY to VERIFIED only
with that evidence attached.
