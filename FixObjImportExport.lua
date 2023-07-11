-- fix obj import/export due to blender exporting incorrect coordinates
-- due to floating point inaccuracy and MMEditor not catching this
local oldLoadObj = Editor.LoadObj
function Editor.LoadObj(fileName, asObjects, ...)
	if (Editor.State or {}).RoundToInteger == false then -- will be false if nil (unset)
		return oldLoadObj(fileName, asObjects, ...)
	end
	local file = io.open(fileName, "r")
	if file then
		local f = file:read("*a")
		local t = {}
		local old = {}
		for line in f:gmatch("[^\r\n]+") do
			line = line:gsub("^%s*(.-)%s*$", function(text) return text end) or ""
			local numberRegex = "[+-]?%d+[.]?%d*"
			if #line >= 2 and line:sub(1, 2) == "v " then -- exclude vt and vn
				local i = 1
				line = line:gsub(numberRegex, function(n)
					if i ~= 4 then
						n = string.format("%d", math.round(tonumber(n)))
						i = i + 1
					end
					return n
				end)
			end
			table.insert(t, line)
		end
		io.SaveString(fileName .. ".old", f)
		file:close()
		file = io.open(fileName, "w+")
		file:write(table.concat(t, "\n"))
		file:close()
	end
	return oldLoadObj(fileName, asObjects, ...)
end

function universalEnum(t, array, unlimitedElementAmount)
	local meta = type(t) == "table" and getmetatable(t)
	local c = {}
	local i = 0
	for k, v in unpack(not meta and {(array and ipairs or pairs)(t or {})} or meta.members and {structs.enum(t)} or
		meta.__call and type(meta.__call) == "function" and {t} or {(array and ipairs or pairs)(t or {})}) do
		c[k] = v
		i = i + 1
		if not unlimitedElementAmount and i == 100000 then
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

function selLen()
	local i = 0
	for k, v in pairs(Editor.Selection) do
		i = i + 1
	end
	return i
end

function selectAdjacentTextures(textures)
	if not Editor or not Editor.WorkMode then
		return error("Not in editor!")
	end
	local facetStack, processedFacets = {}, {}
	local textureIds = {}
	local ins = not textures
	for k in pairs(Editor.Selection) do
		if ins then
			textureIds = textureIds or {}
			table.insert(textureIds, Map.Facets[k].BitmapId)
		end
		table.insert(facetStack, k)
	end
	if #facetStack == 0 then
		return error("Nothing selected!")
	end
	local _, x = next(textures or {})
	if type(x) == "string" then
		for i, b in Game.BitmapsLod.Bitmaps do
			if table.find(textures, b.Name:lower()) and not table.find(textureIds, i) then
				table.insert(textureIds, i)
			end
		end
	else
		textureIds = table.join(textureIds, textures or {})
	end
	local vertexFacets = {}
	for fid, f in Map.Facets do
		for vid, v in f.VertexIds do
			v = Map.Vertexes[v]
			table.insert(tget(vertexFacets, v[1], v[2], v[3]), fid)
		end
	end
	local i = 0
	while #facetStack > 0 do
		i = i + 1
		local facetId = facetStack[#facetStack]
		facetStack[#facetStack] = nil
		table.insert(processedFacets, facetId)
		local adjacentVertexes = {}
		for i, vertexId in Map.Facets[facetId].VertexIds do
			local v = Map.Vertexes[vertexId]
			local facetIds = vertexFacets[v[1] ][v[2] ][v[3] ] or {}
			for i, fid in ipairs(facetIds) do
				if not table.find(facetStack, fid) and not table.find(processedFacets, fid)
					and table.find(textureIds, Map.Facets[fid].BitmapId) then
					table.insert(facetStack, fid)
				end
			end
			vertexFacets[v[1] ][v[2] ][v[3] ] = nil -- vertex already processed
		end
	end
	for _, i in ipairs(processedFacets) do
		Editor.SelectSingleFacet(i)
	end
	Editor.UpdateSelectionState()
	return selLen()
end
sel = selectAdjacentTextures

function selectChest()
	local t = {}
	for i, b in Game.BitmapsLod.Bitmaps do
		if b.Name:lower():match("^gt") then
			table.insert(t, b.Name:lower())
		end
	end
	--debug.Message(dump(t))
	return selectAdjacentTextures(t)
end

ch = selectChest

function F()
	local o = Mouse:GetTarget()
	if o.Kind == const.ObjectRefKind.Facet then
		return Map.Facets[o.Index]
	end
end