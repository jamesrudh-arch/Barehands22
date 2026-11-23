# LEVERAGE — Characters & Story

> **Everyone has leverage on you.** The story is a debt triangle: Family,
> Corporation, Crew — and one man who owes all three something different.

---

## 1. The 16 named characters (`data/characters.json`)

| ID | Name | Role | Faction | What they want from Eli |
|---|---|---|---|---|
| **eli** | Eli Vane | Protagonist, 27, dock loader, amateur boxer | — | (player) |
| **marcus** | Marcus Vane | Brother, 24, gambler with a system | family | Forgiveness — and 5,000 cr by Friday |
| **ruth** | Mama Ruth | Runs Ruth's Soul Food; raised both brothers after their mother died | family | The boys safe; the family name clean |
| **roz** | Roz | Ashfall Syndicate lieutenant, docks | crew | Quiet hands, fast backs; loyalty tests |
| **crane** | Silas Crowe | Crowe Credit / Halcyon Group "facilitator" | corp | The ledger back — and Eli on a leash |
| **vivian** | Vivian Crowe-Hale | Halcyon Group heir, PR-steel | corp | Her father's empire sanitized; uses Eli |
| **okoro** | Dr. Okoro | Clinic doctor, asks no questions | none | Supplies; patients kept alive |
| **bishop** | Bishop | Runs the shelter under Static-88's tower | none | Halcyon's secrets out of his basement |
| **tess** | Tess | Static-88 pirate radio host | none | The truth, on air, whatever it costs |
| **gunnar** | Gunnar | Crowe's enforcer; the hands that take Marcus | corp | Orders followed; respects strength |
| **nia** | Nia | Ruth's night-shift manager | family | The restaurant survives the week |
| **padre_sol** | Padre Sol | St. Ember's parish priest | none | Confessions; souls kept off the slab |
| **dex** | Dex | Garage owner, street-race organizer | crew | Good drivers, clean cars, faster times |
| **mags** | Mags | Gunsmith; hears everything through her counter | none | Ledger pages — they name her brother's killer |
| **crowe_jr** | Julian Crowe | Crowe's son, Yard 4 fight-night bookmaker | corp | A champion he controls |
| **argus** | Argus | Halcyon Tower head of security | corp | Order; zero breaches on his watch |

Relationships run −100..+100 (`WorldState.add_relationship`), moved by
choices, gifts, violence and job outcomes; ambient chat trees exist for
10 of them (phone CALLS app). NPCs remember deeds (`WorldState.remember`).

## 2. Factions

- **Family** (start +40): Kiln Row and the docks — Ruth's, the parish, the
  union tables. Rep rises with honest work, protection, church boxes.
- **Corporation** (start −10): Crowe Credit above, Halcyon Group behind.
  Rep rises with signed paper, recovered assets, silenced broadcasts.
- **Crew** (start 0): Ashfall Syndicate — Roz, Dex, the yards. Rep rises
  with moved cargo, won races, kept mouths shut.

Faction rep gates dialogue tones, shop prices flavour, and the ending
table: who shows up at the plaza depends on who you fed all week.

## 3. Three-act structure (12 story missions)

**Prologue night (Day 1, 21:30, rain).**
- **m01 Last Call** (tutorialised): Marcus comes home bleeding at Ruth's.
  Choice: give him your 400 cr or refuse. The alley cutscene **cs_kidnap**:
  Gunnar's crew takes Marcus — Friday, five thousand, or the harbour gets
  a story. Ruth steadies you. Flags: `story_act1`, `gave_marcus_money` /
  `refused_marcus`.

