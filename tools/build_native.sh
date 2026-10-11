#!/usr/bin/env bash
# Builds host/native into build/native/palcraft.dll with the llvm-mingw in .tools/.
# With "dev" as the first argument the DLL is also copied into the mod folder under a fresh name, so a
# running Palworld can load it without a restart (main.lua reads runtime/dev_dll.txt).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CC_DIR="$(ls -d "$ROOT"/.tools/compiler/*/bin | head -1)"
MH="$ROOT/host/native/third_party/minhook"
OUT="$ROOT/build/native"
mkdir -p "$OUT"
python "$ROOT/tools/gen.py" --force >/dev/null
OBJS=()
for c in "$MH"/src/*.c "$MH"/src/hde/*.c; do
  o="$OUT/$(basename "${c%.c}").o"
  [ "$o" -nt "$c" ] || "$CC_DIR/clang" --target=x86_64-w64-mingw32 -O2 -c "$c" -I"$MH/include" -o "$o"
  OBJS+=("$o")
done
"$CC_DIR/clang++" --target=x86_64-w64-mingw32 -O2 -std=c++17 -Wall -Wno-unused-function -Wno-unused-variable \
  -shared -static -o "$OUT/palcraft.dll" \
  "$ROOT/host/native/src/palcraft.cpp" "${OBJS[@]}" \
  -I"$MH/include" -I"$ROOT/host/native/gen" \
  -ld3d11 -ldxgi -ld3dcompiler -ldxguid -luser32
echo "built $OUT/palcraft.dll ($(stat -c %s "$OUT/palcraft.dll") bytes)"
if [ "${1:-}" = "dev" ]; then
  name="palcraft_dev_$(date +%H%M%S).dll"
  cp "$OUT/palcraft.dll" "$ROOT/host/lua/PalCraft/$name"
  printf '%s' "$name" > "$ROOT/runtime/dev_dll.txt"
  echo "dev copy: $name"
else
  cp "$OUT/palcraft.dll" "$ROOT/host/lua/PalCraft/palcraft.dll"
fi
