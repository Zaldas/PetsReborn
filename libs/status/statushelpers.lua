--[[
* Copyright (c) 2023 tirem [github.com/tirem] under the GPL-3.0 license
* Modified 2026 by Zaldas for PetsReborn.
]]--

require('common');
local tables = require('libs/status/statustable');

local statusHelper = T{};

-- Get if we are logged in right when the library is accessed
statusHelper.bLoggedIn = false;
local playerIndex = AshitaCore:GetMemoryManager():GetParty():GetMemberTargetIndex(0);
if playerIndex ~= 0 then
    local entity = AshitaCore:GetMemoryManager():GetEntity();
    local flags = entity:GetRenderFlags0(playerIndex);
    if (bit.band(flags, 0x200) == 0x200) and (bit.band(flags, 0x4000) == 0) then
        statusHelper.bLoggedIn = true;
	end
end

--Thanks to Velyn for the event system and interface hidden signatures!
local pGameMenu = ashita.memory.find('FFXiMain.dll', 0, "8B480C85C974??8B510885D274??3B05", 16, 0);
local pEventSystem = ashita.memory.find('FFXiMain.dll', 0, "A0????????84C0741AA1????????85C0741166A1????????663B05????????0F94C0C3", 0, 0);
local pInterfaceHidden = ashita.memory.find('FFXiMain.dll', 0, "8B4424046A016A0050B9????????E8????????F6D81BC040C3", 0, 0);

statusHelper.GetMenuName = function()
    if pGameMenu == 0 then return ''; end
    local subPointer = ashita.memory.read_uint32(pGameMenu);
    local subValue = ashita.memory.read_uint32(subPointer);
    if (subValue == 0) then
        return '';
    end
    local menuHeader = ashita.memory.read_uint32(subValue + 4);
    local menuName = ashita.memory.read_string(menuHeader + 0x46, 16);
    return string.gsub(tostring(menuName), '\x00', '');
end

statusHelper.GetEventSystemActive = function()
    if (pEventSystem == 0) then
        return false;
    end
    local ptr = ashita.memory.read_uint32(pEventSystem + 1);
    if (ptr == 0) then
        return false;
    end

    return (ashita.memory.read_uint8(ptr) == 1);

end

statusHelper.GetInterfaceHidden = function()
    if (pInterfaceHidden == 0) then
        return false;
    end
    local ptr = ashita.memory.read_uint32(pInterfaceHidden + 10);
    if (ptr == 0) then
        return false;
    end

    return (ashita.memory.read_uint8(ptr + 0xB4) == 1);
end


statusHelper.GetGameInterfaceHidden = function()

	if (statusHelper.GetEventSystemActive()) then
		return true;
	end
	if (string.match(statusHelper.GetMenuName(), 'map')) then
		return true;
	end
    if (statusHelper.GetInterfaceHidden()) then
        return true;
    end
	if (statusHelper.bLoggedIn == false) then
		return true;
	end
    return false;
end

statusHelper.GetStPartyIndex = function()
    local ptr = AshitaCore:GetPointerManager():Get('party');
    if not ptr or ptr == 0 then return nil end
    ptr = ashita.memory.read_uint32(ptr);
    if ptr == 0 then return nil end
    ptr = ashita.memory.read_uint32(ptr);
    if ptr == 0 then return nil end
    local isActive = (ashita.memory.read_uint32(ptr + 0x54) ~= 0);
    if isActive then
        return ashita.memory.read_uint8(ptr + 0x50);
    else
        return nil;
    end
end

statusHelper.GetTargets = function()
    local playerTarget = AshitaCore:GetMemoryManager():GetTarget();
    local party = AshitaCore:GetMemoryManager():GetParty();

    if (playerTarget == nil or party == nil) then
        return nil, nil;
    end

    local mainTarget = playerTarget:GetTargetIndex(0);
    local secondaryTarget = playerTarget:GetTargetIndex(1);
    local partyTarget = statusHelper.GetStPartyIndex();

    if (partyTarget ~= nil) then
        secondaryTarget = mainTarget;
        mainTarget = party:GetMemberTargetIndex(partyTarget);
    end

    return mainTarget, secondaryTarget;
