# gmod addon deploy utility, tg:@s0nny13

# ---------------------------------------------------------------- config
# project root = directory the script was launched from
$script:Root         = (Get-Location).ProviderPath
$script:AddonsFolder = $script:Root
$script:GmodAddons   = "C:\Program Files (x86)\Steam\steamapps\common\GarrysMod\garrysmod\addons"

# ---------------------------------------------------------------- terminal / style
$script:ESC   = [char]27
$script:Block = [char]0x2588

$script:Colors = @{
    success = "${ESC}[32m"
    error   = "${ESC}[31m"
    warning = "${ESC}[33m"
    default = "${ESC}[97m"
}
$script:Reset = "${ESC}[0m"
$script:White = "${ESC}[97m"

function Write-Msg {
    param(
        [Parameter(Mandatory)][string]$Text,
        [ValidateSet("success", "error", "warning", "default")][string]$Type = "default",
        [string]$Comment
    )
    $color = $script:Colors[$Type]
    $line  = "$color$($script:Block) $Text$($script:Reset)"
    if ($Comment) {
        $line += "$($script:White) - $Comment$($script:Reset)"
    }
    [Console]::WriteLine($line)
}

function Read-Input {
    param([Parameter(Mandatory)][string]$Label)
    [Console]::Write("$($script:White)$($script:Block) $Label> $($script:Reset)")
    $value = [Console]::ReadLine()
    if ($null -eq $value) { return "" }
    return $value.Trim()
}

function Confirm-Action {
    param([Parameter(Mandatory)][string]$Text)
    $answer = Read-Input "$Text [y:N]"
    return ($answer -eq "y" -or $answer -eq "Y")
}

function Enter-AltScreen {
    $script:PrevEncoding = [Console]::OutputEncoding
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    [Console]::Write("${ESC}[?1049h${ESC}[2J${ESC}[H")
}

function Exit-AltScreen {
    [Console]::Write("${ESC}[?1049l")
    if ($script:PrevEncoding) { [Console]::OutputEncoding = $script:PrevEncoding }
}

# ---------------------------------------------------------------- architecture data
function New-TreeEntry {
    param([string]$Group, [string]$Path, [string]$Comment, [bool]$Default = $false)
    return [pscustomobject]@{ Group = $Group; Path = $Path; Comment = $Comment; Default = $Default }
}

# every standard folder of a gmod addon ("full" architecture)
# Default = preselected in the custom checklist when creating a new addon
$script:Tree = @(
    New-TreeEntry "lua" "lua\autorun"                    "shared scripts, run on client and server"
    New-TreeEntry "lua" "lua\autorun\client"             "client-only scripts" $true
    New-TreeEntry "lua" "lua\autorun\server"             "server-only scripts" $true
    New-TreeEntry "lua" "lua\entities"                   "scripted entities and npcs" $true
    New-TreeEntry "lua" "lua\weapons"                    "scripted weapons"
    New-TreeEntry "lua" "lua\weapons\gmod_tool\stools"   "toolgun tools"
    New-TreeEntry "lua" "lua\effects"                    "effects"
    New-TreeEntry "lua" "lua\vgui"                       "custom vgui panels"
    New-TreeEntry "lua" "lua\skins"                      "derma skins"
    New-TreeEntry "lua" "lua\postprocess"                "post-processing effects"
    New-TreeEntry "lua" "lua\matproxy"                   "material proxies"
    New-TreeEntry "lua" "lua\includes\modules"           "lua modules for require"
    New-TreeEntry "lua" "lua\bin"                        "binary modules, not accepted by workshop"

    New-TreeEntry "resources" "materials"                "materials and textures"
    New-TreeEntry "resources" "materials\entities"       "spawnmenu icons"
    New-TreeEntry "resources" "materials\vgui\entities"  "spawnmenu icons (vmt)"
    New-TreeEntry "resources" "materials\sprites"        "sprites"
    New-TreeEntry "resources" "materials\models"         "model textures"
    New-TreeEntry "resources" "models"                   "models"
    New-TreeEntry "resources" "sound"                    "sounds"
    New-TreeEntry "resources" "particles"                "particle systems (.pcf)"
    New-TreeEntry "resources" "resource\fonts"           "fonts (.ttf)"
    New-TreeEntry "resources" "resource\localization"    "localization (.properties)"

    New-TreeEntry "scripts and data" "scripts"           "game scripts"
    New-TreeEntry "scripts and data" "scripts\vehicles"  "vehicle scripts"
    New-TreeEntry "scripts and data" "scripts\sounds"    "sound scripts"
    New-TreeEntry "scripts and data" "data"              "runtime data, local only"
    New-TreeEntry "scripts and data" "data_static"       "static data (.txt)"
    New-TreeEntry "scripts and data" "cfg"               "config files, local only"

    New-TreeEntry "maps and modes" "maps"                "maps (.bsp, .nav, .ain)"
    New-TreeEntry "maps and modes" "maps\graphs"         "node graphs"
    New-TreeEntry "maps and modes" "gamemodes"           "gamemodes"
)

