-- Systems "life" and "host_action": whether the Palworld character is usable, deaths in both directions,
-- and the answer to Minecraft's "interact" key (not wired in this version).
local P = require("gen_protocol")
local shm = require("shm")
local M = {}

local OFF, H = P.off.header, P.Header
local wasUsable, wasDead = false, false
local mcDeaths

local function bump(field)
    shm.put(OFF, field, (shm.get(OFF, field) + 1) % 0x100000000)
end

function M.tick(env)
    local dead = false
    if env.hasPawn then
        local cp = env.pawn.CharacterParameterComponent
        dead = cp ~= nil and cp:IsValid() and cp:IsDead()
    end
    env.dead = dead
    -- Palworld mode keeps drawing through a defeat: Steve lies where the character fell. In Minecraft mode
    -- Palworld's defeat screen is its own.
    local body = (env.cflags or 0) & P.ctrl.HOST_BODY ~= 0
    env.busy = not env.hasPawn or (dead and not body)
    if dead and not wasDead then bump(H.hostDeaths) end
    local usable = env.hasPawn and not dead
    if usable and not wasUsable then bump(H.hostLife) end
    wasUsable, wasDead = usable, dead

    if not env.linked then return end
    -- Steve died: the stand-in was only wounded on his behalf, so it starts fresh with him.
    local d = shm.get(OFF, H.mcDeaths)
    if mcDeaths ~= nil and d ~= mcDeaths and usable then
        local cp = env.pawn.CharacterParameterComponent
        if cp and cp:IsValid() then cp:SetHP({ Value = cp:GetMaxHP().Value }) end
    end
    mcDeaths = d

    local req, ack = shm.get(OFF, H.mcActionReq), shm.get(OFF, H.hostActionAck)
    if req ~= ack then
        shm.put(OFF, H.hostActionResult, -1)
        shm.put(OFF, H.hostActionAck, req)
    end
end

return M