end

-- Party member ID cache — rebuilt on zone (0x00A) or party update (0x076) packets.
-- Avoids allocating a new T{} on every GetPartyMemberIds() call (called per-0x028 packet).
local _partyIdsCache = nil;
local _partyIdsDirty = true;

local function _rebuildPartyIds()
    _partyIdsCache = T{};
    local party = AshitaCore:GetMemoryManager():GetParty();
    for i = 0, 5 do
        if (party:GetMemberIsActive(i) == 1) then
            table.insert(_partyIdsCache, party:GetMemberServerId(i));
        end
    end
    _partyIdsDirty = false;
end

statusHelper.GetPartyMemberIds = function()
    if _partyIdsDirty or _partyIdsCache == nil then
        _rebuildPartyIds();
    end
    return _partyIdsCache;
end

statusHelper.InvalidatePartyIds = function()
    _partyIdsDirty = true;
end

statusHelper.GetIsMob = function(index)
	return (bit.band(AshitaCore:GetMemoryManager():GetEntity():GetSpawnFlags(index), 0x10) ~= 0);
end

-- Admits automatons, avatars, jug pets and trusts.  Charmed BST pets are excluded: a charmed
-- mob keeps the Monster flag.
statusHelper.GetIsPartyPet = function(index)
	return (bit.band(AshitaCore:GetMemoryManager():GetEntity():GetSpawnFlags(index), 0x110) == 0x100);
end

statusHelper.GetIsValidMob = function(mobIdx)
    local renderflags = AshitaCore:GetMemoryManager():GetEntity():GetRenderFlags0(mobIdx);
    if bit.band(renderflags, 0x200) ~= 0x200 or bit.band(renderflags, 0x4000) ~= 0 then
        return false;
    end
	return true;
end

statusHelper.GetIndexFromId = function(id)
    local entMgr = AshitaCore:GetMemoryManager():GetEntity();

    --Shortcut for monsters/static npcs..
    if (bit.band(id, 0x1000000) ~= 0) then
        local index = bit.band(id, 0xFFF);
        if (index >= 0x900) then
            index = index - 0x100;
        end

        if (index < 0x900) and (entMgr:GetServerId(index) == id) then
            return index;
        end
    end

    for i = 1,0x8FF do
        if entMgr:GetServerId(i) == id then
            return i;
        end
    end

    return 0;
end

