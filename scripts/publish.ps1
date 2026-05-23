#requires -Version 5.1
<#
.SYNOPSIS
    Builds the ziti-minecraft Fabric jar and publishes a release.

.DESCRIPTION
    Self-contained release pipeline. Uploads to Modrinth via its REST API and creates a
    GitHub Release with the jar attached. Either upload can be skipped by omitting the
    matching token, which is useful for dry-runs.

    Runs identically from a developer workstation and from GitHub Actions; the workflow
    only checks out code, sets up the JDK, and invokes this script with secrets passed
    as parameters.

.PARAMETER Version
    Semantic version for this release, e.g. "0.1.0". Must match the gradle.properties
    `mod_version` so the built jar's filename lines up. The script verifies this.

.PARAMETER SkipBuild
    Skip `./gradlew :fabric:build`. Use when the jar is already built and you just want
    to re-upload.

.PARAMETER ModrinthToken
    Modrinth API token (https://modrinth.com/settings/account). Pass empty string to
    skip Modrinth upload.

.PARAMETER ModrinthProjectId
    Modrinth project ID (the short slug or the long ID from the project URL). Required
    if ModrinthToken is provided.

.PARAMETER GitHubToken
    GitHub token with `contents: write` permission. In GH Actions this is the
    automatically-provided GITHUB_TOKEN. Pass empty string to skip the GitHub Release.

.PARAMETER GitHubRepo
    Repo in `owner/name` form, e.g. `dovholuknf/openziti-mc`. Required if
    GitHubToken is provided.

.PARAMETER Changelog
    Release notes / changelog text. Used for both Modrinth and GitHub Release bodies.
    Defaults to a placeholder.

.PARAMETER GameVersions
    MC versions this release is compatible with. Modrinth metadata.

.PARAMETER Loaders
    Mod loaders this release targets. Modrinth metadata.

.PARAMETER VersionType
    "release", "beta", or "alpha". Modrinth metadata.

.EXAMPLE
    # Dry run: build only, no uploads.
    .\scripts\publish.ps1 -Version 0.1.0

.EXAMPLE
    # Full release.
    .\scripts\publish.ps1 -Version 0.1.0 `
        -ModrinthToken $env:MODRINTH_TOKEN -ModrinthProjectId zitimc `
        -GitHubToken $env:GITHUB_TOKEN -GitHubRepo dovholuknf/openziti-mc `
        -Changelog "First public release. Routes Minecraft over OpenZiti."
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
    [string[]]                        $GameVersions      = @("1.20.1"),
    [string[]]                        $Loaders           = @("fabric"),
    [ValidateSet("release","beta","alpha")]
    [string]                          $VersionType       = "release"
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location $repoRoot

# -------------------------------------------------------------------------
# 1. Sanity: the requested version must match the version in gradle.properties.
# -------------------------------------------------------------------------

$gradleProps     = Get-Content (Join-Path $repoRoot "gradle.properties")
$gradleVersion   = ($gradleProps | Select-String '^mod_version=(.+)$').Matches[0].Groups[1].Value.Trim()
if ($gradleVersion -ne $Version) {
    throw "Requested version '$Version' does not match gradle.properties mod_version '$gradleVersion'. Bump gradle.properties first."
}

# -------------------------------------------------------------------------
# 2. Build (unless skipped).
# -------------------------------------------------------------------------

if (-not $SkipBuild) {
    Write-Host "Building :fabric:build ..."
    & ./gradlew :fabric:build --no-daemon
    if ($LASTEXITCODE -ne 0) { throw "Gradle build failed (exit $LASTEXITCODE)." }
}

$jarPath = Join-Path $repoRoot "fabric/build/libs/openziti-fabric-$Version.jar"
if (-not (Test-Path $jarPath)) {
    throw "Built jar not found at $jarPath. Did the build succeed?"
}
$jarFile = Get-Item $jarPath
Write-Host "Jar: $($jarFile.FullName) ($([math]::Round($jarFile.Length / 1MB, 2)) MB)"

# -------------------------------------------------------------------------
# 3. Modrinth upload.
# -------------------------------------------------------------------------

if ($ModrinthToken) {
    if (-not $ModrinthProjectId) { throw "ModrinthProjectId is required when ModrinthToken is set." }

    $modrinthHeaders = @{
        Authorization = $ModrinthToken
        "User-Agent"  = "dovholuknf/openziti-mc publish.ps1"
    }

    # Modrinth's /v2/version API wants the project's base62 short ID, not the slug.
    # Resolve via /v2/project/{slug-or-id} which accepts either and returns the canonical id.
    Write-Host "Resolving Modrinth project '$ModrinthProjectId' ..."
    try {
        $projectInfo = Invoke-RestMethod -Method Get -Uri "https://api.modrinth.com/v2/project/$ModrinthProjectId" -Headers $modrinthHeaders
        $resolvedProjectId = $projectInfo.id
        Write-Host "  -> ID: $resolvedProjectId (slug: $($projectInfo.slug))"
    }
    catch {
        $errBody = if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $_.ErrorDetails.Message } else { "" }
        throw "Failed to look up Modrinth project '$ModrinthProjectId': $($_.Exception.Message)`n$errBody"
    }

    Write-Host "Uploading to Modrinth (project=$resolvedProjectId, version=$Version) ..."

    $metadata = @{
        name           = "ziti-minecraft $Version"
        version_number = $Version
        version_type   = $VersionType
        loaders        = $Loaders
        game_versions  = $GameVersions
        featured       = $false
        dependencies   = @(
            @{ project_id = "P7dR8mSH"; dependency_type = "required" }   # Fabric API
            @{ project_id = "lhGA9TYQ"; dependency_type = "required" }   # Architectury API
        )
        project_id     = $resolvedProjectId
        file_parts     = @("file_0")
        primary_file   = "file_0"
        changelog      = $Changelog
    } | ConvertTo-Json -Depth 5 -Compress

    $boundary  = [System.Guid]::NewGuid().ToString("N")
    $lf        = "`r`n"
    $jarBytes  = [System.IO.File]::ReadAllBytes($jarPath)
    $enc       = [System.Text.Encoding]::UTF8

    $bodyStream = New-Object System.IO.MemoryStream
    $bw         = New-Object System.IO.BinaryWriter($bodyStream)

    function Append-StringPart {
        param($writer, $boundary, $name, $value)
        $part  = "--$boundary$lf"
        $part += "Content-Disposition: form-data; name=`"$name`"$lf$lf"
        $part += "$value$lf"
        $writer.Write($enc.GetBytes($part))
    }

    function Append-FilePart {
        param($writer, $boundary, $name, $filename, $bytes)
        $header  = "--$boundary$lf"
        $header += "Content-Disposition: form-data; name=`"$name`"; filename=`"$filename`"$lf"
        $header += "Content-Type: application/java-archive$lf$lf"
        $writer.Write($enc.GetBytes($header))
        $writer.Write($bytes)
        $writer.Write($enc.GetBytes($lf))
    }

    Append-StringPart $bw $boundary "data"   $metadata
    Append-FilePart   $bw $boundary "file_0" $jarFile.Name $jarBytes
    $bw.Write($enc.GetBytes("--$boundary--$lf"))
    $bw.Flush()
    $bodyBytes = $bodyStream.ToArray()

    try {
        $resp = Invoke-RestMethod -Method Post -Uri "https://api.modrinth.com/v2/version" `
            -Headers $modrinthHeaders -ContentType "multipart/form-data; boundary=$boundary" `
            -Body $bodyBytes
        Write-Host "  -> Modrinth version id: $($resp.id)"
        Write-Host "  -> https://modrinth.com/mod/$($projectInfo.slug)/version/$($resp.version_number)"
    }
    catch {
        # PS 7+: response body lives on ErrorDetails.Message
        # PS 5.1: also has ErrorDetails.Message for Invoke-RestMethod failures
        $errBody = if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $_.ErrorDetails.Message } else { "" }
        throw "Modrinth upload failed: $($_.Exception.Message)`n$errBody"
    }
}
else {
    Write-Host "Modrinth upload skipped (no token)."
}

