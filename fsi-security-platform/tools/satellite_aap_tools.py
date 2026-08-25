"""
tools.py — the agent's entire interface to the outside world.

GOVERNANCE BOUNDARY (see Secure Governance Framework):
Every function in this file is Tier 1 (read) or Tier 2 (recommend/draft).
NONE of them execute a remediation, change a Satellite policy, or modify
AAP job templates. If you're tempted to add a function here that DOES
something rather than READS or DRAFTS something, stop — that belongs in
a separate, explicitly-reviewed Tier 3 AAP Job Template instead, triggered
by a human approving this agent's recommendation.
"""

import requests
import json
import os
from datetime import datetime, timedelta

SATELLITE_URL = os.environ.get("SATELLITE_URL", "https://ip-10-0-1-135.us-east-2.compute.internal")
SATELLITE_USER = os.environ.get("SATELLITE_USER", "admin")
SATELLITE_PASSWORD = os.environ.get("SATELLITE_PASSWORD")

AAP_URL = os.environ.get("AAP_URL", "https://localhost:443")
AAP_USER = os.environ.get("AAP_USER", "admin")
AAP_PASSWORD = os.environ.get("AAP_PASSWORD")

INSIGHTS_TOKEN = os.environ.get("REDHAT_OFFLINE_TOKEN")

VERIFY_SSL = False  # self-signed certs throughout this environment
requests.packages.urllib3.disable_warnings()


# ============================================================
# TIER 1 — READ ONLY
# ============================================================

def get_compliance_status(host_filter: str = None) -> dict:
    """
    Get compliance scan status for hosts. Returns pass/fail counts per host.
    Optionally filter by hostname substring.
    """
    resp = requests.get(
        f"{SATELLITE_URL}/api/hosts",
        auth=(SATELLITE_USER, SATELLITE_PASSWORD),
        verify=VERIFY_SSL,
        params={"per_page": 100},
    )
    resp.raise_for_status()
    hosts = resp.json().get("results", [])
    if host_filter:
        hosts = [h for h in hosts if host_filter.lower() in h.get("name", "").lower()]
    return {
        "host_count": len(hosts),
        "hosts": [{"name": h.get("name"), "os": h.get("operatingsystem_name")} for h in hosts],
    }


def get_recent_aap_jobs(days: int = 7) -> dict:
    """Get AAP job execution history for the last N days — successes, failures, and what ran."""
    since = (datetime.utcnow() - timedelta(days=days)).strftime("%Y-%m-%dT%H:%M:%S")
    resp = requests.get(
        f"{AAP_URL}/api/controller/v2/jobs/",
        auth=(AAP_USER, AAP_PASSWORD),
        verify=VERIFY_SSL,
        params={"created__gte": since, "order_by": "-created", "page_size": 50},
    )
    resp.raise_for_status()
    data = resp.json()
    results = data.get("results", [])
    return {
        "total": data.get("count", len(results)),
        "failed": len([j for j in results if j.get("status") == "failed"]),
        "successful": len([j for j in results if j.get("status") == "successful"]),
        "jobs": [
            {"name": j.get("name"), "status": j.get("status"), "finished": j.get("finished")}
            for j in results[:20]
        ],
    }


def get_cve_data(known_exploit_only: bool = False) -> dict:
    """
    Get CVE data from Red Hat Insights for registered hosts.
    Set known_exploit_only=True to filter to actively-exploited CVEs only —
    this is the actual urgency signal, not raw CVSS score.
    """
    token_resp = requests.post(
        "https://sso.redhat.com/auth/realms/redhat-external/protocol/openid-connect/token",
        data={
            "grant_type": "refresh_token",
            "client_id": "rhsm-api",
            "refresh_token": INSIGHTS_TOKEN,
        },
    )
    token_resp.raise_for_status()
    access_token = token_resp.json()["access_token"]

    resp = requests.get(
        "https://console.redhat.com/api/vulnerability/v1/vulnerabilities/cves",
        headers={"Authorization": f"Bearer {access_token}"},
        params={"limit": 500, "sort": "-public_date"},
    )
    resp.raise_for_status()
    cves = resp.json().get("data", [])
    if known_exploit_only:
        cves = [c for c in cves if c.get("known_exploit")]
    return {"count": len(cves), "cves": cves[:50]}  # cap payload size for the model


