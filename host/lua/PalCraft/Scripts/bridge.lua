-- System "frame_loop": once per Palworld frame, on the game thread, read what Minecraft wants, apply it,
-- and write down what Palworld did.
local P = require("gen_protocol")
local U = require("util")
local shm = require("shm")
local camera = require("camera")
local standin = require("standin")
local M = {}

local OFF, C, L, H = P.off, P.Control, P.LuaState, P.Header
local TAGS = P.const.TAG_COUNT
local CONTROL_SIZE = 0x64

-- The other systems. Each has tick(env); a system that fails to load is reported and skipped.
local systems = {}
for _, name in ipairs({ "life", "rays", "probe", "body", "entities", "combat", "selftest" }) do
    local ok, m = pcall(require, name)
    if ok then systems[#systems + 1] = { name = name, mod = m }
    else U.log("system " .. name .. " not loaded: " .. tostring(m)) end
end

local runtime, dev
local tick = 0
local lastFrame = -1
local mcBeat, mcBeatMs
local aspect = 16 / 9
local poseHist = {}
for i = 0, TAGS - 1 do poseHist[i] = 0 end
local centerDist = 0
local KSL
local black = { R = 0, G = 0, B = 0, A = 0 }

local function mc_alive()
    local hb = shm.get(OFF.header, H.mcHeartbeat)
    local now = U.now_ms()
    if mcBeat == nil then mcBeat = hb
    elseif hb ~= mcBeat then mcBeat, mcBeatMs = hb, now end
    return mcBeatMs ~= nil and now - mcBeatMs < P.tune.link_timeout_ms
end

-- Development: distance to the first surface along the camera axis, to check the near plane against.
local function trace_center(pawn, pos, target)
    local ex, ey, ez = U.to_ue(pos[1], pos[2], pos[3])
    local tx, ty, tz = U.to_ue(target[1], target[2], target[3])
    local dx, dy, dz = tx - ex, ty - ey, tz - ez
    local n = math.sqrt(dx * dx + dy * dy + dz * dz)
    if n < 1e-6 then return 0 end
    local s = 20000 / n
    local hit = {}
    local ok = KSL:LineTraceSingle(pawn, { X = ex, Y = ey, Z = ez }, { X = ex + dx * s, Y = ey + dy * s, Z = ez + dz * s },
        0, false, {}, 0, hit, true, black, black, 0.0)
    U.release(hit)
    return ok and hit.Distance / 100 or 0
end

local env = { P = P, U = U, shm = shm }

local function on_tick(pc)
    KSL = KSL or StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
    local frame = KSL:GetFrameCount()
    if frame == lastFrame then return end
    lastFrame = frame
    if not shm.open(runtime) then return end
    tick = tick + 1
    local k = tick % TAGS
    if tick % 30 == 1 then
        local w, h = shm.get(OFF.state, P.GameState.bb)
        if w > 0 and h > 0 then aspect = w / h end
    end

    local pawn = pc.Pawn
    local hasPawn = pawn ~= nil and pawn:IsValid()
    local ctrl = mc_alive() and shm.snapshot(OFF.control, CONTROL_SIZE) or nil
    local cflags = ctrl and shm.field(ctrl, C.flags) or 0
    env.pc, env.pawn, env.hasPawn, env.ctrl, env.cflags, env.tick, env.linked = pc, pawn, hasPawn, ctrl, cflags, tick, ctrl ~= nil
    env.busy, env.dead = not hasPawn, false

    -- Life first: it decides whether the character is usable this tick.
    for _, s in ipairs(systems) do
        if s.name == "life" then U.guard("life", s.mod.tick, env) end
    end

    local flags, pose, steveShot = 0, 0, true
    local camPos, camTarget, fovY = { 0, 0, 0 }, { 0, 0, 1 }, 70
    local feet, quat = { 0, 0, 0 }, { 0, 0, 0, 1 }
    if hasPawn then
        flags = flags | P.state.PLAYER_VALID | P.state.CAMERA_VALID
        local usable = ctrl ~= nil and not env.busy
        -- Palworld mode: the pose is Palworld's own camera, echoed by Minecraft once Steve is drawn for it.
        local body = usable and cflags & P.ctrl.HOST_BODY ~= 0
        if usable and cflags & P.ctrl.OVERRIDE_CAMERA ~= 0 then
            local px, py, pz = shm.field(ctrl, C.camPos)
            local tx, ty, tz = shm.field(ctrl, C.camTarget)
            local f = shm.field(ctrl, C.fovYDeg)
            local shown
            if body then
                shown = camera.apply_body(pc, pawn, { px, py, pz }, { tx, ty, tz })
                if not shown and camera.yielding() then
                    shown, steveShot = camera.shot(pc, { px, py, pz }, { tx, ty, tz }, f, aspect)
                end
            else
                shown = camera.apply(pc, pawn, { px, py, pz }, { tx, ty, tz }, f, aspect, false)
            end
            if shown then
                pose = shm.field(ctrl, C.mcFrame)
                camPos, camTarget, fovY = { px, py, pz }, { tx, ty, tz }, f
                flags = flags | P.state.CAM_OVERRIDDEN
            end
        else
            camera.release(pc, pawn)
        end
        if usable and cflags & P.ctrl.MOVE_HUNTER ~= 0 then
            local hx, hy, hz = shm.field(ctrl, C.hunterPos)
            standin.carry(pawn, { hx, hy, hz }, (shm.field(ctrl, C.hunterYawDeg)))
        else
            standin.release(pawn)
        end
        -- In a cutscene Palworld's camera shows its own character: Steve is not drawn there.
        standin.hide(pawn, usable and cflags & P.ctrl.HIDE_HUNTER ~= 0 and (not camera.yielding() or (body and steveShot)))
        if body and camera.yielding() then
            -- Palworld's own shot: Minecraft draws Steve from that camera.
            camPos, camTarget, fovY = camera.own(pc, aspect)
            flags = flags | (U.guard("pose_flags", standin.pose_flags, pc, pawn, P.state) or 0)
        elseif body then
            camPos, camTarget, fovY = camera.body(pc, pawn, aspect)
            flags = flags | (U.guard("pose_flags", standin.pose_flags, pc, pawn, P.state) or 0)
        elseif pose == 0 then
            camPos, camTarget, fovY = camera.own(pc, aspect)
        end
        feet, quat = standin.where(pawn)
        camera.tag(pawn, k)
        if dev and tick % 30 == 0 then centerDist = U.guard("trace_center", trace_center, pawn, camPos, camTarget) or 0 end
    end
    if env.busy then flags = flags | P.state.HOST_BUSY end
    if env.dead then flags = flags | P.state.PLAYER_DEAD end
    poseHist[k] = pose

    shm.publish(OFF.luastate, string.pack("<I4I8fffffffffffffffffffI4I8I4f", flags, frame,
        camPos[1], camPos[2], camPos[3], camTarget[1], camTarget[2], camTarget[3], 0, 1, 0,
        fovY, P.tune.host_near_m, 0,
        feet[1], feet[2], feet[3], quat[1], quat[2], quat[3], quat[4],
        1, pose, tick, centerDist) .. string.pack("<" .. string.rep("I8", TAGS), table.unpack(poseHist, 0, TAGS - 1)))

    env.feet, env.pose = feet, pose
    for _, s in ipairs(systems) do
        if s.name ~= "life" then U.guard(s.name, s.mod.tick, env) end
    end
end

function M.start(runtimeDir, isDev)
    runtime, dev = runtimeDir, isDev
    local hooked = false
    local gen = _G.PALCRAFT_GEN -- a reloaded copy of the mod retires this one's hook
    local function try_hook()
        if hooked then return end
        local ok, err = pcall(RegisterHook, P.hook.tick, function(ctx)
            if gen ~= _G.PALCRAFT_GEN then return end
            U.guard("tick", on_tick, ctx:get())
            if dev then U.guard("dev", require("dev").tick) end
        end)
        if ok then
            hooked = true
            U.log("frame loop hooked")
        end
    end
    try_hook()
    -- The player controller's class only exists once a world is loading: keep trying until then.
    LoopAsync(2000, function()
        if hooked or gen ~= _G.PALCRAFT_GEN then return true end
        ExecuteInGameThread(try_hook)
        return false
    end)
end

return M
