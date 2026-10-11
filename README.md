# PalCraft

Play Palworld as Steve. You move, look, build and fight with Minecraft's controls, and you see it happen
inside Palworld's world.

PalCraft runs both games at once. Minecraft: Java Edition owns your player, your camera, your blocks and your
weapons. Palworld owns the islands and the Pals. Palworld draws its frame from Minecraft's camera, then PalCraft
paints Minecraft's blocks, hand and hotbar into that frame, hidden behind Palworld's hills and trees where they
should be.

## What you can do

- Walk, sprint, jump and swim on Palworld's terrain with Minecraft movement.
- Place and break blocks anywhere on the islands. Build a cobblestone hut next to a Lamball.
- Hit Pals with a sword, shoot them with a bow, or light TNT beside them. Their Palworld health drops.
- Take damage. You play in survival, and a Pal that hurts your Palworld character hurts Steve.
- Press **F8** to hand the keyboard and mouse to Palworld for menus, catching and base work. Press **F8**
  again to go back to Minecraft.

You start in survival with a kit: iron sword, bow and 64 arrows, iron pickaxe, cobblestone, oak planks, glass,
TNT, flint and steel, cooked beef, torches, ladders and two oak doors. Type `/gamemode creative` if you would
rather build without limits.

## What you need

- Palworld on Steam, version 1.0, running in DirectX 11 (the default).
- Minecraft: Java Edition on your Microsoft account.
- Windows 10 or 11.

## Install and play

Install PalCraft from its [Melty](https://melty.gg) page and press Play. Melty installs UE4SS into Palworld,
unpacks a private Minecraft 1.21.1 with Fabric into `%LOCALAPPDATA%\PalCraft`, signs it in with your Minecraft
account and starts both games.

The first Play downloads Minecraft and takes a few minutes. After that:

1. In Palworld, start or load a single-player world.
2. Minecraft opens its own PalCraft world by itself. Steve appears where your Palworld character stands.
3. Play. Minecraft's window sits unseen on top of Palworld's and takes your keyboard and mouse, so you look at
   one picture: Palworld's, with Minecraft drawn into it.

## Keys

| Key | When | Does |
|-----|------|------|
| F8 | Minecraft has control | Hands keyboard and mouse to Palworld |
| F8 | Palworld has control | Hands them back to Minecraft |

Every other key is Minecraft's own.

## Limits in 0.1.0

- Single player. The bridge has room for co-op and 0.1.0 does not use it.
- DirectX 11 only. Remove `-dx12` from Palworld's Steam launch options if you added it.
- Minecraft's picture crosses to Palworld through main memory at up to 1280x720, then Palworld scales it up.
  Blocks look softer than Palworld's own scenery at 1440p and above.
- Your Palworld character stays hidden and follows Steve. PalCraft refills its health while Steve lives, so a
  hit costs Steve hearts and leaves the character alive. If a single blow kills the character outright, press
  F8 and respawn in Palworld.
- The G key asks Palworld to interact, and 0.1.0 answers "unsupported". Use F8 for chests, Pal Spheres and
  menus.
- A passive Pal may ignore your first hits and keep grazing.

## How it works

Three parts share two memory-mapped files in `%LOCALAPPDATA%\PalCraft\runtime`.

- **Fabric mod** (`mc/`). Renders Minecraft's world, hand and HUD into separate layers with depth and copies
  them to `frames.shm`. It writes the camera pose and Steve's feet to `bridge.shm` and asks Palworld where the
  ground is by sending batches of rays.
- **UE4SS Lua mod** (`host/lua/PalCraft/Scripts`). Runs once per Palworld frame. It points a camera actor at
  Minecraft's pose, carries the hidden character to Steve, answers the rays with line traces, lists nearby Pals
  with their health, and applies damage in both directions.
- **Native DLL** (`host/native`). The Lua mod loads it. It hooks Direct3D 11's `Present`, finds Palworld's
  scene depth buffer and draws Minecraft's layers into the frame, comparing depths pixel by pixel.

Minecraft and Palworld render at different rates, so the DLL has to know which camera pose Palworld used for
the frame on screen. Each tick the Lua mod clears one of 16 tiny render targets, each a different width. The
DLL watches for that viewport size and reads the pose stored under the same number.

## Build it yourself

The design lives in `sheets/*.json`: one row per system, channel, struct field, key and kit item.
`tools/gen.py` checks every sheet for empty cells and broken references, then generates the protocol constants
for C++, Lua and Java. It refuses to generate while a check fails.

```
python tools/gen.py --check
bash tools/build_native.sh
cd mc && gradlew.bat build
python tools/package.py
```

`tools/package.py` writes `dist/PalCraft-0.1.0.zip` (the Palworld mod) and `dist/PalCraft-Minecraft-0.1.0.zip`
(Prism Launcher with the PalCraft instance). You need llvm-mingw and JDK 21 or newer on your PATH. The script
expects the Prism Launcher portable zip and the Fabric API jar in `.tools/dl/`.

## Credits

- [Minecraft Ring](https://github.com/siddoff/Minecraft-Ring) by siddoff and justbustin (MIT): the bridge
  protocol and the Fabric mod PalCraft forks.
- [universal-modder](https://github.com/rehan-remade/universal-modder) by rehan-remade (MIT): the passthrough
  method.
- MinHook, UE4SS, Fabric and Prism Launcher. [THIRD_PARTY.md](THIRD_PARTY.md) lists each license.

PalCraft is MIT licensed. Remix it.

Palworld belongs to Pocketpair. Minecraft belongs to Mojang and Microsoft. Neither company made or endorses
PalCraft.
