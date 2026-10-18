-- Config-file features: custom personality, custom stunts (one too close -> rejected),
-- schedule with tag, numbered launch flag, per-template weights, the template file compiles.
-- usage: luae run_config.lua <DAWS dir>
local DIR = arg[1]
dofile(DIR .. "/tests/mock_dcs.lua")
local M = MOCK
local fails = 0
local function check(c, what) print((c and "  ok   " or "  FAIL ") .. what); if not c then fails = fails + 1 end end
local function has(p) return #M.grep(p) > 0 end

local f, e = loadfile(DIR .. "/DAWS_config_template.lua")
check(f ~= nil, "DAWS_config_template.lua compiles" .. (e and (": " .. e) or ""))
f()
local n = 0
for _ in pairs(DAWS_CONFIG) do n = n + 1 end
check(n == 0, "the template is all comments: loading it changes nothing")

dofile(DIR .. "/tests/fixture_config.lua")
local C = DAWS_CONFIG
C.auto = false
C.personalities = { cowboy = { label = "cowboy", depth = 2, stunts = { 2, 2 }, opens_with = "sit_six",
                                pool = { "sit_six", "high_wing" }, comply_s = { 0, 0 }, escort_need_s = 0, turnback = 0 } }
C.stunts = { high_wing = { "%s is sitting high on your wing.", { pos = { 0, 80, 250 }, s = 20, say = true } },
             too_close = { "%s nearly hit you.", { pos = { 30, 0, 40 }, s = 10, say = true } } }
C.schedule = { { at = 30, lane = "COAST", personality = "cowboy", tag = "OPENER" } }
C.launch_flags = { [100] = { lane = "RIDGE EAST", template = "DAWS_MIG31_MOZDOK" } }
M.addTemplate("DAWS_SU27_SUKHUMI", 42.86, 41.13, 21)
M.addTemplate("DAWS_MIG31_MOZDOK", 43.79, 44.61, 28)
for _, t in ipairs(C.templates) do if t.template == "DAWS_SU27_SUKHUMI" then t.weights = { hothead = 1 } end end
dofile(DIR .. "/DAWS.lua")

check(DAWS.stunts.high_wing ~= nil, "custom stunt high_wing accepted")
check(DAWS.stunts.too_close == nil and has("STUNT_REJECTED|too_close"), "custom stunt inside min_sep rejected")
check(DAWS.personalities.cowboy and DAWS.personalities.cowboy.opens_with == "sit_six", "custom personality cowboy loaded")

-- a blue fighter on the coast that runs the bandit down and then flies straight
local p = coord.LLtoLO(42.30, 41.40)
local bg = M.addGroup(2, "Viper 1-1", { x = p.x, y = 7000, z = p.z }, { air = true, player = "TestPilot", attrs = { ["Multirole fighters"] = true } })
bg.u.v = { x = 0, z = 1 }
local mode = "cap"
bg.script = function(u, t, dt)
  local s = DAWS.sorties[1]
  local bu = s and Group.getByName(s.lead) and Group.getByName(s.lead):getUnit()
  if mode == "cap" and bu and bu.air and s.state == "PROBE" then mode = "run" end
  if mode == "run" and bu then
    local h = math.atan2(bu.v.z, bu.v.x)
    local tx, tz = bu.p.x - 1500 * math.sin(h), bu.p.z + 1500 * math.cos(h)
    local dx, dz = tx - u.p.x, tz - u.p.z
    local d = math.sqrt(dx * dx + dz * dz)
    local sp = math.min(d / dt, 400)
    if d > 1 then u.v = { x = dx / d * sp, z = dz / d * sp }; u.p.x, u.p.z = u.p.x + u.v.x * dt, u.p.z + u.v.z * dt end
    u.p.y = bu.p.y
    if s.state == "SHADOWED" or s.state == "SHOW" then mode = "straight"; u.v = { x = 0, z = -230 } end
  elseif mode == "straight" then
    u.p.x, u.p.z = u.p.x + u.v.x * dt, u.p.z + u.v.z * dt
  end
end
for _ = 1, 40 do M.tick(1) end
local s1 = DAWS.sorties[1]
check(s1 and s1.tag == "OPENER" and s1.pers == "cowboy", "schedule: t+30 launched the cowboy, tagged OPENER")
M.flags[100] = 1
for _ = 1, 3 do M.tick(1) end
local s2 = DAWS.sorties[2]
check(s2 and s2.lane.name == "RIDGE EAST" and s2.tdef.template == "DAWS_MIG31_MOZDOK" and s2.pers == "book",
  "numbered launch flag 100 -> MiG-31 on RIDGE EAST (forced by-the-book)")
for _ = 1, 3600 do M.tick(1) end
local steps = {}
for _, l in ipairs(M.grep("SHOW_STEP|" .. s1.name)) do steps[#steps + 1] = l:match("SHOW_STEP|[^|]+|%d+|([%w_]+)|") end
check(steps[2] == "sit_six", "the cowboy opened with sit_six (" .. table.concat(steps, ",") .. ")")
local hw = false
for _, k in ipairs(steps) do if k == "high_wing" then hw = true end end
check(hw, "and flew the custom high_wing pass")
local msg = false
for _, t in ipairs(M.texts) do if t:find("[OPENER]", 1, true) then msg = true end end
check(msg, "the tag prefixes his calls")
local d = DAWS.launch("COAST", "DAWS_SU27_SUKHUMI")
check(d and d.pers == "hothead", "per-template weights { hothead = 1 } -> always a hothead")
for _, l in ipairs(M.logs) do if l:find("ERR", 1, true) then print("  " .. l); fails = fails + 1 end end
print(fails == 0 and "CONFIG PASS" or ("CONFIG FAILED " .. fails))
