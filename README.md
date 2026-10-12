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
- Hit Pals with a sword, shoot them with a bow, or light TNT beside them. Their Palworld health drops, and a
  kill gives your Palworld character experience.
- Take damage. You play in survival, and a Pal that hurts your Palworld character hurts Steve.
- Wear armor. A Pal's hit goes through Minecraft's armor, toughness, Protection and shield rules.
- Dig Palworld's ground, cliffs and trees for materials, hunt Pals for meat and leather, farm, craft and smelt.
- Press **F5** for third person. You see Steve standing in Palworld.
- Press **F8** for Palworld mode: catch Pals, build a base, craft, talk to people and fast travel, with Steve
  as your character. Press **F8** again to go back to Minecraft.

You start in survival with a kit: iron sword, bow and 64 arrows, iron pickaxe, cobblestone, oak planks, glass,
TNT, flint and steel, cooked beef, torches, ladders, two oak doors, two water buckets, wheat seeds, oak
saplings, a crafting table and two golden apples. Type `/gamemode creative` if you would rather build without
limits.

## Survival

Palworld's ground, cliffs and trees stay where they are, so you dig them for materials. Aim at the world and
hold attack. A bar fills, then the drops pop out. Each spot gives once and refills after 90 seconds.

| You dig | With | You get |
|---------|------|---------|
| Trees and bushes | hand or axe | oak logs, sticks, saplings, apples |
| Grass | anything | dirt, wheat seeds, sometimes carrots, potatoes, beetroot, melon and pumpkin seeds, sugar cane |
| Bare soil | anything | dirt, flint, clay, gravel with a shovel |
| Sand and snow | anything | sand, cactus, snowballs |
| Rock | pickaxe | cobblestone and coal. Stone pickaxe adds iron and copper. Iron pickaxe adds gold, redstone, lapis, diamonds and emeralds. Diamond pickaxe adds obsidian. |
| Palworld ore nodes | pickaxe | the same ores, several times as often |

Better tools dig faster. Blocks you place break the normal Minecraft way.

**Hunting.** A Pal you kill drops Minecraft loot and experience: beef, bones and leather from most Pals, wool
and mutton from Lamballs, feathers and chicken from Chikipi, porkchops from Rushoar, gunpowder from Foxparks.
Syndicate thugs carry arrows, emeralds and gold.

**Farming.** Place dirt, till it with a hoe, pour your water beside it and plant. Crops and saplings grow as
they do in Minecraft.

**Armor.** Craft it from the iron, gold and diamonds you dig and the leather you hunt. PalCraft sends each Pal
hit through Minecraft's own damage rules, so full iron takes about 40% off a hit and full diamond about 70%.
Armor wears with each hit. Shields block, and Protection enchantments count. Cold, heat and poison pass armor,
as freezing and fire do in Minecraft.

**Golden apples.** Craft a golden apple from eight gold ingots and an apple. Minecraft has no recipe for the
enchanted golden apple, so PalCraft gives you two ways to get one. Kill an alpha Pal and it drops one, with
golden apples and diamonds. Or use the old recipe: eight gold blocks around an apple. Any Pal has a small
chance to drop a plain golden apple.

**Hunger.** Steve's food bar feeds your hidden Palworld character. Eat Minecraft food and neither of you
starves. The bundled AppleSkin mod shows saturation on the hunger bar.

**Temperature.** The gauge above the hunger bar shows Palworld's body temperature: blue cells for cold on the
left, red for heat on the right. The green line marks the range your Palworld clothes handle. Outside it the
gauge blinks, frost creeps over the screen in the cold, and you lose health. A campfire, a fire or lava within
five blocks warms you by two steps. A torch nearby or in your hand gives one, and so does a piece of leather
armor (two for the full set). Standing in water cools you by one on a hot day.

## Palworld mode

Press **F8** and Palworld takes the keyboard and mouse. Its rules, its HUD and its menus are yours, and Steve stays on screen as your character, walking, crouching and swinging where Palworld's own would. Press **F8** again for Minecraft's controls.

Played this way so far: the fast travel statue, the first quests, talking to the islander, the tech tree, the build menu, a workbench, a pickaxe, Pal Spheres, catching a Chikipi, summoning it, the cold at night, defeat, the respawn map and respawning.

The two modes keep separate health. In Palworld mode Palworld's health bar is the one that counts, and nothing in Minecraft hurts Steve.

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

## Add your own mods

PalCraft's Minecraft is Java Edition 1.21.1 on Fabric. It lives in its own folder, apart from your other
Minecraft installs.

1. Close Palworld and Minecraft.
2. Download the mod's **Fabric** file for Minecraft **1.21.1** from CurseForge or Modrinth.
3. Press Win+R, paste `%LOCALAPPDATA%\PalCraft\Prism\instances\PalCraft\.minecraft\mods` and press Enter.
4. Drop the `.jar` file into that folder.
5. Press Play.

