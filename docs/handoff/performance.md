# Performance

Diagnosis of 2026-10-13 from the code and the logs (28 Palworld sessions with 1943 sync windows, 13
Minecraft logs with 969 five-second windows). No log holds a timing line, so each estimate below comes from
byte and call counts. Nothing here has run in the games.

## One frame today

- Rates at 1920x1079: Palworld median 101 fps. Minecraft renders median 94 fps and publishes median 84.
- Pixels: one layer is 8.29 MB. Palworld mode sends 3 layers (24.9 MB), first person 4 (33.1 MB). Each
  byte moves four times: GPU to PBO (`FramePassthrough.java:286`), PBO to `frames.shm` (`:418-427`),
  `frames.shm` to a D3D11 dynamic texture (`palcraft.cpp:749-752`), driver to GPU. That is 100 to 130 MB of
  memory traffic per frame.
- Lua per Palworld tick: about 49 calls into Unreal and about 50 file syscalls, plus the entity table
  every 2 ticks and terrain rays under a 4 ms budget.
- Sync: 1,123,535 frames exact, 1 older, 42,264 missing. Median window 2.2% missing, 90th percentile 7.5%.

## Bottlenecks, by cost per frame

1. **Minecraft's CPU pixel path** (`FramePassthrough.java:273-288`, `405-448`): about 3 to 5 ms of a
   10.6 ms frame at 1080p. At 2560x1439 Minecraft fell to 48 to 63 fps. Before capture starts it renders
   115 to 119 fps.
2. **Native upload on Palworld's render thread** (`palcraft.cpp:737-767`): a 25 to 33 MB copy inside the
   draw hook, about 2 to 4 ms per new Minecraft frame, plus a back-buffer copy and two downsample draws
   per present. Palworld's median fps falls with layer size: 114 at 1280x720, 101 at 1920x1079.
3. **Terrain rays on Palworld's game thread** (`rays.lua:72-101`): 4 to 6 ms on a busy tick, because
   `os.clock` steps in 1 ms and overruns the budget. `TerrainPrefetch.java:6-7` asks again for 197 columns
   x 26 rays every 2 s (2,600 rays a second standing still), in Palworld mode too, where nothing uses
   Minecraft's collision. Each ray builds a 3 KB hit table, two vector tables and a closure, then makes 7
   calls in `is_character`.
4. **Missing frames:** on 2 to 7% of presents Palworld draws the previous Minecraft picture under a new
   camera. `frames.shm` holds 3 slots; Minecraft rewrites a slot about 28 to 31 ms after filling it, and
   the path from Lua tick to composite reaches 27 to 30 ms. The counter also counts cutscene frames as
   missing. The freed tag render targets of the crash note may add to this.
5. **Entity table** (`entities.lua`): about 0.5 to 1.5 ms per tick with 50 to 100 characters.
6. **Vsync in Minecraft:** the installed `options.txt` has `enableVsync:true`. Each swap waits for a
   vblank although Minecraft's window shows nothing: up to 8.3 ms of delay per frame.
7. **Lua file IO:** about 0.1 to 0.2 ms per tick. `combat.lua:105-106` publishes an unchanged report each
   tick.
8. **Memory:** 6 PBO sets x 4 PBOs hold 199 MB at 1080p and 354 MB at 1440p; two sets at most are in
   flight.

`GpuTransport.java` is dead code: the native side never advertises GPU sharing.

## Patches in `perf-patches/`, cheapest and safest first

Apply from the repo root with `git apply`, in order. `all.patch` holds all seven.

| File | What it does | Risk |
|---|---|---|
| `01-diagnostics.patch` | Splits cutscene frames out of "missing"; logs Minecraft's copy time per frame | None: no behaviour change |
| `02-combat.patch` | Publishes the combat report only when it changes | None found |
| `03-hand.patch` | Skips the hand layer when Minecraft draws no hand (F5, asleep): one 8.3 MB layer less | Low |
| `04-rays.patch` | Caches "is this component's owner a character" per batch, reuses the vector tables: 30 to 50% less Lua time per ray | Holds component addresses for one batch. Check it against the fresh-handle rule in `HANDOFF.md` |
| `05-vsync.patch` | Vsync off while Palworld draws the frames | Changing the vsync option mid-session turns the wait back on until the next mode change |
| `06-entities.patch` | Checks far characters once per 15 tables, caches each near Pal's facts | **Caches handles across ticks: breaks the fresh-handle rule. Rework before use.** A Pal entering the radius shows up to 0.3 s late |
| `07-hud.patch` | Sends the HUD layer on every second frame when no screen is open | The HUD updates at half the frame rate. Ship the Minecraft half and the DLL together |

After 06 and 07 run `python tools/gen.py` (they add tuning rows `entity_far_tables` and
`hud_every_frames`), then rebuild the DLL and the mod.

Verified: all seven pass `git apply --check` in order; the Java compiles after 05 and after 07; the DLL
builds with no warnings after 01 and after 07; preflight passes with both rows. Nobody has run the Lua
changes.

## Larger work, by gain

- **A. GPU-shared textures** (D3D11 shared handles imported through GL `EXT_memory_object_win32`): removes
  bottlenecks 1 and 2. Days of work. A shared texture has no seqlock, so it needs a keyed mutex or one
  texture per slot.
- **B. Missing frames:** let the native side upload each new slot at Present into a ring of 3 to 4 texture
  sets keyed by pose id, or raise `FRAME_SLOTS` from 3 to 5 (+250 MB of shm, layout version bump).
- **C. Slow or stop the terrain refresh in Palworld mode.** Largest game-thread gain.
- **D. Publish at frame start** by polling the fence at the head of `runTick`: cuts about 5 to 9 ms of
  camera-to-picture delay.
- **E.** `ray_budget_ms` 4 to 2: halves the hitch, doubles terrain delay.
- **F.** PBO sets 6 to 3: frees 100 MB at 1080p.

## How to measure

- Minecraft log, "Capture pipeline" line: "copy X ms a frame for Y layers" (patch 01).
- `palcraft_native.log`, "sync:" line: Palworld fps = 600 / seconds between two sync lines.
- Rays and entities: the dev prefetch diagnostic ("last/max ms") and `tools/palmem.sh`. Compare at one
  spot, one picture size, in both modes.
