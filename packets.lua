-- packets.lua
-- Packet ID constants, pure parse functions, and dispatch handler.
-- Parse functions are pure (no side effects). Callers update State.

local packets   = {}
local socket    = require('socket')
local dataLib   = require('data')
local maneuvers = require('data/maneuvers')
local automatonIcd = require('modules/automatonIcd')

-- Packet IDs
packets.ID = {
    ACTION      = 0x0028,   -- Actions (attacks, magic, weapon skills)
    CHECK_IN    = 0x0029,   -- Check (/check command response from server)
    ZONE_IN     = 0x000A,   -- Zone-in event
    ACTION_OUT  = 0x001A,   -- Outgoing action packet (JA/WS/spell use)
    CHECK_OUT   = 0x00DD,   -- Outgoing check packet (/check command)
    ENTITY_SYNC = 0x0067,   -- Entity update; mode 4 carries the local client's pet
    PET_SYNC    = 0x0068,   -- Byte-identical duplicate of 0x0067, the one LSB actually sends
    EXT_JOB     = 0x0044,   -- Extended job data; the PUP variant carries the automaton's stats
}

-- 0x0044 extended-job data, PUP variant. Field offsets per
-- LSB-server/src/map/packets/s2c/0x044_extended_job_pup.h, with the 4-byte packet header:
--   0x04 uint8   Job      <- must be PUP; BLU and Monstrosity reuse this packet id
--   0x05 uint8   IsSubJob
--   0x08 uint8   Head
--   0x09 uint8   Frame
--   0x0A uint8   Attachments[12]
--   0x68 uint16  HP
--   0x6A uint16  MaxHP
--   0x6C uint16  MP
--   0x6E uint16  MaxMP
local EXT_JOB_PUP = 18

-- MaxMP ends at byte 0x6F.
local EXT_JOB_MIN_BYTES = 0x70

-- 0x0067/0x0068 mode 4 ("updates the local client pet information").
-- Mode is the low 6 bits of the uint16 at offset 0x04; the other modes update player (2)
-- and NPC (3) entities and carry entirely different field layouts at these offsets.
local PET_SYNC_MODE_PET = 4

-- UniqueNoTarget ends at byte 0x17, so 0x18 bytes must be present before it can be read.
-- LSB sends 0x2C with a pet and 0x1C without one (pet_sync.cpp:37,46).
local PET_SYNC_MIN_BYTES = 0x18

-- Outgoing action packet constants
local JA_CATEGORY         = 0x09    -- Job ability category in outgoing action packet
local CHARM_ABILITY       = 0x34    -- Charm ability ID (52)
local FAMILIAR_ABILITY    = 0x18    -- Familiar ability ID (24) -- BST 2hr
local ASTRAL_FLOW_ABILITY = 0x1E    -- Astral Flow ability ID (30) -- SMN 2hr
local SPIRIT_SURGE_ABILITY = 0x1D   -- Spirit Surge ability ID (29) -- DRG 2hr
local OVERDRIVE_ABILITY    = 0x87   -- Overdrive ability ID (135) -- PUP 2hr

-- 0x0028 cmd_no values. The automaton's abilities always arrive as MobSkillFinish, never as
-- AbilityFinish. The magic gate is stamped on the START, which is when the server stamps its own.
local CMD_MAGIC_START      = 8
local CMD_MOB_SKILL_FINISH = 11

-- Low half of a cast's four-character code. An interrupted cast is re-sent under MagicStart
-- carrying the same spell id, so only the FourCC separates it from a real cast: every cast code
-- ends "ca", every interrupt "sp".
local FOURCC_CAST_INTERRUPT = 0x7073

-- BST pet command ability IDs (in 0x0028 action packet)
local STAY_ABILITY  = 0x49   -- Stay  (73)
local HEEL_ABILITY  = 0x46   -- Heel  (70)
local LEAVE_ABILITY = 0x47   -- Leave (71)

-- Jug pet summon abilities: these own the start of the jug countdown.
local CALL_BEAST_ABILITY      = 0x55    -- Call Beast      (85)
local BESTIAL_LOYALTY_ABILITY = 0x183   -- Bestial Loyalty (387)

-- Stat index constants
local CHR_STAT_INDEX = 6     -- CHR stat index in GetStat()

