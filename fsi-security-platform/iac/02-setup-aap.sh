#!/bin/bash
# Run this ON the AAP instance (via bastion hop), as ec2-user.
# AAP 2.7 has NO RPM installer — containerized (Podman) only.
set -euo pipefail

echo "=== Step 1: Self-resolve fix ==="
MY_IP=$(hostname -I | awk '{print $1}')
MY_FQDN=$(hostname -f)
if ! getent hosts "$MY_FQDN" > /dev/null 2>&1; then
  echo "$MY_IP $MY_FQDN ${MY_FQDN%%.*}" | sudo tee -a /etc/hosts
fi

echo "=== Step 2: Register with subscription-manager ==="
sudo subscription-manager register

echo "=== Step 3: CRITICAL — enable manage_repos ==="
sudo subscription-manager config --rhsm.manage_repos=1

echo "=== Step 4: Enable AAP 2.7 + RHEL 9 repos ==="
sudo subscription-manager repos --enable ansible-automation-platform-2.7-for-rhel-9-x86_64-rpms
sudo subscription-manager repos --enable rhel-9-for-x86_64-baseos-rpms
sudo subscription-manager repos --enable rhel-9-for-x86_64-appstream-rpms

echo "=== Step 5: Install Podman + ansible-core (the actual install tools) ==="
sudo dnf install podman ansible-core tmux -y

echo "=== Step 6: Enable IP forwarding (needed for Podman networking) ==="
sudo sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward = 1" | sudo tee /etc/sysctl.d/99-podman-forward.conf
sudo sysctl --system

echo ""
echo "=== MANUAL STEPS FROM HERE ==="
echo "1. Download the AAP 2.7 Containerized Setup Bundle from:"
echo "   https://access.redhat.com/downloads/content/480"
echo "   (get RHEL 9 x86_64 variant, employee portal login required)"
echo ""
echo "2. curl -L -o aap-bundle.tar.gz '<signed-url-from-portal>'"
echo "   (signed URLs expire ~1hr -- grab fresh right before running)"
echo ""
echo "3. tar xvzf aap-bundle.tar.gz && cd ansible-automation-platform-containerized-setup-bundle-2.7-*"
echo ""
echo "4. Edit inventory-growth:"
echo "   - Replace all 'aap.example.org' with your FQDN (\$MY_FQDN = $MY_FQDN)"
echo "   - Set real passwords for every '<set your own>' line"
echo "   - Leave [ansiblelightspeed] commented out unless you have AI service creds ready"
echo "   - Uncomment [ansiblemcp] section if you want the MCP server (recommended)"
echo ""
echo "   *** CRITICAL FIX — add this line under [all:vars] ***"
echo "   This is THE fix for AAP job containers not being able to reach your VPC subnets."
echo "   Without it, every AAP job against a remote host fails with 'No route to host'"
echo "   because job containers default to slirp4netns networking, which does not route"
echo "   to your VPC subnets. This switches job containers to host networking instead."
echo '   controller_extra_settings=[{"setting": "DEFAULT_CONTAINER_RUN_OPTIONS", "value": ["--network", "host", "--security-opt", "label=level:s0:c100,c200"]}]'
echo ""
echo "5. tmux new -s aap-install"
echo "   ansible-playbook -i inventory-growth ansible.containerized_installer.install"
echo "   (Ctrl+B then D to safely detach if needed -- do NOT just close the terminal)"
echo ""
echo "6. Verify: podman ps -a  (NOT sudo podman ps -a -- this is a rootless install,"
echo "   containers run under ec2-user's UID, sudo looks in the wrong namespace)"
echo ""
echo "7. Access via tunnel: ssh -i <key>.pem -L 8444:${MY_IP}:443 ec2-user@<bastion-ip>"
echo "   then https://localhost:8444"
