# PalCraft handoff

Written 2026-10-13 for whoever continues this project. Read this page first, then the five notes in
`docs/handoff/`, then `MODLOG.md` for the history.

## What PalCraft is

A mashup of Palworld (host) and Minecraft: Java Edition (companion). Both games run at once. Minecraft draws
Steve, his blocks and its HUD, and a native DLL inside Palworld paints those layers into Palworld's frame.
F8 swaps between Minecraft mode and Palworld mode. In Palworld mode Palworld has the controls and Steve
stands where its hidden character stands.

Three parts:

- `mc/`: the Fabric 1.21.1 mod (Java, Mojang mappings).
- `host/lua/PalCraft/`: the UE4SS 3.0.1 Lua mod Palworld loads.
- `host/native/`: the D3D11 compositor DLL (MinHook), built with the llvm-mingw in `.tools/`.

The two games talk through two shared-memory files, `frames.shm` and `bridge.shm`.

## Where things stand

State of 2026-10-13, afternoon.

- **Melty:** 0.2.2 was published on 2026-10-13 and went into Melty's safety review; `mod_status` names the live version (0.2.1 until the review passes). Page: https://melty.gg/m/palcraft-6. Mod id
  `bbee49ad-dee7-4100-8bdb-020e22bcc147`. The owner asked for "updated" in the title: it reads
  "PalCraft | Updated". Melty's numbers for 0.2.1: 30 Plays started, 9 crashed.
- **Melty's test of 0.2.2 passed** on 2026-10-13: 2 runs of 6 minutes, no crash, all 5 self-checks, test `0d39b797-8fb2-4d45-9e04-82068e2176ea`. Both runs entered "PalCraft Test" by clicks (`tools/pal.sh`): the world list sorts by last played, so look at the screenshot before choosing a row.
- **Fixed in 0.2.2, checked in the games:** the crash a minute into a world (stale handles), Steve's 10 km
  drop after a world load, ground that vanished under him, the Minecraft freeze at render distance 32.
- **Reduced in 0.2.2, not gone:** the crash while a world loads. 16 of 21 loads died in 0.2.1, 1 of 6 in
  the setup players get. See "The load crash".
- **Open: Palworld's memory grows while Minecraft is linked.** Measured 2026-10-13 (`build/mem.log`,
  `tools/mem_watch.ps1`): +72 MB a minute while Steve moves, about +20 standing still, none with Minecraft
  unlinked (5,785 to 5,834 MB, up and down). The mod's Lua heap stays at 0.8 to 1.2 MB, so the growth sits
  in UE4SS's C++ side or in `palcraft.dll`. Minecraft swings between 3.0 and 3.7 GB with no trend. Nobody
  has measured 0.2.1. Melty's `memory-steady` check reads the Lua heap only and passes. First thing to try:
  halve the terrain rays and see whether the growth halves.
- **Applied from the handoff patch sets:** terrain 2, 3 and 4 (ground, net, walls); performance 02, 04 and
  05 (combat report, rays, vsync). Performance 06 and 07 conflict with the rewrite and stay out.
- **Co-op is in the tree and switched off** (`coop_enabled` 0 in `sheets/tuning.json`). `players.lua` still
  uses `FindAllOf` and `NotifyOnNewObject`: rewrite it onto `PalCharacter_Player` before switching it on.
