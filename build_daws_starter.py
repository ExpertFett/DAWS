"""Build DAWS_Starter_Caucasus - the example a mission maker opens in the Mission
Editor: everything is set up the NO-LUA way (names, waypoints, flags), and the
only scripts are the borders file and DAWS.lua. No config file.

    python build_daws_starter.py [VERSION]   -> Saved Games/DCS/Missions/DAWS_Starter_Caucasus_v<VERSION>.miz

What's in it (and what it teaches):
  red templates  late-activated, RUNWAY start, weapons hold, white smoke pod where the type takes one:
                   "DAWS Su-27 Sochi @GAGRA @POTI"      any personality, two lanes
                   "DAWS Su-33 Sochi #hothead @GAGRA"   always a hothead
                   "DAWS MiG-29 Krymsk #showboat @POTI" always a showboat
                   "DAWS Su-27 Beslan @ROKI"
                   "DAWS MiG-31 Mozdok #book @ROKI"     (no smoke pod on the MiG-31 -> no fuel dump)
  lanes          late-activated groups "DAWS LANE GAGRA" / "DAWS LANE POTI" / "DAWS LANE ROKI #land":
                 their waypoints are the probe leg (parallel to the border, outside it)
  borders        DAWS_borders_caucasus.lua (real borders, loaded automatically on this map)
  blue           client F/A-18Cs at Senaki, client F-14Bs at Kutaisi, OVERLORD E-3A
  ME triggers    F10 radio items that set DAWS_LAUNCH_* / DAWS_PAUSE flags, and a trigger that
                 reacts to DAWS_ESCORTED_OUT - DAWS driven from the Mission Editor, no Lua
"""
import os
import sys
import datetime

import dcs
from dcs import Mission, terrain
from dcs import planes as P
from dcs import task as T
from dcs import triggers as TR
from dcs import condition as CO
from dcs import action as A
from dcs.mission import StartType
from dcs.unit import Skill

import daws_build_common as B

VERSION = sys.argv[1] if len(sys.argv) > 1 else "1.0"
NAME = "DAWS_Starter_Caucasus_v%s.miz" % VERSION

TEMPLATES = [("DAWS Su-27 Sochi @GAGRA @POTI", P.Su_27, "Sochi-Adler"),
             ("DAWS Su-33 Sochi #hothead @GAGRA", P.Su_33, "Sochi-Adler"),
             ("DAWS MiG-29 Krymsk #showboat @POTI", P.MiG_29S, "Krymsk"),
             ("DAWS Su-27 Beslan @ROKI", P.Su_27, "Beslan"),
             ("DAWS MiG-31 Mozdok #book @ROKI", P.MiG_31, "Mozdok")]
# lane legs (lat, lon) - same as DAWS_config_Caucasus.lua, here drawn as ME waypoints
LANES = [("DAWS LANE GAGRA", [(43.11, 39.53), (42.86, 39.98), (42.61, 40.43)], 7000),
         ("DAWS LANE POTI", [(42.45, 40.91), (42.10, 41.01), (41.80, 41.11)], 6500),
         ("DAWS LANE ROKI #land", [(43.00, 43.55), (42.95, 43.95), (42.95, 44.35)], 8000)]


