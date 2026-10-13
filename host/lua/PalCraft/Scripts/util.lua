-- Coordinates. The bridge speaks "host metres": left-handed, +X right, +Y up, +Z forward.
-- Unreal is centimetres, +X forward, +Y right, +Z up.
local M = {}

function M.to_ue(x, y, z) return z * 100, x * 100, y * 100 end

function M.to_host(X, Y, Z) return Y / 100, Z / 100, X / 100 end

local t0 = os.clock()
function M.now_ms() return (os.clock() - t0) * 1000 end

local runtime
function M.set_runtime(r) runtime = r end

function M.log(msg)
    print("[PalCraft] " .. msg .. "\n")
    if not runtime then return end
    local f = io.open(runtime .. "palcraft_lua.log", "ab")
    if f then
        f:write(os.date("%H:%M:%S ") .. msg .. "\n")
        f:close()
    end
end

-- UE4SS 3.0.1 takes a registry reference to every table passed as an out parameter and never gives it back,
-- so the table and everything the call wrote into it live forever. A line trace's hit result is 3 KB and
-- the terrain scan makes thousands a second: Palworld grew by 1.2 GB a minute and ran the PC out of memory
-- after 80 minutes (2026-10-12). M.release(t) gives the reference back exactly as luaL_unref would: call it
-- after every call that took t as an out parameter. t stays usable.
local REG = debug and debug.getregistry and debug.getregistry()
local FREE = 3 -- Lua 5.4.3 and later: head of luaL_ref's free list
local last
local function ref_of(t)
    if last and rawget(REG, last) == t then return last end
    local n = #REG
    for k = n, math.max(FREE + 1, n - 8), -1 do
        if rawget(REG, k) == t then return k end
    end
end
function M.release(t)
    if not REG or math.type(rawget(REG, FREE)) ~= "integer" then return end
    local k = ref_of(t)
    if not k then return end
    rawset(REG, k, rawget(REG, FREE))
    rawset(REG, FREE, k)
    last = k
end

-- Palworld frees its objects between frames, and a UE4SS handle knows nothing of that: IsValid() on the
-- handle of a freed object reads the freed memory. That crashed Palworld for players of 0.2.1 about a
-- minute into a world (2026-10-12). So no handle is kept from one tick to the next. Every tick starts from
-- the player controller Palworld hands the frame loop and follows Palworld's own properties from there: its
-- character, its HUD, the lists of PalUtility:GetPalObjectCollector.
-- NotifyOnNewObject is not used either. Asking for it while Palworld loads a world changes a list its
-- loading thread is reading, and that crashed the game five seconds into a world (2026-10-13).
--
-- Where no property leads to an object, its path is remembered instead and M.find asks for the object of
-- that path. Measured: up to 0.2 ms for an object that exists, 75 ms for one that is gone (UE4SS then looks
-- at every object Palworld has). So paths are for the few objects that outlive their use, asked rarely.
function M.path(obj)
    return (obj:GetFullName():match("^%S+%s+(.+)$"))
end

-- The live object of a remembered path, or nil.
function M.find(path)
    if not path then return nil end
    local obj = StaticFindObject(path)
    if obj and obj:IsValid() then return obj end
    return nil
end

-- Lua memory, for the self-check and the log.
function M.lua_mb() return collectgarbage("count") / 1024 end

-- Runs fn and reports an error once per distinct message, so a broken system cannot flood the log.
local seen = {}
function M.guard(name, fn, ...)
    local ok, a, b, c = pcall(fn, ...)
    if ok then return a, b, c end
    local key = name .. tostring(a)
    if not seen[key] then
        seen[key] = true
        M.log(name .. " failed: " .. tostring(a))
    end
    return nil
end

return M
