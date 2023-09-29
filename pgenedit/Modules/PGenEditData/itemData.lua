local data = {}
for i, item in Game.ItemsTxt do
    data[tostring(i)] = true -- index is item id as string
end
return data