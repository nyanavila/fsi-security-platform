# FSI Security-First Infrastructure Platform

Red Hat Satellite + AAP + image-mode RHEL, wired into a full compliance
automation and AI-assisted triage loop for an FSI (financial services)
environment. See `docs/fsi-security-strategy.md` for the full narrative.

## Repo layout

```
iac/                    Terraform for the network layer, plus Satellite/AAP
                         setup scripts encoding every fix discovered during
                         the build (DNS hostnames, manage_repos, the AAP
                         job-container networking fix, etc.)

playbooks/compliance/    The full compliance loop:
  01-create-compliance-policy.yml       create Satellite PCI-DSS policies
  02-assign-hosts-to-policy.yml         assign registered hosts to a policy
  03-trigger-scan.yml                   fire an on-demand OpenSCAP scan
  04-parse-arf-and-report.yml           parse results, render a matrix
  05-remediate-high-severity.yml        auto-fix HIGH findings with a snippet
  06-generate-executive-summary.yml     LLM-generated board-readable summary
  parse_satellite_arf_with_remediations.yml
                                         confirmed-authentic version sourced
                                         from redhat-partner-tech/automated-satellite
  pull-and-triage-cves.yml              pull + prioritize CVEs from Insights API

agents/                  Working agentic loops (Anthropic tool-use API):
  compliance_triage_agent.py            reads live data, drafts recommendations
  remediation_planner_agent.py          drafts AAP Job Template specs

tools/
  satellite_aap_tools.py                the agents' only interface to
                                         Satellite/AAP — deliberately Tier 1/2
                                         scoped, no write-to-production function
                                         exists

governance/
  secure-governance-framework.md        the four-tier model everything above
                                         is built to comply with

docs/
  fsi-security-strategy.md              the full narrative + architecture
  fsi-security-fit-analysis.md          honest FSI regulatory fit assessment
  mcp-use-cases-and-objectives.md       MCP tool use cases, Tier-mapped

scripts/
  fsi-connect.sh                        SSH hop helper (bastion -> Satellite/
                                         AAP/runner), fill in RUNNER_IP before use
```

## Quick start

1. **Infrastructure**: `iac/main.tf` + `terraform.tfvars.example` — see
   `iac/03-activation-keys-and-registration.md` for the manual steps that
   follow (Satellite manifest, activation keys, client registration).
2. **Compliance loop**: run `playbooks/compliance/01` through `05` in order
   against your registered hosts. See each file's header comments for
   required `-e` vars.
3. **Agents**: `agents/README.md` equivalent is in the header docstring of
   each script — set `ANTHROPIC_API_KEY`, `SATELLITE_PASSWORD`, `AAP_PASSWORD`,
   run directly.

## Honest status (as of last working session)

- Core infra: built and working (Satellite 6.18, AAP 2.7 with MCP server,
  8 hosts registered, GitHub Actions building hardened bootc images into
  Satellite's registry and converting to AMIs)
- Compliance playbooks 01-06: written and environment-configured, **not yet
  run end-to-end against live data in this session** — first real run is
  the next step, not a confirmed-working fact yet
- Agents: built and structurally sound, same caveat — not yet run against
  live Satellite/AAP data
- Known gaps: no SBOM generation, no incident-reporting integration, no
  audit logging on agent tool calls, `mcp_allow_write_operations` still
  `false` (deliberately, pending the governance decision described in
  `docs/mcp-use-cases-and-objectives.md`)

See `docs/fsi-security-fit-analysis.md` for the full, unvarnished gap
analysis against actual FSI regulatory pressure (DORA, PCI-DSS) — this repo
is a strong foundation layer, not a complete compliance program.