# -------------------------------------------------------------------------
# 4. GitHub Release.
# -------------------------------------------------------------------------

if ($GitHubToken) {
    if (-not $GitHubRepo) { throw "GitHubRepo is required when GitHubToken is set." }

    $tag = "v$Version"
    Write-Host "Creating GitHub Release $tag in $GitHubRepo ..."

    $createBody = @{
        tag_name = $tag
        name     = $tag
        body     = $Changelog
        draft    = $false
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
    }
    catch {
        throw "GitHub Release creation failed: $($_.Exception.Message)"
    }

    Write-Host "  -> Release id: $($release.id)"
    Write-Host "  -> $($release.html_url)"

    Write-Host "Uploading jar asset ..."
    $uploadUrl   = $release.upload_url -replace '\{\?.*\}', ""
    $uploadUrl  += "?name=$($jarFile.Name)"
    $assetHeaders = @{
        Authorization = "Bearer $GitHubToken"
        Accept        = "application/vnd.github+json"
        "User-Agent"  = "dovholuknf/openziti-mc publish.ps1"
    }
    $assetResp = Invoke-RestMethod -Method Post -Uri $uploadUrl `
        -Headers $assetHeaders -ContentType "application/java-archive" `
        -InFile $jarPath
    Write-Host "  -> Asset: $($assetResp.browser_download_url)"
}
else {
    Write-Host "GitHub Release skipped (no token)."
}

Write-Host ""
Write-Host "Done."
