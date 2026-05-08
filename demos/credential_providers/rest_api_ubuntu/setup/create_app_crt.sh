#!/bin/bash
set -euo pipefail

# Self sign certificate
# !! Install public.crt to CCP Server Cert Manager in "Trusted Root Certification Authorities"
openssl req \
    -new \
    -newkey rsa:4096 \
    -days 365 \
    -nodes \
    -x509 \
    -subj "${CERT_SUBJECT:-/C=CA/ST=Cybr/L=Demos/O=CCP/CN=cybr-demos}" \
    -addext "subjectAltName=DNS:${CERT_SAN_DNS:-cybr-demos-rest-api.local},URI:${CERT_SAN_URI:-spiffe://cybr-demos/credential-providers/rest-api-ubuntu}" \
    -keyout app.key \
    -out app.crt

openssl pkcs12 -export -out app.pfx -inkey app.key -in app.crt -password pass:
