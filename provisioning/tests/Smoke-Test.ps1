<#
.SYNOPSIS
  Simple smoke test: ensure connection and print the current site.

.USAGE
  pwsh provisioning/tests/Smoke-Test.ps1
#>

[CmdletBinding()] param()
Set-StrictMode -Version Latest

. "$PSScriptRoot/../Ensure-Connected.ps1"

# Ensure we're connected to the DT_SITE_URL from .env (reconnects if needed)
Ensure-DTConnected

# Prove we can call PnP cmdlets without errors
$web = Get-PnPWeb -Includes Title, Url
Write-Host ("OK: {0} ({1})" -f $web.Title, $web.Url) -ForegroundColor Green