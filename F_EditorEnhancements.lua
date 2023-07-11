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
	local texturesToSelect = {}
	local texturesGiven = #(textures or {}) ~= 0
	local facetStack = {}
	for k in pairs(Editor.Selection) do
		table.insert(facetStack, k)
		if not texturesGiven then
			local bitmapId = Map.Facets[k].BitmapId
			texturesToSelect[bitmapId] = true
		end
	end
	if #facetStack == 0 then
		return error("Nothing selected!")
	end
	local _, x = next(textures or {})
	if type(x) == "string" then
		for i, b in Game.BitmapsLod.Bitmaps do
			if table.find(textures, b.Name:lower()) then
				texturesToSelect[i] = true
			end
		end
	elseif type(x) == "number" then
		for i, v in ipairs(textures) do
			texturesToSelect[v] = true
		end
	end
	local vertexFacets = {}
	for fid, f in Map.Facets do
		for vid, v in f.VertexIds do
			v = Map.Vertexes[v]
			table.insert(tget(vertexFacets, v[1], v[2], v[3]), fid)
		end
	end
	local processedFacets = {}
	local facetStackLen = #facetStack
	while facetStackLen > 0 do
		local facetId = facetStack[facetStackLen] -- get last element
		facetStack[facetStackLen] = nil
		facetStackLen = facetStackLen - 1
		processedFacets[facetId] = true
		for _, vertexId in Map.Facets[facetId].VertexIds do
			local v = Map.Vertexes[vertexId]
			local facetIds = vertexFacets[v[1] ][v[2] ][v[3] ] or {}
			for _, fid in ipairs(facetIds) do
				if not table.find(facetStack, fid) and not processedFacets[fid] and texturesToSelect[Map.Facets[fid].BitmapId] then
					table.insert(facetStack, fid)
				end
			end
			vertexFacets[v[1] ][v[2] ][v[3] ] = nil -- vertex already processed
		end
	end
	for i, _ in pairs(processedFacets) do
		Editor.SelectSingleFacet(i)
	end
	Editor.UpdateSelectionState()
	return selLen()
end

sel = selectAdjacentTextures

local chT = {}
for i, b in Game.BitmapsLod.Bitmaps do
	if b.Name:lower():match("^gt") then
		table.insert(chT, b.Name:lower())
	end
end

function selectChest()
	--debug.Message(dump(t))
	return selectAdjacentTextures(table.copy(chT))
end

ch = selectChest

function F()
	local o = Mouse:GetTarget()
	if o.Kind == const.ObjectRefKind.Facet then
		return Map.Facets[o.Index]
	end
end

function bmpSize()
	local f = F()
	if f then
		local bmp = Game.BitmapsLod.Bitmaps[f.BitmapId]
		print(string.format("width: %d, height: %d", bmp.Width, bmp.Height))
	else
		print "No facet selected!"
	end
end