statusHelper.ParseActionPacket = function(e)
    local bitData;
    local bitOffset;
    local maxLength = e.size * 8;
    local function UnpackBits(length)
        if ((bitOffset + length) > maxLength) then
            maxLength = 0; --Using this as a flag since any malformed fields mean the data is trash anyway.
            return 0;
        end
        local value = ashita.bits.unpack_be(bitData, 0, bitOffset, length);
        bitOffset = bitOffset + length;
        return value;
    end

    local actionPacket = T{};
    bitData = e.data_raw;
    bitOffset = 40;
    actionPacket.UserId = UnpackBits(32);
    actionPacket.UserIndex = statusHelper.GetIndexFromId(actionPacket.UserId); --Many implementations of this exist, or you can comment it out if not needed.  It can be costly.
    local targetCount = UnpackBits(6);
    --Unknown 4 bits
    bitOffset = bitOffset + 4;
    actionPacket.Type = UnpackBits(4);
    if actionPacket.Type == 8 or actionPacket.Type == 9 then
        actionPacket.Param = UnpackBits(16);
        actionPacket.SpellGroup = UnpackBits(16);
    else
        -- Not every action packet has the same data at the same offsets so we just skip this for now
        actionPacket.Param = UnpackBits(32);
    end

    actionPacket.Recast = UnpackBits(32);

    actionPacket.Targets = T{};
    if (targetCount > 0) then
        for _ = 1,targetCount do
            local target = T{};
            target.Id = UnpackBits(32);
            local actionCount = UnpackBits(4);
            target.Actions = T{};
            if (actionCount == 0) then
                goto continue_target;
            end
            for _ = 1,actionCount do
                local action = {};
                action.Reaction = UnpackBits(5);
                action.Animation = UnpackBits(12);
                action.SpecialEffect = UnpackBits(7);
                action.Knockback = UnpackBits(3);
                action.Param = UnpackBits(17);
                action.Message = UnpackBits(10);
                action.Flags = UnpackBits(31);

                local hasAdditionalEffect = (UnpackBits(1) == 1);
                if hasAdditionalEffect then
                    local additionalEffect = {};
                    additionalEffect.Damage = UnpackBits(10);
                    additionalEffect.Param = UnpackBits(17);
                    additionalEffect.Message = UnpackBits(10);
                    action.AdditionalEffect = additionalEffect;
                end

                local hasSpikesEffect = (UnpackBits(1) == 1);
                if hasSpikesEffect then
                    local spikesEffect = {};
                    spikesEffect.Damage = UnpackBits(10);
                    spikesEffect.Param = UnpackBits(14);
                    spikesEffect.Message = UnpackBits(10);
                    action.SpikesEffect = spikesEffect;
                end

                target.Actions:append(action);
            end
            actionPacket.Targets:append(target);
            ::continue_target::
        end
    end

    if  (maxLength ~= 0) and (#actionPacket.Targets > 0) then
        return actionPacket;
    end
end

statusHelper.ParseMobUpdatePacket = function(e)
	if (e.id == 0x00E) then
		local mobPacket = T{};
		mobPacket.monsterId = struct.unpack('L', e.data, 0x04 + 1);
		mobPacket.monsterIndex = struct.unpack('H', e.data, 0x08 + 1);
		mobPacket.updateFlags = struct.unpack('B', e.data, 0x0A + 1);
		if (bit.band(mobPacket.updateFlags, 0x02) == 0x02) then
			mobPacket.newClaimId = struct.unpack('L', e.data, 0x2C + 1);
		end
		return mobPacket;
	end
end

statusHelper.ParseMessagePacket = function(e)
    local basic = {
        sender     = struct.unpack('i4', e, 0x04 + 1),
        target     = struct.unpack('i4', e, 0x08 + 1),
        param      = struct.unpack('i4', e, 0x0C + 1),
        value      = struct.unpack('i4', e, 0x10 + 1),
        sender_tgt = struct.unpack('i2', e, 0x14 + 1),
        target_tgt = struct.unpack('i2', e, 0x16 + 1),
        message    = struct.unpack('i2', e, 0x18 + 1),
    }
    return basic
end

-- Gets if a status effect is technically a positive status effect
statusHelper.GetIsBuff = function(StatusId)
    return tables.IsBuff(StatusId);
end

-- Gets if a job is a spellcaster (uses MP) by their job abberviation
statusHelper.GetIsSpellcaster = function(JobAbv)
    return tables.IsSpellcaster(JobAbv);
end

-- Gets if a pet is a job by by the pet name
statusHelper.GetIsJugPet = function(PetName)
    return tables.IsJugPet(PetName);
end

-- Get a jobs SP (1, 2 hr) ability name by its job abberviation
statusHelper.GetSpAbilityName = function(JobAbv)
    return tables.GetSPAbilityName(JobAbv);
end

-- Tears down this module's registered event handler. Call from the addon's unload event.
statusHelper.Dispose = function()
    ashita.events.unregister('packet_in', '__statushelpers_packet_in_cb');
end

-- The usual packet event doesn't register in libs but this __settings one does. Feels bad.
ashita.events.register('packet_in', '__statushelpers_packet_in_cb', function (e)

    -- Track our logged in status
    if (e.id == 0x00A) then
        statusHelper.bLoggedIn = true;
        _partyIdsDirty = true;  -- party composition may change on zone
    elseif (e.id == 0x00B) then
        statusHelper.bLoggedIn = false;
    elseif (e.id == 0x076) then
        _partyIdsDirty = true;  -- party update packet: membership or IDs may have changed
    end
end);

return statusHelper;