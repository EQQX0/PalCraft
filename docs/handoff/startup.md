# Start-up and crashes: the second diagnosis

**Later the same day:** the stale-handle rewrite is done (finding 3). The 23:17 crash of finding 2 is not the
debug window: it is the load crash, two faults in UE4SS. 0.2.2 works around the first; Melty's loader owns
the setting behind the second. `HANDOFF.md`, "The load
crash", has the measurements. `try_hook`, its timer and its load-flag test are gone: the frame loop hooks a
built-in function at mod start. Findings 1, 4 and 5 are fixed as proposed below.

A second pass over the crash dumps and the start-up logs, finished 2026-10-13. It agrees with "The crash"
in `HANDOFF.md` and adds detail. The diffs here are hand-written against the working tree. Nobody has run
them through `git apply --check` or the games.

## Findings, most certain first

1. **The 00:18 crash of 2026-10-13 is the dev console running a stale script (about 90%).** The fault at
   `UE4SS+0x388fb7` is the Lua `GetClass()` binding on an empty handle (`+0x388f37`, the crash of
   2026-10-11 22:05, is the same for `GetFName()`). The stack is `ExecuteInGameThread` -> `pcall` -> Lua,
   which only `dev.lua:78-79` has. `runtime/dev_in.lua` survived the 23:17 crash, and `dev.lua:71-76`
   picks up any waiting file 500 ms after start. `tools/repl.py` never removes its script on a timeout.
   Players are not affected.

2. **The 23:17 crash of 2026-10-12 is not Lua (about 90%), and is probably UE4SS's debug window (about
   70%).** The crashed thread is Palworld's async loading thread, inside a UE4SS vector copy
   (`UE4SS+0x4870c3` <- `+0x462c6d`), while the game thread sits in the same UE4SS function. The two lists
   it copies belong to an object-creation listener used from two threads. `UE4SS-settings.ini` as Melty
   installs it has `GuiConsoleEnabled = 1`; the dev backup in `build/dev_ue4ss_backup/` has 0. **Players
   get Melty's file on every Play, so this can hit them while a world loads.** Whether the recipe can set
   that line is a question for Melty.

3. **The owner's crashes: `IsValid()` on a kept handle (mechanism about 90%, which handle about 60%).**
   The stack is one `pcall` deep, so the call sits at `on_tick` level, outside the guarded systems. The
   only cached actor tested there is `cam` (`camera.lua:16` and `:84`). The 21:39 crash came 4 s after a
   death and respawn loading screen. The 10:11 crash fits `camera.lua:241` (`rt:IsValid()` on the tag
   render targets) or `camera.lua:54` (`held`). The 23:11 crash is two `pcall`s deep: `standin.lua:81`,
   `entities.lua:56` or `players.lua`. `UE4SS.dll` does not export the Lua C API, so a native "is this
   address readable" helper is not a quick way out.

4. **Render distance 32 freezes Minecraft at `-Xmx3072m` (about 85%).** 22:35:30 "Changing view distance
   to 32, from 12", fps 75 to 0 within a minute; the next start loaded 32 from `options.txt` and froze too.
   The start after that worked only because Melty re-extracted the package and reset `options.txt`.

5. **A stale control block after an unclean Minecraft exit (from code, effect not seen in game).**
   `BridgeShm.initHeader` keeps the old regions when the magic matches; `CameraSync.releaseHostCamera`
   writes flags = 0 only if `controlling`; `bridge.lua:34-40` trusts any heartbeat change for 2000 ms. A
   new or frozen Minecraft makes Palworld apply the previous session's camera, carry and hide flags.

6. **"Could not change Minecraft window owner: Windows error 5":** seen once, 5 s before a normal
   shutdown. Cause unknown. `WindowsOverlay.updateOwner` logs only the first error.

7. No sign of a double Prism launch or a leftover `javaw`.

## Fixes

**A. Dev console: never run a script left by an earlier Palworld.** Also make `tools/repl.py` delete
`dev_in.lua` before it reports TIMEOUT.

```diff
--- a/host/lua/PalCraft/Scripts/dev.lua
+++ b/host/lua/PalCraft/Scripts/dev.lua
@@ -59,5 +59,8 @@
 function M.start(runtime)
     if not readfile(runtime .. "dev_enabled") then return end
     dir = runtime
+    -- A script still waiting from a Palworld that crashed was written for a world that is gone: at the
+    -- title screen it calls objects that do not exist yet, and that crashed the game (2026-10-13).
+    os.remove(runtime .. "dev_in.lua")
     local busy = false
     local gen = _G.PALCRAFT_GEN
```

**B. Dev start: switch UE4SS's debug window off.**

