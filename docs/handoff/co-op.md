# Co-op

**2026-10-13:** co-op is switched off in 0.2.2 (`coop_enabled` 0). `players.lua` breaks the handle rule of
`HANDOFF.md`: it keeps characters from `FindAllOf` and `NotifyOnNewObject`. Rewrite it onto
`PalUtility:GetPalObjectCollector(pawn).PalCharacter_Player`, read fresh each tick, before switching it on.
The frame loop now runs from the HUD of the player at this PC, so the "is this controller mine" test is gone.

## What the owner asked for

1. 2026-10-12: "make multiplayer". Scope chosen from the offered options: friends join the Palworld co-op
   world the normal way, and every player with PalCraft sees themself and the others as Minecraft
   characters. Blocks and digging stay each player's own. No second tester exists yet.
2. 2026-10-13: "make co-op only with ppl with mash up so custom co-op cuz the normal one will connect ppl
   with no mods".
3. 2026-10-13: "If the cause of the crashes is the co-op then disable it". Co-op is not in 0.2.1 and is
   not the cause. Keep it off in the next release all the same.

## What is built (working tree, not committed)

System `coop_players` in the sheets (`systems`, `channels`, `structs`, `flags`, `hooks`, `entities`,
`tuning`). Preflight clean at 3413 cells. Java compiles.

- **Palworld side, `host/lua/PalCraft/Scripts/players.lua`:** lists the other `PalPlayerCharacter` actors
  with a valid PlayerState, hides their Palworld bodies on this PC (`Mesh:SetVisibility(false, true)`, which
  does not replicate) and publishes one row each in channel `players` (`bridge.shm` 0x002000, header 0x10,
  32 rows of 0x80). Row: id u64, flags u32 (CROUCH 1, SWIM 2, DEAD 4, ACT 8), health f32, feet f32 x3 in
  host metres, Unreal yaw, pitch, name char[32] at 0x30, tool char[48] at 0x50. Lua pack string
  `"<I8I4ffffffc12c32c48"`.
- **`bridge.lua`:** the tick runs only for the local controller (`pc:IsLocalController()`), because a
  co-op host ticks a controller per friend. With friends present the own body is hidden as a mesh instead
  of as an actor (`standin.lua`), because a host's hidden actors replicate to every PC.
- **Minecraft side:** `CoopSteve extends RemotePlayer` (client-only entity, default skin chosen by a UUID
  whose high half is `0x50414C4352414654`), `CoopPlayers` (creates, updates and removes them each client
  tick; places them each frame from `CameraSync.afterCameraSetup`), `PlayerInfo`, `BridgeShm.readPlayers`,
  mixin changes for skin and light.
- **Dev aid:** `require("players").pretend(actor)` makes any character stand in for a friend
  (`build/probe/mp2.lua`).

## What was seen working, on one PC

With a Lamball as the stand-in: the table publishes one row, Minecraft draws a player with a different
default skin and a "Friend" name tag at the Lamball's place, the Palworld body hides and returns, and the
own body switches to the mesh hide. Screenshot: `build/shots/keep_coop_friend_standin.png`.

## What is not done or not verified

- **`players.lua` keeps handles across ticks**, the fault behind the 0.2.1 crashes. Rewrite it by the
  fresh-handle rule in `HANDOFF.md` (candidate: `GameState.PlayerArray` and `PlayerState:GetPawn()`).
- A real second player. A joiner's side (a client of a host). A host with real friends.
- Palworld's own nameplate still shows over the Minecraft player.
- The tool in a friend's hand, and the crouch, swim, dead and act flags.
- `melty.json` has no multiplayer block. `sheets/listing.json` still says single player. README, listing
  and MODLOG do not mention co-op.
- Add a switch that turns the whole system off, and ship the next release with it off.

## Facts checked in Palworld

- Solo world: `KSL:IsStandalone(pawn)` true, `IsServer` true, `IsDedicatedServer` false.
- `PlayerState.PlayerId` is 259 for the owner; `GetPlayerName():ToString()` is non-ASCII on this PC.
- `pawn:GetBaseAimRotation().Pitch`, `pawn.Mesh:GetAnimInstance():IsAnyMontagePlaying()` and
  `GameplayStatics:GetGameState(pawn).PlayerArray` work.
- The Multiplayer switch is under World Select, Change World Settings. With it ON, the Options menu's
  Player List tab shows the Invitation Code.
- One Palworld crash happened 23 s after starting with the hosted test world as the target. The second
  diagnosis puts it in UE4SS's debug window, not in this code (`startup.md`, finding 2).

## Plan for "only people with the mashup"

Palworld's invite code lets anyone in, with or without PalCraft. The way to keep co-op between PalCraft
players is Melty's own lobby:

1. The recipe gets a multiplayer block. Draft from `setup_multiplayer` (folder "PalCraft"):
   `"multiplayer":{"maxPlayers":4,"connect":{"address":{"log":"{localappdata}/PalCraft/melty.log","after":"Melty join address: "},"joinFile":{"path":"{localappdata}/PalCraft/melty.properties","key":"join"}}}`
2. Hosting: the mod reads the invite code and writes `Melty join address: <address>` to that log. Melty
   wants a lowercase host name or an IPv4 address; "a relay id goes in as a host name, like
   <id>.steamlobby".
3. Joining: Melty writes the address into `melty.properties`; the mod joins and writes
   `Melty joined: <address>` or `Melty join failed: <why>`.
4. Melty then shows open games and join links only to people who have the mashup.

Open problems:

- Nobody has found how to read the invite code from Lua, or how to join by code without driving the
  title menu.
- A host can still hand the code to someone outside Melty. Refusing such a player needs a handshake
  between the two mods, and no channel for one is known yet.
- Palworld connects through Steam, so the join test needs a second PC and a second account. One PC can
  only check the host half.
- `setup_multiplayer` runs before `submit_release`, and again with both logs after the test.
