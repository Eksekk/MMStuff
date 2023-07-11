function events.CanPlayerLearnSpell(t)
	local school = math.floor((t.Spell - 1) / 11)
	if school == 7 then -- 7 = light
		local sorcSpells = {const.Spells.DayOfProtection, const.Spells.HourOfPower, const.Spells.DivineIntervention}
		if t.Player.Class == const.Class.PriestLight and table.find(sorcSpells, t.Spell) then
			t.CanLearn = false
		elseif t.Player.Class == const.Class.ArchMage and not table.find(sorcSpells, t.Spell) then
			t.CanLearn = false
		end
	end
end