<#
.SYNOPSIS
  Create a KB domain from a slug: kb-<slug>-draft + kb-<slug>, and secure them.

.DESCRIPTION
  - Creates two document libraries:
      • kb-<slug>-draft   (curation)
      • kb-<slug>         (published)
  - Enables content types; attaches "Kb Article"; sets as default
  - Sets a clean default view (Name, KbTitle, KbDescription, KbTags, Modified)
  - Enforces Indexed + Unique on KbTitle at the library level
  - Creates a SharePoint group kb-<slug>-writers, adds UPNs you supply
  - Breaks inheritance on both libraries; grants:
      • Edit to kb-<slug>-writers
      • Read to the site's Visitors group (everyone else)

.PARAMETER Slug
  Short domain slug (e.g., hr, frontier-agency, m365, cstudio).

.PARAMETER WriterUpns
  Array of UPNs to add to the kb-<slug>-writers SharePoint group.

.PARAMETER TitlePrefix
  Optional display title prefix (default: "KB").

.PARAMETER MakeDefault
  Make "Kb Article" the default CT (default: On).

.PARAMETER EnforceUniqueKbTitle
  Index + unique on KbTitle in both libs (default: On).

.PARAMETER ViewFields
  Optional field order for the default view.

.USAGE
  pwsh provisioning/New-KBDomain.ps1 -Slug "frontier-agency" -WriterUpns "kevin@frontieragency.us" -Verbose
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$Slug,
  [string[]]$WriterUpns = @(),
  [string]$TitlePrefix = "KB",
  [bool]$MakeDefault = $true,
  [bool]$EnforceUniqueKbTitle = $true,
  [string[]]$ViewFields = @("DocIcon","LinkFilename","KbTitle","KbDescription","KbTags","Modified"),
  [bool]$SeedTemplate = $true,                           # NEW: seed article template into draft library
  [string]$TemplatePath                                  # NEW: optional override path to template file
)

Set-StrictMode -Version Latest
. "$PSScriptRoot/Ensure-Connected.ps1"
Ensure-DTConnected

# Pre-req: Kb Article CT exists
$ct = Get-PnPContentType -Identity "Kb Article" -ErrorAction SilentlyContinue
if (-not $ct) { throw "Site content type 'Kb Article' not found. Run provisioning/Ensure-KBSchema.ps1 first." }

# Library names
$draftName = "kb-$Slug-draft"
$pubName   = "kb-$Slug"

# Create (or ensure) a SharePoint group for writers
$writersGroupName = "kb-$Slug-writers"
$writersGroup     = Get-PnPGroup -Identity $writersGroupName -ErrorAction SilentlyContinue
if (-not $writersGroup) {
  $writersGroup = New-PnPGroup -Title $writersGroupName -ErrorAction Stop
  Write-Verbose "Created SharePoint group: $writersGroupName"
}
# Add UPNs to writers group (Add-PnPGroupMember supersedes Add-PnPUserToGroup in latest module)
foreach ($upn in $WriterUpns) {
  try {
    Add-PnPGroupMember -Group $writersGroupName -LoginName $upn -ErrorAction Stop | Out-Null
    Write-Verbose "Added $upn to $writersGroupName"
  } catch {
    # Use ${writersGroupName} to avoid parser treating the colon as part of a scoped variable (e.g., $env:PATH)
    Write-Verbose "Could not add $upn to ${writersGroupName}: $($_.Exception.Message)"
  }
}

