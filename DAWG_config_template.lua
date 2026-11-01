-- ============================================================================
-- DAWG config template (DAWG v1.0.0-beta).  OPTIONAL - DAWG runs without it.
-- Copy this file, uncomment what you want to change, and load it with DO SCRIPT
-- FILE *before* DAWG.lua. Everything left commented keeps the default shown.
-- Points are { lat, lon } in degrees (or { x = , z = } in DCS metres).
-- ============================================================================
DAWG_CONFIG = {

  -- ---------------------------------------------------------------- general
  -- side = "red",                 -- the probing side ("red" or "blue")
  -- awacs = "OVERLORD",           -- callsign that makes the calls to the defenders
  -- messages = true,              -- text calls on screen
  -- msg_all = false,              -- true = calls to EVERYONE (spectator / demo missions)
  -- group_msgs_to_all = false,    -- true = close-pass calls to the whole defending side, not just the target
  -- menu = true,                  -- F10 GM menu for the defending side
  -- menu_name = "DAWG (GM)",

  -- ------------------------------------------------------- automatic launches
  -- auto = true,                  -- false = only launches you ask for (schedule / flags / F10 / API)
  -- first_s = 600,                -- first automatic probe, seconds after DAWG loads
  -- interval_s = { 900, 1500 },   -- then one every 15-25 min (random between the two)
  -- max_active = 2,               -- automatic probes out at once

  -- -------------------------------------------------------------- pilots
  -- Chance of each personality for a probe that has no fixed one.
  -- weights = { book = 45, showboat = 30, hothead = 15, tester = 10 },
  --
  -- Change a built-in personality, or add your own (any name):
  -- personalities = {
  --   hothead = { escort_need_s = 240 },               -- make hotheads harder to walk out
  --   cowboy  = { label = "cowboy", depth = 2, stunts = { 3, 3 }, opens_with = "sit_six",
  --               pool = { "sit_six", "canopy_pass", "nose_cross" },
  --               comply_s = { 0, 0 }, escort_need_s = 60, turnback = 0.5 },
  -- },
  --   depth          steps closer to the border he starts (each step_nm)
  --   stunts         { min, max } close passes once identified (0 = none)
  --   pool           which passes he picks from (see "stunts" below)
  --   opens_with     a pass he always does first (fuel_dump needs a smoke pod)
  --   comply_s       { min, max } s after the ID before he turns home (pilots with no show)
  --   escort_need_s  after his show: seconds of escort before he gives up (0 = leaves at once)
  --   turnback       chance (0-1) he turns back if nobody follows him out
  -- (add one to weights = { ... } if it should come up at random)

  -- ---------------------------------------------------------------- borders
  -- Leave both out to use the map's built-in real borders (load DAWG_borders_<map>.lua)
  -- and/or Mission Editor polygon zones named "DAWG BORDER ...".
  -- border = { { 42.42, 41.28 }, { 42.39, 41.56 }, ... },          -- one no-go polygon
  -- borders = { { name = "Georgia", points = { ... } }, ... },     -- several

  -- ---------------------------------------------------------------- probing
  -- floor_nm = 2,                 -- closest any probe gets to a border
  -- step_nm = 4,                  -- how much closer each "push" goes
  -- max_depth = 3,                -- most pushes (unanswered probes and lane memory add them)
  -- max_laps = 3,                 -- passes along the leg before he gives up and goes home

  -- --------------------------------------------------- intercept / escort
  -- response_nm = 20,             -- a defending fighter this close = "response" (timed)
  -- intercept_nm = 2,             -- identified = a defender inside this ...
  -- intercept_alt_m = 1000,       -- ... within this much altitude ...
  -- intercept_s = 10,             -- ... for this long
  -- escort_nm = 3, escort_alt_m = 1500,
  -- escort_credit_s = 60,         -- escort time needed to be credited with ESCORTED_OUT
  -- release_nm = 30,              -- "out" = this far from the border (or landed)
  -- land_intercept_nm = 15, land_escort_nm = 15,   -- lanes over land: you shadow from your own side
  -- turnback_after_s = 90,        -- unescorted this long while leaving -> may turn back

  -- ------------------------------------------------------------------ shows
  -- min_sep_m = 100,              -- no pass position, or path between two, inside this of the target
  -- abort_sep_m = 50,             -- anything defending this close = abort, break away
  -- min_agl_m = 1500,             -- no shows with the target below this
  -- max_turn_dps = 9,             -- target turning harder = pause, move out wide
  -- show_border_nm = 1,           -- no shows this close to a border
  -- formation = "steer",          -- "steer" (any target) or "follow" (DCS Follow task, same coalition only)

  -- ------------------------------------------------------ voices (needs DCS-ATC)
  -- voice = true,                 -- with the DCS-ATC script in the mission the probes answer on Guard 243.0
  -- voice_order_credit_s = 30,    -- each order to a stubborn pilot counts this much toward walking him out
  -- voice_lines = {               -- override any line: a string, a per-pilot table, a list, or false (silence)
  --   land = "Nyet, {you}.",      -- {you} {who} {type} = "American aircraft", "Soviet Air Force", "Su twenty seven"
  -- },
  -- Keys: hail hail_again refuse comply follow follow_refuse land leaving leaving_now taunt show fuel_dump fired_on
  -- obeys (under personalities): orders on Guard before he turns for home - book 1, showboat 2, hothead 3, tester 1
  --
  -- Your own pass (offsets from the target in metres: { ahead, up, right }, written for the right side;
  -- the first string is the call when the step marked say = true is reached). Validated against min_sep_m.
  -- stunts = {
  --   high_wing = { "%s is sitting high on your wing.", { pos = { 0, 80, 250 }, s = 30, say = true } },
  -- },
  -- Built in: wing_look, close_wing, nose_cross, fuel_dump, belly_check, canopy_pass, sit_six

  -- ------------------------------------------------------------- templates
  -- Leave out to use late-activated groups of the probing side named "DAWG ...".
  -- templates = {
  --   { template = "Su-27 Sochi",            -- the late-activated group (single ship is fine)
  --     label = "Flanker",                   -- what the calls say (default: NATO name of the type)
  --     base = "Sochi",                      -- for the calls
  --     home = "Sochi-Adler",                -- landing field for AIR-START templates (runway starts go home)
  --     flight = { 1, 2 },                   -- singles or pairs (lead + wing spawn as separate groups)
  --     smoke = true,                        -- has a smoke pod (default: read from its payload)
  --     stunts = true,                       -- false = never does a show (default false for bombers / big jets)
  --     personality = "hothead",             -- always this pilot (else weights)
  --     weights = { hothead = 50, book = 50 },
  --     alt = 7000, speed = 230 },           -- cruise, metres / m/s (default: its 2nd waypoint)
  -- },

  -- ----------------------------------------------------------------- lanes
  -- Leave out to use late-activated groups named "DAWG LANE <name>" (waypoints = the leg).
  -- lanes = {
  --   { name = "GAGRA",
  --     leg = { { 43.11, 39.53 }, { 42.86, 39.98 }, { 42.61, 40.43 } },   -- parallel to the border, outside it
  --     toward = 45,                       -- bearing to the border (default: worked out from the borders)
  --     entry = { 43.30, 39.20 }, exit = { 43.45, 39.30 },                -- optional
  --     land = false,                      -- over land? (default: worked out from the terrain)
  --     templates = { "Su-27 Sochi" },     -- who flies it (default: templates tagged @GAGRA, else all)
  --     personality = nil, weights = nil,  -- lane-wide pilot choice
  --     intercept_nm = nil, escort_nm = nil },
  -- },

  -- -------------------------------------------------- scripted launches
  -- schedule = {
  --   { at = 300, lane = "GAGRA", personality = "hothead", tag = "Opening act" },
  --   { at = 1200, lane = "ROKI", every = { 1800, 2400 } },    -- repeats
  -- },

  -- --------------------------------------------- Mission Editor flags
  -- DAWG watches:  DAWG_LAUNCH  (any lane)   DAWG_LAUNCH_<LANE>  (spaces -> _)   DAWG_PAUSE
  --   set > 0 to launch; the VALUE picks the pilot: 1 weights, 2 book, 3 showboat, 4 hothead, 5 tester
  -- DAWG counts up (+1 each time):  DAWG_LAUNCHED DAWG_PROBE DAWG_INTERCEPT DAWG_SHOW DAWG_FUEL_DUMP
  --   DAWG_ESCORTED_OUT DAWG_WITHDREW DAWG_UNANSWERED DAWG_TURNBACK DAWG_FIRED_ON DAWG_SHOW_ABORT DAWG_LOST
  -- launch_flag = "DAWG_LAUNCH", lane_flag_prefix = "DAWG_LAUNCH_", pause_flag = "DAWG_PAUSE",
  -- event_flags = { INTERCEPT = "DAWG_INTERCEPT", ... },      -- false = none
  -- launch_flags = { [100] = { lane = "GAGRA", personality = "hothead" } },   -- your own numbered flags

  -- ------------------------------------------------- naming (discovery)
  -- template_prefix = "DAWG", lane_prefix = "DAWG LANE", border_prefix = "DAWG BORDER",
  -- legacy_names = true,          -- also accept the old name everywhere ("DAWS ..." groups, DAWS_LAUNCH,
                                   -- DAWS_CONFIG, DAWS_BORDERS_<MAP>) and write the counters as DAWS_* too

  -- --------------------------------------------------------------- misc
  -- roe = 4,                      -- probing side's air ROE (4 = weapons hold, 3 = return fire)
  -- wing_delay_s = 45,            -- wingman launches this long after the lead (runway spacing)
  -- max_sortie_s = 5400,
}
