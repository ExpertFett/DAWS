-- Test fixture config (tests only): a stylised Caucasus border - land south of a
-- simplified ridge line plus a 12 NM sea strip - three lanes, six runway templates.
-- The real-border example is DAWS_config_Caucasus.lua.
DAWS_CONFIG = {
  side = "red",                 -- the probing side
  awacs = "OVERLORD",           -- who makes the calls to the defenders
  menu_name = "DAWS (GM)",

  first_s = 300,                -- first automatic probe (s after the script loads)
  interval_s = { 900, 1500 },   -- then one every 15-25 min
  max_active = 2,               -- sorties out at once

  floor_nm = 2,                 -- closest any probe leg gets to the border
  step_nm = 4,                  -- how much deeper each "push" goes
  max_depth = 3,
  release_nm = 30,              -- escorted out = past this far from the border

  min_sep_m = 100,              -- no show position / path inside this of the target
  abort_sep_m = 50,             -- real separation below this = abort, break away
  min_agl_m = 1500,             -- no shows below this (defender AGL)

  weights = { book = 50, showboat = 35, hothead = 15 },

  border = {
    { 42.42, 41.28 },
    { 42.39, 41.56 }, { 42.72, 42.05 }, { 43.05, 42.65 }, { 43.10, 43.20 }, { 42.85, 43.90 }, { 42.66, 44.64 }, { 42.55, 45.20 },
    { 41.20, 46.60 }, { 41.10, 43.40 }, { 41.50, 41.55 }, { 41.50, 41.28 },
  },

  -- single-ship, late-activated, RUNWAY-start templates placed in the mission.
  -- smoke = carries a white smoke generator (the fuel-dump pass). stunts = false: never does a show.
  templates = {
    { template = "DAWS_SU27_SUKHUMI",  label = "Flanker",  base = "Sukhumi",  flight = { 1, 2 }, smoke = true,  alt = 7000, speed = 230 },
    { template = "DAWS_SU33_GUDAUTA",  label = "Su-33",    base = "Gudauta",  flight = { 1, 2 }, smoke = true,  alt = 7000, speed = 230 },
    { template = "DAWS_MIG29_GUDAUTA", label = "Fulcrum",  base = "Gudauta",  flight = 2,        smoke = true,  alt = 6500, speed = 230 },
    { template = "DAWS_MIG29_NALCHIK", label = "Fulcrum",  base = "Nalchik",  flight = 2,        smoke = true,  alt = 7500, speed = 230 },
    { template = "DAWS_SU27_BESLAN",   label = "Flanker",  base = "Beslan",   flight = { 1, 2 }, smoke = true,  alt = 7500, speed = 230 },
    -- the Foxhound runs high and fast, by the book, no show (and has no smoke pod in DCS)
    { template = "DAWS_MIG31_MOZDOK",  label = "Foxhound", base = "Mozdok",   flight = 2, smoke = false, stunts = false,
      personality = "book", alt = 12000, speed = 280 },
  },

  -- leg = flown parallel to the border, outside it. toward = compass bearing
  -- from the leg TO the border (the way a "push" moves it).
  lanes = {
    { name = "COAST", toward = 90,
      entry = { 42.80, 40.70 }, exit = { 43.15, 40.30 },
      leg = { { 42.70, 40.95 }, { 42.20, 40.95 }, { 41.70, 40.95 } },
      templates = { "DAWS_SU27_SUKHUMI", "DAWS_SU33_GUDAUTA", "DAWS_MIG29_GUDAUTA" } },
    { name = "RIDGE WEST", toward = 145,
      entry = { 43.40, 42.90 }, exit = { 43.50, 43.40 },
      leg = { { 42.97, 42.05 }, { 43.30, 42.65 } },
      templates = { "DAWS_MIG29_NALCHIK", "DAWS_SU27_BESLAN" } },
    { name = "RIDGE EAST", toward = 180,
      entry = { 43.55, 43.60 }, exit = { 43.55, 44.40 },
      leg = { { 43.35, 43.15 }, { 43.08, 43.90 }, { 42.92, 44.60 } },
      templates = { "DAWS_MIG29_NALCHIK", "DAWS_SU27_BESLAN", "DAWS_MIG31_MOZDOK" } },
  },
}
