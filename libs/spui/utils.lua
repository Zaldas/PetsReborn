--[[
    Copyright © 2023, Tylas
    All rights reserved.

    Redistribution and use in source and binary forms, with or without
    modification, are permitted provided that the following conditions are met:

        * Redistributions of source code must retain the above copyright
          notice, this list of conditions and the following disclaimer.
        * Redistributions in binary form must reproduce the above copyright
          notice, this list of conditions and the following disclaimer in the
          documentation and/or other materials provided with the distribution.
        * Neither the name of XivParty nor the
          names of its contributors may be used to endorse or promote products
          derived from this software without specific prior written permission.

    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
    ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
    WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
    DISCLAIMED. IN NO EVENT SHALL <your name> BE LIABLE FOR ANY
    DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
    (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
    LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
    ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
    (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
    SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
]]

local utils = {}

-- visibility flag constants (replaces const.lua dependency)
utils.VIS_DEFAULT = 1   -- general visibility flag
utils.VIS_TOKEN   = 2   -- controlled by token bindings
utils.VIS_INIT    = 3   -- delayed show after texture load

-- log levels:
-- 0 ... finest
-- 1 ... fine
-- 2 ... info (default)
-- 3 ... warning
-- 4 ... error
utils.level = 3

function utils:colorFromHex(hexStr)
    if not hexStr then return nil end
    local len = #hexStr
    if len == 0 then return nil end

    if hexStr:sub(1, 1) ~= '#' or len < 7 or len > 9 then
        utils:print('Invalid hexadecimal color code. Expected format #RRGGBB or #RRGGBBAA', 4)
        return nil
    end

    return {
        r = tonumber(hexStr:sub(2, 3), 16) or 255,
        g = tonumber(hexStr:sub(4, 5), 16) or 255,
        b = tonumber(hexStr:sub(6, 7), 16) or 255,
        a = len > 7 and (tonumber(hexStr:sub(8, 9), 16) or 255) or 255,
    }
end

-- interprets a list with two elements as X,Y coordinates
function utils:coord(coordList)
    local coord = {}

    if coordList then
        coord.x = tonumber(coordList[1])
        coord.y = tonumber(coordList[2])
    end

    if not coord.x then coord.x = 0 end
    if not coord.y then coord.y = 0 end

    return coord
end

function utils:round(num, numDecimalPlaces)
    if numDecimalPlaces and numDecimalPlaces > 0 then
        local mult = 10 ^ numDecimalPlaces
        return math.floor(num * mult + 0.5) / mult
    end

    return math.floor(num + 0.5)
end

-- returns true if the specified function returns true for ALL list values
function utils:all(list, func)
    if not func then func = function(x) return x end end

    local result = false
    local first = true
    for _, v in pairs(list) do
        if first then
            first = false
            result = func(v)
        else
            result = result and func(v)
        end
    end
    return result
end

-- returns true if the specified function returns true for ANY list value
function utils:any(list, func)
    if not func then func = function(x) return x end end

    local result = false
    for _, v in pairs(list) do
        result = result or func(v)
        if result then return result end
    end
    return result
end

-- stable in-place sorting
-- @param func a comparison function that returns true when a > b
function utils:insertionSort(array, func)
    local len = #array
    for j = 2, len do
        local key = array[j]
        local i = j - 1
        while i > 0 and func(array[i], key) do
            array[i + 1] = array[i]
            i = i - 1
        end
        array[i + 1] = key
    end
    return array
end

function utils:print(text, level)
    if level == nil then
        level = 2 -- default log level: info
    end

    if self.level <= level and text then
        print(text)
    end
end

function utils:toString(obj)
    if obj then
        return tostring(obj)
    end
    return '???'
end

function utils:logTable(t, depth)
    if not depth then
        depth = 0
    end

    local indent = ''
    for _ = 0, depth, 1 do
        indent = indent .. ' '
    end

    if type(t) == 'table' then
        for key, value in pairs(t) do
            if type(value) == 'table' then
                print(indent .. key)
            elseif key ~= '_raw' and key ~= '_data' then
                print(indent .. key .. ' = ' .. tostring(value) .. '(' .. type(value) .. ')')
            end
            utils:logTable(value, depth + 3)
        end
    end
end

-- bitwise operations

function utils:bitAnd(a, b)
    local p, c = 1, 0
    while a > 0 and b > 0 do
        local ra, rb = a % 2, b % 2
        if ra + rb > 1 then c = c + p end
        a, b, p = (a - ra) / 2, (b - rb) / 2, p * 2
    end
    return c
end

function utils:bitOr(a, b)
    local p, c = 1, 0
    while a + b > 0 do
        local ra, rb = a % 2, b % 2
        if ra + rb > 0 then c = c + p end
        a, b, p = (a - ra) / 2, (b - rb) / 2, p * 2
    end
    return c
end

function utils:bitNot(n)
    local p, c = 1, 0
    while n > 0 do
        local r = n % 2
        if r < 1 then c = c + p end
        n, p = (n - r) / 2, p * 2
    end
    return c
end

return utils
