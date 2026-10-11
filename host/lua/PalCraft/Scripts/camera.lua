-- Systems "camera" and "frame_tag": Palworld renders from Minecraft's eye, and every tick marks its frame
-- so the native side knows exactly which Minecraft pose the frame on screen was drawn with.
local P = require("gen_protocol")
local U = require("util")
local M = {}

local cam            -- our CameraActor
local onCam = false  -- the player's view target is our camera
local yielding = false -- Palworld took the view for a cutscene; ours is waiting
local tags = {}      -- frame tag render targets
local KRL, UI
local black = { R = 0, G = 0, B = 0, A = 1 }

local function ensure_cam(pawn)
    if cam and cam:IsValid() then return cam end
    local cls = StaticFindObject("/Script/Engine.CameraActor")
    local loc = pawn:K2_GetActorLocation()
    cam = pawn:GetWorld():SpawnActor(cls, { X = loc.X, Y = loc.Y, Z = loc.Z + 100 }, { Pitch = 0, Yaw = 0, Roll = 0 })
    if cam and cam:IsValid() then
        cam.CameraComponent.bConstrainAspectRatio = false
    end
    onCam = false
    return cam
end

-- Palworld's own HUD would sit on top of Minecraft's: it is hidden while Minecraft's camera is in use.
local hudVisible = true
local function hud(pawn, visible)
    if visible == hudVisible then return end
    hudVisible = visible
    UI = UI or StaticFindObject("/Script/Pal.Default__PalUIUtility")
    pcall(function() UI:SetVisibilityHUD(pawn, visible) end)
end

-- Unreal's camera FOV is horizontal or vertical depending on the player's axis constraint.
local function ue_fov(pc, fovY, aspect)
    local axis = 1
    pcall(function() axis = pc.Player.AspectRatioAxisConstraint end)
    if axis == 0 or (axis == 2 and aspect < 1) then return fovY end
    return math.deg(2 * math.atan(math.tan(math.rad(fovY) / 2) * aspect))
end

-- Renders this frame from the pose in ctrl (host metres). Returns true when the pose was applied.
-- keepHud: Palworld has the controls and needs its own HUD.
function M.apply(pc, pawn, pos, target, fovY, aspect, keepHud)
    local c = ensure_cam(pawn)
    if not c or not c:IsValid() then return false end
    local ex, ey, ez = U.to_ue(pos[1], pos[2], pos[3])
    local tx, ty, tz = U.to_ue(target[1], target[2], target[3])
    local dx, dy, dz = tx - ex, ty - ey, tz - ez
    local flat = math.sqrt(dx * dx + dy * dy)
    if flat + math.abs(dz) < 1e-4 then return false end
    local rot = { Pitch = math.deg(math.atan(dz, flat)), Yaw = math.deg(math.atan(dy, dx)), Roll = 0 }
    -- Palworld moves the view itself for a cutscene or a boss entrance. That is its picture to show: ours
    -- waits until the view is back on the character.
    local view = pc:GetViewTarget()
    local at = view and view:IsValid() and view:GetAddress() or 0
    if onCam and at ~= c:GetAddress() and at ~= pawn:GetAddress() then
        if not yielding then
            yielding = true
            U.log("camera: Palworld shows its own view (" .. view:GetFullName():match("[%w_]+") .. "); waiting")
        end
        hud(pawn, true)
        return false
    end
    yielding = false
    c:K2_SetActorLocationAndRotation({ X = ex, Y = ey, Z = ez }, rot, false, {}, true)
    c.CameraComponent:SetFieldOfView(ue_fov(pc, fovY, aspect))
    if not onCam or at ~= c:GetAddress() then
        pc:SetViewTargetWithBlend(c, 0.0, 0, 0.0, false)
        onCam = true
    end
    hud(pawn, keepHud == true)
    return true
end

-- Hands the view back to Palworld's own camera.
function M.release(pc, pawn)
    yielding = false
    if onCam then
        onCam = false
        if pawn and pawn:IsValid() then
            pc:SetViewTargetWithBlend(pawn, 0.0, 0, 0.0, false)
            hud(pawn, true)
        end
    end
end

function M.overridden() return onCam end

-- True while Palworld shows a view of its own and ours waits.
function M.yielding() return yielding end

-- The camera Palworld wants while ours is the view target: the character's own follow camera, which its
-- spring arm keeps moving. In host metres: pos, target, fovY.
function M.body(pc, pawn, aspect)
    local c = pawn.FollowCamera
    if not c or not c:IsValid() then return M.own(pc, aspect) end
    local l, r = c:K2_GetComponentLocation(), c:K2_GetComponentRotation()
    local px, py, pz = U.to_host(l.X, l.Y, l.Z)
    local cp, sp = math.cos(math.rad(r.Pitch)), math.sin(math.rad(r.Pitch))
    local fx, fy, fz = U.to_host(cp * math.cos(math.rad(r.Yaw)) * 100, cp * math.sin(math.rad(r.Yaw)) * 100, sp * 100)
    local fovY = math.deg(2 * math.atan(math.tan(math.rad(c.FieldOfView) / 2) / aspect))
    return { px, py, pz }, { px + fx, py + fy, pz + fz }, fovY
end

-- Palworld's own camera, in host metres: pos, target, fovY.
function M.own(pc, aspect)
    local m = pc.PlayerCameraManager
    local l, r = m:GetCameraLocation(), m:GetCameraRotation()
    local px, py, pz = U.to_host(l.X, l.Y, l.Z)
    local cp, sp = math.cos(math.rad(r.Pitch)), math.sin(math.rad(r.Pitch))
    local fx, fy, fz = U.to_host(cp * math.cos(math.rad(r.Yaw)) * 100, cp * math.sin(math.rad(r.Yaw)) * 100, sp * 100)
    local hfov = m:GetFOVAngle()
    local fovY = math.deg(2 * math.atan(math.tan(math.rad(hfov) / 2) / aspect))
    return { px, py, pz }, { px + fx, py + fy, pz + fz }, fovY
end

-- Clears tiny render target number k: the clear reaches the graphics card just before this tick's frame,
-- and its odd size is what the native side recognises.
function M.tag(pawn, k)
    KRL = KRL or StaticFindObject("/Script/Engine.Default__KismetRenderingLibrary")
    local rt = tags[k]
    if not rt or not rt:IsValid() then
        rt = KRL:CreateRenderTarget2D(pawn, P.const.TAG_BASE_W + k, P.const.TAG_H, 2, black, false)
        tags[k] = rt
    end
    if rt and rt:IsValid() then KRL:ClearRenderTarget2D(pawn, rt, black) end
end

return M
