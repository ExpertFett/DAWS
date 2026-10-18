"""Build the DAWS FIVE-INTERCEPT demo (all AI, spectator, REAL borders).

    python build_daws_demo5.py   -> Saved Games/DCS/Missions/DAWS_Demo_Caucasus_v<VERSION>.miz

Five scenarios side by side, staggered ~2 min apart, each looping (daws_demo5.lua):
  1 HOTHEAD (GAGRA sea, Pontiac 1)   2 SHOWBOAT (POTI sea, Pontiac 2)
  3 BY-THE-BOOK (ROKI ridge, Pontiac 3)   4 TESTER - turns back (DARIAL ridge, Pontiac 4)
  5 UNANSWERED (ELBRUS ridge, nobody) - the lane remembers
Borders = DAWS_borders_caucasus.lua (Natural Earth 10m, de jure Georgia + 12 NM sea, Turkey ...).
"""
import os
import sys
import datetime

import dcs
from dcs import Mission, terrain
from dcs import planes as P
from dcs import task as T
from dcs.mission import StartType
from dcs.unit import Skill
from dcs.forcedoptions import ForcedOptions

import daws_build_common as B

VERSION = "1.3"
NAME = "DAWS_Demo_Caucasus_v%s.miz" % VERSION

# (template, type, spawn lat, lon, alt m) - air start, mid-transit, outside every no-go polygon
RED = [("DEMO1_SU27", P.Su_27, 43.38, 39.20, 7000),
       ("DEMO2_MIG29", P.MiG_29S, 42.95, 39.30, 6500),
       ("DEMO3_SU27", P.Su_27, 43.40, 43.70, 8000),
       ("DEMO4_MIG29", P.MiG_29S, 43.35, 45.10, 8000),
       ("DEMO5_MIG31", P.MiG_31, 43.90, 42.40, 9000)]
# (group, callsign number, orbit lat, lon) - inside Georgia / its territorial sea
BLUE = [("Pontiac 1", 1, 42.95, 40.55), ("Pontiac 2", 2, 42.10, 41.50),
        ("Pontiac 3", 3, 42.40, 43.90), ("Pontiac 4", 4, 42.45, 44.85)]


def red_air(m, ussr, name, ptype, lat, lng, alt_m):
    g = m.flight_group_inflight(ussr, name, ptype, B.ll(m, lat, lng), altitude=int(alt_m), speed=830,
                                maintask=T.CAP, group_size=1)
    g.late_activation = True
    g.load_task_default_loadout(T.CAP)
    g.units[0].skill = Skill.Excellent
    g.frequency = B.RED_FREQ
    g.points[0].tasks.append(T.OptROE(T.OptROE.Values.WeaponHold))
    g.points[0].tasks.append(T.OptReactOnThreat(T.OptReactOnThreat.Values.EvadeFire))
    return B.add_smoke(g, ptype) if ptype is not P.MiG_31 else None


def build():
    m = Mission(terrain.Caucasus())
    m.start_time = datetime.datetime(2006, 5, 5, 10, 0, 0)       # GPS needs 2006+
    m.weather.clouds_density = 0
    m.set_description_text(
        "DAWS DEMO - five intercepts, five different pilots (all AI - you spectate)\n\n"
        "Real borders: Georgia (incl. Abkhazia + South Ossetia) and its 12 NM territorial sea are blue airspace; "
        "Russia is red. Soviet/Russian fighters probe five stretches of it, ~2 minutes apart, and keep cycling:\n\n"
        "1 HOTHEAD - GAGRA sea lane, Pontiac 1: fuel dump across the nose, close passes, then back to his probe "
        "track until he's walked out.\n"
        "2 SHOWBOAT - POTI sea lane, Pontiac 2: a pass or two, then home.\n"
        "3 BY-THE-BOOK - ROKI ridge, Pontiac 3: shadowed from the Georgian side (nobody crosses), complies.\n"
        "4 TESTER - DARIAL ridge, Pontiac 4: complies fast, then turns BACK when Pontiac goes home for fuel.\n"
        "5 UNANSWERED - ELBRUS ridge, nobody: comes closer every lap; the next probe there starts deeper.\n\n"
        "Every message is tagged with its scenario number. F10 map: red = Georgia, blue = territorial sea, "
        "yellow = probe lanes (dashed = the deepest push). F2/F6 cycle cameras. Nobody shoots.")
    m.set_description_bluetask_text("Spectate.")
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
    m.forced_options.options_view = ForcedOptions.Views.All
    m.forced_options.external_views = True

    smoke = {name: red_air(m, ussr, name, pt, la, lo, alt) for name, pt, la, lo, alt in RED}
    for name, nr, la, lo in BLUE:
        g = m.flight_group_inflight(usa, name, P.FA_18C_hornet, B.ll(m, la, lo), altitude=7500, speed=800,
                                    maintask=T.CAP, group_size=1, callsign_name="Pontiac", callsign_nr=nr)
        g.load_task_default_loadout(T.CAP)
        g.units[0].skill = Skill.Excellent
        g.points[0].tasks.append(T.OptROE(T.OptROE.Values.WeaponHold))
        g.points[0].tasks.append(T.OrbitAction(7500, 800, T.OrbitAction.OrbitPattern.Circle))
    m.awacs_flight(usa, "OVERLORD", P.E_3A, None, B.ll(m, 42.00, 43.00), race_distance=60000, heading=300,
                   altitude=int(30000 * B.FT), speed=650, start_type=StartType.Warm, frequency=251.0)
    for g in usa.plane_group:
        if g.name == "OVERLORD":
            g.units[0].callsign_dict = {1: 1, 2: 1, 3: 1, "name": "Overlord11"}

    B.add_script(m, os.path.join(B.HERE, "DAWS_borders_caucasus.lua"), 1, "DAWS real borders (Caucasus)")
    B.add_script(m, os.path.join(B.HERE, "DAWS_config_Caucasus.lua"), 2, "DAWS config (Caucasus, real borders)")
    B.add_script(m, os.path.join(B.HERE, "DAWS_demo5_overrides.lua"), 3, "DAWS demo overrides (five intercepts)")
    B.add_script(m, os.path.join(B.HERE, "DAWS.lua"), 4, "DAWS - Dynamic Air Warfare System")
    B.add_script(m, os.path.join(B.HERE, "daws_demo5.lua"), 5, "DAWS demo director (five intercepts)")

    out = os.path.join(B.OUT_DIR, NAME)
    if os.path.exists(out):
        sys.exit("refusing to overwrite %s - bump VERSION" % out)
    m.save(out)
    print("wrote", out)
    print("smoke pylons:", smoke)


if __name__ == "__main__":
    build()
