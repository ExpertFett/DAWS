-- ============================================================================
-- DAWG example config - Caucasus, REAL borders. Everything given in Lua instead
-- of the Mission Editor: your mission needs late-activated groups with the
-- template names below. Load DAWG_borders_caucasus.lua FIRST, then this, then
-- DAWG.lua.
--   no-go = Georgia (de jure: incl. Abkhazia + South Ossetia) + its 12 NM
--   territorial sea; Turkey + its 12 NM sea; Armenia, Azerbaijan.
--   red fields: Sochi-Adler, Krymsk, Nalchik, Beslan, Mozdok.
--   Five lanes: GAGRA + POTI over the Black Sea (where shows happen), ELBRUS /
--   ROKI / DARIAL along the main ridge (shadowed from the Georgian side).
-- ============================================================================
DAWG_CONFIG = {
  side = "red",
  awacs = "OVERLORD",
  menu_name = "DAWG (GM)",
  first_s = 300, interval_s = { 900, 1500 }, max_active = 2,
  floor_nm = 2, step_nm = 4, max_depth = 3, release_nm = 30,
  min_sep_m = 100, abort_sep_m = 50, min_agl_m = 1500,
  weights = { book = 50, showboat = 35, hothead = 15 },

  borders = DAWG_BORDERS_CAUCASUS,

  templates = {
    { template = "DAWG_SU27_SOCHI",     label = "Flanker",  base = "Sochi",     flight = { 1, 2 }, smoke = true, alt = 7000, speed = 230 },
    { template = "DAWG_SU27_KRYMSK",    label = "Flanker",  base = "Krymsk",    flight = { 1, 2 }, smoke = true, alt = 7000, speed = 230 },
    { template = "DAWG_MIG29_KRYMSK",   label = "Fulcrum",  base = "Krymsk",    flight = 2,        smoke = true, alt = 6500, speed = 230 },
    { template = "DAWG_MIG29_NALCHIK",  label = "Fulcrum",  base = "Nalchik",   flight = 2,        smoke = true, alt = 8000, speed = 230 },
    { template = "DAWG_SU27_BESLAN",    label = "Flanker",  base = "Beslan",    flight = { 1, 2 }, smoke = true, alt = 8000, speed = 230 },
    { template = "DAWG_MIG31_MOZDOK",   label = "Foxhound", base = "Mozdok",    flight = 2, smoke = false, stunts = false,
      personality = "book", alt = 12000, speed = 280 },
  },

  -- Sea lanes: shows happen out here, in international airspace.
  -- Land lanes (over the main Caucasus ridge): nobody crosses into the other's
  -- airspace, so the defender shadows from his own side - wider ID / escort radii.
  lanes = {
    { name = "GAGRA", toward = 45, land = false,
      entry = { 43.30, 39.20 }, exit = { 43.45, 39.30 },
      leg = { { 43.11, 39.53 }, { 42.86, 39.98 }, { 42.61, 40.43 } },
      templates = { "DAWG_SU27_SOCHI", "DAWG_SU27_KRYMSK", "DAWG_MIG29_KRYMSK" } },
    { name = "POTI", toward = 90, land = false,
      entry = { 42.75, 39.80 }, exit = { 43.10, 39.20 },
      leg = { { 42.45, 40.91 }, { 42.10, 41.01 }, { 41.80, 41.11 } },
      templates = { "DAWG_SU27_KRYMSK", "DAWG_MIG29_KRYMSK", "DAWG_SU27_SOCHI" } },
    { name = "ELBRUS", toward = 180, land = true, intercept_nm = 15, escort_nm = 15,
      entry = { 43.80, 42.80 }, exit = { 43.80, 43.40 },
      leg = { { 43.50, 41.80 }, { 43.45, 42.40 }, { 43.35, 43.00 } },
      templates = { "DAWG_MIG29_NALCHIK", "DAWG_MIG31_MOZDOK" } },
    { name = "ROKI", toward = 180, land = true, intercept_nm = 15, escort_nm = 15,
      entry = { 43.30, 43.90 }, exit = { 43.40, 44.40 },
      leg = { { 43.00, 43.55 }, { 42.95, 43.95 }, { 42.95, 44.35 } },
      templates = { "DAWG_SU27_BESLAN", "DAWG_MIG29_NALCHIK" } },
    { name = "DARIAL", toward = 195, land = true, intercept_nm = 15, escort_nm = 15,
      entry = { 43.30, 44.90 }, exit = { 43.45, 44.70 },
      leg = { { 42.98, 44.75 }, { 42.90, 45.20 }, { 42.80, 45.65 } },
      templates = { "DAWG_SU27_BESLAN", "DAWG_MIG31_MOZDOK" } },
  },
}
