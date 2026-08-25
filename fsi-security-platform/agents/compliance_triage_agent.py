"""
compliance_triage_agent.py — a real, working agentic loop.

This is Tier 2 of the Secure Governance Framework: the agent can read
(Tier 1) and draft recommendations (Tier 2), and it structurally cannot
do anything else — its only tools are read functions and one "save a
draft file" function. There is no tool here that changes production
state. That boundary is enforced by what tools exist, not by asking the
model nicely to behave.

Usage:
    export ANTHROPIC_API_KEY=...
    export SATELLITE_PASSWORD=...
    export AAP_PASSWORD=...
    export REDHAT_OFFLINE_TOKEN=...   # optional, only needed for CVE tool
    python3 compliance_triage_agent.py "What should we prioritize this week?"
"""

import sys
import os
import json
import anthropic

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools"))
from satellite_aap_tools import TOOL_DEFINITIONS, TOOL_FUNCTIONS

SYSTEM_PROMPT = """You are a compliance triage agent for an FSI (financial \
services) infrastructure environment running Red Hat Satellite and Ansible \
Automation Platform.

Your job: read live compliance, automation, and vulnerability data, and \
produce a prioritized, honest recommendation for what a human security \
engineer should look at this week.

CRITICAL RULES:
1. You can only read data and draft recommendations. You cannot and must \
   not claim to have fixed, remediated, or changed anything -- you have no \
   tools that do that, and you must never imply otherwise.
2. Prioritize by REAL urgency signals (known active exploits, repeated job \
   failures, hosts that haven't checked in) -- not just by raw counts or \
   CVSS scores. A CVE with a known exploit affecting 1 host matters more \
   than a CVSS 9.8 with no known exploit affecting 12 hosts.
3. Be honest about what you don't know or couldn't check. If a tool call \
   fails or returns incomplete data, say so in the recommendation rather \
   than papering over the gap.
4. Always end by calling save_draft_recommendation with your findings -- \
   this is a DRAFT for human review, and your output must make that \
   explicit, not present itself as a completed action.
5. Keep the tone plain and specific -- real host names, real numbers, no \
   vague hand-waving like "several issues were found."
"""


def run_agent(user_request, max_turns=8):
    client = anthropic.Anthropic()  # reads ANTHROPIC_API_KEY from env

    messages = [{"role": "user", "content": user_request}]

    for turn in range(max_turns):
        response = client.messages.create(
            model="claude-sonnet-4-6",
            max_tokens=2000,
            system=SYSTEM_PROMPT,
            tools=TOOL_DEFINITIONS,
            messages=messages,
        )

        for block in response.content:
            if block.type == "text":
                print("\n[Agent reasoning]: " + block.text + "\n")

        if response.stop_reason != "tool_use":
            print("=== Agent finished ===")
            break

        messages.append({"role": "assistant", "content": response.content})

        tool_results = []
        for block in response.content:
            if block.type == "tool_use":
                tool_name = block.name
                tool_input = block.input
                print("[Tool call]: " + tool_name + "(" + json.dumps(tool_input) + ")")

                try:
                    func = TOOL_FUNCTIONS[tool_name]
                    result = func(**tool_input)
                except Exception as e:
                    result = {"error": str(e)}

                tool_results.append({
                    "type": "tool_result",
                    "tool_use_id": block.id,
                    "content": json.dumps(result, default=str),
                })

        messages.append({"role": "user", "content": tool_results})

    else:
        print("=== Agent hit max turns without finishing -- check for a loop ===")


if __name__ == "__main__":
    default_request = (
        "Review our compliance posture, recent automation activity, and CVE "
        "exposure. What are the top 3 things I should look at this week, "
        "and why? Save your findings as a draft recommendation."
    )
    request = sys.argv[1] if len(sys.argv) > 1 else default_request
    run_agent(request)
