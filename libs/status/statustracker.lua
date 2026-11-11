--[[
* Copyright (c) 2023 tirem [github.com/tirem] under the GPL-3.0 license
* Modified 2026 by Zaldas for PetsReborn.
]]--

require('common');
local statusTable = require('libs/status/statustable');
local helpers = require('libs/status/statushelpers');
local spellDurations            = nil;
local abilityDurations          = nil;
local additionalEffectDurations = nil;
local mobStatusDurations        = nil;
local exclusionGroups           = nil;
local negativeEffects           = nil;
local petAbilities              = nil;
local wsDurations               = nil;
local absorbSpells              = nil;
local mobSkillSilentDebuffs     = nil;
local bioDiaData                = nil;
local spellMeta                 = nil;
local physicalJaDebuffs         = nil;
local bloodPactDebuffs          = nil;
local wardBuffDurations         = nil;
local FALLBACK_DURATION_S       = 300;

-- Status-ON messages: action packet messages that carry a status effect application.
-- Named IDs match xi.msg.basic in LSB-server/scripts/enum/msg.lua.
-- IDs marked [retail] are from retail packet captures; not in HorizonXI's msg.lua but
-- confirmed by LSB test comments — harmless if they don't fire here.
--   101=USES (mob 2hr self-buffs), 127=JA_ENFEEB_IS, 160=ADD_EFFECT_STATUS,
--   164=ADD_EFFECT_STATUS_2, 166=ADD_EFFECT_SELFBUFF, 186=SKILL_GAIN_EFFECT,
--   194=[retail] SKILL_GAIN_EFFECT variant (LSB test: "Retail accurate is 194"),
--   203=IS_STATUS, 205=GAINS_EFFECT_OF_STATUS, 230=MAGIC_GAIN_EFFECT,
--   236=MAGIC_ENFEEB_IS, 237=MAGIC_ENFEEB, 242=SKILL_ENFEEB_IS, 243=SKILL_ENFEEB,
--   266=JA_GAIN_EFFECT, 267=JA_RECEIVES_EFFECT, 268=MAGIC_BURST_ENFEEB,
--   269=[retail], 271=MAGIC_BURST_ENFEEB_IS, 272=[retail], 277=IS_EFFECT,
--   278/279=[retail], 280=[retail] JA_GAIN_EFFECT variant ("Retail accurate is 280"),
--   319=SKILL_GAIN_EFFECT_2, 320=JA_RECEIVES_EFFECT_2, 375=ITEM_RECEIVES_EFFECT,
--   412/645/754/755/804=[retail]
-- NOTE: 277=IS_EFFECT ("is <status>") is included — the server sends this for AoE secondary
--   targets (e.g. Sleepga: direct target gets 230, all other targets in the AoE get 277).
--   Excluding it breaks AoE status tracking entirely; any false-timer risk on mob skills is
--   minor and accepted.
local statusOnMes = {[101]=true,[127]=true,[160]=true,[164]=true,[166]=true,[186]=true,[194]=true,[203]=true,[205]=true,[230]=true,[236]=true,[242]=true,[243]=true,[266]=true,[267]=true,[268]=true,[269]=true,[237]=true,[271]=true,[272]=true,[277]=true,[278]=true,[279]=true,[280]=true,[319]=true,[320]=true,[375]=true,[412]=true,[645]=true,[754]=true,[755]=true,[804]=true}
-- Status-OFF messages: action/message packet messages that indicate a status was removed.
--   64=[retail], 159=SKILL_ERASE, 204=IS_NO_LONGER_STATUS, 206=STATUS_WEARS_OFF,
--   321=JA_REMOVE_EFFECT_2, 322=[retail], 341=MAGIC_ERASE, 342/343/344=[retail],
--   350=[retail], 378=ITEM_EFFECT_DISAPPEARS, 531/647/805/806=[retail],
--   168=ADD_EFFECT_DISPEL (sent as an additional-effect message; param is the removed status)
local statusOffMes = {[64]=true,[159]=true,[168]=true,[204]=true,[206]=true,[321]=true,[322]=true,[341]=true,[342]=true,[343]=true,[344]=true,[350]=true,[378]=true,[531]=true,[647]=true,[805]=true,[806]=true}
-- Sleep-family status IDs: 2=Sleep I, 19=Sleep II (tracked as 19 via spellMeta buffId),
-- 193=Lullaby. They share wear-off messaging, so they are always cleared together.
local SLEEP_FAMILY_STATUS_IDS = {[2]=true, [19]=true, [193]=true}
local deathMes = {[6]=true,[20]=true,[97]=true,[113]=true,[406]=true,[605]=true,[646]=true}