-- 2-hour effect durations (seconds)
local FAMILIAR_DURATION = 1800   -- 30 minutes (matches HorizonXI server)
local AF_DURATION       = 180    -- 3 minutes (matches HorizonXI server)
local SS_DURATION       = 60     -- 1 minute (matches HorizonXI server)
local OD_DURATION       = 60     -- 1 minute (matches HorizonXI server)


-- Charm check state machine (nil, 'sending', 'waiting')
local charmCheckState       = nil
local pendingCharmTarget    = nil   -- target server ID from outgoing Charm action
local pendingCharmTargetIdx = nil   -- target entity index from outgoing Charm action


-- Calculates charm duration in seconds using the LSB server formula.
-- Source: LSB-server/scripts/globals/job_utils/beastmaster.lua
-- Quintic polynomial fitted to BG wiki table (R^2 > 0.999).
-- @param mobLevel   target mob's main level
-- @param chr        charmer's CHR stat
-- @param playerLvl  charmer's main job level
-- @param gearMod    sum of CHARM_TIME bonus from equipped gear
-- @return floor(duration in seconds)
function packets._calcCharmDuration(mobLevel, chr, playerLvl, gearMod)
    local base = math.floor(1.25 * chr + 150)
    local dLvl = playerLvl - mobLevel

    -- Mirrors LSB beastmaster.lua exactly:
    --   dLvl < -6      -> minimum cap (1/24)
    --   -6 <= dLvl < 9 -> quintic polynomial
    --   dLvl >= 9      -> maximum cap (6)
    local mult
    if dLvl < -6 then
        mult = 1 / 24
    elseif dLvl >= 9 then
        mult = 6
    else
        local x = dLvl
        mult = 0.9997336
            + 0.3652882      * x
            + 0.02097742     * x^2
            - 0.004106429    * x^3
            + 0.000007231037 * x^4
            + 0.00005102634  * x^5
    end

    local duration = base * mult * (1 + 0.05 * (gearMod or 0))
    return math.floor(duration)
end

-- Called for every outgoing packet. Handles charm /check interception.
-- @param e      Ashita packet_out event
-- @param State  the shared state table
function packets.handlePacketOut(e, State)
    if not e or not e.id then return end

    -- Detect Charm job ability being used
    if e.id == packets.ID.ACTION_OUT then
        local data = e.data
        if not data or #data < 16 then return end

        local category, abilityId, target, targetIdx
        local ok = pcall(function()
            target    = struct.unpack('I', data, 0x04 + 1)
            targetIdx = struct.unpack('H', data, 0x08 + 1)
            category  = struct.unpack('H', data, 0x0A + 1)
            abilityId = struct.unpack('H', data, 0x0C + 1)
        end)
        if not ok then return end

        if category == JA_CATEGORY then
            -- Charm: JA category 9, ability 0x34; only trigger when no pet is active
            if abilityId == CHARM_ABILITY and not State.active then
                pendingCharmTarget    = target
                pendingCharmTargetIdx = targetIdx
                charmCheckState       = 'sending'
                AshitaCore:GetChatManager():QueueCommand(1, '/check')
            end
            -- Familiar and Astral Flow are confirmed via the incoming 0x0028 action packet
            -- to avoid starting the timer when the server rejects the ability.
        end
        return
    end

    -- Intercept /check and redirect it to the charm target
    if e.id == packets.ID.CHECK_OUT then
        if charmCheckState ~= 'sending' then return end

        local data = e.data
        if not data then return end

        -- Substitute charm target into the /check packet.
        -- Packet layout (0-based offsets, 1-indexed in struct):
        --   bytes 0-3: header (unchanged)
        --   uint32 at offset 4: target server ID (UniqueNo)
        --   uint32 at offset 8: target entity index (ActIndex) -- full 32-bit field in this packet,
        --                       unlike 0x001A where ActIndex is only 16 bits
        --   remaining bytes: unchanged
        local pkt = data:totable()
        local ok = pcall(function()
            pkt[5] = bit.band(pendingCharmTarget,    0xFF)
            pkt[6] = bit.band(bit.rshift(pendingCharmTarget,    8), 0xFF)
            pkt[7] = bit.band(bit.rshift(pendingCharmTarget,    16), 0xFF)
            pkt[8] = bit.band(bit.rshift(pendingCharmTarget,    24), 0xFF)
            pkt[9] = bit.band(pendingCharmTargetIdx, 0xFF)
            pkt[10]= bit.band(bit.rshift(pendingCharmTargetIdx, 8), 0xFF)
            pkt[11]= 0
            pkt[12]= 0
        end)
        if ok then
            e.data_modified = pkt
        end
        charmCheckState = 'waiting'
        return
    end
