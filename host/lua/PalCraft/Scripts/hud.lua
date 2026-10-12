-- System "hud_swap": in Palworld mode the HUD is Minecraft's. Hearts show the character's health and the
-- hunger bar its stomach, so Palworld's own health, hunger and temperature gauges step aside. Everything
-- Minecraft has no picture for stays Palworld's: prompts, compass, the Pal party, key guides, boss bars.
-- System "loadout_hotbar": Minecraft's hotbar shows the tools in Palworld's weapon slots and its spheres.
-- System "menu_steve": Palworld's inventory screen shows Steve where its own character stood.
local P = require("gen_protocol")
local U = require("util")
local shm = require("shm")
local camera = require("camera")
local M = {}

local OFF, B = P.off.body, P.Body
-- Named parts of Palworld's player gauge. Faded parts keep their place in the layout. The stat-point banner
-- sits where Minecraft's hotbar is drawn; Minecraft's chat says when there are points to spend. The weapon
-- panel is Minecraft's hotbar now.
local FADE = { Canvas_HP = true, WBP_IngameHungerGauge = true, WBP_Ingame_Thermometer = true,
    WBP_IngameStatusPoint = true, Canvas_WeaponInfo = true }
local LEVEL = "WBP_PLLvExp_C" -- its level and experience: Minecraft's experience bar shows both
local PREVIEW_HOME = "CanvasPanelChara" -- the panel of the inventory screen that holds the character preview
local DEPTH = 6
local SLOTS = 8 -- Minecraft's hotbar has nine: eight tools and the sphere

local parts            -- name -> widget, of the gauge on screen
local swapped = false
local nextFind = 0
local reapply = 0
local healthTick = 0
local sentHealth, sentAway, sentPreview = -1, -1, -1
local sentLoadout
local PANEL, USER
local building = false
local previewFaded, previewCount = false, 0

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
                break
            end
        end
    end
    if not parts then return end
    local n = 0
    for _, w in ipairs(FindAllOf(LEVEL) or {}) do
        -- The one on screen has its widgets built; the pattern Palworld copies it from has none.
        if w:IsValid() and w.WidgetTree and w.WidgetTree:IsValid() then
            n = n + 1
            parts[LEVEL .. n] = w
        end
    end
end

-- Screens Palworld makes when the player first asks for them: take those that exist, then let Palworld tell
-- us about each new one. Neither works before Palworld has loaded the class, so ask until it has.
local function watcher(path)
    local self = { list = {}, on = false }
    local short = path:match("%.([%w_]+)$")
    function self.watch()
        if self.on then return end
        local class = StaticFindObject(path)
        if not (class and class:IsValid()) then return end
        self.on = true
        for _, w in ipairs(FindAllOf(short) or {}) do
            if w:IsValid() then self.list[#self.list + 1] = w end
        end
        local gen = _G.PALCRAFT_GEN
        NotifyOnNewObject(path, function(w)
            if gen ~= _G.PALCRAFT_GEN then return true end
            self.list[#self.list + 1] = w
        end)
    end
    -- Drops the ones Palworld has thrown away; true if test fits one of the rest.
    function self.any(test)
        local hit = false
        for i = #self.list, 1, -1 do
            local w = self.list[i]
            if not w:IsValid() then
                table.remove(self.list, i)
            elseif not hit and test(w) then
                hit = true
            end
        end
        return hit
    end
    return self
end
local builders = watcher(P.hook.build_screen)
local previews = watcher(P.hook.menu_preview)

local function visible(w)
    return w:IsVisible()
end

-- The preview of the inventory screen (character creation has one too), with every panel around it showing.
local function in_inventory(w)
    local parent = w:GetParent()
    return parent and parent:IsValid() and parent:GetFName():ToString() == PREVIEW_HOME
end
local function preview_up(w)
    if not (in_inventory(w) and w:IsVisible()) then return false end
    local parent = w:GetParent()
    for _ = 1, 6 do
        if not (parent and parent:IsValid()) then break end
        if not parent:IsVisible() then return false end
        parent = parent:GetParent()
    end
    return true
end

local function fade_previews(want)
    previews.any(function(w)
        if in_inventory(w) then w:SetRenderOpacity(want and 0 or 1) end
        return false
    end)
    previewFaded, previewCount = want, #previews.list
end

local function alive()
    return parts and parts.Canvas_HP:IsValid()
end

local function apply(want)
    for _, w in pairs(parts) do
        if w:IsValid() then w:SetRenderOpacity(want and 0 or 1) end
    end
end

-- What the character carries in its weapon slots, as Palworld's class names without their BP_ and _C.
local function loadout(env)
    local sel = env.pawn.LoadoutSelectorComponent
    if not (sel and sel:IsValid()) then return end
    local inv = env.pc.PlayerState:GetInventoryData()
    local slot = sel.currentItemSlotIndex
    local weapons = sel.spawnedWeaponsArray
    local count = math.min(#weapons, inv:GetUnlockedWeaponSlotNum(), SLOTS)
    local names, held = {}, nil
    for i = 1, count do
        local a = weapons[i]
        if a and a:IsValid() then
            names[i] = a:GetClass():GetFName():ToString():gsub("^BP_", ""):gsub("_C$", "")
            if i == slot + 1 then held = a end
        else
            names[i] = ""
        end
    end
    local ammo, spare = -1, 0
    if held then
        spare = held:GetInventoryBulletCount()
        if held:GetMagazineSize() > 0 or spare > 0 then ammo = held:GetRemainBulletCount() end
    end
    local ball = sel.NowEquipBallItemID
    local id = ball:ToString()
    local balls = id ~= "None" and inv:CountItemNum(ball) or 0
    if balls <= 0 then id = "" end
    local tools = table.concat(names, "|"):sub(1, B.loadout[3] - 1)
    id = id:sub(1, B.ball[3] - 1)
    local key = table.concat({ slot, balls, ammo, spare, tools, id }, ";")
    if key == sentLoadout then return end
    sentLoadout = key
    shm.write(OFF + B.toolSlot[1], string.pack("<i4I4i4I4", slot, balls, ammo, spare))
    shm.put(OFF, B.loadout, tools)
    shm.put(OFF, B.ball, id)
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
        builders.watch()
        previews.watch()
        building = body and builders.any(visible)
        local cp = env.pawn.CharacterParameterComponent
        if cp and cp:IsValid() then
            local max = cp:GetMaxHP().Value
            local health = max > 0 and math.max(0, math.min(1, cp:GetHP().Value / max)) or 0
            if math.abs(health - sentHealth) > 0.002 then
                sentHealth = health
                shm.put(OFF, B.health, health)
            end
        end
        if body then U.guard("loadout", loadout, env) end
        if body ~= previewFaded or #previews.list ~= previewCount then fade_previews(body) end
        local preview = (body and menu and previews.any(preview_up)) and 1 or 0
        if preview ~= sentPreview then
            sentPreview = preview
            shm.put(OFF, B.preview, preview)
        end
    end

    if body and not alive() and U.now_ms() >= nextFind then
        nextFind = U.now_ms() + P.tune.hud_find_ms
        parts = nil
        find()
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
