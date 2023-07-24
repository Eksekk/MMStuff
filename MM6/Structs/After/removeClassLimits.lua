do return end
--[[
    define.method{p = 0x48F552, name = "GetStartingClass"}
    define.method{p = mmv(0x483D90, 0x490242), name = "ResetToClass", must = 1} -- ???
    [0].struct(structs.GameClasses)  'Classes'
	[0].struct(structs.GameClassKinds)  'ClassKinds'
]]

local availableDescriptionFields = 43

-- 0 is 0th tier (base class), 1 is 1st tier etc.
-- assumption is that nth tier can be promoted to any nth + 1 tier, but that can be changed
local classProgressionTemplate = "012"

-- class names, skills

local u4 = mem.u4
function replacePtrs(addrTable, origin, target)
	for i, v in ipairs(addrTable) do
		u4[v] = u4[v] + target - origin
	end
end

-- just loaded class txt
local count
mem.autohook(0x44A449, function(d)
    --debug.Message(d.eax)
    -- if row has less that minCols columns, its number is returned as count
    -- if any row
    count = DataTables.ComputeRowCountInPChar(d.eax, 2, 2) - 1
    -- assert(count % classProgressionTemplate:len() == 0, "Invalid class.txt row number according to class template")
    local oldPtr = Game.ClassDescriptions["?ptr"]
    local classDescriptionPtrs = mem.StaticAlloc(count * 4)
    mem.u4[d.esp + 0x1C] = classDescriptionPtrs -- destination
    mem.prot(true)
    mem.u4[0x44A4EA] = classDescriptionPtrs + count * 4 - 4 -- array end address (inclusive)
    replacePtrs({0x411A1D, 0x41384D, 0x44A45D}
    , oldPtr, classDescriptionPtrs)
    mem.prot()
    mem.ChangeGameArray("ClassDescriptions", classDescriptionPtrs, count)
end)

