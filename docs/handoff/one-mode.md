# One mode, no F8

The owner asked on 2026-10-12: "make game function in minecraft mod i want it to be 1 mode instead of
switching with F8". This note holds the survey of 2026-10-12 and the plan. Nothing is built.

## What F8 flips today

Four things at once. Each already has its own switch in the code.

| Switch | Minecraft mode | Palworld mode | Set by |
|---|---|---|---|
| Windows focus | Minecraft's window: owned by Palworld's, 1/255 opaque, mouse grabbed | Palworld's window; Minecraft's is hidden | `Overlay.java:92-132`, `palcraft.cpp:1169-1192` |
| Camera | Minecraft's leads; Palworld renders from a CameraActor | Palworld's leads; the pawn stays view target | `CTRL_HOST_BODY`: `CameraSync.java:165-171` vs `218-220`, `camera.lua` |
| Body | Minecraft physics; the hidden character is carried in `MOVE_None` | Palworld's movement; Steve is placed at the character | `CTRL_MOVE_HUNTER`: `standin.lua:19-46`, `HostBody.java:156-174` |
| HUD and health | Steve's hotbar, hearts and food; Palworld's HUD off | Hearts mirror the character; hotbar shows Palworld's tools; Palworld's prompts on | `camera.lua:28-34`, `hud.lua:187-237`, `GuiMixin.java:33-62` |

Input follows the Windows foreground window and nothing else. In Minecraft mode Palworld receives no key
or click, nothing forwards input, and the "interact" request answers "unsupported" (`life.lua:40-44`).

A swap to Palworld takes a few frames. A swap back takes about half a second (one server tick plus a fixed
400 ms settle, `Overlay.java:236`), during which Palworld's own character and camera show.

## What goes wrong in a swap today

1. The swap bounces: back and forth inside 70 ms (`palcraft_native.log:21329-21330`). The Minecraft side
   has no guard against F8 still being down.
2. Palworld mode without the keyboard: in 15 of 19 logged hand-overs `SetForegroundWindow` reported "not
   yet" and nothing retries.
3. The character falls or starts inside geometry: `standin.release` sets `MOVE_Falling` at Steve's spot,
   which may be a Minecraft tower Palworld cannot see.
4. Minecraft physics take over in mid-glide, mid-climb or on a mount.
5. Two healths: Palworld mode mirrors the character and blocks damage to Steve; Minecraft mode refills the
   character after each hit.
6. Palworld food eaten in Palworld mode is lost: back in Minecraft mode the stomach is set from Steve's
   food bar (`body.lua:65-69`).
7. Open Minecraft screens close on the way out. Minecraft keeps ticking while the player cannot act there.
8. A defeat in Minecraft mode needs F8.

## What works in which mode today

Everything that fails in Minecraft mode fails for one of three reasons: Palworld gets no input, its HUD is
off, or the body is not Palworld's. Everything that fails in Palworld mode fails because Minecraft gets no
input.

- **Minecraft mode only:** digging for Minecraft drops, placing and breaking blocks, Minecraft inventory
  and crafting, Minecraft weapons, Minecraft food.
- **Palworld mode only:** Palworld materials, Palworld inventory, workbench, building, technology, map and
  fast travel, spheres, summoning and commanding Pals, Palworld weapons, NPC talk, Palworld chests,
  pickups, Palworld food, beds, respawn after the character dies, towers, cutscenes, gliding, climbing,
  swimming.
- **Untested even in Palworld mode:** riding, guns, raids, arrow damage, dungeons, climbing, sleeping.

## Three designs

**A. Minecraft drives.** Minecraft keeps focus, camera and physics. Palworld's verbs get Minecraft key
bindings that forward the matching Palworld key. Palworld receives the focus by itself while one of its
pointer screens is up. Palworld's tools and spheres sit on Minecraft's hotbar as token items, and the
selected slot decides which game gets the mouse buttons. Palworld's movement takes the body by itself for
a mount, a glide, its water, a dungeon teleport or a defeat. About 20 files, 15 to 20 working days.

**B. Palworld moves the body.** Palworld keeps the focus. The DLL subclasses Palworld's window procedure,
swallows the inputs that belong to Minecraft and Minecraft replays them. Placed blocks need a new system of
invisible blocking actors or the body walks through them. Minecraft movement goes (ladders, water, flight).
About 30 files, 25 to 35 days, three unknowns on the critical path.

**C. The hand-over presses itself.** Both rule sets stay. F8 goes. A Palworld verb key, a defeat or a shot
Palworld starts hands over; Palworld's own state hands back. About 12 source files and 5 sheets, 3 to 5
days, low risk. The camera cut and the two healths remain during a hand-over.

## Decision

Build A in three stages, with C as stage 1. The owner's words name Minecraft mode as the one to keep, A
keeps the movement the listing advertises, and stage 1 ships on parts that have run in play.

