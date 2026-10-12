-- System "stand_in": the Palworld character is hidden and carried to wherever Steve stands, so Palworld
-- keeps loading the world around him and Pals have someone to attack.
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

function M.hide(pawn, want)
    if want ~= hidden and pawn and pawn:IsValid() then
        pawn:SetActorHiddenInGame(want)
        hidden = want
    end
end

-- The character's feet in host metres and facing as a quaternion about the up axis.
function M.where(pawn)
    local l = pawn:K2_GetActorLocation()
    local x, y, z = U.to_host(l.X, l.Y, l.Z - halfHeight)
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
