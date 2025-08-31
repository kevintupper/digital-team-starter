<#
.SYNOPSIS
  Common helpers (forced-connect pattern) for Digital Team Starter scripts.

.DESCRIPTION
  For multi-tenant users, each script should explicitly connect to the target site.
  This module provides:
    - Connect-PnPStrict: always establishes a new PnP connection to a given SiteUrl
    - Write-Log: lightweight console/file logging
    - Invoke-Safely: try/catch wrapper with timing

.USAGE
  . "$PSScriptRoot/common.ps1"

  $conn = Connect-PnPStrict -SiteUrl "https://<tenant>.sharepoint.com/sites/DigitalTeam" -AuthMode Interactive
  # ... call PnP cmdlets ...
#>

Set-StrictMode -Version Latest

function Write-Log {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Message,
    [ValidateSet('Info','Warn','Error','Debug')][string]$Level = 'Info',
    [string]$Path
  )
  $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
  $prefix = "[{0}] [{1}]" -f $ts, $Level.ToUpper()
  switch ($Level) {
    'Info'  { Write-Host    "$prefix $Message" -ForegroundColor Cyan }
    'Warn'  { Write-Warning "$prefix $Message" }
    'Error' { Write-Error   "$prefix $Message" }
    'Debug' { Write-Host    "$prefix $Message" -ForegroundColor DarkGray }
  }
  if ($Path) { "$prefix $Message" | Out-File -FilePath $Path -Append -Encoding utf8 }
}

function Invoke-Safely {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][ScriptBlock]$ScriptBlock,
    [string]$LogPath
  )
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  try {
    Write-Log -Level Info -Message "▶ $Name..." -Path $LogPath
    $out = & $ScriptBlock
    $sw.Stop()
    Write-Log -Level Info -Message "✔ $Name (in $($sw.Elapsed.ToString()))" -Path $LogPath
    return $out
  } catch {
    $sw.Stop()
    Write-Log -Level Error -Message "✖ $Name failed: $($_.Exception.Message)" -Path $LogPath
    throw
  }
}

function Connect-PnPStrict {
<#
.SYNOPSIS
  Always creates a fresh PnP connection to the specified SharePoint site.

.PARAMETER SiteUrl
  Target SharePoint site URL (tenant-qualified). Required.

.PARAMETER AuthMode
  Interactive (default) or DeviceCode. (AppOnly reserved for CI later.)

.PARAMETER LogPath
  Optional log file path.

.OUTPUTS
  Returns the new PnP connection object and sets it as current context.

.EXAMPLE
  $conn = Connect-PnPStrict -SiteUrl "https://contoso.sharepoint.com/sites/DigitalTeam"
#>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$SiteUrl,
    [ValidateSet('Interactive','DeviceCode','AppOnly')][string]$AuthMode = 'Interactive',
    [string]$LogPath
  )

  Write-Log -Level Info -Message "Connecting to $SiteUrl via $AuthMode..." -Path $LogPath

  switch ($AuthMode) {
    'Interactive' { Connect-PnPOnline -Url $SiteUrl -Interactive | Out-Null }
    'DeviceCode'  { Connect-PnPOnline -Url $SiteUrl -DeviceLogin  | Out-Null }
    'AppOnly'     { throw "AuthMode 'AppOnly' not implemented yet (reserved for CI/Runbook)." }
  }

  $conn = Get-PnPConnection
  if (-not $conn) { throw "Connect-PnPStrict: Failed to obtain PnP connection." }

  # Ensure all subsequent PnP cmdlets use this connection
  Set-PnPConnection -Connection $conn
  Write-Log -Level Debug -Message "PnP connection established." -Path $LogPath
  return $conn
}