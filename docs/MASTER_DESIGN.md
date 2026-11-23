# LEVERAGE — Master Game Design Document

> **Everyone has leverage on you.**

Third-person open-world crime-action drama. Godot 4.7, Mobile renderer,
target device: iPhone via XOGOT. Single-player, offline, touch-first.

---

## 1. Concept

Eli Vane, 27, dock loader, amateur boxer. His brother Marcus gambles away
money he does not have — 5,000 credits owed to Silas Crowe's loan operation
by Friday, enforced by the Halcyon Group's "asset recovery" division. Marcus
is taken as collateral. Eli has six days, no money, and a city where every
faction — the **Family** (dockside tradition), the **Corporation** (Halcyon
Group / Crowe Credit), and the **Crew** (Ashfall Syndicate) — already owns a
piece of everyone. The player's leverage is the only thing they can make.

**Fantasy:** not the gangster with the most guns — the person who understands
what everyone needs, and trades it. Combat, driving, stealth, conversations
and choices are all currencies.

**Tone:** rain-slick industrial noir, warm human moments, procedural radio,
a city that keeps score.

## 2. Pillars

1. **The city keeps score.** Crimes raise wanted levels; witnesses call it
   in; factions remember; NPCs react to gunfire and fights; news headlines
   are generated from the player's actual deeds.
2. **Fists tell a story.** Five melee disciplines that genuinely differ
   (see §5). Eli is a fighter first; guns are loud, criminal, and costly.
3. **Everyone has leverage.** Every major character wants something; every
   choice trades one debt for another. No purely "good" endings.
4. **Built for glass.** iPhone-first: touch controls are the primary scheme,
   sessions are short, the HUD is legible at arm's length, and simulation
   scales down aggressively with distance (LOD).

## 3. Structure

- **Three acts + prologue night.** Act 1: the debt becomes real (m01–m04).
  Act 2: gathering leverage — docks, Static-88, the shelter, Yard 4 fight
  night, Halcyon Tower, the exchange (m05–m09). Act 3: the finale — smoke
  line alliances, the plaza, everyone (m10–m12).
- **20 missions** total: 12 story + 8 side jobs (courier, 2 street races,
  night shift escort, dockwork, fight club, ledger pages, favors).
- **Meaningful choices** with persistent flags: give Marcus the money or
  refuse; work for the Crew, legit, or shake down collectors; sign Crowe's
  paper or refuse; broadcast the truth or keep quiet; dump cargo or run the
  blockade. Choices gate missions (`requires_flag`), alter faction rep,
  alter relationships, and steer the ending cutscene.

## 4. Core loops

**Minute-to-minute:** move/observe → interact (B) → conflict (melee/gun/
vehicle) → heat (wanted/witnesses) → cool off or outrun → spend/upgrade.

**Session:** accept job (phone/Jobs app or story trigger) → objective chain
(HUD + minimap marker) → staged gameplay (goto/talk/choice/combat/drive/
race/escort/stealth/search/carry/collect) → reward (credits/rep/items/
flags) → autosave.

**Meta:** faction reputation (family/corp/crew) + 16 character
relationships + discovered POIs + owned weapons/outfits/vehicles + news
feed the player authored.

## 5. Combat design (exact mapping, authoritative)

| Button | Action | Notes |
|---|---|---|
| **X** | **PUNCH** | Combo chain jab→cross→hook; with melee weapon: swings/stab |
| **Y** | **HEAVY ATTACK** | Slow, high damage, stagger; weapon: vertical swing |
| **A** | **KICK** | kick_r/teep alternates; knockback tool |
| **B** | **DODGE** | Directional roll with i-frames; **outside combat B = contextual INTERACT** |

Plus: block/parry (hold BLK; parry window <0.18 s → clang + attacker
stagger), lock-on (cycles hostiles <25 m), aim/fire/reload for guns.

**Five disciplines** (`data/combat_styles.json`, cycle with STY):

1. **Brawler** — balanced, fast chains, medium damage, head-bob sway stance.
2. **Kickboxing** — long reach kicks, teep creates space, strong vs groups.
3. **Grappling** — shorter reach, throw (heavy) does massive damage +
   knockdown, best 1v1.
4. **Drunken** — unpredictable sway, dodge rolls further, hit windows
   shifted; trades defense for chaos.
5. **Weapon** — melee weapon focus (crowbar/bat/pipe/knife/machete) with
   per-weapon reach/damage/speed from `data/weapons.json`.

Stamina gates attacks and sprint; armor (jacket/vest/plate) reduces damage
and slightly slows; knockdown above 55 stagger; death → clinic respawn fee.

## 6. Vehicles

