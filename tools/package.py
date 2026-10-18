"""Assemble the DAWS release zip.

    python tools/package.py

-> dist/DAWS_v<ver>/ (folder) + dist/DAWS_v<ver>.zip, and a copy of the zip in
   Saved Games/DCS Library/Scripts & Templates/DAWS/.
Refuses if any bundled mission carries a DAWS.lua that differs from the release
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
LIBRARY = os.path.join(HOME, "Saved Games", "DCS Library", "Scripts & Templates", "DAWS")
BUNDLE_MISSIONS = ["DAWS_Starter_Caucasus_v1.0.miz", "DAWS_Demo_Caucasus_v1.3.miz"]


def sha(b):
    return hashlib.sha256(b).hexdigest()[:16]


def main():
    engine = open(os.path.join(ROOT, "DAWS.lua"), "rb").read()
    ver = re.search(rb'local VERSION = "([^"]+)"', engine).group(1).decode()
    name = "DAWS_v" + ver
    print("DAWS", ver, "engine", sha(engine))

    for m in BUNDLE_MISSIONS:                    # every bundled mission must carry THIS engine
        with zipfile.ZipFile(os.path.join(MISSIONS, m)) as z:
            packed = z.read("l10n/DEFAULT/DAWS.lua")
        if packed != engine:
            sys.exit("%s carries DAWS.lua %s, release is %s - rebuild the missions first" % (m, sha(packed), sha(engine)))
        print("  mission ok:", m)

    if "--skip-tests" not in sys.argv:
        r = subprocess.run([sys.executable, os.path.join(ROOT, "tests", "run_all.py"), "--runs", "2"],
                           capture_output=True, text=True)
        print("\n".join("  " + l for l in r.stdout.splitlines()))
        if r.returncode != 0:
            sys.exit("tests failed - not packaging")

    layout = {
        "DAWS.lua": "DAWS.lua",
        "DAWS_borders_caucasus.lua": "DAWS_borders_caucasus.lua",
        "DAWS_config_template.lua": "DAWS_config_template.lua",
        "README.md": "README.md",
        "DAWS_User_Guide.pdf": "docs/DAWS_User_Guide.pdf",
        "MANUAL.md": "docs/MANUAL.md",
        "CHANGELOG.md": "docs/CHANGELOG.md",
        "LICENSE.txt": "LICENSE",
        "examples/DAWS_config_Caucasus.lua": "DAWS_config_Caucasus.lua",
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
    os.makedirs(LIBRARY, exist_ok=True)
    shutil.copy2(zpath, os.path.join(LIBRARY, name + ".zip"))
    print("wrote", zpath, "(%d files, %.0f KB)" % (len(names), os.path.getsize(zpath) / 1024))
    for n in names:
        print("   ", n)
    print("copied to", LIBRARY)


if __name__ == "__main__":
    main()
