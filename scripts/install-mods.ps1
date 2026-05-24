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

# -- Partition into download vs skip ----------------------------------------

# Skip any planned file that already exists in the mods dir with the matching size.
# A size mismatch usually means a partial download; redownload those.
$toDownload = @()
$toSkip     = @()
foreach ($item in $plan) {
    $dest = Join-Path $ModsDir $item.filename
    if ((Test-Path $dest) -and ((Get-Item $dest).Length -eq $item.size)) {
        $toSkip += $item
    } else {
        $toDownload += $item
    }
}

# Find stale OpenZiti MC jars to remove (different filename from the planned one).
# Without this, Fabric Loader refuses to start with two jars claiming the same mod id.
$openZitiPlan = $plan | Where-Object { $_.label -eq "OpenZiti MC" } | Select-Object -First 1
$toRemove = @()
if ($openZitiPlan) {
    $toRemove = Get-ChildItem -Path $ModsDir -Filter "openziti-fabric-*.jar" -ErrorAction SilentlyContinue `
        | Where-Object { $_.Name -ne $openZitiPlan.filename }
}

# -- Show plan + confirm -----------------------------------------------------

Write-Banner "Plan"
if ($toSkip.Count -gt 0) {
    Write-Host "Already present (will skip):" -ForegroundColor Yellow
    $toSkip | ForEach-Object { Write-Host ("  {0,-22}  {1}" -f $_.label, $_.filename) }
}
if ($toRemove.Count -gt 0) {
    if ($toSkip.Count -gt 0) { Write-Host "" }
    Write-Host "Will remove (stale OpenZiti MC versions, prevents Fabric duplicate-mod conflict):" -ForegroundColor Yellow
    $toRemove | ForEach-Object { Write-Host ("  {0}" -f $_.Name) }
}
if ($toDownload.Count -gt 0) {
    if ($toSkip.Count -gt 0 -or $toRemove.Count -gt 0) { Write-Host "" }
    Write-Host "Will download:"
    $toDownload | ForEach-Object {
        $sizeMb = [math]::Round($_.size / 1MB, 2)
        Write-Host ("  {0,-22}  {1,7} MB  {2}" -f $_.label, $sizeMb, $_.filename)
    }
    $totalMb = [math]::Round(($toDownload | Measure-Object -Property size -Sum).Sum / 1MB, 2)
    Write-Host ""
    Write-Host "  Total: $totalMb MB across $($toDownload.Count) jars"
} else {
    Write-Host "Nothing to download -- all five jars are already in place." -ForegroundColor Green
}

if (($toDownload.Count -gt 0 -or $toRemove.Count -gt 0) -and -not $NonInteractive) {
    $confirm = Read-Host "`nProceed with the above to $ModsDir [Y/n]"
    if ($confirm -and $confirm -notmatch '^[Yy]') {
        Write-Host "Aborted." -ForegroundColor Yellow
        return
    }
}

# -- Download ----------------------------------------------------------------

if ($toDownload.Count -gt 0) {
    Write-Banner "Downloading"
    foreach ($item in $toDownload) {
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
}

# Remove stale OpenZiti MC versions after the new one is in place, so we never leave
# the mods dir in a broken state if a download fails.
if ($toRemove.Count -gt 0) {
    Write-Banner "Removing stale versions"
    foreach ($f in $toRemove) {
        Write-Host "  $($f.Name)"
        try {
            Remove-Item -LiteralPath $f.FullName -Force
        } catch {
            Write-Host "  -> failed to remove $($f.Name): $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

# -- Optional identity copy --------------------------------------------------

Write-Banner "OpenZiti identity"

if (-not $IdentityFile -and -not $NonInteractive) {
    $hasIdentity = Read-Host "Do you have an enrolled OpenZiti identity .json file ready? [y/N]"
    if ($hasIdentity -match '^[Yy]') {
        while (-not $IdentityFile) {
            $candidate = Read-Host "Full path to the identity .json (blank to skip)"
            if (-not $candidate) {
                Write-Host "  Skipping identity placement." -ForegroundColor Yellow
                break
            }
            # Strip surrounding quotes some users paste from Explorer's "Copy as path".
            $candidate = $candidate.Trim('"').Trim("'")
            if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                $IdentityFile = $candidate
            } else {
                Write-Host "  File not found at: $candidate" -ForegroundColor Red
                Write-Host "  Try again or press Enter to skip."
            }
        }
    }
}

if ($IdentityFile) {
    if (-not (Test-Path -LiteralPath $IdentityFile -PathType Leaf)) {
        Write-Host "  Identity file not found at: $IdentityFile" -ForegroundColor Red
        Write-Host "  Copy it manually to:" -ForegroundColor Yellow
        Write-Host "    $ConfigDir\openziti\identity.json"
    } else {
        $destDir  = Join-Path $ConfigDir "openziti"
        $destFile = Join-Path $destDir "identity.json"
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        Copy-Item -LiteralPath $IdentityFile -Destination $destFile -Force
        Write-Host "  Identity placed at: $destFile" -ForegroundColor Green
    }
} else {
    Write-Host "  Skipped. When you have one, copy it to:" -ForegroundColor Yellow
    Write-Host "    $ConfigDir\openziti\identity.json"
}

# -- Done --------------------------------------------------------------------

Write-Banner "Done"
Write-Host "$($plan.Count) jars in place at $ModsDir ($($toSkip.Count) skipped, $($toDownload.Count) downloaded, $($toRemove.Count) stale removed)." -ForegroundColor Green
Write-Host ""
Write-Host "Launch Minecraft, pick the Fabric 1.20.1 profile, then:"
Write-Host "  Mods -> OpenZiti MC -> Configure  (verify identity path + service name)"
Write-Host "  Multiplayer -> Add Server -> type the OpenZiti service name -> Done -> Join"
Write-Host ""
