function reload()
	dofile("Scripts/Global/GenerateStructInfo.lua")
end
r = reload
local mmver = offsets.MMVersion
local function mm78(...)
	local r = select(mmver - 6, ...)
	assert(r ~= nil)
	return r
end
local _DEBUG = true
--[[
	> dump(structs, 1)
	-- interesting stuff:
   	class = function: 0x0329b2d8,\ -- class with custom methods and "new" method
	enum = function: 0x0329b338,\ -- for iterating over struct instance's properties
	f = table: 0x03259168,\ -- definition functions
	m = table: 0x032591f0,\ -- member handler functions (handle every access and write to it)
	name = function: 0x0329b450,\ -- gets struct name from its class
	o = table: 0x032591c8\ -- offsets of all members
	
	-- also:
	
	mem.structs.types
	mem.structs.types.u4
	mem.structs.types.array -- etc.
	
	-- a lot of info is stored in upvalues
	-- debug.getinfo also was useful in one case
]]

-- generic constants

local types = mem.structs.types

local EditPChar_newindex, EditConstPChar_newindex = getmetatable(mem.EditPChar).__newindex, getmetatable(mem.EditConstPChar).__newindex

local booleanHandlers = {
	[getUpvalue(mem.structs.types.b1, "handler")] = 1,
	[getUpvalue(mem.structs.types.b2, "handler")] = 2,
	[getUpvalue(mem.structs.types.b4, "handler")] = 4,
}

local bitIndex = {}
do
	local bit = 1
	for i = 0, 7 do
		bitIndex[bit] = i
		bit = bit * 2
	end
end
local AnyABitHandler = getU(getU(types.abit, "doBit"), "AnyABitHandler")

local luaData = {}
local function setBaseTypeField(data, field, value) -- if there are arrays, skips them
	local data2 = data
	while data2.array do
		data2 = data2.innerType
	end
	data2[field] = value
end

local function getBaseTypeField(data, field)
	local data2 = data
	while data2.array do
		data2 = data2.innerType
	end
	return data2[field]
end

local getGroup

local function getCustomFieldSizes(structName)
	local oldMember = types.CustomType
	local fieldSizes = {}
	function types.CustomType(name, size, f, ...)
		fieldSizes[name] = size
		return oldMember(name, size, f, ...)
	end
	mem.struct(structs.f[structName])
	types.CustomType = oldMember
	return fieldSizes
end

function getStructureMembersInfoData(structName)
	local oldStru = structs.f[structName]
	local output, methods = {}, {}
	structs.f[structName] = function(define, ...)
		local oldInfo, oldFunc, oldMethod = types.Info, types.func, types.method
		local prevDefined
		function types.Info(t, ...)
			local name = define.LastDefinedMemberName or "DefaultIndex"
			if t ~= nil and (type(t) ~= "table" or not t.new) -- not added by mmext
				and prevDefined ~= name -- don't overwrite old data, for example if define.f.Something is defined, because it doesn't change "LastDefinedMemberName"
			then
				prevDefined = name
				output[name] = t
			end
			return oldInfo(t, ...)
		end
		function types.func(def, ...)
			define.LastDefinedMemberName = def.name
			return oldFunc(def, ...)
		end
		function types.method(def, ...)
			define.LastDefinedMemberName = def.name
			methods[def.name] = true
			return oldMethod(def, ...)
		end
		-- skip info calls after "define.f.functionName" or "define.m.functionName"
		local metaF, metaM = getmetatable(types.f), getmetatable(types.m)
		local oldF, oldM = metaF.__newindex, metaM.__newindex
		function metaF.__newindex(...)
			prevDefined = define.LastDefinedMemberName 
			return oldF(...)
		end
		function metaM.__newindex(...)
			prevDefined = define.LastDefinedMemberName
			return oldM(...)
		end
		local ret = {oldStru(define, ...)}
		types.Info, types.func, types.method = oldInfo, oldFunc, oldMethod
		metaF.__newindex, metaM.__newindex = oldF, oldM
		return unpack(ret)
	end
	mem.struct(structs.f[structName])
	structs.f[structName] = oldStru
	return output, methods
end

local globalExcludes =
{
	Player = {"Attrs"}, -- attrs is from merge.
	GameStructure = {"Dialogs"}, -- mmext
	Item = {"ExtraData"}, -- my stuff for MAW mod
}

function getFunctionsData(class, infoData)
	local data = {}
	for mname, handler in pairs(class or {}) do
		if type(handler) == "function" then
			local def = getU(handler, "def")
			if type(def) == "table" then
				data[mname] = data[mname] or {}
				data[mname] = {def = def, info = infoData[mname]}
			end
		end
	end
	return data
end

-- C++ definition generator constants
local skipBitsText = "SKIPBITS(%d);"
local skipBytesText = "SKIP(%d);"
local INDENT_CHARS = "\t"
local namespaceStr = "mm" .. _G.offsets.MMVersion .. "::"
local commonTypeNamesToCpp = 
{
	u1 = "uint8_t",
	u2 = "uint16_t",
	u4 = "uint32_t",
	u8 = "uint64_t",
	i1 = "int8_t",
	i2 = "int16_t",
	i4 = "int32_t",
	i8 = "int64_t",
	r4 = "float",
	r8 = "double",
	r10 = "long double",
	b1 = "bool",
}
local extra = -- extra fields in structs
{
	Player =
	{
		{games = {7, 8}, data = {offset = structs.o.Player.FireResistanceBase + 18, name = "LightResistanceBase", typeName = commonTypeNamesToCpp.i2, size = 2, dataType = types.i2} },
		{games = {7, 8}, data = {offset = structs.o.Player.FireResistanceBase + 20, name = "DarkResistanceBase", typeName = commonTypeNamesToCpp.i2, size = 2, dataType = types.i2} },
		{games = {7, 8}, data = {offset = structs.o.Player.FireResistanceBase + 22 + 18, name = "LightResistanceBonus", typeName = commonTypeNamesToCpp.i2, size = 2, dataType = types.i2} },
		{games = {7, 8}, data = {offset = structs.o.Player.FireResistanceBase + 22 + 20, name = "DarkResistanceBonus", typeName = commonTypeNamesToCpp.i2, size = 2, dataType = types.i2} },
	}
}
local globalReplacements = {class = "clas", ["if"] = "if_", ["else"] = "else_"}
local convertToPointers = -- because updated during runtime etc.
{
	SpritesLod = {"SpritesSW"},
	GameStructure = {"NPCDataTxt", "MonstersTxt", "CharacterPortraits", "TransportLocations", "NPCGroup", "NPCText", "TransTxt", "ShopTheftExpireTime",
		"MapDoorSound", "GlobalEvtLines", "ItemsTxt", "NPC", "MixPotions", "ReagentSettings", "NPCNews", "MapFogChances",
		"ShopItems", "GuildItems", "NPCTopic", "ShopSpecialItems", "AutonoteTxt", "MapStats", "Houses", "ClassNames", "HostileTxt",
		"PlaceMonTxt", "AutonoteCategory", "QuestsTxt", "HousesExtra", "CharacterDollTypes", "HouseMovies", "NPCGreet", "TransportIndex",
		"GuildNextRefill2", "ShopNextRefill", "ClassNames" -- from merge
		, "PatchOptions" -- potentially relocated each run
		, "CustomLods", "MonsterKinds", "TitleTrackOffset", "MissileSetup", "AwardsSort" -- MMExt
	},
	GameClasses = {"HPBase", "SPBase", "HPFactor", "SPFactor", "StartingStats", "Skills" -- Merge
	, "SPStats"}, -- MMExt
	GameClassKinds = {"StartingSkills"}, -- Merge
	DialogLogic = {"List"} -- MMExt
}

-- decided to keep all three games' structures in one file, because I would have to include files for all games anyway
local structureByFile =
{
	MapModel = {"ModelVertex", "ModelFacet", "BSPNode", "MapModel"},

	MapMisc = {"TilesetDef", "MapOutline", "MapOutlines", "OdmHeader", "BlvHeader", "SpawnPoint", "BaseLight", "MapNote"},

	MapElements = {"FacetData", "MapLight", "MapRoom", "MapVertex", "MapFacet", "MapDoor", "MapSprite", "MapChest"},

	Common = {"SpellBuff", "SpellEffect", "Item", "StartStat", "ObjectRef2", "FloatVector", "ObjectRef"},

	Monster = {"MonsterSchedule", "MonsterAttackInfo", "MapMonster", "MonstersTxtItem", "MonsterKind"},

	GameMap = {"MapExtra", "MapObject", "GameMap"},

	Arcomage = {"ArcomageAction", "ArcomageActions", "ArcomageCard", "ArcomagePlayer", "Arcomage"},

	Lod = {"LodRecord", "CustomLods", "LodFile", "Lod", "LodSprite", "LodSpriteD3D", "SpritesLod", "LodBitmap", "BitmapsLod", "LodSpriteLine", "LodPcx"},

	Bin = {"DecListItem", "OverlayItem", "TileItem", "ObjListItem", "DChestItem", "SoundsItem", "TFTItem", "MonListItem", "PFTItem", "IFTItem", "SFTItem", "SFT", "CurrentTileBin"},
	
	TxtFileItems = {"HistoryTxtItem", "StdItemsTxtItem", "SpcItemsTxtItem", "SpellsTxtItem", "MapStatsItem", "ItemsTxtItem", "NPCProfTxtItem", "Events2DItem", },

	GameDataStructs = {"GameRaces", "GameClasses", "GameClassKinds", "DialogLogic", "Dlg", "GameScreen"},

	GameMisc = {"SpellInfo", "TravelInfo", "FogChances", "ShopItemKind", "GeneralStoreItemKind", "HouseMovie", "Weather", "MoveToMap", "MissileSetup", "TownPortalTownInfo", "EventLine", "ProgressBar", "ActionItem", "PatchOptions", "GameMouse", "MouseStruct", "Fnt"},

	Player = {"FaceAnimationInfo", "LloydBeaconSlot", "BaseBonus", "Player"},

	GameParty = {"GameParty", "NPC", "Button", "NPCNewsItem"},

	MergeSpecific = {"ArmorShopRule", "ShopRule", "WeaponShopRule", "ArcomageRule", "HouseRules", "HousesExtra", "CharacterDollType", "CharacterVoices", "CharacterPortrait", "PartyLight", "EquipCoordsCloak", "EquipCoordinates", "ArmorPicsCoords", "ReagentSettings"},

	GameStructure = {"GameStructure"}
}