```diff
--- a/tools/pal_up.sh
+++ b/tools/pal_up.sh
@@ -9,5 +9,7 @@
   W="/c/Program Files (x86)/Steam/steamapps/common/Palworld/Pal/Binaries/Win64"
   [ -f "$W/dwmapi.dll" ] || cp "$W/dwmapi.dll.melty-off" "$W/dwmapi.dll"
+  # Melty's loader ships UE4SS's debug window on: its object listener crashed the loading thread (2026-10-12).
+  sed -i 's/^GuiConsoleEnabled = 1/GuiConsoleEnabled = 0/' "$W/UE4SS-settings.ini"
   rm -f "$LOG"
   python -m um win launch --steam 1623730
 fi
```

**C. Camera: find our camera again each tick through references Unreal keeps.** Untested: `SetOwner` on
the camera is new, and the view-target branch does not check ownership.

```diff
--- a/host/lua/PalCraft/Scripts/camera.lua
+++ b/host/lua/PalCraft/Scripts/camera.lua
@@ -13,12 +13,31 @@
 local ARM_END = FName("SpringEndpoint")
 
-local function ensure_cam(pawn)
-    if cam and cam:IsValid() then return cam end
+-- A pointer kept from an earlier tick is only good while Unreal still holds the actor: UE4SS's IsValid
+-- reads the object first, and a freed one crashes the game (2026-10-12). So the camera is looked up
+-- again each tick: as the view target, or among the actors the character owns.
+local camAt
+local function live_cam(pc, pawn)
+    if not camAt then return nil end
+    local view = pc:GetViewTarget()
+    if view and view:IsValid() and view:GetAddress() == camAt then return view end
+    local found
+    pawn.Children:ForEach(function(_, e)
+        local a = e:get()
+        if a and a:IsValid() and a:GetAddress() == camAt then found = a end
+    end)
+    return found
+end
+
+local function ensure_cam(pc, pawn)
+    cam = live_cam(pc, pawn)
+    if cam then return cam end
     local cls = StaticFindObject("/Script/Engine.CameraActor")
     local loc = pawn:K2_GetActorLocation()
     cam = pawn:GetWorld():SpawnActor(cls, { X = loc.X, Y = loc.Y, Z = loc.Z + 100 }, { Pitch = 0, Yaw = 0, Roll = 0 })
     if cam and cam:IsValid() then
         cam.CameraComponent.bConstrainAspectRatio = false
+        cam:SetOwner(pawn)
+        camAt = cam:GetAddress()
     end
     onCam = false
     return cam
@@ -81,7 +100,7 @@
     local view = pc:GetViewTarget()
     local at = view and view:IsValid() and view:GetAddress() or 0
     if at ~= pawn:GetAddress() then
-        if cam and cam:IsValid() and at == cam:GetAddress() then
+        if camAt and at == camAt then
             pc:SetViewTargetWithBlend(pawn, 0.0, 0, 0.0, false)
             onCam = false
         else
@@ -112,7 +131,7 @@
 -- keepHud: Palworld has the controls and needs its own HUD.
 function M.apply(pc, pawn, pos, target, fovY, aspect, keepHud)
     free_follow(pawn)
-    local c = ensure_cam(pawn)
+    local c = ensure_cam(pc, pawn)
     if not c or not c:IsValid() then return false end
     local loc, rot = look(pos, target)
     if not loc then return false end
```

**Designed, not written:**

- `camera.lua:45-54`: drop `held`, keep only `heldAt`, read `pawn.FollowCamera` again each tick.
- `camera.lua:238-246`: keep each tag target's path and find it again with `StaticFindObject` each tick.
- Minecraft: write an empty control block when it maps `bridge.shm` (finding 5). Clamp render and
  simulation distance through a new tuning row, e.g. `mc_max_view_chunks` 12 (finding 4).
- Logging: the date in `U.log`; link up and down in `bridge.lua` `mc_alive`; every owner error code in
  `WindowsOverlay`.

## Checks to play

- A: leave a `dev_in.lua` containing `P(FindFirstOf('PalCharacter'):GetClass())` in `runtime/` and start
  Palworld. With the fix: no crash, and the file is gone.
- B: with `GuiConsoleEnabled = 0`, enter a world several times. `python tools/crashwho.py` shows no crash
  at `UE4SS+0x462c6d`.
- C: in Minecraft mode, kill Steve and let Palworld respawn; play past two collector cycles (over two
  minutes); F8 both ways. No crash at `UE4SS+0x4baaaf` <- `+0x3b23fc`.
- Finding 5: kill `javaw` in Minecraft mode, start Minecraft again, and watch whether Palworld's camera
  jumps to the old pose before Minecraft joins its world.

## Not checked

- What destroys the camera actor.
- Whether the owner's sessions ran with `GuiConsoleEnabled = 1` (assumed from Melty's re-extract).
- `palcraft.cpp` start-up (the `frames.shm` mapping, depth detection, the stale "F8 in Palworld" request
  logged at DLL start), `FramePassthrough.java`, `players.lua`, `body.lua`.
- Why the 06:11 and 07:31 starts of 2026-10-12 never hooked the frame loop and the 04:51 start took four
  minutes.
- The six older crashes at `UE4SS+0x9f577e` and the C++ exception of 02:04.
