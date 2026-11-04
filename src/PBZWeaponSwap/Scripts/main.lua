-- PBZWeaponSwap v3.1.0
-- 用游戏原生的换武器键驱动两套武器：
--   主武器   键盘 1 / 手柄十字键左   -> SetCurrentWeaponByIndex(idx, true)
--   影之武装 键盘 2 / 手柄十字键右   -> SetCurrentWeaponByIndex(idx, false)
-- 每套各自有 关闭 / 循环 / 随机 / 自定义池 四种模式，F9 打开菜单，首行选择要配置哪一套。

local SRC = debug.getinfo(1, 'S').source:gsub('^@', '')
local DIR = SRC:match('^(.*[/\\])') or ''
local ROOT = DIR:gsub('Scripts[\\/]$', '')
local LOG_PATH = ROOT .. 'log.txt'
local CFG_PATH = ROOT .. 'config.txt'
local SNAP_PATH = ROOT .. 'snapshot.txt'
local DEBUG = true
local VERSION = "3.1.0"

local function log(fmt, ...)
    local ok, s = pcall(string.format, fmt, ...)
    if not ok then s = tostring(fmt) end
    print("[PBZWeaponSwap] " .. s .. "\n")
    if DEBUG then
        local f = io.open(LOG_PATH, "a")
        if f then f:write(os.date("%H:%M:%S "), s, "\n"); f:close() end
    end
end

-- ── 汉字 -> 拼音（覆盖武器名用到的字）──────────────────────────────
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
    ["冥"] = "ming", ["勾"] = "gou", ["爪"] = "zhua", ["锤"] = "chui", ["枪"] = "qiang",
    ["炮"] = "pao", ["弩"] = "nu", ["弓"] = "gong", ["镖"] = "biao", ["轮"] = "lun",
    -- 影之武装用到的字
    ["柄"] = "bing", ["金"] = "jin", ["瓜"] = "gua", ["客"] = "ke", ["召"] = "zhao",
    ["集"] = "ji", ["令"] = "ling", ["霆"] = "ting", ["催"] = "cui", ["心"] = "xin",
    ["琵"] = "pi", ["琶"] = "pa", ["墨"] = "mo", ["血"] = "xue", ["无"] = "wu",
    ["痕"] = "hen", ["妙"] = "miao", ["手"] = "shou", ["飞"] = "fei", ["巨"] = "ju",
    ["斧"] = "fu", ["拙"] = "zhuo", ["壁"] = "bi", ["盾"] = "dun", ["操"] = "cao",
    ["偶"] = "ou", ["铃"] = "ling", ["铛"] = "dang", ["泥"] = "ni", ["头"] = "tou",
    ["车"] = "che", ["游"] = "you", ["龙"] = "long", ["叉"] = "cha", ["火"] = "huo",
    ["流"] = "liu", ["星"] = "xing", ["烈"] = "lie", ["焰"] = "yan", ["狮"] = "shi",
    ["独"] = "du", ["眼"] = "yan", ["羽"] = "yu", ["苦"] = "ku", ["叶"] = "ye",
    ["寺"] = "si", ["珠"] = "zhu", ["串"] = "chuan", ["虎"] = "hu", ["虚"] = "xu",
    ["空"] = "kong", ["华"] = "hua", ["滴"] = "di", ["子"] = "zi", ["贪"] = "tan",
    ["狼"] = "lang", ["追"] = "zhui", ["锁"] = "suo", ["镰"] = "lian", ["铁"] = "tie",
    ["拳"] = "quan", ["套"] = "tao", ["黄"] = "huang", ["铳"] = "chong", ["柄"] = "bing",
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

-- ── 两套武器的访问器 ──────────────────────────────────────────────
local T = {
    main = {
        key = "main",
        label = "主武器",
        hotkey = "键盘 1 / 手柄十字键左",
        isNormal = true,
        arr = function(sub) return sub.MainWeapons end,
        curIdx = function(sub) return sub.CurrentWeaponIndex end,
        curId = function(sub) return sub.CurrentMainWeaponID end,
        replace = function(sub, id, slot) sub:ReplaceWeaponByIndex(FName(id), slot) end,
        setCur = function(sub, idx) sub:SetCurrentWeaponByIndex(idx, true) end,
        tbl = function(sub, fn) return sub:GetMainWeaponTableData(fn) end,
        all = function(sub) return sub:GetAllNormalWeapons() end,
    },
    shaqi = {
        key = "shaqi",
        label = "影之武装",
        hotkey = "键盘 2 / 手柄十字键右",
        isNormal = false,
        arr = function(sub) return sub.ShaqiWeapons end,
        curIdx = function(sub) return sub.CurrentShaqiWeaponIndex end,
        curId = function(sub) return nil end,
        replace = function(sub, id, slot) sub:ReplaceShaqiWeaponByIndex(FName(id), slot) end,
        setCur = function(sub, idx) sub:SetCurrentWeaponByIndex(idx, false) end,
        tbl = function(sub, fn) return sub:GetShaqiWeaponTableData(fn) end,
        all = function(sub) return sub:GetAllShaqiWeapons() end,
    },
}
local KINDS = { "main", "shaqi" }

-- ── 配置 ─────────────────────────────────────────────────────────
-- Cfg[kind] = { mode = "off"|"cycle"|"random"|"custom", customRandom = bool, pool = { [id]=true } | nil }
local Cfg = {
    target = "main", -- F9 菜单首行选择：正在配置哪一套
    lang = "auto",   -- auto = 跟随游戏语言；也可写 zh / en
    main = { mode = "cycle", customRandom = false, pool = nil },
    shaqi = { mode = "cycle", customRandom = false, pool = nil },
}

-- ── 语言：默认跟随游戏语言，config.txt 里 lang=zh/en 可强制 ──────────
local LANG = "zh"

local function gameCulture()
    local ok, lib = pcall(function()
        return StaticFindObject('/Script/Engine.Default__KismetInternationalizationLibrary')
    end)
    if not (ok and lib) then
        local ok2, lib2 = pcall(FindFirstOf, "KismetInternationalizationLibrary")
        lib = (ok2 and lib2) or nil
    end
    if not lib then return nil end
    local ok3, v = pcall(function() return lib:GetCurrentLanguage() end)
    if not ok3 or v == nil then return nil end
    if type(v) == "string" then return v end
    local ok4, s = pcall(function() return v:ToString() end)
    if ok4 and type(s) == "string" then return s end
    return nil
end

local function resolveLang()
    if Cfg.lang == "zh" or Cfg.lang == "en" then
        LANG = Cfg.lang
        return
    end
    local cult = gameCulture()
    if cult and cult ~= "" and cult ~= "nil" then
        local c = string.lower(cult)
        LANG = (string.find(c, "zh", 1, true) or string.find(c, "chinese", 1, true)) and "zh" or "en"
        log("game language: %s -> UI %s", cult, LANG)
    else
        LANG = "zh"
        log("game language: not detected -> UI zh (config.txt: lang=zh|en to force)")
    end
end

local function L(zh, en)
    if LANG == "en" then return en end
    return zh
end

local function poolIsAll(kind)
    return Cfg[kind].pool == nil
end

local function normMode(v)
    if v == "off" or v == "cycle" or v == "random" or v == "custom" then return v end
    return nil
end

