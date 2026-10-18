-- ============================================================================
-- DAWS DEMO - five intercepts, five reactions (all AI, spectator, REAL borders).
--   1 HOTHEAD     GAGRA sea lane   Pontiac 1  show + fuel dump, refuses to leave until walked out
--   2 SHOWBOAT    POTI sea lane    Pontiac 2  a pass or two, then home
--   3 BY-THE-BOOK ROKI ridge       Pontiac 3  shadowed from the Georgian side, complies, goes home
--   4 TESTER      DARIAL ridge     Pontiac 4  complies - then turns BACK when Pontiac leaves
--   5 UNANSWERED  ELBRUS ridge     (nobody)   comes deeper every lap; the lane remembers
-- Each restarts ~90 s after its sortie heads home, so they keep cycling.
-- Over the sea Pontiac flies out into international airspace to intercept; over
-- the ridge nobody crosses - Pontiac shadows from 1 NM inside Georgia.
-- ============================================================================
local NM = 1852
local SC = {
  { tag = "1 HOTHEAD",     lane = "GAGRA",  tpl = "DEMO1_SU27",  pers = "hothead",  int = "Pontiac 1", kind = "sea",  hdg = 225, start = 20,
    orbit = { 42.95, 40.55 },
    expect = "a FUEL DUMP across Pontiac's nose, close passes, then he goes back to his probe track and has to be walked out" },
  { tag = "2 SHOWBOAT",    lane = "POTI",   tpl = "DEMO2_MIG29", pers = "showboat", int = "Pontiac 2", kind = "sea",  hdg = 270, start = 140,
    orbit = { 42.10, 41.50 }, expect = "one or two passes on Pontiac to show off, then he goes home" },
  { tag = "3 BY-THE-BOOK", lane = "ROKI",   tpl = "DEMO3_SU27",  pers = "book",     int = "Pontiac 3", kind = "land", start = 260,
    orbit = { 42.40, 43.90 }, expect = "shadowed along the ridge from the Georgian side; he complies and goes home. No drama" },
  { tag = "4 TESTER",      lane = "DARIAL", tpl = "DEMO4_MIG29", pers = "tester",   int = "Pontiac 4", kind = "land", start = 380,
    orbit = { 42.45, 44.85 }, expect = "he complies quickly - but when Pontiac goes home for fuel, he turns BACK to see if anyone is still watching" },
  { tag = "5 UNANSWERED",  lane = "ELBRUS", tpl = "DEMO5_MIG31", pers = "book",     int = nil,         start = 500,
    expect = "nobody goes up. Each lap he runs closer to the border (F10 map), and the NEXT probe on this lane starts deeper" },
}

local function say(sc, t, d) trigger.action.outText("[" .. sc.tag .. "] " .. t, d or 20) end
local function lg(...) env.info("DAWSDEMO|" .. string.format("%d", timer.getTime()) .. "|" .. table.concat({ ... }, "|")) end
local function wpt(x, z, alt, spd)
  return { x = x, y = z, alt = alt, alt_type = "BARO", type = "Turning Point", action = "Turning Point",
           speed = spd, speed_locked = true, task = { id = "ComboTask", params = { tasks = {} } } }
end

if not DAWS or not DAWS.launch then
  trigger.action.outText("DEMO: DAWS did not load - nothing will happen. Send Claude the DAWS lines from Saved Games\\DCS\\Logs\\dcs.log", 120)
  env.error("[DAWSDEMO] DAWS not loaded")
  return
end
for _, sc in ipairs(SC) do
  if sc.orbit then local p = coord.LLtoLO(sc.orbit[1], sc.orbit[2], 0); sc.home = { x = p.x, z = p.z } end
end