-- Server's "prevent-action" status set: while any of these is genuinely active, the entity
-- is AI-locked (Inactive state) and cannot generate an action packet at all — so observing
-- ANY action packet from a tracked entity is deterministic proof these already ended.
--   2=Sleep I, 7=Petrification, 10=Stun, 19=Sleep II, 28=Terror, 159=Penalty, 193=Lullaby
local preventActionStatusIds = {[2]=true,[7]=true,[10]=true,[19]=true,[28]=true,[159]=true,[193]=true}
-- Statuses that block one kind of action, keyed by the action packet type that proves them gone.
-- Amnesia is checked only when readying starts, so a skill finish (11/13) proves nothing.
--   4=MagicFinish, 8=MagicStart → 6=Silence, 29=Mute
--   6=JobAbility, 7=SkillStart → 16=Amnesia
local SILENCE_STATUS_IDS = {[6]=true,[29]=true}
local AMNESIA_STATUS_IDS = {[16]=true}
local actionBlockStatusIds = {
    [4]=SILENCE_STATUS_IDS, [8]=SILENCE_STATUS_IDS,
    [6]=AMNESIA_STATUS_IDS, [7]=AMNESIA_STATUS_IDS,
}
-- Type 4 also reports failed non-spell actions (paralyzed attack, skill out of range); every
-- such packet carries this animation on its target result.
local SKILL_INTERRUPT_ANIMATION = 508
local TRUST_SPAWN_FLAG = 0x1000  -- set on trusts (4366), clear on pets (258), players and mobs

-- An entity under Bind, Petrification or Terror cannot move, so a position change is
-- deterministic proof all of them ended (Bind's 95%-per-hit break roll is not observable).
-- Not included: Stun (mob skills pair it with knockback) and the Sleep family (has its own
-- wake message, and is often cast on an entity still sliding to a stop).
-- [serverId] = { x, y, z, seen, pending } — see pollMoveBlockBreak. seen = { [statusId] = expiry }
-- of the live statuses at the last poll; a new or refreshed entry re-baselines, a removal keeps it.
-- Accepted risk: knockback while the status is genuinely active reads as movement.
-- 7=Petrification, 11=Bind, 28=Terror
local MOVE_BLOCK_STATUS_IDS = {[7]=true,[11]=true,[28]=true}
local moveBlockPositions = {}
local MOVE_BLOCK_POLL_INTERVAL = 1  -- seconds between polls
local MOVE_BLOCK_THRESHOLD = 0.5    -- yalms of position delta that counts as genuine movement (absorbs render-interpolation jitter)
local _lastMoveBlockPollTime = 0

-- Shadow images end when the images are consumed, not when the timer runs out. The wear-off
-- message (206) is the signal for that, and the statusOff path already handles it.
--
-- Copy Image is cleared by a landed single-target physical hit as well: it absorbs EVERY such
-- attack (battleutils.cpp IsAbsorbByShadow), so damage getting through proves its images are
-- spent. Blink is deliberately NOT cleared that way, because it whiffs 20% of the time and a
-- landed hit proves nothing. AoE and magic bypass shadows entirely, so message 185 (AoE weapon
-- skills and mob skills) is excluded for the same reason.
--
-- 66=Copy Image, 444/445/446=Copy Image (2)/(3)/(4+). The counter icons are set for PCs only,
-- so a mob's shadows always read as plain Copy Image.
local SHADOW_COPY_IMAGE_IDS = {[66]=true,[444]=true,[445]=true,[446]=true}
local SHADOW_SINGLE_HIT_MES = {[1]=true,[67]=true,[352]=true,[353]=true,[576]=true,[577]=true}
local SHADOW_ABSORB_MES = 31

local spellDamageMes = {[2]=true,[252]=true,[264]=true,[265]=true}
-- Bio/Dia outcomes that deal no damage — nullified (85) or absorbed (7). The status still lands.
-- 284/367 are their AoE variants; that mapping lives in C++, so a Lua grep turns up nothing.
local bioDiaNoDamageMes = {[7]=true,[85]=true,[284]=true,[367]=true}

-- [targetId] = { statusId, tier } — single slot; Bio/Dia are mutually exclusive.
local bioDiaTiers = {}

-- Owned by writeStatus/removeStatus: every write replaces the override and every explicit
-- removal clears it, so it always belongs to the latest write.
-- [serverId][realStatusId] = displayStatusId (814-1022 range)
local displayIdOverrides = {}

local function getDisplayId(serverId, statusId)
    local overrides = displayIdOverrides[serverId]
    return (overrides and overrides[statusId]) or statusId
end

-- [displayId] = real status ID; built in init from bioDiaData and spellMeta
local baseStatusIds = {}

-- Server ID of the only entity tracked (the pet); 0 = none. Action packets that neither come
-- from nor land on it are dropped before any entity lookup.
local trackedId = 0

-------------------------------------------------------------------------------
-- exported functions
-------------------------------------------------------------------------------

local statusTracker = {
    trackedEntities = T{}; -- entities by serverId that we are tracking buffs and debuffs on
};

-- Every status write and explicit removal must go through these so the tier icon always
-- belongs to the latest write; a direct trackedEntities write leaves a stale icon.
-- displayId: tier icon for this write, nil for none
local function writeStatus(serverId, statusId, expiry, displayId)
    local statuses = statusTracker.trackedEntities[serverId]
    if statuses == nil then
        statuses = T{}
        statusTracker.trackedEntities[serverId] = statuses
    end
    statuses[statusId] = expiry
    local overrides = displayIdOverrides[serverId]
    if displayId then
        if overrides == nil then
            overrides = {}
            displayIdOverrides[serverId] = overrides
        end
        overrides[statusId] = displayId
    elseif overrides then
        overrides[statusId] = nil
    end
end

local function removeStatus(serverId, statusId)
    local statuses = statusTracker.trackedEntities[serverId]
    if statuses then statuses[statusId] = nil end
    local overrides = displayIdOverrides[serverId]
    if overrides then overrides[statusId] = nil end
end

-- Drops an entity's status shell and every side table keyed by it.
local function clearTrackedShell(serverId)
    statusTracker.trackedEntities[serverId] = nil
    bioDiaTiers[serverId] = nil
    displayIdOverrides[serverId] = nil
    moveBlockPositions[serverId] = nil
end

-- Real status ID behind a display ID, for resource lookups.
statusTracker.GetBaseStatusId = function(statusId)
    return baseStatusIds[statusId] or statusId
end

-------------------------------------------------------------------------------
-- HandleActionPacket path handlers
-- Each function implements exactly one of the tracking paths dispatched from
-- HandleActionPacket's main loop below. Parameter shape is uniform: (action, target,
-- ability, now); applyStatusOn additionally receives whether the actor is a
-- party-owned pet (resolved once per packet in HandleActionPacket). Guards specific
-- to each path (message-set membership, hit confirmation, actor==target checks,
-- etc.) live inside the function that needs them.
-------------------------------------------------------------------------------