local function stripNamespaces(str)
	return str:gsub(".-::", "")
end

local function getStructFile(name)
	for k, v in pairs(structureByFile) do
		if table.find(v, name) then
			return k
		end
	end
	printf("No file specified for name %q", name)
	return "unknown"
end

-- helper functions
-- DEFINED IN A_EksekkFunctions.lua

--[[
all possible attributes:
- array - is array
	- beyondLen - access beyond length (???)
	- count - number of elements
	- size - full array size (product of count and all child array counts and base type size)
	- low - first element index (usually 0 or 1)
	- innerType - return value from recursive call
- typeName - data type name (for structs it's struct name)
- constValue - value of this member can't be changed
- formatTypeName - %s is embedded in string and represents member name and thus must be formatted
- ptr - is ptr to something (array, character string, structure etc.)
- constPtr - pointer can't be changed
- size - entire member size in memory, for arrays it's count * innerType.size
- bit - is bit
	- bitValue - used for named bits (like structs.Item.Stolen)
	- bitIndex - index of bit in little endian starting from 0 (bit 0x200 of container 0xFE84 would have index 14), used only with named bits
	- bigEndian - used with bit arrays
	- anti - is anti bit (if you access a bit (0-7) with index 2, anti bit index is (7 - 2) = 5), used only with unnamed bits
- comments - table of strings
- struct - is struct (or pointer to it if ptr is set)
- commentOut - self-explanatory, used for custom types with 0 size
- padding
- [added in processStruct] ptrValue - pointer with set value
- [added in getGroup] padStart
]]
local getMemberData
function getMemberData(structName, memberName, member, offsets, members, class, rofields, customFieldSizes, inArray)
	rofields = rofields or {}
	member = member or members[memberName]
	local data = {name = memberName or "", offset = offsets[memberName or ""] or 0}
	local function addComment(s)
		data.comments = data.comments or {}
		table.insert(data.comments, s)
	end
	if type(memberName) == "number" then -- unions
		data.name = "_" .. memberName
	end
	local protFunc = getU(member, "f0")
	if protFunc then
		addComment("requires unprotect before change")
		member = protFunc
	end
	local up = debug.upvalues(member)
	local arrayHandler = up.f
	local boolsize = booleanHandlers[member] -- boolean
	local memArr = up.arr -- mem arrays etc.
	local sname = (type(arrayHandler) == "table" and arrayHandler or {})[internal.structs_name_t] -- structure
	local bitValue = up.b
	local isAutoValueBit = up.bitHandlers and true or false -- bit without specifying value (contiguous), used in arrays
	local stringLen = up.len
	local unionOffsets = up.offs
	data.constValue = memberName and (tostring(memberName):len() > 0) and (table.find(rofields, memberName) ~= nil)
	if unionOffsets then
		data.union, data.offsets, data.fields, data.rofields = true, unionOffsets, up.fields, up.rofields
		
		-- assume union offset is minimum offset among its fields
		local offset = 0xFFFFFFFF
		for k, v in pairs(data.offsets) do
			offset = math.min(offset, v)
		end
		data.offset = offset
		data.dataType = types.union
	elseif up.count then -- array
		-- if Merge and table.find({"HPBase", "SPBase", "HPFactor", "SPFactor", "SPStats"}, memberName) then
		-- 	data.offset = getU(getmetatable(Game.Classes[memberName]).__index, "o")
		-- end
		data.array = true
		data.innerType = getMemberData(structName, memberName, arrayHandler, offsets, members, class, rofields, customFieldSizes, true)
		if data.innerType.replaceWith then
			data.replaceWith = data.innerType.replaceWith
			return data
		end
		data.ptr = up.ptr
		data.lenP = up.lenP
		data.lenA = data.lenP and getU(MT(up.lenA).__index, "size")
		data.beyondLen = up.beyondLen
		data.count = up.count == 0xFFFFFFFF and 0 or up.count
		if data.beyondLen then
			addComment("AccessBeyondLength is active (???)")
		end
		data.low = up.low
		if data.low and data.low > 0 then
			addComment(string.format("MMExt: %d..%d, here %d..%d", data.low, data.low + data.count - 1, 0, data.count - 1))
		end
		data.size = ((data.ptr or data.count == 0) and 4 or data.count * up.size)
		-- PADDING PROBLEMS, two solutions below:
		if data.innerType.size and up.size > data.innerType.size then
			data.innerType.padding = up.size - data.innerType.size
			-- 1st, count padding as type size
			--data.innerType.size = up.size
		end
		if data.innerType.bit then
			data.originalBitCount = data.count
			local bytes = data.count:div(8)
			data.count = bytes
			addComment("array of " .. (data.innerType.anti and "abits (real index = 7 - usual)" or "bits"))
			data.size = bytes
		else
			-- 2nd, padding is distinct and add it only when necessary
			data.size = (data.ptr or data.count == 0) and 4 or math.ceil(data.count * (data.innerType.size + (data.innerType.padding or 0)))
		end
		data.dataType = data.ptr and types.parray or types.array
		-- change array to pointer
		if convertToPointers[structName] and table.find(convertToPointers[structName], data.name) then
			tget(luaData, structName, data.name).ptrName = data.name
			setBaseTypeField(data, "convertToPointer", true) -- setting this to explicitly signal to processStruct that it needs to convert length field into pointer
			--setBaseTypeField(data, "padding", (getBaseTypeField(data, "padding") or 0) + getBaseTypeField(data, "size") - 4)
		end
	elseif stringLen then -- string (fixed size, not pointer)
		data.array = true
		data.count = stringLen
		data.low = 0
		data.size = data.count
		data.innerType = {typeName = "char", name = memberName, offset = 0, size = 1, dataType = types.string}
		addComment("fixed size string, " .. (up.NoZero and "doesn't require null terminator" or "requires null terminator"))
		data.dataType = types.string
	elseif bitValue then
		data.size = 1/8
		data.bitIndex = 7 - bitIndex[bitValue] or error("Not a valid bit", 1)
		data.typeName = "bool %s : 1"
		data.formatTypeName = true
		data.bit = true
		data.dataType = types.bit
	elseif isAutoValueBit then
		data.size = 1/8
		data.bit = true
		if inArray then
			data.bigEndian = true
			data.typeName = "uint8_t"
		else
			data.typeName = "bool %s : 1"
			data.formatTypeName = true
		end
		data.anti = member == AnyABitHandler -- is anti bit (if you access a bit (0-7) with index 2, anti bit index is (7 - 2) = 5)
		data.dataType = data.anti and types.abit or types.bit
	elseif getUpvalueByValue(member, EditPChar_newindex) then
		data.size = 4
		data.typeName = "char"
		data.ptr = true
		data.dataType = types.EditPChar
		addComment("EditPChar")
	elseif getUpvalueByValue(member, EditConstPChar_newindex) then
		data.size = 4
		data.typeName = "char"
		data.ptr = true
		addComment("EditConstPChar - unprotect before/protect after edit")
		data.dataType = types.EditConstPChar
	elseif boolsize then
		if boolsize == 1 then
			data.typeName = "bool"
		else
			data.typeName = boolsize == 2 and commonTypeNamesToCpp.u2 or commonTypeNamesToCpp.u4
			addComment(boolsize .. "-byte boolean")
		end
		data.size = boolsize
		data.dataType = types["b" .. boolsize]
	elseif memArr then
		local found
		for _, name in ipairs{"u1", "u2", "u4", "u8", "i1", "i2", "i4", "i8", "r4", "r8", "r10"} do
			if memArr == mem[name] then
				data.typeName = commonTypeNamesToCpp[name]
				data.size = tonumber(name:sub(2))
				found = true
				data.dataType = types[name]
				break
			end
		end
		if memArr == mem.pchar then
			data.size = 4
			data.typeName = "char"
			data.ptr = true
			data.constPtr = true
			data.constValue = true
			data.dataType = types.pchar
			addComment("PChar (read-only)")
			found = true
		end
		found = found or error("Unknown mem array type")
	elseif sname then -- struct or pstruct
		if sname == "PlayerResistanceBaseBonus" then
			local ro = table.find(rofields, memberName)
			local newBase, newBonus = "ResistanceBase", "ResistanceBonus"
			data.replaceWith =
			{
				{
					offset = data.offset, array = true, count = 11, low = 0, size = 22, name = newBase, constValue = ro, dataType = types.array, innerType =
					{
						typeName = commonTypeNamesToCpp.i2, offset = data.offset, size = 2, name = newBase, constValue = ro, dataType = types.i2
					},
				},
				{
					offset = data.offset + 22, array = true, count = 11, low = 0, size = 22, name = newBonus, constValue = ro, dataType = types.array, innerType =
					{
						typeName = commonTypeNamesToCpp.i2, offset = data.offset + 22, size = 2, name = newBonus, constValue = ro, dataType = types.i2
					},
				},
			}
			return data
			--data.size = 4
		end
		local isPtr = up.pstruct
		data.typeName = sname
		data.ptr = isPtr
		data.struct = true
		data.size = isPtr and 4 or structs[sname]["?size"]
		data.dataType = isPtr and types.pstruct or types.struct
	else
		data.array = true
		data.innerType = {size = 1, typeName = commonTypeNamesToCpp.u1, name = memberName, dataType = types.u1, unknownType = true}
		data.count = customFieldSizes[memberName] or error("Unknown custom type name: " .. memberName, 2)
		if data.count == 0 then
			--data.count = 1
			data.commentOut = true
			data.innerType.commentOut = true
			addComment("real size is 0")
		end
		data.low = 0
		data.size = data.count
		addComment("Unknown type")
	end
	if convertToPointers[structName] and table.find(convertToPointers[structName], data.name) then
		tget(luaData, structName, data.name).ptrName = data.name
		data.convertToPointer = true
	end
	return data
end

function getArrayPointerString(arrays, last, addPointer) -- for testing: https://cdecl.org/
	local stdArray = "std::array<%s, %d>"
	local type = (last.namespacePrefix or "") .. last.typeName .. (last.ptr and "*" or "") .. (last.constPtr and "const" or "")
	for i = #arrays, 1, -1 do
		local arr = arrays[i]
		if arr.count == 0 then
			type = type .. "*"
		else
			type = stdArray:format(type, arr.count) .. (arr.ptr and "*" or "")
			-- std::array<std::array<uint8_t, 128>*, 128> heightMap;
		end
	end
	return type .. (addPointer and "*" or "") .. " " .. last.name
end

local function toCamelCase(str)
	local twoUpper = str:len() >= 2 and str:sub(1, 2):upper() == str:sub(1, 2)
	str = twoUpper and str or (str:sub(1, 1):lower() .. (str:len() >= 2 and str:sub(2) or ""))
	str = globalReplacements[str] or str
	return str
end

local function getArraysCommentsAndBaseData(data)
	-- collect array info and get to base type
	local arrays, comments = {}, {}
	while data.array do
		comments = table.join(comments, data.comments or {})
		arrays[#arrays + 1] = data
		data = data.innerType
	end
	comments = table.join(comments, data.comments or {})
	return arrays, comments, data
end

local function structField(value)
	return {type = "struct", value = value}
end
local function memberField(value)
	return {type = "member", value = value}
end
local function unionField(value)
	return {type = "union", value = value}
end
local function paddingField(value)
	return {type = "padding", value = value}
end

local function processSingle(data, indentLevel, structName, namespaceStr, debugLines, layout)
	indentLevel = indentLevel or 0
	local indentOuter, indentInner = string.rep(INDENT_CHARS, indentLevel), string.rep(INDENT_CHARS, indentLevel + 1)
	local dataCopy = data
	local s = indentOuter
	local arrays, comments, data = getArraysCommentsAndBaseData(data)
	if #arrays == 0 then arrays = nil end
	
	-- use camel case (I personally prefer it)
	data.pascalCaseName = data.name
	table.foreach(arrays or {}, function(v) v.pascalCaseName = v.name end)
	data.name = toCamelCase(tostring(data.name))

	local function doBaseType(doArrays)
		local result = data.static and "static " or ""
		-- structure, mem array, edit pchars, bools, bits
		if data.constValue then
			result = result .. "const "
		end
		if data.formatTypeName then
			result = result .. data.typeName:format(data.name)
		else
			if arrays and doArrays then
				result = result .. getArrayPointerString(arrays, data)
			else
				result = result .. (data.namespacePrefix or "") .. data.typeName .. (data.ptr and "*" or "") .. " " .. data.name
			end
		end
		local offset = arrays and arrays[1] and arrays[1].offset or data.offset or 0
		table.insert(comments, string.format("0x%X (%d decimal)", offset, offset))
		if data.bit and data.bitIndex then
			comments[#comments] = comments[#comments] .. ", bit index " .. data.bitIndex
		end
		if data.commentOut then
			result = "// " .. result
		end
		return result
	end
	local layoutAdd
	if data.union then
		s = {}
		for i, v in ipairs(data.code) do
			s[i] = indentOuter .. v
		end
		layoutAdd = assert(data.layout)
	elseif arrays and #arrays == 1 and data.padding then -- NPCTopic, NPCText - element size 4, "real" size 8, overlapping
		local structName = "__" .. data.name
		local old1 = data.name
		data.name = "value"
		s = {
			indentOuter .. "struct " .. structName,
			indentOuter .. "{",
			indentInner .. 		doBaseType(false) .. ";",
			indentInner .. 		skipBytesText:format(data.padding),
			indentOuter .. "};"
		}
		layoutAdd = {
			{type = "struct", value = {
				{type = "member", value = data},
				{type = "padding", value = data.padding}
			}
		}}
		data.name = old1
		local old2, old3 = data.typeName, data.ptr -- hacky hacky
		data.typeName = structName
		data.ptr = nil
		s[#s + 1] = indentOuter .. doBaseType(true) .. ";"
		table.insert(layoutAdd, {type = "member", value = arrays and arrays[1] or data})
		data.typeName, data.ptr = old2, old3
	else
		if data.padStart then
			s = {
				indentOuter .. "struct " .. structName,
				indentOuter .. "{",
				indentInner .. 		skipBytesText:format(data.padStart),
				indentInner .. 		doBaseType(true) .. ";",
				indentOuter .. "};"
			}
			layoutAdd = {
				{type = "struct", value = {
					{type = "padding", value = data.padStart},
					{type = "member", value = arrays and arrays[1] or data}
				}
			}}
		else
			s = s .. doBaseType(true)
			layoutAdd = {{type = "member", value = arrays and arrays[1] or data}}
		end
	end
	local commentsStr = #comments > 0 and (" // " .. table.concat(comments, " | ")) or ""
	if type(s) == "table" then
		s[#s] = s[#s] .. commentsStr
	else
		s = s .. ";" .. commentsStr
	end
	if _DEBUG and not data.static and not data.commentOut then
		local off = arrays and arrays[1] and arrays[1].offset or data.offset or 0
		local formatStr = "%sstatic_assert(offsetof(%s, %s) == %d);"
		if off ~= 0 and structName and not data.bit then
			table.insert(debugLines, formatStr:format(indentOuter, namespaceStr .. structName, data.name, off))
		end
	end
	data = dataCopy
	mergeArraysShallowCopy(layout, assert(layoutAdd), true)
	return s
end

--[[
	{type = "member", value = {name = "X"}},
	{type = "padding", value = 5},
	{type = "member", value = {name = "StableZ"}},
	{type = "union", value = {
		{type = "member", value = {size = 6}},
		{type = "struct", value = {
			{type = "padding", value = 4},
			{type = "member", value = {size = 1}},
			{type = "member", value = {size = 1}},
		}
	},
	{type = "struct", value = {
		{type = "member", value = {name = "X"}},
		{type = "member", value = {name = "Y"}},
		{type = "member", value = {name = "Z"}},
	},
	{type = "padding", value = 20},
	{type = "member", value = {name = "LookAngle", dataType = types.i4}},
]]

-- using visual studio code with "lua booster" extension
-- need to dummy forward declare to not miss recursive call when using "find references"
local processGroup
function processGroup(group, indentLevel, structName, namespaceStr, debugLines, layout)
	indentLevel = indentLevel or 0
	if #group == 1 then
		local ret = processSingle(group[1], indentLevel, structName, namespaceStr, debugLines, layout)
		return type(ret) == "table" and ret or {ret}
	end
	local indentOuter, indentInner = string.rep(INDENT_CHARS, indentLevel), string.rep(INDENT_CHARS, indentLevel + 1)
	-- do union wrap
	local union = {type = "union", value = {}}
	table.insert(layout, union)
	layout = union.value -- everything else goes into union
	local code = {
		indentOuter .. "union",
		indentOuter .. "{"
	}
	setmetatable(code, {__newindex = function(t, k, v) -- used in processSingle(), for convenience value can be table
		if type(v) == "table" then
			multipleInsert(t, k, v)
		else
			rawset(t, k, v)
		end
	end})
	-- if any two members have different sizes, need to wrap in struct
	-- members with size equal to biggest among group will be outside, other inside
	local maxS = 0
	for i, v in ipairs(group) do
		maxS = math.max(maxS, v.size)
	end
	local wrap = {}
	local offset = group[1].offset
	local skipFirst = true -- first is at right offset, second needs adjustment (usually by 4)
	for i, member in ipairs(group) do
		if member.size ~= maxS then
			wrap[#wrap + 1] = member
		else
			-- for now taken care of by processSingle
			local padding = member.innerType and member.innerType.padding
			local layoutTmp = layout
			if padding and not skipFirst then
				code[#code + 1] = indentInner .. "struct"
				code[#code + 1] = indentInner .. "{"
				indentLevel = indentLevel + 1
				code[#code + 1] = string.rep(INDENT_CHARS, indentLevel + 1) .. skipBytesText:format(padding)
				local stru = {type = "struct", value = {}}
				table.insert(stru.value, {type = "padding", value = padding})
				layoutTmp = stru.value -- next call will pack members into this struct
				table.insert(layout, stru)
			end
			code[#code + 1] = processSingle(member, indentLevel + 1, structName, namespaceStr, debugLines, layoutTmp)
			if padding and not skipFirst then
				indentLevel = indentLevel - 1
				code[#code + 1] = indentInner .. "};"
			end
			if padding then
				skipFirst = not skipFirst
			end
		end
		offset = member.offset + member.size + ((member.innerType or {}).padding or 0)
	end
	if #wrap > 0 then
		-- do struct wrap
		table.sort(wrap, function(a, b) return a.offset < b.offset end)
		do
			local stru = structField{}
			table.insert(layout, stru)
			layout = stru.value
		end
		code[#code + 1] = indentInner .. "struct"
		code[#code + 1] = indentInner .. "{"
		local indentInnerInner = string.rep(INDENT_CHARS, indentLevel + 2)
		local lastOffset = group[1].offset
		local i = 1
		while true do
			local currentField = wrap[i]
			local members
			members, i = getGroup(wrap, currentField, i)
			local skipBits = (currentField.offset - lastOffset) * 8
			if skipBits > 0 and skipBits % 8 == 0 then
				local bytes = skipBits:div(8)
				code[#code + 1] = indentInnerInner .. skipBytesText:format(bytes)
				table.insert(layout, paddingField(bytes))
			elseif skipBits > 0 then
				--[[
				SATISFY MSVC
				packing bitfields there is wonky
				
				either have each bitfield item the size of item outside of bitfield (unsigned also strongly recommended), otherwise there will be wasted space
				
				or use 1-byte fields and carefully adjust size of skipped bits so that 8-bit boundary is not crossed in one declaration (if so, other bits will be skipped,
				so not only wasted space, but also subsequent bit positions will be wrong and union size may be wrong)
				(thank god to my idea to put static_assert! I would not catch this that soon otherwise)
				
				I chose second approach because first conflicts with my (attempted) decoupled functions structure (processGroup shouldn't care what type field has,
				while to fix it it would have to change types of bit fields), while getMemberData shouldn't care about type outside bitfield
				]]
				local previousBit = (lastOffset % 1) * 8
				local skip = math.min(skipBits, 8 - previousBit)
				-- don't print total if it's just single skipbits "instruction"
				local total = skipBits - skip > 0 and string.format(" // skipping %d bytes and %d bits, in total %d bits", skipBits:div(8), skipBits % 8, skipBits) or ""
				code[#code + 1] = indentInnerInner .. skipBitsText:format(skip) .. total
				table.insert(layout, paddingField(skip / 8))
				skipBits = skipBits - skip
				local function doBits()
					if skipBits > 0 then
						skip = math.min(skipBits, 8) -- no more than 8 bits in one go
						code[#code + 1] = indentInnerInner .. skipBitsText:format(skip)
						skipBits = skipBits - skip
						table.insert(layout, paddingField(skip / 8))
					end
				end
				doBits() -- TODO: useless call?
				local skipBytes = skipBits:div(8)
				if skipBytes > 0 then
					code[#code + 1] = indentInnerInner .. skipBytesText:format(skipBytes)
					table.insert(layout, paddingField(skipBytes))
					skipBits = skipBits - skipBytes * 8
				end
				doBits()
			end
			if #members == 1 then
				code[#code + 1] = processSingle(currentField, indentLevel + 2, structName, namespaceStr, debugLines, layout)
			else
				code[#code + 1] = processGroup(members, indentLevel + 2, structName, namespaceStr, debugLines, layout) -- nested unions
			end
			lastOffset = currentField.offset + currentField.size
			if i > #wrap then break end
		end
		code[#code + 1] = indentInner .. "};"
	end
	code[#code + 1] = indentOuter .. "};"
	return code
end

local function findDependencies(data, structureDependencies)
	local data2 = data
	while data2 do
		if data2.struct then
			if not table.find(structureDependencies, data2.typeName) then
				structureDependencies[#structureDependencies + 1] = data2.typeName
			end
		end
		data2 = data2.innerType
	end
end
 -- for doing unions
 -- returns group members, next index for full members array, and offset which marks group end (non-inclusive, member at this offset won't be in group)
function getGroup(fields, firstField, i)
	local members = {firstField}
	debugTable(firstField)
	
	local maxNextOffset = firstField.offset + firstField.size

	for j = i + 1, #fields do
		if fields[j].offset >= maxNextOffset then
			return members, j, maxNextOffset
		end
		maxNextOffset = math.max(maxNextOffset, fields[j].offset + fields[j].size)
		table.insert(members, fields[j])
	end
	return members, #fields + 1, maxNextOffset
end

local function addExtraFields(name, fields)
	-- fields hardcoded into this file, because they really need special processing (for example,
	-- light resistance doesn't have name and thus also offset)
	local extra = extra[name]
	if extra then
		for k, v in pairs(extra) do
			if table.find(v.games, offsets.MMVersion) then
				fields[#fields + 1] = table.copy(v.data)
			end
		end
	end
end

local function addNamespacePrefixes(data, namespaceStr)
	local data2 = data
	while data2 do
		if data2.struct then
			data2.namespacePrefix = namespaceStr
		end
		data2 = data2.innerType
	end
end

local function definitelyShouldSkipMember(structName, includeMembers, excludeMembers, memberName)
	if (type(includeMembers) == "table" and not table.find(includeMembers, memberName)) or (type(memberName) == "string" and memberName:len() == 0) then -- last check is for dummy names
		return true
	elseif type(excludeMembers) == "table" and table.find(excludeMembers, memberName) or globalExcludes[structName] and table.find(globalExcludes[structName], memberName) then
		return true
	end
	return false
end
--[[
args = table with:
	name - structure/union name
	indentLevel - if omitted, is assumed to be 0
	includeMembers - if is table, only members with names existing in table will be added
	offsets - member offsets (if omitted, will be taken from structs.o.*)
	members - member functions (if omitted, will be taken from structs.m.*)
	class - structure class (if omitted, will be the result of structs.class function call)
	union - structure is union (in MMExt sense)
	prependNamespace - prepend game-specific namespace to member structure names (for example mm8::Item)
	offset - if union, then its calculated offset, else unset (and assumed 0)
	processDependencies - whether to recursively process non-anonymous member structures
	processedStructs - table where all function results will be saved (best to pass same table for each call, that
		way same struct won't be processed more than once)
	structOrder - used for printing structure and dependencies code in correct order - to declare dependency before struct requiring it
	
function returns table with definition lines, array of names of structures it depends on (they also need to be defined),
	calculated size (most useful for mmext unions) and "processedStructs" table (if you were too lazy to pass your own)
]]
local checkInvalidProcessedStructIndex
do
	local expected = {"code", "dependencies", "size", "processedStructs", "staticDefinitionCode", "fields", "groups", "memberInfoData", "functionData", "methods"}
	function checkInvalidProcessedStructIndex(tbl, key)
		if table.find(expected, key) then return end
		error(string.format("Unexpected struct table index %q", key), 2)
	end
end

local processStruct
function processStruct(args)
	-- initialization

	-- default arguments
	args.offset = args.offset or 0
	args.structOrder = args.structOrder or {}
	args.indentLevel = args.indentLevel or 0
	args.processedStructs = args.processedStructs or {}
	local layout = args.layout or {}

	-- locals
	local fields, structureDependencies = {}, {}
	local myNamespaceStr = args.prependNamespace and namespaceStr or ""
	local indentOuter, indentInner = string.rep(INDENT_CHARS, args.indentLevel), string.rep(INDENT_CHARS, args.indentLevel + 1)
	local customFieldSizes = not args.union and getCustomFieldSizes(args.name) or {}
	local staticPtrDeclarationCode, staticConvertToPointerDeclarationCode, staticDefinitionCode = {}, {}, {}
	local offsets, members = args.offsets or structs.o[args.name], args.members or structs.m[args.name]
	local class, rofields = args.class or structs[args.name], args.rofields or {}
	local size = not args.union and class["?size"] or 0
	
	-- after initialization
	-- forward declaration only if structure has 0 size or no members (yes, those exists)
	-- idk if 0 size struct is possible in C++
	if not next(members) or (not args.union and size == 0) then
		local data = {
			code = {
				string.format("%sstruct %s; // 0-size struct, declaration only", string.rep(INDENT_CHARS, args.indentLevel), args.name)
			}, 
			dependencies = {}, 
			size = 0,
			processedStructs = args.processedStructs,
			fields = {},
			functionData = {},
			methods = {}, class = {}, layout = {}
		}
		args.processedStructs[args.name] = data
		table.insert(tget(args, "structOrder"), 1, args.name)
		return setmetatable(data, {__index = invalidIndex})
	end

	addExtraFields(args.name, fields)

	-- get Info{} data
	local infoData, methods
	if not args.union then
		infoData, methods = getStructureMembersInfoData(args.name)
	end
	-- get function data
	local functionData = not args.union and getFunctionsData(class, infoData)

	-- process members
	for mname, f in sortpairs(members) do
		if definitelyShouldSkipMember(args.name, args.includeMembers, args.excludeMembers, mname) then
			goto continue
		end
		local data = getMemberData(args.name, mname, f, offsets, members, class, rofields, customFieldSizes, false)
		local function addArraySizeField()
			if data.array and data.lenP then
				local t = {name = mname .. "_size", offset = data.lenP, size = data.lenA, 
					typeName = commonTypeNamesToCpp["u" .. data.lenA], dataType = types["u" .. data.lenA]}
				t.pascalCaseName = t.name
				table.insert(tget(data, "comments"), string.format("size field offset is 0x%X", data.lenP))
				table.insert(fields, t)
			end
		end
		if data then -- in certain cases member data is unknown or otherwise unavailable to gather
			addNamespacePrefixes(data, myNamespaceStr)
			if args.union and tonumber(data.name) then
				-- array with some fields rearranged, so it can't be indexed with const.* in all cases
				-- TODO: proper handling, like static const translation table
				data.name = "_" .. tostring(data.name)
			end
			-- add pointers for structs which don't really reside at 0 address
			if data.struct and data.offset == 0 then
				table.insert(staticPtrDeclarationCode,
					string.format("%sstatic inline %s%s* const %s = 0;", -- assumes C++17 for static inline const
					indentInner,
					myNamespaceStr,
					data.typeName,
					toCamelCase(data.name))
				)
				findDependencies(data, structureDependencies)
				goto continue
			elseif data.struct and data.size == 0 then -- Merge, PartyLight
				goto continue
			elseif (data.array and data.innerType.convertToPointer) or data.convertToPointer then
				findDependencies(data, structureDependencies)
				if not args.saveToGeneratorDirectory then -- keep normal field only if reverse engineering?
					local f = deepcopyMM(data)
					table.insert(fields, f)
				end
				local arrays, comments, baseData = getArraysCommentsAndBaseData(data)
				local arraysNestedOnly = table.slice(deepcopyMM(arrays), 2)
				local old1 = baseData.name
				baseData.name = toCamelCase(baseData.name)
				local resultTypeAndName = getArrayPointerString(arraysNestedOnly, baseData, true)
				local comment = "" -- "converted to pointer to not break with limits removal scripts"
				comment = comment .. string.format(--[[", ]]"original offset 0x%X (%d decimal)", data.offset, data.offset)
				if #arrays > 0 then
					comment = comment .. string.format(--[[", ]]"element size: 0x%X (%d decimal)", data.innerType.size, data.innerType.size)
				end
				table.insert(staticConvertToPointerDeclarationCode,
					string.format(
						"%sstatic %s; // %s",
						indentInner,
						resultTypeAndName,
						comment
					)
				)
				local old2 = baseData.namespacePrefix
				baseData.namespacePrefix = myNamespaceStr .. args.name .. "::"
				resultTypeAndName = getArrayPointerString(arraysNestedOnly, baseData, true)
				table.insert(staticDefinitionCode, string.format("%s = nullptr;", resultTypeAndName))
				if arrays[1] then
					if not args.saveToGeneratorDirectory then -- if for reverse engineering, add default size field
						addArraySizeField()
					end
					local isPointer = arrays[1].lenA and true or false
					-- size field pointer, getting one (but not pointer) even if original array doesn't have it
					local typeNameWithPtr = isPointer and (commonTypeNamesToCpp["u" .. arrays[1].lenA] .. "*") or commonTypeNamesToCpp.u4
					local fieldName = toCamelCase(mname .. "_size") .. (isPointer and "Ptr" or "")
					local comment = "Offset/size: " -- (isPointer and "pointer to size" or "size field") .. ", set during initialization. Original offset/size: "
					comment = comment .. (
						string.format("0x%X (%d decimal)",
							isPointer and arrays[1].lenP or arrays[1].count,
							isPointer and arrays[1].lenP or arrays[1].count
						)
					)
					table.insert(staticConvertToPointerDeclarationCode,
						string.format("%sstatic %s %s; // %s",
							indentInner,
							typeNameWithPtr,
							fieldName,
							comment
						)
					)
					table.insert(staticDefinitionCode,
						string.format("%s %s = %s;",
							-- prepend namespace here should always be implicitly true because wrapping in header stuff requires it, but whatever
							typeNameWithPtr,
							myNamespaceStr .. args.name .. "::" .. fieldName,
							isPointer and "nullptr" or "0"
						)
					)

					tget(luaData, args.name, baseData.name).sizePtrName = fieldName
				end
				baseData.name, baseData.namespacePrefix = old1, old2
			elseif data.union then
				local res = processStruct{name = data.name:sub(1, 1):lower() .. data.name:sub(2), offsets = data.offsets, members = data.fields, rofields = data.rofields,
					union = true, indentLevel = 0, prependNamespace = args.prependNamespace, offset = data.offset, processedStructs = args.processedStructs, parent = args.name,
					processDependencies = args.processDependencies, structOrder = args.structOrder, shouldProcessDependency = args.shouldProcessDependency, layout = {}}
				data.code, data.size, data.layout = res.code, res.size, res.layout
					-- unions have 0 indent level and this breaks normal structs processed as dependencies
					-- this whole indent system should be probably redone anyways
				-- doesn't work with non-integer key tables
				--multipleInsert(fields, #fields + 1, data)
				table.insert(fields, data)
				mergeArraysShallowCopy(structureDependencies, res.dependencies, true)
			elseif data.replaceWith then
				multipleInsert(fields, #fields + 1, data.replaceWith)
			else
				findDependencies(data, structureDependencies)
				table.insert(fields, data)
				addArraySizeField()
			end
			local convertToPointer = (data.array and data.innerType.convertToPointer) or data.convertToPointer
			if not getBaseTypeField(data, "static") and not convertToPointer then
				size = math.max(size, math.ceil(data.offset + (data.size or 0)))
			end
		end
		::continue::
	end
	table.sort(fields, function(a, b)
		if a.offset ~= b.offset then
			return a.offset < b.offset
		end
		if a.size ~= b.size then
			return a.size > b.size
		end
		return a.name < b.name
	end)
	local code = {}
	code[#code + 1] = indentOuter .. "{"
	if #staticPtrDeclarationCode > 0 then
		table.insert(staticPtrDeclarationCode, "")
	end
	multipleInsert(code, #code + 1, staticPtrDeclarationCode)
	if #staticConvertToPointerDeclarationCode > 0 then
		table.insert(staticConvertToPointerDeclarationCode, "")
	end
	multipleInsert(code, #code + 1, staticConvertToPointerDeclarationCode)
	local currentOffset = -1
	local prevOffset = args.offset or 0 -- for skipping bytes
	local i = 1
	local maxNextOffset = 0
	local debugLines = {}
	local groups = {}
	while true do
		local currentField = fields[i]
		if not currentField then break end
		if not getBaseTypeField(currentField, "static") then
			currentOffset = currentField.offset
			local skip = currentOffset - prevOffset
			skip = skip > 0 and math.floor(skip) or 0 -- bits
			if skip > 0 then
				code[#code + 1] = indentInner .. skipBytesText:format(skip)
				table.insert(layout, {type = "padding", value = skip})
			end
		end
		local members
		local firstIndex = i
		members, i, maxNextOffset = getGroup(fields, currentField, i)
		groups[#groups + 1] = {members = members, firstIndex = firstIndex, maxNextOffset = maxNextOffset}
		local group = processGroup(members, args.indentLevel + 1, not args.union and args.name, not args.union and myNamespaceStr or "", debugLines, layout)
		multipleInsert(code, #code + 1, group)
		prevOffset = maxNextOffset
	end
	if args.union then
		size = math.ceil(maxNextOffset - args.offset) -- ceil is for bits
	else
		local endPadding = size - prevOffset
		if endPadding >= 1 then
			code[#code + 1] = indentInner .. skipBytesText:format(endPadding)
			table.insert(layout, {type = "padding", value = endPadding})
		end
	end
	code[#code + 1] = args.union and string.format("%s} %s;", indentOuter, args.name) or (indentOuter .. "};")
	if args.union then
		table.insert(code, 1, string.format("%sstruct // size: 0x%X, MMExt union", indentOuter, size))
	else
		table.insert(code, 1, string.format("%sstruct %s // size: 0x%X", indentOuter, args.name, size))
	end
	do
		local tmpname = (not args.union and namespaceStr or "") .. args.name -- unions are inline&anonymous struct, so need to check instance of it, not type
		local cppAssert = "%sstatic_assert(sizeof(%s) == 0x%X, \"Invalid \\\"%s\\\" structure size\");"
		code[#code + 1] = cppAssert:format(indentOuter, tmpname, size, tmpname)
	end
	for i, v in ipairs(debugLines) do
		-- even out indentation
		debugLines[i] = v:gsub(INDENT_CHARS:escapeRegex() .. "+", indentOuter)
	end
	multipleInsert(code, #code + 1, debugLines)
	-- unions are not considered structs in many aspects
	if not args.union then
		if args.processDependencies then
			local addDepNames = {}
			for i, name in ipairs(structureDependencies) do
				if not args.processedStructs[name] and (not args.shouldProcessDependency or args.shouldProcessDependency(name)) then
					local passArgs = table.copy(args)
					passArgs.name = name
					local res = processStruct(passArgs)
					--args.processedStructs[name] = {code = depCode, dependencies = depends, size = size} -- args.processedStructs is shared and written to a bit further
					mergeArraysShallowCopy(addDepNames, res.dependencies, true)
				end
			end
			mergeArraysShallowCopy(structureDependencies, addDepNames, true)
		end
		if not args.processedStructs[args.name] then -- unions are inline
			args.processedStructs[args.name] = setmetatable({code = code, dependencies = structureDependencies,
				size = size, staticDefinitionCode = staticDefinitionCode, groups = groups, fields = fields, memberInfoData = infoData,
				functionData = functionData, methods = methods, class = class, layout = layout},
				{__index = invalidIndex}
			)
		end
		-- structure needs to be after all of its dependencies
		local maxI = 0
		for i, name in ipairs(args.structOrder) do
			if table.find(structureDependencies, name) then
				maxI = i
			end
		end
		table.insert(args.structOrder, math.min(#args.structOrder + 1, maxI + 1), args.name)
	end
	return setmetatable(args.processedStructs[args.name] or {code = code, dependencies = structureDependencies, size = size,
		processedStructs = args.processedStructs, groups = groups, fields = fields, memberInfoData = infoData,
		functionData = functionData, methods = methods, class = class, layout = layout}, {__index = invalidIndex})
end

local function processAll(args)
	local processed = {}
	args = args or {}
	args.indentLevel = args.indentLevel or 0
	table.copy({name = "GameStructure", processDependencies = true,
		prependNamespace = true, processedStructs = processed
	}, args, true)
	local t = processStruct(args)
	local old = args.name
	args.name = "Button" -- npc dialog item
	do local x = structs.Button end -- generate data (__index)
	t = processStruct(args)
	args.name = old
	return processed
end

-- saveToGeneratorDirectory - whether it's for my project (true) or for reverse engineering purposes (false)
-- isLast if it's last of 3 games processed
function printStruct(name, includeMembers, excludeMembers, indentLevel, saveToGeneratorDirectory, isLast, directoryPrefix) 
	luaData = {}
	indentLevel = indentLevel or 1 -- always 1 indentation level if wrapping
	local args = {name = name, includeMembers = includeMembers, excludeMembers = excludeMembers, indentLevel = indentLevel, saveToGeneratorDirectory = saveToGeneratorDirectory}
	local processed = processAll(args)
	_G.processed, _G.args = processed, args
	local pathToLoad = "C:\\Users\\Eksekk\\code.bin"
	local oldCode
	local ok, fileContent = pcall(io.load, pathToLoad)
	if ok then
		ok, oldCode = pcall(internal.unpersist, fileContent)
	end
	local code = ok and oldCode or {}
	-- for i, name in ipairs(args.structOrder) do
	-- 	structureByFile[name] = {name} -- hack to help with doxygen
	-- end
	local usedFiles = {}
	for i, name in ipairs(args.structOrder) do
		local struct = processed[name]
		setmetatable(struct.code, nil) -- just in case
		local fileName = getStructFile(name)
		code[fileName] = code[fileName] or {header = {}, source = {}, includes = {}}
		local currentCode = code[fileName]
		if not table.find(usedFiles, fileName) then
			multipleInsert(currentCode.header, #currentCode.header + 1, {
				"namespace mm" .. Game.Version,
				"{"
			})
			table.insert(usedFiles, fileName)
		end
		currentCode.header = table.join(currentCode.header, struct.code)
		multipleInsert(currentCode.header, #currentCode.header + 1, {
			"",
			"",
			""
		})
		if struct.staticDefinitionCode and #struct.staticDefinitionCode > 0 then
			currentCode.source = table.join(currentCode.source, struct.staticDefinitionCode)
			table.insert(currentCode.source, "")
		end
		for i, v in ipairs(struct.dependencies) do
			local depFileName = getStructFile(v)
			if not table.find(currentCode.includes, depFileName) and depFileName ~= fileName then
				table.insert(currentCode.includes, depFileName)
			end
		end
	end
	for fname, _ in pairs(structureByFile) do
		if code[fname] then
			local header = code[fname].header
			for i = 1, 3 do
				table.remove(header, #header)
			end
		end
	end
	--code = table.join(code, processed[name].code)
	--io.save("structs.h", table.concat(code, "\n"))
	for i, fileName in ipairs(usedFiles) do
		local currentCode = code[fileName]
		multipleInsert(currentCode.header, #currentCode.header + 1, {
			"}"
		})
	end
	if not isLast then
		io.save(pathToLoad, internal.persist(code))
	else
		if saveToGeneratorDirectory then
			os.remove("C:\\Users\\Eksekk\\source\\repos\\PGenEdit\\PGenEditDLL\\headers\\structs")
			os.remove("C:\\Users\\Eksekk\\source\\repos\\PGenEdit\\PGenEditDLL\\sources\\structs")
		else
			for p in path.find("C:\\Users\\Eksekk\\structOffsets\\*") do
				if not mem.dll.shlwapi.PathIsDirectoryA(p) then
					os.remove(p)
				end
			end
		end
		os.remove("C:\\Users\\Eksekk\\code.bin")
		for fileName in pairs(code) do
			local currentCode = code[fileName]
			local includeCode = {}
			for i, v in ipairs(currentCode.includes) do
				table.insert(includeCode, string.format("#include \"%s.h\"", v))
			end
			local prefix = {
				"#pragma once",
				"#include \"pch.h\"",
				"#include \"main.h\"",
			}
			if not saveToGeneratorDirectory then -- all header includes are in pch.h
				multipleInsert(prefix, #prefix + 1, includeCode)
			end
			multipleInsert(prefix, #prefix + 1, {
				"",
				"#pragma pack(push, 1)",
				"",
			})
			multipleInsert(currentCode.header, 1, prefix)
			multipleInsert(currentCode.header, #currentCode.header + 1, {
				"",
				"#pragma pack(pop)"
			})
			local headerFileName, sourceFileName
			if saveToGeneratorDirectory then
				headerFileName = string.format("C:\\Users\\Eksekk\\source\\repos\\PGenEdit\\PGenEditDLL\\headers\\structs\\%s.h", fileName)
				sourceFileName = string.format("C:\\Users\\Eksekk\\source\\repos\\PGenEdit\\PGenEditDLL\\sources\\structs\\%s.cpp", fileName)
			else
				headerFileName = string.format("%s\\MM%d\\%s.h", directoryPrefix or "C:\\Users\\Eksekk\\structOffsets", Game.Version, fileName)
				sourceFileName = string.format("%s\\MM%d\\%s.cpp", directoryPrefix or "C:\\Users\\Eksekk\\structOffsets", Game.Version, fileName)
			end
			local luaDataFileName = "C:\\Users\\Eksekk\\source\\repos\\PGenEdit\\luaData.cpp"
			io.save(headerFileName, table.concat(currentCode.header, "\n"))
			if #currentCode.source > 0 and saveToGeneratorDirectory then
				local prefix = {
					"#pragma once",
					"#include \"pch.h\"",
					"#include \"main.h\"",
				}
				multipleInsert(prefix, #prefix + 1, includeCode)
				table.insert(prefix, "")
				multipleInsert(currentCode.source, 1, prefix)
				io.save(sourceFileName, table.concat(currentCode.source, "\n"))
			end
			-- ptrName
			--tget(luaData, args.name, baseData.name).sizePtrName
			if saveToGeneratorDirectory then
				local content = {}
				for sname, fields in pairs(luaData) do
					for fname, field in pairs(fields) do
						local s = ""
						if field.ptrName then
							s = s .. string.format(", pointer name: %q", stripNamespaces(field.ptrName))
						end
						if field.sizePtrName then
							s = s .. string.format(", size field/pointer name: %q", stripNamespaces(field.sizePtrName))
						end
						table.insert(content, string.format("// struct %q, field name %q%s", stripNamespaces(sname), stripNamespaces(fname), s))
					end
				end
				io.save(luaDataFileName, table.concat(content, "\n"))
			else
				io.save(headerFileName:replace(fileName, "pch"), table.concat({
					"#pragma once"
				}, "\r\n"))
				io.save(headerFileName:replace(fileName, "main"), table.concat({
					"#pragma once",
					"#define JOIN(a, b) a ## b",
					"#define JOIN2(a, b) JOIN(a, b)",
					"#define SKIP(bytes) uint8_t JOIN2(unknown_, __COUNTER__)[bytes]",
					'#define SKIPBITS(bits) static_assert(bits <= 8, "Bit amount cannot be higher than 8 because MSVC compiler will not pack bitfields properly"); \\',
					"bool : bits // name is optional",
					"#include <array>",
					"#include <cstdint>",
				}, "\r\n"))
			end
		end
	end
end

function pr(str)
	reload();printStruct(str, nil, nil, nil, false, true)
end

function pr2(str)
	printStruct("GameStructure", nil, nil, nil, false, true)
end

function pr3(isLast)
	printStruct("GameStructure", nil, nil, nil, false, isLast)
end

-- adding most information from lua to x64dbg database

do
	-- these are structs which only exist one at a time, at fixed offset, so their fields can be directly labelled
	local singleInstanceStructs = {GameStructure = "Game", GameParty = "Party", GameMap = "Map", GameMouse = "Mouse", GameScreen = "Screen", Arcomage = "Arcomage",
		GameRaces = "Races", GameClasses = "Classes", GameClassKinds = "ClassKinds", Weather = "Weather", DialogLogic = "DialogLogic", SpritesLod = "SpritesLod",
		BitmapsLod = "BitmapsLod", IconsLod = "IconsLod"}
	-- some are created at offset other than 0
	local singleInstanceCustomOffsets = {GameMouse = Mouse["?ptr"], GameScreen = Screen["?ptr"], BitmapsLod = Game.BitmapsLod["?ptr"], 
		IconsLod = Game.IconsLod["?ptr"], SpritesLod = Game.SpritesLod["?ptr"]}
	local commonTypes = {[types.u1] = "u1", [types.u2] = "u2", [types.u4] = "u4", [types.u8] = "u8", [types.i1] = "i1", [types.i2] = "i2", [types.i4] = "i4",
		[types.i8] = "i8", [types.r4] = "r4", [types.r8] = "r8", [types.r10] = "r10", [types.pchar] = "PChar", [types.b1] = "b1", [types.b2] = "b2",
		[types.b4] = "b4", [types.EditPChar] = "EditPChar", [types.EditConstPChar] = "EditConstPChar"}
	local format = string.format
	local json = require"json"

	local function structureMemberStr(structName, mname, dot)
		return format(dot and "%s.%s" or "%s::%s", structName, mname)
	end

	local function getModuleOffset(offset, structName, mname)
		local offset2 = offset - 0x400000
		if offset2 < 0 then
			printf("%q : offset is less than 0x400000", structureMemberStr(structName, mname))
			return offset
		end
		return offset2
	end

	local function getArrayStr(arrays)
		local str = ""
		local hasPtr
		for i, arr in ipairs(arrays) do
			if arr.ptr then
				if hasPtr then
					error("Two pointers in array series", 2)
				elseif i ~= 1 then
					error("Pointer to array not at first level", 2)
				end
				hasPtr = true
			end
			if arr.count == 0 then
				str = str .. "[]"
			else
				str = str .. format("[%d]", arr.originalBitCount or arr.count)
			end
		end
		return str, hasPtr
	end

	-- https://x64dbg.com/blog/2016/12/04/type-system.html
	-- https://gist.github.com/mrexodia/e949ab26d5986a5fc1fa4944ac68147a#file-types-json
	local mmextToX64Dbg = {
		[types.i1] = "char",
		[types.i2] = "short",
		[types.i4] = "int",
		[types.i8] = "long long",
		[types.u1] = "unsigned char",
		[types.u2] = "unsigned short",
		[types.u4] = "unsigned int",
		[types.u8] = "unsigned long long",
		[types.b1] = "unsigned char",
		[types.b2] = "unsigned short",
		[types.b4] = "unsigned int",
		[types.r4] = "float",
		[types.r8] = "double",
		[types.EditPChar] = "char*",
		[types.EditConstPChar] = "char*",
		[types.PChar] = "const char*",
		[types.string] = "char", -- there's no "inline string" type :(
	}

	local function doPrimitive(data)
		local typ = mmextToX64Dbg[data.dataType] or (data.struct and data.typeName)
		if typ then
			return {
				type = typ,
				name = data.pascalCaseName,
			}
		elseif data.bit then -- skip
			return false
		end
		error("Unknown type", 2)
	end

	local function noInfinity(amount) -- structs.Fnt
		if math.abs(amount) ~= 1/0 then
			return amount
		end
		return 256
	end

	function processDebuggerDatabase(removeOld) -- remove old for testing
		local database = json.decode(io.load(format("mm%d.exe.dd32", Game.Version)))
		local labelsByAddress = {}
		if not removeOld then
			for i, label in ipairs(database.labels) do
				labelsByAddress[label.address] = label
			end
		end
		local processed = processAll()
		_G.processed = processed
		-- hack to process also icons lod (it's really bitmaps lod struct, not its own type, so loop below wouldn't catch it)
		processed.IconsLod = processed.BitmapsLod
		local moduleStr = format("mm%d.exe", Game.Version)
		local defs = {structs = {}, unions = {}}
		local done = {} -- some functions have two names and only one has extra info
		-- store done here and if old doesn't have sig or has less arguments, overwrite
		local logLines = {}
		local function printf(...) -- replace with temporary version to automatically save to log file
			logLines[#logLines + 1] = string.print(string.format(...))
			_G.printf(...)
		end
		local structIndex = 0 -- anonymous struct index for, well, anonymous structs/unions
		for structName, structData in pairs(processed) do
			local singleName = singleInstanceStructs[structName]
			-- TODO: if single instance, add labels recursively - for example Mouse.Item
			if singleName then -- single instance - add all fields at fixed offset
				for _, data in ipairs(structData.fields) do
					local arrays, comments, baseData = getArraysCommentsAndBaseData(data)
					local mname = data.pascalCaseName
					if baseData.struct and singleInstanceStructs[baseData.typeName] then
						printf("%q : skipping, single instance struct as member", structureMemberStr(singleName, mname, true))
						goto continue
					end
					data.offset = data.offset + (singleInstanceCustomOffsets[structName] or 0)
					local moduleOffset = getModuleOffset(data.offset, singleName, mname)
					if data.offset > 0x1500000 then
						printf("%q : member has too high address (0x%X). It could be dynamically assigned. Skipping", structureMemberStr(singleName, mname), data.offset)
						goto continue
					end
					-- TODO: deal with alts and duplicated names
					if labelsByAddress[moduleOffset] then
						printf("%q : label at address 0x%X already exists (text: %q). Skipping", structureMemberStr(singleName, mname),
							data.offset, labelsByAddress[moduleOffset].text)
						goto continue
					end
					local label = {
						module = moduleStr,
						address = format("0x%X", moduleOffset),
						manual = false, -- just in case
					}
					local text = format("%s.%s (%%s)", singleName, mname)
					local arrayStr, hasPtr = getArrayStr(arrays)
					local ptrString = hasPtr and "->" or ""
					local commonStr = commonTypes[baseData.dataType]
					if baseData.unknownType and arrays[1].size > 0 then -- if custom type, innermost size is always nonzero (u1), real size is array element count
						printf("%q : unknown type member labelled because of nonzero size", structureMemberStr(singleName, mname))
					elseif commonStr and not baseData.unknownType then
						text = text:format(ptrString .. commonStr .. arrayStr)
					elseif baseData.dataType == types.string then
						text = text:format(format("%sstring%s", ptrString, arrayStr))
					elseif baseData.struct then
						text = text:format(format("%s%s%s", ptrString, baseData.typeName, arrayStr))
					elseif baseData.bit and not baseData.bitValue then -- only bit arrays, because x64dbg doesn't support plain bits
						text = text:format(ptrString .. (baseData.anti and "abit" or "bit") .. arrayStr)
					else
						printf("%q : unknown type, skipping", structureMemberStr(singleName, mname))
						goto continue
					end
					labelsByAddress[moduleOffset] = label
					label.text = text
					::continue::
				end
			else -- multi instance - add dedicated type for inspection
				local function getJsonForMember(data)
					local arrays, comments, baseData = getArraysCommentsAndBaseData(data)
					if #arrays == 0 then
						return doPrimitive(baseData)
					elseif #arrays == 1 and not arrays[1].ptr and arrays[1].count > 0 then -- not pointer, not variable size
						if baseData.bit then
							local t = {
								name = baseData.name,
								type = mmextToX64Dbg.u1,
								arrsize = noInfinity(arrays[1].size) --/ 8, -- shrink array 8-fold and set base data type to u1
							}
							assert(t.arrsize % 1 == 0)
							return t
						end
						local json = doPrimitive(baseData)
						json.arrsize = noInfinity(arrays[1].count)
						return json
					else -- #arrays >= 2 or #arrays == 1 and (arrays[1].ptr or arrays[1].count == 0)
						-- define inner arrays
						local sname, isPlain
						if baseData.bit then -- again shrink and set type, this time last array
							local a = arrays[#arrays]
							local count = noInfinity(a.size) --/ 8
							assert(count % 1 == 0)
							a.size = count
							a.count = count
							sname = mmextToX64Dbg.u1
						else
							isPlain = mmextToX64Dbg[baseData.dataType] and true or false
							sname = baseData.struct and baseData.typeName or mmextToX64Dbg[baseData.dataType]
						end
						for arrid = 1, #arrays do -- if not ptr, base array can be done with arrsize
							-- ->u1[5][5]
							local arr = arrays[arrid]
							if arr.count == 0 then -- replace with pointer
								sname = sname .. "*"
							else
								local sname2 = format("%s[%d]", sname, noInfinity(arr.count))
								if not table.findIf(defs.structs, function(s) return s.name == sname2 end) then
									table.insert(defs.structs, {
										name = sname2,
										members = {
											{
												type = sname, -- also struct has version added a bit above
												name = "value",
												arrsize = noInfinity(arr.count)
											}
										}
									})
								end
								sname = sname2
							end
						end
						-- here add prefix???

						return {
							type = sname,
							name = baseData.pascalCaseName,
							arrsize = not arrays[1].ptr and arrays[1].size > 0 and arrays[1].count or nil
						}
					end
				end
				local paddingIndex = 0
				local function doPadding(size)
					local p = {
						name = "padding_" .. paddingIndex,
						type = mmextToX64Dbg[types.u1],
						arrsize = size
					}
					paddingIndex = paddingIndex + 1
					return p
				end
				local doStructUnion
				function doStructUnion(struct, name, isUnion)
					local json = {
						name = name or ((isUnion and "U" or "S") .. "_" .. structIndex),
						members = {}
					}
					structIndex = structIndex + 1
					local pad = 0
					local function maybePadding()
						if pad > 0 then
							table.insert(json.members, doPadding(math.ceil(pad)))
							pad = 0
						end
					end
					for i, v in ipairs(struct) do
						local what, value = v.type, v.value
						if what == "padding" then
							pad = pad + value
						elseif what == "member" then
							if value.bit then
								pad = pad + 0.125
							else
								maybePadding()
								local memberJson = getJsonForMember(value)
								table.insert(json.members, memberJson)
							end
						elseif what == "struct" or what == "union" then
							maybePadding()
							local structJson = doStructUnion(value, nil, what == "union")
							table.insert(json.members, {
								name = structJson.name,
								type = structJson.name,
							})
						else
							error(format("Unknown layout element %q", what))
						end
					end
					maybePadding()
					table.insert(isUnion and defs.unions or defs.structs, json)
					return json
				end
				doStructUnion(structData.layout, assert(structName), false)
			end
			-- functions

			-- obsolete TODO: because "define.class.AddHitPoints" doesn't use "method{}" call, it's not considered a method and thus
			-- overwrites "AddHP()" with two argument parentheses
			-- fixed by adding condition to not replace label if I don't have info data and other one has
			for fname, data in pairs(structData.functionData) do
				local def = data.def
				local isMethod = structData.methods and structData.methods[fname]
				-- exception for party struct
				if structName == "GameParty" and structData.class.ptr and def[1] == structData.class.ptr then
					isMethod = true
				end
				local moduleOffset = getModuleOffset(def.p, singleName or structName, fname)
				local str = (singleName or structName) .. (isMethod and "::" or ".") .. fname
				local argCount = math.max(#def, def.must) - (isMethod and 1 or 0)
				local sig = data.info and data.info.Sig
				if sig then
					str = str .. format("(%s)", sig)
				else
					--printf("%q : missing signature", format("%s::%s()", singleName or structName, fname))
					local tab = {}
					for i = 1, argCount do
						tab[#tab + 1] = "?"
					end
					str = str .. format("(%s)", table.concat(tab, ", "))
				end
				str = "__" .. assert(select(def.cc + 1, "stdcall", "thiscall", "fastcall", "fastcall+eax"), dump(def)) .. " " .. str
				local label = {
					module = moduleStr,
					address = format("0x%X", moduleOffset),
					manual = false, -- just in case
					text = str
				}
				local otherDone = done[moduleOffset]
				if labelsByAddress[moduleOffset] then
					 -- replace BitmapsLod and SpritesLod with base Lod where possible
					if otherDone and not (otherDone.info and not data.info) and not table.find({"BitmapsLod", "SpritesLod"}, structName) and ( -- [I don't have info, other does] -> skip
						(structName == "Lod")
						or otherDone.info == false -- explicitly set to false to disable (misspelling etc.)
						or (not otherDone.info and data.info) -- I have info, other doesn't
						or ((not otherDone.info or not otherDone.info.Sig) and data.info and data.info.Sig) -- I have sig, other doesn't
						or (argCount > otherDone.arg)) -- I have more arguments
					then
						printf("Replacing %q (sig: %s, arg: %d) with %q (sig: %s, arg: %d)",
							structureMemberStr(otherDone.structName, otherDone.name) .. "()", otherDone.info and otherDone.info.Sig and true or false, otherDone.arg,
							structureMemberStr(singleName or structName, fname) .. "()", data.info and data.info.Sig and true or false, argCount
						)
					else
						printf("%q : label at address 0x%X already exists (text: %q)", format("%s::%s", singleName or structName, fname),
							def.p, labelsByAddress[moduleOffset].text)
						goto continueF
					end
				end
				done[moduleOffset] = {info = data.info, arg = argCount, name = fname, structName = singleName or structName}
				labelsByAddress[moduleOffset] = label
				::continueF::
			end
		end
		io.save(moduleStr .. " json type definitions.json", json.encode(defs))
		local labels = {}
		for k, v in sortpairs(labelsByAddress) do
			labels[#labels + 1] = v
		end
		database.labels = labels
		io.save(format("processed %s.dd32", moduleStr), json.encode(database))
		io.save("debugger database log.txt", table.concat(logLines, "\r\n"))
	end
	pdd = processDebuggerDatabase
end




-- "ENUM" GENERATOR
local namePrefixes = {["Stats"] = "STAT", ["Skills"] = "SKILL", ["Damage"] = "DMG"}
local consts, header, source = {}, {}, {}
function processConst(name)
	if not consts[6] then
		consts[Game.Version] = const
		for _, i in ipairs{6, 7 ,8} do
			if i ~= Game.Version then
				local f, err = loadfile((DevPath or AppPath) .. "Scripts/Core/ConstAndBits.lua")
				if not f then
					print(err)
					goto continue
				end
				local o = table.copy(offsets)
				o.MMVersion = i
				local env = {
					offsets = o,
					select = select,
					mem = mem,
					pairs = pairs,
					internal = {MMVersion = Game.Version},
					string = string,
					setmetatable = setmetatable,
					table = table
				}
				setfenv(f, env)
				f()
				consts[i] = env.const
				::continue::
			end
		end
	end
	local prefix = namePrefixes[name]
	
	-- header
	
	local allKeys = {}
	for i, const in pairs(consts) do
		for v, k in sortpairs(table.invert(const[name])) do
			if not table.find(allKeys, k) then
				allKeys[#allKeys + 1] = k
			end
		end
	end
	local function formatName(name)
		name = name:gsub("([a-z])([A-Z0-9])", "%1_%2")
		name = prefix .. "_" .. name:upper()
		return name
	end
	local forwardDecl = {"extern int"}
	for i, k in ipairs(allKeys) do
		table.insert(forwardDecl, "\t" .. formatName(k) .. (i == #allKeys and ";" or ","))
	end
	table.insert(forwardDecl, "") -- becomes newline after concat
	for _, i in ipairs{6, 7, 8} do
		table.insert(forwardDecl, string.format("extern void makeEnum%s_%d();", name, i))
	end
	multipleInsert(header, #header + 1, forwardDecl)
	table.insert(header, "")
	
	-- source
	
	source[#source + 1] = "int "
	local last = allKeys[#allKeys]
	for _, k in ipairs(allKeys) do
		table.insert(source, string.format("\t%s = INVALID_ID%s", formatName(k), k == last and ";" or ","))
	end
	table.insert(source, "")
	
	for _, i in ipairs{6, 7, 8} do
		table.insert(source, string.format("void makeEnum%s_%d()", name, i))
		table.insert(source, "{")
		for v, k in sortpairs(table.invert(consts[i][name])) do
			table.insert(source, string.format("\t%s = %d;", formatName(k), v))
		end
		
		table.insert(source, "}")
		table.insert(source, "")
	end
	table.insert(source, "")
end

local constsToProcess = {"Damage"}
function writeConsts()
	for _, const in ipairs(constsToProcess) do
		processConst(const)
	end
	io.save("constHeader.h", table.concat(header, "\n"))
	io.save("constSource.cpp", table.concat(source, "\n"))
	header, source = {}, {}
end