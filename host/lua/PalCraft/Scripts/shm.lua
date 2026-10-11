-- bridge.shm through plain file IO. Windows keeps file reads/writes and the other programs' memory maps of
-- the same file coherent, so this is the same memory the native DLL and Minecraft see.
local M = {}
local f

function M.open(runtime)
    if f then return true end
    f = io.open(runtime .. "bridge.shm", "r+b")
    if not f then return false end
    f:setvbuf("no")
    return true
end

function M.read(off, n)
    f:seek("set", off)
    return f:read(n)
end

function M.write(off, s)
    f:seek("set", off)
    f:write(s)
end

-- One field, by its row in gen_protocol ({offset, format, bytes}).
function M.get(region, d)
    f:seek("set", region + d[1])
    return string.unpack(d[2], f:read(d[3]))
end

function M.put(region, d, ...)
    f:seek("set", region + d[1])
    f:write(string.pack(d[2], ...))
end

-- A consistent copy of a seqlocked region, or nil while its writer is busy.
function M.snapshot(off, size)
    for _ = 1, 4 do
        f:seek("set", off)
        local s = f:read(size)
        if not s or #s < size then return nil end
        local s1 = string.unpack("<I4", s)
        if s1 % 2 == 0 then
            f:seek("set", off)
            if string.unpack("<I4", f:read(4)) == s1 then return s end
        end
    end
    return nil
end

function M.field(s, d)
    return string.unpack(d[2], s, d[1] + 1)
end

-- Writes a seqlocked region whose first 4 bytes are the sequence number. body = everything after it.
local seqs = {}
function M.publish(off, body)
    local s = (seqs[off] or 0) + 1
    f:seek("set", off)
    f:write(string.pack("<I4", s))
    f:seek("set", off + 4)
    f:write(body)
    f:seek("set", off)
    f:write(string.pack("<I4", s + 1))
    seqs[off] = (s + 1) % 0x7FFFFFF0
end

return M
