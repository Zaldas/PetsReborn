-- Bio/Dia: mirrors server logic (onSpellCast in dia.lua / bio.lua).
-- The status lands regardless of damage dealt, including casts that deal none at all
-- (bioDiaNoDamageMes). Applies only on a strictly higher tier — a same-tier recast does not
-- refresh the duration.
-- Tiers: Dia(1) < Bio(2) < DiaII(3) < BioII(4) < DiaIII(5) < BioIII(6)

return {
    [23]  = { statusId=134, opposing=135, tier=1, dur=60  },             -- Dia
    [33]  = { statusId=134, opposing=135, tier=1, dur=60  },             -- Diaga
    [24]  = { statusId=134, opposing=135, tier=3, dur=120, displayId=814 }, -- Dia II
    [34]  = { statusId=134, opposing=135, tier=3, dur=120, displayId=814 }, -- Diaga II
    [25]  = { statusId=134, opposing=135, tier=5, dur=180, displayId=821 }, -- Dia III
    [230] = { statusId=135, opposing=134, tier=2, dur=60  },             -- Bio
    [231] = { statusId=135, opposing=134, tier=4, dur=120, displayId=815 }, -- Bio II
    [232] = { statusId=135, opposing=134, tier=6, dur=180, displayId=820 }, -- Bio III
}
