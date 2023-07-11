data = {}

local minimumMasteryToSpellIndexMap = {[1] = 1, [2] = 1, [3] = 1, [4] = 1, [5] = 2, [6] = 2, [7] = 2,
    [8] = 3, [9] = 3, [10] = 3, [11] = 4}
for id, spell in Game.Spells do
    data[id] = {}
    local sp, txt = Game.SpellsTxt[id]
    data.recoveryDelayByMastery = table.copy(spell.Delay)
    data.damageAddByMastery = {spell.DamageAdd, spell.DamageAdd, spell.DamageAdd, spell.DamageAdd}
    data.damageDiceSides = spell.DamageDiceSides

    data.name = txt.Name
    data.shortName = txt.shortName
    data.description = txt.Description
    data.rankDescriptions = {txt.Normal, txt.Expert, txt.Master, txt.GM}
    data.damageTypes = {txt.DamageType}
    data.manaCostByMastery = table.copy(txt.SpellPoints)

    local spellIndex = (id - 1) % 11 + 1
    data.minimumMasteryToLearn = minimumMasteryToSpellIndexMap[spellIndex]
    data.powerWithinSchool = spellIndex
    data.schoolSkill = const.Skills.Fire + (id - spellIndex) / 11
end