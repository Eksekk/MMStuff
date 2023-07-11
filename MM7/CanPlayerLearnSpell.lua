if not const.Spells then
	const.Spells = {
		TorchLight = 1,
		Haste = 5,
		Fireball = 6,
		MeteorShower = 9,
		Inferno = 10,
		Incinerate = 11,
		WizardEye = 12,
		Sparks = 15,
		Shield = 17,
		LightningBolt = 18,
		Implosion = 20,
		Fly = 21,
		Starburst = 22,
		Awaken = 23,
		WaterWalk = 27,
		TownPortal = 31,
		IceBlast = 32,
		LloydsBeacon = 33,
		Stun = 34,
		DeadlySwarm = 37,
		StoneSkin = 38,
		Blades = 39,
		StoneToFlesh = 40,
		RockBlast = 41,
		DeathBlossom = 43,
		MassDistortion = 44,
		Bless = 46,
		RemoveCurse = 49,
		Heroism = 51,
		RaiseDead = 53,
		SharedLife = 54,
		Resurrection = 55,
		CureInsanity = 64,
		PsychicShock = 65,
		CureWeakness = 67,
		Harm = 70,
		CurePoison = 72,
		CureDisease = 74,
		FlyingFist = 76,
		PowerCure = 77,
		DispelMagic = 80,
		DayOfTheGods = 83,
		PrismaticLight = 84,
		DivineIntervention = 88,
		Reanimate = 89,
		ToxicCloud = 90,
		DragonBreath = 97,
		Armageddon = 98,
		ShootFire = nil,  -- unused
	}

	table.copy({
		Shoot = 100,
		ShootFire = 101,
		ShootBlaster = 102,
	}, const.Spells, true)

	table.copy({
		FireBolt = 2,
		FireResistance = 3,
		FireAura = 4,
		FireSpike = 7,
		Immolation = 8,
		FeatherFall = 13,
		AirResistance = 14,
		Jump = 16,
		Invisibility = 19,
		PoisonSpray = 24,
		WaterResistance = 25,
		IceBolt = 26,
		RechargeItem = 28,
		AcidBurst = 29,
		EnchantItem = 30,
		Slow = 35,
		EarthResistance = 36,
		Telekinesis = 42,
		DetectLife = 45,
		Fate = 47,
		TurnUndead = 48,
		Preservation = 50,
		SpiritLash = 52,
		MindResistance = 58,
		CureParalysis = 61,
		Berserk = 62,
		MassFear = 63,
		Enslave = 66,
		Heal = 68,
		BodyResistance = 69,
		Regeneration = 71,
		Hammerhands = 73,
		ProtectionFromMagic = 75,
		LightBolt = 78,
		DestroyUndead = 79,
		Paralyze = 81,
		SummonElemental = 82,
		DayOfProtection = 85,
		HourOfPower = 86,
		Sunray = 87,
		VampiricWeapon = 91,
		ShrinkingRay = 92,
		Shrapmetal = 93,
		ControlUndead = 94,
		PainReflection = 95,
		Souldrinker = 99,
	}, const.Spells, true)

	table.copy({
		RemoveFear = 56,
		MindBlast = 57,
		Telepathy = 59,
		Charm = 60,
		Sacrifice = 96,
	}, const.Spells, true)
end

local NewCode = mem.asmpatch(0x46858B, [[
	cmp dword ptr [ss:ebp-8],eax
	nop
	nop
	nop
	nop
	nop
	jle absolute 0x4685C1
]])

local function GetPlayer(ptr)
	local i = (ptr - Party.PlayersArray["?ptr"]) / Party.PlayersArray[0]["?size"]
	return i, Party.PlayersArray[i]
end

mem.hook(NewCode + 3, function(d)
	local t = {}
	local idx, player = GetPlayer(d.esi)
	t.Player = player
	t.Spell = mem.u4[0xAD458C] - 399
	t.CanLearn = d.ZF or d.SF ~= d.OF
	events.call("CanPlayerLearnSpell", t)
	if t.CanLearn then
		d.ZF = true
	else
		d.ZF = false
		d.SF = d.OF
	end
end)