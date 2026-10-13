-- Systems "camera" and "frame_tag": Palworld renders from Minecraft's eye, and every tick marks its frame
-- so the native side knows exactly which Minecraft pose the frame on screen was drawn with.
local P = require("gen_protocol")
local U = require("util")
local M = {}

local onCam = false  -- the player's view target is our camera
local yielding = false -- Palworld took the view for a cutscene; ours is waiting
local KRL, UI, KSL
local black = { R = 0, G = 0, B = 0, A = 1 }
local ARM_END = FName("SpringEndpoint")

local CAMERA, CAPTURE
local TAGS, TAG_W, TAG_H = P.const.TAG_COUNT, P.const.TAG_BASE_W, P.const.TAG_H

-- Our camera is an actor this mod spawns and gives to the player controller. No handle of it is kept (see
-- util.lua): Palworld's own list of what the controller owns leads to it, once per tick.
local tickPc, tickCam, tickLooked
function M.frame(pc)
    tickPc, tickCam, tickLooked = pc, nil, false
end
local function our_cam()
    if tickLooked then return tickCam end
    tickLooked = true
    CAMERA = CAMERA or StaticFindObject("/Script/Engine.CameraActor")
    local class = CAMERA:GetAddress()
    tickPc.Children:ForEach(function(_, e)
        if tickCam then return end
        local a = e:get()
        -- Exactly a CameraActor: Palworld's cutscene cameras are classes of their own.
        if a and a:IsValid() and a:GetClass():GetAddress() == class then tickCam = a end
    end)
    return tickCam
end
local function ensure_cam(pawn)
    local cam = our_cam()
    if cam then return cam end
    local loc = pawn:K2_GetActorLocation()
    cam = pawn:GetWorld():SpawnActor(CAMERA, { X = loc.X, Y = loc.Y, Z = loc.Z + 100 }, { Pitch = 0, Yaw = 0, Roll = 0 })
    onCam = false
    if not (cam and cam:IsValid()) then return nil end
    cam.CameraComponent.bConstrainAspectRatio = false
    cam:SetOwner(tickPc)
    tickCam = cam
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

-- Palworld mode cuts the character's follow camera loose from its arm (see M.apply_body). This puts it back.
local heldAt
local function free_follow(pawn)
    heldAt = nil
    -- The component itself knows whether it was cut loose, so a reloaded copy of this file frees it too.
    local c
    if pawn and pawn:IsValid() then
        local f = pawn.FollowCamera
        if f and f:IsValid() and f.bAbsoluteLocation then c = f end
    end
    if c then
        pcall(function()
            c:SetAbsolute(false, false, false)
            local swept = {}
            c:K2_SetRelativeLocationAndRotation({ X = 0, Y = 0, Z = 0 }, { Pitch = 0, Yaw = 0, Roll = 0 }, false, swept, true)
            U.release(swept)
        end)
    end
end

local function look(pos, target)
    local ex, ey, ez = U.to_ue(pos[1], pos[2], pos[3])
    local tx, ty, tz = U.to_ue(target[1], target[2], target[3])
    local dx, dy, dz = tx - ex, ty - ey, tz - ez
    local flat = math.sqrt(dx * dx + dy * dy)
    if flat + math.abs(dz) < 1e-4 then return nil end
    return { X = ex, Y = ey, Z = ez }, { Pitch = math.deg(math.atan(dz, flat)), Yaw = math.deg(math.atan(dy, dx)), Roll = 0 }
end

