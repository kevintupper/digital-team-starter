# provisioning/utils/Remove-SiteContentType.ps1  (fixed)
[CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
param(
  [string]$Id,
  [string]$Name,
  [int]$PageSize = 1000
)

Set-StrictMode -Version Latest
. "$PSScriptRoot/../Ensure-Connected.ps1"
Ensure-DTConnected

function Resolve-SiteCT {
  param([string]$Id,[string]$Name)
  if ($Id) {
    $ct = Get-PnPContentType -Identity $Id -ErrorAction SilentlyContinue
    if ($ct) { return $ct }  else { throw "Site content type Id '$Id' not found." }
  }
  if (-not $Name) { throw "Specify -Id or -Name." }
  $cts       = @(Get-PnPContentType)
  $ctMatches = @($cts | Where-Object { $_.Name -eq  $Name })
  if ($ctMatches.Count -eq 0) { $ctMatches = @($cts | Where-Object { $_.Name -ieq $Name }) }
  if ($ctMatches.Count -eq 0) { throw "Site content type named '$Name' not found." }
  if ($ctMatches.Count -gt 1) { throw "Multiple site CTs named '$Name'. Use -Id instead." }
  return $ctMatches[0]
}

function Detach-From-List {
  param(
    [Microsoft.SharePoint.Client.List]$List,
    [string]$TargetCtIdPrefix,
    [int]$PageSize = 1000
  )

  $origEnabled = $List.ContentTypesEnabled
  $canManage   = $true

  # Try to enable CTs if currently off; some lists simply don't allow it → skip
  if (-not $origEnabled) {
    try {
      Set-PnPList -Identity $List -EnableContentTypes $true | Out-Null
    } catch {
      Write-Verbose ("  • Skipping list '{0}': does not allow content types." -f $List.Title)
      return
    }
  }

  # Re-fetch to get current flags (if the toggle worked)
  $List = Get-PnPList -Identity $List
  if (-not $List.ContentTypesEnabled) {
    Write-Verbose ("  • Skipping list '{0}': content types remain disabled." -f $List.Title)
    return
  }

  # Find a child list CT that inherits from the target CT Id
  $listCTs = @(Get-PnPContentType -List $List -ErrorAction SilentlyContinue)
  if ($listCTs.Count -eq 0) {
    if (-not $origEnabled) { Set-PnPList -Identity $List -EnableContentTypes $false | Out-Null }
    return
  }

  $matches = @(
    $listCTs | Where-Object { $_.StringId -like "$TargetCtIdPrefix*" } |
    Sort-Object { $_.StringId.Length } -Descending
  )
  if ($matches.Count -eq 0) {
    if (-not $origEnabled) { Set-PnPList -Identity $List -EnableContentTypes $false | Out-Null }
    return
  }

  $listCt = $matches[0]

  # Fallback CT: prefer 'Document', else first CT on the list
  $fallback = Get-PnPContentType -List $List -Identity "Document" -ErrorAction SilentlyContinue
  if (-not $fallback) { $fallback = $listCTs | Select-Object -First 1 }
  if (-not $fallback) {
    Write-Verbose ("  • No fallback CT available for '{0}', skipping detach." -f $List.Title)
    if (-not $origEnabled) { Set-PnPList -Identity $List -EnableContentTypes $false | Out-Null }
    return
  }

  # Reassign items currently using the child CT (guard for empty sets)
  $items = @()
  try { $items = @(Get-PnPListItem -List $List -PageSize $PageSize -Fields "ContentTypeId") } catch { }
  if ($items.Count -gt 0) {
    $toChange = @(
      $items | Where-Object {
        $_["ContentTypeId"] -and $_["ContentTypeId"].ToString().StartsWith($listCt.StringId,[System.StringComparison]::OrdinalIgnoreCase)
      }
    )
    if ($toChange.Count -gt 0) {
      Write-Verbose ("  • Reassigning {0} item(s) in '{1}' to '{2}'" -f $toChange.Count,$List.Title,$fallback.Name)
      foreach ($it in $toChange) {
        Set-PnPListItem -List $List -Identity $it.Id -ContentType $fallback.Name -ErrorAction SilentlyContinue | Out-Null
      }
    }
  }

  # Remove the child CT and restore original flag
  Remove-PnPContentTypeFromList -List $List -ContentType $listCt.Name -ErrorAction SilentlyContinue
  Write-Host ("  • Removed from list: {0}" -f $List.Title) -ForegroundColor Green
  if (-not $origEnabled) { Set-PnPList -Identity $List -EnableContentTypes $false | Out-Null }
}


# Resolve target site content type
try {
  $siteCT = Resolve-SiteCT -Id $Id -Name $Name
  Write-Verbose ("Target CT: {0} [{1}]  (ReadOnly={2}, Sealed={3})" -f $siteCT.Name,$siteCT.StringId,$siteCT.ReadOnly,$siteCT.Sealed)
  if ($siteCT.ReadOnly -or $siteCT.Sealed) { throw "Site CT is ReadOnly/Sealed (likely hub-published). Unpublish, then retry." }

  $children = @((Get-PnPContentType) | Where-Object { $_.StringId -like "$($siteCT.StringId)*" -and $_.StringId -ne $siteCT.StringId } |
                Sort-Object { $_.StringId.Length } -Descending)

  if ($children.Count -gt 0) {
    Write-Host ("Found {0} child site CT(s)…" -f $children.Count) -ForegroundColor Yellow
    $lists = @(Get-PnPList -Includes Title,Hidden)  # -Includes works per docs; use properties you need.  [oai_citation:1‡PNP GitHub](https://pnp.github.io/powershell/cmdlets/Get-PnPList.html?utm_source=chatgpt.com)
    foreach ($child in $children) {
      foreach ($l in $lists) { Detach-From-List -List $l -TargetCtIdPrefix $child.StringId }
      Remove-PnPContentType -Identity $child.StringId -Force -ErrorAction SilentlyContinue  # remove child CT first  [oai_citation:2‡PNP GitHub](https://pnp.github.io/powershell/cmdlets/Remove-PnPContentType.html?utm_source=chatgpt.com)
      Write-Host ("Deleted child CT: {0}" -f $child.Name) -ForegroundColor Green
    }
  }

  $lists2 = @(Get-PnPList -Includes Title,Hidden)
  foreach ($l in $lists2) { Detach-From-List -List $l -TargetCtIdPrefix $siteCT.StringId }

  Remove-PnPContentType -Identity $siteCT.StringId -Force -ErrorAction Stop
  Write-Host ("Deleted site content type: {0}" -f $siteCT.Name) -ForegroundColor Green
}
catch {
  $msg = $_.Exception.Message
  Write-Error $msg
  if ($msg -match 'publish|gallery|sealed|readonly') {
    Write-Warning "If hub-published, unpublish in the Content Type Gallery and try again."
  }
  if ($msg -match 'unauthorized|access') {
    Write-Warning "Ensure you are **Site Collection Admin** on this site."
  }
  exit 1
}