#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""4.5.5 -> 4.5.12 稳定性/开销优化补丁（玩法行为不变）。

每处替换都断言唯一命中，任何一处没匹配上就整体失败、不写文件。
用法：python tools/patch_4512.py [--check]
"""
import sys
from pathlib import Path

SRC = Path(__file__).resolve().parent.parent / "src" / "PBZWeaponSwap" / "Scripts" / "main.lua"

# (说明, 旧文本, 新文本)
PATCHES = []


def add(name, old, new):
    PATCHES.append((name, old, new))


# ── 1. 头部版本与更新说明 ────────────────────────────────────────────
add("header-version", "-- PBZWeaponSwap v4.5.5\n", "-- PBZWeaponSwap v4.5.12\n")

add(
    "header-notes",
    """--        2) 菜单重建从按钮/下拉框回调里移出、合并成延迟单次重建，解决点“刷新武器列表”
--           或连续操作时 UE4SS 直接崩溃（重建会销毁正在派发事件的控件）。
""",
    """--        2) 菜单重建从按钮/下拉框回调里移出、合并成延迟单次重建，解决点“刷新武器列表”
--           或连续操作时 UE4SS 直接崩溃（重建会销毁正在派发事件的控件）。
-- 4.5.12：稳定性与开销优化（玩法不变）——
--        1) 切图后作废背挂网格组件缓存，不再对已销毁对象调 RefreshWeaponVisibility；
--        2) 预置逻辑复用已读到的槽位数组，每轮少一半反射调用；
--        3) 关掉逐帧槽位观察、ModMenu 追踪与函数转储（DEBUG_* 开关可开回），日志加 2 MB 轮转；
--        4) 移除从未调用的 findWeaponConfig（内部含 LoadAsset）与永远为假的列表变更检测；
--        5) F2 恢复整段屏蔽钩子，写槽不再可能被自己拦下。
""",
)

# ── 2. 调试开关 + 日志轮转 ──────────────────────────────────────────
add(
    "debug-flags",
    """local DEBUG = true
local VERSION = "4.5.5"

