#!/usr/bin/env bash
#
# bootstrap.sh — turn a stock AlmaLinux OS 10 instance into an
# AlmaLinux M&E-alike workstation.
#
# Run ON the instance:
#   sudo dnf -y install git
#   git clone https://github.com/<your-org>/almalinux-me-ec2.git
#   cd almalinux-me-ec2 && ./bootstrap.sh
#
# Safe to re-run: everything underneath is idempotent Ansible.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $EUID -eq 0 ]]; then
  SUDO=""
else
  SUDO="sudo"
fi

echo "==> Installing Ansible and git (if missing)..."
$SUDO dnf -y install ansible-core git python3-libdnf5

echo "==> Installing required Ansible collections..."
ansible-galaxy collection install ansible.posix community.general --upgrade

echo "==> Running the M&E configuration playbook (this takes a while —"
echo "    a full KDE desktop plus ~30 creative applications)..."
cd "${REPO_DIR}/ansible"
ansible-playbook site.yml "$@"

echo
echo "==> Done. Reboot to start the graphical target:"
echo "    sudo reboot"
echo "    Then connect via Amazon DCV:  https://<instance-address>:8443"
