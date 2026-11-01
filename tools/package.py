"""Assemble the DAWG release zip.

    python tools/package.py

-> dist/DAWG_v<ver>/ (folder) + dist/DAWG_v<ver>.zip, and a copy of the zip in
   Saved Games/DCS Library/Scripts & Templates/DAWG/.
Refuses if any bundled mission carries a DAWG.lua that differs from the release
copy (rebuild the missions first), or if the full offline test suite fails.
"""
import hashlib
import os
import re
import shutil
import subprocess
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HOME = os.path.expanduser("~")
MISSIONS = os.path.join(HOME, "Saved Games", "DCS", "Missions")
LIBRARY = os.path.join(HOME, "Saved Games", "DCS Library", "Scripts & Templates", "DAWG")
BUNDLE_MISSIONS = ["DAWG_Starter_Caucasus_v1.2.miz", "DAWG_Demo_Caucasus_v1.4.miz"]


def sha(b):
    return hashlib.sha256(b).hexdigest()[:16]


SHIPPED = ["DAWG.lua", "DAWG_borders_caucasus.lua", "DAWG_config_template.lua", "DAWG_config_Caucasus.lua",
           "README.md", "LICENSE", "docs/MANUAL.md", "docs/CHANGELOG.md", "docs/DAWG_User_Guide.pdf"]


def main():
    # Ship committed files only: on 2026-10-18 another session was mid-edit on DAWG.lua while
    # this ran, and a half-written engine went into the zip under the old version number.
    if "--dirty" not in sys.argv:
        r = subprocess.run(["git", "status", "--porcelain", "--"] + SHIPPED, cwd=ROOT, capture_output=True, text=True)
        if r.returncode == 0 and r.stdout.strip():
            sys.exit("uncommitted changes in shipped files - commit them (or --dirty to package anyway):\n" + r.stdout)
    engine = open(os.path.join(ROOT, "DAWG.lua"), "rb").read()
    ver = re.search(rb'local VERSION = "([^"]+)"', engine).group(1).decode()
    name = "DAWG_v" + ver
    print("DAWG", ver, "engine", sha(engine))

    for m in BUNDLE_MISSIONS:                    # every bundled mission must carry THIS engine
        with zipfile.ZipFile(os.path.join(MISSIONS, m)) as z:
            packed = z.read("l10n/DEFAULT/DAWG.lua")
        if packed != engine:
            sys.exit("%s carries DAWG.lua %s, release is %s - rebuild the missions first" % (m, sha(packed), sha(engine)))
        print("  mission ok:", m)

    if "--skip-tests" not in sys.argv:
        r = subprocess.run([sys.executable, os.path.join(ROOT, "tests", "run_all.py"), "--runs", "2"],
                           capture_output=True, text=True)
        print("\n".join("  " + l for l in r.stdout.splitlines()))
        if r.returncode != 0:
            sys.exit("tests failed - not packaging")

    layout = {
        "DAWG.lua": "DAWG.lua",
        "DAWG_borders_caucasus.lua": "DAWG_borders_caucasus.lua",
        "DAWG_config_template.lua": "DAWG_config_template.lua",
        "README.md": "README.md",
        "DAWG_User_Guide.pdf": "docs/DAWG_User_Guide.pdf",
        "MANUAL.md": "docs/MANUAL.md",
        "CHANGELOG.md": "docs/CHANGELOG.md",
        "LICENSE.txt": "LICENSE",
        "examples/DAWG_config_Caucasus.lua": "DAWG_config_Caucasus.lua",
    }
    dist = os.path.join(ROOT, "dist")
    out = os.path.join(dist, name)
    if os.path.exists(out):
        shutil.rmtree(out)
    os.makedirs(os.path.join(out, "examples"))
    os.makedirs(os.path.join(out, "missions"))
    for dst, src in layout.items():
        shutil.copy2(os.path.join(ROOT, src), os.path.join(out, dst))
    for m in BUNDLE_MISSIONS:
        shutil.copy2(os.path.join(MISSIONS, m), os.path.join(out, "missions", m))

    zpath = os.path.join(dist, name + ".zip")
    with zipfile.ZipFile(zpath, "w", zipfile.ZIP_DEFLATED) as z:   # forward-slash entries (not PS Compress-Archive)
        for base, _, files in os.walk(out):
            for f in sorted(files):
                full = os.path.join(base, f)
                arc = name + "/" + os.path.relpath(full, out).replace("\\", "/")
                z.write(full, arc)
    with zipfile.ZipFile(zpath) as z:
        bad = z.testzip()
        names = z.namelist()
    if bad or any("\\" in n for n in names):
        sys.exit("zip check failed: %s" % (bad or "backslash entry"))
    with zipfile.ZipFile(zpath) as z:                # the engine in the zip = the one tested + matched above
        if z.read(name + "/DAWG.lua") != engine:
            os.remove(zpath)
            sys.exit("DAWG.lua changed while packaging - zip deleted, run again")
    os.makedirs(LIBRARY, exist_ok=True)
    shutil.copy2(zpath, os.path.join(LIBRARY, name + ".zip"))
    print("wrote", zpath, "(%d files, %.0f KB)" % (len(names), os.path.getsize(zpath) / 1024))
    for n in names:
        print("   ", n)
    print("copied to", LIBRARY)


if __name__ == "__main__":
    main()
