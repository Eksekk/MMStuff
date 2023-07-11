evt.hint[100] = "Door"
evt.map[100] = function()
	evt.SetDoorState{Id = 1, State = 2}
end

--evt.MoveToMap{Name = "_dungeon_.blv"}

-- button in upper portion
evt.hint[1] = "Button"
evt.map[1] = function()
	evt.SetDoorState{Id = 2, State = 2}
end

-- secret stairs cache
evt.map[2] = function()
	evt.SetDoorState{Id = 3, State = 0}
end

-- item359.bmp
-- find 3 shards of 

-- free prisoner, guards idea

-- main big doors

evt.hint[3] = "Door"
evt.map[3] = function()
	evt.SetDoorState{Id = 5, State = 0}
	evt.SetDoorState{Id = 6, State = 0}
end

evt.hint[4] = "Door"
evt.map[4] = function()
	evt.SetDoorState{Id = 5, State = 0}
	evt.SetDoorState{Id = 6, State = 0}
end

-- big ground lever

evt.hint[5] = "Lever"
evt.map[5] = function()
	evt.SetDoorState{Id = 4, State = 2}
end

-- big barrel with water

evt.hint[6] = "Water"
evt.map[6] = function()
	Game.ShowStatusText("You feel energized")
	evt.Set("SpeedBonus", 20)
	evt.Set("AccuracyBonus", 10)
end

-- "altar" in main big room
evt.hint[7] = "Weird shrine"
evt.map[7] = function()
	if not cmpSetMapvarBool("shrine") then
		Game.ShowStatusText("You feel something has changed")
		for i = evt.VarNum.FireResistance, evt.VarNum.FireResistance + 3 do
			evt.All.Add(i, 10) -- increase elemental resists by 10
		end
		evt.All.Add("BaseIntellect", 10)
		evt.All.Add("BasePersonality", 10)
	end
end

-- monster stuff
local GROUP_NUMBER = 5
if not mapvars.monstersSpawned then
	mapvars.monstersSpawned = true
	for _, mon in Map.Monsters do
		mon.Group = GROUP_NUMBER
	end
	-- near "elven" chest
	pseudoSpawnpoint{monster = 49, x = 9741, y = 7725, z = -144, count = "3-6", powerChances = {33, 33, 33}, radius = 1024, group = GROUP_NUMBER} -- elven archers
	pseudoSpawnpoint{monster = 52, x = 9998, y = 6723, z = -125, count = "2-4", powerChances = {20, 30, 50}, radius = 1024, group = GROUP_NUMBER} -- elven warriors

	-- room with two columns leading to elven part
	pseudoSpawnpoint{monster = 106, x = 5955, y = 3994, z = -155, count = "4-7", powerChances = {66, 17, 17}, radius = 1024, group = GROUP_NUMBER} -- monks

	evt.SetMonGroupBit{NPCGroup = GROUP_NUMBER, Bit = const.MonsterBits.Hostile, On = true}
end