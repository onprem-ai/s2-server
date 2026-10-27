#!/bin/bash
# s2-server 04-provisioning.md Phase 5, Rocky Linux 10: Docker Engine + NVIDIA Container Toolkit
set -euo pipefail
log() { echo; echo "=== $*"; }
command -v nvidia-smi >/dev/null || { echo "STOP: NVIDIA driver missing: run provision-phases-2-4.sh and reboot first"; exit 1; }
log "Remove Podman (conflicts with Docker)"
dnf remove -y podman runc || true
log "Docker CE (key fingerprint must be 060A 61C5 1B55 8A7F 742B 77AA C52F EB6B 621E 9F35)"
dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
# Import Docker's key only if its fingerprint is the published one, then install unattended.
curl -fsSL https://download.docker.com/linux/rhel/gpg -o /tmp/docker.gpg
FPR=$(gpg --show-keys --with-colons /tmp/docker.gpg | awk -F: '/^fpr/{print $10; exit}')
[ "$FPR" = "060A61C51B558A7F742B77AAC52FEB6B621E9F35" ] || { echo "STOP: Docker key fingerprint $FPR"; exit 1; }
rpm --import /tmp/docker.gpg
dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker
log "NVIDIA Container Toolkit"
dnf config-manager --add-repo \
  https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo
dnf install -y nvidia-container-toolkit
nvidia-ctk runtime configure --runtime=docker
systemctl restart docker
dnf versionlock add docker-ce docker-ce-cli containerd.io nvidia-container-toolkit \
  nvidia-container-toolkit-base libnvidia-container-tools libnvidia-container1
log "CDI"
systemctl enable --now nvidia-cdi-refresh.path
systemctl restart nvidia-cdi-refresh.service
nvidia-ctk cdi list
log "Checks"
docker version --format '{{.Server.APIVersion}}'
docker info --format '{{json .Runtimes}}' | grep -o nvidia
docker run --rm --gpus all ubuntu:24.04 nvidia-smi -L
docker run --rm --device nvidia.com/gpu=all ubuntu:24.04 nvidia-smi -L
log "DONE"