-- Palworld mode: renders this frame from the pose in ctrl, with the character still Palworld's view target.
-- Its dialogue camera works out its place from the player's own camera and lands three kilometres away when
-- another actor holds the view (2026-10-12). So the follow camera itself is cut loose from its arm and put
-- at the pose; M.body reads where the arm wanted it.
function M.apply_body(pc, pawn, pos, target)
    local c = pawn.FollowCamera
    local loc, rot = look(pos, target)
    if not loc or not c or not c:IsValid() then return false end
    local view = pc:GetViewTarget()
    local at = view and view:IsValid() and view:GetAddress() or 0
    if at ~= pawn:GetAddress() then
        local cam = our_cam()
        if cam and at == cam:GetAddress() then
            pc:SetViewTargetWithBlend(pawn, 0.0, 0, 0.0, false)
            onCam = false
        else
            -- A cutscene or a conversation: Palworld's picture, and its camera back where it expects it.
            if not yielding then
                yielding = true
                U.log("camera: Palworld shows its own view (" .. view:GetFullName():match("[%w_]+") .. "); waiting")
            end
            free_follow(pawn)
            hud(pawn, true)
            return false
        end
    end
    yielding = false
    if heldAt ~= c:GetAddress() then
        free_follow(pawn)
        c:SetAbsolute(true, true, false)
        heldAt = c:GetAddress()
    end
    local swept = {}
    c:K2_SetWorldLocationAndRotation(loc, rot, false, swept, true)
    U.release(swept)
    hud(pawn, true)
    return true
end

-- Renders this frame from the pose in ctrl (host metres). Returns true when the pose was applied.
-- keepHud: Palworld has the controls and needs its own HUD.
function M.apply(pc, pawn, pos, target, fovY, aspect, keepHud)
    free_follow(pawn)
    local c = ensure_cam(pawn)
    if not c or not c:IsValid() then return false end
    local loc, rot = look(pos, target)
    if not loc then return false end
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
    local swept = {}
    c:K2_SetActorLocationAndRotation(loc, rot, false, swept, true)
    U.release(swept)
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
    free_follow(pawn)
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

-- System "steve_shot": Palworld is showing a shot of its own in Palworld mode. Minecraft drew its frame from
-- the pose in ctrl; when that is the shot's camera, near enough, Steve belongs in the picture. Returns
-- drawSteve, hideCharacter: a shot that keeps moving shows Palworld's own character instead.
local misses = 0
function M.shot(pc, pos, target, fovY, aspect)
    local p, t, f = M.own(pc, aspect)
    local dx, dy, dz = pos[1] - p[1], pos[2] - p[2], pos[3] - p[3]
    local ax, ay, az = target[1] - pos[1], target[2] - pos[2], target[3] - pos[3]
    local bx, by, bz = t[1] - p[1], t[2] - p[2], t[3] - p[3]
    local na, nb = math.sqrt(ax * ax + ay * ay + az * az), math.sqrt(bx * bx + by * by + bz * bz)
    local cos = na > 1e-6 and nb > 1e-6 and (ax * bx + ay * by + az * bz) / (na * nb) or 0
    local same = dx * dx + dy * dy + dz * dz < P.tune.shot_match_m ^ 2
        and cos > math.cos(math.rad(P.tune.shot_match_deg)) and math.abs(fovY - f) < P.tune.shot_match_deg
    misses = same and 0 or misses + 1
    return same, misses < P.tune.shot_miss_ticks
end

