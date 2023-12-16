local u1, u2, u4, i1, i2, i4 = mem.u1, mem.u2, mem.u4, mem.i1, mem.i2, mem.i4
local hook, autohook, autohook2, asmpatch = mem.hook, mem.autohook, mem.autohook2, mem.asmpatch
local max, min, floor, ceil, round, random = math.max, math.min, math.floor, math.ceil, math.round, math.random
local format = string.format

local E = {}
E.tests = {}

local mmver = offsets.MMVersion
local function mmv(...)
	local r = select(mmver - 5, ...)
	assert(r ~= nil)
	return r
end
E.mmv = mmv

local function mm78(...)
    local r = select(mmver - 6, ...)
    assert(r ~= nil)
    return r
end
E.mm78 = mm78

local function callWhenGameInitialized(f, ...)
    if _G.GameInitialized2 then
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

local function getSlot(player)
    for i, pl in Party do
        if pl == player then
            return i
        end
    end
end
E.getSlot = getSlot

local function getSpellQueueData(spellQueuePtr, targetPtr)
	local t = {Spell = i2[spellQueuePtr], Caster = Party.PlayersArray[i2[spellQueuePtr + 2]]}
	t.SpellSchool = ceil(t.Spell / 11)
	local flags = u2[spellQueuePtr + 8]
	if flags:And(0x10) ~= 0 then -- caster is target
		t.Caster = Party[i2[spellQueuePtr + 4]]
	end
    t.CasterIndex = getSlot(t.Caster)

	if flags:And(1) ~= 0 then
		t.FromScroll = true
		t.Skill, t.Mastery = SplitSkill(u2[spellQueuePtr + 0xA])
	else
		if mmver > 6 then
			t.Skill, t.Mastery = SplitSkill(t.Caster:GetSkill(const.Skills.Fire + t.SpellSchool - 1))
		else -- no GetSkill
			t.Skill, t.Mastery = SplitSkill(t.Caster.Skills[const.Skills.Fire + t.SpellSchool - 1])
		end
	end

	local targetIdKey = mmv("TargetIndex", "TargetIndex", "TargetRosterId")
	if targetPtr then
		if type(targetPtr) == "number" then
			t[targetIdKey], t.Target = internal.GetPlayer(targetPtr)
		else
			t[targetIdKey], t.Target = targetPtr:GetIndex(), targetPtr
		end
	else
		local pl = Party[i2[spellQueuePtr + 4]]
		t[targetIdKey], t.Target = pl:GetIndex(), pl
	end
	return t
end
E.getSpellQueueData = getSpellQueueData

local function arrayFieldOffsetName(arr, offset)
    if offset >= arr["?ptr"] then
        offset = offset - arr["?ptr"]
    end
    if offset < 0 then
        offset = offset + arr.ItemSize
    end
	local i = offset:div(arr.ItemSize)
	local off = offset % arr.ItemSize
    local minDiffBelow, minDiffBelowName
	for k, v in pairs(structs.o[structs.name(arr[0])]) do
		if v == off then
			return k
        elseif not minDiffBelow or off - v < minDiffBelow then
            minDiffBelow = off - v
            minDiffBelowName = k
        end
	end
    return minDiffBelowName, true
end
E.arrayFieldOffsetName = arrayFieldOffsetName

