[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$ScriptDir      = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir        = Split-Path -Parent $ScriptDir
$CsvPath        = Join-Path $ScriptDir "profiles.csv"
$ChromeExe      = Join-Path $RootDir "chrome\chrome.exe"
$UserDataDir    = Join-Path $ScriptDir "ProfileData"
$DebugPort      = 9222
$Lang           = "vi"
$MinAvatarIndex = 27  # Bo avatar hien dai cua Chrome (27 -> 55)
$MaxAvatarIndex = 55
$DefaultColors  = @(
    "#1E88E5", # Xanh duong
    "#43A047", # Xanh la
    "#FB8C00", # Cam
    "#E53935", # Do
    "#8E24AA", # Tim
    "#00ACC1", # Xanh ngoc
    "#D81B60", # Hong
    "#FDD835", # Vang
    "#3949AB", # Cham
    "#6D4C41"  # Nau
)

function Convert-HexToSignedArgb {
    param([string]$Hex)
    $clean = $Hex.Trim().TrimStart('#')
    if ($clean -notmatch '^[0-9A-Fa-f]{6}$') { return $null }
    $uintVal = [Convert]::ToUInt32("FF$clean", 16)
    return [BitConverter]::ToInt32([BitConverter]::GetBytes($uintVal), 0)
}

function Set-JsonProp {
    param($Obj, [string]$Name, $Value)
    $Obj | Add-Member -MemberType NoteProperty -Name $Name -Value $Value -Force
}

function Ensure-JsonObject {
    param($Parent, [string]$Name)
    $prop = $Parent.PSObject.Properties[$Name]
    if ($null -eq $prop -or $null -eq $prop.Value -or ($prop.Value -isnot [PSCustomObject])) {
        $child = [PSCustomObject]@{}
        Set-JsonProp -Obj $Parent -Name $Name -Value $child
        return $child
    }
    return $prop.Value
}

function Save-JsonUtf8NoBom {
    param([string]$Path, $Object)
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $json = $Object | ConvertTo-Json -Depth 100 -Compress
    [System.IO.File]::WriteAllText($Path, $json, [System.Text.UTF8Encoding]::new($false))
}

if (-not (Test-Path $CsvPath)) {
    Write-Host "[LOI] Khong tim thay file: $CsvPath" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $ChromeExe)) {
    Write-Host "[CANH BAO] Khong tim thay Chrome tai: $ChromeExe" -ForegroundColor Yellow
}

# Kiem tra xem Chromium tai $ChromeExe co dang chay khong
$ChromeRunning = $false
try {
    $runningProcs = Get-Process -Name "chrome" -ErrorAction SilentlyContinue | Where-Object {
        try { $_.Path -eq $ChromeExe } catch { $false }
    }
    if ($runningProcs) { $ChromeRunning = $true }
} catch { }

$WshShell = New-Object -ComObject WScript.Shell

# Quet cac shortcut .lnk hien co de cap nhat in-place theo ProfileDir
$ExistingProfileDirs = @{}
Get-ChildItem -Path $ScriptDir -Filter "*.lnk" | ForEach-Object {
    try {
        $sc = $WshShell.CreateShortcut($_.FullName)
        if ($sc.Arguments -match '--profile-directory="([^"]+)"') {
            $dirKey = $Matches[1].Trim().ToLowerInvariant()
            $ExistingProfileDirs[$dirKey] = $_.FullName
        }
    } catch {
        # Bo qua shortcut loi neu co
    }
}

# Doc Local State (neu Chromium khong dang chay)
$LocalStatePath = Join-Path $UserDataDir "Local State"
$LocalState = $null
$LocalStateDirty = $false
if (-not $ChromeRunning) {
    if (Test-Path $LocalStatePath) {
        try {
            $LocalState = Get-Content -Path $LocalStatePath -Raw -Encoding UTF8 | ConvertFrom-Json
        } catch {
            Write-Host "[CANH BAO] Khong doc duoc Local State, bo qua cap nhat Local State." -ForegroundColor Yellow
            $LocalState = $null
        }
    } else {
        $LocalState = [PSCustomObject]@{}
    }
}

$Rows = Import-Csv -Path $CsvPath -Encoding UTF8
$CreatedCount = 0
$UpdatedCount = 0
$SkippedCount = 0
$RowIndex = 0
$AvatarSpan = $MaxAvatarIndex - $MinAvatarIndex + 1
$InvalidChars = [System.IO.Path]::GetInvalidFileNameChars()

Write-Host "=== BAT DAU TAO / CAP NHAT CHROME PROFILE SHORTCUT ===" -ForegroundColor Cyan
Write-Host "Thu muc du lieu: $UserDataDir" -ForegroundColor Gray
if ($ChromeRunning) {
    Write-Host "[CANH BAO] Chromium dang chay! Chi cap nhat shortcut (.lnk), bo qua mau & avatar." -ForegroundColor Yellow
    Write-Host "           Hay dong het cua so Chromium roi chay lai script de ap dung mau & avatar." -ForegroundColor Yellow
}
Write-Host ""

