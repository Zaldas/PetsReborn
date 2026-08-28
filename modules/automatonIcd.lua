-- modules/automatonIcd.lua
-- Tracks the automaton's internal cooldowns: the magic gates its controller enforces between
-- casts, and the recasts its attachment abilities apply to themselves.
--
-- Neither is exposed in client memory. The equipped head, frame and attachments arrive in the
-- 0x0044 PUP packet, and every gate is timed from the automaton's own actions -- packets.lua
-- decodes those and calls onCast/onMobSkill.
--
-- Sole owner of the internal-cooldown recast rows: data.lua appends slots() to the automaton's
-- ability slots, and PetsReborn.lua rebuilds those rows whenever signature() changes.

local cooldownData = require('data/automatonCooldowns')

local M = {}

local enabled     = true
local head        = nil
local frame       = nil
local attachments = nil    -- [1..12] raw 0x0044 byte, 0 for an empty slot

-- Start time of the last observed use, keyed by gate id for gates and by skill id for
-- attachment abilities. No stamp means ready, so everything that ends an automaton must drop
-- the stamps with it or the next one inherits them.
local stamps       = {}
local trackedPetId = 0

local cachedSignature = nil
local cachedSlots     = {}

-- Skill id -> recast, for every attachment ability the data file knows. Doubles as the set of
-- mob skills worth stamping.
local skillCooldown = {}
for _, entry in pairs(cooldownData.attachmentAbilities) do
    skillCooldown[entry.skillId] = entry.cooldown
end

local function gateSlot(id, displayName, key, duration, isAttachment)
    return {
        id           = 'icd:' .. id,
        displayName  = displayName,
        requiresPet  = true,
        isIcd        = true,
        isAttachment = isAttachment,
        icdKey       = key,
        icdDuration  = duration,
    }
end

