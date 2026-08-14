--[[
    spui/sprites.lua
    Instanced sprite engine factory for PetsReborn.
    Each newEngine() call returns an isolated sprite context.
    A single global D3DXSprite and imageCache are shared across all engines.
]]

require('common')
local d3d8 = require('d3d8')
local ffi  = require('ffi')
local gdi  = require('libs/gdifonts/include')

-- gdifonts auto-registers its own d3d_present handler on load (renders text as soon
-- as it's required). We own text-over-images ordering here instead: disable its
-- auto-render (unregistering the handler if already registered) and call
-- gdi:render() explicitly after our own sprite draw pass below, every frame.
gdi:set_auto_render(false)

local M = {}

local d3dDevice = d3d8.get_device()
local d3dSprite = nil          -- single D3DXSprite shared across all engines
local imageCache = {}          -- path -> {texture, width, height}; shared (textures are immutable)
-- ORDERING CONTRACT: cross-engine render order is pure insertion order — there is
-- no z-index concept. The d3d_present dispatcher below iterates this list with
-- ipairs(), so engines created earlier draw first (i.e. behind later ones).
-- engine:destroy() removes an engine from this list, and a subsequent
-- M.newEngine() call appends the new engine at the END of the list. This means a
-- style/scale-triggered engine rebuild (destroy + newEngine) silently moves that
-- engine's render layer to the BACK of the global cross-engine order. Today this
-- is invisible in PetsReborn because only one engine exists (shared by petFrame
-- and targetFrame), but any future consumer that needs more than one engine per
-- addon with stable cross-engine layering will need this API extended with an
-- explicit ordering/z-index parameter.
local engines = {}             -- ordered list of all engine instances (controls cross-system z-order)

-- Pre-allocated FFI structs for 9-slice rendering (reused each frame; single-threaded safe)
local nsRect     = ffi.new('RECT[9]')
local nsVecPos   = ffi.new('D3DXVECTOR2[9]')
local nsVecScale = ffi.new('D3DXVECTOR2[9]')

local function createD3DSprite()
    local ptr = ffi.new('ID3DXSprite*[1]')
    if ffi.C.D3DXCreateSprite(d3dDevice, ptr) ~= ffi.C.S_OK then
        error('[PetsReborn] Failed to create D3DXSprite')
    end
    return d3d8.gc_safe_release(ffi.cast('ID3DXSprite*', ptr[0]))
end

local function loadImage(path)
    if imageCache[path] then
        return imageCache[path][1], imageCache[path][2], imageCache[path][3]
    end

    if not path or path == '' or not ashita.fs.exists(path) then
        return nil, 0, 0
    end

    local texPtr  = ffi.new('IDirect3DTexture8*[1]')
    local imgInfo = ffi.new('D3DXIMAGE_INFO')

    local hr = ffi.C.D3DXCreateTextureFromFileExA(
        d3dDevice, path,
        0xFFFFFFFF, 0xFFFFFFFF, 1, 0,
        ffi.C.D3DFMT_A8R8G8B8, ffi.C.D3DPOOL_MANAGED,
        ffi.C.D3DX_DEFAULT, ffi.C.D3DX_DEFAULT,
        0x00000000, imgInfo, nil, texPtr)

    if hr == ffi.C.S_OK then
        local tex = d3d8.gc_safe_release(ffi.cast('IDirect3DTexture8*', texPtr[0]))
        imageCache[path] = { tex, imgInfo.Width, imgInfo.Height }
        return tex, imgInfo.Width, imgInfo.Height
    end

    return nil, 0, 0
end

-- Writes slice `idx` (0-8) directly into the pre-allocated FFI arrays; no Lua tables.
local function setSlice(idx, left, top, right, bottom, dstX, dstY, scaleX, scaleY)
    local r = nsRect[idx]
    r.left = left; r.top = top; r.right = right; r.bottom = bottom
    local p = nsVecPos[idx]
    p.x = dstX; p.y = dstY
    local s = nsVecScale[idx]
    s.x = scaleX; s.y = scaleY
end

local function renderNineSlice(spr, v)
    local bL, bR, bT, bB = v.nineSlice[1], v.nineSlice[2], v.nineSlice[3], v.nineSlice[4]
    local tw, th = v.nativeW, v.nativeH
    local dw, dh = v.destW, v.destH
    local dx, dy = v.position_x, v.position_y

    -- Derive the UI scale from height (height is pure UI scale; width may be user-resized)
    local uiScale = dh / th

    -- Destination-space border sizes (scaled with the UI, not raw texture pixels)
    local dbL = bL * uiScale
    local dbR = bR * uiScale
    local dbT = bT * uiScale
    local dbB = bB * uiScale

    local mSrcW = math.max(1, tw - bL - bR)
    local mSrcH = math.max(1, th - bT - bB)
    local mDstW = math.max(0, dw - dbL - dbR)
    local mDstH = math.max(0, dh - dbT - dbB)
    local scX = mDstW / mSrcW
    local scY = mDstH / mSrcH

    -- Source-space (texture pixel) slice boundaries
    local midL, midR = bL, tw - bR
    local midT, midB = bT, th - bB
    -- Destination-space (UI-scaled) slice boundaries
    local dstMidL, dstMidR = dx + dbL, dx + dw - dbR
    local dstMidT, dstMidB = dy + dbT, dy + dh - dbB

    -- 9 slices: TL, TC, TR, ML, MC, MR, BL, BC, BR.
    -- Corners use uiScale so they shrink/grow with the UI scale factor.
    setSlice(0, 0,    0,    midL, midT, dx,      dy,      uiScale, uiScale)  -- TL
    setSlice(1, midL, 0,    midR, midT, dstMidL, dy,      scX,     uiScale)  -- TC
    setSlice(2, midR, 0,    tw,   midT, dstMidR, dy,      uiScale, uiScale)  -- TR
    setSlice(3, 0,    midT, midL, midB, dx,      dstMidT, uiScale, scY    )  -- ML
    setSlice(4, midL, midT, midR, midB, dstMidL, dstMidT, scX,     scY    )  -- MC
    setSlice(5, midR, midT, tw,   midB, dstMidR, dstMidT, uiScale, scY    )  -- MR
    setSlice(6, 0,    midB, midL, th,   dx,      dstMidB, uiScale, uiScale)  -- BL
    setSlice(7, midL, midB, midR, th,   dstMidL, dstMidB, scX,     uiScale)  -- BC
    setSlice(8, midR, midB, tw,   th,   dstMidR, dstMidB, uiScale, uiScale)  -- BR

    for idx = 0, 8 do
        spr:Draw(v.texture, nsRect[idx], nsVecScale[idx], nil, 0.0, nsVecPos[idx], v.color)
    end
end

-- Global render dispatcher
ashita.events.register('d3d_present', '__petsreborn_spui_present_cb', function()
    if d3dSprite ~= nil then
        d3dSprite:Begin()
        for _, eng in ipairs(engines) do
            for i = 1, eng.sortedCount do
                local v = eng.renderInfo[eng.sortedKeys[i]]
                if v and v.visible and v.texture ~= nil then
                    if v.nineSlice then
                        renderNineSlice(d3dSprite, v)
                    else
                        v.rect.right   = v.nativeW
                        v.rect.bottom  = v.nativeH
                        v.vecPos.x     = v.position_x
                        v.vecPos.y     = v.position_y
                        v.vecScale.x   = (v.displayW or v.nativeW) / math.max(1, v.nativeW)
                        v.vecScale.y   = (v.displayH or v.nativeH) / math.max(1, v.nativeH)
                        d3dSprite:Draw(v.texture, v.rect, v.vecScale, nil, 0.0, v.vecPos, v.color)
                    end
                end
            end
        end
        d3dSprite:End()
    end
    gdi:render()  -- draw text every frame, unconditionally, so it always layers on top of sprites
end)

-- Creates and returns a new isolated sprite engine instance.
-- Appends to the global engines list — see the ORDERING CONTRACT comment above `local engines = {}`.
function M.newEngine()
    local engine = {
        renderInfo  = {},     -- renderKey -> sprite obj
        sortedKeys  = {},     -- ordered for z-rendering
        sortedCount = 0,
        nextKey     = 1,      -- monotonic; never reused
    }

    -- Creates a new sprite object registered with this engine.
    function engine:newSprite()
        local spr = {
            visible    = true,
            position_x = 0,
            position_y = 0,
            nativeW    = 0,
            nativeH    = 0,
            displayW   = 0,
            displayH   = 0,
            color      = d3d8.D3DCOLOR_ARGB(255, 255, 255, 255),
            texture    = nil,
            rect       = ffi.new('RECT', { 0, 0, 0, 0 }),
            vecPos     = ffi.new('D3DXVECTOR2', { 0, 0 }),
            vecScale   = ffi.new('D3DXVECTOR2', { 1, 1 }),
            nineSlice  = nil,
            destW      = 0,
            destH      = 0,
        }
        spr.renderKey = self.nextKey
        self.nextKey = self.nextKey + 1
        self.renderInfo[spr.renderKey] = spr
        self.sortedCount = self.sortedCount + 1
        self.sortedKeys[self.sortedCount] = spr.renderKey
        return spr
    end

    -- Removes a sprite from this engine.
    function engine:destroySprite(spr)
        if not spr then return end
        self.renderInfo[spr.renderKey] = nil
        local key = spr.renderKey
        for i = 1, self.sortedCount do
            if self.sortedKeys[i] == key then
                for j = i, self.sortedCount - 1 do
                    self.sortedKeys[j] = self.sortedKeys[j + 1]
                end
                self.sortedKeys[self.sortedCount] = nil
                self.sortedCount = self.sortedCount - 1
                break
            end
        end
    end

    -- Loads a texture by path, caches globally. Returns texture, nativeW, nativeH.
    function engine:loadImage(path)
        local tex, w, h = loadImage(path)
        if tex ~= nil and d3dSprite == nil then
            d3dSprite = createD3DSprite()
        end
        return tex, w, h
    end

    -- Sets color on a sprite from hex string '#RRGGBBAA' (layout format: red first, alpha last)
    function engine:setColor(spr, hexStr)
        if not hexStr then
            spr.color = d3d8.D3DCOLOR_ARGB(255, 255, 255, 255)
            return
        end
        local hex = hexStr:gsub('#', '')
        local r = tonumber(hex:sub(1, 2), 16) or 255
        local g = tonumber(hex:sub(3, 4), 16) or 255
        local b = tonumber(hex:sub(5, 6), 16) or 255
        local a = 255
        if #hex >= 8 then
            a = tonumber(hex:sub(7, 8), 16) or 255
        end
        spr.color = d3d8.D3DCOLOR_ARGB(a, r, g, b)
    end

    -- Destroys all sprites in this engine and removes it from the global list.
    function engine:destroy()
        self.renderInfo  = {}
        self.sortedKeys  = {}
        self.sortedCount = 0
        for i, e in ipairs(engines) do
            if e == self then
                table.remove(engines, i)
                break
            end
        end
    end

    table.insert(engines, engine)
    return engine
end

-- Clears the image cache (call on addon reload if textures change).
function M.clearCache()
    imageCache = {}
end

return M
