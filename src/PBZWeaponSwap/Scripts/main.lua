-- PBZWeaponSwap v4.5.12
-- 用游戏原生的换武器键驱动两套武器：
--   主武器   键盘 1 / 手柄十字键左   -> SetCurrentWeaponByIndex(idx, true)
--   影之武装 键盘 2 / 手柄十字键右   -> SetCurrentWeaponByIndex(idx, false)
-- 每套各自有 关闭 / 循环 / 随机 / 自定义池 四种模式，F9 打开菜单，首行选择要配置哪一套。
-- 4.5.0：重做菜单面板排版与状态行；武器列表按拼音排序、支持自定义池；
--        新增“武器切换冷却”开关（cd=1 保留游戏原生冷却，cd=0 由模组切换后立即清冷却）。
-- 4.5.1：修两处菜单问题——
--        1) 全选/取消全选的状态判断错了：空池（一个都没勾）被当成“已全选”，于是取消后
--           再也选不回来，按钮只能一直取消；
--        2) 菜单重建从按钮/下拉框回调里移出、合并成延迟单次重建，解决点“刷新武器列表”
--           或连续操作时 UE4SS 直接崩溃（重建会销毁正在派发事件的控件）。
-- 4.5.12：稳定性与开销优化（玩法不变）——
--        1) 切图后作废背挂网格组件缓存，不再对已销毁对象调 RefreshWeaponVisibility；
--        2) 预置逻辑复用已读到的槽位数组，每轮少一半反射调用；
--        3) 关掉逐帧槽位观察、ModMenu 追踪与函数转储（DEBUG_* 开关可开回），日志加 2 MB 轮转；
--        4) 移除从未调用的 findWeaponConfig（内部含 LoadAsset）与永远为假的列表变更检测；
--        5) F2 恢复整段屏蔽钩子，写槽不再可能被自己拦下。


local SRC = debug.getinfo(1, 'S').source:gsub('^@', '')
local DIR = SRC:match('^(.*[/\\])') or ''
local ROOT = DIR:gsub('Scripts[\\/]$', '')
local LOG_PATH = ROOT .. 'log.txt'
local CFG_PATH = ROOT .. 'config.txt'
local SNAP_PATH = ROOT .. 'snapshot.txt'
local DEBUG = true
local DEBUG_WATCH = false   -- 逐 tick 打印槽位变化（只在排查槽位问题时开）
local DEBUG_TRACE = false   -- 追踪 ModMenu 关闭流程的每一步（只在排查关闭崩溃时开）
local DUMP_FUNCS = false    -- 启动 4 秒后把 CharacterWeaponsComponent 的函数名打进日志
local VERSION = "4.5.12"

-- 日志轮转：>2 MB 就把旧日志转成 log.prev.txt（只留一份），避免长期游玩后无限增长
do
    local f = io.open(LOG_PATH, "rb")
    if f then
        local size = f:seek("end")
        f:close()
        if size and size > 2 * 1024 * 1024 then
            os.remove(ROOT .. "log.prev.txt")
            os.rename(LOG_PATH, ROOT .. "log.prev.txt")
        end
    end
end

-- random 模式用 math.random，不播种的话每次启动都是同一串顺序
pcall(math.randomseed, os.time())

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