-- Every attachment ability the data file knows, deduped by skill id because tiers share one
-- recast. Built once and independent of what is fitted: the settings list offers all of them
-- so a choice can be made before the automaton is ever called, while slots() stays equipment
-- driven and decides what actually renders.
--
-- attachmentAbilities is keyed by item id, so pairs() order varies between runs; the sort is
-- what keeps the settings list from reshuffling itself.
local attachmentOptions = {}
do
    -- The lowest item id of a skill id's family is its base tier, and that is the name the
    -- settings row carries: this list is equipment independent, so it cannot know which tier
    -- will be fitted. A fitted row is named for the tier actually on the automaton.
    local base = {}
    for itemId, entry in pairs(cooldownData.attachmentAbilities) do
        local current = base[entry.skillId]
        if current == nil or itemId < current.itemId then
            base[entry.skillId] = { itemId = itemId, entry = entry }
        end
    end

    for _, picked in pairs(base) do
        local entry = picked.entry
        local slot  = gateSlot(entry.skillId, entry.name, entry.skillId, entry.cooldown, true)
        slot.ability = entry.label
        slot.effect  = entry.effect
        attachmentOptions[#attachmentOptions + 1] = slot
    end

    table.sort(attachmentOptions, function(a, b)
        return a.displayName < b.displayName
    end)
end

local function buildSlots()
    local slots = {}
    if not enabled or head == nil or frame == nil then
        return slots
    end

    -- Gates exist only on the frames that call setMagicCooldowns. On any other frame the
    -- automaton casts nothing at all, whatever head it is wearing.
    local categories = cooldownData.magicFrames[frame] and cooldownData.categories[head]
    local order      = categories and cooldownData.display[head]
    if order then
        for _, category in ipairs(order) do
            local duration = categories[category]
            if duration then
                slots[#slots + 1] = gateSlot(category, cooldownData.CATEGORY_LABELS[category],
                                             category, duration)
            end
        end
    end

    if attachments then
        local seen = {}
        for _, value in ipairs(attachments) do
            local entry = value ~= 0
                and cooldownData.attachmentAbilities[cooldownData.ATTACHMENT_ITEM_BASE + value]
                or nil
            if entry and not seen[entry.skillId] then
                seen[entry.skillId] = true
                slots[#slots + 1] = gateSlot(entry.skillId, entry.name,
                                             entry.skillId, entry.cooldown, true)
            end
        end
    end

    return slots
end

-- 0x0044 arrives on every server tick the automaton's updatemask is set, so this allocates at
-- that rate if called unconditionally. Both callers gate it on a real change.
local function rebuild()
    local parts = { tostring(enabled), tostring(head), tostring(frame) }
    if attachments then
        for _, value in ipairs(attachments) do
            parts[#parts + 1] = tostring(value)
        end
    end
    cachedSignature = table.concat(parts, '|')
    cachedSlots     = buildSlots()
end

local function sameAttachments(a, b)
    if a == nil or b == nil then return a == b end
    if #a ~= #b then return false end
    for slot = 1, #a do
        if a[slot] ~= b[slot] then return false end
    end
    return true
end

-- Called every frame from the settings, so it must cost a comparison when nothing changed.
function M.setEnabled(value)
    value = value ~= false
    if value == enabled then return end
    enabled = value
    rebuild()
end

-- headValue and frameValue are the raw 0x0044 bytes (itemId - 0x2000); attachmentBytes is the
-- twelve-entry array, 0 for an empty slot.
--
-- Head, frame and attachments can only be changed with the automaton put away, so a change here
-- means every stamp belongs to an automaton that no longer exists.
function M.setEquipment(headValue, frameValue, attachmentBytes)
    if headValue == head and frameValue == frame
        and sameAttachments(attachments, attachmentBytes) then
        return
    end

    head        = headValue
    frame       = frameValue
    attachments = attachmentBytes

    stamps       = {}
    trackedPetId = 0
    rebuild()
end

-- A confirmed Activate or Deus Ex Automata. Horizon does not pre-apply the attachment recasts
-- at spawn that LSB does, so the new automaton starts with everything clear.
--
-- Needed on top of trackPet because Deactivate then Activate can hand back the same server id,
-- which trackPet reads as no change at all.
function M.onSummonConfirmed()
    stamps = {}
end

-- Follows the automaton entity. serverId 0 means none is out.
function M.trackPet(serverId)
    if serverId == trackedPetId then return end
    trackedPetId = serverId
    stamps       = {}
end

-- A cast the automaton started. The global gate advances on any cast the controller makes
-- (automaton_controller.cpp:214 stamps it on every successful TrySpellcast, before the head
-- switch picks a category), so it is stamped even for a spell this table does not categorise.
-- Returning early on those would leave Latency reading ready while the gate is still closed.
function M.onCast(spellId, now)
    stamps['magic'] = now

    local category = cooldownData.spellCategory[spellId]
    if category ~= nil then
        stamps[category] = now
    end
end

-- A mob skill the automaton used. Only the attachment abilities carry a recast.
function M.onMobSkill(skillId, now)
    if skillCooldown[skillId] == nil then return end
    stamps[skillId] = now
end

-- The recast rows this equipment produces, in the head's own cast priority. Never nil.
function M.slots()
    return cachedSlots
end

-- Every attachment ability, fitted or not, for the settings list. Never nil.
function M.attachmentOptions()
    return attachmentOptions
end

-- Changes exactly when slots() would return a different list.
function M.signature()
    return cachedSignature
end

-- Whole seconds remaining and whether the gate is ready, for one slot from M.slots().
--
-- ceil, not floor: any remainder under a second is still a second the gate is closed for.
function M.state(slot, now)
    local stamp = stamps[slot.icdKey]
    if stamp == nil then
        return 0, true
    end

    local elapsed = now - stamp
    if elapsed < slot.icdDuration then
        return math.ceil(slot.icdDuration - elapsed), false
    end
    return 0, true
end

rebuild()

return M
