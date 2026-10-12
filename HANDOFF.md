# PalCraft handoff

Written 2026-10-12 for whoever continues this project. Read this page, then `MODLOG.md` for the history.

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

- **Live on Melty: 0.2.1.** Page: https://melty.gg/m/palcraft-6. Mod id
  `bbee49ad-dee7-4100-8bdb-020e22bcc147`. It passed a two-run Melty test before publishing.
- **In the repo, not released:** two changes made after 0.2.1 shipped.
  - A zoomed bow aim counts as a close camera, so Steve steps out of the picture. Seen working in the dev
    client.
  - Steve holds the Minecraft item that stands for the Palworld tool in hand. Built, never checked on screen.
- **Tested by play in Palworld mode:** see the list in `README.md`, plus tree chopping and the bow (craft,
  aim, shoot, arrow count).
- **Not tested:** an arrow hit on a Pal, riding, raids, guns.

## Next steps, in order

1. Start the dev setup and look at Steve holding a tool. Fix what looks wrong.
2. Shoot a Pal with the bow and confirm damage.
3. Riding: needs a Pal Gear Workbench, a saddle and a caught mount. Reach it by play.
4. Raids: need a base (Palbox). Palworld decides when one starts.
5. Guns: technology level 21, ingots and gunpowder away from the level 6 test character.
6. Bump the version to 0.2.2 in the sheets, build, package, upload, submit, test, then ask the owner before
   publishing.

## Rules of the project

- **Sheets first.** The design lives in `sheets/*.json`. Change the sheet, then the code.
- **Preflight before every build:** `python tools/gen.py --check`. Build only when it is clean.
  `python tools/gen.py` regenerates `Tune.java`, `Loadout.java`, `gen_protocol.lua` and `protocol.h`.
- Nothing a game ships with goes into the other game or the upload. Prism downloads Minecraft on the
  player's PC.
- Single player only.
- No work around anti-cheat. No item cheats: test gear comes from play.
- Never package `accounts.json` or any token. `tools/package.py` refuses the known secret files.
- Ask the owner before publishing or changing the public listing.

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

The dev tools assume Palworld in `C:\Program Files (x86)\Steam\steamapps\common\Palworld`, a 1920x1080
window and this repo at `C:\Users\Admin\Desktop\repos\PalCraft`. Adjust the paths in `tools/*.sh` on another PC.

1. Close Palworld. Move the installed `Pal\Binaries\Win64\Mods\PalCraft` folder to
   `build\installed_backup\PalCraft` and make a junction from that Mods path to `host\lua\PalCraft`.
2. `bash tools/pal_dev.sh` starts Palworld and enters the first world.
3. Start the Minecraft dev client in the background:
   `cd mc; JAVA_HOME=... PALCRAFT_DIR=<repo>/runtime ./gradlew.bat runClient`
4. `bash tools/mc.sh host` enters Palworld mode. `bash tools/mc.sh quit` stops the client.

Useful tools: `tools/repl.py` (run Lua inside Palworld), `tools/reload.sh` (reload the Lua mod),
`tools/build_native.sh dev` (hot-swap the DLL), `tools/pal.sh` (send input to Palworld and screenshot),
`tools/near.sh`, `tools/goto.sh`, `tools/tree.sh` (stand the character next to things), `tools/palmem.sh`
(memory growth).

When done: quit both games, delete the junction, move the backup folder back, and delete the `dwmapi.dll`
copy beside `dwmapi.dll.melty-off`. Melty switches the loader off itself when Palworld exits.

## Traps already hit

- UE4SS 3.0.1 keeps every table a script passes as an out parameter. Release them (`U.release`), or
  Palworld's memory grows by 1 GB a minute.
- Reading enum properties from Lua crashes. `K2_GetComponentsByClass` crashes.
- `FindAllOf` costs about 34 ms. Call it once, then use `NotifyOnNewObject`.
- The compositor puts Minecraft's layers in before Palworld draws its interface. Anything that must show
  over a Palworld menu needs the top pass (`composite_over`).
- Weapons in Palworld switch with the mouse wheel. The number keys command Pals.
- On an installed build F8 goes to Minecraft's input window (`tools/mcdrive.py`).
- Melty's app sometimes restarts between test runs and the test ends "app-went-quiet". Start it again.
- `tools/shmdump.py` prints the newer Body fields wrong. Read them raw with `struct`.

## Melty

Publishing runs through Melty's MCP tools: `start_upload`, PUT the bytes, `finish_upload`,
`submit_release` with the recipe in `melty.json`, `test_release`, `test_result`, `publish`, `mod_status`.
The owner's Publish prompt carries a token that publishes under the owner's account. It is not in this
repo and must stay out of it.