-- random 模式用 math.random，不播种的话每次启动都是同一串顺序
""",
    """local DEBUG = true
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
""",
)

# ── 3. 拼音缺字打日志 ────────────────────────────────────────────────
add(
    "pinyin-missing",
    """local function pinyin(name)
    local out = {}
    for _, cp in utf8.codes(name) do
        local ch = utf8.char(cp)
        out[#out + 1] = PY[ch] or ch
    end
    return table.concat(out, "")
end
""",
    """local pyMissing = {}
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
""",
)

# ── 4. curOf 拆成可复用数组的版本 ────────────────────────────────────
add(
    "curOf-split",
    """-- 以装备栏数组为准取当前武器：CurrentMainWeaponID 在切换后常有延迟，不能用于判断
local function curOf(sub, kind)
    local def = T[kind]
    local _, order, cnt = equippedSlots(sub, kind)
    local okI, idx = pcall(def.curIdx, sub)
""",
    """-- 以装备栏数组为准取当前武器：CurrentMainWeaponID 在切换后常有延迟，不能用于判断。
-- 已经读过槽位数组的调用方（预置 tick）走 curOfWith，省掉一次 equippedSlots 反射。
local function curOfWith(sub, kind, order, cnt)
    local def = T[kind]
    local okI, idx = pcall(def.curIdx, sub)
""",
)

add(
    "curOf-wrapper",
    """    local okD, id = pcall(def.curId, sub)
    return okD and S(id) or nil, idx
end

-- 武器 ID → 游戏内中文显示名""",
    """    local okD, id = pcall(def.curId, sub)
    return okD and S(id) or nil, idx
end

local function curOf(sub, kind)
    local _, order, cnt = equippedSlots(sub, kind)
    return curOfWith(sub, kind, order, cnt)
end

-- 武器 ID → 游戏内中文显示名""",
)

# ── 5. pendingAt 注释与未使用的 age ─────────────────────────────────
add(
    "pending-comment",
    'local pendingAt = { main = 0, shaqi = 0 }   -- 4.8.9：装填标记的写入时间，超时自动作废\n',
    'local pendingAt = { main = 0, shaqi = 0 }   -- 装填标记的写入时间（仅日志/诊断，不做超时作废）\n',
)

add(
    "pending-age",
    """    if p then
        local age = os.clock() - (pendingAt[kind] or 0)
        if p == curId then
""",
    """    if p then
        if p == curId then
""",
)

# ── 6. 背挂组件：存活校验 + 失效重收 ───────────────────────────────
add(
    "compAlive",
    """local backComps = nil
local backProbeLogged = false
local backSyncOff = false

local function collectWeaponComps()
""",
    """local backComps = nil
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
""",
)

add(
    "backSync-revalidate",
    """    if backComps == nil then
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
""",
    """    local stale = false
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
""",
)

add(
    "backSync-owner-loop",
    """            for _, c in ipairs(backComps) do
                local own = nil
                pcall(function() own = c:GetOwner() end)
                if own then
                    local okA, errA = pcall(function() own:RefreshWeaponVisibility() end)
                    log("back-sync[%s]: owner-refresh %s -> ok=%s err=%s", tag, tostring(own), tostring(okA), tostring(errA))
                    if okA then break end
                end
            end
""",
    """            for _, c in ipairs(backComps) do
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
""",
)

# ── 7. F2 恢复整段屏蔽钩子 ──────────────────────────────────────────
add(
    "restore-mute",
    """    busy = true
    local ok, err = pcall(function()
        for _, kind in ipairs(KINDS) do
            local s = snap[kind]
""",
    """    busy = true
    local ok, err = pcall(function()
        muteHook(1.0) -- 整段恢复期间屏蔽钩子：写槽本身不该被当成玩家按键
        for _, kind in ipairs(KINDS) do
            local s = snap[kind]
""",
)

# ── 8. 预置逻辑复用已读数组 ─────────────────────────────────────────
add(
    "stage-reuse-slots",
    """    local slots, order, cnt = equippedSlots(sub, kind)
    if cnt < 1 then return end
    local curId, curIdx = curOf(sub, kind)
""",
    """    local slots, order, cnt = equippedSlots(sub, kind)
    if cnt < 1 then return end
    local curId, curIdx = curOfWith(sub, kind, order, cnt)
""",
)

# ── 9. 调试项：槽位观察 / 追踪 / 函数转储 ───────────────────────────
add(
    "slotWatch-gate",
    """local function slotWatch()
    for _, kind in ipairs({ "main", "shaqi" }) do
""",
    """local function slotWatch()
    if not DEBUG_WATCH then return end
    for _, kind in ipairs({ "main", "shaqi" }) do
""",
)

add(
    "tick-gate",
    """            pcall(slotWatch)
""",
    """            if DEBUG_WATCH then pcall(slotWatch) end
""",
)

add(
    "trace-gate",
    """    traceFn("PBZWSMenu.shell.confirm", "Hide", "Confirm.Hide")
    traceFn("PBZWSMenu.core.input", "ClearClickState", "Input.ClearClickState")
    traceFn("PBZWSMenu.widgets.dropdown", "collapseAll", "Dropdown.collapseAll")
    traceFn("PBZWSMenu.core.cursor", "Hide", "Cursor.Hide")
    traceFn("PBZWSMenu.core.inputmode", "SetActive", "InputMode.SetActive")
""",
    """    if DEBUG_TRACE then
        traceFn("PBZWSMenu.shell.confirm", "Hide", "Confirm.Hide")
        traceFn("PBZWSMenu.core.input", "ClearClickState", "Input.ClearClickState")
        traceFn("PBZWSMenu.widgets.dropdown", "collapseAll", "Dropdown.collapseAll")
        traceFn("PBZWSMenu.core.cursor", "Hide", "Cursor.Hide")
        traceFn("PBZWSMenu.core.inputmode", "SetActive", "InputMode.SetActive")
    end
""",
)

# ── 10. 刷新按钮文案：说的是它真正做的事 ────────────────────────────
add(
    "refresh-label",
    """label = L("刷新武器列表（加入新获得的武器）", "Refresh weapon list (pick up newly acquired)")""",
    """label = L("刷新武器列表（重建列表与状态）", "Refresh weapon list (rebuild list and status)")""",
)


def cut_between(text, start_marker, end_marker, replacement, name):
    """删掉 [start_marker, end_marker) 之间的整块，换成 replacement。"""
    i = text.find(start_marker)
    if i < 0:
        raise SystemExit("[FAIL] %s: start marker not found" % name)
    if text.find(start_marker, i + 1) >= 0:
        raise SystemExit("[FAIL] %s: start marker not unique" % name)
    j = text.find(end_marker, i)
    if j < 0:
        raise SystemExit("[FAIL] %s: end marker not found" % name)
    return text[:i] + replacement + text[j:]


def main():
    # 用字节读写，避免 Windows 文本模式把 LF 全换成 CRLF（会让整份文件出现在 diff 里）
    text = SRC.read_bytes().decode("utf-8")
    before_lines = text.count("\n")

    for name, old, new in PATCHES:
        n = text.count(old)
        if n != 1:
            raise SystemExit("[FAIL] %s: expected 1 match, found %d" % (name, n))
        text = text.replace(old, new, 1)
        print("[ok] %s" % name)

    # 整块删除：从未被调用的 findWeaponConfig（内部会 LoadAsset，加载期风险）
    text = cut_between(
        text,
        "local cfgDiagDone = false\n",
        "\n-- ── F9 菜单",
        "-- 4.x 里 getWeaponConfig 不是必需的：武器只按名字/id 写槽，\n"
        "-- 当年留着的 findWeaponConfig（内部 LoadAsset）从没被调用过，已移除。\n",
        "drop-findWeaponConfig",
    )
    print("[ok] drop-findWeaponConfig")

    # 整块删除：weaponCount / listChanged（数的是内置表，永远判不出变化）
    text = cut_between(
        text,
        "-- 4.x 下 GetAllNormalWeapons() 的返回形态不稳定",
        "local function refreshWeapons(force)",
        "-- 4.x 下 GetAllNormalWeapons() 的返回形态不稳定（且 GetMainWeaponTableData 会崩），\n"
        "-- 武器名单因此固定在内置 NAMES 里；下面只负责按当前配置重建缓存与控件。\n"
        "local function refreshWeapons(force)",
        "drop-weaponCount",
    )
    print("[ok] drop-weaponCount")

    text = text.replace(
        "    if force or listChanged(sub) then\n",
        "    if force then\n",
        1,
    )
    text = text.replace(
        "            if listChanged(sub2) then pcall(refreshWeapons, false) end\n",
        "",
        1,
    )
    if "listChanged" in text or "weaponCount" in text:
        raise SystemExit("[FAIL] leftover reference to listChanged/weaponCount")

    # 整块删除：启动 4 秒后的 ForEachFunction 转储，改成受 DUMP_FUNCS 控制
    i = text.find("ExecuteInGameThreadWithDelay(4000, function()")
    if i < 0:
        raise SystemExit("[FAIL] dump block not found")
    j = text.find("loadCfg()", i)
    if j < 0:
        raise SystemExit("[FAIL] dump block end not found")
    block = text[i:j]
    indented = "".join(("    " + ln if ln.strip() else ln) for ln in block.splitlines(True))
    text = text[:i] + "if DUMP_FUNCS then\n" + indented.rstrip("\n") + "\nend\n\n" + text[j:]
    print("[ok] dump-gate")

    # 切图后清掉所有指向旧 World 的缓存
    text = text.replace(
        """    idleTicks = 0
    invWidget = nil
end
""",
        """    idleTicks = 0
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
""",
        1,
    )
    if "backSyncOff = false\n    watchPrev = {}" not in text:
        raise SystemExit("[FAIL] resetWeaponState not patched")

    SRC.write_bytes(text.encode("utf-8"))
    print("\nsaved %s (%d -> %d lines, %d bytes)" % (
        SRC, before_lines, text.count("\n"), len(text.encode("utf-8"))))


if __name__ == "__main__":
    main()