# Helper to create + configure a library
function Ensure-KBLibrary {
  param([string]$LibraryName, [string]$Title)

  $list = Get-PnPList -Identity $LibraryName -ErrorAction SilentlyContinue
  if (-not $list) {
    New-PnPList -Title $Title -Template DocumentLibrary -Url $LibraryName -OnQuickLaunch:$true | Out-Null
    Write-Verbose "Created library: $LibraryName"
    $list = Get-PnPList -Identity $LibraryName
  } else {
    Write-Verbose "Library exists: $LibraryName"
  }

  # Enable CTs; attach Kb Article; set default
  Set-PnPList -Identity $LibraryName -EnableContentTypes $true | Out-Null
  Add-PnPContentTypeToList -List $LibraryName -ContentType $ct.Name -ErrorAction SilentlyContinue | Out-Null

  if ($MakeDefault) {
    $listCt = Get-PnPContentType -List $LibraryName -Identity $ct.Name -ErrorAction SilentlyContinue
    if ($listCt) {
      try {
        Set-PnPDefaultContentTypeToList -List $LibraryName -ContentType $listCt | Out-Null
      } catch {
        $order  = @($listCt.Name)
        $others = Get-PnPContentType -List $LibraryName | Where-Object { $_.Name -ne $listCt.Name } | Select-Object -ExpandProperty Name
        $order += $others
        Set-PnPContentTypeOrder -List $LibraryName -ContentTypes $order -DefaultContentType $listCt.Name | Out-Null
      }
    }
  }

  # Set default view
  try {
    Set-PnPView -List $LibraryName -Identity "All Documents" -Fields $ViewFields -ErrorAction Stop | Out-Null
  } catch {
    try {
      $newView = Add-PnPView -List $LibraryName -Title "KB Articles" -Fields $ViewFields -ErrorAction Stop
      Set-PnPView -List $LibraryName -Identity $newView -SetAsDefault | Out-Null
    } catch {
  Write-Verbose "View not set for ${LibraryName}: $($_.Exception.Message)"
    }
  }

  # Enforce Indexed + Unique for KbTitle at the library scope
  if ($EnforceUniqueKbTitle) {
    $listField = Get-PnPField -List $LibraryName -Identity "KbTitle" -ErrorAction SilentlyContinue
    if ($listField) {
      try {
        Set-PnPField -List $LibraryName -Identity "KbTitle" -Values @{ Indexed = $true } | Out-Null
        Set-PnPField -List $LibraryName -Identity "KbTitle" -Values @{ EnforceUniqueValues = $true } | Out-Null
        Write-Verbose "[$LibraryName] KbTitle → Indexed + Unique"
      } catch {
        Write-Verbose "[$LibraryName] Could not set Index/Unique on KbTitle: $($_.Exception.Message)"
      }
    }
  }

  # Break inheritance and set clean permissions:
  #  - writers group gets Edit
  #  - site's Visitors group gets Read
  Set-PnPList -Identity $LibraryName -BreakRoleInheritance -CopyRoleAssignments:$false -ClearSubscopes:$true | Out-Null

  # grant Edit to writers group
  Set-PnPListPermission -Identity $LibraryName -Group $writersGroupName -AddRole Edit | Out-Null

  # grant Read to associated Visitors group (fallback logged if not present)
  try {
    $vis = Get-PnPGroup -AssociatedVisitorGroup -ErrorAction Stop
  Set-PnPListPermission -Identity $LibraryName -Group $vis.Title -AddRole Read | Out-Null
  } catch {
    Write-Verbose "Could not find associated Visitors group; please ensure general readers have access."
  }

  Write-Host ("Library ready: {0}" -f $LibraryName) -ForegroundColor Green
}

# Create Draft and Published
Ensure-KBLibrary -LibraryName $draftName -Title "$TitlePrefix $Slug (Draft)"
Ensure-KBLibrary -LibraryName $pubName   -Title "$TitlePrefix $Slug"

# ------------------------------
# Seed template markdown (draft library only)
# ------------------------------
if ($SeedTemplate) {
  try {
    $defaultTemplate = Join-Path (Split-Path $PSScriptRoot -Parent) "templates/kb-article-template.md"
    $tpl = if ($TemplatePath) { $TemplatePath } else { $defaultTemplate }

    if (-not (Test-Path $tpl)) {
      Write-Verbose "Template not found at $tpl (skipping)."
    } else {
      $fileName = Split-Path $tpl -Leaf
      $exists = Get-PnPListItem -List $draftName -Fields FileLeafRef -PageSize 500 |
                  Where-Object { $_["FileLeafRef"] -eq $fileName } |
                  Select-Object -First 1

      if ($exists) {
        Write-Verbose "Template file '$fileName' already present in $draftName (skip upload)."
      } else {
        Write-Verbose "Uploading KB template '$fileName' to $draftName..."
        Add-PnPFile -Path $tpl -Folder $draftName -Values @{
          KbTitle       = "KB Article Template"
          KbDescription = "Template article to show how to add markdown knowledge base files."
          KbTags        = "template"
        } -ErrorAction Stop | Out-Null
        Write-Host "Seeded KB article template into $draftName" -ForegroundColor Cyan
      }
    }
  } catch {
    Write-Verbose "Could not seed template: $($_.Exception.Message)"
  }
}