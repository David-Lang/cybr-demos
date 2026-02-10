#!/bin/bash
set -euo pipefail

echo "cert serial number: "
openssl x509 -noout -serial -in ./app.crt | cut -d'=' -f2 | sed 's/../&:/g;s/:$//'
openssl x509 -noout -serial -in ./app.crt | cut -d'=' -f2 | sed 's/../&/g;s/$//' > cert_serial_number
