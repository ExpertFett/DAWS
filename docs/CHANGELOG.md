# DAWG changelog

## 1.2.0-beta (2026-11-01): renamed DAWG, Dynamic Air Warfare Group

- **DAWS is now DAWG.** The script is `DAWG.lua`, the config global `DAWG_CONFIG`, the borders file defines `DAWG_BORDERS_<MAP>`, templates and lanes are `DAWG ...` / `DAWG LANE ...` groups, zones `DAWG BORDER ...`, the flags `DAWG_LAUNCH`, `DAWG_LAUNCH_<LANE>`, `DAWG_PAUSE` and the `DAWG_*` counters, the log prefix `DAWG|`, the F10 menu "DAWG (GM)".
- **Everything built for the old name still works** (`legacy_names`, on by default): `DAWS_CONFIG` is read, `DAWS ...` groups and `DAWS BORDER` zones are found, a `DAWS_BORDERS_<MAP>` file is used, `DAWS_LAUNCH` / `DAWS_PAUSE` are watched, every counter is also written to its `DAWS_` twin, and the global `DAWS` is an alias of `DAWG`. Set `legacy_names = false` to drop all of that.
- Starter and demo missions rebuilt under the new name: `DAWG_Starter_Caucasus_v1.2.miz`, `DAWG_Demo_Caucasus_v1.4.miz`.

## 1.1.0-beta (2026-10-18): voices on Guard

- **The probes talk, with [DCS-ATC](https://github.com/ExpertFett/DCS-ATC) in the mission.** Hail one on Guard 243.0 and he answers in the ATC's Russian voice through his own radio. Orders ("turn left heading...", "leave the area", "follow me", "land") count by personality: book and tester comply at the first, showboat at the second, hothead at the third (`obeys`). Hotheads taunt when identified, showboats announce their passes, the fuel dump comes with a line, a shot at him "will be reported". Orders to a stubborn hothead count toward walking him out (`voice_order_credit_s`).
- New config: `voice`, `voice_order_credit_s`, `voice_lines` (override any line, per pilot); `obeys` on personalities.
- New log events `HAILED`, `ORDERED`, `VOICE`; new API `DAWG.onGuard(ev)`, what the ATC calls. Nothing changes without the ATC.
- Offline scenario `guard` covers the handshake, both kinds of pilot and a mission's own line.

## 1.0.0-beta (2026-10-17): first public build

**Setup without Lua**
- Templates found by name: late-activated `DAWG ...` groups. Name tags: `#book #showboat #hothead #tester #nostunts #smoke #single #pair @LANE`.
- Lanes found by name: late-activated `DAWG LANE <name>` groups, whose waypoints are the leg. `#land` / `#sea` tags.
- Which way each lane pushes toward the border, and whether it runs over land, are now worked out automatically.
- Borders from Mission Editor polygon or circle zones named `DAWG BORDER ...`.
- Built-in real borders load by themselves for the map (`DAWG_borders_caucasus.lua`).
- The smoke pod is detected from the template's payload; label (NATO name) and cruise come from the template.
- Mission Editor flags: `DAWG_LAUNCH`, `DAWG_LAUNCH_<LANE>` (the value picks the pilot) and `DAWG_PAUSE`, plus twelve event counters (`DAWG_INTERCEPT`, `DAWG_ESCORTED_OUT`, ...).

**Behaviour**
- Fourth built-in pilot: **tester**. He complies, then turns back if nobody follows him out.
- Custom personalities, custom passes (validated like the built-in ones), and per-template and per-lane weights.
- `schedule` for timed and repeating launches, with a tag shown on that probe's messages.
- `DAWG.launch{ lane=, template=, personality=, tag= }`.

**Fixes from the first in-sim runs**
- **Shows now steer the bandit onto his slots every second**, instead of using DCS's Follow task. Follow didn't hold across coalitions: in the 2026-10-17 run every pass step timed out. `SHOW_STEP` log lines now record each slot as reached or timed out.
- **Spawns are checked for the right coalition.** `coalition.addGroup` files a group by the engine's own country table, so a tool-added country (USSR) could spawn neutral. DAWG now picks a country the engine puts on the probing side, verifies, and retries.
- Removed the `math.randomseed` call: DCS strips it, and calling it killed the script at load.
- Air-start probes with no home field now finish, so they no longer hold a `max_active` slot forever.
- A lane listing a template missing from the mission no longer breaks launches on that lane.
- The pause flag acts on changes only (it used to undo `auto = false` on the first second).
- Several no-go polygons with bounding-box pruning; per-lane ID and escort radii (land lanes shadow from your own side).

## 0.1 (2026-10-12): internal
Probes, intercept / escort-out, three personalities, close passes and fuel dump, lane memory, GM menu, Caucasus demo missions.
