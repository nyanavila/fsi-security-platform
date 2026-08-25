#!/bin/bash
# Run this ON the Satellite instance (via bastion hop), as ec2-user.
# Encodes every fix discovered during the first build so this run is clean.
set -euo pipefail

echo "=== Step 1: Self-resolve fix (installer pre-flight check needs this) ==="
MY_IP=$(hostname -I | awk '{print $1}')
MY_FQDN=$(hostname -f)
if ! getent hosts "$MY_FQDN" > /dev/null 2>&1; then
  echo "$MY_IP $MY_FQDN ${MY_FQDN%%.*}" | sudo tee -a /etc/hosts
fi

echo "=== Step 2: Register with subscription-manager ==="
echo "You will be prompted for your Red Hat employee username/password."
sudo subscription-manager register

echo "=== Step 3: CRITICAL — enable manage_repos (off by default on this AMI) ==="
sudo subscription-manager config --rhsm.manage_repos=1

echo "=== Step 4: Enable Satellite 6.18 + RHEL 9 base repos ==="
sudo subscription-manager repos --enable satellite-6.18-for-rhel-9-x86_64-rpms
sudo subscription-manager repos --enable satellite-maintenance-6.18-for-rhel-9-x86_64-rpms
sudo subscription-manager repos --enable rhel-9-for-x86_64-baseos-rpms
sudo subscription-manager repos --enable rhel-9-for-x86_64-appstream-rpms

echo "=== Step 5: Install Satellite ==="
sudo dnf install satellite -y

echo "=== Step 6: Run satellite-installer ==="
echo "!! Set a real password below before running in production use !!"
sudo satellite-installer --scenario satellite \
  --foreman-initial-admin-username admin \
  --foreman-initial-admin-password 'ChangeMe123!'

echo "=== Done. Access via SSH tunnel: ==="
echo "  ssh -i <key>.pem -L 8443:${MY_IP}:443 ec2-user@<bastion-public-ip>"
echo "  then browse to https://localhost:8443  (login: admin / ChangeMe123!)"
echo ""
echo "Next manual steps (not scriptable from here):"
echo "  1. Create a subscription manifest at console.redhat.com/subscriptions/manifests,"
echo "     add MCT3718 (Satellite Infrastructure Subscription), export, upload via"
echo "     Content -> Subscriptions -> Manage Manifest"
echo "  2. Enable Red Hat repos: RHEL 8/9 BaseOS+AppStream, Satellite Client 6 for RHEL 8/9"
echo "  3. Sync content: Content -> Sync Status -> Synchronize"
echo "  4. Create activation keys per tier (see 03-activation-keys.md)"
