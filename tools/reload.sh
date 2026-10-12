#!/usr/bin/env bash
# Dev: reload the Lua mod inside Palworld. A reload forgets which tools the old instance hid, so show them first.
cd /c/Users/Admin/PalCraft
python tools/repl.py "local pawn=FindFirstOf('PlayerController').Pawn local base=StaticFindObject('/Script/Pal.PalWeaponBase') pawn.Children:ForEach(function(i,e) local a=e:get() if a and a:IsValid() and a:IsA(base) and not a:GetClass():GetFName():ToString():find('Dummy') then a:SetActorHiddenInGame(false) end end) P('tools shown')" | tail -1
python tools/repl.py "dofile([[C:\\Users\\Admin\\PalCraft\\host\\lua\\PalCraft\\Scripts\\main.lua]]) P('reloaded')" | tail -1
sleep 2; tail -3 runtime/palcraft_lua.log | cut -c1-200
