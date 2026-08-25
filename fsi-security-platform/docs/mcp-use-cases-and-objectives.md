# MCP Tools — Use Cases and Objectives

## What exists right now

| MCP Server | Status | Where it runs |
|---|---|---|
| AAP MCP server | GA, container confirmed running (`ansiblemcp`, ports 8080/8086) | On the AAP instance, part of the containerized install |
| Satellite MCP server | Tech Preview (6.18) | Not yet installed/confirmed running — needs verification |

Neither has been connected to an actual MCP client yet, and — critically —
**`mcp_allow_write_operations` defaults to `false`** on the AAP server. Every
use case below assumes read-only unless explicitly marked otherwise, and any
write-capable use case requires a deliberate, documented decision to flip
that flag plus a narrowly-scoped token, per the Secure Governance Framework's
Tier 1/Tier 3 boundary.

---

## Objective

Give a human operator (and, later, an agent) a conversational interface onto
Satellite and AAP that **cannot exceed what that operator's own RBAC role
would allow through the UI** — the MCP layer should feel like a faster way
to ask the same questions and take the same actions a human already has
permission for, never a backdoor to more.

---

## Use Case 1 — Fleet status queries (AAP MCP, read-only)

**The question a human currently has to click through 3-4 UI screens to
answer:** "Which hosts failed their last compliance scan, and when did we
last run automation against them?"

**With MCP:** ask it directly. The agent (or a human via a chat client)
calls AAP's inventory/job-history tools and Satellite's host-status data
(once wired) and answers in one turn.

**Objective this serves:** cuts the time between "something might be wrong"
and "here's the actual current state" from minutes of UI navigation to a
single query — directly useful during a live incident, not just a demo trick.

**Write risk:** none — pure read.

---

## Use Case 2 — Guided remediation triggering (AAP MCP, write-gated)

**The question:** "Remediate the HIGH severity findings on
core-banking-payments-02."

**With MCP (write enabled, narrowly scoped token):** the agent translates
this into a call to the *already-approved* `05-remediate-high-severity.yml`
Job Template — it does not write new automation, it launches an existing,
human-reviewed one.

**Objective this serves:** this is the concrete instance of "AI can only
act through validated automation" from the Better Together strategy doc —
the demo moment that makes the governance framework's Tier 3 boundary
tangible rather than theoretical.

**Write risk:** real, but bounded — the token used must be scoped to
"launch specific job templates," not general AAP admin. This is the one
use case in this document where flipping `mcp_allow_write_operations` to
`true` is actually the point, not a risk to avoid.

---

## Use Case 3 — Content/registry provenance queries (Satellite MCP, read-only)

**The question:** "What's actually in the `fsi-hardened-images` Content
View right now, and has it been promoted to Prod?"

**With MCP:** answers directly from Satellite's Content View/Lifecycle
Environment data, without needing the UI.

**Objective this serves:** this is the audit/compliance use case — a
security reviewer (or an AI assistant helping one) can verify "what's
actually running came from where we think it came from" conversationally,
which is the single most auditor-relevant question this whole environment
is built to answer.

**Write risk:** none if kept read-only, which Red Hat's own guidance
recommends as the default for this Tech Preview server.

---

## Use Case 4 — CVE-to-fleet cross-referencing (AAP MCP + Insights data, read-only)

**The question:** "Of the 425 tracked CVEs, which ones actually apply to
packages installed on our 8 registered hosts, and which of those have a
known exploit?"

**With MCP:** ties directly to the CVE triage agent already built —
instead of running that agent as a standalone script, it becomes a live,
on-demand conversational query.

**Objective this serves:** turns a static, point-in-time PDF report into a
live, queryable source of truth — directly addresses the "continuous proof,
not point-in-time audit" pressure from the FSI security fit-analysis.

**Write risk:** none — pure read, cross-referencing two read-only data
sources.

---

## Use Case 5 — Executive summary on demand (composition of the above, read-only)

**The question:** "Give me the board-readable version of our compliance
posture right now."

**With MCP:** rather than running the executive-summary playbook on a
schedule, an executive-facing chat client could ask this directly, and the
same underlying data (compliance status, job history, CVE exposure) gets
composed into the plain-language format that playbook already produces.

**Objective this serves:** the single highest-value gap-closer from the
fit-analysis document, made conversational instead of scheduled-batch.

**Write risk:** none.

---

## What's explicitly OUT of scope for MCP tool use right now

- **Anything that modifies Satellite Content Views, Lifecycle promotion, or
  manifest state** — these are Tier 4 (human approval) actions per the
  governance framework and should stay UI/API-driven by a human directly,
  not conversational, regardless of how convenient it would be.
- **Anything that creates or modifies AAP Job Templates themselves** — same
  reasoning. MCP can *launch* an approved template; it should never *define*
  one.
- **Direct SSH/host-level command execution via MCP** — if a use case seems
  to need this, that's a sign it belongs in a proper AAP Job Template
  first, then exposed as a launch action, not as a raw MCP capability.

---

## Concrete next steps, in priority order

1. **Verify what's actually running** — confirm the Satellite MCP server is
   installed at all (Tech Preview, may not be enabled by default even on
   6.18) before designing further around it.
2. **Wire Use Case 1 first** (read-only, AAP MCP, already running) — lowest
   risk, immediate utility, no governance decision required since it's pure
   read.
3. **Connect a real MCP client** (Claude Desktop/Code, per the earlier
   connection guide) and validate Use Cases 1, 3, 4, 5 all work read-only
   before touching the write flag at all.
4. **Only after 1-3 are proven**, have the explicit, documented conversation
   about enabling Use Case 2's write path — including exactly which token,
   which job templates it can launch, and who signs off on that scope.
