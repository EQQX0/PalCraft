-- System "self_test": during a Melty test run, report which parts of the bridge came alive.
-- Melty leaves %LOCALAPPDATA%\Melty\test\<slug>.json while it watches a run; players never have it.
local P = require("gen_protocol")
local shm = require("shm")
local M = {}

local SLUG = P.listing.slug
local checksPath   -- where to append results; false = not a test run
local done = {}
local raysAnswered = false

local function find_test()
    local f = io.open((os.getenv("LOCALAPPDATA") or "") .. "\\Melty\\test\\" .. SLUG .. ".json", "rb")
    if not f then return false end
    local text = f:read("a")
    f:close()
    local path = text:match('"checks"%s*:%s*"(.-[^\\])"')
    return path and (path:gsub("\\\\", "\\"):gsub("\\/", "/")) or false
end

local function pass(name)
    if done[name] then return end
    local f = io.open(checksPath, "ab")
    if not f then return end
    f:write("pass " .. name .. "\n")
    f:close()
    done[name] = true
end

function M.tick(env)
    if checksPath == false or env.tick % 60 ~= 0 then return end
    if checksPath == nil then
        checksPath = find_test()
        if not checksPath then return end
    end
    local state = shm.get(P.off.state, P.GameState.flags)
    if state & P.state.WINDOW_VALID ~= 0 then pass("native-hooked") end
    if env.linked then pass("minecraft-linked") end
    if state & P.state.COMPOSITING ~= 0 and env.pose ~= 0 then pass("minecraft-drawn") end
    if not raysAnswered then
        local req, resp = string.unpack("<I4I4", shm.read(P.off.rays, 8))
        raysAnswered = req ~= 0 and req == resp
    end
    if raysAnswered then pass("terrain-answered") end
end

return M
