<#
.SYNOPSIS
  Connect to SharePoint using values from .env (DeviceCode by default).

.DESCRIPTION
  - Reads .env at repo root (EXACT keys).
  - Connects using PnP.PowerShell:
      * Device Code: -DeviceLogin -Tenant -ClientId   (default, recommended)
      * Interactive: -Interactive                      (if DT_AUTH_MODE=Interactive)
  - No Set-PnPConnection used; relies on PnP session state.
  - Prints site Title/Url to confirm.

.REQUIREMENTS
  - PowerShell 7+ (pwsh)
  - PnP.PowerShell (Install-Module PnP.PowerShell -Scope CurrentUser)
  - Entra App Registration (public client enabled) with delegated permissions:
      SharePoint (Office 365): AllSites.FullControl (or sufficient)
      Graph: User.Read (optionally offline_access, openid, profile)
  - .env at repo root with:
      DT_TENANT_SHORT, DT_TENANT_DOMAIN, DT_SITE_URL, DT_CLIENT_ID, DT_AUTH_MODE

.USAGE
  pwsh provisioning/Connect.ps1
  # Then run other provisioning scripts in the same shell.
#>

[CmdletBinding()]
param([string]$LogPath = "$PSScriptRoot/connect.log", [switch]$ShowEnv)

Set-StrictMode -Version Latest

# Require PnP.PowerShell
if (-not (Get-Module -ListAvailable -Name PnP.PowerShell)) {
  Write-Error "PnP.PowerShell not found. Run: Install-Module PnP.PowerShell -Scope CurrentUser"
  exit 1
}

. "$PSScriptRoot/common.ps1"

try {
  $env = Read-DotEnv

  if ($ShowEnv) {
    Write-Host "---- .env ----" -ForegroundColor Cyan
    "{0,-18}: {1}" -f "DT_TENANT_SHORT",  $env.DT_TENANT_SHORT  | Write-Host
    "{0,-18}: {1}" -f "DT_TENANT_DOMAIN", $env.DT_TENANT_DOMAIN | Write-Host
    "{0,-18}: {1}" -f "DT_SITE_URL",      $env.DT_SITE_URL      | Write-Host
    "{0,-18}: {1}" -f "DT_CLIENT_ID",     $env.DT_CLIENT_ID     | Write-Host
    "{0,-18}: {1}" -f "DT_AUTH_MODE",     $env.DT_AUTH_MODE     | Write-Host
    Write-Host "--------------" -ForegroundColor Cyan
  }

  switch ($env.DT_AUTH_MODE) {
    'Interactive' {
      Connect-PnPOnline -Url $env.DT_SITE_URL -Interactive | Out-Null
    }
    default {
      Connect-PnPOnline -Url $env.DT_SITE_URL `
                        -DeviceLogin `
                        -Tenant $env.DT_TENANT_DOMAIN `
                        -ClientId $env.DT_CLIENT_ID | Out-Null
    }
  }

  $web = Get-PnPWeb -Includes Title, Url
  if (-not $web) { throw "PnP connection failed. Check .env & app registration/consent." }

  Write-Host ("Connected → {0} ({1})" -f $web.Title, $web.Url) -ForegroundColor Green
  "[$(Get-Date -Format s)] Connected $($web.Url)" | Out-File -FilePath $LogPath -Append -Encoding utf8
}
catch {
  Write-Error $_.Exception.Message
  Write-Host "Troubleshooting:" -ForegroundColor Yellow
  Write-Host "  • Verify .env keys and values (tenant, site, client id)." -ForegroundColor Yellow
  Write-Host "  • Ensure App Registration has SharePoint delegated perms and admin consent." -ForegroundColor Yellow
  Write-Host "  • Update PnP module: Update-Module PnP.PowerShell -Force" -ForegroundColor Yellow
  exit 1
}