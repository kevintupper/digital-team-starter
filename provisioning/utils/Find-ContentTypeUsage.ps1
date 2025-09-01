<#
.SYNOPSIS
  Report every web/list in this site collection that still uses a given site content type.

.USAGE
  pwsh provisioning/Connect.ps1                # connect once
  pwsh provisioning/utils/Find-ContentTypeUsage.ps1 -Id "0x0101001BB999DF308D0542A1641C8A32C82B79"
  # or by name (case-insensitive):
  pwsh provisioning/utils/Find-ContentTypeUsage.ps1 -Name "Kb Article"
#>

[CmdletBinding()]
param(
  [string]$Id,
  [string]$Name
)

Set-StrictMode -Version Latest

. "$PSScriptRoot/../common.ps1"
. "$PSScriptRoot/../Ensure-Connected.ps1"
Ensure-DTConnected

# Resolve site CT by Id or Name once at the root web
function Resolve-SiteCT {
  param([string]$Id,[string]$Name)
  if ($Id) {
    $ct = Get-PnPContentType -Identity $Id -ErrorAction SilentlyContinue
    if ($ct) { return $ct } else { throw "Site CT id '$Id' not found on root web." }
  }
  if (-not $Name) { throw "Specify -Id or -Name." }
  $cts = @(Get-PnPContentType)
  $m   = @($cts | Where-Object { $_.Name -eq  $Name })
  if ($m.Count -eq 0) { $m = @($cts | Where-Object { $_.Name -ieq $Name }) }
  if ($m.Count -eq 0) { throw "Site CT named '$Name' not found on root web." }
  if ($m.Count -gt 1) { throw "Multiple site CTs named '$Name'. Use -Id." }
  return $m[0]
}

$ct = Resolve-SiteCT -Id $Id -Name $Name
$ctIdPrefix = $ct.StringId

# Get all webs (root + subsites)
$rootWeb = Get-PnPWeb -Includes Title, Url
$webs    = @([PSCustomObject]@{ Title=$rootWeb.Title; Url=$rootWeb.Url })

# Include subsites, if any (modern sites often have none)
$subs = @(Get-PnPSubWeb -Recurse -IncludeRootWeb:$false -ErrorAction SilentlyContinue)
foreach ($w in $subs) { $webs += [PSCustomObject]@{ Title=$w.Title; Url=$w.Url } }

Write-Host ("Scanning {0} web(s) for CT '{1}'…" -f $webs.Count, $ct.Name) -ForegroundColor Cyan

# We’ll reuse your .env to switch context to each web silently (token cache should avoid extra prompts)
$env = Read-DotEnv

$hits = @()
foreach ($w in $webs) {
  # switch context to this web
  try {
    Connect-PnPOnline -Url $w.Url -DeviceLogin -Tenant $env.DT_TENANT_DOMAIN -ClientId $env.DT_CLIENT_ID | Out-Null
  } catch { Write-Verbose "Reconnect to $($w.Url) failed: $($_.Exception.Message)"; continue }

  $lists = @(Get-PnPList -Includes Title, RootFolder, Hidden -ErrorAction SilentlyContinue)
  foreach ($l in $lists) {
    # only lists that actually support content types will return list CTs
    $listCTs = @(Get-PnPContentType -List $l -ErrorAction SilentlyContinue)
    if ($listCTs.Count -eq 0) { continue }

    $match = @($listCTs | Where-Object { $_.StringId -like "$ctIdPrefix*" })
    if ($match.Count -gt 0) {
      $relPath = $l.RootFolder.ServerRelativeUrl
      $hits += [PSCustomObject]@{
        WebTitle = $w.Title
        WebUrl   = $w.Url
        List     = $l.Title
        ListUrl  = "$($env.DT_TENANT_DOMAIN) $relPath"
        CTName   = $match[0].Name
        CTId     = $match[0].StringId
      }
      Write-Host ("• {0}  |  {1}" -f $w.Url, $l.Title) -ForegroundColor Yellow
    }
  }
}

if ($hits.Count -eq 0) {
  Write-Host "No remaining list usages found for CT '$($ct.Name)'." -ForegroundColor Green
} else {
  Write-Host "`nSummary:" -ForegroundColor Cyan
  $hits | Format-Table WebTitle, List, CTName, CTId, WebUrl -AutoSize
}