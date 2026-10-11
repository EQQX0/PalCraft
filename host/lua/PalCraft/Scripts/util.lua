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
