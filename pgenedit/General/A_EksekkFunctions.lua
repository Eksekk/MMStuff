local format = string.format

function universalEnum(t, array, unlimitedElementAmount)
	local meta = type(t) == "table" and getmetatable(t)
	local c = {}
	local i = 0
	for k, v in unpack(not meta and {(array and ipairs or pairs)(t or {})} or meta.members and {structs.enum(t)} or
		meta.__call and type(meta.__call) == "function" and {t} or {(array and ipairs or pairs)(t or {})}) do
		c[k] = v
		i = i + 1
		if i == 100000 and not unlimitedElementAmount then
			error("Infinite loop or more than 100000 elements (pass true as third argument to override)", 2)
		end
	end
	local key = array and (c[0] ~= nil and 0 or 1) or (next(c))
	return function()
		local v = c[key]
		if v ~= nil then
			local r1, r2 = key, v
			key = array and key + 1 or (next(c, key))
			return r1, r2
		end
	end
end

-- for k, v in universalEnum(Map.Facets) do print(k, v) end

function equalArrays(t1, t2)
	if #t1 ~= #t2 then return false end
	for i, v in universalEnum(t1, true) do
		if t2[i] ~= v then
			return false
		end
	end
	return true
end

table.findarray = function(t, a)
	for i, v in ipairs(t) do
		if type(v) == "table" and equalArrays(v, a) then
			return i
		end
	end
end

dofile("C:\\Users\\Eksekk\\Documents\\GitHub\\MMStuff\\F_EditorEnhancements.lua")

local fileNameByMapName = {}
local fileNames = {}
function events.GameInitialized2()
	for _, msi in Game.MapStats do
		fileNameByMapName[msi.Name:lower()] = msi.FileName:lower()
		table.insert(fileNames, msi.FileName:lower())
	end
end

function mtm(str, x, y, z)
	-- show error instead of crashing game
	local s1, s2 = path.setext(str:lower(), ".odm"), path.setext(str:lower(), ".blv")
	local zero = not str or str:match("^0")

	--assert(mapFileNamesToNames[s1] or table.find(fileNames, s1), "Invalid map name")
	return evt.MoveToMap{Name = assert(
		fileNameByMapName[str:lower()]
		or fileNameByMapName["the " .. str:lower()]
		or fileNames[table.find(fileNames, s1)]
		or fileNames[table.find(fileNames, s2)]
		or zero and "0",
		"Invalid map name"),
		X = x or nil,
		Y = y or nil,
		Z = z or nil,
	}
end

function kill(includeFriendly)
	for k, v in Map.Monsters do
		if includeFriendly or v.Hostile then
			v.HP = 0
		end
	end
end

local mapIdsToItemNames = {}

local invItemType = table.invert(const.ItemType)

function events.GameInitialized2()
	for i, entry in Game.ItemsTxt do
		local stat = entry.EquipStat + 1
		table.insert(tget(mapIdsToItemNames, entry.Name:lower()), {id = i, typeName = invItemType[stat]:lower()})
	end
end

function item(what, typ, props)
	local item
	if type(what) == "number" then
		item = what
	else
		local find = table.findIf(mapIdsToItemNames[what:lower()] or {}, function(data)
			if not typ then return true end
			if data.typeName:find(typ:lower(), nil, true) then
				return true
			end
		end)
		if find then
			item = mapIdsToItemNames[what][find].id
		end
	end
	if not item then
		error(string.format("Couldn't find item %q", what) .. (typ and string.format(", type %q", typ) or ""))
	end
	evt.GiveItem{Id = item}
	for k, v in pairs(props or {}) do
		Mouse.Item[k] = v
	end
end

-- gives ring with spc bonus with "NameAdd" matching provided text
function spcBonus(what)
	what = what:lower()
	for i, spc in Game.SpcItemsTxt do
		if spc.NameAdd:lower():match(what) then
			evt.GiveItem{Type = const.ItemType.Ring, Strength = 5}
			Mouse.Item.Bonus = 0
			Mouse.Item.Bonus2 = i + 1
			Mouse:ReleaseItem()
			return true
		end
	end
	error(string.format("%q doesn't match any NameAdd", what))
end

