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

function M.start(runtime)
    if not readfile(runtime .. "dev_enabled") then return end
    local busy = false
    local out = {}
    local gen = _G.PALCRAFT_GEN
    _G.P = function(...)
        local n = select("#", ...)
        local parts = {}
        for i = 1, n do parts[i] = tostring((select(i, ...))) end
        out[#out + 1] = table.concat(parts, "\t")
    end
    LoopAsync(150, function()
        if gen ~= _G.PALCRAFT_GEN then return true end
        if busy then return false end
        local src = readfile(runtime .. "dev_in.lua")
        if not src then return false end
        os.remove(runtime .. "dev_in.lua")
        busy = true
        ExecuteInGameThread(function()
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
            busy = false
        end)
        return false
    end)
    print("[PalCraft] dev console on\n")
end

return M
