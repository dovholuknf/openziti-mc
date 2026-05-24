#requires -Version 5.1
<#
.SYNOPSIS
    Lists active MC version targets from settings.gradle.

.DESCRIPTION
    Parses settings.gradle for uncommented `include "mc-X.Y.Z"` lines and
    emits each MC version (without the "mc-" prefix). Default output is a
    JSON array suitable for a GitHub Actions matrix.

    Runs identically on Windows + Linux (PowerShell Core / pwsh).

.PARAMETER Format
    "json" (default) -- JSON array of strings, single line.
    "plain"          -- one MC version per line.

.EXAMPLE
    ./scripts/list-modules.ps1
    ["1.20","1.20.1","1.20.2","1.20.3","1.20.4","1.20.5","1.20.6","1.21","1.21.1","1.21.2","1.21.3","1.21.4"]
#>

[CmdletBinding()]
param(
    [ValidateSet("json","plain")]
    [string] $Format = "json"
)

$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$settings = Get-Content (Join-Path $repoRoot "settings.gradle")

$modules = New-Object System.Collections.ArrayList
foreach ($line in $settings) {
    # Skip comments (lines starting with // after optional whitespace).
    if ($line -match '^\s*//') { continue }
    if ($line -match '^\s*include\s+"mc-(.+)"\s*$') {
        [void]$modules.Add($matches[1])
    }
}

if ($Format -eq "plain") {
    $modules -join "`n"
} else {
    # Force array output: piping a single-element collection to ConvertTo-Json
    # otherwise yields a scalar, which would break GH Actions matrix.fromJson.
    ConvertTo-Json -Compress -InputObject ([string[]]$modules)
}
