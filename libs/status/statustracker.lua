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
local petAbilities              = nil;
local FALLBACK_DURATION_S       = 300;

-- Status-ON messages: action packet messages that carry a status effect application.
-- Named IDs match xi.msg.basic in LSB-server/scripts/enum/msg.lua.
-- IDs marked [retail] are from retail packet captures; not in HorizonXI's msg.lua but
-- confirmed by XIUI and LSB test comments — harmless if they don't fire here.
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
--   minor and accepted (matches XIUI behaviour).
local statusOnMes = {[101]=true,[127]=true,[160]=true,[164]=true,[166]=true,[186]=true,[194]=true,[203]=true,[205]=true,[230]=true,[236]=true,[242]=true,[243]=true,[266]=true,[267]=true,[268]=true,[269]=true,[237]=true,[271]=true,[272]=true,[277]=true,[278]=true,[279]=true,[280]=true,[319]=true,[320]=true,[375]=true,[412]=true,[645]=true,[754]=true,[755]=true,[804]=true}
-- Status-OFF messages: action/message packet messages that indicate a status was removed.
--   64=[retail], 159=SKILL_ERASE, 204=IS_NO_LONGER_STATUS, 206=STATUS_WEARS_OFF,
--   321=JA_REMOVE_EFFECT_2, 322=[retail], 341=MAGIC_ERASE, 342/343/344=[retail],
--   350=[retail], 378=ITEM_EFFECT_DISAPPEARS, 531/647/805/806=[retail]
local statusOffMes = {[64]=true,[159]=true,[204]=true,[206]=true,[321]=true,[322]=true,[341]=true,[342]=true,[343]=true,[344]=true,[350]=true,[378]=true,[531]=true,[647]=true,[805]=true,[806]=true}
local WAKEUP_MES = 168  -- "X awakens." — woken from sleep by damage; param is not a status ID
local deathMes = {[6]=true,[20]=true,[97]=true,[113]=true,[406]=true,[605]=true,[646]=true}
local spellDamageMes = {[2]=true,[252]=true,[264]=true,[265]=true}

-- Bio/Dia: mirrors server logic (onSpellCast in dia.lua / bio.lua).
-- Server always deals damage, but only applies the status if new tier > existing opposing tier.
-- Tiers: Dia(1) < Bio(2) < DiaII(3) < BioII(4) < DiaIII(5) < BioIII(6)
local bioDiaData = {
    [23]  = { statusId=134, opposing=135, tier=1, dur=60  },             -- Dia
    [33]  = { statusId=134, opposing=135, tier=1, dur=60  },             -- Diaga
    [24]  = { statusId=134, opposing=135, tier=3, dur=120, displayId=807 }, -- Dia II
    [34]  = { statusId=134, opposing=135, tier=3, dur=120, displayId=807 }, -- Diaga II
    [25]  = { statusId=134, opposing=135, tier=5, dur=180, displayId=807 }, -- Dia III
    [230] = { statusId=135, opposing=134, tier=2, dur=60  },             -- Bio
    [231] = { statusId=135, opposing=134, tier=4, dur=120, displayId=808 }, -- Bio II
    [232] = { statusId=135, opposing=134, tier=6, dur=180, displayId=808 }, -- Bio III
}
-- [targetId] = { statusId, tier } — single slot; Bio/Dia are mutually exclusive.
local bioDiaTiers = {}

-- Per-spell metadata applied in the statusOnMes path.
--   buffId    — override the status ID the server sends (e.g. Sleep II sends 2, we track as 19)
--   clears    — status IDs to remove before applying the new one
--   statusId  — expected status ID guard for displayId (must match ability.Param after buffId remap)
--   displayId — custom icon to show instead of the real status icon (base-tier spell clears it)
local spellMeta = {
    [259] = { buffId = 19, clears = {2, 193} },  -- Sleep II    → SLEEP_II (19), clears Sleep I + Lullaby
    [274] = { buffId = 19, clears = {2, 193} },  -- Sleepga II  → SLEEP_II (19), clears Sleep I + Lullaby
    [364] = { buffId = 19, clears = {2, 193} },  -- Sleepga III → SLEEP_II (19), clears Sleep I + Lullaby
    [221] = { statusId = 3, displayId = 809 },   -- Poison II   → custom icon (809)
}