function increaseSpawnsInMapstats(infile, outfile, s, e, howMuch)
	local t = LoadBasicTextTable(infile, 0)
	for i = s, e do
		local index = i + 3
		local row = t[index]
		for j = 20, 28, 4 do
			local min, max = row[j]:match("(%d+)%-(%d+)")
			min = tonumber(min) or 0
			max = tonumber(max) or 0
			if max - min <= 0 then goto continue end
			min = min + howMuch
			max = max + howMuch
			row[j] = " " .. min .. "-" .. max
			::continue::
		end
	end
	WriteBasicTextTable(t, outfile)
end

function idm(pl, level, mastery)
	Party[pl].Skills[const.Skills.IdentifyMonster] = JoinSkill(level, mastery)
end

function deepcopyMM(t)
	local copy = {}
	if type(t) == "table" then -- only tables are passed by reference, and thus need copying
		local meta = getmetatable(t)
		local function copyRow(k, v)
			if type(v) == "table" then
				local meta = getmetatable(v)
				copy[k] = {}
				if meta and meta.members then
					for k2, v2 in structs.enum(v) do
						copy[k][k2] = (type(v2) == "table" and deepcopyMM(v2) or v2)
					end
				elseif meta and meta.__call and type(meta.__call) == "function" then
					for k2, v2 in v do
						copy[k][k2] = (type(v2) == "table" and deepcopyMM(v2) or v2)
					end
				else
					for k2, v2 in pairs(v) do
						copy[k][k2] = (type(v2) == "table" and deepcopyMM(v2) or v2)
					end
				end
			else
				copy[k] = v
			end
		end
		if meta and meta.members then
			for k2, v2 in structs.enum(t) do
				copy[k2] = (type(v2) == "table" and deepcopyMM(v2) or v2)
			end
		elseif meta and meta.__call and type(meta.__call) == "function" then
			for k, v in t do
				copyRow(k, v)
			end
		else
			for k, v in pairs(t) do
				copyRow(k, v)
			end
		end
		return copy
	else
		return t
	end
end

function multipleInsert(t, index, ...)
	local v = {...}
	if #v == 1 and type(v[1]) == "table" then
		v = v[1]
	end
	local shift = #v
	for i = #t, index, -1 do
		t[i + shift] = t[i]
	end
	for i = 1, #v do
		t[index + i - 1] = v[i]
	end
	return t
end

function getLocals(lev)
	lev = lev + 1 -- because current function call effectively reduces supplied stack level by 1
	local i = 1
	assert(debug.getinfo(lev, "f"), "Invalid stack level")
	local t = {}
	while true do
		local name, value = debug.getlocal(lev, i)
		if not name then break end
		t[name] = value
		i = i + 1
	end
	return t
end

getLs = getLocals

function dumpLocals(lev)
	lev = lev + 1
	for k, v in pairs(getLocals(lev)) do
		print(k, v)
	end
end

dumpL = dumpLocals

function findLocal(lev, name)
	lev = lev + 1
	local locals = getLocals(lev)
	if locals[name] ~= nil then
		return name, value
	end
end

findL = findLocal

function setLocal(lev, name, value)
	lev = lev + 1
	local i = 1
	local updateIndex -- set local with highest index (the "most local" one), since we return it in get and dump functions
	assert(debug.getinfo(lev, "f"), "Invalid stack level")
	while true do
		local localName = debug.getlocal(lev, i)
		if not localName then break end
		if localName == name then
			updateIndex = i
		end
		i = i + 1
	end
	if updateIndex then
		debug.setlocal(lev, updateIndex, value)
		return true
	end
	return false
end

setL = setLocal

function setLocalsTable(lev)
	LOCALS = deepcopyMM(getLocals(lev + 1))
end

setLT = setLocalsTable

function setLocalsTableAndDump(lev)
	lev = lev + 1
	locals = getLocals(lev)
	LOCALS = deepcopyMM(locals)
	for k, v in pairs(locals) do
		print(k, v)
	end
end

function table.findIf(t, func)
	for k, v in pairs(t) do
		if func(v, k) then
			return k, v
		end
	end
end

