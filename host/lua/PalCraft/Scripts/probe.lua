-- System "surface_probe": Minecraft digs Palworld's world for materials. It sends one ray along Steve's
-- crosshair and gets back what kind of surface that ray lands on, so a tree gives wood and a cliff gives stone.
local P = require("gen_protocol")
local shm = require("shm")
local M = {}

local OFF = P.off.probe
local F = P.Probe
local S = P.surface
local black = { R = 0, G = 0, B = 0, A = 0 }
local none = {}
local KSL

local function name_of(obj)
    return obj:GetFName():ToString()
end

-- Palworld names its meshes and physical materials in plain words; those words decide the kind.
local WOOD = { "tree", "oak_", "spruce", "palm", "fir_", "alder", "sycamore", "birch", "pine", "maple", "willow", "cedar",
    "sakura", "cherry", "bamboo", "stump", "wood", "log_", "bush" }
local ORE = { "_ore", "ore_", "metalore", "coal", "sulfur", "quartz", "paldium", "crystal" }
local function classify(hit)
    local c = hit.Component:Get()
    if not c or not c:IsValid() then return S.STONE, false end
    local class = name_of(c:GetClass())
    local owner = c:GetOwner()
    if owner and owner:IsValid() and owner.CharacterParameterComponent ~= nil and owner.CharacterParameterComponent:IsValid() then
        return S.NONE, true -- a Pal or a person: look behind it
    end
    local mesh, mat = "", ""
    if class:find("StaticMesh") or class:find("ISM") then
        pcall(function()
            local m = c.StaticMesh
            if m and m:IsValid() then mesh = name_of(m) end
        end)
    end
    pcall(function()
        local m = hit.PhysMaterial:Get()
        if m and m:IsValid() then mat = name_of(m) end
    end)
    local thing = (mesh .. " " .. (owner and owner:IsValid() and name_of(owner:GetClass()) or "")):lower()
    mat = mat:lower()
    for _, word in ipairs(WOOD) do
        if thing:find(word, 1, true) then return S.WOOD, false end
    end
    if mat:find("wood") then return S.WOOD, false end
    for _, word in ipairs(ORE) do
        if thing:find(word, 1, true) then return S.ORE, false end
    end
    if mat:find("stone") or mat:find("rock") or mat:find("metal") then return S.STONE, false end
    if mat:find("sand") or thing:find("sand") then return S.SAND, false end
    if mat:find("snow") or mat:find("ice") or thing:find("snow") then return S.SNOW, false end
    if mat:find("grass") or thing:find("grass_") or thing:find("flower") or thing:find("fern") then return S.GRASS, false end
    if mat:find("ground") or mat:find("dirt") or mat:find("soil") or mat:find("mud") or class:find("Landscape") then
        return S.SOIL, false
    end
    return S.STONE, false
end

local function probe(pawn, sx, sy, sz, ex, ey, ez)
    for _ = 1, 3 do
        local hit = {}
        if not KSL:LineTraceSingle(pawn, { X = sz * 100, Y = sx * 100, Z = sy * 100 }, { X = ez * 100, Y = ex * 100, Z = ey * 100 },
                0, false, none, 0, hit, true, black, black, 0.0) then
            return S.NONE
        end
        local ok, kind, character = pcall(classify, hit)
        if not ok then return S.STONE end
        if not character then return kind end
        local dx, dy, dz = ex - sx, ey - sy, ez - sz
        local len = math.sqrt(dx * dx + dy * dy + dz * dz)
        local step = len > 1e-4 and (hit.Distance / 100 + 0.5) / len or 1
        if step >= 1 then return S.NONE end
        sx, sy, sz = sx + dx * step, sy + dy * step, sz + dz * step
    end
    return S.NONE
end

function M.tick(env)
    if not env.hasPawn then return end
    local req, resp = string.unpack("<I4I4", shm.read(OFF, 8))
    if req == resp then return end
    KSL = KSL or StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
    local sx, sy, sz, ex, ey, ez = string.unpack("<ffffff", shm.read(OFF + F.start[1], 24))
    shm.put(OFF, F.kind, probe(env.pawn, sx, sy, sz, ex, ey, ez))
    shm.put(OFF, F.respSeq, req)
end

return M
