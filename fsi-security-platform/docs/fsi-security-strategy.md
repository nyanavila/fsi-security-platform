# FSI Security-First Software Supply Chain — Strategy & Narrative

## The thesis

A regulated financial services institution cannot treat security as a bolt-on
audit step. It has to be **provable at every layer, continuously** — the OS a
server boots from, the automation that touches it, the dependencies an app
pulls in, and the ongoing proof that all of it still meets policy today, not
just on install day.

This environment demonstrates that end-to-end, using only Red Hat's own stack
plus the open tooling it's built on — no third-party security bolt-ons. That's
the "Better Together" story: **Red Hat Enterprise Linux (image mode), Red Hat
Satellite, and Red Hat Ansible Automation Platform form a closed loop where
every layer both enforces and proves compliance**, and the loop is driven by
ordinary GitHub Actions CI/CD — nothing exotic required to adopt this.

---

## The five layers of trust, and what proves each one

| Layer | Question it answers | What proves it | Built today |
|---|---|---|---|
| **1. OS provenance** | Did this system boot from Red Hat-entitled, unmodified content? | Satellite Content Views + Subscription Manifest | ✅ |
| **2. Build-time hardening** | Was the OS image scanned for compliance *before* it was ever deployed? | OpenSCAP scan in CI, gated (not just logged) | 🔧 needs the gate fix |
| **3. Controlled distribution** | Is there one governed source of truth for what's allowed to run? | Satellite Content Views + Lifecycle Environments (Dev→UAT→Prod) | ✅ |
| **4. Automated deployment & drift correction** | Can the fleet be updated/corrected without manual SSH, consistently? | AAP job templates + `bootc switch`/`upgrade` | ✅ |
| **5. Continuous runtime proof** | Is the *already-running* fleet still compliant, not just at build time? | Satellite Compliance Policies + OpenSCAP scans + AAP remediation | 🔧 policy not yet assigned |

**The narrative arc for a live demo is literally this table, top to bottom** —
each row is a beat, each row has a Red Hat product doing the enforcing, and
each row has an artifact (a report, a promoted image, a job log) that proves
it happened.

---

## The two supply chains, and why keeping them separate is the point

```
PIPELINE 1 — Platform team owns this
┌────────────────────────────────────────────────────────────┐
│ fsi-hardened-os (GitHub Actions, self-hosted runner in VPC)  │
│                                                                │
│  Containerfile ── FROM Satellite-mirrored RHEL 9 bootc base   │
│       │                                                        │
│       ├─→ Build (Podman)                                      │
│       ├─→ OpenSCAP PCI-DSS scan  ──────► gate: fail on findings│
│       ├─→ Push to Satellite (fsi-hardened-images product)     │
│       └─→ (optional) Build AMI for fresh EC2 launches          │
└────────────────────────────────────────────────────────────┘
                          │
                          │  promoted through Satellite
                          │  Lifecycle Environments
                          ▼
┌────────────────────────────────────────────────────────────┐
│ Satellite Content View: fsi-hardened-os-cv                    │
│   Library → Dev → UAT → Prod                                  │
└────────────────────────────────────────────────────────────┘
                          │
                          │  AAP pulls the PROMOTED tag only
                          ▼
┌────────────────────────────────────────────────────────────┐
│ AAP Job Template: "Deploy Hardened Bootc Fleet"                │
│   bootc switch <satellite>/fsi-hardened-images/...:prod        │
│   bootc upgrade                                                │
└────────────────────────────────────────────────────────────┘

PIPELINE 2 — App teams own this (future work / narrative extension)
┌────────────────────────────────────────────────────────────┐
│ fsi-payments-app                                               │
│   FROM fsi-hardened-os:prod   ← consumes Pipeline 1's output    │
│   Resolve app dependencies via Lightwell (or equivalent)        │
│   Sign, push, deploy                                            │
└────────────────────────────────────────────────────────────┘
```

**Why this separation matters for the story, not just for org-chart reasons:**
a bank's platform/security team can prove the base OS is trustworthy once, and
every app team downstream inherits that guarantee without re-deriving it. This
is exactly how real regulated shops scale compliance — centralize the hard
proof, let consuming teams build on top of it with confidence, don't re-litigate
OS-layer trust in every app repo.

---

## What each Red Hat product is doing, and why it's the right tool