def build():
    m = Mission(terrain.Caucasus())
    m.start_time = datetime.datetime(2006, 5, 5, 10, 0, 0)       # GPS needs 2006+
    m.weather.clouds_density = 0
    m.set_description_text(
        "DAWS STARTER - set up the no-Lua way. Open it in the Mission Editor and look:\n\n"
        "TEMPLATES: late-activated red groups named 'DAWS ...' (runway start, weapons hold). Tags in the name: "
        "#hothead / #showboat / #book / #tester fix the pilot; @GAGRA etc. pick the lanes it flies.\n"
        "LANES: late-activated groups named 'DAWS LANE <name>' - their waypoints are the probe leg. #land = over the ridge.\n"
        "BORDERS: real borders load automatically on the Caucasus (DAWS_borders_caucasus.lua). "
        "Or draw polygon zones named 'DAWS BORDER ...'.\n"
        "FLAGS: F10 > Other has radio items that set DAWS_LAUNCH_GAGRA (value 4 = hothead) etc. "
        "A trigger watches DAWS_ESCORTED_OUT.\n\n"
        "Fly it: take a Hornet out of Senaki and intercept the probes. Inside 2 NM, co-altitude, 10 s = identified. "
        "WEAPONS TIGHT. Probes on 276.000 AM.")
    m.set_description_bluetask_text("Intercept, identify and escort Soviet/Russian probes. WEAPONS TIGHT.")
    m.set_description_redtask_text("AI only.")

    usa = m.country("USA")
    ussr = m.country("USSR")
    if ussr is None:
        m.coalition["red"].add_country(dcs.countries.USSR())
        ussr = m.country("USSR")
    for ab in ("Sukhumi-Babushara", "Gudauta", "Senaki-Kolkhi", "Kutaisi", "Batumi", "Kobuleti",
               "Tbilisi-Lochini", "Vaziani", "Soganlug"):
        m.terrain.airports[ab].set_blue()
    for ab in ("Sochi-Adler", "Krymsk", "Maykop-Khanskaya", "Mineralnye Vody", "Nalchik", "Beslan", "Mozdok"):
        m.terrain.airports[ab].set_red()
    for side in ("blue", "red", "neutrals"):
        if side in m.coalition and not m.coalition[side].bullseye:
            m.coalition[side].bullseye = {"x": 0, "y": 0}

    smoke = {}
    for name, ptype, field in TEMPLATES:
        g = m.flight_group_from_airport(ussr, name, ptype, m.terrain.airports[field], maintask=T.CAP,
                                        start_type=StartType.Runway, group_size=1)
        g.late_activation = True
        g.load_task_default_loadout(T.CAP)
        g.units[0].skill = Skill.Excellent
        g.frequency = B.RED_FREQ
        g.points[0].tasks.append(T.OptROE(T.OptROE.Values.WeaponHold))
        g.points[0].tasks.append(T.OptReactOnThreat(T.OptReactOnThreat.Values.EvadeFire))
        smoke[name] = B.add_smoke(g, ptype) if ptype is not P.MiG_31 else None
    for name, leg, alt in LANES:
        g = m.flight_group_inflight(ussr, name, P.An_26B, B.ll(m, *leg[0]), altitude=alt, speed=800,
                                    maintask=T.Transport, group_size=1)
        g.late_activation = True                    # never spawned: it's only a drawing of the leg
        for la, lo in leg[1:]:
            g.add_waypoint(B.ll(m, la, lo), alt, 800)

    senaki = m.terrain.airports["Senaki-Kolkhi"]
    g = m.flight_group_from_airport(usa, "Hornet 1", P.FA_18C_hornet, senaki, maintask=T.CAP,
                                    start_type=StartType.Warm, group_size=2)
    g.load_task_default_loadout(T.CAP)
    for u in g.units:
        u.skill = Skill.Client
    g = m.flight_group_from_airport(usa, "Tomcat 1", P.F_14B, m.terrain.airports["Kutaisi"], maintask=T.CAP,
                                    start_type=StartType.Warm, group_size=2)
    g.load_task_default_loadout(T.CAP)
    for u in g.units:
        u.skill = Skill.Client
    m.awacs_flight(usa, "OVERLORD", P.E_3A, None, B.ll(m, 42.00, 43.00), race_distance=60000, heading=300,
                   altitude=int(30000 * B.FT), speed=650, start_type=StartType.Warm, frequency=251.0)
    for g in usa.plane_group:
        if g.name == "OVERLORD":
            g.units[0].callsign_dict = {1: 1, 2: 1, 3: 1, "name": "Overlord11"}

    B.add_script(m, os.path.join(B.HERE, "DAWS_borders_caucasus.lua"), 1, "DAWS real borders (Caucasus)")
    B.add_script(m, os.path.join(B.HERE, "DAWS.lua"), 2, "DAWS - Dynamic Air Warfare System")

    # DAWS from the Mission Editor: radio items that set its flags...
    t = TR.TriggerOnce(comment="DAWS - F10 radio items (Mission Editor flags, no Lua)")
    t.add_condition(CO.TimeAfter(3))
    for text, flag, value in (("DAWS: hothead on GAGRA", "DAWS_LAUNCH_GAGRA", 4),
                              ("DAWS: showboat on POTI", "DAWS_LAUNCH_POTI", 3),
                              ("DAWS: by-the-book on ROKI", "DAWS_LAUNCH_ROKI", 2),
                              ("DAWS: random probe, any lane", "DAWS_LAUNCH", 1),
                              ("DAWS: pause auto launches", "DAWS_PAUSE", 1),
                              ("DAWS: resume auto launches", "DAWS_PAUSE", 0)):
        t.add_action(A.AddRadioItem(m.string(text), flag, value))
    m.triggerrules.triggers.append(t)
    # ...and a trigger that reacts to one DAWS counts up
    t = TR.TriggerOnce(comment="DAWS - react to an escort-out (DAWS counts DAWS_ESCORTED_OUT up)")
    t.add_condition(CO.FlagIsMore("DAWS_ESCORTED_OUT", 0))
    t.add_action(A.MessageToAll(m.string("Mission Editor trigger: first probe escorted out - well done."), 15))
    m.triggerrules.triggers.append(t)

    out = os.path.join(B.OUT_DIR, NAME)
    if os.path.exists(out):
        sys.exit("refusing to overwrite %s - bump VERSION" % out)
    m.save(out)
    print("wrote", out)
    print("smoke pylons:", smoke)
    return out


if __name__ == "__main__":
    build()
