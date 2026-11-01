-- Five-intercept demo end-to-end in the mock (real .miz + its packed scripts).
-- usage: luae run_demo5.lua <DAWG dir> <extracted miz dir> [hours]
local DIR, X = arg[1], arg[2]
local HOURS = tonumber(arg[3] or "3")
dofile(DIR .. "/tests/mock_dcs.lua")
local M = MOCK
dofile(X .. "/mission")
env.mission = mission
local fails = 0
local function check(c, what) print((c and "  ok   " or "  FAIL ") .. what); if not c then fails = fails + 1 end end

M.airbases = {}
for i, a in ipairs({ { "Sochi-Adler", 43.44, 39.94 }, { "Krymsk", 44.96, 37.99 }, { "Beslan", 43.21, 44.59 }, { "Mozdok", 43.79, 44.61 } }) do
  local p = coord.LLtoLO(a[2], a[3])
  M.airbases[i] = { name = a[1], getID = function() return 100 + i end, getPoint = function() return { x = p.x, y = 0, z = p.z } end }
end
for _, c in ipairs(mission.coalition.blue.country) do
  for _, g in ipairs((c.plane and c.plane.group) or {}) do
    local u = g.units[1]
    local mg = M.addGroup(2, g.name, { x = u.x, y = u.alt or 7500, z = u.y }, { air = true,
      attrs = (u.type == "FA-18C_hornet") and { ["Multirole fighters"] = true } or {} })
    mg.u.v = { x = 150, z = 150 }
    local o = g.route.points[1].task.params.tasks
    for _, t in ipairs(o) do if t.id == "Orbit" then mg.ctl.task = { id = "Orbit", params = { point = { x = u.x, y = u.y }, altitude = 7500, speed = 220 } } end end
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

-- realism watch: red never inside a no-go polygon; ridge interceptors never leave Georgia
local redMin, redWho, ridgeMax, ridgeWho = 1e9, "-", -1e9, "-"
for _ = 1, HOURS * 3600 do
  M.tick(1)
  for _, g in ipairs(M.groups) do
    if not g.gone and g.u.air then
      local b = DAWG.borderNm(g.u.p)
      if g.side == 1 and b < redMin then redMin, redWho = b, g.name .. " @" .. M.t end
      if (g.name == "Pontiac 3" or g.name == "Pontiac 4") and M.t > 60 and b > ridgeMax then ridgeMax, ridgeWho = b, g.name .. " @" .. M.t end
    end
  end
end

-- sortie name -> scenario tag
local tagOf = {}
for _, l in ipairs(M.grep("DAWGDEMO|")) do
  local tag, name = l:match("|LAUNCH|([^|]+)|%d+|([^|]+)|")
  if tag then tagOf[name] = tag end
end
local ev = {}
for _, l in ipairs(M.grep("DAWG|")) do
  local kind, name, rest = l:match("^DAWG|%d+|([%u_]+)|([^|]+)|?(.*)")
  local tag = name and tagOf[name]
  if tag then ev[tag] = ev[tag] or {}; table.insert(ev[tag], kind .. (rest ~= "" and ("|" .. rest) or "")) end
end
local function has(tag, pat)
  for _, e in ipairs(ev[tag] or {}) do if e:find(pat, 1, true) then return true end end
end
local function count(tag, pat)
  local n = 0
  for _, e in ipairs(ev[tag] or {}) do if e:find(pat, 1, true) then n = n + 1 end end
  return n
end
for _, tag in ipairs({ "1 HOTHEAD", "2 SHOWBOAT", "3 BY-THE-BOOK", "4 TESTER", "5 UNANSWERED" }) do
  local seen, line = {}, {}
  for _, e in ipairs(ev[tag] or {}) do
    local k = e:match("^[%u_]+")
    if k ~= "AIRBORNE" and k ~= "RESPONSE" and not seen[k .. #line] then line[#line + 1] = k end
    if #line > 14 then break end
  end
  print(string.format("  %-14s %s", tag, table.concat(line, " > ")))
end

check(has("1 HOTHEAD", "FUEL_DUMP") and has("1 HOTHEAD", "walked out") and has("1 HOTHEAD", "ESCORTED_OUT"), "1 HOTHEAD: fuel dump, stubborn, walked out, escorted out")
check(has("1 HOTHEAD", "INTERCEPT|Pontiac 1"), "1 HOTHEAD: intercepted by Pontiac 1")
check(has("2 SHOWBOAT", "SHOW_START") and has("2 SHOWBOAT", "show done"), "2 SHOWBOAT: a show, then home")
check(has("2 SHOWBOAT", "INTERCEPT|Pontiac 2"), "2 SHOWBOAT: intercepted by Pontiac 2")
check(has("3 BY-THE-BOOK", "INTERCEPT|Pontiac 3") and not has("3 BY-THE-BOOK", "SHOW_START") and has("3 BY-THE-BOOK", "COMPLY|intercepted"),
  "3 BY-THE-BOOK: shadowed by Pontiac 3, no show, complied")
check(has("4 TESTER", "TURNBACK") and count("4 TESTER", "INTERCEPT|") >= 2, "4 TESTER: turned back after Pontiac left, re-intercepted")
check(not has("5 UNANSWERED", "INTERCEPT|") and count("5 UNANSWERED", "UNANSWERED|") >= 2 and has("5 UNANSWERED", "probe complete"),
  "5 UNANSWERED: nobody came, went deeper each lap, probe complete")
local d1, d2
for _, e in ipairs(ev["5 UNANSWERED"] or {}) do
  local d = e:match("^LAUNCH|.-|depth (%d)")
  if d then if not d1 then d1 = tonumber(d) elseif not d2 then d2 = tonumber(d) end end
end
check(d1 and d2 and d2 > d1, string.format("5 UNANSWERED: the lane remembered - next probe started deeper (depth %s -> %s)", tostring(d1), tostring(d2)))
check(redMin >= 0, string.format("no red jet ever entered blue / no-go airspace (closest %.1f NM, %s)", redMin, redWho))
check(ridgeMax <= 0.05, string.format("ridge interceptors never left Georgia (max %.2f NM outside, %s)", ridgeMax, ridgeWho))
local tagged = 0
for _, t in ipairs(M.texts) do if t:find("^%[ALL%] %[%d ") then tagged = tagged + 1 end end
check(tagged > 20, "messages tagged by scenario (" .. tagged .. ")")
local untagged = 0
for _, s in ipairs(DAWG.sorties) do if not s.tag then untagged = untagged + 1 end end
check(untagged == 0, "no automatic launches on top of the scenarios (auto = false held; " .. untagged .. " untagged)")
for _, l in ipairs(M.logs) do if l:find("ERR", 1, true) then print("  " .. l); fails = fails + 1 end end
print(fails == 0 and "DEMO5 PASS" or ("DEMO5 FAILED " .. fails))
