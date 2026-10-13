-- System "pals": the Pals and people near Steve, as boxes with health that Minecraft can aim at.
-- Rows of sheets/entities.json decide what each character is to Minecraft.
local P = require("gen_protocol")
local U = require("util")
local shm = require("shm")
local M = {}

local OFF = P.off.entities
local MAXN = P.const.MAX_ENTITIES
local util
local byId = {}      -- id -> { kind, maxHp, pos }
local frame = 0
local far = {}       -- address of a character far from Steve -> the table it is measured again at

-- Palworld keeps its own list of every character that is not a player. It is read anew for each table, so
-- every handle is as old as this tick: see util.lua.
local function characters(env)
    util = util or StaticFindObject("/Script/Pal.Default__PalUtility")
    local col = util:GetPalObjectCollector(env.pawn)
    if not (col and col:IsValid()) then return nil end
    return col.PalCharacter_NPC
end

-- The character behind an id of the last table, as it is now, or nil when it is gone.
function M.actor(env, id)
    local list = characters(env)
    local found
    if list then
        list:ForEach(function(_, e)
            if found then return end
            local a = e:get()
            if a and a:IsValid() and a:GetAddress() == id then found = a end
        end)
    end
    return found
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

-- Returns the table row of a character, and whether it is near enough to measure again for the next table.
-- Players are not in the list this reads (rows player and other_player).
local function describe(a, id, feet, r2, near2)
    local l = a:K2_GetActorLocation()
    local x, y, z = U.to_host(l.X, l.Y, l.Z)
    local dx, dy, dz = x - feet[1], y - feet[2], z - feet[3]
    local d2 = dx * dx + dy * dy + dz * dz
    if d2 > r2 then return nil, d2 <= near2 end
    if not a:GetActorEnableCollision() then return nil, true end                -- stored_pal
    local cp = a.CharacterParameterComponent
    if not cp or not cp:IsValid() then return nil, true end
    local hp, maxHp = cp:GetHP().Value / 1000, cp:GetMaxHP().Value / 1000
    local radius, half = 0.4, 0.9
    local cap = a.CapsuleComponent
    if cap and cap:IsValid() then radius, half = cap:GetScaledCapsuleRadius() / 100, cap:GetScaledCapsuleHalfHeight() / 100 end
    -- A Lamball's capsule is a 60 cm ball that the grass and the terrain blocks around it swallow. Give small Pals
    -- a box Steve can find with a sword, grown upward from where they stand.
    local feetY = y - half
    radius, half = math.max(radius, P.tune.pal_box_min_radius_m), math.max(half, P.tune.pal_box_min_half_m)
    local name = a:GetClass():GetFName():ToString():gsub("^BP_", ""):gsub("_C$", "")
    local seen = byId[id]
    local kind = seen and seen.kind or classify(a, cp, name, maxHp)
    local dead = cp:IsDead() or hp <= 0
    local yaw = math.rad(a:K2_GetActorRotation().Yaw)
    local flags = P.entity.WORLD_BOX | (dead and P.entity.DEAD or 0)
    local e = seen or { kind = kind }
    e.maxHp, e.pos, e.seen = maxHp, { x, y, z }, frame
    byId[id] = e
    return string.pack("<I8I4I4fffffffffffffffI4c48", id, kind, 0,
        x, feetY, z, 0, math.sin(yaw / 2), 0, math.cos(yaw / 2),
        x, feetY + half, z, radius, half, radius, hp, maxHp, flags, name:sub(1, 47)), true
end

function M.tick(env)
    if not env.linked or env.tick % P.tune.entity_period_ticks ~= 0 then return end
    frame = frame + 1
    local rows = {}
    local list = env.hasPawn and characters(env)
    if list then
        local r2 = P.tune.entity_radius_m ^ 2
        local near2 = (P.tune.entity_radius_m + P.tune.entity_near_margin_m) ^ 2
        local wait = P.tune.entity_far_tables
        local feet = env.feet
        -- Most characters are far away, and measuring one costs ten times what reading its address does.
        list:ForEach(function(_, e)
            local a = e:get()
            if not (a and a:IsValid()) then return end
            local id = a:GetAddress()
            local due = far[id]
            if due and due > frame then return end
            local ok, row, close = pcall(describe, a, id, feet, r2, near2)
            -- Spread by address, so the far ones do not all fall due in the same table.
            far[id] = not (ok and close) and frame + 1 + (id >> 8) % wait or nil
            if ok and row and #rows < MAXN then rows[#rows + 1] = row end
        end)
        -- A character that left Palworld's list is never due again: forget it.
        if frame % (wait * 8) == 0 then
            for id, due in pairs(far) do
                if due < frame then far[id] = nil end
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
