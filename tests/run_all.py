"""Run every DAWG offline test with DCS's own Lua (luae).

    python tests/run_all.py [--runs N]

  scenarios  run_tests.lua x7 scenarios, N runs each (pilot / pass picks are random)
  config     run_config.lua      custom personality + stunt, schedule, flags, the config template
  lanes      lane_check.lua      real-border lanes vs the floor at every push depth
  starter    run_starter.lua     the Starter .miz: no-Lua discovery + Mission Editor flags
  demo       run_demo5.lua       the five-intercept demo .miz, 3 h: every behaviour + realism checks
  verify     verify_miz.lua      (the canon CAUC test mission, if built)
"""
import glob
import os
import subprocess
import sys
import tempfile
import time
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE).replace("\\", "/")
LUAE = os.environ.get("DAWG_LUAE", r"D:\DCS World Server\bin\luae.exe")   # DCS's own Lua 5.1: <any DCS install>\bin\luae.exe
MISSIONS = os.path.join(os.path.expanduser("~"), "Saved Games", "DCS", "Missions")
RUNS = int(sys.argv[sys.argv.index("--runs") + 1]) if "--runs" in sys.argv else 3


def lua(*args, timeout=900):
    r = subprocess.run([LUAE] + list(args), capture_output=True, text=True, timeout=timeout)
    return r.stdout + r.stderr


def latest(pattern):
    files = sorted(glob.glob(os.path.join(MISSIONS, pattern)),
                   key=lambda f: [int(x) for x in os.path.basename(f).rsplit("_v", 1)[1].split(".miz")[0].split("_")[0].split(".")])
    return files[-1] if files else None


def extract(miz, tmp):
    d = os.path.join(tmp, os.path.basename(miz)[:-4])
    zipfile.ZipFile(miz).extractall(d)
    return d.replace("\\", "/")


def main():
    bad = []
    with tempfile.TemporaryDirectory() as tmp:
        for sc in ("unanswered", "book_escort", "hothead", "abort", "hardturn", "turnback", "mig31", "airstart", "guard", "legacy"):
            ok = 0
            for _ in range(RUNS):
                out = lua(HERE + "/run_tests.lua", ROOT, sc)
                if "\nPASS" in out:
                    ok += 1
                else:
                    bad.append(sc)
                    print("\n".join(l for l in out.splitlines() if "FAIL" in l or "ERR" in l)[:2000])
                time.sleep(1.1)
            print("%-12s %d/%d" % (sc, ok, RUNS))
        for name, args, token in (("config", [HERE + "/run_config.lua", ROOT], "CONFIG PASS"),
                                  ("lanes", [HERE + "/lane_check.lua", ROOT], "LANES OK")):
            out = lua(*args)
            print("%-12s %s" % (name, "PASS" if token in out else "FAIL"))
            if token not in out:
                bad.append(name)
                print(out[-2000:])
        for name, pattern, script, token, extra in (
                ("starter", "DAWG_Starter_Caucasus_v*.miz", "run_starter.lua", "STARTER PASS", []),
                ("demo", "DAWG_Demo_Caucasus_v*.miz", "run_demo5.lua", "DEMO5 PASS", ["3"])):
            miz = latest(pattern)
            if not miz:
                print("%-12s SKIP (no %s)" % (name, pattern))
                continue
            out = lua(HERE + "/" + script, ROOT, extract(miz, tmp), *extra)
            ok = token in out
            print("%-12s %s  (%s)" % (name, "PASS" if ok else "FAIL", os.path.basename(miz)))
            if not ok:
                bad.append(name)
                print("\n".join(l for l in out.splitlines() if "FAIL" in l or "ERR" in l))
    print("ALL PASS" if not bad else "FAILED: " + ", ".join(sorted(set(bad))))
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
