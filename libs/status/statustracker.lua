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
--   350=[retail], 378=ITEM_EFFECT_DISAPPEARS, 531/647/805/806=[retail]
local statusOffMes = {[64]=true,[159]=true,[204]=true,[206]=true,[321]=true,[322]=true,[341]=true,[342]=true,[343]=true,[344]=true,[350]=true,[378]=true,[531]=true,[647]=true,[805]=true,[806]=true}
local WAKEUP_MES = 168  -- "X awakens." — woken from sleep by damage; param is not a status ID
local deathMes = {[6]=true,[20]=true,[97]=true,[113]=true,[406]=true,[605]=true,[646]=true}

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
-- [serverId][realStatusId] = displayStatusId (814-1022 range, see libs/status/icons/README.md)
local displayIdOverrides = {}

local function getDisplayId(serverId, statusId)
    local overrides = displayIdOverrides[serverId]
    return (overrides and overrides[statusId]) or statusId
end

-------------------------------------------------------------------------------
-- Unknown duration audit log
-------------------------------------------------------------------------------

local UNKNOWN_BUFF_LOG    = nil
local loggedUnknownSpells   = {}  -- [spellId]  = true; deduplicate within a session
local loggedUnknownSelfBuffs = {}  -- [statusId] = true; deduplicate mob self-buffs within a session
local loggedUntrackedMobSkills = {}  -- [skillId]  = true; deduplicate unrecognized mob skill hits

local function logUnknownDuration(spellId, statusId)
    if not UNKNOWN_BUFF_LOG then return end
    if loggedUnknownSpells[spellId] then return end
    loggedUnknownSpells[spellId] = true
    local resMgr = AshitaCore:GetResourceManager()
    local spellRes = resMgr and resMgr:GetSpellById(spellId)
    local spellName = (spellRes and spellRes.Name and spellRes.Name[1]) or '?'
    local f = io.open(UNKNOWN_BUFF_LOG, 'a')
    if not f then return end
    f:write(string.format('%s  spellId=%-5d  statusId=%-5d  name=%s\n',
        os.date('%Y-%m-%d %H:%M:%S'), spellId, statusId, spellName))
    f:close()
end

-- Mob skill names live in the client's 'monsters.abilities' string table indexed at
-- skillId - 256; GetAbilityById is a different namespace and returns an unrelated
-- name for the same number (mob skill 1836 Nerve Gas resolves there as "Frogkick").
local function resolveMobSkillName(skillId)
    local resMgr = AshitaCore:GetResourceManager()
    if not resMgr then return nil end
    if skillId < 256 then
        local res = resMgr:GetAbilityById(skillId)
        if res and res.Name and res.Name[1] and res.Name[1] ~= '' then return res.Name[1] end
        return nil
    end
    local name = resMgr:GetString('monsters.abilities', skillId - 256)
    if name and name ~= '' then return name end
    return nil
end

-- Log type 7/11 mob skills that dealt damage but had no status message and are not in any
-- tracking table. Candidates for mobSkillSilentDebuffs if LSB confirms a silent
-- mobStatusEffectMove() call. Deduplicated by skill ID per session.
-- hasSkillDebuffs marks a skill that owns a skillDebuffs entry which this damage message could
-- not reach — the strongest silent-status candidates, since the entry proves a status is known.
local function logUntrackedMobSkillHit(skillId, message, damage, actorId, targetId, hasSkillDebuffs)
    if not UNKNOWN_BUFF_LOG then return end
    if loggedUntrackedMobSkills[skillId] then return end
    loggedUntrackedMobSkills[skillId] = true
    local skillName = resolveMobSkillName(skillId) or ('skill#' .. skillId)
    local f = io.open(UNKNOWN_BUFF_LOG, 'a')
    if not f then return end
    f:write(string.format('%s  UNTRACKED_MOB_SKILL  skillId=%-5d  msg=%-4d  dmg=%-6d  actor=%-8d  target=%-8d  entry=%-11s name=%s\n',
        os.date('%Y-%m-%d %H:%M:%S'), skillId, message, damage, actorId or 0, targetId or 0,
        hasSkillDebuffs and 'skillDebuffs' or 'none', skillName))
    f:close()
