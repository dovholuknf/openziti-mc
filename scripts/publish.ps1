#requires -Version 5.1
<#
.SYNOPSIS
    Builds and publishes a multi-MC-version OpenZiti MC release.

.DESCRIPTION
    Self-contained release pipeline. Builds one jar per supported Minecraft version
    (mc-1.20.1, mc-1.21.1, mc-1.21.4), then:
      - creates ONE GitHub Release with all three jars attached.
      - creates ONE Modrinth version PER MC target, each tagged with that single
        MC version (Modrinth filters by game_versions, so a separate version per
        target is the standard pattern).

    Runs identically from a developer workstation and from GitHub Actions.

.PARAMETER Version
    Semantic version for this release, e.g. "0.3.0". Must match gradle.properties
    mod_version.

.PARAMETER SkipBuild
    Skip the gradle build (jars must already exist under each module's build/libs).

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
    # Dry run -- build everything, no uploads.
    .\scripts\publish.ps1 -Version 0.3.0

.EXAMPLE
    # Full release.
    .\scripts\publish.ps1 -Version 0.3.0 `
        -ModrinthToken $env:MODRINTH_TOKEN -ModrinthProjectId openziti-mc `
        -GitHubToken $env:GITHUB_TOKEN -GitHubRepo dovholuknf/openziti-mc `
        -Changelog "Multi-version release: 1.20.1, 1.21.1, 1.21.4."
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]   $Version,
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
# Layout: the modules we ship a jar for. Add a new MC version by adding a row.
# -------------------------------------------------------------------------

$targets = @(
    [PSCustomObject]@{ module = "mc-1.20.1"; mc = "1.20.1" }
    [PSCustomObject]@{ module = "mc-1.21.1"; mc = "1.21.1" }
    [PSCustomObject]@{ module = "mc-1.21.4"; mc = "1.21.4" }
)

# -------------------------------------------------------------------------
# 1. Sanity: requested version must match gradle.properties mod_version.
# -------------------------------------------------------------------------

$gradleProps   = Get-Content (Join-Path $repoRoot "gradle.properties")
$gradleVersion = ($gradleProps | Select-String '^mod_version=(.+)$').Matches[0].Groups[1].Value.Trim()
if ($gradleVersion -ne $Version) {
    throw "Requested version '$Version' does not match gradle.properties mod_version '$gradleVersion'. Bump gradle.properties first."
}

# -------------------------------------------------------------------------
# 2. Build all modules in one shot.
# -------------------------------------------------------------------------

if (-not $SkipBuild) {
    Write-Host "Building all modules ..."
    & ./gradlew build --no-daemon
    if ($LASTEXITCODE -ne 0) { throw "Gradle build failed (exit $LASTEXITCODE)." }
}

# Resolve the produced jar for each target.
foreach ($t in $targets) {
    $jarName = "openziti-mc-$Version.mc$($t.mc).jar"
    $jarPath = Join-Path $repoRoot "$($t.module)/build/libs/$jarName"
    if (-not (Test-Path $jarPath)) {
        throw "Built jar not found at $jarPath. Did :$($t.module):build succeed?"
    }
    $jar = Get-Item $jarPath
    Add-Member -InputObject $t -NotePropertyName jarPath -NotePropertyValue $jar.FullName
    Add-Member -InputObject $t -NotePropertyName jarName -NotePropertyValue $jar.Name
    Add-Member -InputObject $t -NotePropertyName jarSize -NotePropertyValue $jar.Length
    Write-Host ("  {0,-10}  {1,7:F2} MB  {2}" -f $t.mc, ($jar.Length / 1MB), $jar.Name)
}

# -------------------------------------------------------------------------
# 3. Modrinth uploads -- one version per MC target.
# -------------------------------------------------------------------------

if ($ModrinthToken) {
    if (-not $ModrinthProjectId) { throw "ModrinthProjectId is required when ModrinthToken is set." }

    $modrinthHeaders = @{
        Authorization = $ModrinthToken
        "User-Agent"  = "dovholuknf/openziti-mc publish.ps1"
    }

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
# 4. GitHub Release -- one release with all three jars attached.
# -------------------------------------------------------------------------

if ($GitHubToken) {
    if (-not $GitHubRepo) { throw "GitHubRepo is required when GitHubToken is set." }

    $tag = "v$Version"
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
