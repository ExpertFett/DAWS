-- The Starter mission's no-Lua setup, end to end in the mock: discovery from
-- Mission Editor names, then launches driven by ME flags.
-- usage: luae run_starter.lua <DAWS dir> <extracted miz dir>
local DIR, X = arg[1], arg[2]
dofile(DIR .. "/tests/mock_dcs.lua")
local M = MOCK
dofile(X .. "/mission")
env.mission = mission
local fails = 0
local function check(c, what) print((c and "  ok   " or "  FAIL ") .. what); if not c then fails = fails + 1 end end
local function has(p) return #M.grep(p) > 0 end

-- airfields the templates sit on (mission airdromeIds)
M.airbases = {}
for _, c in ipairs(mission.coalition.red.country) do
  for _, g in ipairs((c.plane and c.plane.group) or {}) do
    local p = g.route.points[1]
    if p.airdromeId then
      local id = p.airdromeId
      M.airbases[#M.airbases + 1] = { name = "AB" .. id, getName = function() return "AB" .. id end,
        getID = function() return id end, getPoint = function() return { x = p.x, y = 0, z = p.y } end }
    end
  end
end

local files = {}
for k, v in pairs(mission.trig.actions) do
  local key = tostring(v):match('getValueResourceByKey%(%s*\\?"([^"\\]+)')
  if key then files[#files + 1] = { k = k, key = key } end
end
table.sort(files, function(a, b) return a.k < b.k end)
dofile(X .. "/l10n/DEFAULT/mapResource")
for _, f in ipairs(files) do print("  load " .. mapResource[f.key]); dofile(X .. "/l10n/DEFAULT/" .. mapResource[f.key]) end
check(DAWS_CONFIG and DAWS_CONFIG.templates == nil and DAWS_CONFIG.lanes == nil, "no config file: everything discovered")

print("== discovery")
check(has("|BORDERS|built-in Caucasus|"), "real Caucasus borders loaded automatically (theatre = " .. tostring(mission.theatre) .. ")")
local n = 0
for _, t in ipairs(DAWS.templates) do
  n = n + 1
  print(string.format("    template %-38s label=%-9s pers=%-8s smoke=%-5s lanes=%s", t.template, t.label, tostring(t.personality),
    tostring(t.smoke), t.lanes and table.concat(t.lanes, ",") or "-"))
end
check(n == 5, "5 templates found by name (not the 3 DAWS LANE groups)")
local T = DAWS.templates
check(T["DAWS Su-33 Sochi #hothead @GAGRA"] and T["DAWS Su-33 Sochi #hothead @GAGRA"].personality == "hothead", "#hothead tag read")
check(T["DAWS MiG-31 Mozdok #book @ROKI"] and T["DAWS MiG-31 Mozdok #book @ROKI"].smoke == false and T["DAWS MiG-31 Mozdok #book @ROKI"].label == "Foxhound",
  "MiG-31: label Foxhound, no smoke pod detected")
check(T["DAWS Su-27 Sochi @GAGRA @POTI"] and T["DAWS Su-27 Sochi @GAGRA @POTI"].smoke == true, "Su-27: smoke pod detected from its payload")
for _, ln in ipairs(DAWS.lanes) do
  print(string.format("    lane %-6s land=%-5s templates=%s  dir=(%.2f,%.2f)", ln.name, tostring(ln.land), table.concat(ln.def.templates, " | "), ln.dir.x, ln.dir.z))
end
check(#DAWS.lanes == 3 and DAWS.lanes.GAGRA and DAWS.lanes.POTI and DAWS.lanes.ROKI, "3 lanes from 'DAWS LANE' groups")
check(DAWS.lanes.ROKI.land == true and DAWS.lanes.ROKI.def.intercept_nm == 15, "#land lane gets the wide shadow radius")
check(#DAWS.lanes.GAGRA.def.templates == 2 and #DAWS.lanes.ROKI.def.templates == 2, "@LANE tags pick each lane's templates")
check(not has("LANE_WARN"), "every leg point outside the floor")

print("== Mission Editor flags")
M.flags["DAWS_LAUNCH_GAGRA"] = 4                      -- radio item 'hothead on GAGRA'
for _ = 1, 5 do M.tick(1) end
local s1 = DAWS.sorties[1]
check(s1 and s1.lane.name == "GAGRA" and s1.pers == "hothead", "DAWS_LAUNCH_GAGRA = 4 -> hothead on GAGRA (" .. tostring(s1 and s1.pers) .. ")")
check(M.flags["DAWS_LAUNCH_GAGRA"] == 0, "flag reset to 0 after the launch")
M.flags["DAWS_LAUNCH_ROKI"] = 2
for _ = 1, 5 do M.tick(1) end
local s2 = DAWS.sorties[2]
check(s2 and s2.lane.name == "ROKI" and s2.pers == "book", "DAWS_LAUNCH_ROKI = 2 -> by-the-book on ROKI")
M.flags["DAWS_PAUSE"] = 1
for _ = 1, 3 do M.tick(1) end
check(DAWS.paused == true, "DAWS_PAUSE = 1 pauses auto launches")
M.flags["DAWS_PAUSE"] = 0
for _ = 1, 3 do M.tick(1) end
check(DAWS.paused == false, "DAWS_PAUSE = 0 resumes")
check((M.flags["DAWS_LAUNCHED"] or 0) >= 2, "DAWS counted DAWS_LAUNCHED up (" .. tostring(M.flags["DAWS_LAUNCHED"]) .. ")")
for _ = 1, 1200 do M.tick(1) end
check(has("|PROBE|" .. s1.name), "the GAGRA hothead reached his probe leg")
check((M.flags["DAWS_PROBE"] or 0) >= 1, "DAWS_PROBE counted up")
local red = true
for _, s in ipairs(DAWS.sorties) do local g = Group.getByName(s.lead); if g and g:getCoalition() ~= 1 then red = false end end
check(red and has("SPAWN_COUNTRY"), "spawned RED (USSR 68 is neutral in this engine map -> DAWS switched country)")
for _, l in ipairs(M.logs) do if l:find("ERR", 1, true) or l:find("|WARN|", 1, true) then print("  " .. l); fails = fails + 1 end end
print(fails == 0 and "STARTER PASS" or ("STARTER FAILED " .. fails))
