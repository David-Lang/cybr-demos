# spire-tools: Alpine + shell + curl + openssl + statically-linked spire-agent CLI.
#
# The official ghcr.io/spiffe/spire-agent image is distroless (no shell), which
# makes the simple "loop and refetch" pattern in the demo workloads impossible
# and prevents `kubectl exec`-driven demos. We layer the binary onto alpine to
# get the trusted upstream binary AND interactive tools (curl + openssl + jq).

ARG SPIRE_VERSION=1.13.2

FROM ghcr.io/spiffe/spire-agent:${SPIRE_VERSION} AS spire

FROM alpine:3.20
RUN apk add --no-cache \
      bash \
      ca-certificates \
      curl \
      openssl \
      jq \
      coreutils
COPY --from=spire /opt/spire/bin/spire-agent /usr/local/bin/spire-agent
RUN spire-agent --version || true
ENTRYPOINT ["/bin/sh"]