-- Bio and Dia: mirrors the server's tier rules (see bioDiaData).
-- spellDamageMes fires even when the server rejects the status, so the caller gates on
-- action.Type == 4 and spellDamageMes/bioDiaNoDamageMes[message] before calling this.
local function applyBioDia(action, target, ability, now)
    local spell = action.Param
    local bioDia = bioDiaData[spell]
    if not bioDia then return end
    local active = bioDiaTiers[target.Id]
    -- sweepExpiredEntities only drops the tier record when the entity's whole shell goes, so a
    -- Bio/Dia that lapsed while other debuffs kept the shell alive leaves a stale record behind.
    -- Gate on the live timer, not the record, or the next cast of that tier is rejected forever.
    if active then
        local expiry = statusTracker.trackedEntities[target.Id][active.statusId]
        if expiry == nil or expiry <= now then active = nil end
    end
    if not active or active.tier < bioDia.tier then
        removeStatus(target.Id, bioDia.opposing)
        writeStatus(target.Id, bioDia.statusId, now + bioDia.dur, bioDia.displayId)
        bioDiaTiers[target.Id] = { statusId = bioDia.statusId, tier = bioDia.tier }
    end
end

-- Remove any other member of statusId's exclusion group. The server drops the loser silently
-- (no wear-off packet), so without this the previous member lingers until its own timer runs out.
local function clearExclusionGroup(serverId, statusId)
    local group = exclusionGroups and exclusionGroups.groupOf[statusId]
    if group == nil then return end
    for _, otherId in ipairs(exclusionGroups.members[group]) do
        if otherId ~= statusId then
            removeStatus(serverId, otherId)
        end
    end
end

-- Write a landed status. Clears what the server removes silently on landing: the rest of its
-- exclusion group and its opposing effect (see negativeEffects).
-- inferred: the status rides a damage message, so a resist is indistinguishable from a landing;
-- the opposing effect is left in place.
-- displayId: tier icon for this write, nil for none
local function recordStatus(serverId, statusId, expiry, inferred, displayId)
    clearExclusionGroup(serverId, statusId)
    local opposingId = not inferred and negativeEffects and negativeEffects[statusId]
    if opposingId then
        removeStatus(serverId, opposingId)
    end
    writeStatus(serverId, statusId, expiry, displayId)
end

-- Regular buffs/debuffs from a statusOnMes message (the non-mob-self-buff sub-path).
-- Returns true if the caller should `goto continue_ability` (status unresolved, or the
-- resolved duration is a known-zero shadow/luopan-based effect with no time component).
local function applyStatusOn(action, target, ability, now, isPetActor)
    local spell = action.Param
    -- Regular buffs/debuffs (including mob skills targeting the pet). ability.Param is
    -- bit-unpacked so it defaults to 0 (never nil); treat 0 as "no status ID" and fall back to
    -- the spell table for type-4 casts.
    local statusId = ability.Param
    if statusId == 0 and action.Type == 4 then
        statusId = statusTable.GetStatusIdBySpellId(spell)
    end
    if statusId == nil or statusId == 0 then
        return true
    end
    -- Spells only: mob skills and abilities reuse the same IDs
    local meta = action.Type == 4 and spellMeta[spell] or nil
    if meta and meta.buffId then statusId = meta.buffId end

    local duration
    if action.Type == 6 and abilityDurations[spell] then
        duration = abilityDurations[spell]
    elseif action.Type == 3 and physicalJaDebuffs[spell] then
        -- Applied immediately: the statusOnMes-classified message already confirms the status
        -- landed. applyPhysicalJaDebuff handles the same ability arriving with a damage message.
        duration = physicalJaDebuffs[spell].duration
    elseif isPetActor and action.Type == 11 and petAbilities ~= nil and petAbilities.durations[spell] ~= nil then
        -- Ahead of skillDebuffs: pet ability IDs share the mob-skill namespace, so a pet
        -- ability must not resolve against a mob-skill entry of the same ID.
        duration = petAbilities.durations[spell]
    elseif (action.Type == 7 or action.Type == 11 or (action.Type == 3 and action.UserIndex ~= nil and helpers.GetIsMob(action.UserIndex) == true)) and mobStatusDurations ~= nil and mobStatusDurations.skillDebuffs[spell] ~= nil then
        local skillEntry = mobStatusDurations.skillDebuffs[spell]
        if type(skillEntry) == 'table' then
            local d = statusId and skillEntry[statusId]
            if d ~= nil then duration = d end
        else
            duration = skillEntry
        end
    elseif action.Type == 4 and spellDurations[spell] then
        duration = spellDurations[spell]
    elseif action.Type == 13 and wardBuffDurations[spell] then
        duration = wardBuffDurations[spell]
    end
    if duration == nil then
        duration = FALLBACK_DURATION_S
    end
    if duration == 0 then return true end  -- shadow/luopan-based effects have no time component
    if meta and meta.clears then
        for _, clearId in ipairs(meta.clears) do
            removeStatus(target.Id, clearId)
        end
    end
    local displayId = meta and meta.statusId == statusId and meta.displayId or nil
    recordStatus(target.Id, statusId, now + duration, false, displayId)
    return false
