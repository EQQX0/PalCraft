-- Development console: runs Lua dropped into <runtime>/dev_in.lua on the game thread and writes the
-- result to <runtime>/dev_out.txt. Only active when <runtime>/dev_enabled exists, so players never run it.
local M = {}

local function readfile(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local s = f:read("a")
    f:close()
    return s
end

local function writefile(path, s)
    local f = io.open(path, "wb")
    if not f then return false end
    f:write(s)
    f:close()
    return true
end

-- Runs one waiting script. Game thread only.
local out = {}
local function run(runtime, src)
    out = {}
    local fn, err = load(src, "dev", "t", _G)
    if not fn then
        out[1] = "COMPILE ERROR: " .. tostring(err)
    else
        local res = table.pack(pcall(fn))
        if not res[1] then
            out[#out + 1] = "RUNTIME ERROR: " .. tostring(res[2])
        else
            for i = 2, res.n do out[#out + 1] = "=> " .. tostring(res[i]) end
        end
    end
    writefile(runtime .. "dev_out.tmp", table.concat(out, "\n") .. "\n")
    os.remove(runtime .. "dev_out.txt")
    os.rename(runtime .. "dev_out.tmp", runtime .. "dev_out.txt")
end

local dir          -- runtime folder while the console is on
local lastTick = 0 -- os.clock() of the frame loop's last visit
local frames = 0

-- Called by the frame loop. While it runs, scripts are picked up here: Lua running on UE4SS's async thread at
-- the same time as the frame hook shares one Lua state with it, and a long run of console calls crashed
-- Palworld that way (2026-10-12).
function M.tick()
    if not dir then return end
    lastTick = os.clock()
    frames = frames + 1
    if frames % 6 ~= 0 then return end
    local src = readfile(dir .. "dev_in.lua")
    if not src then return end
    os.remove(dir .. "dev_in.lua")
    run(dir, src)
end

function M.start(runtime)
    if not readfile(runtime .. "dev_enabled") then return end
    dir = runtime
    -- A script nobody collected would run at the title screen of the next start, where it has no world to
    -- ask: that crashed Palworld (2026-10-13).
    os.remove(runtime .. "dev_in.lua")
    local busy = false
    local gen = _G.PALCRAFT_GEN
    _G.P = function(...)
        local n = select("#", ...)
        local parts = {}
        for i = 1, n do parts[i] = tostring((select(i, ...))) end
        out[#out + 1] = table.concat(parts, "\t")
    end
    -- Without a world there is no frame loop (title screen): only then does the async thread look for scripts.
    LoopAsync(500, function()
        -- PALCRAFT_DEV_QUIET: a test of a world load wants nothing of the console running beside it.
        if gen ~= _G.PALCRAFT_GEN or _G.PALCRAFT_DEV_QUIET then return true end
        if busy or os.clock() - lastTick < 2 then return false end
        local src = readfile(runtime .. "dev_in.lua")
        if not src then return false end
        os.remove(runtime .. "dev_in.lua")
        busy = true
        ExecuteInGameThread(function()
            run(runtime, src)
            busy = false
        end)
        return false
    end)
    print("[PalCraft] dev console on\n")
end

return M