-- processes an array of raw addresses and generates a table, which can be passed to processReferencesTable (after manual verification and correction)
local function processRawAddresses(arrayName, addresses)
    assert(addresses, "No addresses specified")
    -- 1. command size
    -- 2. array offset and field name
    
    -- only processes direct references - count, limit, size still need to be done manually
    local results = {}
    local arr = Game[arrayName]
    local lower, upper = arr["?ptr"] - arr.ItemSize, arr["?ptr"] + arr.Size + arr.ItemSize
    for i, addr in ipairs(addresses) do
        local len = mem.GetInstructionSize(addr)
        if len < 5 then -- minimum size
            error(format("Address 0x%X has instruction size less than 5", addr))
        end
        -- find command size and if there are instruction bytes after memory offsets
        local cmdSize, hasFreeBytes
        for i = 0, len - 4 do
            local val = u4[addr + i]
            if val >= lower and val <= upper then -- found
                if cmdSize then -- found twice
                    error(format("Address 0x%X has two valid references to array", addr))
                end
                cmdSize = i
                hasFreeBytes = (i + 4 ~= len)
            end
        end
        if not cmdSize then
            error(format("No array reference found at address 0x%X", addr))
        end
        local name, notBeginning = arrayFieldOffsetName(arr, u4[addr + cmdSize])
        if not name then
            error(format("Couldn't find structure field for reference at address 0x%X", addr))
        end
        print(format("Address 0x%X, cmdSize %d, references 0x%X, field name %q (%s)",
            addr, cmdSize, u4[addr + cmdSize], name, notBeginning and "NB" or "B"))
        
        table.insert(results, {address = addr, cmdSize = cmdSize, reference = u4[addr + cmdSize], fieldName = name, notFieldBeginning = notBeginning, hasFreeBytes = hasFreeBytes})
    end
    local output = {}
    local ptr = arr["?ptr"]
    local justBeforeEnd = ptr + arr.Size - arr.ItemSize
    for _, data in ipairs(results) do
        if data.address == ptr + arr.ItemSize then -- end reference?
            table.insert(tget(output, "End"), data.address)
        elseif data.notFieldBeginning then
            table.insert(tget(output, "verify"), data.address)
        else
            if data.address >= justBeforeEnd then
                table.insert(tget(output, data.cmdSize), {addr = data.address, verifyMe = true})
            else
                table.insert(tget(output, data.cmdSize), data.address)
            end
        end
    end
    local text = dump(output, nil, true):gsub("%d+", function(num) return format("0x%X", num) end)
    --print(text)
end
E.processRawAddresses = processRawAddresses

local function printSortedArraysData(arrs, dataOrigin)
    arrs = arrs or {"ItemsTxt", "StdItemsTxt", "SpcItemsTxt", "PotionTxt", "ScrollTxt"}
    dataOrigin = dataOrigin or Game.ItemsTxt["?ptr"] - 4
    local out = {}
    for k, name in pairs(arrs) do
        local s = Game[name]
        local low, high, size, itemSize, dataOffset = s["?ptr"], s["?ptr"] + s.Limit * s.ItemSize, s.Size, s.ItemSize, s["?ptr"] - dataOrigin
        table.insert(out, {name = name, low = low, high = high, size = size, itemSize = itemSize, dataOffset = dataOffset})
    end
    table.sort(out, function(a, b) return a.low < b.low end)
    for _, data in ipairs(out) do
        print(format("%-15s %-17s %-17s %-17s %-17s %-17s",
            data.name .. ":",
            format("low = 0x%X", data.low),
            format("high = 0x%X", data.high),
            format("size = 0x%X", data.size),
            format("itemSize = 0x%X", data.itemSize), 
            format("dataOffset = 0x%X", data.dataOffset)
        ))
    end
end
E.printSortedArraysData = printSortedArraysData

local function replacePtrs(t) -- addrTable, newAddr, origin, cmdSize, check)
    local func = t.func
    local arr = t.arr or u4
	for i, oldAddr in ipairs(t.addrTable) do
        local arr, oldAddr = arr, oldAddr
        if type(oldAddr) == "table" then
            arr = oldAddr.arr
            oldAddr = oldAddr[1]
        end
		local old = arr[oldAddr + t.cmdSize]
        local new
        if func then
            new = func(old)
        else
		    new = t.newAddr - (t.origin - old)
        end
		t.check(old, new, t.cmdSize, i)
		arr[oldAddr + t.cmdSize] = new
	end
end
E.replacePtrs = replacePtrs

