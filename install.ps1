# 一键安装：把 PBZWeaponSwap 复制到 UE4SS 的 Mods 目录并写入 mods.txt
# 用法：
#   powershell -ExecutionPolicy Bypass -File .\install.ps1
#   powershell -ExecutionPolicy Bypass -File .\install.ps1 -GameDir "D:\steam\steamapps\common\PBZ"
param(
    [string]$GameDir = ""
)

$ErrorActionPreference = "Stop"

function Find-GameDir {
    # 1) Steam 库配置文件
    $steam = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
    $candidates = @()
    if ($steam) {
        $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
        if (Test-Path $vdf) {
            foreach ($m in [regex]::Matches((Get-Content $vdf -Raw), '"path"\s+"([^"]+)"')) {
                $candidates += ($m.Groups[1].Value -replace '\\\\', '\')
            }
        }
        $candidates += $steam
    }
    $candidates += 'C:\Program Files (x86)\Steam', 'D:\steam', 'E:\steam'

    foreach ($c in $candidates) {
        $p = Join-Path $c 'steamapps\common\PBZ'
        if (Test-Path (Join-Path $p 'platform\steam\ue4ss')) { return $p }
    }
    return $null
}

if (-not $GameDir) {
    $GameDir = Find-GameDir
    if (-not $GameDir) {
        Write-Host "没找到游戏目录，请手动指定：" -ForegroundColor Yellow
        Write-Host '  .\install.ps1 -GameDir "D:\steam\steamapps\common\PBZ"'
        exit 1
    }
}

$modsDir = Join-Path $GameDir 'platform\steam\ue4ss\Mods'
if (-not (Test-Path $modsDir)) {
    Write-Host "没有找到 UE4SS：$modsDir" -ForegroundColor Red
    Write-Host "请先安装 UE4SS（https://github.com/UE4SS-RE/RE-UE4SS）。"
    exit 1
}

$src = Join-Path $PSScriptRoot 'src\PBZWeaponSwap'
$dst = Join-Path $modsDir 'PBZWeaponSwap'
Copy-Item $src $dst -Recurse -Force
Write-Host "已复制到 $dst"

# mods.txt
$modsTxt = Join-Path $modsDir 'mods.txt'
if (Test-Path $modsTxt) {
    Copy-Item $modsTxt "$modsTxt.bak-$(Get-Date -Format yyyyMMdd-HHmmss)" -Force
    $lines = Get-Content $modsTxt
    if ($lines -match '^\s*PBZWeaponSwap\s*:') {
        Write-Host "mods.txt 里已有 PBZWeaponSwap 条目，未改动。"
    } else {
        $out = @()
        $inserted = $false
        foreach ($l in $lines) {
            if (-not $inserted -and $l -match '^\s*Keybinds\s*:') {
                $out += 'PBZWeaponSwap : 1'
                $inserted = $true
            }
            $out += $l
        }
        if (-not $inserted) { $out += 'PBZWeaponSwap : 1' }
        Set-Content $modsTxt $out -Encoding UTF8
        Write-Host "已在 mods.txt 中加入 'PBZWeaponSwap : 1'（原文件已备份）。"
    }
} else {
    Write-Host "警告：$modsTxt 不存在，请手动加入 'PBZWeaponSwap : 1'" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "装好了。进游戏后：" -ForegroundColor Green
Write-Host "  <  上一把    >  下一把    F2  恢复原始装备    F11 自检    F12 打印排序"
