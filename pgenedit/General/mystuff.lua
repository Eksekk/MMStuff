function reloadM()
	M = dofile"C:\\Users\\Eksekk\\Documents\\GitHub\\MMStuff\\EksekkStuff.lua"
end
json = require"json"
reloadM()
if not M.dll then
	-- IMPORTANT: run after game is initialized, otherwise skill names, class names etc. will be empty
	function events.GameInitialized2()
		M.loadDll()
	end
end