end

-- Mob self-buff (statusOnMes, actor == target): track event-driven using exact per-skill
-- duration where known. Captured regardless of targeting (e.g. 2hr Invincible mid-fight).
local function applyMobSelfBuff(action, target, ability, now)
    local spell = action.Param
    local statusId = ability.Param
    if statusId and statusId ~= 0 then
        local dur = mobStatusDurations.getSelfBuffDuration(statusId, spell)
        -- nil: unknown self-buff; 0: known permanent effect (e.g. bastion_of_twilight)
        if dur ~= nil and dur > 0 then
            recordStatus(target.Id, statusId, now + dur)
        end
    end
end

-- Dispel, Finale, or other buff-removal spells/abilities targeting this entity.
-- ability.Param carries the status effect ID that was removed.
local function applyStatusOff(action, target, ability, now)
    local statusId = ability.Param
    if statusId and statusId ~= 0 then
        removeStatus(target.Id, statusId)
    end
end

-- Absorb-*: the packet carries the target's debuff message only. Apply that debuff, and the
-- caster's matching boost, which the server grants silently.
local function applyAbsorbSpell(action, target, ability, now)
    local absorb = absorbSpells and absorbSpells[action.Param]
    if absorb == nil or ability.Message ~= absorb.message then return false end
    local expiry = now + absorb.duration
    if target.Id == trackedId then
        recordStatus(target.Id, absorb.down, expiry)
    end
    if action.UserId == trackedId then
        recordStatus(action.UserId, absorb.boost, expiry)
    end
    return true
end

-- Physical JA debuffs (type 3): weapon-based abilities (Shield Bash, Weapon Bash).
-- Apply on hit confirmed (ability.Param = damage > 0), no overwrite if already active.
local function applyPhysicalJaDebuff(action, target, ability, now)
    local spell = action.Param
    local jaDebuff = physicalJaDebuffs[spell]
    if jaDebuff and ability.Param > 0 then
        local existing = statusTracker.trackedEntities[target.Id][jaDebuff.statusId]
        if not existing or existing <= now then
            recordStatus(target.Id, jaDebuff.statusId, now + jaDebuff.duration, true)
        end
    end

    -- Weapon skills (also action type 3). Keys do not overlap physicalJaDebuffs, so the two
    -- tables are looked up independently rather than merged.
    local ws = wsDurations and wsDurations[spell]
    if ws and ability.Param > 0 then
        local statusIds = ws.statusIds or { ws.statusId }
        for _, statusId in ipairs(statusIds) do
            local existing = statusTracker.trackedEntities[target.Id][statusId]
            if not existing or existing <= now then
                recordStatus(target.Id, statusId, now + ws.duration, true)
            end
        end
    end
end

-- Blood pact debuffs/buffs: avatar pacts tracked via bloodPactDebuffs.
-- Two sub-paths — see bloodPactDebuffs comment for full format description.
local function applyBloodPact(action, target, ability, now)
    local pactDebuff = bloodPactDebuffs[action.Param]
    if not pactDebuff then return end
    if pactDebuff.messages then
        -- Message-triggered path: custom msg (not in statusOnMes), script returns 0.
        -- Apply all statuses when the message matches; always overwrite (server refreshes on recast).
        if pactDebuff.messages[ability.Message] then
            for sid, dur in pairs(pactDebuff.statuses) do
                recordStatus(target.Id, sid, now + dur)
            end
        end
    elseif ability.Param > 0 then
        -- Physical hit path: only when damage > 0 and no active timer exists.
        local existing = statusTracker.trackedEntities[target.Id][pactDebuff.statusId]
        if not existing or existing <= now then
            recordStatus(target.Id, pactDebuff.statusId, now + pactDebuff.duration, true)
        end
    end
end

-- Mob skill silent debuffs: mob skills that apply status via mobStatusEffectMove()
-- but never call skill:setMsg() — damage message fires, status lands silently.
-- Pet abilities of the same shape come from petAbilities.hitData.
-- Only applied when ability.Param (damage) > 0 and no active timer exists. A shadow absorb
-- (msg 31) carries the shadow count in Param, not damage.
local function applySilentMobDebuff(action, target, ability, now)
    local spell = action.Param
    local silentDebuff = mobSkillSilentDebuffs[spell]
    if not silentDebuff and petAbilities then
        silentDebuff = petAbilities.hitData[spell]
    end
    if silentDebuff and ability.Param > 0 and ability.Message ~= SHADOW_ABSORB_MES then
        -- Multi-status skills hold a list of records; single-status ones are the record itself.
        local records = silentDebuff[1] and silentDebuff or { silentDebuff }
        for _, record in ipairs(records) do
            local existing = statusTracker.trackedEntities[target.Id][record.statusId]
            if not existing or existing <= now then
                recordStatus(target.Id, record.statusId, now + record.duration, true)
            end
        end
    end
