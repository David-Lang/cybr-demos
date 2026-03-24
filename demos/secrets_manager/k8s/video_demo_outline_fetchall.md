# Kubernetes FetchAll Video Demo Outline

Target length: 6 minutes 30 seconds

Audience: security teams and stakeholders

Scope: validation only

Focus:

- `demo-k8-secrets-fetch-all`
- `demo-push-to-file-fetch-all`

Does not cover:

- `demo_setup.md`
- Helm installation
- cluster provisioning
- non-FetchAll patterns unless needed for comparison

## Demo Goal

Show how the same CyberArk-authenticated Kubernetes workload identity can retrieve all authorized secrets through two different delivery models: native Kubernetes secret sync and sidecar-driven file delivery.

## Audience Message

- Goal:
  Show two practical FetchAll delivery patterns that use the same workload identity and CyberArk control plane.
- Pain:
  Teams often need broad secret access for a workload, but that creates risk if the retrieval scope, delivery method, and ownership boundaries are not clearly understood.
- Security posture:
  Authentication is based on the pod service account JWT, authorization is enforced by CyberArk, and the delivery method determines where the secrets land inside Kubernetes.
- Low friction ease of use / stakeholder UX:
  Application teams consume either a native Kubernetes secret or a local file without building direct CyberArk API calls into the app.
- Security team control plane enablement:
  Security defines which workload identity is trusted and what that identity is allowed to retrieve, while platform teams choose the delivery pattern that best fits the application.

## Recorded Flow

### 0:00-0:45 Opening Context

Talk track:

- This video explains two Kubernetes FetchAll patterns and what they mean for security teams and stakeholders.
- The focus is validation of a working environment, not setup.
- The central question is how one trusted workload identity can retrieve all authorized secrets through different runtime delivery models.

On screen:

- Open `demos/secrets_manager/k8s/demo_validation.md`
- Highlight `JWT Authentication Model`, `Pattern 2: K8s Secrets FetchAll`, and `Pattern 4: Push To File FetchAll`

### 0:45-1:35 Goal, Pain, And Security Posture

Talk track:

- The goal is to compare two ways of delivering all authorized secrets to a Kubernetes workload.
- The pain is that broad secret retrieval can be operationally convenient, but it also increases risk if the workload is over-permissioned or if the delivery path is poorly understood.
- The security posture depends on two things: the Kubernetes workload identity and the CyberArk authorization boundary behind that identity.

On screen:

- Show the `JWT Authentication Model` section
- Briefly point to the FetchAll sections later in the document

Key points:

- Both patterns use the same trust model.
- The main difference is where the secrets are delivered.
- FetchAll is powerful, but it increases blast radius if permissions are too broad.

### 1:35-2:20 Explain The Shared CyberArk Flow

Talk track:

- In both patterns, the pod authenticates with a projected Kubernetes service account token.
- CyberArk validates the JWT, maps the workload identity, and authorizes the workload to retrieve the variables it is allowed to see.
- After that, the delivery pattern changes: one writes to a Kubernetes secret, and the other writes to a file in a shared volume.

On screen:

```bash
cd demos/secrets_manager/k8s
source setup/vars.env
export DEMO_NAMESPACE="$SM_SERVICE_NAME"
kubectl get pods -n "$DEMO_NAMESPACE"
```

Then show:

```bash
kubectl exec -n "$DEMO_NAMESPACE" deploy/alpine-curl -- \
  cat /var/run/secrets/tokens/jwt > /tmp/k8s-demo.jwt

jq -R 'split(".") | {header: .[0] | @base64d | fromjson, payload: .[1] | @base64d | fromjson}' \
  /tmp/k8s-demo.jwt
```

Key points:

- The JWT is the shared authentication mechanism.
- The `sub` claim identifies the Kubernetes workload identity.
- CyberArk policy decides what that identity can retrieve.

### 2:20-3:25 Validate K8s Secrets FetchAll

Talk track:

- The first validation check is the Kubernetes manifest intent.
- Before looking at runtime output, it is important to confirm which manifest sections enable this pattern.
- The first pattern writes all authorized variables into a native Kubernetes secret.
- This is useful when the application already expects environment variables or native Kubernetes secret consumption.

On screen:

```bash
kubectl get secret demo-k8-secret-fetch-all -n "$DEMO_NAMESPACE" -o yaml
kubectl get deploy demo-k8-secrets-fetch-all -n "$DEMO_NAMESPACE" -o yaml
```

