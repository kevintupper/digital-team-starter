# Digital Team Starter

**A repeatable, as-code starter kit for building curated SharePoint Knowledge Bases and surfacing them as Copilot Studio agents.**  
_GCC-safe by default. Works on macOS/Windows/Linux._

> **Status:** Draft v0 — we’ll iterate this README step-by-step and adjust as we implement each piece.

---

## What you get

- **Standard KB schema**: site columns (`KbTitle`, `KbDescription`, `KbTags`) + **KB Article** content type (wraps DOCX, PDF, PPTX, MD, etc.)
- **Domain KB pattern**: for each domain slug (e.g., `hr`) create:
  - `kb-hr-draft` (curation) with minor versions + approvals
  - `kb-hr` (published) with major versions only
- **Security groups per domain**: `kb-hr-editors`, `kb-hr-approvers` (created/ensured)
- **Consistent views**: `Name, KbTitle, KbDescription, KbTags, Modified`
- **Agent bootstrap (baseline)**: create `agent-hr` and bind it to `kb-hr` with a standard system prompt, citations on
- **Auditability**: every provisioning action logged to timestamped CSV
- **Cross-platform**: PowerShell 7 + PnP.PowerShell (no Windows-only dependencies)

---

## Design goals

- **Curated & governed by default** (Draft → Approve → Published)
- **Agent-ready content** (clean titles/descriptions/tags, citations)
- **Repeatable & auditable** (scripts in source control; logs for every run)
- **Least surprise for government** (GCC-safe capabilities, SharePoint security trimming, no third-party deps)

---

## Architecture (high-level)

+———————+        Approve         +––––––––––+
|  kb-hr-draft        |  ——————>   |  kb-hr (Published) |
|  (Curators edit)    |                        |  (Agent knowledge) |
+–––––+–––––+                        +–––––+———+
^                                              |
|  Editors/Approvers groups                    |  Copilot Studio agent
|                                              v
+–––––––––––+                 +———————+
| kb-hr-editors       |                 | agent-hr            |
| kb-hr-approvers     |                 | (scoped to kb-hr)   |
+–––––––––––+                 +———————+

---

## Terminology & conventions

- **Domain slug**: short, unique (`hr`, `m365`, `cstudio`, `frontier`)
- **Library names**:
  - Draft: `kb-<slug>-draft`  → e.g., `kb-hr-draft`
  - Published: `kb-<slug>`    → e.g., `kb-hr`
- **Security groups**:
  - Editors:   `kb-<slug>-editors` (create/update in Draft)
  - Approvers: `kb-<slug>-approvers` (approve in Draft; contribute in Published)
  - _Readers_: **not created by default** — pass an existing group if you want explicit read on Published (can be “Everyone”)
- **Metadata (site columns)**:
  - `KbTitle` (Text, required)
  - `KbDescription` (Multi-line)
  - `KbTags` (Choice, multi-select)
- **Content type**: `KB Article` (parent: Document) — required in all KB libraries

---

## ALM stance

- **Provisioning** (as code): PnP.PowerShell + Graph (scripts in this repo)
- **Agents**: packaged/imported via **Power Platform Solutions** (baseline template) for repeatable creation
- **Operations**: Power Automate for Draft→Published copy notices, feedback capture, reminders (added later)

---

## Quickstart (cross-platform)

### Prereqs
- PowerShell 7+  
- PnP.PowerShell module  
- Site Collection Admin on your SharePoint Team site (e.g., `https://<tenant>.sharepoint.com/sites/DigitalTeam`)