end

-------------------------------------------------------------------------------
-- Status effect audit log
-- Records every status-on application so timers can be audited.
-- Output: config/addons/<addonName>/statusAudit.log (addonName passed to statusLib.init())
-- Fields: action type, ability/spell ID+name, statusId, message, actor, target,
--         duration assigned, and which lookup table provided it (or FALLBACK_300).
-------------------------------------------------------------------------------

local STATUS_AUDIT_LOG = nil

-- Resolve a human-readable name for an ability/spell ID given the action type.
local function resolveAbilityName(actionType, abilityId)
    local resMgr = AshitaCore:GetResourceManager()
    if not resMgr then return '?' end
    -- Types 4/8 = magic spell (finish / cast start)
    if actionType == 4 or actionType == 8 then
        local res = resMgr:GetSpellById(abilityId)
        return (res and res.Name and res.Name[1]) or ('spell#' .. abilityId)
    end
    -- Types 6 = job ability, 7 = monster skill, 11 = 2hr/special.
    -- Automaton abilities resolve to the wrong name via GetAbilityById, and always arrive
    -- as type 11 (MobSkillFinish) — never type 7.
    if actionType == 11 then
        local petName = petAbilities and petAbilities.names[abilityId]
        if petName then return petName end
    end
    -- Monster skills index a separate string table, not the ability table.
    if actionType == 7 or actionType == 11 then
        local mobName = resolveMobSkillName(abilityId)
        if mobName then return mobName end
    end
    -- The client's ability table indexes weapon skills at the raw ID and job abilities at
    -- ID + 0x200. Type 3 carries both: weapon skills and the physical JAs.
    local lookupId = abilityId
    if actionType == 6 or (actionType == 3 and physicalJaDebuffs and physicalJaDebuffs[abilityId]) then
        lookupId = abilityId + 0x200
    end
    local res = resMgr:GetAbilityById(lookupId)
    if res and res.Name and res.Name[1] and res.Name[1] ~= '' then
        return res.Name[1]
    end
    return ('ability#' .. abilityId)
end

-- Resolve an entity name from its server ID via entity memory.
local function resolveEntityName(serverId)
    if not serverId or serverId == 0 then return '?' end
    local entMgr = AshitaCore:GetMemoryManager():GetEntity()
    if not entMgr then return '?' end
    -- Monster shortcut
    if bit.band(serverId, 0x1000000) ~= 0 then
        local idx = bit.band(serverId, 0xFFF)
        if idx >= 0x900 then idx = idx - 0x100 end
        if idx < 0x900 and entMgr:GetServerId(idx) == serverId then
            return entMgr:GetName(idx) or '?'
        end
    end
    for i = 1, 0x8FF do
        if entMgr:GetServerId(i) == serverId then
            return entMgr:GetName(i) or '?'
        end
    end
    return '?'
end

-- Log mob self-buffs whose statusId is not in mobStatusDurations.selfBuffs.
-- These are candidates to add to selfBuffs once the correct duration is researched.
local function logUnknownMobSelfBuff(actionType, abilityId, statusId, actorId)
    if not UNKNOWN_BUFF_LOG then return end
    if loggedUnknownSelfBuffs[statusId] then return end
    loggedUnknownSelfBuffs[statusId] = true
    local actorName = resolveEntityName(actorId)
    local abilityName = resolveAbilityName(actionType, abilityId)
    local actionTypeName = ({[7]='MobSkill',[11]='MobSpecial'})[actionType] or ('t'..actionType)
    local f = io.open(UNKNOWN_BUFF_LOG, 'a')
    if not f then return end
    f:write(string.format('%s  MOB_SELF_BUFF  %-10s abilityId=%-5d %-22s statusId=%-5d actor=%08X(%s)\n',
        os.date('%Y-%m-%d %H:%M:%S'), actionTypeName, abilityId, abilityName, statusId, actorId, actorName))
    f:close()