-- [serverId][realStatusId] = displayStatusId (807-1022 range, see libs/status/icons/README.md)
local displayIdOverrides = {}

local function getDisplayId(serverId, statusId)
    local overrides = displayIdOverrides[serverId]
    return (overrides and overrides[statusId]) or statusId
end

-- Physical JA debuffs (type 3): weapon-based player abilities that apply status effects
-- server-side via addStatusEffect(). Fire as action type 3 (not type 6), so the normal
-- abilityDurations path never fires for them.
-- Keyed by ability ID (action.Param). Applied when damage > 0 (hit confirmed).
local physicalJaDebuffs = {
    [46] = { statusId = 10, duration = 6 },   -- Shield Bash (PLD) → STUN (10), fixed 6s
    [77] = { statusId = 10, duration = 8 },   -- Weapon Bash (DRK) → STUN (10), random 2-8s; max
    [57] = { statusId = 11, duration = 30 },  -- Shadowbind (RNG) → BIND (11), fixed 30s [LSB abilities.sql: actionType=3, not 6]
}

-- Blood pact debuffs/buffs on the pet or enemies: avatar pacts that apply status effects
-- server-side in ways the normal action packet paths cannot track.  Two sub-formats:
--
--   Physical hit path  { statusId, duration }
--     Avatar physical attack calls addStatusEffect() server-side.  Status does not appear
--     in AdditionalEffect bits.  Triggered only when ability.Param (damage) > 0 (hit
--     confirmed) and the target has no active timer (mirrors LSB hasStatusEffect check).
--
--   Message path  { messages = {[msgId]=true,...}, statuses = {[statusId]=duration,...} }
--     Avatar pact uses a custom result message (not in statusOnMes) and returns 0 from
--     the script, so ability.Param=0.  Triggered when ability.Message matches any entry
--     in messages{}; all statuses{} are applied simultaneously.
--
-- Keyed by ability ID (action.Param for type 13).
local bloodPactDebuffs = {
    -- ── Physical hit pacts ────────────────────────────────────────────────────
    [513] = { statusId = 3,  duration = 60  },  -- Poison Nails  (Carbuncle) → Poison (3),      60s  [physical hit]
    [528] = { statusId = 5,  duration = 30  },  -- Moonlit Charge(Fenrir)    → Blindness (5),   30s  [physical hit]
    [529] = { statusId = 4,  duration = 90  },  -- Crescent Fang (Fenrir)    → Paralysis (4),   90s  [physical hit]
    [578] = { statusId = 12, duration = 120 },  -- Tail Whip     (Leviathan) → Weight (12),    120s  [physical hit, resist-scaled]
    [624] = { statusId = 10, duration = 2   },  -- Shock Strike  (Ramuh)     → Stun (10),        2s  [physical hit]
    [627] = { statusId = 4,  duration = 60  },  -- Thunderspark  (Ramuh)     → Paralysis (4),   60s  [physical hit; thunderspark.lua]
    [630] = { statusId = 10, duration = 15  },  -- Chaotic Strike(Ramuh)     → Stun (10),        3 hits × 0-5s; max 15s [horizonffxi.wiki/Chaotic_Strike]
    [657] = { statusId = 12, duration = 120 },  -- Somnolence    (Diabolos)  → Weight (12),    120s  [physical hit; somnolence.lua]
    -- ── Message-triggered pacts (custom msg, script returns 0) ────────────────
    -- Ecliptic Growl (Fenrir): msg 364/365 (STATUS_BOOST/_2) → 7 stat boosts, 180s
    [532] = { messages = {[364]=true, [365]=true}, statuses = {[80]=180, [81]=180, [82]=180, [83]=180, [84]=180, [85]=180, [86]=180} },
    -- Ecliptic Howl (Fenrir): msg 146/147 (ACC_EVA_BOOST/_2) → ACCURACY_BOOST(90) + EVASION_BOOST(92), 180s
    [533] = { messages = {[146]=true, [147]=true}, statuses = {[90]=180, [92]=180} },
}