end

-- Called for every incoming packet. Updates State as appropriate.
-- @param e       Ashita packet event (contains .id, .data_modified_shifted, etc.)
-- @param State   the shared state table
-- @param activeModule  the currently active type module (may be nil)
function packets.handlePacketIn(e, State, activeModule)
    if not e or not e.id then return end

    if e.id == packets.ID.ZONE_IN then
        -- Zone transition: clear pet state to avoid stale display
        State.reset()
        -- Maneuver burden and the Overload countdown survive the zone, the same way the jug
        -- clock does. Zoning marks the automaton Status::Disappear but the server keeps the
        -- entity and its burden array (zone_entities.cpp:519), so clearing here under-reports.
        -- Both live inside State.automaton.burdenModel, which State.reset() does not touch --
        -- only a confirmed Activate reseeds them.
        -- Forward to active module for cleanup
        if activeModule and activeModule.onPacket then
            activeModule.onPacket(e)
        end
        return
    end

    -- Pet sync: the pet's target, straight from the server. Entity memory's GetTargetedIndex
    -- is documented "not always populated" and reads 0 for pets in practice -- see data.lua's
    -- target block.
    if e.id == packets.ID.PET_SYNC or e.id == packets.ID.ENTITY_SYNC then
        local parsed = packets._parsePetSync(e.data)
        if parsed then
            State.target.pktServerId = parsed.targetServerId
        end
        return
    end

    -- Extended job data: the only source of the automaton's HP/MP figures and pool sizes.
    -- The memory manager exposes percentages only, and GetPetMPPercent reports 0 for a frame
    -- with no pool and for a drained caster alike.
    if e.id == packets.ID.EXT_JOB then
        local parsed = packets._parseExtJobPup(e.data)
        if parsed then
            local a = State.automaton
            a.hp    = parsed.hp
            a.maxHp = parsed.maxHp
            a.mp    = parsed.mp
            a.maxMp = parsed.maxMp
            -- Sets the burden decay rate. Re-sent whenever the automaton's updatemask
            -- changes, so an attachment swap lands without a reload.
            a.heatsink = parsed.heatsink
            -- Head, frame and attachments are the only source for the internal cooldown rows:
            -- nothing in client memory exposes what the automaton is wearing.
            automatonIcd.setEquipment(parsed.head, parsed.frame, parsed.attachments)
        end
        return
    end

    -- Check response: extract mob level and calculate charm duration
    if e.id == packets.ID.CHECK_IN then
        if charmCheckState ~= 'waiting' then return end
        charmCheckState = nil   -- consume regardless of validity

        local data = e.data
        if not data or #data < 28 then return end

        local param1, param2, msg
        local ok = pcall(function()
            param1 = struct.unpack('l', data, 0x0C + 1)   -- signed int32: mob level
            param2 = struct.unpack('L', data, 0x10 + 1)   -- uint32: level range flag
            msg    = struct.unpack('H', data, 0x18 + 1)   -- uint16: message type
        end)
        if not ok then return end

        -- Validate this is a real level-check response (filters out non-combat checks)
        -- msg 0xAA-0xB2: "Target's level is X" messages
        -- param2 0x40-0x47: level range indicators
        local valid = (msg >= 0xAA and msg <= 0xB2) or (param2 >= 0x40 and param2 <= 0x47)
        if not valid then return end

        local memMgr = AshitaCore and AshitaCore:GetMemoryManager()
        if not memMgr then return end
        local player = memMgr:GetPlayer()
        if not player then return end

        local chr     = player:GetStat(CHR_STAT_INDEX)
        local plvl    = player:GetMainJobLevel()
        local gearMod = dataLib.getCharmGearBonus()
        local duration = packets._calcCharmDuration(param1, chr, plvl, gearMod)

        State.charm.mobLevel      = param1
        State.charm.expireTime    = os.time() + duration
        State.charm.totalDuration = duration
        State.charm.known         = true
        return
    end

    if e.id == packets.ID.ACTION then
        local data = e.data
        if not data then return end

        -- Parse action for actor ID (needed for BST command / 2hr tracking below)
        local parsed = packets._parseAction(data)

        -- The automaton's own actions drive its internal cooldowns.
        if parsed and parsed.actorId ~= 0 and State.petType == 'automaton'
            and State.active and parsed.actorId == State.serverId then
            local petAction = packets._parseAutomatonAction(data)
            if petAction ~= nil then
                if petAction.kind == 'cast' then
                    automatonIcd.onCast(petAction.id, socket.gettime())
                else
                    automatonIcd.onMobSkill(petAction.id, socket.gettime())
                end
            end
        end

        -- BST pet commands: only trigger when server confirms the ability fired
        -- Extract cmd_no and abilityId from 0x0028 bitstream (layout per XiPackets/0x0028/Reversing.md):
        --   Bitstream starts at byte 0x09 (after 32-bit actor ID at 0x05):
        --     bits 0-5:  trg_sum  (6 bits)
        --     bits 6-9:  res_sum  (4 bits)
        --     bits 10-13: cmd_no  (4 bits) <- 6 = Ability Finish
        --     bits 14-45: cmd_arg (32 bits) <- ability ID for cmd_no 6
        --   Reading uint16 at 0x0A covers stream bits 8-23:
        --     bits 0-1 of uint16 = res_sum bits 2-3
        --     bits 2-5 of uint16 = cmd_no  -> rshift(w,2) & 0xF
        --     bits 6-15 of uint16 = cmd_arg bits 0-9 -> rshift(w,6)
        if parsed and parsed.actorId ~= 0 then
            local memMgr = AshitaCore and AshitaCore:GetMemoryManager()
            local party  = memMgr and memMgr:GetParty()
            local playerServerId = party and party:GetMemberServerId(0) or 0
            if playerServerId ~= 0 and parsed.actorId == playerServerId then
                local cmdParsed = packets._parseActionCommand(data)
                local cmdNo     = cmdParsed and cmdParsed.cmdNo
                local abilityId = cmdParsed and cmdParsed.abilityId
                -- Only check ability IDs for Ability Finish (cmd_no 6).
                -- Without this guard, spells (cmd_no 4/8) can produce false matches
                -- against JA ability IDs via their spell IDs sharing the same lower bits.
                if abilityId and cmdNo == 6 then
                    if abilityId == STAY_ABILITY then
                        if State.bst.stayExpiry == nil then
                            State.bst.stayExpiry = socket.gettime() + 20
                        end
                    elseif abilityId == HEEL_ABILITY then
                        State.bst.stayExpiry = nil

                    elseif abilityId == LEAVE_ABILITY then
                        -- Leave dismisses the pet outright, so the jug countdown ends with it.
                        -- (Heel only recalls the pet -- the clock keeps running there.)
                        State.bst.stayExpiry  = nil
                        State.jug.expireTime  = nil
                        State.jug.remaining   = 0
                        State.jug.duration    = 0
                        State.jug.pendingCall = false

                    elseif abilityId == CALL_BEAST_ABILITY or abilityId == BESTIAL_LOYALTY_ABILITY then
                        -- A confirmed summon is the only thing that starts a jug clock, so a
                        -- stale clock left by an unobserved release -- player KO, job change,
                        -- pet dying out of sight -- is overwritten, not inherited by the new pet.
                        State.jug.pendingCall = true

                    elseif abilityId == FAMILIAR_ABILITY then  -- Familiar (BST 2hr): server confirmed
                        State.familiar.expireTime = os.time() + FAMILIAR_DURATION
                        State.familiar.remaining  = FAMILIAR_DURATION
                        State.familiar.elapsed    = 0

                    elseif abilityId == ASTRAL_FLOW_ABILITY then  -- Astral Flow (SMN 2hr): server confirmed
                        State.avatar.afExpireTime = os.time() + AF_DURATION
                        State.avatar.afRemaining  = AF_DURATION

                    elseif abilityId == SPIRIT_SURGE_ABILITY then  -- Spirit Surge (DRG 2hr): server confirmed
                        State.wyvern.ssExpireTime = os.time() + SS_DURATION
                        State.wyvern.ssRemaining  = SS_DURATION

                    elseif abilityId == OVERDRIVE_ABILITY then  -- Overdrive (PUP 2hr): server confirmed
                        State.automaton.odExpireTime = os.time() + OD_DURATION
                        State.automaton.odRemaining  = OD_DURATION
                    end

                    -- The new automaton's internal cooldowns all start clear, so the old
                    -- one's stamps must not outlive it.
                    if abilityId == maneuvers.ACTIVATE_ABILITY or abilityId == maneuvers.DEA_ABILITY then
                        automatonIcd.onSummonConfirmed()
                    end

                    -- PUP maneuver burden. The server volunteers the exact overload chance
                    -- in the action result, so nothing here computes one.
                    -- Dot calls only: a colon passes the model itself as `index`, which
                    -- reads back nil and renders every percentage 0 forever, with no error.
                    local burdenModel = State.automaton and State.automaton.burdenModel
                    if burdenModel then
                        local element = maneuvers.byAbilityId[abilityId]
                        if element then
                            local result = packets._parseActionResult(data)
                            -- Cross-check the bitstream reader against the uint16 shortcut:
                            -- wrong offsets yield plausible garbage rather than an error, so
                            -- every percentage would render as a meaningless number.
                            -- The shortcut's abilityId is only the low 10 bits of cmd_arg and
                            -- must be masked. Both compared fields live in stream bits 10-23,
                            -- so this verifies alignment only through cmd_arg bit 9 -- not the
                            -- cmd_arg width above that, nor the target/result skips, which rest
                            -- on the field widths in _parseActionResult.
                            if result and (result.cmdNo ~= cmdNo
                                or bit.band(result.abilityId, 0x3FF) ~= abilityId) then
                                result = nil
                            end
                            local message = result and result.message
                            local now     = os.time()
                            if result and message == maneuvers.MSG_OVERLOADED then
                                burdenModel.stamp(element.index, result.param)
                                burdenModel.setOverload(result.param, now)
                            elseif result and message == maneuvers.MSG_OVERLOAD_CHANCE then
                                -- Taken at face value, Overdrive included. OVERLOAD_THRESH
                                -- +5000 clamps the reported chance to 0 for the whole of an
                                -- Overdrive while burden keeps climbing, so the column reads
                                -- clean through that window and re-anchors on the first
                                -- report after it drops.
                                burdenModel.stamp(element.index, result.param)
                            end
                        elseif abilityId == maneuvers.ACTIVATE_ABILITY then
                            -- A fresh automaton spawns with burden in every element, not at
                            -- 0, so the baseline is SPAWN_PCT. Overload is not cleared here:
                            -- the Overload buff is the authority and it outlives the
                            -- automaton, so data.lua reconciles it.
                            burdenModel.resetAll(burdenModel.SPAWN_PCT)
                        elseif abilityId == maneuvers.DEA_ABILITY then
                            -- Without this the model inherits the dead automaton's stamps and
                            -- every element reads 0 while sitting one maneuver away from a
                            -- near-certain Overload.
                            burdenModel.resetAll(burdenModel.DEA_SPAWN_PCT)
                        end
                    end
                end
            end
        end

        -- Forward to active module
        if activeModule and activeModule.onPacket then
            activeModule.onPacket(e)
        end
        return
    end

