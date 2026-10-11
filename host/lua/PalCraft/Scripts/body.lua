-- System "body_needs": one body, two games. Minecraft owns hunger, so the hidden character's stomach follows
-- Steve's food bar and it never starves behind his back. Palworld owns the weather, so its body temperature
-- goes to Steve's gauge, and a fire Steve lights in Minecraft counts as a Palworld heat source.
local P = require("gen_protocol")
local shm = require("shm")
local U = require("util")
local M = {}

local OFF = P.off.body
local B = P.Body
local SOURCE = "PalCraftWarmth"
local applied = 0        -- the heat level this mod has given Palworld
local appliedTo
local exposed = false
local nextAt, settledAt = 0, 0

-- Freezing or burning: the temperature is past what the character's clothes take.
function M.exposed()
    return exposed
end

-- Steve's fires only take the edge off cold, and water only off heat: neither pushes a mild day into harm.
local function helpful(base, warmth)
    if base < 0 and warmth > 0 then return math.min(warmth, -base) end
    if base > 0 and warmth < 0 then return math.max(warmth, -base) end
    return 0
end

local function set_heat(comp, base, warmth)
    local address = comp:GetAddress()
    if address ~= appliedTo then appliedTo, applied = address, 0 end -- a respawned character starts clean
    if U.now_ms() < settledAt then return end -- Palworld's reading still lags the last change
    local level = helpful(base - applied, warmth)
    if level == applied then return end
    settledAt = U.now_ms() + P.tune.heat_settle_ms
    if applied ~= 0 then comp:RemoveHeatSource(FName(SOURCE)) end
    if level ~= 0 then comp:AddHeatSource(FName(SOURCE), level) end
    applied = level
end

function M.tick(env)
    if U.now_ms() < nextAt then return end
    nextAt = U.now_ms() + P.tune.body_period_ms
    if not env.hasPawn then
        exposed, applied = false, 0
        shm.put(OFF, B.valid, 0)
        return
    end
    local carried = env.linked and env.cflags & P.ctrl.MOVE_HUNTER ~= 0
    local food, warmth = string.unpack("<fi4", shm.read(OFF + B.food[1], 8))
    local stomach = 0
    local cp = env.pawn.CharacterParameterComponent
    if cp and cp:IsValid() then
        local max = cp:GetMaxFullStomach()
        if carried and max > 0 then
            local want = max * math.max(0, math.min(20, food)) / 20
            local ind = cp.IndividualParameter
            if ind and ind:IsValid() and math.abs(cp:GetFullStomach() - want) > max * 0.02 then ind:SetFullStomach(want) end
        end
        if max > 0 then stomach = cp:GetFullStomach() / max end
    end
    local comp = env.pawn.PalBodyTemperature
    if not comp or not comp:IsValid() then
        exposed = false
        shm.put(OFF, B.valid, 0)
        return
    end
    set_heat(comp, comp.TemperatureInfo.CurrentTemperature, carried and warmth or 0)
    local info = comp.TemperatureInfo
    local t, heat, cold = info.CurrentTemperature, info.CurrentResistRank_Heat, info.CurrentResistRank_Cold
    exposed = t > heat or t < -cold
    shm.write(OFF + B.temperature[1], string.pack("<i4i4i4fI4", t, heat, cold, stomach, 1))
end

return M
