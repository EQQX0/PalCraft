-- Systems "mc_damage" and "pal_damage": Minecraft's hits land on Pals, and what Pals do to the hidden
-- character is reported so Steve takes it.
local P = require("gen_protocol")
local U = require("util")
local shm = require("shm")
local entities = require("entities")
local body = require("body")
local M = {}

local DQ, HE = P.off.damage, P.off.hunter
local RING, DSIZE = P.const.DAMAGE_RING, P.const.DAMAGE_SIZE
local lastHp
local hits, total, status, lastDamage, lastKind = 0, 0, 0, 0, 0
local lastFrom = { 0, 0, 0 }
local lastHitTick = 0
local sent -- the report Minecraft has

-- Minecraft damage points -> Pal HP. A sword hit is about a seventh of a small Pal and a sliver of a boss
-- (the curve Minecraft Ring uses for Elden Ring enemies).
local function to_hp(amount, maxHp)
    local pool = math.max(10, math.min(300, 20 * math.sqrt(maxHp / 100)))
    return amount * maxHp / pool * P.tune.pal_damage_scale
end

-- System "kill_exp": the slip damage below has no attacker, so Palworld gives nothing for the kill. The
-- character gets experience by the Pal's level instead, through the call Palworld uses for nearby players.
local UTIL
local function reward(env, e, cp)
    local level = 1
    pcall(function() level = math.max(1, cp.IndividualParameter:GetLevel()) end)
    pcall(function()
        local mine = env.pawn.CharacterParameterComponent.IndividualParameter:GetLevel()
        level = math.min(level, mine + P.tune.kill_exp_level_lead)
    end)
    local exp = P.tune.kill_exp_base * level ^ P.tune.kill_exp_power
    if e.kind == P.ent.LARGE then exp = exp * P.tune.kill_exp_boss end
    exp = math.floor(exp + 0.5)
    UTIL = UTIL or StaticFindObject("/Script/Pal.Default__PalUtility")
    UTIL:GiveExpToAroundPlayerCharacter(env.pawn, env.pawn:K2_GetActorLocation(), 300.0, exp, true)
    env.killExp = ((env.killExp or 0) + exp) % 0x100000000
end

local function apply(env, id, amount, hx, hy, hz)
    local e = entities.find(id)
    if not e or e.kind == P.ent.OTHER or amount <= 0 then return end
    local actor = entities.actor(env, id)
    if not actor then return end
    local dr = actor.DamageReactionComponent
    if not dr or not dr:IsValid() then return end
    -- knocked away from Steve if this kills it
    local dx, dz = e.pos[1] - env.feet[1], e.pos[3] - env.feet[3]
    local n = math.max(0.01, math.sqrt(dx * dx + dz * dz))
    local vx, vy, vz = U.to_ue(dx / n * 4, 3, dz / n * 4)
    local cp = actor.CharacterParameterComponent
    local alive = cp and cp:IsValid() and not cp:IsDead()
    dr:SlipDamageAndBlowWhenDead(math.max(1, math.floor(to_hp(amount, e.maxHp) + 0.5)), { X = vx, Y = vy, Z = vz })
    if alive and cp:IsDead() then U.guard("kill_exp", reward, env, e, cp) end
end

local function drain(env)
    local w, r = string.unpack("<I4I4", shm.read(DQ, 8))
    if w == r then return end
    local n = (w - r) % 0x100000000
    if n > RING then r = (w - RING) % 0x100000000 end
    while r ~= w do
        local id, amount, hx, hy, hz = string.unpack("<I8ffff", shm.read(DQ + P.const.DAMAGE_OFF_RING + (r % RING) * DSIZE, DSIZE))
        if env.hasPawn then U.guard("damage", apply, env, id, amount, hx, hy, hz) end
        r = (r + 1) % 0x100000000
    end
    shm.put(DQ, P.DamageQueue.read, w)
end

-- The character's health is only a meter here: every loss is passed to Steve, then topped back up, so the
-- hidden character does not die of wounds Steve already took.
local function near(a, b, r)
    local dx, dy, dz = a[1] - b[1], a[2] - b[2], a[3] - b[3]
    return dx * dx + dy * dy + dz * dz <= r * r
end

local function watch_player(env)
    if not env.hasPawn or env.dead then
        lastHp = nil
        return
    end
    local cp = env.pawn.CharacterParameterComponent
    if not cp or not cp:IsValid() then return end
    local hp, maxHp = cp:GetHP().Value / 1000, cp:GetMaxHP().Value / 1000
    local carried = env.cflags & P.ctrl.MOVE_HUNTER ~= 0
    if lastHp and carried and hp < lastHp - 0.01 then
        local loss = lastHp - hp
        local who = entities.nearest_hostile(env.feet)
        if loss < maxHp * P.tune.status_hit_fraction then
            -- Poison or burn from a fight reaches Steve. With nobody near, the hidden character is hungry or
            -- cold, which the player cannot see: the top-up below is all it gets.
            if who and near(who.pos, env.feet, P.tune.status_enemy_radius_m) then status = status + loss end
        elseif who and near(who.pos, env.feet, P.tune.hit_enemy_radius_m) then
            hits, total, lastDamage, lastHitTick = hits + 1, total + loss, loss, env.tick
            lastFrom, lastKind = who.pos, who.kind
        elseif body.exposed() then
            status = status + loss -- freezing or burning: Steve sees it on his temperature gauge
        end
        -- Any other loss is Palworld's own survival at work on the hidden character: an empty stomach, a fall
        -- while it is carried. Steve has Minecraft's hunger and fall damage instead, so those stop here.
        cp:SetHP({ Value = math.floor(maxHp * 1000) })
        hp = maxHp
    end
    lastHp = hp
    -- Minecraft reads this twenty times a second and it changes with a hit: written when it does.
    local report = string.pack("<I4ffffffI8I4f", hits, total, lastDamage, lastFrom[1], lastFrom[2], lastFrom[3], maxHp,
        lastHitTick, lastKind, status)
    if report ~= sent then
        sent = report
        shm.publish(HE, report)
    end
end

function M.tick(env)
    if not env.linked then
        lastHp = nil
        return
    end
    drain(env)
    watch_player(env)
end

return M
