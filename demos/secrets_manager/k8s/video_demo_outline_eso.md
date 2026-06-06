# Kubernetes ESO Video Demo Outline

Target length: 6 minutes 15 seconds

Audience: security teams and stakeholders

Scope: validation only

Focus:

- `SecretStore/conjur`
- `ExternalSecret/conjur`
- synced Kubernetes `Secret/conjur`
- External Secrets Operator controller health

Does not cover:

- `demo_setup.md`
- Helm installation
- cluster provisioning
- non-ESO delivery patterns except for brief comparison

## Demo Goal

Show how External Secrets Operator uses a Kubernetes workload identity to authenticate to CyberArk Secrets Manager with JWT, retrieve authorized variables, and sync them into a native Kubernetes secret under centralized CyberArk control.

## Audience Message

- Goal:
  Show a controller-based Kubernetes secret sync pattern that keeps CyberArk authentication and authorization centralized.
- Pain:
  Many teams still copy secret values into cluster-managed secrets manually or build brittle sync jobs with unclear ownership and weak policy boundaries.
- Security posture:
  Authentication is based on a Kubernetes service account JWT, authorization is enforced by CyberArk, and the resulting secret is created only after the identity and policy checks succeed.
- Low friction ease of use / stakeholder UX:
  Application teams consume a normal Kubernetes secret while ESO handles retrieval and refresh in the background.
- Security team control plane enablement:
  Security owns the trusted identity model, the JWT authenticator configuration, and the CyberArk authorization boundary without forcing apps to call CyberArk directly.

## Recorded Flow

### 0:00-0:40 Opening Context

Talk track:

- This video explains the Kubernetes External Secrets Operator pattern and why it matters for both security teams and platform stakeholders.
- The focus is runtime validation of a working environment, not setup.
- The main question is how a Kubernetes controller can retrieve CyberArk-managed secrets through workload identity while security keeps centralized control.

On screen:

- Open `demos/secrets_manager/k8s/demo_validation.md`
- Highlight `Request And Retrieval Flow`, the Mermaid diagram, and `Pattern 5: External Secrets Operator`

### 0:40-1:20 Goal, Pain, And Security Posture

Talk track:

- The goal is to sync CyberArk-managed secret values into Kubernetes-native secrets without hardcoding credentials or making the application implement CyberArk API calls.
- The pain is that manual secret copying and ad hoc sync jobs create drift, unclear ownership, and weak access control boundaries.
- The improved security posture comes from separating identity, authorization, and delivery into clear control points.

On screen:

- Stay on the Mermaid workflow in `demo_validation.md`
- Pause on the point where the JWT is presented and where CyberArk authorization is evaluated

Key points:

- ESO is the retrieval component in this pattern.
- The service account JWT is the identity anchor.
- CyberArk still decides what the identity is allowed to read.

### 1:20-2:10 Explain The CyberArk Flow

Talk track:

- Kubernetes issues the projected service account JWT for the trusted service account.
- ESO uses that JWT through the `SecretStore` configuration to authenticate to CyberArk.
- CyberArk validates the JWT, maps the workload identity, evaluates policy, and returns the requested variables.
- ESO then syncs those values into a native Kubernetes secret that the application can consume through familiar Kubernetes patterns.

On screen:

```bash
cd demos/secrets_manager/k8s
source setup/vars.env
export DEMO_NAMESPACE="$SM_SERVICE_NAME"
kubectl get secretstore,externalsecret -n "$DEMO_NAMESPACE"
```

Then show:

```bash
kubectl get secretstore conjur -n "$DEMO_NAMESPACE" -o yaml
kubectl get externalsecret conjur -n "$DEMO_NAMESPACE" -o yaml
```

Pause on:

- `provider.conjur`
- `auth.jwt`
- `serviceID`
- `serviceAccountRef.name`
- `remoteRef.key`

Key points:

- The `SecretStore` defines how ESO authenticates to CyberArk.
- The `ExternalSecret` defines which CyberArk variables should be synchronized.
- The controller model separates retrieval from application pod startup.

### 2:10-3:00 Validate The Trusted Identity

Talk track:

