-- Status effects that silently remove an opposing effect when they land.
--
-- Keyed by the LANDING status ID; the value is the status the server removes. The removal is
-- silent (DelStatusEffectSilent), so no wear-off packet is ever sent. Most pairs are one-way:
-- a boost removes its matching down, but a down landing leaves the boost in place.
--
-- No strength check needed: a refused effect arrives as "no effect" or a miss, never a status-on.
--
-- Source: LSB data/status_effects.yaml `negative`. Not taken from it:
--   Bio/Dia (134/135)  the spell scripts delete each other by tier; owned by bioDiaData
--   Sleep (2/193->19)  every sleep is server status 2 and 19 is a client-side remap; owned
--                      by spellMeta and the sleep-family wear-off handling
--   En-spells (->51)   already covered by the `en` exclusion group
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
}
