# LEVERAGE

> **Everyone has leverage on you.**

A third-person open-world crime-action drama set in **Cinder City**, built with
**Godot 4.7 (Mobile renderer)** for **XOGOT on iPhone**.

You play a man pulled into his brother's debt — kidnapping, loan sharks, a
corporate machine and a street crew all want something from the Vane family,
and everyone keeps score.

## Quick index

| Document | Purpose |
|---|---|
| `docs/DEVELOPMENT_STATE.md` | Current stage, done/remaining, blockers, exact next action |
| `docs/FINAL_REPORT.md` | Honest per-requirement delivery status |
| `docs/MASTER_DESIGN.md` | Master game design document |
| `docs/TECHNICAL_ARCHITECTURE.md` | Engine decisions, systems architecture, documented sources |
| `docs/ART_DIRECTION.md` | Visual identity: palette, materials, lighting, camera, characters |
| `docs/WORLD_DESIGN.md` | Cinder City districts, layout, POIs, streaming |
| `docs/CHARACTERS_AND_STORY.md` | 16 named characters, factions, three-act story, choices |
| `docs/CONTROLS.md` | Authoritative input map (gamepad / keyboard / iPhone touch) |
| `docs/ASSET_REGISTER.md` | Every asset, its source, and how it was produced |
| `docs/LICENSES.md` | Licence record for all third-party content |
| `docs/TRACEABILITY.md` | Requirement-by-requirement → implementation → test evidence |
| `docs/DECISION_LOG.md` | Technical decisions + official documentation sources |
| `docs/CHANGELOG.md` | Session-by-session change record |
| `docs/TEST_REPORTS.md` | Test commands, environments, results, limitations |
| `docs/KNOWN_DEFECTS.md` | Open defects and device-only items |
| `docs/VERIFICATION_GUIDE.md` | How to run, and how to verify on iPhone/XOGOT |

## Running the game

- Desktop QA: open this folder in Godot 4.7 and run (F5), or `godot --path . `
- iPhone: import this project folder into XOGOT (see `docs/VERIFICATION_GUIDE.md`)
- Touch controls are the primary scheme; keyboard/gamepad work for desktop QA.

## Repository layout

```
project.godot          engine config, autoloads, authoritative input map
scenes/                all .tscn scenes (boot, world, player, npc, vehicles, ui)
scripts/               all GDScript systems
data/                  game data as JSON (city, missions, dialogue, items, chars)
assets/                generated textures, audio, fonts, environment resources
tools/forge/           Python asset forge (original procedural textures & audio)
tests/                 headless validation harness + Python validators
docs/                  all documentation (see index above)
```

All art and audio in this project are **original, procedurally generated**
content produced by `tools/forge/` (see `docs/ASSET_REGISTER.md` and
`docs/LICENSES.md`). The only third-party redistributables are the DejaVu
fonts (Bitstream Vera licence, text in `docs/LICENSES.md`).
