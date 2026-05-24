#requires -Version 5.1
<#
.SYNOPSIS
    Publishes a multi-MC-version OpenZiti MC release.

.DESCRIPTION
    Self-contained release pipeline. Two modes:

      1. **Local mode** (default): builds every active `mc-X.Y.Z` module via
         `./gradlew build`, then enumerates the produced jars under
         `mc-*/build/libs/openziti-mc-<Version>.mc*.jar`.

      2. **Artifacts mode** (`-ArtifactsDir <dir>`): skips the build and
         enumerates jars under that directory (recursively). Used by the
         matrix release workflow: each matrix job builds one module and
         uploads the jar as an artifact; the final release job downloads all
         artifacts into one dir and runs publish.ps1 over it.

    Both modes converge on the same upload flow:
      - one Modrinth version per MC target, tagged with that single MC version
      - one GitHub Release with every jar attached

    Adding a new MC version requires only an `include "mc-X.Y.Z"` line in
    settings.gradle plus the module dir; publish.ps1 discovers it from the
    filesystem and no longer needs a hardcoded list.

.PARAMETER Version
    Semantic version for this release, e.g. "0.3.3". Must match
    gradle.properties mod_version.

.PARAMETER ArtifactsDir
    Optional directory containing pre-built jars (matrix-build flow). When
    set, skips the local gradle build and scans this dir recursively for
    `openziti-mc-<Version>.mc*.jar` files (the -dev-shadow and -sources jars
    are ignored).

.PARAMETER SkipBuild
    Local mode only: skip `./gradlew build` even though no ArtifactsDir was
    supplied. The jars must already exist under each module's build/libs.

.PARAMETER ModrinthToken
    Modrinth API token. Empty = skip Modrinth.

.PARAMETER ModrinthProjectId
    Modrinth slug or short ID. Required when ModrinthToken is set.

.PARAMETER GitHubToken
    GitHub token with contents: write. In Actions this is the auto-provided
    GITHUB_TOKEN. Empty = skip GitHub Release.

.PARAMETER GitHubRepo
    "owner/name", e.g. dovholuknf/openziti-mc. Required when GitHubToken is set.

.PARAMETER Changelog
    Release notes body. Used for both Modrinth and GitHub Release.

.PARAMETER VersionType
    "release", "beta", or "alpha". Modrinth metadata.

.EXAMPLE
    # Dry run, local: build everything, no uploads.
    .\scripts\publish.ps1 -Version 0.3.3