# component types that can be added to any addon
#   dir      - folder <Path>\<name>\ with the listed files inside
#   file     - single file <Path>\<name><Ext>
#   gamemode - gamemodes\<name>\<name>.txt + gamemodes\<name>\gamemode\*.lua
function New-Comp {
    param(
        [string]$Name, [string]$Kind, [string]$Path, [string]$Comment,
        [string[]]$Files = @(), [bool]$Strict = $true, [string]$Ext = ".lua"
    )
    return [pscustomobject]@{
        Name = $Name; Kind = $Kind; Path = $Path; Comment = $Comment
        Files = $Files; Strict = $Strict; Ext = $Ext
    }
}

$script:LuaTriple = @("shared.lua", "init.lua", "cl_init.lua")

$script:Components = @(
    New-Comp -Name "entity"       -Kind "dir"      -Path "lua\entities"                 -Files $script:LuaTriple -Comment "lua\entities\<name>\"
    New-Comp -Name "weapon"       -Kind "dir"      -Path "lua\weapons"                  -Files $script:LuaTriple -Comment "lua\weapons\<name>\"
    New-Comp -Name "effect"       -Kind "file"     -Path "lua\effects"                  -Comment "lua\effects\<name>.lua"
    New-Comp -Name "stool"        -Kind "file"     -Path "lua\weapons\gmod_tool\stools" -Comment "toolgun tool, stools\<name>.lua"
    New-Comp -Name "vgui"         -Kind "file"     -Path "lua\vgui"                     -Comment "lua\vgui\<name>.lua"
    New-Comp -Name "skin"         -Kind "file"     -Path "lua\skins"                    -Comment "lua\skins\<name>.lua"
    New-Comp -Name "postprocess"  -Kind "file"     -Path "lua\postprocess"              -Comment "lua\postprocess\<name>.lua"
    New-Comp -Name "matproxy"     -Kind "file"     -Path "lua\matproxy"                 -Comment "lua\matproxy\<name>.lua"
    New-Comp -Name "module"       -Kind "file"     -Path "lua\includes\modules"         -Comment "lua\includes\modules\<name>.lua"
    New-Comp -Name "autorun"      -Kind "file"     -Path "lua\autorun"                  -Comment "shared script, lua\autorun\<name>.lua"
    New-Comp -Name "autorun_cl"   -Kind "file"     -Path "lua\autorun\client"           -Comment "client script, autorun\client\<name>.lua"
    New-Comp -Name "autorun_sv"   -Kind "file"     -Path "lua\autorun\server"           -Comment "server script, autorun\server\<name>.lua"
    New-Comp -Name "vehicle"      -Kind "file"     -Path "scripts\vehicles"             -Ext ".txt" -Comment "scripts\vehicles\<name>.txt"
    New-Comp -Name "soundscript"  -Kind "file"     -Path "scripts\sounds"               -Ext ".txt" -Comment "scripts\sounds\<name>.txt"
    New-Comp -Name "localization" -Kind "file"     -Path "resource\localization\en"     -Ext ".properties" -Comment "resource\localization\en\<name>.properties"
    New-Comp -Name "gamemode"     -Kind "gamemode" -Path "gamemodes"                    -Files $script:LuaTriple -Comment "gamemodes\<name>\"
    New-Comp -Name "materials"    -Kind "dir"      -Path "materials"                    -Strict $false -Comment "materials\<name>\"
    New-Comp -Name "models"       -Kind "dir"      -Path "models"                       -Strict $false -Comment "models\<name>\"
    New-Comp -Name "sound"        -Kind "dir"      -Path "sound"                        -Strict $false -Comment "sound\<name>\"
)

# ---------------------------------------------------------------- helpers
function Get-Dirs {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    return @(Get-ChildItem -LiteralPath $Path -Directory)
}

# addons of the project = sub-folders of the root (dot-folders like .git are ignored)
function Get-Addons {
    return @(Get-Dirs $script:AddonsFolder | Where-Object { $_.Name -notlike ".*" })
}

