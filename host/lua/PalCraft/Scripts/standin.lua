-- System "stand_in": the Palworld character is hidden and carried to wherever Steve stands, so Palworld
-- keeps loading the world around him and Pals have someone to attack.
local P = require("gen_protocol")
local U = require("util")
local M = {}

local carried = false
local hidden = false
local halfHeight = 88

local function movement(pawn, mode)
    local cm = pawn.CharacterMovement
    if cm and cm:IsValid() then cm:SetMovementMode(mode, 0) end
end

-- Palworld gives the character its own movement back after a respawn or a hit reaction. Left falling
-- under a Steve who flies or stands on a tower, it gathers speed and dies when he comes down.
local function hold(pawn)
    local cm = pawn.CharacterMovement
    if cm and cm:IsValid() and cm.MovementMode ~= 0 then
        cm:StopMovementImmediately()
        cm:SetMovementMode(0, 0) -- MOVE_None: no falling while Minecraft decides where he is
    end
end

-- feet = Steve's feet in host metres, yawDeg = Minecraft yaw.
function M.carry(pawn, feet, yawDeg)
    if not carried then
        carried = true
        pcall(function() halfHeight = pawn.CapsuleComponent:GetScaledCapsuleHalfHeight() end)
    end
    hold(pawn)
    local X, Y, Z = U.to_ue(feet[1], feet[2], feet[3])
    local swept = {}
    pawn:K2_SetActorLocationAndRotation({ X = X, Y = Y, Z = Z + halfHeight }, { Pitch = 0, Yaw = yawDeg + 180, Roll = 0 },
        false, swept, true)
    U.release(swept)
end

function M.release(pawn)
    if carried then
        carried = false
        if pawn and pawn:IsValid() then movement(pawn, 3) end -- MOVE_Falling: settle onto Palworld's ground
    end
end

-- What the character holds is an actor of its own: with only the character hidden, its pickaxe floats on
-- Steve's chest. gear = addresses of the tools this mod hid, so showing the character shows those and no
-- tool that Palworld itself had put away.
local gear = {}
local gearTick = 0
local WEAPON
-- The tool Palworld stows on the character's back while a sphere is in its hand is a third kind of actor:
-- attached to the character, owned by nobody. Searching all of Palworld's objects for them takes tens of
-- milliseconds: do it once, then let Palworld tell us about each new one.
local backs = {}
local watching = false
local function watch_backs()
    if watching then return end
    watching = true
    for _, a in ipairs(FindAllOf("PalBackWeaponBase") or {}) do
        if a:IsValid() then backs[a:GetAddress()] = a end
    end
    local gen = _G.PALCRAFT_GEN
    NotifyOnNewObject("/Script/Pal.PalBackWeaponBase", function(a)
        if gen ~= _G.PALCRAFT_GEN then return true end
        backs[a:GetAddress()] = a
    end)
end
local function each_tool(pawn, fn)
    WEAPON = WEAPON or StaticFindObject("/Script/Pal.PalWeaponBase")
    if not WEAPON or not WEAPON:IsValid() then return end
    pawn.Children:ForEach(function(_, e)
        local a = e:get()
        if a and a:IsValid() and a:IsA(WEAPON) then fn(a) end
    end)
    watch_backs()
    local me = pawn:GetAddress()
    for at, a in pairs(backs) do
        if not a:IsValid() then
            backs[at] = nil
        else
            local on = a:GetAttachParentActor()
            if on and on:IsValid() and on:GetAddress() == me then fn(a) end
        end
    end
end
local function hide_gear(pawn)
    each_tool(pawn, function(a)
        if not a.bHidden then
            a:SetActorHiddenInGame(true)
            gear[a:GetAddress()] = true
        end
    end)
end
local function show_gear(pawn)
    each_tool(pawn, function(a)
        if gear[a:GetAddress()] then a:SetActorHiddenInGame(false) end
    end)
    gear = {}
end

-- Unreal stops posing the bones of a mesh nobody sees. A swing is a sweep of the tool along the hand bone:
-- with the character hidden its pickaxe hung still and hit nothing. Option 0 = always tick the pose and
-- refresh the bones. Set through Unreal's own setter, once per character: UE4SS crashed the game reading
-- this enum property, so the mod never learns the old value and leaves the new one in place (it costs
-- nothing on a character the player is looking at).
local posed
local KISMET
local function keep_posing(pawn)
    local at = pawn:GetAddress()
    if posed == at then return end
    KISMET = KISMET or StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
    local mesh = pawn.Mesh
    if not (KISMET and KISMET:IsValid() and mesh and mesh:IsValid()) then return end
    KISMET:SetBytePropertyByName(mesh, FName("VisibilityBasedAnimTickOption"), 0)
    posed = at
end

function M.hide(pawn, want)
    if not (pawn and pawn:IsValid()) then return end
    want = want and true or false
    if want ~= hidden then
        if want then U.guard("posing", function() keep_posing(pawn) end) end
        pawn:SetActorHiddenInGame(want)
        hidden = want
        gearTick = 0
        if not want then U.guard("gear", function() show_gear(pawn) end) end
    end
    if hidden then
        if gearTick <= 0 then
            gearTick = P.tune.gear_scan_ticks
            U.guard("gear", function() hide_gear(pawn) end)
        end
        gearTick = gearTick - 1
    end
end

-- The character's feet in host metres and facing as a quaternion about the up axis.
function M.where(pawn)
    local l = pawn:K2_GetActorLocation()
    local cm = pawn.CharacterMovement
    -- A swimmer's feet trail behind it and its middle sits under the surface. Steve swims flat: measured from
    -- the feet he would lie on the seabed side of the waterline, out of sight under Palworld's water.
    local down = cm and cm:IsValid() and cm.MovementMode == 4 and -P.tune.swim_feet_m * 100 or halfHeight
    local x, y, z = U.to_host(l.X, l.Y, l.Z - down)
    local yaw = math.rad(pawn:K2_GetActorRotation().Yaw)
    return { x, y, z }, { 0, math.sin(yaw / 2), 0, math.cos(yaw / 2) }
end

function M.carried() return carried end

-- Palworld mode: what the character's body is doing, as state flags for Steve to copy.
local attackKey
function M.pose_flags(pc, pawn, S)
    local f = 0
    local cm = pawn.CharacterMovement
    if cm and cm:IsValid() then
        if cm.MovementMode == 4 then f = f | S.BODY_SWIM -- MOVE_Swimming
        elseif pawn.bIsCrouched or cm:IsSliding() then f = f | S.BODY_CROUCH end
    end
    attackKey = attackKey or { KeyName = FName("LeftMouseButton") }
    if not pc.bShowMouseCursor and pc:IsInputKeyDown(attackKey) then f = f | S.BODY_ACT end
    return f
end

return M
