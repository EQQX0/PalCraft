-- System "hud_swap": in Palworld mode the HUD is Minecraft's. Hearts show the character's health and the
-- hunger bar its stomach, so Palworld's own health, hunger and temperature gauges step aside. Everything
-- Minecraft has no picture for stays Palworld's: prompts, compass, the Pal party, tools, boss bars.
local P = require("gen_protocol")
local U = require("util")
local shm = require("shm")
local camera = require("camera")
local M = {}

local OFF, B = P.off.body, P.Body
-- Named parts of Palworld's player gauge. Faded parts keep their place in the layout. The stat-point banner
-- sits where Minecraft's hotbar is drawn; Minecraft's chat says when there are points to spend.
local FADE = { Canvas_HP = true, WBP_IngameHungerGauge = true, WBP_Ingame_Thermometer = true,
    WBP_IngameStatusPoint = true }
local DEPTH = 6

local parts            -- name -> widget, of the gauge on screen
local swapped = false
local nextFind = 0
local reapply = 0
local healthTick = 0
local sentHealth, sentAway = -1, -1
local PANEL, USER
-- Palworld's build-mode screens. It makes the one it shows the first time the player builds: take those
-- that exist, then let Palworld tell us about each new one.
local builders = {}
local watching = false
local building = false

local function collect(w, depth, out)
    if not (w and w:IsValid()) then return end
    local name = w:GetFName():ToString()
    if FADE[name] then out[name] = w end
    if depth <= 0 then return end
    if w:IsA(USER) then
        local tree = w.WidgetTree
        if tree and tree:IsValid() then collect(tree.RootWidget, depth - 1, out) end
    elseif w:IsA(PANEL) then
        for i = 0, w:GetChildrenCount() - 1 do collect(w:GetChildAt(i), depth - 1, out) end
    end
end

-- Searching all of Palworld's objects takes tens of milliseconds: once per gauge, and again only after
-- Palworld has thrown that gauge away (a new world).
local function find()
    PANEL = PANEL or StaticFindObject("/Script/UMG.PanelWidget")
    USER = USER or StaticFindObject("/Script/UMG.UserWidget")
    if not (PANEL and PANEL:IsValid() and USER and USER:IsValid()) then return end
    for _, w in ipairs(FindAllOf("WBP_Ingame_PlayerGauge_Separated_C") or {}) do
        if w:IsValid() then
            local out = {}
            collect(w, DEPTH, out)
            if out.Canvas_HP then
                parts = out
                return
            end
        end
    end
end

local function watch_builders()
    if watching then return end
    local class
    for _, w in ipairs(FindAllOf("WBP_IngameConstruction_C") or {}) do
        if w:IsValid() then
            builders[#builders + 1] = w
            class = class or w:GetClass():GetFullName():match("%s(/.+)$")
        end
    end
    if not class then return end
    watching = true
    local gen = _G.PALCRAFT_GEN
    NotifyOnNewObject(class, function(w)
        if gen ~= _G.PALCRAFT_GEN then return true end
        builders[#builders + 1] = w
    end)
end

local function in_build_mode()
    for i = #builders, 1, -1 do
        local w = builders[i]
        if not w:IsValid() then
            table.remove(builders, i)
        elseif w:IsVisible() then
            return true
        end
    end
    return false
end

local function alive()
    return parts and parts.Canvas_HP:IsValid()
end

local function apply(want)
    for _, w in pairs(parts) do
        if w:IsValid() then w:SetRenderOpacity(want and 0 or 1) end
    end
end

function M.tick(env)
    local body = env.linked and env.hasPawn and not env.busy and (env.cflags or 0) & P.ctrl.HOST_BODY ~= 0

    -- A shot, a menu or a screen Palworld shows by itself stands alone: Minecraft holds its HUD back.
    -- Palworld brings its mouse pointer out for every menu; build mode has none and is asked about.
    local menu = env.pc and env.pc:IsValid() and env.pc.bShowMouseCursor == true
    local away = (env.dead or menu or building or camera.yielding()) and 1 or 0
    if away ~= sentAway then
        sentAway = away
        shm.put(OFF, B.hudAway, away)
    end

    healthTick = healthTick - 1
    if env.hasPawn and healthTick <= 0 then
        healthTick = P.tune.hud_health_ticks
        building = body and in_build_mode()
        local cp = env.pawn.CharacterParameterComponent
        if cp and cp:IsValid() then
            local max = cp:GetMaxHP().Value
            local health = max > 0 and math.max(0, math.min(1, cp:GetHP().Value / max)) or 0
            if math.abs(health - sentHealth) > 0.002 then
                sentHealth = health
                shm.put(OFF, B.health, health)
            end
        end
    end

    if body and not alive() and U.now_ms() >= nextFind then
        nextFind = U.now_ms() + P.tune.hud_find_ms
        parts = nil
        find()
        watch_builders()
    end
    if not alive() then
        swapped = false
        return
    end
    -- Palworld animates these gauges itself (low health, hunger): say it again now and then.
    reapply = reapply - 1
    if body ~= swapped or (swapped and reapply <= 0) then
        swapped = body
        reapply = P.tune.hud_reapply_ticks
        apply(body)
    end
end

return M