end

-- Pure parse: extracts actor server ID from 0x0028 action packet.
-- Returns {actorId} or nil.
function packets._parseAction(data)
    if not data or #data < 16 then return nil end

    local actorId = nil
    local ok = pcall(function()
        actorId = struct.unpack('I', data, 0x05 + 1)
    end)
    if not ok or not actorId then return nil end

    return { actorId = actorId }
end

-- Pure parse: extracts the pet's target server id from a 0x0067/0x0068 mode 4 packet.
-- Layout per XiPackets/world/server/0x0067/README.md, "Mode: 4":
--   0x04 uint16  Mode(6) / Length(10)
--   0x06 uint16  ActIndex
--   0x08 uint32  UniqueNo
--   0x0C uint16  ActIndexOwner
--   0x0E uint8   Hpp
--   0x0F uint8   Mpp
--   0x10 uint32  Tp
--   0x14 uint32  UniqueNoTarget   <- the only field read here
--
-- LSB fills ActIndex/UniqueNo with the OWNER and ActIndexOwner with the pet, the reverse of
-- the README's naming (pet_sync.cpp:41-48), so none of the identity fields can be used to
-- validate the packet -- mode 4 is by definition the local client's own pet.
--
-- targetServerId is 0 whenever the server did not report a target: LSB only writes 0x14
-- while the pet's animation is Attack (pet_sync.cpp:52-55), so a disengage clears it rather
-- than leaving it stale. Returns { targetServerId } or nil for a short or wrong-mode packet.
function packets._parsePetSync(data)
    if not data or #data < PET_SYNC_MIN_BYTES then return nil end

    local mode, targetServerId
    local ok = pcall(function()
        mode = bit.band(data:byte(0x04 + 1), 0x3F)
        targetServerId = struct.unpack('I', data, 0x14 + 1)
    end)
    if not ok or mode ~= PET_SYNC_MODE_PET or not targetServerId then return nil end

    return { targetServerId = targetServerId }