1. **Stage 1 (C), 3 to 5 days.** No F8. Palworld's verbs work from Minecraft by key.
2. **Stage 2, 6 to 8 days.** Focus-only lending for pointer screens, one camera path, tokens on the hotbar
   with aim sync.
3. **Stage 3, 5 to 7 days.** Automatic body hand-over for mount, glide and water. Steve's hearts
   everywhere. Stomach sync both ways. Carry with a sweep as a guard against walls.

## Stage 1, change by change

| File | Change |
|---|---|
| `sheets/keys.json` | Remove `switch_to_host` and `switch_to_mc`. One row per Palworld verb with two new columns: the Palworld key to press and `kind` (`screen`, `tap`, `hold`). Rows: interact F, inventory Tab, build B, map M, summon G (presses E), sphere Z (presses Q, hold), Palworld's hands X (hold), Pal command N (presses 4). Delete the `host_action` row, which also settles the R or G mismatch |
| `sheets/structs.json` | `Header.palKeyReq` u32 at 0x50 and `Header.palKey` u32 at 0x54 (written by Minecraft). `Body.hostWants` u32 at 0xD0 (written by Lua): bit 0 pointer, 1 build, 2 own shot, 3 dead, 4 mounted, 5 not walking, 6 attack held |
| `sheets/channels.json` | `body` size 0xD0 to 0xE0 |
| `sheets/flags.json` | group `wants` with the seven bits |
| `sheets/tuning.json` | `return_idle_ms` 600, `key_focus_wait_ms` 500, `recall_skip_m` 0.5, `rebound_guard_ms` 250 |
| `sheets/systems.json` | rewrite `input_switch` as automatic; replace `host_action` with `pal_keys` |
| `tools/gen.py` | emit the key table for C++ and Java |
| `host/native/src/palcraft.cpp` | `handle_switching` (1169-1192): drop the F8 edge. On a new `palKeyReq`: retry `SetForegroundWindow` until Palworld is in front or `key_focus_wait_ms` passes, then `SendInput` key down; key up when the physical key reads up. About 80 lines |
| `host/lua/PalCraft/Scripts/hud.lua` | publish `Body.hostWants`; evaluate `building` whenever a pawn exists |
| `host/lua/PalCraft/Scripts/standin.lua` | the mounted and not-walking bits, next to `pose_flags` |
| `mc/.../client/PalKeys.java` (new) | registers the bindings from the generated table; a press calls `Overlay.lend` |
| `mc/.../client/ErBridgeClient.java` | remove the F8 binding and the action key block |
| `mc/.../client/Overlay.java` | `lend(mc, row)`; enter by itself on dead or own shot; return when `hostWants == 0`, the key is up and `return_idle_ms` has passed; skip the recall when Steve stands within `recall_skip_m` of the character; ignore PalCraft keys for `rebound_guard_ms` after a return |
| `mc/.../link/BridgeShm.java`, `ErLink.java` | `requestPalKey(row)`, `hostWants()` |
| `mc/.../client/DevCommands.java` | keep `host` as the dev-only manual switch |
| `en_us.json`, `README.md`, `docs/listing.md` | names for the new bindings; ask the owner before the listing changes |

Play tests for stage 1, in this order: Tab and back; M, fast travel and back; F on a dropped item; F at a
workbench with a hold; F on an NPC; B, place a campfire, leave build mode; Z hold and release at a Lamball;
G; a defeat and respawn; Tab on top of a Minecraft tower (the character must not drop).

## Unknowns, cheapest probe first

| # | Question | Decides |
|---|---|---|
| 1 | Does Palworld take posted key and button messages while inactive? | whether stage 2 forwards without a focus change |
| 2 | Does Palworld read XInput while inactive? | the fallback for 1 |
| 3 | Does a carried character (hidden, `MOVE_None`) interact, throw and swing? | tokens under Minecraft physics |
| 4 | Aim source: camera view or control rotation? | whether aim sync is one call |
| 5 | Do Palworld's menus draw with its HUD switched off? | nothing, once `keepHud` is true |
| 6 | Is a mounted pawn attached to its mount? | the mounted bit |
| 7 | How to tell Palworld's water around a body in `MOVE_None`? | the swim hand-over |
| 8 | Does build placement follow Minecraft's camera? | building without a body hand-over |
| 9 | Palworld's default keys (the table above is from memory) | the Palworld column of `keys.json` |

## Loose ends found on the way

- `Header.hostPrompt` is drawn by Minecraft and written by nobody.
- `CTRL_GROUNDED`, `CTRL_FLYING` and `STATE_WINDOW_FOCUSED` are written and read by nobody. One mode uses
  all three.
- `camera.apply` has a `keepHud` parameter that `bridge.lua:110` passes as `false`: the ready switch for
  showing Palworld's HUD under Minecraft's camera.
- A punch at Palworld's world queues a damage row with id 0 that `combat.lua:43-44` drops.