function Show-List {
    param($Items, [string]$Title)
    Write-Msg $Title
    for ($i = 0; $i -lt $Items.Count; $i++) {
        $comment = $null
        if ($Items[$i].PSObject.Properties["Comment"]) { $comment = $Items[$i].Comment }
        Write-Msg "[$i] $($Items[$i].Name)" -Comment $comment
    }
}

# shows list, asks for index, returns chosen item or $null
function Select-FromList {
    param($Items, [string]$Title, [string]$Prompt = "choose by index")
    Show-List $Items $Title
    $raw = Read-Input $Prompt
    if ($raw -eq "") {
        Write-Msg "cancelled" -Type warning
        return $null
    }
    $index = 0
    if (-not [int]::TryParse($raw, [ref]$index) -or $index -lt 0 -or $index -ge $Items.Count) {
        Write-Msg "invalid index" -Type error -Comment "'$raw' is not in range 0..$($Items.Count - 1)"
        return $null
    }
    return $Items[$index]
}

function Select-Addon {
    param([string]$Prompt = "addon#")
    $addons = Get-Addons
    if ($addons.Count -eq 0) {
        Write-Msg "no addons found" -Type warning -Comment "create one with 'new'"
        return $null
    }
    return (Select-FromList $addons "available addons" $Prompt)
}

function Test-ValidName {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return $false }
    return ($Name.IndexOfAny([System.IO.Path]::GetInvalidFileNameChars()) -lt 0)
}

function Test-ComponentName {
    param($Comp, [string]$Name)
    if ($Comp.Strict) { return ($Name -match "^[A-Za-z0-9_]+$") }
    return (Test-ValidName $Name)
}

function Get-Component {
    param([string]$Key)
    return ($script:Components | Where-Object { $_.Name -eq $Key } | Select-Object -First 1)
}

# existing items of one component type inside an addon
function Get-ComponentItems {
    param($Addon, $Comp)
    $root = Join-Path $Addon.FullName $Comp.Path
    if (-not (Test-Path -LiteralPath $root)) { return @() }
    if ($Comp.Kind -eq "file") {
        return @(Get-ChildItem -LiteralPath $root -File -Filter "*$($Comp.Ext)")
    }
    return @(Get-ChildItem -LiteralPath $root -Directory)
}

function Get-ComponentTarget {
    param($Addon, $Comp, [string]$Name)
    $root = Join-Path $Addon.FullName $Comp.Path
    if ($Comp.Kind -eq "file") { return (Join-Path $root "$Name$($Comp.Ext)") }
    return (Join-Path $root $Name)
}

function New-ComponentItem {
    param($Addon, $Comp, [string]$Name)
    $target = Get-ComponentTarget $Addon $Comp $Name
    switch ($Comp.Kind) {
        "dir" {
            New-Item -ItemType Directory -Path $target -Force -ErrorAction Stop | Out-Null
            foreach ($file in $Comp.Files) {
                New-Item -ItemType File -Path (Join-Path $target $file) -ErrorAction Stop | Out-Null
            }
        }
        "file" {
            New-Item -ItemType File -Path $target -Force -ErrorAction Stop | Out-Null
        }
        "gamemode" {
            $gmDir = Join-Path $target "gamemode"
            New-Item -ItemType Directory -Path $gmDir -Force -ErrorAction Stop | Out-Null
            foreach ($file in $Comp.Files) {
                New-Item -ItemType File -Path (Join-Path $gmDir $file) -ErrorAction Stop | Out-Null
            }
            $txt = @"
"gamemode"
{
    "base"        "base"
    "title"       "$Name"
    "maps"        ""
    "menusystem"  "1"
}
"@
            Set-Content -LiteralPath (Join-Path $target "$Name.txt") -Value $txt -Encoding ASCII -ErrorAction Stop
        }
    }
}

function Get-MissingEntries {
    param($Addon)
    return @($script:Tree | Where-Object { -not (Test-Path -LiteralPath (Join-Path $Addon.FullName $_.Path)) })
}

function New-TreeFolders {
    param([string]$Base, $Entries)
    foreach ($entry in @($Entries)) {
        New-Item -ItemType Directory -Path (Join-Path $Base $entry.Path) -Force -ErrorAction Stop | Out-Null
    }
}

