-- System "coop_players": the other players of a co-op session. Minecraft draws each as a player of its own,
-- so their Palworld bodies are hidden here, on this PC only.
local P = require("gen_protocol")
local U = require("util")
local shm = require("shm")
local M = {}

local OFF = P.off.players
local MAXN = P.const.MAX_PLAYERS
local F = P.player
local known = {}      -- every player character alive, by address
local watching = false
local facts = {}      -- address -> { id, name, tool }: what changes slowly, looked up every player_scan_ticks
local scan = 0
local others = 0
local empty = false
-- Bodies this mod hid, by address. Kept across a reload of the mod, so the new copy can show them again.
_G.PALCRAFT_HID = _G.PALCRAFT_HID or {}
local hid = _G.PALCRAFT_HID
local posed = {}
local KISMET

-- Co-op waits for two people to play it: tuning row coop_enabled. While it is 0 nothing here runs.
-- Before it is switched on: known and M.fake hold objects from one tick to the next, which is what crashed
-- 0.2.1, and watch() asks Palworld for new objects, which crashed it too (see util.lua). Both go first:
-- PalUtility:GetPalObjectCollector(pawn).PalCharacter_Player is Palworld's own list of player characters.
local ON = P.tune.coop_enabled ~= 0

-- Searching all of Palworld's objects takes tens of milliseconds: do it once, then let Palworld tell us
-- about each new player character.
local function watch()
    if watching then return end
    watching = true
    for _, a in ipairs(FindAllOf("PalPlayerCharacter") or {}) do
        if a:IsValid() then known[a:GetAddress()] = a end
    end
    local gen = _G.PALCRAFT_GEN
    NotifyOnNewObject(P.hook.player_chars, function(a)
        if gen ~= _G.PALCRAFT_GEN then return true end
        known[a:GetAddress()] = a
    end)
end

-- True for the character of any player, this PC's own included: system "pals" leaves them out.
function M.is_player(addr) return known[addr] ~= nil end

-- True while a friend's character is in reach of this PC. A host has every friend's character at all times.
function M.any() return others > 0 end

-- Development: a character that stands in for a friend, so one PC can show what a friend looks like.
function M.pretend(a)
    M.fake = a
    scan = 0
end

-- A hidden mesh is hidden with everything fastened to it: clothes, hair, the tool in hand. Hiding the
-- actor would do the same, but Unreal sends a host's hidden actors to every PC of the session.
local function show(a, want)
    local mesh = a.Mesh
    if mesh and mesh:IsValid() then mesh:SetVisibility(want, true) end
end

-- Unreal stops posing a mesh nobody sees, and its actions with it: see standin.lua.
local function keep_posing(a, at)
    if posed[at] then return end
    KISMET = KISMET or StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
    local mesh = a.Mesh
    if not (KISMET and KISMET:IsValid() and mesh and mesh:IsValid()) then return end
    KISMET:SetBytePropertyByName(mesh, FName("VisibilityBasedAnimTickOption"), 0)
    posed[at] = true
end

local function clip(s, n)
    if #s <= n then return s end
    while n > 0 and s:byte(n + 1) & 0xC0 == 0x80 do n = n - 1 end -- never cut a letter in half
    return s:sub(1, n)
end

local function tool_of(a)
    local sel = a.LoadoutSelectorComponent
    if not (sel and sel:IsValid()) then return "" end
    local weapons = sel.spawnedWeaponsArray
    local held = weapons[sel.currentItemSlotIndex + 1]
    if held and held:IsValid() then
        return (held:GetClass():GetFName():ToString():gsub("^BP_", ""):gsub("_C$", ""))
    end
    if sel.currentItemSlotIndex >= #weapons then
        local ball = sel.NowEquipBallItemID:ToString()
        if ball ~= "None" then return ball end
    end
    return ""
end