-- ------------------------------------------------------------ F10 map
do
  local id = 9000
  local function V(t) local p = coord.LLtoLO(t[1], t[2], 0); return { x = p.x, y = 0, z = p.z } end
  for _, b in ipairs(DAWS_CONFIG.borders or {}) do
    local sea = b.name:find("sea", 1, true)
    local geo = b.name:find("Georgia", 1, true)
    local line = sea and { 0.3, 0.6, 1, 0.9 } or (geo and { 1, 0.25, 0.25, 0.9 } or { 0.7, 0.7, 0.7, 0.8 })
    local fill = sea and { 0.3, 0.6, 1, 0.12 } or (geo and { 1, 0.25, 0.25, 0.08 } or { 0.7, 0.7, 0.7, 0.05 })
    local pts = {}
    for _, q in ipairs(b.points) do pts[#pts + 1] = V(q) end
    id = id + 1
    local ok = pcall(trigger.action.markupToAll, 7, -1, id, unpack(pts), line, fill, 1, true)
    if not ok then                                    -- fallback: plain lines
      for i = 1, #pts do id = id + 1; trigger.action.lineToAll(-1, id, pts[i], pts[i % #pts + 1], line, 1, true) end
    end
  end
  for _, sc in ipairs(SC) do
    local lane = DAWS.lanes[sc.lane]
    for _, d in ipairs({ 0, DAWS_CONFIG.max_depth }) do
      local pts = DAWS.legAt(lane, d)
      for i = 1, #pts - 1 do
        id = id + 1
        trigger.action.lineToAll(-1, id, { x = pts[i].x, y = 0, z = pts[i].z }, { x = pts[i + 1].x, y = 0, z = pts[i + 1].z },
          d == 0 and { 1, 0.85, 0.1, 0.95 } or { 1, 0.5, 0, 0.6 }, d == 0 and 1 or 2, true)
      end
    end
    local p = DAWS.legAt(lane, 0)[1]
    id = id + 1
    trigger.action.textToAll(-1, id, { x = p.x, y = 0, z = p.z }, { 1, 0.85, 0.1, 1 }, { 0, 0, 0, 0.4 }, 13, true, sc.tag .. " (" .. sc.lane .. ")")
    if sc.home then
      id = id + 1
      trigger.action.textToAll(-1, id, { x = sc.home.x, y = 0, z = sc.home.z }, { 0.5, 0.8, 1, 1 }, { 0, 0, 0, 0.4 }, 11, true, sc.int)
    end
  end
end

-- ------------------------------------------------------------ the interceptors
local function ai(sc, mode, fn)
  if sc.aiMode ~= mode then sc.aiMode = mode; lg("INT", sc.tag, sc.int, mode); pcall(fn) end
end

-- Ridge interceptors must never cross the border, and the straight line between
-- two points inside Georgia can still cut across Russia (South Ossetia's northern
-- notch). Sample the leg; wherever it gets within 1.5 NM of the line, push that
-- sample inward (lane bearing) to 2 NM inside and fly through it first.
local function insidePath(sc, from, to)
  local dir = DAWS.lanes[sc.lane].dir
  local pts, cur = {}, from
  for _ = 1, 4 do
    local bad
    for i = 1, 12 do
      local f = i / 12
      local q = { x = cur.x + (to.x - cur.x) * f, z = cur.z + (to.z - cur.z) * f }
      if DAWS.borderNm(q) > -1.5 then bad = q; break end
    end
    if not bad then break end
    for _ = 1, 80 do
      if DAWS.borderNm(bad) <= -2 then break end
      bad = { x = bad.x + dir.x * 0.5 * NM, z = bad.z + dir.z * 0.5 * NM }
    end
    pts[#pts + 1] = bad
    cur = bad
  end
  pts[#pts + 1] = to
  return pts
end

local function orbit(sc, c, u)
  ai(sc, "orbit", function()
    if sc.kind == "land" and u then         -- go home the long way round if the short way crosses
      local p = u:getPoint()
      local route = {}
      for _, q in ipairs(insidePath(sc, p, sc.home)) do route[#route + 1] = wpt(q.x, q.z, 7500, 220) end
      route[#route].task = { id = "ComboTask", params = { tasks = { { id = "Orbit", params = {
        pattern = "Circle", altitude = 7500, speed = 220 } } } } }
      c:setTask({ id = "Mission", params = { route = { points = route } } })
    else
      c:setTask({ id = "Orbit", params = { pattern = "Circle", point = { x = sc.home.x, y = sc.home.z }, altitude = 7500, speed = 220 } })
    end
  end)
end