Pause on:

- `conjur-map: "*": "*"`
- `conjur.org/secrets-destination: k8s_secrets`
- `conjur.org/k8s-secrets`
- `envFrom` using `demo-k8-secret-fetch-all`

Then show:

```bash
kubectl get secret demo-k8-secret-fetch-all -n "$DEMO_NAMESPACE" -o yaml
kubectl describe pod -n "$DEMO_NAMESPACE" -l app=demo-k8-secrets-fetch-all
```

Key points:

- The manifest explicitly enables FetchAll with `conjur-map: "*": "*"`.
- The pod annotations tell the provider to populate a Kubernetes secret.
- The app consumes the generated secret through standard Kubernetes `envFrom` behavior.
- The generated secret contains more than the seed `conjur-map`.
- The provider fetched all authorized variables for this workload identity.

### 3:25-4:35 Validate Push To File FetchAll

Talk track:

- The second validation check is again the manifest intent.
- This pattern uses the same workload identity model, but different annotations enable sidecar-based file delivery.
- The second pattern uses the same authorization model but delivers the data into a file instead of a Kubernetes secret.
- This is useful for applications that expect a local configuration or credential file.

On screen:

```bash
kubectl get deploy demo-push-to-file-fetch-all -n "$DEMO_NAMESPACE" -o yaml
```

Pause on:

- `conjur.org/container-mode: sidecar`
- `conjur.org/secrets-destination: file`
- `conjur.org/conjur-secrets.test-app: "*"`
- `conjur.org/secret-file-path.conjur-demo-file`
- the shared `conjur-secrets` volume and app mount path

Then show:

```bash
kubectl get pod -n "$DEMO_NAMESPACE" -l app=demo-push-to-file-fetch-all
kubectl exec -n "$DEMO_NAMESPACE" deploy/demo-push-to-file-fetch-all -c app-container -- \
  cat /opt/secrets/conjur/credentials.yaml
```

Key points:

- The manifest annotations explicitly enable FetchAll file delivery.
- The sidecar writes to a shared in-memory volume mounted into the app container.
- The sidecar retrieves all authorized variables and writes them into the shared in-memory volume.
- The application reads a local file rather than a Kubernetes secret object.
- This is the file-based equivalent of FetchAll.

### 4:35-5:35 Compare The Two Delivery Patterns

Talk track:

- At this point, the shared authentication and authorization story is the same, but the operational experience is different.
- The Kubernetes secret pattern fits workloads that already use native Kubernetes secret consumption.
- The file-delivery pattern fits workloads that expect configuration files or should avoid storing the data in a Kubernetes secret object.

On screen:

- Return to `demo_validation.md`
- Move between `Pattern 2`, `Pattern 4`, and the comparison language around FetchAll

Key points:

- Same workload identity model.
- Same CyberArk authorization boundary.
- Different runtime delivery target: Kubernetes secret versus file.
- Both require careful permission scoping because FetchAll broadens retrieval.

### 5:35-6:10 Stakeholder Impact And Security Team Control Plane

Talk track:

- For security teams, the main value is that trust and authorization stay centralized even when application delivery models differ.
- For platform and application teams, the value is flexibility: the same control plane can support different runtime integration styles.
- For stakeholders, this is a useful example of how security control and application usability can be aligned rather than traded off.

On screen:

- Highlight the cautionary language in the FetchAll sections

Key points:

- Security controls identity trust and access scope centrally.
- Platform teams choose the delivery pattern based on application fit.
- FetchAll should be used deliberately because broader authorization increases risk.

### 6:10-6:30 Close

Talk track:

- These two patterns show the same CyberArk control model applied to two different Kubernetes delivery methods.
- The key takeaway is that workload identity and authorization remain centralized, while the delivery method can be chosen based on application needs.

## Notes

- Keeps the terminal font large and output focused on the relevant lines.
- Does not explain setup, Helm deployment, or cluster provisioning.
- Uses `demo_validation.md` as the source of truth for the runtime story.
- If time is tight, shortens the JWT decoding section and keeps one validation command for each FetchAll pattern.
- Most important proof points:
  the JWT authentication model, the manifest annotations and secret seed that enable each pattern, the generated Kubernetes secret for `demo-k8-secrets-fetch-all`, and the rendered file for `demo-push-to-file-fetch-all`.
