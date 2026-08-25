# What FSI IT Security Is Actually Trying to Solve — And Where This Build Fits

## What FSI security teams are actually under pressure to solve right now

Financial services security priorities have shifted meaningfully in the last
two years, driven largely by regulation catching up to reality. Five things
dominate what's actually keeping FSI security and compliance leaders up at
night in 2026:

**1. Continuous proof, not point-in-time audits.**
Regulators (DORA in the EU being the sharpest current example, but PCI-DSS,
SOX, and NIST-driven US frameworks are converging on the same expectation)
have explicitly moved from "show us your policy documents" to "show us live
evidence that controls are operating today." One 2026 DORA guide put it
directly: supervisors are "examining how organisations manage incidents,
oversee third-party providers, conduct resilience testing, and maintain
business continuity under real-world conditions" — not reviewing static
policy binders. Annual compliance snapshots are no longer sufficient.

**2. Software supply chain visibility, down to the fourth and fifth party.**
DORA's Register of Information requirement — which Deloitte research found
46% of financial entities call the single hardest requirement to meet — forces
institutions to know not just their direct vendors but the subcontractors
and components *those* vendors depend on. This is the SBOM problem: "a modern
application is mostly third-party code... each is a potential entry point."
Supply chain scanning of container images and open-source packages *before*
they reach production is now flagged as "the most common area for audit
findings in 2026."

**3. Third-party and concentration risk management.**
Regulators increasingly scrutinize vendor lock-in itself as a compliance
failure, not just a commercial risk — institutions must document exit plans
for critical providers and prove they aren't systemically dependent on any
single point of failure.

**4. Governance catching up to AI.**
Germany's BaFin issued 2026 guidance making clear that generative AI and LLM
systems aren't a separate regulatory category — they must be "fully embedded
into existing ICT governance, testing, and third-party risk frameworks,"
including documented access controls and resilience testing. Security teams
are now expected to have an answer for "how is AI governed here," not just
"is AI banned or allowed."

**5. Operational resilience as a boardroom issue, not just an IT issue.**
DORA explicitly shifted accountability for digital resilience strategy to
CEOs and executive committees. Security posture is no longer purely a CISO
concern — it's a governance and disclosure obligation with real financial
penalties (up to 2% of annual global turnover for critical DORA failures).

---

## How this build actually maps to those five pressures

| FSI pressure | What we built | Genuine fit? |
|---|---|---|
| Continuous proof, not point-in-time | Satellite compliance policies + scheduled OpenSCAP scans + AAP remediation loop | **Strong** — this is precisely "operating controls, evidenced continuously," not a policy document |
| Supply chain visibility / SBOM | Satellite as single content source + GitHub Actions build provenance | **Partial** — we have provenance for the OS layer; no actual SBOM generation exists yet |
| Third-party / concentration risk | Everything runs on Red Hat's own stack, self-hosted, no external SaaS dependency for the core loop | **Strong, but different framing** — reduces *our* vendor risk, doesn't yet help document *the institution's* broader vendor register |
| AI governance | AAP's MCP server as the sole path an AI agent has to touch infrastructure — never raw SSH | **Directionally strong, structurally incomplete** — the access-control shape is right, but no audit logging/access-review layer sits on top of MCP usage yet |
| Executive/boardroom resilience narrative | The whole "provable at every layer" thesis | **Strong as a narrative, weak as evidence** — nothing here yet produces an executive-readable report; everything is technical-audience artifacts (job logs, ARF XML, Satellite UI screens) |

---

## Honest strengths

**1. The core architecture genuinely matches where regulation is heading.**
DORA's shift toward continuous, evidenced control operation — not annual
attestation — is exactly what a Satellite-scheduled scan + AAP-driven
remediation loop produces natively. This isn't a stretch fit; it's the right
shape of solution for the actual regulatory direction.

**2. Real, working provenance for the OS layer.**
Unlike most compliance demos that show a dashboard and call it done, this
build has an actual, reproducible chain: RHEL entitlement → Satellite content
→ OpenSCAP scan → promoted image → AAP-driven deployment. Every link in that
chain is real infrastructure, not slideware.

**3. Reduced blast radius by design, not by policy.**
Image mode (bootc) plus AAP-mediated access means there is structurally no
path for drift to accumulate silently — every change is either a new promoted
image or a logged AAP job. That's a stronger default posture than most
traditional package-managed fleets, where config drift between "documented
state" and "actual state" is the norm, not the exception.