-- The camera Palworld wants while ours is the view target: the character's own follow camera, which its
-- spring arm keeps moving. In host metres: pos, target, fovY.
function M.body(pc, pawn, aspect)
    local c = pawn.FollowCamera
    if not c or not c:IsValid() then return M.own(pc, aspect) end
    local l, ux, uy, uz
    if heldAt == c:GetAddress() then
        -- Cut loose and sitting at Minecraft's pose: the end of its arm is where Palworld wants it.
        local t = pawn.CameraBoom:GetSocketTransform(ARM_END, 0)
        local q = t.Rotation
        l = t.Translation
        ux, uy, uz = 1 - 2 * (q.Y * q.Y + q.Z * q.Z), 2 * (q.X * q.Y + q.W * q.Z), 2 * (q.X * q.Z - q.W * q.Y)
    else
        local r = c:K2_GetComponentRotation()
        local cp = math.cos(math.rad(r.Pitch))
        l = c:K2_GetComponentLocation()
        ux, uy, uz = cp * math.cos(math.rad(r.Yaw)), cp * math.sin(math.rad(r.Yaw)), math.sin(math.rad(r.Pitch))
    end
    local flat = math.max(1e-6, math.sqrt(ux * ux + uy * uy))
    -- Steve is wider than Palworld's character: the camera steps back along the view and a little to the
    -- right, so the middle of the picture looks along a parallel line half a metre over and Steve stays left
    -- of it. A wall in the way shortens the step.
    local sx = -(P.tune.body_cam_back_m * ux) - P.tune.body_cam_side_m * uy / flat
    local sy = -(P.tune.body_cam_back_m * uy) + P.tune.body_cam_side_m * ux / flat
    local sz = -(P.tune.body_cam_back_m * uz)
    local step = math.sqrt(sx * sx + sy * sy + sz * sz) * 100
    if step > 1 then
        local nx, ny, nz = sx * 100 / step, sy * 100 / step, sz * 100 / step
        KSL = KSL or StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
        local hit = {}
        local ok, blocked = pcall(function()
            return KSL:LineTraceSingle(pawn, { X = l.X, Y = l.Y, Z = l.Z },
                { X = l.X + nx * (step + 30), Y = l.Y + ny * (step + 30), Z = l.Z + nz * (step + 30) },
                0, false, {}, 0, hit, true, black, black, 0.0)
        end)
        U.release(hit)
        if not ok then step = 0 elseif blocked then step = math.max(0, math.min(step, hit.Distance - 30)) end
        l = { X = l.X + nx * step, Y = l.Y + ny * step, Z = l.Z + nz * step }
    end
    local px, py, pz = U.to_host(l.X, l.Y, l.Z)
    local fx, fy, fz = U.to_host(ux * 100, uy * 100, uz * 100)
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

-- Frame tag k is a tiny render target of a width of its own: clearing it reaches the graphics card just
-- before this tick's frame, and the odd size is what the native side recognises.
-- Nothing in Palworld holds such a target, and what nothing holds Palworld throws away about once a minute.
-- The handles kept here then pointed at freed memory: the crashes of 0.2.1. Now each target hangs on a
-- scene capture actor that never captures, the captures belong to our camera in the order of their tags, and
-- every tick walks from the controller to the camera to capture k to its target.
local function new_target(pawn, comp, k)
    local rt = KRL:CreateRenderTarget2D(pawn, TAG_W + k, TAG_H, 2, black, false)
    comp.TextureTarget = rt
    return rt
end
local function new_holder(pawn, cam, k)
    CAPTURE = CAPTURE or StaticFindObject("/Script/Engine.SceneCapture2D")
    local loc = cam:K2_GetActorLocation()
    local cap = pawn:GetWorld():SpawnActor(CAPTURE, { X = loc.X, Y = loc.Y, Z = loc.Z }, { Pitch = 0, Yaw = 0, Roll = 0 })
    if not (cap and cap:IsValid()) then return nil end
    local comp = cap.CaptureComponent2D
    -- Off before it has a target: a capture would draw the whole world into it every frame.
    comp.bCaptureEveryFrame = false
    comp.bCaptureOnMovement = false
    new_target(pawn, comp, k)
    cap:SetOwner(cam)
    return cap
end
function M.tag(pawn, k)
    KRL = KRL or StaticFindObject("/Script/Engine.Default__KismetRenderingLibrary")
    local cam = ensure_cam(pawn)
    if not cam then return end
    for i = #cam.Children, TAGS - 1 do
        if not new_holder(pawn, cam, i) then return end
    end
    local cap = cam.Children[k + 1]
    if not (cap and cap:IsValid()) then return end
    local comp = cap.CaptureComponent2D
    local rt = comp.TextureTarget
    if not (rt and rt:IsValid() and rt.SizeX == TAG_W + k) then rt = new_target(pawn, comp, k) end
    if rt and rt:IsValid() then KRL:ClearRenderTarget2D(pawn, rt, black) end
end

return M