foreach ($Row in $Rows) {
    $RawShortcutName = if ($null -ne $Row.ShortcutName) { $Row.ShortcutName } elseif ($null -ne $Row.TenShortcut) { $Row.TenShortcut } else { "" }
    $ShortcutName    = $RawShortcutName.Trim()
    $ProfileDir      = if ($null -ne $Row.ProfileDir)  { $Row.ProfileDir.Trim() }  else { "" }
    $RawThemeColor   = if ($null -ne $Row.ThemeColor)  { $Row.ThemeColor.Trim() }  else { "" }
    $RawAvatarIndex  = if ($null -ne $Row.AvatarIndex) { $Row.AvatarIndex.Trim() } else { "" }

    # Bo qua dong trong hoac dong ghi chu bat dau bang #
    if ([string]::IsNullOrWhiteSpace($ShortcutName) -or $ShortcutName.StartsWith("#")) {
        continue
    }

    # Xac dinh ThemeColor (#RRGGBB); neu bo trong hoac sai dinh dang thi tu dong xoay vong
    $ThemeColorHex = $DefaultColors[$RowIndex % $DefaultColors.Count]
    $ThemeColorArgb = Convert-HexToSignedArgb -Hex $RawThemeColor
    if ($null -ne $ThemeColorArgb) {
        $ThemeColorHex = "#" + $RawThemeColor.TrimStart('#').ToUpperInvariant()
    } else {
        $ThemeColorArgb = Convert-HexToSignedArgb -Hex $ThemeColorHex
    }

    # Xac dinh AvatarIndex (27 -> 55); neu bo trong thi tu dong xoay vong
    $ParsedAvatar = 0
    if (-not [string]::IsNullOrWhiteSpace($RawAvatarIndex) -and [int]::TryParse($RawAvatarIndex, [ref]$ParsedAvatar) -and $ParsedAvatar -ge 0 -and $ParsedAvatar -le $MaxAvatarIndex) {
        $AvatarIndex = $ParsedAvatar
    } else {
        $AvatarIndex = $MinAvatarIndex + ($RowIndex % $AvatarSpan)
    }

    $RowIndex++

    # Neu khong dien ProfileDir thi tu dong lay theo TenShortcut
    if ([string]::IsNullOrWhiteSpace($ProfileDir)) {
        $ProfileDir = $ShortcutName
    }

    # Loc ky tu khong hop le cho ten file
    $SafeShortcutName = $ShortcutName
    foreach ($ch in $InvalidChars) {
        $SafeShortcutName = $SafeShortcutName.Replace($ch, '_')
    }

    $ShortcutPath  = Join-Path $ScriptDir "$SafeShortcutName.lnk"
    $ProfileDirKey = $ProfileDir.ToLowerInvariant()

    # 1. Cap nhat / tao shortcut .lnk
    $IsUpdate = $false
    $TargetShortcutPath = $ShortcutPath
    if (Test-Path $ShortcutPath) {
        $IsUpdate = $true
    } elseif ($ExistingProfileDirs.ContainsKey($ProfileDirKey)) {
        $IsUpdate = $true
        $TargetShortcutPath = $ExistingProfileDirs[$ProfileDirKey]
    }

    $TargetFileName = Split-Path -Leaf $TargetShortcutPath
    $NewArgs        = "--remote-debugging-port=$DebugPort --user-data-dir=`"$UserDataDir`" --profile-directory=`"$ProfileDir`" --lang=$Lang --no-default-browser-check --no-first-run --start-maximized"
    $NewWorkDir     = Split-Path -Parent $ChromeExe
    $NewIcon        = "$ChromeExe,0"

    $Shortcut = $WshShell.CreateShortcut($TargetShortcutPath)
    $ShortcutChanged = (-not $IsUpdate) -or
        ($Shortcut.TargetPath -ne $ChromeExe) -or
        ($Shortcut.Arguments -ne $NewArgs) -or
        ($Shortcut.WorkingDirectory -ne $NewWorkDir) -or
        ($Shortcut.IconLocation -ne $NewIcon)

    if ($ShortcutChanged) {
        $Shortcut.TargetPath       = $ChromeExe
        $Shortcut.Arguments        = $NewArgs
        $Shortcut.WorkingDirectory = $NewWorkDir
        $Shortcut.IconLocation     = $NewIcon
        $Shortcut.Save()
    }
    $ExistingProfileDirs[$ProfileDirKey] = $TargetShortcutPath

    # 2. Cap nhat mau theme, avatar & ten profile trong Preferences va Local State (khi Chromium da dong)
    $ProfileConfigChanged = $false
    if (-not $ChromeRunning) {
        $ProfileFolderPath = Join-Path $UserDataDir $ProfileDir
        $PrefPath = Join-Path $ProfileFolderPath "Preferences"

        $PrefObj = $null
        if (Test-Path $PrefPath) {
            try {
                $PrefObj = Get-Content -Path $PrefPath -Raw -Encoding UTF8 | ConvertFrom-Json
            } catch {
                $PrefObj = $null
            }
        } else {
            $PrefObj = [PSCustomObject]@{}
        }

        if ($null -ne $PrefObj) {
            $profNode = Ensure-JsonObject -Parent $PrefObj -Name "profile"
            $browserNode = Ensure-JsonObject -Parent $PrefObj -Name "browser"
            $themeNode = Ensure-JsonObject -Parent $browserNode -Name "theme"

            $needPrefSave = $false
            if ($profNode.name -ne $ShortcutName) { Set-JsonProp $profNode "name" $ShortcutName; $needPrefSave = $true }
            if ($profNode.avatar_index -ne $AvatarIndex) { Set-JsonProp $profNode "avatar_index" $AvatarIndex; $needPrefSave = $true }
            if ($profNode.using_default_avatar -ne $false) { Set-JsonProp $profNode "using_default_avatar" $false; $needPrefSave = $true }
            if ($profNode.using_default_name -ne $false) { Set-JsonProp $profNode "using_default_name" $false; $needPrefSave = $true }

            if ($themeNode.follows_system_colors -ne $false) { Set-JsonProp $themeNode "follows_system_colors" $false; $needPrefSave = $true }
            if ($themeNode.is_grayscale2 -ne $false) { Set-JsonProp $themeNode "is_grayscale2" $false; $needPrefSave = $true }
            if ($themeNode.user_color2 -ne $ThemeColorArgb) { Set-JsonProp $themeNode "user_color2" $ThemeColorArgb; $needPrefSave = $true }
            if ($themeNode.color_variant2 -ne 1) { Set-JsonProp $themeNode "color_variant2" 1; $needPrefSave = $true }

            if ($needPrefSave -or -not (Test-Path $PrefPath)) {
                Save-JsonUtf8NoBom -Path $PrefPath -Object $PrefObj
                $ProfileConfigChanged = $true
            }
        }

        if ($null -ne $LocalState) {
            $lsProfile = Ensure-JsonObject -Parent $LocalState -Name "profile"
            $infoCache = Ensure-JsonObject -Parent $lsProfile -Name "info_cache"
            $entry = Ensure-JsonObject -Parent $infoCache -Name $ProfileDir

            $avatarUri = "chrome://theme/IDR_PROFILE_AVATAR_$AvatarIndex"
            $needLsSave = $false
            if ($entry.name -ne $ShortcutName) { Set-JsonProp $entry "name" $ShortcutName; $needLsSave = $true }
            if ($entry.is_using_default_name -ne $false) { Set-JsonProp $entry "is_using_default_name" $false; $needLsSave = $true }
            if ($entry.avatar_icon -ne $avatarUri) { Set-JsonProp $entry "avatar_icon" $avatarUri; $needLsSave = $true }
            if ($entry.is_using_default_avatar -ne $false) { Set-JsonProp $entry "is_using_default_avatar" $false; $needLsSave = $true }
            if ($entry.profile_color_seed -ne $ThemeColorArgb) { Set-JsonProp $entry "profile_color_seed" $ThemeColorArgb; $needLsSave = $true }
            if ($entry.profile_highlight_color -ne $ThemeColorArgb) { Set-JsonProp $entry "profile_highlight_color" $ThemeColorArgb; $needLsSave = $true }

            if ($needLsSave) {
                $LocalStateDirty = $true
                $ProfileConfigChanged = $true
            }
        }
    }

    if (-not $IsUpdate) {
        Write-Host "[DA TAO] $TargetFileName  -->  Profile: '$ProfileDir' | Mau: $ThemeColorHex | Avatar: $AvatarIndex" -ForegroundColor Green
        $CreatedCount++
    } elseif ($ShortcutChanged -or $ProfileConfigChanged) {
        Write-Host "[CAP NHAT] $TargetFileName  -->  Profile: '$ProfileDir' | Mau: $ThemeColorHex | Avatar: $AvatarIndex" -ForegroundColor Yellow
        $UpdatedCount++
    } else {
        Write-Host "[KHONG DOI] $TargetFileName  -->  Profile: '$ProfileDir' | Mau: $ThemeColorHex | Avatar: $AvatarIndex" -ForegroundColor Gray
        $SkippedCount++
    }
}

if ($LocalStateDirty -and $null -ne $LocalState) {
    Save-JsonUtf8NoBom -Path $LocalStatePath -Object $LocalState
}

Write-Host ""
Write-Host "=== HOAN THANH ===" -ForegroundColor Cyan
Write-Host "Da tao moi : $CreatedCount" -ForegroundColor Green
Write-Host "Da cap nhat: $UpdatedCount" -ForegroundColor Yellow
Write-Host "Khong doi  : $SkippedCount" -ForegroundColor Gray