local function flyInterceptor(sc, now)
  if not sc.int then return end
  local g = Group.getByName(sc.int)
  local u = g and g:getUnit(1)
  if not (u and u:isExist()) then return end
  local c = g:getController()
  pcall(function() c:setOption(AI.Option.Air.id.ROE, 4) end)
  local s = sc.s
  local bg = s and Group.getByName(s.lead)
  local bu = bg and bg:getUnit(1)
  local st = s and s.state
  if not bu or st == "RTB" or st == "DONE" or st == "LAUNCH" or st == "TRANSIT" or sc.bingo then return orbit(sc, c, u) end
  local b = bu:getPoint()
  if sc.kind == "land" then
    -- shadow abeam him, 2 NM inside Georgia: never cross the border
    local dir = DAWS.lanes[sc.lane].dir
    local bn = DAWS.borderNm(b)
    if bn > 20 then return orbit(sc, c, u) end         -- he's well clear: nothing to shadow
    local v = bu:getVelocity()
    local sp = math.sqrt(v.x * v.x + v.z * v.z)
    local lead = (st == "PROBE" or st == "STUBBORN") and 20 or 0   -- lead him only while he runs the border
    local k = (bn + 2) * NM
    local tx, tz = b.x + dir.x * k + v.x * lead, b.z + dir.z * k + v.z * lead
    -- the lane bearing isn't perpendicular to the border everywhere: walk the aim point in until it is
    -- at least 2 NM inside Georgia (never aim him across the line)
    for _ = 1, 80 do
      if DAWS.borderNm({ x = tx, z = tz }) <= -2 then break end
      tx, tz = tx + dir.x * 0.5 * NM, tz + dir.z * 0.5 * NM
    end
    sc.aiMode = "shadow"
    local route = {}
    for _, q in ipairs(insidePath(sc, u:getPoint(), { x = tx, z = tz })) do
      route[#route + 1] = wpt(q.x, q.z, b.y, math.max(200, math.min(330, sp + 30)))
    end
    pcall(function() c:setTask({ id = "Mission", params = { route = { points = route } } }) end)
    return
  end
  if st == "SHADOWED" or st == "SHOW" then
    return ai(sc, "steady", function()
      local p = u:getPoint()
      local h = math.rad(sc.hdg)
      c:setTask({ id = "Mission", params = { route = { points = {
        wpt(p.x + math.cos(h) * 200000, p.z + math.sin(h) * 200000, p.y, 220) } } } })
    end)
  end
  -- run him down and sit on his wing - on the coast side
  local a = u:getPoint()
  local d = math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2)
  if sc.aiMode ~= "follow" and sc.aiMode ~= "steer" then sc.tFollow = now end
  if sc.aiMode == "steer" or (sc.aiMode == "follow" and now - sc.tFollow > 120 and d > 3 * NM) then
    if sc.aiMode ~= "steer" then lg("INT", sc.tag, sc.int, "steer (follow did not close)") end
    sc.aiMode = "steer"
    local v = bu:getVelocity()
    local sp = math.sqrt(v.x * v.x + v.z * v.z)
    local hx, hz = (sp > 1) and v.x / sp or 1, (sp > 1) and v.z / sp or 0
    local side = sc.side or 1
    local tx, tz = b.x + hx * 2000 - hz * 1500 * side, b.z + hz * 2000 + hx * 1500 * side
    pcall(function() c:setTask({ id = "Mission", params = { route = { points = {
      wpt(tx, tz, b.y, math.min(400, sp + math.max(0, d - 1500) / 15)) } } } }) end)
  else
    ai(sc, "follow", function()
      local v = bu:getVelocity()
      local sp = math.sqrt(v.x * v.x + v.z * v.z)
      local hx, hz = (sp > 1) and v.x / sp or 1, (sp > 1) and v.z / sp or 0
      local r = DAWS.borderNm({ x = b.x - hz * 1500, z = b.z + hx * 1500 })      -- right side
      local l = DAWS.borderNm({ x = b.x + hz * 1500, z = b.z - hx * 1500 })      -- left side
      sc.side = (r <= l) and 1 or -1                                              -- the coast side
      c:setTask({ id = "Follow", params = { groupId = bg:getID(), pos = { x = 0, y = 0, z = 1500 * sc.side }, lastWptIndexFlag = false } })
    end)
  end
end