local function loadCfg()
    local f = io.open(CFG_PATH, "r")
    if not f then return end
    local lines = {}
    for line in f:lines() do
        line = line:gsub("\r", "")
        local k, v = line:match("^([%w_%.]+)%s*=%s*(.-)%s*$")
        if k then lines[#lines + 1] = { k = k, v = v } end
    end
    f:close()
    for _, kv in ipairs(lines) do
        local k, v = kv.k, kv.v
        if k == "lang" then
            if v == "auto" or v == "zh" or v == "en" then Cfg.lang = v end
        elseif k == "target" then
            if v == "main" or v == "shaqi" then Cfg.target = v end
        elseif k == "mode" or k == "random" or k == "pool" then
            -- v2 旧格式：只有一套主武器
            if k == "mode" then
                local m = normMode(v); if m then Cfg.main.mode = m end
            elseif k == "random" then
                Cfg.main.customRandom = (v == "1" or v == "true")
            else
                local pool = {}
                for id in v:gmatch("[^,]+") do pool[id] = true end
                if next(pool) then Cfg.main.pool = pool end
            end
        else
            local kind, field = k:match("^(%a+)%.(%a+)$")
            if kind and Cfg[kind] then
                if field == "mode" then
                    local m = normMode(v); if m then Cfg[kind].mode = m end
                elseif field == "random" then
                    Cfg[kind].customRandom = (v == "1" or v == "true")
                elseif field == "pool" then
                    local pool = {}
                    for id in v:gmatch("[^,]+") do pool[id] = true end
                    Cfg[kind].pool = (next(pool) ~= nil) and pool or nil
                end
            end
        end
    end
end

local function saveCfg()
    local f = io.open(CFG_PATH, "w")
    if not f then return end
    f:write("version=", VERSION, "\n")
    f:write("lang=", Cfg.lang, "\n")
    f:write("target=", Cfg.target, "\n")
    for _, kind in ipairs(KINDS) do
        local c = Cfg[kind]
        f:write(kind, ".mode=", c.mode, "\n")
        f:write(kind, ".random=", c.customRandom and "1" or "0", "\n")
        if c.pool then
            local ids = {}
            for id in pairs(c.pool) do ids[#ids + 1] = id end
            table.sort(ids)
            f:write(kind, ".pool=", table.concat(ids, ","), "\n")
        end
    end
    f:close()
end

-- ── 武器数据 ─────────────────────────────────────────────────────
local function equippedSlots(sub, kind)
    local def = T[kind]
    local slots, order = {}, {}
    local n = 0
    local okA, arr = pcall(def.arr, sub)
    if okA and arr then
        local ok, cnt = pcall(function() return #arr end)
        if ok and type(cnt) == "number" then n = cnt end
        for i = 1, n do
            local id = S(arr[i])
            slots[id] = i - 1
            order[i] = id
        end
    end
    return slots, order, n
end

-- 以装备栏数组为准取当前武器：CurrentMainWeaponID 在切换后常有延迟，不能用于判断
local function curOf(sub, kind)
    local def = T[kind]
    local _, order, cnt = equippedSlots(sub, kind)
    local okI, idx = pcall(def.curIdx, sub)
    if okI and type(idx) == "number" and idx >= 0 and idx < cnt and order[idx + 1] then
        return order[idx + 1], idx
    end
    local okD, id = pcall(def.curId, sub)
    return okD and S(id) or nil, idx
end

local cache = { main = nil, shaqi = nil }

local function sortedWeapons(sub, kind)
    if cache[kind] then return cache[kind] end
    local def = T[kind]
    local ok, arr = pcall(def.all, sub)
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
            local okT, t = pcall(def.tbl, sub, fn)
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
    cache[kind] = { ids = ids, items = items }
    return cache[kind]
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

local function applyTarget(sub, kind, target, sw)
    local def = T[kind]
    local slots, _, cnt = equippedSlots(sub, kind)
    local name = displayOf(sw, target)
    local curBefore, idxBefore = curOf(sub, kind)
    busy = true
    local ok, err = pcall(function()
        clearCooldown()
        if slots[target] ~= nil then
            local idx = slots[target]
            if idx == idxBefore then
                log("[%s] already current: %s (%s) slot=%d", kind, target, name, idx)
                return
            end
            def.setCur(sub, idx)
            log("[%s] switch %s -> %s (%s) slot=%d", kind, tostring(curBefore), target, name, idx)
        else
            if cnt == 0 then log("[%s] no equipped slot, abort (%s)", kind, target); return end
            local other = 0
            if cnt > 1 then other = (idxBefore == 0) and 1 or 0 end
            def.replace(sub, target, other)
            def.setCur(sub, other)
            log("[%s] equip %s (%s) into slot %d (was %s)", kind, target, name, other, tostring(curBefore))
        end
    end)
    busy = false
    if not ok then log("ERR apply[%s]: %s", kind, tostring(err)) end
    local afterId, afterIdx = curOf(sub, kind)
    local _, order = equippedSlots(sub, kind)
    log("[%s] state: cur=%s idx=%s slots=[%s]", kind, tostring(afterId), tostring(afterIdx), table.concat(order, ","))
end

local function poolFor(kind, sw)
    local c = Cfg[kind]
    if c.mode ~= "custom" or poolIsAll(kind) then return sw.ids end
    local out = {}
    for _, id in ipairs(sw.ids) do if c.pool[id] then out[#out + 1] = id end end
    if #out == 0 then
        log("[%s] 自定义池为空，回退到全部武器", kind)
        return sw.ids
    end
    return out
end

-- 原生切换会同时改掉当前索引，所以循环位置用本模组自己的游标，不依赖游戏当前值
local cursors = { main = nil, shaqi = nil }
-- 已经预置到待切槽、但玩家还没按键的武器：避免随机模式下每个 tick 都换一把塞进去
local pending = { main = nil, shaqi = nil }

local function pickNext(kind, sw, fromId)
    local c = Cfg[kind]
    local pool = poolFor(kind, sw)
    if #pool == 0 then return nil, pool end
    if c.mode == "random" or (c.mode == "custom" and c.customRandom) then
        if #pool == 1 then return pool[1], pool end
        local cands = {}
        for _, id in ipairs(pool) do if id ~= fromId then cands[#cands + 1] = id end end
        return cands[math.random(#cands)], pool
    end
    local pos = indexOf(pool, fromId)
    if not pos then return pool[1], pool end
    return pool[(pos % #pool) + 1], pool
end

local function step(kind)
    kind = kind or Cfg.target
    local sub = getSub()
    if not sub then return end
    local sw = sortedWeapons(sub, kind)
    if not sw or #sw.ids == 0 then log("[%s] no weapons", kind); return end
    if cursors[kind] == nil then cursors[kind] = curOf(sub, kind) end
    local nextId, pool = pickNext(kind, sw, cursors[kind])
    if not nextId then return end
    local actual = curOf(sub, kind)
    if nextId == actual and pool and #pool > 1 then
        local again = pickNext(kind, sw, nextId)
        if again then nextId = again end
    end
    cursors[kind] = nextId
    applyTarget(sub, kind, nextId, sw)
    refreshUi()
end

-- ── 原始装备快照（主武器 + 影之武装）──────────────────────────────
local function saveSnapshot()
    local sub = getSub()
    if not sub then return end
    local f = io.open(SNAP_PATH, "w")
    if not f then return end
    f:write("v2\n")
    for _, kind in ipairs(KINDS) do
        local slots, order, cnt = equippedSlots(sub, kind)
        if cnt > 0 then
            local _, idx = curOf(sub, kind)
            f:write(kind, " ", tostring(idx or 0), " ", tostring(cnt), "\n")
            for i = 1, cnt do f:write(order[i], "\n") end
        end
    end
    f:close()
    for _, kind in ipairs(KINDS) do
        local slots, order = equippedSlots(sub, kind)
        log("snapshot[%s] slots=[%s]", kind, table.concat(order, ","))
    end
end

local function loadSnapshot()
    local f = io.open(SNAP_PATH, "r")
    if not f then return nil end
    local lines = {}
    for line in f:lines() do
        line = line:gsub("\r", ""):gsub("%s+$", "")
        if line ~= "" then lines[#lines + 1] = line end
    end
    f:close()
    if #lines == 0 then return nil end
    if lines[1] == "v2" then
        local out = {}
        local i = 2
        while i <= #lines do
            local kind, idx, cnt = lines[i]:match("^(%a+)%s+(%-?%d+)%s+(%d+)$")
            if not kind or not T[kind] then break end
            idx = tonumber(idx) or 0
            cnt = tonumber(cnt) or 0
            local list = {}
            for j = 1, cnt do list[j] = lines[i + j] end
            out[kind] = { idx = idx, list = list }
            i = i + cnt + 1
        end
        if not next(out) then return nil end
        return out
    end
    -- v2 旧格式：第一行索引，其余为主武器 ID
    local idx = tonumber(lines[1])
    if not idx then return nil end
    local list = {}
    for i = 2, #lines do list[#list + 1] = lines[i] end
    if #list == 0 then return nil end
    return { main = { idx = idx, list = list } }
end

local function ensureSnapshot()
    if loadSnapshot() then return end
    saveSnapshot()
end

local function restoreOriginal()
    local sub = getSub()
    if not sub then
        log("restore: no subsystem")
        return
    end
    local snap = loadSnapshot()
    if not snap then log("no snapshot"); return end
    busy = true
    local ok, err = pcall(function()
        for _, kind in ipairs(KINDS) do
            local s = snap[kind]
            if s and #s.list > 0 then
                for i = 1, #s.list do
                    T[kind].replace(sub, s.list[i], i - 1)
                end
                T[kind].setCur(sub, s.idx)
                log("restored %s: idx=%d [%s]", kind, s.idx, table.concat(s.list, ","))
            end
        end
    end)
    busy = false
    if ok then
        cursors.main = nil
        cursors.shaqi = nil
        refreshUi()
    else
        log("ERR restore: %s", tostring(err))
    end
end

-- ── 拦截游戏原生切换：SetCurrentWeaponByIndex(index, isNormal)──────
local stats = { hits = 0, hits_shaqi = 0 }
local idleTicks = 0 -- 距上次原生切换经过的 tick 数（空闲时才预置待切武器）

local function readParam(p, default)
    if p == nil then return default end
    local okG, v = pcall(function() return p:get() end)
    if okG then return v end
    return p
end

local function onSetWeaponByIndex(ctx, idxParam, isNormalParam)
    local ok, err = pcall(function()
        if busy then return end
        local idx = readParam(idxParam, nil)
        if idx == nil or type(idx) ~= "number" then return end
        local isNormal = readParam(isNormalParam, true)
        local kind = (isNormal == false) and "shaqi" or "main"
        local c = Cfg[kind]
        if c.mode == "off" then return end
        if idx < 0 or idx > 7 then return end
        local sub = getSub()
        if not sub then return end
        local cur = select(2, curOf(sub, kind))
        if type(cur) ~= "number" then return end
        -- 只在“切到相邻槽位”这种原生切换调用上接管
        if math.abs(idx - cur) ~= 1 then return end
        stats.hits = stats.hits + 1
        if kind == "shaqi" then stats.hits_shaqi = stats.hits_shaqi + 1 end
        idleTicks = 0
        log("intercept[%s] native switch: idx=%s cur=%s (hit %d, shaqi %d)",
            kind, tostring(idx), tostring(cur), stats.hits, stats.hits_shaqi)
        -- 原生切换无法取消：目标武器若已在待切槽就直接让原生用它（技能完整播放）；
        -- 否则才在切换瞬间补写一次（仅在未预置的边缘情况发生）。
        local ok2, e2 = pcall(function()
            local sw = sortedWeapons(sub, kind)
            if not sw then return end
            local slots = equippedSlots(sub, kind)
            local curId = curOf(sub, kind)
            if cursors[kind] == nil then cursors[kind] = curId end
            -- 优先用已经预置到待切槽的那把：随机模式下“这一把”就是玩家该拿到的结果
            local target = pending[kind]
            if target ~= nil and (target == curId or slots[target] == nil) then target = nil end
            if target == nil then
                target = pickNext(kind, sw, cursors[kind])
                if target ~= nil and target == curId then
                    local again = pickNext(kind, sw, target)
                    if again then target = again end
                end
            end
            if target == nil then return end
            if slots[target] == nil then
                busy = true
                clearCooldown()
                T[kind].replace(sub, target, idx)
                busy = false
                log("late preload[%s] %s into slot %d (not pre-staged)", kind, target, idx)
            else
                log("native switch[%s] uses pre-staged %s (slot %d)", kind, target, idx)
            end
            pending[kind] = nil
            cursors[kind] = target
            ExecuteInGameThreadWithDelay(200, function()
                local s2 = getSub()
                if s2 then
                    local id2, i2 = curOf(s2, kind)
                    log("after native[%s]: cur=%s idx=%s", kind, tostring(id2), tostring(i2))
                end
                refreshUi()
            end)
        end)
        if not ok2 then
            busy = false
            log("ERR hook-body[%s]: %s", kind, tostring(e2))
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

local function labelOf(kind)
    if kind == "shaqi" then return L("影之武装", "Shaqi weapon") end
    return L("主武器", "Main weapon")
end

local function hotkeyOf(kind)
    if kind == "shaqi" then return L("键盘 2 / 手柄十字键右", "keyboard 2 / D-pad Right") end
    return L("键盘 1 / 手柄十字键左", "keyboard 1 / D-pad Left")
end

local function modeName(m)
    if m == "off" then return L("关闭", "Off") end
    if m == "cycle" then return L("循环", "Cycle") end
    if m == "random" then return L("随机", "Random") end
    return L("自定义", "Custom")
end

local function modeOptions()
    return {
        { label = L("关闭（保留游戏原生行为）", "Off (vanilla behaviour)"), value = "off" },
        { label = L("循环（按拼音顺序轮换）", "Cycle (pinyin order)"), value = "cycle" },
        { label = L("随机（每次换到另一把）", "Random (a different weapon each time)"), value = "random" },
        { label = L("自定义（仅使用勾选的武器）", "Custom (only ticked weapons)"), value = "custom" },
    }
end

local function targetOptions()
    return {
        { label = L("主武器（键盘 1 / 十字键左）", "Main weapon (1 / D-pad Left)"), value = "main" },
        { label = L("影之武装（键盘 2 / 十字键右）", "Shaqi weapon (2 / D-pad Right)"), value = "shaqi" },
    }
end

local function langOptions()
    return {
        { label = L("自动（跟随游戏语言）", "Auto (follow game language)"), value = "auto" },
        { label = L("中文", "Chinese"), value = "zh" },
        { label = "English", value = "en" },
    }
end

local menuBuilt = false
local funcRefreshWeapons = nil
local registerSections = nil

local function poolItemsFor(sub, kind)
    local sw = sortedWeapons(sub, kind)
    local items = {}
    if not sw then return items end
    local c = Cfg[kind]
    for _, it in ipairs(sw.items) do
        local checked = (c.pool == nil) and true or (c.pool[it.id] == true)
        items[#items + 1] = {
            type = 'checkbox',
            id = kind .. '_' .. it.id,
            label = it.name .. '  ' .. it.id,
            default = checked,
            onChange = function(on)
                local cc = Cfg[kind]
                if cc.pool == nil then
                    cc.pool = {}
                    for _, x in ipairs(sw.items) do cc.pool[x.id] = true end
                end
                cc.pool[it.id] = on and true or nil
                saveCfg()
                refreshUi()
            end,
        }
    end
    return items
end

local function swapItems()
    local c = Cfg[Cfg.target]
    return {
        -- 状态区：目标一行，两套武器各一行（原来是挤在一行里的）
        { type = 'label', id = 'curTarget', label = L("当前目标：—", "Editing: —") },
        { type = 'label', id = 'curMain', label = L("主武器：—", "Main weapon: —") },
        { type = 'label', id = 'curShaqi', label = L("影之武装：—", "Shaqi weapon: —") },
        { type = 'label', id = 'poolInfo', label = L("池：—", "Pool: —") },
        { type = 'separator' },
        { type = 'dropdown', id = 'target', label = L("配置对象", "Configure"), options = targetOptions(), default = Cfg.target,
          onChange = function(v)
              if v ~= "main" and v ~= "shaqi" then return end
              Cfg.target = v
              saveCfg()
              if ui then
                  local cc = Cfg[v]
                  pcall(function() ui.Set('swap', 'mode', cc.mode) end)
                  pcall(function() ui.Set('swap', 'custrand', cc.customRandom) end)
                  pcall(function()
                      ui.Register({ id = 'pool', title = L('自定义池 · ', 'Custom pool · ') .. labelOf(v),
                          items = poolItemsFor(getSub(), v) })
                  end)
              end
              log("menu target = %s", v)
              refreshUi()
          end },
        { type = 'dropdown', id = 'mode', label = L("切换模式", "Mode"), options = modeOptions(), default = c.mode,
          onChange = function(v)
              local kind = Cfg.target
              local m = normMode(v)
              if not m then return end
              Cfg[kind].mode = m
              saveCfg()
              log("[%s] mode = %s", kind, m)
              refreshUi()
          end },
        { type = 'checkbox', id = 'custrand', label = L("自定义池内随机顺序", "Random order inside custom pool"), default = c.customRandom,
          onChange = function(on)
              local kind = Cfg.target
              Cfg[kind].customRandom = on and true or false
              saveCfg()
              log("[%s] customRandom = %s", kind, tostring(on))
              refreshUi()
          end },
        { type = 'separator' },
        { type = 'button', id = 'refresh', label = L("刷新武器列表（加入新获得的武器）", "Refresh weapon list (pick up newly acquired)"), onClick = function()
            if funcRefreshWeapons then pcall(funcRefreshWeapons, true) end
        end },
        { type = 'button', id = 'restore', label = L("恢复原始装备（F2）", "Restore original loadout (F2)"), onClick = function()
            pcall(restoreOriginal)
        end },
        { type = 'separator' },
        { type = 'dropdown', id = 'lang', label = L("界面语言", "UI language"), options = langOptions(), default = Cfg.lang,
          onChange = function(v)
              if v ~= "auto" and v ~= "zh" and v ~= "en" then return end
              Cfg.lang = v
              saveCfg()
              resolveLang()
              log("menu lang = %s -> %s", v, LANG)
              local sub = getSub()
              if ui and sub and registerSections then pcall(registerSections, sub) end
              refreshUi()
          end },
        -- 说明区：两套武器各占一行
        { type = 'label', label = L("主武器：键盘 1 / 手柄十字键左", "Main weapon: keyboard 1 / D-pad Left") },
        { type = 'label', label = L("影之武装：键盘 2 / 手柄十字键右", "Shaqi weapon: keyboard 2 / D-pad Right") },
        { type = 'label', label = L("关闭：完全不干预，保持游戏原生行为。",
                                     "Off: no interference, vanilla behaviour.") },
        { type = 'label', label = L("循环：按中文名拼音顺序轮换，走完池里所有武器再回到第一把。",
                                     "Cycle: rotate in pinyin order through the whole pool, then wrap around.") },
        { type = 'label', label = L("随机：每次换到池里另一把，不会连续两次拿到同一把。",
                                     "Random: a different weapon from the pool each time, never the same twice in a row.") },
        { type = 'label', label = L("自定义：只在勾选的武器里按上面的顺序 / 随机规则切换。",
                                     "Custom: only the ticked weapons are used, with the rule above.") },
        { type = 'label', label = L("版本 v", "version v") .. VERSION },
    }
end

registerSections = function(sub)
    if not ui then return end
    ui.Register({ id = 'swap', title = L('武器切换', 'Weapon Swap'), items = swapItems(), collapsible = false })
    ui.Register({ id = 'pool', title = L('自定义池 · ', 'Custom pool · ') .. labelOf(Cfg.target),
        items = poolItemsFor(sub, Cfg.target) })
end

local function setStatusLabels()
    local sub = getSub()
    if not sub or not ui then return end
    pcall(function() ui.SetLabel('swap', 'curTarget', L('当前目标：', 'Editing: ') .. labelOf(Cfg.target)) end)
    for _, kind in ipairs(KINDS) do
        local sw = sortedWeapons(sub, kind)
        local id = curOf(sub, kind)
        local name = displayOf(sw, id) or '—'
        local txt = labelOf(kind) .. L('：', ': ') .. name .. '  ' .. L('（', '(') .. modeName(Cfg[kind].mode) .. L('）', ')')
        local itemId = (kind == 'main') and 'curMain' or 'curShaqi'
        pcall(function() ui.SetLabel('swap', itemId, txt) end)
    end
    local swNow = sortedWeapons(sub, Cfg.target)
    if swNow then
        local pool = poolFor(Cfg.target, swNow)
        local txt
        if Cfg[Cfg.target].pool == nil then
            txt = L(string.format('全部 %d 把', #swNow.ids), string.format('all %d weapons', #swNow.ids))
        else
            txt = L(string.format('%d / %d 把', #pool, #swNow.ids), string.format('%d / %d weapons', #pool, #swNow.ids))
        end
        pcall(function() ui.SetLabel('swap', 'poolInfo', L('池：', 'Pool: ') .. txt) end)
    end
end

local function weaponCount(sub, kind)
    local ok, arr = pcall(T[kind].all, sub)
    if not (ok and arr) then return 0 end
    local ok2, n = pcall(function() return #arr end)
    if ok2 and type(n) == "number" then return n end
    return 0
end

-- 池里可能新增（新获得武器）或消失（换档/读档），据此判断要不要重建列表
local function listChanged(sub)
    for _, kind in ipairs(KINDS) do
        local n = weaponCount(sub, kind)
        local c = cache[kind]
        if n > 0 and (not c or #c.ids ~= n) then return true end
    end
    return false
end

local function refreshWeapons(force)
    local sub = getSub()
    if not sub then return end
    if force or listChanged(sub) then
        cache.main = nil
        cache.shaqi = nil
        pending.main = nil
        pending.shaqi = nil
        for _, kind in ipairs(KINDS) do
            local sw = sortedWeapons(sub, kind)
            local c = Cfg[kind]
            if sw and c.pool then
                for id in pairs(c.pool) do
                    if not indexOf(sw.ids, id) then c.pool[id] = nil end
                end
                if not next(c.pool) then c.pool = nil end
                saveCfg()
            end
        end
    end
    resolveLang()
    if ui then pcall(registerSections, sub) end
    setStatusLabels()
    local m = sortedWeapons(sub, 'main')
    local s = sortedWeapons(sub, 'shaqi')
    log('refresh: main %d / shaqi %d (forced=%s)', (m and #m.ids) or 0, (s and #s.ids) or 0, tostring(force == true))
end
funcRefreshWeapons = refreshWeapons

local function buildMenu(sub)
    if not ui or menuBuilt then return end
    local swMain = sortedWeapons(sub, "main")
    if not swMain or #swMain.items == 0 then return end
    resolveLang()

    ui.Init({
        title = L('武器切换 Weapon Swap', 'Weapon Swap'),
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

    registerSections(sub)
    setStatusLabels()

    local function refresh()
        local ok, err = pcall(function()
            local sub2 = getSub()
            if not sub2 then return end
            if listChanged(sub2) then pcall(refreshWeapons, false) end
            setStatusLabels()
        end)
        if not ok then log("ERR refresh: %s", tostring(err)) end
    end
    funcRefresh = refresh
    ui.OnOpen(refresh)
    menuBuilt = true
    local swShaqi = sortedWeapons(sub, "shaqi")
    log("menu built v%s: main %d / shaqi %d", VERSION, #swMain.items, (swShaqi and #swShaqi.items) or 0)
    for _, kind in ipairs(KINDS) do
        local sw = sortedWeapons(sub, kind)
        if sw then
            for i, it in ipairs(sw.items) do
                log("order[%s] %2d. %s  key=%s  id=%s", kind, i, it.name, it.key, it.id)
            end
        end
    end
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
local function stageNextWeapon(kind)
    local c = Cfg[kind]
    if c.mode == "off" then return end
    local sub = getSub()
    if not sub then return end
    local sw = sortedWeapons(sub, kind)
    if not sw or #sw.ids == 0 then return end
    local slots, _, cnt = equippedSlots(sub, kind)
    if cnt < 2 then return end
    local curId, curIdx = curOf(sub, kind)
    if cursors[kind] == nil then cursors[kind] = curId end
    -- 上一把预置的武器已经拿到手上、或被别的操作挤掉，就作废这个标记
    if pending[kind] then
        if pending[kind] == curId or slots[pending[kind]] == nil then
            pending[kind] = nil
        end
    end
    if pending[kind] then return end -- 待切槽里已有武器，等玩家按键
    local nxt = pickNext(kind, sw, cursors[kind])
    if nxt == nil then return end
    if slots[nxt] ~= nil then
        pending[kind] = nxt
        return
    end
    local other = (curIdx == 0) and 1 or 0
    if other >= cnt then other = 0 end
    busy = true
    local ok, err = pcall(T[kind].replace, sub, nxt, other)
    busy = false
    if ok then
        pending[kind] = nxt
        log("stage[%s] %s -> slot %d", kind, nxt, other)
    else
        log("ERR stage[%s]: %s", kind, tostring(err))
    end
    refreshUi()
end

local function anyModeOn()
    return Cfg.main.mode ~= "off" or Cfg.shaqi.mode ~= "off"
end

-- 只在“没在换武器过场”时清冷却 + 预置，避免打断原生换武器技能
local function idleTicker()
    local ok = pcall(function()
        if not anyModeOn() then idleTicks = 0; return end
        local comp = FindFirstOf("CharacterWeaponsComponent")
        if comp then
            local okT, v = pcall(function() return comp:IsInWeaponTransition() end)
            if okT and v then idleTicks = 0; return end
        end
        idleTicks = idleTicks + 1
        if idleTicks < 3 then return end
        idleTicks = 3
        clearCooldown()
        stageNextWeapon("main")
        stageNextWeapon("shaqi")
    end)
    if not ok then return false end
    return false
end
pcall(function() LoopInGameThreadWithDelay(500, idleTicker) end)

pcall(function()
    RegisterLoadMapPostHook(function()
        cache.main = nil
        cache.shaqi = nil
        cursors.main = nil
        cursors.shaqi = nil
        pending.main = nil
        pending.shaqi = nil
    end)
end)

loadCfg()
log("loaded v" .. VERSION .. ": lang=%s (resolved when menu builds) main=%s shaqi=%s target=%s; F9 menu, F2 restore",
    Cfg.lang, Cfg.main.mode, Cfg.shaqi.mode, Cfg.target)

return { step = step, restore = restoreOriginal, cfg = Cfg }