def get_compliance_policy_findings(policy_name: str) -> dict:
    """Get the most recent findings for a given Satellite compliance policy (e.g. 'fsi-pci-dss-rhel9')."""
    resp = requests.get(
        f"{SATELLITE_URL}/api/compliance/policies",
        auth=(SATELLITE_USER, SATELLITE_PASSWORD),
        verify=VERIFY_SSL,
        params={"search": f'name="{policy_name}"'},
    )
    resp.raise_for_status()
    results = resp.json().get("results", [])
    if not results:
        return {"error": f"Policy '{policy_name}' not found"}
    return {"policy": results[0]}


# ============================================================
# TIER 2 — TRIAGE / RECOMMEND (writes only to a draft location,
# never to production config, AAP templates, or Satellite policy)
# ============================================================

def save_draft_recommendation(title: str, body: str) -> dict:
    """
    Save a draft recommendation for human review. This does NOT execute
    anything — it writes a markdown file a human reads and acts on.
    This is the ONLY 'write' action this agent is permitted to take.
    """
    filename = f"/tmp/agent_recommendation_{datetime.utcnow().strftime('%Y%m%d_%H%M%S')}.md"
    with open(filename, "w") as f:
        f.write(f"# {title}\n\n")
        f.write(f"**Generated by:** FSI Compliance Triage Agent\n")
        f.write(f"**Generated at:** {datetime.utcnow().isoformat()}Z\n")
        f.write(f"**Status:** DRAFT — requires human review and approval before any action is taken\n\n")
        f.write("---\n\n")
        f.write(body)
    return {"saved_to": filename, "status": "draft_saved_pending_human_review"}


# Tool schema for the Anthropic API — describes these functions to the model
TOOL_DEFINITIONS = [
    {
        "name": "get_compliance_status",
        "description": "Get compliance scan status for registered hosts in Satellite.",
        "input_schema": {
            "type": "object",
            "properties": {
                "host_filter": {"type": "string", "description": "Optional hostname substring filter"}
            },
        },
    },
    {
        "name": "get_recent_aap_jobs",
        "description": "Get AAP automation job history (successes/failures) for the last N days.",
        "input_schema": {
            "type": "object",
            "properties": {
                "days": {"type": "integer", "description": "Number of days to look back, default 7"}
            },
        },
    },
    {
        "name": "get_cve_data",
        "description": "Get CVE vulnerability data from Red Hat Insights for registered hosts.",
        "input_schema": {
            "type": "object",
            "properties": {
                "known_exploit_only": {
                    "type": "boolean",
                    "description": "Filter to only actively-exploited CVEs (the real urgency signal)",
                }
            },
        },
    },
    {
        "name": "get_compliance_policy_findings",
        "description": "Get findings for a specific Satellite compliance policy.",
        "input_schema": {
            "type": "object",
            "properties": {
                "policy_name": {"type": "string", "description": "e.g. 'fsi-pci-dss-rhel9'"}
            },
            "required": ["policy_name"],
        },
    },
    {
        "name": "save_draft_recommendation",
        "description": "Save a draft recommendation for human review. Does not execute any change.",
        "input_schema": {
            "type": "object",
            "properties": {
                "title": {"type": "string"},
                "body": {"type": "string", "description": "Full markdown content of the recommendation"},
            },
            "required": ["title", "body"],
        },
    },
]

TOOL_FUNCTIONS = {
    "get_compliance_status": get_compliance_status,
    "get_recent_aap_jobs": get_recent_aap_jobs,
    "get_cve_data": get_cve_data,
    "get_compliance_policy_findings": get_compliance_policy_findings,
    "save_draft_recommendation": save_draft_recommendation,
}
