#!/bin/bash
set -euo pipefail

docker stop jenkins8081 && docker rm jenkins8081