**4. The AI-governance angle is genuinely ahead of where most demos are.**
Most compliance tooling in this space (JFrog, Bitsight, Panorays — the
vendors turning up in current DORA search results) is about *documenting*
third-party risk, not about *architecturally constraining* what an AI agent
can do to production infrastructure. Routing all agent interaction through
AAP's RBAC-scoped, MCP-mediated automation is a structural answer to BaFin's
"AI must be embedded into existing governance" guidance — most competitors are
still at the policy-document stage on this specific question.

---

## Honest weaknesses

**1. No SBOM generation anywhere in the pipeline, and DORA-adjacent regulation is explicitly SBOM-driven.**
Everything built today proves "this OS came from Red Hat, scanned, unmodified"
— but produces no machine-readable manifest of every component and its
provenance, which is precisely the artifact DORA's Register of Information
and Article 28-30 subcontracting requirements are built around. This is the
single biggest structural gap relative to where the regulation actually
points. (The Lightwell/app-dependency conversation from earlier is directly
relevant here — an SBOM covering both OS and app layers is the artifact this
whole story is currently missing.)

**2. The compliance gate doesn't gate.**
This was flagged earlier and bears repeating in this context specifically:
"supply chain scanning... before it reaches production" is called out as
*the* most common 2026 audit finding — and our own pipeline's scan currently
can't fail a build (`|| echo`). If this were shown to an actual FSI security
team, the very first sharp question would be "what happens when it fails,"
and right now the honest answer undermines the whole pitch.

**3. No incident reporting integration.**
DORA's Article 19 imposes strict, timed incident classification and reporting
obligations (24hr initial notification, 72hr follow-up, 1-month final report).
Nothing in this build feeds a finding — a failed compliance scan, a
remediation failure — into any kind of incident workflow. AAP could trigger
this (a webhook to a ticketing/incident system on remediation failure), but
it doesn't exist yet.

**4. No executive-facing reporting layer.**
Every artifact this environment produces (Satellite's compliance tab, AAP job
logs, ARF XML) is built for an engineer, not a board member or an auditor
doing a Register of Information cross-check. Given that DORA explicitly makes
resilience an executive accountability, and NCAs are now "cross-checking
Register of Information data automatically," a translation layer — something
that turns "312 hosts scanned, 4 findings, all remediated within SLA" into a
one-page exec summary — is currently missing entirely.

**5. Single points of failure that would themselves draw scrutiny under this exact regulatory lens.**
Ironically, given the demo's own thesis: one Satellite instance, one AAP
instance, no documented DR/failover story for either. A real DORA reviewer
would ask "what's your Satellite's RTO/RPO, and what's the exit plan if it's
unavailable" — a fair question this build has no answer to yet.

---

## Genuine gaps (not weaknesses in what exists, but things that don't exist at all)

1. **SBOM generation and a queryable component inventory** — the concrete artifact regulation is converging on, not present anywhere in this pipeline.
2. **Incident reporting / ticketing integration** — no bridge from "AAP found a problem" to "the org's formal incident process started."
3. **Vendor/third-party register tooling** — this build proves *our own* stack's integrity; it does nothing for the institution's broader obligation to track and monitor its other 200+ ICT vendors.
4. **Disaster recovery for the control plane itself** — Satellite and AAP are each single instances with no failover story.
5. **Executive/audit-ready reporting** — everything produced today is for engineers, nothing for auditors or the board.
6. **Access review and audit logging on top of MCP/AI usage** — the *access model* is sound (agents only act through AAP), but there's no log of "which agent did what, when, approved by whom" layered on top of that access.

---

## The honest positioning

This build is a genuinely strong, real answer to **one specific and important
question**: *"can we prove our OS and deployment layer are continuously
compliant, with automation driving remediation instead of manual toil?"* That
question matters, and the answer here is a working system, not a slide.

It is **not yet** a complete answer to the broader FSI regulatory mandate,
which extends well beyond the OS layer into vendor governance, incident
reporting, SBOM-level supply chain transparency, and executive disclosure.
Positioned honestly, this is the **foundation layer** of a DORA-aligned
security program — the part that proves infrastructure integrity — not the
whole program. The strongest, most credible way to present this is exactly
that framing: "here is the hard infrastructure-integrity problem, solved and
provable; here is the clear list of what layers on top of it to make this a
complete regulatory answer" — rather than overselling it as end-to-end
compliance coverage it doesn't yet provide.
