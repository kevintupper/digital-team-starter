<#
.SYNOPSIS
  Ensure the active PnP context matches .env; reconnect via Connect.ps1 if not.

.DESCRIPTION
  - Loads .env via common.ps1.
  - Uses Test-DTConnected to validate current connection (host + URL prefix).
  - If not connected correctly, calls Connect.ps1 (which reads .env and connects).

.USAGE
  # At the top of any provisioning script:
  . "$PSScriptRoot/Ensure-Connected.ps1"
  Ensure-DTConnected
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
. "$PSScriptRoot/common.ps1"

function Ensure-DTConnected {
  $env = Read-DotEnv
  if (Test-DTConnected -TargetSiteUrl $env.DT_SITE_URL) { return }

  # Reconnect (reads .env, uses Device Code by default)
  & (Join-Path $PSScriptRoot "Connect.ps1") | Out-Null

  # Verify again
  if (-not (Test-DTConnected -TargetSiteUrl $env.DT_SITE_URL)) {
    throw "Ensure-DTConnected: Unable to establish the expected PnP context ($($env.DT_SITE_URL))."
  }
}