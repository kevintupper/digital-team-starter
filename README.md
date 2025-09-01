# Digital Team Starter

A starter kit for creating curated SharePoint Knowledge Bases (KBs) and surfacing them as Copilot Studio agents.  
Built to be **repeatable, auditable, and simple** — for enterprises and government.

---

## 🌐 Big Picture

As we move toward **reimagining government with AI** and becoming a *Frontier Agency*, how agencies manage and use knowledge must evolve.

- **Domain experts** become **curators of knowledge**
- Curated knowledge becomes the **critical input** for AI-powered agents
- **Agents are not only chatbots** — they’re increasingly **action-oriented teammates** (submit a request, initiate a workflow, approve a form) when authorized

A major blocker today is ROT content (**Redundant, Outdated, Trivial**) scattered across sites and drives. ROT:
- Dilutes retrieval quality and increases hallucination risk
- Wastes vector/index storage and compute
- Erodes executive trust in AI outputs
- Buries authoritative guidance under noise

This starter creates a *governed funnel* (Draft → Approved → Published) that filters ROT before content ever reaches an agent.

When agents can act, the **quality and trustworthiness** of their knowledge is essential.  
Curated **Draft → Approved → Published** knowledge, tied directly to Copilot Studio agents, enables **trusted answers and safe actions**.

---

## ✅ Implemented

### 1. Site schema

- **Site Content Type:** `Kb Article` (Parent: Document, Group: Knowledge Base)
- **Site Columns:**
  - `KbTitle` — Text (single line), MaxLength = 150 (required at CT)
  - `KbDescription` — Note (multi-line, plain), optional
  - `KbTags` — Text (single line CSV), optional
- Uniqueness for `KbTitle` is enforced per library when the CT is attached.

### 2. Domain libraries

Script `New-KbDomain.ps1` provisions a KB domain from a slug.

For each slug it creates two libraries:
- `kb-<slug>-draft` (curation)
- `kb-<slug>` (published)

Each library:
- Enables content types; attaches **Kb Article**; sets it default
- Sets a default view (Name, KbTitle, KbDescription, KbTags, Modified)
- Enforces Indexed + Unique on `KbTitle` (library scope)

Security:
- Creates SharePoint group: `kb-<slug>-writers`
- Adds supplied UPNs
- Breaks inheritance; grants **Edit** to writers and **Read** to the site’s Visitors group

### 3. Draft article template (seeded)

`New-KbDomain.ps1` now seeds a markdown template into the new draft library (unless `-SeedTemplate:$false`):
- Source file: `templates/kb-article-template.md`
- Uploaded name: `kb-article-template.md`
- Metadata applied: `KbTitle = "Template: Replace Title"`, `KbDescription`, `KbTags = template`
- Idempotent: skipped if already present
- Override template path: `-TemplatePath <path>`

---

## ♻️ ROT (Redundant, Outdated, Trivial) Mitigation

Mechanism | ROT Pain Point Addressed
--------- | -------------------------
Draft vs Published boundary | Stops raw or half-baked files from contaminating agent knowledge
Unique `KbTitle` per library | Prevents silent duplication (R in ROT)
Markdown template + required Title discipline | Reduces trivial, low-signal fragments (T in ROT)
Planned LastReviewed + Status metadata | Surfaces staleness and enables aging workflows (O in ROT)
Promotion as copy (immutable snapshot) | Ensures updates are intentional, reviewable
Future review reminders & feedback loop | Continuous pruning cycle to keep corpus lean

Outcome: Agents ingest a *curated minimum necessary set*, increasing precision and organizational trust.

---

## 🚀 Quick Start

```pwsh
# 1. Connect using local .env (Device Code)
pwsh provisioning/Connect.ps1 -ShowEnv

# 2. Provision site schema (idempotent)
pwsh provisioning/Ensure-KbSchema.ps1 -Verbose

# 3. Provision a domain KB (seeds template into draft)
pwsh provisioning/New-KbDomain.ps1 -Slug "frontier-agency" -WriterUpns "kevin@frontieragency.us" -Verbose

# 4. Verify objects
Get-PnPField -Identity KbTitle,KbDescription,KbTags | ft InternalName,TypeAsString
Get-PnPContentType -Identity "Kb Article" | fl Name,Id,ReadOnly,Sealed
Get-PnPList -Identity kb-frontier-agency
Get-PnPList -Identity kb-frontier-agency-draft

# 5. (Optional) Re-seed with custom template
pwsh provisioning/New-KbDomain.ps1 -Slug "frontier-agency" -SeedTemplate:$true -TemplatePath ./templates/kb-article-template.md -Verbose
```

---

## ✍️ Authoring Articles

### Supported file types

You can store and surface multiple file formats in a KB domain:

| Format | Supported | Recommended Use | Notes |
|--------|-----------|-----------------|-------|
| `.md` (Markdown) | ✅ | Primary KB articles (purpose-built guidance, procedures, decision logs) | Clean diffing, small payload, front matter metadata, easy RAG ingestion |
| `.docx` | ✅ | Legacy narrative docs that aren’t yet refactored | Larger, harder to diff; consider converting key sections to Markdown |
| `.xlsx` | ✅ | Reference tables, matrices, controlled lists | Keep narrow in scope; summarize intent in a companion Markdown article if queried often |
| `.pptx` | ✅ | Visual briefing decks, diagrams | Extract core guidance into Markdown to avoid burying actionable steps |
| PDFs / other | (SharePoint can store) | Archival / regulatory snapshots | Prefer PDF/A for longevity; be aware of size/bandwidth impacts |

### Front matter template (current + future-ready)

Only the first three map to existing SharePoint columns today; others are future roadmap.

```yaml
---
Title: <Concise human-readable title>          # maps → KbTitle
Description: <1–2 sentence summary>            # maps → KbDescription
Tags: tag1, tag2, tag3                         # maps → KbTags (comma-separated)
Status: Draft                                  # future (choice/text)
Owner: user@domain.com                         # future (Person)
LastReviewed: 2025-08-31                       # future (Date)
SourceUrl: https://example.com/or/origin       # future (Hyperlink URL)
SourceLabel: Canonical Source                  # future (Hyperlink label)
Related:
  - other-article-slug                         # future (lookup/rel)
  - another-article-slug
---
```

### Create a new draft article

Option A (UI):
1. In `kb-<slug>-draft`, download or open `kb-article-template.md`
2. Copy → rename (e.g., `getting-started.md`)
3. Edit content + front matter; update Title/Description/Tags
4. Save; ensure `KbTitle` (front matter Title) matches SharePoint file’s Title column after upload (scripted method below ensures this)

Option B (local + upload):

```pwsh
$slug     = "frontier-agency"
$draftLib = "kb-$slug-draft"
$file     = "./content/getting-started.md"

# Upload mapping only existing fields
Add-PnPFile -Path $file -Folder $draftLib -Values @{
  KbTitle       = "Getting Started"
  KbDescription = "Orientation to the Frontier Agency knowledge base."
  KbTags        = "overview,intro"
}
```

(You can later add parsing logic to read front matter and build the hashtable automatically.)

### Promote (manual copy today)

```pwsh
$draft = "kb-$slug-draft"
$pub   = "kb-$slug"
$fileName = "getting-started.md"

$item = Get-PnPListItem -List $draft -PageSize 1000 |
          Where-Object { $_["FileLeafRef"] -eq $fileName } |
          Select-Object -First 1

Copy-PnPFile -SourceUrl $item.FieldValues.FileRef `
             -TargetUrl ($item.FieldValues.FileRef -replace $draft,$pub) `
             -OverwriteIfAlreadyExists
```

Automation of Draft → Published approval flow is on the roadmap (see below).

---

## 📦 Repo Structure

```
digital-team-starter/
├─ provisioning/
│  ├─ Connect.ps1
│  ├─ Ensure-Connected.ps1
│  ├─ Ensure-KbSchema.ps1
│  ├─ New-KbDomain.ps1
│  └─ tests/
│     └─ Smoke-Test.ps1
├─ templates/
│  └─ kb-article-template.md
├─ flows/
├─ solutions/
├─ docs/
└─ README.md
```

---

## 🪜 Roadmap

1. Define schema (DONE)  
2. Provision a domain KB (DONE)  
3. Bootstrap an agent (NEXT)
   - Create Copilot Studio agent (`agent-<slug>`)
   - Attach published library as knowledge
   - Apply system prompt & starter Q&A
   - Enable baseline actions (feedback, escalation)
4. Operational flows
   - Approval: Draft → Published (metadata carry-forward + ROT screening)
   - Feedback capture + action (identify ROT candidates)
   - Review reminders (surface Outdated content)
5. Extended metadata
   - KbSource (hyperlink), Status, Owner, LastReviewed, Related article linking
6. Authoring tooling
   - `New-KbArticle.ps1` (scaffold + parse front matter)
   - Promotion script / flow

---

## 🧰 Troubleshooting

Issue: Unauthorized on `Add-PnPField` / `Add-PnPContentType`  
Fix:
1. Entra app (`DT_CLIENT_ID`) has SharePoint (Office 365) → Delegated → `AllSites.FullControl` (admin consent granted)  
2. You are Site Collection Administrator

Template not seeded:
- Confirm `templates/kb-article-template.md` exists
- Run domain script again with `-SeedTemplate:$true`
- Ensure you’re connected to the correct site

---

## 📝 Notes

- Provisioning scripts are idempotent.
- Template seeding is safe to re-run (skips if file exists).
- Lifecycle + unique titles actively reduce ROT drift.
- Keep slugs lowercase, hyphen-separated for readability.