function table.map(t, func)
	local out = {}
	for k, v in pairs(t) do
		out[k] = func(v, k)
	end
	return out
end

function table.foreach(t, func)
	for k, v in pairs(t) do
		func(v, k)
	end
end

function table.filterFunc(t, func) -- filter is taken by merge
	local out = {}
	for k, v in pairs(t) do
		if func(v, k) then
			out[k] = v
		end
	end
	return out
end

function table.reduce(t, func)
	local val = t[1]
	for i = 2, #t do
		val = func(val, t[i])
	end
	return val
end

function table.slice(tbl, first, last)
	local n = #tbl
	local tableFirstIndex = tbl[0] ~= nil and 0 or 1
	first = first or tableFirstIndex
	last = last or math.max(n, first)
	local orig1, orig2 = first, last
	if first < 0 then
		first = n + first + 1
	end
	if last < 0 then
		last = n + last + 1
	end
	if first < tableFirstIndex or first > last then
		error(string.format("bad index values [%d, %d] (table size: %d)", orig1, orig2, n), 2)
	end
	local t = {}
	for i = first, last do
		t[i - first + 1] = tbl[i]
	end
	return t
end

function mergeArraysShallowCopy(t1, t2, inplace) -- handles duplicate keys
	local tt = inplace and t1 or table.copy(t1)
	for i, v in ipairs(t2) do
		if not table.find(tt, v) then
			tt[#tt + 1] = v
		end
	end
	return tt
end

function getUpvalue(f, name, ...)
	local n, v = debug.findupvalue(f, name)
	if select("#", ...) > 0 then
		return getUpvalue(v, ...)
	else
		return v
	end
end

function upvalueDump(f) -- dump() doesn't work
	for k, v in debug.upvalues(f) do
		print(k, v)
	end
end

function getUpvalueByValue(f, val)
	for k, v in debug.upvalues(f) do
		if v == val then
			return k, v
		end
	end
end

function setUpvalue(f, name, val)
	local i, oldVal = debug.findupvalue(f, name)
	assert(i, format("Provided function has no upvalue named %q", name))
	debug.setupvalue(f, i, val)
	return oldVal
end

dumpUpvalues = upvalueDump
getU = getUpvalue
getUbyV = getUpvalueByValue
dumpU = dumpUpvalues
MT = debug.getmetatable or getmetatable
setU = setUpvalue

function printSortedConst(c)
	for v, k in sortpairs(table.invert(c)) do
		print(k, v)
	end
end

function debugTable(tbl, dumpDepth) -- makes table print its contents in stacktrace instead of "(table: 0x0ff488f8)"
	local mt = getmetatable(tbl) or {}
	if not mt.__tostring then
		function mt.__tostring(t)
			local tostr = rawget(getmetatable(t), "__tostring")
			rawset(getmetatable(t), "__tostring", nil) -- avoid infinite recursion
			local ret = dump(t, dumpDepth)
			rawset(getmetatable(t), "__tostring", tostr)
			return ret
		end
	end
	setmetatable(tbl, mt)
end

function vertexLoc()
	local f = F()
	if not f then print"No facet pointed at"; return end
	for i, id in f.VertexIds do print(id, XYZ(Map.Vertexes[id])) end
end

local function indentCount(str)
	str = str:match("(%s*).-") -- get whitespace at beginning
	str = str:gsub("    ", "\t") -- replace sequences of four spaces with tabs
	str = str:gsub(" ", "") -- remove all other spaces
	local count
	str, count = str:gsub("\t", "\t") -- get tab count
	return count
end

function string.trim(text)
	return (text:match("^%s*(.-)%s*$")) or ""
end

function string.trimNewlines(text)
	return (text:match("^\n*(.-)\n*$")) or ""
end

function string.escapeRegex(text)
	return (text:gsub("(%W)", "%%%1"))
end

function string.escapeRegexNoPercent(text)
	return (text:gsub("([^%w%%])", "%%%1"))
end

function printf(...)
	return print(string.format(...))
end

function string.escapeForFormat(text)
	return (text:gsub("(%%)", "%%%1"))
end

-- replace given pattern, correctly dealing with differing indent
function string.replaceIndent(text, replaceWhat, replacement)
	-- split text and replacement into lines and check if first text line is found
	local linesText, linesReplaceWhat, linesReplacement = text:trimNewlines():split("\n"), replaceWhat:trimNewlines():split("\n"), replacement:trimNewlines():split("\n")
	--[[for k, v in pairs{text = text, replaceWhat = replaceWhat, replacement = replacement} do
		local r, rn, n
		_, r = v:gsub("\r", "\r")
		_, rn = v:gsub("\r\n", "\r\n")
		_, n = v:gsub("\n", "\n")
		--printf("%s: R: %d, RN: %d, N: %d", k, r, rn, n)
	end]]
	assert(#text > 20)
	assert(#linesReplaceWhat > 0)
	local firstWhat = linesReplaceWhat[1]:trim():escapeRegex()
	--[[if #linesReplaceWhat <= 1 then
		local count
		firstWhat, count = text:gsub(firstWhat, replacement)
		return firstWhat, count
	end]]
	local firstLinePositions = {}
	for i, line in ipairs(linesText) do
		if line:match(firstWhat) then
		--if line == firstWhat then
			firstLinePositions[#firstLinePositions + 1] = i
		end
	end
	if #firstLinePositions == 0 then
		print("match not found")
		return text, 0
	end
	local errors = {}
	local function errorMsg(...)
		errors[#errors + 1] = string.format(...)
	end
	local replaced, replacedOffset = 0, 0
	for matchIdx, firstLinePos in ipairs(firstLinePositions) do
		firstLinePos = firstLinePos + replacedOffset
		if #linesText - #linesReplaceWhat + 1 < firstLinePos then -- not enough lines to match fully
			errorMsg("replacement %d", matchIdx)
			errorMsg("match not found - not enough lines to match")
			goto continue
		end
		-- skip first line, because already found
		for i = 2, #linesReplaceWhat do
			local idx = firstLinePos + i - 1
			--if not linesText[idx]:match(replaceWhat[i]:trim():escapeRegex()) then
			if not linesText[idx]:match(linesReplaceWhat[i]:trim():escapeRegex()) then
				errorMsg("replacement %d", matchIdx)
				errorMsg("match failed at line %d", i)
				errorMsg("text: %s", linesText[idx]:trim():escapeForFormat())
				errorMsg("replace what: %s", linesReplaceWhat[i]:trim():escapeForFormat())
				goto continue
			end
		end
		replaced, replacedOffset = replaced + 1, replacedOffset + (#linesReplacement - #linesReplaceWhat) -- if replacing 3 lines with 5, only 2 are inserted
		local indentBaseText = indentCount(linesText[firstLinePos])
		-- can't get first replacement line indent? using last, usually will be correct because I usually patch entire blocks
		local indentBaseReplacement = indentCount(linesReplacement[#linesReplacement])
		local output = {}
		-- now replace, ignoring indent
		local linesReplacementSize = #linesReplacement
		for i, repl in ipairs(linesReplacement) do
			local indentDifference = indentCount(repl) - indentBaseReplacement
			local indent = string.rep("\t", math.max(indentBaseText, indentBaseText + indentDifference)) -- not lower than starting indent
			-- if first line or last, replace only part that is matched, because there may be other stuff which is not part of match
			if i == 1 or (i == linesReplacementSize and linesReplaceWhat[i]) then
				local textIndex = firstLinePos + i - 1
				output[#output + 1] = indent .. linesText[textIndex]:trim():gsub(linesReplaceWhat[i]:trim():escapeRegex(), repl:trim():escapeRegex())
			else -- line in the middle, replace completely
				output[#output + 1] = indent .. repl:trim()
			end
		end
		-- start replacing
		local replaceInplace = math.min(#output, #linesReplaceWhat)
		for i = 1, replaceInplace do
			linesText[firstLinePos + i - 1] = output[i]
		end
		-- rest need to have space created for them or be deleted
		local needToDelete = #linesReplaceWhat - #linesReplacement
		local left = #output - replaceInplace
		local begin = firstLinePos + replaceInplace
		if needToDelete > 0 then -- delete
			for moveHere = begin, #linesText - needToDelete do
				linesText[moveHere] = linesText[moveHere + needToDelete]
			end
			for delete = #linesText - needToDelete + 1, #linesText do
				linesText[delete] = nil
			end
		elseif left > 0 then -- insert
			multipleInsert(linesText, begin, table.slice(output, replaceInplace + 1))
		end
		::continue::
	end
	local str = string.format("%d matches, %d replacements done", #firstLinePositions, replaced)
	if #errors > 0 then
		str = str .. "\n" .. table.concat(errors, "\n")
		print(str)
		return table.concat(linesText, "\n"), replaced
	end
	print(str)
	return table.concat(linesText, "\n"), #linesReplacement
	-- KEEP INDENT BELOW LOWEST LINE AND MATCH TO FIRST LINE INDENT
end

function partyTileId()
	return Map.TileMap[(64 - Party.Y / 0x200):floor()] [(64 + Party.X / 0x200):floor()]
end

function partyTile()
	return (Game.CurrentTileBin and Game.CurrentTileBin.Items or Game.TileBin)[partyTileId()]
end

function tlen(t)
	local count = 0
	for i, v in universalEnum(t) do
		count = count + 1
	end
	return count
end

function cmpSetMapvarBool(name)
	local x = mapvars[name]
	if not x then
		mapvars[name] = true
	end
	return x
end

-- prints set bits in a number
-- if bitDesc is provided, it should be a table with descriptions as keys and bit values as values, or vice versa
function printBitValues(combined, bitDesc)
	local t = {}
	local bitDescriptions = bitDesc and table.copy(bitDesc) or {}
	if type(next(bitDescriptions)) ~= "number" then
		bitDescriptions = table.invert(bitDescriptions)
	end
	local bitVal = 1
	for i = 0, 31 do
		if bit.band(combined, bitVal) ~= 0 then
			local desc = bitDescriptions[bitVal]
			if desc then
				table.insert(t, string.format("[0x%X] (#%d) = %s", bitVal, i, desc))
			else
				table.insert(t, string.format("[0x%X] (#%d)", bitVal, i))
			end
		end
		bitVal = bitVal * 2
	end
	print(table.concat(t, "\r\n"))
end

function mtarget()
	local t = Mouse:GetTarget()
	local i = t.Index
	if t.Kind == 0 then
		return
	elseif t.Kind == 1 then
		return Map.Doors[i], i
	elseif t.Kind == 2 then
		return Map.Objects[i], i
	elseif t.Kind == 3 then
		return Map.Monsters[i], i
	elseif t.Kind == 4 then
		return Party[i], i
	elseif t.Kind == 5 then
		return Map.Sprites[i], i
	elseif t.Kind == 6 then
		if Map.IsOutdoor() then
			return Map.Models[i:div(64)].Facets[i % 64], i:div(64), i % 64
		else
			return Map.Facets[i], i
		end
	elseif t.Kind == 7 then
		return Map.Lights[i], i
	end
	error("Invalid mouse target")
end

local max, min = math.max, math.min
function math.clamp(num, low, high)
	return max(min(num, high), low)
end
getmetatable(1).__index.clamp = math.clamp

function arrayEndPtr(arr)
	return (arr["?ptr"] + arr.Limit * arr.ItemSize):tohex()
end

function nthNext(tbl, n)
	local key, val
	for i = 1, n do
		key, val = next(tbl, key)
	end
	return key, val
end

function equippedItemIndex(slot)
	local item = Party[Game.CurrentPlayer]:GetEquippedItem(slot)
	if item then
		for i, item2 in Party[Game.CurrentPlayer].Items do
			if item == item2 then
				print(i)
				return
			end
		end
	end
end

function itemIndexByName(name)
	for i, item in Party[Game.CurrentPlayer].Items do
		if item:T().Name:lower():match(name:lower()) then
			print(i)
			return
		end
	end
end

function getSpriteByName(name)
	for i, spr in Game.SpritesLod.SpritesSW do
		if spr.Name:lower():match(name) then
			return spr
		end
	end
end

function monsterStandSpriteName(id)
	local f = Game.MonListBin[id].FramesStand:lower()
	for i, frame in Game.SFTBin do
		if frame.GroupName:lower() == f then
			return frame.SpriteName
		end
	end
end