end

-- Log a status-on event. Called for every status application so we can audit timers.
-- durationSrc: 'abilityDurations' | 'mobStatusDurations' | 'spellDurations' | 'FALLBACK_300'
local function logStatusApplication(actionType, abilityId, statusId, message, actorId, targetId, duration, durationSrc)
    if not STATUS_AUDIT_LOG then return end
    local f = io.open(STATUS_AUDIT_LOG, 'a')
    if not f then return end
    local abilityName = resolveAbilityName(actionType, abilityId)
    local actorName   = resolveEntityName(actorId)
    local targetName  = resolveEntityName(targetId)
    local isSelf      = (actorId == targetId) and 'SELF' or 'OTHER'
    local actionTypeName = ({[4]='Spell',[6]='JA',[7]='MobSkill',[8]='CastStart',[11]='MobSpecial',[13]='Pet'})[actionType] or ('t'..actionType)
    f:write(string.format(
        '%s  [STATUS_ON]  %-8s id=%-5d %-22s statusId=%-4d msg=%-4d %s  actor=%08X(%-16s) target=%08X(%-16s)  dur=%3ds  src=%s\n',
        os.date('%Y-%m-%d %H:%M:%S'),
        actionTypeName, abilityId, abilityName,
        statusId, message, isSelf,
        actorId, actorName, targetId, targetName,
        duration, durationSrc))
    f:close()
end

-------------------------------------------------------------------------------
-- exported functions
-------------------------------------------------------------------------------