**Red Hat Enterprise Linux, Image Mode (bootc)**
The OS itself is a signed, versioned container image — not a pile of packages
installed over time and drifting. `bootc switch`/`bootc upgrade` make "what's
running" and "what we approved" the same question, and rollback is one command
instead of a restore-from-backup exercise.

**Red Hat Satellite**
The single governed source for: base OS content (mirrored from Red Hat's CDN,
not pulled ad hoc from the internet), your custom hardened image (pushed by
CI), Lifecycle Environment promotion (Dev→UAT→Prod as a deliberate, auditable
gate), and ongoing compliance scanning of the live fleet via OpenSCAP policies.
It is the one place an auditor can be pointed to and asked "prove what's
running and where it came from."

**Red Hat Ansible Automation Platform**
The execution and orchestration layer. It doesn't originate trust — it
*enforces* what Satellite has already validated: deploying only promoted
images, running remediation only for known, tested OpenSCAP fixes (not blind
auto-patching), and — via its MCP server — exposing this automation safely to
AI-assisted operations without handing an agent raw SSH access.

**GitHub Actions (self-hosted runner, inside the VPC)**
The trigger and CI surface. Deliberately *not* the trust boundary itself —
the runner executes builds and scans, but Satellite is what other systems and
auditors actually trust as the source of record. This distinction matters: CI
tooling is process automation, Satellite is the system of record.

---

## What's demo-ready right now vs. what needs to close

### Demo-ready
- Full network build (VPC, bastion, reverse proxy) — reproducible in ~20 min via the Terraform package
- Satellite + AAP running, MCP server live on AAP, all 8 hosts registered
- GitHub Actions pipeline building and pushing a real hardened bootc image into Satellite's registry
- Compliance automation playbook package (policy creation, scan trigger, ARF parsing, remediation)

### Needs to close before this is a complete, honest story

1. **Fix the OpenSCAP gate in Stage 3** — currently `|| echo`, so nothing has ever actually been blocked. This is the single most important fix left: without it, "compliance-gated" is a claim the pipeline doesn't back up.
2. **Assign the core-banking fleet to a Satellite compliance policy** — the automation package is built, the policy just needs to be created and hosts assigned (UI work, ~10 min).
3. **Decide ISO vs. AMI for Stage 4, and finish it** — given the actual deployment target is AWS EC2, switch to `--type ami`; the ISO path was solving a bare-metal problem this environment doesn't have.
4. **Wire the "Deploy Hardened Bootc Fleet" AAP job template** — drafted in this doc's diagram, not yet built in AAP itself.
5. **Base bootc image mirroring (`base-bootc-images` product)** — discovery ran, sync never completed; either fix it or drop it from the narrative rather than leave it visibly broken.
6. **A real domain + Let's Encrypt cert** — optional, but removes the self-signed-cert / port-blocking friction if this environment needs to stay up and be shown to others over time.

### Explicitly out of scope, and that's fine
Lightwell integration (app-dependency trust) is a legitimate *extension* of
this story, not a gap in it — it only applies once there's a real application
with Maven/PyPI dependencies to deploy, which this demo doesn't currently have.
Narrate it as "here's how this extends to the app layer" rather than trying to
force it into the OS-layer pipeline.

---

## The 10-minute demo script, once the above closes

1. **Open on the thesis**: "Every layer here is provable, not just configured."
2. **Show the AAP Workflow diagram** for compliance (policy → scan → report → remediate) — one visual, the whole runtime story.
3. **Trigger a live scan** against a core-banking host, show the real-time Satellite compliance UI.
4. **Push a change to `fsi-hardened-os`** — show GitHub Actions running: build → OpenSCAP gate (now actually blocking) → push to Satellite.
5. **Promote it through Satellite's Lifecycle Environments** — Dev → UAT → Prod, live, in the UI.
6. **Run the AAP job template** — fleet switches to the newly promoted image via `bootc switch`.
7. **Close on the MCP/Lightspeed angle**: this same trust chain is what makes it safe to let an AI agent operate here at all — the agent only ever gets to act through AAP's already-validated, RBAC-scoped automation, never raw access to the fleet.

That closing beat is actually your strongest differentiator: most compliance demos stop at "we can scan and report." Yours ends at "and this is provably safe to hand to an AI agent," which is the more forward-looking story for 2026.
