"""
remediation_planner_agent.py -- drafts a specific AAP Job Template spec for
a given finding, for a human to review and actually create in AAP.

This agent is deliberately more constrained than the triage agent: it does
NOT have access to AAP's job-launch API at all. Its only output is a
structured YAML spec a human copies into AAP's Job Template creation form.
This is the Tier 2 -> Tier 4 boundary: the agent's work product requires a
human to perform the Tier 4 approval action of actually creating the
template before it can ever run as Tier 3.

Usage:
    python3 remediation_planner_agent.py "core-banking-payments-01 failed \
        3 PCI-DSS checks related to SSH cipher configuration"
"""

import sys
import anthropic

SYSTEM_PROMPT = """You are a remediation planning agent. You take a \
description of a compliance or security finding and draft a proposed \
AAP Job Template specification -- NOT a running job, just a spec a human \
reviews and manually creates in AAP.

Your output must be a single YAML block containing:
- name: a clear Job Template name
- description: what this fixes and why
- playbook_outline: a short, human-readable outline of the tasks (not a \
  full playbook -- a human writes and reviews the actual playbook)
- risk_notes: anything the human reviewer should specifically check before \
  approving this (e.g. this changes SSH config, verify no automation \
  depends on the ciphers being removed)
- rollback_notes: how a human would undo this if it causes a problem

Do not write actual executable Ansible tasks. Do not claim this has been \
created in AAP -- you have no tool to do that, and your only job is to \
produce a draft a human reviews before creating anything.
"""


def plan_remediation(finding_description):
    client = anthropic.Anthropic()

    response = client.messages.create(
        model="claude-sonnet-4-6",
        max_tokens=1500,
        system=SYSTEM_PROMPT,
        messages=[{"role": "user", "content": finding_description}],
    )

    output_text = "".join(b.text for b in response.content if b.type == "text")

    safe_name = finding_description[:30].replace(" ", "_").replace("/", "_")
    filename = "/tmp/proposed_job_template_" + safe_name + ".yaml"
    with open(filename, "w") as f:
        f.write("# PROPOSED AAP Job Template -- NOT YET CREATED\n")
        f.write("# A human must review this and manually create the template in AAP\n")
        f.write("# before it exists as a Tier 3 automation resource.\n\n")
        f.write(output_text)

    print(output_text)
    print("\n=== Saved proposed spec to: " + filename + " ===")
    print("=== This is a DRAFT. Nothing has been created in AAP. ===")

    return filename


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print('Usage: python3 remediation_planner_agent.py "<finding description>"')
        sys.exit(1)
    plan_remediation(sys.argv[1])
