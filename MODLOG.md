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
