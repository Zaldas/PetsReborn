-- Per-spell metadata applied in the statusOnMes path.
--   buffId    — override the status ID the server sends (e.g. Sleep II sends 2, we track as 19)
--   clears    — status IDs to remove before applying the new one
--   statusId  — expected status ID guard for displayId (must match ability.Param after buffId remap)
--   displayId — custom icon to show instead of the real status icon (base-tier spell clears it)

return {
    [259] = { buffId = 19, clears = {2, 193} },  -- Sleep II    → SLEEP_II (19), clears Sleep I + Lullaby
    [274] = { buffId = 19, clears = {2, 193} },  -- Sleepga II  → SLEEP_II (19), clears Sleep I + Lullaby
    [364] = { buffId = 19, clears = {2, 193} },  -- Sleepga III → SLEEP_II (19), clears Sleep I + Lullaby
    [221] = { statusId = 3, displayId = 816 },   -- Poison II   → custom icon (816)
    [226] = { statusId = 3, displayId = 816 },   -- Poisonga II → custom icon (816)
    [80]  = { statusId = 4, displayId = 817 },   -- Paralyze II → custom icon (817)
    [276] = { statusId = 5, displayId = 818 },   -- Blind II    → custom icon (818)
    [79]  = { statusId = 13, displayId = 819 },  -- Slow II     → custom icon (819)
}
