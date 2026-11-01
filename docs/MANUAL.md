# DAWG Manual — v1.2.0-beta

DAWG was called DAWS until 1.2.0. A mission set up for the old name keeps working: `DAWS_CONFIG`, `DAWS ...` groups, `DAWS BORDER` zones, the `DAWS_LAUNCH` / `DAWS_PAUSE` flags and a `DAWS_BORDERS_<MAP>` file are all read, the counters are written under both names, and the Lua global `DAWS` is the same table as `DAWG`. `legacy_names = false` in the config switches that off.

1. [How a probe plays out](#1-how-a-probe-plays-out)
2. [Installing](#2-installing)
3. [Setup without Lua (Mission Editor)](#3-setup-without-lua-mission-editor)
4. [Mission Editor flags](#4-mission-editor-flags)
5. [Pilots (personalities)](#5-pilots-personalities)
6. [Close passes (the show)](#6-close-passes-the-show)
7. [The config file](#7-the-config-file)
8. [Scripting API](#8-scripting-api)
9. [For the defending side](#9-for-the-defending-side)
10. [Logs and troubleshooting](#10-logs-and-troubleshooting)

---

## 1. How a probe plays out

```
LAUNCH ─► TRANSIT ─► PROBE ──(nobody comes)──► laps closer ─► goes home (lane remembers: next one starts deeper)
                       │
                  (intercepted: a defending fighter inside 2 NM, same altitude ±1000 m, for 10 s)
                       ▼
                   SHADOWED ─► by-the-book / tester: complies, goes home
                       │
                       ▼
                     SHOW ─► passes on the interceptor ─► showboat: goes home
                       │                                  hothead: STUBBORN, back to his probe track
                       ▼                                           until escorted ~150 s
                    COMPLY ─► escorted out past 30 NM = ESCORTED_OUT   (nobody with him = WITHDREW)
                       └─► left alone while leaving? may TURN BACK (tester always, hothead sometimes)
```

- **Response time.** DAWG times from the probe starting to the first defending fighter coming within 20 NM. It's in the log and in Status.
- **Lane memory.** A probe nobody answered raises that lane's pressure by one step, up to `max_depth`. The next probe there starts `step_nm` (4 NM) closer. A response within 5 minutes followed by an escort out lowers it again.
- **The floor.** No probe ever gets closer than `floor_nm` (2 NM) to a border, however deep it pushes.
- **Pairs.** Lead and wingman spawn as separate single-ship groups, 45 s apart on the runway. The wingman flies formation on the lead, and during a show he hangs back, high, as cover.
- **Over land.** On a lane whose leg runs over land, nobody crosses into anyone's airspace. The defender shadows from his own side, so the ID and escort radii widen to 15 NM, and there are no shows over land.
- **If you shoot.** Any shot or hit on a probe and he breaks off and runs for home at speed (`FIRED_ON`).

## 2. Installing

DAWG is a mission script. Nothing goes in your DCS install, and multiplayer clients need nothing.

Mission Editor → **Triggers**:

| Trigger | Condition | Action |
|---|---|---|
| ONCE | TIME MORE 1 | DO SCRIPT FILE `DAWG_borders_caucasus.lua` *(optional, Caucasus only)* |
| ONCE | TIME MORE 2 | DO SCRIPT FILE `your_config.lua` *(optional)* |
| ONCE | TIME MORE 3 | DO SCRIPT FILE `DAWG.lua` |

Use **DO SCRIPT FILE**, not DO SCRIPT with pasted text. DAWG doesn't need `io`, `os` or `lfs`, so leave `MissionScripting.lua` alone.

## 3. Setup without Lua (Mission Editor)

### Templates: who flies the probes

Templates are **late-activated** groups of the probing side whose name starts with **`DAWG`**. DAWG copies the first unit, so a single ship is enough. It spawns as a single or a pair, at random, unless tagged.

- **Start:** *Takeoff from runway* at the home field. They take off, probe and land back there. Air starts work too, as mid-transit: name their landing field with `home =` in a config, or they fly back the way they came, 60 NM, and are cleaned up.
- **Loadout:** anything. Weapons stay held. For the **fuel dump**, put a **Smoke Generator – white** on a pylon. The Su-27, Su-33, J-11A, MiG-29A/S/G, Su-25 and L-39 offer it, and DAWG detects it from the payload. Types without one, like the MiG-31, never fly the fuel-dump pass.
- **Cruise:** taken from the template's 2nd waypoint (altitude and speed) if it has one, otherwise 7,000 m at 230 m/s.
- **Big jets** (Tu-95/142, Tu-22M3, Tu-160, A-50, Il-76/78, An-26, Su-24MR) probe but never do shows.

Tags in the group name:

| Tag | Effect |
|---|---|
| `#book` `#showboat` `#hothead` `#tester` `#<yours>` | Always this pilot. |
| `#nostunts` | Never does a show. |
| `#smoke` | Treat as having a smoke pod. |
| `#single` / `#pair` | Flight size. |
| `@GAGRA` `@POTI` … | Flies only these lanes. Without any `@`, he flies every lane. |

Example: `DAWG Su-27 Sochi #hothead @GAGRA`.

### Lanes: where they probe

A lane is any **late-activated** group (plane is easiest) named **`DAWG LANE <NAME>`**. It's never spawned; it only draws the leg.

- Its **waypoints are the probe leg**: two or more points, **parallel to the border and outside it**. A good starting depth is 10–15 NM off. DAWG pushes it closer on its own.
- DAWG works out which way the border is (to push the leg toward it), and whether the lane is over land.
- Tags: `#land` / `#sea` override the terrain check. `#hothead` etc. fix the pilot for the whole lane.
- The lane name is uppercased: `DAWG LANE Gagra` becomes lane `GAGRA`, with flag `DAWG_LAUNCH_GAGRA`.

The log warns (`LANE_WARN`) if a leg point sits inside the floor.

### Borders: what they won't cross

- **Caucasus:** load `DAWG_borders_caucasus.lua` and the real borders are used automatically. That covers Georgia (de jure, so Abkhazia and South Ossetia count as Georgia) and its 12 NM territorial sea, Turkey and its 12 NM Black Sea strip, Armenia and Azerbaijan.
- **Any map:** draw **polygon trigger zones** (or circles) named **`DAWG BORDER <anything>`**. Every one is a no-go area. Draw the sea strip as its own polygon.
- They add up. Built-in borders, zones and config borders all count.

## 4. Mission Editor flags

Flags are **named flags**: type the name into the ME flag field.

**DAWG watches these.** Set one above 0 to launch; DAWG sets it back to 0.

| Flag | Value | Effect |
|---|---|---|
| `DAWG_LAUNCH_<LANE>` | 1–n | Launch on that lane (spaces in the name become `_`). |
| `DAWG_LAUNCH` | 1–n | Launch on a random lane. |
| `DAWG_PAUSE` | 1 / 0 | Pause / resume **automatic** launches (flag launches still work). |

The value picks the pilot: **1** from the weights, **2** by-the-book, **3** showboat, **4** hothead, **5** tester, and **6+** your own personalities, in alphabetical order.

A quick no-Lua control panel: **ADD RADIO ITEM** "Hothead on GAGRA", flag `DAWG_LAUNCH_GAGRA`, value `4`.

**DAWG counts these up** (+1 each time):

| Flag | When |
|---|---|
| `DAWG_LAUNCHED` | A probe launched. |
| `DAWG_PROBE` | It reached its leg (the probe has begun). |
| `DAWG_INTERCEPT` | It was identified. |
| `DAWG_SHOW` | A show started. |
| `DAWG_FUEL_DUMP` | A fuel-dump pass. |
| `DAWG_ESCORTED_OUT` | Escorted out past `release_nm`. |
| `DAWG_WITHDREW` | Went home without an escort. |
| `DAWG_UNANSWERED` | A lap with nobody responding. |
| `DAWG_TURNBACK` | Turned back toward the border. |
| `DAWG_FIRED_ON` | A defender shot at or hit one. |
| `DAWG_SHOW_ABORT` | A show aborted (something got inside 50 m). |
| `DAWG_LOST` | A probe was lost (crashed or shot down). |

Example: **FLAG IS MORE** `DAWG_ESCORTED_OUT` 2 → **MESSAGE TO ALL** "Three escorted out — good work."

## 5. Pilots (personalities)

A probe with no fixed pilot draws one from `weights` (default book 45, showboat 30, hothead 15, tester 10).

| Field | by-the-book | showboat | hothead | tester |
|---|---|---|---|---|
| `depth` (steps closer to start) | 0 | 1 | 2 | 1 |
| `stunts` (passes) | 0 | 1–2 | 2–4 | 0 |
| `opens_with` | – | – | `fuel_dump` | – |
| `escort_need_s` (after his show) | 0 | 0 | 150 | 0 |
| `turnback` (chance) | 0 | 0.1 | 0.35 | 1.0 |
| `comply_s` (no-show pilots) | 20–60 | 10–30 | 0 | 10–20 |
| `obeys` (orders on Guard before he goes home, section 11) | 1 | 2 | 3 | 1 |

Changing one, or adding your own, takes a config file (section 7):

```lua
DAWG_CONFIG = {
  personalities = {
    hothead = { escort_need_s = 240 },
    cowboy  = { label = "cowboy", depth = 2, stunts = { 3, 3 }, opens_with = "sit_six",
                pool = { "sit_six", "canopy_pass", "nose_cross" }, escort_need_s = 60, turnback = 0.5 },
  },
  weights = { book = 40, showboat = 30, hothead = 10, tester = 10, cowboy = 10 },
}
```

## 6. Close passes (the show)

| Pass | What the defender sees |
|---|---|
| `wing_look` | Sits on your wing at ~200 m, looking you over. |
| `close_wing` | Tucks in to ~100 m. |
| `nose_cross` | Crosses your nose ~400 m ahead. |
| `fuel_dump` | Crosses ~260 m ahead, slightly high, **trailing white smoke** you fly through (needs a smoke pod). |
| `belly_check` | Slides underneath you at ~130 m. |
| `canopy_pass` | Passes ~150 m over your canopy. |
| `sit_six` | Sits in your six at ~450 m, gun range. He doesn't shoot. |

**Safety**, all automatic:

- **At load:** any pass position, **or straight path between two positions**, inside `min_sep_m` (100 m) of the target is rejected (`STUNT_REJECTED`). That includes your own passes.
- **In flight:** if a defending aircraft comes inside `abort_sep_m` (50 m) of either bandit, the show **aborts** and he breaks away for home.
- **Pauses:** the show pauses with the bandit out wide while the target turns harder than `max_turn_dps` (9°/s) or is below `min_agl_m` (1,500 m). It resumes once things are calm for 8 s.
- **Limits:** no shows within `show_border_nm` of a border, or over land lanes. Each show has a time budget.

**Formation.** The bandit is steered every second toward a point just ahead of his slot, at your speed plus a closing term. That works on any aircraft. DCS's own Follow task didn't hold across coalitions in testing, but `formation = "follow"` keeps it available.

**Your own pass** (offsets in metres from the target: `{ ahead, up, right }`, written for the right side and mirrored automatically):

```lua
stunts = {
  high_wing = { "%s is sitting high on your wing.",          -- the call (%s = "The Flanker")
                { pos = { 0, 80, 250 }, s = 30, say = true } },  -- step: slot, hold seconds, say the call here
}
```

Then add it to a personality's `pool`.

## 7. The config file

Optional. Copy **`DAWG_config_template.lua`**, uncomment what you want to change, and load it before `DAWG.lua`. Every option is listed there with its default. The most used ones:

| Option | Default | |
|---|---|---|
| `side` | `"red"` | The probing side. |
| `auto`, `first_s`, `interval_s`, `max_active` | true, 600, {900,1500}, 2 | Automatic launches. |
| `weights`, `personalities` | — | Section 5. |
| `templates`, `lanes`, `borders` | discovered | Give them in Lua instead of the ME (see `examples/DAWG_config_Caucasus.lua`). |
| `schedule` | — | `{ { at = 300, lane = "GAGRA", personality = "hothead", tag = "Act 1" }, { at = 1200, lane = "ROKI", every = {1800,2400} } }` |
| `floor_nm`, `step_nm`, `max_depth`, `max_laps` | 2, 4, 3, 3 | How close, how fast they push. |
| `intercept_nm`, `intercept_alt_m`, `intercept_s` | 2, 1000, 10 | What counts as an ID. |
| `escort_nm`, `escort_credit_s`, `release_nm` | 3, 60, 30 | What counts as an escort out. |
| `min_sep_m`, `abort_sep_m`, `min_agl_m` | 100, 50, 1500 | Show safety. |
| `msg_all` | false | Calls to everyone (spectator missions). |
| `awacs` | `"OVERLORD"` | Who makes the calls. |
| `roe` | 4 | Probing side's ROE: 4 = weapons hold, 3 = return fire. |
| `voice`, `voice_order_credit_s`, `voice_lines` | true, 30, — | Section 11 (needs DCS-ATC in the mission). |

When a config gives `templates` or `lanes`, those are used **instead of** discovery for that part. Borders always add up.

## 8. Scripting API

```lua
DAWG.launch{ lane = "GAGRA", template = "DAWG Su-27 Sochi", personality = "hothead", tag = "Act 1" }  -- all optional
DAWG.launch("GAGRA", nil, "tester")        -- positional form
DAWG.status()                              -- the Status message to the defending side
DAWG.pause(true) / DAWG.pause(false)       -- automatic launches
DAWG.setPersonality("showboat")            -- the next automatic launch
DAWG.addPersonality("cowboy", { ... })
DAWG.borderNm(point)                       -- NM from the nearest border (negative = inside)
DAWG.onEvent = function(kind, name, ...) end   -- every log event below
DAWG.onGuard(ev)                           -- what DCS-ATC calls with a fighter's hail or order on Guard (section 11)
DAWG.sorties, DAWG.lanes, DAWG.templates, DAWG.personalities, DAWG.stunts   -- live tables (read them)
```

A sortie (`DAWG.sorties[i]`) has `name`, `lane.name`, `pers`, `state`, `tag`, `tResponse`, `intercepted.by`, `escort[name] = seconds`, `lead` / `wing` (group names) and `depth`.

## 9. For the defending side

- **ID:** get inside 2 NM, at the same altitude ±1,000 m, for 10 s. Any fighter counts (player or AI). On land lanes it's 15 NM, shadowing from your own side.
- **Escort out:** stay within 3 NM of him (15 on land) until he's 30 NM from the border. You need 60 s of escort for the credit.
- **During a show:** fly straight and level; that's what keeps the passes tidy. Hard manoeuvring pauses the show. Don't chase him into a 50 m gap: he aborts.
- **AI defenders:** set their ROE to weapons hold, or they'll shoot the probes (a `FIRED_ON`, after which they run).
- **Probes' radio:** whatever frequency you give the templates.

## 10. Logs and troubleshooting

Every event goes to `Saved Games\DCS\Logs\dcs.log` as `DAWG|<mission seconds>|<EVENT>|...`. The events are:

`LOADED`, `BORDERS`, `LAUNCH`, `AIRBORNE`, `PROBE`, `RESPONSE`, `UNANSWERED`, `INTERCEPT`, `SHOW_START`, `SHOW_STEP`, `FUEL_DUMP`, `SHOW_PAUSE`, `SHOW_RESUME`, `SHOW_ABORT`, `SHOW_END`, `COMPLY`, `RESUME_PROBE`, `TURNBACK`, `ESCORTED_OUT`, `WITHDREW`, `FIRED_ON`, `LEAD_LOST`, `LOST`, `END`, `FLAG_LAUNCH`, `SPAWN_COUNTRY`, `PAUSE`, and with DCS-ATC `HAILED`, `ORDERED`, `VOICE` (section 11).

| You see | It means |
|---|---|
| `WARN\|no borders defined` | No borders file, zones or config borders. The probes have nothing to stay out of. |
| `WARN\|no lanes` / `no templates` | Check the names: `DAWG LANE …` / `DAWG …`, and **late activation** on templates. |
| `LANE_WARN\|… only x NM off the border` | Move that waypoint further out. |
| `SPAWN_COUNTRY\|… country 68 -> 0` | Fine. The template's country isn't on the probing side in the engine's own country table, so DAWG spawned as one that is. Without this, spawns can come out **neutral**. |
| `SPAWN_FAIL` | No country on the probing side could spawn it. Is the template on the right side? |
| `SHOW_STEP\|…\|timeout` | The bandit didn't reach that slot in 45 s. A few are normal. If every step times out, report it with the log. |
| `STUNT_REJECTED` | One of your passes comes inside `min_sep_m`. |
| Nothing at all | Is DAWG loaded **last**? Search the log for `[DAWG] loaded` and `Mission script error`. |

## 11. Voices on Guard (with DCS-ATC)

With the [DCS-ATC](https://github.com/ExpertFett/DCS-ATC) script in the same mission (and its SRS listener running on the server), the probes talk. The listener hears a fighter on Guard, 243.0, and the ATC hands the call to DAWG; the probe answers in the ATC's Russian voice, through his own radio, and his personality decides what he does. The ATC tasks nothing of DAWG's and DAWG tasks nothing of the ATC's: the pilot answers, DAWG flies him. Without the ATC in the mission nothing changes.

Inside 5 NM of him, on 243.0:

| You say | What happens |
|---|---|
| "Soviet fighter, this is the United States Navy, identify yourself" / "state your intentions" | He answers in character. Book: "...on a routine patrol in international airspace. State your intentions." Hothead: "You are very close. Keep your distance." Showboat: "We see you. Nice aircraft." |
| "Turn left heading two seven zero", "reverse course", "leave the area immediately" | An order. Book and tester turn for home at the first, showboat at the second, hothead at the third (`obeys`). Until then he refuses, in character. |
| "Follow me" | An order. Book, tester and showboat follow you out when they comply; the hothead never follows ("We do not follow American aircraft"), but it still counts. |
| "Land immediately" | Always refused. Still counts. |

He also talks unprompted: the hothead tells you to back off when you identify him, the showboat says "watch this" before his passes, "Enjoy the fuel" comes with the fuel dump, a shot at him gets "This will be reported", and a pilot who was talking to you says "we are turning for home now" when he goes.

Orders to a stubborn hothead count toward walking him out: each one is worth `voice_order_credit_s` (30 s) of escort.

```lua
DAWG_CONFIG = {
  voice = true,                      -- false: quiet even with the ATC present
  voice_order_credit_s = 30,
  voice_lines = {                    -- override any line: a string, a per-pilot table, a list (picked by how
    land = "Nyet, {you}.",           -- often he has been told) or false for silence. {you} {who} {type} are
    hail = { hothead = "{you}, {who} {type}. Go away." },   -- filled in: "American aircraft", "Soviet Air Force",
  },                                 -- "Su twenty seven"
  personalities = { hothead = { obeys = 5 } },
}
```

Line keys: `hail`, `hail_again`, `refuse`, `comply`, `follow`, `follow_refuse`, `land`, `leaving`, `leaving_now`, `taunt`, `show`, `fuel_dump`, `fired_on`. A pilot without a line of his own uses the by-the-book one; `taunt` and `show` have none, so only the hothead and the showboat say them.

Log events: `HAILED|<probe>|<fighter>`, `ORDERED|<probe>|<order>|<fighter>|x<n>`, `VOICE|<probe>|<line key>|<text>`, and `VOICE|on: the probes answer on Guard through the DCS-ATC` at load when the handshake worked. Load order doesn't matter: whichever script loads second finds the other.