-- Name, id and tool of one friend.
local function look_up(a, at)
    local f = facts[at] or { id = at, name = "", tool = "" }
    facts[at] = f
    if at == M.fakeAt then
        f.name = "Friend"
    else
        local ps = a.PlayerState
        if ps and ps:IsValid() then
            local id = ps.PlayerId
            if id and id ~= 0 then f.id = id end
            pcall(function() f.name = clip(ps:GetPlayerName():ToString(), P.PlayerRow.name[3] - 1) end)
        end
    end
    local ok, tool = pcall(tool_of, a)
    f.tool = ok and clip(tool, P.PlayerRow.tool[3] - 1) or ""
    return f
end

local function describe(a, at)
    local f = facts[at]
    if not f then return nil end
    local l = a:K2_GetActorLocation()
    local half = 88
    local cap = a.CapsuleComponent
    if cap and cap:IsValid() then half = cap:GetScaledCapsuleHalfHeight() end
    local flags = 0
    local swim = false
    local cm = a.CharacterMovement
    if cm and cm:IsValid() then
        swim = cm.MovementMode == 4 -- MOVE_Swimming
        if swim then flags = flags | F.SWIM
        elseif a.bIsCrouched then flags = flags | F.CROUCH end
    end
    -- A swimmer's middle sits under the surface: see standin.where.
    local x, y, z = U.to_host(l.X, l.Y, l.Z - (swim and -P.tune.swim_feet_m * 100 or half))
    local health = 1
    local cp = a.CharacterParameterComponent
    if cp and cp:IsValid() then
        local max = cp:GetMaxHP().Value
        if max > 0 then health = math.max(0, math.min(1, cp:GetHP().Value / max)) end
        if cp:IsDead() then flags = flags | F.DEAD end
    end
    local pitch = 0
    pcall(function() pitch = a:GetBaseAimRotation().Pitch end)
    if pitch > 180 then pitch = pitch - 360 end
    local acting = false
    pcall(function() acting = a.Mesh:GetAnimInstance():IsAnyMontagePlaying() end)
    if acting then flags = flags | F.ACT end
    return string.pack("<I8I4ffffffc12c32c48", f.id, flags, health, x, y, z, a:K2_GetActorRotation().Yaw, pitch,
        "", f.name, f.tool)
end

function M.tick(env)
    if not ON then return end
    watch()
    scan = scan - 1
    local slow = scan <= 0
    if slow then scan = P.tune.player_scan_ticks end
    local mine = env.hasPawn and env.pawn:GetAddress() or 0
    M.fakeAt = M.fake and M.fake:IsValid() and M.fake:GetAddress() or nil
    if M.fakeAt then known[M.fakeAt] = M.fake end
    -- Their Minecraft players are drawn only while Minecraft's picture is in Palworld's.
    local draw = env.linked and env.steves and true or false
    local rows, n = {}, 0
    for at, a in pairs(known) do
        if not a:IsValid() then
            known[at], facts[at], hid[at], posed[at] = nil, nil, nil, nil
        elseif at ~= mine then
            if slow then
                local ps = a.PlayerState
                if at == M.fakeAt or (ps and ps:IsValid()) then U.guard("player_facts", look_up, a, at)
                else facts[at] = nil end -- a character without a player: the preview of a menu
                if not facts[at] and hid[at] then
                    U.guard("player_show", show, a, true)
                    hid[at] = nil
                end
            end
            if facts[at] then
                n = n + 1
                if draw and #rows < MAXN then
                    local ok, row = pcall(describe, a, at)
                    if ok and row then rows[#rows + 1] = row end
                end
                if draw and (slow or not hid[at]) then
                    U.guard("player_posing", keep_posing, a, at)
                    U.guard("player_hide", show, a, false)
                    hid[at] = true
                elseif not draw and hid[at] then
                    U.guard("player_show", show, a, true)
                    hid[at] = nil
                end
            end
        end
    end
    others = n
    if not env.linked then return end
    if #rows == 0 and empty then return end
    empty = #rows == 0
    -- seq, count, frame, then the rows
    shm.publish(OFF, string.pack("<I4I8", #rows, env.tick) .. table.concat(rows))
end

return M
