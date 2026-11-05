-- PBZWeaponSwap v4.5.0
-- 用游戏原生的换武器键驱动两套武器：
--   主武器   键盘 1 / 手柄十字键左   -> SetCurrentWeaponByIndex(idx, true)
--   影之武装 键盘 2 / 手柄十字键右   -> SetCurrentWeaponByIndex(idx, false)
-- 每套各自有 关闭 / 循环 / 随机 / 自定义池 四种模式，F9 打开菜单，首行选择要配置哪一套。
-- 4.5.0：重做菜单面板排版与状态行；武器列表按拼音排序、支持自定义池；
--        新增“武器切换冷却”开关（cd=1 保留游戏原生冷却，cd=0 由模组切换后立即清冷却）。

local SRC = debug.getinfo(1, 'S').source:gsub('^@', '')
local DIR = SRC:match('^(.*[/\\])') or ''
local ROOT = DIR:gsub('Scripts[\\/]$', '')
local LOG_PATH = ROOT .. 'log.txt'
local CFG_PATH = ROOT .. 'config.txt'
local SNAP_PATH = ROOT .. 'snapshot.txt'
local DEBUG = true
local VERSION = "4.5.0"

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

-- 子系统查找：4.0.0 的 FindFirstOf 对 WorldSubsystem 有时返回 nil，
-- 这里按 FindFirstOf -> FindAllOf -> FindObject 逐级回退，并只记一次命中的方式。
local subPath = nil
local function validSub(o)
    if not o then return false end
    local ok, v = pcall(function() return o:IsValid() end)
    return ok and v
end
local function getSub()
    local ok, sub = pcall(FindFirstOf, "PBZBackPackSubsystem")
    if ok and validSub(sub) then
        if subPath ~= "FindFirstOf" then subPath = "FindFirstOf"; log("subsystem via FindFirstOf") end
        return sub
    end
    local okA, arr = pcall(FindAllOf, "PBZBackPackSubsystem")
    if okA and arr then
        local n = 0
        pcall(function() n = arr:GetArrayNum() end)
        for i = 1, (n or 0) do
            local okI, el = pcall(function() return arr[i] end)
            if okI and el then
                local okG, inst = pcall(function() return el:get() end)
                inst = okG and inst or el
                if validSub(inst) then
                    if subPath ~= "FindAllOf" then subPath = "FindAllOf"; log("subsystem via FindAllOf[%d]", i) end
                    return inst
                end
            end
        end
    end
    local okO, o = pcall(FindObject, nil, "PBZBackPackSubsystem")
    if okO and validSub(o) then
        if subPath ~= "FindObject" then subPath = "FindObject"; log("subsystem via FindObject") end
        return o
    end
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
    },
}
local KINDS = { "main", "shaqi" }

