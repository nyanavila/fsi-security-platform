#!/bin/bash
# fsi-connect.sh — quick SSH hop helper for the FSI demo environment
#
# Usage:
#   ./fsi-connect.sh                  -> connects to the bastion only
#   ./fsi-connect.sh satellite        -> hops bastion -> Satellite
#   ./fsi-connect.sh aap              -> hops bastion -> AAP
#   ./fsi-connect.sh runner           -> hops bastion -> CI/CD runner
#   ./fsi-connect.sh <raw-private-ip> -> hops bastion -> that IP directly
#
# Run this from CloudShell (or anywhere with fsi-workshop-key.pem present).
# Update the IPs below whenever instances are relaunched.

set -e

KEY_FILE="fsi-workshop-key.pem"
BASTION_IP="3.146.99.143"        # <-- update if the bastion's Elastic IP changes

# Known hosts -- update these private IPs whenever instances are relaunched
SATELLITE_IP="10.0.1.135"
AAP_IP="10.0.1.211"
RUNNER_IP=""                     # <-- fill in fsi-cicd-runner-01's private IP

# --- Ensure the SSH agent has the key loaded ---
if ! ssh-add -l >/dev/null 2>&1; then
  echo "[fsi-connect] Starting ssh-agent and loading key..."
  eval "$(ssh-agent -s)"
fi

if ! ssh-add -l 2>/dev/null | grep -q "$KEY_FILE"; then
  if [ ! -f "$KEY_FILE" ]; then
    echo "[fsi-connect] ERROR: $KEY_FILE not found in current directory."
    echo "  Upload it first (CloudShell: Actions -> Upload file), then re-run."
    exit 1
  fi
  chmod 400 "$KEY_FILE"
  ssh-add "$KEY_FILE"
fi

TARGET="$1"

case "$TARGET" in
  "")
    echo "[fsi-connect] Connecting to bastion only..."
    ssh -A -i "$KEY_FILE" "ec2-user@${BASTION_IP}"
    ;;
  satellite)
    echo "[fsi-connect] Hopping to Satellite (${SATELLITE_IP})..."
    ssh -A -i "$KEY_FILE" -J "ec2-user@${BASTION_IP}" "ec2-user@${SATELLITE_IP}"
    ;;
  aap)
    echo "[fsi-connect] Hopping to AAP (${AAP_IP})..."
    ssh -A -i "$KEY_FILE" -J "ec2-user@${BASTION_IP}" "ec2-user@${AAP_IP}"
    ;;
  runner)
    if [ -z "$RUNNER_IP" ]; then
      echo "[fsi-connect] ERROR: RUNNER_IP is not set in this script yet."
      echo "  Edit fsi-connect.sh and fill in RUNNER_IP=\"10.0.1.xxx\""
      exit 1
    fi
    echo "[fsi-connect] Hopping to CI/CD runner (${RUNNER_IP})..."
    ssh -A -i "$KEY_FILE" -J "ec2-user@${BASTION_IP}" "ec2-user@${RUNNER_IP}"
    ;;
  *)
    echo "[fsi-connect] Hopping to custom target (${TARGET})..."
    ssh -A -i "$KEY_FILE" -J "ec2-user@${BASTION_IP}" "ec2-user@${TARGET}"
    ;;
esac
