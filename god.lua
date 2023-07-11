local mmver = Game.Version

function god(lev)
	-- get all spells
	for _,pl in Party do
		for i in pl.Spells do
			pl.Spells[i] = true
		end
	end

	-- learn all available skills at their maximum level
	local LearnLevel = {[0] = 0, 1, 4, (mmver > 6 and 7 or 12), 10}
	lev = lev or 60
	if lev then
		LearnLevel = {lev, lev, lev, lev}
	end

	for _, pl in Party do
		for i in pl.Skills do
			pl.Skills[i] = JoinSkill(60, const.GM)
		end
	end
	
	-- level 200 to all
	for _,pl in Party do
		pl.LevelBase = math.max(pl.LevelBase, 500)
	end
	
	-- clear conditions
	for _, a in Party do
		for i in a.Conditions do
			a.Conditions[i] = 0
		end
	end

	-- full HP, SP
	for _,pl in Party do
		pl.HP = pl:GetFullHP()
		pl.SP = pl:GetFullSP()
	end
	
	Game.NeedRedraw = true
end

function godSkill(lev)
	for _, pl in Party do
		for i, v in pl.Skills do
			local skill = math.max(SplitSkill(v), 10)
			pl.Skills[i] = JoinSkill(skill, const.GM or const.Master)
		end
	end
	-- get all spells
	for _,pl in Party do
		for i in pl.Spells do
			pl.Spells[i] = true
		end
	end
end