local statusTracker = { 
    trackedEntities = T{}; -- entites by serverId that we are tracking buffs and debuffs on
    relevantTargets = T{}; -- targets by targetIndex that are relevant to the player
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

-- if a mob updates its claimid to be us or a party member add it to the list
statusTracker.HandleMobUpdatePacket = function(e)
    local mobUpdate = helpers.ParseMobUpdatePacket(e);
	if (mobUpdate == nil) then 
		return; 
	end
    if (helpers.GetIsValidMob(mobUpdate.monsterIndex)) then
        if (mobUpdate.newClaimId ~= nil) then	
            local partyMemberIds = helpers.GetPartyMemberIds();
            if ((partyMemberIds:contains(mobUpdate.newClaimId))) then
                statusTracker.relevantTargets[mobUpdate.monsterIndex] = 1;
            end
        end
    else
        statusTracker.relevantTargets[mobUpdate.monsterIndex] = nil; -- Clear non valid mobs that have received an update
    end
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
    local message = ability.Message
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

    local durationSrc
    local duration
    if action.Type == 6 and abilityDurations[spell] then
        duration = abilityDurations[spell]; durationSrc = 'abilityDurations'
    elseif action.Type == 3 and physicalJaDebuffs[spell] then
        -- physicalJaDebuffs handles this below with hit confirmation; skip FALLBACK here
        duration = physicalJaDebuffs[spell].duration; durationSrc = 'physicalJaDebuffs'
    elseif isPetActor and action.Type == 11 and petAbilities ~= nil and petAbilities.durations[spell] ~= nil then
        -- Ahead of skillDebuffs: pet ability IDs share the mob-skill namespace, so a pet
        -- ability must not resolve against a mob-skill entry of the same ID.
        duration = petAbilities.durations[spell]; durationSrc = 'petAbilities'
    elseif (action.Type == 7 or action.Type == 11 or (action.Type == 3 and action.UserIndex ~= nil and helpers.GetIsMob(action.UserIndex) == true)) and mobStatusDurations ~= nil and mobStatusDurations.skillDebuffs[spell] ~= nil then
        local skillEntry = mobStatusDurations.skillDebuffs[spell]
        if type(skillEntry) == 'table' then
            local d = statusId and skillEntry[statusId]
            if d ~= nil then duration = d; durationSrc = 'mobStatusDurations' end
        else
            duration = skillEntry; durationSrc = 'mobStatusDurations'
        end
    elseif action.Type == 4 and spellDurations[spell] then
        duration = spellDurations[spell]; durationSrc = 'spellDurations'
    elseif action.Type == 13 and wardBuffDurations[spell] then
        duration = wardBuffDurations[spell]; durationSrc = 'wardBuffDurations'
    end
    if duration == nil then
        logUnknownDuration(spell, statusId);
        duration = FALLBACK_DURATION_S; durationSrc = 'FALLBACK_300'
    end
    if duration == 0 then return true end  -- shadow/luopan-based effects have no time component
    if meta and meta.clears then
        for _, clearId in ipairs(meta.clears) do
            removeStatus(target.Id, clearId)
        end
    end
    local displayId = meta and meta.statusId == statusId and meta.displayId or nil
    recordStatus(target.Id, statusId, now + duration, false, displayId)
    logStatusApplication(action.Type, spell, statusId, message, action.UserId, target.Id, duration, durationSrc);
    return false
end

-- Mob self-buff (statusOnMes, actor == target): track event-driven using exact per-skill
-- duration where known. Captured regardless of targeting (e.g. 2hr Invincible mid-fight).
local function applyMobSelfBuff(action, target, ability, now)
    local spell = action.Param
    local message = ability.Message
    local statusId = ability.Param
    if statusId and statusId ~= 0 then
        local dur = mobStatusDurations.getSelfBuffDuration(statusId, spell)
        if dur == nil then
            logUnknownMobSelfBuff(action.Type, spell, statusId, action.UserId)
        elseif dur > 0 then
            recordStatus(target.Id, statusId, now + dur)
            logStatusApplication(action.Type, spell, statusId, message, action.UserId, target.Id, dur, 'selfBuffs')
        end
        -- dur == 0: known permanent effect (e.g. bastion_of_twilight), silently skip
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

-- Physical JA debuffs (type 3): weapon-based abilities (Shield Bash, Weapon Bash).
-- Apply on hit confirmed (ability.Param = damage > 0), no overwrite if already active.
-- Absorb-*: the packet carries the target's debuff message only. Apply that debuff, and the
-- caster's matching boost, which the server grants silently.
local function applyAbsorbSpell(action, target, ability, now)
    local absorb = absorbSpells and absorbSpells[action.Param]
    if absorb == nil or ability.Message ~= absorb.message then return false end
    local expiry = now + absorb.duration
    if statusTracker.trackedEntities[target.Id] then
        recordStatus(target.Id, absorb.down, expiry)
    end
    recordStatus(action.UserId, absorb.boost, expiry)
    logStatusApplication(4, action.Param, absorb.down, ability.Message, action.UserId, target.Id, absorb.duration, 'absorbSpells')
    return true
end

local function applyPhysicalJaDebuff(action, target, ability, now)
    local spell = action.Param
    local message = ability.Message
    local jaDebuff = physicalJaDebuffs[spell]
    if jaDebuff and ability.Param > 0 then
        local existing = statusTracker.trackedEntities[target.Id][jaDebuff.statusId]
        if not existing or existing <= now then
            recordStatus(target.Id, jaDebuff.statusId, now + jaDebuff.duration, true)
            logStatusApplication(3, spell, jaDebuff.statusId, message, action.UserId, target.Id, jaDebuff.duration, 'physicalJaDebuffs')
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
                logStatusApplication(3, spell, statusId, message, action.UserId, target.Id, ws.duration, 'wsDurations')
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
                logStatusApplication(13, action.Param, sid, ability.Message, action.UserId, target.Id, dur, 'bloodPactDebuffs')
            end
        end
    elseif ability.Param > 0 then
        -- Physical hit path: only when damage > 0 and no active timer exists.
        local existing = statusTracker.trackedEntities[target.Id][pactDebuff.statusId]
        if not existing or existing <= now then
            recordStatus(target.Id, pactDebuff.statusId, now + pactDebuff.duration, true)
            logStatusApplication(13, action.Param, pactDebuff.statusId, ability.Message, action.UserId, target.Id, pactDebuff.duration, 'bloodPactDebuffs')
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
    local silentSrc = 'mobSkillSilentDebuffs'
    if not silentDebuff and petAbilities then
        silentDebuff = petAbilities.hitData[spell]
        silentSrc = 'petAbilities'
    end
    if silentDebuff and ability.Param > 0 and ability.Message ~= SHADOW_ABSORB_MES then
        -- Multi-status skills hold a list of records; single-status ones are the record itself.
        local records = silentDebuff[1] and silentDebuff or { silentDebuff }
        for _, record in ipairs(records) do
            local existing = statusTracker.trackedEntities[target.Id][record.statusId]
            if not existing or existing <= now then
                recordStatus(target.Id, record.statusId, now + record.duration, true)
                logStatusApplication(action.Type, spell, record.statusId, ability.Message, action.UserId, target.Id, record.duration, silentSrc)
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

-- A single-target physical hit landing on an entity proves its Copy Image images are spent.
local function noteShadowProof(targetId, now)
    local entity = statusTracker.trackedEntities[targetId]
    if entity == nil then return end
    for statusId in pairs(SHADOW_COPY_IMAGE_IDS) do
        if entity[statusId] ~= nil and entity[statusId] > now then
            removeStatus(targetId, statusId)
        end
    end
end

statusTracker.HandleActionPacket = function(e)

    local action = helpers.ParseActionPacket(e);
    if (action == nil) then
        return;
    end

    local relevantTarget = helpers.GetIsMob(action.UserIndex) and helpers.GetIsValidMob(action.UserIndex);

    -- ParseActionPacket sets UserIndex via GetIndexFromId, which returns 0 on a miss, and
    -- index 0 is the local player.
    local isPetActor = false
    if action.UserIndex ~= nil and action.UserIndex ~= 0 then
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

    local partyMemberIds = helpers.GetPartyMemberIds();
    for _, target in pairs(action.Targets) do
        -- Update our relvant enemies first
        if (relevantTarget and partyMemberIds:contains(target.Id)) then
            statusTracker.relevantTargets[action.UserIndex] = 1;
        end
        for _, ability in pairs(target.Actions) do
            -- Set up our state
            local spell = action.Param
            local message = ability.Message
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
                elseif action.UserId == target.Id then
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
            if (action.Type == 7 or action.Type == 11) and action.UserId ~= target.Id and spell then
                applySilentMobDebuff(action, target, ability, now)
            end

            -- Catch-all: type 7/11 mob skills that dealt damage (ability.Param > 0) with a
            -- message outside statusOnMes and not NONE (0), and are not already covered by
            -- mobSkillSilentDebuffs or petAbilities.hitData. Logged once per skill ID per
            -- session to unknownDurations.log as UNTRACKED_MOB_SKILL — candidates for
            -- mobSkillSilentDebuffs if LSB confirms a silent mobStatusEffectMove() call
            -- (thunderspark pattern).
            -- A skillDebuffs entry does NOT suppress this: that table is only read from the
            -- status-message and NONE-message paths, so on a damage message it did nothing.
            -- Suppressing on it hid barofield (1832) and nerve_gas's POISON from every log.
            if (action.Type == 7 or action.Type == 11)
                    and action.UserId ~= target.Id
                    and spell
                    and ability.Param > 0
                    and message ~= SHADOW_ABSORB_MES
                    and not statusOnMes[message]
                    and message ~= 0 then
                local debuffs = mobStatusDurations and mobStatusDurations.skillDebuffs
                local petHits = petAbilities and petAbilities.hitData
                if not mobSkillSilentDebuffs[spell] and not (petHits and petHits[spell]) then
                    logUntrackedMobSkillHit(spell, message, ability.Param, action.UserId, target.Id,
                        debuffs ~= nil and debuffs[spell] ~= nil)
                end
            end

            applyAdditionalEffect(action, target, ability, now)
            ::continue_ability::
        end
    end
end

-- Call once at plugin load and keep reference to table
statusTracker.ReadPartyStatusFromMemory = function()
    local p = AshitaCore:GetPointerManager():Get('party.statusicons');
    if p == 0 then return {}; end
    local ptrPartyStatus = ashita.memory.read_uint32(p);
    local partyStatusTable = {};
    for memberIndex = 0,4 do
        local memberPtr = ptrPartyStatus + (0x30 * memberIndex);
        local playerId = ashita.memory.read_uint32(memberPtr);
        if (playerId ~= 0) then
            local buffs = {};
            local empty = false;
            for buffIndex = 0,31 do
                if empty then
                    buffs[buffIndex + 1] = nil;
                else
                    local highBits = ashita.memory.read_uint8(memberPtr + 8 + (math.floor(buffIndex / 4)));
                    local fMod = math.fmod(buffIndex, 4) * 2;
                    highBits = bit.lshift(bit.band(bit.rshift(highBits, fMod), 0x03), 8);
                    local lowBits = ashita.memory.read_uint8(memberPtr + 16 + buffIndex);
                    local buff = highBits + lowBits;
                    if buff == 255 then
                        empty = true;
                        buffs[buffIndex + 1] = nil;
                    else
                        buffs[buffIndex + 1] = buff;
                    end
                end
            end
            partyStatusTable[playerId] = buffs;
        end
    end
    return partyStatusTable;
end

statusTracker.partyStatus = statusTracker.ReadPartyStatusFromMemory();

--Call with incoming packet 0x076
statusTracker.HandlePartyUpdatePacket = function(e)
    local partyStatusTable = {};
    for i = 0,4 do
        local memberOffset = 0x04 + (0x30 * i) + 1;
        local memberId = struct.unpack('L', e.data, memberOffset);
        if memberId > 0 then
            local buffs = {};
            local empty = false;
            for j = 0,31 do
                if empty then
                    buffs[j + 1] = nil;
                else
                    --This is at offset 8 from member start.. memberoffset is using +1 for the lua struct.unpacks
                    local highBits = bit.lshift(ashita.bits.unpack_be(e.data_raw, memberOffset + 7, j * 2, 2), 8);
                    local lowBits = struct.unpack('B', e.data, memberOffset + 0x10 + j);
                    local buff = highBits + lowBits;
                    if (buff == 255) then
                        buffs[j + 1] = nil;
                        empty = true;
                    else
                        buffs[j + 1] = buff;
                    end
                end
            end
            partyStatusTable[memberId] = buffs;
        end
    end
    statusTracker.partyStatus =  partyStatusTable;
end


statusTracker.HandleClearMessage = function(e)

    local parsedPacket = helpers.ParseMessagePacket(e.data)
    if (parsedPacket == nil) then
        return;
    end

        -- if we're tracking a mob that dies, reset its status
    if deathMes[parsedPacket.message] and statusTracker.trackedEntities[parsedPacket.target] then
        statusTracker.trackedEntities[parsedPacket.target] = nil
        bioDiaTiers[parsedPacket.target] = nil
        displayIdOverrides[parsedPacket.target] = nil
    elseif parsedPacket.message == WAKEUP_MES then
        -- Mob woke up from damage. param is not a status ID here; clear all sleep-family IDs.
        -- Sleep II is tracked under ID 19 (spellMeta buffId override), so clear both.
        removeStatus(parsedPacket.target, 2)    -- Sleep I
        removeStatus(parsedPacket.target, 19)   -- Sleep II (tracked as 19 via spellMeta buffId)
        removeStatus(parsedPacket.target, 193)  -- Lullaby
    elseif statusOffMes[parsedPacket.message] then
        -- Clear the buffid that just wore off.
        -- Sleep family (IDs 2, 19, 193) shares one wear-off message; clear all three
        -- so a Sleep I icon left from an earlier cast doesn't linger after Sleep II wears.
        if (parsedPacket.param ~= nil) then
            local p = parsedPacket.param;
            if p == 2 or p == 19 or p == 193 then
                removeStatus(parsedPacket.target, 2)
                removeStatus(parsedPacket.target, 19)
                removeStatus(parsedPacket.target, 193)
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

    -- If this is a party member just return the party member
    if (helpers.GetPartyMemberIds():contains(serverId)) then
        return statusTracker.partyStatus[serverId];
    end

    -- Collect our manually tracked entities if it's neither of those
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
        statusTracker.trackedEntities[serverId] = nil;
        displayIdOverrides[serverId] = nil;
    end
    return returnTable;
end

-- Returns {[statusId] = expiryTime} for tracked entities, nil for self/unknown.
-- Party members fall through: HandleActionPacket populates trackedEntities for any target
-- that receives a status-on message, so debuffs (accurate duration) and buffs applied during
-- the session (300s fallback for unknown spells) will have timers; pre-existing buffs will not.
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
            statusTracker.trackedEntities[sid] = nil;
            displayIdOverrides[sid] = nil;
            bioDiaTiers[sid] = nil;
        end
    end
end

statusTracker.GetRelevantTargets = function()
    return statusTracker.relevantTargets;
end

local STATE_FILE = nil

-- Saves non-expired tracked entity debuffs to disk so they survive addon reloads.
statusTracker.SaveState = function()
    local now = os.time()
    local f = io.open(STATE_FILE, 'w')
    if not f then return end
    f:write('return {\n')
    for sid, buffs in pairs(statusTracker.trackedEntities) do
        local lines = {}
        for statusId, expiry in pairs(buffs) do
            if expiry > now then
                lines[#lines + 1] = string.format('    [%d]=%d,', statusId, expiry)
            end
        end
        if #lines > 0 then
            f:write(string.format('  [%d]={\n', sid))
            for _, line in ipairs(lines) do f:write(line .. '\n') end
            f:write('  },\n')
        end
    end
    f:write('}\n')
    f:close()
end

-- Restores non-expired debuffs from the state file saved by a previous session.
statusTracker.RestoreState = function()
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
-- @param opts  { addonPath = string, addonName = string, enableAuditLog = bool }
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

    if opts.enableAuditLog ~= false then
        UNKNOWN_BUFF_LOG = AshitaCore:GetInstallPath() .. 'config/addons/' .. opts.addonName .. '/unknownDurations.log'
        STATUS_AUDIT_LOG = AshitaCore:GetInstallPath() .. 'config/addons/' .. opts.addonName .. '/statusAudit.log'
    end

    STATE_FILE = AshitaCore:GetInstallPath() .. 'config/addons/' .. opts.addonName .. '/statusstate.dat'

    statusTracker.RestoreState()
end

-- Clear all tracked status effects for a specific entity.
statusTracker.clearEntity = function(serverId)
    statusTracker.trackedEntities[serverId] = nil
    bioDiaTiers[serverId] = nil
    displayIdOverrides[serverId] = nil
end

-- Tears down this module's registered event handler. Call from the addon's unload event.
statusTracker.Dispose = function()
    ashita.events.unregister('packet_in', '__status_packet_in_cb');
end

-- The usual packet event doesn't register in libs but this __settings one does. Feels bad.
ashita.events.register('packet_in', '__status_packet_in_cb', function (e)

    if (e.id == 0x076) then
        statusTracker.HandlePartyUpdatePacket(e);
    elseif (e.id == 0x00A) then -- Clear everything on zone
        statusTracker.trackedEntities = T{};
        statusTracker.relevantTargets = T{};
        bioDiaTiers = {};
        displayIdOverrides = {};
    elseif (e.id == 0x0029) then
        statusTracker.HandleClearMessage(e);
    elseif (e.id == 0x0028) then
        statusTracker.HandleActionPacket(e);
    elseif (e.id == 0x00E) then
        statusTracker.HandleMobUpdatePacket(e);
        sweepExpiredEntities();  -- periodic cleanup of stale entity shells (time-gated inside)
    end
end);

return statusTracker;