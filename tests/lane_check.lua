-- Print every lane's leg distance from the real borders at each push depth.
-- usage: luae lane_check.lua <DAWG dir>
local DIR = arg[1]
dofile(DIR .. "/tests/mock_dcs.lua")
dofile(DIR .. "/DAWG_borders_caucasus.lua")
dofile(DIR .. "/DAWG_config_Caucasus.lua")
DAWG_CONFIG.auto = false
dofile(DIR .. "/DAWG.lua")
local C = DAWG_CONFIG
local bad = 0
for _, lane in ipairs(DAWG.lanes) do
  local row = {}
  for d = 0, C.max_depth do
    local pts = DAWG.legAt(lane, d)
    local s = {}
    for _, p in ipairs(pts) do
      local b = DAWG.borderNm(p)
      s[#s + 1] = string.format("%5.1f", b)
      if b < C.floor_nm - 0.01 then bad = bad + 1 end
    end
    row[#row + 1] = "d" .. d .. "[" .. table.concat(s, " ") .. "]"
  end
  for _, k in ipairs({ "entry", "exit" }) do
    if lane[k] then row[#row + 1] = k .. string.format(" %.1f", DAWG.borderNm(lane[k])) end
  end
  print(string.format("%-7s %s", lane.name, table.concat(row, "  ")))
end
for _, l in ipairs(MOCK.logs) do if l:find("LANE_WARN", 1, true) or l:find("ERR", 1, true) then print(l); bad = bad + 1 end end
print(bad == 0 and "LANES OK" or ("LANE PROBLEMS " .. bad))