local pyMissing = {}
local function pinyin(name)
    local out = {}
    for _, cp in utf8.codes(name) do
        local ch = utf8.char(cp)
        local py = PY[ch]
        if py == nil then
            py = ch
            -- 缺字的排序键会混进汉字（排在所有拼音之后），打到日志里方便补表
            if not pyMissing[ch] then
                pyMissing[ch] = true
                log("pinyin: no entry for %s, kept as-is", ch)
            end
        end
        out[#out + 1] = py
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
                    if v == "-" then
                        Cfg[kind].pool = {}   -- 落盘的“一个都不勾”：不能退化成“全部”
                    else
                        local pool = {}
                        for id in v:gmatch("[^,]+") do pool[id] = true end
                        Cfg[kind].pool = (next(pool) ~= nil) and pool or nil
                    end
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
            -- 空池写成 "-"：写成空值再读回来会被当成“全部武器”
            f:write(kind, ".pool=", (#ids > 0) and table.concat(ids, ",") or "-", "\n")
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

-- 以装备栏数组为准取当前武器：CurrentMainWeaponID 在切换后常有延迟，不能用于判断。
-- 已经读过槽位数组的调用方（预置 tick）走 curOfWith，省掉一次 equippedSlots 反射。
local function curOfWith(sub, kind, order, cnt)
    local def = T[kind]
    local okI, idx = pcall(def.curIdx, sub)
    -- pcall 失败时第二个返回值是错误字符串，不能让字符串冒充下标传给调用方
    if not (okI and type(idx) == "number") then idx = nil end
    if idx and idx >= 0 and idx < cnt and order[idx + 1] then
        return order[idx + 1], idx
    end
    local okD, id = pcall(def.curId, sub)
    return okD and S(id) or nil, idx
end

local function curOf(sub, kind)
    local _, order, cnt = equippedSlots(sub, kind)
    return curOfWith(sub, kind, order, cnt)
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

local function inPool(kind, id)
    local c = Cfg[kind]
    if c.pool == nil then return true end
    return c.pool[id] == true
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
local emptyPoolLogged = {}
local singleSlotWarned = {}
-- 已经预置到待切槽、但玩家还没按键的武器：避免随机模式下每个 tick 都换一把塞进去
local pending = { main = nil, shaqi = nil }
local pendingAt = { main = 0, shaqi = 0 }   -- 装填标记的写入时间（仅日志/诊断，不做超时作废）

local function pickNext(kind, sw, fromId)
    local c = Cfg[kind]
    local pool = poolFor(kind, sw)
    if #pool == 0 then
        if not emptyPoolLogged[kind] then
            emptyPoolLogged[kind] = true
            log("[%s] pool is empty: mod will not switch until something is ticked", kind)
        end
        return nil, pool
    end
    emptyPoolLogged[kind] = nil
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
    applyTarget(sub, kind, nextId, sw)
    -- 没换成功就别推进游标，否则下一把会被跳过
    local landed = curOf(sub, kind)
    cursors[kind] = (landed ~= nil and landed == nextId) and nextId or landed
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
        muteHook(1.0) -- 整段恢复期间屏蔽钩子：写槽本身不该被当成玩家按键
        for _, kind in ipairs(KINDS) do
            local s = snap[kind]
            if s and #s.list > 0 then
                -- 现场槽位可能比快照少（玩家在背包里卸过）：只写存在的格，
                -- 否则 ReplaceWeaponByIndex 会拿到越界下标
                local _, _, live = equippedSlots(sub, kind)
                for i = 1, math.min(#s.list, live) do
                    T[kind].replace(sub, s.list[i], i - 1)
                end
                muteHook(0.25)
                if live > 0 then
                    T[kind].setCur(sub, math.min(s.idx, live - 1))
                end
                log("restored %s: idx=%d [%s]", kind, s.idx, table.concat(s.list, ","))
            end
        end
        -- 槽位比快照多：多出来那格是模组换上去的，清空它会崩原生链，只能提示手动卸
        for _, kind in ipairs(KINDS) do
            local s = snap[kind]
            local _, _, live = equippedSlots(sub, kind)
            if s and #s.list > 0 and live > #s.list then
                log("restore[%s]: %d slots now but snapshot had %d, please unequip the extra one in the bag",
                    kind, live, #s.list)
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

-- 切图后这些组件随 World 一起销毁：对已销毁对象解析方法会硬崩，
-- 所以每次用之前先问引擎 IsValid，缓存里混进死对象就整批重收。
local function compAlive(c)
    if c == nil then return false end
    local okG, gv = pcall(function() return IsValid(c) end)
    if okG and type(gv) == "boolean" then return gv end
    return true
end

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
    local stale = false
    if backComps then
        for _, c in ipairs(backComps) do
            if not compAlive(c) then stale = true; break end
        end
    end
    if backComps == nil or stale then
        if stale then
            log("backprobe[%s]: cached components died (map change?), re-collecting", tag)
        end
        backComps, backProbeLogged, backSyncOff = nil, false, false
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
        if compAlive(c) then
            local okR, errR = pcall(function() c:RefreshWeaponVisibility() end)
            if okR then
                okN = okN + 1
            else
                errN = errR
            end
        end
    end
    if not backProbeLogged then
        backProbeLogged = true
        log("back-sync[%s]: component self-refresh ok=%d/%d err=%s", tag, okN, #backComps, tostring(errN))
        if okN == 0 then
            -- 组件上没有这个函数，改在组件所属的武器 actor 上试
            for _, c in ipairs(backComps) do
                if compAlive(c) then
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
end

local function onSetWeaponByIndex(ctx, idxParam, isNormalParam)
    if os.clock() < hookMuteUntil then return nil end
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

-- 4.x 里 getWeaponConfig 不是必需的：武器只按名字/id 写槽，
-- 当年留着的 findWeaponConfig（内部 LoadAsset）从没被调用过，已移除。

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
local menuStaleLogged = false
local funcRefreshWeapons = nil
local registerSections = nil
local requestRebuild = function() end   -- 由下方赋值：重建控件必须推迟到回调之外

-- 4.5.1：「一个都没勾」(pool = {}) 曾被当成「已全选」，所以取消全选后按钮再也选不回来
local function poolAllSelected(kind, items)
    local c = Cfg[kind]
    if c.pool == nil then return true end
    if next(c.pool) == nil then return false end
    for _, it in ipairs(items) do
        if not c.pool[it.id] then return false end
    end
    return true
end

-- 4.5.2：全选按钮绝不再逐个 ui.Set 去写 25 个 checkbox——连点时 SetIsChecked 会在
-- 点击事件还在派发的过程中改控件状态（并触发 InputMode.SetActive），实测直接崩。
-- 只改配置，然后延迟重建一次；重建后每个 checkbox 的默认值本来就从 Cfg 读。
-- 4.5.6：连点节流已去掉——目标状态是按当前配置算出来的（幂等），
-- 节流只会让玩家的点击被吞掉，表现为“连点没反应”。
-- 4.5.9：不再用“同步窗口”挡 onChange。已经改成按状态判断——回调给出的
-- 目标值和配置里已有的值相同，说明是程序性 SetIsChecked 引发的回声，直接忽略；
-- 不同则一定是玩家真点了。这样窗口期内的真实点击也不会被吞掉。

-- 池子变了：循环游标要重新按“手上这把”定位，预置的那把也要作废，
-- 并推迟到回调之外刷新一次界面——否则勾选/全选都要再点「刷新武器列表」才生效。
-- ModMenu 把每个控件的值缓存在 S.values 里，一旦有值就不再读 item.default；
-- 所以重建之前必须把 values 也按当前配置刷一遍，否则重建出来还是旧勾选。
local function syncPoolValues(kind)
    if not ui then return end
    local sub = getSub()
    if not sub then return end
    local sw = sortedWeapons(sub, kind)
    if not sw then return end
    local c = Cfg[kind]
    for _, it in ipairs(sw.items) do
        local on = (c.pool == nil) and true or (c.pool[it.id] == true)
        pcall(function() ui.Set('pool', kind .. '_' .. it.id, on) end)
    end
end

-- 4.5.10：池子的版本号。每次配置变动 +1，延迟同步只在“版本没再变过”时才落地，
-- 否则重新排一次——不然连点时后一次点击会被前一次排下的全量同步盖回旧状态，
-- 表现为“点了没反应”（同步写值与点击在同一帧里交错）。
local poolRev = { main = 0, shaqi = 0 }
local poolRefreshQueued = { main = false, shaqi = false }
local poolSyncSchedule        -- 前向声明（下面的闭包要递归调用自己）

poolSyncSchedule = function(kind, rev)
    if poolRefreshQueued[kind] then return end
    poolRefreshQueued[kind] = true
    ExecuteInGameThreadWithDelay(180, function()
        poolRefreshQueued[kind] = false
        if not funcRefreshWeapons then return end
        if rev ~= poolRev[kind] then
            -- 这段等待期间玩家又改过池子：这轮早已过期，按新版本重新排
            poolSyncSchedule(kind, poolRev[kind])
            return
        end
        pcall(syncPoolValues, kind)
        -- 只同步控件值与状态行，不重建整棵树：重建会让列表闪一下（4.5.6 的反馈）
        local open = false
        if ui then
            local ok, v = pcall(function() return ui.IsOpen() end)
            open = ok and v or false
        end
        if open then
            pcall(setStatusLabels)
        else
            menuStale = true          -- 菜单没开：下次打开时重建，免得显示旧勾选
        end
    end)
end

local function poolChanged(kind)
    pending[kind], pendingAt[kind] = nil, 0
    cursors[kind] = nil
    poolRev[kind] = (poolRev[kind] or 0) + 1
    poolSyncSchedule(kind, poolRev[kind])
end

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
            -- 目标状态永远与现状相反：allNow=true 就全不选，false 就全选。
            -- （4.5.7 曾在这里拿 (pool == nil) 和 allNow 比较，空池时两者都是 false，
            --  于是“取消全选”后再点被当成 already，永远回不到全选。）
            local on = not poolAllSelected(kind, sw.items)
            -- 注意不能写 `on and nil or {}`：on 为 true 时 `true and nil` 是 nil（假值），
            -- 会被 or 吃掉，结果永远赋成空表——第二次按就再也回不到全选。
            if on then
                cc.pool = nil
            else
                cc.pool = {}
            end
            poolChanged(kind)          -- 已预置的那把是按旧池子挑的，立刻作废
            saveCfg()
            log("[%s] pool all = %s (config now, widgets synced after the click)", kind, tostring(on))
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
                local was = (cc.pool == nil) and true or (cc.pool[it.id] == true)
                if was == (on == true) then
                    -- 程序性 SetIsChecked 引起的回声：值本来就一样，什么都不用做
                    return
                end
                if cc.pool == nil then
                    cc.pool = {}
                    for _, x in ipairs(sw.items) do cc.pool[x.id] = true end
                end
                cc.pool[it.id] = on and true or nil
                poolChanged(kind)      -- 池子变了，预置的那把不再属于池子
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
                  requestRebuild(80)   -- 池 section 的标题/内容跟着目标变，延迟重建
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
        { type = 'button', id = 'refresh', label = L("刷新武器列表（重建列表与状态）", "Refresh weapon list (rebuild list and status)"), onClick = function()
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

registerSections = function(sub, immediate)
    -- 默认只排队，不在调用者的回调里同步重建（见 requestRebuild 的注释）；
    -- 首次建菜单（tick 里，非 UI 回调）传 immediate=true 立刻注册。
    if immediate and ui then
        pcall(function()
            ui.Register({ id = 'swap', title = L('武器切换', 'Weapon Swap'),
                items = swapItems(), collapsible = false })
        end)
        pcall(function()
            ui.Register({ id = 'pool', title = L('自定义池 · ', 'Custom pool · ') .. labelOf(Cfg.target),
                items = poolItemsFor(sub, Cfg.target) })
        end)
        return
    end
    requestRebuild(60)
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

-- 4.5.1：重建菜单控件绝不能在按钮/下拉框回调里同步发生——ModMenu.Register 会立刻
-- 调 ExecuteInGameThread 重建整棵树，正在派发事件的那个控件被销毁，UE4SS 直接崩。
-- 这里统一推迟到回调之外，且同一时刻只排一次队；两个 section 之间再隔 120ms，
-- 避免同一帧里连做两次整树重建。
local rebuildQueued = false
requestRebuild = function(delay)
    if rebuildQueued then return end
    rebuildQueued = true
    ExecuteInGameThreadWithDelay(delay or 400, function()
        rebuildQueued = false
        if not ui then return end
        local okOpen, isOpen = pcall(function() return ui.IsOpen() end)
        if not (okOpen and isOpen) then
            menuStale = true                      -- 菜单没开：等下次打开再重建
            log('rebuild: menu closed, deferred to next open')
            return
        end
        local sub = getSub()
        if not sub then return end
        local ok1, err1 = pcall(function()
            ui.Register({ id = 'swap', title = L('武器切换', 'Weapon Swap'),
                items = swapItems(), collapsible = false })
        end)
        log('rebuild: swap section ok=%s err=%s', tostring(ok1), tostring(err1))
        ExecuteInGameThreadWithDelay(120, function()
            local ok2, err2 = pcall(function()
                local s2 = getSub()
                if not s2 then return end
                ui.Register({ id = 'pool', title = L('自定义池 · ', 'Custom pool · ') .. labelOf(Cfg.target),
                    items = poolItemsFor(s2, Cfg.target) })
            end)
            log('rebuild: pool section ok=%s err=%s', tostring(ok2), tostring(err2))
            pcall(setStatusLabels)
        end)
    end)
end


-- 4.x 下 GetAllNormalWeapons() 的返回形态不稳定（且 GetMainWeaponTableData 会崩），
-- 武器名单因此固定在内置 NAMES 里；下面只负责按当前配置重建缓存与控件。
local function refreshWeapons(force)
    local sub = getSub()
    if not sub then return end
    if force then
        cache.main = nil
        cache.shaqi = nil
        pending.main = nil
        pending.shaqi = nil
        for _, kind in ipairs(KINDS) do
            local sw = sortedWeapons(sub, kind)
            local c = Cfg[kind]
            if sw and c.pool then
                local removed = false
                for id in pairs(c.pool) do
                    if not indexOf(sw.ids, id) then
                        c.pool[id] = nil
                        removed = true
                    end
                end
                -- 空池是玩家明确的“一个都不勾”，不能当成没配置改回全选
                -- （4.5.4 起空池落盘为 `pool=-`，loadCfg 会读回空表）
                if removed then saveCfg() end
            end
        end
    end
    resolveLang()
    -- 面包屑：重建菜单控件是最容易硬崩的一步，崩了就只会停在这两行之间
    log('refresh: request deferred rebuild ...')
    requestRebuild(80)
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

    registerSections(sub, true)
    setStatusLabels()

    local function refresh()
        local ok, err = pcall(function()
            local sub2 = getSub()
            if not sub2 then return end
            if menuStale then
                menuStale = false
                menuStaleLogged = false
                pcall(refreshWeapons, true)
                return
            end
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
    if DEBUG_TRACE then
        traceFn("PBZWSMenu.shell.confirm", "Hide", "Confirm.Hide")
        traceFn("PBZWSMenu.core.input", "ClearClickState", "Input.ClearClickState")
        traceFn("PBZWSMenu.widgets.dropdown", "collapseAll", "Dropdown.collapseAll")
        traceFn("PBZWSMenu.core.cursor", "Hide", "Cursor.Hide")
        traceFn("PBZWSMenu.core.inputmode", "SetActive", "InputMode.SetActive")
    end

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
    if not DEBUG_WATCH then return end
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
            if DEBUG_WATCH then pcall(slotWatch) end
            if not menuBuilt then buildMenu(sub) end
            if menuStale and not menuStaleLogged then
                menuStaleLogged = true
                log("menu data stale: rebuild on next open")
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
    local curId, curIdx = curOfWith(sub, kind, order, cnt)
    -- 手里是空槽（玩家在背包里卸下了武器）：没有“当前武器”这个概念，
    -- 从池子的第一把开始装填，而不是沿用那个空 id。
    if curId ~= nil and isBlankId(tostring(curId)) then curId = nil end
    if cursors[kind] == nil or isBlankId(tostring(cursors[kind])) then cursors[kind] = curId end
    -- 上一把预置的武器：已经拿到手上就作废标记；被挤掉也作废；
    -- 仍在另一格时——空手就立刻把那一格设为当前（玩家卸了武器，不能干等按键），
    -- 有武器在手就继续等玩家按切换键（只刷新时间戳，绝不清标记，否则死循环）。
    local p = pending[kind]
    if p and not inPool(kind, p) then
        log("stage[%s] pending %s dropped (no longer in pool)", kind, tostring(p))
        pending[kind], pendingAt[kind] = nil, 0
        p = nil
    end
    if p then
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
    -- 只有一格时，“预置下一把”等于把手上的武器在数据层静默替换掉（没有切换动画，
    -- 玩家手里会突然变成另一把）。这种情况宁可不预置，等玩家按键走 applyTarget。
    if cnt < 2 and curId ~= nil then
        if not singleSlotWarned[kind] then
            singleSlotWarned[kind] = true
            log("stage[%s]: only %d slot, skip staging (would overwrite the held weapon)", kind, cnt)
        end
        return
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
    pendingAt.main = 0
    pendingAt.shaqi = 0
    idleTicks = 0
    invWidget = nil
    -- 下面这些缓存指向旧 World 的对象：背挂组件会随世界销毁，
    -- 留着它们等于下次切换时对野指针反射（崩溃点就在 RefreshWeaponVisibility）
    backComps = nil
    backProbeLogged = false
    backSyncOff = false
    watchPrev = {}
    cdResetLogged = false
    emptyPoolLogged = {}
    singleSlotWarned = {}
end

-- 一次性转储：把 CharacterWeaponsComponent 的函数名全打到日志里（找切换技能入口用）
if DUMP_FUNCS then
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
end

loadCfg()
log("loaded v" .. VERSION .. ": lang=%s (resolved when menu builds) main=%s shaqi=%s target=%s; F9 menu, F2 restore",
    Cfg.lang, Cfg.main.mode, Cfg.shaqi.mode, Cfg.target)

return { step = step, restore = restoreOriginal, cfg = Cfg }