-- Mob skill silent debuffs: mob skills that call mobStatusEffectMove() but do NOT call
-- skill:setMsg() with the result.  The status is applied server-side but the 0x028 action
-- carries a damage message — neither the statusOnMes path nor the NONE-message path fires.
-- Pattern mirrors bloodPactDebuffs: only applied when ability.Param (damage) > 0 and no
-- active timer exists.  May produce false timers if the status was resisted independently
-- of the damage, but resist on these abilities is uncommon.
-- Keyed by mob skill ID (action.Param for type 7/11).
local mobSkillSilentDebuffs = {
    [888] = { statusId = 4, duration = 60 },  -- Thunderspark (Ramuh) → PARALYSIS (4), 60s [thunderspark.lua — ignores mobStatusEffectMove return value]
}

-- Blood pact ward buff durations: SMN avatar ward pacts that apply status effects to party
-- members via addStatusEffect() server-side.  Fire as type 13 (blood pact) actions with
-- msg=JA_GAIN_EFFECT (266) and ability.Param = statusId.
-- Keyed by blood pact ability ID (action.Param for type 13).
-- Duration = base value; actual in-game duration for skill-scaled pacts (Shining Ruby,
-- Hastega) is 180 + clamp(summoning_skill - 300, 0, 200) s.  180 is conservative minimum.
-- Source: LSB scripts/actions/abilities/pets/<name>.lua
local wardBuffDurations = {
    [514] = 180,  -- Shining Ruby     (Carbuncle) → SHINING_RUBY (154), 180s base [shining_ruby.lua]
    [515] = 90,   -- Glittering Ruby  (Carbuncle) → random stat boost,  90s       [glittering_ruby.lua]
    [548] = 60,   -- Crimson Howl     (Ifrit)     → WARCRY       (68),  60s+bonus [crimson_howl.lua]
    [564] = 900,  -- Earthen Ward     (Titan)     → STONESKIN    (37),  900s      [earthen_ward.lua]
    [579] = 120,  -- Spring Water     (Leviathan) → REFRESH      (43),  120s est. [observed in-game; script not explicit]
    [595] = 180,  -- Hastega          (Garuda)    → HASTE        (33),  180s base [hastega.lua]
    [596] = 900,  -- Aerial Armor     (Garuda)    → BLINK        (36),  900s      [aerial_armor.lua]
    [610] = 180,  -- Frost Armor      (Shiva)     → ICE_SPIKES   (35),  180s base [frost_armor.lua]
    [626] = 120,  -- Rolling Thunder  (Ramuh)     → ENTHUNDER    (98),  120s base [rolling_thunder.lua]
    [628] = 180,  -- Lightning Armor  (Ramuh)     → SHOCK_SPIKES (38),  180s base [lightning_armor.lua]
    [658] = 90,   -- Nightmare        (Diabolos)  → SLEEP_I      (2),   90s base  [nightmare.lua]
    [660] = 180,  -- Noctoshield      (Fenrir)    → PHALANX      (116), 180s base [noctoshield.lua]
    [661] = 180,  -- Dream Shroud     (Diabolos)  → MAGIC_ATK/DEF_BOOST, 180s base [dream_shroud.lua]
}


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

-- Log type 7/11 mob skills that dealt damage but had no status message and are not in any
-- tracking table. Candidates for mobSkillSilentDebuffs if LSB confirms a silent
-- mobStatusEffectMove() call. Deduplicated by skill ID per session.
local function logUntrackedMobSkillHit(skillId, message, damage, actorId, targetId)
    if not UNKNOWN_BUFF_LOG then return end
    if loggedUntrackedMobSkills[skillId] then return end
    loggedUntrackedMobSkills[skillId] = true
    local resMgr = AshitaCore:GetResourceManager()
    local res = resMgr and resMgr:GetAbilityById(skillId)
    local skillName = (res and res.Name and res.Name[1] and res.Name[1] ~= '' and res.Name[1]) or ('skill#' .. skillId)
    local f = io.open(UNKNOWN_BUFF_LOG, 'a')
    if not f then return end
    f:write(string.format('%s  UNTRACKED_MOB_SKILL  skillId=%-5d  msg=%-4d  dmg=%-6d  actor=%-8d  target=%-8d  name=%s\n',
        os.date('%Y-%m-%d %H:%M:%S'), skillId, message, damage, actorId or 0, targetId or 0, skillName))
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
    local res = resMgr:GetAbilityById(abilityId)
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

