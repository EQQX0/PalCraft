# PalCraft MODLOG

Mashup: play Palworld as your Minecraft player. Host (primary) = Palworld, companion = Minecraft: Java Edition.
Design agreed with creator 2026-10-11: walk + build + fight (Minecraft weapons hurt Pals, Pals hurt you in
survival), F8 hands control back to Palworld; solo now, built so co-op can come later; survival with a starter
kit; MIT + remixes allowed (recommended option, to confirm before publish).

## Facts
- Palworld 1.0, Steam app 1623730, build 25246127, `C:\Program Files (x86)\Steam\steamapps\common\Palworld`.
  UE 5.1, DX11 by default (`-dx12` is a second Steam launch option). Exe has no version resource.
- Never launched on this PC before 2026-10-11: no `%LOCALAPPDATA%\Pal` yet (no saves to back up).
- Melty installs UE4SS v3.0.1 (mods in `Pal/Binaries/Win64/Mods`). 3.0.1 Lua has LoopAsync,
  ExecuteInGameThread, RegisterHook, package.loadlib; no LoopInGameThread*.
- Work folder is `C:\Users\Admin\PalCraft` (the session's own folder path is too long for git/Gradle).
- Tools (portable, in `.tools/`): llvm-mingw 20261006, Temurin JDK 25.0.4.1, UE4SS v3.0.1 zip.
- Reference code (MIT): `ref/Minecraft-Ring` (justbustin + siddoff bridge), `ref/universal-modder`.

## Route
Passthrough (two games at once), frame compositing, DRIVE_HOST camera:
- Minecraft (Fabric 1.21.1, fork of Minecraft Ring's mc-bridge): owns the player, camera, blocks, combat.
  Publishes frames (world colour+depth, hand, HUD) to `frames.shm` and pose/control to `bridge.shm`.
- Palworld UE4SS Lua mod: applies the camera pose, moves the hidden Palworld character to Steve, answers
  terrain rays with line traces, publishes Pals as entities, applies damage both ways. Talks to `bridge.shm`
  with plain file IO (Windows keeps file IO and mapped views coherent).
- Native DLL loaded by the Lua mod (`package.loadlib`): hooks DXGI Present (D3D11), finds scene depth,
  draws Minecraft's layers into Palworld's frame, publishes window rect + heartbeat.
Host coords in the protocol: metres, left-handed, x right / y up / z forward. UE (cm): host = (Y, Z, X) / 100.

## Dev loop
- Dev UE4SS copy installed by hand into `Pal/Binaries/Win64` (same version Melty installs).
- `runtime/dev_in.lua` -> executed on the game thread by the mod, result in `runtime/dev_out.txt`.

## Log
- 2026-10-12 0.2.0 survival update. Melty showed 0.1.0 live (published 2026-10-11 20:06 UTC from the creator's
  side), so this went up as 0.2.0, draft release fe5478d2. Test ce85d3bd: 2 runs, all four self-checks pass.
  First try failed Melty's loader-errors check on AppleSkin's JEI mixin warning; package.py now drops that
  mixin config from AppleSkin's fabric.mod.json (Unlicense). Melty removes the old jar on update.
- Asked for and not shipped: Upgrader items (EXEcheINZ, All Rights Reserved, Modrinth) and Studious Keybinds
  (StudiousGoose, no license, CurseForge). Fabric 1.21.1 jars are in .tools/dl/extras. Melty's standard wants
  everything in the release and its license to allow sharing; a fetch-at-launch step was refused. Needs the
  authors' permission, or the creator's word that they hold the rights.
- Armor: palcraft:monster and monster_hit stay out of bypasses_armor; measured 9.0 raw -> 8.1 leather,
  5.22 iron, 2.61 diamond (vanilla formula). Status (cold, heat, poison) bypasses armor by design.
- Night at the start area is temperature -1 with cold resist 0: Steve freezes slowly unless he holds a torch,
  stands by a fire or wears leather.
- This PC's installed world had Steve in creative (playerGameType 1); set back to survival during the test.
- 2026-10-12 0.2.0 published on the creator's word ("Publish"); Melty confirmed it live at 2026-10-11 21:56 UTC. Two screenshots added (third person, survival HUD), tagline updated. The two extra mods wait for the authors' permission; planned for 0.2.1.
- 2026-10-12 Creator asked again to put the two mods in with credit and CurseForge links. Not bundled (no permission from the authors; credit does not replace it). Listing description rewritten for 0.2.0 with an Optional add-ons section naming both authors and linking their CurseForge pages; same section in README for 0.2.1. Both mods start beside PalCraft in the dev client (title screen only).
- 2026-10-12 Creator: drop the optional add-ons section, add a how-to for mods and skins. Listing description and README now carry 'Add your own mods' and 'Change your skin'; the two mods are no longer named anywhere on the page.
- 2026-10-12 0.2.1. Played Palworld's opening as Steve in Palworld mode (F8) and fixed what broke:
  - LEAK: UE4SS 3.0.1 takes a registry reference (luaL_ref) to every table passed as an out parameter and never
    frees it. LineTraceSingle's hit table kept 3,016 bytes per call; with the terrain scan that was 23 MB/s,
    81 GB of Lua after 80 minutes, and the PC ran out of commit. 0.2.0 has it. Fix: util.release(t) after each
    such call (registry[k] = registry[3]; registry[3] = k, as luaL_unref does). Lua now sits at 17-32 MB.
    Self-check memory-steady guards it. Measure with tools/palmem.sh and collectgarbage('count').
  - Palworld's dialogue camera (BP_PalIncidentCamera) works out its place from the player's camera and landed
    3 km away while our CameraActor was the view target. Palworld mode now leaves the pawn as view target and
    poses pawn.FollowCamera directly (SetAbsolute + K2_SetWorldLocationAndRotation); the arm's wish is read from
    CameraBoom:GetSocketTransform('SpringEndpoint'). CameraBoom.TargetArmLength is reset by Palworld each tick.
  - Steve vanished after a long move in Palworld mode: the server tracks chunks from client move packets and
    there are none there. HostBodyServer calls getChunkSource().move(player).
  - Palworld's UI drew under the Minecraft layers: composite right after the first back-buffer draw (ui_order).
  - Crash 0xe06d7363 in UE4SS during a run of 60 dev console calls: the console's LoopAsync ran Lua beside the
    frame hook. The console now runs inside the frame hook while it is alive. Release builds stop their only
    LoopAsync once the hook is in.
  - Never again: GenerateSDK() and guessed native signatures (AddItem_ServerInternal...) crash Palworld.
    UFunction parameter reflection is not available in UE4SS 3.0.1 Lua; BP classes do support ForEachFunction.
  - Useful calls: PalUtility:GiveExpToAroundPlayerCharacter(ctx, FVector, radius, exp, bool),
    cp:SetHP({Value = hp*1000}), inv:CountItemNum(FName), pawn:K2_SetActorLocation(loc, false, {}, true).
  - Melty switches the loader off (dwmapi.dll -> .melty-off) whenever Palworld exits; tools/pal_up.sh puts it
    back for dev runs. tools/pal_dev.sh starts Palworld and clicks into the world.
  - Verified by play in Palworld mode: statue + fast travel unlock, NPC talk, survival guide, tech tree, build
    menu, workbench, crafting, Pal Sphere throw and capture, summon, cold, defeat, respawn map, F8 both ways.
    Not tested: riding, gliding, guns, raids, towers, swimming pose.
  - Played the installed build during Melty's test runs and fixed two more things:
    - A wall behind Steve collapses Palworld's camera arm and the camera sat 0.5 m from his back, so he
      filled the screen. Minecraft skips drawing him under 1.25 m (back at 1.5 m): HostBody.watchCamera,
      EntityRendererMixin.shouldRender.
    - SetActorHiddenInGame on the character leaves what it holds visible: tools are actors of their own in
      pawn.Children (PalWeaponBase). standin.lua hides the visible ones with the character, remembers which,
      and shows those again with it. A Lua reload forgets the list and leaves them hidden (dev only).
      ItemInHandLayerMixin empties Steve's hands in Palworld mode.
    - Driving an installed build: tools/mcdrive.py sends keys to Minecraft's input window. tools/pal.sh and
      `um win shot` put Palworld's window in front, so Minecraft loses the keyboard after each screenshot;
      F8 hand-over itself works both ways (checked with mcdrive --raw).
  - Played Palworld mode down the untested list (dev build) and fixed what broke:
    - Mining and melee hit nothing: Unreal stops refreshing the bones of a mesh nobody sees, and a swing is
      the tool swept along the hand bone. standin.lua sets the hidden character's mesh to option 0 (always
      tick pose and refresh bones) through KismetSystemLibrary:SetBytePropertyByName. Measured at one rock,
      6 s of mining: hidden 0 stone, shown 11, hidden with the fix 10. Lamball 584 -> 217 HP in 2.5 s.
    - UE4SS 3.0.1 crashed Palworld (access violation in UE4SS) reading the enum property
      VisibilityBasedAnimTickOption from Lua. K2_GetComponentsByClass from Lua crashed it too. Neither is
      in the mod. GetAttachedActors with a table as out parameter returns nothing.
    - The pickaxe on the back while a sphere is in hand is a PalBackWeaponBase: attached to the character,
      owned by nobody, absent from pawn.Children. FindAllOf costs 34 ms, so standin.lua takes the existing
      ones once and NotifyOnNewObject reports new ones.
    - Defeat: life.lua keeps Palworld mode drawing while the character is dead; HostBody raises deathTime.
    - Swimming (MovementMode 4): Steve lay under the surface; swim_feet_m lifts him to the waterline.
    - Worked as they were: sphere throw and capture attempt, Rayne Syndicate Tower (join prompt, confirm,
      loading screen, intro cutscene, arena, boss bar, defeat, respawn, death chest at the entrance),
      crafting cloth and a parachute, gliding (the parachute shows above Steve), build mode, conversations.
    - Not reached: riding (needs a saddle and a mount), bows and guns (30 wood and 15 fiber short), raids
      (Palworld starts them). PalCheatManager exists in the shipped game with empty native bodies: GetItem,
      SetPlayerHP and console commands do nothing, so test gear comes from play.
    - A workbench outside a base is gone after a defeat and respawn. Palworld's rule, not the mod.
  - Minecraft's HUD in Palworld mode, at the creator's request (system hud_swap):
    - HostBody no longer hides the GUI. Hearts and hunger show Body.health and Body.stomach on the client
      copy of Steve only; the server keeps his own, and leaving Palworld mode reads them back. Health never
      reaches zero on the client, or Minecraft opens its death screen. No crosshair (GuiMixin).
    - hud.lua fades Canvas_HP, WBP_IngameHungerGauge, WBP_Ingame_Thermometer and WBP_IngameStatusPoint
      inside WBP_Ingame_PlayerGauge_Separated_C with SetRenderOpacity, re-applied every 30 ticks.
      SetRenderOpacity on the whole gauge hides the Pal party and tool panel too.
    - Body.hudAway: the character is dead, a shot of Palworld's own is up (camera.yielding), its mouse
      pointer is out (pc.bShowMouseCursor, true in every menu) or WBP_IngameConstruction_C is visible
      (build mode shows no pointer; Palworld makes that widget the first time the player builds).
    - A new Lua module must be in main.lua's reload list, or a dev reload keeps running the old copy.
    - Melty's test run of the installed build showed Minecraft's block outline in the world behind Steve in
      Palworld mode. GameRendererMixin answers shouldRenderBlockOutline with false there.
    - Driving an installed build: F8 goes to Minecraft's input window (tools/mcdrive.py). Sent to Palworld's
      window in Minecraft mode it only hands focus back to Minecraft.
  - "Debug all issues", then "In inventory show steve" and "Add Minecraft crosshair on f5 too":
    - Hotbar (system loadout_hotbar, sheets/tools.json): hud.lua reads LoadoutSelectorComponent
      (currentItemSlotIndex, spawnedWeaponsArray, NowEquipBallItemID) and the inventory's CountItemNum, and
      writes class names into Body.loadout. LoadoutHud maps them to Minecraft items, first match wins.
      While a sphere is aimed currentItemSlotIndex is the slot after the weapon slots (4 with 4 unlocked).
    - Experience bar: Body.level and Body.expFrac from PalExpDatabase:GetTotalExp(level, true).
    - Inventory Steve (system menu_steve): the compositor puts Minecraft's layers in before Palworld draws
      its interface, so a doll in the HUD layer sat blurred under the menu. Minecraft now writes
      Body.previewRect and the native side draws that part of the HUD layer once more at Present
      (composite_over, scissor rectangle). hud.lua fades WBP_PalPlayerInframeRender under CanvasPanelChara
      and raises Body.preview only while that widget and its parents are visible, so other tabs drop it.
    - Crosshair: GuiMixin redirects CameraType.isFirstPerson inside Gui.renderCrosshair. Checked against a
      Pal Sphere throw: Palworld's aim marks sit on Minecraft's crosshair.
    - Close camera: Steve is 1.875 blocks tall and 0.94 wide (1.95 with a helmet), Palworld's character
      about 1.7 by 0.45. At 4.3 m he measures right against ProjectWorldLocationToScreen. A wall at 2.4 m
      makes him a quarter of the picture wide; body_near_hide_m 1.25 -> 1.6, body_near_show_m 1.5 -> 1.9.
    - Melty's needs-vc-runtime finding: Prism's portable build links the Visual C++ runtime and does not
      carry it. Palworld needs the same runtime and Steam installs it with the game, so every player who
      can start Palworld has it. Left as it is.
    - Palworld's AddItem_ServerInternal for test gear: refused by the permission check, and not retried.
      Bows, guns, riding and raids stay untested until play reaches them.
    - One Palworld crash (access violation inside UE4SS, game thread) 46 s after a dev reload of the new
      hud.lua while Minecraft was linking. Not seen again in the sessions after it; cause unknown.
    - tools/shmdump.py prints the newer Body fields wrong. Read them raw with struct.
  - "Bows, guns, riding and raids. Test" (stopped part way: the creator asked for a break and a shutdown):
    - Tree chopping works in Palworld mode (wood 2 -> 68, fiber 0 -> 36). tools/tree.sh stands the
      character at a PalFoliageInstance (WorldTransform.Location); the trunk can be a step off that point.
    - Old Bow and arrows crafted at the workbench by play. Hotbar shows the bow in slot 3 with the round
      loaded and "+N" arrows carried; aim, shot and the count dropping all work. Weapons switch with the
      mouse wheel, not the number keys.
    - Found: a bow aim zooms Palworld's camera from 75 to 55 degrees and Steve filled the left half of
      the picture. HostBody.watchCamera now scales the camera distance by the zoom (body_near_fov_deg);
      seen working in the dev client: Steve steps out while the zoomed aim is that close.
    - New, built but NOT yet checked on screen: Steve holds the Minecraft item that stands for the tool in
      hand (ItemInHandLayerMixin redirects, LoadoutHud.inHand).
    - Not done: an arrow hit on a Pal (damage), guns (tech level 21 and ingots away), riding (needs a Pal
      Gear Workbench, a saddle and a caught mount), raids (need a base; Palworld starts them).
    - The 0.2.1 draft on Melty (release b4dfe987, test fda8e15e passed) does not hold these two changes.
      They need a jar build, package, upload, submit and a new test before publishing.
