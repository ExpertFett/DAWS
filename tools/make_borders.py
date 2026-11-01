"""Generate DAWG_borders_caucasus.lua - REAL (de jure) borders for the DCS Caucasus
map from Natural Earth 10m admin-0 countries.

    python -I make_borders.py <ne_10m_admin_0_countries.geojson>

No-go polygons for the probing (red) side:
  Georgia (land, incl. Abkhazia + South Ossetia - internationally recognised)
  Georgia territorial sea (12 NM strip off the Black Sea coast)
  Turkey (land, clipped to the map) + its 12 NM Black Sea strip
  Armenia, Azerbaijan (land, clipped to the map)
Pure Python (no shapely): Douglas-Peucker simplify, Sutherland-Hodgman clip,
coast detection by probing outward of each vertex, normal offset for the strip.
"""
import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(os.path.dirname(HERE), "DAWG_borders_caucasus.lua")
NM = 1852.0
BBOX = (40.3, 45.6, 36.5, 48.5)            # lat0, lat1, lon0, lon1 - the DCS Caucasus map and a margin


def ring_parts(geom):
    polys = geom["coordinates"] if geom["type"] == "MultiPolygon" else [geom["coordinates"]]
    return [p[0] for p in polys]            # outer rings only


def inside(lon, lat, ring):
    c, j = False, len(ring) - 1
    for i in range(len(ring)):
        xi, yi = ring[i]
        xj, yj = ring[j]
        if (yi > lat) != (yj > lat) and lon < (xj - xi) * (lat - yi) / (yj - yi) + xi:
            c = not c
        j = i
    return c


def in_bbox(ring):
    lats = [p[1] for p in ring]
    lons = [p[0] for p in ring]
    return not (max(lats) < BBOX[0] or min(lats) > BBOX[1] or max(lons) < BBOX[2] or min(lons) > BBOX[3])


def to_m(p, lat0=42.5):                      # local equirectangular metres, fine for 1-2 deg
    return (p[0] * 111320 * math.cos(math.radians(lat0)), p[1] * 111120)


def from_m(q, lat0=42.5):
    return [q[0] / (111320 * math.cos(math.radians(lat0))), q[1] / 111120]


def dp(pts, tol):
    """Douglas-Peucker on an open polyline of [lon,lat] using metre distances."""
    if len(pts) < 3:
        return pts
    a, b = to_m(pts[0]), to_m(pts[-1])
    best, idx = -1, 0
    for i in range(1, len(pts) - 1):
        p = to_m(pts[i])
        vx, vy = b[0] - a[0], b[1] - a[1]
        l2 = vx * vx + vy * vy
        t = 0 if l2 == 0 else max(0, min(1, ((p[0] - a[0]) * vx + (p[1] - a[1]) * vy) / l2))
        d = math.hypot(p[0] - (a[0] + t * vx), p[1] - (a[1] + t * vy))
        if d > best:
            best, idx = d, i
    if best <= tol:
        return [pts[0], pts[-1]]
    return dp(pts[:idx + 1], tol)[:-1] + dp(pts[idx:], tol)


def simplify_ring(ring, tol):
    r = ring[:-1] if ring[0] == ring[-1] else ring[:]
    # split at the two farthest-apart-ish points so DP works on two open halves
    k = max(range(len(r)), key=lambda i: (r[i][0] - r[0][0]) ** 2 + (r[i][1] - r[0][1]) ** 2)
    out = dp(r[:k + 1], tol)[:-1] + dp(r[k:] + [r[0]], tol)[:-1]
    return out


def clip(ring, lat0, lat1, lon0, lon1):
    """Sutherland-Hodgman against an axis-aligned lat/lon box."""
    def edge(pts, inside_fn, inter):
        out = []
        for i in range(len(pts)):
            cur, prev = pts[i], pts[i - 1]
            if inside_fn(cur):
                if not inside_fn(prev):
                    out.append(inter(prev, cur))
                out.append(cur)
            elif inside_fn(prev):
                out.append(inter(prev, cur))
        return out

    def ix_lon(x):
        return lambda a, b: [x, a[1] + (b[1] - a[1]) * (x - a[0]) / (b[0] - a[0])]

    def ix_lat(y):
        return lambda a, b: [a[0] + (b[0] - a[0]) * (y - a[1]) / (b[1] - a[1]), y]

    pts = ring[:-1] if ring[0] == ring[-1] else ring[:]
    pts = edge(pts, lambda p: p[0] >= lon0, ix_lon(lon0))
    pts = edge(pts, lambda p: p[0] <= lon1, ix_lon(lon1)) if pts else pts
    pts = edge(pts, lambda p: p[1] >= lat0, ix_lat(lat0)) if pts else pts
    pts = edge(pts, lambda p: p[1] <= lat1, ix_lat(lat1)) if pts else pts
    return pts


