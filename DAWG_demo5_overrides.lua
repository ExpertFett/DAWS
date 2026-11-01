-- DAWG DEMO (five intercepts) overrides - after DAWG_config_Caucasus.lua, before DAWG.lua.
-- Air-start bandits mid-transit, one per scenario; dawg_demo.lua launches them.
local C = DAWG_CONFIG
C.auto = false
C.menu = false
C.msg_all = true                 -- spectator demo: every call to everyone
C.release_nm = 25
C.turnback_after_s = 60

-- the TESTER: no show, complies quickly - then turns back if nobody keeps watching him leave
C.personalities = C.personalities or {}
C.personalities.tester = { label = "tester", depth = 1, stunts = { 0, 0 }, comply_s = { 10, 20 },
                           escort_need_s = 0, turnback = 1.0, pool = {} }

local function t(name, label, base, home, smoke, alt, extra)
  local d = { template = name, label = label, base = base, home = home, flight = 2, smoke = smoke, alt = alt, speed = 230 }
  for k, v in pairs(extra or {}) do d[k] = v end
  C.templates[#C.templates + 1] = d
end
t("DEMO1_SU27", "Flanker", "Sochi", "Sochi-Adler", true, 7000)
t("DEMO2_MIG29", "Fulcrum", "Krymsk", "Krymsk", true, 6500)
t("DEMO3_SU27", "Flanker", "Beslan", "Beslan", true, 8000)
t("DEMO4_MIG29", "Fulcrum", "Mozdok", "Mozdok", true, 8000)
t("DEMO5_MIG31", "Foxhound", "Mozdok", "Mozdok", false, 9000, { stunts = false, speed = 260 })