-- ── 配置 ─────────────────────────────────────────────────────────
-- Cfg[kind] = { mode = "off"|"cycle"|"random", cd = bool, pool = { [id]=true } | nil }
-- pool = nil 表示全部武器；空表表示一把都不勾（= 模组不接管切换）
local Cfg = {
    target = "main", -- F9 菜单首行选择：正在配置哪一套
    lang = "auto",   -- auto = 跟随游戏语言；也可写 zh / en
    cd = true,       -- 全局：true = 保留武器切换冷却（原生）；false = 模组负责清冷却
    main = { mode = "cycle", pool = nil },
    shaqi = { mode = "cycle", pool = nil },
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
    local p = Cfg[kind].pool
    return p == nil or next(p) == nil
end

local function normMode(v)
    if v == "off" or v == "cycle" or v == "random" then return v end
    return nil
end


local legacyCustom = {}

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
    local seenCd = false
    for _, kv in ipairs(lines) do
        local k, v = kv.k, kv.v
        if k == "cd" then
            Cfg.cd = (v == "1" or v == "true")
            seenCd = true
        elseif k == "lang" then
            if v == "auto" or v == "zh" or v == "en" then Cfg.lang = v end
        elseif k == "target" then
            if v == "main" or v == "shaqi" then Cfg.target = v end
        elseif k == "mode" or k == "random" or k == "pool" then
            -- v2 旧格式：只有一套主武器
            if k == "mode" then
                local m = normMode(v)
                if m then Cfg.main.mode = m elseif v == "custom" then Cfg.main.mode = "cycle" end
            elseif k == "random" then
                Cfg.main.mode = (v == "1" or v == "true") and "random" or "cycle"
            else
                local pool = {}
                for id in v:gmatch("[^,]+") do pool[id] = true end
                if next(pool) then Cfg.main.pool = pool end
            end
        else
            local kind, field = k:match("^(%a+)%.(%a+)$")
            if kind and Cfg[kind] then
                if field == "mode" then
                    local m = normMode(v)
                    if m then
                        Cfg[kind].mode = m
                    elseif v == "custom" then
                        Cfg[kind].mode = "cycle"   -- 旧格式：等 cmode 行升级成 random/cycle
                        legacyCustom[kind] = true
                    end
                elseif field == "cmode" then
                    if legacyCustom[kind] then
                        local m = normMode(v)
                        if m then Cfg[kind].mode = m end
                        legacyCustom[kind] = nil
                    end
                elseif field == "random" then
                    Cfg[kind].mode = (v == "1" or v == "true") and "random" or "cycle"
                elseif field == "cd" then
                    Cfg[kind].cd = (v == "1" or v == "true") -- 旧格式，仅用于迁移
                elseif field == "pool" then
                    local pool = {}
                    for id in v:gmatch("[^,]+") do pool[id] = true end
                    Cfg[kind].pool = (next(pool) ~= nil) and pool or nil
                end
            end
        end
    end
    -- 旧配置只有 kind.cd：按主武器那一套迁移成全局开关
    if not seenCd and Cfg.main.cd ~= nil then Cfg.cd = (Cfg.main.cd == true) end
end

local function saveCfg()
    local f = io.open(CFG_PATH, "w")
    if not f then return end
    f:write("version=", VERSION, "\n")
    f:write("lang=", Cfg.lang, "\n")
    f:write("target=", Cfg.target, "\n")
    f:write("cd=", Cfg.cd and "1" or "0", "\n")
    for _, kind in ipairs(KINDS) do
        local c = Cfg[kind]
        f:write(kind, ".mode=", c.mode, "\n")
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

-- 武器 ID → 游戏内中文显示名（内置，避免在 4.x 上调用 GetMainWeaponTableData 触发崩溃）
local NAMES = {
    main = {
        Tang = "黑伤", WoodenSwordHun = "木制黑伤", Double = "黑伤双刃", IronBlade = "残钢刃",
        Long = "长形黑伤", GuiTouBlade = "红妆鬼斩", ChiZheCanJian = "痴者残剑", ZhanMaBlade = "亡命斩马刀",
        SnakeDual = "白蟒赤练", RenOuQingTongJian = "天玄青铜剑", YuuBlade = "妖锯", LuanYing = "乱莺剑",
        PoJun = "破军", SlitheringSword = "灵蛇软剑", BaiShanShuangJian = "白山风雷剑", DualHook = "别离残钩",
        TianShaShuangYue = "天煞双钺", HorizontalBlade = "荡寇凶刃", JadeDualChakram = "玉双环", BaiYing = "白影",
        CiGuHunDun = "刺骨混沌", RenOuYanYueDao = "偃月刀", Jigsaw = "断肢锯", FangHuaXieShan = "圣母邪扇",
        ZiMingJian = "紫冥剑",
    },
    shaqi = {
        JinGua = "长柄金瓜", JianKeZhaoJiLing = "剑客召集令", ThunderSpear = "雷霆枪", CuiXinPiPa = "催心琵琶",
        MoJian = "墨血无痕", MiaoShouFeiDao = "妙手飞刀", BrutalAxe = "巨凶斧", ZhuoBiDun = "拙壁盾",
        CaoOuSiXian = "操偶铃铛", NiTouche = "泥头车", YouLongCha = "游龙叉", YouLongTou = "游龙头",
        HuoLiuXing = "火流星", LionHead = "烈焰狮头", DuYanGong = "独眼弓", UnnamedBow = "羽弓",
        KuYeSiZhuChuan = "苦叶寺珠串", TigerCannon = "虎炮", XuKongHuaShan = "虚空华扇", XueDiZi = "血滴子",
        TanLang = "贪狼", ShachiHook = "追命锁镰", TieGongZhuQuanTao = "铁拳套", HuangJinHuoChong = "黄金火铳",
    },
}

local cache = { main = nil, shaqi = nil }

local function sortedWeapons(sub, kind)
    if cache[kind] then return cache[kind] end
    local names = NAMES[kind]
    if not names then return nil end
    local items = {}
    for id, zh in pairs(names) do
        items[#items + 1] = { id = id, name = zh, key = pinyin(zh) }
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

local cdResetLogged = false
local function clearCooldown()
    local okC, comp = pcall(FindFirstOf, "CharacterWeaponsComponent")
    if not (okC and comp and comp:IsValid()) then
        if not cdResetLogged then cdResetLogged = true; log("cd reset: no component") end
        return
    end
    local okR, err = pcall(function() comp:ResetChangeWeaponCooldowns() end)
    if not okR then
        if not cdResetLogged then cdResetLogged = true; log("cd reset FAILED: %s", tostring(err)) end
    elseif not cdResetLogged then
        cdResetLogged = true
        log("cd reset: ok (ResetChangeWeaponCooldowns works)")
    end
end

-- ── 应用切换（busy 期间钩子放行，避免自我拦截）────────────────────
local busy = false
local runSwitchSelfTest = nil        -- 前向声明（菜单区块在文件后半段定义前就要用到）
local funcRefresh = nil
local function refreshUi()
    if funcRefresh then pcall(funcRefresh) end
end

-- cd=true 时不重置换武器冷却，交给游戏原生冷却决定按键是否响应。
-- 注意：CharacterWeaponsComponent 的冷却是整个组件共用的，任一套勾了“保留冷却”，
-- 另一套的预置（ReplaceWeaponByIndex）同样会把冷却刷掉，所以这里是全局判断。
-- 模组自己调用 setCur 时，不要把这次调用当成玩家的按键再拦一遍（否则会自激振荡）
local hookMuteUntil = 0
local armedKind, armedUntil = nil, 0   -- 选完后等待下一次按键放行，交给游戏原生切换
local function muteHook(sec)
    hookMuteUntil = os.clock() + (sec or 0.2)
end

local function cdProtected()
    return Cfg.cd == true
end

local function resetCd(kind)
    if cdProtected() then return end
    clearCooldown()
end

-- cd 关时：每一次 ReplaceWeaponByIndex 都会重新压上引擎冷却，换完要立刻清几次
local settleCd
settleCd = function(kind)
    if cdProtected() then return end
    for _, delay in ipairs({ 0, 60, 200 }) do
        ExecuteInGameThreadWithDelay(delay, function()
            pcall(function() resetCd(kind) end)
        end)
    end
end
local function applyTarget(sub, kind, target, sw)
    local def = T[kind]
    local slots, _, cnt = equippedSlots(sub, kind)
    local name = displayOf(sw, target)
    local curBefore, idxBefore = curOf(sub, kind)
    busy = true
    local ok, err = pcall(function()
        resetCd(kind)
        settleCd(kind)
        if slots[target] ~= nil then
            local idx = slots[target]
            if idx == idxBefore then
                log("[%s] already current: %s (%s) slot=%d", kind, target, name, idx)
                return
            end
            muteHook(0.25)
            def.setCur(sub, idx)
            log("[%s] switch %s -> %s (%s) slot=%d", kind, tostring(curBefore), target, name, idx)
        else
            if cnt == 0 then log("[%s] no equipped slot, abort (%s)", kind, target); return end
            local other = 0
            if cnt > 1 then other = (idxBefore == 0) and 1 or 0 end
            def.replace(sub, target, other)
            muteHook(0.25)
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
    if c.pool == nil then return sw.ids end
    local out = {}
    for _, id in ipairs(sw.ids) do if c.pool[id] then out[#out + 1] = id end end
    return out
end

-- 原生切换会同时改掉当前索引，所以循环位置用本模组自己的游标，不依赖游戏当前值
local cursors = { main = nil, shaqi = nil }
-- 已经预置到待切槽、但玩家还没按键的武器：避免随机模式下每个 tick 都换一把塞进去
local pending = { main = nil, shaqi = nil }
local pendingAt = { main = 0, shaqi = 0 }   -- 4.8.9：装填标记的写入时间，超时自动作废

local function pickNext(kind, sw, fromId)
    local c = Cfg[kind]
    local pool = poolFor(kind, sw)
    if #pool == 0 then return nil, pool end
    if c.mode == "random" then
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
                muteHook(0.25)
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
local stageUrgent = false -- 刚切过一次：尽快补预置，别等满 1.5 秒，否则下一把来不及备好、技能会被跳过

-- 地图切换护栏：切换大地图时世界/子系统/组件都会被销毁重建，
-- 这期间任何 ReplaceWeaponByIndex / ResetChangeWeaponCooldowns 都可能踩到半死对象。
local switchingMap = false
local worldGuardUntil = 0 -- os.time() 秒：落地后仍冻结一段时间再恢复
local currentWorld       -- 前向声明：下面的暂停逻辑要用，实现在文件后半段

-- UE4SS 每次取到的 UObject 包裹对象不是同一个 userdata，直接 ~= 比较会永远“不相等”。
-- 判断世界有没有换，必须比地址。
local function worldAddr()
    local w = currentWorld()
    if not w then return nil end
    local ok, a = pcall(function() return w:GetAddress() end)
    if ok and a ~= nil then return a end
    return tostring(w)
end
local menuStale = false
local lastWorldAddr = nil -- 轮询 World 对象地址判定切图（不再用 LoadMap 钩子）
local lastWorldAt = 0       -- 上次检测到换世界的时间（os.clock）；换世界后 3 秒内不弹面板
local WORLD_SETTLE = 3.0
local resetWeaponState  -- 前向声明，实体定义在文件后段
local TOGGLE_MIN_GAP = 0.45 -- F9 连按节流（秒）
local lastToggleAt = 0
local invWidget = nil -- 背包界面控件缓存（打开背包时自动关菜单）
local inventoryVisible -- 前向声明，实体在文件后段（F9 防抖里要用来挡“背包开着按 F9”）

local function inMapTransition()
    if switchingMap then return true end
    if os.time() < worldGuardUntil then return true end
    return false
end

local function readParam(p, default)
    if p == nil then return default end
    local okG, v = pcall(function() return p:get() end)
    if okG then return v end
    return p
end

-- 背上那把武器永远不变：模组只改数据层，游戏不会重建“空槽/非当前槽”那件武器的挂件，
-- 于是它一直挂在背上。RefreshWeaponVisibility 需要 1 个 UObject 参数（传数字、布尔都
-- 报 push_objectproperty），最合理的对象是那把武器自己的网格组件。所以先在角色身上
-- 找出名字带 Weapon 的网格组件，换完武器后让游戏对这些组件重算一次可见性。
local backComps = nil
local backProbeLogged = false
local backSyncOff = false

local function collectWeaponComps()
    local out = {}
    local pawn = nil
    pcall(function()
        local pc = FindFirstOf("PBZPlayerController") or FindFirstOf("PlayerController")
        if pc then pawn = pc.Pawn end
    end)
    for _, cls in ipairs({ "SkeletalMeshComponent", "StaticMeshComponent" }) do
        local list = nil
        pcall(function() list = FindAllOf(cls) end)
        if list then
            for _, c in pairs(list) do
                local okn, nm = pcall(function() return c:GetFName():ToString() end)
                local name = okn and nm or ""
                if name:lower():find("weapon") then
                    local own = nil
                    pcall(function() own = c:GetOwner() end)
                    if own ~= nil and (pawn == nil or own == pawn) then
                        out[#out + 1] = c
                        if #out <= 12 then log("backprobe: comp %s owner=%s", name, tostring(own)) end
                    end
                end
            end
        end
    end
    return out
end

local function backSyncWeapon(tag)
    tag = tostring(tag)
    if backSyncOff then return end
    if backComps == nil then
        local ok, res = pcall(collectWeaponComps)
        backComps = ok and res or {}
        log("backprobe[%s]: weapon components found=%d", tag, #backComps)
        if #backComps == 0 then
            backSyncOff = true
            log("backprobe[%s]: none found, back-sync disabled", tag)
            return
        end
    end
    local okN, errN = 0, nil
    for _, c in ipairs(backComps) do
        local okR, errR = pcall(function() c:RefreshWeaponVisibility() end)
        if okR then
            okN = okN + 1
        else
            errN = errR
        end
    end
    if not backProbeLogged then
        backProbeLogged = true
        log("back-sync[%s]: component self-refresh ok=%d/%d err=%s", tag, okN, #backComps, tostring(errN))
        if okN == 0 then
            -- 组件上没有这个函数，改在组件所属的武器 actor 上试
            for _, c in ipairs(backComps) do
                local own = nil
                pcall(function() own = c:GetOwner() end)
                if own then
                    local okA, errA = pcall(function() own:RefreshWeaponVisibility() end)
                    log("back-sync[%s]: owner-refresh %s -> ok=%s err=%s", tag, tostring(own), tostring(okA), tostring(errA))
                    if okA then break end
                end
            end
        end
    end
end

local function onSetWeaponByIndex(ctx, idxParam, isNormalParam)
    if os.clock() < hookMuteUntil then return nil end
    if armedKind and os.clock() < armedUntil then
        armedKind = nil
        log("armed: let native switch through, will drop the swapped-out one")
        local dropKind = Cfg.target
        ExecuteInGameThreadWithDelay(3000, function()
            local svc = getSub()
            if not svc then return end
            local _, idxNow = curOf(svc, dropKind)
            local _, order = equippedSlots(svc, dropKind)
            local other = 1 - (idxNow or 0)
            local drop = order and order[other + 1]
            if not drop or isBlankId(drop) then
                log("single-slot[%s]: other slot already empty", dropKind)
                return
            end
            log("single-slot[%s]: would drop %s — deletion disabled (9.5.0)", dropKind, tostring(drop))
        end)
        return nil
    end
    local ok, err = pcall(function()
        if busy then return end
        if inMapTransition() then return end
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
        stageUrgent = true
        local pre = pending[kind]
        log("intercept[%s] native switch: idx=%s cur=%s pre=%s (hit %d, shaqi %d)",
            kind, tostring(idx), tostring(cur), tostring(pre), stats.hits, stats.hits_shaqi)

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
                resetCd(kind)
                T[kind].replace(sub, target, idx)
                busy = false
                log("late preload[%s] %s into slot %d (not pre-staged)", kind, target, idx)
            else
                log("native switch[%s] uses pre-staged %s (slot %d)", kind, target, idx)
            end
            pending[kind] = nil
            cursors[kind] = target
            ExecuteInGameThreadWithDelay(200, function()
                pcall(function()
                    if inMapTransition() then return end
                    local s2 = getSub()
                    if s2 then
                        local id2, i2 = curOf(s2, kind)
                        log("after native[%s]: cur=%s idx=%s", kind, tostring(id2), tostring(i2))
                    end
                    backSyncWeapon(kind)
                    refreshUi()
                end)
            end)
        end)
        if not ok2 then
            busy = false
            log("ERR hook-body[%s]: %s", kind, tostring(e2))
        end
    end)
    if not ok then log("ERR hook: %s", tostring(err)) end
    -- UE4SS 4.0.0：hook 回调的返回值会被写进 UFunction 的返回槽，
    -- 对 void 函数（SetCurrentWeaponByIndex 就是）会踩空指针直接崩游戏，
    -- 所以这里必须返回 nil（即不写 return 值）。
    return nil
end

do
    local ok, err = pcall(RegisterHook,
        '/Script/ProjectPBZ.PBZBackPackSubsystem:SetCurrentWeaponByIndex', onSetWeaponByIndex)
    log("hook SetCurrentWeaponByIndex: %s", ok and "ok" or tostring(err))
end


-- 单槽：槽位写入必须走 SetSlotWeapon(tag, index, 武器结构体)，而那个结构体 Lua 构造不出来
--（传 {} 直接硬崩，5.1.0 实测）。RemoveWeaponByID 返回 ok=true 但槽位不变（6.0.0 实测）。
-- 所以这里只做检查与提示：玩家在背包里手动卸下一次后，游戏会把空槽存进存档，模组不再写这一格。
local function isBlankId(id)
    if id == nil then return true end
    id = tostring(id)
    return id == "" or id == "None" or id == "nil" or id == "None_Weapon"
end

-- 把某个槽清空：成功后原生切换会落到“没有武器”上，不会换出任何东西。
-- ReplaceWeaponByIndex 对 "None" 的处理没文档，所以每次都要读回确认，失败就退回镜像方案。
local function slotIsEmpty(kind, sub, slot)
    local _, order = equippedSlots(sub, kind)
    local now = order and order[slot + 1] or nil
    return isBlankId(now), now
end

local cfgDiagDone = false
local function findWeaponConfig(id)
    local tried = { "PBZ_MainWeaponConfig_C", "PBZ_MainWeaponConfig", "PBZ_WeaponConfig_C" }
    for _, cls in ipairs(tried) do
        local ok, list = pcall(function() return FindAllOf(cls) end)
        local n = (ok and list) and #list or -1
        if not cfgDiagDone then
            local samples = {}
            if n > 0 then
                for i = 1, math.min(n, 3) do
                    local okf, full = pcall(function() return list[i]:GetFullName() end)
                    samples[#samples + 1] = okf and full or "?"
                end
            end
            log("cfg diag: %s -> %s [%s]", cls, tostring(n), table.concat(samples, " | "))
        end
        if n > 0 then
            for _, o in ipairs(list) do
                local okn, full = pcall(function() return o:GetFullName() end)
                if okn and full and full:find(id, 1, true) then
                    cfgDiagDone = true
                    return o
                end
            end
        end
    end
    cfgDiagDone = true
    -- 内存里没有 = 这把武器没被加载过，按资源路径拉一次
    local base = "/PBZCombatAsset/ActorData/Players/Hun/Weapon/"
    local cands = {
        base .. id .. "/Weapon_Hun_" .. id .. "." .. "Weapon_Hun_" .. id,
        base .. id .. "/" .. id .. "." .. id,
        base .. id .. "/Weapon_" .. id .. ".Weapon_" .. id,
    }
    for _, path in ipairs(cands) do
        local okL, obj = pcall(function() return LoadAsset(path) end)
        if okL and obj then
            log("cfg loaded: %s", path)
            return obj
        end
        log("cfg load failed: %s (%s)", path, tostring(obj))
    end
    return nil
end

-- 关键怀疑：SetSlotWeapon 对“背包里没有的武器”会返回 ok 但实际不生效。
-- 先把玩家真正拥有的武器列出来看看。
local ownedLogged = false
local function ownedWeapons()
    local sub = getSub()
    if not sub then return nil end
    local out = {}
    local function push(v)
        local id = S(v)
        if id and id ~= "" and id ~= "None" then out[#out + 1] = id end
    end
    local okA, arr = pcall(function() return sub:GetAllNormalWeapons() end)
    local n = 0
    if okA and type(arr) == "table" then
        for _, v in ipairs(arr) do push(v); n = n + 1 end
    end
    local okE, eq = pcall(function() return sub:GetEquipmentNormalWeapons() end)
    local m = 0
    if okE and type(eq) == "table" then
        for _, v in ipairs(eq) do push(v); m = m + 1 end
    end
    if not ownedLogged then
        ownedLogged = true
        log("owned: GetAllNormalWeapons ok=%s n=%d | GetEquipmentNormalWeapons ok=%s n=%d", tostring(okA), n, tostring(okE), m)
        log("owned ids: [%s]", table.concat(out, ","))
    end
    return out
end

-- ── F9 菜单（复用 PBZTrainingDummy 同款 ModMenu 外壳）──────────────
local ui = nil
do
    local ok, mod = pcall(dofile, DIR .. 'vendor/ModMenu.lua')
    if ok and type(mod) == "table" then ui = mod else log("ModMenu load failed: %s", tostring(mod)) end
end

-- ESC：面板或菜单开着就关掉
local function closeAnyUi()
    if ui then pcall(function() ui.Close() end) end
end
pcall(function() RegisterKeyBind(Key.ESCAPE, closeAnyUi) end)
-- F3：安全枚举 UFunction 名字（只读元数据，不碰属性、不调游戏函数）
-- RemoveWeapon 在背包子系统上是 MulticastDelegate 事件，不能调用；改用 ForEachFunction 看真实函数名
local function dumpFuncs(obj, label, pattern)
    if not obj then log("dump[%s]: nil", label); return end
    local cls = nil
    pcall(function() cls = obj:GetClass() end)
    if not cls then log("dump[%s]: no class", label); return end
    local n = 0
    local ok, err = pcall(function()
        -- 回调参数是 UFunction 对象本身（不是字符串），名字要 GetFullName() 再取冒号后半段
        cls:ForEachFunction(function(fn)
            local okn, full = pcall(function() return fn:GetFullName() end)
            if not okn then return end
            local name = tostring(full):match("([%w_]+)$") or tostring(full)
            if pattern == nil or name:lower():find(pattern) then
                n = n + 1
                if n <= 400 then log("dump[%s]: %s", label, name) end
            end
        end)
    end)
    log("dump[%s]: matched=%d ok=%s err=%s", label, n, tostring(ok), ok and "-" or tostring(err))
end

-- 参数类型探测：故意传错类型，让 UE4SS 在“封送参数”阶段就报错（不会执行函数体，不会崩）
local function probeTypes()
    local comp = nil
    pcall(function() comp = FindFirstOf("CharacterWeaponsComponent") end)
    if not comp then log("ptype: no comp"); return end
    local tag = { TagName = "Weapon.Slot.Main" }
    local function try(label, f)
        local ok, err = pcall(f)
        log("ptype[%s]: ok=%s -> %s", label, tostring(ok), tostring(err))
    end
    try("Get(tag,str,str)", function() return comp:GetSlotWeapon(tag, "q", "q") end)
    try("Get(str,str,str)", function() return comp:GetSlotWeapon("q", "q", "q") end)
    try("Set(str,str,str)", function() return comp:SetSlotWeapon("q", "q", "q") end)
    try("Set(tag,str,str)", function() return comp:SetSlotWeapon(tag, "q", "q") end)
    log("ptype: done")
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
        { label = L("循环（池内按拼音顺序轮换）", "Cycle (pinyin order in pool)"), value = "cycle" },
        { label = L("随机（池内随机）", "Random (in pool)"), value = "random" },
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
    items[#items + 1] = {
        type = 'button', id = kind .. '_all',
        label = L("全选 / 取消全选", "Select all / none"),
        onClick = function()
            local cc = Cfg[kind]
            local allOn = (cc.pool == nil) or (next(cc.pool) == nil)
            local on = not allOn
            if on then
                cc.pool = nil
                for _, it in ipairs(sw.items) do pcall(function() ui.Set('pool', kind .. '_' .. it.id, true) end) end
            else
                cc.pool = {}
                for _, it in ipairs(sw.items) do pcall(function() ui.Set('pool', kind .. '_' .. it.id, false) end) end
            end
            saveCfg()
            log("[%s] pool all = %s", kind, tostring(on))
            refreshUi()
        end }

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
        { type = 'checkbox', id = 'cd', label = L("关闭武器切换cd（全局）", "Disable weapon-switch cooldown (global)"), default = (not Cfg.cd),
          onChange = function(on)
              Cfg.cd = not on -- 勾上 = 不要冷却
              saveCfg()
              log("cd = %s (mod clears cooldown: %s)", tostring(Cfg.cd), tostring(not Cfg.cd))
              refreshUi()
          end },
        { type = 'separator' },
        { type = 'dropdown', id = 'target', label = L("配置对象", "Configure"), options = targetOptions(), default = Cfg.target,
          onChange = function(v)
              if v ~= "main" and v ~= "shaqi" then return end
              Cfg.target = v
              saveCfg()
              if ui then
                  local cc = Cfg[v]
                  pcall(function() ui.Set('swap', 'mode', cc.mode) end)
                  pcall(function() ui.Set('swap', 'cd', not Cfg.cd) end)
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

-- 4.x 下 GetAllNormalWeapons() 的返回形态不稳定（且 GetMainWeaponTableData 会崩），
-- 这里直接用内置名单计数，不再碰引擎侧列表接口
local function weaponCount(sub, kind)
    local names = NAMES[kind]
    if not names then return 0 end
    local n = 0
    for _ in pairs(names) do n = n + 1 end
    return n
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
    -- 面包屑：重建菜单控件是最容易硬崩的一步，崩了就只会停在这两行之间
    log('refresh: rebuild menu sections ...')
    if ui then pcall(registerSections, sub) end
    log('refresh: sections done, labels ...')
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
            if menuStale then
                menuStale = false
                pcall(refreshWeapons, true)
                return
            end
            if listChanged(sub2) then pcall(refreshWeapons, false) end
            setStatusLabels()
        end)
        if not ok then log("ERR refresh: %s", tostring(err)) end
    end
    funcRefresh = refresh
    ui.OnOpen(refresh)

    -- F9 防抖：ModMenu 的按键回调每帧直接调 Lifecycle.Toggle（无节流），
    -- 连按时“拆界面”和“建界面”会重叠执行，实测必崩。
    -- 输入回调每次都会 `Lifecycle.Toggle(S)` 现查表，替换模块字段即可全局生效。
    local okL, LC = pcall(require, "PBZWSMenu.shell.lifecycle")
    if okL and type(LC) == "table" and type(LC.Toggle) == "function" and not LC.__wsGuarded then
        local origToggle = LC.Toggle
        LC.__wsGuarded = true
        LC.Toggle = function(S)
            local now = os.clock()
            if now - lastToggleAt < TOGGLE_MIN_GAP then
                log("toggle ignored: only %.2fs since last press", now - lastToggleAt)
                return
            end
            -- 背包开着时不允许弹出菜单（两套 UMG 同时抢输入会崩）
            if not (S and S.menuOpen) and inventoryVisible and inventoryVisible() then
                log("toggle ignored: inventory is open")
                return
            end
            lastToggleAt = now
            local closing = (S and S.menuOpen) == true
            log("toggle: %s", closing and "close" or "open")
            local r = origToggle(S)
            log("toggle done: %s", closing and "close" or "open")
            return r
        end
        log("toggle guard installed: min gap %.2fs", TOGGLE_MIN_GAP)
    else
        log("toggle guard NOT installed (lifecycle=%s)", tostring(LC))
    end

    -- 关闭路径分段追踪：ModMenu.Close 依次调 5 个引擎相关步骤，
    -- 4.x 下不知道崩在哪一步，逐段打点，日志里最后一个 trace> 就是崩溃点。
    local traced = {}
    local function traceFn(modName, key, tag)
        local okM, mod = pcall(require, modName)
        if not okM or type(mod) ~= "table" then
            log("trace skip: %s not loaded", modName)
            return
        end
        if traced[tag] then return end
        local f = mod[key]
        if type(f) ~= "function" then
            log("trace skip: %s.%s missing", modName, key)
            return
        end
        traced[tag] = true
        mod[key] = function(...)
            log("trace> %s", tag)
            local r = f(...)
            log("trace< %s", tag)
            return r
        end
    end
    traceFn("PBZWSMenu.shell.confirm", "Hide", "Confirm.Hide")
    traceFn("PBZWSMenu.core.input", "ClearClickState", "Input.ClearClickState")
    traceFn("PBZWSMenu.widgets.dropdown", "collapseAll", "Dropdown.collapseAll")
    traceFn("PBZWSMenu.core.cursor", "Hide", "Cursor.Hide")
    traceFn("PBZWSMenu.core.inputmode", "SetActive", "InputMode.SetActive")

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
-- 不用 RegisterLoadMapPreHook/PostHook：UE4SS v3.0.1 下多个 Lua mod 同时注册，
-- 会在“设置 LoadMap 返回值”这条路径上冲突（日志：both mods tried to set the same return value），
-- 实测切大地图必崩。改为每 tick 比较 World 对象地址来判定切图。
currentWorld = function()
    local okH, H = pcall(require, "UEHelpers")
    if okH and type(H) == "table" then
        local okW, w = pcall(H.GetWorld)
        if okW and w then return w end
    end
    local okF, w2 = pcall(function() return FindFirstOf("World") end)
    if okF then return w2 end
    return nil
end

local function pollWorldChange()
    local w = currentWorld()
    if not w then return end
    local okA, addr = pcall(function() return w:GetAddress() end)
    if not okA or type(addr) ~= "number" or addr == 0 then return end
    if lastWorldAddr == nil then
        lastWorldAddr = addr
        return
    end
    if addr ~= lastWorldAddr then
        log("world changed: 0x%X -> 0x%X, weapons frozen", lastWorldAddr, addr)
        lastWorldAddr = addr
        switchingMap = true
        lastWorldAt = os.clock()
        worldGuardUntil = os.time() + 10
        menuStale = true
        pcall(resetWeaponState)
        if ui and menuBuilt then pcall(function() ui.Close() end) end
    end
    if switchingMap and os.time() >= worldGuardUntil then
        switchingMap = false
        log("world guard over: weapons resume")
    end
end

-- ── 槽位观察（4.8.8）───────────────────────────────────────────────
-- 单槽需要“把副槽变成空”。Lua 侧唯一被证实能真正改装备栏的入口是
-- ReplaceWeaponByIndex（只能写武器名，写空名被游戏忽略），所以先记录
-- 玩家自己在背包里卸下武器时数据层到底变成什么形状：
--   是数组长度变成 1，还是某格变成空 id？拿到形状才能对齐写法。
local watchPrev = {}
local function slotSignature(kind)
    local sub = getSub()
    if not sub then return nil end
    local ok, _, order, cnt = pcall(equippedSlots, sub, kind)
    if not ok then return nil end
    local ids = {}
    for i = 1, (cnt or 0) do ids[i] = tostring(order[i]) end
    return (cnt or 0) .. "[" .. table.concat(ids, ",") .. "]"
end

local function slotWatch()
    for _, kind in ipairs({ "main", "shaqi" }) do
        local sig = slotSignature(kind)
        if sig then
            if watchPrev[kind] and sig ~= watchPrev[kind] then
                log("watch[%s]: %s -> %s", kind, watchPrev[kind], sig)
            end
            watchPrev[kind] = sig
        end
    end
end

local function tick()
    local ok, err = pcall(function()
        pollWorldChange()
        if inMapTransition() then return end
        local sub = getSub()
        if sub then
            ensureSnapshot()
            pcall(slotWatch)
            if not menuBuilt then buildMenu(sub) end
            if menuStale then
                menuStale = false
                log("map load done: menu data will refresh on next open")
            end
        end
    end)
    if not ok then log("tick: %s", tostring(err)) end
    return false
end
pcall(function() LoopInGameThreadWithDelay(1500, tick) end)

-- ── 备用热键 ───────────────────────────────────────────────────────
pcall(function()
    RegisterKeyBind(Key.F2, {}, function()
        pcall(function()
            ExecuteInGameThread(function()
                if inMapTransition() then return end
                restoreOriginal()
            end)
        end)
    end)
end)

-- ── 等级诊断（F4）────────────────────────────────────────────────
-- 25 级武器被动依赖等级数据；若换装把 MainWeaponInfos 里的等级重置成 1，
-- 效果自然不触发。这里逐步问引擎要数据，崩在哪一步日志里就能看出来。
-- 背包联动：背包一露头就关掉模组菜单。
-- 菜单开着进背包时，两套 UMG 同时抢 UI 输入模式（InputMode / 光标），实测会崩。
-- 探测顺序：① PBZBackPackSubsystem:GetInventoryWidget()（游戏自带的访问器，最准）
--           ② FindFirstOf("PBZInventoryWidget")（C++ 基类，兜底）
local invNextProbe = 0

local probeHow = nil

-- 4.x 下对已销毁的 UObject 解析 IsValid 方法会硬崩，优先用引擎侧全局 IsValid；
-- 两种方式都问不出来时按“仍然有效”处理，避免每 tick 丢弃缓存对象反复重建。
local function objValid(w)
    if w == nil then return false end
    local okG, gv = pcall(function() return IsValid(w) end)
    if okG and type(gv) == "boolean" then return gv end
    local okM, mv = pcall(function() return w:IsValid() end)
    if okM and type(mv) == "boolean" then return mv end
    return true
end

local function widgetVisible(w)
    if not w then return false end
    if not objValid(w) then return false end
    local okI, vis = pcall(function() return w:IsVisible() end)
    if okI and type(vis) == "boolean" then return vis end
    local okG, gv = pcall(function() return w:GetVisibility() end)
    if okG and gv ~= nil then
        local s = tostring(gv)
        return not (s:find("Collapsed") or s:find("Hidden"))
    end
    return false
end

local function probeInventoryWidget()
    local sub = getSub()
    if sub then
        local ok, w = pcall(function() return sub:GetInventoryWidget() end)
        if ok and w and objValid(w) then
            return w, "sub:GetInventoryWidget"
        end
    end
    local ok2, w2 = pcall(function() return FindFirstOf("PBZInventoryWidget") end)
    if ok2 and w2 then return w2, "FindFirstOf(PBZInventoryWidget)" end
    return nil, nil
end

local function inventoryVisible_impl()
    local now = os.clock()
    if invWidget and not objValid(invWidget) then
        invWidget = nil
    end
    if not invWidget and now >= invNextProbe then
        invNextProbe = now + 1.0
        local w, how = probeInventoryWidget()
        if w then
            invWidget = w
            if probeHow ~= how then
                probeHow = how
                log("inventory widget found via %s", tostring(how))
            end
        end
    end
    return widgetVisible(invWidget)
end
inventoryVisible = inventoryVisible_impl

local function inventoryGuardTick()
    local ok, err = pcall(function()
        if not (ui and menuBuilt) then return end
        if inMapTransition() then return end
        if not ui.IsOpen() then return end
        if inventoryVisible() then
            pcall(function() ui.Close() end)
            log("inventory opened -> menu auto closed")
        end
    end)
    if not ok then log("invGuard: %s", tostring(err)) end
    return false
end
pcall(function() LoopInGameThreadWithDelay(150, inventoryGuardTick) end)

-- 空闲预置：把“下一把目标武器”提前放进待切槽，按键时原生直接切出它，技能不会被截断
local function stageNextWeapon(kind)
    local c = Cfg[kind]
    if c.mode == "off" then return end
    if inMapTransition() then return end
    local sub = getSub()
    if not sub then return end
    local okV, live = pcall(function() return sub:IsValid() end)
    if not okV or not live then return end
    local sw = sortedWeapons(sub, kind)
    if not sw or #sw.ids == 0 then return end
    local slots, order, cnt = equippedSlots(sub, kind)
    if cnt < 1 then return end
    local curId, curIdx = curOf(sub, kind)
    -- 手里是空槽（玩家在背包里卸下了武器）：没有“当前武器”这个概念，
    -- 从池子的第一把开始装填，而不是沿用那个空 id。
    if curId ~= nil and isBlankId(tostring(curId)) then curId = nil end
    if cursors[kind] == nil or isBlankId(tostring(cursors[kind])) then cursors[kind] = curId end
    -- 上一把预置的武器：已经拿到手上就作废标记；被挤掉也作废；
    -- 仍在另一格时——空手就立刻把那一格设为当前（玩家卸了武器，不能干等按键），
    -- 有武器在手就继续等玩家按切换键（只刷新时间戳，绝不清标记，否则死循环）。
    local p = pending[kind]
    if p then
        local age = os.clock() - (pendingAt[kind] or 0)
        if p == curId then
            pending[kind] = nil
        elseif slots[p] == nil then
            log("stage[%s] pending %s cleared (gone from slots, cur=%s)", kind, tostring(p), tostring(curId))
            pending[kind] = nil
        elseif curId == nil then
            local slotIdx = slots[p]
            pending[kind], pendingAt[kind] = nil, 0
            log("stage[%s] %s already in slot %d, arming it (hand was empty)", kind, tostring(p), slotIdx)
            ExecuteInGameThreadWithDelay(200, function()
                            muteHook(1.2)
                local svc = getSub()
                if svc then pcall(T[kind].setCur, svc, slotIdx) end
                refreshUi()
            end)
            return
        else
            pendingAt[kind] = os.clock()
            return
        end
    end
    local nxt = pickNext(kind, sw, cursors[kind])
    if nxt == nil then return end
    if slots[nxt] ~= nil then
        local slotIdx = slots[nxt]
        pending[kind] = nxt
        pendingAt[kind] = os.clock()
        -- 手里是空槽（玩家把武器卸了）：不能干等玩家按键，直接把这一格设为当前，
        -- 否则空手状态下永远没人触发切换，看起来就是“根本不装填”。
        if curId == nil and slotIdx ~= curIdx then
            log("stage[%s] %s already in slot %d, arming it (hand was empty)", kind, nxt, slotIdx)
            ExecuteInGameThreadWithDelay(200, function()
                            muteHook(1.2)
                local svc = getSub()
                if svc then pcall(T[kind].setCur, svc, slotIdx) end
                refreshUi()
            end)
        end
        return
    end
    -- 目标格：优先真正的空格（null 或 "None"），否则用非当前格。
    -- 手里是空槽时 curIdx 仍指向那个空位，单槽状态下必须把下一把装进这里，
    -- 否则玩家按键切过去只会拿到一个空手。
    local other = nil
    if curId == nil then
        for i = 0, cnt - 1 do
            local v = order and order[i + 1]
            if v == nil or isBlankId(tostring(v)) then other = i; break end
        end
    end
    if other == nil then
        other = (curIdx == 0) and 1 or 0
        if other >= cnt then other = 0 end
    end
    busy = true
    local ok, err = pcall(T[kind].replace, sub, nxt, other)
    busy = false
    if ok then
        settleCd(kind)
        pending[kind] = nxt
        pendingAt[kind] = os.clock()
        log("stage[%s] %s -> slot %d (cur=%s idx=%s slots=%s/%s)", kind, nxt, other,
            tostring(curId), tostring(curIdx), tostring(order and order[1]), tostring(order and order[2]))
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
        if inMapTransition() then idleTicks = 0; return end
        local comp = FindFirstOf("CharacterWeaponsComponent")
        if comp then
            local okT, v = pcall(function() return comp:IsInWeaponTransition() end)
            if okT and v then idleTicks = 0; return end
        end
        idleTicks = idleTicks + 1
        local need = stageUrgent and 1 or 3
        if idleTicks < need then return end
        idleTicks = need
        stageUrgent = false
        resetCd("main")
        resetCd("shaqi")
        stageNextWeapon("main")
        stageNextWeapon("shaqi")
    end)
    if not ok then return false end
    return false
end
pcall(function() LoopInGameThreadWithDelay(500, idleTicker) end)

resetWeaponState = function()
    cache.main = nil
    cache.shaqi = nil
    cursors.main = nil
    cursors.shaqi = nil
    pending.main = nil
    pending.shaqi = nil
    idleTicks = 0
    invWidget = nil
end

-- 找到某把武器对应的「切换武器技能」GA 实例（GA_Hun_<Weapon>_SWT_C），并通过技能系统激活
local gaDumped = {}
local ascDumped = false

local function dumpClassFns(obj, label)
    local names = {}
    pcall(function()
        local cls = obj:GetClass()
        cls:ForEachFunction(function(fn)
            local okf, f2 = pcall(function() return fn:GetFullName() end)
            if okf and f2 then
                local n = tostring(f2):match("([%w_]+)$")
                if n then names[#names + 1] = n end
            end
        end)
    end)
    table.sort(names)
    log("%s functions(%d): %s", label, #names, table.concat(names, ","))
    return names
end

local function findAsc()
    local out = nil
    for _, cls in ipairs({ "PBZAbilitySystemComponent", "AbilitySystemComponent" }) do
        local ok, list = pcall(FindAllOf, cls)
        if ok and type(list) == "table" and #list > 0 then
            out = { cls = cls, list = list }
            break
        end
    end
    return out
end

fireSwitchAbility = function(kind, id)
    if type(id) ~= "string" or id == "" then return end
    local found = nil
    for _, cls in ipairs({ "GA_Hun_" .. id .. "_SWT_C", "GA_" .. id .. "_SWT_C" }) do
        local okF, list = pcall(FindAllOf, cls)
        if okF and type(list) == "table" and #list > 0 then
            found = { cls = cls, ga = list[1], count = #list }
            break
        end
    end
    if not found then
        -- id 不一定等于资源名（如 RenOuQingTongJian 的配置是 Weapon_Hun_TianXuanQingTongJian），
        -- 改从当前手持武器对象上取名再拼 GA 类名
        local okC, comp = pcall(FindFirstOf, "CharacterWeaponsComponent")
        local names = {}
        if okC and comp then
            for _, g in ipairs({ "GetCurrentWeaponActorWeapon", "GetWeaponActorWeapon", "GetCurrentWeapon" }) do
                local okG, obj = pcall(function() return comp[g](comp) end)
                if okG and obj then
                    local okN, full = pcall(function() return obj:GetFullName() end)
                    if okN and full then
                        names[#names + 1] = tostring(full)
                        local w = tostring(full):match("Weapon_Hun_([%w_]+)")
                        if w then names[#names + 1] = "GA_Hun_" .. w .. "_SWT_C" end
                    end
                end
            end
        end
        log("ga[%s] no GA for id %s; hints: %s", kind, tostring(id), table.concat(names, " | "))
        for _, cls in ipairs(names) do
            if cls:sub(1, 3) == "GA_" then
                local okF, list = pcall(FindAllOf, cls)
                if okF and type(list) == "table" and #list > 0 then
                    found = { cls = cls, ga = list[1], count = #list }
                    log("ga[%s] resolved via hint -> %s", kind, cls)
                    break
                end
            end
        end
        if not found then return end
    end
    log("ga[%s] %s -> %d instance(s)", kind, found.cls, found.count)
    if not gaDumped[found.cls] then
        gaDumped[found.cls] = true
        dumpClassFns(found.ga, "ga[class]")
    end

    local asc = findAsc()
    if not asc then log("ga[%s] no ability system component found", kind); return end
    log("ga[%s] asc = %s (%d)", kind, asc.cls, #asc.list)
    if not ascDumped then
        ascDumped = true
        dumpClassFns(asc.list[1], "asc[class]")
    end

    local gaCls = nil
    pcall(function() gaCls = found.ga:GetClass() end)
    if not gaCls then log("ga[%s] no class on instance", kind); return end
    for i, comp in ipairs(asc.list) do
        local okA, res = pcall(function() return comp:TryActivateAbilityByClass(gaCls, true) end)
        log("ga[%s] asc#%d TryActivateAbilityByClass -> ok=%s res=%s", kind, i,
            tostring(okA), tostring(res))
        if okA then break end
    end
end

-- 侦察：武器相关对象上都有哪些函数（找“切换武器释放技能”的入口）
dumpWeaponApis = function()
    local okC, comp = pcall(FindFirstOf, "CharacterWeaponsComponent")
    if not okC or not comp then log("dump: no component"); return end
    local getters = { "GetCurrentWeapon", "GetCurrentWeaponActorWeapon", "GetWeaponActorWeapon",
                      "GetAbilityWeapon", "GetChangeWeaponAbilityWeapon", "GetChangeArmedAbilityWeapon" }
    for _, g in ipairs(getters) do
        local okG, obj = pcall(function() return comp[g](comp) end)
        if okG and obj then
            local names = {}
            pcall(function()
                obj:ForEachFunction(function(fn)
                    local okN, full = pcall(function() return fn:GetFullName() end)
                    if okN and full then
                        local name = tostring(full):match("([%w_]+)$")
                        if name then names[#names + 1] = name end
                    end
                end)
            end)
            table.sort(names)
            local okCls, clsName = pcall(function() return obj:GetClass():GetFullName() end)
            log("dump %s -> %s (%d fn): %s", g, tostring(okCls and clsName or "?"), #names,
                table.concat(names, ","))
        else
            log("dump %s -> failed (%s)", g, tostring(obj))
        end
    end
end

-- 一次性转储：把 CharacterWeaponsComponent 的函数名全打到日志里（找切换技能入口用）
ExecuteInGameThreadWithDelay(4000, function()
    pcall(function()
        local cls = StaticFindObject("/Script/SGameCombatSystem.CharacterWeaponsComponent")
        if not cls then log("dump: class not found"); return end
        local names = {}
        pcall(function()
            cls:ForEachFunction(function(fn)
                local okN, full = pcall(function() return fn:GetFullName() end)
                if okN and full then
                    local name = tostring(full):match("([%w_]+)$")
                    if name then names[#names + 1] = name end
                end
            end)
        end)
        table.sort(names)
        log("dump functions (%d): %s", #names, table.concat(names, ","))
    end)
end)

loadCfg()
log("loaded v" .. VERSION .. ": lang=%s (resolved when menu builds) main=%s shaqi=%s target=%s; F9 menu, F2 restore",
    Cfg.lang, Cfg.main.mode, Cfg.shaqi.mode, Cfg.target)

return { step = step, restore = restoreOriginal, cfg = Cfg }