# validates a user typed relative path and resolves it inside the addon, $null on error
function Resolve-AddonPath {
    param($Addon, [string]$Rel)
    $segments = @($Rel -split "[\\/]" | Where-Object { $_ -ne "" })
    if ($segments.Count -eq 0) {
        Write-Msg "empty path" -Type error
        return $null
    }
    foreach ($s in $segments) {
        if ($s -eq "." -or $s -eq ".." -or -not (Test-ValidName $s)) {
            Write-Msg "invalid path" -Type error -Comment "'$s' is not allowed"
            return $null
        }
    }
    return (Join-Path $Addon.FullName ($segments -join "\"))
}

# ---------------------------------------------------------------- checklist
# full-screen checklist inside the alt screen
# up/down - move, space - toggle, a - toggle whole group, enter - confirm, esc - cancel
# returns object { Cancelled; Selected }
function Read-Checklist {
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)]$Entries,
        [switch]$NoDefaults,
        [int]$Max = 0
    )
    $Entries = @($Entries)
    $n = $Entries.Count
    $sel = New-Object "bool[]" $n
    if (-not $NoDefaults) {
        for ($i = 0; $i -lt $n; $i++) { $sel[$i] = [bool]$Entries[$i].Default }
    }

    # rows = group headers + items
    $rowKind   = New-Object System.Collections.ArrayList
    $rowRef    = New-Object System.Collections.ArrayList
    $rowOfItem = New-Object "int[]" $n
    $lastGroup = $null
    for ($i = 0; $i -lt $n; $i++) {
        $g = [string]$Entries[$i].Group
        if ($g -ne $lastGroup) {
            if ($g) {
                [void]$rowKind.Add("g")
                [void]$rowRef.Add($g)
            }
            $lastGroup = $g
        }
        [void]$rowKind.Add("i")
        [void]$rowRef.Add($i)
        $rowOfItem[$i] = $rowKind.Count - 1
    }

    $cursor    = 0
    $top       = 0
    $done      = $false
    $cancelled = $false

    [Console]::Write("${ESC}[?25l")
    try {
        while (-not $done) {
            $width  = [Console]::WindowWidth
            $height = [Console]::WindowHeight
            $view   = [Math]::Max(5, $height - 4)

            # keep cursor row (and its group header) visible
            $cr = $rowOfItem[$cursor]
            if ($cr -lt $top) { $top = $cr }
            if ($cr -gt 0 -and $rowKind[$cr - 1] -eq "g" -and ($cr - 1) -lt $top) { $top = $cr - 1 }
            if ($cr -ge $top + $view) { $top = $cr - $view + 1 }
            if ($top -lt 0) { $top = 0 }

            $count = @($sel | Where-Object { $_ }).Count
            if ($Max -gt 0) { $limit = $Max } else { $limit = $n }

            $sb = New-Object System.Text.StringBuilder
            [void]$sb.Append("${ESC}[H${ESC}[J")
            [void]$sb.Append("$($script:Colors.default)$($script:Block) $Title$($script:Reset)`r`n")
            [void]$sb.Append("$($script:Colors.default)$($script:Block) selected $count/$limit$($script:White) - up/down move, space toggle, a group, enter confirm, esc cancel$($script:Reset)`r`n")

            $last = [Math]::Min($rowKind.Count, $top + $view)
            for ($r = $top; $r -lt $last; $r++) {
                if ($rowKind[$r] -eq "g") {
                    $g   = [string]$rowRef[$r]
                    $gi  = @(0..($n - 1) | Where-Object { [string]$Entries[$_].Group -eq $g })
                    $gOn = @($gi | Where-Object { $sel[$_] }).Count
                    $line = "  ${ESC}[1m$($script:Colors.default)$g$($script:Reset)$($script:White) - $gOn/$($gi.Count)$($script:Reset)"
                }
                else {
                    $idx   = [int]$rowRef[$r]
                    $entry = $Entries[$idx]
                    if ($idx -eq $cursor) { $ptr = ">"; $bold = "${ESC}[1m" } else { $ptr = " "; $bold = "" }
                    if ($sel[$idx]) { $color = $script:Colors.success; $mark = "[x]" }
                    else            { $color = $script:Colors.default; $mark = "[ ]" }
                    $text = [string]$entry.Path
                    $line = "$ptr $bold$color$($script:Block) $mark $text$($script:Reset)"
                    $cm = [string]$entry.Comment
                    if ($cm) {
                        $room = $width - 1 - 8 - $text.Length - 3
                        if ($room -ge 4) {
                            if ($cm.Length -gt $room) { $cm = $cm.Substring(0, $room - 3) + "..." }
                            $line += "$($script:White) - $cm$($script:Reset)"
                        }
                    }
                }
                [void]$sb.Append($line + "`r`n")
            }
            [Console]::Write($sb.ToString())

            $key = [Console]::ReadKey($true)
            switch ($key.Key.ToString()) {
                "UpArrow"   { if ($cursor -le 0) { $cursor = $n - 1 } else { $cursor-- } }
                "DownArrow" { if ($cursor -ge $n - 1) { $cursor = 0 } else { $cursor++ } }
                "PageUp"    { $cursor = [Math]::Max(0, $cursor - 10) }
                "PageDown"  { $cursor = [Math]::Min($n - 1, $cursor + 10) }
                "Home"      { $cursor = 0 }
                "End"       { $cursor = $n - 1 }
                "Spacebar" {
                    if ($sel[$cursor]) { $sel[$cursor] = $false }
                    elseif ($Max -le 0 -or $count -lt $Max) { $sel[$cursor] = $true }
                }
                "A" {
                    $g   = [string]$Entries[$cursor].Group
                    $idx = @(0..($n - 1) | Where-Object { [string]$Entries[$_].Group -eq $g })
                    $allOn = (@($idx | Where-Object { -not $sel[$_] }).Count -eq 0)
                    if ($allOn) { foreach ($k in $idx) { $sel[$k] = $false } }
                    elseif ($Max -le 0) { foreach ($k in $idx) { $sel[$k] = $true } }
                }
                "Enter"  { $done = $true }
                "Escape" { $done = $true; $cancelled = $true }
            }
        }
    }
    finally {
        [Console]::Write("${ESC}[?25h${ESC}[2J${ESC}[H")
    }

    $selected = @()
    if (-not $cancelled) {
        $selected = @(0..($n - 1) | Where-Object { $sel[$_] } | ForEach-Object { $Entries[$_] })
    }
    return [pscustomobject]@{ Cancelled = $cancelled; Selected = $selected }
}

