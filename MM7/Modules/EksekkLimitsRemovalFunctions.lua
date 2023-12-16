local u1, u2, u4, i1, i2, i4 = mem.u1, mem.u2, mem.u4, mem.i1, mem.i2, mem.i4
local hook, autohook, autohook2, asmpatch = mem.hook, mem.autohook, mem.autohook2, mem.asmpatch
local max, min, floor, ceil, round, random = math.max, math.min, math.floor, math.ceil, math.round, math.random
local format = string.format

local E = {}

local function callWhenGameInitialized(f, ...)
    if GameInitialized2 then
        f(...)
    else
        local args = {...}
        events.GameInitialized2 = function() f(unpack(args)) end
    end
end
E.callWhenGameInitialized = callWhenGameInitialized

local function checkIndex(index, minIndex, maxIndex, level, formatStr)
    if index < minIndex or index > maxIndex then
        error(format(formatStr or "Index (%d) out of bounds [%d, %d]", index, minIndex, maxIndex), level + 1)
    end
end
E.checkIndex = checkIndex

local function makeMemoryTogglerTable(t)
    local arr, buf, minIndex, maxIndex = t.arr, t.buf, t.minIndex, t.maxIndex
    local bool, errorFormat, size, minValue, maxValue = t.bool, t.errorFormat, t.size, t.minValue, t.maxValue
    local aliases = t.aliases or {} -- string aliases for some indexes
    local mt = {__index = function(_, i)
        i = aliases[i] or i 
        checkIndex(i, minIndex, maxIndex, 2, errorFormat)
        local off = buf + (i - minIndex) * size
        if bool then
            return arr[off] ~= 0
        else
            return arr[off]
        end
    end,
    __newindex = function (_, i, val)
        i = aliases[i] or i
        checkIndex(i, minIndex, maxIndex, 2, errorFormat)
        local off = buf + (i - minIndex) * size
        if bool then
            arr[off] = val and val ~= 0 and 1 or 0
        else
            local smaller, greater = val < (minValue or val), val > (maxValue or val)
            if smaller or greater then
                local str
                if smaller then
                    str = format("New value (%d) is smaller than minimum possible value (%d)", val, minValue)
                elseif greater then
                    str = format("New value (%d) is greater than maximum possible value (%d)", val, maxValue)
                end
                error(str, 2)
            end
            arr[off] = val
        end
    end}
    return setmetatable({}, mt)
end
E.makeMemoryTogglerTable = makeMemoryTogglerTable

return E