-- PBZWeaponSwap v2
-- 用游戏原生的主/副武器切换键驱动换武器：关闭 / 循环 / 随机 / 自定义池，F9 打开设置菜单。
-- 不改按键绑定，只在游戏调用 SetCurrentWeaponByIndex 时接管一次，然后走本模组的切换逻辑。

local SRC = debug.getinfo(1, 'S').source:gsub('^@', '')
local DIR = SRC:match('^(.*[/\\])') or ''
local ROOT = DIR:gsub('Scripts[\\/]$', '')
local LOG_PATH = ROOT .. 'log.txt'
local CFG_PATH = ROOT .. 'config.txt'
local SNAP_PATH = ROOT .. 'snapshot.txt'
local DEBUG = true

local function log(fmt, ...)
    local ok, s = pcall(string.format, fmt, ...)
    if not ok then s = tostring(fmt) end
    print("[PBZWeaponSwap] " .. s .. "\n")
    if DEBUG then
        local f = io.open(LOG_PATH, "a")
        if f then f:write(os.date("%H:%M:%S "), s, "\n"); f:close() end
    end
end

-- ── 汉字 -> 拼音（覆盖 25 把武器名用到的字）────────────────────────
local PY = {
    ["黑"] = "hei", ["伤"] = "shang", ["木"] = "mu", ["制"] = "zhi", ["双"] = "shuang",
    ["刃"] = "ren", ["残"] = "can", ["钢"] = "gang", ["长"] = "chang", ["形"] = "xing",
    ["红"] = "hong", ["妆"] = "zhuang", ["鬼"] = "gui", ["斩"] = "zhan", ["痴"] = "chi",
    ["者"] = "zhe", ["剑"] = "jian", ["亡"] = "wang", ["命"] = "ming", ["马"] = "ma",
    ["刀"] = "dao", ["白"] = "bai", ["蟒"] = "mang", ["赤"] = "chi", ["练"] = "lian",
    ["天"] = "tian", ["玄"] = "xuan", ["青"] = "qing", ["铜"] = "tong", ["妖"] = "yao",
    ["锯"] = "ju", ["乱"] = "luan", ["莺"] = "ying", ["破"] = "po", ["军"] = "jun",
    ["灵"] = "ling", ["蛇"] = "she", ["软"] = "ruan", ["山"] = "shan", ["风"] = "feng",
    ["雷"] = "lei", ["别"] = "bie", ["离"] = "li", ["钩"] = "gou", ["煞"] = "sha",
    ["钺"] = "yue", ["荡"] = "dang", ["寇"] = "kou", ["凶"] = "xiong", ["玉"] = "yu",
    ["环"] = "huan", ["影"] = "ying", ["刺"] = "ci", ["骨"] = "gu", ["混"] = "hun",
    ["沌"] = "dun", ["偃"] = "yan", ["月"] = "yue", ["断"] = "duan", ["肢"] = "zhi",
    ["圣"] = "sheng", ["母"] = "mu", ["邪"] = "xie", ["扇"] = "shan", ["紫"] = "zi",
    ["冥"] = "ming",
}

