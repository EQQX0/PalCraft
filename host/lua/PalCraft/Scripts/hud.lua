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
local FADE = { "WBP_IngameHungerGauge", "WBP_Ingame_Thermometer", "WBP_IngameStatusPoint", "Canvas_WeaponInfo" }
local HEALTH = "Canvas_HP" -- a part of the gauge like those, but Palworld gave it no property: found by walking
local LEVEL = "WBP_PLLvExp" -- its level and experience: Minecraft's experience bar shows both
local PLAYER_UI = "WBP_PlayerUI_C" -- the HUD widget all of these sit in
local PREVIEW_HOME = "CanvasPanelChara" -- the panel of the inventory screen that holds the character preview
local DEPTH = 6
local SLOTS = 8 -- Minecraft's hotbar has nine: eight tools and the sphere

local swapped = false
local reapply = 0
local healthTick = 0
local sentHealth, sentAway, sentPreview = -1, -1, -1
local sentLoadout
local PANEL, USER
local building = false
local previewFaded, previewCount = false, 0

-- A property that holds a widget, or nil.
local function part(owner, name)
    local ok, w = pcall(function() return owner[name] end)
    if ok and w and w:IsValid() then return w end
    return nil
end

-- No widget is kept from one tick to the next (see util.lua). Palworld's own properties lead to the gauge
-- each time: the HUD of the player controller, its list of widgets, the player panel in that list.
local function gauge(pc)
    local hud = pc.MyHUD
    if not (hud and hud:IsValid()) then return nil end
    local ui
    hud.HUDWidgets:ForEach(function(_, e)
        if ui then return end
        local w = e:get()
        if w and w:IsValid() and w:GetClass():GetFName():ToString() == PLAYER_UI then ui = w end
    end)
    local side = ui and part(ui, "WBP_PlayerSideInfo_Separated")
    return ui, side and part(side, "WBP_Ingame_PlayerGauge_Separated")
end

-- The way from a widget down to the one of a name, as steps: -1 into a widget's own tree, n to child n.
-- Steps are numbers, so the way can be kept where the widget cannot.
local function way_to(w, name, depth, steps)
    if not (w and w:IsValid()) then return false end
    if w:GetFName():ToString() == name then return true end
    if depth <= 0 then return false end
    if w:IsA(USER) then
        local tree = w.WidgetTree
        if tree and tree:IsValid() then
            steps[#steps + 1] = -1
            if way_to(tree.RootWidget, name, depth - 1, steps) then return true end
            steps[#steps] = nil
        end
    elseif w:IsA(PANEL) then
        for i = 0, w:GetChildrenCount() - 1 do
            steps[#steps + 1] = i
            if way_to(w:GetChildAt(i), name, depth - 1, steps) then return true end
            steps[#steps] = nil
        end
    end
    return false
end
local function walk(w, steps, name)
    for i = 1, #steps do
        if not (w and w:IsValid()) then return nil end
        if steps[i] < 0 then
            local tree = w.WidgetTree
            w = tree and tree:IsValid() and tree.RootWidget or nil
        else
            w = w:GetChildAt(steps[i])
        end
    end
    if w and w:IsValid() and w:GetFName():ToString() == name then return w end
    return nil
end
local healthWay
local function health_part(g)
    local w = healthWay and walk(g, healthWay, HEALTH)
    if w then return w end
    PANEL = PANEL or StaticFindObject("/Script/UMG.PanelWidget")
    USER = USER or StaticFindObject("/Script/UMG.UserWidget")
    local steps = {}
    healthWay = way_to(g, HEALTH, DEPTH, steps) and steps or nil
    return healthWay and walk(g, healthWay, HEALTH)
end

-- Fades Palworld's gauges out or back in. False while Palworld has no gauge on screen.
local function apply(pc, want)
    local ui, g = gauge(pc)
    if not g then return false end
    local opacity = want and 0 or 1
    for _, name in ipairs(FADE) do
        local w = part(g, name)
        if w then w:SetRenderOpacity(opacity) end
    end
    local hp = health_part(g)
    if hp then hp:SetRenderOpacity(opacity) end
    local level = part(ui, LEVEL)
    if level then level:SetRenderOpacity(opacity) end
    return true
end

-- Build mode has no menu and no mouse pointer: the character's builder says when it is on.
local function in_build_mode(pawn)
    local b = pawn.BuilderComponent
    return b ~= nil and b:IsValid() and b:IsInBuildingMode() == true
end

-- The character previews Palworld has made (its inventory screen has one, character creation another).
-- No property leads to them, so their paths are kept: see util.lua for what that costs. A search looks at
-- every object Palworld has, tens of milliseconds, so it runs only while a menu is open and no preview of
-- the inventory screen is known, and then once per hud_find_ms.
local PREVIEW = P.hook.menu_preview:match("%.([%w_]+)$")
local previews = { list = {}, pc = 0, nextSearch = 0 }
function previews.search()
    local list = {}
    for _, w in ipairs(FindAllOf(PREVIEW) or {}) do
        if w:IsValid() then
            -- Those under /Game are the patterns Palworld copies its screens from, not screens.
            local path = U.path(w)
            if path:find("/Engine/Transient", 1, true) then list[#list + 1] = path end
        end
    end
    previews.list = list
end
-- Drops the ones Palworld has thrown away; true if test fits one of the rest.
function previews.any(test)
    local hit = false
    for i = #previews.list, 1, -1 do
        local w = U.find(previews.list[i])
        if not w then
            table.remove(previews.list, i)
        elseif not hit and test(w) then
            hit = true
        end
    end
    return hit
end

-- The preview of the inventory screen, with every panel around it showing.
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
        building = body and (U.guard("build_mode", in_build_mode, env.pawn) or false)
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
        -- The paths of one world are of no use in the next, and asking for a path that is gone is slow.
        local at = env.pc:GetAddress()
        if at ~= previews.pc then previews.pc, previews.list, previewFaded = at, {}, false end
        if body and menu and U.now_ms() >= previews.nextSearch and not previews.any(in_inventory) then
            previews.nextSearch = U.now_ms() + P.tune.hud_find_ms
            previews.search()
        end
        if body ~= previewFaded or #previews.list ~= previewCount then fade_previews(body) end
        local preview = (body and menu and previews.any(preview_up)) and 1 or 0
        if preview ~= sentPreview then
            sentPreview = preview
            shm.put(OFF, B.preview, preview)
        end
    end

    -- Palworld animates these gauges itself (low health, hunger): say it again now and then.
    reapply = reapply - 1
    if body == swapped and not (body and reapply <= 0) then return end
    reapply = P.tune.hud_reapply_ticks
    swapped = U.guard("hud_swap", apply, env.pc, body) and body or false
end

return M