end

-- Pure parse: extracts the automaton's equipment and vitals from a 0x0044 packet. See the
-- EXT_JOB_PUP comment above for the field offsets. Returns
-- { head, frame, attachments, hp, maxHp, mp, maxMp, heatsink } or nil.
--
-- head and frame are the raw bytes, which are itemId - 0x2000; nil means the slot is empty.
-- attachments is a 12-entry array of raw bytes, itemId - 0x2100, 0 for an empty slot.
--
-- MaxMP is 0 for the whole life of a Valoredge or Sharpshot frame: those frame stat tables
-- grant no pool at any level, and Mana Tank only boosts a pool that already exists. MaxHP
-- gates the read because the server fills both from the same struct -- a 0 there means the
-- automaton stats have not loaded and a 0 MaxMP proves nothing.
--
-- HP reads as MaxHP for a dead automaton, not 0 (0x044_extended_job_pup.cpp:56), and as MaxHP
-- with no automaton out at all. Both are caught downstream by the cross-check against the
-- live entity percent in state.lua.
function packets._parseExtJobPup(data)
    if not data or #data < EXT_JOB_MIN_BYTES then return nil end

    local job, head, frame, hp, maxHp, mp, maxMp
    local attachments = {}
    local heatsink = false
    local ok = pcall(function()
        job   = data:byte(0x04 + 1)
        head  = data:byte(0x08 + 1)
        frame = data:byte(0x09 + 1)
        for slot = 1, 12 do
            local value = data:byte(0x0A + (slot - 1) + 1)
            attachments[slot] = value
            if value == maneuvers.HEATSINK_ATTACHMENT_ID then
                heatsink = true
            end
        end
        hp    = struct.unpack('H', data, 0x68 + 1)
        maxHp = struct.unpack('H', data, 0x6A + 1)
        mp    = struct.unpack('H', data, 0x6C + 1)
        maxMp = struct.unpack('H', data, 0x6E + 1)
    end)
    if not ok or job ~= EXT_JOB_PUP then return nil end
    if not maxHp or maxHp == 0 or not maxMp then return nil end

    return {
        hp = hp, maxHp = maxHp, mp = mp, maxMp = maxMp, heatsink = heatsink,
        head        = head ~= 0 and head or nil,
        frame       = frame ~= 0 and frame or nil,
        attachments = attachments,
    }