-- Bio and Dia: mirrors server tier check (not bio or bio:getTier() < tier).
-- spellDamageMes fires even when the server rejects the status, so the caller gates on
-- action.Type == 4 and spellDamageMes[message] before calling this.
local function applyBioDia(action, target, ability, now)
    local spell = action.Param
    local bioDia = bioDiaData[spell]
    if not bioDia then return end
    local active = bioDiaTiers[target.Id]
    if not active or active.tier < bioDia.tier then
        statusTracker.trackedEntities[target.Id][bioDia.opposing] = nil
        statusTracker.trackedEntities[target.Id][bioDia.statusId] = now + bioDia.dur
        bioDiaTiers[target.Id] = { statusId = bioDia.statusId, tier = bioDia.tier }
        -- Set or clear display icon override based on tier
        local ov = displayIdOverrides[target.Id]
        if bioDia.displayId then
            displayIdOverrides[target.Id] = ov or {}
            displayIdOverrides[target.Id][bioDia.statusId] = bioDia.displayId
            displayIdOverrides[target.Id][bioDia.opposing]  = nil
        else
            if ov then ov[bioDia.statusId] = nil; ov[bioDia.opposing] = nil end
        end
    end
end

-- Regular buffs/debuffs from a statusOnMes message (the non-mob-self-buff sub-path).
-- Returns true if the caller should `goto continue_ability` (status unresolved, or the
-- resolved duration is a known-zero shadow/luopan-based effect with no time component).
local function applyStatusOn(action, target, ability, now, isPetActor)
    local spell = action.Param
    local message = ability.Message
    -- Regular buffs/debuffs (including mob skills targeting the pet)
    local statusId = ability.Param or (action.Type == 4 and statusTable.GetStatusIdBySpellId(spell) or nil);
    if (statusId == nil) then
        return true
    end
    local meta = spellMeta[spell]
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
            statusTracker.trackedEntities[target.Id][clearId] = nil;
        end
    end
    statusTracker.trackedEntities[target.Id][statusId] = now + duration;
    logStatusApplication(action.Type, spell, statusId, message, action.UserId, target.Id, duration, durationSrc);
    if meta and meta.displayId and meta.statusId == statusId then
        displayIdOverrides[target.Id] = displayIdOverrides[target.Id] or {}
        displayIdOverrides[target.Id][statusId] = meta.displayId
    elseif displayIdOverrides[target.Id] then
        displayIdOverrides[target.Id][statusId] = nil  -- base spell: clear any high-tier override
    end
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
            statusTracker.trackedEntities[target.Id][statusId] = now + dur
            logStatusApplication(action.Type, spell, statusId, message, action.UserId, target.Id, dur, 'selfBuffs')
        end
        -- dur == 0: known permanent effect (e.g. bastion_of_twilight), silently skip
    end
end

-- Dispel, Finale, or other buff-removal spells/abilities targeting this entity.
-- ability.Param carries the status effect ID that was removed.
local function applyStatusOff(action, target, ability, now)
    local statusId = ability.Param
    if statusId and statusId ~= 0 and statusTracker.trackedEntities[target.Id] then
        statusTracker.trackedEntities[target.Id][statusId] = nil
    end
end

-- Physical JA debuffs (type 3): weapon-based abilities (Shield Bash, Weapon Bash).
-- Apply on hit confirmed (ability.Param = damage > 0), no overwrite if already active.
local function applyPhysicalJaDebuff(action, target, ability, now)
    local spell = action.Param
    local message = ability.Message
    local jaDebuff = physicalJaDebuffs[spell]
    if jaDebuff and ability.Param > 0 then
        local existing = statusTracker.trackedEntities[target.Id][jaDebuff.statusId]
        if not existing or existing <= now then
            statusTracker.trackedEntities[target.Id][jaDebuff.statusId] = now + jaDebuff.duration
            logStatusApplication(3, spell, jaDebuff.statusId, message, action.UserId, target.Id, jaDebuff.duration, 'physicalJaDebuffs')
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
                statusTracker.trackedEntities[target.Id][sid] = now + dur
                logStatusApplication(13, action.Param, sid, ability.Message, action.UserId, target.Id, dur, 'bloodPactDebuffs')
            end
        end
    elseif ability.Param > 0 then
        -- Physical hit path: only when damage > 0 and no active timer exists.
        local existing = statusTracker.trackedEntities[target.Id][pactDebuff.statusId]
        if not existing or existing <= now then
            statusTracker.trackedEntities[target.Id][pactDebuff.statusId] = now + pactDebuff.duration
            logStatusApplication(13, action.Param, pactDebuff.statusId, ability.Message, action.UserId, target.Id, pactDebuff.duration, 'bloodPactDebuffs')
        end
    end
