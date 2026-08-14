
--[[
* Copyright (c) 2023 tirem [github.com/tirem] under the GPL-3.0 license
* Modified 2026 by Zaldas for PetsReborn.
]]--

require('common');

local icons = require('libs/status/statusicons');
local tracker = require('libs/status/statustracker');

local status = T{};

status.helpers = require('libs/status/statushelpers');

status.GetStatusIdsById = function(ServerId)
    return tracker.GetStatusEffects(ServerId);
end

-- Returns {[buffId] = expiryTime} for mobs, nil for player/party (no expiry data).
status.GetStatusTimesById = function(ServerId)
    return tracker.GetStatusTimes(ServerId);
end

status.GetStatusIdsByIndex = function(TargetIndex)
    return status.GetStatusIdsById(AshitaCore:GetMemoryManager():GetEntity():GetServerId(TargetIndex));
end

status.GetStatusIdsByEntity = function(Entity)
    return status.GetStatusIdsById(Entity.GetServerId());
end

status.GetStatusInfoById = function(ServerId, IconTheme)

    local allIds = status.GetStatusIdsById(ServerId);
    if (allIds == nil) then
        return nil; -- No status effects for this enemy
    end
    
    local statusInfo = T{};
    for i = 1,#allIds do
        statusInfo[i] = T{};
        statusInfo[i].id = allIds[i];
        statusInfo[i].icon = status.GetIconForStatusId(allIds[i], IconTheme);
        statusInfo[i].tooltip = status.GetTooptipForStatusId(allIds[i]);
    end
    return statusInfo;
end

status.GetStatusInfoByIndex = function(TargetIndex, Theme)
    return status.GetStatusInfoById(AshitaCore:GetMemoryManager():GetEntity():GetServerId(TargetIndex), Theme);
end

status.GetStatusInfoByEntity = function(Entity, Theme)
    return status.GetStatusInfoById(Entity.GetServerId(), Theme);
end

status.GetIconForStatusId = function(StatusId, Theme)
    if (Theme == nil) then
        return icons.get_icon_image(StatusId);
    else
        return icons.get_icon_from_theme(StatusId, Theme);
    end
end

status.GetTooptipForStatusId = function(StatusId)
    if (StatusId == nil or StatusId < 1 or StatusId > 0x3FF or StatusId == 255) then
        return;
    end

    local resMan = AshitaCore:GetResourceManager();
    local info = resMan:GetStatusIconByIndex(StatusId);
    local name = resMan:GetString('buffs.names', StatusId);
    local returnTable = T{ name = nil; description = nil;};
    if (name ~= nil and info ~= nil) then
        returnTable.name = name;
        if (info.Description[1] ~= nil) then
            returnTable.description = info.Description[1];
        end
    end
    return returnTable;
end

status.GetRelevantEnemies = function()
    return tracker.GetRelevantTargets();
end

-- Initialize the status library. Must be called before any status tracking.
-- @param opts  { addonPath = string, addonName = string, enableAuditLog = bool }
status.init = function(opts)
    tracker.init(opts)
    icons.init(opts.addonPath)
end

status.SaveState = function()
    tracker.SaveState()
end

status.RestoreState = function()
    tracker.RestoreState()
end

status.GetIconFfi = function(StatusId)
    return icons.get_icon_ffi(StatusId)
end

status.clearTrackedEntity = function(serverId)
    tracker.clearEntity(serverId)
end

status.ClearIconCache = function()
    icons.clear_cache();
end

status.GetIconThemePaths = function()
    return icons.get_status_theme_paths();
end

-- Tears down this library's registered event handlers. Call from the addon's unload event.
status.Dispose = function()
    tracker.Dispose()
    status.helpers.Dispose()
end

return status;