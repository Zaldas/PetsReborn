-- Status effects that silently remove an opposing effect when they land.
--
-- Keyed by the LANDING status ID; the value is the status the server removes. The removal is
-- silent (DelStatusEffectSilent), so no wear-off packet is ever sent.
--
-- No strength check needed: a refused effect arrives as "no effect" or a miss, never a status-on.
--
-- Source: LSB data/status_effects.yaml `negative` and `remove` (both deleted silently on landing,
-- status_effect_container.cpp AddStatusEffect). Not taken from it:
--   Bio/Dia (134/135)  the spell scripts delete each other by tier; owned by bioDiaData
--   Sleep (2/193->19)  every sleep is server status 2 and 19 is a client-side remap; owned
--                      by recordStatus and removeStatusFamily in statustracker.lua
--   En-spells (->51)   already covered by the `en` exclusion group
--   Copy Image (66->36) already covered by the Blink/Copy Image exclusion group
--   Kaustra/Embrava    (23/228) are post-75 effects and not tracked

return {
    -- Two-way pairs
    [33]  = 13,   -- Haste            -> Slow
    [13]  = 33,   -- Slow             -> Haste
    [12]  = 32,   -- Weight           -> Flee
    [32]  = 12,   -- Flee             -> Weight

    -- Boosts remove the matching down
    [80]  = 136,  -- STR Boost        -> STR Down
    [81]  = 137,  -- DEX Boost        -> DEX Down
    [82]  = 138,  -- VIT Boost        -> VIT Down
    [83]  = 139,  -- AGI Boost        -> AGI Down
    [84]  = 140,  -- INT Boost        -> INT Down
    [85]  = 141,  -- MND Boost        -> MND Down
    [86]  = 142,  -- CHR Boost        -> CHR Down
    [88]  = 144,  -- Max HP Boost     -> Max HP Down
    [89]  = 145,  -- Max MP Boost     -> Max MP Down
    [90]  = 146,  -- Accuracy Boost   -> Accuracy Down
    [91]  = 147,  -- Attack Boost     -> Attack Down
    [92]  = 148,  -- Evasion Boost    -> Evasion Down
    [93]  = 149,  -- Defense Boost    -> Defense Down

    -- Downs remove the matching boost
    [136] = 80,   -- STR Down         -> STR Boost
    [137] = 81,   -- DEX Down         -> DEX Boost
    [138] = 82,   -- VIT Down         -> VIT Boost
    [139] = 83,   -- AGI Down         -> AGI Boost
    [140] = 84,   -- INT Down         -> INT Boost
    [141] = 85,   -- MND Down         -> MND Boost
    [142] = 86,   -- CHR Down         -> CHR Boost
    [144] = 88,   -- Max HP Down      -> Max HP Boost
    [145] = 89,   -- Max MP Down      -> Max MP Boost
    [146] = 90,   -- Accuracy Down    -> Accuracy Boost
    [147] = 91,   -- Attack Down      -> Attack Boost
    [148] = 92,   -- Evasion Down     -> Evasion Boost
    [149] = 93,   -- Defense Down     -> Defense Boost

    -- Elemental DoT wheel: each removes the next
    [128] = 129,  -- Burn             -> Frost
    [129] = 130,  -- Frost            -> Choke
    [130] = 131,  -- Choke            -> Rasp
    [131] = 132,  -- Rasp             -> Shock
    [132] = 133,  -- Shock            -> Drown
    [133] = 128,  -- Drown            -> Burn

    -- Other
    [29]  = 6,    -- Mute             -> Silence
    [30]  = 9,    -- Bane             -> Curse
    [68]  = 460,  -- Warcry           -> Blood Rage
    [460] = 68,   -- Blood Rage       -> Warcry
}
