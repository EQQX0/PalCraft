-- System "terrain": Minecraft asks where Palworld's ground and walls are by sending batches of rays;
-- each is answered with a line trace. A batch is spread over ticks so a frame never stalls.
local P = require("gen_protocol")
local shm = require("shm")
local M = {}

local OFF = P.off.rays
local R = P.RayHeader
local RAY, HIT = P.const.RAY_SIZE, P.const.HIT_SIZE
local MISS = string.pack("<ffffffI4I4", 0, 0, 0, 0, 0, 0, 0, 0)
local black = { R = 0, G = 0, B = 0, A = 0 }
local none = {}
local KSL
local job -- the batch in progress

-- Pals and people are not terrain: a ray that hits one carries on behind it.
local function is_character(hit)
    local ok, yes = pcall(function()
        local c = hit.Component:Get()
        local owner = c and c:IsValid() and c:GetOwner()
        return owner and owner:IsValid() and owner.CharacterParameterComponent ~= nil and owner.CharacterParameterComponent:IsValid()
    end)
    return ok and yes
end

local function line(pawn, sx, sy, sz, ex, ey, ez)
    local hit = {}
    if KSL:LineTraceSingle(pawn, { X = sz * 100, Y = sx * 100, Z = sy * 100 }, { X = ez * 100, Y = ex * 100, Z = ey * 100 },
            0, false, none, 0, hit, true, black, black, 0.0) then
        return hit
    end
end

-- Palworld's hills and cliffs are shells with one-sided faces: a ray that starts inside one sees nothing of it
-- and lands on the ground underneath, which would tell Minecraft the hill is open air. A point is inside when
-- a ray from the sky finds a surface above it and a ray from the point up to that surface finds no ceiling.
local function buried(pawn, x, y, z)
    local top = line(pawn, x, y + P.tune.solid_probe_up_m, z, x, y, z)
    if not top or top.Distance < 1 or is_character(top) then return false end
    local roofY = top.ImpactPoint.Z / 100
    if roofY - y < 0.05 then return false end
    return line(pawn, x, y, z, x, roofY - 0.02, z) == nil
end

local function trace(pawn, sx, sy, sz, ex, ey, ez)
    local dx, dy, dz = ex - sx, ey - sy, ez - sz
    if dy < 0 and dy * dy > 9 * (dx * dx + dz * dz) and buried(pawn, sx, sy, sz) then
        return string.pack("<ffffffI4I4", sx, sy, sz, 0, 1, 0, 1, 0)   -- solid right here
    end
    for _ = 1, 3 do
        local hit = {}
        if not KSL:LineTraceSingle(pawn, { X = sz * 100, Y = sx * 100, Z = sy * 100 }, { X = ez * 100, Y = ex * 100, Z = ey * 100 },
                0, false, none, 0, hit, true, black, black, 0.0) then
            return MISS
        end
        local p, n = hit.ImpactPoint, hit.ImpactNormal
        if not is_character(hit) then
            return string.pack("<ffffffI4I4", p.Y / 100, p.Z / 100, p.X / 100, n.Y, n.Z, n.X, 1, 0)
        end
        -- restart just past the character
        local dx, dy, dz = ex - sx, ey - sy, ez - sz
        local len = math.sqrt(dx * dx + dy * dy + dz * dz)
        if len < 1e-4 then return MISS end
        local step = (hit.Distance / 100 + 0.5) / len
        if step >= 1 then return MISS end
        sx, sy, sz = sx + dx * step, sy + dy * step, sz + dz * step
    end
    return MISS
end

function M.tick(env)
    if not env.hasPawn then return end
    KSL = KSL or StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
    local req, resp, count = string.unpack("<I4I4I4", shm.read(OFF, 12))
    if req == resp then
        job = nil
        return
    end
    if not job or job.seq ~= req then
        count = math.min(count, P.const.MAX_RAYS)
        job = { seq = req, count = count, data = count > 0 and shm.read(OFF + P.const.RAYS_OFF_RAYS, count * RAY) or "", i = 0, out = {} }
    end
    local t0, budget, least = os.clock(), P.tune.ray_budget_ms / 1000, P.tune.ray_min_per_tick
    local pawn, data, out, done = env.pawn, job.data, job.out, 0
    while job.i < job.count do
        local sx, sy, sz, ex, ey, ez = string.unpack("<ffffff", data, job.i * RAY + 1)
        out[#out + 1] = trace(pawn, sx, sy, sz, ex, ey, ez)
        job.i = job.i + 1
        done = done + 1
        if done >= least and done % 8 == 0 and os.clock() - t0 > budget then break end
    end
    if job.i >= job.count then
        if job.count > 0 then shm.write(OFF + P.const.RAYS_OFF_HITS, table.concat(out)) end
        shm.put(OFF, R.processed, job.count)
        shm.put(OFF, R.respSeq, job.seq)
        job = nil
    else
        shm.put(OFF, R.processed, job.i)
    end
end

return M