local function pinyin(name)
    local out = {}
    for _, cp in utf8.codes(name) do
        local ch = utf8.char(cp)
        out[#out + 1] = PY[ch] or ch
    end
    return table.concat(out, "")
end

local function S(v)
    if v == nil then return "nil" end
    local ok, s = pcall(function() return v:ToString() end)
    if ok and type(s) == "string" then return s end
    return tostring(v)
end

local function getSub()
    local ok, sub = pcall(FindFirstOf, "PBZBackPackSubsystem")
    if ok and sub and sub:IsValid() then return sub end
    return nil
end

-- ── 配置 ───────────────────────────────────────────────────────────
local Cfg = { mode = "cycle", customRandom = false, pool = nil }  -- pool: { [id]=true }
local poolSet = {}

local function poolIsAll()
    return Cfg.pool == nil
end

local function loadCfg()
    local f = io.open(CFG_PATH, "r")
    if not f then return end
    local poolLine = nil
    for line in f:lines() do
        line = line:gsub("\r", "")
        local k, v = line:match("^(%w+)%s*=%s*(.-)%s*$")
        if k == "mode" then
            if v == "off" or v == "cycle" or v == "random" or v == "custom" then Cfg.mode = v end
        elseif k == "random" then
            Cfg.customRandom = (v == "1" or v == "true")
        elseif k == "pool" then
            poolLine = v
        end
    end
    f:close()
    if poolLine and poolLine ~= "" then
        Cfg.pool = {}
        for id in poolLine:gmatch("[^,]+") do Cfg.pool[id] = true end
    end
    poolSet = Cfg.pool or {}
end

local function saveCfg()
    local f = io.open(CFG_PATH, "w")
    if not f then return end
    f:write("mode=", Cfg.mode, "\n")
    f:write("random=", Cfg.customRandom and "1" or "0", "\n")
    if Cfg.pool then
        local ids = {}
        for id in pairs(Cfg.pool) do ids[#ids + 1] = id end
        table.sort(ids)
        f:write("pool=", table.concat(ids, ","), "\n")
    end
    f:close()
end

-- ── 武器数据 ───────────────────────────────────────────────────────
local function equippedSlots(sub)
    local slots, order = {}, {}
    local n = 0
    local ok, cnt = pcall(function() return #sub.MainWeapons end)
    if ok and type(cnt) == "number" then n = cnt end
    for i = 1, n do
        local id = S(sub.MainWeapons[i])
        slots[id] = i - 1
        order[i] = id
    end
    return slots, order, n
end

-- 以装备栏数组为准取当前武器：CurrentMainWeaponID 在切换后常有延迟，不能用于判断
local function curIdOf(sub)
    local _, order, cnt = equippedSlots(sub)
    local idx = sub.CurrentWeaponIndex
    if type(idx) == "number" and idx >= 0 and idx < cnt and order[idx + 1] then
        return order[idx + 1], idx
    end
    return S(sub.CurrentMainWeaponID), idx
end

local sortedCache = nil
local function sortedWeapons(sub)
    if sortedCache then return sortedCache end
    local ok, arr = pcall(function() return sub:GetAllNormalWeapons() end)
    if not ok or arr == nil then return nil end
    local items = {}
    local n = #arr
    for i = 1, n do
        local okP, p = pcall(function() return arr[i] end)
        if okP and p ~= nil then
            local okG, raw = pcall(function() return p:get() end)
            local fn = okG and raw or p
            local id = S(fn)
            local disp = id
            local okT, t = pcall(function() return sub:GetMainWeaponTableData(fn) end)
            if okT and t ~= nil then
                local okW, wn = pcall(function() return t.WeaponName end)
                if okW and wn ~= nil then
                    local okV, vc = pcall(function() return wn.ValueCache end)
                    if okV and vc ~= nil then
                        local s = S(vc)
                        if s ~= "nil" and s ~= "" then disp = s end
                    end
                end
            end
            items[#items + 1] = { id = id, name = disp, key = pinyin(disp) }
        end
    end
    table.sort(items, function(a, b)
        if a.key == b.key then return a.id < b.id end
        return a.key < b.key
    end)
    local ids = {}
    for i, it in ipairs(items) do ids[i] = it.id end
    sortedCache = { ids = ids, items = items }
    return sortedCache
end

local function indexOf(list, id)
    for i = 1, #list do if list[i] == id then return i end end
    return nil
end

local function displayOf(sw, id)
    if sw then
        for _, it in ipairs(sw.items) do if it.id == id then return it.name end end
    end
    return id
end

local function clearCooldown()
    local okC, comp = pcall(FindFirstOf, "CharacterWeaponsComponent")
    if okC and comp and comp:IsValid() then
        pcall(function() comp:ResetChangeWeaponCooldowns() end)
    end
end

-- ── 应用切换（busy 期间钩子放行，避免自我拦截）────────────────────
local busy = false
local funcRefresh = nil
local function refreshUi()
    if funcRefresh then pcall(funcRefresh) end
end

local function applyTarget(sub, target, sw)
    local slots, _, cnt = equippedSlots(sub)
    local name = displayOf(sw, target)
    local curBefore, idxBefore = curIdOf(sub)
    busy = true
    local ok, err = pcall(function()
        clearCooldown()
        if slots[target] ~= nil then
            local idx = slots[target]
            if idx == idxBefore then
                log("already current: %s (%s) slot=%d", target, name, idx)
                return
            end
            sub:SetCurrentWeaponByIndex(idx, true)
            log("switch %s -> %s (%s) slot=%d", tostring(curBefore), target, name, idx)
        else
            if cnt == 0 then log("no equipped slot, abort (%s)", target); return end
            local other = 0
            if cnt > 1 then other = (idxBefore == 0) and 1 or 0 end
            sub:ReplaceWeaponByIndex(FName(target), other)
            sub:SetCurrentWeaponByIndex(other, true)
            log("equip %s (%s) into slot %d (was %s)", target, name, other, tostring(curBefore))
        end
    end)
    busy = false
    if not ok then log("ERR apply: %s", tostring(err)) end
    local afterId, afterIdx = curIdOf(sub)
    local _, order = equippedSlots(sub)
    log("state: cur=%s idx=%s slots=[%s]", tostring(afterId), tostring(afterIdx), table.concat(order, ","))
end

local function poolFor(sub, sw)
    if Cfg.mode ~= "custom" or poolIsAll() then return sw.ids end
    local out = {}
    for _, id in ipairs(sw.ids) do if poolSet[id] then out[#out + 1] = id end end
    if #out == 0 then
        log("自定义池为空，回退到全部武器")
        return sw.ids
    end
    return out
end

-- 原生切换会同时改掉 CurrentWeaponIndex，所以循环位置用本模组自己的游标，不依赖游戏当前值
local cursorId = nil

local function pickNext(sub, sw, fromId)
    local pool = poolFor(sub, sw)
    if #pool == 0 then return nil, pool end
    if Cfg.mode == "random" or (Cfg.mode == "custom" and Cfg.customRandom) then
        if #pool == 1 then return pool[1], pool end
        local cands = {}
        for _, id in ipairs(pool) do if id ~= fromId then cands[#cands + 1] = id end end
        return cands[math.random(#cands)], pool
    end
    local pos = indexOf(pool, fromId)
    if not pos then return pool[1], pool end
    return pool[(pos % #pool) + 1], pool
end

local function step()
    local sub = getSub()
    if not sub then return end
    local sw = sortedWeapons(sub)
    if not sw or #sw.ids == 0 then log("no weapons"); return end
    if cursorId == nil then cursorId = curIdOf(sub) end
    local nextId, pool = pickNext(sub, sw, cursorId)
    if not nextId then return end
    local actual = curIdOf(sub)
    if nextId == actual and pool and #pool > 1 then
        local again = pickNext(sub, sw, nextId)
        if again then nextId = again end
    end
    cursorId = nextId
    applyTarget(sub, nextId, sw)
    refreshUi()
end
-- ── 原始装备快照 ───────────────────────────────────────────────────
local function saveSnapshot(order, idx)
    local f = io.open(SNAP_PATH, "w")
    if not f then return end
    f:write(tostring(idx), "\n")
    for i = 1, #order do f:write(order[i], "\n") end
    f:close()
end

local function loadSnapshot()
    local f = io.open(SNAP_PATH, "r")
    if not f then return nil end
    local idx = tonumber(f:read("l") or "")
    local list = {}
    for line in f:lines() do
        line = line:gsub("%s+$", "")
        if line ~= "" then list[#list + 1] = line end
    end
    f:close()
    if not idx or #list == 0 then return nil end
    return idx, list
end

local function ensureSnapshot()
    local idx = loadSnapshot()
    if idx then return end
    local sub = getSub()
    if not sub then return end
    local _, order = equippedSlots(sub)
    saveSnapshot(order, sub.CurrentWeaponIndex)
    log("snapshot saved: idx=%d [%s]", sub.CurrentWeaponIndex, table.concat(order, ","))
end

local function restoreOriginal()
    local sub = getSub()
    if not sub then
        log("restore: no subsystem")
        return
    end
    local idx, list = loadSnapshot()
    if not idx then log("no snapshot"); return end
    busy = true
    local ok, err = pcall(function()
        for i = 1, #list do
            sub:ReplaceWeaponByIndex(FName(list[i]), i - 1)
        end
        sub:SetCurrentWeaponByIndex(idx, true)
    end)
    busy = false
    if ok then
        log("restored original loadout (idx=%d)", idx)
        cursorId = nil
        refreshUi()
    else
        log("ERR restore: %s", tostring(err))
    end
end

-- ── 拦截游戏原生切换：SetCurrentWeaponByIndex(index, isNormal)──────
local stats = { hits = 0 }
local idleTicks = 0 -- 距上次原生切换经过的 tick 数（空闲时才预置待切武器）

local function onSetWeaponByIndex(ctx, idxParam, isNormalParam)
    local take = false
    local ok, err = pcall(function()
        if busy then return end
        if Cfg.mode == "off" then return end
        local idx = nil
        if idxParam ~= nil then
            local okG, v = pcall(function() return idxParam:get() end)
            idx = okG and v or idxParam
        end
        local isNormal = true
        if isNormalParam ~= nil then
            local okG, v = pcall(function() return isNormalParam:get() end)
            if okG then isNormal = v and true or false end
        end
        if idx == nil or type(idx) ~= "number" then return end
        if not isNormal then return end
        if idx < 0 or idx > 7 then return end
        local sub = getSub()
        if not sub then return end
        local cur = sub.CurrentWeaponIndex
        if type(cur) ~= "number" then return end
        -- 只在“切到相邻槽位”这种原生切换调用上接管
        if math.abs(idx - cur) ~= 1 then return end
        take = true
        stats.hits = stats.hits + 1
        idleTicks = 0
        log("intercept native switch: idx=%s cur=%s (hit %d)", tostring(idx), tostring(cur), stats.hits)
        -- 原生切换无法取消：目标武器若已在待切槽就直接让原生用它（技能完整播放）；
        -- 否则才在切换瞬间补写一次（仅在未预置的边缘情况发生）。
        local ok2, e2 = pcall(function()
            local sw = sortedWeapons(sub)
            if not sw then return end
            if cursorId == nil then cursorId = curIdOf(sub) end
            local target = pickNext(sub, sw, cursorId)
            if target == nil then return end
            if target == curIdOf(sub) then
                local again = pickNext(sub, sw, target)
                if again then target = again end
            end
            local slots = equippedSlots(sub)
            if slots[target] == nil then
                busy = true
                clearCooldown()
                sub:ReplaceWeaponByIndex(FName(target), idx)
                busy = false
                log("late preload %s into slot %d (not pre-staged)", target, idx)
            else
                log("native switch uses pre-staged %s (slot %d)", target, idx)
            end
            cursorId = target
            ExecuteInGameThreadWithDelay(200, function()
                local s2 = getSub()
                if s2 then
                    local id2, i2 = curIdOf(s2)
                    log("after native: cur=%s idx=%s", tostring(id2), tostring(i2))
                end
                refreshUi()
            end)
        end)
        if not ok2 then
            busy = false
            log("ERR hook-body: %s", tostring(e2))
        end
    end)
    if not ok then log("ERR hook: %s", tostring(err)) end
    return false -- 不拦原生调用：只把目标武器放进原生要切的槽，让原生完成这次切换
end

do
    local ok, err = pcall(RegisterHook,
        '/Script/ProjectPBZ.PBZBackPackSubsystem:SetCurrentWeaponByIndex', onSetWeaponByIndex)
    log("hook SetCurrentWeaponByIndex: %s", ok and "ok" or tostring(err))
end

-- ── F9 菜单（复用 PBZTrainingDummy 同款 ModMenu 外壳）──────────────
local ui = nil
do
    local ok, mod = pcall(dofile, DIR .. 'vendor/ModMenu.lua')
    if ok and type(mod) == "table" then ui = mod else log("ModMenu load failed: %s", tostring(mod)) end
end

local MODE_LABEL = {
    off = "关闭（保留游戏原生行为）",
    cycle = "循环（全部已拥有武器，拼音顺序）",
    random = "随机（全部已拥有武器）",
    custom = "自定义（仅使用勾选的武器）",
}

local modeOptions = {
    { label = MODE_LABEL.off, value = "off" },
    { label = MODE_LABEL.cycle, value = "cycle" },
    { label = MODE_LABEL.random, value = "random" },
    { label = MODE_LABEL.custom, value = "custom" },
}

local menuBuilt = false

local function buildMenu(sub)
    if not ui or menuBuilt then return end
    local sw = sortedWeapons(sub)
    if not sw or #sw.items == 0 then return end

    ui.Init({
        title = '武器切换 Weapon Swap',
        instanceId = 'PBZWeaponSwap',
        key = Key.F9,
        keyHint = 'F9',
        dock = 'right',
        theme = 'dark',
        ignoreLook = true,
        widthFrac = 0.26,
        topFrac = 0.10,
        bottomFrac = 0.12,
    })

    local items = {
        { type = 'label', id = 'cur', label = '当前武器：—' },
        { type = 'dropdown', id = 'mode', label = '模式', options = modeOptions, default = Cfg.mode,
          onChange = function(v)
              Cfg.mode = v
              saveCfg()
              log("mode = %s", v)
              refreshUi()
          end },
        { type = 'separator' },
        { type = 'checkbox', id = 'custrand', label = '自定义池内随机顺序', default = Cfg.customRandom,
          onChange = function(on)
              Cfg.customRandom = on and true or false
              saveCfg()
              refreshUi()
          end },
        { type = 'separator' },
        { type = 'button', id = 'restore', label = '恢复原始装备（F2）', onClick = function()
            pcall(restoreOriginal)
        end },
        { type = 'label', label = '按游戏原生的主/副武器切换键即可切换。\n关闭 = 完全不干预，恢复原版手感。\n循环 = 按拼音顺序轮换全部已拥有武器。\n随机 = 每次随机换到另一把。\n自定义 = 只在勾选的武器里轮换。' },
    }

    local poolItems = {}
    for _, it in ipairs(sw.items) do
        local checked = poolIsAll() and true or (poolSet[it.id] == true)
        poolItems[#poolItems + 1] = {
            type = 'checkbox', id = 'w_' .. it.id, label = it.name .. '  ' .. it.id, default = checked,
            onChange = function(on)
                if poolIsAll() then
                    Cfg.pool = {}
                    for _, x in ipairs(sw.items) do Cfg.pool[x.id] = true end
                end
                Cfg.pool[it.id] = on and true or nil
                poolSet = Cfg.pool
                saveCfg()
                refreshUi()
            end,
        }
    end

    ui.Register({ id = 'swap', title = '武器切换', items = items, collapsible = false })
    ui.Register({ id = 'pool', title = '自定义池', items = poolItems })

    local function refresh()
        local ok, err = pcall(function()
            local sub2 = getSub()
            if not sub2 then return end
            local sw2 = sortedWeapons(sub2)
            local curId = curIdOf(sub2)
            local name = displayOf(sw2, curId)
            ui.SetLabel('swap', 'cur', string.format('当前武器：%s（%s）', name, curId))
            local pool = poolFor(sub2, sw2)
            local txt = poolIsAll() and string.format('全部 %d 把', #sw2.ids)
                or string.format('%d / %d 把', #pool, #sw2.ids)
            log("ui refresh: pool %s", txt)
        end)
        if not ok then log("ERR refresh: %s", tostring(err)) end
    end
    funcRefresh = refresh
    ui.OnOpen(refresh)
    menuBuilt = true
    log("menu built: %d weapons", #sw.items)
end

-- 轮询等子系统就绪后建菜单（不要在 mod 加载时做反射）
local function tick()
    local ok, err = pcall(function()
        local sub = getSub()
        if sub then
            ensureSnapshot()
            if not menuBuilt then buildMenu(sub) end
        end
    end)
    if not ok then log("tick: %s", tostring(err)) end
    return false
end
pcall(function() LoopInGameThreadWithDelay(1500, tick) end)

-- ── 备用热键 ───────────────────────────────────────────────────────
pcall(function()
    RegisterKeyBind(Key.F2, {}, function()
        pcall(function() ExecuteInGameThread(restoreOriginal) end)
    end)
end)

-- 空闲预置：把“下一把目标武器”提前放进待切槽，按键时原生直接切出它，技能不会被截断
local function stageNextWeapon()
    local sub = getSub()
    if not sub then return end
    local sw = sortedWeapons(sub)
    if not sw or #sw.ids == 0 then return end
    local curId, curIdx = curIdOf(sub)
    if cursorId == nil then cursorId = curId end
    local nxt = pickNext(sub, sw, cursorId)
    if nxt == nil then return end
    local slots = equippedSlots(sub)
    if slots[nxt] ~= nil then return end
    local other = (curIdx == 0) and 1 or 0
    busy = true
    local ok, err = pcall(function() sub:ReplaceWeaponByIndex(FName(nxt), other) end)
    busy = false
    if ok then
        log("stage %s -> slot %d (off-hand)", nxt, other)
    else
        log("ERR stage: %s", tostring(err))
    end
    refreshUi()
end

-- 只在“没在换武器过场”时清冷却 + 预置，避免打断原生换武器技能
local function idleTicker()
    local ok = pcall(function()
        if Cfg.mode == "off" then idleTicks = 0; return end
        local comp = FindFirstOf("CharacterWeaponsComponent")
        if comp then
            local okT, v = pcall(function() return comp:IsInWeaponTransition() end)
            if okT and v then idleTicks = 0; return end
        end
        idleTicks = idleTicks + 1
        if idleTicks < 3 then return end
        idleTicks = 3
        clearCooldown()
        stageNextWeapon()
    end)
    if not ok then return false end
    return false
end
pcall(function() LoopInGameThreadWithDelay(500, idleTicker) end)

pcall(function()
    RegisterLoadMapPostHook(function()
        sortedCache = nil
        cursorId = nil
    end)
end)

loadCfg()
log("loaded: native-key takeover, F9 menu, F2 restore; mode=%s", Cfg.mode)

return { step = step, restore = restoreOriginal, cfg = Cfg }