# asks full or custom architecture, returns object { Selected } or $null when cancelled
function Select-Architecture {
    param($Entries, [string]$Title, [switch]$NoDefaults)
    $Entries = @($Entries)
    $modes = @(
        [pscustomobject]@{ Name = "full";   Comment = "all $($Entries.Count) standard folders" }
        [pscustomobject]@{ Name = "custom"; Comment = "choose folders in a checklist" }
    )
    $mode = Select-FromList $modes "architecture" "type#"
    if (-not $mode) { return $null }

    if ($mode.Name -eq "full") {
        return [pscustomobject]@{ Selected = $Entries }
    }

    $result = Read-Checklist -Title $Title -Entries $Entries -NoDefaults:$NoDefaults
    if ($result.Cancelled) {
        Write-Msg "cancelled" -Type warning
        return $null
    }
    return [pscustomobject]@{ Selected = $result.Selected }
}

# ---------------------------------------------------------------- commands
function PrintHelp {
    Write-Msg "help info"
    Write-Msg "help" -Comment "prints this message"
    Write-Msg "exit" -Comment "exits from interactive mode"
    Write-Msg "clear" -Comment "clears the screen"
    Write-Msg "list" -Comment "displays list of available addons"
    Write-Msg "dlist" -Comment "prints list of deployed addons"
    Write-Msg "new" -Comment "creates addon, full or custom architecture"
    Write-Msg "del" -Comment "deletes chosen addon from project"
    Write-Msg "deploy" -Comment "choose addon for deploying"
    Write-Msg "undeploy" -Comment "choose addon for undeploying"
    Write-Msg "tree" -Comment "prints addon tree and missing standard folders"
    Write-Msg "fix" -Comment "adds missing standard folders to addon"
    Write-Msg "show" -Comment "prints components of chosen addon"
    Write-Msg "add" -Comment "adds component (entity, weapon, effect, stool, gamemode...)"
    Write-Msg "rm" -Comment "removes component from addon"
    Write-Msg "aent" -Comment "shortcut for 'add' with entity"
    Write-Msg "dent" -Comment "shortcut for 'rm' with entity"
    Write-Msg "mkdir" -Comment "creates any folder inside addon"
    Write-Msg "touch" -Comment "creates any empty file inside addon"
    Write-Msg "rmpath" -Comment "deletes any file or folder inside addon"
    Write-Msg "json" -Comment "generates addon.json for workshop"
}

function PrintAvailableAddons {
    $addons = Get-Addons
    if ($addons.Count -eq 0) {
        Write-Msg "no addons found" -Type warning -Comment $script:AddonsFolder
        return
    }
    Show-List $addons "available addons"
}

function PrintDeployed {
    $addons = Get-Dirs $script:GmodAddons
    if ($addons.Count -eq 0) {
        Write-Msg "no deployed addons found" -Type warning -Comment $script:GmodAddons
        return
    }
    Show-List $addons "deployed addons"
}