-- ------------------------------------------------------------ narration
local function narrate(sc, s, now)
  local st = s.state
  if st == "TRANSIT" then
    say(sc, string.format("%s mid-transit from %s toward the %s lane. Pilot: %s. Expect: %s.", s.label, s.tdef.base, sc.lane,
      string.upper(s.P.label or s.pers), sc.expect), 25)
  elseif st == "PROBE" and not sc.probed then
    sc.probed = true
    local lu = Group.getByName(s.lead) and Group.getByName(s.lead):getUnit(1)
    local how = (not sc.int) and "Nobody is going up for this one - watch the F10 map." or
      (sc.kind == "land" and (sc.int .. " moves up to shadow him from the Georgian side. Nobody crosses the border.") or
       (sc.int .. " is scrambling."))
    say(sc, string.format("Probe begun, %.0f NM off the border (lane pressure +%d). %s", lu and DAWS.borderNm(lu:getPoint()) or 0,
      DAWS.lanes[sc.lane].bias, how), 20)
  elseif st == "PROBE" and s.turnedBack and not sc.saidTurn then
    sc.saidTurn = true
    sc.bingo = nil
    say(sc, "He TURNED BACK the moment nobody was watching him leave. " .. sc.int .. " is coming back out to meet him.", 25)
  elseif st == "SHADOWED" then
    say(sc, "Identified" .. (sc.int and (" by " .. sc.int) or "") .. ". Watch what this pilot does now.", 15)
  elseif st == "SHOW" then
    say(sc, string.format("THE SHOW: %s flies straight and level, the %s formates on him and runs his passes; the wingman hangs back high. F2 onto the bandit.",
      sc.int, s.tdef.label), 20)
  elseif st == "STUBBORN" then
    say(sc, "Show's over - and he's gone BACK to his probe track. He won't leave until " .. sc.int .. " has sat on his wing for ~2.5 minutes.", 20)
  elseif st == "COMPLY" then
    if sc.pers == "tester" and not s.turnedBack then
      sc.bingo = true
      say(sc, "He complied fast and turned north. " .. sc.int .. " is bingo and heading home... watch the Fulcrums.", 20)
    elseif sc.kind == "land" then
      say(sc, "He's turned away from the border, heading home. " .. (sc.int or "Nobody") .. " holds at the border.", 15)
    else
      say(sc, string.format("He's turning for home. %s escorts him out past %d NM.", sc.int or "Nobody", DAWS_CONFIG.release_nm), 15)
    end
  elseif st == "RTB" then
    local lane = DAWS.lanes[sc.lane]
    say(sc, "Done - he's going home. " .. ((not sc.int) and string.format("Unanswered: this lane's pressure is now +%d, so the next probe here starts closer. ", lane.bias) or "") ..
      "Next one in about 90 s.", 20)
  end
end

local function launch(sc)
  local s = DAWS.launch(sc.lane, sc.tpl, sc.pers)
  if not s then trigger.action.outText("[" .. sc.tag .. "] launch failed - check dcs.log", 20) return end
  s.tag = sc.tag
  sc.s, sc.last, sc.aiMode, sc.nextAt, sc.probed, sc.saidTurn, sc.bingo = s, nil, nil, nil, nil, nil, nil
  sc.n = (sc.n or 0) + 1
  lg("LAUNCH", sc.tag, sc.n, s.name, s.pers)
end

timer.scheduleFunction(function(_, t)
  local now = timer.getTime()
  for _, sc in ipairs(SC) do
    local ok, err = pcall(function()
      if not sc.s and now >= sc.start then launch(sc) end
      local s = sc.s
      if not s then return end
      flyInterceptor(sc, now)
      local key = s.state .. (s.turnedBack and "+tb" or "")
      if key ~= sc.last then sc.last = key; narrate(sc, s, now) end
      if (s.state == "RTB" or s.state == "DONE") and not sc.nextAt then sc.nextAt = now + 90 end
      if sc.nextAt and now >= sc.nextAt then launch(sc) end
    end)
    if not ok then env.error("[DAWSDEMO] " .. sc.tag .. ": " .. tostring(err)) end
  end
  return t + 2
end, nil, timer.getTime() + 3)

local top = missionCommands.addSubMenu("DAWS DEMO")
missionCommands.addCommand("Status", top, function() DAWS.status() end)

timer.scheduleFunction(function()
  local L = { "DAWS DEMO - five intercepts, five different pilots. All AI: just watch. Real borders: red = Georgia, blue = 12 NM territorial sea." }
  for _, sc in ipairs(SC) do L[#L + 1] = string.format("  %s on the %s lane (T+%d:%02d): %s.", sc.tag, sc.lane, math.floor(sc.start / 60), sc.start % 60, sc.expect) end
  L[#L + 1] = "F10 map shows the lanes (yellow; dashed = deepest push) and the interceptors. F2/F6 to cycle cameras. Time acceleration is fine."
  trigger.action.outText(table.concat(L, "\n"), 60)
end, nil, timer.getTime() + 5)
env.info("[DAWSDEMO] five-scenario demo loaded")
