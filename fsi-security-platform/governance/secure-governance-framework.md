# Secure Governance Framework
## For AI, Automation, and Agentic Systems in Regulated Infrastructure

---

## Purpose

This framework codifies a single governing principle that has held across
every layer of this environment: **authority to act is never granted
directly — it is always mediated through an already-audited system, and
anything beyond read access requires a defined approval gate.**

This is not a policy statement layered on top of the infrastructure after the
fact. It's the actual shape of the architecture: no human, script, AI
assistant, or autonomous agent in this environment has a path to touch
production infrastructure that bypasses Satellite's content governance or
AAP's job execution and RBAC layer. That structural fact is what makes the
rest of this document enforceable rather than aspirational.

---

## The Four Governance Tiers

Every actor in this environment — human, script, or AI — sits in exactly one
of four tiers. The tier determines what it can do without further approval,
and what always requires a human gate.

### Tier 1 — Read-Only Observation
**Who's here:** dashboards, reporting scripts, the executive summary
generator, read-only MCP queries, monitoring agents.

**Can do without approval:** query Satellite's compliance API, read AAP job
history, inspect Content Views, pull scan results.

**Cannot do:** modify anything, trigger jobs, register hosts, alter policies.

**Enforcement mechanism:** `mcp_allow_write_operations: false` (AAP MCP
default), read-only API tokens, RBAC roles scoped to `view` permissions only.

### Tier 2 — Triage and Recommendation
**Who's here:** the compliance triage agent, the incident-classification
agent, AI code review on pull requests.

**Can do without approval:** analyze data, draft recommendations, classify
severity, propose remediation plans, comment on PRs.

**Cannot do:** execute the recommendation, merge code, run a remediation job,
send an official incident notification.

**Enforcement mechanism:** these systems have Tier 1 read access plus write
access only to a staging/draft location (a PR comment, a ticket, a draft
report) — never to production configuration, AAP job templates, or
Satellite content.

### Tier 3 — Bounded Execution
**Who's here:** AAP Job Templates and Workflow Templates, scheduled
remediation for known, tested OpenSCAP fixes, the AMI build pipeline.

**Can do without approval (once the template itself has been approved):**
execute exactly what the job template defines, against exactly the inventory
it's scoped to, using exactly the credential it's been assigned.

**Cannot do:** deviate from the template's defined scope, escalate its own
permissions, act outside its assigned inventory.

**Enforcement mechanism:** AAP RBAC (job templates are themselves
access-controlled resources), credential scoping, `05-remediate-high-severity.yml`'s
explicit design choice to only auto-fix rules with a vetted `has_snippet: true`
OpenSCAP fix — never blind remediation.

**Governance gate that got this template here:** every Tier 3 template
reached this tier by being written, reviewed via pull request, and approved
by a human *before* it was ever added to AAP — the template's *existence* is
Tier 4, its *execution* is Tier 3.

### Tier 4 — Human Approval Required
**Who's here:** anyone changing what a Job Template does, anyone approving a
promotion through Satellite's Lifecycle Environments (Dev→UAT→Prod), anyone
sending a real DORA incident notification, anyone flipping
`mcp_allow_write_operations` to `true`, anyone approving a PR that touches
the hardening pipeline.

**This tier cannot be delegated to an AI system.** An agent can draft the
recommendation that lands here; it cannot be the approver.

---

## Applying the Tiers Across the Stack

| System | Tier 1 (read) | Tier 2 (triage) | Tier 3 (execute) | Tier 4 (approve) |
|---|---|---|---|---|
| **Satellite** | Compliance API queries, Content View inspection | — | Scheduled OpenSCAP scans | Manifest changes, Lifecycle promotion, policy creation |
| **AAP** | Job history, inventory queries via MCP | Triage agent reads findings, drafts plan | Job Template execution | New/modified Job Templates, `mcp_allow_write_operations` toggle |
| **GitHub Actions** | Reading workflow runs, artifacts | AI PR review comments | Pipeline execution once merged | Merging to the branch that triggers builds |
| **EDA** | Event observation | Rulebook triage logic | Auto-firing a Tier-3-approved job | Adding a new rulebook or event source |
| **AI/Agents (any)** | Always permitted | Their home tier | Never directly — only by triggering an already-approved Tier 3 template | Never — structurally excluded |

---

## The Four Non-Negotiable Rules

**1. An agent's authority is always inherited, never native.**
No agent gets its own standing permission to modify infrastructure. It
inherits exactly what an AAP credential or Satellite token grants it — the
same boundary a human operator using that same credential would have.

**2. Read and write are architecturally separate, not just policy-separate.**
`mcp_allow_write_operations: false` is the default for a reason: the
distinction between "can see" and "can change" should be enforced by the
system, not by an agent's self-restraint or a prompt instruction that could
be circumvented.

**3. Every Tier 3 template earned its way there through a Tier 4 gate.**
Automation is trustworthy not because it's automation, but because a human
reviewed and approved what it does *before* it started running unattended.
This is why the branch/PR discipline established early in this build (fork,
branch, PR — even solo) isn't ceremony; it's the actual audit trail that
makes Tier 3 defensible later.

**4. Escalation is a re-approval event, not a runtime decision.**
If a Tier 3 job needs to do something outside its original scope, that's not
a judgment call for the automation (or an agent overseeing it) to make live —
it goes back through Tier 4. Nothing in this environment is designed to
expand its own authority at runtime.

---

## How This Maps to the FSI Regulatory Lens

This framework is a direct, structural answer to the specific gap the fit-
analysis document identified: *"AI systems must be fully embedded into
existing ICT governance, testing, and third-party risk frameworks... access
controls, and resilience testing."* (BaFin 2026 guidance on DORA.)

Most vendors answer that requirement with a written AI-usage policy. This
environment answers it with an access model an auditor can actually verify
by reading AAP's RBAC configuration and Satellite's job history — the claim
"our AI cannot act outside approved automation" is checkable, not just
asserted.

---

## What Still Needs to Exist for This to Be Fully Enforced (honest gaps)

1. **No audit log yet ties a specific agent query/action back to a named
   requester** — Tier 1/2 access via MCP needs request-level logging (who
   asked, what was queried, when) to be genuinely auditable, not just
   access-controlled.
2. **No formal Tier 4 approval workflow tooling** — right now "a human
   approved this PR" is the mechanism; there's no dedicated
   approval-and-sign-off system that produces a compliance-grade record
   distinct from a GitHub merge event.
3. **`mcp_allow_write_operations` is currently a single environment-wide
   toggle**, not a per-agent, per-scope permission — a genuinely mature
   version of this framework would allow granting write access to one
   specific, narrow action (e.g., "may trigger `03-trigger-scan.yml` only")
   rather than an all-or-nothing switch.
4. **The triage agent (Tier 2) doesn't exist yet** — this framework describes
   where it fits and its boundary, but the agent itself is a build item, not
   a deployed system.

These gaps are worth stating plainly in any real presentation of this
framework — a governance model that only describes the mature end-state
without flagging what's built versus what's designed is exactly the kind of
overclaiming the fit-analysis document warned against.
