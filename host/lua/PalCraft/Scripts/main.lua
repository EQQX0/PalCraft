-- PalCraft: the Palworld side of the Minecraft passthrough.
local function script_dir()
    local src = debug.getinfo(1, "S").source or ""
    return (src:gsub("^@", ""):gsub("[^\\/]*$", ""))
end

local MOD_DIR = script_dir() .. "..\\"

-- The folder both games share. A runtime_dir.txt next to the mod overrides it (development only).
local function runtime_dir()
    local f = io.open(MOD_DIR .. "runtime_dir.txt", "rb")
    if f then
        local s = f:read("a"):gsub("[\r\n]+$", "")
        f:close()
        if #s > 0 then return s end
    end
    return (os.getenv("LOCALAPPDATA") or ".") .. "\\PalCraft\\runtime\\"
end

local function exists(path)
    local f = io.open(path, "rb")
    if f then f:close() end
    return f ~= nil
end

_G.PALCRAFT_GEN = (_G.PALCRAFT_GEN or 0) + 1
local RUNTIME = runtime_dir()
local DEV = exists(RUNTIME .. "dev_enabled")
print("[PalCraft] loading, runtime " .. RUNTIME .. "\n")

for _, name in ipairs({ "gen_protocol", "util", "shm", "camera", "standin", "life", "rays", "entities", "combat", "bridge", "dev" }) do
    package.loaded[name] = nil
end
local U = require("util")
U.set_runtime(RUNTIME)

-- The native half hooks the graphics card calls; Windows keeps it loaded across Lua reloads.
local dll = "palcraft.dll"
if DEV then
    local f = io.open(RUNTIME .. "dev_dll.txt", "rb")
    if f then
        dll = f:read("a"):gsub("%s+$", "")
        f:close()
    end
end
local ok, err = package.loadlib(MOD_DIR .. dll, "*")
U.log(ok and ("native " .. dll .. " loaded") or ("native " .. dll .. " FAILED to load: " .. tostring(err)))

local started, why = pcall(function() require("bridge").start(RUNTIME, DEV) end)
if not started then U.log("bridge failed to start: " .. tostring(why)) end

local okDev, errDev = pcall(function() require("dev").start(RUNTIME) end)
if not okDev then U.log("dev console failed: " .. tostring(errDev)) end