- Before checking the synced secret, validate the trusted Kubernetes identity.
- This is the identity CyberArk will evaluate when ESO requests a token for the referenced service account.

On screen:

```bash
kubectl get serviceaccount poc-service-account -n "$DEMO_NAMESPACE" -o yaml
kubectl exec -n "$DEMO_NAMESPACE" deploy/alpine-curl -- \
  cat /var/run/secrets/tokens/jwt > /tmp/k8s-demo.jwt

jq -R 'split(".") | {header: .[0] | @base64d | fromjson, payload: .[1] | @base64d | fromjson}' \
  /tmp/k8s-demo.jwt
```

Key points:

- The service account is the trust root for the workload identity.
- The JWT claims show the Kubernetes identity that CyberArk maps.
- Authentication and authorization remain separate decisions.

### 3:00-4:10 Validate The ESO Sync

Talk track:

- Now validate the live controller behavior.
- The important proof is that the `SecretStore` is ready, the `ExternalSecret` reports a successful sync, and the generated Kubernetes secret exists with the expected keys.

On screen:

```bash
kubectl get secretstore,externalsecret -n "$DEMO_NAMESPACE"
kubectl get secret conjur -n "$DEMO_NAMESPACE" -o yaml
kubectl logs -n external-secrets deploy/external-secrets
```

Pause on:

- `status.conditions` showing ready or synced state
- the generated `Secret/conjur`
- the synced secret keys

Optional tighter proof:

```bash
kubectl get secret conjur -n "$DEMO_NAMESPACE" -o jsonpath='{.data.username}' | base64 -d; echo
kubectl get secret conjur -n "$DEMO_NAMESPACE" -o jsonpath='{.data.password}' | base64 -d; echo
```

Key points:

- ESO authenticates through the configured JWT flow.
- CyberArk authorizes the specific `remoteRef.key` values.
- Kubernetes receives a standard secret object that apps can consume normally.
- Refresh is controller-driven rather than tied to pod init or a sidecar lifecycle.

### 4:10-5:00 Explain Why ESO Matters

Talk track:

- This pattern is useful when teams want Kubernetes-native secret consumption but do not want each application pod to own the retrieval workflow.
- The controller handles retrieval and refresh, while CyberArk still controls identity trust and access scope.
- Compared with provider-init or sidecar patterns, ESO is more cluster-centric and less application-lifecycle-centric.

On screen:

- Return to `demo_validation.md`
- Move between `Pattern 5: External Secrets Operator` and `Pattern Comparison`

Key points:

- Same CyberArk control plane, different runtime integration model.
- Native Kubernetes secret output is still the app-facing result.
- ESO reduces per-workload integration logic when controller-based sync is a better fit.

### 5:00-5:50 Stakeholder Impact And Security Team Control Plane

Talk track:

- For security teams, the value is centralized control over authenticator configuration, workload identity trust, and authorization boundaries.
- For platform teams, the value is standardized secret sync through an operator they already understand.
- For application teams, the experience stays low friction because they consume an ordinary Kubernetes secret instead of implementing direct CyberArk calls.

On screen:

- Highlight the `What CyberArk is doing` and `What this proves` parts of the ESO section

Key points:

- Security defines trust and access centrally.
- Platform teams operationalize the sync through ESO.
- Application teams keep a familiar Kubernetes consumption model.

### 5:50-6:15 Close

Talk track:

- This pattern shows how ESO can act as the Kubernetes-side sync engine while CyberArk remains the identity and authorization control plane.
- The main takeaway is that teams can keep Kubernetes-native consumption without giving up centralized security controls.

## Notes

- Keeps the terminal font large and the output focused on the ESO proof points.
- Uses `demo_validation.md` as the source of truth for the runtime story.
- Avoids setup detail unless the audience explicitly asks how the cluster was prepared.
- If time is tight, shorten the JWT decoding section and keep the `SecretStore`, `ExternalSecret`, and synced `Secret` validation.
- Most important proof points:
  the Mermaid runtime flow, `serviceAccountRef` in `SecretStore/conjur`, `remoteRef.key` in `ExternalSecret/conjur`, controller health, and the synced `Secret/conjur`.
