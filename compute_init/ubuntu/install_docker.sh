#!/bin/bash
set -euo pipefail

sudo apt-get update --yes
sudo apt-get remove docker docker-engine docker.io --yes
sudo apt install docker.io --yes
sudo usermod -aG docker ubuntu
sudo systemctl start docker
sudo systemctl enable docker 