Fabric API is in the folder already. Forge and NeoForge files do not load, and neither do files for other
Minecraft versions. Mods that add items or change the HUD and inventory fit best. A mod that replaces
Minecraft's renderer can break the picture inside Palworld. If the game stops starting, take your last jar out.
If a mod is gone after a PalCraft update, drop it in again.

## Change your skin

PalCraft signs Minecraft in with your own account, so Steve wears your account's skin.

1. Sign in at minecraft.net, open your profile and choose Change skin. The official Minecraft Launcher has the
   same setting under Skins.
2. Pick or upload a skin and save.
3. Press Play, then press F5 in the game to see it.

## Keys

| Key | When | Does |
|-----|------|------|
| F8 | Minecraft has control | Palworld mode: Palworld takes keyboard and mouse, Steve stays on screen |
| F8 | Palworld has control | Hands them back to Minecraft |
| F5 | Minecraft has control | Cycles first person, third person and front view |
| Hold attack | Aiming at Palworld's world | Digs it for materials |

Every other key is Minecraft's own.

## New in 0.2.1

- Palworld mode shows Steve. In 0.2.0 F8 showed Palworld's own character.
- Fixed: Palworld's memory grew by about 1 GB a minute while Minecraft was linked. UE4SS 3.0.1 keeps every
  table a script passes as an out parameter, and each terrain ray passed one. PalCraft now gives them back.
- Fixed: progress in the Minecraft world could be lost when Palworld closed first. The world saves every 45
  seconds, and Minecraft closes by itself 20 seconds after Palworld is gone.
- Kills as Steve give Palworld experience, with a message when the character levels up.
- A kit that gained items in an update tops itself up for existing players.
- Palworld's menus and prompts draw over Minecraft's blocks and over Steve.

## Limits in 0.2.1

- Single player. The bridge has room for co-op and 0.2.1 does not use it.
- DirectX 11 only. Remove `-dx12` from Palworld's Steam launch options if you added it.
- Minecraft's picture crosses to Palworld through main memory. PalCraft starts at the sharpest size under 4.2
  megapixels and steps down a size if Minecraft drops below 70 frames a second. On a 1440p screen that means
  full or three-quarter resolution.
- Digging gives materials and leaves Palworld's terrain in place. You cannot tunnel through a hill.
- Palworld chests, ore and wood stay in Palworld's inventory. Press F8 to use them.
- After a session Palworld may show an "unexpected error" notice on its next title screen. Press OK. Your
  save is fine.
- Your Palworld character stays hidden and follows Steve. PalCraft refills its health while Steve lives, so a
  hit costs Steve hearts and leaves the character alive. If a single blow kills the character outright, press
  F8 and respawn in Palworld.
- The G key asks Palworld to interact, and 0.2.1 answers "unsupported". Use F8 for chests, Pal Spheres and
  menus.
- Palworld's defeat screen shows its own character lying there. Steve is back after you respawn.
- Steve is wider than Palworld's character, so he covers more of an over-the-shoulder conversation shot.
- Riding, gliding, guns, raids and boss towers are untested in Palworld mode.
- A passive Pal may ignore your first hits and keep grazing.

## How it works

Three parts share two memory-mapped files in `%LOCALAPPDATA%\PalCraft\runtime`.

- **Fabric mod** (`mc/`). Renders Minecraft's world, hand and HUD into separate layers with depth and copies
  them to `frames.shm`. It writes the camera pose and Steve's feet to `bridge.shm` and asks Palworld where the
  ground is by sending batches of rays.
- **UE4SS Lua mod** (`host/lua/PalCraft/Scripts`). Runs once per Palworld frame. It points a camera actor at
  Minecraft's pose, carries the hidden character to Steve, answers the rays with line traces, names the surface
  under the crosshair for digging, lists nearby Pals with their health, applies damage in both directions, and
  trades hunger and temperature with Minecraft.
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

`tools/package.py` writes `dist/PalCraft-0.2.1.zip` (the Palworld mod) and `dist/PalCraft-Minecraft-0.2.1.zip`
(Prism Launcher with the PalCraft instance). You need llvm-mingw and JDK 21 or newer on your PATH. The script
expects the Prism Launcher portable zip, the Fabric API jar and the AppleSkin jar in `.tools/dl/`.

## Credits

- [Minecraft Ring](https://github.com/siddoff/Minecraft-Ring) by siddoff and justbustin (MIT): the bridge
  protocol and the Fabric mod PalCraft forks.
- [universal-modder](https://github.com/rehan-remade/universal-modder) by rehan-remade (MIT): the passthrough
  method.
- [AppleSkin](https://github.com/squeek502/AppleSkin) by squeek502 (The Unlicense): saturation on the hunger
  bar.
- MinHook, UE4SS, Fabric and Prism Launcher. [THIRD_PARTY.md](THIRD_PARTY.md) lists each license.

PalCraft is MIT licensed. Remix it.

Palworld belongs to Pocketpair. Minecraft belongs to Mojang and Microsoft. Neither company made or endorses
PalCraft.
