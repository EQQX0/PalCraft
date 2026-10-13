# Walls, blocked ways, falling under the map

Diagnosis of 2026-10-13 from the code and the logs of 0.2.1. Nothing here has run in the games. The
patches are in `terrain-patches/` and pass `git apply --check` against the working tree; applied together
in a copy, the Java compiles. Nobody has run the Lua.

## How Steve's ground is made

- **Minecraft asks.** `TerrainManager.java:443-478` queues 26 rays per 1x1 column: a ground ray from
  feet+2.2 to feet-40, a sky ray from feet+40 to feet+2.2, and 24 wall probes at 0.35, 1 and 1.875 m. One
  batch holds 2048 rays (78 columns). Footing, travel clearance, detail, the near ring (radius 8), the
  forecast and the background ring (radius 24) share one mailbox (`:392-407`, `:486-514`).
- **Palworld answers.** `rays.lua:72-101` spends 4 ms per tick on `LineTraceSingle`, Visibility channel,
  simple collision. A steep downward ray first asks `buried` (`:38-50`): a surface above and no ceiling
  means "solid right here". A ray that hits a character restarts 0.5 m further on (`:61-67`).
- **Minecraft builds** in `collectResults` (`:588-720`). Ground hit: a slab two blocks thick with its top
  in sixteenths, so a slope becomes stairs. Steep probe hit: a 3 m wall. Sky hit plus body hit with no
  ground: a hill filled to feet+6. A building floor is a ground hit like any other; `TerrainDetailManager`
  cuts doorways with 16x16 cells per column.
- **Water** has no handling anywhere in this code.

## Causes, most certain first

1. **Certain: Steve is sent 10 km up, then falls.** Palworld spawns the character at (1e6, 1e6, 1e6) cm
   before placing it. `bridge.lua:94-95` raises PLAYER_VALID for any pawn, `life.lua` bumps `hostLife`,
   `TerrainManager.java:334-342` teleports Steve there, and the carry drags the character down with him.
   Evidence: the owner's `latest.log` at 22:42:32, "Moved EqqBeBo to the Palworld character at (7292.04,
   10015.69, -13621.29)"; the same line at 21:37:53 and in `build/mc_run.log` at 23:17:38. Y 10015 lies
   above Minecraft's build limit of 2031, so no block can exist under him. Trigger: a world load or
   anything else that makes Palworld spawn the character anew. The logs show no death that night, so those
   falls came from this.
2. **High, from code: below the ground nothing catches him.** `rays.lua:46-50` answers "solid right here"
   at feet+2.2. `TerrainManager.java:668` builds that column at body height only, `:695-700` skips blocks
   inside his body, and `:708-713` clears the block he stood on. He falls until Palworld kills the carried
   character.
3. **High, from code: a miss erases ground.** `:708-713` clears a column whose ground ray missed, and a
   column's first sample clears its whole range (`:629-641`), including the floor `teleportToHunter` laid
   (`:858-888`). Rays miss while the landscape collision loads after a recall, when a ray starts under
   one-sided landscape with a rock overhead, and under small Pals (the 0.5 m restart can land below the
   ground).
4. **High, measured: the sampler cannot keep up.** "Surface attributes - ground: N" grows by 43 to 95
   columns per second. The 2 s refresh of the near ring alone needs about 100 per second, each 0.5 m of
   height change queues the ring again, the forecast comes after the ring, and detail takes every other
   slot. Walls and ground arrive after Steve has passed. Speed, creative flight and `/tp` make it worse.
5. **Medium: invisible walls.** A steep hit on the 0.35 m probe row alone turns a column into a 3 m wall
   (`:550-570`). Step height 0.6 against one block per column means slopes over 31 degrees need jumps. The
   fallback floor at Y 99 over 5x5 chunks (`:347-352`, `:891-909`) goes down at each start and stays in
   columns no ray has reached.

## Patches, smallest and safest first

| File | Fixes | Notes |
|---|---|---|
| `pcx_0_sheet.patch` | adds tuning rows `world_ceiling_m` 5000, `ray_below_m` 300, `fall_rescue_m` 12, `step_height_m` 1.1 | Inert alone. Run `python tools/gen.py` after it |
| `pcx_1_parking.patch` | cause 1 | Lua half waits until the character is below 5000 m; Java half refuses a recall outside the build height and works alone |
| `pcx_2_ground.patch` | causes 2 and 3 | A miss keeps what the column holds; "solid right here" is solid under his feet too. Cost: a stale wall stays until a ray finds ground there |
| `pcx_3_net.patch` | safety net, step height | Fallen 12 m with no Palworld ground known below: back to where he last stood. Costs: a real drop of more than 36 m into unsampled columns puts him back on the edge; Steve walks up full blocks everywhere |
| `pcx_4_walls.patch` | causes 4 and 5 | The way ahead is sampled first; the ankle row no longer makes walls; the flat fallback floor only goes under a falling Steve. Cost: kerbs and fences under 1 m stop blocking |
| `pcx_full.patch` | all five | |

Patch 4 does not cure the saturation of cause 4. Next things to try with the game running:
`REFRESH_MS` 2000 to 4000 in `TerrainPrefetch`, and a higher `ray_budget_ms`.

## Not determined without the game

- How long Palworld keeps the character at the parking spot, and whether any map places characters above
  5000 m.
- What Palworld does with a character under the map.
- Whether water, bushes or held tools block Visibility traces, and whether Steve sinks in Palworld water.
- Whether a line trace that starts inside a character's capsule hits it.
- What 300 m ground rays cost in Lua against 40 m. If "last/max ms" in `describePrefetch` rises, lower
  `ray_below_m`.

## Checks to play

1. **Patch 1:** load the world, die and respawn, fast travel. Each "Moved ... to the Palworld character
   at" line shows Y inside -2032..2031, and Steve stands on ground at once.
2. **Patch 2:** fight a ChickenPal at melee range for a minute and walk over the spot it stood on: no hole.
   Walk into a cliff face until the hill takes you: the ground stays under your feet.
3. **Patch 3, net:** in creative, fly into a hillside and stop flying, or `/tp ~ ~-30 ~`. After 12 to 36 m
   the log says "fell N m with no Palworld ground under him: back to ..." and Steve stands. Then jump off a
   real cliff higher than 12 m: no such line, and he lands at the bottom.
4. **Patch 3, step:** walk up a 40 degree slope without jumping.
5. **Patch 4:** sprint with Speed II toward a cliff over broken ground: the wall stands when you arrive.
   Walk over roots, kerbs and stairs without stopping. After start-up, walk 40 m around the spawn: no
   invisible plane at Y 100.
