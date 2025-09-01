<#
.SYNOPSIS
  Shared helpers for Digital Team Starter scripts (cross-platform, PS7).

.DESCRIPTION
  Provides two utilities:
    1) Read-DotEnv     : Loads repo-root .env into a hashtable with EXACT key names.
    2) Test-DTConnected: Verifies current PnP PowerShell context matches .env DT_SITE_URL.

  Keep this module tiny—no implicit connects. Other scripts decide when to connect.

.USAGE
  . "$PSScriptRoot/common.ps1"
  $env = Read-DotEnv
  if (-not (Test-DTConnected -TargetSiteUrl $env.DT_SITE_URL)) {
    # call Connect.ps1 or fail fast
  }

.ENV FORMAT (repo root; do not commit):
  DT_TENANT_SHORT=yourtenantshort
  DT_TENANT_DOMAIN=yourtenantshort.onmicrosoft.com
  DT_SITE_URL=https://yourtenantshort.sharepoint.com/sites/DigitalTeam
  DT_CLIENT_ID=00000000-0000-0000-0000-000000000000
  DT_AUTH_MODE=DeviceCode   # or Interactive

.RETURNS
  Read-DotEnv     -> [hashtable]
  Test-DTConnected-> [bool]

.REQUIREMENTS
  PowerShell 7+; PnP.PowerShell for Test-DTConnected (already connected).
#>

Set-StrictMode -Version Latest

function Resolve-DotEnvPath {
<#
.SYNOPSIS
  Find repo-root .env by walking upward from this script's folder.

.OUTPUTS
  [string] full path to .env

.THROWS
  If .env cannot be found within 6 levels.
#>
  [CmdletBinding()]
  param([string]$StartFrom = $PSScriptRoot)

  $dir = $StartFrom
  for ($i = 0; $i -lt 6; $i++) {
    $candidate = Join-Path $dir ".env"
    if (Test-Path $candidate) { return $candidate }
    $parent = Split-Path $dir -Parent
    if ([string]::IsNullOrWhiteSpace($parent) -or ($parent -eq $dir)) { break }
    $dir = $parent
  }
  throw "common.ps1: Cannot find .env (expected at repo root)."
}

function Read-DotEnv {
<#
.SYNOPSIS
  Load .env (exact key names) into a hashtable.

.DESCRIPTION
  Reads key=value pairs, preserves EXACT .env key names (no remapping),
  validates required keys, defaults DT_AUTH_MODE to DeviceCode if missing.

.OUTPUTS
  [hashtable] with keys:
    DT_TENANT_SHORT, DT_TENANT_DOMAIN, DT_SITE_URL, DT_CLIENT_ID, DT_AUTH_MODE
#>
  [CmdletBinding()]
  param([string]$Path = (Resolve-DotEnvPath))

  $envMap = @{}
  foreach ($line in Get-Content -Path $Path) {
    $t = $line.Trim()
    if ($t -eq '' -or $t.StartsWith('#')) { continue }
    $pair = $t -split '=', 2
    if ($pair.Count -eq 2) {
      $k = $pair[0].Trim()
      $v = $pair[1].Trim().Trim('"')
      $envMap[$k] = $v
    }
  }

  foreach ($required in @('DT_TENANT_SHORT','DT_TENANT_DOMAIN','DT_SITE_URL','DT_CLIENT_ID')) {
    if (-not $envMap.ContainsKey($required) -or [string]::IsNullOrWhiteSpace($envMap[$required])) {
      throw "common.ps1: Missing $required in .env"
    }
  }
  if (-not $envMap.ContainsKey('DT_AUTH_MODE') -or [string]::IsNullOrWhiteSpace($envMap['DT_AUTH_MODE'])) {
    $envMap['DT_AUTH_MODE'] = 'DeviceCode'
  }

  return $envMap
}

function Test-DTConnected {
<#
.SYNOPSIS
  Return $true if the current PnP context is connected to DT_SITE_URL.

.PARAMETER TargetSiteUrl
  The DT_SITE_URL from .env.

.RETURNS
  [bool] $true if host matches and current URL starts with TargetSiteUrl (case-insensitive).
#>
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$TargetSiteUrl)

  try {
    $web = Get-PnPWeb -Includes Url -ErrorAction Stop
    if (-not $web -or [string]::IsNullOrWhiteSpace($web.Url)) { return $false }
  } catch { return $false }

  try {
    $currentUri = [Uri]$web.Url
    $targetUri  = [Uri]$TargetSiteUrl
  } catch { return $false }

  $hostMatches   = ($currentUri.Host -ieq $targetUri.Host)
  $prefixMatches = $web.Url.StartsWith($TargetSiteUrl, [System.StringComparison]::OrdinalIgnoreCase)

  return ($hostMatches -and $prefixMatches)
}