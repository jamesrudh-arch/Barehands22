# LEVERAGE — Vision & Escalation Charter

> The user's directive, captured verbatim in intent, plus the design contract
> every system must honor. LEVERAGE is an original neon-noir crime epic —
> its characters, city, and story are its own. Referenced games are
> *quality bars*, never templates to copy.

## The mandate

Mobile-playable, third-person, open-world crime game that is **not**:

- a basic shooting game,
- a walking simulator,
- a bundle of disconnected features.

Every system must touch every other: fighting feeds progression, progression
feeds difficulty, difficulty feeds the story's stakes, the city reacts to all
of it.

## Quality bars (inspiration → what it means here)

| Reference | Bar | LEVERAGE answer |
|---|---|---|
| Sleeping Dogs / Sifu | Melee depth: counters, grappling, throws, ground combat, environmental takedowns, finishers, unlockable techniques | 5 styles × 5-rank mastery ladders that unlock real moves (haymaker, axe kick, suplex, ground pound, flurry, executioner…), parry→counter window, ground finishers, environmental slams, stealth takedowns |
| Max Payne 3 | Gunplay weight | Focus (bullet-time) meter, per-weapon recoil climb patterns, soft cover, suppressors changing crime reporting |
| Sims 4 | NPCs live schedules | Time-of-day day parts (commute_am/work/commute_pm/nightlife/night), crowd rhythms by hour+district+weather, chat idles |
| Hitman | Awareness & disguises | Guard vision cones → suspicion meter → search last-known → alarm; body discovery; outfit disguises with faction tags (blatant acts burn them) |
| Ghost Recon | Gear customization | 6 attachments across 5 slots, per-weapon fitted loadouts, gunsmith MODS bench, persisted in saves |
| — | Living pursuit | 3★ PIT maneuvers, 4★ spike strips (tyres shred, car limps), LOS-break search loops, dispatch scaling with threat |

## Hard rules from the user

1. **Difficulty must increase as the game/story progresses.** No menu
   slider: threat is derived from story completion + player level, with a
   small rubber-band relief after repeated deaths (`scripts/core/difficulty.gd`).
2. **Never cap amounts by previously stated numbers.** Enemy counts, police
   units, crowds, traffic all scale upward with threat. Mobile performance is
   protected by *culling radii and streaming*, not tiny hard caps.
3. **Originality.** Cinder City, Eli Vane, the Halcyon/Kiln Row/Syndicate
   power triangle are original. Do not import named characters, plots, or
   mechanics implementations from any referenced title.

## Escalation math (Difficulty autoload)

```
threat = clamp(story/12 × 0.75 + (level−1)/14 × 0.35 − death_relief, 0, 1.6)
enemy HP   ×(1 + 1.3·t)      enemy damage ×(1 + 0.9·t)
gun accuracy +0.16·t         counts ×(1 + 0.8·t)  (never below authored base)
police cap  4 + 12·t         dispatch  wanted + 3·t
peds 26→40+, traffic 12→20+, fight purse ×(1 + 0.6·t)
late-game thugs roll weapons/armor (loadout_roll)
```

## Progression spine (Progression autoload)

- XP from missions (`rewards.xp` in missions.json), KOs, takedowns.
- Levels raise max HP/stamina/damage; per-style mastery (rank 1–5) grows by
  *using that style in real fights* — no menu grinding.
- Ranks unlock moves the combat controller already understands + passives
  (extended combos, throw damage, counter window, stagger resist, reloads).
- HUD shows LV / XP bar / current style mastery; FOCUS bar appears with guns.

## Verification discipline

No claim of TESTED without runtime evidence. Headless harness
(`tests/harness.gd`) must stay green after every block; device (XOGOT/iPhone)
verification remains the open item W8.