8 vehicle definitions (sedan, muscle, sports, van, truck, taxi, bike,
police). VehicleBody3D physics: steering/traction/suspension per class,
engine audio pitched by speed, headlights/taillights by night+weather,
crash detection (velocity-delta), damage → smoke, horns, police lightbar +
siren. Enter/exit anywhere near a car (CAR button within 3.2 m). Traffic AI
follows 109 per-block lane loops with obstacle raycasts and speed keeping;
police cruisers pursue at wanted ≥1, roadblocks at ≥3, arrest on contact
when on foot.

## 7. Living city

- **6 districts** (Kiln Row, Ashfall Docks, The Furnace, Neon Mile,
  Slagworks, Crown Heights) built as merged per-district meshes with
  trimesh collision; ~25 pedestrian archetypes with routines (commute,
  work, jog, courier, stumble, tourist, guard, vendor, busker) spawned by
  district density; 16 named characters placeable anywhere.
- **Simulation LOD:** NPCs tick at 60 Hz <25 m, 20 Hz <60 m, 5 Hz beyond;
  freeze >140 m. Night lighting uses a pool of 28 omni lights assigned to
  the nearest lamps; building windows switch to emissive facades at night.
- **Weather:** clear/overcast/rain/fog with wetness drift, rain particles
  parented to camera, thunder SFX, ambient loops (rain/traffic/crowd).
- **Day/night:** 24 h clock (compressed), sun angle/color/energy driven by
  hour, sky gradient lerped, fog at night, district ambience + exploration
  music routing, radio news ticker.
- **12 world events** (disputes, fights, muggings, collisions, sweeps,
  steam vents, fire barrels, crowds, ambulances, radio cars, shakedowns,
  stray cat) staged with actors near the player on a timer.
- **Interiors:** 19 procedural room definitions (apartment, Ruth's, church,
  clinic, market, Berth 7, haulage, warehouse, lobby, precinct, Crowe
  office, pawn, lounge, club, casino, shelter, gunsmith, garage, fight
  club) generated on entry, one at a time; exit returns the player exactly.

## 8. Story & characters

16 named characters (see `docs/CHARACTERS_AND_STORY.md`): Eli, Marcus,
Mama Ruth, Roz, Silas Crowe ("Crane"), Vivian, Okoro, Bishop, Tess,
Gunnar, Nia, Padre Sol, Dex, Mags, Julian Crowe Jr., Argus. 49 dialogue
trees (mission scenes, per-character ambient chats, phone calls, shop
keeper greetings, choice nodes). Voices are stylized bark-blips (60 vox
samples) — the audio identity is "radio noir", not full VO.

**Endings** driven by flags: truth broadcast vs quiet deal, family vs corp
vs crew alignment, who was betrayed. cs_ending closes with Ruth's line:
"You came back. That's the only leverage that ever mattered, baby."

## 9. Economy & progression

Credits from jobs/shops/selling. Shops: Ruth's (food/meds), clinic (meds +
full treatment service), market (supplies + outfits), Pawn 24H (weapons,
buys back), Mags Gunsmith (full arsenal + armor), Dex's Garage (vehicle
dealership). Inventory: consumables (bandage/medkit/energy drink),
lockpicks, ammo (4 calibers), collectibles (ledger pages ×12, favor tokens
×20). Outfits change appearance on respawn. No XP/levels — progression is
gear, styles, reputation, and story flags.

## 10. Phone (diegetic menu)

9 apps: **MAP** (live top-down city draw: districts, roads, POIs, job
marker, player arrow, wanted stars), **JOBS** (accept story/side),
**RADIO** (4 stations: Noir FM, Static 88, Furnace Classic, off),
**CALLS** (10 contacts with ambient chat trees + incoming mission calls),
**BAG** (weapons/armor/items equip+use), **MSGS**, **SAVE** (3 slots +
autosave slot 1), **SETTINGS** (volumes, sensitivity, touch scale,
subtitles, shake, invert-Y, quality), **NEWS** (player-authored headlines).

## 11. Presentation flow

D'Youngs Games splash → title (logo + tagline + tap-to-continue) → content
notice (advisory + fiction disclaimer) → main menu (New/Continue/Settings/
Credits) → city boots → opening cinematic (cs_kidnap after m01 build-up) →
tutorialised entry (8 contextual coach hints) → free roam.

## 12. Difficulty & accessibility

No difficulty slider — the city is the difficulty: wanted levels, witness
reports, enemy styles (light/grappler/heavy/gunman/guard), and economics
(fines on bust/death = 10% cash). Accessibility: subtitles toggle, camera
shake toggle, invert-Y, touch scale slider, color-coded minimap markers,
large tap targets (≥44 px), no hover-only UI.

## 13. Out of scope (honest)

No multiplayer, no full voice acting (bark-blip vox only), no photoreal
assets (deliberate procedural art direction), no in-app purchases, no
streaming from network (fully offline), no C#/native addons (XOGOT
constraint: GDScript only on iPhone).