.EXAMPLE
    # Full local release.
    .\scripts\publish.ps1 -Version 0.3.3 `
        -ModrinthToken $env:MODRINTH_TOKEN -ModrinthProjectId openziti-mc `
        -GitHubToken $env:GITHUB_TOKEN -GitHubRepo dovholuknf/openziti-mc `
        -Changelog "Matrix build + 9 more MC version targets."

.EXAMPLE
    # CI artifacts mode (after matrix build).
    .\scripts\publish.ps1 -Version 0.3.3 -ArtifactsDir artifacts `
        -ModrinthToken $env:MODRINTH_TOKEN -ModrinthProjectId openziti-mc `
        -GitHubToken $env:GITHUB_TOKEN -GitHubRepo dovholuknf/openziti-mc
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]   $Version,
    [string]                          $ArtifactsDir      = "",
    [switch]                          $SkipBuild,
    [string]                          $ModrinthToken     = "",
    [string]                          $ModrinthProjectId = "",
    [string]                          $GitHubToken       = "",
    [string]                          $GitHubRepo        = "",
    [string]                          $Changelog         = "See repository for release notes.",
    [ValidateSet("release","beta","alpha")]
    [string]                          $VersionType       = "release"
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location $repoRoot

# -------------------------------------------------------------------------
# 1. Sanity: requested version must match gradle.properties mod_version.
# -------------------------------------------------------------------------

$gradleProps   = Get-Content (Join-Path $repoRoot "gradle.properties")
$gradleVersion = ($gradleProps | Select-String '^mod_version=(.+)$').Matches[0].Groups[1].Value.Trim()
if ($gradleVersion -ne $Version) {
    throw "Requested version '$Version' does not match gradle.properties mod_version '$gradleVersion'. Bump gradle.properties first."
}

# -------------------------------------------------------------------------
# 2. Build (local mode only).
# -------------------------------------------------------------------------

if (-not $ArtifactsDir -and -not $SkipBuild) {
    Write-Host "Building every active mc-* module via ./gradlew build ..."
    & ./gradlew build --no-daemon
    if ($LASTEXITCODE -ne 0) { throw "Gradle build failed (exit $LASTEXITCODE)." }
}

# -------------------------------------------------------------------------
# 3. Discover jars and infer the MC target from each filename.
#    Naming convention: openziti-mc-<Version>.mc<MC>.jar
# -------------------------------------------------------------------------

if ($ArtifactsDir) {
    if (-not (Test-Path $ArtifactsDir)) {
        throw "ArtifactsDir '$ArtifactsDir' does not exist."
    }
    $jarRoot = (Resolve-Path $ArtifactsDir).Path
    Write-Host "Using pre-built jars from $jarRoot"
} else {
    $jarRoot = Join-Path $repoRoot "."
    Write-Host "Discovering jars under mc-*/build/libs/ ..."
}

# Match openziti-mc-<exact version>.mc<MC>.jar where <MC> is strictly
# digits-and-dots. Rejects Loom's intermediate -dev.jar, -dev-shadow.jar,
# and -sources.jar variants because their classifier follows the MC version
# with a literal "-" which the pattern doesn't allow.
$verEscaped = [regex]::Escape($Version)
$jarRegex   = "^openziti-mc-$verEscaped\.mc(\d+(?:\.\d+)*)\.jar$"

$targets = New-Object System.Collections.ArrayList
$allJars = Get-ChildItem -Path $jarRoot -Filter "openziti-mc-*.jar" -Recurse -File
foreach ($jar in $allJars) {
    if ($jar.Name -match $jarRegex) {
        $mc = $matches[1]
        [void]$targets.Add([PSCustomObject]@{
            mc      = $mc
            jarPath = $jar.FullName
            jarName = $jar.Name
            jarSize = $jar.Length
        })
    }
}

if ($targets.Count -eq 0) {
    throw "No jars matching 'openziti-mc-$Version.mc*.jar' found under $jarRoot. Build first, or pass -ArtifactsDir to a directory containing them."
}

# Sort MC versions naturally (so "1.20" < "1.20.1" < "1.21" etc.) by
# splitting each version into its dotted components and comparing as ints.
$targets = $targets | Sort-Object {
    $parts = $_.mc.Split('.') | ForEach-Object { [int]$_ }
    # Pad to 4 parts so 1.21 sorts before 1.21.1.
    while ($parts.Count -lt 4) { $parts += -1 }
    [int64]($parts[0] * 1000000000 + $parts[1] * 1000000 + ($parts[2] + 1) * 1000 + ($parts[3] + 1))
}

Write-Host ""
Write-Host "Targets to publish ($($targets.Count)):"
foreach ($t in $targets) {
    Write-Host ("  {0,-10}  {1,7:F2} MB  {2}" -f $t.mc, ($t.jarSize / 1MB), $t.jarName)
}

# -------------------------------------------------------------------------
# 4. Modrinth uploads -- one version per MC target.
# -------------------------------------------------------------------------

if ($ModrinthToken) {
    if (-not $ModrinthProjectId) { throw "ModrinthProjectId is required when ModrinthToken is set." }

    $modrinthHeaders = @{
        Authorization = $ModrinthToken
        "User-Agent"  = "dovholuknf/openziti-mc publish.ps1"
    }

    Write-Host ""
    Write-Host "Resolving Modrinth project '$ModrinthProjectId' ..."
    try {
        $projectInfo       = Invoke-RestMethod -Method Get -Uri "https://api.modrinth.com/v2/project/$ModrinthProjectId" -Headers $modrinthHeaders
        $resolvedProjectId = $projectInfo.id
        Write-Host "  -> ID: $resolvedProjectId (slug: $($projectInfo.slug))"
    } catch {
        $errBody = if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $_.ErrorDetails.Message } else { "" }
        throw "Failed to look up Modrinth project '$ModrinthProjectId': $($_.Exception.Message)`n$errBody"
    }

    foreach ($t in $targets) {
        # Use "." separator so the Modrinth version_number matches the GitHub asset
        # filename (GitHub sanitizes "+" to "." in asset names).
        $modrinthVersion = "$Version.mc$($t.mc)"
        Write-Host "Uploading to Modrinth: $modrinthVersion (mc=$($t.mc)) ..."

        $metadata = @{
            name           = "OpenZiti MC $modrinthVersion"
            version_number = $modrinthVersion
            version_type   = $VersionType
            loaders        = @("fabric")
            game_versions  = @($t.mc)
            featured       = $false
            dependencies   = @(
                @{ project_id = "P7dR8mSH"; dependency_type = "required" }   # Fabric API
            )
            project_id     = $resolvedProjectId
            file_parts     = @("file_0")
            primary_file   = "file_0"
            changelog      = $Changelog
        } | ConvertTo-Json -Depth 5 -Compress

        $boundary  = [System.Guid]::NewGuid().ToString("N")
        $lf        = "`r`n"
        $jarBytes  = [System.IO.File]::ReadAllBytes($t.jarPath)
        $enc       = [System.Text.Encoding]::UTF8

        $bodyStream = New-Object System.IO.MemoryStream
        $bw         = New-Object System.IO.BinaryWriter($bodyStream)

        $part  = "--$boundary$lf"
        $part += "Content-Disposition: form-data; name=`"data`"$lf$lf"
        $part += "$metadata$lf"
        $bw.Write($enc.GetBytes($part))

        $header  = "--$boundary$lf"
        $header += "Content-Disposition: form-data; name=`"file_0`"; filename=`"$($t.jarName)`"$lf"
        $header += "Content-Type: application/java-archive$lf$lf"
        $bw.Write($enc.GetBytes($header))
        $bw.Write($jarBytes)
        $bw.Write($enc.GetBytes($lf))
        $bw.Write($enc.GetBytes("--$boundary--$lf"))
        $bw.Flush()
        $bodyBytes = $bodyStream.ToArray()

        try {
            $resp = Invoke-RestMethod -Method Post -Uri "https://api.modrinth.com/v2/version" `
                -Headers $modrinthHeaders -ContentType "multipart/form-data; boundary=$boundary" `
                -Body $bodyBytes
            Write-Host "  -> Modrinth version id: $($resp.id)"
            Write-Host "  -> https://modrinth.com/mod/$($projectInfo.slug)/version/$($resp.version_number)"
        } catch {
            $errBody = if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $_.ErrorDetails.Message } else { "" }
            throw "Modrinth upload failed for $modrinthVersion : $($_.Exception.Message)`n$errBody"
        }
    }
} else {
    Write-Host "Modrinth upload skipped (no token)."
}

