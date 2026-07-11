#!/bin/bash
set -euo pipefail

# Non-interactive apt: this runs under Azure run-command / cloud-init with no TTY,
# so avoid debconf prompts (and the "unable to initialize frontend" noise).
export DEBIAN_FRONTEND=noninteractive

# Add Docker's official GPG key:
sudo apt-get update
sudo apt-get install ca-certificates curl gnupg -y
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# Add the repository to Apt sources:
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update -y

sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y

# Add a login user to the docker group so they can run docker without sudo.
# Portable across clouds (Azure uses "azureuser", AWS Ubuntu uses "ubuntu") and
# never fails the install if no such user exists (root can always use docker).
# Override with DOCKER_GROUP_USER=<name>.
docker_group_user="${DOCKER_GROUP_USER:-${SUDO_USER:-}}"
if [ -z "$docker_group_user" ]; then
  for candidate in azureuser ubuntu; do
    if id "$candidate" >/dev/null 2>&1; then
      docker_group_user="$candidate"
      break
    fi
  done
fi
if [ -n "$docker_group_user" ] && id "$docker_group_user" >/dev/null 2>&1; then
  sudo usermod -aG docker "$docker_group_user"
  echo "Added ${docker_group_user} to the docker group."
else
  echo "No non-root login user found for the docker group; skipping (root can run docker)."
fi
