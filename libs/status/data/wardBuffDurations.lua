-- Blood pact ward buff durations: SMN avatar ward pacts that apply status effects to party
-- members via addStatusEffect() server-side.  Fire as type 13 (blood pact) actions with
-- msg=JA_GAIN_EFFECT (266) or SKILL_GAIN_EFFECT_2 (319) -- Rolling Thunder uses 267/320 --
-- and ability.Param = statusId.
-- Keyed by blood pact ability ID (action.Param for type 13).
-- Duration = base value; actual in-game duration for skill-scaled pacts (Shining Ruby,
-- Hastega) is 180 + clamp(summoning_skill - 300, 0, 200) s.  180 is conservative minimum.
-- Source: LSB scripts/actions/abilities/pets/<name>.lua

return {
    [514] = 180,  -- Shining Ruby     (Carbuncle) → SHINING_RUBY (154), 180s base [shining_ruby.lua]
    [515] = 90,   -- Glittering Ruby  (Carbuncle) → random stat boost,  90s       [glittering_ruby.lua]
    [548] = 180,  -- Crimson Howl     (Ifrit)     → WARCRY       (68),  180s (Horizon; LSB 60s+bonus)
    [564] = 900,  -- Earthen Ward     (Titan)     → STONESKIN    (37),  900s      [earthen_ward.lua]
    [579] = 180,  -- Spring Water     (Leviathan) → REFRESH      (43),  180s (Horizon)
    [595] = 180,  -- Hastega          (Garuda)    → HASTE        (33),  180s base [hastega.lua]
    [596] = 900,  -- Aerial Armor     (Garuda)    → BLINK        (36),  900s      [aerial_armor.lua]
    [610] = 180,  -- Frost Armor      (Shiva)     → ICE_SPIKES   (35),  180s base [frost_armor.lua]
    [626] = 120,  -- Rolling Thunder  (Ramuh)     → ENTHUNDER    (98),  120s base [rolling_thunder.lua]
    [628] = 180,  -- Lightning Armor  (Ramuh)     → SHOCK_SPIKES (38),  180s base [lightning_armor.lua]
    [658] = 90,   -- Nightmare        (Diabolos)  → SLEEP_I      (2),   90s base  [nightmare.lua]
    [660] = 180,  -- Noctoshield      (Fenrir)    → PHALANX      (116), 180s base [noctoshield.lua]
    [661] = 180,  -- Dream Shroud     (Diabolos)  → MAGIC_ATK/DEF_BOOST, 180s base [dream_shroud.lua]
}