end

-- Pure parse: classifies one of the automaton's 0x0028 actions as the thing that advances an
-- internal cooldown. Returns { kind = 'cast' | 'mobSkill', id } or nil for anything else --
-- melee rounds, interrupted casts, and every other category.
--
-- Both ids come from the full bitstream reader. _parseActionCommand's uint16 shortcut is used
-- only to skip the melee rounds cheaply: it caps cmd_arg at 1023, which cannot express
-- Flashbulb 1947, Barrage Turbine 2746 or Regulator 3485.
--
-- Trap: cmd_arg holds an id only on the FINISH categories. A cast START carries the spell's
-- FourCC there and the real spell id in result[0].param, and a FourCC read as an id looks like
-- a plausible large number rather than an error.
function packets._parseAutomatonAction(data)
    local command = packets._parseActionCommand(data)
    local cmdNo   = command and command.cmdNo
    if cmdNo ~= CMD_MAGIC_START and cmdNo ~= CMD_MOB_SKILL_FINISH then return nil end

    local action = packets._parseActionResult(data)
    if not action then return nil end

    if action.cmdNo == CMD_MOB_SKILL_FINISH then
        return { kind = 'mobSkill', id = action.abilityId }
    end

    if bit.band(action.abilityId, 0xFFFF) == FOURCC_CAST_INTERRUPT then return nil end
    return { kind = 'cast', id = action.param }
end

