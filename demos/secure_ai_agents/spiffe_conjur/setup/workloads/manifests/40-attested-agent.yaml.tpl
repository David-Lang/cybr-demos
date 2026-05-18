# attested-agent — the AFTER state for the demo.
#
# Templated: setup/workloads/setup.sh runs envsubst on this file with the
# variables listed in the file footer so the trust domain and Conjur details
# come from setup/vars.env.
#
# What's different from 00-vulnerable-agent.yaml:
#   - Zero `env` references containing the API key.
#   - Zero `Secret` references of any kind.
#   - One CSI volume mounts the SPIFFE Workload API Unix socket.
#   - The pod fetches a JWT-SVID, presents it to CyberArk Conjur Cloud
#     (authn-jwt), receives a short-lived access token, and uses it to read
#     the API key from a Conjur variable.

---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ${ATTESTED_AGENT_SA}
  namespace: ${WORKLOADS_NAMESPACE}

---
# Conjur Cloud connection settings — URLs and identifiers only, NO secrets.
apiVersion: v1
kind: ConfigMap
metadata:
  name: conjur-config
  namespace: ${WORKLOADS_NAMESPACE}
data:
  CONJUR_URL: "https://${TENANT_SUBDOMAIN}.secretsmgr.cyberark.cloud/api"
  CONJUR_ACCOUNT: "conjur"
  CONJUR_AUTHENTICATOR_ID: "authn-jwt/${CONJUR_AUTHN_SERVICE_ID}"
  CONJUR_VARIABLE: "${CONJUR_SECRET_VARIABLE}"

---
apiVersion: v1
kind: Pod
metadata:
  name: ${ATTESTED_AGENT_NAME}
  namespace: ${WORKLOADS_NAMESPACE}
  labels:
    app: ${ATTESTED_AGENT_NAME}
    demo: "after"
    spiffe.io/spiffe-id: "true"
spec:
  serviceAccountName: ${ATTESTED_AGENT_SA}
  restartPolicy: Always
  containers:
    - name: agent
      image: ${SPIRE_TOOLS_IMAGE}
      imagePullPolicy: IfNotPresent
      command: ["/bin/sh", "-c"]
      args:
        - |
          set -eu
          echo "[attested-agent] starting"
          echo "[attested-agent] my SPIFFE ID will be:"
          echo "[attested-agent]   spiffe://${TRUST_DOMAIN}/ns/${WORKLOADS_NAMESPACE}/sa/${ATTESTED_AGENT_SA}/app/${ATTESTED_AGENT_NAME}"
          echo "[attested-agent] Conjur Cloud URL: $${CONJUR_URL}"
          echo "[attested-agent] Conjur authenticator: $${CONJUR_AUTHENTICATOR_ID}"
          echo "[attested-agent] Conjur secret variable: $${CONJUR_VARIABLE}"
          echo "[attested-agent] no API key in env, no Secret references in pod spec"
          if env | grep -E '(KEY|TOKEN|PASSWORD|SECRET)='; then
            echo "[attested-agent] FAIL: secret material in env"
          else
            echo "[attested-agent] confirmed: zero secret material in env"
          fi
          while true; do sleep 3600; done
      env:
        - name: SPIFFE_ENDPOINT_SOCKET
          value: unix:///spiffe-workload-api/spire-agent.sock
        - name: CONJUR_URL
          valueFrom:
            configMapKeyRef:
              name: conjur-config
              key: CONJUR_URL
        - name: CONJUR_ACCOUNT
          valueFrom:
            configMapKeyRef:
              name: conjur-config
              key: CONJUR_ACCOUNT
        - name: CONJUR_AUTHENTICATOR_ID
          valueFrom:
            configMapKeyRef:
              name: conjur-config
              key: CONJUR_AUTHENTICATOR_ID
        - name: CONJUR_VARIABLE
          valueFrom:
            configMapKeyRef:
              name: conjur-config
              key: CONJUR_VARIABLE
      volumeMounts:
        - name: spiffe-workload-api
          mountPath: /spiffe-workload-api
          readOnly: true
  volumes:
    - name: spiffe-workload-api
      csi:
        driver: csi.spiffe.io
        readOnly: true

# Variables substituted by envsubst at apply time:
#   ${ATTESTED_AGENT_NAME}, ${ATTESTED_AGENT_SA}, ${WORKLOADS_NAMESPACE},
#   ${TRUST_DOMAIN}, ${TENANT_SUBDOMAIN}, ${CONJUR_AUTHN_SERVICE_ID},
#   ${CONJUR_SECRET_VARIABLE}, ${SPIRE_TOOLS_IMAGE}
