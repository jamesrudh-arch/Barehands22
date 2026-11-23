# LEVERAGE — Authoritative Control Map

One input map (`project.godot [input]`) drives keyboard, gamepad and touch.
Touch buttons call `Input.action_press/release` on **the same actions** —
there is no parallel touch-only code path, so bindings can never desync.

**Combat mapping is contractual:** X = PUNCH, Y = HEAVY ATTACK,
A = KICK, B = DODGE — and B doubles as contextual INTERACT outside combat.

---

## 1. Full action table

| Action | Meaning | Keyboard | Gamepad | Touch (iPhone landscape) |
|---|---|---|---|---|
| `move_left/right/forward/back` | Movement | A / D / W / S | Left stick | Virtual stick (left 45% of screen, appears where you touch) |
| `sprint` | Sprint (hold; drains stamina) | Shift | L3/LS press | **RUN** button (hold) |
| `crouch` | Crouch (hold) | Ctrl | B (while idle) | **CRCH** button (hold) |
| `jump` | Jump | Space | — | (stick up-flick not bound; Space on BT keyboard) |
| **`punch`** | **X — PUNCH** (combo jab→cross→hook; weapon swings/stab) | J / LMB | **X** | **X** pad button (bottom-right cluster, above A) |
| **`heavy_attack`** | **Y — HEAVY ATTACK** (stagger; weapon vertical) | K | **Y** | **Y** pad button (upper-left of cluster) |
| **`kick`** | **A — KICK** (teep alternates; knockback) | L | **A** | **A** pad button (bottom-right corner) |
| **`dodge` / `interact`** | **B — DODGE** (directional roll) / **INTERACT** outside combat | I / RMB | **B** | **B** pad button (left of A); interact prompt "[B]" appears on targets |
| `block` | Guard (hold; <0.18 s = parry) | Q | LB | **BLK** button (hold) |
| `aim` | Gun aim (hold) | R | LT | **AIM** button (visible with gun) |
| `fire` | Gun fire (hold = auto) | F | RT | **FIRE** button (visible with gun) |
| `reload` | Reload | R | X-hold | **RLD** button |
| `lock_on` | Cycle hostile targets (<25 m) | T | RS press | **LOCK** button |
| `style_next` | Cycle fighting style | G | D-pad up | **STY** button |
| `weapon_next/prev` | Cycle owned weapons | 1..5 / wheel | D-pad left/right | BAG app (phone) |
| `vehicle_enter` | Enter/exit vehicle (<3.2 m) | E | Y-hold | **CAR** button |
| `vehicle_brake` | Brake (in vehicle) | S | X | **BRK** button (in vehicle) |
| `vehicle_handbrake` | Handbrake | Space | B | BRK double-purpose (hold at speed) |
| `horn` | Horn | H | D-pad down | **HORN** button |
| `phone` | Open/close phone | Tab | Start/Menu | **PHONE** top-right |
| `map` | Jump to phone MAP app | M | — | **MAP** top-right |
| `pause` | Pause menu | Esc | Options | **II** top-right |
| `ui_accept/ui_cancel` | Menu confirm/back | Enter / Esc | A / B | tap buttons |

## 2. Touch layout (landscape iPhone)

```
┌──────────────────────────────────────────────────────────────┐
│ HP/ARM/STA bars        CLOCK • WEATHER • DAY        MONEY     │
│ [minimap]              DISTRICT                    ★★★★★     │
│  objective…                                    [PHONE][MAP][II]│
│                                                              │
│        (drag anywhere right = camera)                        │
│                                                              │
│   (touch left 45% =                            [RADIO in veh]│
│    floating stick)                              [STY]        │
│                                                 [LOCK]       │
│                                     [AIM]       [BLK]        │
│            [RUN]                  [FIRE]   [Y]               │
│            [CRCH]     [CAR/BRK]         [X]  [B]             │
│                                  [HORN]      [A]             │
└──────────────────────────────────────────────────────────────┘
```

- Pad geometry mirrors the Xbox diamond: **A bottom-right, B left of A,
  X above A, Y above-left** — muscle memory transfers 1:1.
- All buttons ≥44 px (settings → "Touch controls size" scales 0.7–1.5×).
- Virtual stick is *floating* (appears at first touch in the left zone),
  knob clamps to 62 px radius; release re-centers and zeroes movement.
- Camera drag uses `Game.settings.sensitivity` (0.3–2.5) and honors
  invert-Y. Multi-touch: stick + camera + buttons simultaneously
  (tracked by touch index; mouse maps to indices 999 for desktop QA).
- No dead zones: stick has no inner deadzone (analog from 0), buttons are
  press-event based (`ACTION_MODE_BUTTON_PRESS`) so held actions
  (sprint/block/aim/fire) stay held without re-taps.

## 3. Context rules

- **B** resolves in order: combat dodge (if in combat or hostile within
  4 m) → interact (nearest `interact` group node <2.6 m: POI doors, NPCs,
  pickups, vehicle-enter fallback) → dodge-roll.
- **CAR** appears only when a vehicle is within 3.2 m or while driving
  (then it exits); **BRK/HORN/RADIO** only while driving; **AIM/FIRE/RLD**
  only with a gun equipped on foot; **X/Y/A/BLK/LOCK/STY/RUN/CRCH** hidden
  while driving (pad declutters).
- Dialogue/shop/phone/cutscene suppress gameplay input (`Game.cutscene_active`,
  `DialogueUI.is_open()`, `PhoneUI.open`, `ShopUI.open`); tap-to-advance
  drives dialogue; ESC/ui_cancel closes phone.

## 4. Non-negotiables (from requirements)

1. X=PUNCH, Y=HEAVY, A=KICK, B=DODGE — implemented exactly, everywhere.
2. B = contextual interact outside combat — implemented.
3. One authoritative input map — `project.godot`; touch injects into it.
4. No conflicts/dead zones between touch and map — verified: touch buttons
   are the only writers of virtual presses; stick overrides movement axes
   only while touched (`player.touch_move`).