### Install (macOS)
```bash
brew install --cask powershell
pwsh

Install-Module PnP.PowerShell -Scope CurrentUser -Force

Install (Windows / Linux)
	•	Windows: install PS7 from https://aka.ms/PSWindows, then run pwsh
	•	Linux: sudo snap install powershell --classic (or your distro’s instructions), then pwsh
	•	Install PnP as above

⸻

Provisioning flow (what we’ll build in this repo)

We’ll implement these scripts one by one and update README as we go:
	1.	Ensure-KBSchema.ps1
Create (or verify) site columns and KB Article content type.
	2.	New-KBDomain.ps1
Create a new domain KB with:
	•	kb-<slug>-draft / kb-<slug>
	•	enable content types, attach KB Article, remove default “Document”
	•	versioning/approvals
	•	security groups & permissions
	•	default views
	•	optional sensitivity label
	•	full audit log
Parameters (first cut):

New-KBDomain `
  -SiteUrl "https://<tenant>.sharepoint.com/sites/DigitalTeam" `
  -Slug "hr" `
  -DisplayName "Human Resources" `
  -Description "Curated leave, travel, benefits policies" `
  -EditorsGroupName "kb-hr-editors" `
  -ApproversGroupName "kb-hr-approvers" `
  -ReadersGroupName "All Employees" `   # optional; skip to inherit site
  -SensitivityLabel "Internal" `        # optional
  -ReviewCycleDays 180                   # optional, used later by reminders


	3.	New-KBAgent.ps1
Bootstrap a Copilot Studio agent bound to the Published library:
	•	Name: agent-<slug> (e.g., agent-hr)
	•	Knowledge source: kb-<slug>
	•	Standard system prompt (citations on; scope to library)
	•	Seed starter Q&A (optional)
	•	Return agent URL + log entry
Parameters (first cut):

New-KBAgent `
  -SiteUrl "https://<tenant>.sharepoint.com/sites/DigitalTeam" `
  -Slug "hr" `
  -DisplayName "HR Policy" `
  -PublishedLibraryUrl "https://<tenant>.sharepoint.com/sites/DigitalTeam/kb-hr"



We’ll add a Power Platform Solution template for the agent and document import steps once we wire the baseline.

⸻

Security & access
	•	Editors/Approvers: per-domain groups created/ensured and assigned on Draft/Published appropriately.
	•	Readers: not auto-created. If you pass -ReadersGroupName, it gets Read on Published; otherwise we inherit site permissions. Either way, SharePoint security trimming always governs what an agent can surface.
	•	Sensitivity/Retention: optional library-level label in New-KBDomain.ps1 (GCC-safe).

⸻

Roadmap (we’ll add these iteratively)
	•	Ensure-KBSchema.ps1 (site columns + content type)
	•	New-KBDomain.ps1 (libraries, CTs, views, versioning, approvals, groups, labels, audit)
	•	New-KBAgent.ps1 (baseline agent via Solution import; knowledge binding)
	•	Power Automate: Draft→Published notification, Feedback list + action
	•	Optional: Concierge “front door” page/links; JSON view polish
	•	Optional: Review reminders based on ReviewCycleDays

⸻

Usage examples (will be live once scripts land)

# 0) Sign in
Connect-PnPOnline -Url "https://<tenant>.sharepoint.com/sites/DigitalTeam" -Interactive

# 1) Schema (once per site)
pwsh provisioning/Ensure-KBSchema.ps1

# 2) New KB domain (hr)
pwsh provisioning/New-KBDomain.ps1 -SiteUrl "https://<tenant>.../DigitalTeam" `
  -Slug hr -DisplayName "Human Resources" -Description "Curated leave, travel, benefits policies" `
  -EditorsGroupName "kb-hr-editors" -ApproversGroupName "kb-hr-approvers" `
  -ReadersGroupName "All Employees" -SensitivityLabel "Internal"

# 3) Bootstrap agent bound to Published library
pwsh provisioning/New-KBAgent.ps1 -SiteUrl "https://<tenant>.../DigitalTeam" `
  -Slug hr -DisplayName "HR Policy" -PublishedLibraryUrl "https://<tenant>.../kb-hr"


⸻

Contributing
	•	We’ll keep scripts idempotent and logged.
	•	PRs should include: what changed, why, and a sample log excerpt.
	•	Keep everything GCC-safe by default.

⸻

License

MIT (or your preferred permissive license)

⸻


**Next step:** If this structure looks right, I’ll add the **first script stub** (`Ensure-KBSchema.ps1`) and we’ll adjust the README’s “Provisioning flow” section as we go.
