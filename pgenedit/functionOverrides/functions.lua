local function mmv(...)
    local r = select(offsets.MMVersion - 5, ...)
    assert(r ~= nil)
    return r
end
local function mm78(...)
    return mmv(nil, ...)
end

local overrides = {}

overrides.Player = {
    GetSkill = {
        params = {},
        ret = "SkillValue",
        --cc = "__stdcall",
    }
}


return overrides