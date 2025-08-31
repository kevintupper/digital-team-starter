param(
  [Parameter(Mandatory)][string]$SiteUrl,
  [ValidateSet('DeviceCode','Interactive')][string]$AuthMode = 'DeviceCode',
  [string]$LogPath = "$PSScriptRoot/test-connect.log"
)

# dot-source the common helpers
. "$PSScriptRoot/../common.ps1"

# force a fresh connection
$null = Connect-PnPStrict -SiteUrl $SiteUrl -AuthMode $AuthMode -LogPath $LogPath

# run a simple call to prove context
$web = Get-PnPWeb -Includes Title,Url
Write-Host ("Connected OK → {0} ({1})" -f $web.Title, $web.Url) -ForegroundColor Green