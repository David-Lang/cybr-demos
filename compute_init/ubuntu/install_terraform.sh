#!/bin/bash

TERRAFORM_VERSION=1.14.3

set -euxo pipefail

echo "ARCH: $(uname -m)"
echo "OS:   $(lsb_release -ds 2>/dev/null || cat /etc/os-release | head -n1)"

# Ensure tools exist
sudo apt-get update
sudo apt-get install -y curl unzip

# Download to a clean temp dir
tmpdir="$(mktemp -d)"
cd "$tmpdir"

curl -fL -o terraform.zip "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip"

# Verify it's actually a zip (not HTML)
file terraform.zip
unzip -l terraform.zip | head

unzip terraform.zip
ls -l terraform

# Install
sudo install -m 0755 terraform /usr/local/bin/terraform

# Verify install location + PATH
command -v terraform
/usr/local/bin/terraform version
terraform version