# -------------------------------------------------------------------------
# 5. GitHub Release -- one release with every jar attached.
# -------------------------------------------------------------------------

if ($GitHubToken) {
    if (-not $GitHubRepo) { throw "GitHubRepo is required when GitHubToken is set." }

    $tag = "v$Version"
    Write-Host ""
    Write-Host "Creating GitHub Release $tag in $GitHubRepo ..."

    $createBody = @{
        tag_name   = $tag
        name       = $tag
        body       = $Changelog
        draft      = $false
        prerelease = ($VersionType -ne "release")
    } | ConvertTo-Json -Compress

    $ghHeaders = @{
        Authorization          = "Bearer $GitHubToken"
        Accept                 = "application/vnd.github+json"
        "X-GitHub-Api-Version" = "2022-11-28"
        "User-Agent"           = "dovholuknf/openziti-mc publish.ps1"
    }

    try {
        $release = Invoke-RestMethod -Method Post `
            -Uri "https://api.github.com/repos/$GitHubRepo/releases" `
            -Headers $ghHeaders -ContentType "application/json" -Body $createBody
    } catch {
        throw "GitHub Release creation failed: $($_.Exception.Message)"
    }

    Write-Host "  -> Release id: $($release.id)"
    Write-Host "  -> $($release.html_url)"

    $assetHeaders = @{
        Authorization = "Bearer $GitHubToken"
        Accept        = "application/vnd.github+json"
        "User-Agent"  = "dovholuknf/openziti-mc publish.ps1"
    }
    foreach ($t in $targets) {
        Write-Host "Uploading $($t.jarName) ..."
        $uploadUrl  = $release.upload_url -replace '\{\?.*\}', ""
        $uploadUrl += "?name=$($t.jarName)"
        $assetResp = Invoke-RestMethod -Method Post -Uri $uploadUrl `
            -Headers $assetHeaders -ContentType "application/java-archive" `
            -InFile $t.jarPath
        Write-Host "  -> $($assetResp.browser_download_url)"
    }
} else {
    Write-Host "GitHub Release skipped (no token)."
}

Write-Host ""
Write-Host "Done."