function AddonDeploy {
    $addon = Select-Addon
    if (-not $addon) { return }

    if (-not (Test-Path -LiteralPath $script:GmodAddons)) {
        Write-Msg "gmod addons folder not found" -Type error -Comment $script:GmodAddons
        return
    }

    $target = Join-Path $script:GmodAddons $addon.Name
    try {
        if (Test-Path -LiteralPath $target) {
            Write-Msg "addon already deployed" -Type warning -Comment $addon.Name
            if (-not (Confirm-Action "overwrite?")) {
                Write-Msg "cancelled" -Type warning
                return
            }
            Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction Stop
        }
        Copy-Item -LiteralPath $addon.FullName -Destination $script:GmodAddons -Recurse -ErrorAction Stop
        Write-Msg "addon deployed" -Type success -Comment $addon.Name
    }
    catch {
        Write-Msg "deploy failed" -Type error -Comment $_.Exception.Message
    }
}

function AddonUndeploy {
    $addons = Get-Dirs $script:GmodAddons
    if ($addons.Count -eq 0) {
        Write-Msg "no deployed addons found" -Type warning
        return
    }
    $addon = Select-FromList $addons "deployed addons" "addon#"
    if (-not $addon) { return }

    if (-not (Confirm-Action "remove '$($addon.Name)' from game?")) {
        Write-Msg "cancelled" -Type warning
        return
    }
    try {
        Remove-Item -LiteralPath $addon.FullName -Recurse -Force -ErrorAction Stop
        Write-Msg "addon undeployed" -Type success -Comment $addon.Name
    }
    catch {
        Write-Msg "undeploy failed" -Type error -Comment $_.Exception.Message
    }
}

function AddonNew {
    $name = $null
    if (Confirm-Action "name addon folder by yourself?") {
        $name = Read-Input "addon folder name"
        if (-not (Test-ValidName $name) -or $name -like ".*") {
            Write-Msg "invalid name" -Type error -Comment "empty, starts with a dot or contains forbidden characters"
            return
        }
        if (Test-Path -LiteralPath (Join-Path $script:AddonsFolder $name)) {
            Write-Msg "addon already exists" -Type error -Comment $name
            return
        }
    }
    else {
        $n = (Get-Addons).Count
        do {
            $name = "addon{0:D4}" -f $n
            $n++
        } while (Test-Path -LiteralPath (Join-Path $script:AddonsFolder $name))
    }

    $choice = Select-Architecture $script:Tree "new addon '$name' - choose folders"
    if (-not $choice) { return }

    $base = Join-Path $script:AddonsFolder $name
    try {
        New-Item -ItemType Directory -Path $base -Force -ErrorAction Stop | Out-Null
        New-TreeFolders $base $choice.Selected
        Write-Msg "addon created" -Type success -Comment "$name, $($choice.Selected.Count) folders"
    }
    catch {
        Write-Msg "create failed" -Type error -Comment $_.Exception.Message
    }
}

function DeleteAddon {
    $addon = Select-Addon
    if (-not $addon) { return }

    if (-not (Confirm-Action "delete '$($addon.Name)' from project?")) {
        Write-Msg "cancelled" -Type warning
        return
    }
    try {
        Remove-Item -LiteralPath $addon.FullName -Recurse -Force -ErrorAction Stop
        Write-Msg "addon deleted" -Type success -Comment $addon.Name
    }
    catch {
        Write-Msg "delete failed" -Type error -Comment $_.Exception.Message
    }
}

function Write-DirTree {
    param([string]$Path, [int]$Depth)
    $items = @(Get-ChildItem -LiteralPath $Path -Force |
        Sort-Object @{ Expression = { -not $_.PSIsContainer } }, Name)
    foreach ($item in $items) {
        $indent = "  " * $Depth
        if ($item.PSIsContainer) {
            Write-Msg "$indent$($item.Name)\"
            Write-DirTree $item.FullName ($Depth + 1)
        }
        else {
            if ($item.Length -lt 1024) { $size = "$($item.Length) B" }
            else                       { $size = "{0:N1} KB" -f ($item.Length / 1KB) }
            Write-Msg "$indent$($item.Name)" -Comment $size
        }
    }
}

function ShowTree {
    $addon = Select-Addon
    if (-not $addon) { return }

    Write-Msg "$($addon.Name)\"
    $content = @(Get-ChildItem -LiteralPath $addon.FullName -Force)
    if ($content.Count -eq 0) {
        Write-Msg "addon is empty" -Type warning
    }
    else {
        Write-DirTree $addon.FullName 1
    }

    $missing = Get-MissingEntries $addon
    if ($missing.Count -eq 0) {
        Write-Msg "all standard folders present" -Type success
        return
    }
    Write-Msg "missing standard folders" -Type warning -Comment "$($missing.Count), use 'fix' to create them"
    foreach ($entry in $missing) {
        Write-Msg $entry.Path -Type warning -Comment $entry.Comment
    }
}