end

-- Additional effect processing (e.g. Acid Bolts applying Def Down on crabs,
-- overwriting Defender/Def Up). These carry their own message and status ID.
local function applyAdditionalEffect(action, target, ability, now)
    local ae = ability.AdditionalEffect
    if not ae then return end
    local aeMessage = ae.Message
    local aeStatusId = ae.Param
    if aeStatusId and aeStatusId ~= 0 then
        if statusOnMes[aeMessage] then
            local aeDuration = additionalEffectDurations[aeStatusId] or FALLBACK_DURATION_S
            recordStatus(target.Id, aeStatusId, now + aeDuration)
        elseif statusOffMes[aeMessage] then
            removeStatus(target.Id, aeStatusId)
        end
    end
end

-- Mob skills sent with message 0 (xi.msg.basic.NONE), which the statusOnMes path never sees.
--   self-buff: actor == target, status looked up by skill ID via selfBuffSkillMap
--              (e.g. Transmogrification -> Physical Shield, Mind Wall -> Magic Shield)
--   debuff:    actor ~= target, Param carries the status ID, duration from skillDebuffs
--              (e.g. Nuclear Waste -> Elemental Res Down)
local function applyNoneMessageSkill(action, target, ability, now)
    local skillId = action.Param
    if action.UserId == target.Id then
        local statusId = mobStatusDurations.selfBuffSkillMap[skillId]
        if statusId == nil then return end
        local dur = mobStatusDurations.getSelfBuffDuration(statusId, skillId)
        if dur ~= nil and dur > 0 then
            recordStatus(target.Id, statusId, now + dur)
        end
    else
        local statusId = ability.Param
        local skillEntry = mobStatusDurations.skillDebuffs[skillId]
        if statusId == 0 or skillEntry == nil then return end
        local dur
        if type(skillEntry) == 'table' then
            dur = skillEntry[statusId]
        else
            dur = skillEntry
        end
        if dur ~= nil and dur > 0 then
            recordStatus(target.Id, statusId, now + dur)
        end
    end
end

-- Remove every live status in statusIds from serverId.
local function clearLiveStatuses(serverId, statusIds, now)
    local entity = statusTracker.trackedEntities[serverId]
    if entity == nil then return end
    for statusId in pairs(statusIds) do
        local expiry = entity[statusId]
        if expiry ~= nil and expiry > now then
            removeStatus(serverId, statusId)
        end
    end
end

-- A single-target physical hit landing on an entity proves its Copy Image images are spent.
local function noteShadowProof(targetId, now)
    clearLiveStatuses(targetId, SHADOW_COPY_IMAGE_IDS, now)
end

-- Interrupt-notification packets (cast/skill/item cut short) carry param=0x7073.
-- Type 8/9 params are already 16-bit; types 7 (SkillStart) and 12 (RangedStart,
-- RangedInterrupt) are 32-bit, so mask low 16.
local function isInterruptNotification(action)
    if action.Type == 8 or action.Type == 9 then
        return action.Param == 0x7073
    elseif action.Type == 7 or action.Type == 12 then
        return bit.band(action.Param, 0xFFFF) == 0x7073
    end
    return false
end

-- Any observed action packet from an actor proves none of the prevent-action statuses
-- can still be active on it (see preventActionStatusIds) — clear any we still track.
local function clearPreventActionBreak(actorId, now)
    clearLiveStatuses(actorId, preventActionStatusIds, now)
end

-- An action of a kind a status blocks proves that status is not active on the actor (see
-- actionBlockStatusIds). Catches statuses that resisted or wore off without a message.
-- Type 7 counts only from an actor resolved as a non-trust: trusts weapon skill through a path
-- with no Amnesia check.
local function clearActionBlockBreak(action, now)
    local actionType = action.Type
    local blocked = actionBlockStatusIds[actionType]
    if blocked == nil then return end
    local actorId = action.UserId
    if statusTracker.trackedEntities[actorId] == nil then return end
    local userIndex = action.UserIndex
    if actionType == 7 and (userIndex == nil or userIndex == 0
            or bit.band(AshitaCore:GetMemoryManager():GetEntity():GetSpawnFlags(userIndex), TRUST_SPAWN_FLAG) ~= 0) then
        return
    end
    if actionType == 4 then
        for _, target in pairs(action.Targets) do
            for _, result in pairs(target.Actions) do
                if result.Animation == SKILL_INTERRUPT_ANIMATION then return end
            end
        end
    end
    clearLiveStatuses(actorId, blocked, now)
end

