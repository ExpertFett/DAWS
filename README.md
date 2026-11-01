# DAWG — Dynamic Air Warfare Group

**v1.2.0-beta** · DCS World mission script · standalone (no MOOSE, no MIST) · multiplayer / dedicated-server safe · formerly DAWS (everything built for that name still works)

DAWG adds peacetime and crisis air activity to DCS missions. AI fighters launch from their own fields and **probe your border**. They fly along it, never cross it, and time how long you take to respond. When you intercept, each one reacts according to the pilot DAWG drew:

| Pilot | What he does |
|---|---|
| **By-the-book** | Complies once identified and goes home. |
| **Showboat** | Comes over and does a pass or two on you first. |
| **Hothead** | Dumps fuel across your windscreen, crosses your nose, checks your belly and sits in your six. Then he goes back to his probe track and won't leave until you walk him out. |
| **Tester** | Complies quickly, then turns back the moment nobody is watching him leave. |

If nobody answers a probe, it comes closer every lap. The lane **remembers** that, so the next probe there starts deeper. A quick intercept and escort pushes it back out.

Nobody shoots. The probing side is held to weapons hold. Close passes keep at least 100 m from you, and anything closer than 50 m aborts the show.

**They talk back.** With [DCS-ATC](https://github.com/ExpertFett/DCS-ATC) in the mission, hail a probe on Guard and he answers in Russian-accented English through his own radio. Tell him to leave, and his pilot decides how many times you have to say it.

**Download:** grab the zip from [Releases](https://github.com/ExpertFett/DAWG/releases). It has the script, the border data, the manual, and a Starter and a Demo mission.

## Quick start (no Lua)

1. Copy `DAWG.lua`, plus `DAWG_borders_caucasus.lua` if you're on the Caucasus map, somewhere you can pick them in the Mission Editor.
2. Add a trigger: **MISSION START → DO SCRIPT FILE** `DAWG_borders_caucasus.lua`, then a second **DO SCRIPT FILE** `DAWG.lua`.
3. Place **templates**: late-activated, runway-start, single-ship groups of the probing side, named `DAWG <anything>`.
   - Tags in the name fix the pilot (`#hothead`, `#showboat`, `#book`, `#tester`) or the lane (`@GAGRA`).
   - Put a **Smoke Generator – white** on a pylon for the fuel-dump pass. The Su-27, Su-33 and MiG-29 can carry one.
4. Place **lanes**: late-activated groups named `DAWG LANE <NAME>`. Their waypoints are the probe leg, drawn **parallel to the border and outside it**. Add `#land` if the lane runs over land.
5. Fly. The first probe comes at about 10 minutes, then one every 15–25.

Open **`missions/DAWG_Starter_Caucasus_v1.2.miz`** in the Mission Editor to see all of this set up. To watch everything without flying, spectate **`missions/DAWG_Demo_Caucasus_v1.4.miz`**: five intercepts with five different pilots, all AI.

## In the release zip

| File | What |
|---|---|
| `DAWG_User_Guide.pdf` | **Start here.** Eight pages covering setup, choosing pilots, flags, recipes and troubleshooting. Also in this repo: [docs/DAWG_User_Guide.pdf](docs/DAWG_User_Guide.pdf). |
| `DAWG.lua` | The script. Load it last. |
| `DAWG_borders_caucasus.lua` | Real Caucasus borders: Georgia (incl. Abkhazia and South Ossetia) and its 12 NM sea, Turkey and its 12 NM sea, Armenia, Azerbaijan. Source: Natural Earth. |
| `DAWG_config_template.lua` | Every option, commented. Optional. |
| `examples/DAWG_config_Caucasus.lua` | A full config: five real-border lanes, real red fields. |
| `missions/` | Starter (for the Mission Editor) and Demo (for spectating). |
| `MANUAL.md` | Everything: tags, flags, personalities, passes, config, the scripting API, logs, troubleshooting. In this repo: [docs/MANUAL.md](docs/MANUAL.md). |

This repo also holds the mission builders (Python + [pydcs](https://github.com/pydcs/dcs)), the border generator and the offline test suite. See [docs/DEVELOPING.md](docs/DEVELOPING.md).

## Controlling it from the Mission Editor

| Flag | Effect |
|---|---|
| `DAWG_LAUNCH_<LANE>` = n | Launches a probe on that lane. n picks the pilot: 1 random, 2 book, 3 showboat, 4 hothead, 5 tester. |
| `DAWG_LAUNCH` = n | The same, on a random lane. |
| `DAWG_PAUSE` = 1 / 0 | Pauses or resumes automatic launches. |

DAWG counts these flags up as things happen: `DAWG_INTERCEPT`, `DAWG_ESCORTED_OUT`, `DAWG_FUEL_DUMP`, `DAWG_TURNBACK`, `DAWG_UNANSWERED`, `DAWG_FIRED_ON` and more (full list in the manual). Use them as conditions in your own triggers.

There is also an F10 menu, **DAWG (GM)**, for the defending side: status, launch a probe on a lane now, set the next pilot, pause.

## Beta status

Offline, every behaviour passes an automated test against a simulated DCS. In the real sim, version 0.1 completed full probe → intercept → show → fuel dump → turnback → escort-out cycles. The close-pass formation steering is new in this beta (it replaces DCS's Follow task, which didn't hold across coalitions), and it hasn't been flown in the sim yet. The `SHOW_STEP` lines in `dcs.log` show whether each pass reached its slot. Reports welcome.

MIT licence. See [LICENSE](LICENSE).
