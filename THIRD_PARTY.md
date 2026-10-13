# Third-party notices

The MIT license in [LICENSE](LICENSE) covers PalCraft's own code. It grants no rights to Palworld or
Minecraft. PalCraft ships no file from either game. Each player runs their own copies.

## Code PalCraft builds on

**Minecraft Ring** by siddoff, a Windows adaptation of
[minecraft-crossover-bridge](https://github.com/justbustin/minecraft-crossover-bridge) by justbustin. MIT.
PalCraft's Fabric mod in `mc/` is a fork of its `mc-bridge`. The shared-memory protocol and the compositing
shader started from its Elden Ring bridge. Source: <https://github.com/siddoff/Minecraft-Ring>.

**universal-modder** by Rehan and contributors. MIT. PalCraft follows its passthrough method and used its
`um` tool during development. No universal-modder code ships in the packages.
Source: <https://github.com/rehan-remade/universal-modder>.

**MinHook** by Tsuda Kageyu. BSD 2-Clause. Compiled into `palcraft.dll`. The full license, with the Hacker
Disassembler Engine notice, is in
[host/native/third_party/minhook/LICENSE.txt](host/native/third_party/minhook/LICENSE.txt) and ships beside
the DLL as `MinHook-LICENSE.txt`.

## Programs the Minecraft package carries

**Prism Launcher 11.1.1**, GPL-3.0. The package holds the official portable Windows build, byte for byte, with
its own license files. Source: <https://github.com/PrismLauncher/PrismLauncher/tree/11.1.1>.

**Fabric API 0.116.17+1.21.1**, Apache 2.0. Unmodified jar from <https://github.com/FabricMC/fabric>.

**AppleSkin 3.0.6** by squeek502. The Unlicense (public domain). The jar from
<https://modrinth.com/mod/appleskin> with one change: PalCraft's build script drops the JEI mixin config from
its `fabric.mod.json`, because that config logs a failed class load at every start without JEI. It draws
saturation on the hunger bar. Source:
<https://github.com/squeek502/AppleSkin>.

Prism Launcher downloads Minecraft 1.21.1, Fabric Loader 0.19.5 and Java 21 to your PC from their official
servers, signed in with your own Minecraft account.

## Installed by Melty

**UE4SS 3.0.1** by the UE4SS-RE team. MIT. Melty installs it into Palworld. PalCraft ships none of its
files.
Source: <https://github.com/UE4SS-RE/RE-UE4SS>.

## Build tools

llvm-mingw, Eclipse Temurin JDK and Gradle build PalCraft and stay out of the packages. Each keeps its own
license.
