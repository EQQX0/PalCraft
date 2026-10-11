Play Palworld as Steve. You move, look, build, dig and fight with Minecraft's controls, and you see it happen inside Palworld's world.

PalCraft runs both games at once. Minecraft: Java Edition owns your player, your camera, your blocks and your weapons. Palworld owns the islands and the Pals. Palworld draws its frame from Minecraft's camera, then PalCraft paints Minecraft's blocks, hand and hotbar into that frame, hidden behind Palworld's hills and trees where they should be.

## What you can do

- Walk, sprint, jump and swim on Palworld's terrain with Minecraft movement.
- Place and break blocks anywhere on the islands. Build a cobblestone hut next to a Lamball.
- Hold attack on Palworld's ground, rock and trees to dig Minecraft materials: logs, dirt, seeds, cobblestone, coal, iron, gold, diamonds. Better tools dig faster and find better ore.
- Hit Pals with a sword, shoot them with a bow, or light TNT beside them. A Pal you kill drops Minecraft loot and experience.
- Farm, craft and smelt. The kit holds water, seeds, saplings and a crafting table.
- Wear armor. A Pal's hit goes through Minecraft's armor, toughness, Protection and shield rules.
- Eat golden apples. Alpha Pals drop the enchanted one, and the old recipe is back: eight gold blocks around an apple.
- Watch your body. Steve's hunger feeds your hidden Palworld character, AppleSkin shows saturation, and a gauge above the hunger bar shows Palworld's temperature. Campfires, torches and leather armor keep the cold off.
- Press **F5** for third person. Press **F8** to hand the keyboard and mouse to Palworld for menus, catching and base work, and **F8** again to go back.

You start in survival with a kit: iron sword, bow and arrows, iron pickaxe, building blocks, TNT, food, torches, two water buckets, seeds, saplings, a crafting table and two golden apples. Type `/gamemode creative` if you would rather build without limits.

## What you need

- Palworld on Steam, version 1.0, running in DirectX 11 (the default).
- Minecraft: Java Edition on your Microsoft account.

## How to play

Press Play. The first Play downloads Minecraft 1.21.1 and takes a few minutes. Then:

1. In Palworld, start or load a single-player world.
2. Minecraft opens its own PalCraft world by itself. Steve appears where your Palworld character stands.
3. Play. Minecraft's window sits unseen on top of Palworld's and takes your keyboard and mouse, so you look at one picture: Palworld's, with Minecraft drawn into it.

## Add your own mods

PalCraft's Minecraft is Java Edition 1.21.1 on Fabric. It lives in its own folder, apart from your other Minecraft installs.

1. Close Palworld and Minecraft.
2. Download the mod's **Fabric** file for Minecraft **1.21.1** from CurseForge or Modrinth.
3. Press Win+R, paste `%LOCALAPPDATA%\PalCraft\Prism\instances\PalCraft\.minecraft\mods` and press Enter.
4. Drop the `.jar` file into that folder.
5. Press Play.

Fabric API is in the folder already. Forge and NeoForge files do not load, and neither do files for other Minecraft versions. Mods that add items or change the HUD and inventory fit best. A mod that replaces Minecraft's renderer can break the picture inside Palworld. If the game stops starting, take your last jar out. If a mod is gone after a PalCraft update, drop it in again.

## Change your skin

PalCraft signs Minecraft in with your own account, so Steve wears your account's skin.

1. Sign in at minecraft.net, open your profile and choose Change skin. The official Minecraft Launcher has the same setting under Skins.
2. Pick or upload a skin and save.
3. Press Play, then press F5 in the game to see it.

## Limits in 0.2.0

- Single player.
- DirectX 11 only. Remove `-dx12` from Palworld's Steam launch options if you added it.
- Digging gives materials and leaves Palworld's terrain in place. You cannot tunnel through a hill.
- Nights are cold. Hold a torch, stand by a fire or wear leather.
- Your Palworld character stays hidden and follows Steve. If a single blow kills it outright, press F8 and respawn in Palworld.
- Chests, Pal Spheres and Palworld menus need F8 first.

## Credits

- [Minecraft Ring](https://github.com/siddoff/Minecraft-Ring) by siddoff and justbustin (MIT): the bridge protocol and the Fabric mod PalCraft forks.
- [universal-modder](https://github.com/rehan-remade/universal-modder) by rehan-remade (MIT): the passthrough method.
- [AppleSkin](https://github.com/squeek502/AppleSkin) by squeek502 (The Unlicense): saturation on the hunger bar.
- MinHook by Tsuda Kageyu (BSD 2-Clause), UE4SS by the UE4SS-RE team (MIT), Fabric (Apache 2.0), Prism Launcher 11.1.1 (GPL-3.0, shipped unmodified).

PalCraft's own code is MIT licensed. Palworld belongs to Pocketpair. Minecraft belongs to Mojang and Microsoft. Neither company made or endorses PalCraft.
