-- Minimal DCS mission-scripting mock + kinematic sim for DAWS offline tests.
-- Run with DCS's luae (Lua 5.1). Not a flight model: AI flies straight at its
-- waypoint / Follow slot at a capped speed, which is enough to drive the logic.
-- DCS's MissionScripting.lua sanitizes these out of the mission env; so do we
-- (math.randomseed being nil crashed DAWS v0.1 at load in the real sim, 2026-10-12)
math.randomseed = nil
os, io, lfs, require, loadlib = nil, nil, nil, nil, nil
MOCK = { t = 0, groups = {}, byName = {}, nextId = 100, texts = {}, logs = {}, cmds = {}, fns = {}, handlers = {} }
local M = MOCK

-- Caucasus lat/lon -> DCS x/z: cubic fit to pydcs's projection (max error < 4 m over 41-44.2N, 39.5-46E),
-- so lanes from the config and units from a real .miz share one frame
local CX = { -248873.328776, 111165.019378, 9300.405757, -18.308083, 24.104554, 499.636801, -0.008455, -5.840145, 0.720965, 1.096016 }
local CZ = { 681365.950615, -12568.239116, 82259.540088, -117.482377, -1351.421990, 9.022824, 0.691282, -11.928358, -4.451416, 0.180926 }
local function poly(c, a, b)
  return c[1] + c[2] * a + c[3] * b + c[4] * a * a + c[5] * a * b + c[6] * b * b + c[7] * a * a * a + c[8] * a * a * b + c[9] * a * b * b + c[10] * b * b * b
end
coord = {
  LLtoLO = function(lat, lon) local a, b = lat - 42.5, lon - 42.5; return { x = poly(CX, a, b), y = 0, z = poly(CZ, a, b) } end,
}
land = { getHeight = function() return M.ground or 0 end,
  SurfaceType = { LAND = 1, SHALLOW_WATER = 2, WATER = 3, ROAD = 4, RUNWAY = 5 },
  getSurfaceType = function(p) return (M.landFn and M.landFn(p)) and 1 or 3 end }
