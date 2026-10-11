"""Builds the two files Melty installs, plus the install recipe (melty.json) from the sheets.

    python tools/package.py

dist/PalCraft-<v>.zip            -> {game}/Pal/Binaries/Win64/Mods/PalCraft   (UE4SS Lua mod + native DLL)
dist/PalCraft-Minecraft-<v>.zip  -> {localappdata}/PalCraft                    (Prism Launcher + the instance)

Nothing from Palworld or Minecraft goes in: Prism downloads Minecraft on the player's PC.
"""
import hashlib
import json
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DL = ROOT / ".tools" / "dl"
DIST = ROOT / "dist"
NAME = "PalCraft"
PRISM_ZIP = DL / "PrismLauncher-Portable-11.1.1.zip"
STAMP = (2026, 10, 11, 0, 0, 0)

# Dev-only files that must never reach a player.
MOD_SKIP = {"runtime_dir.txt", "dev.lua"}
SECRETS = ("accounts.json", "prismlauncher.cfg", "metacache", ".env")


def sheet(name):
    data = json.loads((ROOT / "sheets" / f"{name}.json").read_text(encoding="utf-8"))
    return [dict(zip(data["columns"], row)) for row in data["rows"]]


def props(path):
    return dict(line.split("=", 1) for line in path.read_text(encoding="utf-8").splitlines() if "=" in line and not line.startswith("#"))


def add(z, arc, data):
    for bad in SECRETS:
        if arc.lower().endswith(bad):
            sys.exit(f"refusing to package {arc}")
    info = zipfile.ZipInfo(arc, STAMP)
    info.compress_type = zipfile.ZIP_DEFLATED
    info.external_attr = 0o644 << 16
    z.writestr(info, data)


def notices(z, prefix=""):
    add(z, prefix + "LICENSE.txt", (ROOT / "LICENSE").read_bytes())
    add(z, prefix + "THIRD_PARTY.md", (ROOT / "THIRD_PARTY.md").read_bytes())
    add(z, prefix + "README.md", (ROOT / "README.md").read_bytes())


def build_host(out):
    mod = ROOT / "host" / "lua" / NAME
    dll = mod / "palcraft.dll"
    if not dll.exists():
        sys.exit("palcraft.dll missing: run  bash tools/build_native.sh")
    with zipfile.ZipFile(out, "w") as z:
        add(z, "enabled.txt", (mod / "enabled.txt").read_bytes())
        add(z, "palcraft.dll", dll.read_bytes())
        for lua in sorted((mod / "Scripts").glob("*.lua")):
            if lua.name not in MOD_SKIP:
                add(z, f"Scripts/{lua.name}", lua.read_bytes())
        add(z, "MinHook-LICENSE.txt", (ROOT / "host/native/third_party/minhook/LICENSE.txt").read_bytes())
        notices(z)


def build_minecraft(out, g, version):
    jar = ROOT / "mc" / "build" / "libs" / f"palcraft-{version}.jar"
    api = DL / f"fabric-api-{g['fabric_api_version']}.jar"
    for need in (jar, api, PRISM_ZIP):
        if not need.exists():
            sys.exit(f"missing {need}")
    inst = f"Prism/instances/{NAME}/"
    pack = {
        "formatVersion": 1,
        "components": [
            {"uid": "org.lwjgl3", "version": "3.3.3", "dependencyOnly": True},
            {"uid": "net.minecraft", "version": g["minecraft_version"], "important": True},
            {"uid": "net.fabricmc.intermediary", "version": g["minecraft_version"], "dependencyOnly": True},
            {"uid": "net.fabricmc.fabric-loader", "version": g["loader_version"]},
        ],
    }
    cfg = "\n".join([
        "[General]", "ConfigVersion=1.2", "InstanceType=OneSix", f"name={NAME}", "iconKey=default",
        "OverrideMemory=true", "MinMemAlloc=512", "MaxMemAlloc=3072",
        "OverrideWindow=true", "LaunchMaximized=false", "MinecraftWinWidth=1280", "MinecraftWinHeight=720",
        "",
    ])
    # Minecraft fills in every option this leaves out.
    options = "\n".join([
        "pauseOnLostFocus:false", "fullscreen:false", "tutorialStep:none", "onboardAccessibility:false",
        "narrator:0", "skipMultiplayerWarning:true", "",
    ])
    with zipfile.ZipFile(out, "w") as z:
        # Prism Launcher's official portable build, byte for byte.
        with zipfile.ZipFile(PRISM_ZIP) as src:
            for e in src.infolist():
                if not e.is_dir():
                    add(z, "Prism/" + e.filename, src.read(e))
        add(z, inst + "instance.cfg", cfg)
        add(z, inst + "mmc-pack.json", json.dumps(pack, indent=2))
        add(z, inst + ".minecraft/options.txt", options)
        add(z, inst + f".minecraft/mods/{jar.name}", jar.read_bytes())
        add(z, inst + f".minecraft/mods/{api.name}", api.read_bytes())
        add(z, "PrismLauncher-COPYING.md", (DL / "PrismLauncher-COPYING.md").read_bytes())
        notices(z)