def area(r):
    s = 0
    for i in range(len(r)):
        a, b = to_m(r[i - 1]), to_m(r[i])
        s += a[0] * b[1] - b[0] * a[1]
    return s / 2


def sea_strips(ring, land, nm=12.0, probe_m=3000):
    """12 NM strips seaward of every coastal run of `ring` (land = all land rings)."""
    r = ring[:]
    if area(r) < 0:
        r.reverse()                                  # CCW: outward normal = right of travel
    n = len(r)
    normals, coastal = [], []
    for i in range(n):
        a, b = to_m(r[i - 1]), to_m(r[(i + 1) % n])
        tx, ty = b[0] - a[0], b[1] - a[1]
        l = math.hypot(tx, ty) or 1
        nx, ny = ty / l, -tx / l                     # right-hand normal = outward for CCW
        normals.append((nx, ny))
        p = to_m(r[i])
        probe = from_m((p[0] + nx * probe_m, p[1] + ny * probe_m))
        coastal.append(not any(inside(probe[0], probe[1], L) for L in land))
    # contiguous coastal runs (wrap-around aware)
    runs, cur = [], []
    start = next((i for i in range(n) if not coastal[i]), 0)
    for k in range(1, n + 1):
        i = (start + k) % n
        if coastal[i]:
            cur.append(i)
        elif cur:
            runs.append(cur)
            cur = []
    if cur:
        runs.append(cur)
    strips = []
    for run in runs:
        if len(run) < 4:
            continue
        coast = dp([r[i] for i in run], 2000)        # smooth before offsetting
        if len(coast) < 2:
            continue
        off = []
        for j in range(len(coast)):
            a = to_m(coast[max(0, j - 1)])
            b = to_m(coast[min(len(coast) - 1, j + 1)])
            tx, ty = b[0] - a[0], b[1] - a[1]
            l = math.hypot(tx, ty) or 1
            p = to_m(coast[j])
            off.append(from_m((p[0] + ty / l * nm * NM, p[1] - tx / l * nm * NM)))
        strips.append(coast + off[::-1])
    return strips


def main(path):
    d = json.load(open(path, encoding="utf-8"))
    by = {f["properties"]["ADM0_A3"]: f["geometry"] for f in d["features"]}
    rings = {k: [r for r in ring_parts(by[k]) if in_bbox(r)] for k in ("GEO", "TUR", "ARM", "AZE", "RUS")}
    land = [r for k in rings for r in rings[k]]
    out = []
    geo = max(rings["GEO"], key=len)
    out.append(("Georgia", simplify_ring(geo, 400)))
    for i, s in enumerate(sea_strips(geo, land)):
        out.append(("Georgia 12 NM sea%s" % ("" if i == 0 else " %d" % (i + 1)), s))
    tur = [clip(r, 40.3, 41.75, 36.5, 46.0) for r in rings["TUR"]]
    tur = [t for t in tur if len(t) > 3]
    for t in tur:
        t2 = simplify_ring(t + [t[0]], 600)
        out.append(("Turkey", t2))
        for s in sea_strips(t2, land):
            lats = [p[1] for p in s]
            if min(lats) > 40.6:                      # Black Sea side only (the clip edges are not coast)
                out.append(("Turkey 12 NM sea", s))
    for k, name in (("ARM", "Armenia"), ("AZE", "Azerbaijan")):
        for r in rings[k]:
            c = clip(r, 40.3, 42.0, 43.0, 47.5)
            if len(c) > 3:
                out.append((name, simplify_ring(c + [c[0]], 600)))
    L = ["-- GENERATED by tools/make_borders.py from Natural Earth 10m admin-0 (public domain).",
         "-- Real (de jure) borders: the probing side must stay out of every polygon below.",
         "DAWG_BORDERS_CAUCASUS = {"]
    for name, pts in out:
        L.append('  { name = "%s", points = {' % name)
        for i in range(0, len(pts), 6):
            L.append("    " + " ".join("{ %.4f, %.4f }," % (p[1], p[0]) for p in pts[i:i + 6]))
        L.append("  } },")
    L.append("}")
    open(OUT, "w", encoding="utf-8", newline="\n").write("\n".join(L) + "\n")
    for name, pts in out:
        print("%-24s %4d pts" % (name, len(pts)))
    print("wrote", OUT)


if __name__ == "__main__":
    main(sys.argv[1])
