-- DAWG offline scenario tests. Usage: luae run_tests.lua <dir-of-DAWG> <scenario>
local DIR, SC = arg[1], arg[2]
dofile(DIR .. "/tests/mock_dcs.lua")
local M = MOCK
dofile(DIR .. "/tests/fixture_config.lua")
local C = DAWG_CONFIG
C.first_s, C.auto = 1e9, false                    -- tests launch by hand
-- turnback: no show (a show can drag him past release_nm), complies at once, always turns back
if SC == "turnback" then C.personalities = { hothead = { turnback = 1.0, stunts = { 0, 0 } } } end
M.addTemplate("DAWG_SU27_SUKHUMI", 42.86, 41.13, 21)
M.addTemplate("DAWG_MIG31_MOZDOK", 43.79, 44.61, 28)
if SC == "guard" then   -- a stand-in for the DCS-ATC's Guard: records what the probes say
  GUARD_SAID, GUARD_REG = {}, nil
  C.voice_lines = { land = "Nyet, {you}." }       -- a mission overriding one line
  C.personalities = { book = { comply_s = { 900, 900 } } }   -- so the book pilot is still around to be ordered
  ATC = { Guard = { register = function(f) GUARD_REG = f; return true end,
                    say = function(u, text, to) GUARD_SAID[#GUARD_SAID + 1] = text; return true end,
                    words = function(u) return { you = "American aircraft", who = "Soviet Air Force", type = "Su twenty seven" } end } }
end
if SC == "legacy" then   -- a mission written for the old name: the config global was DAWS_CONFIG
  DAWS_CONFIG = DAWG_CONFIG
  DAWG_CONFIG = nil
end
dofile(DIR .. "/DAWG.lua")

local fails = 0
local function check(cond, what)
  print((cond and "  ok   " or "  FAIL ") .. what)
  if not cond then fails = fails + 1 end
end
local function has(p) return #M.grep(p) > 0 end
local function run(secs, each) for _ = 1, secs do M.tick(1); if each then each() end end end

-- a blue fighter that sits on a CAP point, then runs the bandit down and flies
-- line-abreast escort `off` m off its right side; modes switched by the test
local B = { mode = "cap", off = 1500 }
local function blue(lat, lon)
  local p = coord.LLtoLO(lat, lon)
  local g = M.addGroup(2, "Viper 1-1", { x = p.x, y = 7000, z = p.z }, { air = true, player = "TestPilot",
    attrs = { ["Multirole fighters"] = true } })
  g.u.v = { x = 0, z = 230 }
  g.script = function(u, t, dt)
    local s = DAWG.sorties[1]
    local bu = s and Group.getByName(s.lead) and Group.getByName(s.lead):getUnit()
    if B.mode == "cap" then
      u.v = { x = 0, z = 0.01 }
      if bu and bu.air then
        local d = math.sqrt((bu.p.x - u.p.x) ^ 2 + (bu.p.z - u.p.z) ^ 2)
        if d < B.react_m then B.mode = "intercept" end
      end
    elseif B.mode == "intercept" or B.mode == "escort" then
      if bu then
        local h = math.atan2(bu.v.z, bu.v.x)
        local tx, tz = bu.p.x - B.off * math.sin(h), bu.p.z + B.off * math.cos(h)
        local dx, dz = tx - u.p.x, tz - u.p.z
        local d = math.sqrt(dx * dx + dz * dz)
        local spd = math.min(d / dt, 400)
        if d > 1 then u.v = { x = dx / d * spd, z = dz / d * spd }; u.p.x, u.p.z = u.p.x + u.v.x * dt, u.p.z + u.v.z * dt
        else u.v = { x = bu.v.x, z = bu.v.z } end
        u.p.y = bu.p.y
        if (d < 300 and B.mode == "intercept") then B.mode = "escort" end
      end
    elseif B.mode == "straight" then                 -- the bandit is formating on us: fly level, steady
      local sp = 230
      local h = B.h or math.atan2(u.v.z, u.v.x)
      B.h = h
      u.v = { x = math.cos(h) * sp, z = math.sin(h) * sp }
      u.p.x, u.p.z = u.p.x + u.v.x * dt, u.p.z + u.v.z * dt
    elseif B.mode == "ram" then                      -- sudden closure to 30 m (abort test)
      u.p.x, u.p.y, u.p.z = bu.p.x + 30, bu.p.y, bu.p.z
      B.mode = "straight"
    elseif B.mode == "hardturn" then
      local h = math.atan2(u.v.z, u.v.x) + math.rad(15) * dt
      u.v = { x = math.cos(h) * 230, z = math.sin(h) * 230 }
      u.p.x, u.p.z = u.p.x + u.v.x * dt, u.p.z + u.v.z * dt
    elseif B.mode == "home" then                    -- walk away east, into Georgia
      u.v = { x = 0, z = 300 }
      u.p.z = u.p.z + 300 * dt
    end
  end
  return g
end

-- show geometry: closest distance between the bandit and the blue jet while in SHOW
local minSep = 1e9
local function watchSep(bg)
  return function()
    local s = DAWG.sorties[1]
    if s and s.state == "SHOW" and s.show and s.show.joined then
      local u = Group.getByName(s.lead) and Group.getByName(s.lead):getUnit()
      if u then
        local d = math.sqrt((u.p.x - bg.u.p.x) ^ 2 + (u.p.y - bg.u.p.y) ^ 2 + (u.p.z - bg.u.p.z) ^ 2)
        minSep = math.min(minSep, d)
      end
    end
  end
end

print("== " .. SC)
-- static checks every run
check(DAWG.version ~= nil and #DAWG.lanes == 3, "loaded with 3 lanes")
local nst = 0
for _ in pairs(DAWG.stunts) do nst = nst + 1 end
check(nst == 7 and not has("STUNT_REJECTED"), "all 7 stunts pass the min_sep path check")
for _, lane in ipairs(DAWG.lanes) do
  for d = 0, C.max_depth do
    local worst = 1e9
    for _, p in ipairs(DAWG.legAt(lane, d)) do worst = math.min(worst, DAWG.borderNm(p)) end
    check(worst >= C.floor_nm - 0.01, string.format("%s depth %d: closest leg point %.1f NM >= floor", lane.name, d, worst))
  end
end
check(not has("LANE_WARN"), "no lane leg starts inside the floor")

if SC == "unanswered" then
  local s = DAWG.launch("COAST", "DAWG_SU27_SUKHUMI", "book")
  check(s ~= nil, "launched")
  run(4 * 3600)
  check(has("|AIRBORNE|"), "airborne")
  check(has("|PROBE|"), "reached the probe leg")
  check(#M.grep("|UNANSWERED|") >= 2, "unanswered laps logged (" .. #M.grep("|UNANSWERED|") .. ")")
  check(s.depth > 0, "went deeper (depth " .. s.depth .. ")")
  check(has("probe complete"), "complied after max laps")
  check(DAWG.lanes.COAST.bias == 1, "lane remembers: next probe starts deeper")
  check(has("|END|"), "landed and cleaned up")
elseif SC == "book_escort" then
  local bg = blue(42.30, 41.40)
  B.react_m = 60000
  local s = DAWG.launch("COAST", "DAWG_SU27_SUKHUMI", "book")
  run(4 * 3600)
  check(has("|RESPONSE|"), "response time logged")
  check(has("|INTERCEPT|"), "intercept logged")
  check(not has("SHOW_START"), "by-the-book: no show")
  check(has("COMPLY|" .. s.name .. "|intercepted"), "complied when intercepted")
  check(has("|ESCORTED_OUT|"), "escorted out credited")
  local e = M.grep("|ESCORTED_OUT|")[1] or ""
  check(e:find("TestPilot", 1, true) ~= nil, "credited to the player name")
elseif SC == "hothead" then
  local bg = blue(42.30, 41.40)
  B.react_m = 60000
  local s = DAWG.launch("COAST", "DAWG_SU27_SUKHUMI", "hothead")
  local switched = false
  run(4 * 3600, function()
    watchSep(bg)()
    if s.state == "SHOW" and not switched then switched = true; B.mode = "straight" end
    if s.state == "STUBBORN" then B.mode = "escort" end
  end)
  check(has("SHOW_START"), "show started")
  check(has("|FUEL_DUMP|"), "fuel dump pass flown")
  local on, off = false, false
  for _, c in ipairs(M.cmds) do
    if c.c.id == "SMOKE_ON_OFF" then if c.c.params.value then on = true elseif on then off = true end end
  end
  check(on and off, "smoke switched on, then off")
  check(has("SHOW_END|" .. s.name .. "|done"), "show ran to the end")
  check(minSep >= C.min_sep_m * 0.8, string.format("closest approach during the show %.0f m (min_sep %d)", minSep, C.min_sep_m))
  check(has("walked out"), "stubborn until walked out")
  check(has("|ESCORTED_OUT|"), "escorted out")
  for _, t in ipairs(M.texts) do if t:find("FUEL", 1, true) or t:find("SIX", 1, true) then print("    msg: " .. t) end end
elseif SC == "abort" then
  local bg = blue(42.30, 41.40)
  B.react_m = 60000
  local s = DAWG.launch("COAST", "DAWG_SU27_SUKHUMI", "hothead")
  run(4 * 3600, function()
    if s.state == "SHOW" and B.mode ~= "ram" and B.mode ~= "straight" then B.mode = "straight"; B.t = M.t end
    if B.mode == "straight" and s.show and s.show.joined and M.t - B.t > 60 then B.mode = "ram" end
    if s.state == "COMPLY" then B.mode = "cap" end
  end)
  check(has("SHOW_ABORT"), "abort fired when the defender turned into him")
  check(has("COMPLY|" .. s.name .. "|abort"), "went home after the abort")
elseif SC == "hardturn" then
  local bg = blue(42.30, 41.40)
  B.react_m = 60000
  local s = DAWG.launch("COAST", "DAWG_SU27_SUKHUMI", "showboat")
  run(4 * 3600, function()
    if s.state == "SHOW" and not B.t then B.mode = "straight"; B.t = M.t end
    if B.t and M.t - B.t > 50 and M.t - B.t < 80 then B.mode = "hardturn" elseif B.t and B.mode == "hardturn" then B.mode = "straight"; B.h = nil end
  end)
  check(has("SHOW_PAUSE"), "show paused while the defender turned hard")
  check(has("SHOW_END|" .. s.name .. "|done"), "show resumed and finished")
elseif SC == "turnback" then
  local bg = blue(42.30, 41.40)
  B.react_m = 60000
  local s = DAWG.launch("COAST", "DAWG_SU27_SUKHUMI", "hothead")
  run(4 * 3600, function()
    if s.state == "SHOW" then B.mode = "straight" end
    if s.state == "STUBBORN" then B.mode = "escort" end
    if s.state == "COMPLY" and not has("TURNBACK") then B.mode = "home" end
  end)
  check(has("|TURNBACK|"), "turned back when the escort left early")
elseif SC == "airstart" then
  -- air-start template, no home field: must still finish (and free its max_active slot)
  local p = coord.LLtoLO(43.20, 40.20)
  table.insert(env.mission.coalition.red.country[1].plane.group, { name = "DAWG_AIR_SU27", groupId = 9, lateActivation = true,
    units = { { name = "DAWG_AIR_SU27-1", unitId = 9, type = "Su-27", x = p.x, y = p.z, payload = { pylons = {} } } },
    route = { points = { { x = p.x, y = p.z, alt = 7000, speed = 230, type = "Turning Point", action = "Turning Point" } } } })
  DAWG.templates[#DAWG.templates + 1] = { template = "DAWG_AIR_SU27", label = "Flanker", flight = 1, alt = 7000, speed = 230 }
  DAWG.templates["DAWG_AIR_SU27"] = DAWG.templates[#DAWG.templates]
  local s = DAWG.launch("COAST", "DAWG_AIR_SU27", "book")
  run(4 * 3600)
  check(s ~= nil and s.homeAb == nil, "air start with no home field launched")
  check(has("probe complete"), "probed, went home")
  check(s.state == "DONE" and has("|END|" .. s.name), "finished and removed (state " .. tostring(s.state) .. ")")
  check(Group.getByName(s.lead) == nil, "his group was despawned")
elseif SC == "mig31" then
  local bg = blue(43.00, 43.80)
  B.react_m = 80000
  local s = DAWG.launch("RIDGE EAST", "DAWG_MIG31_MOZDOK")
  run(4 * 3600)
  check(s.pers == "book", "Foxhound forced by-the-book")
  check(has("|INTERCEPT|") and not has("SHOW_START"), "intercepted, no show")
elseif SC == "guard" then
  -- Voices on Guard: the DCS-ATC hands us a fighter's hail and orders; the personality decides.
  check(GUARD_REG == DAWG.onGuard, "DAWG registered its Guard handler with the ATC")
  check(DAWG.onGuard(nil) == nil and DAWG.onGuard({ op = "hail" }) == nil, "a call with no aircraft of ours is not answered")
  local bg = blue(42.30, 41.40)
  B.react_m = 60000
  local said = {}
  local function order(s, op, arg)
    local r = DAWG.onGuard({ op = op, arg = arg, unit = Group.getByName(s.lead):getUnit(1), flightName = "Camelot 1-1" })
    said[#said + 1] = r and r.text or "<nil>"
    return r
  end
  -- hothead: answers the hail in character, refuses twice, gives in on the third order
  local s = DAWG.launch("COAST", "DAWG_SU27_SUKHUMI", "hothead")
  local step, t0 = 0, 0
  run(4 * 3600, function()
    if s.state == "SHOW" then B.mode = "straight" end
    if s.state == "STUBBORN" or s.state == "COMPLY" then B.mode = "escort" end
    if s.intercepted and step == 0 then step, t0 = 1, M.t; order(s, "hail") end
    if step == 1 and M.t - t0 > 20 then step = 2; order(s, "turn", "270") end
    if step == 2 and M.t - t0 > 40 then step = 3; order(s, "leave") end
    if step == 3 and M.t - t0 > 60 then step = 4; order(s, "leave") end
    if step == 4 and M.t - t0 > 80 then step = 5; order(s, "follow") end
  end)
  check(step >= 5, "the fighter got to talk to him (step " .. step .. ")")
  check((said[1] or ""):find("Keep your distance", 1, true) ~= nil, "hothead answered the hail in character: " .. tostring(said[1]))
  check(has("|HAILED|" .. s.name .. "|Camelot 1-1"), "hail logged")
  check((said[2] or ""):find("^Negative") ~= nil and (said[3] or ""):find("^Negative") ~= nil, "hothead refused the first two orders")
  check((said[4] or ""):find("We are leaving", 1, true) ~= nil, "hothead gave in on the third order: " .. tostring(said[4]))
  check(has("|ORDERED|" .. s.name .. "|leave|Camelot 1-1|x3"), "orders counted")
  check(has("|COMPLY|" .. s.name) and has("ordered by Camelot 1-1"), "went home because he was ordered")
  check((said[5] or ""):find("already leaving", 1, true) ~= nil, "an order after he complied: already leaving")
  local taunted = false
  for _, t in ipairs(GUARD_SAID) do if t:find("Back off", 1, true) then taunted = true end end
  check(taunted, "taunted on Guard, unprompted, when intercepted")
  check(not has("|VOICE|" .. s.name .. "|leaving_now"), "no second 'turning for home' after the comply line")
  check(has("|END|" .. s.name), "finished (state " .. tostring(s.state) .. ")")
  -- by-the-book: complies on the first order; "land" is refused but still counts
  B.mode = "cap"
  said = {}
  local s2 = DAWG.launch("COAST", "DAWG_SU27_SUKHUMI", "book")
  step, t0 = 0, 0
  run(4 * 3600, function()
    if s2.state == "COMPLY" then B.mode = "escort" end
    if s2.intercepted and step == 0 then step, t0 = 1, M.t; order(s2, "hail") end
    if step == 1 and M.t - t0 > 20 then step = 2; order(s2, "land") end
    if step == 2 and M.t - t0 > 40 then step = 3; order(s2, "turn", "090") end
  end)
  check((said[1] or ""):find("routine patrol", 1, true) ~= nil, "book answered the hail: " .. tostring(said[1]))
  check(said[2] == "Nyet, American aircraft.", "a mission's own line for 'land' was used: " .. tostring(said[2]))
  check((said[3] or ""):find("turning for home", 1, true) ~= nil, "book turned for home on the first real order: " .. tostring(said[3]))
  check(has("|COMPLY|" .. s2.name) and has("|END|" .. s2.name), "book complied and finished")
elseif SC == "legacy" then
  -- the old name still works: DAWS_CONFIG, the DAWS global, the DAWS_ flags, counters under both names
  check(DAWS == DAWG and DAWG.cfg == DAWS_CONFIG, "DAWS_CONFIG was read and DAWS is an alias of DAWG")
  M.flags["DAWS_LAUNCH"] = 2                        -- the old launch flag, 2 = by-the-book
  run(5)
  check(M.flags["DAWS_LAUNCH"] == 0 and has("|FLAG_LAUNCH|DAWS_LAUNCH|2|"), "the old launch flag launched a probe and was reset")
  check((M.flags["DAWG_LAUNCHED"] or 0) >= 1 and (M.flags["DAWS_LAUNCHED"] or 0) >= 1, "the counter was written under both names")
  M.flags["DAWS_PAUSE"] = 1
  run(5)
  check(DAWG.paused == true and has("|PAUSE|true"), "the old pause flag pauses")
  M.flags["DAWS_PAUSE"] = 0
  run(5)
  check(DAWG.paused == false, "and resumes")
  check(#M.grep("DAWG|") > 0 and #M.grep("DAWS|") == 0, "log lines carry the new name only")
end

for _, l in ipairs(M.logs) do if l:find("ERR", 1, true) then print("  " .. l); fails = fails + 1 end end
print(fails == 0 and "PASS" or ("FAILED " .. fails))
if M.verbose or fails > 0 or arg[3] == "v" then for _, l in ipairs(M.grep("DAWG|")) do print("    " .. l) end end