function FixAddon {
    $addon = Select-Addon
    if (-not $addon) { return }

    $missing = Get-MissingEntries $addon
    if ($missing.Count -eq 0) {
        Write-Msg "nothing to fix" -Type success -Comment "all standard folders present"
        return
    }

    $choice = Select-Architecture $missing "missing folders of '$($addon.Name)'" -NoDefaults
    if (-not $choice) { return }

    try {
        New-TreeFolders $addon.FullName $choice.Selected
        Write-Msg "folders created" -Type success -Comment "$($addon.Name), $($choice.Selected.Count) folders"
    }
    catch {
        Write-Msg "create failed" -Type error -Comment $_.Exception.Message
    }
}

function ShowAddon {
    $addon = Select-Addon
    if (-not $addon) { return }

    $found = $false
    foreach ($comp in $script:Components) {
        $items = Get-ComponentItems $addon $comp
        if ($items.Count -gt 0) {
            $found = $true
            $names = ($items | ForEach-Object { $_.Name }) -join ", "
            Write-Msg $comp.Name -Comment $names
        }
    }
    if (-not $found) {
        Write-Msg "addon has no components yet" -Type warning -Comment "use 'add'"
    }
}

# TypeKey - optional, skips the type selection (used by aent / dent)
function AddComponent {
    param([string]$TypeKey)

    $addon = Select-Addon
    if (-not $addon) { return }

    if ($TypeKey) { $comp = Get-Component $TypeKey }
    else          { $comp = Select-FromList $script:Components "component types" "type#" }
    if (-not $comp) { return }

    $name = Read-Input "$($comp.Name)_name"
    if ($comp.Kind -eq "file") { $name = $name -replace ([regex]::Escape($comp.Ext) + "$"), "" }
    if (-not (Test-ComponentName $comp $name)) {
        if ($comp.Strict) { $why = "use only letters, digits and _" }
        else              { $why = "empty or contains forbidden characters" }
        Write-Msg "invalid name" -Type error -Comment $why
        return
    }

    if (Test-Path -LiteralPath (Get-ComponentTarget $addon $comp $name)) {
        Write-Msg "$($comp.Name) already exists" -Type error -Comment $name
        return
    }
    try {
        New-ComponentItem $addon $comp $name
        Write-Msg "$($comp.Name) created" -Type success -Comment "$($addon.Name)/$name"
    }
    catch {
        Write-Msg "create failed" -Type error -Comment $_.Exception.Message
    }
}

function RemoveComponent {
    param([string]$TypeKey)

    $addon = Select-Addon
    if (-not $addon) { return }

    if ($TypeKey) { $comp = Get-Component $TypeKey }
    else          { $comp = Select-FromList $script:Components "component types" "type#" }
    if (-not $comp) { return }

    $items = Get-ComponentItems $addon $comp
    if ($items.Count -eq 0) {
        Write-Msg "no $($comp.Name) found" -Type warning -Comment $addon.Name
        return
    }
    $item = Select-FromList $items "$($comp.Name) of $($addon.Name)" "$($comp.Name)#"
    if (-not $item) { return }

    if (-not (Confirm-Action "delete $($comp.Name) '$($item.Name)'?")) {
        Write-Msg "cancelled" -Type warning
        return
    }
    try {
        Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction Stop
        Write-Msg "$($comp.Name) deleted" -Type success -Comment "$($addon.Name)/$($item.Name)"
    }
    catch {
        Write-Msg "delete failed" -Type error -Comment $_.Exception.Message
    }
}

function MakeDir {
    $addon = Select-Addon
    if (-not $addon) { return }

    $rel = Read-Input "folder path inside addon"
    $path = Resolve-AddonPath $addon $rel
    if (-not $path) { return }

    if (Test-Path -LiteralPath $path) {
        Write-Msg "already exists" -Type warning -Comment $rel
        return
    }
    try {
        New-Item -ItemType Directory -Path $path -Force -ErrorAction Stop | Out-Null
        Write-Msg "folder created" -Type success -Comment "$($addon.Name)/$rel"
    }
    catch {
        Write-Msg "create failed" -Type error -Comment $_.Exception.Message
    }
}

