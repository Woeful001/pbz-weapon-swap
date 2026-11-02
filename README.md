# PBZ Weapon Swap

《影之刃零》(Phantom Blade Zero) 的 UE4SS Lua 模组：用 `<` / `>` 按**武器中文名拼音顺序**循环切换主武器。

- 排序取游戏数据表里的中文武器名，按完整拼音升序（首字母分组，组内按全拼）
- 可循环：走到最后一把再按一次回到第一把
- 目标武器在副手 → 直接与主手交换；不在装备栏 → 自动换装进副手槽再切过去
- 不用技能 / 输入链路，切换前重置武器切换冷却，因此不受入战状态影响

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
| `<`（`,` 键 / OEM_COMMA） | 上一把 |
| `>`（`.` 键 / OEM_PERIOD） | 下一把 |
| `F2` | 恢复首次使用模组时记录下的原始装备 |
| `F11` | 自检：连续 26 次「下一把」，日志里可看是否遍历全武器 |
| `F12` | 把当前排序表写进 `log.txt` |

## 排序结果（当前 25 把）

```
白蟒赤练 → 白山风雷剑 → 白影 → 别离残钩 → 残钢刃 → 长形黑伤 → 痴者残剑
→ 刺骨混沌 → 荡寇凶刃 → 断肢锯 → 黑伤 → 黑伤双刃 → 红妆鬼斩 → 灵蛇软剑
→ 乱莺剑 → 木制黑伤 → 破军 → 圣母邪扇 → 天煞双钺 → 天玄青铜剑 → 亡命斩马刀
→ 偃月刀 → 妖锯 → 玉双环 → 紫冥剑 → 回到起点
```

## 实现要点

游戏把装备信息放在 `UPBZBackPackSubsystem`（WorldSubsystem）里：

- `MainWeapons: TArray<FName>` — 已装备的主武器（两个槽，**索引 0 基**）
- `CurrentWeaponIndex` / `CurrentMainWeaponID` — 当前主手
- `GetAllNormalWeapons()` — 全部主武器 ID
- `GetMainWeaponTableData(id).WeaponName.ValueCache` — 中文显示名
- `ReplaceWeaponByIndex(NewWeaponName, ReplaceIndex)` — 改写指定槽
- `SetCurrentWeaponByIndex(WeaponIndex, IsNormalWeapon)` — 切到指定槽

切换流程：

1. 用 `CurrentMainWeaponID` 在排序表里定位，取前一/后一项；
2. 目标已在某个槽 → `SetCurrentWeaponByIndex(该槽)`（即主副手交换）；
3. 目标不在装备栏 → `ReplaceWeaponByIndex(目标, 非当前槽)` 再切过去，
   上一把自然退到副手，往回按可立刻切回；
4. 切换前调用 `CharacterWeaponsComponent:ResetChangeWeaponCooldowns()`。

## 注意

- 该模组会**改写存档里的两个主武器槽**（不是临时效果）。长时间使用，装备栏会随循环变化，`F2` 可一次性还原到第一次使用时的状态。
- 快照文件 `Mods/PBZWeaponSwap/snapshot.txt`，删掉它会在下次按键时重新记录当前装备。
- 日志 `Mods/PBZWeaponSwap/log.txt`，关闭方式：把 `Scripts/main.lua` 顶部的 `DEBUG` 改成 `false`。
- 只在单机存档上验证过；联机 / 存档损坏风险自负。

## License

MIT