def recipe(version, checks):
    prism = {"kind": "exe", "path": f"{{localappdata}}/{NAME}/Prism/prismlauncher.exe", "args": ["--launch", NAME]}
    return {
        "schemaVersion": 1,
        "mode": "installed",
        "games": [{"slug": g["slug"], "role": g["role"]} for g in sheet("games")],
        "components": [
            {"id": "main", "fileName": f"{NAME}-{version}.zip", "label": "PalCraft for Palworld", "kind": "main", "required": True},
            {"id": "minecraft", "fileName": f"{NAME}-Minecraft-{version}.zip",
             "label": "Minecraft side: Prism Launcher with the PalCraft instance", "kind": "extra", "required": True},
        ],
        "requirements": [{"kind": "loader", "id": "ue4ss"}],
        "mappings": [
            {"component": "main", "from": "", "to": "{game}/Pal/Binaries/Win64/Mods/" + NAME},
            {"component": "minecraft", "from": "", "to": "{localappdata}/" + NAME},
        ],
        "launch": {"kind": "game"},
        "setup": {
            "label": "Minecraft",
            "launch": prism,
            "done": {"file": f"{{localappdata}}/{NAME}/Prism/instances/{NAME}/.minecraft/logs/latest.log", "contains": "Backend library:"},
            "stopWhenDone": True,
        },
        "together": [{"launch": prism, "startFirst": False}],
        "runtimeData": ["{localappdata}/" + NAME],
        "notes": {"firstLaunch": "Load a single-player world in Palworld. Minecraft joins by itself; F8 swaps control between the two games."},
        "test": {"checks": checks, "minutes": 10},
    }


def describe(path):
    data = path.read_bytes()
    with zipfile.ZipFile(path) as z:
        entries = [{"path": e.filename, "size": e.file_size} for e in z.infolist()]
    return {"fileName": path.name, "size": len(data), "sha256": hashlib.sha256(data).hexdigest(), "entries": entries}


def main():
    if subprocess.run([sys.executable, str(ROOT / "tools" / "gen.py"), "--check"]).returncode:
        melty = ROOT / "melty.json"
        if melty.exists():
            sys.exit("preflight is not clean: fix the sheets first")
    listing = {r["id"]: r["value"] for r in sheet("listing")}
    version = listing["version"]
    g = props(ROOT / "mc" / "gradle.properties")
    if g["version"] != version:
        sys.exit(f"mc/gradle.properties says {g['version']}, listing sheet says {version}")
    DIST.mkdir(exist_ok=True)
    host = DIST / f"{NAME}-{version}.zip"
    mc = DIST / f"{NAME}-Minecraft-{version}.zip"
    build_host(host)
    build_minecraft(mc, g, version)
    checks = [v for k, v in sorted(listing.items()) if k.startswith("test_check_")]
    files = {"main": describe(host), "minecraft": describe(mc)}
    melty_path = ROOT / "melty.json"
    melty = json.loads(melty_path.read_text(encoding="utf-8")) if melty_path.exists() else {}
    melty.update({"title": listing["title"], "slug": listing["slug"], "modId": listing["mod_id"], "version": version,
                  "recipe": recipe(version, checks)})
    melty_path.write_text(json.dumps(melty, indent=2) + "\n", encoding="utf-8", newline="\n")
    (DIST / "files.json").write_text(json.dumps(files, indent=1), encoding="utf-8")
    for f in files.values():
        print(f"{f['fileName']}: {f['size']} bytes, {len(f['entries'])} files, sha256 {f['sha256']}")


if __name__ == "__main__":
    main()
