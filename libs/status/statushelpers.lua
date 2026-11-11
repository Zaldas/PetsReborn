--[[
* Copyright (c) 2023 tirem [github.com/tirem] under the GPL-3.0 license
* Modified 2026 by Zaldas for PetsReborn.
]]--

require('common');

local statusHelper = T{};

statusHelper.GetIsMob = function(index)
    return (bit.band(AshitaCore:GetMemoryManager():GetEntity():GetSpawnFlags(index), 0x10) ~= 0);
end

-- Admits automatons, avatars, jug pets and trusts.  Charmed BST pets are excluded: a charmed
-- mob keeps the Monster flag.
statusHelper.GetIsPartyPet = function(index)
    return (bit.band(AshitaCore:GetMemoryManager():GetEntity():GetSpawnFlags(index), 0x110) == 0x100);
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
    -- UserIndex is not resolved here: GetIndexFromId can walk the whole entity array, so the
    -- caller resolves it from UserId only when needed.
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

return statusHelper;