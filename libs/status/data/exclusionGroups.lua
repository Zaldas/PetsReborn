-- Status effects that share a server-side exclusion group: only ONE member may be active at
-- a time, and applying any member removes the others.
--
-- The server's removal is silent (DelStatusEffectsByType uses EffectNotice::Silent), so no
-- wear-off packet is ever sent. Without modelling it here the previous member lingers on a
-- mob until its own timer runs out, and the mob shows two en-spells or two spike effects.
--
-- Keyed by STATUS EFFECT ID. Source: LSB data/status_effects.yaml `exclusion_group`.
--
-- Deliberately absent: the sleep group (2/19/193) has its own dedicated path in
-- statustracker.lua, and the petrification group (7/18/28) has no tracked case where two
-- members can collide.
--
-- The `shadow` group below is ours, not the server's. LSB splits it: exclusion_group `blink`
-- covers 36/444/445/446, while copy_image (66) instead carries `remove: blink` and blink
-- carries `block: copy_image`. The observable result is the same in both directions -- an
-- entity can never hold Blink and Copy Image at once -- so one group models it.

local groupOf = {
    -- enfire: every en-spell tier, plus Blood Weapon and Auspice
    [51]  = 'en',  -- Blood Weapon
    [94]  = 'en',  -- Enfire
    [95]  = 'en',  -- Enblizzard
    [96]  = 'en',  -- Enaero
    [97]  = 'en',  -- Enstone
    [98]  = 'en',  -- Enthunder
    [99]  = 'en',  -- Enwater
    [274] = 'en',  -- Enlight
    [275] = 'en',  -- Auspice
    [277] = 'en',  -- Enfire II
    [278] = 'en',  -- Enblizzard II
    [279] = 'en',  -- Enaero II
    [280] = 'en',  -- Enstone II
    [281] = 'en',  -- Enthunder II
    [282] = 'en',  -- Enwater II
    [288] = 'en',  -- Endark
    [487] = 'en',  -- Endrain
    [488] = 'en',  -- Enaspir

    -- blaze_spikes: all spike variants are mutually exclusive
    [34]  = 'spikes',  -- Blaze Spikes
    [35]  = 'spikes',  -- Ice Spikes
    [38]  = 'spikes',  -- Shock Spikes
    [153] = 'spikes',  -- Damage Spikes
    [173] = 'spikes',  -- Dread Spikes
    [403] = 'spikes',  -- Reprisal
    [573] = 'spikes',  -- Deluge Spikes
    [605] = 'spikes',  -- Gale Spikes
    [606] = 'spikes',  -- Clod Spikes
    [607] = 'spikes',  -- Glint Spikes

    -- shadow: Blink, Copy Image, and the Utsusemi image counters
    [36]  = 'shadow',  -- Blink
    [66]  = 'shadow',  -- Copy Image
    [444] = 'shadow',  -- Copy Image (2)
    [445] = 'shadow',  -- Copy Image (3)
    [446] = 'shadow',  -- Copy Image (4+)
}

-- Reverse index, built once at load so clearing is a single array walk.
local members = {}
for statusId, group in pairs(groupOf) do
    members[group] = members[group] or {}
    table.insert(members[group], statusId)
end

return {
    groupOf = groupOf,
    members = members,
}