statusTracker.HandleActionPacket = function(e)
    if trackedId == 0 then return end

    local action = helpers.ParseActionPacket(e);
    if (action == nil) then
        return;
    end

    local actorIsTracked = (action.UserId == trackedId)
    local targetsTracked = false
    for _, target in pairs(action.Targets) do
        if target.Id == trackedId then
            targetsTracked = true
            break
        end
    end
    if not actorIsTracked and not targetsTracked then return end

    -- GetIndexFromId can walk the whole entity array, so it runs only past the filter above.
    -- It returns 0 on a miss, and index 0 is the local player.
    action.UserIndex = helpers.GetIndexFromId(action.UserId)
    local isPetActor = false
    if action.UserIndex ~= 0 then
        isPetActor = (helpers.GetIsPartyPet(action.UserIndex) == true)
    end
    -- Pet abilities absent from petAbilities keep the mob-skill treatment: applyMobSelfBuff
    -- ignores unknown IDs, while applyStatusOn falls back to 300s.
    -- Hoisted out of the target loop: action.Param is constant for the whole packet.
    local isKnownPetAbility = false
    if isPetActor and petAbilities ~= nil then
        isKnownPetAbility = (petAbilities.durations[action.Param] ~= nil
                             or petAbilities.hitData[action.Param] ~= nil)
    end

    local now = os.time()

    -- A same-tick interrupt notification is not proof the actor acted — it means the actor's
    -- own CC (e.g. Stun) just interrupted its cast, the opposite signal. Don't clear.
    if not isInterruptNotification(action) then
        clearPreventActionBreak(action.UserId, now)
        clearActionBlockBreak(action, now)
    end

    for _, target in pairs(action.Targets) do
        for _, ability in pairs(target.Actions) do
            local message = ability.Message
            if target.Id ~= trackedId then
                -- Absorb-* cast by the tracked entity grants it the matching boost.
                if actorIsTracked and action.Type == 4 then
                    applyAbsorbSpell(action, target, ability, now)
                end
                goto continue_ability
            end
            if (statusTracker.trackedEntities[target.Id] == nil) then
                statusTracker.trackedEntities[target.Id] = T{};
            end

            if SHADOW_SINGLE_HIT_MES[message] then
                noteShadowProof(target.Id, now)
            end

            -- Damage and no-damage messages both reach applyBioDia; the tier check inside it
            -- is what rejects a status the server would have rejected.
            if action.Type == 4 and applyAbsorbSpell(action, target, ability, now) then
                -- handled

            elseif action.Type == 4 and (spellDamageMes[message] or bioDiaNoDamageMes[message]) then
                applyBioDia(action, target, ability, now)

            elseif statusOnMes[message] then
                -- Mob self-buffs (type 7 mob skills / type 11 2hr/special on self):
                -- handle event-driven for known selfBuffs so we capture them regardless of targeting.
                -- Unknown self-buffs are silently ignored (no FALLBACK_300).
                -- Type 7/11 where actor != target = mob debuff on pet/player — processed
                -- normally, as is a party-owned pet using an ability petAbilities covers
                -- (automaton abilities are type 11).
                local isMobSelfBuff = (action.Type == 7 or action.Type == 11) and not isKnownPetAbility and (action.UserId == target.Id)
                if not isMobSelfBuff then
                    if applyStatusOn(action, target, ability, now, isPetActor) then
                        goto continue_ability
                    end
                else
                    applyMobSelfBuff(action, target, ability, now)
                end
            elseif statusOffMes[message] then
                applyStatusOff(action, target, ability, now)
            end

            -- Physical JA debuffs (type 3): weapon-based abilities (Shield Bash, Weapon Bash).
            -- Apply on hit confirmed (ability.Param = damage > 0), no overwrite if already active.
            if action.Type == 3 then
                applyPhysicalJaDebuff(action, target, ability, now)
            end

            -- Blood pact debuffs/buffs: avatar pacts tracked via bloodPactDebuffs.
            -- Two sub-paths — see bloodPactDebuffs comment for full format description.
            if action.Type == 13 then
                applyBloodPact(action, target, ability, now)
            end

            -- Mob skill silent debuffs: mob skills that apply status via mobStatusEffectMove()
            -- but never call skill:setMsg() — damage message fires, status lands silently.
            -- Only applied when ability.Param (damage) > 0 and no active timer exists.
            if (action.Type == 7 or action.Type == 11) and action.UserId ~= target.Id then
                applySilentMobDebuff(action, target, ability, now)
            end

            -- Pet abilities share the mob-skill ID namespace, so a known one never resolves
            -- against the mob-skill tables here.
            if (action.Type == 7 or action.Type == 11) and message == 0 and not isKnownPetAbility then
                applyNoneMessageSkill(action, target, ability, now)
            end

            applyAdditionalEffect(action, target, ability, now)
            ::continue_ability::
        end
    end
end

statusTracker.HandleClearMessage = function(e)

    local parsedPacket = helpers.ParseMessagePacket(e.data)
    if (parsedPacket == nil) then
        return;
    end

    -- if we're tracking a mob that dies, reset its status
    if deathMes[parsedPacket.message] and statusTracker.trackedEntities[parsedPacket.target] then
        clearTrackedShell(parsedPacket.target)
    elseif statusOffMes[parsedPacket.message] then
        -- Clear the buffid that just wore off.
        -- Sleep family (IDs 2, 19, 193) shares one wear-off message; clear all three
        -- so a Sleep I icon left from an earlier cast doesn't linger after Sleep II wears.
        if (parsedPacket.param ~= nil) then
            local p = parsedPacket.param;
            if SLEEP_FAMILY_STATUS_IDS[p] then
                for sid in pairs(SLEEP_FAMILY_STATUS_IDS) do
                    removeStatus(parsedPacket.target, sid)
                end
            else
                removeStatus(parsedPacket.target, p)
                if p == 134 or p == 135 then
                    local active = bioDiaTiers[parsedPacket.target]
                    if active and active.statusId == p then
                        bioDiaTiers[parsedPacket.target] = nil
                    end
                end
            end
        end
    end
