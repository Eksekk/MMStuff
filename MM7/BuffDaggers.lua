local function GetPlayer(ptr)
	local i = (ptr - Party.PlayersArray["?ptr"]) / Party.PlayersArray[0]["?size"]
	return i, Party.PlayersArray[i]
end

local function daggerActive(player)
	local main, off = player.ItemMainHand, player.ItemExtraHand
	return (main ~= 0 and Game.ItemsTxt[player.Items[main].Number].Skill == const.Skills.Dagger and not player.Items[main].Broken) or
		   (off ~= 0 and Game.ItemsTxt[player.Items[off].Number].Skill == const.Skills.Dagger and not player.Items[off].Broken)
end

local critsIgnoreResistances = false
local enableDoubleDamage = true
local enableCrits = true
if enableCrits then
	local crit
	local masteryDamageAdd = {0, 0, 50, 125}
	mem[critsIgnoreResistances and "autohook" or "autohook2"](critsIgnoreResistances and 0x4398D1 or 0x43986A, function(d)
		local idx, player
		for i = 0, 3 do
			if Party.PlayersArray[i]["?ptr"] == d.edi then
				idx, player = i, Party.PlayersArray[i]
			end
		end
		if not idx then
			idx, player = GetPlayer(mem.u4[d.esp + 0x4])
		end
		if not daggerActive(player) then return end
		local s, m = SplitSkill(player.Skills[const.Skills.Dagger])
		if s == 0 then return end
		if math.random(1, 100) <= s then
			if masteryDamageAdd[m] > 0 then
				d.eax = d.eax + masteryDamageAdd[m]
				crit = true
			end
		end
	end)

	local hits = "%s critically hits %s for %lu damage!\0"
	local kills = "%s critically inflicts %lu points killing %s!\0"

	mem.autohook2(0x439B79, function(d)
		if crit then
			mem.u4[d.esp] = mem.topointer(kills)
			crit = false
		end
	end)

	mem.autohook2(0x439BDF, function(d)
		if crit then
			mem.u4[d.esp] = mem.topointer(hits)
			crit = false
		end
	end)
	
	-- disable dagger master bonus
	-- main hand
	mem.asmpatch(0x48CEDA, "jmp short " .. 0x48CF15 - 0x48CEDA)
	-- offhand
	mem.asmpatch(0x48D005, "jmp short " .. 0x48D043 - 0x48D005)
end

if enableDoubleDamage then
	function events.CalcStatBonusBySkills(t)
		if t.Result ~= 0 and t.Stat == const.Stats.MeleeDamageBase then  -- t.Result ~= 0 is for speedup
			local sk, mas = SplitSkill(t.Player.Skills[const.Skills.Dagger])
			if mas >= const.GM then
				if daggerActive(t.Player) then
					t.Result = t.Result + sk
				end
			end
		end
	end
end

function events.GameInitialized2()
	-- variables can't be local because they'll contain garbage
	BuffDaggersMaster, BuffDaggersGM = nil, nil
	if enableCrits then
		BuffDaggersMaster = "Chance to do critical hit for extra damage equal to skill"
		if critsIgnoreResistances then
			BuffDaggersMaster = BuffDaggersMaster .. ". This extra damage ignores resistances"
		end
	end
	if enableDoubleDamage then
		BuffDaggersGM = "Skill * 2 added to Attack Damage"
		if enableCrits then
			BuffDaggersGM = BuffDaggersGM .. ". Critical hits are stronger"
		end
	end
	if not enableDoubleDamage and enableCrits then
		BuffDaggersGM = mem.string(mem.u4[0x5C8698]) .. ". Critical hits are stronger"
	end
	if BuffDaggersMaster then
		mem.u4[0x5C8730] = mem.topointer(BuffDaggersMaster)
	end
	if BuffDaggersGM then
		mem.u4[0x5C8698] = mem.topointer(BuffDaggersGM)
	end
end