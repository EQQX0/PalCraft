-- System "pals": the Pals and people near Steve, as boxes with health that Minecraft can aim at.
-- Rows of sheets/entities.json decide what each character is to Minecraft.
local P = require("gen_protocol")
local U = require("util")
local shm = require("shm")
local M = {}

local OFF = P.off.entities
local MAXN = P.const.MAX_ENTITIES
local util
local byId = {}      -- id -> { actor, kind, maxHp }
local frame = 0
local known = {}     -- every PalCharacter alive, by address
local watching = false

-- Searching all of Palworld's objects for characters takes tens of milliseconds: do it once, then let
-- Palworld tell us about each new one.
local function watch()
    if watching then return end
    watching = true
    for _, a in ipairs(FindAllOf("PalCharacter") or {}) do
        if a:IsValid() then known[a:GetAddress()] = a end
    end
    local gen = _G.PALCRAFT_GEN
    NotifyOnNewObject("/Script/Pal.PalCharacter", function(a)
        if gen ~= _G.PALCRAFT_GEN then return true end
        known[a:GetAddress()] = a
    end)
end

function M.find(id) return byId[id] end

-- Nearest hostile to a point (host metres): who probably just hit Steve.
function M.nearest_hostile(feet)
    local best, bestD
    for _, e in pairs(byId) do
        if e.kind ~= P.ent.OTHER then
            local dx, dy, dz = e.pos[1] - feet[1], e.pos[2] - feet[2], e.pos[3] - feet[3]
            local d = dx * dx + dy * dy + dz * dz
            if not bestD or d < bestD then best, bestD = e, d end
        end
    end
    return best
end

local function classify(a, cp, name, maxHp)
    if cp:IsPlayersOtomo() or cp:IsOtomo() then return P.ent.OTHER end       -- own_pal
    if name:find("^NPC_") then return P.ent.SMALL end                          -- npc_human
    if not util:IsWildNPC(a) then return P.ent.OTHER end                       -- own_pal (base workers)
    if maxHp >= 4000 then return P.ent.LARGE end                               -- boss_pal
    return P.ent.SMALL                                                         -- wild_pal
end

local function describe(a, pawnAddr, feet, r2)
    if not a:IsValid() then return nil end
    local id = a:GetAddress()
    if id == pawnAddr then return nil end                                      -- player
    local l = a:K2_GetActorLocation()
    local x, y, z = U.to_host(l.X, l.Y, l.Z)
    local dx, dy, dz = x - feet[1], y - feet[2], z - feet[3]
    if dx * dx + dy * dy + dz * dz > r2 then return nil end
    local cp = a.CharacterParameterComponent
    if not cp or not cp:IsValid() then return nil end
    local hp, maxHp = cp:GetHP().Value / 1000, cp:GetMaxHP().Value / 1000
    local radius, half = 0.4, 0.9
    local cap = a.CapsuleComponent
    if cap and cap:IsValid() then radius, half = cap:GetScaledCapsuleRadius() / 100, cap:GetScaledCapsuleHalfHeight() / 100 end
    local name = a:GetClass():GetFName():ToString():gsub("^BP_", ""):gsub("_C$", "")
    local seen = byId[id]
    local kind = seen and seen.kind or classify(a, cp, name, maxHp)
    local dead = cp:IsDead() or hp <= 0
    local yaw = math.rad(a:K2_GetActorRotation().Yaw)
    local flags = P.entity.WORLD_BOX | (dead and P.entity.DEAD or 0)
    local e = seen or { actor = a, kind = kind }
    e.maxHp, e.pos, e.seen = maxHp, { x, y, z }, frame
    byId[id] = e
    return string.pack("<I8I4I4fffffffffffffffI4c48", id, kind, 0,
        x, y - half, z, 0, math.sin(yaw / 2), 0, math.cos(yaw / 2),
        x, y, z, radius, half, radius, hp, maxHp, flags, name:sub(1, 47))
end

function M.tick(env)
    if not env.linked or env.tick % P.tune.entity_period_ticks ~= 0 then return end
    util = util or StaticFindObject("/Script/Pal.Default__PalUtility")
    frame = frame + 1
    local rows = {}
    if env.hasPawn then
        local pawnAddr = env.pawn:GetAddress()
        local r2 = P.tune.entity_radius_m ^ 2
        watch()
        for addr, a in pairs(known) do
            if not a:IsValid() then
                known[addr] = nil
            elseif #rows < MAXN then
                local ok, row = pcall(describe, a, pawnAddr, env.feet, r2)
                if ok and row then rows[#rows + 1] = row end
            end
        end
    end
    for id, e in pairs(byId) do
        if e.seen ~= frame then byId[id] = nil end
    end
    -- seq, count, frame, then the rows
    shm.publish(OFF, string.pack("<I4I8", #rows, env.tick) .. table.concat(rows))
end

return M