end

local function FilterPlayerStatus(PlayerBuffs)
    local filteredStatus = T{};
    for _,v in pairs(PlayerBuffs) do
        if (v == -1) then break; end
        table.insert(filteredStatus, v);
    end
    return filteredStatus;
end

statusTracker.GetStatusEffects = function(serverId)
    -- If this is just the player return the buffs in memory
    if (serverId == AshitaCore:GetMemoryManager():GetParty():GetMemberServerId(0)) then
        return FilterPlayerStatus(AshitaCore:GetMemoryManager():GetPlayer():GetBuffs());
    end

    -- Otherwise collect our manually tracked entity
    if (statusTracker.trackedEntities[serverId] == nil) then
        return nil;
    end
    local returnTable = {};
    local now = os.time();
    for k,v in pairs(statusTracker.trackedEntities[serverId]) do
        if (v ~= 0 and v > now) then
            table.insert(returnTable, getDisplayId(serverId, k));
        else
            statusTracker.trackedEntities[serverId][k] = nil; -- Clear this entry if it's not valid
        end
    end
    -- Remove the entity shell when all its debuffs have expired to prevent unbounded growth
    if next(statusTracker.trackedEntities[serverId]) == nil then
        clearTrackedShell(serverId);
    end
    return returnTable;
end

-- Returns {[statusId] = expiryTime} for the tracked entity, nil for self/unknown. Statuses
-- that landed before tracking began have no timer.
-- Expiry times are absolute os.time() values; subtract os.time() at render to get remaining seconds.
statusTracker.GetStatusTimes = function(serverId)
    if (serverId == AshitaCore:GetMemoryManager():GetParty():GetMemberServerId(0)) then
        return nil  -- self: buff IDs come from GetPlayer():GetBuffs(), no expiry data available
    end
    if (statusTracker.trackedEntities[serverId] == nil) then
        return nil
    end
    local returnTable = {}
    local now = os.time()
    for k, v in pairs(statusTracker.trackedEntities[serverId]) do
        if (v ~= 0 and v > now) then
            returnTable[getDisplayId(serverId, k)] = v  -- absolute expiry timestamp
        end
    end
    return returnTable
end

-- Sweep trackedEntities and remove any entity whose every debuff has expired.
-- Called periodically to reclaim memory from mobs that died/walked away without triggering
-- the death-message cleanup path.
local _lastSweepTime = 0;
local SWEEP_INTERVAL = 60;  -- seconds between sweeps

local function sweepExpiredEntities()
    local now = os.time();
    if (now - _lastSweepTime) < SWEEP_INTERVAL then return; end
    _lastSweepTime = now;
    for sid, buffs in pairs(statusTracker.trackedEntities) do
        local anyActive = false;
        for k, expiry in pairs(buffs) do
            if expiry > now then
                anyActive = true;
                break;
            else
                buffs[k] = nil;
            end
        end
        if not anyActive then
            clearTrackedShell(sid);
        end
    end
end

-- Poll live positions of entities with a tracked MOVE_BLOCK_STATUS_IDS status; movement beyond
-- MOVE_BLOCK_THRESHOLD clears all of them. Baseline is deferred one poll: right after the status
-- lands the rendered position can still be settling toward the server's, and a baseline taken
-- then reads as false movement. The first sighting is pending; the second is the baseline.
local function pollMoveBlockBreak(now)
    if (now - _lastMoveBlockPollTime) < MOVE_BLOCK_POLL_INTERVAL then return end
    _lastMoveBlockPollTime = now
    local entMgr = AshitaCore:GetMemoryManager():GetEntity()
    for serverId, buffs in pairs(statusTracker.trackedEntities) do
        local live = nil
        for statusId in pairs(MOVE_BLOCK_STATUS_IDS) do
            local expiry = buffs[statusId]
            if expiry ~= nil and expiry > now then
                live = live or {}
                live[statusId] = expiry
            end
        end
        if live == nil then
            moveBlockPositions[serverId] = nil
        else
            -- index == 0: despawned or out of range — keep any baseline and retry next poll.
            local index = helpers.GetIndexFromId(serverId)
            if index ~= nil and index ~= 0 then
                local x, y, z = entMgr:GetLocalPositionX(index), entMgr:GetLocalPositionY(index), entMgr:GetLocalPositionZ(index)
                local tracked = moveBlockPositions[serverId]
                -- A status absent from seen, or with a changed expiry, is a fresh (re)apply.
                local fresh = (tracked == nil)
                if not fresh then
                    for statusId, expiry in pairs(live) do
                        if tracked.seen[statusId] ~= expiry then
                            fresh = true
                            break
                        end
                    end
                end
                if fresh then
                    moveBlockPositions[serverId] = { x = x, y = y, z = z, seen = live, pending = true }
                elseif tracked.pending then
                    tracked.seen = live
                    tracked.x, tracked.y, tracked.z = x, y, z
                    tracked.pending = nil
                else
                    -- Compare against the settled baseline so slow drift accumulates.
                    tracked.seen = live
                    local dx, dy, dz = x - tracked.x, y - tracked.y, z - tracked.z
                    if math.sqrt(dx*dx + dy*dy + dz*dz) > MOVE_BLOCK_THRESHOLD then
                        clearLiveStatuses(serverId, MOVE_BLOCK_STATUS_IDS, now)
                        moveBlockPositions[serverId] = nil
                    end
                end
            end
        end
    end