- **Git:** 0.2.2 is committed and pushed to `origin` (https://github.com/EQQX0/PalCraft), branch master.
- **Not tested:** the build-mode signal (`IsInBuildingMode()` while placing a building), an arrow hit on a
  Pal, riding, raids, guns, a second world entry in one Palworld process, 100 Pals on screen.

## What the owner asked for, in order of arrival

1. "make multiplayer". Scope chosen: friends join the Palworld co-op world and see each other as Minecraft
   players. No second tester exists yet.
2. Fix bugs at start-up, Steve running inside walls or blocked ways, Steve falling under the map. Make the
   game work and run faster.
3. One mode instead of the F8 switch, with the game playing as Minecraft.
4. Co-op only between people who have the mashup, because Palworld's own co-op also lets in people without
   it.
5. "If the cause of the crashes is the co-op then disable it." It is not the cause: 0.2.1 has no co-op
   code. Ship the crash fix with co-op switched off all the same.

Order of work: 0.2.2 with the fixes and co-op off (built), then one mode, then co-op.

## The crash

`python tools/crashwho.py [dump] [depth]` reads a Palworld minidump and names the UE4SS frames on the
faulting thread. Dumps sit in `%LOCALAPPDATA%\Pal\Saved\Crashes\`. Sixteen dumps up to 2026-10-13:

| Group | Dumps | What it is |
|---|---|---|
| `GetInternalIndex` reads freed memory | 4, both of the owner's | A Lua call on a handle whose object Palworld has freed |
| `UE4SS.dll+0x9f577e`, read of 0x1, property and class frames above | 6 | The same, where the freed memory still looked like an object |
| Read of 0x10 or 0x18 in a Lua-called function | 2 | Dev console only: a script called `GetClass` or `GetFName` on an empty handle |
| `memcpy` in a UE4SS vector copy on Palworld's loading thread, 23 s after start | 1 | Not Lua. Probably UE4SS's debug window, which Melty's `UE4SS-settings.ini` switches on (`GuiConsoleEnabled = 1`): players can hit it while a world loads |
| `push_arrayproperty` then `push_objectproperty`, read of 0x8 | 1 | UE4SS crashes filling a Lua table from an out-parameter array of objects |
| Others | 2 | A native DLL bug of 2026-10-11 (fixed) and a C++ exception inside UE4SS |

**Cause of the first two groups.** The Lua mod keeps UE4SS handles from one frame to later ones. Palworld
frees the objects in between. `IsValid()` on such a handle reads the freed object: it crashes when Windows
has taken the page back, and it can answer "valid" when another object now sits in that slot. Places that
do this:

- `camera.lua` `tags`: 16 render targets nothing in Palworld refers to. Palworld's garbage collector frees
  them about once a minute. This fits the owner's crashes: 134 s and 145 s after start, one minute into
  the world. It may also explain part of the "missing" frames in the sync log.
- `entities.lua` `known` and `byId[...].actor`, `players.lua` `known` (new co-op code, same fault),
  `standin.lua` `backs`: Pals and tools from `NotifyOnNewObject`, checked only while Minecraft is linked.
- `hud.lua` `parts`, `builders.list`, `previews.list`: widgets. Palworld never marks a closed screen dead
  before freeing it, so no per-frame check can catch them.
- `camera.lua` `cam` and `held`, `body.lua` `EXPDB`: these live as long as the world. They go stale when
  the player returns to the title and enters a world again.

**The rule, in force since 2026-10-13:** no handle outlives the tick that got it. No `NotifyOnNewObject`,
no `FindAllOf` per tick. Each tick starts from the player controller and asks Palworld again:

- Characters: `PalUtility:GetPalObjectCollector(pawn).PalCharacter_NPC` (Palworld's own list).
- The mod's camera: found in `pc.Children`. Its 16 capture actors sit in `cam.Children`, and each holds one
  tag render target, so Palworld's collector sees them.
- The HUD gauge: `pc.MyHUD.HUDWidgets`, then the `WBP_PlayerUI_C` in that list.
- Inventory previews: `FindAllOf` only while a menu is open and no preview is known. The mod keeps their
  paths, never the objects.
- A stored party Pal waits 29 m above its owner with collision off: `entities.lua` leaves it out.

Do **not** pass a Lua table to a function that fills an array of objects (`GetAllActorsOfClass`,
`GetAttachedActors`, `GetAllWidgetsOfClass`): one of them crashed inside `push_arrayproperty`. Array
properties work (`Children:ForEach`, `GameState.PlayerArray`, `spawnedWeaponsArray`).

## The load crash

Palworld died while loading a world, a few seconds after the player controller appeared. Melty's players
report it too: "ntdll.dll c0000374, about 70 s in" on every version. `build/load_loop.log` holds every
load of 2026-10-13. `tools/load_loop.sh` produced it: start Palworld, enter the test world, stay, quit.

| Frame loop | Loader cache | Fine | Died |
|---|---|---|---|
| Hook on the Blueprint tick (0.2.1) | on (Melty's setting) | 5 | 16 |
| Hook on the Blueprint tick | off | 18 | 1 |
| No frame loop | on | 4 | 2 |
| Hook on `PalHUDInGame:TickWorldHUDs` | on | 5 | 1 |
| Hook on `PalHUDInGame:TickWorldHUDs` | off | 11 | 0 |

Two causes, both inside UE4SS 3.0.1:

1. **A hook on a Blueprint function.** `RegisterHook` on `BP_PalPlayerController_C:ReceiveTick` is a
   "script hook". With one registered, UE4SS builds the path name of every Blueprint function Palworld
   calls, on every thread, to look for its hook. Dump 32488 shows the game thread dying there
   (`GetPathName`, `FMalloc::Free`). The frame loop now hooks `/Script/Pal.PalHUDInGame:TickWorldHUDs`, a
   built-in function Palworld's in-world HUD calls once per frame (684 calls in 684 frames). The class is
   native, so the hook goes in at mod start: no timer, no wait for a class. `ctx:get().PlayerOwner` is the
   controller. Side effects: frame sync 600 of 600 (was 596 to 599), Palworld 114 fps where it had 109.
   **Never hook a Blueprint function.**
2. **The loader's object cache.** `bUseUObjectArrayCache = true` in Melty's `UE4SS-settings.ini` makes
   UE4SS listen to every object Palworld creates. Palworld's loading thread dies in a vector copy there
   (`UE4SS.dll+0x4870c3` under `+0x462c6d`) with no PalCraft code running. The file's own comment says to
   switch it off for start-up crashes. **A mashup cannot change it.** A package that carried the file
   with that line changed failed Melty's install: "conflict: Pal/Binaries/Win64/UE4SS-settings.ini is
   already provided by UE4SS". The recipe's `settings` field reaches only a mashup's own files. So 0.2.2
   ships with the cache on, and row 4 of the table is what players get. The changed file is in
   `build/probe/UE4SS-settings.cache-off.ini` for dev runs. Do not write the game's copy from the mod:
   Melty's 12 other Palworld mashups share it. The fix belongs to Melty's loader package: report it there.

Ruled out by the loop: the dev console's timer, searches during the load, and the frame loop's own work
(a gate that kept it idle until the character was placed changed nothing).

The heap corruption dumps in `%LOCALAPPDATA%\CrashDumps` show the crash handler, not the cause: Palworld's
own dump writer trips over the damage. Read the `UEMinidump.dmp` of the same minute, or the game thread in
`build/probe/threads.py`.

**Start-up items done in 0.2.2:** render and simulation distance capped; Minecraft clears the control
block when it maps `bridge.shm`; `dev.lua` deletes a leftover `dev_in.lua` at start.

**Open:** "Could not change Minecraft window owner: Windows error 5" in the owner's log of 2026-10-12
22:49. Melty also lists for 0.2.1: `prismlauncher.exe` c0000005 after 44 s (5 players), `javaw.exe` hung
(4), `OpenAL.dll` c0000409 (3), "Minecraft was closed before it finished setting up" (3). Nobody has
looked at those. `mcp__melty__player_logs` names the logs players sent.

## The other notes

- `docs/handoff/startup.md`: the second pass over the crashes and the start-up logs, with three diffs.
- `docs/handoff/terrain.md`: walls, blocked ways, falling. Five causes, five patches in
  `docs/handoff/terrain-patches/`.
- `docs/handoff/performance.md`: where a frame's time goes. Seven patches in `docs/handoff/perf-patches/`.
- `docs/handoff/one-mode.md`: the plan for dropping F8.
- `docs/handoff/co-op.md`: what is built, and the plan for co-op between PalCraft players only.

Both patch sets pass `git apply --check` against the working tree of 2026-10-13, alone and together.
Nobody has run either set in the games.

## Rules of the project

- **Sheets first.** The design lives in `sheets/*.json`. Change the sheet, then the code.
- **Preflight before every build:** `python tools/gen.py --check`. Build only when it is clean.
  `python tools/gen.py` regenerates `Tune.java`, `Loadout.java`, `gen_protocol.lua` and `protocol.h`.
- Nothing a game ships with goes into the other game or the upload. Prism downloads Minecraft on the
  player's PC.
- No work around anti-cheat. No item cheats: test gear comes from play.
- Never package `accounts.json` or any token. `tools/package.py` refuses the known secret files.
- Ask the owner before publishing or changing the public listing.
- The owner uses this PC while tests run, and can press Play in Melty at any moment. Before each dev
  launch, check that no `Palworld-Win64-Shipping` or `javaw` process is running. Never leave the dev
  junction in place when you stop: on 2026-10-13 a start of Palworld at 00:18 ran the dev copy and crashed.
- Only the world named "PalCraft Test" is for testing (third row of the world list, Multiplayer ON since
  2026-10-12). "eqq Islands" and "eqq" are the owner's. On 2026-10-12 a dev script entered "eqq Islands",
  moved the character about 6 m and the game saved it.

## Build

```
python tools/gen.py --check
bash tools/build_native.sh            # release DLL into host/lua/PalCraft/palcraft.dll
cd mc && JAVA_HOME=<repo>/.tools/jdk/jdk-25.0.4.1+1 ./gradlew.bat build -q
python tools/package.py               # writes dist/PalCraft-<v>.zip and dist/PalCraft-Minecraft-<v>.zip
```

`.tools/` (JDK, compiler, downloads) and `ref/` (universal-modder) are not in git. A fresh machine needs
them again from their official sources; `THIRD_PARTY.md` names each one.

## Dev setup

The dev tools assume Palworld in `C:\Program Files (x86)\Steam\steamapps\common\Palworld` and this repo at
`C:\Users\Admin\Desktop\repos\PalCraft`. Palworld's window is 2560x1440 on this PC now.

1. Check that no game is running. Move the installed `Pal\Binaries\Win64\Mods\PalCraft` folder to
   `build\installed_backup\PalCraft` and make a junction from that Mods path to `host\lua\PalCraft`.
   Keep a copy of the game's `UE4SS-settings.ini` first (`build/installed_backup/UE4SS-settings.ini.melty`):
   `load_loop.sh` rewrites it.
2. Start the Minecraft dev client in the background:
   `cd mc; JAVA_HOME=... PALCRAFT_DIR=<repo>/runtime ./gradlew.bat runClient`
3. `bash tools/pal_up.sh` starts Palworld. Run `python tools/repl.py -f tools/pal_enter.lua` until it prints
   "started": it enters "PalCraft Test" through the title screens' own handlers, with no click and no key.
   `python tools/pal_inworld.py` prints "inworld" once the frame loop runs. `tools/pal_dev.sh` and
   `tools/pal_enter.sh` pick the first world, which is the owner's: do not use them.
4. `bash tools/mc.sh host` enters Palworld mode, `bash tools/mc.sh "switch mc"` leaves it,
   `bash tools/mc.sh quit` stops the client.

Nothing here takes the mouse, the keyboard or the focus. `tools/keep_on_monitor.ps1` holds the test windows
on one monitor and `tools/mute_games.ps1` mutes them (`-Unmute` before the games close: Windows remembers
a mute per program). Both act on `java` and Palworld only. `javaw` can be the owner's own Minecraft.

Useful tools: `tools/respawn.sh` (after a death), `tools/pal_key.py 0x09` (a key to Palworld's window
without focus: Tab, Esc 0x1B, B 0x42), `tools/load_loop.sh` with `tools/stop_loop.ps1`, `tools/mem_watch.ps1`,
`tools/repl.py` (run Lua inside Palworld; `-f file`), `tools/reload.sh` (reload the Lua mod),
`tools/build_native.sh dev` (hot-swap the DLL), `tools/pal.sh` (send input to Palworld and screenshot),
`tools/near.sh`, `tools/goto.sh`, `tools/tree.sh`, `tools/palmem.sh`, `tools/crashwho.py`.

When done: quit both games, put `UE4SS-settings.ini.melty` back over the game's `UE4SS-settings.ini`,
delete the junction (check it is a junction first), move the backup folder back, delete the `dwmapi.dll`
copy beside `dwmapi.dll.melty-off` after comparing the two, and run `gradlew --stop`.

## Traps already hit

- UE4SS 3.0.1 keeps every table a script passes as an out parameter. Release them (`U.release`), or
  Palworld's memory grows by 1 GB a minute.
- Out-parameter arrays of objects crash (see "The crash"). Reading enum properties from Lua crashes.
  `K2_GetComponentsByClass` crashes. A member call on an empty handle crashes: check `IsValid()` first.
- `FindAllOf` costs about 34 ms. A `StaticFindObject` that finds nothing costs 75 ms.
- Calling a function that returns an enum crashes too (`BuilderComponent:GetCurrentMode()`).
- `ForEachProperty` on a function throws in this UE4SS. `ForEachFunction` on a class works.
- In Minecraft mode the character follows Steve: move with `tools/mc.sh "run tp @s ~x ~y ~z"`, not with
  `K2_SetActorLocation`. Minecraft's delta is (Palworld dx, dy, -dz) in metres.
- Stopping a background loop script leaves its shells alive. Run `tools/stop_loop.ps1` and read its count
  before starting another. Never overwrite a bash script that is running.
- `sed -i` in Git Bash turns CRLF into LF. UE4SS reads its settings file either way.
- Lua on UE4SS's async thread (`LoopAsync`) shares one Lua state with the frame hook. Do the work in
  `ExecuteInGameThread` or in the hook.
- The compositor puts Minecraft's layers in before Palworld draws its interface. Anything that must show
  over a Palworld menu needs the top pass (`composite_over`).
- Weapons in Palworld switch with the mouse wheel. The number keys command Pals.
- Palworld opens its Options menu when its window loses focus.
- On an installed build F8 goes to Minecraft's input window (`tools/mcdrive.py`).
- Melty's app sometimes restarts between test runs and the test ends "app-went-quiet". Start it again.
- `tools/shmdump.py` prints the newer Body fields wrong. Read them raw with `struct`.
- The action key is R in the code and G in `sheets/keys.json` and the README.

## Melty

Publishing runs through Melty's MCP tools: `start_upload`, PUT the bytes, `finish_upload`,
`setup_multiplayer` (multiplayer releases only), `submit_release` with the recipe in `melty.json`,
`test_release`, `test_result`, `publish`, `mod_status`. The owner's Publish prompt carries a token that
publishes under the owner's account. It is not in this repo and must stay out of it. The chat transcripts
under `C:\Users\Admin\.claude` contain it: never copy them here.

The owner has two live mashups: PalCraft and Hero Stats (`47d1d98e-32cc-493c-8396-dc776dbcdb9a`). They
asked whether a mashup can be deleted. Melty's agent tools have no delete or unpublish action. If Melty
offers one, it is in Melty Studio and it is the owner's click.
