-- Dev: from Palworld's title screen into the world "PalCraft Test", through the title screens' own handlers
-- instead of clicks, so nothing takes the mouse or the keyboard. Run it again until it prints "started":
--   python tools/repl.py -f tools/pal_enter.lua
-- The other worlds on this PC are the owner's own: this only ever starts the one of this name.
local NAME = 'PalCraft Test'
local function live(class)
    for _, w in ipairs(FindAllOf(class) or {}) do
        if w:IsValid() and w:GetFullName():find('/Engine/Transient', 1, true) then return w end
    end
end
local function call(w, fn, ...)
    local ok, err = pcall(w[fn], w, ...)
    if not ok then P('call failed: ' .. fn .. ': ' .. tostring(err)) end
    return ok
end

local notice = live('WBP_ModCautionDialog_ExternalCrash_C')
if notice and notice:IsVisible() then
    call(notice, 'BndEvt__WBP_ModDisclaimerDialog_WBP_CommonButton_K2Node_ComponentBoundEvent_1_OnClicked__DelegateSignature')
    P('step: crash notice closed')
    return
end
local list = live('WBP_TitleLocalWorldSelect_C')
if not list then
    local menu = live('WBP_TitleMenu_C')
    if not menu then P('no title menu: not at the title screen') return end
    call(menu, 'BndEvt__WBP_TitleMenu_WBP_Title_MenuButton_StartLocalGame_K2Node_ComponentBoundEvent_0_OnClicked__DelegateSignature')
    P('step: world list opened')
    return
end
if list['Selected World Name']:ToString() ~= NAME then
    for _, w in ipairs(FindAllOf('WBP_Title_WorldSelect_ListContent_C') or {}) do
        if w:IsValid() and w:GetFullName():find('/Engine/Transient', 1, true) and w['World Name']:ToString() == NAME then
            call(w, 'BndEvt__WBP_Title_WorldSelect_ListContent_WBP_PalInvisibleButton_K2Node_ComponentBoundEvent_0_CommonButtonBaseClicked__DelegateSignature',
                w.WBP_PalInvisibleButton)
            P('step: row selected')
            return
        end
    end
    P('no world named ' .. NAME)
    return
end
call(list, 'BndEvt__WBP_TitleLocalWorldSelect_WBP_Title_WorldSelect_K2Node_ComponentBoundEvent_2_OnClickedStartWorldButton__DelegateSignature')
-- With runtime/dev_quiet in place the console's timer stops here: scripts wait for the frame loop.
local quiet = io.open('C:/Users/Admin/Desktop/repos/PalCraft/runtime/dev_quiet', 'rb')
if quiet then quiet:close() _G.PALCRAFT_DEV_QUIET = true end
P('started')
