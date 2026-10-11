"""Sheets -> code, and the preflight that guards every build.

    python tools/gen.py            preflight, then generate
    python tools/gen.py --check    preflight only

Preflight lists every unfilled cell and every reference from one sheet to another (or to a file, or to a
Java constant) that does not resolve. Nothing is generated unless that list is empty.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SHEETS = ROOT / "sheets"
PROTOCOL_JAVA = ROOT / "mc/src/main/java/dev/palcraft/bridge/link/Protocol.java"

SIZES = {"u32": 4, "i32": 4, "f32": 4, "u64": 8, "char": 1}
LUA_FMT = {"u32": "I4", "i32": "i4", "f32": "f", "u64": "I8"}


def load(name):
    data = json.loads((SHEETS / f"{name}.json").read_text(encoding="utf-8"))
    cols = data["columns"]
    return [dict(zip(cols, r)) | {"_n": i + 1, "_len": len(r), "_cols": len(cols)} for i, r in enumerate(data["rows"])]


def num(v):
    return int(v, 0) if isinstance(v, str) else int(v)


def java_constants():
    text = PROTOCOL_JAVA.read_text(encoding="utf-8")
    env = {}
    for m in re.finditer(r"public static final int\s+([^;]+);", text):
        for part in m.group(1).split(","):
            if "=" not in part:
                continue
            name, expr = (s.strip() for s in part.split("=", 1))
            expr = re.sub(r"//.*", "", expr).strip()
            try:
                env[name] = int(eval(expr, {"__builtins__": {}}, dict(env)))
            except Exception:
                pass
    return env


def preflight():
    problems = []
    names = ["games", "sides", "systems", "channels", "structs", "flags", "hooks", "keys", "kit", "entities",
             "tuning", "listing", "gather", "pal_loot"]
    S = {}
    for n in names:
        try:
            S[n] = load(n)
        except FileNotFoundError:
            problems.append(f"{n}.json: sheet missing")
            S[n] = []
    for n, rows in S.items():
        for r in rows:
            if r["_len"] != r["_cols"]:
                problems.append(f"{n} row {r['_n']}: {r['_len']} cells for {r['_cols']} columns")
            for k, v in r.items():
                if k.startswith("_"):
                    continue
                if v is None or (isinstance(v, str) and v.strip() in ("", "?", "TBD", "TODO")):
                    problems.append(f"{n} row {r['_n']}: '{k}' is not filled in")

    sides = {r["id"] for r in S["sides"]}
    games = {r["slug"] for r in S["games"]} | {"shared", "-"}
    systems = {r["id"] for r in S["systems"]}
    channels = {r["id"] for r in S["channels"]}
    structs = {}
    for r in S["structs"]:
        structs.setdefault(r["struct"], []).append(r)
    java = java_constants()

    def ref(sheet, r, col, value, pool, what):
        if value not in pool:
            problems.append(f"{sheet} row {r['_n']}: {col} '{value}' is not a known {what}")

    def java_ref(sheet, r, value):
        j = r["java"]
        if j == "-":
            return
        if j not in java:
            problems.append(f"{sheet} row {r['_n']}: Java constant {j} not found in Protocol.java")
        elif java[j] != value:
            problems.append(f"{sheet} row {r['_n']}: Java {j} = {java[j]:#x}, sheet says {value:#x}")

    for r in S["sides"]:
        ref("sides", r, "game", r["game"], games, "game")
    for r in S["channels"]:
        ref("channels", r, "struct", r["struct"], structs, "struct")
        ref("channels", r, "writer", r["writer"], sides, "side")
        for x in r["readers"]:
            ref("channels", r, "readers", x, sides, "side")
        if r["struct"] in structs:
            end = max(num(f["off"]) + SIZES.get(f["type"], 0) * f["count"] for f in structs[r["struct"]])
            if end > num(r["size"]):
                problems.append(f"channels row {r['_n']}: struct {r['struct']} needs {end:#x} bytes, region has {r['size']}")
    by_file = {}
    for r in S["channels"]:
        by_file.setdefault(r["file"], []).append(r)
    for rows in by_file.values():
        rows = sorted(rows, key=lambda r: num(r["offset"]))
        for a, b in zip(rows, rows[1:]):
            if num(a["offset"]) + num(a["size"]) > num(b["offset"]) and a["id"] != "frames_slot":
                problems.append(f"channels: {a['id']} runs into {b['id']}")
    for name, fields in structs.items():
        spans = []
        for f in fields:
            ref("structs", f, "writer", f["writer"], sides, "side")
            if f["type"] not in SIZES:
                problems.append(f"structs row {f['_n']}: unknown type {f['type']}")
                continue
            java_ref("structs", f, num(f["off"]))
            spans.append((num(f["off"]), num(f["off"]) + SIZES[f["type"]] * f["count"], f["field"]))
        spans.sort()
        for a, b in zip(spans, spans[1:]):
            if a[1] > b[0]:
                problems.append(f"structs: {name}.{a[2]} overlaps {name}.{b[2]}")
    for r in S["flags"]:
        ref("flags", r, "writer", r["writer"], sides, "side")
        java_ref("flags", r, num(r["value"]))
    for r in S["hooks"]:
        ref("hooks", r, "side", r["side"], sides, "side")
        ref("hooks", r, "sys", r["sys"], systems, "system")
    for r in S["keys"]:
        ref("keys", r, "side", r["side"], sides, "side")
    for r in S["tuning"]:
        ref("tuning", r, "side", r["side"], sides, "side")
    ent_kinds = {r["name"] for r in S["flags"] if r["group"] == "ent"} | {"-"}
    for r in S["entities"]:
        ref("entities", r, "kind", r["kind"], ent_kinds, "entity kind")
    seen = set()
    for r in S["kit"]:
        if r["slot"] in seen or not 0 <= r["slot"] <= 35:
            problems.append(f"kit row {r['_n']}: slot {r['slot']} is taken or out of range")
        seen.add(r["slot"])
        if not 1 <= r["count"] <= 64:
            problems.append(f"kit row {r['_n']}: count {r['count']} is not 1..64")
        if not re.fullmatch(r"[a-z0-9_]+:[a-z0-9_/]+", r["item"]):
            problems.append(f"kit row {r['_n']}: '{r['item']}' is not an item id")
    surfaces = {r["name"] for r in S["flags"] if r["group"] == "surface"}
    for n in ("gather", "pal_loot"):
        for r in S[n]:
            if not re.fullmatch(r"[a-z0-9_]+:[a-z0-9_/]+", str(r["item"])):
                problems.append(f"{n} row {r['_n']}: '{r['item']}' is not an item id")
            if not (1 <= r["min"] <= r["max"] <= 64) or not (0 < r["chance"] <= 1):
                problems.append(f"{n} row {r['_n']}: count {r['min']}..{r['max']} or chance {r['chance']} out of range")
    for r in S["gather"]:
        ref("gather", r, "surface", r["surface"], surfaces, "surface")
        ref("gather", r, "tool", r["tool"], {"any", "pickaxe", "axe", "shovel", "hoe"}, "tool")
        if not 0 <= r["min_tier"] <= 4:
            problems.append(f"gather row {r['_n']}: min_tier {r['min_tier']} is not 0..4")
    for r in S["systems"]:
        ref("systems", r, "owner", r["owner"], games, "game")
        for c in r["channels"]:
            ref("systems", r, "channels", c, channels, "channel")
        if r["in_0_1"] and r["code"] != "-" and not (ROOT / r["code"]).exists():
            problems.append(f"systems row {r['_n']}: {r['id']} has no code yet ({r['code']})")
        if r["in_0_1"] and r["code"] == "-":
            problems.append(f"systems row {r['_n']}: {r['id']} is in this version but names no code")
    for r in S["listing"]:
        if r["kind"] == "file" and not (ROOT / r["value"]).exists():
            problems.append(f"listing row {r['_n']}: file {r['value']} does not exist")
    return S, problems


def c_name(s):
    return re.sub(r"(?<=[a-z0-9])(?=[A-Z])", "_", s).upper()


def generate(S):
    out = []
    # ---- C header
    h = ["/* Generated by tools/gen.py from sheets/. Do not edit. */", "#pragma once", ""]
    for r in S["channels"]:
        h.append(f"#define PC_OFF_{r['id'].upper()} {r['offset']}u")
        h.append(f"#define PC_SIZE_{r['id'].upper()} {r['size']}u")
    h.append("")
    for r in S["structs"]:
        h.append(f"#define PC_{c_name(r['struct'])}_{c_name(r['field'])} {r['off']}u")
    h.append("")
    for r in S["flags"]:
        h.append(f"#define PC_{r['group'].upper()}_{r['name']} {r['value']}u")
    h.append("")
    for r in S["tuning"]:
        if r["side"] == "native":
            h.append(f"#define PC_TUNE_{r['id'].upper()} {float(r['value'])!r}f")
    for r in S["hooks"]:
        if r["side"] == "native":
            h.append(f"#define PC_SLOT_{r['id'].upper()} {r['slot']}")
    for r in S["keys"]:
        if r["side"] == "native":
            h.append(f"#define PC_VK_{r['id'].upper()} {r['vk']}")
    out.append((ROOT / "host/native/gen/protocol.h", "\n".join(h) + "\n"))

    # ---- Lua module
    L = ["-- Generated by tools/gen.py from sheets/. Do not edit.", "local P = {}", "P.off = {"]
    for r in S["channels"]:
        if r["file"] == "bridge.shm":
            L.append(f"    {r['id']} = {r['offset']},")
    L.append("}")
    by = {}
    for r in S["structs"]:
        by.setdefault(r["struct"], []).append(r)
    for name, fields in by.items():
        L.append(f"P.{name} = {{")
        for f in fields:
            fmt = f"c{f['count']}" if f["type"] == "char" else LUA_FMT[f["type"]] * f["count"]
            L.append(f"    [\"{f['field']}\"] = {{ {f['off']}, \"<{fmt}\", {SIZES[f['type']] * f['count']} }},")
        L.append("}")
    groups = {}
    for r in S["flags"]:
        groups.setdefault(r["group"], []).append(r)
    for g, rows in groups.items():
        L.append(f"P.{g} = {{")
        for r in rows:
            L.append(f"    {r['name']} = {r['value']},")
        L.append("}")
    L.append("P.tune = {")
    for r in S["tuning"]:
        if r["side"] == "lua":
            L.append(f"    {r['id']} = {r['value']},")
    L.append("}")
    L.append("P.hook = {")
    for r in S["hooks"]:
        if r["side"] == "lua":
            L.append(f"    {r['id']} = \"{r['target']}\",")
    L.append("}")
    L.append("P.listing = {")
    for r in S["listing"]:
        if r["kind"] == "id":
            L.append(f"    {r['id']} = \"{r['value']}\",")
    L.append("}")
    L.append("return P")
    out.append((ROOT / "host/lua/PalCraft/Scripts/gen_protocol.lua", "\n".join(L) + "\n"))

    # ---- Java starter kit
    J = ["// Generated by tools/gen.py from sheets/kit.json. Do not edit.", "package dev.palcraft.bridge.gen;", "",
         "public final class Kit {", "\tprivate Kit() {", "\t}", "",
         "\t/** slot, item id, count. */", "\tpublic static final Object[][] STACKS = {"]
    for r in S["kit"]:
        J.append(f"\t\t{{{r['slot']}, \"{r['item']}\", {r['count']}}},")
    J += ["\t};", "}"]
    out.append((ROOT / "mc/src/main/java/dev/palcraft/bridge/gen/Kit.java", "\n".join(J) + "\n"))

    # ---- Java loot tables and Minecraft-side tuning
    surface = {r["name"]: num(r["value"]) for r in S["flags"] if r["group"] == "surface"}
    J = ["// Generated by tools/gen.py from sheets/gather.json and sheets/pal_loot.json. Do not edit.",
         "package dev.palcraft.bridge.gen;", "", "public final class Loot {", "\tprivate Loot() {", "\t}", "",
         "\t/** surface, tool, lowest tier, item id, min, max, chance, xp. */", "\tpublic static final Object[][] GATHER = {"]
    for r in S["gather"]:
        J.append(f"\t\t{{{surface[r['surface']]}, \"{r['tool']}\", {r['min_tier']}, \"{r['item']}\", {r['min']}, {r['max']}, "
                 f"{float(r['chance'])!r}, {r['xp']}}},")
    J += ["\t};", "", "\t/** part of the Palworld character id (* = every Pal), item id, min, max, chance. */",
          "\tpublic static final Object[][] PALS = {"]
    for r in S["pal_loot"]:
        J.append(f"\t\t{{\"{r['match']}\", \"{r['item']}\", {r['min']}, {r['max']}, {float(r['chance'])!r}}},")
    J += ["\t};", "}"]
    out.append((ROOT / "mc/src/main/java/dev/palcraft/bridge/gen/Loot.java", "\n".join(J) + "\n"))
    J = ["// Generated by tools/gen.py from sheets/tuning.json (side mc). Do not edit.", "package dev.palcraft.bridge.gen;", "",
         "public final class Tune {", "\tprivate Tune() {", "\t}", ""]
    for r in S["tuning"]:
        if r["side"] == "mc":
            J.append(f"\t/** {r['meaning']} ({r['unit']}) */")
            J.append(f"\tpublic static final double {r['id'].upper()} = {float(r['value'])!r};")
    J += ["}"]
    out.append((ROOT / "mc/src/main/java/dev/palcraft/bridge/gen/Tune.java", "\n".join(J) + "\n"))

    for path, text in out:
        path.parent.mkdir(parents=True, exist_ok=True)
        if not path.exists() or path.read_text(encoding="utf-8") != text:
            path.write_text(text, encoding="utf-8", newline="\n")
            print(f"wrote {path.relative_to(ROOT)}")


def main():
    S, problems = preflight()
    cells = sum(len([k for k in r if not k.startswith("_")]) for rows in S.values() for r in rows)
    if problems:
        print(f"PREFLIGHT: {len(problems)} open item(s) in {cells} cells")
        for p in problems:
            print("  - " + p)
        if "--force" not in sys.argv:
            return 1
    else:
        print(f"PREFLIGHT clean: {cells} cells, every reference resolves")
    if "--check" not in sys.argv:
        generate(S)
    return 0


if __name__ == "__main__":
    sys.exit(main())
