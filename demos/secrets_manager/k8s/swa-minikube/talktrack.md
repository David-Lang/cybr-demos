# Talk Track: Secure Workload Access on Kubernetes (~12-15 min)

Presenter script for `bash demo.sh`. Each section maps to a step in the interactive walkthrough.
Press ENTER to advance.

## Framing (before you start)

> "Most Kubernetes secret integrations authenticate with the pod's raw service-account token. That
> works, but the identity is the cluster's token — it can be over-broad and it leaves the cluster.
> Secure Workload Access takes a different approach: it issues each workload a **cryptographically
> attested SPIFFE identity**, then lets that identity — not a shared key — unlock secrets in Conjur
> Cloud."

## Step 1 — The in-cluster control plane

> "Two CyberArk components run here. The **SWA Server** registered with Conjur Cloud and vouches for
> nodes. The **SWA Agent** is a DaemonSet on every node; it's the local identity authority that
> attests workloads and hands out short-lived SVIDs."

Point at: `swa-server` Deployment and `swa-agent` DaemonSet, both Running.

## Step 2 — SPIFFE objects as code

> "The trust domain, server group, and node group were declared with the SWA Terraform provider —
> policy-as-code. Note the node group's SPIFFE template: identity is bound to namespace and service
> account. The trust domain signs with RSA, which is what the JWT authenticator requires."

## Step 3 — The workload gets an identity

> "When this pod started, its init container talked to the node-local agent over a Unix socket. The
> agent attested it — confirmed the namespace and service account — and issued a JWT-SVID. Look at
> the decoded claims: the `sub` is the workload's SPIFFE ID, it's scoped to the `conjur` audience,
> and it expires. This is the workload's passport, minted on the node, never stored long-term."

## Step 4 — Conjur maps identity to access

> "Conjur Cloud validates that SVID against the trust domain's JWKS, maps the SPIFFE ID to a host in
> policy, and checks safe membership. The access grant is auditable YAML — the workload can only read
> the secrets we explicitly allowed."

## Step 5 — The payoff (live, on demand)

> "Let's not just read a log — let's do it live. With one keypress the workload runs the exact three
> calls: read its own SVID, exchange it at `authn-jwt` for a Conjur token, and GET the secret. There's
> the username and password, retrieved right now, by the pod's identity. No password in the image, no
> API key in the manifest, no static SA token off-cluster."

## Step 5.5 — Rotate it live (the everyday win)

> "Here's what operations actually cares about. I'll change the password at the SOURCE — in Privilege
> Cloud — then watch Conjur Sync replicate it in seconds. Now the SAME pod, with the SAME identity,
> reads the new value. Before / after, right on screen. No redeploy, no secret to push into the
> cluster, no new identity. That's lifecycle management instead of key sprawl."

Point at: the before/after password lines and "zero redeploy". (Sync typically lands in ~15-60s.)

## Step 6 — Red-team the boundary (the showpiece)

> "Let's not take it on faith — let's attack it live. **Attack one:** I steal the pod's real SVID and
> flip one character of its signature, then present it to Conjur. Watch — HTTP 401. The signature no
> longer matches the trust domain's keys, so Conjur rejects it before it even reads policy. The
> genuine token still returns 200."
>
> "**Attack two — the scary one:** I deploy the *exact same container image and code* into a different
> namespace with a different service account. SWA still fairly issues it an identity — but look, it's a
> **different SPIFFE ID**. When that imposter presents its valid SVID to Conjur for the secret: 401
> denied. Access is bound to *what the workload is*, not its image. Copying the container gets the
> attacker nothing."

Point at: the side-by-side (trusted ALLOW vs imposter DENY). The imposter namespace is auto-cleaned.

## Close

> "Same model runs on VMs, EKS, and OpenShift. The takeaway: workload identity becomes a first-class,
> attested, short-lived credential — and CyberArk governs exactly which identity can reach which
> secret."

## Likely questions

- **"How is this different from your ESO demo?"** ESO uses the raw K8s SA JWT. SWA adds node +
  workload attestation and issues a purpose-built SPIFFE SVID, decoupling identity from SA tokens.
- **"What signs the SVID?"** The SWA trust domain (RSA / RS256). Conjur validates every SVID against
  the trust domain's hosted JWKS at
  `https://<sub>.secretsmgr.cyberark.cloud/api/swa/trust-domains/<trust-domain>/.well-known/jwks`.
- **"What if a pod lies about its identity?"** It can't — the agent attests via the kubelet and the
  server attests the node via TokenReview. Identity is derived, not asserted. The red-team step proves
  this: a look-alike workload gets a *different* SPIFFE ID and is denied.
- **"What stops someone replaying a stolen token?"** Audience-binding (`aud: conjur`) plus a
  minutes-long expiry, and the signature can't be altered (red-team Attack #1 shows the 401). A theft
  buys almost nothing.
- **"Lifetime?"** SVIDs are short-lived (TTL from the trust domain `token_ttl`, 3600s here). The demo
  pod fetches its SVID at startup via an init container; in production a sidecar (`spiffe-helper`) or
  the SPIFFE CSI driver refreshes it continuously. `demo.sh` re-fetches at the start of each run so
  the walkthrough is always live.