**Act 1 — the debt becomes real.**
- **m02 The Book**: Mags points at Crowe's ledger. Route choice (persistent):
  `route_crew` (Roz's work), `route_jobs` (legit grind), `route_shake`
  (shake down Julian's collectors, +1 wanted). Raise 1,500 cr any way.
  Buy Marcus's note location from Crowe's clerk.
- **m03 Berth 7** (requires `route_crew`): Night cargo run Berth 7 → Yard 4.
  Police sweep event mid-run. Choice: dump the cargo (crew −15) or run the
  blockade (crew +15, wanted 2). Pays 1,200.
- **m04 Crowe Credit**: Crane offers 4,000 on Crowe paper. Choice: sign
  (`signed_crowe`, corp +10, money) or refuse (`refused_crowe`, Marcus
  respects you). Flag `story_act2`.

**Act 2 — gathering leverage.**
- **m05 Static**: Tess calls (phone stage). At the Noir Lounge: choice to
  broadcast the debt truth (`truth_on_air`, wanted 1) or keep quiet for the
  exchange (`quiet_air`). Flag `knows_drive`.
- **m06 The Shelter**: Bishop's basement under the tower. Halcyon sweep
  event; hide-or-bluff choice. Search the shelter → **halcyon_drive**.
- **m07 Yard 4**: Fight night. Three staged bouts teaching the disciplines
  (brawler → grappler → heavy; style hints on HUD). Julian watches. Pays
  900, `yard4_champ`, fights_won +3.
- **m08 Halcyon Tower**: Plan with Tess (or Dex). **Stealth** infiltration
  (guards alarm on sight-line; alarms convert to combat). Search Argus's
  floor. Choice with the drive in hand. Fight out past 3 guards.
  Flag `story_act3`.
- **m09 The Exchange**: Refinery gate, **cs_exchange** cutscene. Crowe's
  gunmen (4) — the deal was never the deal. Marcus comes home.
  Flags `marcus_safe`, `truth_known`.

**Act 3 — everyone.**
- **m10 Smoke Line**: Alliance round — talk Gunnar (defection seeded),
  Roz, Okoro. Choice locks the finale approach (`finale_set`).
- **m11 The Leverage**: The plaza. **cs_finale**: Crowe asks what your
  leverage is worth; you answer with where the bodies are buried. Final
  fight (5 gunmen). `finale_done`.
- **m12 Everyone**: The overlook at dawn. **cs_ending**: three debts,
  three truths; the ledger is ash; the pen is yours. `game_complete` →
  credits card → menu.

## 4. Side jobs (8, repeatable flagged)

side_courier (Dex; timed van run garage→noodle row, 90 s, 350 cr) ·
side_race1/2 (quay & neon circuits, 2 laps vs 2 AI rivals, 800/1,200 cr,
races_won) · side_nightshift (Nia; escort 2 staff through the Mile) ·
side_dockwork (Gunnar; carry 8 crates to Berth 7) · side_fightclub (Yard
4 random-thug bouts, 400 cr) · side_ledger (Mags; collect 12 ledger pages
scattered in the Furnace, 1,000 cr + `ledger_half`) · side_favors (Ruth;
collect 20 favor tokens in Kiln Row, 600 cr, family +10).

## 5. Choice → consequence map (examples, all persisted as flags/rep)

| Choice | Immediate | Later consequence |
|---|---|---|
| Give Marcus 400 (m01) | −400 cr, marcus +15, family +5 | Marcus references it in m09; Ruth's chat warmer |
| Refuse Marcus (m01) | marcus −10 | He gambles again — harder exchange in m09 flavour |
| route_shake (m02) | wanted +1 | Police sweep events weight up; Roz respects, Ruth disappointed |
| Sign Crowe paper (m04) | +4,000, corp +10 | Vivian opens country club side dialogue; m11 has corp muscle at plaza |
| truth_on_air (m05) | wanted +1, family +10 | Tess becomes ally in m10; Static-88 news quotes you |
| Dump cargo (m03) | crew −15 | Roz's job offers dry up until rep recovers |
| Alarm in tower (m08) | stealth → combat | Argus remembers; halcyon guards hostile on re-entry |

## 6. Dialogue system

49 trees in `data/dialogue.json`: mission scenes (linear + choice nodes
with effects), per-character ambient chats (`chat_*`), phone calls
(`call_*`), shop keeper greetings (`shop_*`). Format: `{start, nodes:{id:
{spk, text, next|opts}}}`; choice effects (money/faction/rel/flag/wanted/
item) applied by DialogueUI on pick. Lines are voiced with stylized bark
blips + subtitles (toggle). Barks (fear/combat/gunshots/greet/city/rain/
night) come from `data/news.json` bark pools so crowd reaction dialogue is
data-driven too.