end

-- Call every frame from d3d_present.
statusTracker.Update = function()
    pollMoveBlockBreak(os.time())
    sweepExpiredEntities()  -- time-gated inside
end

local STATE_FILE = nil

-- Saves the tracked entity's non-expired statuses to disk so they survive addon reloads.
-- With no tracked entity (pet not yet in range since load or zone) the file is left as is, so
-- statuses restored at load survive another reload.
statusTracker.SaveState = function()
    if trackedId == 0 or STATE_FILE == nil then return end
    local now = os.time()
    local f = io.open(STATE_FILE, 'w')
    if not f then return end
    f:write('return {\n')
    local buffs = statusTracker.trackedEntities[trackedId]
    local lines = {}
    if buffs then
        for statusId, expiry in pairs(buffs) do
            if expiry > now then
                lines[#lines + 1] = string.format('    [%d]=%d,', statusId, expiry)
            end
        end
    end
    if #lines > 0 then
        f:write(string.format('  [%d]={\n', trackedId))
        for _, line in ipairs(lines) do f:write(line .. '\n') end
        f:write('  },\n')
    end
    f:write('}\n')
    f:close()
end

-- Restores non-expired debuffs from the state file saved by a previous session.
statusTracker.RestoreState = function()
    if STATE_FILE == nil then return end
    local fn = loadfile(STATE_FILE)
    if not fn then return end
    local ok, data = pcall(fn)
    if not ok or type(data) ~= 'table' then return end
    local now = os.time()
    for sid, buffs in pairs(data) do
        if type(buffs) == 'table' then
            for statusId, expiry in pairs(buffs) do
                if type(expiry) == 'number' and expiry > now then
                    writeStatus(sid, statusId, expiry, nil)
                end
            end
        end
    end
end


-- Initialize the status tracker. Must be called before any packet processing.
-- @param opts  { addonPath = string, addonName = string }
statusTracker.init = function(opts)
    spellDurations            = dofile(opts.addonPath .. 'libs/status/data/spellDurations.lua');
    abilityDurations          = dofile(opts.addonPath .. 'libs/status/data/abilityDurations.lua');
    additionalEffectDurations = dofile(opts.addonPath .. 'libs/status/data/additionalEffectDurations.lua');
    mobStatusDurations        = dofile(opts.addonPath .. 'libs/status/data/mobStatusDurations.lua');
    petAbilities              = dofile(opts.addonPath .. 'libs/status/data/petAbilities.lua');
    wsDurations               = dofile(opts.addonPath .. 'libs/status/data/wsDurations.lua');
    absorbSpells              = dofile(opts.addonPath .. 'libs/status/data/absorbSpells.lua');
    exclusionGroups           = dofile(opts.addonPath .. 'libs/status/data/exclusionGroups.lua');
    negativeEffects           = dofile(opts.addonPath .. 'libs/status/data/negativeEffects.lua');
    mobSkillSilentDebuffs     = dofile(opts.addonPath .. 'libs/status/data/mobSkillSilentDebuffs.lua');
    bioDiaData                = dofile(opts.addonPath .. 'libs/status/data/bioDiaData.lua');
    spellMeta                 = dofile(opts.addonPath .. 'libs/status/data/spellMeta.lua');
    physicalJaDebuffs         = dofile(opts.addonPath .. 'libs/status/data/physicalJaDebuffs.lua');
    bloodPactDebuffs          = dofile(opts.addonPath .. 'libs/status/data/bloodPactDebuffs.lua');
    wardBuffDurations         = dofile(opts.addonPath .. 'libs/status/data/wardBuffDurations.lua');

    baseStatusIds = {}
    for _, d in pairs(bioDiaData) do
        if d.displayId then baseStatusIds[d.displayId] = d.statusId end
    end
    for _, m in pairs(spellMeta) do
        if m.displayId then baseStatusIds[m.displayId] = m.statusId end
    end

    STATE_FILE = AshitaCore:GetInstallPath() .. 'config/addons/' .. opts.addonName .. '/statusstate.dat'

    statusTracker.RestoreState()
end

-- Sets the one entity whose statuses are tracked (0 = none) and drops every other shell.
statusTracker.setTrackedEntity = function(serverId)
    trackedId = serverId
    for sid in pairs(statusTracker.trackedEntities) do
        if sid ~= serverId then
            clearTrackedShell(sid)
        end
    end
end

-- Tears down this module's registered event handler. Call from the addon's unload event.
statusTracker.Dispose = function()
    ashita.events.unregister('packet_in', '__status_packet_in_cb');
end

ashita.events.register('packet_in', '__status_packet_in_cb', function (e)

    if (e.id == 0x00A) then -- Clear everything on zone
        statusTracker.trackedEntities = T{};
        bioDiaTiers = {};
        displayIdOverrides = {};
        moveBlockPositions = {};
    elseif (e.id == 0x0029) then
        statusTracker.HandleClearMessage(e);
    elseif (e.id == 0x0028) then
        statusTracker.HandleActionPacket(e);
    end
end);

return statusTracker;