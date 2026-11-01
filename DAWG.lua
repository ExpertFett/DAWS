-- ============================================================================
-- DAWG - Dynamic Air Warfare Group (formerly DAWS)               v1.2.0-beta
-- Peacetime / crisis air activity for DCS World: the probing side flies out of
-- its own fields, PROBES the other side's border without crossing it, and reacts
-- to the intercept according to a PERSONALITY - from "complies and goes home" to
-- "dumps fuel across your windscreen and will not leave until walked out".
-- Standalone: no MOOSE, no MIST. Multiplayer / dedicated-server safe.
--
-- LOAD ORDER (Mission Editor, MISSION START or TIME MORE, action DO SCRIPT FILE):
--   1. (optional) a borders file, e.g. DAWG_borders_caucasus.lua
--   2. (optional) your config, e.g. DAWG_config.lua  (sets DAWG_CONFIG = { ... })
--   3. DAWG.lua
-- With no config at all DAWG sets itself up from the Mission Editor:
--   templates = late-activated groups of the probing side named "DAWG ..."
--               (tags in the name: #book #showboat #hothead #tester #nostunts @LANE)
--   lanes     = late-activated groups named "DAWG LANE <name>" - their waypoints
--               are the probe leg (flown parallel to the border, outside it)
--   borders   = trigger zones named "DAWG BORDER ..." (polygon or circle), plus
--               the built-in real borders for the map if that borders file is loaded
-- Full manual: README.md / MANUAL.md in the release zip.
--
-- SAFETY: the probing side never enters a border polygon and never shoots
-- (weapons hold). Close passes are validated at load (no slot, and no straight
-- path between slots, inside min_sep_m of the target) and checked every second
-- in flight (anything defending inside abort_sep_m = abort, break away). Shows
-- pause while the target turns hard or is low, and never happen near a border.
--
-- Log lines (dcs.log): DAWG|<mission time>|<EVENT>|...
-- ============================================================================
env.info("[DAWG] script start")
local VERSION = "1.2.0-beta"
DAWG_CONFIG = DAWG_CONFIG or DAWS_CONFIG or {}     -- DAWS_CONFIG: a config written for the old name
local C = DAWG_CONFIG

local DEFAULTS = {
  side = "red",                      -- the probing side
  messages = true, msg_all = false, group_msgs_to_all = false,
  menu = true, menu_name = "DAWG (GM)",
  awacs = "OVERLORD",                -- who makes the calls to the defenders
  auto = true, first_s = 600, interval_s = { 900, 1500 }, max_active = 2,
  wing_delay_s = 45,
  floor_nm = 2, step_nm = 4, max_depth = 3, max_laps = 3,
  response_nm = 20, intercept_nm = 2, intercept_alt_m = 1000, intercept_s = 10,
  escort_nm = 3, escort_alt_m = 1500, escort_credit_s = 60, release_nm = 30,
  land_intercept_nm = 15, land_escort_nm = 15,      -- lanes over land: shadow from your own side
  min_sep_m = 100, abort_sep_m = 50, min_agl_m = 1500, max_turn_dps = 9,
  show_border_nm = 1, join_timeout_s = 150, step_timeout_s = 45, show_max_s = 1200,
  quick_response_s = 300, max_sortie_s = 5400, roe = 4, turnback_after_s = 90,
  formation = "steer",               -- "steer" (works on any target) or "follow" (DCS Follow task)
  -- Voices on Guard: with the DCS-ATC script in the mission the probes answer a fighter that
  -- hails them on 243.0 and take his orders by personality (see "voices" below).
  voice = true, voice_order_credit_s = 30, voice_lines = {},
  template_prefix = "DAWG", lane_prefix = "DAWG LANE", border_prefix = "DAWG BORDER",
  weights = { book = 45, showboat = 30, hothead = 15, tester = 10 },
  -- Mission Editor flags (named flags; false = off). DAWG counts these up when they happen:
  event_flags = { LAUNCH = "DAWG_LAUNCHED", PROBE = "DAWG_PROBE", INTERCEPT = "DAWG_INTERCEPT",
                  SHOW_START = "DAWG_SHOW", FUEL_DUMP = "DAWG_FUEL_DUMP", ESCORTED_OUT = "DAWG_ESCORTED_OUT",
                  WITHDREW = "DAWG_WITHDREW", UNANSWERED = "DAWG_UNANSWERED", TURNBACK = "DAWG_TURNBACK",
                  FIRED_ON = "DAWG_FIRED_ON", SHOW_ABORT = "DAWG_SHOW_ABORT", LOST = "DAWG_LOST" },
  -- ...and watches these: set one > 0 to launch (DAWG sets it back to 0). The value picks the pilot:
  -- 1 = from the weights, 2 = book, 3 = showboat, 4 = hothead, 5 = tester, 6+ = your own, in order.
  launch_flag = "DAWG_LAUNCH", lane_flag_prefix = "DAWG_LAUNCH_", pause_flag = "DAWG_PAUSE",
  -- The old name. With this on, groups and zones named "DAWS ...", the DAWS_LAUNCH / DAWS_PAUSE
  -- flags, a DAWS_BORDERS_<MAP> borders file and DAWS_CONFIG all still work, and every event
  -- counter is also written to its DAWS_ twin. Set false once nothing uses the old name.
  legacy_names = true,
}
for k, v in pairs(DEFAULTS) do if C[k] == nil then C[k] = v end end

local NM = 1852
local SIDE = coalition.side[string.upper(C.side)]
local FOE = (SIDE == coalition.side.RED) and coalition.side.BLUE or coalition.side.RED
local SIDE_NAME = string.lower(C.side)
DAWG = { version = VERSION, sorties = {}, lanes = {}, templates = {}, paused = not C.auto, cfg = C,
         pauseFlagWas = false }             -- the pause flag acts on CHANGES only (off at start = no change)
DAWS = DAWG                                 -- the old name, for scripts that still look for it (the DCS-ATC's Guard handshake)
-- An old-name twin of a DAWG_ flag or prefix (nil when legacy names are off or it has none).
local function legacyName(s)
  if C.legacy_names == false or type(s) ~= "string" or s:sub(1, 4):upper() ~= "DAWG" then return nil end
  return "DAWS" .. s:sub(5)
end

do  -- randomness. DCS strips math.randomseed (and os) from mission scripts, so
    -- burn a varying number of draws instead: a fresh table's address differs per run
  local entropy = tonumber((tostring({}):match("(%x+)$")) or "0", 16) or 0
  if os and os.time then entropy = entropy + os.time() end
  if math.randomseed then math.randomseed(entropy % 2147483647) end
  for _ = 1, (entropy % 997) + 3 do math.random() end
end

-- ============================================================ utilities
local CUR                                   -- the sortie being processed: its tag prefixes every call
local function log(...)
  local p = { "DAWG", string.format("%d", timer.getTime()) }
  for _, v in ipairs({ ... }) do p[#p + 1] = tostring(v) end
  env.info(table.concat(p, "|"))
  if DAWG.onEvent then pcall(DAWG.onEvent, ...) end
  local f = C.event_flags and C.event_flags[(...)]
  if f then pcall(function() trigger.action.setUserFlag(f, (trigger.misc.getUserFlag(f) or 0) + 1) end) end
  local f2 = legacyName(f)
  if f2 then pcall(function() trigger.action.setUserFlag(f2, (trigger.misc.getUserFlag(f2) or 0) + 1) end) end
end
local function tagged(text) return (CUR and CUR.tag) and ("[" .. CUR.tag .. "] " .. text) or text end
local function sayAll(text, t)
  text = tagged(text)
  env.info("[DAWG] " .. text:gsub("\n", " | "))
  if not C.messages then return end
  if C.msg_all then trigger.action.outText(text, t or 12)
  else trigger.action.outTextForCoalition(FOE, text, t or 12) end
end
local function sayGroup(g, text, t)
  text = tagged(text)
  env.info("[DAWG] >" .. tostring(g and g:getName()) .. ": " .. text)
  if not C.messages then return end
  if C.msg_all then
    trigger.action.outText((g and (g:getName() .. ": ") or "") .. text, t or 10)
  elseif C.group_msgs_to_all then
    trigger.action.outTextForCoalition(FOE, (g and (g:getName() .. ": ") or "") .. text, t or 10)
  elseif g then pcall(function() trigger.action.outTextForGroup(g:getID(), text, t or 10) end) end
end
local function sayStatus(text) if C.msg_all then trigger.action.outText(text, 25) else trigger.action.outTextForCoalition(FOE, text, 25) end end
local function safe(f, d) local ok, v = pcall(f); if ok and v ~= nil then return v end return d end
local function mmss(s) return string.format("%d:%02d", math.floor(s / 60), math.floor(s % 60)) end
local function rnd(r) if type(r) ~= "table" then return r end return r[1] + math.random() * (r[2] - r[1]) end
local function rndi(r) if type(r) ~= "table" then return r end return math.random(r[1], r[2]) end
local function clamp(v, a, b) return math.max(a, math.min(b, v)) end

local function toXZ(t)
  if t.x then return { x = t.x, z = t.z or t.y } end
  local p = coord.LLtoLO(t[1], t[2], 0)
  return { x = p.x, z = p.z }
end
local function d2(a, b) local dx, dz = a.x - b.x, a.z - b.z; return math.sqrt(dx * dx + dz * dz) end
local function d3(a, b) local dx, dy, dz = a.x - b.x, (a.y or 0) - (b.y or 0), a.z - b.z; return math.sqrt(dx * dx + dy * dy + dz * dz) end
local function inPoly(p, poly)
  local c, j = false, #poly
  for i = 1, #poly do
    local a, b = poly[i], poly[j]
    if ((a.z > p.z) ~= (b.z > p.z)) and (p.x < (b.x - a.x) * (p.z - a.z) / (b.z - a.z) + a.x) then c = not c end
    j = i
  end
  return c
end
local function segDist(p, a, b)
  local vx, vz = b.x - a.x, b.z - a.z
  local l2 = vx * vx + vz * vz
  local t = l2 > 0 and math.max(0, math.min(1, ((p.x - a.x) * vx + (p.z - a.z) * vz) / l2)) or 0
  return d2(p, { x = a.x + t * vx, z = a.z + t * vz })
end

-- ============================================================== borders
-- No-go polygons. NM from the nearest: positive outside all of them, negative
-- inside any. (Outside a union, the min distance over the pieces is exact.)
local POLYS = {}
local function borderNm(p)
  local best, inside = 1e12, false
  for _, P in ipairs(POLYS) do
    local bx = math.max(P.x0 - p.x, 0, p.x - P.x1)
    local bz = math.max(P.z0 - p.z, 0, p.z - P.z1)
    if bx * bx + bz * bz < best * best then
      local pts, j = P.pts, #P.pts
      for i = 1, #pts do best = math.min(best, segDist(p, pts[j], pts[i])); j = i end
      if not inside and bx == 0 and bz == 0 and inPoly(p, pts) then inside = true end
    end
  end
  if #POLYS == 0 then return 1e6 end
  best = best / NM
  return inside and -best or best
end
local function addPoly(name, pts, raw)
  local P = { name = name, pts = {}, x0 = 1e12, x1 = -1e12, z0 = 1e12, z1 = -1e12 }
  for _, q in ipairs(pts) do
    local v = raw and q or toXZ(q)
    P.pts[#P.pts + 1] = v
    P.x0, P.x1, P.z0, P.z1 = math.min(P.x0, v.x), math.max(P.x1, v.x), math.min(P.z0, v.z), math.max(P.z1, v.z)
  end
  if #P.pts >= 3 then POLYS[#POLYS + 1] = P end
end
DAWG.borderNm = borderNm
DAWG.polys = POLYS

local function startsWith(s, p) return type(s) == "string" and s:sub(1, #p):upper() == p:upper() end
-- A group or zone name carrying the prefix, under the new name or (legacy_names) the old one.
local function hasPrefix(s, p)
  if startsWith(s, p) then return true end
  local old = legacyName(p)
  return old ~= nil and startsWith(s, old)
end

if C.border then addPoly("border", C.border) end
for _, b in ipairs(C.borders or {}) do addPoly(b.name or "border", b.points) end
-- built-in real borders for this map, when the borders file is loaded and no config borders were given
if not C.border and not C.borders then
  local theatre = env.mission and env.mission.theatre
  local builtin = theatre and (_G["DAWG_BORDERS_" .. string.upper(theatre)]
                              or (C.legacy_names ~= false and _G["DAWS_BORDERS_" .. string.upper(theatre)]))
  if builtin then
    for _, b in ipairs(builtin) do addPoly(b.name, b.points) end
    log("BORDERS", "built-in " .. theatre, #builtin .. " polygons")
  end
end
-- Mission Editor zones named "DAWG BORDER ..." (polygon zones, or circles as 24-gons)
for _, z in ipairs((env.mission and env.mission.triggers and env.mission.triggers.zones) or {}) do
  if hasPrefix(z.name, C.border_prefix) then
    local pts = {}
    if z.verticies and #z.verticies >= 3 then
      for _, v in ipairs(z.verticies) do pts[#pts + 1] = { x = v.x, z = v.y } end
    else
      for i = 0, 23 do
        local a = i / 24 * 2 * math.pi
        pts[#pts + 1] = { x = z.x + z.radius * math.cos(a), z = z.y + z.radius * math.sin(a) }
      end
    end
    addPoly(z.name, pts, true)
    log("BORDERS", "zone " .. z.name)
  end
end

-- ================================================================ units
local function grp(name)
  local g = name and Group.getByName(name)
  if g and g:isExist() and g:getSize() > 0 then return g end
end
local function lead(name)
  local g = grp(name)
  local u = g and g:getUnit(1)
  if u and u:isExist() then return u end
end
local function heading(u)
  local v = u:getVelocity()
  return math.atan2(v.z, v.x), math.sqrt(v.x * v.x + v.z * v.z)
end
local function agl(p) return p.y - land.getHeight({ x = p.x, y = p.z }) end
local function who(u) return safe(function() return u:getPlayerName() end, nil) or safe(function() return u:getName() end, "?") end

-- ============================================================ voices (DCS-ATC on Guard)
-- With the DCS-ATC script in the mission (ATC.Guard), a probe answers a fighter that hails
-- it on Guard 243.0 in the ATC's Russian voice, through its own radio, and takes orders by
-- personality. These are the lines; cfg.voice_lines overrides any key (a string, a
-- per-personality table, a list to pick from by how often he has been told, or false).
-- {you} {who} {type} are filled in: "American aircraft", "Soviet Air Force", "Su twenty seven".
local LINES = {
  hail = { book = "{you}, this is {who} {type} on a routine patrol in international airspace. State your intentions.",
           tester = "{you}, this is {who} {type} on a routine patrol in international airspace. State your intentions.",
           showboat = "{you}, {who} {type}. We see you. Nice aircraft.",
           hothead = "{you}, this is {who} {type}. You are very close. Keep your distance." },
  hail_again = "{you}, {who} {type}, go ahead.",
  refuse = { book = "Negative, {you}. We are in international airspace and we continue on our route.",
             showboat = "Negative, {you}. One moment, we are not finished here.",
             hothead = { "Negative, {you}. International airspace. We go where we like.",
                         "Negative, {you}. Your orders mean nothing here." } },
  comply = { book = "Understood, {you}. We are turning for home.",
             tester = "Understood, {you}. We are turning for home.",
             showboat = "Very well, {you}. It was a pleasure. We are leaving.",
             hothead = "Very well, {you}. We are leaving. Tell your admiral the Soviet Air Force sends regards." },
  follow = { book = "Understood, {you}. We will follow you out.",
             tester = "Understood, {you}. We will follow you out.",
             showboat = "Very well, {you}. Lead on, we will follow you out.",
             hothead = false },                                  -- false: he does not do follow (see follow_refuse)
  follow_refuse = "Negative, {you}. We do not follow American aircraft.",
  land = "Negative, {you}. We will not land. We are returning to our base.",
  leaving = "{you}, we are already leaving your area.",
  leaving_now = "{you}, we are turning for home now.",
  taunt = { hothead = "{you}, you are too close. Back off." },
  show = { showboat = "{you}, watch this." },
  fuel_dump = "Enjoy the fuel, {you}.",
  fired_on = "{you}, you fired on us! We are breaking off. This will be reported.",
}
local function lineFor(key, pers, n)
  local v = C.voice_lines and C.voice_lines[key]
  if v == nil then v = LINES[key] end
  if type(v) == "table" then
    if v[pers] ~= nil then v = v[pers]
    elseif #v == 0 then v = v.book                 -- a personality without its own line uses the by-the-book one
    end
  end
  if type(v) == "table" then
    if #v == 0 then return nil end
    v = v[n and math.min(n, #v) or math.random(#v)]
  end
  return type(v) == "string" and v or nil
end
local function voiceWords(s)
  local u = lead(s.lead)
  local w = (u and type(ATC) == "table" and ATC.Guard and ATC.Guard.words) and safe(function() return ATC.Guard.words(u) end, nil)
  return w or { you = "American aircraft", who = "Soviet Air Force", type = "aircraft" }, u
end
local function fill(line, w) return (line:gsub("{(%w+)}", function(k) return w[k] or k end)) end
local function voice(s, key, n)              -- the probe says something on Guard, unprompted
  if not (C.voice and type(ATC) == "table" and ATC.Guard and ATC.Guard.say) then return nil end
  local w, u = voiceWords(s)
  local line = lineFor(key, s.pers, n)
  if not (line and u) then return nil end
  local text = fill(line, w)
  pcall(ATC.Guard.say, u, text, s.hailedBy)
  log("VOICE", s.name, key, text)
  return text
end
local function foeAir()
  local out = {}
  for _, g in pairs(coalition.getGroups(FOE, Group.Category.AIRPLANE) or {}) do
    for _, u in ipairs(g:getUnits() or {}) do
      if u:isExist() and u:inAir() then out[#out + 1] = u end
    end
  end
  return out
end
local function isFighter(u)
  return u:hasAttribute("Fighters") or u:hasAttribute("Multirole fighters") or u:hasAttribute("Interceptors")
end
local function overLand(p)
  return safe(function() return land.getSurfaceType({ x = p.x, y = p.z }) == land.SurfaceType.LAND end, false)
end

-- ======================================================= tasks / routes
local function combo() return { id = "ComboTask", params = { tasks = {} } } end
local function wp(p, alt, spd)
  return { x = p.x, y = p.z, alt = alt, alt_type = "BARO", type = "Turning Point", action = "Turning Point",
           speed = spd, speed_locked = true, task = combo() }
end
local function setRoute(g, pts)
  if g then pcall(function() g:getController():setTask({ id = "Mission", params = { route = { points = pts } } }) end) end
end
local function follow(g, target, pos)
  if not (g and target) then return end
  pcall(function()
    g:getController():setTask({ id = "Follow", params = { groupId = target:getID(),
      pos = { x = pos[1] or pos.x, y = pos[2] or pos.y, z = pos[3] or pos.z }, lastWptIndexFlag = false } })
  end)
end
local function smoke(g, on)
  if g then pcall(function() g:getController():setCommand({ id = "SMOKE_ON_OFF", params = { value = on } }) end) end
end
local function setOptions(g)
  pcall(function()
    local c = g:getController()
    c:setOption(AI.Option.Air.id.ROE, C.roe)
    c:setOption(AI.Option.Air.id.RTB_ON_BINGO, true)
  end)
end
local airbases
local function airbaseById(id)
  if not airbases then
    airbases = {}
    for _, ab in ipairs(world.getAirbases() or {}) do airbases[safe(function() return ab:getID() end, -1)] = ab end
  end
  return airbases[id]
end

-- Formation on ANY aircraft (the DCS Follow task did not hold across coalitions
-- in testing): every second, fly at a point just ahead of the slot, at the
-- target's speed plus a closure term. `pos` = { ahead, up, right } metres.
local function slotWorld(tu, pos)
  local p = tu:getPoint()
  local h = heading(tu)
  local c, s = math.cos(h), math.sin(h)
  return { x = p.x + pos[1] * c - pos[3] * s, y = p.y + pos[2], z = p.z + pos[1] * s + pos[3] * c }
end
local function steer(g, tu, pos)
  local me = g and g:getUnit(1)
  if not (me and me:isExist() and tu and tu:isExist()) then return end
  local slot = slotWorld(tu, pos)
  local h, sp = heading(tu)
  local v = tu:getVelocity()
  local mp = me:getPoint()
  local fx, fz = math.cos(h), math.sin(h)
  local dist = d3(mp, slot)
  local behind = (slot.x - mp.x) * fx + (slot.z - mp.z) * fz          -- + = the slot is ahead of us
  local spd, aim
  if dist > 3000 then                                                  -- far: run to where the slot will be
    local tt = clamp(dist / 120, 5, 40)
    aim = { x = slot.x + v.x * tt, z = slot.z + v.z * tt }
    spd = clamp(sp + 120, 150, 420)
  else                                                                 -- near: hold the slot
    aim = { x = slot.x + v.x * 5, z = slot.z + v.z * 5 }
    spd = clamp(sp + clamp(behind / 6, -50, 90), 110, 420)
  end
  setRoute(g, { wp(aim, slot.y, spd) })
  return dist
end
local function formate(g, target, tu, pos)
  if C.formation == "follow" then follow(g, target, pos) else steer(g, tu, pos) end
end

-- ============================================================ templates
local function deepcopy(o)
  if type(o) ~= "table" then return o end
  local r = {}
  for k, v in pairs(o) do r[k] = deepcopy(v) end
  return r
end
local tplCache = {}
local function findTemplate(name)
  if tplCache[name] then return tplCache[name].g, tplCache[name].cid end
  for _, side in pairs(env.mission.coalition or {}) do
    for _, ctry in ipairs(side.country or {}) do
      for _, g in ipairs((ctry.plane and ctry.plane.group) or {}) do
        if g.name == name then tplCache[name] = { g = g, cid = ctry.id }; return g, ctry.id end
      end
    end
  end
end

-- coalition.addGroup files a group by the ENGINE's country->coalition map, not
-- by where the template sat in the mission file: a tool-added country can spawn
-- NEUTRAL silently. Spawn as a country the engine really puts on our side, and
-- check the result.
local function sideCountries(prefer)
  local list, seen = {}, {}
  local can = coalition.getCountryCoalition ~= nil
  local function add(id)
    if id == nil or seen[id] then return end
    seen[id] = true
    if not can or coalition.getCountryCoalition(id) == SIDE then list[#list + 1] = id end
  end
  add(prefer)
  for _, g in pairs(coalition.getGroups(SIDE) or {}) do                 -- what the side already flies as
    local u = g:isExist() and g:getUnit(1)
    if u then add(safe(function() return u:getCountry() end, nil)) end
  end
  for _, c in ipairs(((env.mission.coalition or {})[SIDE_NAME] or {}).country or {}) do add(c.id) end
  for _, id in ipairs(((env.mission.coalitions or {})[SIDE_NAME]) or {}) do add(id) end
  if can then for id = 0, 130 do add(id) end end                        -- last resort: any country the engine puts there
  if #list == 0 then list[1] = prefer end
  return list
end

local SMOKE_CLSIDS = { ["{D3F65166-1AB8-490f-AF2F-2FB6E22568B4}"] = true, ["{D3F65166-1AB8-490f-AF2F-2FB6E22568B1}"] = true,
  ["{D3F65166-1AB8-490f-AF2F-2FB6E22568B2}"] = true, ["{D3F65166-1AB8-490f-AF2F-2FB6E22568B3}"] = true,
  ["{D3F65166-1AB8-490f-AF2F-2FB6E22568B5}"] = true, ["{D3F65166-1AB8-490f-AF2F-2FB6E22568B6}"] = true,
  ["{A4BCC903-06C8-47bb-9937-A30FEDB4E744}"] = true, ["{A4BCC903-06C8-47bb-9937-A30FEDB4E741}"] = true,
  ["{INV-SMOKE-WHITE}"] = true }
local NATO_NAMES = { ["Su-27"] = "Flanker", ["Su-33"] = "Flanker-D", ["Su-30"] = "Flanker-C", ["J-11A"] = "Flanker",
  ["MiG-29A"] = "Fulcrum", ["MiG-29S"] = "Fulcrum", ["MiG-29G"] = "Fulcrum", ["MiG-31"] = "Foxhound",
  ["MiG-25PD"] = "Foxbat", ["MiG-23MLD"] = "Flogger", ["MiG-21Bis"] = "Fishbed", ["Su-24M"] = "Fencer",
  ["Su-24MR"] = "Fencer-E", ["Su-34"] = "Fullback", ["Su-25"] = "Frogfoot", ["Su-25T"] = "Frogfoot",
  ["Tu-95MS"] = "Bear", ["Tu-142"] = "Bear-F", ["Tu-22M3"] = "Backfire", ["Tu-160"] = "Blackjack",
  ["A-50"] = "Mainstay", ["IL-76MD"] = "Candid", ["IL-78M"] = "Midas", ["An-26B"] = "Curl", ["Su-17M4"] = "Fitter",
  ["JF-17"] = "Thunder", ["J-10"] = "Firebird" }
local BIG = { ["Tu-95MS"] = true, ["Tu-142"] = true, ["Tu-22M3"] = true, ["Tu-160"] = true, ["A-50"] = true,
  ["IL-76MD"] = true, ["IL-78M"] = true, ["An-26B"] = true, ["An-30M"] = true, ["Su-24MR"] = true }

-- fill the gaps in a template definition from the template group itself
local function completeTdef(t)
  local g = findTemplate(t.template)
  if not g then return nil end
  local u = g.units and g.units[1] or {}
  t.type = t.type or u.type
  t.label = t.label or NATO_NAMES[u.type] or u.type or "bandit"
  if t.smoke == nil then
    t.smoke = false
    for _, p in pairs((u.payload and u.payload.pylons) or {}) do if SMOKE_CLSIDS[p.CLSID] then t.smoke = true end end
  end
  if t.stunts == nil and BIG[u.type] then t.stunts = false end
  local pts = g.route and g.route.points or {}
  local cruise = pts[2] or pts[1] or {}
  if not t.alt then t.alt = (cruise.alt and cruise.alt > 1000) and cruise.alt or 7000 end
  if not t.speed then t.speed = (cruise.speed and cruise.speed > 100) and cruise.speed or 230 end
  t.flight = t.flight or { 1, 2 }
  return t
end

local serial = 0
local function spawn(tdef, tag, route)
  local src, cid = findTemplate(tdef.template)
  if not src then log("NO_TEMPLATE", tdef.template) return nil end
  serial = serial + 1
  local g = deepcopy(src)
  g.name = string.format("DAWG-%d %s %s", serial, tdef.label, tag)
  g.groupId, g.lateActivation, g.start_time, g.uncontrolled = nil, nil, 0, false
  g.units = { g.units[1] }                     -- single-ship groups: lead and wing fly as separate groups
  g.units[1].unitId = nil
  g.units[1].name = g.name
  local pts = { g.route.points[1] }
  for _, p in ipairs(route) do pts[#pts + 1] = p end
  g.route = { points = pts }
  for _, country in ipairs(sideCountries(tdef.country or cid)) do
    local ok, ng = pcall(coalition.addGroup, country, Group.Category.AIRPLANE, g)
    if ok and ng then
      local side = safe(function() return ng:getCoalition() end, SIDE)
      if side == SIDE then
        if country ~= cid then log("SPAWN_COUNTRY", tdef.template, "country " .. tostring(cid) .. " -> " .. tostring(country)) end
        tdef.country = country
        setOptions(ng)
        return g.name
      end
      log("SPAWN_WRONG_SIDE", tdef.template, "country " .. tostring(country), "side " .. tostring(side))
      pcall(function() ng:destroy() end)
    end
  end
  log("SPAWN_FAIL", tdef.template)
  return nil
end

-- ======================================================== the show book
-- Positions are offsets from the target: { ahead, up, right } metres, written for
-- the RIGHT side and mirrored when the bandit is on the left. First entry = the
-- call the defender hears when the "say" step is reached.
local STUNTS = {
  wing_look = { "%s has slid onto your wing, about 200 m, and is looking you over.",
    { pos = { 0, 0, 200 }, s = 40, say = true } },
  close_wing = { "%s is tucked in on your wing, about 100 m. Close. He is grinning at you.",
    { pos = { 0, 0, 250 }, s = 8 }, { pos = { -10, 5, 110 }, s = 25, say = true }, { pos = { 0, 0, 250 }, s = 8 } },
  nose_cross = { "%s just crossed your nose, about 400 m ahead, right to left.",
    { pos = { 0, 0, 220 }, s = 8 }, { pos = { 380, 30, 220 }, s = 10 },
    { pos = { 380, 30, -220 }, s = 12, say = true }, { pos = { 0, 0, -220 }, s = 10 } },
  fuel_dump = { "%s is DUMPING FUEL across your nose - you are flying through his trail.",
    { pos = { 0, 0, 220 }, s = 8 }, { pos = { 260, 25, 240 }, s = 10 },
    { pos = { 260, 25, -240 }, s = 16, smoke = true, say = true }, { pos = { 0, 0, -220 }, s = 10 } },
  belly_check = { "%s is underneath you - right under your belly, about 130 m.",
    { pos = { 0, 0, 220 }, s = 8 }, { pos = { 30, -130, 140 }, s = 8 },
    { pos = { 30, -130, 0 }, s = 15, say = true }, { pos = { 0, 0, -220 }, s = 10 } },
  canopy_pass = { "%s is right over your canopy, about 150 m above.",
    { pos = { 0, 0, 220 }, s = 8 }, { pos = { 150, 160, 150 }, s = 8 },
    { pos = { 0, 150, 0 }, s = 12, say = true }, { pos = { 0, 0, -220 }, s = 10 } },
  sit_six = { "%s is sitting in your SIX, about 450 m - gun range. He is not shooting. Do not shoot.",
    { pos = { -300, 0, 300 }, s = 10 }, { pos = { -450, 0, 0 }, s = 35, say = true }, { pos = { -300, 50, -300 }, s = 10 } },
}
for name, st in pairs(C.stunts or {}) do STUNTS[name] = st end      -- your own (validated below like the rest)
local JOIN = { pos = { -700, 150, 700 }, s = 10 }
local WIDE = { -350, 120, 600 }
local BREAK = { -200, 300, 900 }
local COVER = { -1200, 300, -1500 }            -- the wingman hangs back, other side, high

local function vlen(p) return math.sqrt(p[1] * p[1] + p[2] * p[2] + p[3] * p[3]) end
local function segOrigin(a, b)
  local v = { b[1] - a[1], b[2] - a[2], b[3] - a[3] }
  local l2 = v[1] * v[1] + v[2] * v[2] + v[3] * v[3]
  local t = l2 > 0 and math.max(0, math.min(1, -(a[1] * v[1] + a[2] * v[2] + a[3] * v[3]) / l2)) or 0
  return vlen({ a[1] + t * v[1], a[2] + t * v[2], a[3] + t * v[3] })
end
local function mirror(p, side) return { p[1], p[2], p[3] * side } end
do  -- refuse any stunt that comes inside min_sep anywhere along its path
  local bad = {}
  for name, st in pairs(STUNTS) do
    local prev = JOIN.pos
    for i = 2, #st do
      local p = st[i].pos
      if vlen(p) < C.min_sep_m or segOrigin(prev, p) < C.min_sep_m then bad[#bad + 1] = name; break end
      prev = p
    end
  end
  for _, name in ipairs(bad) do log("STUNT_REJECTED", name, "inside min_sep " .. C.min_sep_m .. " m"); STUNTS[name] = nil end
end
DAWG.stunts = STUNTS

-- ======================================================== personalities
-- depth        how many steps closer to the border he starts (each step_nm)
-- stunts       {min,max} close passes once identified (0 = none)
-- pool         which passes he picks from
-- opens_with   a pass he always does first if he can (fuel_dump needs a smoke pod)
-- comply_s     {min,max} seconds after the ID before he turns for home (no-show pilots)
-- escort_need_s after his show: seconds of escort before he gives up (0 = leaves at once)
-- turnback     chance he turns back toward the border if nobody follows him out
-- obeys        how many orders on Guard (through the DCS-ATC) it takes before he turns for home
local PERS = {
  book = { label = "by-the-book", depth = 0, stunts = { 0, 0 }, comply_s = { 20, 60 }, escort_need_s = 0, turnback = 0, pool = {},
           obeys = 1 },
  showboat = { label = "showboat", depth = 1, stunts = { 1, 2 }, comply_s = { 10, 30 }, escort_need_s = 0, turnback = 0.1,
               pool = { "wing_look", "nose_cross", "belly_check", "fuel_dump" }, obeys = 2 },
  hothead = { label = "hothead", depth = 2, stunts = { 2, 4 }, comply_s = { 0, 0 }, escort_need_s = 150, turnback = 0.35,
              opens_with = "fuel_dump", pool = { "close_wing", "nose_cross", "fuel_dump", "belly_check", "canopy_pass", "sit_six" },
              obeys = 3 },
  tester = { label = "tester", depth = 1, stunts = { 0, 0 }, comply_s = { 10, 20 }, escort_need_s = 0, turnback = 1.0, pool = {},
             obeys = 1 },
}
for k, v in pairs(C.personalities or {}) do
  PERS[k] = PERS[k] or { label = k, depth = 0, stunts = { 0, 0 }, comply_s = { 20, 60 }, escort_need_s = 0, turnback = 0, pool = {},
                         obeys = 1 }
  for kk, vv in pairs(v) do PERS[k][kk] = vv end
end
DAWG.personalities = PERS
local PERS_ORDER = { "book", "showboat", "hothead", "tester" }       -- flag values 2..5
do  -- your own personalities follow, ALPHABETICALLY (flag values 6, 7, ...)
  local custom = {}
  for k in pairs(PERS) do
    local known = false
    for _, o in ipairs(PERS_ORDER) do if o == k then known = true end end
    if not known then custom[#custom + 1] = k end
  end
  table.sort(custom)
  for _, k in ipairs(custom) do PERS_ORDER[#PERS_ORDER + 1] = k end
end

local function pickWeighted(w)
  local total = 0
  for k, v in pairs(w) do if PERS[k] then total = total + v end end
  if total <= 0 then return "book" end
  local r = math.random() * total
  for _, k in ipairs(PERS_ORDER) do
    if w[k] and PERS[k] then r = r - w[k]; if r <= 0 then return k end end
  end
  return "book"
end
local function pickPersonality(tdef, lane)
  if tdef.personality then return tdef.personality end
  if lane.def.personality then return lane.def.personality end
  return pickWeighted(tdef.weights or lane.def.weights or C.weights)
end

-- ======================================== templates + lanes from config / ME
local TDEF = DAWG.templates
local function nameTags(name)
  local t = {}
  for tag in name:gmatch("#(%w+)") do
    tag = tag:lower()
    if PERS[tag] then t.personality = tag elseif tag == "nostunts" then t.stunts = false
    elseif tag == "smoke" then t.smoke = true elseif tag == "single" then t.flight = 1
    elseif tag == "pair" then t.flight = 2 end
  end
  for l in name:gmatch("@([%w_%-]+)") do t.lanes = t.lanes or {}; t.lanes[#t.lanes + 1] = l:upper() end
  return t
end
if C.templates then
  for _, t in ipairs(C.templates) do if completeTdef(t) then TDEF[#TDEF + 1] = t; TDEF[t.template] = t else log("NO_TEMPLATE", t.template) end end
else  -- discover: late-activated planes of the probing side named "DAWG ..." (not "DAWG LANE ...")
  for _, c in ipairs(((env.mission.coalition or {})[SIDE_NAME] or {}).country or {}) do
    for _, g in ipairs((c.plane and c.plane.group) or {}) do
      if g.lateActivation and hasPrefix(g.name, C.template_prefix) and not hasPrefix(g.name, C.lane_prefix) then
        local t = nameTags(g.name)
        t.template = g.name
        local p1 = g.route and g.route.points and g.route.points[1]
        local ab = p1 and p1.airdromeId and airbaseById(p1.airdromeId)
        t.base = ab and safe(function() return ab:getName() end, nil) or nil
        if completeTdef(t) then TDEF[#TDEF + 1] = t; TDEF[t.template] = t end
      end
    end
  end
end

local function nearestBorderDir(p)              -- unit vector from p toward the closest border point
  local best, bq = 1e12, nil
  for _, P in ipairs(POLYS) do
    local pts, j = P.pts, #P.pts
    for i = 1, #pts do
      local a, b = pts[j], pts[i]
      local vx, vz = b.x - a.x, b.z - a.z
      local l2 = vx * vx + vz * vz
      local t = l2 > 0 and math.max(0, math.min(1, ((p.x - a.x) * vx + (p.z - a.z) * vz) / l2)) or 0
      local q = { x = a.x + t * vx, z = a.z + t * vz }
      local d = d2(p, q)
      if d < best then best, bq = d, q end
      j = i
    end
  end
  if not bq or best < 1 then return { x = 1, z = 0 } end
  return { x = (bq.x - p.x) / best, z = (bq.z - p.z) / best }
end

local function addLane(L)
  local lane = { def = L, name = L.name, bias = 0, legs = {}, flown = 0 }
  lane.entry = L.entry and toXZ(L.entry)
  lane.exit = L.exit and toXZ(L.exit)
  for _, p in ipairs(L.leg) do lane.legs[#lane.legs + 1] = toXZ(p) end
  if #lane.legs < 2 then log("LANE_WARN", L.name, "needs at least 2 leg points") return end
  local mid = lane.legs[math.ceil(#lane.legs / 2)]
  if L.toward then
    local h = math.rad(L.toward)
    lane.dir = { x = math.cos(h), z = math.sin(h) }
  else
    lane.dir = nearestBorderDir(mid)
  end
  lane.land = L.land
  if lane.land == nil then lane.land = overLand(mid) end
  if lane.land then
    if L.intercept_nm == nil then L.intercept_nm = C.land_intercept_nm end
    if L.escort_nm == nil then L.escort_nm = C.land_escort_nm end
  end
  for i, p in ipairs(lane.legs) do
    local b = borderNm(p)
    if b < C.floor_nm then log("LANE_WARN", L.name, "leg point " .. i .. " only " .. string.format("%.1f", b) .. " NM off the border") end
  end
  if L.templates then               -- keep only templates that exist in this mission
    local keep = {}
    for _, n in ipairs(L.templates) do
      if TDEF[n] then keep[#keep + 1] = n else log("LANE_NO_TEMPLATE", L.name, n) end
    end
    L.templates = (#keep > 0) and keep or nil
  end
  if not L.templates then           -- templates tagged @LANE, else every template
    local pool = {}
    for _, t in ipairs(TDEF) do
      if t.lanes then for _, n in ipairs(t.lanes) do if n == L.name:upper() then pool[#pool + 1] = t.template end end end
    end
    if #pool == 0 then for _, t in ipairs(TDEF) do pool[#pool + 1] = t.template end end
    L.templates = pool
  end
  DAWG.lanes[#DAWG.lanes + 1] = lane
  DAWG.lanes[L.name] = lane
end
if C.lanes then
  for _, L in ipairs(C.lanes) do addLane(L) end
else  -- discover: late-activated groups named "DAWG LANE <name>" - waypoints = the leg
  for _, side in pairs(env.mission.coalition or {}) do
    for _, c in ipairs(side.country or {}) do
      for _, cat in ipairs({ "plane", "helicopter", "vehicle", "ship" }) do
        for _, g in ipairs((c[cat] and c[cat].group) or {}) do
          if hasPrefix(g.name, C.lane_prefix) then
            local name = g.name:sub(#C.lane_prefix + 1):gsub("#.*$", ""):gsub("^%s+", ""):gsub("%s+$", "")
            local leg = {}
            for _, p in ipairs((g.route and g.route.points) or {}) do leg[#leg + 1] = { x = p.x, z = p.y } end
            local L = { name = (name ~= "" and name or ("LANE " .. (#DAWG.lanes + 1))):upper(), leg = leg }
            for tag in g.name:gmatch("#(%w+)") do
              tag = tag:lower()
              if PERS[tag] then L.personality = tag elseif tag == "land" then L.land = true elseif tag == "sea" then L.land = false end
            end
            addLane(L)
          end
        end
      end
    end
  end
end

-- the leg pushed `depth` steps toward the border, each point held >= floor
local function legAt(lane, depth)
  local out = {}
  for _, p in ipairs(lane.legs) do
    local push = depth * C.step_nm * NM
    local q
    while true do
      q = { x = p.x + lane.dir.x * push, z = p.z + lane.dir.z * push }
      if push <= 0 or borderNm(q) >= C.floor_nm then break end
      push = math.max(0, push - 0.5 * NM)
    end
    out[#out + 1] = q
  end
  return out
end
DAWG.legAt = legAt

-- ============================================================== sorties
local function lane(s, key) local v = s.lane.def[key]; if v == nil then v = C[key] end return v end
local S = DAWG.sorties
local nextPers                      -- GM override for the next launch

local function sortieUnits(s)
  local out = {}
  for _, n in ipairs({ s.lead, s.wing }) do local u = lead(n); if u then out[#out + 1] = u end end
  return out
end

local function homePoints(s)
  local pts = {}
  local lu = lead(s.lead)
  local alt = s.tdef.alt or 7000
  if s.lane.exit then pts[#pts + 1] = wp(s.lane.exit, alt, s.tdef.speed or 230) end
  local ab = s.homeAb and airbaseById(s.homeAb)
  if ab then
    local p = ab:getPoint()
    pts[#pts + 1] = { x = p.x, y = p.z, alt = 0, alt_type = "RADIO", type = "Land", action = "Landing",
                      airdromeId = s.homeAb, speed = 130, task = combo() }
  elseif lu and #pts == 0 then
    local p = lu:getPoint()
    pts[#pts + 1] = wp({ x = p.x - s.lane.dir.x * 60 * NM, z = p.z - s.lane.dir.z * 60 * NM }, alt, 230)
  end
  return pts
end

local function wingRejoin(s)
  local w, l = grp(s.wing), grp(s.lead)
  if w and l then follow(w, l, { -200, 0, -350 }) end           -- same coalition: the DCS Follow task is fine here
end

local function probeRoute(s)
  local pts = legAt(s.lane, s.depth)
  if s.reverse then
    local r = {}
    for i = #pts, 1, -1 do r[#r + 1] = pts[i] end
    pts = r
  end
  s.legEnd = pts[#pts]
  local route = {}
  for _, p in ipairs(pts) do route[#route + 1] = wp(p, s.tdef.alt or 7000, s.tdef.speed or 230) end
  setRoute(grp(s.lead), route)
  wingRejoin(s)
end

local function goHome(s, why, fast)
  if s.show and s.show.smoke then smoke(grp(s.lead), false); s.show.smoke = false end
  s.state, s.tComply = "COMPLY", timer.getTime()
  local pts = homePoints(s)
  if fast and pts[1] then pts[1].speed = 300 end
  local last = pts[#pts]
  s.homeEnd = last and { x = last.x, z = last.y }
  setRoute(grp(s.lead), pts)
  wingRejoin(s)
  log("COMPLY", s.name, why or "-")
  if s.hails and not s.saidLeaving then s.saidLeaving = true; voice(s, "leaving_now") end   -- he was talking to someone
end

local function newSortie(lane, tdef, pers, tag)
  local now = timer.getTime()
  local src = findTemplate(tdef.template)
  if not src then log("NO_TEMPLATE", tdef.template) return end
  local p1 = src.route and src.route.points and src.route.points[1]
  local homeAb = p1 and p1.airdromeId
  if tdef.home then                           -- air-start templates name their home field
    local ab = Airbase.getByName(tdef.home)
    homeAb = ab and safe(function() return ab:getID() end, nil) or homeAb
    if not homeAb then log("NO_HOME", tdef.home) end
  end
  local s = { id = #S + 1, lane = lane, tdef = tdef, pers = pers or pickPersonality(tdef, lane), t0 = now, tag = tag,
              state = "LAUNCH", laps = 0, close = {}, escort = {}, escortS = 0, homeAb = homeAb }
  if not PERS[s.pers] then log("NO_PERSONALITY", tostring(s.pers), "using book"); s.pers = "book" end
  s.P = PERS[s.pers]
  s.depth = math.max(0, math.min(C.max_depth, (s.P.depth or 0) + lane.bias))
  s.n = rndi(tdef.flight or 1)
  s.label = tdef.label .. (s.n > 1 and " pair" or "")
  local alt, spd = tdef.alt or 7000, tdef.speed or 230
  local route = {}
  if lane.entry then route[#route + 1] = wp(lane.entry, alt, spd) end
  s.legStart = legAt(lane, s.depth)[1]
  route[#route + 1] = wp(s.legStart, alt, spd)
  s.route0 = route
  s.lead = spawn(tdef, "lead", route)
  if not s.lead then return end
  s.name = s.lead
  S[#S + 1] = s
  lane.flown = lane.flown + 1
  log("LAUNCH", s.name, lane.name, tdef.template, s.pers, "depth " .. s.depth, "x" .. s.n)
  return s
end

-- DAWG.launch("LANE", "TEMPLATE", "personality") or DAWG.launch{ lane=, template=, personality=, tag= }
-- every field optional: random lane, a template from that lane's pool, a personality from the weights
function DAWG.launch(a, b, c)
  local o = type(a) == "table" and a or { lane = a, template = b, personality = c }
  local ln = o.lane and DAWG.lanes[string.upper(o.lane)] or o.lane and DAWG.lanes[o.lane]
  if o.lane and not ln then log("NO_LANE", tostring(o.lane)) return nil end
  ln = ln or DAWG.lanes[math.random(#DAWG.lanes)]
  if not ln then log("NO_LANE", "none defined") return nil end
  local pool = ln.def.templates or {}
  local tname = o.template or pool[math.random(math.max(1, #pool))]
  local tdef = tname and TDEF[tname]
  if not tdef then log("NO_TDEF", tostring(tname)) return nil end
  return newSortie(ln, tdef, o.personality, o.tag)
end

-- --------------------------------------------------------------- show
local function buildShow(s)
  local side = (math.random() < 0.5) and 1 or -1
  local steps = { { pos = mirror(JOIN.pos, side), s = JOIN.s, stunt = "join" } }
  local n = rndi(s.P.stunts or 0)
  local pool = {}
  for _, k in ipairs(s.P.pool or {}) do
    if STUNTS[k] and (k ~= "fuel_dump" or s.tdef.smoke) then pool[#pool + 1] = k end
  end
  local order, used = {}, {}
  local first = s.P.opens_with
  if first and STUNTS[first] and n > 0 and (first ~= "fuel_dump" or s.tdef.smoke) then order[1], used[first] = first, true end
  local guard = 0
  while #order < math.min(n, #pool + #order) and guard < 200 do
    guard = guard + 1
    local k = pool[math.random(#pool)]
    if not used[k] then used[k] = true; order[#order + 1] = k end
  end
  for _, k in ipairs(order) do
    local st = STUNTS[k]
    for j = 2, #st do
      steps[#steps + 1] = { pos = mirror(st[j].pos, side), s = st[j].s, smoke = st[j].smoke,
                            say = st[j].say and st[1] or nil, stunt = k }
    end
    local last = st[#st].pos
    if last[3] ~= 0 then side = side * (last[3] > 0 and 1 or -1) end
  end
  steps[#steps + 1] = { pos = mirror(BREAK, side), s = 8, stunt = "break" }
  return steps
end

local function pushStep(s)
  local sh = s.show
  local step = sh.steps[sh.i]
  local g = grp(s.lead)
  if sh.at and segOrigin(sh.at, step.pos) < C.min_sep_m then      -- runtime path check: detour wide
    local side = (sh.at[3] >= 0) and 1 or -1
    table.insert(sh.steps, sh.i, { pos = mirror(WIDE, side), s = 4, stunt = "detour" })
    step = sh.steps[sh.i]
  end
  if sh.smoke and not step.smoke then smoke(g, false); sh.smoke = false end
  if step.smoke then smoke(g, true); sh.smoke = true; log("FUEL_DUMP", s.name, sh.targetBy); voice(s, "fuel_dump") end
  sh.at, sh.tStep, sh.arrived, sh.best = step.pos, timer.getTime(), nil, 1e9
  if C.formation == "follow" then follow(g, Group.getByName(sh.target), step.pos) end
end

local function startShow(s, tu)
  local tg = tu:getGroup()
  s.show = { target = tg:getName(), targetUnit = tu, targetBy = who(tu), steps = buildShow(s), i = 1, t0 = timer.getTime() }
  local budget = C.join_timeout_s + 90
  for _, st in ipairs(s.show.steps) do budget = budget + st.s + 30 end
  s.show.budget = math.min(budget, C.show_max_s)
  s.state, s.showDone = "SHOW", true
  log("SHOW_START", s.name, s.show.targetBy, #s.show.steps - 2 .. " steps")
  sayGroup(tg, string.format("%s: the %s is coming over to join on you. Let him look. Weapons tight.", C.awacs, s.tdef.label), 10)
  voice(s, "show")
  pushStep(s)
  if C.formation == "follow" and grp(s.wing) then follow(grp(s.wing), tg, COVER) end
end

local function endShow(s, why)
  local sh = s.show
  if sh and sh.smoke then smoke(grp(s.lead), false); sh.smoke = false end
  log("SHOW_END", s.name, why, string.format("%d/%d steps in slot", sh and sh.inSlot or 0, sh and #sh.steps or 0))
  if (s.P.escort_need_s or 0) > 0 and why == "done" then
    s.state, s.tStub = "STUBBORN", timer.getTime()
    probeRoute(s)
    sayGroup(Group.getByName(sh.target), string.format("%s: the %s has gone back to his probe track. He is not leaving until you walk him out.",
      C.awacs, s.tdef.label), 12)
  else
    goHome(s, "show " .. why, why ~= "done")
  end
end

local function tickShow(s, now, foes, lu)
  local sh = s.show
  local tg = Group.getByName(sh.target)
  local tu = sh.targetUnit
  if not (tu and tu:isExist() and tu:inAir()) then tu = tg and tg:isExist() and tg:getUnit(1) end
  if not (tu and tu:isExist() and tu:inAir()) then return endShow(s, "target gone") end
  local lp, tp = lu:getPoint(), tu:getPoint()
  for _, u in ipairs(sortieUnits(s)) do                -- hard abort: anything defending inside abort_sep
    local up = u:getPoint()
    for _, f in ipairs(foes) do
      local sep = d3(up, f:getPoint())
      if sep < C.abort_sep_m then
        log("SHOW_ABORT", s.name, who(f), string.format("%.0f m", sep))
        sayGroup(tg, string.format("%s: the %s broke off - that was too close.", C.awacs, s.tdef.label), 10)
        return goHome(s, "abort", true)
      end
    end
  end
  if borderNm(lp) < C.show_border_nm then return endShow(s, "border") end
  if now - sh.t0 > sh.budget or (sh.paused and now - sh.paused > 90) then return endShow(s, "timeout") end
  local h = heading(tu)                                -- pause wide while the target is busy or low
  local dps = 0
  if sh.lastH then
    local dh = math.abs(h - sh.lastH)
    if dh > math.pi then dh = 2 * math.pi - dh end
    dps = math.deg(dh) / math.max(0.5, now - sh.lastT)
  end
  sh.lastH, sh.lastT = h, now
  local wing = grp(s.wing)
  if wing and C.formation ~= "follow" then steer(wing, tu, COVER) end
  if dps > C.max_turn_dps or agl(tp) < C.min_agl_m then
    sh.calm = nil
    if not sh.paused then
      sh.paused = now
      if sh.smoke then smoke(grp(s.lead), false); sh.smoke = false end
      log("SHOW_PAUSE", s.name, string.format("%.0f dps / %.0f m agl", dps, agl(tp)))
    end
    local side = (sh.at and sh.at[3] < 0) and -1 or 1
    sh.at = mirror(WIDE, side)
    formate(grp(s.lead), tg, tu, sh.at)
    return
  elseif sh.paused then
    sh.calm = sh.calm or now
    formate(grp(s.lead), tg, tu, sh.at)
    if now - sh.calm < 8 then return end
    sh.paused = nil
    log("SHOW_RESUME", s.name)
    pushStep(s)
    return
  end
  local step = sh.steps[sh.i]
  if C.formation ~= "follow" then steer(grp(s.lead), tu, step.pos) end
  local slot = slotWorld(tu, step.pos)
  local dist = d3(lp, slot)
  sh.best = math.min(sh.best or 1e9, dist)
  if now - sh.t0 > C.join_timeout_s and not sh.joined and d3(lp, tp) > NM then return endShow(s, "join stalled") end
  if not sh.arrived then
    if dist <= math.max(150, 0.35 * vlen(step.pos)) then
      sh.arrived, sh.joined, sh.inSlot = now, true, (sh.inSlot or 0) + 1
      log("SHOW_STEP", s.name, sh.i, step.stunt, "in slot", string.format("%.0f m", dist))
      if step.say then sayGroup(tg, string.format(step.say, "The " .. s.tdef.label), 12) end
    elseif now - sh.tStep > C.step_timeout_s then
      sh.arrived = now
      log("SHOW_STEP", s.name, sh.i, step.stunt, "timeout", string.format("closest %.0f m", sh.best))
    end
  end
  if sh.arrived and now - sh.arrived >= step.s then
    sh.i = sh.i + 1
    if sh.i > #sh.steps then return endShow(s, "done") end
    pushStep(s)
  end
end

local function escortTick(s, foes, dt)
  local any = false
  for _, u in ipairs(sortieUnits(s)) do
    local up = u:getPoint()
    for _, f in ipairs(foes) do
      if isFighter(f) and d2(up, f:getPoint()) <= lane(s, "escort_nm") * NM and math.abs(up.y - f:getPoint().y) <= lane(s, "escort_alt_m") then
        local n = who(f)
        s.escort[n] = (s.escort[n] or 0) + dt
        any = true
      end
    end
  end
  if any then s.escortS, s.lastEscort = s.escortS + dt, timer.getTime() end
  return any
end
local function bestEscort(s)
  local bn, bs = nil, 0
  for n, t in pairs(s.escort) do if t > bs then bn, bs = n, t end end
  return bn, bs
end

local function tickSortie(s, now, foes, dt)
  if s.n > 1 and s.wing == nil and now - s.t0 >= C.wing_delay_s then
    s.wing = spawn(s.tdef, "wing", s.route0) or false
  end
  if s.wing and not s.wingJoined then
    local wu = lead(s.wing)
    if wu and wu:inAir() and grp(s.lead) then s.wingJoined = true; if s.state ~= "SHOW" then wingRejoin(s) end end
  end
  local lu = lead(s.lead)
  if not lu then
    if s.wing and lead(s.wing) then
      log("LEAD_LOST", s.name, "wing takes lead")
      s.lead, s.wing = s.wing, nil
      lu = lead(s.lead)
      if s.state == "SHOW" then endShow(s, "lead lost")
      elseif s.state == "PROBE" or s.state == "STUBBORN" then probeRoute(s)
      elseif s.state == "COMPLY" or s.state == "RTB" then setRoute(grp(s.lead), homePoints(s))
      elseif s.state == "TRANSIT" then setRoute(grp(s.lead), s.route0) end
    else
      if s.state ~= "DONE" then log("LOST", s.name, s.state) end
      s.state = "DONE"
      return
    end
  end
  local lp = lu:getPoint()
  if now - s.t0 > C.max_sortie_s and s.state ~= "RTB" and s.state ~= "COMPLY" then goHome(s, "timeout") end

  local nearest, nd = nil, 1e9
  for _, f in ipairs(foes) do
    if isFighter(f) then
      local d = d2(lp, f:getPoint()) / NM
      if d < nd then nearest, nd = f, d end
    end
  end
  if s.tProbe and not s.tResponse and nd <= C.response_nm then
    s.tResponse = now - s.tProbe
    log("RESPONSE", s.name, who(nearest), mmss(s.tResponse))
  end
  if not s.intercepted and (s.state == "PROBE" or s.state == "TRANSIT" or s.state == "STUBBORN") then
    for _, u in ipairs(sortieUnits(s)) do
      local up = u:getPoint()
      for _, f in ipairs(foes) do
        local fp = f:getPoint()
        if isFighter(f) and d2(up, fp) <= lane(s, "intercept_nm") * NM and math.abs(up.y - fp.y) <= lane(s, "intercept_alt_m") then
          local n = who(f)
          s.close[n] = (s.close[n] or 0) + dt
          if s.close[n] >= C.intercept_s and not s.intercepted then
            s.intercepted = { by = n, unit = f, t = now - (s.tProbe or s.t0), nm = borderNm(up) }
          end
        end
      end
    end
    if s.intercepted then
      local i = s.intercepted
      log("INTERCEPT", s.name, i.by, mmss(i.t), string.format("%.0f", i.nm), s.pers)
      sayAll(string.format("%s: %s intercepted and identified by %s, %.0f NM off the border.", C.awacs, s.label, i.by, i.nm), 12)
      voice(s, "taunt")
      local n = rndi(s.P.stunts or 0)
      if s.showDone then
        if (s.P.escort_need_s or 0) > 0 then s.state, s.tStub, s.escortS = "STUBBORN", now, 0
        else s.state, s.tShowAt, s.tComplyAt = "SHADOWED", nil, now + rnd(s.P.comply_s or 30) end
      elseif n > 0 and s.tdef.stunts ~= false and not s.lane.land and i.unit:isExist() and borderNm(lp) >= C.show_border_nm + 1 then
        s.state, s.tShowAt = "SHADOWED", now + 5
      else
        s.state, s.tShowAt = "SHADOWED", nil
        s.tComplyAt = now + rnd(s.P.comply_s or 30)
      end
    end
  end

  if s.state == "LAUNCH" then
    if lu:inAir() then s.state = "TRANSIT"; log("AIRBORNE", s.name) end
  elseif s.state == "TRANSIT" then
    if d2(lp, s.legStart) <= 4 * NM then
      s.state, s.tProbe = "PROBE", now
      probeRoute(s)
      log("PROBE", s.name, s.lane.name, "depth " .. s.depth, string.format("%.1f NM", borderNm(lp)))
      sayAll(string.format("%s: new track - %s off %s, running along the border on the %s lane. Intercept and escort, weapons tight.",
        C.awacs, s.label, s.tdef.base or "their field", s.lane.name), 15)
    end
  elseif s.state == "PROBE" then
    if s.legEnd and d2(lp, s.legEnd) <= 3 * NM then
      s.laps = s.laps + 1
      if not s.tResponse then
        s.depth = math.min(C.max_depth, s.depth + 1)
        log("UNANSWERED", s.name, "lap " .. s.laps, "depth now " .. s.depth)
        if s.laps == 1 then sayAll(string.format("%s: nobody went out to the %s. They are coming in closer.", C.awacs, s.label), 12) end
      end
      if s.laps >= C.max_laps then
        if not s.intercepted then s.lane.bias = math.min(C.max_depth, s.lane.bias + 1) end
        goHome(s, "probe complete")
      else
        s.reverse = not s.reverse
        probeRoute(s)
      end
    end
  elseif s.state == "SHADOWED" then
    if s.tShowAt and now >= s.tShowAt then
      local tu = s.intercepted.unit
      if tu and tu:isExist() and tu:inAir() then startShow(s, tu) else goHome(s, "target gone") end
    elseif s.tComplyAt and now >= s.tComplyAt then
      goHome(s, "intercepted")
      sayAll(string.format("%s: the %s is turning for home. Shadow it out to %d NM.", C.awacs, s.label, C.release_nm), 12)
    end
  elseif s.state == "SHOW" then
    tickShow(s, now, foes, lu)
  elseif s.state == "STUBBORN" then
    if escortTick(s, foes, dt) and s.escortS >= s.P.escort_need_s then
      goHome(s, "walked out")
      sayAll(string.format("%s: the %s gave up and turned for home. Stay on him to %d NM.", C.awacs, s.label, C.release_nm), 12)
    elseif (now - math.max(s.lastEscort or 0, s.tStub)) > 120 then
      s.state = "PROBE"
      s.intercepted, s.close = nil, {}
      log("RESUME_PROBE", s.name)
    end
  elseif s.state == "COMPLY" then
    escortTick(s, foes, dt)
    local b = borderNm(lp)
    if b >= C.release_nm or not lu:inAir() or now - s.tComply > 1800 then
      local by, t = bestEscort(s)
      if by and t >= C.escort_credit_s then
        log("ESCORTED_OUT", s.name, by, string.format("%d", t))
        sayAll(string.format("%s: %s escorted the %s out past %d NM. Nicely done.", C.awacs, by, s.label, C.release_nm), 12)
        if s.tResponse and s.tResponse <= C.quick_response_s then s.lane.bias = math.max(0, s.lane.bias - 1) end
      else
        log("WITHDREW", s.name, "no escort")
      end
      s.state = "RTB"
    elseif not s.turnedBack and (s.P.turnback or 0) > 0 and (now - (s.lastEscort or s.tComply)) > C.turnback_after_s
           and (now - s.tComply) > C.turnback_after_s then
      s.turnedBack = true
      if math.random() < s.P.turnback then
        s.state = "PROBE"
        s.intercepted, s.close = nil, {}
        probeRoute(s)
        log("TURNBACK", s.name)
        sayAll(string.format("%s: the %s has turned BACK toward the border - he was waiting to see if you would follow him out.",
          C.awacs, s.label), 15)
      end
    end
  elseif s.state == "RTB" then
    s.tRTB = s.tRTB or now
    if not lu:inAir() then
      s.landedAt = s.landedAt or now
      if now - s.landedAt > 90 then s.state = "DONE" end
    elseif (not s.homeAb and s.homeEnd and d2(lp, s.homeEnd) <= 3 * NM) or now - s.tRTB > 2700 then
      s.despawn, s.state = true, "DONE"        -- no field to land at (air start) / never got down: remove him
    end
  end
end

local function cleanup(s)
  for _, n in ipairs({ s.lead, s.wing }) do
    local g = grp(n)
    if g then local u = g:getUnit(1); if s.despawn or not (u and u:inAir()) then pcall(function() g:destroy() end) end end
  end
  log("END", s.name, s.intercepted and s.intercepted.by or "not intercepted", bestEscort(s) or "no escort")
end

-- ========================================================= schedulers
local lastLaunch, nextGap = timer.getTime(), C.first_s
local t0 = timer.getTime()
for _, e in ipairs(C.schedule or {}) do e.next = t0 + (e.at or 0) end

local lastT
timer.scheduleFunction(function(_, t)
  local ok, err = pcall(function()
    local now = timer.getTime()
    local dt = lastT and (now - lastT) or 1
    lastT = now
    local foes = foeAir()
    local active = 0
    for _, s in ipairs(S) do
      if s.state ~= "DONE" then
        CUR = s
        tickSortie(s, now, foes, dt)
        if s.state == "DONE" then cleanup(s) else active = active + 1 end
        CUR = nil
      end
    end
    -- scripted launches: schedule = { { at = s, lane = , template = , personality = , tag = , every = s }, ... }
    for _, e in ipairs(C.schedule or {}) do
      if e.next and now >= e.next then
        e.next = e.every and (now + rnd(e.every)) or nil
        DAWG.launch{ lane = e.lane, template = e.template, personality = e.personality, tag = e.tag }
      end
    end
    -- Mission Editor flags: DAWG_LAUNCH, DAWG_LAUNCH_<LANE>, and cfg.launch_flags = { [flag] = { lane=, template=, personality= } }
    local function flagPers(v) return (v >= 2) and PERS_ORDER[v - 1] or nil end
    local function watch(f, o)
      local v = tonumber(trigger.misc.getUserFlag(f)) or 0
      if v > 0 then
        trigger.action.setUserFlag(f, 0)
        local spec = {}
        for k, x in pairs(o) do spec[k] = x end
        spec.personality = spec.personality or flagPers(math.floor(v))
        local s = DAWG.launch(spec)
        log("FLAG_LAUNCH", tostring(f), tostring(v), s and s.name or "failed")
      end
    end
    local function watchBoth(f, o)                -- the flag, and its old-name twin
      watch(f, o)
      local old = legacyName(f)
      if old then watch(old, o) end
    end
    if C.launch_flag then watchBoth(C.launch_flag, {}) end
    if C.lane_flag_prefix then
      for _, ln in ipairs(DAWG.lanes) do watchBoth(C.lane_flag_prefix .. ln.name:gsub("%s+", "_"), { lane = ln.name }) end
    end
    for f, o in pairs(C.launch_flags or {}) do watch(f, type(o) == "table" and o or {}) end
    if C.pause_flag then                         -- flag on = auto launches paused, off = resumed (edges only)
      local old = legacyName(C.pause_flag)
      local f = (trigger.misc.getUserFlag(C.pause_flag) or 0) > 0
        or (old ~= nil and (trigger.misc.getUserFlag(old) or 0) > 0)
      if f ~= DAWG.pauseFlagWas then DAWG.pauseFlagWas = f; DAWG.pause(f) end
    end
    if not DAWG.paused and active < C.max_active and now - lastLaunch >= nextGap and #DAWG.lanes > 0 then
      lastLaunch, nextGap = now, rnd(C.interval_s)
      DAWG.launch{ personality = nextPers }
      nextPers = nil
    end
  end)
  if not ok then env.error("[DAWG] tick error: " .. tostring(err)) end
  return t + 1
end, nil, timer.getTime() + 2)

-- ===================================================== defenders shoot
local H = {}
local function sortieOf(unit)
  local gn = unit and safe(function() return unit:getGroup():getName() end, nil)
  if not gn then return nil end
  for _, s in ipairs(S) do if s.lead == gn or s.wing == gn then return s end end
end
function H:onEvent(e)
  if not e then return end
  if e.id == world.event.S_EVENT_SHOT or e.id == world.event.S_EVENT_HIT then
    local tgt = (e.id == world.event.S_EVENT_SHOT) and e.weapon and safe(function() return e.weapon:getTarget() end, nil) or e.target
    local s = tgt and sortieOf(tgt)
    if s and s.state ~= "DONE" and s.state ~= "RTB" and not s.firedOn then
      s.firedOn = true
      CUR = s
      log("FIRED_ON", s.name, e.initiator and who(e.initiator) or "?")
      voice(s, "fired_on")
      if s.state ~= "COMPLY" then
        if s.state == "SHOW" then endShow(s, "fired on") else goHome(s, "fired on", true) end
      end
      CUR = nil
    end
  elseif e.id == world.event.S_EVENT_CRASH or e.id == world.event.S_EVENT_PILOT_DEAD then
    local u = e.initiator
    if u and safe(function() return u:getCoalition() end, -1) == FOE then
      for _, s in ipairs(S) do
        if s.state == "SHOW" then
          local lu = lead(s.lead)
          if lu and d3(lu:getPoint(), u:getPoint()) < 3000 then
            log("SHOW_MISHAP", s.name, who(u))
            env.warning("[DAWG] defender crashed within 3 km of a show - review min_sep_m / abort_sep_m")
          end
        end
      end
    end
  end
end
world.addEventHandler(H)

-- =============================================================== status
function DAWG.status()
  local L = { "DAWG v" .. VERSION .. " - probes" .. (DAWG.paused and " (auto launches PAUSED)" or "") }
  local n = 0
  for _, s in ipairs(S) do
    if s.state ~= "DONE" or timer.getTime() - s.t0 < 3600 then
      n = n + 1
      local by, et = bestEscort(s)
      L[#L + 1] = string.format("  %s%s [%s, %s] %s | response %s | ID %s | escort %s", s.tag and ("[" .. s.tag .. "] ") or "",
        s.label, s.lane.name, s.P.label or s.pers, s.state,
        s.tResponse and mmss(s.tResponse) or "-",
        s.intercepted and (s.intercepted.by .. " @" .. mmss(s.intercepted.t)) or "-",
        by and string.format("%s %ds", by, et) or "-")
    end
  end
  if n == 0 then L[#L + 1] = "  nothing out" end
  local lb = {}
  for _, ln in ipairs(DAWG.lanes) do lb[#lb + 1] = ln.name .. " +" .. ln.bias end
  L[#L + 1] = "  lane pressure: " .. table.concat(lb, ", ")
  sayStatus(table.concat(L, "\n"))
end
function DAWG.pause(p) DAWG.paused = p; log("PAUSE", tostring(p)) end
function DAWG.setPersonality(k) if PERS[k] then nextPers = k; return true end end
function DAWG.addPersonality(k, def) PERS[k] = def; PERS_ORDER[#PERS_ORDER + 1] = k end

if C.menu then
  local top = missionCommands.addSubMenuForCoalition(FOE, C.menu_name)
  missionCommands.addCommandForCoalition(FOE, "Status", top, DAWG.status)
  local ml = missionCommands.addSubMenuForCoalition(FOE, "Launch a probe now", top)
  for _, ln in ipairs(DAWG.lanes) do
    missionCommands.addCommandForCoalition(FOE, ln.name, ml, function()
      local s = DAWG.launch{ lane = ln.name, personality = nextPers }
      nextPers = nil
      trigger.action.outTextForCoalition(FOE, s and ("DAWG: launched " .. s.label .. " (" .. s.pers .. ") on " .. ln.name) or "DAWG: launch failed - see dcs.log", 8)
    end)
  end
  local mp = missionCommands.addSubMenuForCoalition(FOE, "Next probe's personality", top)
  for _, k in ipairs(PERS_ORDER) do
    missionCommands.addCommandForCoalition(FOE, PERS[k].label or k, mp, function()
      nextPers = k
      trigger.action.outTextForCoalition(FOE, "DAWG: next probe will be a " .. (PERS[k].label or k), 6)
    end)
  end
  missionCommands.addCommandForCoalition(FOE, "Pause / resume auto launches", top, function()
    DAWG.pause(not DAWG.paused)
    trigger.action.outTextForCoalition(FOE, "DAWG: auto launches " .. (DAWG.paused and "PAUSED" or "RESUMED"), 6)
  end)
end

-- ======================================== orders on Guard (through the DCS-ATC)
-- The ATC calls this when a fighter hails or orders one of our probes on Guard 243.0:
-- ev = { op = "hail" | "turn" | "leave" | "follow" | "land", arg, unit, name, flightName, ... }.
-- nil = not one of ours (the ATC answers itself); { text = ... } = what the pilot says
-- (the ATC speaks it through the probe's radio, and tasks nothing - his personality
-- decides, DAWG flies him). Talking to a stubborn pilot counts toward walking him out.
function DAWG.onGuard(ev)
  local s = ev and ev.unit and sortieOf(ev.unit)
  if not s or s.state == "DONE" then return nil end
  CUR = s
  local w = voiceWords(s)
  local by = ev.flightName or "?"
  local reply
  if ev.op == "hail" then
    s.hails = (s.hails or 0) + 1
    s.hailedBy = by
    reply = lineFor(s.hails == 1 and "hail" or "hail_again", s.pers)
    log("HAILED", s.name, by)
  else
    s.orders = (s.orders or 0) + 1
    s.hails = s.hails or 0
    s.hailedBy = s.hailedBy or by
    log("ORDERED", s.name, ev.op, by, "x" .. s.orders)
    local need = s.P.obeys or 1
    if s.state == "COMPLY" or s.state == "RTB" then
      reply = lineFor("leaving", s.pers)
    elseif ev.op == "land" then
      reply = lineFor("land", s.pers)                       -- nobody lands; it still counts as an order
    elseif s.orders < need then
      if s.state == "STUBBORN" then s.escortS = s.escortS + (C.voice_order_credit_s or 30) end   -- talking to him counts
      if ev.op == "follow" and lineFor("follow", s.pers) == nil then reply = lineFor("follow_refuse", s.pers)
      else reply = lineFor("refuse", s.pers, s.orders) end
    else
      s.saidLeaving = true
      reply = (ev.op == "follow" and lineFor("follow", s.pers)) or lineFor("comply", s.pers)
      if s.state == "SHOW" then endShow(s, "ordered by " .. by) else goHome(s, "ordered by " .. by) end
      sayAll(string.format("%s: the %s is complying with %s and turning for home. Shadow him out to %d NM.",
        C.awacs, s.label, by, C.release_nm), 12)
    end
  end
  CUR = nil
  if not reply then return { text = nil } end
  local text = fill(reply, w)
  log("VOICE", s.name, ev.op, text)
  return { text = text }
end
if C.voice and type(ATC) == "table" and ATC.Guard and ATC.Guard.register then
  ATC.Guard.register(DAWG.onGuard)
  log("VOICE", "on: the probes answer on Guard through the DCS-ATC")
end

if #POLYS == 0 then log("WARN", "no borders defined - probes have nothing to stay out of") end
if #DAWG.lanes == 0 then log("WARN", "no lanes - add DAWG LANE groups or cfg.lanes") end
if #TDEF == 0 then log("WARN", "no templates - add late-activated '" .. C.template_prefix .. " ...' groups or cfg.templates") end
log("LOADED", VERSION, #DAWG.lanes .. " lanes", #TDEF .. " templates", #POLYS .. " border polygons", "formation " .. C.formation)
env.info("[DAWG] loaded v" .. VERSION)
