# PBZWeaponSwap 交接说明（4.8.0）

## 一、这是什么东西

《影之刃零》（Phantom Blade Zero，Steam appid 4115450，UE5.7）的 UE4SS Lua 模组，做「按键切换武器」+「暂停选武器」。

- 引擎注入：UE4SS 4.0.0 PreRelease #1（git ac877679），装在 `D:\steam\steamapps\common\PBZ\platform\steam\`（`dwmapi.dll` + `ue4ss\`）。
- 模组目录：`D:\steam\steamapps\common\PBZ\platform\steam\ue4ss\Mods\PBZWeaponSwap\`
  - `Scripts\main.lua`（105,936 B，VERSION="4.8.0"，第 14 行）
  - `Scripts\pickpanel.lua`（13,928 B，居中弹窗，手搓 UMG）
  - `Scripts\vendor\ModMenu.lua`（243,071 B，F9 设置菜单框架，不要改）
  - `Scripts\vendor\UEHelpers.lua`（9,962 B）
  - `config.txt`：`version / lang / target / cd / main.mode / shaqi.mode`
  - `log.txt`：模组自己写的日志（**排查全靠它**，UE4SS.log 会被多模组截断）
- 仓库副本（改完要同步）：`D:\Projects\pbz-weapon-swap\src\PBZWeaponSwap\Scripts\`
- 发行包输出：`D:\Projects\pbz-weapon-swap\dist\PBZWeaponSwap-4.8.0.zip`
- 开关：`ue4ss\Mods\mods.txt` 里 `PBZWeaponSwap : 1`（4.0.0 的 mods.txt 只剩注释行，条目要手写回来）。

## 二、热键

- **F9** 设置菜单；**F2** 还原原版武器
- **1 / 2** 主武器 / 影之武装切换（自选模式下按它就是弹面板）
- F5 训练木桩、F6/F7/F8 篝火重生（别的 mod 占的，不要抢）
- ESC 关面板/关菜单

## 三、游戏侧 API 实测结论（血泪，别再猜）

`PBZBackPackSubsystem`（背包子系统）：
- `MainWeapons: TArray<FName>`、`CurrentWeaponIndex: int`、`ShaqiWeapons`
- `SetCurrentWeaponByIndex(idx:number, isNormal:bool)` —— **true=主武器，false=影之武装**；这是唯一能真正触发完整切换链（含技能）的入口
- `ReplaceWeaponByIndex(FName, slot)` —— 往槽里写武器；**目标槽为空时不生成武器实例**，人会空手
- `GetAllNormalWeapons()` → 25 把（玩家全都有，别做“未拥有”过滤）
- `RemoveWeaponByID(FName, bool)` —— **bool=true 会把武器从存档里真正删掉**，已在 9.5.0 永久禁用
- `ReplaceWeapon / ClearWeapon / DisposeWeapon` 等：名字看着能用，实际多半是属性不是函数

`CharacterWeaponsComponent`（角色武器组件，`FindFirstOf("CharacterWeaponsComponent")`）：
- `SetSlotWeapon(SlotTag: FGameplayTag, slotIndex: number, weaponStruct)` —— 游戏自己脱/装装备走的就是这条
- `SetCurrentWeapon(SlotTag, slot)`、`SetArmed(SlotTag, bool)`、`AutoSetCurrentWeapon(SlotTag)`
- `IsInWeaponTransition()`、`ResetChangeWeaponCooldowns()`、`StartChangeWeaponCooldown`

槽位 Tag（FGameplayTag 结构体，Lua 里**手搓 table 必崩**）：
`Weapon.Slot.Main` / `Weapon.Slot.Shachi` / `Weapon.Slot.Item1` / `Item2` / `Interact`

拿到 Tag 的唯一办法：**钩游戏自己的调用把结构体截下来**（现在是 `captureTag()`，钩 `GetSlotWeapon`/`SetArmed`/`SetSlotWeapon`，存 `tagMain`/`tagShachi`）。空武器结构体同理（`emptyWeaponStruct`，钩 `SetSlotWeapon` 时 `TagName` 为空的那种）。

武器配置：`PBZ_MainWeaponConfig_C`，用 `FindAllOf("PBZ_MainWeaponConfig_C")` 按名字找（中文资源名≠id），找不到就用 `LoadAsset("/PBZCombatAsset/ActorData/Players/Hun/Weapon/<id>/Weapon_Hun_<id>.Weapon_Hun_<id>")` 兜底；**LoadAsset 只能在游戏线程调**（按键回调里调会报 `can only be called from within the game thread`，要包 `ExecuteInGameThreadWithDelay(1, ...)`）。

切换技能：每把武器一个 `GA_Hun_<资源名>_SWT_C`，由游戏在原生切换链里自己激活；模组里硬激活是空转（不在 ASC 的 ActivatableAbilities 里）。

## 四、用户要的功能（原话）

1. 自选模式（pick）：按 1/2 时**先弹居中面板**（每行 5 个、带图标占位），玩家选一把，然后人真的换上这把并放切换技能。
2. **单槽设计（用户死守，不许废掉）**：平时只留手上这一把，另一格空。
3. 打开背包时自动关掉模组菜单 / 面板。
4. cd 开关（`关闭武器切换cd`，默认不勾选 = 保留原生冷却）。

## 五、当前状态（4.8.0）

已经能跑通的：
- 面板能弹出、能点（`pickpanel: tile clicked <id>` → `pick: clicked <id>`）
- 截 Tag / 截空结构体、`SetSlotWeapon` 清槽、`SetCurrentWeaponByIndex` 原生切换，这三步单独验证都成功（见 log.txt 里 `full: clear slot 0 -> ok=true` / `full: SetSlotWeapon(...) ok=true` / `full: native SetCurrentWeaponByIndex(...) ok=true`）
- 单槽改成“卸下”（`SetSlotWeapon(tag, 槽, 空结构体)`），武器回背包不删档

**上一版每次点击都失败的根因**：`fullSwitch` 用 `local function` 定义在 `chooseWeapon` 之后，Lua 词法作用域把它解析成全局 nil → `ERR choose(...): attempt to call a nil value (global 'fullSwitch')`。4.8.0 已加前向声明 `local fullSwitch = nil`（第 396 行）+ 改为赋值定义（第 1105 行）。**这一处还没在游戏里验证过。**

## 六、踩过的坑（别重复）

- Lua 局部函数**必须先声明后使用**，这个坑已经踩了 5 次（normCmode / openPick / pickItems / equipById / fullSwitch）。改完 grep 一遍“在定义之前被调用”的 local function。
- `RegisterKeyBind` 返回 nil，不能写 `pcall(RegisterKeyBind(...))`，要 `pcall(function() RegisterKeyBind(...) end)`。
- 不要用 `pcall` 兜结构体调用：参数类型不对是硬 fault，游戏直接闪退，pcall 抓不住、不生成 dump。
- 不要在 mod 加载阶段跑 `GenerateLuaTypes()` / `ForEachFunction` / `GetPropertyNames()`：4.0.0 下会硬崩。
- 别拿 `sub:GetAllNormalWeapons()` 的结果去拼 `LoadAsset` 路径当真理，中文资源名和 id 对不上。
- 改完必须 `python -c "from luaparser import ast;ast.parse(open('main.lua',encoding='utf-8').read())"` 验语法（本机没有 lua 解释器；`pip install lupa` 也能跑但中文路径会报错）。
- 用户不喜欢被擅自改需求（单槽那套是他调了一晚上的），改动方向先照他说的做。

## 七、下一步建议

1. 进游戏 → 切“自选” → 按 1 → 点一把武器，看 `log.txt` 是否出现 `pick[main] fullSwitch -> <id> slot <n>`，以及随后 `slot 0/1` 的实际内容、人手上有没有武器、有没有放技能。
2. 若 `fullSwitch` 内部报错，按日志里的行号继续修（它是唯一还带不确定性的环节）。
3. 稳定后再把 `main.mode`/`shaqi.mode` 的默认值、README 版本历史一起更新，最后才谈发布（用户明确说暂不发 GitHub，Nexus 他自己传）。
