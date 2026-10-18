"""Shared pydcs helpers for the DAWS mission builders (starter + demo)."""
import os

from dcs import triggers as TR
from dcs import condition as CO
from dcs import action as A
from dcs.mapping import Point, LatLng

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.join(os.path.expanduser("~"), "Saved Games", "DCS", "Missions")
FT = 0.3048
RED_FREQ = 276.0        # the probes' radio (UHF AM)
SMOKE_WHITE = "{D3F65166-1AB8-490f-AF2F-2FB6E22568B4}"


def ll(m, lat, lng):
    return Point.from_latlng(LatLng(lat, lng), m.terrain)


def add_script(m, path, delay, comment):
    key = m.map_resource.add_resource_file(path)
    t = TR.TriggerOnce(comment=comment)
    t.add_condition(CO.TimeAfter(delay))
    t.add_action(A.DoScriptFile(key))
    m.triggerrules.triggers.append(t)


def add_smoke(g, ptype):
    """White smoke generator on the free pylon nearest the centreline (the fuel-dump pass)."""
    pylons = sorted(n for n in range(1, 20) if hasattr(ptype, "Pylon%d" % n))
    if not pylons:
        return None
    mid = (pylons[0] + pylons[-1]) / 2.0
    u = g.units[0]
    used = set(u.pylons.keys())
    for n in sorted(pylons, key=lambda n: (abs(n - mid), n)):
        pyl = getattr(ptype, "Pylon%d" % n)
        for v in vars(pyl).values():
            if isinstance(v, tuple) and len(v) == 2 and isinstance(v[1], dict) and v[1].get("clsid") == SMOKE_WHITE:
                if n not in used:
                    u.load_pylon(v, n)
                    return n
    # nothing free: take the nearest-centre pylon that can carry it
    for n in sorted(pylons, key=lambda n: (abs(n - mid), n)):
        pyl = getattr(ptype, "Pylon%d" % n)
        for v in vars(pyl).values():
            if isinstance(v, tuple) and len(v) == 2 and isinstance(v[1], dict) and v[1].get("clsid") == SMOKE_WHITE:
                u.load_pylon(v, n)
                return n
    return None