function MakeFile {
    $addon = Select-Addon
    if (-not $addon) { return }

    $rel = Read-Input "file path inside addon"
    $path = Resolve-AddonPath $addon $rel
    if (-not $path) { return }

    if (Test-Path -LiteralPath $path) {
        Write-Msg "already exists" -Type error -Comment $rel
        return
    }
    try {
        New-Item -ItemType File -Path $path -Force -ErrorAction Stop | Out-Null
        Write-Msg "file created" -Type success -Comment "$($addon.Name)/$rel"
    }
    catch {
        Write-Msg "create failed" -Type error -Comment $_.Exception.Message
    }
}

function RemovePath {
    $addon = Select-Addon
    if (-not $addon) { return }

    $rel = Read-Input "path inside addon"
    $path = Resolve-AddonPath $addon $rel
    if (-not $path) { return }

    if (-not (Test-Path -LiteralPath $path)) {
        Write-Msg "path not found" -Type error -Comment $rel
        return
    }
    if (-not (Confirm-Action "delete '$rel'?")) {
        Write-Msg "cancelled" -Type warning
        return
    }
    try {
        Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop
        Write-Msg "deleted" -Type success -Comment "$($addon.Name)/$rel"
    }
    catch {
        Write-Msg "delete failed" -Type error -Comment $_.Exception.Message
    }
}

function AddonJson {
    $addon = Select-Addon
    if (-not $addon) { return }

    $path = Join-Path $addon.FullName "addon.json"
    if (Test-Path -LiteralPath $path) {
        Write-Msg "addon.json already exists" -Type warning -Comment $addon.Name
        if (-not (Confirm-Action "overwrite?")) {
            Write-Msg "cancelled" -Type warning
            return
        }
    }

    $title = Read-Input "title (empty = $($addon.Name))"
    if ($title -eq "") { $title = $addon.Name }

    $types = @("gamemode", "map", "weapon", "vehicle", "npc", "tool", "effects", "model", "servercontent") |
        ForEach-Object { [pscustomobject]@{ Name = $_ } }
    $type = Select-FromList $types "addon type" "type#"
    if (-not $type) { return }

    $tags = @("fun", "roleplay", "scenic", "movie", "realism", "cartoon", "water", "comic", "build") |
        ForEach-Object { New-TreeEntry "" $_ "" }
    $result = Read-Checklist -Title "tags for '$($addon.Name)' (max 2)" -Entries $tags -NoDefaults -Max 2
    if ($result.Cancelled) {
        Write-Msg "cancelled" -Type warning
        return
    }

    $data = [ordered]@{
        title  = $title
        type   = $type.Name
        tags   = @($result.Selected | ForEach-Object { $_.Path })
        ignore = @("*.psd", "*.vcproj", "*.svn*")
    }
    try {
        $json = ConvertTo-Json -InputObject $data -Depth 3
        [System.IO.File]::WriteAllText($path, $json, (New-Object System.Text.UTF8Encoding($false)))
        Write-Msg "addon.json created" -Type success -Comment "$($addon.Name), type $($type.Name)"
    }
    catch {
        Write-Msg "create failed" -Type error -Comment $_.Exception.Message
    }
}

# ---------------------------------------------------------------- main loop
function InteractiveMode {
    Write-Msg "utility for deploying gmod addons" -Comment "tg:@s0nny13"
    Write-Msg "project root" -Comment $script:Root
    Write-Msg "type 'help' to see commands"

    while ($true) {
        [Console]::WriteLine()
        $cmd = Read-Input "DU"
        switch ($cmd) {
            "help"     { PrintHelp }
            "exit"     { return }
            "clear"    { [Console]::Write("${ESC}[2J${ESC}[H") }
            "list"     { PrintAvailableAddons }
            "dlist"    { PrintDeployed }
            "new"      { AddonNew }
            "del"      { DeleteAddon }
            "deploy"   { AddonDeploy }
            "undeploy" { AddonUndeploy }
            "tree"     { ShowTree }
            "fix"      { FixAddon }
            "show"     { ShowAddon }
            "add"      { AddComponent }
            "rm"       { RemoveComponent }
            "aent"     { AddComponent "entity" }
            "dent"     { RemoveComponent "entity" }
            "mkdir"    { MakeDir }
            "touch"    { MakeFile }
            "rmpath"   { RemovePath }
            "json"     { AddonJson }
            ""         { }
            default {
                Write-Msg "unrecognized input" -Type error -Comment $cmd
                PrintHelp
            }
        }
    }
}

Enter-AltScreen
try {
    InteractiveMode
}
finally {
    Exit-AltScreen
}