end

-- Mob skill silent debuffs: mob skills that apply status via mobStatusEffectMove()
-- but never call skill:setMsg() — damage message fires, status lands silently.
-- Pet abilities of the same shape come from petAbilities.hitData.
-- Only applied when ability.Param (damage) > 0 and no active timer exists.
local function applySilentMobDebuff(action, target, ability, now)
    local spell = action.Param
    local silentDebuff = mobSkillSilentDebuffs[spell]
    local silentSrc = 'mobSkillSilentDebuffs'
    if not silentDebuff and petAbilities then
        silentDebuff = petAbilities.hitData[spell]
        silentSrc = 'petAbilities'
    end
    if silentDebuff and ability.Param > 0 then
        local existing = statusTracker.trackedEntities[target.Id][silentDebuff.statusId]
        if not existing or existing <= now then
            statusTracker.trackedEntities[target.Id][silentDebuff.statusId] = now + silentDebuff.duration
            logStatusApplication(action.Type, spell, silentDebuff.statusId, ability.Message, action.UserId, target.Id, silentDebuff.duration, silentSrc)
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
            statusTracker.trackedEntities[target.Id][aeStatusId] = now + aeDuration
        elseif statusOffMes[aeMessage] then
            if statusTracker.trackedEntities[target.Id] then
                statusTracker.trackedEntities[target.Id][aeStatusId] = nil
            end
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

            -- Bio and Dia: mirrors server tier check (not bio or bio:getTier() < tier).
            -- spellDamageMes fires even when the server rejects the status, so we must gate here.
            if action.Type == 4 and spellDamageMes[message] then
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
            -- skillDebuffs, mobSkillSilentDebuffs or petAbilities.hitData. Logged once per
            -- skill ID per session to unknownDurations.log as UNTRACKED_MOB_SKILL — candidates
            -- for mobSkillSilentDebuffs if LSB confirms a silent mobStatusEffectMove() call
            -- (thunderspark pattern).
            if (action.Type == 7 or action.Type == 11)
                    and action.UserId ~= target.Id
                    and spell
                    and ability.Param > 0
                    and not statusOnMes[message]
                    and message ~= 0 then
                local debuffs = mobStatusDurations and mobStatusDurations.skillDebuffs
                local petHits = petAbilities and petAbilities.hitData
                if not mobSkillSilentDebuffs[spell] and not (debuffs and debuffs[spell]) and not (petHits and petHits[spell]) then
                    logUntrackedMobSkillHit(spell, message, ability.Param, action.UserId, target.Id)
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
        local entity = statusTracker.trackedEntities[parsedPacket.target]
        if entity then
            entity[2]   = nil;  -- Sleep I
            entity[19]  = nil;  -- Sleep II (tracked as 19 via spellMeta buffId)
            entity[193] = nil;  -- Lullaby
        end
    elseif statusOffMes[parsedPacket.message] then
        if statusTracker.trackedEntities[parsedPacket.target] == nil then
            return
        end

        -- Clear the buffid that just wore off.
        -- Sleep family (IDs 2, 19, 193) shares one wear-off message; clear all three
        -- so a Sleep I icon left from an earlier cast doesn't linger after Sleep II wears.
        if (parsedPacket.param ~= nil) then
            local p = parsedPacket.param;
            if p == 2 or p == 19 or p == 193 then
                statusTracker.trackedEntities[parsedPacket.target][2]   = nil;
                statusTracker.trackedEntities[parsedPacket.target][19]  = nil;
                statusTracker.trackedEntities[parsedPacket.target][193] = nil;
            else
                statusTracker.trackedEntities[parsedPacket.target][p] = nil;
                if displayIdOverrides[parsedPacket.target] then
                    displayIdOverrides[parsedPacket.target][p] = nil
                end
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
                    if statusTracker.trackedEntities[sid] == nil then
                        statusTracker.trackedEntities[sid] = T{}
                    end
                    statusTracker.trackedEntities[sid][statusId] = expiry
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