timer = {
  getTime = function() return M.t end,
  getAbsTime = function() return 36000 + M.t end,
  scheduleFunction = function(f, arg, at) M.fns[#M.fns + 1] = { f = f, arg = arg, at = at } end,
}
env = {
  info = function(s) M.logs[#M.logs + 1] = s; if M.verbose then print(s) end end,
  warning = function(s) M.logs[#M.logs + 1] = "WARN " .. s; print("WARN " .. s) end,
  error = function(s) M.logs[#M.logs + 1] = "ERR " .. s; print("ERR " .. s) end,
  mission = { coalition = { red = { country = { { id = 68, plane = { group = {} } } } }, blue = { country = {} } } },
}
M.flags = {}
trigger = { misc = { getUserFlag = function(f) return M.flags[f] or 0 end }, action = {
  setUserFlag = function(f, v) M.flags[f] = (v == true and 1) or (v == false and 0) or v end,
  outText = function(text) M.texts[#M.texts + 1] = "[ALL] " .. text end,
  lineToAll = function() end, textToAll = function() end, markToAll = function() end,
  outTextForCoalition = function(side, text) M.texts[#M.texts + 1] = "[C" .. side .. "] " .. text end,
  outTextForGroup = function(id, text) M.texts[#M.texts + 1] = "[G" .. id .. "] " .. text end,
} }
coalition = { side = { NEUTRAL = 0, RED = 1, BLUE = 2 } }
-- the engine's country -> coalition map. USSR (68) is NEUTRAL here on purpose: a tool-added
-- country spawned neutral through coalition.addGroup in the real engine (DCS-ATC, 2026-10-13)
M.countryCoalition = { [0] = 1, [2] = 2, [68] = 0, [80] = 2, [81] = 1 }
coalition.getCountryCoalition = function(id) return M.countryCoalition[id] or 0 end
Group = { Category = { AIRPLANE = 0, HELICOPTER = 1, GROUND = 2, SHIP = 3 } }
AI = { Option = { Air = { id = { ROE = 0, REACTION_ON_THREAT = 1, RTB_ON_BINGO = 6 } } } }
world = {
  event = { S_EVENT_SHOT = 1, S_EVENT_HIT = 2, S_EVENT_CRASH = 5, S_EVENT_PILOT_DEAD = 9 },
  addEventHandler = function(h) M.handlers[#M.handlers + 1] = h end,
  getAirbases = function() return M.airbases or {} end,
}
missionCommands = {
  addSubMenuForCoalition = function(_, name) return { name } end,
  addCommandForCoalition = function(_, name, path, fn) M.menu = M.menu or {}; M.menu[name] = fn end,
  addSubMenu = function(name) return { name } end,
  addCommand = function(name, path, fn) M.menu = M.menu or {}; M.menu[name] = fn end,
}

-- ------------------------------------------------------------ objects
local Unit, Grp, Ctl = {}, {}, {}
Unit.__index, Grp.__index, Ctl.__index = Unit, Grp, Ctl

function Unit:isExist() return not self.dead end
function Unit:inAir() return self.air end
function Unit:getPoint() return { x = self.p.x, y = self.p.y, z = self.p.z } end
function Unit:getVelocity() return { x = self.v.x, y = 0, z = self.v.z } end
function Unit:getName() return self.name end
function Unit:getPlayerName() return self.player end
function Unit:getGroup() return self.group end
function Unit:getCoalition() return self.group.side end
function Unit:getCountry() return self.group.country end
function Unit:getTypeName() return self.type or "jet" end
function Unit:hasAttribute(a) return self.attrs and self.attrs[a] or false end

function Grp:isExist() return not self.gone end
function Grp:getSize() return (self.u and not self.u.dead) and 1 or 0 end
function Grp:getUnit() return self.u end
function Grp:getUnits() return { self.u } end
function Grp:getName() return self.name end
function Grp:getCoalition() return self.side end
function Grp:getID() return self.id end
function Grp:getController() return self.ctl end
function Grp:destroy() self.gone = true; self.u.dead = true end

function Ctl:setTask(t) self.task = t; if t.id == "Mission" then self.wpi = 1 end end
function Ctl:setOption(k, v) self.opts = self.opts or {}; self.opts[k] = v end
function Ctl:setCommand(c) M.cmds[#M.cmds + 1] = { t = M.t, g = self.g.name, c = c } end

function M.addGroup(side, name, p, opts)
  M.nextId = M.nextId + 1
  local g = setmetatable({ name = name, id = M.nextId, side = side }, Grp)
  g.ctl = setmetatable({ g = g }, Ctl)
  g.u = setmetatable({ name = name, group = g, p = { x = p.x, y = p.y or 0, z = p.z }, v = { x = 0, z = 0 },
                       air = opts and opts.air or false, attrs = opts and opts.attrs, player = opts and opts.player,
                       speed = opts and opts.speed or 230 }, Unit)
  M.groups[#M.groups + 1] = g
  M.byName[name] = g
  return g
end
Airbase = { getByName = function(n)
  for _, ab in ipairs(M.airbases or {}) do if ab.name == n then return ab end end
end }
function Group.getByName(n) local g = M.byName[n]; if g and not g.gone then return g end end
coalition.getGroups = function(side, cat)
  local out = {}
  for _, g in ipairs(M.groups) do if g.side == side and not g.gone then out[#out + 1] = g end end
  return out
end
coalition.addGroup = function(cid, cat, data)
  local p1 = data.route.points[1]
  if M.byName[data.name] then M.byName[data.name].gone = true end      -- same name replaces, like DCS
  local g = M.addGroup(coalition.getCountryCoalition(cid), data.name, { x = p1.x, y = 0, z = p1.y }, { attrs = { Fighters = true } })
  g.country = cid
  g.ctl.task = { id = "Mission", params = { route = data.route } }
  g.ctl.wpi = 2
  g.spawnT = M.t
  return g
end

-- ------------------------------------------------------------ kinematics
local function step(u, tx, ty, tz, spd, dt)
  local dx, dy, dz = tx - u.p.x, ty - u.p.y, tz - u.p.z
  local d = math.sqrt(dx * dx + dz * dz)
  local s = math.min(spd * dt, d)
  if d > 0.01 then
    u.v = { x = dx / d * s / dt, z = dz / d * s / dt }
    u.p.x, u.p.z = u.p.x + dx / d * s, u.p.z + dz / d * s
  end
  u.p.y = u.p.y + math.max(-60 * dt, math.min(60 * dt, dy))
  return d
end

function M.slot(tu, pos)
  local h = math.atan2(tu.v.z, tu.v.x)
  local c, s = math.cos(h), math.sin(h)
  return tu.p.x + pos.x * c - pos.z * s, tu.p.y + pos.y, tu.p.z + pos.x * s + pos.z * c
end

function M.tick(dt)
  for _, g in ipairs(M.groups) do              -- AI first, scripted defenders after (they react to where AI is)
    local u = g.u
    if not g.gone and not u.dead then
      if g.script then
      else
        local task = g.ctl.task
        if not u.air and g.spawnT and M.t - g.spawnT >= 20 and not u.landed then u.air = true; u.p.y = 500 end
        if u.air and task and task.id == "Mission" then
          local pts = task.params.route.points
          local w = pts[g.ctl.wpi or 1]
          if w then
            local d = step(u, w.x, w.alt or u.p.y, w.y, w.speed or 230, dt)
            if d < 600 then
              if w.type == "Land" then u.air, u.landed, u.p.y = false, true, 0; u.v = { x = 0, z = 0 }
              else g.ctl.wpi = (g.ctl.wpi or 1) + 1 end
            end
          end
        elseif u.air and task and task.id == "Orbit" then
          local c = task.params.point
          local a = math.atan2(u.p.z - c.y, u.p.x - c.x) + (task.params.speed or 220) * dt / 6000
          step(u, c.x + 6000 * math.cos(a), task.params.altitude or u.p.y, c.y + 6000 * math.sin(a), task.params.speed or 220, dt)
        elseif u.air and task and task.id == "Follow" then
          local tg
          for _, o in ipairs(M.groups) do if o.id == task.params.groupId then tg = o end end
          -- like the real engine (2026-10-17 run): Follow does not hold on another coalition's group
          if tg and not tg.gone and tg.side == g.side then
            local x, y, z = M.slot(tg.u, task.params.pos)
            local ts = math.sqrt(tg.u.v.x ^ 2 + tg.u.v.z ^ 2)
            step(u, x, y, z, ts + 120, dt)
          end
        end
      end
    end
  end
  for _, g in ipairs(M.groups) do
    if g.script and not g.gone and not g.u.dead then g.script(g.u, M.t, dt) end
  end
  M.t = M.t + dt
  local due = {}
  for i = #M.fns, 1, -1 do if M.fns[i].at <= M.t then due[#due + 1] = table.remove(M.fns, i) end end
  for _, f in ipairs(due) do
    local nt = f.f(f.arg, M.t)
    if nt then M.fns[#M.fns + 1] = { f = f.f, arg = f.arg, at = nt } end
  end
end

function M.addTemplate(name, lat, lon, abId)
  local p = coord.LLtoLO(lat, lon)
  table.insert(env.mission.coalition.red.country[1].plane.group, {
    name = name, groupId = 1, lateActivation = true,
    units = { { name = name .. "-1", unitId = 1, type = "Su-27", x = p.x, y = p.z } },
    route = { points = { { x = p.x, y = p.z, alt = 0, type = "TakeOff", action = "From Runway", airdromeId = abId } } },
  })
  M.airbases = M.airbases or {}
  M.airbases[#M.airbases + 1] = { getName = function() return "AB" .. abId end, getID = function() return abId end, getPoint = function() return { x = p.x, y = 0, z = p.z } end }
end

function M.grep(pat)
  local out = {}
  for _, l in ipairs(M.logs) do if l:find(pat, 1, true) then out[#out + 1] = l end end
  return out
end