local function processReferencesTable(args)
    local arrName, newAddress, newCount, addressTable, lenP = args.arrName, args.newAddress, args.newCount, args.addressTable, args.lenP
    local oldRelativeBegin, newRelativeBegin = args.oldRelativeBegin, args.newRelativeBegin
    local arr = Game[arrName]
    local origin = arr["?ptr"]
    local lowerBoundIncrease = (addressTable.lowerBoundIncrease or 0) * arr.ItemSize
    addressTable.lowerBoundIncrease = nil -- eliminate special case in loop below
    local oldMin, oldMax = origin - arr.ItemSize - lowerBoundIncrease, origin + (arr.Limit + 1) * arr.ItemSize
    local newMin, newMax = newAddress - arr.ItemSize - lowerBoundIncrease, newAddress + arr.ItemSize * (newCount + 1)
    local function check(old, new, cmdSize, i)
        assert(old >= oldMin and old <= oldMax, format("[%s] old address 0x%X [cmdSize %d; array index %d] is outside array bounds [0x%X, 0x%X] (new entry count: %d)", arrName, old, cmdSize, i, oldMin, oldMax, newCount))
        assert(new >= newMin and new <= newMax, format("[%s] new address 0x%X [cmdSize %d; array index %d] is outside array bounds [0x%X, 0x%X] (new entry count: %d)", arrName, new, cmdSize, i, newMin, newMax, newCount))
    end
    mem.prot(true)
    for cmdSize, addresses in pairs(addressTable) do
        if type(cmdSize) == "number" then
            -- normal refs
            replacePtrs{addrTable = addresses, newAddr = newAddress, origin = origin, cmdSize = cmdSize, check = check}
        else
            -- special refs
            local what = cmdSize
            local memArr = addresses.arr or i4
            for cmdSize, addresses in pairs(addresses) do
                if what == "relative" then
                    local function checkRelative(old, new, cmdSize, i)
                        check(old + oldRelativeBegin, new + newRelativeBegin, cmdSize, i)
                    end
                    replacePtrs{addrTable = addresses, newAddr = newAddress - assert(newRelativeBegin), origin = origin - assert(oldRelativeBegin),
                        cmdSize = cmdSize, check = checkRelative}
                else
                    for i, data in ipairs(addresses) do
                        -- support per-address mem array types
                        local memArr, addr = memArr -- intentionally override local
                        if type(data) == "table" then
                            memArr = data.arr or memArr
                            addr = data[1]
                        else
                            addr = data
                        end
                        if what == "limit" then
                            memArr[addr + cmdSize] = memArr[addr + cmdSize] - arr.Limit + newCount
                        elseif what == "count" then
                            -- skip (I don't move count addresses atm)
                        elseif what == "high" then
                            memArr[addr + cmdSize] = newCount - 1
                        elseif what == "size" then
                            memArr[addr + cmdSize] = arr.ItemSize * newCount
                        elseif what == "End" then
                            memArr[addr + cmdSize] = newAddress + arr.ItemSize * newCount
                        end
                    end
                end
            end
        end
    end
    mem.ChangeGameArray(arrName, newAddress, newCount, lenP)
    mem.prot()
end
E.processReferencesTable = processReferencesTable

local function testItemGeneration()
    local item = Mouse.Item
    for _, itemType in pairs(const.ItemType) do
        for treasureLevel = 1, 6 do
            for cnt = 1, 1000 do
                item:Randomize(treasureLevel, itemType)
            end
        end
    end
end
E.tests.testItemGeneration = testItemGeneration

local function tryGetItem(lev, field, wantedFieldVal, typ, itemId)
    --local typ = Game.ItemsTxt[id].EquipStat + 1
    local item = Mouse.Item
    for c = 1, 10000 do
        local useLev = lev or random(1, 6)
        item:Randomize(useLev, typ or 0)
        local hasWantedField
        if wantedFieldVal ~= nil then
            hasWantedField = item[field] == wantedFieldVal
        else
            hasWantedField = true
        end
        local hasItemId
        if itemId then
            hasItemId = (item.Number == itemId)
        else
            hasItemId = true
        end
        if hasWantedField and hasItemId then
            print(true, useLev, c)
            return
        end
    end
    print(false)
end
E.tests.tryGetItem = tryGetItem

local function tryGetMouseItem(id, lev, typ)
    return tryGetItem(lev, nil, nil, typ, id)
end
E.tests.tryGetMouseItem = tryGetMouseItem

local function tryGetStdBonus(bonus, lev, typ, id)
    return tryGetItem(lev, "Bonus", bonus, typ, id)
end
E.tests.tryGetStdBonus = tryGetStdBonus

local function tryGetSpcBonus(bonus, lev, typ, id)
    return tryGetItem(lev, "Bonus2", bonus, typ, id)
end
E.tests.tryGetSpcBonus = tryGetSpcBonus

return E