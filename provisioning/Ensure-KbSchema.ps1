<#
.SYNOPSIS
  Create/update the Digital Team site schema: site columns + "Kb Article" content type.

.DESCRIPTION
  Defines three site columns and a site content type once, to be reused by all KB libraries:
    • KbTitle        : Text (single line), Required (at CT), MaxLength = 150, Unique per library (applied later)
    • KbDescription  : Note  (multi-line, plain), Optional
    • KbTags         : Text (single line CSV),    Optional
  Creates/updates site content type:
    • Name  : "Kb Article"  (parent = Document, group "Knowledge Base")
    • Fields from the array below; honors Required = $true per field.

  NOTE: Uniqueness for KbTitle is enforced **per library** (Step 2), not at site column level.

.REQUIREMENTS
  - PowerShell 7+ (pwsh)
  - PnP.PowerShell (Install-Module PnP.PowerShell -Scope CurrentUser)
  - Active PnP connection (run provisioning/Connect.ps1 first)
  - App registration has SharePoint delegated permission (AllSites.FullControl) and admin consent,
    and you are Site Collection Admin for this site.

.USAGE
  pwsh provisioning/Ensure-KBSchema.ps1 -Verbose
  # optional: remove any extra custom fields from the CT that aren't listed in $Fields
  pwsh provisioning/Ensure-KBSchema.ps1 -PruneExtraFields -Verbose
#>

[CmdletBinding()]
param(
  [switch]$PruneExtraFields
)

Set-StrictMode -Version Latest

. "$PSScriptRoot/Ensure-Connected.ps1"
Ensure-DTConnected

# ------------------------------
# Configuration (edit in one place)
# ------------------------------
$ContentTypeName  = "Kb Article"
$ContentTypeGroup = "Knowledge Base"
$ParentCTName     = "Document"       # site-level parent

# Field definitions (site columns). InternalName is immutable: pick carefully.
# Type: 'Text' | 'Note' (site column types we use here)
# RequiredAtCT: required on the Content Type (true/false)
# MaxLength: applies to Text only
$Fields = @(
  @{
    InternalName  = "KbTitle"
    DisplayName   = "Kb Title"
    Type          = "Text"
    RequiredAtCT  = $true
    MaxLength     = 150
  },
  @{
    InternalName  = "KbDescription"
    DisplayName   = "Kb Description"
    Type          = "Note"
    RequiredAtCT  = $false
  },
  @{
    InternalName  = "KbTags"
    DisplayName   = "Kb Tags"
    Type          = "Text"
    RequiredAtCT  = $false
  }
)

# ------------------------------
# Preflight: verify write capability (clear error if missing perms)
# ------------------------------
function Test-CanCreateSiteColumn {
  $probeName  = ("_dt_probe_{0:yyyyMMddHHmmss}" -f (Get-Date))
  try {
    # try create a hidden text field then delete it immediately
    Add-PnPField -DisplayName $probeName -InternalName $probeName -Type Text -Group $ContentTypeGroup -ErrorAction Stop | Out-Null
    Remove-PnPField -Identity $probeName -Force -ErrorAction Stop
    return $true
  } catch {
    Write-Error ("Preflight failed: cannot create a site column. " +
                "Ensure your current session has SharePoint delegated write permission (e.g., AllSites.FullControl) and you are Site Collection Admin. " +
                "Details: {0}" -f $_.Exception.Message)
    return $false
  }
}

if (-not (Test-CanCreateSiteColumn)) { exit 1 }

# ------------------------------
# Ensure site columns
# ------------------------------
foreach ($f in $Fields) {
  $existing = Get-PnPField -Identity $f.InternalName -ErrorAction SilentlyContinue
  if (-not $existing) {
    try {
      Add-PnPField -DisplayName $f.DisplayName -InternalName $f.InternalName -Type $f.Type -Group $ContentTypeGroup -ErrorAction Stop | Out-Null
      Write-Verbose ("Created field: {0} ({1})" -f $f.InternalName, $f.Type)
    } catch {
      throw "Failed to create site column '$($f.InternalName)'. Details: $($_.Exception.Message)"
    }
  } else {
    Write-Verbose ("Field exists: {0}" -f $f.InternalName)
  }

  # Update field properties as needed (currently only MaxLength for Text)
  if ($f.Type -eq "Text" -and $f.ContainsKey("MaxLength") -and $f.MaxLength) {
    try {
      Set-PnPField -Identity $f.InternalName -Values @{ MaxLength = [int]$f.MaxLength } -ErrorAction Stop | Out-Null
      Write-Verbose ("{0} → MaxLength set to {1}" -f $f.InternalName, $f.MaxLength)
    } catch {
      throw "Failed to set MaxLength on '$($f.InternalName)'. Details: $($_.Exception.Message)"
    }
  }
}

# ------------------------------
# Ensure site content type
# ------------------------------
$parentCT = Get-PnPContentType -Identity $ParentCTName -ErrorAction Stop

$ct = Get-PnPContentType -Identity $ContentTypeName -ErrorAction SilentlyContinue
if (-not $ct) {
  try {
    Add-PnPContentType -Name $ContentTypeName -Description "Curated $ContentTypeName" -Group $ContentTypeGroup -ParentContentType $parentCT -ErrorAction Stop | Out-Null
    $ct = Get-PnPContentType -Identity $ContentTypeName
    Write-Verbose ("Created content type: {0}" -f $ContentTypeName)
  } catch {
    throw "Failed to create content type '$ContentTypeName'. Details: $($_.Exception.Message)"
  }
} else {
  Write-Verbose ("Content type exists: {0}" -f $ContentTypeName)
}

# Attach only the desired fields, honor RequiredAtCT
foreach ($f in $Fields) {
  $isRequired = $false
  if ($f.ContainsKey("RequiredAtCT")) { $isRequired = [bool]$f.RequiredAtCT }

  try {
    if ($isRequired) {
      Add-PnPFieldToContentType -ContentType $ContentTypeName -Field $f.InternalName -Required -ErrorAction Stop | Out-Null
    } else {
      Add-PnPFieldToContentType -ContentType $ContentTypeName -Field $f.InternalName -ErrorAction Stop | Out-Null
    }
    Write-Verbose ("Attached {0}{1}" -f $f.InternalName, $(if($isRequired){" (Required)"} else {""}))
  } catch {
    Write-Verbose ("{0} already attached (or attachment failed benignly): {1}" -f $f.InternalName, $_.Exception.Message)
  }
}

# Optional: prune unexpected custom fields from the CT to keep it in sync with $Fields
if ($PruneExtraFields) {
  $desired = $Fields.InternalName
  $ctFields = @(Get-PnPContentType -Identity $ContentTypeName | Get-PnPProperty -Property FieldLinks)
  foreach ($link in $ctFields) {
    $name = $link.Name
    # Skip built-ins; only consider our group and our three internal names
    if ($desired -notcontains $name) {
      # Only remove if it's clearly in our group (avoid nuking default CT members)
      $siteField = Get-PnPField -Identity $name -ErrorAction SilentlyContinue
      if ($siteField -and $siteField.Group -eq $ContentTypeGroup) {
        try {
          Remove-PnPFieldFromContentType -Field $name -ContentType $ContentTypeName -ErrorAction Stop | Out-Null
          Write-Verbose ("Pruned extra field from CT: {0}" -f $name)
        } catch {
          Write-Verbose ("Could not prune '{0}': {1}" -f $name, $_.Exception.Message)
        }
      }
    }
  }
}

Write-Host ("Schema ready: site columns + {0} content type (synced)." -f $ContentTypeName) -ForegroundColor Green