-- Pure parse: extracts cmd_no and abilityId from the 0x0028 action packet's
-- bitstream (layout per XiPackets/0x0028/Reversing.md). See handlePacketIn's
-- ACTION branch for the bitstream field breakdown.
-- Returns { cmdNo, abilityId } or nil.
function packets._parseActionCommand(data)
    if not data or #data < 12 then return nil end

    local cmdNo, abilityId
    local ok = pcall(function()
        local w = struct.unpack('H', data, 0x0A + 1)
        cmdNo     = bit.band(bit.rshift(w, 2), 0xF)
        abilityId = bit.rshift(w, 6)
    end)
    if not ok then return nil end

    return { cmdNo = cmdNo, abilityId = abilityId }
end

-- The 0x0028 packed fields begin at byte 0x09: the client hands CXiSchStatus::Unpack the
-- buffer at +4, steps one more byte over an ignored size field, then reads the 32-bit
-- actor id from 0x05-0x08 (XiPackets/world/server/0x0028/Reversing.md).
local ACTION_BITSTREAM_START = 0x09 * 8

-- Reaching the end of result[0].message costs 168 bits from 0x09 (78 header + 36 for
-- target[0] + 54 for result[0]), so the last byte touched is 0x1D.
local ACTION_RESULT_MIN_BYTES = 30

-- Reads `count` bits at absolute bit offset `bitPos` (bit 0 = the low bit of packet byte 0),
-- returning the value and the next bit offset, or nil past the end of the buffer.
--
-- Bits are little-endian within each byte and run on across byte boundaries: the client's
-- FUNC_Bits_Unpack takes the low bit first and shifts the byte right. An MSB-first reader
-- produces plausible garbage here rather than an error. The value accumulates arithmetically
-- because a 32-bit field with its top bit set comes back negative from LuaJIT's bit library.
local function readBits(data, bitPos, count)
    local value = 0
    local scale = 1
    for i = 0, count - 1 do
        local absolute = bitPos + i
        local byte = data:byte(math.floor(absolute / 8) + 1)
        if byte == nil then return nil end
        value = value + bit.band(bit.rshift(byte, absolute % 8), 1) * scale
        scale = scale * 2
    end
    return value, bitPos + count
end

-- Pure parse: unpacks the 0x0028 bitstream through target[0].result[0], which is where the
-- result message and its value live. _parseActionCommand's uint16 shortcut cannot reach
-- either -- it only covers cmd_no and the low 10 bits of cmd_arg.
--
-- Field order per XiPackets/world/server/0x0028/Reversing.md:
--   header:    trg_sum(6) res_sum(4) cmd_no(4) cmd_arg(32) info(32)
--   target[0]: m_uID(32) result_sum(4)
--   result[0]: miss(3) kind(2) sub_kind(12) info(5) scale(5) value(17) message(10)
--
-- `param` is result.value (LSB-server/src/map/action/action.h:55 -- "result.value - 17 bits").
-- `message` is 10 bits, max 1023, which is why message ids 798/799 fit.
-- Returns { cmdNo, abilityId, trgSum, resultSum, message, param } or nil.
function packets._parseActionResult(data)
    if not data or #data < ACTION_RESULT_MIN_BYTES then return nil end

    local trgSum, cmdNo, abilityId, resultSum, message, param
    local ok = pcall(function()
        local pos = ACTION_BITSTREAM_START
        trgSum, pos    = readBits(data, pos, 6)
        pos            = pos + 4                 -- res_sum
        cmdNo, pos     = readBits(data, pos, 4)
        abilityId, pos = readBits(data, pos, 32) -- cmd_arg
        pos            = pos + 32                -- info
        pos            = pos + 32                -- target[0].m_uID
        resultSum, pos = readBits(data, pos, 4)
        pos            = pos + 27                -- result[0]: miss(3) kind(2) sub_kind(12) info(5) scale(5)
        param, pos     = readBits(data, pos, 17) -- result[0].value
        message        = readBits(data, pos, 10)
    end)
    if not ok then return nil end
    if not trgSum or trgSum == 0 then return nil end
    if not resultSum or resultSum == 0 then return nil end
    if not message or not param then return nil end

    return {
        cmdNo     = cmdNo,
        abilityId = abilityId,
        trgSum    = trgSum,
        resultSum = resultSum,
        message   = message,
        param     = param,
    }
end

return packets
