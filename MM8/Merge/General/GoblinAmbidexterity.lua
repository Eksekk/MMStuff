do return end

function events.GameInitialized2()
	-- getRace
	-- it's not exposed anywhere as asm function and I want asm,
	-- so I take address from one of its call sites and check with other
	-- I could duplicate it but it's not good
	local getRaceAddress = mem.i4[0x4C6A18] + 0x4C6A1C
	if getRaceAddress ~= mem.i4[0x490443] + 0x490447 then
		error("Unknown GetRace function address")
	end
	
	-- handle equipping
	-- 1 if doesn't have skill: cannot equip
	-- 2 elseif offhand is 2h axe or staff: cannot equip (unconditional)
	-- 3 elseif mainhand is 2h axe or staff:
		-- 4 if offhand is empty: swap and equip (vanilla)
		-- 5 else: cannot equip
	-- spear is tricky:
	-- 6 elseif either of mainhand, offhand, new item is a spear:
		-- 7 can equip spear in one hand: equip (unconditional)
		-- 8 else if offhand nonempty: cannot equip (unconditional)
		-- 9 else: equip (vanilla - conditional (if mainhand nonempty, exchange, otherwise equip))
	-- 10 else: equip (unconditional)

	local hooks = HookManager{GetRace = getRaceAddress, RaceGoblin = const.Race.Goblin,
		OffhandNoSwap = 0x4677E1, -- always equips in offhand, overwriting existing weapon if it exists
		OffhandSwap = 0x46777E, -- always equips in offhand, swapping with existing weapon if it exists
		MainhandSwap = 0x46781A, -- always equips in mainhand (weapon to equip 1h only), swapping with existing weapon if it exists
		ItemsTxtPtr = Game.ItemsTxt["?ptr"], SkillSpear = const.Skills.Spear,
		GetSkill = 0x48EF4F, GetSkillMastery = 0x455B09, OrigEquip = 0x46770E, -- does any of 4 actions depending on vanilla logic
		Cannot = 0x4674A8, HasSkill = 0x490FE0, Mainhand2HNoSwap = 0x46799A, Mainhand2HSwap = 0x467943} -- weapon to equip 2H only
		
	const.EquipWeaponResult = {
		Standard = 0,
		MainhandSwap = 1,
		Mainhand2HSwap = 2,
		Mainhand2HNoSwap = 3,
		OffhandNoSwap = 4,
		OffhandSwap = 5,
		Cannot = 6
	}
	local r = const.EquipWeaponResult
	local rets = {hooks.ref.MainhandSwap, hooks.ref.Mainhand2HSwap, hooks.ref.Mainhand2HNoSwap,
		hooks.ref.OffhandNoSwap, hooks.ref.OffhandSwap, hooks.ref.Cannot}
	--[[hooks.autohook2(0x467483, function(d)
		-- ebx - player ptr, edi = mainhand item, [ebp - 4] - offhand item, [ebp - 8] - equip stat, esi - skill
		local t = {}
		t.PlayerIndex, t.Player = internal.GetPlayer(d.ebx)
		t.MainHandItem = d.edi ~= 0 and t.Player.Items[d.edi]
		t.OffHandItem = mem.u4[d.ebp - 4] ~= 0 and t.Player.Items[mem.u4[d.ebp - 4] ]
		t.EquipItem = Mouse.Item
		t.EquipStat = mem.u4[d.ebp - 8]
		t.Skill = d.esi
		t.Result = 0
		t.TwoHanded = false
		events.call("CanEquipWeapon", t)
		local ret = rets[t.Result]
		if ret then
			-- mem.u4[d.ebp - 0xC] = d.edi -- set to mainhand item if its equip stat is 1 (most two handed weapons)
			d:push(ret)
			return true
		end
	end)]]
	
	-- check: can you equip one handed weapon with mainhand empty and sword/dagger in offhand (with required skill)?
	-- remake: is two handed, can be equipped in one hand, function "equipping in mainhand" equips wand if offhand is present? may need to make
	-- "equip weapon in mainhand, switching with existing if present" asm function
	local function isTwoHandedDefault(player, item)
		local s, m = SplitSkill(player.Skills[const.Skills.Spear])
		if item:T().EquipStat == const.ItemType.Weapon2H - 1 then
			return true
		end
		return item:T().Skill == const.Skills.Spear and m < const.Master
	end
	
	local function canBeEquippedInOffhandDefault(player, item)
		local itemTxt = item:T()
		if itemTxt == false then return end
		local s, m = SplitSkill(player.Skills[itemTxt.Skill])
		return itemTxt.Skill == const.Skills.Shield or itemTxt.Skill == const.Skills.Dagger and m >= const.Expert or
			itemTxt.Skill == const.Skills.Sword and m >= const.Master
	end
	
	-- problem: equip one hand weapon in place of mainhand 2h weapon, no offhand
	local function equipResultDefault(player, equipItem, isTwoHanded, canBeEquippedInOffhand)
		local s, m = SplitSkill(equipItem:T().Skill == const.SkillClub and 0 or player.Skills[equipItem:T().Skill])
		if equipItem:T().Skill ~= const.SkillClub and (s == 0 or m == 0) then
			return r.Cannot
		end
		isTwoHanded = isTwoHanded or isTwoHandedDefault
		canBeEquippedInOffhand = canBeEquippedInOffhand or canBeEquippedInOffhandDefault
		local equip, main, off = equipItem, player.ItemMainHand ~= 0 and player.Items[player.ItemMainHand], player.ItemExtraHand ~= 0 and player.Items[player.ItemExtraHand]
		local equip2H, main2H, off2H = equip and isTwoHanded(player, equip), main and isTwoHanded(player, main), off and isTwoHanded(player, off)
		local canEquipBeOffhand = false
		if off2H then
			return r.Cannot
		elseif main2H then
			if not off then
				return equip2H and r.Mainhand2HSwap or r.MainhandSwap
			else
				return r.Cannot
			end
		elseif equip2H then
			return off and r.Cannot or r.Mainhand2HSwap
		else
			return not main and r.MainhandSwap or not off and r.OffhandNoSwap or r.OffhandSwap
		end
	end
	
	function events.CanEquipWeapon(t)
		if GetRace(t.Player) == const.Race.Goblin then
			local function isTwoHanded(player, item)
				local itemTxt = item:T()
				if itemTxt.EquipStat == const.ItemType.Weapon2H - 1 then
					return true
				end
				if itemTxt.Skill == const.Skills.Spear then
					local s, m = SplitSkill(player.Skills(const.Skills.Spear))
					return m < const.Master
				end
				return false
			end
			t.Result = equipResultDefault(t.Player, t.EquipItem, isTwoHanded)
		elseif GetRace(t.Player) == const.Race.Minotaur then
			t.Result = equipResultDefault(t.Player, t.EquipItem, function() return false end)
		end
	end
	--[=[hooks.asmhook2(0x467483, [[
		;ebx - player ptr, edi = mainhand item, [ebp - 4] - offhand item, [ebp - 8] - equip stat, esi - skill
		push eax
		push ecx
		sub esp, 8
		cmp dword [ebp - 8], 0
		ja @exit ; not (1h weapon or spear)
		mov ecx, ebx
		call absolute %GetRace%
		cmp eax, %RaceGoblin%
		jne @exit
		;1 
		push edx
		mov ecx, ebx
		push esi
		call absolute %HasSkill%
		pop edx
		test eax, eax
		jz @cannot
		; setup
		and dword [esp + 4], 0 ; offhand itemsTxt offset
		and dword [esp], 0 ; mainhand itemsTxt offset
		mov ecx, dword [ebp - 4]
		jecxz @noOffhandPtr ; hey look, I know advanced assembly instructions!!! I'm so good /s
		lea ecx, dword [ecx + ecx * 8]
		mov ecx, dword [ebx + ecx * 4 + 0x484]
		lea ecx, dword [ecx + ecx * 2]
		shl ecx, 4
		mov dword [esp + 4], ecx
		@noOffhandPtr:
		test edi, edi
		jz @noMainhandPtr
		lea ecx, dword [edi + edi * 8]
		mov ecx, dword [ebx + ecx * 4 + 0x484]
		lea ecx, dword [ecx + ecx * 2]
		shl ecx, 4
		mov dword [esp], ecx
		@noMainhandPtr:
		; 2
		mov ecx, dword [esp + 4]
		jecxz @offhandCheckPassed
		cmp byte [ecx + %ItemsTxtPtr% + 0x1C], 1 ; 2h weapon
		je @cannot
		@offhandCheckPassed:
		; 3
		mov ecx, dword [esp]
		jecxz @twoHandedChecksPassed
		cmp byte [ecx + %ItemsTxtPtr% + 0x1C], 1
		jne @twoHandedChecksPassed
		; 4
		mov ecx, dword [esp + 4]
		jecxz @orig
		; 5
		jmp @cannot
		@twoHandedChecksPassed:
		; 6
		cmp esi, %SkillSpear%
		je @spear
		mov ecx, dword [esp + 4]
		jecxz @noOffhand
		cmp byte [ecx + %ItemsTxtPtr% + 0x1D], %SkillSpear%
		je @spear
		@noOffhand:
		mov ecx, dword [esp]
		jecxz @equip
		cmp byte [ecx + %ItemsTxtPtr% + 0x1D], %SkillSpear%
		jne @equip
		@spear:
		; 7
		push edx
		mov ecx, ebx
		push %SkillSpear%
		call absolute %GetSkill%
		pop edx
		mov ecx, eax
		call absolute %GetSkillMastery%
		cmp eax, 3
		jae @equip
		; 8
		test dword [ebp - 4], 0xFFFFFFFF
		jnz @cannot
		; 9
		@orig:
		add esp, 8
		pop ecx
		pop eax
		jmp absolute %OrigEquip%
		@equip:
		; 10
		add esp, 8
		pop ecx
		pop edx
		test edi, edi
		jz absolute %EquipMainhand%
		test dword [ebp - 4], 0xFFFFFFFF
		jz absolute %EquipOffhandEmpty%
		jmp absolute %EquipOffhand%
		@cannot:
		add esp, 8
		pop ecx
		pop eax
		jmp absolute %CannotEquip%
		@exit:
		add esp, 8
		pop ecx
		pop eax
	]])]=]
	
	-- rotate offhand weapon
	hooks.nop(0x43B7DF)
	--[=[hooks.asmhook(0x43B7CC, [[
		test byte [eax + %ItemsTxtPtr% + 0x1C], 0xFF ; equip stat, make sure it's 1h weapon (or spear)
		jnz @exit
		push eax
		mov ecx, dword [esp + 0x20] ; player ptr
		call absolute %GetRace%
		cmp eax, %RaceGoblin%
		pop eax
		jne @exit
		mov byte [esp + 0x28], 1 ; 1 = sword or dagger (can be rotated)
		jmp absolute 0x43B7E6
		@exit:
	]])]=]
end