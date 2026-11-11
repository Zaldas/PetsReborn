
--[[
* Copyright (c) 2023 tirem [github.com/tirem] under the GPL-3.0 license
* Modified 2026 by Zaldas for PetsReborn.
]]--

require('common');

local icons = require('libs/status/statusicons');
local tracker = require('libs/status/statustracker');

local status = T{};

status.GetStatusIdsById = function(ServerId)
    return tracker.GetStatusEffects(ServerId);
end

-- Returns {[buffId] = expiryTime} for the tracked entity, nil for the player (no expiry data).
status.GetStatusTimesById = function(ServerId)
    return tracker.GetStatusTimes(ServerId);
end

-- Real status ID behind a tier display ID (814+); other IDs pass through.
status.GetBaseStatusId = function(StatusId)
    return tracker.GetBaseStatusId(StatusId);
end

status.GetIconForStatusId = function(StatusId, Theme)
    if (Theme == nil) then
        return icons.get_icon_image(StatusId);
    else
        return icons.get_icon_from_theme(StatusId, Theme);
    end
end

-- Initialize the status library. Must be called before any status tracking.
-- @param opts  { addonPath = string, addonName = string }
status.init = function(opts)
    tracker.init(opts)
    icons.init(opts.addonPath)
end

status.SaveState = function()
    tracker.SaveState()
end

status.GetIconFfi = function(StatusId)
    return icons.get_icon_ffi(StatusId)
end

-- Sets the one entity whose statuses are tracked (0 = none) and drops every other entity's.
status.setTrackedEntity = function(serverId)
    tracker.setTrackedEntity(serverId)
end

status.Update = function()
    tracker.Update()
end

status.ClearIconCache = function()
    icons.clear_cache();
end

status.GetIconThemePaths = function()
    return icons.get_status_theme_paths();
end

-- Tears down this library's registered event handler. Call from the addon's unload event.
status.Dispose = function()
    tracker.Dispose()
end

return status;