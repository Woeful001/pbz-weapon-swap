# PBZ Weapon Swap

《影之刃零》(Phantom Blade Zero) 的 UE4SS Lua 模组：把游戏**原生的切换键**（键盘 `1` / `2`、手柄十字键）改成「按拼音顺序换上武器池里的下一把」。
<img width="1604" height="947" alt="c4474755910aa3370900f0fb3305904f" src="https://github.com/user-attachments/assets/1cf15270-11c5-4947-b439-220f83842a1c" />
- **两套武器都能管**：主武器（原生 `1` / 十字键左）、影之武装（原生 `2` / 十字键右），各自独立开关与武器池
- 一次按键 = 一次切换：原生换武器动作（含配套的换武器技能）完整播放，不是「先切一把再补一刀」
- 四种模式：关闭 / 循环 / 随机 / 自定义，`F9` 打开设置菜单，**首行选改哪一套**，下面才是它自己的模式与勾选池
- 排序取游戏数据表里的中文武器名，按完整拼音升序（首字母分组，组内按全拼），可循环
- 目标武器在副手 → 直接与主手交换；不在装备栏 → 自动换装进副手槽再切过去
- 改的是数据层槽位，不经过技能/输入判定，因此不受入战状态影响

## 安装

前置：已安装 [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS)（本模组在 UE4SS v3.0.1 Beta 上开发验证）。

1. 把 `PBZWeaponSwap` 整个文件夹放进：

   ```
   <游戏目录>\platform\steam\ue4ss\Mods\
   ```

2. 编辑同目录下的 `mods.txt`，在 `Keybinds : 1` 之前加一行：

   ```
   PBZWeaponSwap : 1
   ```

3. 启动游戏，进存档即可使用。

也可以直接运行 `install.ps1`（自动复制并写入 `mods.txt`，带备份）：

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

## 热键

| 按键 | 作用 |
| --- | --- |
| `1` / 手柄十字键左（原生切换键） | 切换主武器，绑定未改动 |
| `2` / 手柄十字键右（原生切换键） | 切换影之武装，绑定未改动 |
| `F9` | 打开设置菜单（选目标 → 模式 → 自定义池） |
| `F2` | 恢复首次使用模组时记录下的原始装备 |

## 菜单（F9）

```
目标        主武器 / 影之武装          ← 首行，决定下面这些设置在改谁
模式        关闭 / 循环 / 随机 / 自定义
自定义随机  仅自定义模式生效
恢复原始装备
自定义池    （当前目标那一套的武器，逐个勾选）
```

| 模式 | 行为 |
| --- | --- |
| 关闭 | 该套武器完全不干预，恢复原版两把互换的手感 |
| 循环 | 按拼音顺序在全部已拥有武器里轮换，最后一把之后回到第一把 |
| 随机 | 每次随机换到另一把（不会连着换到同一把） |
| 自定义 | 只在勾选的武器里轮换；「自定义随机」勾上后走随机 |

两套各自保存，切换目标时菜单里的模式与勾选会跟着换，切回去还是原来的设定。
设置保存在 `Mods/PBZWeaponSwap/config.txt`，下次进游戏自动读回。
先前版本的 `mode=` / `random=` / `pool=` 会被当作主武器的设置读入。

## 排序结果

主武器（25 把）：

```
白蟒赤练 → 白山风雷剑 → 白影 → 别离残钩 → 残钢刃 → 长形黑伤 → 痴者残剑
→ 刺骨混沌 → 荡寇凶刃 → 断肢锯 → 黑伤 → 黑伤双刃 → 红妆鬼斩 → 灵蛇软剑
→ 乱莺剑 → 木制黑伤 → 破军 → 圣母邪扇 → 天煞双钺 → 天玄青铜剑 → 亡命斩马刀
→ 偃月刀 → 妖锯 → 玉双环 → 紫冥剑 → 回到起点
```

影之武装（24 把）：

```
操偶铃铛 → 长柄金瓜 → 催心琵琶 → 独眼弓 → 黄金火铳 → 火流星 → 虎炮
→ 剑客召集令 → 巨凶斧 → 苦叶寺珠串 → 雷霆枪 → 烈焰狮头 → 妙手飞刀
→ 墨血无痕 → 泥头车 → 贪狼 → 铁拳套 → 血滴子 → 虚空华扇 → 游龙叉
→ 游龙头 → 羽弓 → 追命锁镰 → 拙壁盾 → 回到起点
```

## 实现要点

游戏把装备信息放在 `UPBZBackPackSubsystem`（WorldSubsystem）里，两套武器结构对称：

| 用途 | 主武器 | 影之武装 |
| --- | --- | --- |
| 已装备（0 基两槽） | `MainWeapons` | `ShaqiWeapons` |
| 当前槽索引 | `CurrentWeaponIndex` | `CurrentShaqiWeaponIndex` |
| 全部武器 | `GetAllNormalWeapons()` | `GetAllShaqiWeapons()` |
| 数据表 | `GetMainWeaponTableData(id)` | `GetShaqiWeaponTableData(id)` |
| 改写槽位 | `ReplaceWeaponByIndex(name, slot)` | `ReplaceShaqiWeaponByIndex(name, slot)` |
| 切换 | `SetCurrentWeaponByIndex(idx, true)` | `SetCurrentWeaponByIndex(idx, false)` |

中文显示名统一走 `GetXxxTableData(id).WeaponName.ValueCache:ToString()`。

切换流程：

1. `RegisterHook('/Script/ProjectPBZ.PBZBackPackSubsystem:SetCurrentWeaponByIndex', ...)`：
   游戏按原生键时必然调用它，参数是「要切到的那个槽」+ `IsNormalWeapon`（`true` 主武器 / `false` 影之武装）；
2. 命中时不取消原生调用，而是保证那个槽里就是「下一把目标武器」
   （`ReplaceWeaponByIndex(目标, 槽位)`），让原生这一次切换直接把新武器拿到手上；
3. 平时（距上次切换 ≥1.5 秒、且不在换武器过场中）后台就把下一把预置到副手槽，
   按键时槽里已是目标武器，动作完全不被插入打断；预置过的那把在玩家按键前不会被换掉；
4. 循环位置用模组自己的游标，不依赖切换后有延迟的 `CurrentWeaponIndex`，
   因此不会卡在同一把或在小范围里打转；随机模式下预置的那一把就是这次的结果。

## 第三方库

`Scripts/vendor/` 下为第三方 MIT 代码，仅为菜单 UI 与取玩家控制器服务：

- `ModMenu.lua` — [mattdavida/ue4ss-ModMenu](https://github.com/mattdavida/ue4ss-ModMenu)（MIT）
- `UEHelpers.lua` — UE4SS 社区版 UEHelpers（MIT）

## 注意

- 该模组会**改写存档里的武器槽**（不是临时效果）。长时间使用，装备栏会随循环变化，`F2` 可一次性还原到第一次使用时的状态。
- 快照文件 `Mods/PBZWeaponSwap/snapshot.txt`，删掉它会在下次使用时重新记录当前装备。
- 日志 `Mods/PBZWeaponSwap/log.txt`，关闭方式：把 `Scripts/main.lua` 顶部的 `DEBUG` 改成 `false`。
- 只在单机存档上验证过；联机 / 存档损坏风险自负。

## License

MIT
