#!/bin/bash -xe
cybr_demos_repo="https://github.com/David-Lang/cybr-demos.git"
cybr_demos_repo_branch="mis-flow"
sudo rm -rf "$CYBR_DEMOS_PATH"
sudo mkdir -p "$CYBR_DEMOS_PATH"
sudo git clone $cybr_demos_repo --branch $cybr_demos_repo_branch "$CYBR_DEMOS_PATH"
sudo chown -R ubuntu:ubuntu "$CYBR_DEMOS_PATH"
