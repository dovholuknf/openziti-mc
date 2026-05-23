#requires -Version 5.1
<#
.SYNOPSIS
    Install OpenZiti MC and its required dependencies into a Minecraft Fabric instance.

.DESCRIPTION
    One-shot installer. Resolves the latest matching version of each required mod for
    the chosen Minecraft version + Fabric loader, downloads everything into the
    instance's mods\ folder, and (optionally) drops your enrolled OpenZiti identity
    .json into the right place.

    Sources:
      OpenZiti MC      -- GitHub Releases (https://github.com/dovholuknf/openziti-mc)
      Fabric API       -- Modrinth
      Architectury API -- Modrinth
      Cloth Config     -- Modrinth
      ModMenu          -- Modrinth

    No Modrinth account or token required -- the public REST API is used.

.PARAMETER MinecraftVersion
    Minecraft version. Default 1.20.1.

.PARAMETER ModsDir
    Target mods directory. Default %APPDATA%\.minecraft\mods (Mojang launcher default).

.PARAMETER ConfigDir
    Mod config directory (for the optional identity .json copy). Default
    %APPDATA%\.minecraft\config.

.PARAMETER OpenZitiVersion
    Specific OpenZiti MC version (without the leading 'v'). Default: latest GitHub
    release.

.PARAMETER IdentityFile
    Path to your enrolled OpenZiti identity .json. If provided (or supplied at the
    prompt), the script copies it to <ConfigDir>\openziti\identity.json.

.PARAMETER NonInteractive
    Skip all prompts. Use defaults and the latest resolved versions.

.EXAMPLE
    # Interactive install -- recommended for first-time users.
    .\install-mods.ps1

.EXAMPLE
    # Run remotely without saving the script:
    iwr https://raw.githubusercontent.com/dovholuknf/openziti-mc/main/scripts/install-mods.ps1 | iex

.EXAMPLE
    # Fully unattended.
    .\install-mods.ps1 -NonInteractive -IdentityFile C:\Users\you\Downloads\client-mc.json
#>

[CmdletBinding()]
param(
    [string] $MinecraftVersion = "1.20.1",
    [string] $ModsDir          = (Join-Path $env:APPDATA ".minecraft\mods"),
    [string] $ConfigDir        = (Join-Path $env:APPDATA ".minecraft\config"),
    [string] $OpenZitiVersion  = "",
    [string] $IdentityFile     = "",
    [switch] $NonInteractive
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

function Write-Banner([string]$text) {
    Write-Host ""
    Write-Host "=== $text ===" -ForegroundColor Cyan
}

function Ask([string]$prompt, [string]$default) {
    if ($NonInteractive) { return $default }
    $shown = if ($default) { "[$default]" } else { "[]" }
    $answer = Read-Host "$prompt $shown"
    if (-not $answer) { return $default }
    return $answer
}

Write-Host ""
Write-Host "OpenZiti MC installer" -ForegroundColor Green
Write-Host "Downloads OpenZiti MC + the four required Fabric dependencies into your"
Write-Host "Minecraft mods folder. Press Enter at any prompt to accept the default."

# -- Inputs ------------------------------------------------------------------

Write-Banner "Settings"
$MinecraftVersion = Ask "Minecraft version" $MinecraftVersion
$ModsDir          = Ask "Mods directory"    $ModsDir
$OpenZitiVersion  = Ask "OpenZiti MC version (blank = latest)" $OpenZitiVersion

# Ensure dirs exist.
if (-not (Test-Path $ModsDir)) {
    Write-Host "Creating $ModsDir"
    New-Item -ItemType Directory -Path $ModsDir -Force | Out-Null
}

# Warn about existing jars.
$existing = Get-ChildItem -Path $ModsDir -Filter "*.jar" -ErrorAction SilentlyContinue
if ($existing.Count -gt 0) {
    Write-Host ""
    Write-Host "$($existing.Count) jar(s) already in $ModsDir :" -ForegroundColor Yellow
    $existing | ForEach-Object { Write-Host "  $($_.Name)" }
    if (-not $NonInteractive) {
        $proceed = Read-Host "Continue? Files with the same name will be overwritten [Y/n]"
        if ($proceed -and $proceed -notmatch '^[Yy]') {
            Write-Host "Aborted." -ForegroundColor Yellow
            return
        }
    }
}

# -- Resolve versions --------------------------------------------------------

Write-Banner "Resolving latest versions for $MinecraftVersion + Fabric"

$plan = @()

# OpenZiti MC from GitHub Releases.
try {
    $url = if ($OpenZitiVersion) {
        $tag = if ($OpenZitiVersion -like 'v*') { $OpenZitiVersion } else { "v$OpenZitiVersion" }
        "https://api.github.com/repos/dovholuknf/openziti-mc/releases/tags/$tag"
    } else {
        "https://api.github.com/repos/dovholuknf/openziti-mc/releases/latest"
    }
    $ghRelease = Invoke-RestMethod -Uri $url -UseBasicParsing
    $asset = $ghRelease.assets `
        | Where-Object { $_.name -like "openziti-fabric-*.jar" `
                          -and $_.name -notlike "*-sources.jar" `
                          -and $_.name -notlike "*-dev-shadow.jar" } `
        | Select-Object -First 1
    if (-not $asset) { throw "No openziti-fabric-*.jar asset in release $($ghRelease.tag_name)." }
    $plan += [PSCustomObject]@{
        source   = "GitHub"
        label    = "OpenZiti MC"
        filename = $asset.name
        url      = $asset.browser_download_url
        size     = $asset.size
    }
} catch {
    Write-Host "Failed to find OpenZiti MC on GitHub: $($_.Exception.Message)" -ForegroundColor Red
    throw
}

# Modrinth dependencies.
$modrinthMods = @(
    @{ slug = "fabric-api";        label = "Fabric API" }
    @{ slug = "architectury-api";  label = "Architectury API" }
    @{ slug = "cloth-config";      label = "Cloth Config" }
    @{ slug = "modmenu";           label = "ModMenu" }
)
$gv = [Uri]::EscapeDataString("[`"$MinecraftVersion`"]")
$ld = [Uri]::EscapeDataString("[`"fabric`"]")

foreach ($mod in $modrinthMods) {
    try {
        $uri = "https://api.modrinth.com/v2/project/$($mod.slug)/version?game_versions=$gv&loaders=$ld"
        $versions = Invoke-RestMethod -Uri $uri -UseBasicParsing
        if (-not $versions -or $versions.Count -eq 0) {
            throw "No $($mod.label) version matches $MinecraftVersion + Fabric. Check that Modrinth has a $($mod.label) build for MC $MinecraftVersion."
        }
        $latest  = $versions[0]
        $primary = $latest.files | Where-Object { $_.primary } | Select-Object -First 1
        if (-not $primary) { $primary = $latest.files[0] }
        $plan += [PSCustomObject]@{
            source   = "Modrinth"
            label    = $mod.label
            filename = $primary.filename
            url      = $primary.url
            size     = $primary.size
        }
    } catch {
        Write-Host "Failed to resolve $($mod.label): $($_.Exception.Message)" -ForegroundColor Red
        throw
    }
}

# -- Show plan + confirm -----------------------------------------------------

Write-Banner "Plan"
$plan | ForEach-Object {
    $sizeMb = [math]::Round($_.size / 1MB, 2)
    Write-Host ("  {0,-22} {1,7} MB  {2}" -f $_.label, $sizeMb, $_.filename)
}
$totalMb = [math]::Round(($plan | Measure-Object -Property size -Sum).Sum / 1MB, 2)
Write-Host ""
Write-Host "  Total: $totalMb MB across $($plan.Count) jars"

if (-not $NonInteractive) {
    $confirm = Read-Host "`nDownload to $ModsDir [Y/n]"
    if ($confirm -and $confirm -notmatch '^[Yy]') {
        Write-Host "Aborted." -ForegroundColor Yellow
        return
    }
}

# -- Download ----------------------------------------------------------------

Write-Banner "Downloading"
foreach ($item in $plan) {
    $dest = Join-Path $ModsDir $item.filename
    $sizeMb = [math]::Round($item.size / 1MB, 2)
    Write-Host ("  {0,7} MB  {1}" -f $sizeMb, $item.filename)
    try {
        Invoke-WebRequest -Uri $item.url -OutFile $dest -UseBasicParsing
    } catch {
        Write-Host "  -> FAILED: $($_.Exception.Message)" -ForegroundColor Red
        throw
    }
}

# -- Optional identity copy --------------------------------------------------

Write-Banner "OpenZiti identity"
if (-not $IdentityFile -and -not $NonInteractive) {
    Write-Host "Optional: drop your enrolled OpenZiti identity .json file in place now."
    Write-Host "Paste the full path to the .json (or press Enter to skip and do it manually later)."
    $IdentityFile = Read-Host "Identity .json path"
}

if ($IdentityFile) {
    if (-not (Test-Path $IdentityFile)) {
        Write-Host "  Identity file not found at: $IdentityFile" -ForegroundColor Red
        Write-Host "  Skipping; copy it manually to:" -ForegroundColor Yellow
        Write-Host "    $ConfigDir\openziti\identity.json"
    } else {
        $destDir  = Join-Path $ConfigDir "openziti"
        $destFile = Join-Path $destDir "identity.json"
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        Copy-Item -Path $IdentityFile -Destination $destFile -Force
        Write-Host "  Identity placed at: $destFile" -ForegroundColor Green
    }
} else {
    Write-Host "  Skipped. Place your enrolled identity at:"
    Write-Host "    $ConfigDir\openziti\identity.json"
}

# -- Done --------------------------------------------------------------------

Write-Banner "Done"
Write-Host "Installed $($plan.Count) jars into $ModsDir." -ForegroundColor Green
Write-Host ""
Write-Host "Launch Minecraft, pick the Fabric 1.20.1 profile, then:"
Write-Host "  Mods -> OpenZiti MC -> Configure  (verify identity path + service name)"
Write-Host "  Multiplayer -> Add Server -> type the OpenZiti service name -> Done -> Join"
Write-Host ""
