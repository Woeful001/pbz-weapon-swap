-- PBZWeaponSwap
-- < / > 按武器中文名拼音字母顺序循环切换主武器；目标武器不在装备栏时自动换装进副手槽再切换。
-- 副作用：装备栏（存档中的 2 个主武器槽）会被改写；F2 可恢复首次使用时记录的原始装备。

local MOD = "PBZWeaponSwap"
local LOG_PATH = "D:/steam/steamapps/common/PBZ/platform/steam/ue4ss/Mods/PBZWeaponSwap/log.txt"
local DEBUG = true

local function log(fmt, ...)
    local ok, s = pcall(string.format, fmt, ...)
    if not ok then s = tostring(fmt) end
    print("[" .. MOD .. "] " .. s .. "\n")
    if DEBUG then
        local f = io.open(LOG_PATH, "a")
        if f then f:write(os.date("%H:%M:%S "), s, "\n"); f:close() end
    end
end

-- ── 汉字 -> 拼音（仅需覆盖武器名用到的字；无谓词声调）──────────────────────
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

-- ── 基础取值 ────────────────────────────────────────────────────────
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

local function equippedSlots(sub)
    local slots, order = {}, {}
    local n = 0
    local ok, cnt = pcall(function() return #sub.MainWeapons end)
    if ok and type(cnt) == "number" then n = cnt end
    for i = 1, n do
        local id = S(sub.MainWeapons[i])
        slots[id] = i - 1      -- 0 基
        order[i] = id
    end
    return slots, order, n
end

-- 排序后的武器 ID 列表（按中文名拼音，同名按 ID）
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

-- 清掉切换冷却，避免受入战/动作状态影响
local function clearCooldown()
    local okC, comp = pcall(FindFirstOf, "CharacterWeaponsComponent")
    if okC and comp and comp:IsValid() then
        pcall(function() comp:ResetChangeWeaponCooldowns() end)
    end
end

-- ── 核心：循环切换 ──────────────────────────────────────────────────
local function cycle(dir)
    local sub = getSub()
    if not sub then log("no subsystem"); return end
    local sw = sortedWeapons(sub)
    if not sw or #sw.ids == 0 then log("no weapons"); return end
    local list = sw.ids
    local n = #list

    local curId = S(sub.CurrentMainWeaponID)
    local pos = indexOf(list, curId)
    if not pos then
        -- 当前武器不在表里（例如空手），从第一把开始
        pos = 1
        if dir < 0 then pos = 1 end
        log("current %s not in list, start at %s", curId, list[pos])
    else
        if dir > 0 then pos = (pos % n) + 1 else pos = ((pos - 2) % n) + 1 end
    end
    local target = list[pos]

    clearCooldown()

    local slots, order, cnt = equippedSlots(sub)
    local name = target
    for _, it in ipairs(sw.items) do if it.id == target then name = it.name break end end

    if slots[target] ~= nil then
        local idx = slots[target]
        local ok, r = pcall(function() return sub:SetCurrentWeaponByIndex(idx, true) end)
        log("switch %s -> %s (%s) slot=%d ok=%s %s", curId, target, name, idx, tostring(ok), tostring(r))
    else
        if cnt == 0 then
            log("no equipped slot, abort (%s)", target)
            return
        end
        local other = 0
        if cnt > 1 then
            local ci = sub.CurrentWeaponIndex
            other = (ci == 0) and 1 or 0
        end
        local ok1, r1 = pcall(function() return sub:ReplaceWeaponByIndex(FName(target), other) end)
        local ok2, r2 = pcall(function() return sub:SetCurrentWeaponByIndex(other, true) end)
        log("equip %s (%s) into slot %d ok=%s %s | switch ok=%s %s",
            target, name, other, tostring(ok1), tostring(r1), tostring(ok2), tostring(r2))
    end
end

-- ── 恢复原始装备 ────────────────────────────────────────────────────
local SNAP_PATH = "D:/steam/steamapps/common/PBZ/platform/steam/ue4ss/Mods/PBZWeaponSwap/snapshot.txt"

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
    local idx, list = loadSnapshot()
    if idx then return idx, list end
    local sub = getSub()
    if not sub then return nil end
    local slots, order = equippedSlots(sub)
    saveSnapshot(order, sub.CurrentWeaponIndex)
    log("snapshot saved: idx=%d [%s]", sub.CurrentWeaponIndex, table.concat(order, ","))
    return sub.CurrentWeaponIndex, order
end

local function restore()
    local sub = getSub()
    if not sub then return end
    local idx, list = loadSnapshot()
    if not idx then log("no snapshot to restore"); return end
    for i = 1, #list do
        local ok, r = pcall(function() return sub:ReplaceWeaponByIndex(FName(list[i]), i - 1) end)
        log("restore slot %d <- %s ok=%s %s", i - 1, list[i], tostring(ok), tostring(r))
    end
    pcall(function() return sub:SetCurrentWeaponByIndex(idx, true) end)
    log("restored to original loadout (idx=%d)", idx)
end

-- ── 热键 ───────────────────────────────────────────────────────────
local KEY_PREV = Key.OEM_COMMA   -- "<"
local KEY_NEXT = Key.OEM_PERIOD  -- ">"

local function onKey(delay)
    local function job()
        local ok, e = pcall(function()
            ensureSnapshot()
            cycle(delay)
        end)
        if not ok then log("ERR %s", tostring(e)) end
    end
    pcall(function() ExecuteInGameThread(job) end)
end

pcall(function() RegisterKeyBind(KEY_PREV, {}, function() onKey(-1) end) end)
pcall(function() RegisterKeyBind(KEY_NEXT, {}, function() onKey(1) end) end)
pcall(function() RegisterKeyBind(Key.F2, {}, function() pcall(function() ExecuteInGameThread(restore) end) end) end)
pcall(function() RegisterKeyBind(Key.F12, {}, function()
    pcall(function() ExecuteInGameThread(function()
        sortedCache = nil
        local sub = getSub()
        local sw = sub and sortedWeapons(sub)
        if sw then
            log("==== order (%d) ====", #sw.items)
            for i, it in ipairs(sw.items) do log("%2d %-20s %s (%s)", i, it.id, it.name, it.key) end
        end
    end) end)
end) end)

-- 自检：连续 26 次“下一把”，验证能遍历全部武器而不打转
pcall(function() RegisterKeyBind(Key.F11, {}, function()
    pcall(function() ExecuteInGameThread(function()
        ensureSnapshot()
        log("==== F11 self-test: 26x next ====")
        local step = 0
        local function one()
            step = step + 1
            if step > 26 then
                log("==== self-test end ====")
                return
            end
            local ok, e = pcall(cycle, 1)
            if not ok then log("step %d ERR %s", step, tostring(e)) end
            ExecuteInGameThreadWithDelay(250, one)
        end
        ExecuteInGameThreadWithDelay(300, one)
    end) end)
end) end)

-- 地图切换后重算武器表（武器解锁/装备可能变化）
pcall(function()
    RegisterLoadMapPostHook(function()
        sortedCache = nil
    end)
end)

log("loaded: < (OEM_COMMA) prev, > (OEM_PERIOD) next, F2 restore, F12 dump order, F11 self-test")
